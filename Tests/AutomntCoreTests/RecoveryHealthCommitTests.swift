import Foundation
import Testing
@testable import AutomntCore

struct RecoveryHealthCommitTests {
    @Test func onlyConfirmedHealthyObservationCommitsAndSuppressionWins() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = RecoveryStateRepository(url: directory.appendingPathComponent("mount-recovery-state.plist"))
        let key = UUID().uuidString
        let initial = MountRecoveryStateFile(volumes: [key: MountRecoveryVolumeRecord(volumeKey: key,
            state: .pendingRecovery, repairEjectEvidence: true, attemptCount: 2)], cleanupLedger: [key: 1])
        try repository.save(initial)
        do {
        let lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
        try withExtendedLifetime(lock) {
            for evidence: VolumeHealthEvidence in [.failed, .unavailable] {
                let observation = RecoveryHealthPolicy.observation(identity: key, actualPath: directory.path,
                    hostReachable: true, health: evidence, observedAt: Date())
                try RecoveryHealthCommit.apply(observation, directory: directory, stillMounted: true)
                #expect(repository.read() == .loaded(initial))
            }
            let healthy = RecoveryHealthPolicy.observation(identity: key, actualPath: directory.path,
                hostReachable: true, health: .healthy, observedAt: Date())
            #expect(throws: AutomntIssue.signalUnavailable) {
                try RecoveryHealthCommit.apply(healthy, directory: directory, stillMounted: false)
            }
            try RecoveryHealthCommit.apply(healthy, directory: directory, stillMounted: true)
            var state = repository.read().file
            #expect(state.volumes[key]?.everHealthyMounted == true)
            #expect(state.volumes[key]?.state == .attached)
            #expect(state.cleanupLedger[key] == nil)
            state.volumes[key]?.state = .suppressed
            state.volumes[key]?.suppressionBoundary = UUID().uuidString
            try repository.save(state)
            try RecoveryHealthCommit.apply(healthy, directory: directory, stillMounted: true)
            #expect(repository.read() == .loaded(state))
            let malformed = Data(UUID().uuidString.utf8)
            try PrivateAtomicFile.replace(malformed, at: repository.url)
            #expect(throws: AutomntIssue.signalUnavailable) {
                try RecoveryHealthCommit.apply(healthy, directory: directory, stillMounted: true)
            }
            #expect(try PrivateAtomicFile.read(repository.url) == malformed)
        }
        }
        let worker = WorkerOperationStore(authorizedDirectory: directory)
        _ = try worker.begin(revision: ConfigRevision(digest: UUID().uuidString), generation: 1)
        let healthy = RecoveryHealthPolicy.observation(identity: key, actualPath: directory.path,
            hostReachable: true, health: .healthy, observedAt: Date())
        #expect(throws: AutomntIssue.signalUnavailable) {
            try RecoveryHealthCommit.apply(healthy, directory: directory, stillMounted: true)
        }
    }
}
