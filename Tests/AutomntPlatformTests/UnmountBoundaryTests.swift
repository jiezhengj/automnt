import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

struct UnmountBoundaryTests {
    @Test func expiredAndNonSMBPathsNeverSubmitUnmount() throws {
        let volume = VolumeObservation(identity: UUID().uuidString, status: .healthy,
            actualPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
            observedAt: Date())
        #expect(throws: AutomntIssue.timeout) {
            try DiskArbitrationWorkerOperation.unmount(volume, deadline: ContinuousClock.now.advanced(by: .seconds(-1)))
        }
        #expect(throws: AutomntIssue.pathConflict) {
            try DiskArbitrationWorkerOperation.unmount(volume, deadline: ContinuousClock.now.advanced(by: .seconds(1)))
        }
        let root = VolumeObservation(identity: volume.identity, status: .healthy, actualPath: "/", observedAt: Date())
        #expect(throws: AutomntIssue.pathConflict) {
            try DiskArbitrationWorkerOperation.unmount(root, deadline: ContinuousClock.now.advanced(by: .seconds(1)))
        }
    }
    @Test func cancelledOperationNeverSubmitsUnmount() async {
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let volume = VolumeObservation(identity: UUID().uuidString, status: .healthy, actualPath: "/", observedAt: Date())
            do {
                _ = try DiskArbitrationWorkerOperation.unmount(volume, deadline: ContinuousClock.now.advanced(by: .seconds(1)))
                Issue.record("Cancelled operation returned success")
            } catch { #expect(error is CancellationError) }
        }
        await operation.value
    }
}
