import Foundation
import Darwin
import Testing
@testable import AutomntCore

struct PrivateFileTests {
    @Test func privateReadRejectsBroadModesLinksAndFIFOs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(UUID().uuidString)
        let content = Data(UUID().uuidString.utf8)
        try PrivateAtomicFile.replace(content, at: file)
        #expect(try PrivateAtomicFile.read(file) == content)
        for mode in [mode_t(0o644), mode_t(0o660), mode_t(0o1600)] {
            #expect(chmod(file.path, mode) == 0)
            #expect(throws: (any Error).self) { try PrivateAtomicFile.read(file) }
        }
        #expect(chmod(file.path, 0o600) == 0)
        let link = directory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(throws: (any Error).self) { try PrivateAtomicFile.read(link) }
        let fifo = directory.appendingPathComponent(UUID().uuidString)
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(throws: (any Error).self) { try PrivateAtomicFile.read(fifo) }
        #expect(throws: (any Error).self) { try PrivateAtomicFile.read(file, maximumBytes: content.count - 1) }
    }

    @Test func productConfigurationWithBroadPermissionsIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(AutomntConfig())
        let file = directory.appendingPathComponent("automnt.plist")
        #expect(chmod(file.path, 0o644) == 0)
        #expect(throws: (any Error).self) { try repository.read() }
        #expect(throws: (any Error).self) { try repository.save(snapshot.configuration, baseRevision: snapshot.revision) }
        #expect(chmod(file.path, 0o600) == 0)
        #expect(try repository.read().revision == snapshot.revision)
    }
}
