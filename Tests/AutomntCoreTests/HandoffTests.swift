import Foundation
import Testing
@testable import AutomntCore

private actor HandoffProbe: HandoffServiceAdapter {
    var calls: [String] = []
    var stoppedOwners: [BackendState.Owner] = []
    let stopped: BackendState.ServiceStatus
    let evaluationIssue: AutomntIssue?
    var observed: BackendState.ServiceStatus
    init(stopped: BackendState.ServiceStatus = .stopped, observed: BackendState.ServiceStatus = .enabled, evaluationIssue: AutomntIssue? = nil) {
        self.evaluationIssue = evaluationIssue
        self.stopped = stopped; self.observed = observed
    }
    func stopAndVerify(owner: BackendState.Owner, deadline: ContinuousClock.Instant) -> BackendState.ServiceStatus {
        calls.append("stop"); stoppedOwners.append(owner); return stopped
    }
    func register(owner: BackendState.Owner, deadline: ContinuousClock.Instant) -> BackendState.ServiceStatus {
        calls.append("register"); return .enabled
    }
    func status(owner: BackendState.Owner, deadline: ContinuousClock.Instant) -> BackendState.ServiceStatus {
        calls.append("status"); return observed
    }
    func requestEvaluation(state: BackendState, deadline: ContinuousClock.Instant) throws {
        calls.append("evaluate")
        #expect(state.phase == .active)
        if let evaluationIssue { throw evaluationIssue }
    }
    func approve() { observed = .enabled }
}

private actor CompetingHandoffProbe: HandoffServiceAdapter {
    let directory: URL
    let revision: ConfigRevision
    var rejected = false
    init(directory: URL, revision: ConfigRevision) {
        self.directory = directory; self.revision = revision
    }
    func stopAndVerify(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus {
        let generation = try BackendStateStore(authorizedDirectory: directory).read().generation
        do {
            _ = try await HandoffCoordinator(authorizedDirectory: directory).transfer(to: .none, expectedGeneration: generation, revision: revision, adapter: HandoffProbe(), deadline: deadline)
        } catch {
            guard error as? AutomntIssue == .configurationConflict else { throw error }
            rejected = true
        }
        return .stopped
    }
    func register(owner: BackendState.Owner, deadline: ContinuousClock.Instant) -> BackendState.ServiceStatus { .enabled }
    func status(owner: BackendState.Owner, deadline: ContinuousClock.Instant) -> BackendState.ServiceStatus { .enabled }
    func requestEvaluation(state: BackendState, deadline: ContinuousClock.Instant) throws {
        #expect(try BackendStateStore(authorizedDirectory: directory).read() == state)
    }
}

private actor SavingDuringStopProbe: HandoffServiceAdapter {
    let directory: URL
    var calls: [String] = []
    init(directory: URL) { self.directory = directory }
    func stopAndVerify(owner: BackendState.Owner, deadline: ContinuousClock.Instant) throws -> BackendState.ServiceStatus {
        calls.append("stop")
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.read()
        var configuration = snapshot.configuration
        configuration.autoMountRecovery = false
        _ = try repository.save(configuration, baseRevision: snapshot.revision)
        return .stopped
    }
    func register(owner: BackendState.Owner, deadline: ContinuousClock.Instant) -> BackendState.ServiceStatus {
        calls.append("register"); return .enabled
    }
    func status(owner: BackendState.Owner, deadline: ContinuousClock.Instant) -> BackendState.ServiceStatus { .enabled }
    func requestEvaluation(state: BackendState, deadline: ContinuousClock.Instant) { calls.append("evaluate") }
}

struct HandoffTests {
    @Test func saveDuringStopRejectsStaleCompletionAndPreservesNewConfiguration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: snapshot.revision)
        let probe = SavingDuringStopProbe(directory: directory)
        await #expect(throws: AutomntIssue.configurationConflict) {
            try await HandoffCoordinator(authorizedDirectory: directory).transfer(to: .none,
                expectedGeneration: 0, revision: snapshot.revision, adapter: probe,
                deadline: .now.advanced(by: .seconds(5)))
        }
        #expect(await probe.calls == ["stop"])
        #expect(try store.read().phase == .failed)
        let latest = try repository.read()
        #expect(latest.revision != snapshot.revision)
        #expect(latest.configuration.autoMountRecovery == false)
        #expect(latest.configuration.isAutomationEnabled)
    }

    @Test func activeConfigurationChangeRepairsThroughStopAndCanDisableWithoutRegistering() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let initial = try repository.create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: initial.revision)
        let coordinator = HandoffCoordinator(authorizedDirectory: directory)
        let first = try await coordinator.transfer(to: .app, expectedGeneration: 0, revision: initial.revision,
            adapter: HandoffProbe(), deadline: .now.advanced(by: .seconds(5)))
        var configuration = initial.configuration
        configuration.autoMountRecovery = false
        let edited = try repository.save(configuration, baseRevision: initial.revision)
        let repair = HandoffProbe()
        let repaired = try await coordinator.transfer(to: .app, expectedGeneration: first.generation, revision: edited.revision,
            adapter: repair, deadline: .now.advanced(by: .seconds(5)))
        #expect(await repair.calls == ["stop", "register", "status", "evaluate"])
        #expect(repaired.revision == edited.revision)
        configuration.automationEnabled = false
        let disabled = try repository.save(configuration, baseRevision: edited.revision)
        let stop = HandoffProbe()
        let stopped = try await coordinator.transfer(to: .none, expectedGeneration: repaired.generation, revision: disabled.revision,
            adapter: stop, deadline: .now.advanced(by: .seconds(5)))
        #expect(await stop.calls == ["stop"])
        #expect(stopped.owner == .none && stopped.phase == .stopped)
        #expect(try repository.read().configuration.autoMountRecovery == false)
    }
    @Test func evaluationFailureDoesNotUndoVerifiedActiveOwnership() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let revision = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig()).revision
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: revision)
        let probe = HandoffProbe(evaluationIssue: .offline)
        do {
            _ = try await HandoffCoordinator(authorizedDirectory: directory).transfer(to: .app, expectedGeneration: 0, revision: revision, adapter: probe, deadline: ContinuousClock.now.advanced(by: .seconds(5)))
            Issue.record("Evaluation issue should reach caller")
        } catch { #expect(error as? AutomntIssue == .offline) }
        #expect(try store.read().phase == .active)
        #expect(try store.read().owner == .app)
        #expect(try store.journal().failure == nil)
        #expect(await probe.calls == ["stop", "register", "status", "evaluate"])
    }

    @Test func interruptedActiveCommitRecoversMatchingPriorPendingOnly() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let revision = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig()).revision
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: revision)
        let journal = try store.begin(desiredOwner: .app, expectedGeneration: 0, revision: revision, verifyConfiguration: true)
        let activating = try store.advance(id: journal.id, to: .activating, verifiedStatus: .stopped)
        _ = try store.advance(id: journal.id, to: .active, verifiedStatus: .enabled, expectedRevision: revision)
        #expect(try store.journal().priorPending == activating)
        let coordinator = HandoffCoordinator(authorizedDirectory: directory)
        let probe = HandoffProbe()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        do {
            _ = try await coordinator.recoverInterruptedTransition(id: journal.id, adapter: probe, deadline: deadline)
            Issue.record("A committed active service must not be stopped by recovery")
        } catch { #expect(error as? AutomntIssue == .configurationConflict) }
        #expect(await probe.calls.isEmpty)
        try PrivateAtomicFile.replace(PropertyListEncoder().encode(activating), at: directory.appendingPathComponent("backend-state.plist"))
        #expect(throws: AutomntIssue.serviceTransitionFailed) { try store.read() }
        let recovered = try await coordinator.recoverInterruptedTransition(id: journal.id, adapter: probe, deadline: deadline)
        #expect(recovered.phase == .stopped && recovered.owner == .none)
        #expect(await probe.calls == ["stop"])
        #expect(try store.read() == recovered)
    }

    @Test func interruptedActivationDrainsIdentityAndNeverRegisters() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let revision = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig()).revision
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: revision)
        let journal = try store.begin(desiredOwner: .app, expectedGeneration: 0, revision: revision, verifyConfiguration: true)
        let activating = try store.advance(id: journal.id, to: .activating, verifiedStatus: .stopped, expectedRevision: revision)
        let coordinator = HandoffCoordinator(authorizedDirectory: directory)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        let uncertain = HandoffProbe(stopped: .unavailable)
        do {
            _ = try await coordinator.recoverInterruptedTransition(id: journal.id, adapter: uncertain, deadline: deadline)
            Issue.record("Unverified recovery must preserve journal")
        } catch { #expect(error as? AutomntIssue == .serviceTransitionFailed) }
        #expect(try store.read() == activating)
        let probe = HandoffProbe()
        let recovered = try await coordinator.recoverInterruptedTransition(id: journal.id, adapter: probe, deadline: deadline)
        #expect(recovered.phase == .stopped && recovered.owner == .none)
        #expect(recovered.generation == activating.generation)
        #expect(await probe.stoppedOwners == [.app])
        #expect(await probe.calls == ["stop"])
        do {
            _ = try await coordinator.recoverInterruptedTransition(id: journal.id, adapter: probe, deadline: deadline)
            Issue.record("Committed stopped state must not be recovered again")
        } catch { #expect(error as? AutomntIssue == .configurationConflict) }
        #expect(await probe.calls == ["stop"])
    }

    @Test func inconsistentJournalRejectsRecoveryBeforeServiceCalls() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let revision = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig()).revision
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: revision)
        let original = try store.begin(desiredOwner: .app, expectedGeneration: 0, revision: revision)
        for mutation in 0..<3 {
            var journal = original
            switch mutation {
            case 0: journal.pending.transitionID = UUID()
            case 1: journal.pending.generation += 1
            default:
                var prior = journal.pending
                prior.revision = ConfigRevision(digest: UUID().uuidString)
                journal.priorPending = prior
            }
            // Malformed crash metadata only; business configuration is product-generated.
            try PrivateAtomicFile.replace(PropertyListEncoder().encode(journal), at: directory.appendingPathComponent("transition-journal.plist"))
            try PrivateAtomicFile.replace(PropertyListEncoder().encode(journal.pending), at: directory.appendingPathComponent("backend-state.plist"))
            let probe = HandoffProbe()
            await #expect(throws: AutomntIssue.serviceTransitionFailed) {
                try await HandoffCoordinator(authorizedDirectory: directory).recoverAppInterruptedTransition(
                    adapter: probe, deadline: .now.advanced(by: .seconds(5)))
            }
            #expect(await probe.calls.isEmpty)
        }
    }

    @Test func appOnlyJournalRecoveryRejectsCLIBeforeAnyServiceCalls() async throws {
        for owner in [BackendState.Owner.cli, .app] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let revision = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig()).revision
            let store = BackendStateStore(authorizedDirectory: directory)
            _ = try store.initialize(revision: revision)
            let journal = try store.begin(desiredOwner: owner, expectedGeneration: 0, revision: revision)
            try PrivateAtomicFile.replace(PropertyListEncoder().encode(journal.previous), at: directory.appendingPathComponent("backend-state.plist"))
            let probe = HandoffProbe()
            let coordinator = HandoffCoordinator(authorizedDirectory: directory)
            if owner == .cli {
                await #expect(throws: AutomntIssue.incompatibleOwner) {
                    try await coordinator.recoverAppInterruptedTransition(adapter: probe, deadline: .now.advanced(by: .seconds(5)))
                }
                #expect(await probe.calls.isEmpty)
                #expect(try store.journal() == journal)
            } else {
                let state = try await coordinator.recoverAppInterruptedTransition(adapter: probe, deadline: .now.advanced(by: .seconds(5)))
                #expect(state.owner == .none && state.phase == .stopped)
                #expect(await probe.calls == ["stop"])
            }
        }
    }

    @Test func journalFirstInterruptedWriteRecoversWithoutNormalStateRead() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let revision = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig()).revision
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: revision)
        let journal = try store.begin(desiredOwner: .cli, expectedGeneration: 0, revision: revision, verifyConfiguration: true)
        // Reproduce the existing journal-first write boundary using the store's
        // generated previous state. This is transition metadata, not business config.
        try PrivateAtomicFile.replace(PropertyListEncoder().encode(journal.previous), at: directory.appendingPathComponent("backend-state.plist"))
        #expect(throws: AutomntIssue.serviceTransitionFailed) { try store.read() }
        let probe = HandoffProbe()
        let recovered = try await HandoffCoordinator(authorizedDirectory: directory).recoverInterruptedTransition(id: journal.id, adapter: probe, deadline: ContinuousClock.now.advanced(by: .seconds(5)))
        #expect(recovered.phase == .stopped && recovered.generation == 1)
        #expect(try store.read() == recovered)
        #expect(await probe.stoppedOwners == [.cli])
    }

    @Test func transitionLockSurvivesAsyncAdapterCall() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let revision = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig()).revision
        _ = try BackendStateStore(authorizedDirectory: directory).initialize(revision: revision)
        let probe = CompetingHandoffProbe(directory: directory, revision: revision)
        let result = try await HandoffCoordinator(authorizedDirectory: directory).transfer(to: .app, expectedGeneration: 0, revision: revision, adapter: probe, deadline: ContinuousClock.now.advanced(by: .seconds(5)))
        #expect(await probe.rejected)
        #expect(result.phase == .active && result.generation == 1)
    }

    @Test func competingTransitionRejectsBeforeTouchingServicesAndReleasesForRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let revision = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig()).revision
        let store = BackendStateStore(authorizedDirectory: directory)
        let initial = try store.initialize(revision: revision)
        let coordinator = HandoffCoordinator(authorizedDirectory: directory)
        let probe = HandoffProbe()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        do {
            let lock = try StableFileLock(url: directory.appendingPathComponent("handoff.lock"))
            defer { withExtendedLifetime(lock) {} }
            do {
                _ = try await coordinator.transfer(to: .app, expectedGeneration: 0, revision: revision, adapter: probe, deadline: deadline)
                Issue.record("A competing handoff must be rejected")
            } catch { #expect(error as? AutomntIssue == .configurationConflict) }
            #expect(await probe.calls.isEmpty)
            #expect(try store.read() == initial)
        }
        #expect(try await coordinator.transfer(to: .app, expectedGeneration: 0, revision: revision, adapter: probe, deadline: deadline).phase == .active)
    }

    @Test func transferUsesFreshStatusAndApprovalDoesNotRegisterAgain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let revision = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig()).revision
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: revision)
        let coordinator = HandoffCoordinator(authorizedDirectory: directory)
        let probe = HandoffProbe(observed: .requiresApproval)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        let pending = try await coordinator.transfer(to: .app, expectedGeneration: 0, revision: revision, adapter: probe, deadline: deadline)
        #expect(pending.phase == .awaitingApproval)
        #expect(pending.owner == .none)
        #expect(await probe.calls == ["stop", "register", "status"])
        let id = try #require(pending.transitionID)
        #expect(try await coordinator.completeApproval(id: id, adapter: probe, deadline: deadline).phase == .awaitingApproval)
        await probe.approve()
        #expect(try await coordinator.completeApproval(id: id, adapter: probe, deadline: deadline).owner == .app)
        #expect(await probe.calls == ["stop", "register", "status", "status", "status", "evaluate"])
    }

    @Test func changedConfigurationBlocksApprovalWithoutAdditionalSystemCalls() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: snapshot.revision)
        let coordinator = HandoffCoordinator(authorizedDirectory: directory)
        let probe = HandoffProbe(observed: .requiresApproval)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        let pending = try await coordinator.transfer(to: .app, expectedGeneration: 0, revision: snapshot.revision, adapter: probe, deadline: deadline)
        var edited = snapshot.configuration
        edited.automationEnabled = false
        _ = try repository.save(edited, baseRevision: snapshot.revision)
        await probe.approve()
        do {
            _ = try await coordinator.completeApproval(id: #require(pending.transitionID), adapter: probe, deadline: deadline)
            Issue.record("A stale transition must not activate changed configuration")
        } catch { #expect(error as? AutomntIssue == .configurationConflict) }
        #expect(try store.read() == pending)
        #expect(await probe.calls == ["stop", "register", "status"])
    }

    @Test func failedRegistrationResidualIsStoppedBeforeDisable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let revision = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig()).revision
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: revision)
        let coordinator = HandoffCoordinator(authorizedDirectory: directory)
        let failedProbe = HandoffProbe(observed: .unavailable)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        do {
            _ = try await coordinator.transfer(to: .app, expectedGeneration: 0, revision: revision, adapter: failedProbe, deadline: deadline)
            Issue.record("Unknown status cannot activate")
        } catch { #expect(error as? AutomntIssue == .serviceTransitionFailed) }
        let failed = try store.read()
        #expect(failed.owner == .none && failed.desiredOwner == .app)
        let blockedCleanup = HandoffProbe(stopped: .unavailable)
        do {
            _ = try await coordinator.transfer(to: .none, expectedGeneration: failed.generation, revision: revision, adapter: blockedCleanup, deadline: deadline)
            Issue.record("Cleanup uncertainty must preserve residual identity")
        } catch { #expect(error as? AutomntIssue == .serviceTransitionFailed) }
        #expect(try store.read() == failed)
        let cleanup = HandoffProbe()
        let stopped = try await coordinator.transfer(to: .none, expectedGeneration: failed.generation, revision: revision, adapter: cleanup, deadline: deadline)
        #expect(stopped.owner == .none && stopped.phase == .stopped)
        #expect(await cleanup.stoppedOwners == [.none, .app, .none])
        #expect(await cleanup.calls == ["stop", "stop", "stop"])
    }

    @Test func unverifiedStopNeverRegistersAndLeavesFailedNonActiveState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let revision = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig()).revision
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: revision)
        let probe = HandoffProbe(stopped: .unavailable)
        do {
            _ = try await HandoffCoordinator(authorizedDirectory: directory).transfer(to: .app, expectedGeneration: 0, revision: revision, adapter: probe, deadline: ContinuousClock.now.advanced(by: .seconds(5)))
            Issue.record("Unverified old service must block registration")
        } catch { #expect(error as? AutomntIssue == .serviceTransitionFailed) }
        #expect(await probe.calls == ["stop"])
        #expect(try store.read().phase == .failed)
        #expect(try store.journal().failure == .serviceTransitionFailed)
    }
}
