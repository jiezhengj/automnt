import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

struct BackgroundTriggerTests {
    @Test func ownershipChangeDuringSystemQueryPreventsEvaluation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: snapshot.revision)
        let journal = try store.begin(desiredOwner: .app, expectedGeneration: 0, revision: snapshot.revision)
        _ = try store.advance(id: journal.id, to: .activating, verifiedStatus: .stopped)
        let active = try store.advance(id: journal.id, to: .active, verifiedStatus: .enabled)
        var evaluated = false
        do {
            _ = try await BackgroundEvaluationTrigger.run(directory: directory, expectedState: active,
                deadline: ContinuousClock.now.advanced(by: .seconds(3)), serviceStatus: { _ in
                    _ = try store.begin(desiredOwner: .none, expectedGeneration: active.generation, revision: snapshot.revision)
                    return .enabled
                }, evaluate: { _ in evaluated = true; return BackgroundEvaluationSummary() })
            Issue.record("Changed ownership must invalidate the trigger")
        } catch { #expect(error as? AutomntIssue == .configurationConflict) }
        #expect(!evaluated)
    }

    @Test func staleActivationAndExpiredDeadlineNeverQueryServicesOrEvaluate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        let stopped = try store.initialize(revision: snapshot.revision)
        var calls = 0
        do {
            _ = try await BackgroundEvaluationTrigger.run(directory: directory, expectedState: stopped,
                deadline: ContinuousClock.now.advanced(by: .seconds(2)), serviceStatus: { _ in calls += 1; return .enabled },
                evaluate: { _ in calls += 1; return BackgroundEvaluationSummary() })
            Issue.record("Stopped ownership must reject evaluation")
        } catch { #expect(error as? AutomntIssue == .incompatibleOwner) }
        #expect(calls == 0)
        do {
            _ = try await BackgroundEvaluationTrigger.run(directory: directory, expectedState: stopped,
                deadline: ContinuousClock.now, serviceStatus: { _ in calls += 1; return .enabled },
                evaluate: { _ in calls += 1; return BackgroundEvaluationSummary() })
            Issue.record("Expired trigger must reject evaluation")
        } catch { #expect(error as? AutomntIssue == .timeout) }
        #expect(calls == 0)
    }
}
