import Testing
import AutomntCore
@testable import AutomntPlatform

struct ServiceStopCompletionTests {
    @Test func lateSuccessCannotOverrideTimeoutOrResumeTwice() async {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let completion = ServiceStopCompletion(continuation)
                completion.finish(.timeout)
                completion.finish(nil)
                completion.finish(.serviceTransitionFailed)
            }
            Issue.record("Timeout must survive late completion")
        } catch { #expect(error as? AutomntIssue == .timeout) }
    }
    @Test func cancellationBeforeContinuationInstallationSurvivesLateSuccess() async {
        let completion = ServiceStopCompletion()
        completion.cancel()
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                completion.install(continuation)
                completion.finish(nil)
            }
            Issue.record("Cancellation must survive installation race")
        } catch { #expect(error is CancellationError) }
    }
    @Test func cancellationAfterInstallationIgnoresLateSystemCallback() async {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let completion = ServiceStopCompletion(continuation)
                completion.cancel()
                completion.finish(nil)
            }
            Issue.record("Cancelled system wait must fail")
        } catch { #expect(error is CancellationError) }
    }
    @Test func successfulCompletionIgnoresLateTimeout() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let completion = ServiceStopCompletion(continuation)
            completion.finish(nil)
            completion.finish(.timeout)
        }
    }
}
