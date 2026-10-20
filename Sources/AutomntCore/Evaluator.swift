import Foundation
import Darwin

public struct EvaluationRetryRunner: Sendable {
    public let policy: RetryPolicy
    public init(policy: RetryPolicy = RetryPolicy()) { self.policy = policy }

    public func run(deadline: ContinuousClock.Instant,
                    block: (ContinuousClock.Instant) async throws -> Bool) async throws -> Bool {
        let clock = ContinuousClock()
        let policy = RetryPolicyBounds.clamped(self.policy)
        let attempts = policy.maxAttempts ?? RetryPolicyBounds.defaultAttempts
        let interval = policy.intervalMs ?? RetryPolicyBounds.defaultIntervalMs
        let window = policy.maxTotalWindowMs ?? RetryPolicyBounds.defaultWindowMs
        let end = min(deadline, clock.now.advanced(by: .milliseconds(window)))
        for attempt in 1...attempts {
            try Task.checkCancellation()
            guard clock.now < end else { return false }
            if try await block(end) { return true }
            guard attempt < attempts else { return false }
            let wake = clock.now.advanced(by: .milliseconds(interval))
            guard wake < end else { return false }
            try await clock.sleep(until: wake)
        }
        return false
    }

    public func run(block: () -> Bool) -> Bool {
        let policy = RetryPolicyBounds.clamped(self.policy)
        let attempts = policy.maxAttempts ?? RetryPolicyBounds.defaultAttempts
        let interval = policy.intervalMs ?? RetryPolicyBounds.defaultIntervalMs
        let window = policy.maxTotalWindowMs ?? RetryPolicyBounds.defaultWindowMs
        let started = ContinuousClock.now
        for attempt in 1...attempts {
            if block() { return true }
            if attempt == attempts { break }
            let elapsed = started.duration(to: .now)
            if elapsed + .milliseconds(interval) > .milliseconds(window) { break }
            usleep(useconds_t(interval * 1000))
        }
        return false
    }
}

public enum HostPriorityEvaluator {
    /// One host's bounded reachability probe under the shared retry policy.
    public static func isReachable(_ host: HostConfig,
                                   configuration: AutomntConfig,
                                   deadline: ContinuousClock.Instant,
                                   probe: any ReachabilityProbe) async throws -> Bool {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { return false }
        return try await EvaluationRetryRunner(policy: configuration.retryPolicy ?? RetryPolicy())
            .run(deadline: deadline) { end in
                let remaining = ContinuousClock.now.duration(to: end).components
                let milliseconds = remaining.seconds * 1000 + remaining.attoseconds / 1_000_000_000_000_000
                let budget = min(max(host.timeoutMs, 1), Int(max(milliseconds, 1)))
                return try await probe.isReachable(host: host.host, port: host.port, timeoutMilliseconds: budget)
            }
    }

    /// Enabled hosts in saved order that answer within the deadline.
    ///
    /// `first_reachable` stops at the first answer; `all_reachable` keeps probing the
    /// remaining hosts in the same order. Probing never runs in parallel and never
    /// exceeds the bounded evaluation window.
    public static func reachableHosts(in configuration: AutomntConfig,
                                      deadline: ContinuousClock.Instant,
                                      probe: any ReachabilityProbe,
                                      stopAfterFirst: Bool) async throws -> [HostConfig] {
        guard configuration.isAutomationEnabled else { return [] }
        var reachable: [HostConfig] = []
        for host in configuration.hosts where host.enabled {
            guard ContinuousClock.now < deadline else { break }
            if try await isReachable(host, configuration: configuration, deadline: deadline, probe: probe) {
                reachable.append(host)
                if stopAfterFirst { break }
            }
        }
        return reachable
    }

    public static func firstReachable(in configuration: AutomntConfig,
                                      deadline: ContinuousClock.Instant,
                                      probe: any ReachabilityProbe) async throws -> HostConfig? {
        try await reachableHosts(in: configuration, deadline: deadline, probe: probe,
            stopAfterFirst: true).first
    }

    /// A share failure cannot cause fallback: select the host before mounting.
    public static func firstReachable(in configuration: AutomntConfig,
                                      probe: (HostConfig) -> Bool) -> HostConfig? {
        guard configuration.isAutomationEnabled else { return nil }
        for host in configuration.hosts where host.enabled {
            if EvaluationRetryRunner(policy: configuration.retryPolicy ?? RetryPolicy()).run(block: { probe(host) }) {
                return host
            }
        }
        return nil
    }
}
