import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

struct BackgroundRetryTests {
    @Test func callerDeadlinePreventsSchedulingBeyondItsWindow() async throws {
        var rounds = 0
        _ = try await BackgroundRetryScheduler.run(policy: RetryPolicy(intervalMs: 5000),
            deadline: ContinuousClock.now.advanced(by: .milliseconds(100))) {
                rounds += 1
                return BackgroundEvaluationSummary(retrySuggested: true)
            }
        #expect(rounds == 1)
        do {
            _ = try await BackgroundRetryScheduler.run(policy: nil, deadline: ContinuousClock.now) {
                rounds += 1
                return BackgroundEvaluationSummary()
            }
            Issue.record("Expired deadline must reject first round")
        } catch { #expect(error as? AutomntIssue == .timeout) }
        #expect(rounds == 1)
    }

    @Test func configurationChangeDuringRetryStopsWithoutFurtherRounds() async throws {
        var rounds = 0
        do {
            _ = try await BackgroundRetryScheduler.run(policy: RetryPolicy(intervalMs: 100)) {
                rounds += 1
                if rounds == 2 { throw AutomntIssue.configurationConflict }
                return BackgroundEvaluationSummary(retrySuggested: true)
            }
            Issue.record("A changed configuration must terminate the scheduling run")
        } catch {
            #expect(error as? AutomntIssue == .configurationConflict)
        }
        #expect(rounds == 2)
    }

    @Test func mixedShareSummaryRetainsFailuresAndSuccessesAcrossRetry() async throws {
        let failed = UUID().uuidString
        let healthy = UUID().uuidString
        var rounds = 0
        let summary = try await BackgroundRetryScheduler.run(policy: RetryPolicy(maxAttempts: 2, intervalMs: 100)) {
            rounds += 1
            return BackgroundEvaluationSummary(observations: [
                VolumeObservation(identity: failed, status: .failed, actualPath: nil,
                    observedAt: Date(), issue: .shareRejected),
                VolumeObservation(identity: healthy, status: .healthy, actualPath: nil, observedAt: Date())
            ], issue: .shareRejected, retrySuggested: true)
        }
        #expect(rounds == 2)
        #expect(summary.observations.map(\.identity) == [failed, healthy])
        #expect(summary.issue == .shareRejected)
    }

    @Test func retriesOnlyExplicitSuggestionAndCapsBaselineFailures() async throws {
        var count = 0
        let result = try await BackgroundRetryScheduler.run(policy: RetryPolicy(maxAttempts: 2, intervalMs: 100)) {
            count += 1
            return BackgroundEvaluationSummary(issue: .shareRejected, retrySuggested: true)
        }
        #expect(count == 2)
        #expect(result.issue == .shareRejected)
        count = 0
        _ = try await BackgroundRetryScheduler.run(policy: nil) {
            count += 1
            return BackgroundEvaluationSummary(issue: .timeout)
        }
        #expect(count == 1)
        count = 0
        _ = try await BackgroundRetryScheduler.run(policy: RetryPolicy(intervalMs: 5000, maxTotalWindowMs: 1000)) {
            count += 1
            return BackgroundEvaluationSummary(retrySuggested: true)
        }
        #expect(count == 1)
    }
}
