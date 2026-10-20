import Foundation

/// Structured errors shared by foreground and bounded background operations.
public enum AutomntIssue: String, Codable, Sendable, Error {
    case unconfigured, authorizationRequired, backgroundApprovalRequired
    case offline, credentialFailure, shareRejected, pathConflict, volumeBusy, timeout
    case configurationConflict, incompatibleOwner, serviceTransitionFailed, signalUnavailable
    case invalidConfiguration
}

public struct ConfigRevision: Codable, Equatable, Sendable {
    public let digest: String
    public init(digest: String) { self.digest = digest }
}

public struct ConfigSnapshot: Sendable {
    public let configuration: AutomntConfig
    public let revision: ConfigRevision
    public init(configuration: AutomntConfig, revision: ConfigRevision) {
        self.configuration = configuration
        self.revision = revision
    }
}

public enum VolumeStatus: String, Codable, Sendable {
    case unconfigured, needsAuthorization, evaluating, healthy, offline, failed, suppressed, stopped
}

public struct VolumeObservation: Codable, Equatable, Sendable {
    public let identity: String
    public let status: VolumeStatus
    public let actualPath: String?
    public let observedAt: Date
    public let issue: AutomntIssue?
    public init(identity: String, status: VolumeStatus, actualPath: String?, observedAt: Date, issue: AutomntIssue? = nil) {
        self.identity = identity
        self.status = status
        self.actualPath = actualPath
        self.observedAt = observedAt
        self.issue = issue
    }
}

public enum PostMountResult: String, Codable, Sendable {
    case notRequested, markerCreated, markerAlreadyPresent, readOnly, permissionDenied, unavailable, timedOut
}

public struct MountResult: Sendable {
    public let observation: VolumeObservation
    public let postMount: PostMountResult
    public init(observation: VolumeObservation, postMount: PostMountResult) {
        self.observation = observation
        self.postMount = postMount
    }
}

public protocol ReachabilityProbe: Sendable {
    func isReachable(host: String, port: Int, timeoutMilliseconds: Int) async throws -> Bool
}

public protocol MountBackend: Sendable {
    /// Credentials remain in the adapter; no secret enters shared operation results.
    func mount(_ share: SMBShareConfig, on host: HostConfig, deadline: ContinuousClock.Instant) async throws -> MountResult
    func unmount(_ volume: VolumeObservation, deadline: ContinuousClock.Instant) async throws -> VolumeObservation
}

public protocol PostMountBackend: Sendable {
    /// A marker is evidence of a requested exclusion, not proof Spotlight stopped indexing.
    func preventIndexing(at actualPath: String, deadline: ContinuousClock.Instant) async -> PostMountResult
}

public enum NotificationDelivery: String, Codable, Sendable {
    case delivered, denied, suppressedForeground, unavailable, failed
}

public protocol UserNotifier: Sendable {
    /// The caller already consumed the round/session budget. Suppressed delivery never catches up.
    func deliver(_ notification: FailureNotification) async -> NotificationDelivery
}

public protocol ConfigRepository: Sendable {
    func read() throws -> ConfigSnapshot
    @discardableResult func save(_ configuration: AutomntConfig, baseRevision: ConfigRevision) throws -> ConfigSnapshot
}
