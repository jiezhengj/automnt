import Foundation
import AutomntCore

/// Shared bounded entry for launchd events and explicit post-activation evaluation.
/// No registration, configuration writes or permission UI are performed here.
public enum BackgroundEvaluationTrigger {
    public static func run(applicationBundle: Bundle, directory: AuthorizedDirectory,
                           expectedState: BackendState? = nil,
                           deadline: ContinuousClock.Instant) async throws -> BackgroundEvaluationSummary {
        try await run(directory: directory.url, expectedState: expectedState, deadline: deadline,
            serviceStatus: { configuration in
                await MainActor.run {
                    BackgroundServiceReadiness.classify(configuration: configuration,
                        baseline: ServiceController(mode: .baseline).status,
                        recovery: ServiceController(mode: .recovery).status)
                }
            }, evaluate: { revision in
                try await BackgroundEvaluator.evaluate(applicationBundle: applicationBundle,
                    directory: directory, deadline: deadline, expectedRevision: revision)
            })
    }

    static func run(directory: URL, expectedState: BackendState?, deadline: ContinuousClock.Instant,
                    isolation: isolated (any Actor)? = #isolation,
                    serviceStatus: (AutomntConfig) async throws -> BackendState.ServiceStatus,
                    evaluate: (ConfigRevision) async throws -> BackgroundEvaluationSummary) async throws -> BackgroundEvaluationSummary {
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let store = BackendStateStore(authorizedDirectory: directory)
        let initial = try repository.read()
        let expected = try expectedState ?? store.read()
        return try await BackgroundRetryScheduler.run(policy: initial.configuration.retryPolicy, deadline: deadline) {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw AutomntIssue.timeout }
            let current = try repository.read()
            guard current.revision == initial.revision, expected.revision == current.revision else {
                throw AutomntIssue.configurationConflict
            }
            guard try store.read() == expected else { throw AutomntIssue.configurationConflict }
            guard current.configuration.isAutomationEnabled else { return BackgroundEvaluationSummary() }
            // Reject stale ownership before contacting system services or probing hosts.
            do {
                let permit = try EvaluationPermit(directory: directory, repository: repository,
                    expected: current, owner: .app, generation: expected.generation, readBackend: store.read)
                permit.perform { _ in }
            }
            guard try await serviceStatus(current.configuration) == .enabled else {
                throw AutomntIssue.backgroundApprovalRequired
            }
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw AutomntIssue.timeout }
            guard try store.read() == expected else { throw AutomntIssue.configurationConflict }
            let fresh = try repository.read()
            do {
                let permit = try EvaluationPermit(directory: directory, repository: repository,
                    expected: current, owner: .app, generation: expected.generation, readBackend: store.read)
                try permit.perform { _ in
                    guard fresh.revision == current.revision else { throw AutomntIssue.configurationConflict }
                }
            }
            // Workers independently revalidate immediately before system operations.
            return try await evaluate(current.revision)
        }
    }
}
