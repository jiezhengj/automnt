import Foundation
import Testing
import AutomntCore

/// The durable backend state records the configuration revision it was activated for.
/// The app advances it after every save; otherwise its own next evaluation is rejected as
/// a stale conflict ("changed in another window or from the command line").
struct BackendRevisionAdoptionTests {
    private func activeBackend() throws -> (URL, BackendStateStore, ConfigSnapshot) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let first = try repository.create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: first.revision)
        let journal = try store.begin(desiredOwner: .app, expectedGeneration: 0, revision: first.revision)
        _ = try store.advance(id: journal.id, to: .activating, verifiedStatus: .stopped)
        _ = try store.advance(id: journal.id, to: .active, verifiedStatus: .enabled)
        return (directory, store, first)
    }

    private func save(_ first: ConfigSnapshot, in directory: URL) throws -> ConfigSnapshot {
        var configuration = first.configuration
        configuration.updateChannel = configuration.updateChannel == "off" ? "stable" : "off"
        return try FileConfigRepository(authorizedDirectory: directory)
            .save(configuration, baseRevision: first.revision)
    }

    @Test func adoptionAdvancesStateAndJournalWithoutChangingIdentity() throws {
        let (directory, store, first) = try activeBackend()
        defer { try? FileManager.default.removeItem(at: directory) }
        let saved = try save(first, in: directory)

        let adopted = try store.adoptConfigurationRevision(expected: first.revision, new: saved.revision)
        #expect(adopted.revision == saved.revision)
        #expect(adopted.owner == .app)
        #expect(adopted.phase == .active)
        #expect(adopted.generation == 1)
        #expect(try store.read().revision == saved.revision)
        let journal = try store.journal()
        #expect(journal.pending.revision == saved.revision)
        #expect(journal.pending == adopted)
        #expect(journal.priorPending?.revision == saved.revision)
    }

    @Test func adoptionIsANoOpWhenRevisionAlreadyMatches() throws {
        let (directory, store, first) = try activeBackend()
        defer { try? FileManager.default.removeItem(at: directory) }
        let adopted = try store.adoptConfigurationRevision(expected: first.revision, new: first.revision)
        #expect(adopted.revision == first.revision)
        #expect(adopted.phase == .active)
    }

    @Test func adoptionRefusesARevisionTheStateDoesNotRecord() throws {
        let (directory, store, first) = try activeBackend()
        defer { try? FileManager.default.removeItem(at: directory) }
        let saved = try save(first, in: directory)
        _ = try store.adoptConfigurationRevision(expected: first.revision, new: saved.revision)
        // Already adopted: replacing the old revision is no longer possible.
        #expect(throws: AutomntIssue.configurationConflict) {
            try store.adoptConfigurationRevision(expected: first.revision, new: saved.revision)
        }
    }

    @Test func adoptionRefusesARevisionThatIsNotTheOneOnDisk() throws {
        let (directory, store, first) = try activeBackend()
        defer { try? FileManager.default.removeItem(at: directory) }
        let saved = try save(first, in: directory)
        let unrelated = ConfigRevision(digest: String(repeating: "0", count: 64))
        #expect(throws: AutomntIssue.configurationConflict) {
            try store.adoptConfigurationRevision(expected: first.revision, new: unrelated)
        }
    }

    @Test func adoptionRefusesBackendThatIsNotActiveAndAppOwned() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let first = try repository.create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: first.revision)
        let saved = try save(first, in: directory)
        #expect(throws: AutomntIssue.configurationConflict) {
            try store.adoptConfigurationRevision(expected: first.revision, new: saved.revision)
        }
    }
}
