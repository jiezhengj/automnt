import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

/// R5 / V8 缺陷 G2 的防回归：`sessionBoundary == nil` 时**不得**启用同路径对端抑制。
///
/// 三条路径（planner / `BaselineMountDecision` / helper 桥接）必须对 `nil` 与 `""`
/// 给出**一致**结论。改动前 helper 走 `BaselineMountDecision`（nil 时跳过对端检查），
/// 而 task-15 曾把 nil 传成 `""`，使 helper 与 worker 结论相反。
///
/// 业务配置一律经产品 API（`FileConfigRepository.create`）生成。
struct RecoveryBoundaryConsistencyTests {

    /// 双主机、**同一挂载点**的配置：身份 A 曾健康挂载（对端），判定身份 B。
    private struct Fixture {
        let directory: URL
        let configuration: AutomntConfig
        let first: RecoveryRoundConfiguredVolume
        let second: RecoveryRoundConfiguredVolume
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("automnt-bnd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = FileConfigRepository(authorizedDirectory: directory)
        _ = try repository.create(AutomntConfig(retryPolicy: RetryPolicy(maxAttempts: 2, intervalMs: 100,
                                                                        maxTotalWindowMs: 1000),
            hosts: [HostConfig(host: "first.bnd.example", shares: [SMBShareConfig(name: "Shared",
                smbURL: "smb://first.bnd.example/Shared", mountPoint: "/Volumes/Shared")]),
                    HostConfig(host: "second.bnd.example", shares: [SMBShareConfig(name: "Shared",
                smbURL: "smb://second.bnd.example/Shared", mountPoint: "/Volumes/Shared")])],
            autoMountRecovery: true, automationEnabled: true))
        let configuration = try repository.read().configuration
        let volumes = configuredRecoveryVolumes(from: configuration)
        return Fixture(directory: directory, configuration: configuration,
                       first: volumes[0], second: volumes[1])
    }

    /// 对端（A）曾健康挂载或处于抑制状态；边界按参数设置。
    private func peerFile(_ fixture: Fixture, boundary: String?,
                          peerState: MountRecoveryVolumeState = .attached) -> MountRecoveryStateFile {
        MountRecoveryStateFile(sessionBoundary: boundary, volumes: [fixture.first.identity:
            MountRecoveryVolumeRecord(volumeKey: fixture.first.identity, state: peerState,
                suppressionBoundary: peerState == .suppressed ? (boundary ?? "") : nil,
                everHealthyMounted: true)])
    }

    /// 路径 2：`BaselineMountDecision`（worker 子进程复核）。
    private func baseline(_ fixture: Fixture, boundary: String?,
                          peerState: MountRecoveryVolumeState = .attached) -> BaselineMountDecision {
        BaselineMountDecision.decide(identity: fixture.second.identity, path: .absent,
            recovery: .loaded(peerFile(fixture, boundary: boundary, peerState: peerState)),
            configuration: fixture.configuration, mountPoint: fixture.second.mountPoint,
            allowRecovery: true)
    }

    /// 路径 3：helper 桥接（内部入口，签名与生产一致）。
    private func helper(_ fixture: Fixture, boundary: String?,
                        peerState: MountRecoveryVolumeState = .attached) -> RecoveryVolumeJudgment {
        BackgroundEvaluator.judge(identity: fixture.second.identity,
            share: SMBShareConfig(name: "Shared", smbURL: fixture.second.url,
                                  mountPoint: fixture.second.mountPoint),
            configuration: fixture.configuration,
            recovery: .loaded(peerFile(fixture, boundary: boundary, peerState: peerState)),
            present: false, health: .unavailable)
    }

    /// 路径 1：planner。
    private func planner(_ fixture: Fixture, boundary: String?,
                         peerState: MountRecoveryVolumeState = .attached,
                         network: String = "bnd-net", login: String = "bnd-login") -> RecoveryVolumeAction {
        var mounts = 0
        let result = RecoveryRoundPlanner.run(
            request: RecoveryRoundRequest(configuration: fixture.configuration,
                load: .loaded(peerFile(fixture, boundary: boundary, peerState: peerState)),
                sessionNetwork: network, sessionLoginEpoch: login, mountedIdentities: [],
                manualRecovery: false, volumes: [fixture.second],
                now: { Date(timeIntervalSince1970: 1_700_000_000) }),
            observe: { RecoveryRoundVolumeSnapshot(identity: $0.identity, mountPoint: $0.mountPoint,
                host: $0.host, port: $0.port, presentInMountTable: false, observedPath: nil,
                hostReachable: true, health: .unavailable) },
            effects: RecoveryRoundEffects(cleanup: { _ in false },
                mount: { _ in mounts += 1; return RecoveryMountAttempt(succeeded: true, failure: .mounted) },
                budgetRemaining: { 30 }))
        return result.plan.first?.action ?? .deferred
    }

    /// 共享判定层：nil 与 "" 必须给出同一结论（nil/空串都表示「尚未建立边界」）。
    ///
    /// 这是 G2 的根因所在——旧实现只用 `let boundary`，空串会误通过 `let`。
    @Test func sharedGateTreatsNilAndEmptyBoundaryIdentically() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        for peerState in [MountRecoveryVolumeState.attached, .suppressed] {
            for boundary in [nil, ""] as [String?] {
                let judgment = RecoveryVolumeDecisionPolicy.judge(
                    RecoveryVolumeFacts(identity: fixture.second.identity,
                        mountPoint: fixture.second.mountPoint, presentInMountTable: false,
                        hostReachable: true, health: .unavailable),
                    context: RecoveryVolumeContext(configuration: fixture.configuration,
                        state: peerFile(fixture, boundary: boundary, peerState: peerState),
                        stateReadable: true, boundary: boundary,
                        peers: RecoveryVolumeDecisionPolicy.peers(configuration: fixture.configuration),
                        manualRecovery: false, permitsMount: true))
                // nil 与 "" 都不得启用对端抑制 ⇒ 可恢复。
                #expect(judgment.decision == .recover,
                        "peerState=\(peerState) boundary=\(String(describing: boundary)) → \(judgment.decision)")
            }
            // 反证非真空：真实边界必须能触发抑制。
            let live = RecoverySessionIdentity(network: "live", loginEpoch: "epoch", previous: nil).combined
            let suppressed = RecoveryVolumeDecisionPolicy.judge(
                RecoveryVolumeFacts(identity: fixture.second.identity,
                    mountPoint: fixture.second.mountPoint, presentInMountTable: false,
                    hostReachable: true, health: .unavailable),
                context: RecoveryVolumeContext(configuration: fixture.configuration,
                    state: peerFile(fixture, boundary: live, peerState: peerState),
                    stateReadable: true, boundary: live,
                    peers: RecoveryVolumeDecisionPolicy.peers(configuration: fixture.configuration),
                    manualRecovery: false, permitsMount: true))
            #expect(suppressed.decision == .sessionSuppressed,
                    "peerState=\(peerState): 真实边界必须触发对端抑制")
        }
    }

    /// 路径 A（worker）：`BaselineMountDecision` 对 nil 与 "" 结论一致。
    @Test func baselinePathAgreesOnNilAndEmptyBoundary() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        for peerState in [MountRecoveryVolumeState.attached, .suppressed] {
            #expect(baseline(fixture, boundary: nil, peerState: peerState)
                    == baseline(fixture, boundary: "", peerState: peerState))
            #expect(baseline(fixture, boundary: nil, peerState: peerState) == .mount)
            // 真实边界仍抑制（非真空）。
            let live = RecoverySessionIdentity(network: "live", loginEpoch: "epoch", previous: nil).combined
            #expect(baseline(fixture, boundary: live, peerState: peerState) == .suppressed)
        }
    }

    /// 路径 B（helper 桥接）：对 nil 与 "" 结论一致，且真实边界仍抑制。
    @Test func helperBridgeAgreesOnNilAndEmptyBoundary() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        for peerState in [MountRecoveryVolumeState.attached, .suppressed] {
            #expect(helper(fixture, boundary: nil, peerState: peerState).decision
                    == helper(fixture, boundary: "", peerState: peerState).decision)
            #expect(helper(fixture, boundary: nil, peerState: peerState).decision == .recover)
            let live = RecoverySessionIdentity(network: "live", loginEpoch: "epoch", previous: nil).combined
            #expect(helper(fixture, boundary: live, peerState: peerState).decision == .sessionSuppressed)
        }
    }

    /// helper 桥接必须原样传递 nil（不得 `?? ""`）——state 无 sessionBoundary 时可恢复。
    @Test func helperBridgePreservesNilBoundaryFromState() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let noBoundary = MountRecoveryStateFile(volumes: [fixture.first.identity:
            MountRecoveryVolumeRecord(volumeKey: fixture.first.identity, everHealthyMounted: true)])
        #expect(noBoundary.sessionBoundary == nil)
        let judgment = BackgroundEvaluator.judge(identity: fixture.second.identity,
            share: SMBShareConfig(name: "Shared", smbURL: fixture.second.url,
                                  mountPoint: fixture.second.mountPoint),
            configuration: fixture.configuration, recovery: .loaded(noBoundary),
            present: false, health: .unavailable)
        #expect(judgment.decision == .recover)
    }

    /// 路径 C（planner）：结构上先经 `RecoverySessionPolicy.advance`，
    /// 其**判定所用边界恒为 advance 后的具体标识**（永不为 nil/空串）。
    ///
    /// 因此对 planner 的正确断言不是「nil 输入」，而是：传入 nil/""/有边界三种初值时，
    /// 若 advance 后落到同一会话，则逐卷决策与用同一具体边界直接调共享判定一致。
    @Test func plannerUsesPostAdvanceConcreteBoundary() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let network = "bnd-net"
        let login = "bnd-login"
        let expectedBoundary = RecoverySessionIdentity(network: network, loginEpoch: login,
                                                      previous: nil).combined
        #expect(!expectedBoundary.isEmpty)

        // planner 在 nil 初值下（establishing 分支）仍以具体边界评估；establishing 还会
        // 把「`.attached` 但不在挂载表中」的陈旧记录改成 `.pendingRecovery`，因此共享判定
        // 必须在同一份推进后的记录上比较。用户弹出记录（`.suppressed`）保持抑制。
        for (initial, advanced) in [(MountRecoveryVolumeState.attached, MountRecoveryVolumeState.pendingRecovery),
                                    (MountRecoveryVolumeState.suppressed, MountRecoveryVolumeState.suppressed)] {
            let action = planner(fixture, boundary: nil, peerState: initial)
            let shared = RecoveryVolumeDecisionPolicy.judge(
                RecoveryVolumeFacts(identity: fixture.second.identity,
                    mountPoint: fixture.second.mountPoint, presentInMountTable: false,
                    hostReachable: true, health: .unavailable),
                context: RecoveryVolumeContext(configuration: fixture.configuration,
                    state: peerFile(fixture, boundary: expectedBoundary, peerState: advanced),
                    stateReadable: true, boundary: expectedBoundary,
                    peers: RecoveryVolumeDecisionPolicy.peers(configuration: fixture.configuration),
                    manualRecovery: false, permitsMount: true))
            #expect(action == RecoveryVolumeAction.planned(for: shared.decision),
                    "peer=\(initial) planner action=\(action) shared(concrete)=\(shared.decision)")
        }
    }
}
