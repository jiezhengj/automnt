import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

struct AppServiceAdapterTests {
    @Test @MainActor func registrationRequiresActivatingJournalAndIdleWorker() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: snapshot.revision)
        let adapter = AppServiceHandoffAdapter(authorizedDirectory: directory, revision: snapshot.revision)
        do {
            _ = try await adapter.register(owner: .app, deadline: ContinuousClock.now.advanced(by: .seconds(2)))
            Issue.record("Unprepared registration must reject before system calls")
        } catch { #expect(error as? AutomntIssue == .incompatibleOwner) }
        let journal = try store.begin(desiredOwner: .app, expectedGeneration: 0, revision: snapshot.revision)
        _ = try store.advance(id: journal.id, to: .activating, verifiedStatus: .stopped)
        #expect(try adapter.registrationMode() == .recovery)
        _ = try WorkerOperationStore(authorizedDirectory: directory).begin(revision: snapshot.revision, generation: journal.pending.generation)
        #expect(throws: AutomntIssue.signalUnavailable) { try adapter.registrationMode() }
    }
}
