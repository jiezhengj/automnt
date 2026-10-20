import Foundation
import AutomntCore

/// Fixed SMAppService registrations only. CLI control must be provided separately
/// once its process-convergence contract is implemented; never execute an external CLI.
@MainActor
public final class AppServiceHandoffAdapter: HandoffServiceAdapter {
    private let directory: URL
    private let revision: ConfigRevision
    public init(authorizedDirectory: URL, revision: ConfigRevision) {
        directory = authorizedDirectory
        self.revision = revision
    }
    public func stopAndVerify(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus {
        try check(deadline)
        guard owner != .cli else { throw AutomntIssue.incompatibleOwner }
        for mode in [ServiceController.Mode.baseline, .recovery] {
            _ = try await ServiceController(mode: mode).unregister(deadline: deadline)
            try check(deadline)
        }
        try ServiceController.verifyHelperStopped(authorizedDirectory: directory)
        let lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
        try withExtendedLifetime(lock) {
            try WorkerOperationStore(authorizedDirectory: directory).verifyIdle()
        }
        return .stopped
    }
    public func register(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus {
        try check(deadline)
        guard owner == .app else { throw AutomntIssue.incompatibleOwner }
        let mode = try registrationMode()
        let result = try ServiceController(mode: mode).register()
        try check(deadline)
        return result
    }
    public func status(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus {
        try check(deadline)
        guard owner == .app else { throw AutomntIssue.incompatibleOwner }
        let snapshot = try FileConfigRepository(authorizedDirectory: directory).read()
        guard snapshot.revision == revision else { throw AutomntIssue.configurationConflict }
        return BackgroundServiceReadiness.classify(configuration: snapshot.configuration,
            baseline: ServiceController(mode: .baseline).status,
            recovery: ServiceController(mode: .recovery).status)
    }
    public func requestEvaluation(state: BackendState, deadline: ContinuousClock.Instant) async throws {
        // Compose with EvaluatingHandoffAdapter; no silent success without evaluation.
        throw AutomntIssue.signalUnavailable
    }
    /// Short local preflight only; system registration happens after releasing locks.
    func registrationMode() throws -> ServiceController.Mode {
        let lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
        return try withExtendedLifetime(lock) {
            let snapshot = try FileConfigRepository(authorizedDirectory: directory).read()
            let state = try BackendStateStore(authorizedDirectory: directory).read()
            guard snapshot.revision == revision, state.revision == revision else {
                throw AutomntIssue.configurationConflict
            }
            guard state.phase == .activating, state.desiredOwner == .app,
                  state.transitionID != nil, state.lastVerifiedServiceStatus == .stopped,
                  snapshot.configuration.isAutomationEnabled else {
                throw AutomntIssue.incompatibleOwner
            }
            try WorkerOperationStore(authorizedDirectory: directory).verifyIdle()
            return snapshot.configuration.autoMountRecovery ?? true ? .recovery : .baseline
        }
    }

    private func check(_ deadline: ContinuousClock.Instant) throws {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw AutomntIssue.timeout }
    }
}
