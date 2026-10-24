import Foundation
import AutomntCore

/// Sign-in material handed to the isolated worker for one mount.
///
/// The product deliberately does not manage SMB passwords. If an app-scoped item exists
/// (for an explicitly stored credential), it is used; otherwise the mount proceeds without
/// a credential so NetFS reuses the sign-in macOS already holds, exactly like the CLI.
/// A missing or unreadable item is not a failure: `kNAUIOptionNoUI` prevents a background
/// credential prompt, and the mount result reports the real rejection.
public enum SMBSystemCredential {
    public static func reuse(shareURL: String) -> MemoryCredential {
        let empty = MemoryCredential(username: "", password: Data())
        guard let identity = smbResourceIdentity(shareURL),
              let stored = try? KeychainCredentialProvider().read(identity: identity) else { return empty }
        return stored
    }
}
