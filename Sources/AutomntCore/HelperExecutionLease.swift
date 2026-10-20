import Foundation
import Darwin

/// A cooperative helper holds this stable lock for its entire authorized lifetime.
/// Acquiring it after registration removal proves no participating helper is alive
/// in this shared directory; it does not prove mount-worker or kernel convergence.
public final class HelperExecutionLease {
    private let lock: StableFileLock
    public init(authorizedDirectory: URL) throws {
        do {
            lock = try StableFileLock(url: authorizedDirectory.appendingPathComponent("helper-execution.lock"))
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EWOULDBLOCK) {
            throw AutomntIssue.serviceTransitionFailed
        }
    }
    public func perform<T>(_ operation: () throws -> T) rethrows -> T {
        try withExtendedLifetime(lock) { try operation() }
    }
}
