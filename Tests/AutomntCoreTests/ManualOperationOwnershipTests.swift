import Foundation
import Testing
@testable import AutomntCore

struct ManualOperationOwnershipTests {
    @Test func stoppedBackendRequiresPositiveStopEvidenceAndDisabledAutomation() {
        var state = BackendState(owner: .none, phase: .stopped, generation: 0,
            revision: ConfigRevision(digest: "manual-policy"))
        #expect(!ManualOperationOwnership.permits(state, automationEnabled: false))
        state.lastVerifiedServiceStatus = .stopped
        #expect(ManualOperationOwnership.permits(state, automationEnabled: false))
        #expect(!ManualOperationOwnership.permits(state, automationEnabled: true))
        state.transitionID = UUID()
        #expect(!ManualOperationOwnership.permits(state, automationEnabled: false))
        state.desiredOwner = BackendState.Owner.none
        #expect(ManualOperationOwnership.permits(state, automationEnabled: false))
        state.phase = .stopping
        #expect(!ManualOperationOwnership.permits(state, automationEnabled: false))
    }

    @Test func lockedPermitRejectsStaleWorkAndDoesNotRelaxAutomaticEvaluation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        var configuration = AutomntConfig()
        configuration.automationEnabled = false
        let snapshot = try repository.create(configuration)
        var state = BackendState(owner: .none, phase: .stopped, generation: 3, revision: snapshot.revision)
        state.lastVerifiedServiceStatus = .stopped
        do {
            let permit = try EvaluationPermit(directory: directory, repository: repository,
                expected: snapshot, owner: .app, generation: 3, explicitManualAppOperation: true,
                readBackend: { state })
            permit.perform { #expect($0.revision == snapshot.revision) }
        }
        #expect(throws: AutomntIssue.incompatibleOwner) {
            _ = try EvaluationPermit(directory: directory, repository: repository,
                expected: snapshot, owner: .app, generation: 3, readBackend: { state })
        }
        #expect(throws: AutomntIssue.configurationConflict) {
            _ = try EvaluationPermit(directory: directory, repository: repository,
                expected: snapshot, owner: .app, generation: 2, explicitManualAppOperation: true,
                readBackend: { state })
        }
        state.owner = .cli
        state.phase = .active
        #expect(throws: AutomntIssue.incompatibleOwner) {
            _ = try EvaluationPermit(directory: directory, repository: repository,
                expected: snapshot, owner: .app, generation: 3, explicitManualAppOperation: true,
                readBackend: { state })
        }
    }

    @Test func cliAndUnfinishedTransitionsNeverPermitManualAppOperations() {
        var state = BackendState(owner: .cli, phase: .active, generation: 0,
            revision: ConfigRevision(digest: "manual-policy"))
        #expect(!ManualOperationOwnership.permits(state, automationEnabled: false))
        state.owner = .app
        #expect(ManualOperationOwnership.permits(state, automationEnabled: true))
        state.transitionID = UUID()
        #expect(!ManualOperationOwnership.permits(state, automationEnabled: true))
        state.desiredOwner = .app
        state.lastVerifiedServiceStatus = .enabled
        #expect(ManualOperationOwnership.permits(state, automationEnabled: true))
        state.desiredOwner = .cli
        #expect(!ManualOperationOwnership.permits(state, automationEnabled: true))
        state.desiredOwner = nil
        state.phase = .stopping
        #expect(!ManualOperationOwnership.permits(state, automationEnabled: false))
    }
}
