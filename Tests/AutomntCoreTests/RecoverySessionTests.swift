import Foundation
import Testing
@testable import AutomntCore

struct RecoverySessionTests {
    @Test func unavailableNetworkAndFirstReadableSnapshotPreserveEject() throws {
        let login = UUID().uuidString
        let key = UUID().uuidString
        let network = UUID().uuidString
        let unknown = RecoverySessionIdentity(network: nil, loginEpoch: login, previous: nil)
        var state = MountRecoveryStateFile(sessionBoundary: unknown.combined, volumes: [key:
            MountRecoveryVolumeRecord(volumeKey: key, state: .suppressed, suppressionBoundary: unknown.combined,
                                      everHealthyMounted: true, notificationCount: 2)])
        RecoverySessionPolicy.advance(&state, to: unknown, mountedKeys: [])
        #expect(state.volumes[key]?.state == .suppressed)
        let readable = RecoverySessionIdentity(network: network, loginEpoch: login, previous: state.sessionBoundary)
        RecoverySessionPolicy.advance(&state, to: readable, mountedKeys: [])
        #expect(state.volumes[key]?.state == .suppressed)
        #expect(state.volumes[key]?.suppressionBoundary == readable.combined)
        #expect(state.volumes[key]?.notificationCount == 2)
        let unavailable = RecoverySessionIdentity(network: nil, loginEpoch: login, previous: state.sessionBoundary)
        #expect(unavailable == readable)
        RecoverySessionPolicy.advance(&state, to: unavailable, mountedKeys: [])
        #expect(state.volumes[key]?.state == .suppressed)
    }

    @Test func actualBoundaryResetsBudgetWithoutLosingHealthAndCleanupEvidence() {
        let network = UUID().uuidString
        let login = UUID().uuidString
        let original = RecoverySessionIdentity(network: network, loginEpoch: login, previous: nil)
        let missing = UUID().uuidString
        let mounted = UUID().uuidString
        let newVolume = UUID().uuidString
        var state = MountRecoveryStateFile(sessionBoundary: original.combined, volumes: [
            missing: MountRecoveryVolumeRecord(volumeKey: missing, state: .suppressed,
                suppressionBoundary: original.combined, everHealthyMounted: true, notificationCount: 2),
            mounted: MountRecoveryVolumeRecord(volumeKey: mounted, everHealthyMounted: true, notificationCount: 2),
            newVolume: MountRecoveryVolumeRecord(volumeKey: newVolume)
        ], cleanupLedger: [missing: 1])
        let next = RecoverySessionIdentity(network: UUID().uuidString, loginEpoch: login, previous: state.sessionBoundary)
        RecoverySessionPolicy.advance(&state, to: next, mountedKeys: [mounted])
        #expect(state.volumes[missing]?.state == .pendingRecovery)
        #expect(state.volumes[missing]?.suppressionBoundary == nil)
        #expect(state.volumes[missing]?.everHealthyMounted == true)
        #expect(state.volumes[missing]?.notificationCount == 0)
        #expect(state.volumes[mounted]?.state == .attached)
        #expect(state.volumes[newVolume]?.state == .attached)
        #expect(state.cleanupLedger[missing] == 1)
        #expect(judgeRecoverySignal(volumeKey: missing, presentInMountTable: false, hostReachable: true,
            record: state.volumes[missing], cleanupLedger: state.cleanupLedger, stateReadable: true) == .productCleanup)
        let before = state
        RecoverySessionPolicy.advance(&state, to: next, mountedKeys: [mounted])
        #expect(state == before)
        let relogin = RecoverySessionIdentity(network: nil, loginEpoch: UUID().uuidString, previous: next.combined)
        RecoverySessionPolicy.advance(&state, to: relogin, mountedKeys: [mounted])
        #expect(state.sessionBoundary == relogin.combined)
    }

    @Test func baselineBackupRespectsPeerEjectWithoutInheritingCleanup() {
        let primary = UUID().uuidString.lowercased()
        let backup = UUID().uuidString.lowercased()
        let share = UUID().uuidString
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let hosts = [primary, backup].map { host in
            HostConfig(host: host, shares: [SMBShareConfig(name: share, smbURL: "smb://\(host)/\(share)", mountPoint: path)])
        }
        let configuration = AutomntConfig(hosts: hosts)
        let first = smbResourceIdentity(hosts[0].shares[0].smbURL)!
        let second = smbResourceIdentity(hosts[1].shares[0].smbURL)!
        let boundary = UUID().uuidString
        var state = MountRecoveryStateFile(sessionBoundary: boundary, volumes: [first:
            MountRecoveryVolumeRecord(volumeKey: first, state: .suppressed, suppressionBoundary: boundary,
                                      everHealthyMounted: true)])
        #expect(BaselineMountDecision.decide(identity: second, path: .absent, recovery: .loaded(state),
            configuration: configuration, mountPoint: path) == .suppressed)
        state.volumes[first]?.state = .pendingRecovery
        state.volumes[first]?.suppressionBoundary = nil
        state.cleanupLedger[first] = 1
        #expect(BaselineMountDecision.decide(identity: second, path: .absent, recovery: .loaded(state),
            configuration: configuration, mountPoint: path) == .mount)
        #expect(state.volumes[second] == nil)
        #expect(state.cleanupLedger[second] == nil)
    }

    @Test func unknownHealthNeverGrantsCleanupOrClaimsHealthy() {
        let key = UUID().uuidString
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let now = Date()
        #expect(RecoveryHealthPolicy.signal(base: .attachedHealthy, present: true, hostReachable: true,
            health: .unavailable) == .attachedHealthy)
        #expect(RecoveryHealthPolicy.signal(base: .attachedHealthy, present: true, hostReachable: true,
            health: .failed) == .deadButPresent)
        #expect(RecoveryHealthPolicy.signal(base: .unknownConservative, present: true, hostReachable: true,
            health: .failed) == .unknownConservative)
        #expect(RecoveryHealthPolicy.signal(base: .healthyEject, present: false, hostReachable: true,
            health: .failed) == .healthyEject)
        let unknown = RecoveryHealthPolicy.observation(identity: key, actualPath: path, hostReachable: true,
            health: .unavailable, observedAt: now)
        #expect(unknown.status == .evaluating)
        #expect(unknown.issue == .signalUnavailable)
        #expect(unknown.observedAt == now)
        #expect(unknown.actualPath == path)
        #expect(RecoveryHealthPolicy.observation(identity: key, actualPath: path, hostReachable: true,
            health: .healthy, observedAt: now).status == .healthy)
        #expect(RecoveryHealthPolicy.observation(identity: key, actualPath: path, hostReachable: false,
            health: .healthy, observedAt: now).status == .offline)
    }

    /// 首次建立会话边界（没有旧 boundary，例如升级后第一次运行）时，`.attached` 只表示
    /// 本项目曾挂载过该卷；挂载表里已不存在且没有弹出记录，说明它是上次会话遗留的陈旧
    /// 状态，必须恢复而非按“健康弹出”抑制。用户弹出记录仍保持抑制。
    @Test func firstBaselineRecoversStaleAttachedWithoutCancellingEject() {
        let stale = UUID().uuidString
        let ejected = UUID().uuidString
        let identity = RecoverySessionIdentity(network: "network", loginEpoch: "boot-1-console-unreadable",
            previous: nil)
        var state = MountRecoveryStateFile(volumes: [
            stale: MountRecoveryVolumeRecord(volumeKey: stale, state: .attached,
                everHealthyMounted: true, attemptCount: 2),
            ejected: MountRecoveryVolumeRecord(volumeKey: ejected, state: .suppressed,
                suppressionBoundary: "old|boot-0", everHealthyMounted: true, notificationCount: 1)
        ])
        RecoverySessionPolicy.advance(&state, to: identity, mountedKeys: [])
        #expect(state.sessionBoundary == identity.combined)
        #expect(state.volumes[stale]?.state == .pendingRecovery)
        #expect(state.volumes[stale]?.attemptCount == 0)
        #expect(state.volumes[stale]?.everHealthyMounted == true)
        #expect(state.volumes[ejected]?.state == .suppressed)
        #expect(state.volumes[ejected]?.suppressionBoundary == identity.combined)
        #expect(state.volumes[ejected]?.notificationCount == 1)
    }

    /// 首次建立边界时仍在挂载表中的卷不得被重置为待恢复。
    @Test func firstBaselineKeepsAttachedVolumeThatIsStillMounted() {
        let mounted = UUID().uuidString
        let identity = RecoverySessionIdentity(network: "network", loginEpoch: "boot-1", previous: nil)
        var state = MountRecoveryStateFile(volumes: [
            mounted: MountRecoveryVolumeRecord(volumeKey: mounted, state: .attached, everHealthyMounted: true)
        ])
        RecoverySessionPolicy.advance(&state, to: identity, mountedKeys: [mounted])
        #expect(state.volumes[mounted]?.state == .attached)
        #expect(state.sessionBoundary == identity.combined)
    }


    /// 同一次启动、同一网络下，只有「能否读取 console 记录」不同（沙盒读不到 utmpx，
    /// CLI 读得到）不构成新会话：不得改写边界，也不得清除本会话的弹出抑制。
    @Test func consoleReadabilityDifferenceWithinOneBootKeepsSessionSuppression() {
        let key = UUID().uuidString
        let boot = "1792778275"
        let previousBoundary = "network|\(boot)-console-unreadable"
        var state = MountRecoveryStateFile(sessionBoundary: previousBoundary, volumes: [key:
            MountRecoveryVolumeRecord(volumeKey: key, state: .suppressed,
                suppressionBoundary: previousBoundary, everHealthyMounted: true, notificationCount: 1)])
        let readable = RecoverySessionIdentity(network: "network", loginEpoch: "\(boot)-1792779000",
            previous: previousBoundary)
        RecoverySessionPolicy.advance(&state, to: readable, mountedKeys: [])
        #expect(state.sessionBoundary == previousBoundary)
        #expect(state.volumes[key]?.state == .suppressed)
        #expect(state.volumes[key]?.suppressionBoundary == previousBoundary)
        #expect(state.volumes[key]?.notificationCount == 1)
    }

    /// 同一网络下换了启动时刻仍是新会话（真实重启路径），陈旧 `.attached` 必须恢复。
    @Test func newBootOnSameNetworkResetsStaleAttachedState() {
        let key = UUID().uuidString
        let previousBoundary = "network|1792778275-console-unreadable"
        var state = MountRecoveryStateFile(sessionBoundary: previousBoundary, volumes: [key:
            MountRecoveryVolumeRecord(volumeKey: key, state: .attached, everHealthyMounted: true,
                attemptCount: 2)])
        let rebooted = RecoverySessionIdentity(network: "network", loginEpoch: "1792780000-console-unreadable",
            previous: previousBoundary)
        RecoverySessionPolicy.advance(&state, to: rebooted, mountedKeys: [])
        #expect(state.sessionBoundary == rebooted.combined)
        #expect(state.volumes[key]?.state == .pendingRecovery)
        #expect(state.volumes[key]?.attemptCount == 0)
    }

}
