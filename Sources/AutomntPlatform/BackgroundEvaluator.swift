import Foundation
import AutomntCore

public struct BackgroundEvaluationSummary: Codable, Sendable {
    public let schema: Int
    public let observedAt: Date
    public let observations: [VolumeObservation]
    public let issue: AutomntIssue?
    public let retrySuggested: Bool?
    public init(observations: [VolumeObservation] = [], issue: AutomntIssue? = nil,
                retrySuggested: Bool = false) {
        self.retrySuggested = retrySuggested
        schema = 1
        observedAt = Date(); self.observations = observations; self.issue = issue
    }
}

/// worker 挂载执行结果：响应 + 该次请求的操作标识（失败提交需要它）。
struct BackgroundMountExecution {
    let response: WorkerMountResponse
    let operationID: UUID
}

/// helper 特有的平台副作用接缝。
///
/// 只封装「平台适配」：worker 子进程调用、隔离健康探测、凭据读取、内核挂载表查询，
/// 以及随调用发生的 EvaluationPermit + 组件级持久提交。**不含任何恢复业务规则**——
/// 逐卷动作判定统一来自 `AutomntCore.RecoveryVolumeDecisionPolicy`。
struct BackgroundVolumeEffects {
    var mountPathState: (String) -> MountPathState
    var inspect: (SMBShareConfig, HostConfig, ConfigSnapshot, BackendState,
                  URL, ContinuousClock.Instant) throws -> WorkerMountResponse
    var mount: (SMBShareConfig, HostConfig, ConfigSnapshot, BackendState,
                URL, ContinuousClock.Instant) throws -> BackgroundMountExecution
    var cleanup: (SMBShareConfig, HostConfig, ConfigSnapshot, BackendState,
                  URL, ContinuousClock.Instant) throws -> WorkerMountResponse

    /// 生产接线：真实 worker 子进程 + 内核挂载表 + Keychain。
    ///
    /// runner 延迟构造，保持改动前「先探活主机、再构造 worker runner」的顺序
    /// （主机全不可达时不得因 runner 构造失败而改变返回值）。
    static func live(applicationBundle: Bundle, directory: AuthorizedDirectory) -> BackgroundVolumeEffects {
        let runner = LazyRunner(applicationBundle: applicationBundle)
        return BackgroundVolumeEffects(
            mountPathState: { NetFSWorkerOperation.mountPathState(at: $0) },
            inspect: { share, host, snapshot, backend, _, deadline in
                try inspect(runner: runner.value(), share: share, host: host, snapshot: snapshot,
                            backend: backend, directory: directory, deadline: deadline)
            },
            mount: { share, host, snapshot, backend, _, deadline in
                try mount(runner: runner.value(), share: share, host: host, snapshot: snapshot,
                          backend: backend, directory: directory, deadline: deadline)
            },
            cleanup: { share, host, snapshot, backend, _, deadline in
                try cleanup(runner: runner.value(), share: share, host: host, snapshot: snapshot,
                            backend: backend, directory: directory, deadline: deadline)
            })
    }

    /// 首次用到 worker 时才构造（并发安全：evaluate 内串行使用）。
    private final class LazyRunner: @unchecked Sendable {
        private let applicationBundle: Bundle
        private var cached: MountWorkerRunner?
        init(applicationBundle: Bundle) { self.applicationBundle = applicationBundle }
        func value() throws -> MountWorkerRunner {
            if let cached { return cached }
            let created = try MountWorkerRunner(applicationBundle: applicationBundle)
            cached = created
            return created
        }
    }

    // MARK: - worker 子进程 + 组件级提交

    static func inspect(runner: MountWorkerRunner, share: SMBShareConfig, host: HostConfig,
                                snapshot: ConfigSnapshot, backend: BackendState,
                                directory: AuthorizedDirectory,
                                deadline: ContinuousClock.Instant) throws -> WorkerMountResponse {
        try Task.checkCancellation()
        let remaining = ContinuousClock.now.duration(to: deadline).components
        let seconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
        guard seconds > 0 else { throw AutomntIssue.timeout }
        let request = WorkerMountRequest(host: host, share: share,
            expiresAtUptime: ProcessInfo.processInfo.systemUptime + min(seconds, 1),
            revision: snapshot.revision, generation: backend.generation, operation: .health)
        let response = runner.health(request: request, authorizedDirectory: directory)
        if let observation = response.observation {
            let repository = FileConfigRepository(authorizedDirectory: directory.url)
            let store = BackendStateStore(authorizedDirectory: directory.url)
            let permit = try EvaluationPermit(directory: directory.url, repository: repository,
                expected: snapshot, owner: .app, generation: backend.generation, readBackend: store.read)
            try permit.perform { _ in
                try RecoveryHealthCommit.apply(observation, directory: directory.url,
                    stillMounted: NetFSWorkerOperation.mountedIdentity(at: share.mountPoint) == observation.identity)
            }
        }
        return response
    }

    static func cleanup(runner: MountWorkerRunner, share: SMBShareConfig, host: HostConfig,
                                snapshot: ConfigSnapshot, backend: BackendState,
                                directory: AuthorizedDirectory,
                                deadline: ContinuousClock.Instant) throws -> WorkerMountResponse {
        try Task.checkCancellation()
        let remaining = ContinuousClock.now.duration(to: deadline).components
        let seconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
        guard seconds > 0 else { throw AutomntIssue.timeout }
        let request = WorkerMountRequest(host: host, share: share,
            expiresAtUptime: ProcessInfo.processInfo.systemUptime + min(seconds, 5),
            revision: snapshot.revision, generation: backend.generation, operation: .cleanup)
        let response = runner.cleanup(request: request, authorizedDirectory: directory)
        if let observation = response.observation {
            let repository = FileConfigRepository(authorizedDirectory: directory.url)
            let store = BackendStateStore(authorizedDirectory: directory.url)
            let permit = try EvaluationPermit(directory: directory.url, repository: repository,
                expected: snapshot, owner: .app, generation: backend.generation, readBackend: store.read)
            try permit.perform { current in
                try RecoveryCleanupCommit.apply(observation, directory: directory.url,
                    configuration: current.configuration, path: NetFSWorkerOperation.mountPathState(at: share.mountPoint))
            }
        }
        return response
    }

    static func mount(runner: MountWorkerRunner, share: SMBShareConfig, host: HostConfig,
                      snapshot: ConfigSnapshot, backend: BackendState,
                      directory: AuthorizedDirectory,
                      deadline: ContinuousClock.Instant) throws -> BackgroundMountExecution {
        // 顺序与改动前一致：先取凭据，再核剩余预算。
        let credential = try KeychainCredentialProvider().read(identity: smbResourceIdentity(share.smbURL) ?? "")
        let remaining = ContinuousClock.now.duration(to: deadline).components
        let seconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
        guard seconds > 0 else { throw AutomntIssue.timeout }
        let request = WorkerMountRequest(host: host, share: share,
            expiresAtUptime: ProcessInfo.processInfo.systemUptime + min(seconds, 30),
            revision: snapshot.revision, generation: backend.generation)
        let response = runner.mount(request: request, credential: credential, authorizedDirectory: directory)
        return BackgroundMountExecution(response: response, operationID: request.operationID)
    }
}

/// A single bounded evaluation; launchd triggers are provided separately.
public enum BackgroundEvaluator {
    public static func evaluate(applicationBundle: Bundle, directory: AuthorizedDirectory,
                                deadline: ContinuousClock.Instant,
                                expectedRevision: ConfigRevision? = nil) async throws -> BackgroundEvaluationSummary {
        let repository = FileConfigRepository(authorizedDirectory: directory.url)
        let snapshot = try repository.read()
        if let expectedRevision, snapshot.revision != expectedRevision {
            throw AutomntIssue.configurationConflict
        }
        guard snapshot.configuration.isAutomationEnabled else { return BackgroundEvaluationSummary() }
        let stateStore = BackendStateStore(authorizedDirectory: directory.url)
        let backend = try stateStore.read()
        // Validate under the operation lock before even probing. Release before child launch.
        do {
            let permit = try EvaluationPermit(directory: directory.url, repository: repository,
                expected: snapshot, owner: .app, generation: backend.generation, readBackend: stateStore.read)
            try permit.perform { current in
                guard current.configuration.isAutomationEnabled else { throw AutomntIssue.incompatibleOwner }
                let stateURL = directory.url.appendingPathComponent("mount-recovery-state.plist")
                let previous = RecoveryStateRepository(url: stateURL).read()
                var mountedKeys = Set<String>()
                for host in current.configuration.hosts where host.enabled {
                    for share in host.shares where share.enabled {
                        switch NetFSWorkerOperation.mountPathState(at: share.mountPoint) {
                        case .unavailable: throw AutomntIssue.signalUnavailable
                        case .smb(let identity): mountedKeys.insert(identity)
                        case .absent, .occupied: break
                        }
                    }
                }
                _ = try RecoverySessionCommit.advance(directory: directory.url,
                    identity: RecoverySessionCollector.collect(previous: previous.file.sessionBoundary),
                    mountedKeys: mountedKeys)
            }
        }
        let effects = BackgroundVolumeEffects.live(applicationBundle: applicationBundle, directory: directory)
        // Keep the security-scoped directory alive across the whole bounded evaluation.
        defer { withExtendedLifetime(directory) {} }
        return try await evaluate(directory: directory.url, snapshot: snapshot, backend: backend,
            deadline: deadline, probe: TCPReachabilityProbe(), effects: effects)
    }

    /// 可注入核心：async 探活与 worker 副作用均来自参数，判定来自共享 `RecoveryVolumeDecisionPolicy`。
    static func evaluate(directory: URL, snapshot: ConfigSnapshot, backend: BackendState,
                         deadline: ContinuousClock.Instant, probe: any ReachabilityProbe,
                         effects: BackgroundVolumeEffects,
                         isolation: isolated (any Actor)? = #isolation) async throws -> BackgroundEvaluationSummary {
        guard let host = try await HostPriorityEvaluator.firstReachable(in: snapshot.configuration,
            deadline: deadline, probe: probe) else {
            return BackgroundEvaluationSummary(issue: .offline)
        }
        var observations: [VolumeObservation] = []
        var deferred = false
        var definiteFailure: AutomntIssue?
        for share in host.shares where share.enabled {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline, let identity = smbResourceIdentity(share.smbURL) else {
                return BackgroundEvaluationSummary(observations: observations, issue: .timeout)
            }
            let recovery = RecoveryStateRepository(url: directory.appendingPathComponent("mount-recovery-state.plist")).read()
            let path = effects.mountPathState(share.mountPoint)
            let present = path == .smb(identity: identity)

            // 挂载点状态门（非恢复规则）：不可用/占用/其他身份一律阻断。
            if let blocked = BaselineMountDecision.block(path: path, identity: identity) {
                switch blocked {
                case .blocked(let issue): return BackgroundEvaluationSummary(observations: observations, issue: issue)
                case .inspectExisting: break
                case .mount, .suppressed, .deferred: return BackgroundEvaluationSummary(observations: observations, issue: .pathConflict)
                }
            }

            // 逐卷判定唯一实现（共享）。在表卷先以 unknown 健康判定（保守：不得清理），
            // 探测后以真实健康复判 attachHealthy / cleanupThenRecover。
            var judgment = judge(identity: identity, share: share, configuration: snapshot.configuration,
                recovery: recovery, present: present, health: .unavailable)

            if present {
                let response = try effects.inspect(share, host, snapshot, backend, directory, deadline)
                if let observation = response.observation { observations.append(observation) }
                if let issue = response.issue {
                    return BackgroundEvaluationSummary(observations: observations, issue: issue)
                }
                judgment = judge(identity: identity, share: share, configuration: snapshot.configuration,
                    recovery: recovery, present: true, health: healthEvidence(of: response.observation))
                switch judgment.decision {
                case .attachHealthy:
                    // 健康/未知：无动作（未知健康不得授予清理许可）。
                    continue
                case .cleanupThenRecover:
                    guard let observation = response.observation,
                          RecoveryCleanupCommit.permits(configuration: snapshot.configuration, recovery: recovery,
                              identity: identity, health: .failed) else { continue }
                    _ = observation
                    let cleaned = try effects.cleanup(share, host, snapshot, backend, directory, deadline)
                    if let issue = cleaned.issue {
                        return BackgroundEvaluationSummary(observations: observations, issue: issue)
                    }
                    // Clear the obsolete failed observation before the replacement mount.
                    observations.removeLast()
                default:
                    continue
                }
            } else {
                switch judgment.decision {
                case .sessionSuppressed:
                    observations.append(VolumeObservation(identity: identity, status: .suppressed,
                        actualPath: nil, observedAt: Date()))
                    continue
                case .deferred:
                    deferred = true
                    observations.append(VolumeObservation(identity: identity, status: .evaluating,
                        actualPath: nil, observedAt: Date()))
                    continue
                case .pendingUnreachable:
                    // 主机已探活可达；此处仅在共享判定拒绝挂载时保守跳过，不伪造失败。
                    observations.append(VolumeObservation(identity: identity, status: .offline,
                        actualPath: nil, observedAt: Date()))
                    continue
                case .recover: break
                case .attachHealthy, .cleanupThenRecover: continue
                }
            }

            let execution = try effects.mount(share, host, snapshot, backend, directory, deadline)
            let response = execution.response
            if let issue = response.issue {
                if let observation = RecoveryFailureObservation.mount(identity: identity, issue: issue,
                    requiresReconciliation: response.requiresReconciliation) {
                    let permit = try EvaluationPermit(directory: directory,
                        repository: FileConfigRepository(authorizedDirectory: directory),
                        expected: snapshot, owner: .app, generation: backend.generation,
                        readBackend: BackendStateStore(authorizedDirectory: directory).read)
                    try permit.perform { _ in
                        try RecoveryAttemptCommit.rejected(identity: identity, directory: directory,
                            path: effects.mountPathState(share.mountPoint),
                            operationID: execution.operationID, observedAt: observation.observedAt)
                    }
                    observations.append(observation)
                    definiteFailure = issue
                    continue
                }
                return BackgroundEvaluationSummary(observations: observations, issue: issue)
            }
            // Mount confirmation establishes kernel identity only; verify access in a new child.
            let healthRemaining = ContinuousClock.now.duration(to: deadline).components
            let healthSeconds = Double(healthRemaining.seconds) + Double(healthRemaining.attoseconds) / 1e18
            guard healthSeconds > 0 else {
                if let observation = response.observation { observations.append(observation) }
                return BackgroundEvaluationSummary(observations: observations, issue: .timeout)
            }
            let healthResponse = try effects.inspect(share, host, snapshot, backend, directory, deadline)
            if let observation = healthResponse.observation { observations.append(observation) }
            if let issue = healthResponse.issue {
                return BackgroundEvaluationSummary(observations: observations, issue: issue)
            }
        }
        // superseded 剔除唯一实现在 `RecoverySupersededPolicy`（新主机已同一路径接管）。
        let filtered = supersededFiltered(observations, configuration: snapshot.configuration)
        return BackgroundEvaluationSummary(observations: filtered, issue: definiteFailure,
            retrySuggested: deferred || definiteFailure != nil)
    }

    /// 共享逐卷判定桥接（internal 以便测试直接断言三路径一致性）。
    ///
    /// 约定：`sessionBoundary == nil` 表示尚未建立会话边界，此时**不得**启用同路径
    /// 对端抑制（由 `RecoveryVolumeDecisionPolicy` 的 `let boundary` 门实现）。
    /// 三处调用点必须原样传递 `state.sessionBoundary`，不得用 `?? ""` 之类的兜底
    /// 掩盖 nil（V8 缺陷 G2）。
    static func judge(identity: String, share: SMBShareConfig, configuration: AutomntConfig,
                              recovery: MountRecoveryStoreLoad, present: Bool,
                              health: VolumeHealthEvidence) -> RecoveryVolumeJudgment {
        RecoveryVolumeDecisionPolicy.judge(
            RecoveryVolumeFacts(identity: identity, mountPoint: share.mountPoint,
                presentInMountTable: present, hostReachable: true, health: health),
            context: RecoveryVolumeContext(configuration: configuration, state: recovery.file,
                // nil 必须保持 nil：`sessionBoundary == nil` 表示尚未建立会话边界，
                // 此时不得启用同路径对端抑制（与 BaselineMountDecision/改动前 helper 一致）。
                // 传空串会通过 `let boundary` 而错误启用该抑制（V8 缺陷 G2）。
                stateReadable: recovery.isReadable, boundary: recovery.file.sessionBoundary,
                peers: RecoveryVolumeDecisionPolicy.peers(configuration: configuration),
                manualRecovery: false,
                permitsMount: configuration.isAutoMountRecoveryEnabled,
                appliesAttemptLimit: true, appliesRetryInterval: true))
    }

    private static func healthEvidence(of observation: VolumeObservation?) -> VolumeHealthEvidence {
        guard let observation else { return .unavailable }
        if observation.status == .healthy && observation.issue == nil { return .healthy }
        if observation.status == .failed && observation.issue == .shareRejected { return .failed }
        return .unavailable
    }

    /// 用共享 superseded 规则过滤观测：同一挂载点已被其他身份恢复时不得再报失败。
    ///
    /// 单主机轮次内配置校验禁止同主机重复挂载点，故此处通常为空操作；
    /// 仍保留以与 CLI 共用同一规则（跨主机备用场景由 CLI/planner 覆盖）。
    private static func supersededFiltered(_ observations: [VolumeObservation],
                                           configuration: AutomntConfig) -> [VolumeObservation] {
        let mounts = Dictionary(configuration.hosts.filter(\.enabled).flatMap { host in
            host.shares.filter(\.enabled).compactMap { share -> (String, String)? in
                smbResourceIdentity(share.smbURL).map { ($0, share.mountPoint) }
            }
        }, uniquingKeysWith: { first, _ in first })
        let recovered = Set(observations.filter { $0.status == .healthy && $0.issue == nil }.map(\.identity))
        let superseded = RecoverySupersededPolicy.supersededIdentities(recovered: recovered,
            volumes: mounts.map { (identity: $0.key, mountPoint: $0.value) })
        guard !superseded.isEmpty else { return observations }
        return observations.filter { !superseded.contains($0.identity) }
    }
}
