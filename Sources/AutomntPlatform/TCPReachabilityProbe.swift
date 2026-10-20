import Foundation
import Network
import AutomntCore

public struct TCPReachabilityProbe: ReachabilityProbe {
    public init() {}
    public func isReachable(host: String, port: Int, timeoutMilliseconds: Int) async throws -> Bool {
        guard !host.isEmpty, !host.contains("\0"), (1...65535).contains(port), timeoutMilliseconds > 0,
              let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw AutomntIssue.invalidConfiguration
        }
        try Task.checkCancellation()
        let attempt = TCPAttempt(host: host, port: endpointPort, milliseconds: min(timeoutMilliseconds, 30000))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { attempt.start($0) }
        } onCancel: { attempt.finish(.failure(CancellationError())) }
    }
}

/// Network callbacks and timeout share a queue; the lock also covers task cancellation
/// arriving before continuation installation. Exactly one result resumes the caller.
private final class TCPAttempt: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "org.automnt.tcp-attempt")
    private let connection: NWConnection
    private let milliseconds: Int
    private var continuation: CheckedContinuation<Bool, any Error>?
    private var result: Result<Bool, any Error>?
    private var timer: DispatchSourceTimer?

    init(host: String, port: NWEndpoint.Port, milliseconds: Int) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        self.milliseconds = milliseconds
    }

    func start(_ continuation: CheckedContinuation<Bool, any Error>) {
        let early = lock.withLock { () -> Result<Bool, any Error>? in
            if let result { return result }
            self.continuation = continuation
            return nil as Result<Bool, any Error>?
        }
        if let early { continuation.resume(with: early); return }
        queue.async { [self] in
            guard !lock.withLock({ result != nil }) else { return }
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.finish(.success(true))
                case .failed, .waiting: self?.finish(.success(false))
                case .cancelled: self?.finish(.failure(CancellationError()))
                default: break
                }
            }
            let timeout = DispatchSource.makeTimerSource(queue: queue)
            timer = timeout
            timeout.schedule(deadline: .now() + .milliseconds(milliseconds))
            timeout.setEventHandler { [weak self] in self?.finish(.success(false)) }
            timeout.resume()
            connection.start(queue: queue)
        }
    }

    func finish(_ result: Result<Bool, any Error>) {
        let completion = lock.withLock { () -> CheckedContinuation<Bool, any Error>? in
            guard self.result == nil else { return nil }
            self.result = result
            let pending = continuation
            continuation = nil
            return pending
        }
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
        completion?.resume(with: result)
    }
}
