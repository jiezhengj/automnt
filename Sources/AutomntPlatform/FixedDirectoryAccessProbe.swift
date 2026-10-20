import Foundation
import Darwin
import AutomntCore

/// Explicit runtime diagnostics for the real canonical directory. Does not create
/// targets, evaluate mounts, change backend ownership or register a service.
public enum FixedDirectoryAccessProbe {
    public static func run(prepareDirectory: Bool = false) throws -> String {
        let store = PermissionStore()
        let directory = try prepareDirectory ? store.prepareFixedSettings() : store.resolve()
        let canonical = PermissionStore.expectedDirectory.standardizedFileURL
        guard directory.url.standardizedFileURL == canonical,
              !directory.scoped, PermissionStore.hasFixedDirectoryEntitlement else {
            throw AutomntIssue.authorizationRequired
        }
        let probe = canonical.appendingPathComponent(".automnt-access-probe-" + UUID().uuidString)
        guard probe.deletingLastPathComponent() == canonical,
              probe.standardizedFileURL == probe,
              probe.lastPathComponent.hasPrefix(".automnt-access-probe-") else {
            throw AutomntIssue.authorizationRequired
        }
        // Only this uniquely-created auxiliary probe file is removed. Production
        // configuration and its stable lock are never replaced or deleted here.
        defer {
            if probe.deletingLastPathComponent() == canonical,
               probe.standardizedFileURL == probe,
               probe.resolvingSymlinksInPath() == probe {
                _ = unlink(probe.path)
            }
            withExtendedLifetime(directory) {}
        }
        let first = Data(UUID().uuidString.utf8)
        let second = Data(UUID().uuidString.utf8)
        try PrivateAtomicFile.replace(first, at: probe)
        guard try PrivateAtomicFile.read(probe) == first else { throw AutomntIssue.invalidConfiguration }
        var before = stat()
        guard lstat(probe.path, &before) == 0, before.st_mode & 0o777 == 0o600 else {
            throw AutomntIssue.authorizationRequired
        }
        try PrivateAtomicFile.replace(second, at: probe)
        var after = stat()
        guard try PrivateAtomicFile.read(probe) == second,
              lstat(probe.path, &after) == 0,
              before.st_ino != after.st_ino,
              after.st_mode & 0o777 == 0o600 else { throw AutomntIssue.invalidConfiguration }

        let lockURL = canonical.appendingPathComponent("config.lock")
        let inode: ino_t = try {
            let lock = try StableFileLock(url: lockURL)
            return try withExtendedLifetime(lock) {
                var info = stat()
                guard lstat(lockURL.path, &info) == 0, info.st_mode & 0o777 == 0o600 else {
                    throw AutomntIssue.authorizationRequired
                }
                do {
                    let competing = try StableFileLock(url: lockURL)
                    withExtendedLifetime(competing) {}
                    throw AutomntIssue.configurationConflict
                } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EWOULDBLOCK) {
                    return info.st_ino
                }
            }
        }()
        do {
            let reacquired = try StableFileLock(url: lockURL)
            try withExtendedLifetime(reacquired) {
                var info = stat()
                guard lstat(lockURL.path, &info) == 0, info.st_ino == inode else {
                    throw AutomntIssue.configurationConflict
                }
            }
        }
        let configuration: String
        do {
            _ = try FileConfigRepository(authorizedDirectory: canonical).read()
            configuration = "readable"
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == ENOENT {
            configuration = "not-created"
        }
        var root = stat()
        guard lstat(canonical.path, &root) == 0 else { throw AutomntIssue.authorizationRequired }
        return "fixed-directory-probe: uid=\(getuid()) parent=\(getppid()) own-entitlement=true scoped=false directory-mode=\(String(root.st_mode & 0o777, radix: 8)) file-mode=600 atomic-replace=true lock-contention=true stable-lock-inode=\(inode) configuration=\(configuration)\n"
    }
}
