import Foundation
import Testing
@testable import AutomntCore

private actor GateProbe: HandoffServiceAdapter {
    func stopAndVerify(owner: BackendState.Owner, deadline: ContinuousClock.Instant) -> BackendState.ServiceStatus { .stopped }
    func register(owner: BackendState.Owner, deadline: ContinuousClock.Instant) -> BackendState.ServiceStatus { .enabled }
    func status(owner: BackendState.Owner, deadline: ContinuousClock.Instant) -> BackendState.ServiceStatus { .enabled }
    func requestEvaluation(state: BackendState, deadline: ContinuousClock.Instant) {}
}

/// B2/T010-a：CLI owner-aware 接线与统一 evaluation.lock 的纯逻辑回归。
///
/// 业务配置一律经产品 API（`FileConfigRepository.create`）生成；只有
/// `backend-state.plist` 这类转换元数据会被直接改写以复现崩溃/中断边界。
struct CliOwnershipTests {
    private func makeWorkspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func stateBytes(_ directory: URL) throws -> Data {
        try PrivateAtomicFile.read(directory.appendingPathComponent("backend-state.plist"))
    }

    /// app owner 时 CLI 注册被拒绝，且不改任何状态字节。
    @Test func appOwnerRefusesCLIRegistrationWithoutTouchingState() async throws {
        let directory = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: snapshot.revision)
        let active = try await HandoffCoordinator(authorizedDirectory: directory).transfer(
            to: .app, expectedGeneration: 0, revision: snapshot.revision,
            adapter: GateProbe(), deadline: .now.advanced(by: .seconds(5)))
        #expect(active.owner == .app && active.phase == .active)

        let before = try stateBytes(directory)
        let configBefore = try PrivateAtomicFile.read(directory.appendingPathComponent("automnt.plist"))
        #expect(CLIOwnershipGate.decide(action: .registration, state: active, revision: snapshot.revision)
                == .refusedAppOwner(.active))
        #expect(throws: AutomntIssue.incompatibleOwner) {
            try CLIOwnershipGate.withPermission(action: .registration, state: active,
                                                revision: snapshot.revision) { Issue.record("CLI must not register while the app owns the backend") }
        }
        // 被拒绝的路径不得改动原文件字节。
        #expect(try stateBytes(directory) == before)
        #expect(try PrivateAtomicFile.read(directory.appendingPathComponent("automnt.plist")) == configBefore)
        #expect(try store.read() == active)
    }

    /// desiredOwner=app 的失败残留不得被 CLI 静默接管。
    @Test func failedAppResidualRequiresExplicitRepairNotSilentTakeover() async throws {
        let directory = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: snapshot.revision)
        let journal = try store.begin(desiredOwner: .app, expectedGeneration: 0,
                                      revision: snapshot.revision, verifyConfiguration: true)
        _ = try store.advance(id: journal.id, to: .failed, verifiedStatus: .unavailable,
                              failure: .serviceTransitionFailed)
        let failed = try store.read()
        #expect(failed.desiredOwner == .app)
        let before = try stateBytes(directory)
        for action in [CLIOwnershipAction.registration, .evaluation] {
            #expect(CLIOwnershipGate.decide(action: action, state: failed, revision: snapshot.revision) == .requiresRepair)
        }
        #expect(throws: AutomntIssue.serviceTransitionFailed) {
            try CLIOwnershipGate.withPermission(action: .evaluation, state: failed, revision: snapshot.revision) { }
        }
        #expect(try stateBytes(directory) == before)
        #expect(try store.read() == failed)
    }

    /// generation 变化 → 旧快照动作被拒绝，原状态字节保留。
    @Test func generationChangeRejectsStaleSnapshotAndPreservesBytes() async throws {
        let directory = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        let initial = try store.initialize(revision: snapshot.revision)
        #expect(initial.generation == 0)
        // CLI 判定门对过期代次的直接拒绝。
        #expect(CLIOwnershipGate.decide(action: .evaluation, state: initial,
                                        revision: snapshot.revision, expectedGeneration: 99) == .staleGeneration)
        // 发生一次真实转换后 generation 变化。
        let active = try await HandoffCoordinator(authorizedDirectory: directory).transfer(
            to: .cli, expectedGeneration: 0, revision: snapshot.revision,
            adapter: GateProbe(), deadline: .now.advanced(by: .seconds(5)))
        #expect(active.generation == 1)
        let before = try stateBytes(directory)
        // 旧快照（generation 0）的动作必须被 EvaluationPermit 拒绝。
        #expect(throws: AutomntIssue.configurationConflict) {
            _ = try EvaluationPermit(directory: directory, repository: repository,
                                     expected: snapshot, owner: .cli, generation: 0,
                                     readBackend: store.read)
        }
        #expect(try stateBytes(directory) == before)
        #expect(try store.read() == active)
        // 同代次的新快照可以通过，证明拒绝来自代次而非一律失败。
        let permit = try EvaluationPermit(directory: directory, repository: repository,
                                          expected: snapshot, owner: .cli, generation: 1,
                                          readBackend: store.read)
        #expect(permit.generation == 1)
    }

    /// revision 变化 → 旧快照被拒绝，且未建立任何动作。
    @Test func staleRevisionRefusesEvaluationWithoutWrites() async throws {
        let directory = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        let initial = try store.initialize(revision: snapshot.revision)
        #expect(throws: AutomntIssue.configurationConflict) {
            try CLIOwnershipGate.withPermission(action: .evaluation, state: initial,
                                                revision: ConfigRevision(digest: "stale")) { }
        }
        #expect(CLIOwnershipGate.decide(action: .evaluation, state: initial,
                                        revision: ConfigRevision(digest: "stale")) == .staleRevision(.stopped))
        #expect(try store.read() == initial)
        // evaluation.lock 判定为纯读，绝对不替换锁 inode。
        let active = try await HandoffCoordinator(authorizedDirectory: directory).transfer(
            to: .cli, expectedGeneration: 0, revision: snapshot.revision,
            adapter: GateProbe(), deadline: .now.advanced(by: .seconds(5)))
        let lockURL = directory.appendingPathComponent("evaluation.lock")
        let before = try FileManager.default.attributesOfItem(atPath: lockURL.path)
        let beforeInode = (before[.systemFileNumber] as? NSNumber)?.intValue
        let permit = try EvaluationPermit(directory: directory, repository: repository,
                                          expected: snapshot, owner: .cli,
                                          generation: active.generation, readBackend: store.read)
        permit.perform { _ in }
        let after = try FileManager.default.attributesOfItem(atPath: lockURL.path)
        #expect((after[.systemFileNumber] as? NSNumber)?.intValue == beforeInode)
    }

    /// 状态缺失 → 明确要求初始化，而不是静默当作已授权。
    @Test func missingDurableStateRequiresExplicitInitialization() throws {
        let directory = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig())
        #expect(CLIOwnershipGate.decide(action: .registration, state: nil, revision: snapshot.revision) == .needsInitialization)
        #expect(CLIOwnershipGate.decide(action: .evaluation, state: nil, revision: snapshot.revision) == .needsInitialization)
        let store = BackendStateStore(authorizedDirectory: directory)
        let initialized = try store.initialize(revision: snapshot.revision)
        #expect(initialized.owner == .none && initialized.phase == .stopped && initialized.generation == 0)
        // 只读状态查询在有 app owner 时仍可用。
        var appOwned = initialized
        appOwned.owner = .app
        appOwned.phase = .active
        #expect(CLIOwnershipGate.decide(action: .status, state: appOwned, revision: snapshot.revision) == .permitted)
    }

    /// 免费 CLI 契约：无常驻 KeepAlive、无周期轮询。
    @Test func cliDefinitionStaysEventDrivenWithoutResidentProcess() {
        let eventDriven: [String: Any] = [
            "Label": "com.user.automnt",
            "ProgramArguments": ["/tmp/automnt"],
            "RunAtLoad": true,
            "WatchPaths": ["/Library/Preferences/SystemConfiguration"],
            "StartOnMount": true
        ]
        #expect(CLIOwnershipGate.permitsNonResidentDefinition(eventDriven))
        for forbidden in ["KeepAlive", "StartInterval", "StartCalendarInterval"] {
            var resident = eventDriven
            resident[forbidden] = true
            #expect(!CLIOwnershipGate.permitsNonResidentDefinition(resident))
        }
    }

    /// 并发持锁是保护而非损坏：不得引导用户去"修复"。
    @Test func operationInProgressIsDistinctFromRepair() throws {
        let directory = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = try FileConfigRepository(authorizedDirectory: directory).create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        let initial = try store.initialize(revision: snapshot.revision)
        let decision = CLIOwnershipDecision.operationInProgress
        #expect(decision.tag == "operationInProgress")
        #expect(decision != .requiresRepair)
        #expect(throws: AutomntIssue.configurationConflict) {
            try CLIOwnershipGate.withPermission(action: .evaluation, state: initial,
                                                revision: ConfigRevision(digest: "stale")) { }
        }
        // 持锁（构造第二把 evaluation.lock）时并发预检失败且不改状态。
        let lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
        defer { withExtendedLifetime(lock) {} }
        #expect(throws: NSError.self) {
            _ = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
        }
        #expect(try store.read() == initial)
    }
}
