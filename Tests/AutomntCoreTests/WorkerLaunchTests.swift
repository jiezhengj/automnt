import Foundation
import Testing
@testable import AutomntCore

struct WorkerLaunchTests {
    @Test func failedLaunchClearsOnlyItsOwnIntentAndSuccessfulLaunchStaysPending() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkerOperationStore(authorizedDirectory: directory)
        let revision = ConfigRevision(digest: UUID().uuidString)
        let id = UUID()
        #expect(throws: AutomntIssue.authorizationRequired) {
            try store.launch(revision: revision, generation: 1, id: id) {
                throw AutomntIssue.authorizationRequired
            }
        }
        let lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
        try withExtendedLifetime(lock) { try store.verifyIdle() }
    }

    @Test func successfulLaunchAndBlockedSecondLaunchKeepPending() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkerOperationStore(authorizedDirectory: directory)
        let revision = ConfigRevision(digest: UUID().uuidString)
        let id = UUID()
        #expect(try store.launch(revision: revision, generation: 1, id: id) {} == id)
        var called = false
        #expect(throws: AutomntIssue.signalUnavailable) {
            try store.launch(revision: revision, generation: 1, id: UUID()) { called = true }
        }
        #expect(!called)
        let lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
        try withExtendedLifetime(lock) {
            try store.verifyPending(id: id, revision: revision, generation: 1)
            #expect(throws: AutomntIssue.signalUnavailable) { try store.verifyIdle() }
        }
    }
}
