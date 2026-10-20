import Foundation
import Darwin

/// A sandbox denial is unknown, never evidence that no CLI configuration exists.
/// This probe does not decode, migrate or modify the legacy configuration.
public enum LegacyConfigurationConflict: Error, Sendable {
    case takeoverRequired
}

public enum LegacyConfigurationPresence: Equatable, Sendable {
    case absent, present, unknown

    public static func inspect(at url: URL) -> Self {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        guard descriptor >= 0 else { return errno == ENOENT ? .absent : .unknown }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG else { return .unknown }
        return .present
    }
}
