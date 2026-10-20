import Foundation
import Testing
@testable import AutomntCore

struct TransitionWorkerTests {
    @Test func pendingWorkerBlocksActivationAndInterruptedRepairWithoutChangingJournal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let revision = ConfigRevision(digest: UUID().uuidString)
        let backend = BackendStateStore(authorizedDirectory: directory)
        _ = try backend.initialize(revision: revision)
        let worker = WorkerOperationStore(authorizedDirectory: directory)
        let id = try worker.begin(revision: revision, generation: 0)
        let transition = try backend.begin(desiredOwner: .app, expectedGeneration: 0, revision: revision)
        #expect(throws: AutomntIssue.signalUnavailable) {
            try backend.advance(id: transition.id, to: .activating, verifiedStatus: .stopped)
        }
        #expect(throws: AutomntIssue.signalUnavailable) {
            try backend.reconcileInterruptedTransition(verifiedStatus: .stopped)
        }
        #expect(try backend.journal() == transition)
        #expect(try backend.read() == transition.pending)
        try worker.complete(id: id, revision: revision, generation: 0)
        #expect(try backend.advance(id: transition.id, to: .activating, verifiedStatus: .stopped).phase == .activating)
        #expect(try backend.advance(id: transition.id, to: .active, verifiedStatus: .enabled).owner == .app)
    }
}
