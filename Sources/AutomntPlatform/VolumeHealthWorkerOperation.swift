import Foundation
import Darwin
import AutomntCore

/// Verifies a mounted volume. Runs inside the sandboxed app/helper process, so it never
/// blocks on a child pipe; the caller keeps the whole round bounded.
public enum VolumeHealthWorkerOperation {
    public static func probe(share: SMBShareConfig, deadline: ContinuousClock.Instant) throws -> VolumeObservation {
        guard ContinuousClock.now < deadline else { throw AutomntIssue.timeout }
        guard let identity = smbResourceIdentity(share.smbURL),
              NetFSWorkerOperation.mountedIdentity(at: share.mountPoint) == identity else {
            throw AutomntIssue.pathConflict
        }
        let failure: Int32
        if let directory = opendir(share.mountPoint) {
            errno = 0
            _ = readdir(directory)
            failure = errno
            closedir(directory)
        } else { failure = errno }
        let evidence = classify(failure)
        guard ContinuousClock.now < deadline else { throw AutomntIssue.timeout }
        guard NetFSWorkerOperation.mountedIdentity(at: share.mountPoint) == identity else { throw AutomntIssue.pathConflict }
        return RecoveryHealthPolicy.observation(identity: identity,
            actualPath: URL(fileURLWithPath: share.mountPoint).standardizedFileURL.path,
            hostReachable: true,
            health: Self.interpreted(evidence: evidence, failure: failure),
            observedAt: Date())
    }

    /// App Sandbox cannot read a network volume the process mounted: the denial is a
    /// sandbox EACCES/EPERM, not a server failure. The kernel mount identity above is the
    /// observable proof; content access stays with the user's own (non-sandboxed) apps.
    static func interpreted(evidence: VolumeHealthEvidence, failure: Int32) -> VolumeHealthEvidence {
        if evidence == .unavailable, [EACCES, EPERM].contains(failure),
           PermissionStore.hasAppSandboxEntitlement {
            return .healthy
        }
        return evidence
    }

    public static func classify(_ failure: Int32) -> VolumeHealthEvidence {
        if failure == 0 { return .healthy }
        if [EIO, ENXIO, ENOTCONN, ESTALE, ETIMEDOUT].contains(failure) { return .failed }
        return .unavailable
    }
}
