// ServiceAdapter.swift
// CLI 侧所有权适配（T010-a / T022 owner-aware 部分）。
//
// 本文件只做三件事：
// 1. 把 CLI 的安装/自愈/卸载/状态入口接到统一的 owner/generation/revision 预检
//    （`CLIOwnershipGate`，位于 AutomntCore，规则单一来源）；
// 2. 为共享 `HandoffCoordinator` 提供 CLI 侧 `HandoffServiceAdapter` 实现；
// 3. 提供 CLI 挂载/恢复动作的 `EvaluationPermit` 生命周期封装。
//
// 明确不做：
// - 不引入常驻 IPC 服务或新守护进程；CLI 继续走传统 LaunchAgent（事件驱动）；
// - 不复制任何恢复/挂载业务规则（判定由 AutomntCore `RecoveryRoundPlanner` 承担）；
// - 不手写 automnt.plist / LaunchAgent 业务配置，一切经产品 API。

#if canImport(AutomntCore)
import AutomntCore
#endif
import Foundation
import Dispatch

// MARK: - CLI 所有权预检与生命周期

/// 注册动作的结果，供安装/自愈入口区分提示语义。
enum CLIRegistrationOutcome: Equatable {
    case registered
    /// 守护运行态按既有契约跳过（无副作用）。
    case skipped
    case refusedAppOwner
    case unavailable
}

/// CLI 挂载/恢复动作的持锁上下文。
///
/// `permit` 在整段有界操作期间持有统一 `evaluation.lock`，因此动作内的状态写入
/// 与动作后的复核都在同一临界区内；`expectedGeneration` 用于动作后的代次复核。
struct CLIEvaluationContext {
    let permit: EvaluationPermit
    let snapshot: ConfigSnapshot
    let expectedGeneration: UInt64
}

/// 所有会改变或依赖后端所有权的 CLI 动作的统一入口。
enum CLIOwnership {
    /// 活动配置目录：CLI 的一切锁与状态都在真实配置目录内，绝不从 host/share/mountPoint 推导。
    ///
    /// 标准安装下等于 `~/Library/Application Support/automnt`（与 GUI
    /// `PermissionStore.expectedDirectory` 一致，经 getpwuid 解析真实 HOME）；
    /// `configURLOverride` 仅供 CLI 自测注入临时目录，不是私有容器回退。
    static var directory: URL { getActiveConfigURL().deletingLastPathComponent() }

    /// 自测可显式声明「本调用点已由真实入口持有许可」，用于验证无许可路径的保守行为。
    /// 仅测试置位；生产路径恒为 false。由 `LockedBox` 承载以满足 Swift 6 并发安全。
    private static let selfTestPermitSuppliedBox = LockedBox<Bool>(false)
    static var selfTestPermitSupplied: Bool {
        get { selfTestPermitSuppliedBox.value }
        set { selfTestPermitSuppliedBox.value = newValue }
    }

    /// 读取持久后端状态。nil 表示 `backend-state.plist` 不存在；抛错表示存在但不可信。
    static func durableState() throws -> BackendState? {
        let store = BackendStateStore(authorizedDirectory: directory)
        do {
            return try store.read()
        } catch let error as NSError
            where error.domain == NSPOSIXErrorDomain && error.code == ENOENT {
            return nil
        }
    }

    /// 首次运行时建立明确状态（owner=none / phase=stopped / generation=0）。
    /// 只在状态文件确实缺失时写入；已存在的状态一律原样返回，绝不覆盖。
    @discardableResult
    static func initializeOwnershipIfNeeded(revision: ConfigRevision) throws -> BackendState {
        try BackendStateStore(authorizedDirectory: directory).initialize(revision: revision)
    }

    /// 注册类入口的预检：返回非 nil 表示必须拒绝，调用方不得注册/自愈。
    static func registrationRefusal() -> String? {
        let snapshot: ConfigSnapshot
        do {
            snapshot = try FileConfigRepository(authorizedDirectory: directory).read()
        } catch let error as NSError
            where error.domain == NSPOSIXErrorDomain && error.code == ENOENT {
            // 尚无配置文件的显式安装：放行给 performRegistration() 按其既有
            // 「无配置不建立与文件不符的所有权状态」分支处理。此前这里把 ENOENT
            // 落入通用 catch，导致全新安装被误报为 requiresRepair 而**永远无法首次注册**。
            return nil
        } catch {
            writeLog("CLI registration precheck failed: \(error)")
            return refusalLine(.requiresRepair)
        }
        do {
            let state = try durableState()
            guard let state else {
                // 首次运行：建立明确状态，绝不把「无状态」当成已授权。
                _ = try initializeOwnershipIfNeeded(revision: snapshot.revision)
                return nil
            }
            let decision = CLIOwnershipGate.decide(action: .registration, state: state,
                                                   revision: snapshot.revision)
            switch decision {
            case .permitted, .needsInitialization:
                return nil
            case .transitionInFlight:
                return refusalLine(decision)
            case .staleRevision, .staleGeneration:
                // 配置已变：登记路径按新 revision 重新收敛（协调器随后复核）。
                return nil
            default:
                return refusalLine(decision)
            }
        } catch {
            writeLog("CLI registration precheck failed: \(error)")
            return refusalLine(.requiresRepair)
        }
    }

    /// CLI 注册入口（显式 `--install`）：经共享协调器把所有权交给 cli 并完成真实注册。
    ///
    /// - 守护运行态一律不做（否则 bootout 自终止，与既有 `DaemonRuntime` 契约一致）；
    /// - app 持有时拒绝抢占；
    /// - 尚未生成配置时保留既有「按默认配置生成服务定义」行为（不伪造业务配置，
    ///   也不写与真实文件不符的所有权状态；配置生成后的下一次运行会正常建立状态）；
    /// - 其他失败保持明确状态，返回 `.unavailable` 由调用方给出修复指引。
    static func performRegistration() -> CLIRegistrationOutcome {
        let snapshot: ConfigSnapshot
        do {
            snapshot = try FileConfigRepository(authorizedDirectory: directory).read()
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == ENOENT {
            // 无配置的显式安装：维持原行为，不建立与文件不符的所有权状态。
            guard !DaemonRuntime.isDaemon() else { return .skipped }
            return registerOrUpdateLaunchAgent() ? .registered : .unavailable
        } catch {
            writeLog("CLI registration could not read configuration: \(error)")
            return .unavailable
        }
        do {
            let current = try durableState() ?? initializeOwnershipIfNeeded(revision: snapshot.revision)
            if CLIOwnershipGate.refusesAppClaim(current) {
                if let line = refusalLine(.refusedAppOwner(current.phase)) { fputs(line + "\n", stderr) }
                return .refusedAppOwner
            }
            guard !DaemonRuntime.isDaemon() else { return .skipped }
            let committed = try blockingTransfer(to: .cli, expectedGeneration: current.generation,
                                                 revision: snapshot.revision)
            return committed.owner == .cli && committed.phase == .active ? .registered : .unavailable
        } catch {
            writeLog("CLI registration refused: \(error)")
            return .unavailable
        }
    }

    // MARK: 评估（挂载/恢复/弹出/清理）生命周期

    /// 准备一次受 `EvaluationPermit` 保护的有界评估。
    ///
    /// 返回 nil 表示已拒绝（并已打印结构化提示），调用方必须跳过全部挂载副作用。
    /// 成功时统一 `evaluation.lock` 已被持有，直到上下文释放。
    static func beginEvaluation() -> CLIEvaluationContext? {
        do {
            let repository = FileConfigRepository(authorizedDirectory: directory)
            let store = BackendStateStore(authorizedDirectory: directory)
            var snapshot = try repository.read()
            var durable = try durableState() ?? initializeOwnershipIfNeeded(revision: snapshot.revision)
            if durable.phase == .failed || durable.phase == .stopping || durable.phase == .activating {
                print(cliRecoveryStatusLine())
                return nil
            }
            let needsClaim = !(durable.owner == .cli && durable.phase == .active
                               && durable.revision == snapshot.revision)
            if needsClaim {
                if CLIOwnershipGate.refusesAppClaim(durable) {
                    print(refusalLine(.refusedAppOwner(durable.phase)) ?? "")
                    return nil
                }
                if DaemonRuntime.isDaemon() || hasRecognizedCLIService(configuration: snapshot.configuration) {
                    // 两种情况都按「恢复原 owner」收敛，不做系统调用：
                    // a) 守护运行态不得注册（bootout 会自终止）；
                    // b) 现有 LaunchAgent 已符合目标定义且已注册——普通 `automnt` 运行
                    //    绝不能 bootout 再 bootstrap 正在运行的作业。自愈仍由 `--install`
                    //    或交互入口按明确条件处理。
                    guard adoptRecognizedCLIService(revision: snapshot.revision, state: durable) else {
                        print(refusalLine(.requiresRepair) ?? "")
                        return nil
                    }
                } else {
                    _ = try blockingTransfer(to: .cli, expectedGeneration: durable.generation,
                                             revision: snapshot.revision)
                }
                durable = try store.read()
                snapshot = try repository.read()
            }
            let permit = try EvaluationPermit(directory: directory, repository: repository,
                                              expected: snapshot, owner: .cli,
                                              generation: durable.generation, readBackend: store.read)
            return CLIEvaluationContext(permit: permit, snapshot: snapshot,
                                        expectedGeneration: durable.generation)
        } catch let error as NSError
            where error.domain == NSPOSIXErrorDomain
                && (error.code == Int(EWOULDBLOCK) || error.code == Int(EAGAIN)) {
            // 另一轮评估正在持锁运行：这是并发保护，不是需要修复的损坏状态。
            print(refusalLine(.operationInProgress) ?? "")
            writeLog("CLI evaluation deferred: another evaluation holds the operation lock")
            return nil
        } catch let error as AutomntIssue {
            switch error {
            case .incompatibleOwner:
                print(refusalLine(.refusedAppOwner(.stopped)) ?? "")
            case .serviceTransitionFailed:
                print(serviceRegistrationUnavailableLine())
            case .configurationConflict:
                print(refusalLine(.operationInProgress) ?? "")
            default:
                print(refusalLine(.requiresRepair) ?? "")
            }
            writeLog("CLI evaluation refused: \(error)")
            return nil
        } catch {
            print(refusalLine(.requiresRepair) ?? "")
            writeLog("CLI evaluation refused: \(error)")
            return nil
        }
    }

    /// 动作结束后在同一上下文内复核代次：变化即报告，绝不复用过期快照执行新动作。
    @discardableResult
    static func endEvaluation(_ context: CLIEvaluationContext) -> Bool {
        do {
            let snapshot = try FileConfigRepository(authorizedDirectory: directory).read()
            let durable = try BackendStateStore(authorizedDirectory: directory).read()
            guard durable.generation == context.expectedGeneration,
                  durable.owner == .cli, durable.phase == .active,
                  snapshot.revision == context.snapshot.revision else {
                print(refusalLine(.staleGeneration) ?? "")
                writeLog("CLI evaluation observed a changed backend generation or configuration")
                return false
            }
            return true
        } catch {
            writeLog("CLI evaluation could not re-verify ownership: \(error)")
            return false
        }
    }

    /// Explicit terminal operation; preserve installation, shares and unknown fields.
    static func disableAutomation() throws {
        guard !CLIOwnershipGate.refusesAppClaim(try durableState()) else {
            throw AutomntIssue.incompatibleOwner
        }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.read()
        var configuration = snapshot.configuration
        configuration.automationEnabled = false
        let saved = try repository.save(configuration, baseRevision: snapshot.revision)
        guard stopServiceForDisable(revision: saved.revision) else {
            throw AutomntIssue.serviceTransitionFailed
        }
    }

    /// 停用/卸载：调用方先保存配置，这里再把服务停到明确 stopped 状态。
    /// 只停服务，不卸载已有卷宗（停用语义 FR-002）。
    @discardableResult
    static func stopServiceForDisable(revision: ConfigRevision) -> Bool {
        do {
            if CLIOwnershipGate.refusesAppClaim(try durableState()) { return false }
            let current = try durableState() ?? initializeOwnershipIfNeeded(revision: revision)
            let committed = try blockingTransfer(to: .none, expectedGeneration: current.generation,
                                                 revision: revision)
            return committed.owner == .none && committed.phase == .stopped
        } catch {
            writeLog("CLI disable stop failed: \(error)")
            return false
        }
    }

    /// A previous transition is not the problem when the CLI simply could not register
    /// its LaunchAgent. Keep the two diagnoses separate so users are not told to run a
    /// recovery for a registration/permission failure.
    static func serviceRegistrationUnavailableLine() -> String {
        "[cli-ownership:serviceUnavailable] " + tr(
            "无法建立命令行后台服务：LaunchAgent 未注册或注册失败。请运行 automnt --install，并在系统设置中允许后台项目后重试。",
            "The command-line background service could not be established: its LaunchAgent is not registered or registration failed. Run automnt --install, then allow the background item in System Settings and retry.")
    }

    /// 结构化、脱敏的拒绝提示：带机器可读判定标签，便于调用点与自测断言。
    /// 文案属于 CLI 本地化层，AutomntCore 不持有面向用户的字符串。
    static func refusalLine(_ decision: CLIOwnershipDecision) -> String? {
        let message: String
        switch decision {
        case .permitted:
            return nil
        case .needsInitialization:
            message = tr("后端状态未初始化；请重新运行以建立明确状态。",
                         "Backend state is not initialized; re-run to establish explicit state.")
        case .refusedAppOwner:
            message = tr("后台服务当前由 Automnt 应用管理；命令行不会注册、自愈或抢占挂载。请在应用内停用后台服务后再使用命令行。",
                         "The background service is managed by the Automnt app; the command line will not register, self-heal, or take over mounts. Disable the app's background service first.")
        case .requiresRepair:
            message = tr("上次服务转换未完成；已保留明确失败状态，需显式修复后再继续，不会自动接管。",
                         "A previous service transition did not complete; the explicit failed state is preserved. Repair it explicitly before continuing; the CLI will not take over automatically.")
        case .transitionInFlight:
            message = tr("服务转换正在进行中；请稍后重试。",
                         "A service transition is in progress; try again later.")
        case .staleRevision:
            message = tr("配置已变更；本次操作基于过期快照，已拒绝且未做任何改动。请重新读取后再试。",
                         "Configuration changed; this operation used a stale snapshot and was refused without any change. Reload and retry.")
        case .staleGeneration:
            message = tr("后端状态代次已变化；本次操作基于过期快照，已拒绝且未做任何改动。",
                         "The backend generation changed; this operation used a stale snapshot and was refused without any change.")
        case .operationInProgress:
            message = tr("另一轮挂载评估正在运行或持有操作锁；请稍后重试。",
                         "Another mount evaluation is running or holds the operation lock; try again later.")
        }
        return "[cli-ownership:\(decision.tag)] \(message)"
    }

    /// 现有 LaunchAgent 是否已经是本 CLI 的目标定义并被 launchd 真实注册。
    /// 纯只读判定：文件校验 + `launchctl print`，不做任何系统改动。
    static func hasRecognizedCLIService(configuration: AutomntConfig) -> Bool {
        guard FileManager.default.fileExists(atPath: getLaunchAgentPlistURL().path),
              installedServiceDefinitionMatches(config: configuration) else { return false }
        return getLaunchAgentDiagnostic().isRegistered
    }

    // MARK: 内部实现

    /// 守护运行态或既有已注册服务下按「恢复原 owner」收敛：用 store 状态机把
    /// owner 收敛为 cli/active，不做任何系统调用。
    private static func adoptRecognizedCLIService(revision: ConfigRevision, state: BackendState) -> Bool {
        guard state.phase == .stopped || state.phase == .active || state.phase == .failed else { return false }
        let config = loadConfig(from: getActiveConfigURL(), migrate: false) ?? AutomntConfig()
        guard installedServiceDefinitionMatches(config: config),
              getLaunchAgentDiagnostic().isRegistered else { return false }
        let store = BackendStateStore(authorizedDirectory: directory)
        do {
            let journal = try store.begin(desiredOwner: .cli, expectedGeneration: state.generation,
                                          revision: revision, verifyConfiguration: true)
            _ = try store.advance(id: journal.id, to: .activating, verifiedStatus: .stopped)
            _ = try store.advance(id: journal.id, to: .active, verifiedStatus: .enabled,
                                  expectedRevision: revision)
            return true
        } catch {
            writeLog("CLI recognized-service adoption failed: \(error)")
            return false
        }
    }

    /// 同步 CLI 调用共享 async 协调器的有界桥接。
    /// 协调器与 CLI 适配器均无 MainActor 依赖，故不会与主线程互等。
    private static func blockingTransfer(to owner: BackendState.Owner, expectedGeneration: UInt64,
                                         revision: ConfigRevision) throws -> BackendState {
        let directory = self.directory
        let adapter = CLIServiceHandoffAdapter(revision: revision)
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        // 受锁容器表达跨线程一次性回传，无需 `@unchecked Sendable`。
        let box = LockedBox<Result<BackendState, AutomntIssue>?>(nil)
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let committed = try await HandoffCoordinator(authorizedDirectory: directory).transfer(
                    to: owner, expectedGeneration: expectedGeneration, revision: revision,
                    adapter: adapter, deadline: deadline)
                box.value = .success(committed)
            } catch {
                box.value = .failure(error as? AutomntIssue ?? .serviceTransitionFailed)
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 40) == .success, let value = box.value else {
            throw AutomntIssue.timeout
        }
        return try value.get()
    }
}

// MARK: - CLI 侧共享交接适配器

/// `HandoffServiceAdapter` 的 CLI 实现。
///
/// 复用 Entry.swift 中既有的执行函数（同模块 internal 可直接调用）：
/// - `registerOrUpdateLaunchAgent`：生成并 bootstrap 传统 LaunchAgent；
/// - `getLaunchAgentDiagnostic`：launchd 的真实注册状态（系统事实，非磁盘字段）。
///
/// 该适配器本身不做判定，判定统一在 `HandoffCoordinator` + `CLIOwnershipGate`。
struct CLIServiceHandoffAdapter: HandoffServiceAdapter {
    let revision: ConfigRevision
    let strictIdentity: Bool

    init(revision: ConfigRevision, strictIdentity: Bool = false) {
        self.revision = revision
        self.strictIdentity = strictIdentity
    }

    func stopAndVerify(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus {
        try check(deadline)
        guard owner == .cli || owner == .none else { throw AutomntIssue.incompatibleOwner }
        // 只注销服务，不删除用户配置、不注入/移除 Shell 入口（那是显式 --uninstall 的语义）。
        let plistURL = getLaunchAgentPlistURL()
        var needsBootout = true
        let observedPID = LockedBox<Int32?>(nil)
        if strictIdentity {
            if FileManager.default.fileExists(atPath: plistURL.path) {
                let data = try PrivateAtomicFile.read(plistURL)
                guard let definition = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                      definition["Label"] as? String == launchAgentLabel,
                      definition["ProgramArguments"] as? [String] == [getActiveInstalledBinaryURL().path],
                      definition["Program"] == nil,
                      CLIOwnershipGate.permitsNonResidentDefinition(definition) else {
                    throw AutomntIssue.incompatibleOwner
                }
            }
            switch try verifiedPresence(deadline: deadline, requireCLIIdentity: true, observedPID: observedPID) {
            case .registered: break
            case .absent: needsBootout = false
            case .unknown: throw AutomntIssue.serviceTransitionFailed
            }
        }
        let serviceTarget = "gui/\(getuid())/\(launchAgentLabel)"
        let remaining = ContinuousClock.now.duration(to: deadline).components
        let timeout = max(0, Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18)
        if needsBootout {
            let stopped = runCommandDiscardingOutputWithTimeout(executable: "/bin/launchctl",
                arguments: ["bootout", serviceTarget], timeout: min(timeout, 10))
            guard !stopped.timedOut, stopped.processStopped, stopped.error == nil else {
                throw AutomntIssue.serviceTransitionFailed
            }
        }
        try check(deadline)
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
        try check(deadline)
        guard try verifiedPresence(deadline: deadline) == .absent else { throw AutomntIssue.serviceTransitionFailed }
        if let pid = observedPID.value {
            while !(kill(pid, 0) == -1 && errno == ESRCH) {
                try check(deadline)
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        // 与挂载共用同一把评估锁，确认无在途 worker。
        let lock = try StableFileLock(url: CLIOwnership.directory.appendingPathComponent("evaluation.lock"))
        try withExtendedLifetime(lock) {
            try WorkerOperationStore(authorizedDirectory: CLIOwnership.directory).verifyIdle()
        }
        guard try verifiedPresence(deadline: deadline) == .absent else { throw AutomntIssue.serviceTransitionFailed }
        return .stopped
    }

    private func verifiedPresence(deadline: ContinuousClock.Instant, requireCLIIdentity: Bool = false,
                                  observedPID: LockedBox<Int32?>? = nil) throws -> LaunchAgentPresence {
        try check(deadline)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("automnt-launchctl-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw AutomntIssue.serviceTransitionFailed
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let remaining = ContinuousClock.now.duration(to: deadline).components
        let timeout = max(0, Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18)
        let result = runCommandDiscardingOutputWithTimeout(executable: "/bin/launchctl",
            arguments: ["print", "gui/\(getuid())/\(launchAgentLabel)"], timeout: min(timeout, 5),
            standardOutputFile: requireCLIIdentity ? handle : nil, standardErrorFile: handle)
        let data = try PrivateAtomicFile.read(url, maximumBytes: 65_536)
        let output = String(decoding: data, as: UTF8.self)
        let presence = LaunchAgentPresence.classify(status: result.status, timedOut: result.timedOut,
            processStopped: result.processStopped, standardError: output, serviceLabel: launchAgentLabel)
        if requireCLIIdentity && presence == .registered {
            guard firstRegexCapture(#"(?m)^\s*program = (.+)$"#, in: output) == getActiveInstalledBinaryURL().path else {
                throw AutomntIssue.incompatibleOwner
            }
            if let value = firstRegexCapture(#"(?m)^\s*pid = (.+)$"#, in: output) {
                guard let pid = Int32(value), pid > 1, pid != getpid() else { throw AutomntIssue.incompatibleOwner }
                observedPID?.value = pid
            }
        }
        return presence
    }

    func register(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus {
        try check(deadline)
        guard owner == .cli else { throw AutomntIssue.incompatibleOwner }
        // app 持有时严禁注册/自愈抢占。这里刻意只按 owner 判定而不按 phase：
        // 协调器刚写入的 activating 日志（desiredOwner=cli）属于本次转换本身，必须容忍。
        let state = try CLIOwnership.durableState()
        guard !CLIOwnershipGate.refusesAppClaim(state) else { throw AutomntIssue.incompatibleOwner }
        guard !DaemonRuntime.isDaemon() else { throw AutomntIssue.incompatibleOwner }
        guard registerOrUpdateLaunchAgent() else { throw AutomntIssue.serviceTransitionFailed }
        try check(deadline)
        return try await status(owner: owner, deadline: deadline)
    }

    func status(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus {
        try check(deadline)
        guard owner == .cli else { throw AutomntIssue.incompatibleOwner }
        let snapshot = try FileConfigRepository(authorizedDirectory: CLIOwnership.directory).read()
        guard snapshot.revision == revision else { throw AutomntIssue.configurationConflict }
        switch try verifiedPresence(deadline: deadline) {
        case .registered: return .enabled
        case .absent: return .stopped
        case .unknown: return .unavailable
        }
    }

    /// CLI 没有独立常驻评估进程：本次调用方就是评估者。
    /// 此处只在持锁下复核系统事实，绝不改配置、绝不制造「已评估」的假成功。
    func requestEvaluation(state: BackendState, deadline: ContinuousClock.Instant) async throws {
        try check(deadline)
        guard state.phase == .active, state.owner == .cli else { throw AutomntIssue.incompatibleOwner }
        let store = BackendStateStore(authorizedDirectory: CLIOwnership.directory)
        let lock = try StableFileLock(url: CLIOwnership.directory.appendingPathComponent("evaluation.lock"))
        try withExtendedLifetime(lock) {
            let durable = try store.read()
            guard durable.generation == state.generation, durable.owner == .cli else {
                throw AutomntIssue.configurationConflict
            }
            let snapshot = try FileConfigRepository(authorizedDirectory: CLIOwnership.directory).read()
            guard snapshot.revision == state.revision else { throw AutomntIssue.configurationConflict }
            guard getLaunchAgentDiagnostic().isRegistered else { throw AutomntIssue.serviceTransitionFailed }
        }
    }

    private func check(_ deadline: ContinuousClock.Instant) throws {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw AutomntIssue.timeout }
    }
}
