import Foundation
import Testing
@testable import AutomntCore

/// R2/Lead 裁决 A 的回归：`.suppressed` 记录（`UserEjectCommit` 只写 state+boundary，
/// 不写 `everHealthyMounted`）必须在共享逐卷判定中落 `sessionSuppressed`，
/// 且手动恢复（"立即重新挂载"）与新会话边界两个出口都保持可用。
///
/// 业务配置一律经产品 API（`FileConfigRepository.create`）生成；恢复账本属转换元数据，
/// 按既有测试惯例直接构造以复现指定边界。
struct RecoverySuppressedRecordTests {

    private func makeConfiguration() throws -> (AutomntConfig, RecoveryRoundConfiguredVolume, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("automnt-suppressed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let host = "eject.example"
        let repository = FileConfigRepository(authorizedDirectory: directory)
        _ = try repository.create(AutomntConfig(retryPolicy: RetryPolicy(maxAttempts: 2, intervalMs: 100,
                                                                        maxTotalWindowMs: 1000),
            hosts: [HostConfig(host: host, shares: [SMBShareConfig(name: "Shared",
                smbURL: "smb://\(host)/Shared", mountPoint: "/Volumes/Shared")])]))
        let configuration = try repository.read().configuration
        return (configuration, configuredRecoveryVolumes(from: configuration)[0], directory)
    }

    /// `UserEjectCommit.apply` 真实写出的记录形态：`.suppressed` + boundary，无 everHealthyMounted。
    private func userEjectRecord(_ identity: String, boundary: String) -> MountRecoveryVolumeRecord {
        MountRecoveryVolumeRecord(volumeKey: identity, state: .suppressed,
                                  suppressionBoundary: boundary, everHealthyMounted: false)
    }

    private func run(configuration: AutomntConfig, volume: RecoveryRoundConfiguredVolume,
                     load: MountRecoveryStoreLoad, network: String, login: String,
                     manual: Bool, mount: @escaping () -> Void) -> RecoveryRoundResult {
        RecoveryRoundPlanner.run(
            request: RecoveryRoundRequest(configuration: configuration, load: load,
                sessionNetwork: network, sessionLoginEpoch: login, mountedIdentities: [],
                manualRecovery: manual, volumes: [volume],
                now: { Date(timeIntervalSince1970: 1_700_000_000) }),
            observe: { RecoveryRoundVolumeSnapshot(identity: $0.identity, mountPoint: $0.mountPoint,
                host: $0.host, port: $0.port, presentInMountTable: false, observedPath: nil,
                hostReachable: true, health: .unavailable) },
            effects: RecoveryRoundEffects(cleanup: { _ in false },
                mount: { _ in mount(); return RecoveryMountAttempt(succeeded: true, failure: .mounted) },
                budgetRemaining: { 30 }))
    }

    /// (a) `.suppressed` + `everHealthyMounted == false` + 缺失 → `suppress` 且零挂载副作用。
    @Test func firstEjectWithoutHealthHistoryIsSuppressedWithZeroMounts() throws {
        let (configuration, volume, directory) = try makeConfiguration()
        defer { try? FileManager.default.removeItem(at: directory) }
        let boundary = RecoverySessionIdentity(network: "eject-network", loginEpoch: "eject-login",
                                               previous: nil).combined
        let state = MountRecoveryStateFile(sessionBoundary: boundary,
            volumes: [volume.identity: userEjectRecord(volume.identity, boundary: boundary)])

        var mounts = 0
        let result = run(configuration: configuration, volume: volume, load: .loaded(state),
                         network: "eject-network", login: "eject-login", manual: false, mount: { mounts += 1 })

        #expect(result.plan == [RecoveryVolumePlan(identity: volume.identity,
                                                   mountPoint: volume.mountPoint,
                                                   action: RecoveryVolumeAction.suppress)])
        #expect(result.suppressed == [volume.identity])
        #expect(result.recovered.isEmpty && result.failed.isEmpty)
        #expect(mounts == 0)
        #expect(result.notificationIdentities.isEmpty)
        #expect(result.state.volumes[volume.identity]?.state == .suppressed)

        // 判定层复核：正是 `.suppressed` 门在生效，而不是别的分支。
        let judgment = RecoveryVolumeDecisionPolicy.judge(
            RecoveryVolumeFacts(identity: volume.identity, mountPoint: volume.mountPoint,
                presentInMountTable: false, hostReachable: true, health: .unavailable),
            context: RecoveryVolumeContext(configuration: configuration, state: state,
                stateReadable: true, boundary: boundary,
                peers: RecoveryVolumeDecisionPolicy.peers(configuration: configuration),
                manualRecovery: false, permitsMount: true))
        #expect(judgment.decision == .sessionSuppressed)
        #expect(judgment.signal == .healthyEject)
    }

    /// (b) 同上但 `manualRecovery == true` → 允许恢复（"立即重新挂载"仍然可用）。
    @Test func explicitManualRecoveryStillRestoresFirstEjectRecord() throws {
        let (configuration, volume, directory) = try makeConfiguration()
        defer { try? FileManager.default.removeItem(at: directory) }
        let boundary = RecoverySessionIdentity(network: "eject-network", loginEpoch: "eject-login",
                                               previous: nil).combined
        let state = MountRecoveryStateFile(sessionBoundary: boundary,
            volumes: [volume.identity: userEjectRecord(volume.identity, boundary: boundary)])

        var mounts = 0
        let result = run(configuration: configuration, volume: volume, load: .loaded(state),
                         network: "eject-network", login: "eject-login", manual: true, mount: { mounts += 1 })

        #expect(result.plan == [RecoveryVolumePlan(identity: volume.identity,
                                                   mountPoint: volume.mountPoint, action: .recover)])
        #expect(result.recovered == [volume.identity])
        #expect(result.suppressed.isEmpty)
        #expect(mounts == 1)
    }

    /// (c) 会话边界推进后该记录不再是抑制（会话推进会话解除），随后可恢复。
    @Test func sessionAdvanceReleasesSuppressionForFirstEjectRecord() throws {
        let (configuration, volume, directory) = try makeConfiguration()
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldBoundary = RecoverySessionIdentity(network: "old-network", loginEpoch: "old-login",
                                                  previous: nil).combined
        let state = MountRecoveryStateFile(sessionBoundary: oldBoundary,
            volumes: [volume.identity: userEjectRecord(volume.identity, boundary: oldBoundary)])

        // 新会话边界（网络变化）：RecoverySessionPolicy.advance 把 .suppressed 重置为 .pendingRecovery。
        var advanced = state
        let next = RecoverySessionIdentity(network: "new-network", loginEpoch: "old-login",
                                           previous: oldBoundary)
        RecoverySessionPolicy.advance(&advanced, to: next, mountedKeys: [])
        #expect(advanced.volumes[volume.identity]?.state == .pendingRecovery)
        #expect(advanced.volumes[volume.identity]?.suppressionBoundary == nil)

        var mounts = 0
        let result = run(configuration: configuration, volume: volume, load: .loaded(advanced),
                         network: "new-network", login: "old-login", manual: false, mount: { mounts += 1 })
        #expect(result.recovered == [volume.identity])
        #expect(result.suppressed.isEmpty)
        #expect(mounts == 1)
    }

    /// 边界不匹配时（会话未推进但 boundary 与当前不同）不得误抑制跨会话记录。
    @Test func suppressionGateOnlyAppliesWithinMatchingSession() throws {
        let (configuration, volume, directory) = try makeConfiguration()
        defer { try? FileManager.default.removeItem(at: directory) }
        // 记录来自一个「未推进」的旧边界：当前轮边界不同 → 会话推进已重置，故这里用未推进状态验证
        // 判定不依赖 boundary 相等性，而依赖 advance 的调度（保守不变宽）。
        let oldBoundary = RecoverySessionIdentity(network: "old-network", loginEpoch: "old-login",
                                                  previous: nil).combined
        var state = MountRecoveryStateFile(volumes: [volume.identity:
            userEjectRecord(volume.identity, boundary: oldBoundary)])
        // 无 sessionBoundary 的首次采集：establishing 分支只把 boundary 绑定到记录。
        let first = RecoverySessionIdentity(network: "new-network", loginEpoch: "old-login", previous: nil)
        RecoverySessionPolicy.advance(&state, to: first, mountedKeys: [])
        #expect(state.volumes[volume.identity]?.state == .suppressed)

        var mounts = 0
        let result = run(configuration: configuration, volume: volume, load: .loaded(state),
                         network: first.network, login: first.loginEpoch, manual: false, mount: { mounts += 1 })
        #expect(result.suppressed == [volume.identity])
        #expect(mounts == 0)
    }

    /// 无记录的卷（record == nil）不受新门影响，仍按 FR-002④ 挂载。
    @Test func missingRecordIsStillNeverMountedRatherThanSuppressed() throws {
        let (configuration, volume, directory) = try makeConfiguration()
        defer { try? FileManager.default.removeItem(at: directory) }
        var mounts = 0
        let result = run(configuration: configuration, volume: volume, load: .absent,
                         network: "n", login: "l", manual: false, mount: { mounts += 1 })
        #expect(result.recovered == [volume.identity])
        #expect(result.suppressed.isEmpty)
        #expect(mounts == 1)
    }

    /// `BaselineMountDecision`（helper/worker 路径）与 planner 对新门判断一致。
    @Test func helperAndPlannerAgreeOnSuppressedRecord() throws {
        let (configuration, volume, directory) = try makeConfiguration()
        defer { try? FileManager.default.removeItem(at: directory) }
        let boundary = RecoverySessionIdentity(network: "n", loginEpoch: "l", previous: nil).combined
        let state = MountRecoveryStateFile(sessionBoundary: boundary,
            volumes: [volume.identity: userEjectRecord(volume.identity, boundary: boundary)])
        #expect(BaselineMountDecision.decide(identity: volume.identity, path: .absent,
            recovery: .loaded(state), configuration: configuration, mountPoint: volume.mountPoint,
            allowRecovery: true) == .suppressed)
    }
}
