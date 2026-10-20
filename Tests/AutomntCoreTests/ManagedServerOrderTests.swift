import Foundation
import Testing
@testable import AutomntCore

/// One managed share per named server, so ordering tests read as host lists.
func makeOrderTestConfig(_ hosts: [String]) -> AutomntConfig {
    AutomntConfig(hosts: hosts.map { name in
        HostConfig(host: name, shares: [
            SMBShareConfig(name: "Docs", smbURL: "smb://\(name)/Docs", mountPoint: "/Volumes/\(name)-Docs")
        ])
    })
}

struct ManagedServerOrderTests {
    private func config(_ hosts: [String]) -> AutomntConfig { makeOrderTestConfig(hosts) }

    @Test func moveReportsFinalIndexAndKeepsIdentity() throws {
        let original = config(["a.example", "b.example", "c.example"])
        let moved = try #require(ManagedServerOrder.moving(original, identity: "a.example:445", to: 2))
        #expect(moved.hosts.map(\.host) == ["b.example", "c.example", "a.example"])
        let back = try #require(ManagedServerOrder.moving(moved, identity: "a.example:445", to: 0))
        #expect(back.hosts.map(\.host) == ["a.example", "b.example", "c.example"])
    }

    @Test func moveRejectsUnknownIdentityAndUnchangedDestination() {
        let original = config(["a.example", "b.example"])
        #expect(ManagedServerOrder.moving(original, identity: "missing.example:445", to: 0) == nil)
        #expect(ManagedServerOrder.moving(original, identity: "a.example:445", to: 0) == nil)
        #expect(ManagedServerOrder.moving(original, identity: "a.example:445", to: 9) == nil)
    }

    @Test func portIsPartOfServerIdentity() throws {
        var original = config(["a.example"])
        original.hosts.append(HostConfig(host: "a.example", port: 1445, shares: [
            SMBShareConfig(name: "Docs", smbURL: "smb://a.example:1445/Docs", mountPoint: "/Volumes/Alt")
        ]))
        #expect(ManagedServerOrder.identities(of: original) == ["a.example:445", "a.example:1445"])
        let moved = try #require(ManagedServerOrder.moving(original, identity: "a.example:1445", to: 0))
        #expect(ManagedServerOrder.identities(of: moved) == ["a.example:1445", "a.example:445"])
    }

    @Test func restoreDropsIdentitiesThatNoLongerExist() throws {
        let original = config(["a.example", "b.example", "c.example"])
        let restored = try #require(ManagedServerOrder.restoring(original, order: ["c.example:445", "gone.example:445", "a.example:445"]))
        #expect(restored.hosts.map(\.host) == ["c.example", "a.example", "b.example"])
        // An order identical to the current one is not a change.
        #expect(ManagedServerOrder.restoring(original, order: ["a.example:445", "b.example:445", "c.example:445"]) == nil)
    }
}

struct ManagedServerOrderControllerTests {
    private func repository() throws -> (FileConfigRepository, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return (FileConfigRepository(authorizedDirectory: directory), directory)
    }

    private func seeded(_ names: [String]) throws -> (FileConfigRepository, URL, ConfigSnapshot) {
        let (repository, directory) = try repository()
        let snapshot = try repository.create(AutomntConfig(hosts: names.map { name in
            HostConfig(host: name, shares: [
                SMBShareConfig(name: "Docs", smbURL: "smb://\(name)/Docs", mountPoint: "/Volumes/\(name)")
            ])
        }))
        return (repository, directory, snapshot)
    }

    @Test func moveSavesImmediatelyAndUndoRestoresPreviousOrder() throws {
        let (repository, directory, snapshot) = try seeded(["a.example", "b.example", "c.example"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = ManagedServerOrderController(repository: repository)

        let outcome = controller.move(identity: "a.example:445", to: 2, baseRevision: snapshot.revision)
        #expect(outcome.issue == nil)
        #expect(outcome.savedOrder == ["b.example:445", "c.example:445", "a.example:445"])
        // Persisted, not just in memory.
        #expect(try repository.read().configuration.hosts.map(\.host) == ["b.example", "c.example", "a.example"])

        let undo = try #require(outcome.undo)
        let undone = controller.undo(undo)
        #expect(undone.issue == nil)
        #expect(undone.savedOrder == ["a.example:445", "b.example:445", "c.example:445"])
        #expect(try repository.read().configuration.hosts.map(\.host) == ["a.example", "b.example", "c.example"])
    }

    @Test func moveOnStaleRevisionConflictsWithoutOverwriting() throws {
        let (repository, directory, snapshot) = try seeded(["a.example", "b.example"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = ManagedServerOrderController(repository: repository)
        // Another entry point saves first.
        let other = try repository.save(makeOrderTestConfig(["a.example", "b.example", "extra.example"]), baseRevision: snapshot.revision)

        let outcome = controller.move(identity: "a.example:445", to: 1, baseRevision: snapshot.revision)
        #expect(outcome.issue == .configurationConflict)
        #expect(outcome.snapshot == nil)
        #expect(try repository.read().revision == other.revision)
        #expect(try repository.read().configuration.hosts.map(\.host) == ["a.example", "b.example", "extra.example"])
    }

    @Test func undoAfterAnotherSaveIsRefusedAndKeepsLatestOrder() throws {
        let (repository, directory, snapshot) = try seeded(["a.example", "b.example", "c.example"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = ManagedServerOrderController(repository: repository)
        let outcome = controller.move(identity: "a.example:445", to: 2, baseRevision: snapshot.revision)
        let undo = try #require(outcome.undo)
        let afterMove = try #require(outcome.snapshot)

        // A later unrelated change invalidates the captured revision.
        let later = try repository.save(makeOrderTestConfig(["x.example", "b.example", "c.example", "a.example"]),
                                        baseRevision: afterMove.revision)
        let refused = controller.undo(undo)
        #expect(refused.issue == .configurationConflict)
        #expect(try repository.read().configuration.hosts.map(\.host) == ["x.example", "b.example", "c.example", "a.example"])
        #expect(try repository.read().revision == later.revision)
    }
}
