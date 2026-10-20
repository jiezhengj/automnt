import Foundation
import Testing
@testable import AutomntCore

struct RetryPolicyBoundsTests {
    @Test func clampingFillsDefaultsAndEnforcesSharedRanges() {
        let empty = RetryPolicyBounds.clamped(nil)
        #expect(empty.maxAttempts == 3)
        #expect(empty.intervalMs == 1000)
        #expect(empty.maxTotalWindowMs == 10000)

        let extreme = RetryPolicyBounds.clamped(RetryPolicy(maxAttempts: 99, intervalMs: 1, maxTotalWindowMs: 999_999))
        #expect(extreme.maxAttempts == 10)
        #expect(extreme.intervalMs == 100)
        #expect(extreme.maxTotalWindowMs == 30000)

        let low = RetryPolicyBounds.clamped(RetryPolicy(maxAttempts: 0, intervalMs: 0, maxTotalWindowMs: 0))
        #expect(low.maxAttempts == 1)
        #expect(low.intervalMs == 100)
        #expect(low.maxTotalWindowMs == 1000)
    }

    @Test func userInputOutsideTheRangeIsRejectedRatherThanSilentlyClamped() {
        #expect(RetryPolicyBounds.problems(attempts: 3, intervalMs: 1000, windowMs: 10000).isEmpty)
        #expect(RetryPolicyBounds.problems(attempts: 0, intervalMs: 1000, windowMs: 10000) == [.attemptsOutOfRange])
        #expect(RetryPolicyBounds.problems(attempts: 11, intervalMs: 1000, windowMs: 10000) == [.attemptsOutOfRange])
        #expect(RetryPolicyBounds.problems(attempts: 3, intervalMs: 99, windowMs: 10000) == [.intervalOutOfRange])
        #expect(RetryPolicyBounds.problems(attempts: 3, intervalMs: 1000, windowMs: 999) == [.windowOutOfRange])
        // A window shorter than the interval can never complete a second attempt.
        #expect(RetryPolicyBounds.problems(attempts: 3, intervalMs: 5000, windowMs: 1000).contains(.windowShorterThanInterval))
        #expect(RetryPolicyBounds.policy(attempts: 3, intervalMs: 1000, windowMs: 10000)?.maxAttempts == 3)
        #expect(RetryPolicyBounds.policy(attempts: 0, intervalMs: 1000, windowMs: 10000) == nil)
    }

    @Test func evaluatorUsesTheSharedBoundsForAHandEditedPolicy() {
        // A configuration file with an absurd retry budget must not widen the run.
        let runner = EvaluationRetryRunner(policy: RetryPolicy(maxAttempts: 500, intervalMs: 1, maxTotalWindowMs: 10_000_000))
        var calls = 0
        _ = runner.run { calls += 1; return false }
        #expect(calls == 10)

        let single = EvaluationRetryRunner(policy: RetryPolicy(maxAttempts: 0, intervalMs: 1, maxTotalWindowMs: 0))
        var singleCalls = 0
        _ = single.run { singleCalls += 1; return false }
        #expect(singleCalls == 1)
    }
}
