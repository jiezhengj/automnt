import Foundation
import Testing
@testable import AutomntCore

struct TransitionRevisionTests {
    @Test func guardedCommitBlocksConcurrentSaveAndStaleStateRemainsUnchanged() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: snapshot.revision)
        let transition = try store.begin(desiredOwner: .app, expectedGeneration: 0, revision: snapshot.revision, verifyConfiguration: true)
        try repository.withRevision(snapshot.revision) {
            #expect(throws: AutomntIssue.configurationConflict) {
                try repository.save(snapshot.configuration, baseRevision: snapshot.revision)
            }
        }
        var changed = snapshot.configuration
        changed.automationEnabled = false
        _ = try repository.save(changed, baseRevision: snapshot.revision)
        #expect(throws: AutomntIssue.configurationConflict) {
            try store.advance(id: transition.id, to: .activating, verifiedStatus: .stopped, expectedRevision: snapshot.revision)
        }
        #expect(try store.read() == transition.pending)
        #expect(try store.journal() == transition)
    }
}
