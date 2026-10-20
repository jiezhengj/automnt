import Foundation

/// Durable minimum spacing across separate helper launches. Scheduling remains separate.
public enum RecoveryRetryInterval {
    public static func permits(record: MountRecoveryVolumeRecord?, policy: RetryPolicy?,
                               now: Date) -> Bool {
        guard let record, record.attemptCount > 0 else { return true }
        // Older schema-1 records only have updatedAt; retain their conservative spacing.
        let attemptedAt = record.lastAttemptAt ?? record.updatedAt
        guard attemptedAt.isFinite else { return false }
        let interval = Double(min(max(policy?.intervalMs ?? 1000, 100), 5000)) / 1000
        // A wall-clock rollback delays retries conservatively; it never spends attempts early.
        return now.timeIntervalSince1970 - attemptedAt >= interval
    }
}
