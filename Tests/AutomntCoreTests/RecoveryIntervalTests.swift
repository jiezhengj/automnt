import Foundation
import Testing
@testable import AutomntCore

struct RecoveryIntervalTests {
    @Test func waitingDoesNotConsumeBudgetAndClampsConfiguredInterval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = UUID().uuidString
        var config = AutomntConfig()
        config.autoMountRecovery = true
        let repo = RecoveryStateRepository(url: directory.appendingPathComponent("mount-recovery-state.plist"))
        try repo.save(MountRecoveryStateFile(volumes: [key: MountRecoveryVolumeRecord(volumeKey: key,
            state: .pendingRecovery, attemptCount: 1, updatedAt: 100)]))
        #expect(BaselineMountDecision.decide(identity: key, path: .absent, recovery: repo.read(),
            configuration: config, allowRecovery: true, now: Date(timeIntervalSince1970: 100.5)) == .deferred)
        let lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
        try withExtendedLifetime(lock) {
            let bytes = try PrivateAtomicFile.read(repo.url)
            #expect(throws: AutomntIssue.configurationConflict) {
                try RecoveryAttemptCommit.reserve(identity: key, directory: directory, configuration: config,
                    observedAt: Date(timeIntervalSince1970: 99))
            }
            #expect(try PrivateAtomicFile.read(repo.url) == bytes)
            try RecoveryAttemptCommit.reserve(identity: key, directory: directory, configuration: config,
                observedAt: Date(timeIntervalSince1970: 101))
            #expect(repo.read().file.volumes[key]?.attemptCount == 2)
            #expect(repo.read().file.volumes[key]?.lastAttemptAt == 101)
            var changed = repo.read().file
            changed.volumes[key]?.updatedAt = 200
            try repo.save(changed)
            #expect(!RecoveryRetryInterval.permits(record: repo.read().file.volumes[key], policy: nil,
                now: Date(timeIntervalSince1970: 101.5)))
            #expect(RecoveryRetryInterval.permits(record: repo.read().file.volumes[key], policy: nil,
                now: Date(timeIntervalSince1970: 102)))
        }
        let record = MountRecoveryVolumeRecord(volumeKey: key, attemptCount: 1, updatedAt: 100)
        #expect(!RecoveryRetryInterval.permits(record: record, policy: RetryPolicy(intervalMs: 99999), now: Date(timeIntervalSince1970: 104)))
        #expect(RecoveryRetryInterval.permits(record: record, policy: RetryPolicy(intervalMs: 99999), now: Date(timeIntervalSince1970: 105)))
        #expect(RecoveryRetryInterval.permits(record: nil, policy: nil, now: Date()))
    }
}
