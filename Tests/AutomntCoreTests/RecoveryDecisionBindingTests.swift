import Foundation
import Testing
@testable import AutomntCore

/// R5 / V8 缺陷 G1 的防回归：**planner 的动作唯一来源是 `judgment.decision`**。
///
/// 本文件不读 `signal` 推演动作，而是直接构造六种 `RecoveryVolumeDecision` 对应的
/// 输入，断言 (1) 共享判定给出的 decision，(2) planner 计划动作 = `.planned(for: decision)`，
/// (3) 实际副作用（挂载/清理次数）与 decision 一致。
/// 因此「`decide()` 的 action 映射退化」或「planner 绕开 decision 自行推导」都会变红。
struct RecoveryDecisionBindingTests {

    private func makeConfiguration(_ host: String = "bind.example",
                                    share: String = "Shared") throws -> (AutomntConfig, RecoveryRoundConfiguredVolume, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("automnt-bind-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = FileConfigRepository(authorizedDirectory: directory)
        _ = try repository.create(AutomntConfig(retryPolicy: RetryPolicy(maxAttempts: 2, intervalMs: 100,
                                                                        maxTotalWindowMs: 1000),
            hosts: [HostConfig(host: host, shares: [SMBShareConfig(name: share,
                smbURL: "smb://\(host)/\(share)", mountPoint: "/Volumes/\(share)")])],
            autoMountRecovery: true, automationEnabled: true))
        let configuration = try repository.read().configuration
        return (configuration, configuredRecoveryVolumes(from: configuration)[0], directory)
    }

    private struct SideEffects {
        var mounts = 0
        var cleanups = 0
    }

    /// 跑一轮 planner，返回判定、计划动作与实际副作用。
    private func run(_ configuration: AutomntConfig, _ volume: RecoveryRoundConfiguredVolume,
                     load: MountRecoveryStoreLoad, present: Bool, reachable: Bool,
                     health: VolumeHealthEvidence, manual: Bool = false,
                     budget: TimeInterval = 30, now: Date = Date(timeIntervalSince1970: 1_700_000_000),
                     network: String = "bind-net", login: String = "bind-login",
                     mounts: Bool = true, cleanupResult: Bool = true) -> (judgment: RecoveryVolumeJudgment,
                                                                          action: RecoveryVolumeAction,
                                                                          effects: SideEffects,
                                                                          result: RecoveryRoundResult) {
        var side = SideEffects()
        let boundary = RecoverySessionIdentity(network: network, loginEpoch: login, previous: nil).combined
        let judgment = RecoveryVolumeDecisionPolicy.judge(
            RecoveryVolumeFacts(identity: volume.identity, mountPoint: volume.mountPoint,
                presentInMountTable: present, hostReachable: reachable, health: health),
            context: RecoveryVolumeContext(configuration: configuration, state: load.file,
                stateReadable: load.isReadable, boundary: load.file.sessionBoundary ?? boundary,
                peers: RecoveryVolumeDecisionPolicy.peers(configuration: configuration),
                manualRecovery: manual,
                permitsMount: RecoveryRoundPlanner.isPermitted(configuration: configuration), now: now))
        let result = RecoveryRoundPlanner.run(
            request: RecoveryRoundRequest(configuration: configuration, load: load,
                sessionNetwork: network, sessionLoginEpoch: login, mountedIdentities: [],
                manualRecovery: manual, volumes: [volume], now: { now }),
            observe: { RecoveryRoundVolumeSnapshot(identity: $0.identity, mountPoint: $0.mountPoint,
                host: $0.host, port: $0.port, presentInMountTable: present,
                observedPath: present ? $0.mountPoint : nil, hostReachable: reachable, health: health) },
            effects: RecoveryRoundEffects(
                cleanup: { _ in side.cleanups += 1; return cleanupResult },
                mount: { _ in
                    side.mounts += 1
                    return RecoveryMountAttempt(succeeded: mounts, failure: .shareRejected)
                },
                budgetRemaining: { budget }))
        return (judgment, result.plan.first?.action ?? .deferred, side, result)
    }

    /// 六种 decision ↔ 计划动作的唯一映射（`.planned(for:)`）逐项绑定。
    /// 该映射是 planner 动作的唯一来源；任一项改动都会使本断言变红。
    @Test func planningMapBindsEveryDecisionToOneAction() {
        #expect(RecoveryVolumeAction.planned(for: .attachHealthy) == .attachHealthy)
        #expect(RecoveryVolumeAction.planned(for: .cleanupThenRecover) == .cleanupThenRecover)
        #expect(RecoveryVolumeAction.planned(for: .recover) == .recover)
        #expect(RecoveryVolumeAction.planned(for: .sessionSuppressed) == .suppress)
        #expect(RecoveryVolumeAction.planned(for: .pendingUnreachable) == .pendingUnreachable)
        #expect(RecoveryVolumeAction.planned(for: .deferred) == .deferred)
        // 映射必须是单射：六种 decision 不得塌缩到同一动作。
        let all = [RecoveryVolumeDecision.attachHealthy, .cleanupThenRecover, .recover,
                   .sessionSuppressed, .pendingUnreachable, .deferred]
        let descriptions = all.map { String(describing: RecoveryVolumeAction.planned(for: $0)) }
        #expect(Set(descriptions).count == 6)
    }

    /// planner 可达的五种 decision：计划动作 == `planned(for: decision)`，且副作用与之一致。
    ///
    /// 说明：`deferred` 在 planner 侧**不可达**（planner 不启用逐卷重试间隔门；
    /// 该门只在 helper 桥接与 `BaselineMountDecision` 启用）。这与 R5 之前一致——
    /// 整轮顺延由 `RecoveryRoundPlanner.deferRound` 表达。故此处覆盖五种，
    /// `deferred` 由 `planningMapBindsEveryDecisionToOneAction` 与
    /// `deferredDecisionConsumesNoBudgetOrSideEffects`（helper 桥接路径）覆盖。
    @Test func plannerActionIsBoundToSharedDecisionForAllReachableCases() throws {
        let (configuration, volume, directory) = try makeConfiguration()
        defer { try? FileManager.default.removeItem(at: directory) }
        let boundary = RecoverySessionIdentity(network: "bind-net", loginEpoch: "bind-login",
                                               previous: nil).combined
        func state(_ record: MountRecoveryVolumeRecord?) -> MountRecoveryStoreLoad {
            .loaded(MountRecoveryStateFile(sessionBoundary: boundary,
                volumes: record.map { [volume.identity: $0] } ?? [:]))
        }
        let suppressedRecord = MountRecoveryVolumeRecord(volumeKey: volume.identity, state: .suppressed,
            suppressionBoundary: boundary, everHealthyMounted: false)

        let scenarios: [(name: String, load: MountRecoveryStoreLoad, present: Bool, reachable: Bool,
                         health: VolumeHealthEvidence, expected: RecoveryVolumeDecision)] = [
            ("recover", .absent, false, true, .unavailable, .recover),
            ("cleanupThenRecover", .absent, true, true, .failed, .cleanupThenRecover),
            ("attachHealthy", .absent, true, true, .healthy, .attachHealthy),
            ("sessionSuppressed", state(suppressedRecord), false, true, .unavailable, .sessionSuppressed),
            ("pendingUnreachable", .absent, true, false, .unavailable, .pendingUnreachable),
        ]
        var seen = Set<RecoveryVolumeDecision>()
        for scenario in scenarios {
            let outcome = run(configuration, volume, load: scenario.load, present: scenario.present,
                reachable: scenario.reachable, health: scenario.health)
            #expect(outcome.judgment.decision == scenario.expected,
                    "\(scenario.name): \(outcome.judgment)")
            #expect(outcome.action == RecoveryVolumeAction.planned(for: outcome.judgment.decision),
                    "\(scenario.name): action=\(outcome.action) decision=\(outcome.judgment.decision)")
            // 副作用必须与 decision 一致：只有 recover/cleanupThenRecover 挂载，
            // 只有 cleanupThenRecover 清理，其余一律零副作用。
            let shouldMount = scenario.expected == .recover || scenario.expected == .cleanupThenRecover
            let shouldClean = scenario.expected == .cleanupThenRecover
            #expect(outcome.effects.mounts == (shouldMount ? 1 : 0),
                    "\(scenario.name): mounts=\(outcome.effects.mounts)")
            #expect(outcome.effects.cleanups == (shouldClean ? 1 : 0),
                    "\(scenario.name): cleanups=\(outcome.effects.cleanups)")
            seen.insert(outcome.judgment.decision)
        }
        #expect(seen.count == 5, "五种 planner 可达 decision 必须全部覆盖，实际 \(seen.count)")
    }

    /// `deferred` 不得消耗预算、不得挂载、不得改动账本/通知额度。
    ///
    /// 逐卷 `deferred` 只在启用重试间隔门的路径可达，故此处直接以
    /// `RecoveryVolumeContext(appliesRetryInterval: true)` 复现 helper 桥接的判定，
    /// 再用 `deferRound` 覆盖整轮顺延的零副作用。
    @Test func deferredDecisionConsumesNoBudgetOrSideEffects() throws {
        let (configuration, volume, directory) = try makeConfiguration()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let boundary = RecoverySessionIdentity(network: "bind-net", loginEpoch: "bind-login",
                                               previous: nil).combined
        // attemptCount 必须低于 maxAttempts(2)，否则先被尝试上限门判为 sessionSuppressed。
        let record = MountRecoveryVolumeRecord(volumeKey: volume.identity, state: .pendingRecovery,
            everHealthyMounted: true, attemptCount: 1, updatedAt: now.timeIntervalSince1970,
            notificationCount: 1)
        let load = MountRecoveryStoreLoad.loaded(MountRecoveryStateFile(sessionBoundary: boundary,
                                                                       volumes: [volume.identity: record]))
        let facts = RecoveryVolumeFacts(identity: volume.identity, mountPoint: volume.mountPoint,
            presentInMountTable: false, hostReachable: true, health: .unavailable)
        let deferred = RecoveryVolumeDecisionPolicy.judge(facts,
            context: RecoveryVolumeContext(configuration: configuration, state: load.file,
                stateReadable: true, boundary: load.file.sessionBoundary,
                peers: RecoveryVolumeDecisionPolicy.peers(configuration: configuration),
                manualRecovery: false, permitsMount: true,
                appliesAttemptLimit: true, appliesRetryInterval: true, now: now))
        #expect(deferred.decision == RecoveryVolumeDecision.deferred)
        #expect(RecoveryVolumeAction.planned(for: deferred.decision) == RecoveryVolumeAction.deferred)

        // 整轮顺延（deferRound）：零挂载、零预算、零账本改动。
        let round = RecoveryRoundPlanner.deferRound(configuration: configuration)
        #expect(round.deferredIdentities == [volume.identity])
        #expect(round.plan.first?.action == RecoveryVolumeAction.deferred)
        #expect(round.attempted == 0)
        #expect(round.state == MountRecoveryStateFile())
        #expect(round.failed.isEmpty && round.recovered.isEmpty && round.suppressed.isEmpty)
        #expect(round.notificationIdentities.isEmpty)
    }

    /// `cleanupThenRecover` 的清理失败必须退回 `.pendingUnreachable`，且零挂载。
    @Test func cleanupFailureFallsBackToPendingWithoutMounting() throws {
        let (configuration, volume, directory) = try makeConfiguration()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outcome = run(configuration, volume, load: .absent, present: true, reachable: true,
                          health: .failed, cleanupResult: false)
        #expect(outcome.judgment.decision == .cleanupThenRecover)
        #expect(outcome.action == .pendingUnreachable)
        #expect(outcome.effects.cleanups == 1)
        #expect(outcome.effects.mounts == 0)
        #expect(outcome.result.failed == [volume.identity])
        #expect(outcome.result.state.cleanupLedger[volume.identity] == nil)
    }
}
