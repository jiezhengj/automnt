import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

struct WorkerCompletionTests {
    @Test func responseRequiresNormalExitAndMatchingKernelState() {
        let host = HostConfig(host: UUID().uuidString)
        let url = "smb://\(host.host)/\(UUID().uuidString)"
        let identity = smbResourceIdentity(url)!
        let share = SMBShareConfig(name: UUID().uuidString, smbURL: url, mountPoint: deriveStandardMountPoint(from: url)!)
        for operation: WorkerOperation in [.mount, .health, .unmount, .cleanup] {
            let request = WorkerMountRequest(host: host, share: share,
                expiresAtUptime: ProcessInfo.processInfo.systemUptime + 1,
                revision: ConfigRevision(digest: UUID().uuidString), generation: 1, operation: operation)
            let removed = operation == .unmount || operation == .cleanup
            let observation = VolumeObservation(identity: identity,
                status: removed ? .stopped : operation == .health ? .healthy : .evaluating,
                actualPath: removed ? nil : share.mountPoint, observedAt: Date())
            let response = WorkerMountResponse(observation: observation)
            let expected: MountPathState = removed ? .absent : .smb(identity: identity)
            #expect(WorkerCompletionPolicy.mayComplete(request: request, response: response, exitedNormally: true, path: expected))
            #expect(!WorkerCompletionPolicy.mayComplete(request: request, response: response, exitedNormally: false, path: expected))
            for path: MountPathState in [.occupied, .unavailable, .smb(identity: UUID().uuidString), removed ? .smb(identity: identity) : .absent] {
                #expect(!WorkerCompletionPolicy.mayComplete(request: request, response: response, exitedNormally: true, path: path))
            }
            #expect(!WorkerCompletionPolicy.mayComplete(request: request,
                response: WorkerMountResponse(observation: observation, requiresReconciliation: true), exitedNormally: true, path: expected))
            #expect(!WorkerCompletionPolicy.mayComplete(request: request, response: WorkerMountResponse(), exitedNormally: true, path: expected))
        }
    }

    @Test func onlyConfirmedAbsentMountRejectionCanCompleteAnError() {
        let host = HostConfig(host: UUID().uuidString)
        let url = "smb://\(host.host)/\(UUID().uuidString)"
        let share = SMBShareConfig(name: UUID().uuidString, smbURL: url, mountPoint: deriveStandardMountPoint(from: url)!)
        for operation: WorkerOperation in [.mount, .health, .unmount, .cleanup] {
            let request = WorkerMountRequest(host: host, share: share,
                expiresAtUptime: ProcessInfo.processInfo.systemUptime + 1,
                revision: ConfigRevision(digest: UUID().uuidString), generation: 1, operation: operation)
            let rejected = WorkerMountResponse(issue: .shareRejected)
            #expect(WorkerCompletionPolicy.mayComplete(request: request, response: rejected, exitedNormally: true, path: .absent) == (operation == .mount))
            for path: MountPathState in [.unavailable, .occupied, .smb(identity: smbResourceIdentity(url)!)] {
                #expect(!WorkerCompletionPolicy.mayComplete(request: request, response: rejected, exitedNormally: true, path: path))
            }
            for issue: AutomntIssue in [.timeout, .signalUnavailable, .authorizationRequired, .volumeBusy, .pathConflict] {
                #expect(!WorkerCompletionPolicy.mayComplete(request: request, response: WorkerMountResponse(issue: issue), exitedNormally: true, path: .absent))
            }
            #expect(!WorkerCompletionPolicy.mayComplete(request: request, response: rejected, exitedNormally: false, path: .absent))
        }
    }
}
