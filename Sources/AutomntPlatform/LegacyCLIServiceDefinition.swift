import Foundation
import Darwin

/// Definition evidence only. Absence does not prove launchd has no loaded job.
public enum LegacyCLIServiceDefinition: Equatable, Sendable {
    case absent, recognized, unknown

    public static func inspect(at url: URL) -> Self {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        guard descriptor >= 0 else { return errno == ENOENT ? .absent : .unknown }
        defer { close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              before.st_mode & S_IFMT == S_IFREG,
              before.st_size > 0, before.st_size <= 1_048_576 else { return .unknown }
        var data = Data(count: Int(before.st_size))
        let length = data.count
        let readComplete = data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < length {
                let count = Darwin.read(descriptor, bytes.baseAddress!.advanced(by: offset), length - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
        var after = stat()
        guard readComplete, fstat(descriptor, &after) == 0,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { return .unknown }
        return classify(data)
    }

    static func classify(_ data: Data) -> Self {
        guard data.count <= 1_048_576,
              let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let definition = value as? [String: Any],
              definition["Label"] as? String == "com.user.automnt",
              let arguments = definition["ProgramArguments"] as? [String], arguments.count == 1,
              arguments[0].hasPrefix("/"),
              URL(fileURLWithPath: arguments[0]).lastPathComponent == "automnt",
              definition["Program"] == nil,
              definition["RunAtLoad"] as? Bool == true,
              let paths = definition["WatchPaths"] as? [String],
              paths.contains("/Library/Preferences/SystemConfiguration") else { return .unknown }
        // Recognized means consistent with the shipped legacy shape, never an
        // authenticated executable/version or proof that its process has exited.
        return .recognized
    }
}
