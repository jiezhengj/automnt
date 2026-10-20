import Foundation

public enum RecoveryNotificationPolicy {
    /// Consume before delivery; denial/foreground suppression must not accrue catch-up notices.
    public static func consume(_ record: inout MountRecoveryVolumeRecord) -> Bool {
        guard record.notificationCount >= 0, record.notificationCount < 2 else { return false }
        record.notificationCount += 1
        return true
    }

    public static func merge(failed: Set<String>, recovered: Set<String>,
                             state: inout MountRecoveryStateFile) -> FailureNotification? {
        var eligible = Set<String>()
        for key in failed.subtracting(recovered).sorted() {
            var record = state.volumes[key] ?? MountRecoveryVolumeRecord(volumeKey: key)
            guard record.state != .suppressed, consume(&record) else { continue }
            state.volumes[key] = record
            eligible.insert(key)
        }
        return FailureNotification(failed: failed, recovered: recovered, eligible: eligible)
    }

    /// Caller retains EvaluationPermit. Unknown state or pending work cannot grant a notice budget.
    public static func commit(directory: URL, failed: Set<String>, recovered: Set<String>) throws -> FailureNotification? {
        try WorkerOperationStore(authorizedDirectory: directory).verifyIdle()
        let repository = RecoveryStateRepository(url: directory.appendingPathComponent("mount-recovery-state.plist"))
        let loaded = repository.read()
        guard loaded.isReadable else { throw AutomntIssue.signalUnavailable }
        var state = loaded.file
        let notification = merge(failed: failed, recovered: recovered, state: &state)
        if state != loaded.file { try repository.save(state) }
        return notification
    }
}
