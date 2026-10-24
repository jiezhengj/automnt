import Foundation
import Testing
@testable import AutomntPlatform

struct ApplicationBundleLocationTests {
    private func makeApplication(identifier: String = "org.automnt.automnt") throws -> (root: URL, application: URL, executable: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let application = root.appendingPathComponent("Automnt.app")
        let helpers = application.appendingPathComponent("Contents/Helpers")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": identifier,
                                   "CFBundleExecutable": "Automnt",
                                   "CFBundleName": "Automnt"]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: application.appendingPathComponent("Contents/Info.plist"))
        let executable = helpers.appendingPathComponent("AutomntHelper")
        try Data().write(to: executable)
        return (root, application, executable)
    }

    @Test func resolvesApplicationFromExecutableInsteadOfArgvOrWorkingDirectory() throws {
        let fixture = try makeApplication()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(ApplicationBundleLocation.applicationURL(containingExecutable: fixture.executable)?.standardizedFileURL
            == fixture.application.standardizedFileURL)
        #expect(ApplicationBundleLocation.application(containingExecutable: fixture.executable)?.bundleIdentifier
            == "org.automnt.automnt")
    }

    @Test func rejectsForeignBundleIdentityAndExecutablesOutsideAnApp() throws {
        let foreign = try makeApplication(identifier: "com.example.other")
        defer { try? FileManager.default.removeItem(at: foreign.root) }
        #expect(ApplicationBundleLocation.application(containingExecutable: foreign.executable) == nil)

        let bare = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("bin/helper")
        #expect(ApplicationBundleLocation.applicationURL(containingExecutable: bare) == nil)
    }

    @Test func bundledAgentLabelsAreFixedAndBidirectional() {
        for agent in BundledAgent.allCases {
            #expect(BundledAgent(label: agent.label) == agent)
            #expect(agent.plistName == "automnt.\(agent.rawValue).plist")
        }
        #expect(BundledAgent(label: "com.example.other") == nil)
    }
}
