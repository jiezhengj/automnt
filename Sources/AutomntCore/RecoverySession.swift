import Foundation

/// Platform collectors provide identities; unavailable collection preserves the prior network.
public struct RecoverySessionIdentity: Equatable, Sendable {
    public let network: String
    public let loginEpoch: String
    public var combined: String { "\(network)|\(loginEpoch)" }
    public init(network: String?, loginEpoch: String, previous: String?) {
        self.network = network ?? previous?.split(separator: "|", omittingEmptySubsequences: false).dropLast().joined(separator: "|") ?? "<unreadable>"
        self.loginEpoch = loginEpoch
    }
}

public enum RecoverySessionPolicy {
    /// The first readable network snapshot establishes a baseline, rather than cancelling an eject.
    public static func advance(_ state: inout MountRecoveryStateFile,
                               to identity: RecoverySessionIdentity, mountedKeys: Set<String>) {
        let boundary = identity.combined
        let previous = state.sessionBoundary?.split(separator: "|", omittingEmptySubsequences: false)
        let establishing = state.sessionBoundary == nil ||
            (previous?.dropLast().joined(separator: "|") == "<unreadable>" &&
             previous?.last.map(String.init) == identity.loginEpoch)
        guard state.sessionBoundary != boundary else { return }
        // 同一次启动、同一网络下，登录纪元只可能因「能否读取 console 记录」而写法不同
        // （沙盒读不到 utmpx，CLI 读得到）。这不是新会话，不能因此清除本会话的弹出抑制，
        // 也不改写边界：抑制记录按边界值绑定，改写会让对端抑制失配。
        if !establishing, let previousBoundary = state.sessionBoundary {
            let parts = previousBoundary.split(separator: "|", omittingEmptySubsequences: false)
            let previousNetwork = parts.dropLast().joined(separator: "|")
            if previousNetwork == identity.network, let previousEpoch = parts.last {
                if bootComponent(String(previousEpoch)) == bootComponent(identity.loginEpoch) { return }
            }
        }
        if establishing {
            for (key, var record) in state.volumes {
                if record.state == .suppressed {
                    record.suppressionBoundary = boundary
                } else if record.state == .attached, !mountedKeys.contains(key) {
                    // `.attached` only ever means this project mounted the volume; with no
                    // eject record and nothing in the mount table it is stale state from an
                    // earlier session (the common upgrade/restart case). Recover it instead
                    // of reporting it as a healthy eject that suppresses automatic mounting.
                    record.state = .pendingRecovery
                    record.lastAttemptAt = nil
                    record.attemptOperationID = nil
                    record.attemptCount = 0
                    record.notificationCount = 0
                }
                state.volumes[key] = record
            }
        } else {
            for (key, var record) in state.volumes {
                if record.state == .suppressed || (record.everHealthyMounted && !mountedKeys.contains(key)) {
                    record.state = .pendingRecovery
                    record.suppressionBoundary = nil
                }
                record.lastAttemptAt = nil
                record.attemptOperationID = nil
                record.attemptCount = 0
                record.notificationCount = 0
                state.volumes[key] = record
            }
        }
        state.sessionBoundary = boundary
    }

    /// 登录纪元形如 `<boot>-<consoleStart|console-unreadable>`；重启才会改变前段。
    private static func bootComponent(_ epoch: String) -> Substring {
        epoch.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
    }
}

public struct RecoveryPeer: Sendable {
    public let identity: String
    public let mountPoint: String
    public let present: Bool
    public let hostReachable: Bool
    public init(identity: String, mountPoint: String, present: Bool, hostReachable: Bool) {
        self.identity = identity; self.mountPoint = mountPoint
        self.present = present; self.hostReachable = hostReachable
    }
}

public enum RecoverySuppressionPolicy {
    /// Only eject protection crosses a shared path; never transfer health or cleanup permission.
    public static func protectedByPeer(identity: String, mountPoint: String, boundary: String,
                                       peers: [RecoveryPeer], state: MountRecoveryStoreLoad) -> Bool {
        let file = state.file
        return peers.contains { peer in
            guard peer.identity != identity, peer.mountPoint == mountPoint, !peer.present,
                  let record = file.volumes[peer.identity] else { return false }
            if record.state == .suppressed && record.suppressionBoundary == boundary { return true }
            return judgeRecoverySignal(volumeKey: peer.identity, presentInMountTable: false,
                hostReachable: peer.hostReachable, record: record, cleanupLedger: file.cleanupLedger,
                stateReadable: state.isReadable) == .healthyEject
        }
    }
}

public enum VolumeHealthEvidence: Equatable, Sendable { case healthy, failed, unavailable }

public enum RecoveryHealthPolicy {
    /// Presence and reachability do not establish successful file access.
    public static func observation(identity: String, actualPath: String, hostReachable: Bool,
                                   health: VolumeHealthEvidence, observedAt: Date) -> VolumeObservation {
        guard hostReachable else {
            return VolumeObservation(identity: identity, status: .offline, actualPath: actualPath,
                                     observedAt: observedAt, issue: .offline)
        }
        switch health {
        case .healthy:
            return VolumeObservation(identity: identity, status: .healthy, actualPath: actualPath, observedAt: observedAt)
        case .failed:
            return VolumeObservation(identity: identity, status: .failed, actualPath: actualPath,
                                     observedAt: observedAt, issue: .shareRejected)
        case .unavailable:
            return VolumeObservation(identity: identity, status: .evaluating, actualPath: actualPath,
                                     observedAt: observedAt, issue: .signalUnavailable)
        }
    }

    public static func signal(base: RecoverySignal, present: Bool, hostReachable: Bool,
                              health: VolumeHealthEvidence) -> RecoverySignal {
        // Preserve damaged-state protection; unknown access never grants cleanup permission.
        guard base != .unknownConservative, present, hostReachable else { return base }
        if case .failed = health { return .deadButPresent }
        return base
    }

}
