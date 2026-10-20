import Foundation
import Testing
@testable import AutomntCore

struct RecoveryOutcomeTests {
    @Test func confirmedFailureIsIdempotentAndHealthyRecoveryRecordsBeforeBudgetReset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = UUID().uuidString
        let repository = RecoveryStateRepository(url: directory.appendingPathComponent("mount-recovery-state.plist"))
        let date = Date()
        let operationID = UUID()
        try repository.save(MountRecoveryStateFile(volumes: [key: MountRecoveryVolumeRecord(
            volumeKey: key, state: .pendingRecovery, attemptCount: 2, updatedAt: date.timeIntervalSince1970)]))
        var reserved = repository.read().file
        reserved.volumes[key]?.attemptOperationID = operationID
        try repository.save(reserved)
        let lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
        try withExtendedLifetime(lock) {
            #expect(throws: AutomntIssue.signalUnavailable) {
                try RecoveryAttemptCommit.rejected(identity: key, directory: directory, path: .unavailable, operationID: operationID)
            }
            try RecoveryAttemptCommit.rejected(identity: key, directory: directory, path: .absent, operationID: UUID())
            #expect(repository.read().file.volumes[key]?.attemptOperationID == operationID)
            #expect(repository.read().file.attempts.isEmpty)
            try RecoveryAttemptCommit.rejected(identity: key, directory: directory, path: .absent, operationID: operationID)
            try RecoveryAttemptCommit.rejected(identity: key, directory: directory, path: .absent, operationID: operationID)
            #expect(repository.read().file.attempts[key]?.count == 1)
            #expect(repository.read().file.attempts[key]?.first?.outcome == .shareRejected)
            let healthy = VolumeObservation(identity: key, status: .healthy, actualPath: directory.path, observedAt: Date())
            try RecoveryHealthCommit.apply(healthy, directory: directory, stillMounted: true)
            try RecoveryHealthCommit.apply(healthy, directory: directory, stillMounted: true)
            #expect(repository.read().file.attempts[key]?.count == 2)
            #expect(repository.read().file.attempts[key]?.last?.outcome == .mounted)
            #expect(repository.read().file.attempts[key]?.last?.sequence == 2)
            #expect(repository.read().file.volumes[key]?.attemptCount == 0)
            try RecoveryAttemptCommit.rejected(identity: UUID().uuidString, directory: directory, path: .absent, operationID: operationID)
            #expect(repository.read().file.attempts.count == 1)
        }
    }
}
