import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

struct ConfigurationImportPreviewTests {
    @Test func previewReadsProgramCreatedConfigurationWithoutChangingIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let original = try repository.create(AutomntConfig())
        let file = directory.appendingPathComponent("automnt.plist")
        let preview = try ConfigurationImportPreview(selectedFile: file)
        #expect(preview.configuration == original.configuration)
        #expect(try repository.read().revision == original.revision)
        let link = directory.appendingPathComponent("link.plist")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(throws: (any Error).self) { try ConfigurationImportPreview(selectedFile: link) }
    }
}
