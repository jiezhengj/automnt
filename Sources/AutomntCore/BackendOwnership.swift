import Foundation

public struct BackendState: Codable, Equatable, Sendable {
    public enum Owner: String, Codable, Sendable { case cli, app, none }
    public enum Phase: String, Codable, Sendable {
        case active, stopping, awaitingApproval, activating, stopped, failed
    }
    public var schemaVersion: Int = 1
    public var owner: Owner
    public var phase: Phase
    public var generation: UInt64
    public var revision: ConfigRevision
    public var desiredOwner: Owner? = nil
    public var lastVerifiedServiceStatus: ServiceStatus? = nil
    public var transitionID: UUID? = nil

    public enum ServiceStatus: String, Codable, Sendable {
        case enabled, stopped, requiresApproval, unavailable
    }

    public init(owner: Owner, phase: Phase, generation: UInt64, revision: ConfigRevision) {
        self.owner = owner
        self.phase = phase
        self.generation = generation
        self.revision = revision
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case owner, phase, generation, revision
        case desiredOwner = "desired_owner"
        case lastVerifiedServiceStatus = "last_verified_service_status"
        case transitionID = "transition_id"
    }
}

/// Explicit GUI operations may use a verified stopped backend without enabling automation.
/// This policy does not waive revision, generation, worker-idle or legacy-store checks.
public enum ManualOperationOwnership {
    public static func permits(_ state: BackendState, automationEnabled: Bool) -> Bool {
        if state.owner == .app && state.phase == .active {
            return (state.desiredOwner == nil || state.desiredOwner == .app) &&
                (state.transitionID == nil ||
                 (state.desiredOwner == .app && state.lastVerifiedServiceStatus == .enabled))
        }
        return !automationEnabled && state.owner == .none && state.phase == .stopped &&
            (state.transitionID == nil || state.desiredOwner == BackendState.Owner.none) &&
            (state.desiredOwner == nil || state.desiredOwner == BackendState.Owner.none) &&
            state.lastVerifiedServiceStatus == .stopped
    }
}

public struct EvaluationPermit {
    private let lock: StableFileLock
    public let snapshot: ConfigSnapshot
    public let generation: UInt64

    /// The configuration lock is released by read() before waiting for the operation lock.
    /// Re-read both durable facts after taking that lock; stale work is rejected.
    public init(directory: URL, repository: any ConfigRepository, expected: ConfigSnapshot,
                owner: BackendState.Owner, generation: UInt64,
                explicitManualAppOperation: Bool = false,
                readBackend: () throws -> BackendState) throws {
        lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
        let current = try repository.read()
        let state = try readBackend()
        guard current.revision == expected.revision, state.generation == generation,
              state.revision == current.revision else { throw AutomntIssue.configurationConflict }
        if explicitManualAppOperation {
            guard owner == .app,
                  ManualOperationOwnership.permits(state, automationEnabled: current.configuration.isAutomationEnabled)
            else { throw AutomntIssue.incompatibleOwner }
        } else {
            guard state.owner == owner, state.phase == .active else { throw AutomntIssue.incompatibleOwner }
        }
        self.snapshot = current
        self.generation = generation
    }

    /// Keep this value alive through the complete bounded operation.
    public func perform<T>(_ operation: (ConfigSnapshot) throws -> T) rethrows -> T {
        try withExtendedLifetime(lock) { try operation(snapshot) }
    }
}
