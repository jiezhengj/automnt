import Foundation
import Darwin
import AutomntCore

/// Directory access may block in SMB; invoke only inside the supervised child.
public enum VolumeHealthWorkerOperation {
    public static func probe(share: SMBShareConfig, deadline: ContinuousClock.Instant) throws -> VolumeObservation {
        guard ContinuousClock.now < deadline else { throw AutomntIssue.timeout }
        guard let identity = smbResourceIdentity(share.smbURL),
              NetFSWorkerOperation.mountedIdentity(at: share.mountPoint) == identity else {
            throw AutomntIssue.pathConflict
        }
        let evidence: VolumeHealthEvidence
        if let directory = opendir(share.mountPoint) {
            errno = 0
            _ = readdir(directory)
            let failure = errno
            closedir(directory)
            evidence = classify(failure)
        } else { evidence = classify(errno) }
        guard ContinuousClock.now < deadline else { throw AutomntIssue.timeout }
        guard NetFSWorkerOperation.mountedIdentity(at: share.mountPoint) == identity else { throw AutomntIssue.pathConflict }
        return RecoveryHealthPolicy.observation(identity: identity,
            actualPath: URL(fileURLWithPath: share.mountPoint).standardizedFileURL.path,
            hostReachable: true, health: evidence, observedAt: Date())
    }

    public static func classify(_ failure: Int32) -> VolumeHealthEvidence {
        if failure == 0 { return .healthy }
        if [EIO, ENXIO, ENOTCONN, ESTALE, ETIMEDOUT].contains(failure) { return .failed }
        return .unavailable
    }
}
