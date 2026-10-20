import Foundation

/// 逐卷观测事实（判定输入）。只承载事实，不承载结论。
public struct RecoveryVolumeFacts: Equatable, Sendable {
    public let identity: String
    public let mountPoint: String
    public let presentInMountTable: Bool
    public let hostReachable: Bool
    public let health: VolumeHealthEvidence

    public init(identity: String, mountPoint: String, presentInMountTable: Bool,
                hostReachable: Bool, health: VolumeHealthEvidence) {
        self.identity = identity
        self.mountPoint = mountPoint
        self.presentInMountTable = presentInMountTable
        self.hostReachable = hostReachable
        self.health = health
    }
}

/// 逐卷判定的上下文（配置、账本、会话边界与调用方许可）。
public struct RecoveryVolumeContext: Sendable {
    public let configuration: AutomntConfig
    public let state: MountRecoveryStateFile
    public let stateReadable: Bool
    /// 当前会话边界；`nil` 表示尚未建立可读边界（此时不得套用同路径对端抑制，
    /// 与改动前 `BaselineMountDecision`「仅当 sessionBoundary 存在才检查对端」一致）。
    public let boundary: String?
    public let peers: [RecoveryPeer]
    public let manualRecovery: Bool
    /// 是否允许在本轮发起挂载（helper 基线复核；planner 已由整轮开关门控制）。
    /// 等价于改动前的 `allowRecovery && isAutoMountRecoveryEnabled`。
    public let permitsMount: Bool
    /// 调用方是否请求恢复尝试（改动前的 `allowRecovery` 原始值）。
    /// 改动前「重试间隔」门只要求该值为真，不要求恢复开关为真。
    public let allowsRecoveryAttempts: Bool
    /// 是否存在配置（改动前「同会话尝试上限」门要求配置存在，否则跳过）。
    public let configurationProvided: Bool
    /// 是否套用「同会话尝试上限」门（helper/worker 的挂载前复核）。
    public let appliesAttemptLimit: Bool
    /// 是否套用「跨唤醒最小重试间隔」门（helper/worker 的挂载前复核）。
    /// 与 `appliesAttemptLimit` 不同，改动前该门**同时要求** `allowRecovery`（`permitsMount`）为真。
    public let appliesRetryInterval: Bool
    public let now: Date

    public init(configuration: AutomntConfig, state: MountRecoveryStateFile, stateReadable: Bool,
                boundary: String?, peers: [RecoveryPeer], manualRecovery: Bool,
                permitsMount: Bool, allowsRecoveryAttempts: Bool? = nil,
                configurationProvided: Bool = true,
                appliesAttemptLimit: Bool = false,
                appliesRetryInterval: Bool = false, now: Date = Date()) {
        self.configuration = configuration
        self.state = state
        self.stateReadable = stateReadable
        self.boundary = boundary
        self.peers = peers
        self.manualRecovery = manualRecovery
        self.permitsMount = permitsMount
        self.allowsRecoveryAttempts = allowsRecoveryAttempts ?? permitsMount
        self.configurationProvided = configurationProvided
        self.appliesAttemptLimit = appliesAttemptLimit
        self.appliesRetryInterval = appliesRetryInterval
        self.now = now
    }
}

/// 逐卷应执行的动作（调用方据此执行副作用）。
public enum RecoveryVolumeDecision: Equatable, Sendable {
    /// 已健康挂载：幂等跳过。
    case attachHealthy
    /// 在表但不健康：先清理再恢复。
    case cleanupThenRecover
    /// 缺失且具备恢复资格：纳入恢复。
    case recover
    /// 会话抑制：本可达会话内零重挂（用户弹出意图或保守跳过）。
    case sessionSuppressed
    /// 本轮不挂载：主机不可达。
    case pendingUnreachable
    /// 重试间隔未到：不消耗尝试预算。
    case deferred
}

/// 计划动作的**唯一**映射来源（V8 缺陷 G1）。
///
/// planner 的逐卷动作必须由此派生，不得再从 `signal` 二次推导；
/// `RecoveryVolumeAction.planned(for:)` 是「共享 decision → 计划动作」的单一函数，
/// 由 `RecoveryRoundPlanner` 直接调用，并有逐项绑定断言保护。
public extension RecoveryVolumeAction {
    static func planned(for decision: RecoveryVolumeDecision) -> RecoveryVolumeAction {
        switch decision {
        case .attachHealthy: return .attachHealthy
        case .cleanupThenRecover: return .cleanupThenRecover
        case .recover: return .recover
        case .sessionSuppressed: return .suppress
        case .pendingUnreachable: return .pendingUnreachable
        case .deferred: return .deferred
        }
    }
}

/// 逐卷判定结果：底层信号 + 动作 + 是否经由预算门。
public struct RecoveryVolumeJudgment: Equatable, Sendable {
    public let signal: RecoverySignal
    public let decision: RecoveryVolumeDecision
    public init(signal: RecoverySignal, decision: RecoveryVolumeDecision) {
        self.signal = signal
        self.decision = decision
    }
}

/// **逐卷判定唯一实现**：CLI 的 `RecoveryRoundPlanner` 与 helper 的
/// `BaselineMountDecision`（worker 子进程复核）都必须经此函数，不得各自实现分支。
public enum RecoveryVolumeDecisionPolicy {

    /// 配置启用卷构造的同路径对端集合（备用身份只传播抑制，不传播健康/修复许可）。
    public static func peers(configuration: AutomntConfig,
                             presentIdentities: Set<String> = []) -> [RecoveryPeer] {
        configuration.hosts.filter(\.enabled).flatMap { host in
            host.shares.filter(\.enabled).compactMap { share -> RecoveryPeer? in
                guard let key = smbResourceIdentity(share.smbURL) else { return nil }
                return RecoveryPeer(identity: key, mountPoint: share.mountPoint,
                    present: presentIdentities.contains(key), hostReachable: false)
            }
        }
    }

    /// 同一会话内的尝试上限（与 `RecoveryAttemptCommit.reserve` 同一夹限）。
    public static func attemptLimit(_ configuration: AutomntConfig) -> Int {
        min(max(configuration.retryPolicy?.maxAttempts ?? 3, 1), 10)
    }

    /// 单一逐卷判定。
    ///
    /// 优先级（与改动前的 CLI 行为逐条一致，且「抑制优先」与 helper 一致）：
    /// 0. 显式手动恢复（`manualRecovery` + 缺失）→ 强制「从未挂载」。这与改动前 CLI 的
    ///    `if manualRecovery, !present { signal = .neverMounted }` 同序，保证「立即重新挂载」
    ///    既能在状态损坏时兜底，也能手动词恢复被会话抑制的卷（含同路径备用）；
    /// 1. 状态不可读 → 保守抑制（FR-010），绝不误判为「从未挂载」；
    /// 2. 缺失卷且账本为 `.suppressed` → 会话抑制。`UserEjectCommit` 在用户弹出后
    ///    **只写** `state = .suppressed` + `suppressionBoundary`，不写 `everHealthyMounted`，
    ///    因此该记录是本可达会话弹出意图的直接证据，必须**早于** `everHealthyMounted`
    ///    与清理账/修复证据判定，否则「首次即被弹出」的卷会落 `.neverMounted` 被重挂（FR-002③）；
    /// 3. 其余按 `judgeRecoverySignal`（清理账 / 修复证据 / 曾健康挂载 / 从未挂载）；
    /// 4. 同路径备用身份抑制；
    /// 5. 在表且可达时以健康证据覆盖（未知健康不证明健康、不授予清理许可）；
    /// 6. 仅在缺失分支套用调用方的尝试上限/重试间隔门与挂载许可。
    public static func judge(_ facts: RecoveryVolumeFacts,
                             context: RecoveryVolumeContext) -> RecoveryVolumeJudgment {
        // 0. 显式手动恢复是最终裁决，优先于状态损坏与一切抑制（改动前 CLI 同序）。
        if context.manualRecovery, !facts.presentInMountTable {
            return RecoveryVolumeJudgment(signal: .neverMounted,
                decision: decide(facts, signal: .neverMounted,
                    record: context.state.volumes[facts.identity], context: context))
        }
        guard context.stateReadable else {
            return RecoveryVolumeJudgment(signal: .unknownConservative, decision: .sessionSuppressed)
        }
        let record = context.state.volumes[facts.identity]

        // 2. 会话抑制优先：缺失卷的用户弹出记录（不依赖 everHealthyMounted）。
        if !facts.presentInMountTable, record?.state == .suppressed {
            return RecoveryVolumeJudgment(signal: .healthyEject, decision: .sessionSuppressed)
        }

        var signal = judgeRecoverySignal(volumeKey: facts.identity,
            presentInMountTable: facts.presentInMountTable, hostReachable: facts.hostReachable,
            record: record, cleanupLedger: context.state.cleanupLedger, stateReadable: true)

        // 4. 同路径备用身份只传播抑制（仅在**已建立**会话边界时），并且**短路返回**。
        //    有效边界标识形如 "<network>|<loginEpoch>"（`RecoverySessionIdentity.combined`），
        //    因此 nil 与空串都表示「尚未建立边界」，二者必须给出同一结论：跳过对端检查。
        //    旧实现只用 `let boundary`，空串会误通过 `let` 而启用对端抑制（V8 缺陷 G2）。
        //    短路语义与改动前 `BaselineMountDecision` 一致：对端抑制在尝试上限/重试间隔
        //    门**之前**即返回 suppressed（否则 helper 会把对端抑制错报为 deferred）。
        if !facts.presentInMountTable, let boundary = context.boundary, !boundary.isEmpty,
           RecoverySuppressionPolicy.protectedByPeer(identity: facts.identity,
               mountPoint: facts.mountPoint, boundary: boundary,
               peers: context.peers, state: .loaded(context.state)) {
            return RecoveryVolumeJudgment(signal: .healthyEject, decision: .sessionSuppressed)
        }
        // 5. 健康证据覆盖。
        if facts.presentInMountTable, facts.hostReachable {
            signal = RecoveryHealthPolicy.signal(base: signal, present: true,
                hostReachable: true, health: facts.health)
        }

        return RecoveryVolumeJudgment(signal: signal,
            decision: decide(facts, signal: signal, record: record, context: context))
    }

    private static func decide(_ facts: RecoveryVolumeFacts, signal: RecoverySignal,
                               record: MountRecoveryVolumeRecord?,
                               context: RecoveryVolumeContext) -> RecoveryVolumeDecision {
        if facts.presentInMountTable {
            switch signal {
            case .attachedHealthy: return .attachHealthy
            case .deadButPresent: return facts.hostReachable ? .cleanupThenRecover : .pendingUnreachable
            default: return .sessionSuppressed
            }
        }
        // 顺序与改动前逐条一致：尝试上限 → 重试间隔 → 抑制回落 → 可达性 → 挂载许可。
        // 「重试间隔→deferred」必须先于抑制回落，否则已抑制信号会吞掉 legacy 的 deferred。
        if context.appliesAttemptLimit, context.configurationProvided, signal != .neverMounted,
           (record?.attemptCount ?? 0) >= attemptLimit(context.configuration) {
            return .sessionSuppressed
        }
        if context.appliesRetryInterval, context.allowsRecoveryAttempts, signal != .neverMounted,
           !RecoveryRetryInterval.permits(record: record, policy: context.configuration.retryPolicy,
                                          now: context.now) {
            return .deferred
        }
        guard !signal.isSuppressed else { return .sessionSuppressed }
        guard facts.hostReachable else { return .pendingUnreachable }
        return MissingVolumeRecoveryPolicy.mayMount(signal: signal, enabled: context.permitsMount)
            ? .recover : .sessionSuppressed
    }
}

/// superseded 路径剔除的唯一实现：新主机已成功恢复同一挂载点时，
/// 其他身份的离线记录仍须保留，但不得继续报告为失败/抑制/通知。
public enum RecoverySupersededPolicy {
    public static func supersededIdentities(recovered: Set<String>,
                                            volumes: [(identity: String, mountPoint: String)]) -> Set<String> {
        let restored = Set(volumes.filter { recovered.contains($0.identity) }.map(\.mountPoint))
        return Set(volumes.filter { restored.contains($0.mountPoint) && !recovered.contains($0.identity) }
            .map(\.identity))
    }
}
