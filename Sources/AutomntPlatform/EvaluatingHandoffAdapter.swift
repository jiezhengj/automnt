import Foundation
import AutomntCore

/// Adds the real app evaluation path to a service adapter. The supplied control
/// adapter remains responsible for bounded registration and process convergence.
public struct EvaluatingHandoffAdapter: HandoffServiceAdapter {
    private let controls: any HandoffServiceAdapter
    private let applicationURL: URL
    private let directory: AuthorizedDirectory

    public init(controls: any HandoffServiceAdapter, applicationURL: URL, directory: AuthorizedDirectory) {
        self.controls = controls
        self.applicationURL = applicationURL
        self.directory = directory
    }

    public func stopAndVerify(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus {
        try await controls.stopAndVerify(owner: owner, deadline: deadline)
    }
    public func register(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus {
        try await controls.register(owner: owner, deadline: deadline)
    }
    public func status(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus {
        try await controls.status(owner: owner, deadline: deadline)
    }
    public func requestEvaluation(state: BackendState, deadline: ContinuousClock.Instant) async throws {
        guard state.phase == .active else { throw AutomntIssue.incompatibleOwner }
        if state.owner == .cli {
            try await controls.requestEvaluation(state: state, deadline: deadline)
            return
        }
        guard state.owner == .app else { throw AutomntIssue.incompatibleOwner }
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw AutomntIssue.timeout }
        // Run synchronous worker I/O away from the GUI actor. Keep directory
        // authorization alive until all child operations have returned.
        let task = Task.detached { [applicationURL, directory] in
            guard let bundle = Bundle(url: applicationURL), bundle.bundleIdentifier == "org.automnt.automnt" else {
                throw AutomntIssue.authorizationRequired
            }
            let summary = try await BackgroundEvaluationTrigger.run(applicationBundle: bundle,
                directory: directory, expectedState: state, deadline: deadline)
            try Task.checkCancellation()
            try BackgroundObservationCommit.commit(summary, state: state, directory: directory.url)
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
