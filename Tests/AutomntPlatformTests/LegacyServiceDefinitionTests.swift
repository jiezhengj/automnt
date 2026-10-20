import Foundation
import Testing
@testable import AutomntPlatform

struct LegacyServiceDefinitionTests {
    @Test func definitionRecognitionDoesNotTrustLabelAlone() throws {
        let binary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("automnt")
        var definition: [String: Any] = ["Label": "com.user.automnt", "ProgramArguments": [binary.path],
            "RunAtLoad": true, "WatchPaths": ["/Library/Preferences/SystemConfiguration"]]
        func classify() throws -> LegacyCLIServiceDefinition {
            LegacyCLIServiceDefinition.classify(try PropertyListSerialization.data(fromPropertyList: definition, format: .binary, options: 0))
        }
        #expect(try classify() == .recognized)
        definition["ProgramArguments"] = [binary.path, "--init"]
        #expect(try classify() == .unknown)
        definition["ProgramArguments"] = [binary.path]
        definition["Program"] = binary.path
        #expect(try classify() == .unknown)
        #expect(LegacyCLIServiceDefinition.classify(Data()) == .unknown)
    }
    @Test func linkedAndOversizedDefinitionsRemainUnknown() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target")
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(LegacyCLIServiceDefinition.inspect(at: link) == .unknown)
        try Data(repeating: 0, count: 1_048_577).write(to: target)
        #expect(LegacyCLIServiceDefinition.inspect(at: target) == .unknown)
        #expect(LegacyCLIServiceDefinition.inspect(at: link) == .unknown)
    }
    @Test func missingDefinitionAndUnreadableShapeAreDifferent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(LegacyCLIServiceDefinition.inspect(at: directory) == .absent)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(LegacyCLIServiceDefinition.inspect(at: directory) == .unknown)
    }
}
