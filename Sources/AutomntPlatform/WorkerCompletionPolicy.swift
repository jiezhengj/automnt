import Foundation
import AutomntCore

public enum WorkerCompletionPolicy {
    /// A response alone cannot prove process exit or kernel convergence.
    public static func mayComplete(request: WorkerMountRequest, response: WorkerMountResponse,
                                   exitedNormally: Bool, path: MountPathState) -> Bool {
        guard exitedNormally, !response.requiresReconciliation,
              (try? WorkerPipeProtocol.validate(response: response, for: request)) != nil else { return false }
        if let issue = response.issue {
            return request.operation == .mount && issue == .shareRejected && path == .absent
        }
        guard response.observation != nil else { return false }
        switch request.operation {
        case .mount, .health:
            guard let identity = smbResourceIdentity(request.share.smbURL) else { return false }
            return path == .smb(identity: identity)
        case .unmount, .cleanup:
            return path == .absent
        }
    }
}
