import Foundation
import Testing
@testable import AutomntCore

struct LogRetentionTests {
    private func fixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func oldLogsAreRemovedAndRecentLogsStay() throws {
        let directory = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = directory.appendingPathComponent("old.log")
        let recent = directory.appendingPathComponent("recent.log")
        try Data("old\n".utf8).write(to: old)
        try Data("recent\n".utf8).write(to: recent)
        let now = Date()
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-8 * 24 * 60 * 60)],
                                              ofItemAtPath: old.path)
        try LogRetention.enforce(files: [old, recent], now: now)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
    }

    @Test func oversizedLogKeepsTheTailOnALineBoundary() throws {
        let directory = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("large.log")
        let lines = (1...200).map { "line-\($0)-payload\n" }
        let original = lines.joined()
        try Data(original.utf8).write(to: log)
        let policy = LogRetention.Policy(maximumAge: 365 * 24 * 60 * 60, maximumBytes: 200)
        try LogRetention.enforce(files: [log], policy: policy, now: Date())
        let data = try Data(contentsOf: log)
        #expect(data.count <= 200)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasSuffix("line-200-payload\n"))
        #expect(text.hasPrefix("line-"))
        #expect(!text.hasPrefix("payload"))
    }

    @Test func clearRemovesExistingLogsAndToleratesMissingFiles() throws {
        let directory = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("one.log")
        let missing = directory.appendingPathComponent("two.log")
        try Data("one\n".utf8).write(to: first)
        try LogRetention.clear(files: [first, missing])
        #expect(!FileManager.default.fileExists(atPath: first.path))
    }
}
