import Foundation
import Darwin
import AutomntCore

/// Run inside the bounded worker process, never the GUI/helper executor: network
/// filesystem syscalls may block despite O_NONBLOCK. Parent must enforce termination.
/// Caller verifies the mounted SMB identity and retains its security scope before calling.
/// Marker creation requests exclusion; it cannot prove Spotlight actually stopped.
public struct VolumeMarkerPostMountBackend: PostMountBackend {
    public init() {}
    public func preventIndexing(at actualPath: String, deadline: ContinuousClock.Instant) async -> PostMountResult {
        preventIndexingBlocking(at: actualPath, deadline: deadline)
    }
    /// Same bounded local descriptor work without async suspension points, for callers
    /// that already run on a dedicated background path.
    public func preventIndexingBlocking(at actualPath: String, deadline: ContinuousClock.Instant) -> PostMountResult {
        guard ContinuousClock.now < deadline else { return .timedOut }
        guard actualPath.hasPrefix("/"), actualPath != "/", !actualPath.contains("\0") else { return .unavailable }
        // Local nonblocking descriptor operations only. Never invoke mdutil from the GUI channel.
        let directory = open(actualPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard directory >= 0 else { return result(errno) }
        defer { close(directory) }
        guard ContinuousClock.now < deadline else { return .timedOut }
        let descriptor = openat(directory, ".metadata_never_index", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, mode_t(0o600))
        guard descriptor >= 0 else {
            if errno == EEXIST {
                var info = stat()
                guard fstatat(directory, ".metadata_never_index", &info, AT_SYMLINK_NOFOLLOW) == 0,
                      info.st_mode & S_IFMT == S_IFREG else { return .unavailable }
                return .markerAlreadyPresent
            }
            return result(errno)
        }
        close(descriptor)
        return .markerCreated
    }
    private func result(_ code: Int32) -> PostMountResult {
        switch code {
        case EROFS: .readOnly
        case EACCES, EPERM: .permissionDenied
        default: .unavailable
        }
    }
}
