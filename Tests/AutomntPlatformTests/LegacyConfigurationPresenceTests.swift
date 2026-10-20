import Foundation
import Testing
@testable import AutomntPlatform

struct LegacyConfigurationPresenceTests {
    @Test func absentFileIsDistinctFromExistingFileAndUnsafePath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("legacy")
        #expect(LegacyConfigurationPresence.inspect(at: file) == .absent)
        // Content is intentionally not a business configuration: this is only a
        // presence probe and must not mistake malformed existing data for absence.
        try Data("invalid".utf8).write(to: file)
        #expect(LegacyConfigurationPresence.inspect(at: file) == .present)
        #expect(LegacyConfigurationPresence.inspect(at: directory) == .unknown)
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(LegacyConfigurationPresence.inspect(at: link) == .unknown)
        try FileManager.default.removeItem(at: file)
        #expect(LegacyConfigurationPresence.inspect(at: link) == .unknown)
    }
}
