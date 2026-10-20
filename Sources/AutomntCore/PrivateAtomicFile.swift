import Foundation
import Darwin

/// Writes private auxiliary state in the authorized directory, never a container fallback.
public enum PrivateAtomicFile {
    public static func replace(_ data: Data, at destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".automnt-\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor); _ = unlink(temporary.path) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw posixError() }
                offset += count
            }
        }
        guard fsync(descriptor) == 0, rename(temporary.path, destination.path) == 0 else { throw posixError() }
        let parent = open(directory.path, O_RDONLY | O_CLOEXEC)
        guard parent >= 0 else { throw posixError() }
        defer { close(parent) }
        guard fsync(parent) == 0 else { throw posixError() }
    }

    public static func read(_ url: URL, maximumBytes: Int = 16 * 1024 * 1024) throws -> Data {
        // Nonblocking open also prevents a malformed FIFO from hanging before fstat.
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw posixError() }
        guard (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid(),
              info.st_mode & 0o077 == 0, info.st_mode & 0o7000 == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        }
        guard maximumBytes >= 0, info.st_size >= 0, info.st_size <= maximumBytes else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EFBIG))
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw posixError() }
            if count == 0 { return data }
            guard count <= maximumBytes - data.count else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(EFBIG))
            }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
