import Foundation
import Testing
@testable import AutomntCore

struct RecoveryCleanupTests {
    @Test func cleanupRequiresReadableExplicitFailureAndEnabledRecovery() {
        let key = UUID().uuidString
        var config = AutomntConfig()
        #expect(RecoveryCleanupCommit.permits(configuration: config, recovery: .absent, identity: key, health: .failed))
        for health: VolumeHealthEvidence in [.healthy, .unavailable] {
            #expect(!RecoveryCleanupCommit.permits(configuration: config, recovery: .absent, identity: key, health: health))
        }
        #expect(!RecoveryCleanupCommit.permits(configuration: config, recovery: .corrupt(reason: "unreadable"), identity: key, health: .failed))
        let protected = MountRecoveryStateFile(volumes: [key: MountRecoveryVolumeRecord(volumeKey: key, state: .suppressed)])
        #expect(!RecoveryCleanupCommit.permits(configuration: config, recovery: .loaded(protected), identity: key, health: .failed))
        config.autoMountRecovery = false
        #expect(!RecoveryCleanupCommit.permits(configuration: config, recovery: .absent, identity: key, health: .failed))
        config.autoMountRecovery = true
        config.automationEnabled = false
        #expect(!RecoveryCleanupCommit.permits(configuration: config, recovery: .absent, identity: key, health: .failed))
    }

    @Test func onlyConfirmedAbsenceCommitsLedgerAndPendingRejectsIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = UUID().uuidString
        let repository = RecoveryStateRepository(url: directory.appendingPathComponent("mount-recovery-state.plist"))
        let initial = MountRecoveryStateFile(volumes: [key: MountRecoveryVolumeRecord(volumeKey: key,
            everHealthyMounted: true, attemptCount: 1)])
        try repository.save(initial)
        let stopped = VolumeObservation(identity: key, status: .stopped, actualPath: nil, observedAt: Date())
        do {
            let lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
            try withExtendedLifetime(lock) {
                for path: MountPathState in [.occupied, .unavailable, .smb(identity: key)] {
                    #expect(throws: AutomntIssue.signalUnavailable) {
                        try RecoveryCleanupCommit.apply(stopped, directory: directory, configuration: AutomntConfig(), path: path)
                    }
                    #expect(repository.read() == .loaded(initial))
                }
                try RecoveryCleanupCommit.apply(stopped, directory: directory, configuration: AutomntConfig(), path: .absent)
                let saved = repository.read().file
                #expect(saved.volumes[key]?.state == .pendingRecovery)
                #expect(saved.volumes[key]?.everHealthyMounted == true)
                #expect(saved.volumes[key]?.attemptCount == 1)
                #expect(saved.cleanupLedger[key] == stopped.observedAt.timeIntervalSince1970)
                #expect(BaselineMountDecision.decide(identity: key, path: .absent, recovery: .loaded(saved),
                    configuration: AutomntConfig(), allowRecovery: true,
                    now: Date(timeIntervalSince1970: saved.volumes[key]!.updatedAt + 1)) == .mount)
                var suppressed = saved
                suppressed.volumes[key]?.state = .suppressed
                suppressed.volumes[key]?.suppressionBoundary = UUID().uuidString
                try repository.save(suppressed)
                #expect(throws: AutomntIssue.configurationConflict) {
                    try RecoveryCleanupCommit.apply(stopped, directory: directory, configuration: AutomntConfig(), path: .absent)
                }
                #expect(repository.read() == .loaded(suppressed))
                let malformed = Data(UUID().uuidString.utf8)
                try PrivateAtomicFile.replace(malformed, at: repository.url)
                #expect(throws: AutomntIssue.configurationConflict) {
                    try RecoveryCleanupCommit.apply(stopped, directory: directory, configuration: AutomntConfig(), path: .absent)
                }
                #expect(try PrivateAtomicFile.read(repository.url) == malformed)
            }
        }
        let store = WorkerOperationStore(authorizedDirectory: directory)
        _ = try store.begin(revision: ConfigRevision(digest: UUID().uuidString), generation: 1)
        #expect(throws: AutomntIssue.signalUnavailable) {
            try RecoveryCleanupCommit.apply(stopped, directory: directory, configuration: AutomntConfig(), path: .absent)
        }
    }
}
