import Foundation

public enum UserEjectCommit {
    /// Caller holds evaluation.lock inside the pending unmount worker.
    /// Damaged recovery state must be rejected before requesting an eject.
    public static func verifyReadable(directory: URL) throws {
        guard repository(directory).read().isReadable else { throw AutomntIssue.signalUnavailable }
    }

    public static func apply(_ observation: VolumeObservation, directory: URL, path: MountPathState,
                             operationID: UUID, revision: ConfigRevision, generation: UInt64) throws {
        try WorkerOperationStore(authorizedDirectory: directory).verifyPending(
            id: operationID, revision: revision, generation: generation)
        guard observation.status == .stopped, observation.actualPath == nil, observation.issue == nil,
              path == .absent else { throw AutomntIssue.signalUnavailable }
        let repository = repository(directory)
        let loaded = repository.read()
        guard loaded.isReadable else { throw AutomntIssue.signalUnavailable }
        var state = loaded.file
        var record = state.volumes[observation.identity] ?? MountRecoveryVolumeRecord(volumeKey: observation.identity)
        record.state = .suppressed
        record.suppressionBoundary = state.sessionBoundary
        record.repairEjectEvidence = false
        record.updatedAt = observation.observedAt.timeIntervalSince1970
        state.volumes[observation.identity] = record
        state.cleanupLedger.removeValue(forKey: observation.identity)
        try repository.save(state)
    }

    /// Caller holds the pending worker's evaluation lock. Failed requests preserve eject intent.
    public static func resumeAfterManualMount(identity: String, directory: URL, path: MountPathState) throws {
        guard path == .smb(identity: identity) else { throw AutomntIssue.signalUnavailable }
        let repository = repository(directory)
        let loaded = repository.read()
        guard loaded.isReadable else { throw AutomntIssue.signalUnavailable }
        var state = loaded.file
        guard var record = state.volumes[identity] else { return }
        record.state = .attached
        record.suppressionBoundary = nil
        record.attemptCount = 0
        record.lastAttemptAt = nil
        record.attemptOperationID = nil
        state.volumes[identity] = record
        try repository.save(state)
    }

    private static func repository(_ directory: URL) -> RecoveryStateRepository {
        RecoveryStateRepository(url: directory.appendingPathComponent("mount-recovery-state.plist"))
    }
}
