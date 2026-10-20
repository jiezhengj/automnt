import Foundation

public enum RecoveryAttemptCommit {
    /// Caller holds EvaluationPermit; only a normally exited, definitively rejected
    /// mount with confirmed absent path may record a failure. Never records baseline calls.
    public static func rejected(identity: String, directory: URL, path: MountPathState,
                                operationID: UUID, observedAt: Date = Date()) throws {
        try WorkerOperationStore(authorizedDirectory: directory).verifyIdle()
        guard path == .absent else { throw AutomntIssue.signalUnavailable }
        let repository = RecoveryStateRepository(url: directory.appendingPathComponent("mount-recovery-state.plist"))
        let loaded = repository.read()
        guard loaded.isReadable else { throw AutomntIssue.signalUnavailable }
        var state = loaded.file
        guard let record = state.volumes[identity], record.state == .pendingRecovery,
              record.attemptCount > 0, record.attemptOperationID == operationID else { return }
        let history = state.attempts[identity] ?? []
        state.volumes[identity]?.attemptOperationID = nil
        state.attempts[identity] = Array((history + [RecoveryAttempt(
            timestamp: max(observedAt.timeIntervalSince1970, record.updatedAt),
            outcome: .shareRejected, sequence: record.attemptCount)]).suffix(10))
        try repository.save(state)
    }

    /// Caller holds evaluation.lock and has revalidated the pending operation and mount decision.
    /// Persist before NetFS so interrupted/failed calls consume a bounded session attempt.
    public static func reserve(identity: String, directory: URL, configuration: AutomntConfig,
                               operationID: UUID? = nil, observedAt: Date = Date()) throws {
        let repository = RecoveryStateRepository(url: directory.appendingPathComponent("mount-recovery-state.plist"))
        let loaded = repository.read()
        guard loaded.isReadable else { throw AutomntIssue.signalUnavailable }
        var state = loaded.file
        var record = state.volumes[identity] ?? MountRecoveryVolumeRecord(volumeKey: identity)
        let signal = judgeRecoverySignal(volumeKey: identity, presentInMountTable: false,
            hostReachable: true, record: record, cleanupLedger: state.cleanupLedger, stateReadable: true)
        guard signal != .neverMounted else { return }
        guard record.state != .suppressed,
              MissingVolumeRecoveryPolicy.mayMount(signal: signal, enabled: configuration.isAutoMountRecoveryEnabled),
              record.attemptCount < min(max(configuration.retryPolicy?.maxAttempts ?? 3, 1), 10) else {
            throw AutomntIssue.configurationConflict
        }
        guard RecoveryRetryInterval.permits(record: record, policy: configuration.retryPolicy, now: observedAt) else {
            throw AutomntIssue.configurationConflict
        }
        record.lastAttemptAt = observedAt.timeIntervalSince1970
        record.attemptOperationID = operationID
        record.attemptCount += 1
        record.state = .pendingRecovery
        record.updatedAt = observedAt.timeIntervalSince1970
        state.volumes[identity] = record
        try repository.save(state)
    }
}
