import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

struct BackgroundObservationTests {
    @Test func staleHelperCannotOverwriteObservationsAfterHandoff() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: snapshot.revision)
        let journal = try store.begin(desiredOwner: .app, expectedGeneration: 0, revision: snapshot.revision)
        _ = try store.advance(id: journal.id, to: .activating, verifiedStatus: .stopped)
        let active = try store.advance(id: journal.id, to: .active, verifiedStatus: .enabled)
        try BackgroundObservationCommit.commit(BackgroundEvaluationSummary(issue: .offline), state: active, directory: directory)
        let url = directory.appendingPathComponent("background-observations.plist")
        let original = try PrivateAtomicFile.read(url)
        _ = try store.begin(desiredOwner: .none, expectedGeneration: active.generation, revision: snapshot.revision)
        do {
            try BackgroundObservationCommit.commit(BackgroundEvaluationSummary(), state: active, directory: directory)
            Issue.record("Stale helper must not overwrite observations")
        } catch { #expect(error as? AutomntIssue == .configurationConflict) }
        #expect(try PrivateAtomicFile.read(url) == original)
    }
}
