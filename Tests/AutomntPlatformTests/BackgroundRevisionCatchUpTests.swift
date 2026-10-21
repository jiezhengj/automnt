import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

/// Regression: the app saves a configuration while its background service stays active.
/// Before the fix the trigger compared the backend state's old revision with the new
/// configuration and threw `.configurationConflict`, so "check now" / the helper failed
/// even though nothing external had changed. After adoption the round must run.
struct BackgroundRevisionCatchUpTests {
    @Test func adoptedRevisionLetsTheRoundRunAfterAnAppSave() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let first = try repository.create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: first.revision)
        let journal = try store.begin(desiredOwner: .app, expectedGeneration: 0, revision: first.revision)
        _ = try store.advance(id: journal.id, to: .activating, verifiedStatus: .stopped)
        let active = try store.advance(id: journal.id, to: .active, verifiedStatus: .enabled)

        var configuration = first.configuration
        configuration.updateChannel = configuration.updateChannel == "off" ? "stable" : "off"
        let saved = try repository.save(configuration, baseRevision: first.revision)

        // Without the catch-up the trigger must refuse: this pins the old defect.
        do {
            _ = try await BackgroundEvaluationTrigger.run(directory: directory, expectedState: active,
                deadline: ContinuousClock.now.advanced(by: .seconds(3)), serviceStatus: { _ in .enabled },
                evaluate: { _ in BackgroundEvaluationSummary() })
            Issue.record("A stale backend revision must not evaluate")
        } catch { #expect(error as? AutomntIssue == .configurationConflict) }

        let adopted = try store.adoptConfigurationRevision(expected: first.revision, new: saved.revision)
        var evaluated = false
        _ = try await BackgroundEvaluationTrigger.run(directory: directory, expectedState: adopted,
            deadline: ContinuousClock.now.advanced(by: .seconds(3)), serviceStatus: { _ in .enabled },
            evaluate: { _ in evaluated = true; return BackgroundEvaluationSummary() })
        #expect(evaluated)
    }
}
