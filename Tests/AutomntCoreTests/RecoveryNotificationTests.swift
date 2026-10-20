import Foundation
import Testing
@testable import AutomntCore

struct RecoveryNotificationTests {
    @Test func mergedNoticeConsumesOnlyUnrecoveredUnprotectedBudget() throws {
        let failed = UUID().uuidString
        let recovered = UUID().uuidString
        let protected = UUID().uuidString
        var state = MountRecoveryStateFile(volumes: [protected:
            MountRecoveryVolumeRecord(volumeKey: protected, state: .suppressed)])
        for _ in 0..<2 {
            let notice = RecoveryNotificationPolicy.merge(failed: [failed, recovered, protected], recovered: [recovered], state: &state)
            #expect(notice?.count == 1)
            let bytes = try JSONEncoder().encode(notice)
            for key in [failed, recovered, protected] { #expect(bytes.range(of: Data(key.utf8)) == nil) }
        }
        #expect(state.volumes[failed]?.notificationCount == 2)
        #expect(state.volumes[recovered] == nil)
        #expect(state.volumes[protected]?.notificationCount == 0)
        let before = state
        #expect(RecoveryNotificationPolicy.merge(failed: [failed], recovered: [], state: &state) == nil)
        #expect(state == before)
        var invalid = MountRecoveryVolumeRecord(volumeKey: UUID().uuidString, notificationCount: -1)
        #expect(!RecoveryNotificationPolicy.consume(&invalid))
    }

    @Test func budgetPersistsAndCorruptStateCannotBeReplaced() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = UUID().uuidString
        let repository = RecoveryStateRepository(url: directory.appendingPathComponent("mount-recovery-state.plist"))
        let lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
        try withExtendedLifetime(lock) {
            #expect(try RecoveryNotificationPolicy.commit(directory: directory, failed: [key], recovered: [])?.count == 1)
            #expect(repository.read().file.volumes[key]?.notificationCount == 1)
            try RecoveryHealthCommit.apply(VolumeObservation(identity: key, status: .healthy, actualPath: directory.path,
                observedAt: Date()), directory: directory, stillMounted: true)
            #expect(repository.read().file.volumes[key]?.notificationCount == 0)
            let bad = Data(UUID().uuidString.utf8)
            try PrivateAtomicFile.replace(bad, at: repository.url)
            #expect(throws: AutomntIssue.signalUnavailable) {
                try RecoveryNotificationPolicy.commit(directory: directory, failed: [key], recovered: [])
            }
            #expect(try PrivateAtomicFile.read(repository.url) == bad)
        }
    }
}
