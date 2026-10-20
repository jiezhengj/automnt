import Foundation
import Testing
@testable import AutomntCore

/// T009-c2 委托等价性：`BaselineMountDecision.decide` 现在委托共享
/// `RecoveryVolumeDecisionPolicy`。本文件保存**改动前的实现作为特征化预言机**
/// （characterization oracle，仅测试用，不是第二套产品逻辑），在穷举输入矩阵上
/// 逐项比对，证明委托化未改变任何对外可观察结果。
///
/// 注意：预言机只描述历史行为；产品规则的真实定义只有 `RecoveryVolumeDecisionPolicy`。
/// 若将来有意变更规则，应同步更新本预言机并在此说明理由。
///
/// R5 订正（V8 提示级）：矩阵新增 `peerKind` 维度，配置中加入**第二个主机/共享**，
/// 使 `RecoverySuppressionPolicy.protectedByPeer` 的同路径对端抑制分支真正被触发
/// （旧矩阵只有单一身份，`peer.identity != identity` 守卫使其恒为死代码）。
private enum LegacyBaselineDecide {
    static func decide(identity: String, path: MountPathState,
                       recovery: MountRecoveryStoreLoad,
                       configuration: AutomntConfig? = nil, mountPoint: String? = nil,
                       allowRecovery: Bool = false, now: Date = Date()) -> BaselineMountDecision {
        switch path {
        case .unavailable: return .blocked(.signalUnavailable)
        case .occupied: return .blocked(.pathConflict)
        case .smb(let actual): return actual == identity ? .inspectExisting : .blocked(.pathConflict)
        case .absent: break
        }
        guard recovery.isReadable else { return .suppressed }
        let file = recovery.file
        if let configuration, let mountPoint, let boundary = file.sessionBoundary {
            let peers = configuration.hosts.filter(\.enabled).flatMap { host in
                host.shares.filter(\.enabled).compactMap { share -> RecoveryPeer? in
                    guard let key = smbResourceIdentity(share.smbURL) else { return nil }
                    return RecoveryPeer(identity: key, mountPoint: share.mountPoint, present: false, hostReachable: false)
                }
            }
            if RecoverySuppressionPolicy.protectedByPeer(identity: identity, mountPoint: mountPoint,
                boundary: boundary, peers: peers, state: recovery) { return .suppressed }
        }
        let record = file.volumes[identity]
        guard record?.state != .suppressed else { return .suppressed }
        let signal = judgeRecoverySignal(volumeKey: identity, presentInMountTable: false,
            hostReachable: true, record: record, cleanupLedger: file.cleanupLedger, stateReadable: true)
        if signal != .neverMounted, let configuration,
           (record?.attemptCount ?? 0) >= min(max(configuration.retryPolicy?.maxAttempts ?? 3, 1), 10) {
            return .suppressed
        }
        if signal != .neverMounted, allowRecovery,
           !RecoveryRetryInterval.permits(record: record, policy: configuration?.retryPolicy, now: now) {
            return .deferred
        }
        return MissingVolumeRecoveryPolicy.mayMount(signal: signal,
            enabled: allowRecovery && (configuration?.isAutoMountRecoveryEnabled ?? false)) ? .mount : .suppressed
    }
}

struct BaselineDelegationEquivalenceTests {
    private struct Case {
        var path: MountPathState = .absent
        var allowRecovery = false
        var autoRecovery = false
        var state: MountRecoveryVolumeState = .attached
        var everHealthy = false
        var repair = false
        var ledger = false
        var attempts = 0
        var updatedAt = 0.0
        var boundary: String? = nil
        var corrupt = false
        var maxAttempts = 3
        var configurationGiven = true
        /// 对端（第二身份、**同一挂载点**）的记录形态：驱动 `protectedByPeer` 的两条判据。
        var peerKind = 0   // 0=同边界 suppressed, 1=everHealthyMounted(healthyEject), 2=无记录, 3=不同挂载点
    }

    @Test func delegatedDecideMatchesPreRefactorBehaviorAcrossFullMatrix() {
        let now = Date(timeIntervalSince1970: 10_000)
        var cases: [Case] = []
        for path in [MountPathState.absent, .occupied, .unavailable,
                     .smb(identity: "//a.example/s"), .smb(identity: "//zzz.example/x")] {
            for allow in [false, true] {
                for auto in [false, true] {
                    for state in [MountRecoveryVolumeState.attached, .pendingRecovery, .suppressed,
                                  .lost, .recovering] {
                        for everHealthy in [false, true] {
                            for repair in [false, true] {
                                for ledger in [false, true] {
                                    for attempts in [0, 1, 3, 10] {
                                        for updated in [now.timeIntervalSince1970 - 100,
                                                        now.timeIntervalSince1970 - 0.2, 0.0] {
                                            for boundary in [nil, "n|l", "other|bound"] as [String?] {
                                                for corrupt in [false, true] {
                                                    for maxAttempts in [1, 3, 10] {
                                                        for given in [false, true] {
                                                            for peerKind in 0...3 {
                                                                var item = Case()
                                                                item.path = path; item.allowRecovery = allow
                                                                item.autoRecovery = auto; item.state = state
                                                                item.everHealthy = everHealthy; item.repair = repair
                                                                item.ledger = ledger; item.attempts = attempts
                                                                item.updatedAt = updated; item.boundary = boundary
                                                                item.corrupt = corrupt; item.maxAttempts = maxAttempts
                                                                item.configurationGiven = given
                                                                item.peerKind = peerKind
                                                                cases.append(item)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        let identity = "//a.example/s"
        let peer = "//b.example/t"
        var mismatches: [String] = []
        for item in cases {
            let record = MountRecoveryVolumeRecord(volumeKey: identity, state: item.state,
                suppressionBoundary: item.state == .suppressed ? (item.boundary ?? "") : nil,
                repairEjectEvidence: item.repair, everHealthyMounted: item.everHealthy,
                attemptCount: item.attempts, updatedAt: item.updatedAt)
            // 对端身份与配置：peerKind 决定记录形态与挂载点，
            // 使 `protectedByPeer`（含 `peer.identity != identity` 守卫）真正被触发。
            let peerMountPoint = item.peerKind == 3 ? "/Volumes/Other" : "/Volumes/S"
            var volumes = [identity: record]
            if item.peerKind != 2 {
                let peerRecord = MountRecoveryVolumeRecord(volumeKey: peer,
                    state: item.peerKind == 0 ? .suppressed : .attached,
                    suppressionBoundary: item.peerKind == 0 ? (item.boundary ?? "") : nil,
                    everHealthyMounted: true)
                volumes[peer] = peerRecord
            }
            var file = MountRecoveryStateFile(sessionBoundary: item.boundary, volumes: volumes)
            if item.ledger { file.cleanupLedger[identity] = 1 }
            let load: MountRecoveryStoreLoad = item.corrupt ? .corrupt(reason: "x") : .loaded(file)
            var config = AutomntConfig(retryPolicy: RetryPolicy(maxAttempts: item.maxAttempts,
                intervalMs: 1000, maxTotalWindowMs: 10000))
            config.autoMountRecovery = item.autoRecovery
            config.hosts = [HostConfig(host: "a.example", shares: [SMBShareConfig(name: "s",
                smbURL: "smb://a.example/s", mountPoint: "/Volumes/S")]),
                HostConfig(host: "b.example", shares: [SMBShareConfig(name: "t",
                    smbURL: "smb://b.example/t", mountPoint: peerMountPoint)])]
            let passedConfiguration: AutomntConfig? = item.configurationGiven ? config : nil

            let legacy = LegacyBaselineDecide.decide(identity: identity, path: item.path,
                recovery: load, configuration: passedConfiguration, mountPoint: "/Volumes/S",
                allowRecovery: item.allowRecovery, now: now)
            let delegated = BaselineMountDecision.decide(identity: identity, path: item.path,
                recovery: load, configuration: passedConfiguration, mountPoint: "/Volumes/S",
                allowRecovery: item.allowRecovery, now: now)
            if legacy != delegated {
                mismatches.append("path=\(item.path) allow=\(item.allowRecovery) auto=\(item.autoRecovery) "
                    + "state=\(item.state) everHealthy=\(item.everHealthy) repair=\(item.repair) "
                    + "ledger=\(item.ledger) attempts=\(item.attempts) updated=\(item.updatedAt) "
                    + "boundary=\(String(describing: item.boundary)) corrupt=\(item.corrupt) "
                    + "max=\(item.maxAttempts) given=\(item.configurationGiven) peerKind=\(item.peerKind) "
                    + "legacy=\(legacy) delegated=\(delegated)")
            }
        }
        // 矩阵规模与零不一致都是断言的一部分：防止将来把循环改小后「静默通过」。
        #expect(cases.count == 1_382_400)
        #expect(mismatches.isEmpty, "\(mismatches.prefix(5).joined(separator: " | "))")
    }

    /// 委托后仍必须保留的两个入口级事实（与 worker 子进程复核相关）。
    @Test func delegatedDecideKeepsPathGateAndConservativeStateHandling() {
        let identity = UUID().uuidString
        #expect(BaselineMountDecision.decide(identity: identity, path: .occupied, recovery: .absent)
                == .blocked(.pathConflict))
        #expect(BaselineMountDecision.decide(identity: identity, path: .unavailable, recovery: .absent)
                == .blocked(.signalUnavailable))
        #expect(BaselineMountDecision.decide(identity: identity, path: .smb(identity: identity),
                                             recovery: .corrupt(reason: "x")) == .inspectExisting)
        #expect(BaselineMountDecision.decide(identity: identity, path: .absent,
                                             recovery: .corrupt(reason: "x")) == .suppressed)
    }
}
