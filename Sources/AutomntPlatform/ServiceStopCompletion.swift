import Foundation
import AutomntCore

/// A late system callback cannot resume a timed out or cancelled caller twice.
final class ServiceStopCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var result: Result<Void, any Error>?
    init() {}
    convenience init(_ continuation: CheckedContinuation<Void, any Error>) {
        self.init()
        install(continuation)
    }
    func install(_ continuation: CheckedContinuation<Void, any Error>) {
        lock.lock()
        let completed = result
        if completed == nil { self.continuation = continuation }
        lock.unlock()
        if let completed { continuation.resume(with: completed) }
    }
    func finish(_ issue: AutomntIssue?) {
        complete(issue.map { .failure($0) } ?? .success(()))
    }
    func cancel() { complete(.failure(CancellationError())) }
    private func complete(_ value: Result<Void, any Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: value)
    }
}
