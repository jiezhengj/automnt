import Foundation

/// 恢复轮次的配置启用卷视图（Core SSOT：启用主机 × 启用共享）。
///
/// CLI 与 helper 共用同一份「哪些卷参与恢复」的规则，避免第二套实现。
public struct RecoveryRoundConfiguredVolume: Equatable, Sendable {
    public let identity: String
    public let url: String
    public let mountPoint: String
    public let host: String
    public let port: Int
    public let preventSpotlightIndex: Bool

    public init(identity: String, url: String, mountPoint: String, host: String, port: Int,
                preventSpotlightIndex: Bool) {
        self.identity = identity
        self.url = url
        self.mountPoint = mountPoint
        self.host = host
        self.port = port
        self.preventSpotlightIndex = preventSpotlightIndex
    }

    /// 身份别名：与配置模型中的 `volumeKey` 语义一致。
    public var key: String { identity }
}

/// 配置启用卷的唯一来源；禁用项保留历史账目但不再参与恢复。
public func configuredRecoveryVolumes(from configuration: AutomntConfig) -> [RecoveryRoundConfiguredVolume] {
    var volumes: [RecoveryRoundConfiguredVolume] = []
    for host in configuration.hosts where host.enabled {
        for share in host.shares where share.enabled {
            guard let identity = smbResourceIdentity(share.smbURL) else { continue }
            volumes.append(RecoveryRoundConfiguredVolume(identity: identity, url: share.smbURL,
                mountPoint: share.mountPoint, host: host.host, port: host.port,
                preventSpotlightIndex: host.preventSpotlightIndex))
        }
    }
    return volumes
}

/// 自账清理范围：全部配置条目（含禁用）。只有真正删除配置条目才清除历史。
public func knownRecoveryVolumeIdentities(in configuration: AutomntConfig) -> Set<String> {
    Set(configuration.hosts.flatMap { $0.shares }.compactMap { smbResourceIdentity($0.smbURL) })
}

/// 单卷观测快照：只承载事实，不承载判定结论。
public struct RecoveryRoundVolumeSnapshot: Equatable, Sendable {
    public let identity: String
    public let mountPoint: String
    public let host: String
    public let port: Int
    public let presentInMountTable: Bool
    public let observedPath: String?
    public let hostReachable: Bool
    public let health: VolumeHealthEvidence

    public init(identity: String, mountPoint: String, host: String, port: Int,
                presentInMountTable: Bool, observedPath: String?, hostReachable: Bool,
                health: VolumeHealthEvidence) {
        self.identity = identity
        self.mountPoint = mountPoint
        self.host = host
        self.port = port
        self.presentInMountTable = presentInMountTable
        self.observedPath = observedPath
        self.hostReachable = hostReachable
        self.health = health
    }
}

/// 本卷在本轮实际采取的动作（计划即执行依据）。
public enum RecoveryVolumeAction: Equatable, Sendable {
    /// 已健康挂载：幂等跳过，并清除修复证据与预算。
    case attachHealthy
    /// 死卷（在表但不可达/不健康）：先清理再恢复。
    case cleanupThenRecover
    /// 纳入恢复挂载。
    case recover
    /// 会话抑制：本可达会话内零重挂。
    case suppress
    /// 本轮不进入挂载，保留待恢复（主机不可达，或死卷清理未成功）。
    case pendingUnreachable
    /// 整轮顺延：锁不可用或另一轮正在运行；不消耗预算与通知额度。
    case deferred
}

/// 逐卷计划条目。
public struct RecoveryVolumePlan: Equatable, Sendable {
    public let identity: String
    public let mountPoint: String
    public let action: RecoveryVolumeAction

    public init(identity: String, mountPoint: String, action: RecoveryVolumeAction) {
        self.identity = identity
        self.mountPoint = mountPoint
        self.action = action
    }
}

/// 单次挂载尝试的结果；`failure` 仅在未成功时使用。
public struct RecoveryMountAttempt: Equatable, Sendable {
    public let succeeded: Bool
    public let failure: RecoveryAttemptOutcome

    public init(succeeded: Bool, failure: RecoveryAttemptOutcome) {
        self.succeeded = succeeded
        self.failure = failure
    }
}

/// 注入副作用：挂载、清理与剩余预算。判定规则不在此层。
public struct RecoveryRoundEffects {
    /// 清理死卷（入参为观测到的挂载路径）；返回是否清理成功。
    public var cleanup: (String) -> Bool
    /// 对某卷执行一次有界挂载尝试。
    public var mount: (String) -> RecoveryMountAttempt
    /// 剩余执行预算秒数；≤0 时本轮不再发起新尝试。
    public var budgetRemaining: () -> TimeInterval

    public init(cleanup: @escaping (String) -> Bool,
                mount: @escaping (String) -> RecoveryMountAttempt,
                budgetRemaining: @escaping () -> TimeInterval) {
        self.cleanup = cleanup
        self.mount = mount
        self.budgetRemaining = budgetRemaining
    }
}

/// 一轮恢复的输入。
public struct RecoveryRoundRequest {
    public let configuration: AutomntConfig
    public let load: MountRecoveryStoreLoad
    public let sessionNetwork: String
    public let sessionLoginEpoch: String
    public let mountedIdentities: Set<String>
    public let manualRecovery: Bool
    public let volumes: [RecoveryRoundConfiguredVolume]
    public let now: () -> Date

    public init(configuration: AutomntConfig, load: MountRecoveryStoreLoad,
                sessionNetwork: String, sessionLoginEpoch: String,
                mountedIdentities: Set<String>, manualRecovery: Bool,
                volumes: [RecoveryRoundConfiguredVolume],
                now: @escaping () -> Date = Date.init) {
        self.configuration = configuration
        self.load = load
        self.sessionNetwork = sessionNetwork
        self.sessionLoginEpoch = sessionLoginEpoch
        self.mountedIdentities = mountedIdentities
        self.manualRecovery = manualRecovery
        self.volumes = volumes
        self.now = now
    }
}

/// 一轮恢复的结果：账本、动作计划与对外可观察集合。
public struct RecoveryRoundResult: Sendable {
    public var state: MountRecoveryStateFile
    public var plan: [RecoveryVolumePlan]
    public var recovered: [String]
    public var failed: [String]
    public var suppressed: [String]
    public var deferredIdentities: [String]
    public var attempted: Int
    /// 本轮允许进入通知的卷身份集合。
    public var notificationIdentities: [String]

    public init(state: MountRecoveryStateFile = MountRecoveryStateFile(),
                plan: [RecoveryVolumePlan] = [], recovered: [String] = [], failed: [String] = [],
                suppressed: [String] = [], deferredIdentities: [String] = [],
                attempted: Int = 0, notificationIdentities: [String] = []) {
        self.state = state
        self.plan = plan
        self.recovered = recovered
        self.failed = failed
        self.suppressed = suppressed
        self.deferredIdentities = deferredIdentities
        self.attempted = attempted
        self.notificationIdentities = notificationIdentities
    }
}

/// 恢复轮次共享协调器（T009-c 的规则部分）。
///
/// 单轮 = 会话边界推进 → 逐卷分类 → 按计划执行清理/挂载副作用 → 结算账本与通知额度。
/// 全部判定、账本与通知计数规则集中在此，CLI 与 helper 只提供观测与副作用。
public enum RecoveryRoundPlanner {

    /// 恢复判定与会话抑制的开关门（FR-008）。
    public static func isPermitted(configuration: AutomntConfig) -> Bool {
        configuration.isAutomationEnabled && configuration.isAutoMountRecoveryEnabled
    }

    /// 单轮执行预算窗口（毫秒，1000–30000 夹限）。
    public static func retryWindowMilliseconds(_ configuration: AutomntConfig) -> Int {
        min(max(configuration.retryPolicy?.maxTotalWindowMs ?? 10000, 1000), 30000)
    }

    /// 探测结果映射为健康证据；未知不证明健康。
    public static func healthEvidence(_ probe: Bool?) -> VolumeHealthEvidence {
        guard let probe else { return .unavailable }
        return probe ? .healthy : .failed
    }

    /// 主机顺位：首个启用的可达主机。共享失败不得切换备用主机（在挂载前选定）。
    public static func firstReachableHost(in configuration: AutomntConfig,
                                          probe: (String, Int) -> Bool) -> HostConfig? {
        configuration.hosts.first { $0.enabled && probe($0.host, $0.port) }
    }

    /// 本轮参与判定的卷：仅选定主机；但在表且主机不可达的卷仍须进入（否则死卷清理与
    /// 修复证据丢失）。
    public static func relevantVolumes(configuration: AutomntConfig, mountedIdentities: Set<String>,
                                       probe: (String, Int) -> Bool) -> [RecoveryRoundConfiguredVolume] {
        let all = configuredRecoveryVolumes(from: configuration)
        let selected = firstReachableHost(in: configuration, probe: probe)
        return all.filter {
            selected == nil ||
            ($0.host == selected?.host && $0.port == selected?.port) ||
            (mountedIdentities.contains($0.identity) && !probe($0.host, $0.port))
        }
    }

    /// 整轮顺延（锁不可用/另一轮运行中）。不读取、不写账本，不消耗预算与通知额度。
    public static func deferRound(configuration: AutomntConfig) -> RecoveryRoundResult {
        let volumes = configuredRecoveryVolumes(from: configuration)
        return RecoveryRoundResult(
            plan: volumes.map { RecoveryVolumePlan(identity: $0.identity, mountPoint: $0.mountPoint,
                                                    action: .planned(for: .deferred)) },
            deferredIdentities: volumes.map(\.identity))
    }

    /// 执行一轮恢复。`observe` 逐卷按序提供观测快照，保持与执行交错的探测顺序。
    public static func run(request: RecoveryRoundRequest,
                           observe: (RecoveryRoundConfiguredVolume) -> RecoveryRoundVolumeSnapshot,
                           effects: RecoveryRoundEffects) -> RecoveryRoundResult {
        var result = RecoveryRoundResult(state: request.load.file)
        guard isPermitted(configuration: request.configuration) else { return result }

        let stateReadable = request.load.isReadable
        let mountedKeys = request.mountedIdentities
        let allVolumes = configuredRecoveryVolumes(from: request.configuration)

        let identity = RecoverySessionIdentity(network: request.sessionNetwork,
            loginEpoch: request.sessionLoginEpoch, previous: result.state.sessionBoundary)
        let boundary = identity.combined
        RecoverySessionPolicy.advance(&result.state, to: identity, mountedKeys: mountedKeys)

        // 禁用保留历史；只有真正删除配置条目才清除自账。
        let knownKeys = knownRecoveryVolumeIdentities(in: request.configuration)
        result.state.volumes = result.state.volumes.filter { knownKeys.contains($0.key) }
        result.state.cleanupLedger = result.state.cleanupLedger.filter { knownKeys.contains($0.key) }
        result.state.attempts = result.state.attempts.filter { knownKeys.contains($0.key) }

        // 逐卷判定唯一实现在 `RecoveryVolumeDecisionPolicy`；planner 与 helper
        // （BaselineMountDecision / worker）共用它，此处不得再自行实现分支。
        let peers = RecoveryVolumeDecisionPolicy.peers(configuration: request.configuration,
                                                       presentIdentities: mountedKeys)

        for volume in request.volumes {
            let snapshot = observe(volume)
            // 逐卷判定唯一实现在 `RecoveryVolumeDecisionPolicy`；planner 与 helper
            // （BaselineMountDecision / worker）共用它，此处不得再自行实现分支。
            let judgment = RecoveryVolumeDecisionPolicy.judge(
                RecoveryVolumeFacts(identity: snapshot.identity, mountPoint: snapshot.mountPoint,
                    presentInMountTable: snapshot.presentInMountTable,
                    hostReachable: snapshot.hostReachable, health: snapshot.health),
                context: RecoveryVolumeContext(configuration: request.configuration,
                    state: result.state, stateReadable: stateReadable, boundary: boundary,
                    peers: peers, manualRecovery: request.manualRecovery,
                    permitsMount: RecoveryRoundPlanner.isPermitted(configuration: request.configuration),
                    now: request.now()))
            // **动作的唯一来源是 `judgment.decision`**：下方 switch 直接以它分派，
            // 不得再由 `signal` 二次推导动作（V8 缺陷 G1）。`signal` 仅用于账本标记
            // （unknownConservative 的保守 everHealthyMounted）与诊断；superseded 剔除
            // 与通知额度结算是**结算**逻辑，同样不构成第二套动作映射。
            let signal = judgment.signal

            var working = result.state.volumes[snapshot.identity] ?? MountRecoveryVolumeRecord(volumeKey: snapshot.identity)
            working.updatedAt = request.now().timeIntervalSince1970
            var action: RecoveryVolumeAction

            switch judgment.decision {
            case .attachHealthy:
                // 幂等 + 自触发防护：已挂载即跳过，且自身挂载不产生新的恢复尝试。
                working.state = .attached
                working.repairEjectEvidence = false
                working.everHealthyMounted = true
                working.attemptCount = 0
                working.notificationCount = 0
                working.suppressionBoundary = nil
                // 成功挂载清除抑制（FR-002）。
                result.state.cleanupLedger.removeValue(forKey: snapshot.identity)
                action = .planned(for: judgment.decision)

            case .recover, .cleanupThenRecover:
                // `.cleanupThenRecover` 的计划是「先清理死卷、再恢复」；清理副作用
                // 失败时本轮不得挂载，按待恢复记录——这是执行结果，不是第二套映射。
                let cleanupFirst = judgment.decision == .cleanupThenRecover
                if cleanupFirst {
                    working.repairEjectEvidence = true
                    working.everHealthyMounted = true
                    let cleaned = snapshot.hostReachable
                        && snapshot.observedPath.map { effects.cleanup($0) } == true
                    guard cleaned else {
                        // 死卷清理未成功（或主机已不可达）：保留证据，转入待恢复。
                        working.state = .pendingRecovery
                        result.failed.append(snapshot.identity)
                        result.state.attempts[snapshot.identity] = [RecoveryAttempt(timestamp: working.updatedAt,
                            outcome: snapshot.hostReachable ? .shareRejected : .hostUnreachable, sequence: 0)]
                        action = .pendingUnreachable // 执行结果覆盖（清理失败），非第二套映射
                        break
                    }
                    result.state.cleanupLedger[snapshot.identity] = working.updatedAt
                }
                working.state = .recovering
                var attempts: [RecoveryAttempt] = []
                let mounted = EvaluationRetryRunner(policy: request.configuration.retryPolicy ?? RetryPolicy()).run {
                    guard effects.budgetRemaining() > 0 else { return false }
                    result.attempted += 1
                    let attempt = effects.mount(snapshot.identity)
                    attempts.append(RecoveryAttempt(timestamp: request.now().timeIntervalSince1970,
                        outcome: attempt.succeeded ? .mounted : attempt.failure, sequence: attempts.count + 1))
                    return attempt.succeeded
                }
                working.attemptCount = attempts.count
                result.state.attempts[snapshot.identity] = attempts
                if mounted {
                    working.state = .attached
                    working.repairEjectEvidence = false
                    working.everHealthyMounted = true
                    working.attemptCount = 0
                    working.notificationCount = 0
                    working.suppressionBoundary = nil
                    result.state.cleanupLedger.removeValue(forKey: snapshot.identity)
                    result.recovered.append(snapshot.identity)
                } else {
                    working.state = .pendingRecovery
                    result.failed.append(snapshot.identity)
                }
                action = .planned(for: judgment.decision)

            case .sessionSuppressed:
                // 会话抑制：本可达会话零重挂（FR-002③/FR-010）。
                working.state = .suppressed
                working.suppressionBoundary = boundary
                if signal == .unknownConservative {
                    working.everHealthyMounted = true // 保守：不得被后续误判为「从未挂载」
                }
                result.suppressed.append(snapshot.identity)
                result.state.attempts[snapshot.identity] = [RecoveryAttempt(timestamp: working.updatedAt,
                    outcome: .suppressedSkipped, sequence: 0)]
                action = .planned(for: judgment.decision)

            case .pendingUnreachable:
                // 主机不可达（在表死卷或缺失卷）：本轮零挂载，保留待恢复状态。
                working.state = .pendingRecovery
                if snapshot.presentInMountTable {
                    working.everHealthyMounted = true
                    working.repairEjectEvidence = true
                }
                result.failed.append(snapshot.identity)
                result.state.attempts[snapshot.identity] = [RecoveryAttempt(timestamp: working.updatedAt,
                    outcome: .hostUnreachable, sequence: 0)]
                action = .planned(for: judgment.decision)

            case .deferred:
                // 共享判定判定重试间隔未到：零挂载、不消耗预算与通知额度，也不写账本。
                result.plan.append(RecoveryVolumePlan(identity: snapshot.identity,
                    mountPoint: snapshot.mountPoint, action: .planned(for: judgment.decision)))
                continue
            }

            if result.failed.contains(snapshot.identity),
               RecoveryNotificationPolicy.consume(&working) {
                result.notificationIdentities.append(snapshot.identity)
            }
            result.state.volumes[snapshot.identity] = working
            result.plan.append(RecoveryVolumePlan(identity: snapshot.identity,
                mountPoint: snapshot.mountPoint, action: action))
        }

        // 不同顺位可共用挂载点；新主机已成功接管时，旧主机的离线记录
        // 仍须保留，但不能把已恢复的同一路径继续报告为失败。
        // 剔除算法唯一实现在 `RecoverySupersededPolicy`。
        let supersededKeys = RecoverySupersededPolicy.supersededIdentities(
            recovered: Set(result.recovered),
            volumes: allVolumes.map { (identity: $0.identity, mountPoint: $0.mountPoint) })
        result.failed.removeAll { supersededKeys.contains($0) }
        result.suppressed.removeAll { supersededKeys.contains($0) }
        result.notificationIdentities.removeAll { supersededKeys.contains($0) }
        if request.manualRecovery {
            for key in supersededKeys {
                guard var peerRecord = result.state.volumes[key] else { continue }
                peerRecord.state = .pendingRecovery
                peerRecord.suppressionBoundary = nil
                peerRecord.notificationCount = 0
                result.state.volumes[key] = peerRecord
            }
        }
        return result
    }
}
