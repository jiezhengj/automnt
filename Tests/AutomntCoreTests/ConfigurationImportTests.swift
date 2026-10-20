import Foundation
import Testing
@testable import AutomntCore

struct ConfigurationImportTests {
    @Test func importPreservesExtensionsDisablesAutomationAndRefusesOverwrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceDirectory = root.appendingPathComponent("source")
        let targetDirectory = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Generate a dormant configuration through the repository, without targets.
        try FileConfigRepository(authorizedDirectory: sourceDirectory).create(AutomntConfig())
        let source = try Data(contentsOf: sourceDirectory.appendingPathComponent("automnt.plist"))
        var object = try #require(PropertyListSerialization.propertyList(from: source, format: nil) as? [String: Any])
        object["future_extension"] = ["schema": 2]
        let bytes = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
        let repository = FileConfigRepository(authorizedDirectory: targetDirectory)
        let imported = try repository.importConfiguration(bytes)
        #expect(!imported.configuration.isAutomationEnabled)
        let saved = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: targetDirectory.appendingPathComponent("automnt.plist")), format: nil) as? [String: Any])
        #expect((saved["future_extension"] as? [String: Int])?["schema"] == 2)
        #expect(throws: AutomntIssue.configurationConflict) { try repository.importConfiguration(bytes) }
        #expect(try repository.read().revision == imported.revision)
    }
}
