import Foundation
import AutomntCore

/// The two mutually exclusive bundled LaunchAgents that evaluate automatic mounting.
public enum BundledAgent: String, Sendable, CaseIterable {
    case baseline
    case recovery

    public var label: String { "org.automnt.automnt." + rawValue }
    public var plistName: String { "automnt.\(rawValue).plist" }

    public init?(label: String) {
        guard let value = Self.allCases.first(where: { $0.label == label }) else { return nil }
        self = value
    }
}

/// The fixed, signed agent definition shipped inside the app bundle.
///
/// launchd resolves `BundleProgram` relative to the application bundle, and the helper
/// inherits no bundle identity of its own. Verification therefore operates on an explicit
/// application URL instead of `Bundle.main`.
public enum BundledServiceDefinition {
    public static let helperRelativePath = ApplicationBundleLocation.helperRelativePath

    public static func plistURL(applicationURL: URL, agent: BundledAgent) -> URL {
        applicationURL
            .appendingPathComponent("Contents/Library/LaunchAgents")
            .appendingPathComponent(agent.plistName)
    }

    public static func helperURL(applicationURL: URL) -> URL {
        applicationURL.appendingPathComponent(helperRelativePath)
    }

    /// Pure validation of a decoded plist, kept separate so it is testable without a
    /// signed bundle. The definition must be a bundled-agent form: fixed label and
    /// `BundleProgram`, no inlined `Program`/`ProgramArguments`, and `RunAtLoad`.
    public static func accepts(_ plist: [String: Any], agent: BundledAgent) -> Bool {
        plist["Label"] as? String == agent.label &&
        plist["BundleProgram"] as? String == helperRelativePath &&
        plist["Program"] == nil &&
        plist["ProgramArguments"] == nil &&
        plist["RunAtLoad"] as? Bool == true
    }

    /// Strict verification: the app/helper identity plus the fixed bundled definition.
    /// Throws `AutomntIssue.authorizationRequired` for every mismatch.
    public static func verify(applicationURL: URL, agent: BundledAgent) throws {
        try BundledCodeVerifier.verifyHelper(applicationURL: applicationURL,
                                             helperURL: helperURL(applicationURL: applicationURL))
        let data = try Data(contentsOf: plistURL(applicationURL: applicationURL, agent: agent))
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              accepts(plist, agent: agent) else {
            throw AutomntIssue.authorizationRequired
        }
    }
}
