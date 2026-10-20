import Foundation
import Darwin
import Testing
@testable import AutomntCore

struct MergeReadTests {
    @Test func mergeRejectsUnreadableExistingConfigurationWithoutChangingIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(AutomntConfig())
        let file = directory.appendingPathComponent("automnt.plist")
        let original = try PrivateAtomicFile.read(file)
        #expect(chmod(file.path, 0o644) == 0)
        #expect(throws: (any Error).self) {
            try encodeConfigPreservingUnknownFields(snapshot.configuration, at: file)
        }
        #expect(chmod(file.path, 0o600) == 0)
        #expect(try PrivateAtomicFile.read(file) == original)
        let malformed = Data(UUID().uuidString.utf8)
        try PrivateAtomicFile.replace(malformed, at: file)
        #expect(throws: (any Error).self) {
            try encodeConfigPreservingUnknownFields(snapshot.configuration, at: file)
        }
        #expect(try PrivateAtomicFile.read(file) == malformed)
        let missing = directory.appendingPathComponent(UUID().uuidString)
        let encoded = try encodeConfigPreservingUnknownFields(snapshot.configuration, at: missing)
        #expect(try PropertyListDecoder().decode(AutomntConfig.self, from: encoded).hosts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }
}
