import Foundation
import Darwin

/// Held descriptor owns the lock; the on-disk inode is never replaced or deleted.
public final class StableFileLock {
    private let descriptor: Int32
    public init(url: URL, nonblocking: Bool = true) throws {
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            let error = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            close(descriptor); throw error
        }
        guard (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid() else {
            close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        }
        guard fchmod(descriptor, 0o600) == 0,
              flock(descriptor, LOCK_EX | (nonblocking ? LOCK_NB : 0)) == 0 else {
            let error = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            close(descriptor)
            throw error
        }
        self.descriptor = descriptor
    }
    deinit { _ = flock(descriptor, LOCK_UN); close(descriptor) }
}
