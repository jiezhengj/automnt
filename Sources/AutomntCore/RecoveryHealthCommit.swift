import Foundation

public enum RecoveryHealthCommit {
    /// Within EvaluationPermit.perform, after child exit, validated response and idle intent.
    public static func apply(_ observation: VolumeObservation, directory: URL, stillMounted: Bool) throws {
        try WorkerOperationStore(authorizedDirectory: directory).verifyIdle()
        guard stillMounted else { throw AutomntIssue.signalUnavailable }
        guard observation.status == .healthy, observation.issue == nil else { return }
        let repository = RecoveryStateRepository(url: directory.appendingPathComponent("mount-recovery-state.plist"))
        let loaded = repository.read()
        guard loaded.isReadable else { throw AutomntIssue.signalUnavailable }
        var state = loaded.file
        var record = state.volumes[observation.identity] ?? MountRecoveryVolumeRecord(volumeKey: observation.identity)
        // A concurrently recorded user intent wins over a delayed health response.
        guard record.state != .suppressed else { return }
        if record.attemptCount > 0 {
            let attempt = RecoveryAttempt(timestamp: observation.observedAt.timeIntervalSince1970,
                outcome: .mounted, sequence: record.attemptCount)
            state.attempts[observation.identity] = Array(((state.attempts[observation.identity] ?? []) + [attempt]).suffix(10))
        }
        record.everHealthyMounted = true
        record.state = .attached
        record.suppressionBoundary = nil
        record.repairEjectEvidence = false
        record.lastAttemptAt = nil
        record.attemptOperationID = nil
        record.attemptCount = 0
        record.notificationCount = 0
        record.updatedAt = observation.observedAt.timeIntervalSince1970
        state.volumes[observation.identity] = record
        state.cleanupLedger.removeValue(forKey: observation.identity)
        if state != loaded.file { try repository.save(state) }
    }
}
