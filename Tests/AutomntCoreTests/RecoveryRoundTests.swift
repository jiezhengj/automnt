import Foundation
import Testing
@testable import AutomntCore

/// 共享恢复轮次协调器的行为回归（T009-c 规则部分）。
///
/// 这些断言覆盖 CLI 内置自测无法覆盖的组合：未知状态不误判、同路径备用只传播抑制、
/// superseded 剔除、预算/顺延与通知额度。业务配置全部经产品 API
/// （`FileConfigRepository.create/save`）生成，绝不手写活动 plist。
struct RecoveryRoundTests {

    // MARK: - 测试夹具

    private final class RoundHarness {
        let directory: URL
        var cleanupCalls: [String] = []
        var mountCalls: [String] = []
        var cleanupResult = true
        var mountResult = true
        var failure: RecoveryAttemptOutcome = .shareRejected
        var budget: TimeInterval = 30
        /// 可注入时钟：清理账写入与 updatedAt 断言需要一个确定的时间戳。
        var now = Date(timeIntervalSince1970: 1_700_000_000)

        init(directory: URL) { self.directory = directory }

        var effects: RecoveryRoundEffects {
            RecoveryRoundEffects(
                cleanup: { [self] path in cleanupCalls.append(path); return cleanupResult },
                mount: { [self] identity in
                    mountCalls.append(identity)
                    return RecoveryMountAttempt(succeeded: mountedOverride ?? mountResult,
                                                failure: failure)
                },
                budgetRemaining: { [self] in budget })
        }

        /// 需要按轮次切换挂载结果时使用。
        var mountedOverride: Bool?

        func request(configuration: AutomntConfig, load: MountRecoveryStoreLoad,
                     network: String = "round-network", login: String = "round-login",
                     mounted: Set<String> = [], manual: Bool = false) -> RecoveryRoundRequest {
            RecoveryRoundRequest(configuration: configuration, load: load,
                sessionNetwork: network, sessionLoginEpoch: login, mountedIdentities: mounted,
                manualRecovery: manual,
                volumes: configuredRecoveryVolumes(from: configuration),
                now: { [self] in now })
        }

        /// 只针对给定的卷集合构造请求（用于顺位独占/备用身份场景）。
        func request(configuration: AutomntConfig, load: MountRecoveryStoreLoad,
                     volumes: [RecoveryRoundConfiguredVolume], network: String = "round-network",
                     login: String = "round-login", mounted: Set<String> = [],
                     manual: Bool = false) -> RecoveryRoundRequest {
            RecoveryRoundRequest(configuration: configuration, load: load,
                sessionNetwork: network, sessionLoginEpoch: login, mountedIdentities: mounted,
                manualRecovery: manual, volumes: volumes, now: { [self] in now })
        }
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("automnt-round-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// 经产品 API 生成业务配置（本文件不手写任何 plist）。
    private func productConfiguration(directory: URL, hosts: [HostConfig]) throws -> AutomntConfig {
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let configuration = AutomntConfig(retryPolicy: RetryPolicy(maxAttempts: 1, intervalMs: 100,
                                                                   maxTotalWindowMs: 1000),
                                          hosts: hosts)
        _ = try repository.create(configuration)
        let saved = try repository.read().configuration
        // 产品 API 往返：保存一次修改后的副本，确认后续断言使用的配置确实由仓库产出。
        var updated = saved
        updated.autoMountRecovery = true
        _ = try repository.save(updated, baseRevision: try repository.read().revision)
        return try repository.read().configuration
    }

    private func snapshot(_ volume: RecoveryRoundConfiguredVolume, present: Bool,
                          reachable: Bool, health: VolumeHealthEvidence = .unavailable) -> RecoveryRoundVolumeSnapshot {
        RecoveryRoundVolumeSnapshot(identity: volume.identity, mountPoint: volume.mountPoint,
            host: volume.host, port: volume.port, presentInMountTable: present,
            observedPath: present ? volume.mountPoint : nil, hostReachable: reachable, health: health)
    }

    private func observe(present: @escaping (String) -> Bool = { _ in false },
                         reachable: @escaping (String) -> Bool = { _ in true },
                         health: @escaping (String) -> VolumeHealthEvidence = { _ in .unavailable })
        -> (RecoveryRoundConfiguredVolume) -> RecoveryRoundVolumeSnapshot {
        { volume in
            let isPresent = present(volume.identity)
            return RecoveryRoundVolumeSnapshot(identity: volume.identity, mountPoint: volume.mountPoint,
                host: volume.host, port: volume.port, presentInMountTable: isPresent,
                observedPath: isPresent ? volume.mountPoint : nil,
                hostReachable: reachable(volume.identity), health: health(volume.identity))
        }
    }

    // MARK: - 1. 未知状态不误判为「从未挂载」

    @Test func unreadableStateSuppressesInsteadOfFirstUseMount() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = "state-host.example"
        let configuration = try productConfiguration(directory: directory, hosts: [
            HostConfig(host: host, shares: [SMBShareConfig(name: "Shared", smbURL: "smb://\(host)/Shared",
                                                           mountPoint: "/Volumes/Shared")])])
        let volume = configuredRecoveryVolumes(from: configuration)[0]
        let harness = RoundHarness(directory: directory)

        let corrupt = RecoveryRoundPlanner.run(
            request: harness.request(configuration: configuration, load: .corrupt(reason: "state file unreadable")),
            observe: observe(), effects: harness.effects)

        #expect(corrupt.plan == [RecoveryVolumePlan(identity: volume.identity,
                                                    mountPoint: volume.mountPoint, action: .suppress)])
        #expect(corrupt.suppressed == [volume.identity])
        #expect(corrupt.recovered.isEmpty && corrupt.failed.isEmpty)
        #expect(harness.mountCalls.isEmpty)
        // 保守抑制：既不发失败通知，也不消耗通知额度。
        #expect(corrupt.notificationIdentities.isEmpty)
        #expect(corrupt.state.volumes[volume.identity]?.state == .suppressed)
        #expect(corrupt.state.volumes[volume.identity]?.notificationCount == 0)
        // FR-002/FR-010 的关键写入：保守抑制必须同时记下「曾健康挂载」，
        // 否则状态从损坏转为可读后，同一卷会落回 .neverMounted 并绕过会话抑制被重挂。
        #expect(corrupt.state.volumes[volume.identity]?.everHealthyMounted == true)
        // 保守方向：不写清理账，也不冒充曾健康挂载之外的健康许可。
        #expect(corrupt.state.cleanupLedger[volume.identity] == nil)
        #expect(corrupt.state.volumes[volume.identity]?.suppressionBoundary
                == RecoverySessionIdentity(network: "round-network", loginEpoch: "round-login",
                                           previous: nil).combined)

        // 对照：状态可读且确无记录（全新安装/新加入的启用卷）才走 FR-002④ 基线段挂载。
        let fresh = RecoveryRoundPlanner.run(
            request: harness.request(configuration: configuration, load: .absent),
            observe: observe(), effects: harness.effects)
        #expect(fresh.plan == [RecoveryVolumePlan(identity: volume.identity,
                                                  mountPoint: volume.mountPoint, action: .recover)])
        #expect(fresh.recovered == [volume.identity])
        #expect(fresh.suppressed.isEmpty)
    }

    /// DEF-1 闭环：状态从「损坏」转为「可读」后，同一卷 MUST NOT 被重新挂载。
    ///
    /// 第一轮 `.corrupt` 保守抑制并记下 `everHealthyMounted`；第二轮状态可读
    /// （该轮账本里已有这条记录）时，判定必须落回 `.healthyEject`（会话抑制），
    /// 而不是 `.neverMounted`（FR-002④ 基线段挂载）——即会话抑制未被绕过。
    @Test func corruptStateNeverFallsThroughToRemountOnceReadableAgain() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = "recoverable-state.example"
        let configuration = try productConfiguration(directory: directory, hosts: [
            HostConfig(host: host, shares: [SMBShareConfig(name: "Shared", smbURL: "smb://\(host)/Shared",
                                                           mountPoint: "/Volumes/Shared")])])
        let volume = configuredRecoveryVolumes(from: configuration)[0]
        let boundary = RecoverySessionIdentity(network: "round-network", loginEpoch: "round-login",
                                              previous: nil).combined
        let harness = RoundHarness(directory: directory)

        // 第一轮：状态损坏 → 保守抑制。
        let corrupt = RecoveryRoundPlanner.run(
            request: harness.request(configuration: configuration, load: .corrupt(reason: "state file unreadable")),
            observe: observe(), effects: harness.effects)
        #expect(corrupt.plan == [RecoveryVolumePlan(identity: volume.identity,
                                                    mountPoint: volume.mountPoint, action: .suppress)])
        #expect(corrupt.state.volumes[volume.identity]?.everHealthyMounted == true)
        #expect(harness.mountCalls.isEmpty)

        // 第二轮：同一账本转为可读；观测仍是「缺失且主机可达」。
        // 若 everHealthyMounted 未保留，这里会得到 .neverMounted 并被真实挂载。
        let persisted = corrupt.state
        let readable = RecoveryRoundPlanner.run(
            request: harness.request(configuration: configuration, load: .loaded(persisted)),
            observe: observe(), effects: harness.effects)

        #expect(readable.plan == [RecoveryVolumePlan(identity: volume.identity,
                                                     mountPoint: volume.mountPoint, action: .suppress)])
        #expect(readable.plan.contains { $0.action == .recover } == false)
        #expect(readable.recovered.isEmpty)
        #expect(readable.suppressed == [volume.identity])
        #expect(harness.mountCalls.isEmpty)
        #expect(readable.state.volumes[volume.identity]?.state == .suppressed)
        #expect(readable.state.volumes[volume.identity]?.suppressionBoundary == boundary)
        #expect(readable.notificationIdentities.isEmpty)

        // 判定层复核：该记录必须被判为 healthyEject，且明确不具恢复资格。
        let signal = judgeRecoverySignal(volumeKey: volume.identity, presentInMountTable: false,
            hostReachable: true, record: readable.state.volumes[volume.identity],
            cleanupLedger: readable.state.cleanupLedger, stateReadable: true)
        #expect(signal == .healthyEject)
        #expect(!MissingVolumeRecoveryPolicy.mayMount(signal: signal, enabled: true))
    }

    // MARK: - 2. 同路径备用身份只传播抑制

    @Test func sharedPathPeerPropagatesSuppressionWithoutHealthOrRepairPermission() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let primary = "primary.example"
        let backup = "backup.example"
        let configuration = try productConfiguration(directory: directory, hosts: [
            HostConfig(host: primary, shares: [SMBShareConfig(name: "Shared",
                smbURL: "smb://\(primary)/Shared", mountPoint: "/Volumes/Shared")]),
            HostConfig(host: backup, shares: [SMBShareConfig(name: "Shared",
                smbURL: "smb://\(backup)/Shared", mountPoint: "/Volumes/Shared")])])
        let volumes = configuredRecoveryVolumes(from: configuration)
        let first = volumes[0].identity
        let second = volumes[1].identity
        let boundary = RecoverySessionIdentity(network: "round-network", loginEpoch: "round-login",
                                               previous: nil).combined

        // 主身份在健康时被使用者弹出（本会话抑制）。
        var state = MountRecoveryStateFile(sessionBoundary: boundary, volumes: [first:
            MountRecoveryVolumeRecord(volumeKey: first, state: .suppressed,
                                      suppressionBoundary: boundary, everHealthyMounted: true)])
        let harness = RoundHarness(directory: directory)
        let result = RecoveryRoundPlanner.run(
            request: harness.request(configuration: configuration, load: .loaded(state)),
            observe: observe(), effects: harness.effects)

        #expect(result.plan.contains(RecoveryVolumePlan(identity: second,
                                                        mountPoint: "/Volumes/Shared", action: .suppress)))
        #expect(result.suppressed.contains(second))
        #expect(result.recovered.isEmpty)
        #expect(harness.mountCalls.isEmpty)
        #expect(result.notificationIdentities.isEmpty)
        // 只传播抑制：备用身份不继承健康记录，也不获得清理/修复许可。
        #expect(result.state.volumes[second]?.state == .suppressed)
        #expect(result.state.volumes[second]?.everHealthyMounted == false)
        #expect(result.state.volumes[second]?.repairEjectEvidence == false)
        #expect(result.state.cleanupLedger[second] == nil)

        // 会话边界变化后抑制解除：备用身份按正常资格评估（此处沿用主机顺位独占，
        // 只把备用主机纳入本轮，与真实轮次的卷集合一致）。
        state = result.state
        let releasedHarness = RoundHarness(directory: directory)
        let releaseRequest = RecoveryRoundRequest(configuration: configuration, load: .loaded(state),
            sessionNetwork: "round-network-changed", sessionLoginEpoch: "round-login",
            mountedIdentities: [], manualRecovery: false, volumes: [volumes[1]])
        let released = RecoveryRoundPlanner.run(request: releaseRequest,
            observe: { volume in
                RecoveryRoundVolumeSnapshot(identity: volume.identity, mountPoint: volume.mountPoint,
                    host: volume.host, port: volume.port, presentInMountTable: false,
                    observedPath: nil, hostReachable: true, health: .unavailable)
            }, effects: releasedHarness.effects)
        #expect(released.recovered == [second])
        #expect(released.suppressed.isEmpty)
        #expect(released.notificationIdentities.isEmpty)
    }

    // MARK: - 3. superseded 路径剔除

    @Test func supersededPathLeavesNoFailureSuppressionOrNotification() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let primary = "stale.example"
        let backup = "takeover.example"
        let configuration = try productConfiguration(directory: directory, hosts: [
            HostConfig(host: primary, shares: [SMBShareConfig(name: "Shared",
                smbURL: "smb://\(primary)/Shared", mountPoint: "/Volumes/Shared")]),
            HostConfig(host: backup, shares: [SMBShareConfig(name: "Shared",
                smbURL: "smb://\(backup)/Shared", mountPoint: "/Volumes/Shared")])])
        let volumes = configuredRecoveryVolumes(from: configuration)
        let first = volumes[0].identity
        let second = volumes[1].identity

        // 旧主机已死卷（在表不可达），新主机可达并成功接管同一路径。
        let probe: (String, Int) -> Bool = { host, _ in host == backup }
        let relevant = RecoveryRoundPlanner.relevantVolumes(configuration: configuration,
            mountedIdentities: [first], probe: probe)
        #expect(Set(relevant.map(\.identity)) == Set([first, second]))

        let harness = RoundHarness(directory: directory)
        let request = RecoveryRoundRequest(configuration: configuration, load: .absent,
            sessionNetwork: "round-network", sessionLoginEpoch: "round-login",
            mountedIdentities: [first], manualRecovery: false, volumes: relevant)
        let result = RecoveryRoundPlanner.run(request: request,
            observe: observe(present: { $0 == first }, reachable: { $0 == second }),
            effects: harness.effects)

        #expect(result.recovered == [second])
        #expect(result.failed.isEmpty)
        #expect(result.suppressed.isEmpty)
        #expect(result.notificationIdentities.isEmpty)
        #expect(harness.mountCalls == [second])
        // 旧主机的离线记录仍保留证据，只是不再报告为失败。
        #expect(result.state.volumes[first]?.repairEjectEvidence == true)
        #expect(result.state.volumes[first]?.everHealthyMounted == true)

        // 手动恢复：清理旧身份的陈旧抑制与通知额度，使其重新回到待恢复。
        var seeded = result.state
        seeded.volumes[first]?.state = .suppressed
        seeded.volumes[first]?.suppressionBoundary = "stale-boundary"
        seeded.volumes[first]?.notificationCount = 2
        let manualHarness = RoundHarness(directory: directory)
        let manualRequest = RecoveryRoundRequest(configuration: configuration, load: .loaded(seeded),
            sessionNetwork: "round-network", sessionLoginEpoch: "round-login",
            mountedIdentities: [first], manualRecovery: true, volumes: relevant)
        let manual = RecoveryRoundPlanner.run(request: manualRequest,
            observe: observe(present: { $0 == first }, reachable: { $0 == second }),
            effects: manualHarness.effects)
        #expect(manual.recovered.contains(second))
        #expect(manual.state.volumes[first]?.state == .pendingRecovery)
        #expect(manual.state.volumes[first]?.suppressionBoundary == nil)
        #expect(manual.state.volumes[first]?.notificationCount == 0)
    }

    // MARK: - 4. 预算耗尽与整轮顺延

    @Test func exhaustedBudgetStopsProbingAndBoundedAttemptsSuppressLaterRounds() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = "budget.example"
        let configuration = try productConfiguration(directory: directory, hosts: [
            HostConfig(host: host, shares: [SMBShareConfig(name: "Shared", smbURL: "smb://\(host)/Shared",
                                                           mountPoint: "/Volumes/Shared")])])
        let volume = configuredRecoveryVolumes(from: configuration)[0]
        var bounded = configuration
        bounded.retryPolicy = RetryPolicy(maxAttempts: 2, intervalMs: 100, maxTotalWindowMs: 1000)

        // 预算提前耗尽：不发起任何尝试，也不消耗通知额度以外的副作用。
        let exhausted = RoundHarness(directory: directory)
        exhausted.budget = -1
        let exhaustedResult = RecoveryRoundPlanner.run(
            request: exhausted.request(configuration: bounded, load: .absent),
            observe: observe(), effects: exhausted.effects)
        #expect(exhausted.mountCalls.isEmpty)
        #expect(exhaustedResult.attempted == 0)
        #expect(exhaustedResult.failed == [volume.identity])
        #expect(exhaustedResult.state.volumes[volume.identity]?.state == .pendingRecovery)
        #expect(exhaustedResult.state.attempts[volume.identity]?.isEmpty == true)

        // 有界重试：恰好耗尽配置次数后进入失败，随后续轮按尝试上限抑制。
        let limited = RoundHarness(directory: directory)
        limited.mountResult = false
        let failed = RecoveryRoundPlanner.run(
            request: limited.request(configuration: bounded, load: .absent),
            observe: observe(), effects: limited.effects)
        #expect(limited.mountCalls.count == 2)
        #expect(failed.attempted == 2)
        #expect(failed.failed == [volume.identity])
        #expect(failed.state.volumes[volume.identity]?.attemptCount == 2)
        let decision = BaselineMountDecision.decide(identity: volume.identity, path: .absent,
            recovery: .loaded(failed.state), configuration: bounded,
            mountPoint: volume.mountPoint, allowRecovery: true)
        #expect(decision == .suppressed)
    }

    @Test func deferredRoundDoesNotConsumeBudgetNotificationOrState() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let hosts = ["defer-one.example", "defer-two.example"].map { host in
            HostConfig(host: host, shares: [SMBShareConfig(name: "Shared", smbURL: "smb://\(host)/Shared",
                                                            mountPoint: "/Volumes/\(host)")])
        }
        let configuration = try productConfiguration(directory: directory, hosts: hosts)
        let volumes = configuredRecoveryVolumes(from: configuration)

        let deferred = RecoveryRoundPlanner.deferRound(configuration: configuration)
        #expect(deferred.deferredIdentities == volumes.map(\.identity))
        // 非空前提：避免 allSatisfy 对空 plan 真空为真而失去保护力（DEF-3）。
        #expect(!deferred.plan.isEmpty)
        #expect(deferred.plan.count == volumes.count)
        #expect(deferred.plan == volumes.map { RecoveryVolumePlan(identity: $0.identity,
                                                                  mountPoint: $0.mountPoint, action: .deferred) })
        #expect(deferred.plan.allSatisfy { $0.action == .deferred })
        #expect(deferred.attempted == 0)
        #expect(deferred.failed.isEmpty && deferred.recovered.isEmpty && deferred.suppressed.isEmpty)
        #expect(deferred.notificationIdentities.isEmpty)
        #expect(deferred.state == MountRecoveryStateFile())

        // 独立事实：延后轮次不得触碰副作用与账本，也不得写清理账。
        let harness = RoundHarness(directory: directory)
        let executed = RecoveryRoundPlanner.run(
            request: harness.request(configuration: configuration, load: .absent),
            observe: observe(), effects: harness.effects)
        #expect(harness.mountCalls == volumes.map(\.identity))
        #expect(harness.cleanupCalls.isEmpty)
        #expect(executed.recovered == volumes.map(\.identity))
        #expect(executed.failed.isEmpty && executed.suppressed.isEmpty)
        #expect(executed.deferredIdentities.isEmpty)
        #expect(executed.state.cleanupLedger.isEmpty)
        // deferRound 自身绝不产生任何账本或副作用。
        #expect(deferred.state == MountRecoveryStateFile())
    }

    // MARK: - 5. 通知额度：上限 2、成功恢复重置、抑制不计

    @Test func notificationBudgetCapsAtTwoAndResetsOnRecovery() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = "notify.example"
        let configuration = try productConfiguration(directory: directory, hosts: [
            HostConfig(host: host, shares: [SMBShareConfig(name: "Shared", smbURL: "smb://\(host)/Shared",
                                                           mountPoint: "/Volumes/Shared")])])
        let volume = configuredRecoveryVolumes(from: configuration)[0]
        let harness = RoundHarness(directory: directory)
        harness.mountResult = false
        var load = MountRecoveryStoreLoad.absent

        // 第 1、2 轮各消费一次；第 3 轮静默。
        for round in 1...3 {
            let result = RecoveryRoundPlanner.run(
                request: harness.request(configuration: configuration, load: load),
                observe: observe(), effects: harness.effects)
            #expect(result.failed == [volume.identity])
            #expect(result.notificationIdentities == (round <= 2 ? [volume.identity] : []))
            load = .loaded(result.state)
        }
        #expect(load.file.volumes[volume.identity]?.notificationCount == 2)

        // 成功恢复：重置计数并清除修复证据。
        harness.mountResult = true
        let recovered = RecoveryRoundPlanner.run(
            request: harness.request(configuration: configuration, load: load),
            observe: observe(), effects: harness.effects)
        #expect(recovered.recovered == [volume.identity])
        #expect(recovered.state.volumes[volume.identity]?.notificationCount == 0)
        #expect(recovered.state.volumes[volume.identity]?.repairEjectEvidence == false)

        // 抑制卷不进入通知集合，也不消耗额度。
        var suppressed = MountRecoveryStateFile(sessionBoundary: RecoverySessionIdentity(
            network: "round-network", loginEpoch: "round-login", previous: nil).combined,
            volumes: [volume.identity: MountRecoveryVolumeRecord(volumeKey: volume.identity,
                everHealthyMounted: true, notificationCount: 2)])
        let suppressedHarness = RoundHarness(directory: directory)
        let suppressedResult = RecoveryRoundPlanner.run(
            request: suppressedHarness.request(configuration: configuration, load: .loaded(suppressed)),
            observe: observe(), effects: suppressedHarness.effects)
        #expect(suppressedResult.suppressed == [volume.identity])
        #expect(suppressedResult.notificationIdentities.isEmpty)
        #expect(suppressedResult.state.volumes[volume.identity]?.notificationCount == 2)
        suppressed = suppressedResult.state
        #expect(suppressed.volumes[volume.identity]?.notificationCount == 2)
    }

    // MARK: - 6. 开关门与健康证据映射

    @Test func disabledAutomationPerformsNoClassification() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = "disabled.example"
        var configuration = try productConfiguration(directory: directory, hosts: [
            HostConfig(host: host, shares: [SMBShareConfig(name: "Shared", smbURL: "smb://\(host)/Shared",
                                                           mountPoint: "/Volumes/Shared")])])
        configuration.autoMountRecovery = false
        #expect(!RecoveryRoundPlanner.isPermitted(configuration: configuration))
        let harness = RoundHarness(directory: directory)
        let result = RecoveryRoundPlanner.run(
            request: harness.request(configuration: configuration, load: .absent),
            observe: observe(), effects: harness.effects)
        #expect(result.plan.isEmpty && result.attempted == 0)
        #expect(harness.mountCalls.isEmpty)
        #expect(result.state == MountRecoveryStateFile())

        #expect(RecoveryRoundPlanner.healthEvidence(nil) == .unavailable)
        #expect(RecoveryRoundPlanner.healthEvidence(true) == .healthy)
        #expect(RecoveryRoundPlanner.healthEvidence(false) == .failed)
        #expect(RecoveryRoundPlanner.retryWindowMilliseconds(configuration) == 1000)
    }

    // MARK: - 7. 轮次动作与清理账本的直接断言（DEF-4）

    /// `.attachHealthy`：已健康挂载的卷幂等跳过，并清除预算、修复证据与清理账。
    @Test func healthyAttachedVolumePlansAttachHealthyAndClearsStaleLedgers() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = "attached.example"
        let configuration = try productConfiguration(directory: directory, hosts: [
            HostConfig(host: host, shares: [SMBShareConfig(name: "Shared", smbURL: "smb://\(host)/Shared",
                                                           mountPoint: "/Volumes/Shared")])])
        let volume = configuredRecoveryVolumes(from: configuration)[0]
        let harness = RoundHarness(directory: directory)
        harness.now = Date(timeIntervalSince1970: 1_700_000_123)

        // 历史记录：曾修复证据 + 已耗尽预算 + 已消费通知额度 + 清理账残留 + 曾抑制。
        var seeded = MountRecoveryStateFile(
            sessionBoundary: RecoverySessionIdentity(network: "round-network", loginEpoch: "round-login",
                                                     previous: nil).combined,
            volumes: [volume.identity: MountRecoveryVolumeRecord(volumeKey: volume.identity,
                state: .pendingRecovery, suppressionBoundary: "stale", repairEjectEvidence: true,
                everHealthyMounted: true, attemptCount: 3, notificationCount: 2)],
            cleanupLedger: [volume.identity: 1], attempts: [volume.identity: []])
        let result = RecoveryRoundPlanner.run(
            request: harness.request(configuration: configuration, load: .loaded(seeded), mounted: [volume.identity]),
            observe: observe(present: { _ in true }, health: { _ in .healthy }),
            effects: harness.effects)

        #expect(result.plan == [RecoveryVolumePlan(identity: volume.identity,
                                                   mountPoint: volume.mountPoint, action: .attachHealthy)])
        #expect(harness.mountCalls.isEmpty)
        #expect(harness.cleanupCalls.isEmpty)
        #expect(result.attempted == 0)
        #expect(result.recovered.isEmpty && result.failed.isEmpty && result.suppressed.isEmpty)
        #expect(result.notificationIdentities.isEmpty)
        let record = result.state.volumes[volume.identity]
        #expect(record?.state == .attached)
        #expect(record?.everHealthyMounted == true)
        #expect(record?.repairEjectEvidence == false)
        #expect(record?.attemptCount == 0)
        #expect(record?.notificationCount == 0)
        #expect(record?.suppressionBoundary == nil)
        // 成功挂载清除抑制及其清理账（FR-002）。
        #expect(result.state.cleanupLedger[volume.identity] == nil)
        seeded = result.state
        #expect(seeded.volumes[volume.identity]?.state == .attached)
    }

    /// `.cleanupThenRecover` + 清理账成功写入：可达但不健康的在表死卷先清理再恢复。
    @Test func reachableUnhealthyVolumeCleansThenRecoversAndRecordsLedger() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = "dead.example"
        let configuration = try productConfiguration(directory: directory, hosts: [
            HostConfig(host: host, shares: [SMBShareConfig(name: "Shared", smbURL: "smb://\(host)/Shared",
                                                           mountPoint: "/Volumes/Shared")])])
        let volume = configuredRecoveryVolumes(from: configuration)[0]
        let harness = RoundHarness(directory: directory)
        harness.now = Date(timeIntervalSince1970: 1_700_000_500)

        let result = RecoveryRoundPlanner.run(
            request: harness.request(configuration: configuration, load: .absent,
                                     mounted: [volume.identity]),
            observe: observe(present: { _ in true }, health: { _ in .failed }),
            effects: harness.effects)

        #expect(result.plan == [RecoveryVolumePlan(identity: volume.identity,
                                                   mountPoint: volume.mountPoint, action: .cleanupThenRecover)])
        // 清理使用观测到的挂载路径，且必须真的被调用一次。
        #expect(harness.cleanupCalls == [volume.mountPoint])
        #expect(harness.mountCalls == [volume.identity])
        #expect(result.recovered == [volume.identity])
        #expect(result.attempted == 1)
        // 清理成功才写入清理账；随后成功恢复又按 FR-002 清除该账。
        #expect(result.state.cleanupLedger[volume.identity] == nil)
        #expect(result.state.volumes[volume.identity]?.state == .attached)
        #expect(result.state.volumes[volume.identity]?.everHealthyMounted == true)
        #expect(result.state.volumes[volume.identity]?.repairEjectEvidence == false)

        // 清理成功但挂载失败：清理账必须被真实写入并保留（RecoveryRound.swift 的
        // `cleanupLedger[identity] = working.updatedAt`），否则删除该行不会被发现。
        let ledgerHarness = RoundHarness(directory: directory)
        ledgerHarness.now = Date(timeIntervalSince1970: 1_700_000_777)
        ledgerHarness.mountResult = false
        let ledger = RecoveryRoundPlanner.run(
            request: ledgerHarness.request(configuration: configuration, load: .absent,
                                           mounted: [volume.identity]),
            observe: observe(present: { _ in true }, health: { _ in .failed }),
            effects: ledgerHarness.effects)
        #expect(ledger.plan == [RecoveryVolumePlan(identity: volume.identity,
                                                   mountPoint: volume.mountPoint, action: .cleanupThenRecover)])
        #expect(ledgerHarness.cleanupCalls == [volume.mountPoint])
        #expect(ledger.state.cleanupLedger[volume.identity] == ledgerHarness.now.timeIntervalSince1970)
        #expect(ledger.state.volumes[volume.identity]?.state == .pendingRecovery)
        #expect(ledger.failed == [volume.identity])

        // 对照：清理失败时清理账不得被伪造（同一轮内 cleanupThenRecover 仍成立）。
        let failedHarness = RoundHarness(directory: directory)
        failedHarness.cleanupResult = false
        failedHarness.mountResult = false
        let failed = RecoveryRoundPlanner.run(
            request: failedHarness.request(configuration: configuration, load: .absent,
                                           mounted: [volume.identity]),
            observe: observe(present: { _ in true }, health: { _ in .failed }),
            effects: failedHarness.effects)
        #expect(failedHarness.cleanupCalls == [volume.mountPoint])
        #expect(failed.state.cleanupLedger[volume.identity] == nil)
        #expect(failed.state.volumes[volume.identity]?.repairEjectEvidence == true)
        #expect(failed.failed == [volume.identity])
    }

    /// `.pendingUnreachable`：主机不可达时不执行清理/挂载，保留待恢复证据。
    @Test func unreachableVolumePlansPendingUnreachableWithoutCleanup() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = "unreachable.example"
        let configuration = try productConfiguration(directory: directory, hosts: [
            HostConfig(host: host, shares: [SMBShareConfig(name: "Shared", smbURL: "smb://\(host)/Shared",
                                                           mountPoint: "/Volumes/Shared")])])
        let volume = configuredRecoveryVolumes(from: configuration)[0]

        // 在表但不可达的死卷：不得阻塞在强制卸载上，只保留死卷证据。
        let harness = RoundHarness(directory: directory)
        let dead = RecoveryRoundPlanner.run(
            request: harness.request(configuration: configuration, load: .absent,
                                     mounted: [volume.identity]),
            observe: observe(present: { _ in true }, reachable: { _ in false }),
            effects: harness.effects)
        #expect(dead.plan == [RecoveryVolumePlan(identity: volume.identity,
                                                 mountPoint: volume.mountPoint, action: .pendingUnreachable)])
        #expect(harness.cleanupCalls.isEmpty)
        #expect(harness.mountCalls.isEmpty)
        #expect(dead.attempted == 0)
        #expect(dead.failed == [volume.identity])
        #expect(dead.state.cleanupLedger[volume.identity] == nil)
        #expect(dead.state.volumes[volume.identity]?.state == .pendingRecovery)
        #expect(dead.state.volumes[volume.identity]?.repairEjectEvidence == true)
        #expect(dead.state.attempts[volume.identity]?.first?.outcome == .hostUnreachable)

        // 缺失但主机不可达的启用卷：同样只记待恢复，不消耗挂载尝试。
        let missingHarness = RoundHarness(directory: directory)
        let missing = RecoveryRoundPlanner.run(
            request: missingHarness.request(configuration: configuration, load: .absent),
            observe: observe(reachable: { _ in false }), effects: missingHarness.effects)
        #expect(missing.plan == [RecoveryVolumePlan(identity: volume.identity,
                                                    mountPoint: volume.mountPoint, action: .pendingUnreachable)])
        #expect(missing.failed == [volume.identity])
        #expect(missingHarness.mountCalls.isEmpty)
        #expect(missing.state.attempts[volume.identity]?.first?.outcome == .hostUnreachable)
    }

    /// `.recover`：可读状态 + 缺失 + 主机可达 + 非在表，走普通恢复（不触发清理）。
    @Test func missingReachableVolumePlansRecoverWithoutCleanup() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = "recover.example"
        let configuration = try productConfiguration(directory: directory, hosts: [
            HostConfig(host: host, shares: [SMBShareConfig(name: "Shared", smbURL: "smb://\(host)/Shared",
                                                           mountPoint: "/Volumes/Shared")])])
        let volume = configuredRecoveryVolumes(from: configuration)[0]
        let harness = RoundHarness(directory: directory)
        let result = RecoveryRoundPlanner.run(
            request: harness.request(configuration: configuration, load: .absent),
            observe: observe(), effects: harness.effects)
        #expect(result.plan == [RecoveryVolumePlan(identity: volume.identity,
                                                   mountPoint: volume.mountPoint, action: .recover)])
        #expect(harness.cleanupCalls.isEmpty)
        #expect(harness.mountCalls == [volume.identity])
        #expect(result.recovered == [volume.identity])
    }
}
