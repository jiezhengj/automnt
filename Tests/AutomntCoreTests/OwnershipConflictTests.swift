import Foundation
import Testing
@testable import AutomntCore

private actor OwnershipProbe: HandoffServiceAdapter {
    func stopAndVerify(owner: BackendState.Owner, deadline: ContinuousClock.Instant) -> BackendState.ServiceStatus { .stopped }
    func register(owner: BackendState.Owner, deadline: ContinuousClock.Instant) -> BackendState.ServiceStatus { .enabled }
    func status(owner: BackendState.Owner, deadline: ContinuousClock.Instant) -> BackendState.ServiceStatus { .enabled }
    func requestEvaluation(state: BackendState, deadline: ContinuousClock.Instant) {}
}

/// T025：所有权冲突与在途快照的关键不变量。
///
/// 业务配置一律经产品 API（`FileConfigRepository.create/save`）生成；
/// `backend-state.plist`/`transition-journal.plist` 这类转换元数据才允许直接改写以复现边界。
struct OwnershipConflictTests {
    private func makeWorkspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func share(_ suffix: String, mountPoint: String) -> SMBShareConfig {
        let host = "ownership-\(suffix).example"
        return SMBShareConfig(name: suffix, smbURL: "smb://\(host)/\(suffix)", mountPoint: mountPoint)
    }

    private func model(_ suffix: String, mountPoint: String) -> AutomntConfig {
        AutomntConfig(hosts: [HostConfig(host: "ownership-\(suffix).example", shares: [share(suffix, mountPoint: mountPoint)])])
    }

    private func inode(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.systemFileNumber] as? NSNumber)?.intValue ?? -1
    }

    /// 在途操作锁不得因产品编辑/保存配置而更换 inode 或路径；旧快照不得执行新动作。
    @Test func inFlightSnapshotRejectsMountPointChangeWithoutReplacingOperationLock() async throws {
        let directory = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let original = try repository.create(model("one", mountPoint: "/Volumes/OwnershipA"))
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: original.revision)
        let active = try await HandoffCoordinator(authorizedDirectory: directory).transfer(
            to: .cli, expectedGeneration: 0, revision: original.revision,
            adapter: OwnershipProbe(), deadline: .now.advanced(by: .seconds(5)))

        let operationLock = directory.appendingPathComponent("evaluation.lock")
        let configurationLock = directory.appendingPathComponent("config.lock")
        let operationInode = try inode(operationLock)
        let configurationInode = try inode(configurationLock)
        let stateBytes = try PrivateAtomicFile.read(directory.appendingPathComponent("backend-state.plist"))

        // 旧快照取得操作锁（在途操作）。permit 持有锁直到其作用域结束。
        do {
            let permit = try EvaluationPermit(directory: directory, repository: repository,
                expected: original, owner: .cli, generation: active.generation,
                readBackend: store.read)
            try permit.perform { _ in
                // 持操作锁期间，产品编辑/保存把 mount_point 改成新路径。
                var changed = original.configuration
                let edited = share("one", mountPoint: "/Volumes/OwnershipB")
                let editedHost = HostConfig(host: changed.hosts[0].host, shares: [edited])
                changed.hosts[0] = editedHost
                _ = try repository.save(changed, baseRevision: original.revision)

                // 在途 permit 存活期间，第二把操作锁不得取得：并发保护（EWOULDBLOCK），
                // 而不是静默并行执行两个动作。断言必须是锁争用本身，不能只用
                // `throws: NSError.self`——那样任意错误（例如 revision 冲突）都会通过。
                do {
                    _ = try EvaluationPermit(directory: directory, repository: repository,
                        expected: original, owner: .cli, generation: active.generation,
                        readBackend: store.read)
                    Issue.record("a second operation lock must not be obtainable while the first is held")
                } catch let error as NSError {
                    #expect(error.domain == NSPOSIXErrorDomain)
                    #expect(error.code == Int(EWOULDBLOCK))
                }
            }
        } // permit 释放操作锁

        // 操作锁与配置锁都不得被原子替换（inode 稳定）。
        #expect(try inode(operationLock) == operationInode)
        #expect(try inode(configurationLock) == configurationInode)

        // 旧快照在配置变更后不得再启动新动作（锁已释放，拒绝来自 revision 失效）。
        #expect(throws: AutomntIssue.configurationConflict) {
            _ = try EvaluationPermit(directory: directory, repository: repository,
                expected: original, owner: .cli, generation: active.generation,
                readBackend: store.read)
        }
        // 旧快照的 revision 与新配置不同，直接证明这是 revision 失效而非代次。
        #expect(try repository.read().revision != original.revision)
        // 后端状态未被在途配置编辑改写。
        #expect(try PrivateAtomicFile.read(directory.appendingPathComponent("backend-state.plist")) == stateBytes)
        #expect(try store.read() == active)
    }

    /// 在产品编辑中删除唯一 mount_point 条目后，旧快照同样不得启动动作。
    @Test func inFlightSnapshotRejectsDeletedMountPointTarget() async throws {
        let directory = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let original = try repository.create(model("two", mountPoint: "/Volumes/OwnershipC"))
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: original.revision)
        let active = try await HandoffCoordinator(authorizedDirectory: directory).transfer(
            to: .cli, expectedGeneration: 0, revision: original.revision,
            adapter: OwnershipProbe(), deadline: .now.advanced(by: .seconds(5)))

        var emptied = original.configuration
        emptied.hosts = []
        let saved = try repository.save(emptied, baseRevision: original.revision)
        #expect(saved.configuration.hosts.isEmpty)

        #expect(throws: AutomntIssue.configurationConflict) {
            _ = try EvaluationPermit(directory: directory, repository: repository,
                expected: original, owner: .cli, generation: active.generation,
                readBackend: store.read)
        }
        #expect(try store.read() == active)
        // 真实入口先读配置（新 revision）再读后端状态（旧 revision）：
        // 两者不一致时 CLI 判定门必须报 staleRevision，而不是照旧执行。
        #expect(CLIOwnershipGate.decide(action: .evaluation, state: active,
                                        revision: saved.revision) == .staleRevision(.active))
    }

    /// 两开关经共用保存路径往返时相互独立，且显式 false 不被缺键迁移覆盖。
    ///
    /// 只保留 `ConfigurationContractTests`/`RegressionTests` 未覆盖的部分：缺键的
    /// nil 语义、以及「另一个开关被改回 true 时不连带恢复本开关」这一跨开关组合。
    @Test func automationAndRecoverySwitchesStayIndependentAcrossRoundTrips() throws {
        let directory = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let created = try repository.create(model("three", mountPoint: "/Volumes/OwnershipD"))

        // 缺键 → 按旧产品启用意图兼容（两个开关都视为启用），但字段本身仍保持 nil。
        #expect(created.configuration.automationEnabled == nil)
        #expect(created.configuration.isAutomationEnabled)
        #expect(created.configuration.isAutoMountRecoveryEnabled)

        var both = created.configuration
        both.automationEnabled = false
        both.autoMountRecovery = false
        let off = try repository.save(both, baseRevision: created.revision)
        #expect(!off.configuration.isAutomationEnabled)
        #expect(!off.configuration.isAutoMountRecoveryEnabled)

        // 只把自动挂载改回 true：恢复开关的显式 false 必须保留。
        var automationOn = off.configuration
        automationOn.automationEnabled = true
        _ = try repository.save(automationOn, baseRevision: off.revision)
        let reopened = try FileConfigRepository(authorizedDirectory: directory).read()
        #expect(reopened.configuration.isAutomationEnabled)
        #expect(!reopened.configuration.isAutoMountRecoveryEnabled)
    }

    /// 失败的旧服务必须回退或明确停用，不得出现双 active 或死锁。
    @Test func failedRegistrationNeverLeavesTwoActiveOrDeadlocks() async throws {
        let directory = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(model("four", mountPoint: "/Volumes/OwnershipE"))
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: snapshot.revision)
        let coordinator = HandoffCoordinator(authorizedDirectory: directory)

        let active = try await coordinator.transfer(to: .cli, expectedGeneration: 0,
            revision: snapshot.revision, adapter: OwnershipProbe(),
            deadline: .now.advanced(by: .seconds(5)))
        #expect(active.phase == .active && active.generation == 1)

        // 转换为 app 时注册失败：必须收敛到明确失败/停用，不得声称 active。
        let failing = FailingRegistrationProbe()
        await #expect(throws: (any Error).self) {
            _ = try await coordinator.transfer(to: .app, expectedGeneration: active.generation,
                revision: snapshot.revision, adapter: failing,
                deadline: .now.advanced(by: .seconds(5)))
        }
        let converged = try store.read()
        #expect(converged.phase != .active || converged.owner == .cli)
        #expect(converged.owner != .app || converged.phase != .active)
        #expect(await failing.registerAttempts >= 1)
        // 单一 owner：前后两次转换后 generation 单调递增，不存在两个 active 代次。
        #expect(converged.generation > active.generation)
    }

    /// 后端状态自身记录了过期配置 revision 时，动作必须被拒绝——
    /// 这与「调用者传入的 expected 快照过期」是两个独立的校验。
    @Test func backendStateRevisionMismatchIsRejectedEvenWhenCallerSnapshotMatches() async throws {
        let directory = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let original = try repository.create(model("six", mountPoint: "/Volumes/OwnershipG"))
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: original.revision)
        let active = try await HandoffCoordinator(authorizedDirectory: directory).transfer(
            to: .cli, expectedGeneration: 0, revision: original.revision,
            adapter: OwnershipProbe(), deadline: .now.advanced(by: .seconds(5)))

        // 产品保存产生新 revision；调用者却拿着「新」快照、用旧的后端状态代次申请许可。
        var edited = original.configuration
        edited.autoMountRecovery = false
        let saved = try repository.save(edited, baseRevision: original.revision)
        #expect(saved.revision != original.revision)

        // 后端状态仍记录旧 revision → 即使调用者的快照与磁盘一致，也必须拒绝。
        #expect(throws: AutomntIssue.configurationConflict) {
            _ = try EvaluationPermit(directory: directory, repository: repository,
                expected: saved, owner: .cli, generation: active.generation,
                readBackend: store.read)
        }
        #expect(try store.read() == active)
    }

    /// 调用者传入的快照本身过期（磁盘与后端状态都已前进到新 revision）时，
    /// 许可必须在任何动作前拒绝——这是与「后端状态 revision 失配」**不同**的一条校验。
    @Test func staleCallerSnapshotIsRejectedEvenWhenBackendStateIsCurrent() async throws {
        let directory = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let original = try repository.create(model("seven", mountPoint: "/Volumes/OwnershipH"))
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: original.revision)
        let coordinator = HandoffCoordinator(authorizedDirectory: directory)
        let first = try await coordinator.transfer(to: .cli, expectedGeneration: 0,
            revision: original.revision, adapter: OwnershipProbe(),
            deadline: .now.advanced(by: .seconds(5)))

        // 配置前进到新 revision，随后后端状态也经产品协调器前进到同一 revision。
        var edited = original.configuration
        edited.autoMountRecovery = false
        let saved = try repository.save(edited, baseRevision: original.revision)
        let second = try await coordinator.transfer(to: .cli, expectedGeneration: first.generation,
            revision: saved.revision, adapter: OwnershipProbe(),
            deadline: .now.advanced(by: .seconds(5)))
        #expect(second.revision == saved.revision)
        #expect(try store.read().revision == saved.revision)

        // 此刻磁盘与后端状态一致（都已是新 revision），唯一过期的是调用者的快照。
        // 若只校验后端状态 revision，这里会错误地放行一个基于旧配置的动作。
        #expect(throws: AutomntIssue.configurationConflict) {
            _ = try EvaluationPermit(directory: directory, repository: repository,
                expected: original, owner: .cli, generation: second.generation,
                readBackend: store.read)
        }
        // 对照：同一后端状态配上与磁盘一致的快照即可通过，证明拒绝来自调用者快照过期。
        let permit = try EvaluationPermit(directory: directory, repository: repository,
            expected: saved, owner: .cli, generation: second.generation,
            readBackend: store.read)
        permit.perform { snapshot in
            #expect(snapshot.revision == saved.revision)
            #expect(!snapshot.configuration.isAutoMountRecoveryEnabled)
        }
    }

    /// 配置保存与评估的锁顺序固定：配置锁短持有，评估锁不参与配置写入。
    @Test func configurationSaveDoesNotHoldEvaluationLock() throws {        let directory = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(model("five", mountPoint: "/Volumes/OwnershipF"))
        let operationLock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
        defer { withExtendedLifetime(operationLock) {} }
        // 持有评估锁时，配置保存仍必须成功（两个锁相互独立，不会互相等待）。
        var edited = snapshot.configuration
        edited.autoMountRecovery = false
        let saved = try repository.save(edited, baseRevision: snapshot.revision)
        #expect(!saved.configuration.isAutoMountRecoveryEnabled)
    }
}

private actor FailingRegistrationProbe: HandoffServiceAdapter {
    private(set) var registerAttempts = 0
    func stopAndVerify(owner: BackendState.Owner, deadline: ContinuousClock.Instant) -> BackendState.ServiceStatus { .stopped }
    func register(owner: BackendState.Owner, deadline: ContinuousClock.Instant) throws -> BackendState.ServiceStatus {
        registerAttempts += 1
        throw AutomntIssue.serviceTransitionFailed
    }
    func status(owner: BackendState.Owner, deadline: ContinuousClock.Instant) -> BackendState.ServiceStatus { .stopped }
    func requestEvaluation(state: BackendState, deadline: ContinuousClock.Instant) {}
}
