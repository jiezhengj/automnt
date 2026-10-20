import Foundation
import Darwin
import Testing
import AutomntCore
@testable import AutomntPlatform

struct VolumeHealthTests {
    @Test func expiredOrNonSMBProbeNeverAccessesDirectory() {
        let share = SMBShareConfig(name: UUID().uuidString, smbURL: "smb://\(UUID().uuidString)/\(UUID().uuidString)",
            mountPoint: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path)
        #expect(throws: AutomntIssue.timeout) { try VolumeHealthWorkerOperation.probe(share: share, deadline: .now) }
        #expect(throws: AutomntIssue.pathConflict) {
            try VolumeHealthWorkerOperation.probe(share: share, deadline: .now.advanced(by: .seconds(1)))
        }
        if case .healthy = VolumeHealthWorkerOperation.classify(0) {} else { Issue.record("successful directory access") }
        for error in [EACCES, EPERM, ENOENT, EBUSY] {
            if case .unavailable = VolumeHealthWorkerOperation.classify(error) {} else { Issue.record("ambiguous access must preserve volume") }
        }
        for error in [EIO, ENXIO, ENOTCONN, ESTALE, ETIMEDOUT] {
            if case .failed = VolumeHealthWorkerOperation.classify(error) {} else { Issue.record("explicit session failure") }
        }
    }
}
