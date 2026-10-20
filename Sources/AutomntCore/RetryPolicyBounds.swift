import Foundation

/// Single source of truth for the retry parameters shared by the CLI, the GUI and the
/// background evaluator. The interface must not invent its own limits, and every entry
/// point clamps and validates through these values.
public enum RetryPolicyBounds {
    public static let attemptRange = 1...10
    public static let intervalRangeMs = 100...5000
    public static let windowRangeMs = 1000...30000

    public static let defaultAttempts = 3
    public static let defaultIntervalMs = 1000
    public static let defaultWindowMs = 10000

    /// Clamps a stored policy into the shared bounds. Used by the evaluator on every
    /// read so a hand-edited configuration cannot widen the retry budget.
    public static func clamped(_ policy: RetryPolicy?) -> RetryPolicy {
        let policy = policy ?? RetryPolicy()
        return RetryPolicy(
            maxAttempts: min(max(policy.maxAttempts ?? defaultAttempts, attemptRange.lowerBound), attemptRange.upperBound),
            intervalMs: min(max(policy.intervalMs ?? defaultIntervalMs, intervalRangeMs.lowerBound), intervalRangeMs.upperBound),
            maxTotalWindowMs: min(max(policy.maxTotalWindowMs ?? defaultWindowMs, windowRangeMs.lowerBound), windowRangeMs.upperBound))
    }

    public enum Problem: String, Equatable, Sendable {
        case attemptsOutOfRange
        case intervalOutOfRange
        case windowOutOfRange
        case windowShorterThanInterval
    }

    /// Validates user input before it is written. Rejects out-of-range values instead
    /// of silently clamping, so the interface can show the field that is wrong. The
    /// window/interval relation is only reported when both values are otherwise valid,
    /// so one bad field yields one message.
    public static func problems(attempts: Int, intervalMs: Int, windowMs: Int) -> [Problem] {
        var problems: [Problem] = []
        if !attemptRange.contains(attempts) { problems.append(.attemptsOutOfRange) }
        let intervalValid = intervalRangeMs.contains(intervalMs)
        let windowValid = windowRangeMs.contains(windowMs)
        if !intervalValid { problems.append(.intervalOutOfRange) }
        if !windowValid { problems.append(.windowOutOfRange) }
        if intervalValid, windowValid, windowMs < intervalMs { problems.append(.windowShorterThanInterval) }
        return problems
    }

    public static func policy(attempts: Int, intervalMs: Int, windowMs: Int) -> RetryPolicy? {
        guard problems(attempts: attempts, intervalMs: intervalMs, windowMs: windowMs).isEmpty else { return nil }
        return RetryPolicy(maxAttempts: attempts, intervalMs: intervalMs, maxTotalWindowMs: windowMs)
    }
}
