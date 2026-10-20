import Foundation

public struct BackendTransitionJournal: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public let id: UUID
    public let previous: BackendState
    public var pending: BackendState
    public var failure: AutomntIssue?
    /// The state immediately before the latest journal-first commit.
    public var priorPending: BackendState? = nil

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id, previous, pending, failure
        case priorPending = "prior_pending"
    }
}

/// Durable transitions use evaluation.lock, the same exclusion as mounting.
/// Service registration and permission UI occur outside this short critical section.
public struct BackendStateStore: Sendable {
    public let directory: URL
    public init(authorizedDirectory: URL) { directory = authorizedDirectory }
    private var stateURL: URL { directory.appendingPathComponent("backend-state.plist") }
    private var journalURL: URL { directory.appendingPathComponent("transition-journal.plist") }

    public func read() throws -> BackendState {
        let state = try PropertyListDecoder().decode(BackendState.self, from: PrivateAtomicFile.read(stateURL))
        guard state.schemaVersion == 1 else { throw AutomntIssue.incompatibleOwner }
        do {
            let transition = try journal()
            guard transition.pending == state else { throw AutomntIssue.serviceTransitionFailed }
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == 2 {
            guard state.transitionID == nil else { throw AutomntIssue.serviceTransitionFailed }
        }
        return state
    }

    public func journal() throws -> BackendTransitionJournal {
        let value = try PropertyListDecoder().decode(BackendTransitionJournal.self, from: PrivateAtomicFile.read(journalURL))
        guard value.schemaVersion == 1, value.previous.schemaVersion == 1,
              value.pending.schemaVersion == 1 else { throw AutomntIssue.incompatibleOwner }
        guard value.previous.generation < UInt64.max,
              value.pending.generation == value.previous.generation + 1,
              value.pending.transitionID == value.id,
              value.pending.desiredOwner != nil else { throw AutomntIssue.serviceTransitionFailed }
        if let prior = value.priorPending, prior != value.previous {
            guard prior.schemaVersion == 1, prior.transitionID == value.id,
                  prior.generation == value.pending.generation,
                  prior.revision == value.pending.revision,
                  prior.desiredOwner == value.pending.desiredOwner else {
                throw AutomntIssue.serviceTransitionFailed
            }
        }
        return value
    }

    public func initialize(revision: ConfigRevision) throws -> BackendState {
        let lock = try operationLock()
        return try withExtendedLifetime(lock) {
            do { return try read() }
            catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == 2 {
                let state = BackendState(owner: .none, phase: .stopped, generation: 0, revision: revision)
                try write(state, to: stateURL)
                return state
            }
        }
    }

    public func begin(desiredOwner: BackendState.Owner, expectedGeneration: UInt64,
                      revision: ConfigRevision,
                      verifyConfiguration: Bool = false) throws -> BackendTransitionJournal {
        if verifyConfiguration {
            return try FileConfigRepository(authorizedDirectory: directory).withRevision(revision) {
                try begin(desiredOwner: desiredOwner, expectedGeneration: expectedGeneration, revision: revision)
            }
        }
        let lock = try operationLock()
        return try withExtendedLifetime(lock) {
            let previous = try read()
            guard previous.generation == expectedGeneration,
                  previous.phase == .active || previous.phase == .stopped || previous.phase == .failed,
                  previous.generation < UInt64.max else { throw AutomntIssue.configurationConflict }
            let id = UUID()
            var pending = BackendState(owner: previous.owner, phase: .stopping,
                                       generation: previous.generation + 1, revision: revision)
            pending.desiredOwner = desiredOwner
            pending.transitionID = id
            let journal = BackendTransitionJournal(id: id, previous: previous, pending: pending)
            // Journal first: an interrupted write remains detectable and cannot silently activate.
            try write(journal, to: journalURL)
            try write(pending, to: stateURL)
            return journal
        }
    }

    public func advance(id: UUID, to phase: BackendState.Phase,
                        verifiedStatus: BackendState.ServiceStatus,
                        failure: AutomntIssue? = nil,
                        expectedRevision: ConfigRevision? = nil) throws -> BackendState {
        if let expectedRevision {
            return try FileConfigRepository(authorizedDirectory: directory).withRevision(expectedRevision) {
                try advance(id: id, to: phase, verifiedStatus: verifiedStatus, failure: failure)
            }
        }
        let lock = try operationLock()
        return try withExtendedLifetime(lock) {
            var journal = try self.journal()
            let state = try read()
            guard journal.id == id, state.transitionID == id,
                  state.generation == journal.pending.generation,
                  state == journal.pending else { throw AutomntIssue.configurationConflict }
            let allowed: Bool
            switch (state.phase, phase) {
            case (.stopping, .activating), (.stopping, .stopped): allowed = verifiedStatus == .stopped
            case (.activating, .awaitingApproval): allowed = verifiedStatus == .requiresApproval
            case (.activating, .active), (.awaitingApproval, .active): allowed = verifiedStatus == .enabled
            case (.stopping, .failed), (.activating, .failed), (.awaitingApproval, .failed): allowed = true
            default: allowed = false
            }
            guard allowed else { throw AutomntIssue.serviceTransitionFailed }
            if phase == .activating || phase == .active || phase == .stopped {
                try WorkerOperationStore(authorizedDirectory: directory).verifyIdle()
            }
            journal.priorPending = state
            journal.pending.phase = phase
            journal.pending.lastVerifiedServiceStatus = verifiedStatus
            journal.failure = failure
            if phase == .active { journal.pending.owner = state.desiredOwner ?? .none }
            if phase == .stopped { journal.pending.owner = .none }
            try write(journal, to: journalURL)
            try write(journal.pending, to: stateURL)
            return journal.pending
        }
    }

    /// Validate recovery eligibility before touching system services.
    public func interruptedJournal(id: UUID) throws -> BackendTransitionJournal {
        let lock = try operationLock()
        return try withExtendedLifetime(lock) {
            let journal = try self.journal()
            guard journal.id == id else { throw AutomntIssue.configurationConflict }
            let state = try PropertyListDecoder().decode(BackendState.self, from: PrivateAtomicFile.read(stateURL))
            guard state.schemaVersion == 1,
                  state == journal.pending || state == journal.previous || state == journal.priorPending else {
                throw AutomntIssue.serviceTransitionFailed
            }
            if state == journal.pending && (state.phase == .active || state.phase == .stopped) {
                throw AutomntIssue.configurationConflict
            }
            return journal
        }
    }

    /// Crash repair only converges to stopped after the adapter proved all relevant
    /// services and in-flight workers stopped. It never promotes journal intent to active.
    public func reconcileInterruptedTransition(verifiedStatus: BackendState.ServiceStatus,
                                               expectedTransitionID: UUID? = nil) throws -> BackendState {
        guard verifiedStatus == .stopped else { throw AutomntIssue.serviceTransitionFailed }
        let lock = try operationLock()
        return try withExtendedLifetime(lock) {
            try WorkerOperationStore(authorizedDirectory: directory).verifyIdle()
            var journal = try self.journal()
            if let expectedTransitionID, journal.id != expectedTransitionID {
                throw AutomntIssue.configurationConflict
            }
            let diskState = try PropertyListDecoder().decode(BackendState.self, from: PrivateAtomicFile.read(stateURL))
            guard diskState.schemaVersion == 1,
                  diskState == journal.previous || diskState == journal.pending || diskState == journal.priorPending else {
                throw AutomntIssue.serviceTransitionFailed
            }
            journal.priorPending = diskState
            journal.pending.owner = .none
            journal.pending.phase = .stopped
            journal.pending.lastVerifiedServiceStatus = .stopped
            journal.failure = .serviceTransitionFailed
            try write(journal, to: journalURL)
            try write(journal.pending, to: stateURL)
            return journal.pending
        }
    }

    private func operationLock() throws -> StableFileLock {
        try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
    }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try PrivateAtomicFile.replace(encoder.encode(value), at: url)
    }
}
