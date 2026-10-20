import Foundation
import Testing
@testable import AutomntCore

struct UserEjectTests {
    @Test func confirmedUserEjectOverridesRecoveryEvidenceWithoutResettingBudgets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("mount-recovery-state.plist")
        let repository = RecoveryStateRepository(url: url)
        let identity = UUID().uuidString
        let boundary = UUID().uuidString
        try repository.save(MountRecoveryStateFile(sessionBoundary: boundary,
            volumes: [identity: MountRecoveryVolumeRecord(volumeKey: identity, state: .pendingRecovery,
                repairEjectEvidence: true, everHealthyMounted: true, attemptCount: 3, notificationCount: 2)],
            cleanupLedger: [identity: 1]))
        let store = WorkerOperationStore(authorizedDirectory: directory)
        let revision = ConfigRevision(digest: UUID().uuidString)
        let id = try store.begin(revision: revision, generation: 1)
        let lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
        try withExtendedLifetime(lock) {
            let stopped = VolumeObservation(identity: identity, status: .stopped, actualPath: nil, observedAt: Date())
            try UserEjectCommit.verifyReadable(directory: directory)
            let before = try PrivateAtomicFile.read(url)
            for path: MountPathState in [.unavailable, .occupied, .smb(identity: identity)] {
                #expect(throws: AutomntIssue.signalUnavailable) {
                    try UserEjectCommit.apply(stopped, directory: directory, path: path, operationID: id, revision: revision, generation: 1)
                }
                #expect(try PrivateAtomicFile.read(url) == before)
            }
            #expect(throws: AutomntIssue.configurationConflict) {
                try UserEjectCommit.apply(stopped, directory: directory, path: .absent, operationID: UUID(), revision: revision, generation: 1)
            }
            try UserEjectCommit.apply(stopped, directory: directory, path: .absent, operationID: id, revision: revision, generation: 1)
            let state = repository.read().file
            #expect(state.volumes[identity]?.state == .suppressed)
            #expect(state.volumes[identity]?.suppressionBoundary == boundary)
            #expect(state.volumes[identity]?.repairEjectEvidence == false)
            #expect(state.volumes[identity]?.everHealthyMounted == true)
            #expect(state.volumes[identity]?.attemptCount == 3)
            #expect(state.volumes[identity]?.notificationCount == 2)
            #expect(state.cleanupLedger[identity] == nil)
            let corrupt = Data(UUID().uuidString.utf8)
            try PrivateAtomicFile.replace(corrupt, at: url)
            #expect(throws: AutomntIssue.signalUnavailable) { try UserEjectCommit.verifyReadable(directory: directory) }
            #expect(throws: AutomntIssue.signalUnavailable) {
                try UserEjectCommit.apply(stopped, directory: directory, path: .absent, operationID: id, revision: revision, generation: 1)
            }
            #expect(try PrivateAtomicFile.read(url) == corrupt)
        }
    }
}
