import Foundation
import AutomntCore

/// Local preflight only. launchd owns independent helper startup; a sandboxed
/// GUI must not spawn the helper to manufacture runtime-readiness evidence.
public enum HelperAuthorizationCheck {
    public static func verify(applicationURL: URL) async throws {
        try Task.checkCancellation()
        let helper = applicationURL.appendingPathComponent("Contents/Helpers/AutomntHelper")
        try BundledCodeVerifier.verifyHelper(applicationURL: applicationURL, helperURL: helper)
        _ = try SharedContainer.locate()
    }

    public static func ensure(applicationURL: URL, directory: AuthorizedDirectory) async throws {
        try await verify(applicationURL: applicationURL)
        guard directory.url.standardizedFileURL == PermissionStore.expectedDirectory.standardizedFileURL else {
            throw AutomntIssue.authorizationRequired
        }
        try await HelperPermissionProbe.ensure(directory: directory)
    }
}
