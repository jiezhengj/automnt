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
        if establishing {
            for (key, var record) in state.volumes where record.state == .suppressed {
                record.suppressionBoundary = boundary
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
