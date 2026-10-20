import Foundation
import Testing
@testable import AutomntCLI
import AutomntCore

private actor RecoveryService: HandoffServiceAdapter {
    var stopped: [BackendState.Owner] = []
    let result: BackendState.ServiceStatus
    let directory: URL
    init(directory: URL, result: BackendState.ServiceStatus = .stopped) {
        self.directory = directory
        self.result = result
    }
    func stopAndVerify(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus {
        // Discriminates a wrapper accidentally retaining evaluation.lock across await.
        let lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
        withExtendedLifetime(lock) { stopped.append(owner) }
        return result
    }
    func register(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus {
        Issue.record("Recovery must never register")
        return .unavailable
    }
    func status(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus { .stopped }
    func requestEvaluation(state: BackendState, deadline: ContinuousClock.Instant) async throws {
        Issue.record("Recovery must never mount/evaluate")
    }
}

@Suite struct CLITransitionRecoveryTests {
    private func fixture() throws -> (URL, BackendStateStore, BackendTransitionJournal) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Business configuration is produced exclusively by the product repository API.
        let snapshot = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: snapshot.revision)
        let journal = try store.begin(desiredOwner: .cli, expectedGeneration: 0,
                                      revision: snapshot.revision, verifyConfiguration: true)
        return (directory, store, journal)
    }
    private func request(_ journal: BackendTransitionJournal) -> CLIRecoveryRequest {
        CLIRecoveryRequest(transitionID: journal.id, generation: journal.pending.generation)
    }

    @Test func strictGrammarRejectsExtraFlagsAndInvalidGeneration() {
        let id = UUID().uuidString
        #expect(CLIRecoveryRequest.parse([id, "--generation", "1"]) != nil)
        for args in [[], [id], [id, "--generation", "1", "--self-test"],
                     ["bad", "--generation", "1"], [id, "--generation", "-1"],
                     [id, "--generation", "+1"], [id, "--generation", "01"],
                     [id, "--generation", "18446744073709551616"],
                     [id, "--generation", "1 "], [id, "--force", "1"]] {
            #expect(CLIRecoveryRequest.parse(args) == nil)
        }
        #expect(runCLIRecoveryCommand(arguments: [id, "--generation", "1", "--force"]) == 64)
    }

    @Test func abandonedStoppingConvergesAndCannotBeRecoveredTwice() async throws {
        let (directory, store, journal) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = RecoveryService(directory: directory)
        let configBefore = try PrivateAtomicFile.read(directory.appendingPathComponent("automnt.plist"))
        #expect(try inspectCLIRecovery(directory: directory).0 == .interrupted)
        let state = try await recoverCLITransition(directory: directory, request: request(journal),
            adapter: service, deadline: .now.advanced(by: .seconds(2)))
        #expect(state.owner == .none && state.phase == .stopped)
        #expect(state.generation == journal.pending.generation)
        #expect(try store.read() == state)
        #expect(await service.stopped == [.cli])
        #expect(try PrivateAtomicFile.read(directory.appendingPathComponent("automnt.plist")) == configBefore)
        #expect(try inspectCLIRecovery(directory: directory).0 == .notInterrupted)
    }

    @Test func liveTransitionAndEvaluationLocksRefuseRecovery() throws {
        let (directory, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let lock = try StableFileLock(url: directory.appendingPathComponent("handoff.lock"))
            let problem = try withExtendedLifetime(lock) { try inspectCLIRecovery(directory: directory).0 }
            #expect(problem == .transitionInProgress)
        }
        do {
            let lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
            let problem = try withExtendedLifetime(lock) { try inspectCLIRecovery(directory: directory).0 }
            #expect(problem == .operationInProgress)
        }
    }

    @Test func staleGenerationRefusesWithoutServiceCalls() async throws {
        let (directory, store, journal) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = RecoveryService(directory: directory)
        do {
            _ = try await recoverCLITransition(directory: directory,
                request: CLIRecoveryRequest(transitionID: journal.id, generation: journal.pending.generation + 1),
                adapter: service, deadline: .now.advanced(by: .seconds(2)))
            Issue.record("Expected stale request refusal")
        } catch { #expect(error as? CLIRecoveryProblem == .staleRequest) }
        #expect(await service.stopped.isEmpty)
        #expect(try store.read() == journal.pending)
    }

    @Test func mixedAppJournalRefusesBeforeStoppingCLI() async throws {
        let (directory, store, first) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try store.advance(id: first.id, to: .activating, verifiedStatus: .stopped)
        let active = try store.advance(id: first.id, to: .active, verifiedStatus: .enabled,
                                       expectedRevision: first.pending.revision)
        let mixed = try store.begin(desiredOwner: .app, expectedGeneration: active.generation,
                                    revision: active.revision, verifyConfiguration: true)
        let service = RecoveryService(directory: directory)
        do {
            _ = try await recoverCLITransition(directory: directory, request: request(mixed),
                adapter: service, deadline: .now.advanced(by: .seconds(2)))
            Issue.record("Expected app-owner refusal")
        } catch { #expect(error as? CLIRecoveryProblem == .appOwner) }
        #expect(await service.stopped.isEmpty)
        #expect(try store.read() == mixed.pending)
    }

    @Test func pendingWorkerAndUnconfirmedSystemStateStayUnrecovered() async throws {
        let (directory, store, journal) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let worker = WorkerOperationStore(authorizedDirectory: directory)
        let workerID = try worker.begin(revision: journal.pending.revision, generation: journal.pending.generation)
        let service = RecoveryService(directory: directory, result: .unavailable)
        #expect(try inspectCLIRecovery(directory: directory).0 == .requiresRepair)
        do {
            _ = try await recoverCLITransition(directory: directory, request: request(journal),
                adapter: service, deadline: .now.advanced(by: .seconds(2)))
            Issue.record("Expected pending worker refusal")
        } catch { #expect(error as? CLIRecoveryProblem == .requiresRepair) }
        #expect(await service.stopped.isEmpty)
        try worker.complete(id: workerID, revision: journal.pending.revision, generation: journal.pending.generation)
        do {
            _ = try await recoverCLITransition(directory: directory, request: request(journal),
                adapter: service, deadline: .now.advanced(by: .seconds(2)))
            Issue.record("Expected system-state refusal")
        } catch { #expect(error as? AutomntIssue == .serviceTransitionFailed) }
        #expect(try store.read() == journal.pending)
    }
}
