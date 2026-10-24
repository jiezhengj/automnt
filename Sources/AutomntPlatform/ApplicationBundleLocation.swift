import Foundation
import Darwin

/// Locates the enclosing application bundle from the running executable.
///
/// A bundled launchd agent declares `BundleProgram = Contents/Helpers/AutomntHelper`, so
/// launchd passes exactly that bundle-relative string as `argv[0]`. A sandboxed helper also
/// runs with its working directory inside its own container
/// (`~/Library/Containers/org.automnt.automnthelper/Data`), therefore
/// `CommandLine.arguments[0]` can never locate the application bundle. The kernel's view of
/// the executable path is independent of both and is the only reliable source here.
public enum ApplicationBundleLocation {
    public static let applicationBundleIdentifier = "org.automnt.automnt"
    public static let helperRelativePath = "Contents/Helpers/AutomntHelper"

    /// Absolute path of the running executable as recorded by the kernel.
    ///
    /// Falls back to `Bundle.main.executableURL` only when `proc_pidpath` is unavailable;
    /// callers still validate that the result resolves to our signed app bundle.
    public static func currentExecutableURL() -> URL? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let length = proc_pidpath(getpid(), &buffer, UInt32(buffer.count))
        if length > 0 {
            let path = String(decoding: buffer[0..<Int(length)], as: UTF8.self)
            return URL(fileURLWithPath: path).resolvingSymlinksInPath()
        }
        return Bundle.main.executableURL?.resolvingSymlinksInPath()
    }

    /// Walks up from the executable to its nearest `.app` directory.
    ///
    /// The walk deliberately does not consult `argv[0]`, `Bundle.main.bundleURL` or the
    /// working directory: all three are wrong in the launchd helper context.
    public static func applicationURL(containingExecutable executable: URL) -> URL? {
        var candidate = executable.resolvingSymlinksInPath().deletingLastPathComponent()
        while candidate.path != "/" && !candidate.path.isEmpty {
            if candidate.pathExtension == "app" { return candidate }
            candidate = candidate.deletingLastPathComponent()
        }
        return nil
    }

    /// The containing `.app` as a bundle, only when it carries the Automnt identity.
    public static func application(containingExecutable executable: URL) -> Bundle? {
        guard let url = applicationURL(containingExecutable: executable),
              let bundle = Bundle(url: url),
              bundle.bundleIdentifier == applicationBundleIdentifier else { return nil }
        return bundle
    }

    /// Convenience for the current process; nil when the process is not inside our app.
    public static func currentApplication() -> Bundle? {
        guard let executable = currentExecutableURL() else { return nil }
        return application(containingExecutable: executable)
    }
}
