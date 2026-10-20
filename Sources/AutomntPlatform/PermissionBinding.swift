import Foundation
import Darwin
import AutomntCore

/// One-time transfer uses an implicit-scope bookmark, never the GUI's stored bookmark.
/// The receiver creates its own explicit-scope bookmark in its private preferences.
public enum PermissionBinding {
    private static let maximumSize = 65_536

    public static func transferData(directory: AuthorizedDirectory) throws -> Data {
        let bookmark = try directory.url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        guard !bookmark.isEmpty, bookmark.count <= maximumSize else { throw AutomntIssue.authorizationRequired }
        var size = UInt32(bookmark.count).bigEndian
        var result = withUnsafeBytes(of: &size) { Data($0) }
        result.append(bookmark)
        return result
    }

    /// Reads a length-prefixed frame with a single deadline, without logging bookmark bytes.
    public static func receiveFromStandardInput() throws -> AuthorizedDirectory {
        let bookmark = try receiveFrame(descriptor: STDIN_FILENO,
            deadline: ContinuousClock.now.advanced(by: .seconds(5)))
        return try authorizeTransferredBookmark(bookmark)
    }

    public static func authorizeTransferredBookmark(_ bookmark: Data) throws -> AuthorizedDirectory {
        guard !bookmark.isEmpty, bookmark.count <= maximumSize else { throw AutomntIssue.authorizationRequired }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale else { throw AutomntIssue.authorizationRequired }
        // Resolving an implicit-scope bookmark extends the receiving process's access.
        // authorize validates the actual directory before storing a new private bookmark.
        return try PermissionStore().authorize(selectedDirectory: url)
    }

    static func receiveFrame(descriptor: Int32, deadline: ContinuousClock.Instant) throws -> Data {
        let header = try readExactly(4, descriptor: descriptor, deadline: deadline)
        let size = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard size > 0, size <= maximumSize else { throw AutomntIssue.authorizationRequired }
        return try readExactly(Int(size), descriptor: descriptor, deadline: deadline)
    }

    private static func readExactly(_ count: Int, descriptor input: Int32, deadline: ContinuousClock.Instant) throws -> Data {
        var result = Data()
        while result.count < count {
            guard ContinuousClock.now < deadline else { throw AutomntIssue.timeout }
            var descriptor = pollfd(fd: input, events: Int16(POLLIN), revents: 0)
            let status = Darwin.poll(&descriptor, 1, 20)
            if status < 0 {
                if errno == EINTR { continue }
                throw AutomntIssue.authorizationRequired
            }
            if status == 0 { continue }
            guard descriptor.revents & Int16(POLLIN | POLLHUP) != 0 else { throw AutomntIssue.authorizationRequired }
            var buffer = [UInt8](repeating: 0, count: min(count - result.count, 4096))
            let received = Darwin.read(input, &buffer, buffer.count)
            if received < 0 && errno == EINTR { continue }
            guard received > 0 else { throw AutomntIssue.authorizationRequired }
            result.append(contentsOf: buffer.prefix(received))
        }
        return result
    }
}
