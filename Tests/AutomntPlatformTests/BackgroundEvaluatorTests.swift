import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

/// T009-c2：`BackgroundEvaluator` 编排行为等价性（表驱动，无真实 SMB）。
///
/// runner/探活/状态文件全部注入；业务配置一律经产品 API（`FileConfigRepository.create`）生成。
/// 覆盖 task-15 点名的 7 个场景，并锁定「判定来自共享 `RecoveryVolumeDecisionPolicy`」。
struct BackgroundEvaluatorTests {

    // MARK: - 夹具

    private struct Harness {
        let directory: URL
        let snapshot: ConfigSnapshot
        let backend: BackendState
        let volumes: [RecoveryRoundConfiguredVolume]
        let host: HostConfig
        var inspected: [String] = []
        var mounted: [String] = []
        var cleaned: [String] = []
        var inspectHealth: [String: WorkerMountResponse] = [:]
        var mountResponse: (String) -> WorkerMountResponse = { identity in
            WorkerMountResponse(observation: VolumeObservation(identity: identity, status: .healthy,
                actualPath: "/Volumes/x", observedAt: Date()), postMount: .notRequested)
        }
    }

    private func makeHarness(_ hostName: String,
                             shares: [(name: String, mount: String)]) async throws -> Harness {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("automnt-bg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let host = HostConfig(host: hostName, shares: shares.map {
            SMBShareConfig(name: $0.name, smbURL: "smb://\(hostName)/\($0.name)", mountPoint: $0.mount)
        })
        let repository = FileConfigRepository(authorizedDirectory: directory)
        _ = try repository.create(AutomntConfig(retryPolicy: RetryPolicy(maxAttempts: 2, intervalMs: 100,
                                                                        maxTotalWindowMs: 5000),
            hosts: [host], autoMountRecovery: true, automationEnabled: true))
        let snapshot = try repository.read()
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: snapshot.revision)
        let journal = try store.begin(desiredOwner: .app, expectedGeneration: 0, revision: snapshot.revision)
        _ = try store.advance(id: journal.id, to: .activating, verifiedStatus: .stopped)
        let backend = try store.advance(id: journal.id, to: .active, verifiedStatus: .enabled)
        return Harness(directory: directory, snapshot: snapshot, backend: backend,
            volumes: configuredRecoveryVolumes(from: snapshot.configuration), host: host)
    }

    private struct StubProbe: ReachabilityProbe {
        let reachable: Bool
        func isReachable(host: String, port: Int, timeoutMilliseconds: Int) async throws -> Bool { reachable }
    }

    /// 把可变状态装进引用盒，供并发安全的闭包捕获。
    private final class Box: @unchecked Sendable {
        var inspected: [String] = []
        var mounted: [String] = []
        var cleaned: [String] = []
        var inspectHealth: [String: WorkerMountResponse] = [:]
        var mountResponse: (String) -> WorkerMountResponse = { identity in
            WorkerMountResponse(observation: VolumeObservation(identity: identity, status: .healthy,
                actualPath: "/Volumes/x", observedAt: Date()), postMount: .notRequested)
        }
    }

    private func effects(_ box: Box, present: @escaping (String) -> MountPathState) -> BackgroundVolumeEffects {
        BackgroundVolumeEffects(
            mountPathState: present,
            inspect: { share, _, _, _, _, _ in
                let identity = smbResourceIdentity(share.smbURL) ?? ""
                box.inspected.append(identity)
                return box.inspectHealth[identity] ?? WorkerMountResponse(
                    observation: VolumeObservation(identity: identity, status: .evaluating,
                        actualPath: nil, observedAt: Date(), issue: .signalUnavailable),
                    postMount: .notRequested, issue: .signalUnavailable, requiresReconciliation: true)
            },
            mount: { share, _, _, _, _, _ in
                let identity = smbResourceIdentity(share.smbURL) ?? ""
                box.mounted.append(identity)
                return BackgroundMountExecution(response: box.mountResponse(identity), operationID: UUID())
            },
            cleanup: { share, _, _, _, _, _ in
                let identity = smbResourceIdentity(share.smbURL) ?? ""
                box.cleaned.append(identity)
                return WorkerMountResponse(observation: VolumeObservation(identity: identity, status: .stopped,
                    actualPath: nil, observedAt: Date()), postMount: .notRequested)
            })
    }

    private func evaluate(_ harness: Harness, box: Box, reachable: Bool = true,
                          present: @escaping (String) -> MountPathState = { _ in .absent }) async -> BackgroundEvaluationSummary {
        (try? await BackgroundEvaluator.evaluate(directory: harness.directory,
            snapshot: harness.snapshot, backend: harness.backend,
            deadline: ContinuousClock.now.advanced(by: .seconds(5)),
            probe: StubProbe(reachable: reachable), effects: effects(box, present: present)))
            ?? BackgroundEvaluationSummary(issue: .signalUnavailable)
    }

    private func writeState(_ harness: Harness, _ state: MountRecoveryStateFile) throws {
        try RecoveryStateRepository(url: harness.directory.appendingPathComponent("mount-recovery-state.plist")).save(state)
    }

    private func boundary(_ network: String = "bg-network", _ login: String = "bg-login") -> String {
        RecoverySessionIdentity(network: network, loginEpoch: login, previous: nil).combined
    }

    // MARK: - 场景表

    /// 1. missing + reachable → mount（recover），产出 healthy 观测。
    @Test func missingReachableVolumeMounts() async throws {
        let harness = try await makeHarness("bg-mount.example", shares: [("Shared", "/Volumes/Shared")])
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let box = Box()
        let identity = harness.volumes[0].identity
        box.inspectHealth[identity] = WorkerMountResponse(observation: VolumeObservation(identity: identity,
            status: .healthy, actualPath: "/Volumes/Shared", observedAt: Date()), postMount: .notRequested)
        let summary = await evaluate(harness, box: box)
        #expect(box.mounted == [identity])
        #expect(summary.observations.contains { $0.identity == identity && $0.status == .healthy })
        #expect(summary.issue == nil)
        #expect(summary.retrySuggested == false)
    }

    /// all_reachable：按保存顺序处理每个可达服务器，并为其自身的共享记录结果；
    /// 不可达服务器的启用共享记为 offline，而不是从这一轮里消失。
    @Test func allReachableRoundProcessesEveryHostAndRecordsOfflineForUnreachable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("automnt-bg-scope-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = HostConfig(host: "first-scope.example", shares: [
            SMBShareConfig(name: "A", smbURL: "smb://first-scope.example/A", mountPoint: "/Volumes/A")])
        let second = HostConfig(host: "second-scope.example", shares: [
            SMBShareConfig(name: "B", smbURL: "smb://second-scope.example/B", mountPoint: "/Volumes/B")])
        let repository = FileConfigRepository(authorizedDirectory: directory)
        var configuration = AutomntConfig(
            retryPolicy: RetryPolicy(maxAttempts: 2, intervalMs: 100, maxTotalWindowMs: 5000),
            hosts: [first, second], autoMountRecovery: true, automationEnabled: true)
        configuration.mountPolicy = .allReachable
        _ = try repository.create(configuration)
        let snapshot = try repository.read()
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: snapshot.revision)
        let journal = try store.begin(desiredOwner: .app, expectedGeneration: 0, revision: snapshot.revision)
        _ = try store.advance(id: journal.id, to: .activating, verifiedStatus: .stopped)
        let backend = try store.advance(id: journal.id, to: .active, verifiedStatus: .enabled)

        struct FirstOnlyProbe: ReachabilityProbe {
            func isReachable(host: String, port: Int, timeoutMilliseconds: Int) async throws -> Bool {
                host == "first-scope.example"
            }
        }
        let a = smbResourceIdentity(first.shares[0].smbURL)!
        let b = smbResourceIdentity(second.shares[0].smbURL)!
        let box = Box()
        box.inspectHealth[a] = WorkerMountResponse(observation: VolumeObservation(identity: a,
            status: .healthy, actualPath: "/Volumes/A", observedAt: Date()), postMount: .notRequested)
        box.mountResponse = { identity in
            WorkerMountResponse(observation: VolumeObservation(identity: identity, status: .healthy,
                actualPath: "/Volumes/A", observedAt: Date()), postMount: .notRequested)
        }
        let summary = (try? await BackgroundEvaluator.evaluate(directory: directory,
            snapshot: snapshot, backend: backend,
            deadline: ContinuousClock.now.advanced(by: .seconds(5)),
            probe: FirstOnlyProbe(), effects: effects(box, present: { _ in .absent })))
            ?? BackgroundEvaluationSummary(issue: .signalUnavailable)
        #expect(box.mounted == [a])
        #expect(summary.observations.contains { $0.identity == a && $0.status == .healthy })
        #expect(summary.observations.contains { $0.identity == b && $0.status == .offline })
        #expect(summary.issue == nil)
    }

    /// 2. missing + unreachable → offline（不挂载）。
    @Test func missingUnreachableHostReturnsOfflineWithoutMounting() async throws {
        let harness = try await makeHarness("bg-offline.example", shares: [("Shared", "/Volumes/Shared")])
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let box = Box()
        let summary = await evaluate(harness, box: box, reachable: false)
        #expect(summary.issue == .offline)
        #expect(box.mounted.isEmpty)
        #expect(box.inspected.isEmpty && box.cleaned.isEmpty)
    }

    /// 3. present + unreachable（死卷）→ 不清理、不挂载；观测标记 evaluating/unavailable。
    @Test func presentVolumeWithUnavailablePathIsBlockedNotCleaned() async throws {
        let harness = try await makeHarness("bg-dead.example", shares: [("Shared", "/Volumes/Shared")])
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let box = Box()
        let summary = await evaluate(harness, box: box, present: { _ in .unavailable })
        #expect(summary.issue == .signalUnavailable)
        #expect(box.cleaned.isEmpty && box.mounted.isEmpty)
    }

    /// 4. present + healthy → attachHealthy（无清理、无挂载）。
    @Test func presentHealthyVolumeAttachesWithoutCleanupOrMount() async throws {
        let harness = try await makeHarness("bg-healthy.example", shares: [("Shared", "/Volumes/Shared")])
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let box = Box()
        let identity = harness.volumes[0].identity
        box.inspectHealth[identity] = WorkerMountResponse(observation: VolumeObservation(identity: identity,
            status: .healthy, actualPath: "/Volumes/Shared", observedAt: Date()), postMount: .notRequested)
        let summary = await evaluate(harness, box: box, present: { _ in .smb(identity: identity) })
        #expect(box.inspected == [identity])
        #expect(box.cleaned.isEmpty)
        #expect(box.mounted.isEmpty)
        #expect(summary.issue == nil)
        #expect(summary.observations.count == 1)
        #expect(summary.observations.first?.status == .healthy)
    }

    /// 4b. present + failed（明确拒绝）→ 清理后再恢复（死卷清理路径）。
    @Test func presentFailedVolumeCleansThenRecovers() async throws {
        let harness = try await makeHarness("bg-cleanup.example", shares: [("Shared", "/Volumes/Shared")])
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let box = Box()
        let identity = harness.volumes[0].identity
        box.inspectHealth[identity] = WorkerMountResponse(observation: VolumeObservation(identity: identity,
            status: .failed, actualPath: "/Volumes/Shared", observedAt: Date(), issue: .shareRejected),
            postMount: .notRequested)
        let summary = await evaluate(harness, box: box, present: { _ in .smb(identity: identity) })
        #expect(box.cleaned == [identity])
        #expect(box.mounted == [identity])
        #expect(summary.issue == nil)
    }

    /// 5. suppressed（`.suppressed` 记录，无 everHealthyMounted）→ 不挂载、观测 suppressed。
    @Test func suppressedRecordSkipsMount() async throws {
        let harness = try await makeHarness("bg-suppressed.example", shares: [("Shared", "/Volumes/Shared")])
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let identity = harness.volumes[0].identity
        let record = MountRecoveryVolumeRecord(volumeKey: identity, state: .suppressed,
            suppressionBoundary: boundary(), everHealthyMounted: false)
        try writeState(harness, MountRecoveryStateFile(sessionBoundary: boundary(), volumes: [identity: record]))
        let box = Box()
        let summary = await evaluate(harness, box: box)
        #expect(box.mounted.isEmpty)
        #expect(summary.observations.contains { $0.identity == identity && $0.status == .suppressed })
    }

    /// 6. deferred（同会话重试间隔未到）→ 不挂载，标记 retrySuggested。
    @Test func retryIntervalDefersWithoutMounting() async throws {
        let harness = try await makeHarness("bg-deferred.example", shares: [("Shared", "/Volumes/Shared")])
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let identity = harness.volumes[0].identity
        let now = Date().timeIntervalSince1970
        let record = MountRecoveryVolumeRecord(volumeKey: identity, state: .pendingRecovery,
            everHealthyMounted: true, attemptCount: 1, updatedAt: now)
        try writeState(harness, MountRecoveryStateFile(sessionBoundary: boundary(), volumes: [identity: record]))
        let box = Box()
        let summary = await evaluate(harness, box: box)
        #expect(box.mounted.isEmpty)
        #expect(summary.retrySuggested == true)
        #expect(summary.observations.contains { $0.identity == identity && $0.status == .evaluating })
        // 延后不得消耗尝试预算，也不得写入清理账或改动通知额度。
        let after = RecoveryStateRepository(url: harness.directory
            .appendingPathComponent("mount-recovery-state.plist")).read().file
        #expect(after.volumes[identity]?.attemptCount == 1)
        #expect(after.volumes[identity]?.state == .pendingRecovery)
        #expect(after.cleanupLedger[identity] == nil)
        #expect(after.volumes[identity]?.notificationCount == 0)
    }

    /// 7. 单主机轮次：失败观测不得被 superseded 过滤吞掉（配置校验禁止同主机重复挂载点，
    ///    故 cross-identity superseded 在 helper 单轮内不可能发生；此处锁定它是**空操作**）。
    @Test func failedObservationSurvivesSupersededFilterInSingleHostRound() async throws {
        let harness = try await makeHarness("bg-superseded.example", shares: [("Shared", "/Volumes/Shared")])
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let identity = harness.volumes[0].identity
        let box = Box()
        // 挂载子进程明确拒绝（绝对失败，非 reconciliation），健康复核无需进行。
        box.mountResponse = { _ in
            WorkerMountResponse(observation: nil, postMount: .notRequested,
                issue: .shareRejected, requiresReconciliation: false)
        }
        let summary = await evaluate(harness, box: box)
        // 失败观测必须保留并被报告为失败，绝不能被 superseded 过滤删除。
        #expect(summary.observations.contains { $0.identity == identity && $0.status == .failed })
        #expect(summary.observations.contains { $0.status == .healthy } == false)
    }

    /// 7b. `RecoverySupersededPolicy` 单测：跨身份同路径的恢复者剔除未恢复者；
    ///     未被恢复、路径不同、以及恢复者自身都不被剔除。
    @Test func supersededPolicyRemovesOnlyOtherIdentitiesOnRestoredPath() {
        let restored = "//new.example/shared"
        let stale = "//old.example/shared"
        let unrelated = "//other.example/other"
        let volumes = [(identity: restored, mountPoint: "/Volumes/Shared"),
                       (identity: stale, mountPoint: "/Volumes/Shared"),
                       (identity: unrelated, mountPoint: "/Volumes/Other")]
        let superseded = RecoverySupersededPolicy.supersededIdentities(recovered: [restored], volumes: volumes)
        #expect(superseded == [stale])
        #expect(!superseded.contains(restored))
        #expect(!superseded.contains(unrelated))
        // 无恢复者时不得剔除任何身份。
        #expect(RecoverySupersededPolicy.supersededIdentities(recovered: [], volumes: volumes).isEmpty)
    }

    /// 探活顺序：首个可达主机独占（共享失败不得切换备用主机）。
    @Test func unreachableFirstHostNeverFallsBackToSecond() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("automnt-bg-priority-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = HostConfig(host: "first-bg.example", shares: [SMBShareConfig(name: "A",
            smbURL: "smb://first-bg.example/A", mountPoint: "/Volumes/A")])
        let second = HostConfig(host: "second-bg.example", shares: [SMBShareConfig(name: "B",
            smbURL: "smb://second-bg.example/B", mountPoint: "/Volumes/B")])
        let repository = FileConfigRepository(authorizedDirectory: directory)
        _ = try repository.create(AutomntConfig(retryPolicy: RetryPolicy(maxAttempts: 1, intervalMs: 100,
                                                                        maxTotalWindowMs: 2000),
            hosts: [first, second], autoMountRecovery: true, automationEnabled: true))
        let snapshot = try repository.read()
        let store = BackendStateStore(authorizedDirectory: directory)
        _ = try store.initialize(revision: snapshot.revision)
        let journal = try store.begin(desiredOwner: .app, expectedGeneration: 0, revision: snapshot.revision)
        _ = try store.advance(id: journal.id, to: .activating, verifiedStatus: .stopped)
        let backend = try store.advance(id: journal.id, to: .active, verifiedStatus: .enabled)

        struct SelectiveProbe: ReachabilityProbe {
            func isReachable(host: String, port: Int, timeoutMilliseconds: Int) async throws -> Bool {
                host == "second-bg.example"
            }
        }
        let box = Box()
        let secondIdentity = smbResourceIdentity(second.shares[0].smbURL)!
        // 挂载成功后的健康复核也必须成功，否则 summary 会带 signalUnavailable 而非 nil。
        box.inspectHealth[secondIdentity] = WorkerMountResponse(observation: VolumeObservation(
            identity: secondIdentity, status: .healthy, actualPath: "/Volumes/B", observedAt: Date()),
            postMount: .notRequested)
        let summary = (try? await BackgroundEvaluator.evaluate(directory: directory, snapshot: snapshot,
            backend: backend, deadline: ContinuousClock.now.advanced(by: .seconds(3)),
            probe: SelectiveProbe(), effects: effects(box, present: { _ in .absent })))
            ?? BackgroundEvaluationSummary(issue: .signalUnavailable)
        // 第一主机不可达 → 顺位选到第二主机，仅第二主机身份被尝试。
        let firstIdentity = smbResourceIdentity(first.shares[0].smbURL)!
        #expect(box.mounted == [secondIdentity])
        #expect(!box.mounted.contains(firstIdentity))
        #expect(summary.issue == nil)
    }
}
