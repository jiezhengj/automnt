import Foundation
import Testing
@testable import AutomntCore

struct ManagedMembershipTests {
    private func candidate(_ name: String, host: String = "new.example", path: String? = nil) -> ManagedMembership.Candidate {
        ManagedMembership.Candidate(host: host, name: name,
            smbURL: "smb://\(host)/\(name)", mountPoint: path ?? "/Volumes/\(name)")
    }

    @Test func firstShareOnNewServerAppendsToManagedOrder() {
        let base = makeOrderTestConfig(["a.example", "b.example"])
        let outcome = ManagedMembership.adding(candidate("Media"), to: base)
        let updated = try? #require(outcome.configuration)
        #expect(updated?.hosts.map(\.host) == ["a.example", "b.example", "new.example"])
        #expect(outcome.appendedServer)
    }

    @Test func addingToExistingServerKeepsIdentityParametersAndOrder() throws {
        var base = makeOrderTestConfig(["a.example", "b.example"])
        base.hosts[1].alias = "Backup NAS"
        base.hosts[1].port = 1445
        base.hosts[1].timeoutMs = 2500
        let outcome = ManagedMembership.adding(
            ManagedMembership.Candidate(host: "b.example", port: 1445, name: "Media",
                smbURL: "smb://b.example:1445/Media", mountPoint: "/Volumes/Media"), to: base)
        let updated = try #require(outcome.configuration)
        #expect(updated.hosts.map(\.host) == ["a.example", "b.example"])
        #expect(updated.hosts[1].alias == "Backup NAS")
        #expect(updated.hosts[1].timeoutMs == 2500)
        #expect(updated.hosts[1].shares.map(\.name) == ["Docs", "Media"])
        #expect(!outcome.appendedServer)
    }

    @Test func duplicateIdentityOnSameServerIsRejected() {
        let base = makeOrderTestConfig(["a.example"])
        let outcome = ManagedMembership.adding(candidate("Docs", host: "a.example"), to: base)
        #expect(outcome.problem == .duplicateShare)
        #expect(outcome.configuration == nil)
    }

    @Test func sameServerPathConflictIsRejectedButCrossServerReuseIsAllowed() throws {
        var base = makeOrderTestConfig(["a.example"])
        base.hosts[0].shares[0].mountPoint = "/Volumes/Shared"
        // Different share name, same path, same server -> rejected.
        let sameServer = ManagedMembership.adding(candidate("Other", host: "a.example", path: "/Volumes/Shared"), to: base)
        #expect(sameServer.problem == .duplicateMountPath)
        // Different server, same configured path -> allowed (runtime must still check occupancy).
        let crossServer = ManagedMembership.adding(candidate("Other", host: "c.example", path: "/Volumes/Shared"), to: base)
        let updated = try #require(crossServer.configuration)
        #expect(updated.hosts.count == 2)
    }

    @Test func removingAShareKeepsServerWhenSharesRemain() throws {
        var base = makeOrderTestConfig(["a.example", "b.example"])
        base.hosts[0].shares.append(SMBShareConfig(name: "Media", smbURL: "smb://a.example/Media", mountPoint: "/Volumes/Media"))
        let outcome = ManagedMembership.removing(smbURL: "smb://a.example/Docs", from: base)
        let updated = try #require(outcome.configuration)
        #expect(updated.hosts.map(\.host) == ["a.example", "b.example"])
        #expect(updated.hosts[0].shares.map(\.name) == ["Media"])
    }

    @Test func removingLastShareAlsoRemovesTheServer() throws {
        let base = makeOrderTestConfig(["a.example", "b.example"])
        let outcome = ManagedMembership.removing(smbURL: "smb://a.example/Docs", from: base)
        let updated = try #require(outcome.configuration)
        #expect(updated.hosts.map(\.host) == ["b.example"])
    }

    @Test func removingUnknownTargetIsReported() {
        let base = makeOrderTestConfig(["a.example"])
        #expect(ManagedMembership.removing(smbURL: "smb://zzz.example/Docs", from: base).problem == .unknownTarget)
        #expect(ManagedMembership.removing(smbURL: "not a url", from: base).problem == .invalidTarget)
    }

    @Test func removingAServerDropsItsSharesTogether() throws {
        let base = makeOrderTestConfig(["a.example", "b.example"])
        let outcome = ManagedMembership.removingServer(identity: "a.example:445", from: base)
        let updated = try #require(outcome.configuration)
        #expect(updated.hosts.map(\.host) == ["b.example"])
    }
}

struct ManagedMembershipControllerTests {
    @Test func addPersistsImmediatelyAndReportsConflictOnStaleRevision() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(makeOrderTestConfig(["a.example"]))
        let controller = ManagedMembershipController(repository: repository)

        let added = controller.add(ManagedMembership.Candidate(host: "b.example", name: "Media",
            smbURL: "smb://b.example/Media", mountPoint: "/Volumes/Media"), baseRevision: snapshot.revision)
        #expect(added.issue == nil)
        #expect(added.savedOrder == ["a.example:445", "b.example:445"])

        // Reusing the original revision must not overwrite the saved change.
        let stale = controller.add(ManagedMembership.Candidate(host: "c.example", name: "Docs",
            smbURL: "smb://c.example/Docs", mountPoint: "/Volumes/C-Docs"), baseRevision: snapshot.revision)
        #expect(stale.issue == .configurationConflict)
        #expect(try repository.read().configuration.hosts.map(\.host) == ["a.example", "b.example"])
    }

    @Test func removalIsPersistedAndLeavesNoLocalDraft() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(makeOrderTestConfig(["a.example", "b.example"]))
        let controller = ManagedMembershipController(repository: repository)

        let removed = controller.remove(smbURL: "smb://a.example/Docs", baseRevision: snapshot.revision)
        #expect(removed.issue == nil)
        #expect(try repository.read().configuration.hosts.map(\.host) == ["b.example"])
    }
}
