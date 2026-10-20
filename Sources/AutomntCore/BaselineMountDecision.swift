import Foundation

/// A missing SMB identity alone cannot establish that a configured path is free.
public enum MountPathState: Equatable, Sendable {
    case absent
    case smb(identity: String)
    case occupied
    case unavailable
}

public enum BaselineMountDecision: Equatable, Sendable {
    case mount, inspectExisting, suppressed, deferred
    case blocked(AutomntIssue)

    /// 挂载点状态门（不涉及恢复规则）：不可用/占用/其他身份一律阻断。
    public static func block(path: MountPathState, identity: String) -> BaselineMountDecision? {
        switch path {
        case .unavailable: return .blocked(.signalUnavailable)
        case .occupied: return .blocked(.pathConflict)
        case .smb(let actual): return actual == identity ? .inspectExisting : .blocked(.pathConflict)
        case .absent: return nil
        }
    }

    /// **委托**共享逐卷判定（`RecoveryVolumeDecisionPolicy`），本函数不再自行实现恢复分支。
    /// helper (`BackgroundEvaluator`) 与 worker 子进程复核共用同一规则。
    public static func decide(identity: String, path: MountPathState,
                              recovery: MountRecoveryStoreLoad,
                              configuration: AutomntConfig? = nil, mountPoint: String? = nil,
                              allowRecovery: Bool = false, now: Date = Date()) -> BaselineMountDecision {
        let configurationGiven = configuration != nil
        if let blocked = block(path: path, identity: identity) { return blocked }
        let state = recovery.file
        let configuration = configuration ?? AutomntConfig()
        // 与改动前一致：未提供配置时不得授予挂载许可（`configuration?.isAutoMountRecoveryEnabled ?? false`）。
        let permitsMount = allowRecovery && (configuration.isAutoMountRecoveryEnabled && configurationGiven)
        return translate(RecoveryVolumeDecisionPolicy.judge(
            RecoveryVolumeFacts(identity: identity, mountPoint: mountPoint ?? "",
                presentInMountTable: false, hostReachable: true, health: .unavailable),
            context: RecoveryVolumeContext(configuration: configuration, state: state,
                stateReadable: recovery.isReadable, boundary: state.sessionBoundary,
                peers: RecoveryVolumeDecisionPolicy.peers(configuration: configuration),
                manualRecovery: false,
                permitsMount: permitsMount, allowsRecoveryAttempts: allowRecovery,
                configurationProvided: configurationGiven,
                appliesAttemptLimit: true, appliesRetryInterval: true, now: now)).decision)
    }

    private static func translate(_ decision: RecoveryVolumeDecision) -> BaselineMountDecision {
        switch decision {
        case .attachHealthy: return .inspectExisting
        case .recover: return .mount
        case .sessionSuppressed: return .suppressed
        case .deferred: return .deferred
        // 缺失卷（本入口恒为缺失）不会产生在表动作；保守落抑制。
        case .cleanupThenRecover, .pendingUnreachable: return .suppressed
        }
    }
}
