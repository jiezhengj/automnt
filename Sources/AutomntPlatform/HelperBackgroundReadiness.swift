import Foundation
import AutomntCore

/// Readiness gate for the independent background helper.
///
/// The helper cannot use `SMAppService.agent(plistName:)`: that API resolves agent plists
/// relative to `Bundle.main`, and inside `Contents/Helpers` the main bundle is the Helpers
/// directory, so every status query fails (measured: error 22,
/// "Unable to find service status (LaunchAgent(automnt.recovery.plist))"). The app process
/// remains the source of truth for `SMAppService` status; the helper instead proves its own
/// launch readiness with three facts it can actually observe:
///
/// 1. the launched identity (`XPC_SERVICE_NAME` set by launchd) matches the mode the
///    configuration currently expects, so a stale opposite registration cannot evaluate;
/// 2. the fixed, signed definition for that agent exists in the resolved app bundle (the
///    helper verifies this once at startup and passes the result in);
/// 3. the committed backend state says the app owns an active service whose last verified
///    system status was enabled, at a non-zero generation.
///
/// Any unknown or partial state returns `.unavailable`; the caller then exits without
/// evaluating. This mirrors the app-side rule that only a verified `enabled` registration
/// authorizes evaluation.
public struct HelperBackgroundReadiness: Sendable {
    public let applicationURL: URL
    public let launchedServiceLabel: String?
    public let definitionVerified: Bool

    public init(applicationURL: URL, launchedServiceLabel: String?, definitionVerified: Bool) {
        self.applicationURL = applicationURL
        self.launchedServiceLabel = launchedServiceLabel
        self.definitionVerified = definitionVerified
    }

    /// launchd exports the job label to the spawned process. A user shell or manual launch
    /// has no such value, so manual runs are refused rather than treated as approved.
    public static func launchedServiceLabel(
        in environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard let value = environment["XPC_SERVICE_NAME"], !value.isEmpty else { return nil }
        return value
    }

    public static func expectedAgent(for configuration: AutomntConfig) -> BundledAgent {
        (configuration.autoMountRecovery ?? true) ? .recovery : .baseline
    }

    /// Verifies the signed fixed definition for the agent that launchd actually launched.
    /// Runs once per helper lifetime; the result is carried by `definitionVerified`.
    @discardableResult
    public static func verifyLaunchedDefinition(applicationURL: URL,
                                                launchedServiceLabel: String?) throws -> BundledAgent {
        guard let label = launchedServiceLabel,
              let agent = BundledAgent(label: label) else {
            throw AutomntIssue.authorizationRequired
        }
        try BundledServiceDefinition.verify(applicationURL: applicationURL, agent: agent)
        return agent
    }

    /// The status consumed by the bounded trigger. Only `.enabled` authorizes evaluation.
    public func status(configuration: AutomntConfig, backend: BackendState) -> BackendState.ServiceStatus {
        let expected = Self.expectedAgent(for: configuration)
        guard launchedServiceLabel == expected.label, definitionVerified else { return .unavailable }
        guard backend.generation > 0,
              backend.owner == .app,
              backend.desiredOwner == .app,
              backend.phase == .active,
              backend.lastVerifiedServiceStatus == .enabled else { return .unavailable }
        return .enabled
    }
}
