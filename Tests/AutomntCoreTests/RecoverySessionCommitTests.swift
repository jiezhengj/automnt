import Foundation
import Testing
@testable import AutomntCore

struct RecoverySessionCommitTests {
    @Test func permitRejectsStaleSnapshotAndPendingChildWithoutChangingRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(AutomntConfig())
        let recovery = RecoveryStateRepository(url: directory.appendingPathComponent("mount-recovery-state.plist"))
        let old = RecoverySessionIdentity(network: UUID().uuidString, loginEpoch: UUID().uuidString, previous: nil)
        let key = UUID().uuidString
        let initial = MountRecoveryStateFile(sessionBoundary: old.combined, volumes: [key:
            MountRecoveryVolumeRecord(volumeKey: key, state: .suppressed, suppressionBoundary: old.combined,
                                      everHealthyMounted: true, notificationCount: 2)])
        try recovery.save(initial)
        let backend = BackendState(owner: .app, phase: .active, generation: 1, revision: snapshot.revision)
        let next = RecoverySessionIdentity(network: UUID().uuidString, loginEpoch: old.loginEpoch, previous: old.combined)
        func advance() throws {
            let permit = try EvaluationPermit(directory: directory, repository: repository, expected: snapshot,
                owner: .app, generation: 1, readBackend: { backend })
            try permit.perform { _ in
                _ = try RecoverySessionCommit.advance(directory: directory, identity: next, mountedKeys: [])
            }
        }
        do {
            let competing = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
            withExtendedLifetime(competing) {
                #expect(throws: (any Error).self) { try advance() }
                #expect(recovery.read() == .loaded(initial))
            }
        }
        let worker = WorkerOperationStore(authorizedDirectory: directory)
        let operation = try worker.begin(revision: snapshot.revision, generation: 1)
        #expect(throws: AutomntIssue.signalUnavailable) { try advance() }
        #expect(recovery.read() == .loaded(initial))
        try worker.complete(id: operation, revision: snapshot.revision, generation: 1)
        try advance()
        #expect(recovery.read().file.volumes[key]?.state == .pendingRecovery)
        #expect(recovery.read().file.sessionBoundary == next.combined)
        var draft = snapshot.configuration
        draft.automationEnabled = false
        _ = try repository.save(draft, baseRevision: snapshot.revision)
        let bytes = try PrivateAtomicFile.read(recovery.url)
        #expect(throws: AutomntIssue.configurationConflict) { try advance() }
        #expect(try PrivateAtomicFile.read(recovery.url) == bytes)
    }

    @Test func unreadableIdentityAndDamagedStateCannotReleaseProtection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = RecoveryStateRepository(url: directory.appendingPathComponent("mount-recovery-state.plist"))
        let key = UUID().uuidString
        let boundary = UUID().uuidString
        let initial = MountRecoveryStateFile(sessionBoundary: boundary, volumes: [key:
            MountRecoveryVolumeRecord(volumeKey: key, state: .suppressed, suppressionBoundary: boundary)])
        try repository.save(initial)
        let lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
        try withExtendedLifetime(lock) {
            #expect(try RecoverySessionCommit.advance(directory: directory, identity: nil, mountedKeys: []) == .loaded(initial))
            let malformed = Data(UUID().uuidString.utf8)
            try PrivateAtomicFile.replace(malformed, at: repository.url)
            #expect(throws: AutomntIssue.signalUnavailable) {
                try RecoverySessionCommit.advance(directory: directory,
                    identity: RecoverySessionIdentity(network: UUID().uuidString, loginEpoch: UUID().uuidString, previous: nil), mountedKeys: [])
            }
            #expect(try PrivateAtomicFile.read(repository.url) == malformed)
        }
    }
}
