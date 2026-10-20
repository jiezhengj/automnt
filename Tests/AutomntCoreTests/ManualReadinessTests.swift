import Foundation
import Testing
@testable import AutomntCore

struct ManualReadinessTests {
    @Test func completedHandoffJournalAllowsActionsAndStaleApprovalRejects() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: snapshot.revision)
        let journal = try store.begin(desiredOwner: .app, expectedGeneration: 0, revision: snapshot.revision)
        _ = try store.advance(id: journal.id, to: .activating, verifiedStatus: .stopped)
        let approval = try store.advance(id: journal.id, to: .awaitingApproval, verifiedStatus: .requiresApproval)
        #expect(ManualActionReadiness.classify(approval, revision: snapshot.revision) == .needsApproval)
        #expect(ManualActionReadiness.classify(approval, revision: ConfigRevision(digest: UUID().uuidString)) == .needsRepair)
        let active = try store.advance(id: journal.id, to: .active, verifiedStatus: .enabled)
        #expect(active.transitionID != nil)
        #expect(ManualActionReadiness.classify(active, revision: snapshot.revision, requiredServices: [.enabled]) == .eligible)
        #expect(ManualActionReadiness.classify(active, revision: snapshot.revision, requiredServices: [.stopped]) == .needsRepair)
        #expect(ManualActionReadiness.classify(active, revision: snapshot.revision, requiredServices: [.requiresApproval]) == .needsRepair)
        #expect(ManualActionReadiness.classify(approval, revision: snapshot.revision, requiredServices: [.enabled]) == .needsApproval)
        let stop = try store.begin(desiredOwner: .none, expectedGeneration: active.generation, revision: snapshot.revision)
        let stopped = try store.advance(id: stop.id, to: .stopped, verifiedStatus: .stopped)
        #expect(ManualActionReadiness.classify(stopped, revision: snapshot.revision) == .needsSetup)
    }

    @Test func requiredServiceStatusesGateAppEligibility() {
        let revision = ConfigRevision(digest: UUID().uuidString)
        var state = BackendState(owner: .app, phase: .active, generation: 1, revision: revision)
        for (statuses, expected): ([BackendState.ServiceStatus], ManualActionReadiness) in [
            ([], .needsRepair), ([.enabled], .eligible), ([.enabled, .enabled], .eligible),
            ([.enabled, .stopped], .needsRepair), ([.enabled, .requiresApproval], .needsRepair),
            ([.requiresApproval, .unavailable], .needsRepair)] {
            #expect(ManualActionReadiness.classify(state, revision: revision, requiredServices: statuses) == expected)
        }
        state.owner = .cli
        #expect(ManualActionReadiness.classify(state, revision: revision, requiredServices: [.enabled]) == .cliManaged)
    }

    @Test func readinessNeverClaimsRuntimeServiceLiveness() {
        let revision = ConfigRevision(digest: UUID().uuidString)
        var state = BackendState(owner: .app, phase: .active, generation: 1, revision: revision)
        #expect(ManualActionReadiness.classify(state, revision: revision) == .eligible)
        state.owner = .cli
        #expect(ManualActionReadiness.classify(state, revision: revision) == .cliManaged)
        state.owner = .none
        #expect(ManualActionReadiness.classify(state, revision: revision) == .needsSetup)
        state.owner = .app
        for (phase, expected): (BackendState.Phase, ManualActionReadiness) in [
            (.awaitingApproval, .needsRepair), (.activating, .transitioning),
            (.stopping, .transitioning), (.stopped, .needsSetup), (.failed, .needsRepair)] {
            state.phase = phase
            #expect(ManualActionReadiness.classify(state, revision: revision) == expected)
        }
        state.phase = .active
        #expect(ManualActionReadiness.classify(state, revision: ConfigRevision(digest: UUID().uuidString)) == .needsRepair)
        state.transitionID = UUID()
        #expect(ManualActionReadiness.classify(state, revision: revision) == .needsRepair)
        state.transitionID = nil
        state.schemaVersion = 2
        #expect(ManualActionReadiness.classify(state, revision: revision) == .needsRepair)
    }
}
