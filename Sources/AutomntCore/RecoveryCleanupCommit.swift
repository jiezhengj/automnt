import Foundation

public enum RecoveryCleanupCommit {
    public static func permits(configuration: AutomntConfig, recovery: MountRecoveryStoreLoad,
                               identity: String, health: VolumeHealthEvidence) -> Bool {
        guard configuration.isAutomationEnabled, configuration.isAutoMountRecoveryEnabled,
              recovery.isReadable, recovery.file.volumes[identity]?.state != .suppressed else { return false }
        if case .failed = health { return true }
        return false
    }

    /// Caller holds EvaluationPermit; invoke only following validated normal child exit.
    public static func apply(_ observation: VolumeObservation, directory: URL,
                             configuration: AutomntConfig, path: MountPathState) throws {
        try WorkerOperationStore(authorizedDirectory: directory).verifyIdle()
        guard observation.status == .stopped, observation.actualPath == nil, observation.issue == nil,
              path == .absent else { throw AutomntIssue.signalUnavailable }
        let repository = RecoveryStateRepository(url: directory.appendingPathComponent("mount-recovery-state.plist"))
        let loaded = repository.read()
        guard permits(configuration: configuration, recovery: loaded, identity: observation.identity, health: .failed) else {
            throw AutomntIssue.configurationConflict
        }
        var state = loaded.file
        var record = state.volumes[observation.identity] ?? MountRecoveryVolumeRecord(volumeKey: observation.identity)
        record.state = .pendingRecovery
        record.suppressionBoundary = nil
        record.updatedAt = observation.observedAt.timeIntervalSince1970
        state.volumes[observation.identity] = record
        state.cleanupLedger[observation.identity] = record.updatedAt
        try repository.save(state)
    }
}
