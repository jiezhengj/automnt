import Foundation
import Darwin
import Testing
@testable import AutomntCore

struct ConfigLockTests {
    @Test func busyStableLockRejectsRepositoryOperationsAndPreservesInode() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(AutomntConfig())
        let url = directory.appendingPathComponent("config.lock")
        var before = stat()
        #expect(lstat(url.path, &before) == 0)
        do {
            let held = try StableFileLock(url: url)
            try withExtendedLifetime(held) {
                #expect(throws: AutomntIssue.configurationConflict) { try repository.read() }
                #expect(throws: AutomntIssue.configurationConflict) {
                    try repository.save(snapshot.configuration, baseRevision: snapshot.revision)
                }
                #expect(throws: AutomntIssue.configurationConflict) { try repository.create(AutomntConfig()) }
            }
        }
        #expect(try repository.read().revision == snapshot.revision)
        try repository.save(snapshot.configuration, baseRevision: snapshot.revision)
        var after = stat()
        #expect(lstat(url.path, &after) == 0)
        #expect(before.st_ino == after.st_ino)
        #expect(after.st_mode & 0o777 == 0o600)
    }
}
