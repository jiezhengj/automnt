import Foundation
import Darwin

/// Adapters must bound every call by the supplied deadline. Stopped requires both
/// registration removal and confirmed process convergence, not just a status flag.
public protocol HandoffServiceAdapter: Sendable {
    func stopAndVerify(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus
    func register(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus
    func status(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus
    /// Explicit bounded wake after durable activation; implementations must revalidate
    /// the supplied state and configuration before evaluating, never rewrite enabled.
    func requestEvaluation(state: BackendState, deadline: ContinuousClock.Instant) async throws
}

public struct HandoffCoordinator: Sendable {
    private let store: BackendStateStore
    public init(authorizedDirectory: URL) { store = BackendStateStore(authorizedDirectory: authorizedDirectory) }

    /// Only invoked after explicit user consent. The durable stopping phase prevents
    /// newly started helpers from evaluating while system calls run outside the lock.
    public func transfer(to owner: BackendState.Owner, expectedGeneration: UInt64,
                         revision: ConfigRevision, adapter: any HandoffServiceAdapter,
                         deadline: ContinuousClock.Instant) async throws -> BackendState {
        let transitionLock = try acquireTransitionLock()
        defer { withExtendedLifetime(transitionLock) {} }
        try checkDeadline(deadline)
        try checkRevision(revision)
        let previous = try store.read()
        guard previous.generation == expectedGeneration else { throw AutomntIssue.configurationConflict }
        if previous.phase == .failed {
            // Preserve the failed journal until all possibly registered identities
            // are drained. A cleanup failure must not overwrite its desired owner.
            var identities = [previous.owner]
            if let residual = previous.desiredOwner, residual != .none, residual != previous.owner {
                identities.append(residual)
            }
            for identity in identities {
                let status = try await adapter.stopAndVerify(owner: identity, deadline: deadline)
                try checkDeadline(deadline)
                guard status == .stopped else { throw AutomntIssue.serviceTransitionFailed }
            }
            _ = try store.reconcileInterruptedTransition(verifiedStatus: .stopped, expectedTransitionID: previous.transitionID)
        }
        let journal = try store.begin(desiredOwner: owner, expectedGeneration: expectedGeneration, revision: revision, verifyConfiguration: true)
        let committed: BackendState
        do {
            let stopped = try await adapter.stopAndVerify(owner: journal.previous.owner, deadline: deadline)
            try checkDeadline(deadline)
            guard stopped == .stopped else { throw AutomntIssue.serviceTransitionFailed }
            if owner == .none {
                return try store.advance(id: journal.id, to: .stopped, verifiedStatus: stopped, expectedRevision: revision)
            }
            try checkRevision(revision)
            _ = try store.advance(id: journal.id, to: .activating, verifiedStatus: stopped, expectedRevision: revision)
            let registration = try await adapter.register(owner: owner, deadline: deadline)
            try checkDeadline(deadline)
            guard registration == .enabled || registration == .requiresApproval else {
                throw AutomntIssue.serviceTransitionFailed
            }
            // Registration's return is not proof of the latest system state.
            let observed = try await adapter.status(owner: owner, deadline: deadline)
            try checkDeadline(deadline)
            try checkRevision(revision)
            committed = try commit(id: journal.id, status: observed, revision: revision)
        } catch {
            // Keep the owner non-active even if a system call had partial effects.
            // Never claim stopped or silently restart the previous service on uncertainty.
            let issue = error as? AutomntIssue ?? .serviceTransitionFailed
            _ = try store.advance(id: journal.id, to: .failed, verifiedStatus: .unavailable, failure: issue)
            throw error
        }
        if committed.phase == .active {
            try checkDeadline(deadline)
            try await adapter.requestEvaluation(state: committed, deadline: deadline)
        }
        return committed
    }

    /// Explicit crash recovery drains every identity in the durable journal. It
    /// tolerates journal-first interrupted writes and never resumes registration.
    public func recoverInterruptedTransition(id: UUID, adapter: any HandoffServiceAdapter,
                                             deadline: ContinuousClock.Instant, appOnly: Bool = false) async throws -> BackendState {
        let transitionLock = try acquireTransitionLock()
        defer { withExtendedLifetime(transitionLock) {} }
        try checkDeadline(deadline)
        let journal = try store.interruptedJournal(id: id)
        if appOnly {
            for state in [journal.previous, journal.pending, journal.priorPending].compactMap({ $0 }) {
                guard state.owner != .cli, state.desiredOwner != .cli else { throw AutomntIssue.incompatibleOwner }
            }
        }
        var identities: [BackendState.Owner] = []
        for identity in [journal.previous.owner, journal.previous.desiredOwner,
                         journal.pending.owner, journal.pending.desiredOwner].compactMap({ $0 }) {
            if identity != .none, !identities.contains(identity) { identities.append(identity) }
        }
        for identity in identities {
            let status = try await adapter.stopAndVerify(owner: identity, deadline: deadline)
            try checkDeadline(deadline)
            guard status == .stopped else { throw AutomntIssue.serviceTransitionFailed }
        }
        return try store.reconcileInterruptedTransition(verifiedStatus: .stopped, expectedTransitionID: id)
    }

    /// App-only recovery must inspect all journal identities before touching services,
    /// including journal-first writes that normal state reads intentionally reject.
    public func recoverAppInterruptedTransition(adapter: any HandoffServiceAdapter,
                                               deadline: ContinuousClock.Instant) async throws -> BackendState {
        let journal = try store.journal()
        let validated = try store.interruptedJournal(id: journal.id)
        for state in [validated.previous, validated.pending, validated.priorPending].compactMap({ $0 }) {
            guard state.owner != .cli, state.desiredOwner != .cli else { throw AutomntIssue.incompatibleOwner }
        }
        return try await recoverInterruptedTransition(id: validated.id, adapter: adapter, deadline: deadline, appOnly: true)
    }

    /// Approval is a separate foreground action; it never registers again.
    public func completeApproval(id: UUID, adapter: any HandoffServiceAdapter,
                                 deadline: ContinuousClock.Instant) async throws -> BackendState {
        let transitionLock = try acquireTransitionLock()
        defer { withExtendedLifetime(transitionLock) {} }
        try checkDeadline(deadline)
        let current = try store.read()
        guard current.transitionID == id, current.phase == .awaitingApproval,
              let owner = current.desiredOwner, owner != .none else {
            throw AutomntIssue.configurationConflict
        }
        try checkRevision(current.revision)
        let observed = try await adapter.status(owner: owner, deadline: deadline)
        try checkDeadline(deadline)
        try checkRevision(current.revision)
        if observed == .requiresApproval { return try store.read() }
        guard observed == .enabled else { throw AutomntIssue.serviceTransitionFailed }
        let committed = try store.advance(id: id, to: .active, verifiedStatus: observed, expectedRevision: current.revision)
        try checkDeadline(deadline)
        try await adapter.requestEvaluation(state: committed, deadline: deadline)
        return committed
    }

    private func commit(id: UUID, status: BackendState.ServiceStatus, revision: ConfigRevision) throws -> BackendState {
        switch status {
        case .enabled: return try store.advance(id: id, to: .active, verifiedStatus: status, expectedRevision: revision)
        case .requiresApproval: return try store.advance(id: id, to: .awaitingApproval, verifiedStatus: status, expectedRevision: revision)
        case .stopped, .unavailable: throw AutomntIssue.serviceTransitionFailed
        }
    }
    /// Separate from evaluation.lock so immediate launchd helpers can read the
    /// non-active state and exit while registration waits on system services.
    private func acquireTransitionLock() throws -> StableFileLock {
        do {
            return try StableFileLock(url: store.directory.appendingPathComponent("handoff.lock"))
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EWOULDBLOCK) {
            throw AutomntIssue.configurationConflict
        }
    }
    private func checkRevision(_ expected: ConfigRevision) throws {
        guard try FileConfigRepository(authorizedDirectory: store.directory).read().revision == expected else {
            throw AutomntIssue.configurationConflict
        }
    }
    private func checkDeadline(_ deadline: ContinuousClock.Instant) throws {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw AutomntIssue.timeout }
    }
}
