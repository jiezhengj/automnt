import Foundation
import AutomntCore

/// Runs only after an external trigger, with a bounded scheduling window and no idle polling.
public enum BackgroundRetryScheduler {
    public static func run(policy: RetryPolicy?, deadline: ContinuousClock.Instant? = nil, isolation: isolated (any Actor)? = #isolation,
                           evaluate: () async throws -> BackgroundEvaluationSummary) async throws -> BackgroundEvaluationSummary {
        let clock = ContinuousClock()
        let window = min(max(policy?.maxTotalWindowMs ?? 10000, 1000), 30000)
        let interval = min(max(policy?.intervalMs ?? 1000, 100), 5000)
        let policyEnd = clock.now.advanced(by: .milliseconds(window))
        let end = deadline.map { min($0, policyEnd) } ?? policyEnd
        try Task.checkCancellation()
        guard clock.now < end else { throw AutomntIssue.timeout }
        // Bounds baseline failures too, which do not consume recovery-state attempts.
        let limit = min(max(policy?.maxAttempts ?? 3, 1), 10)
        var summary = try await evaluate()
        for _ in 1..<limit {
            guard summary.retrySuggested == true else { break }
            let next = clock.now.advanced(by: .milliseconds(interval))
            guard next < end else { break }
            try await clock.sleep(until: next)
            try Task.checkCancellation()
            guard clock.now < end else { break }
            summary = try await evaluate()
        }
        return summary
    }
}
