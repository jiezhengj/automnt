import Foundation
import Testing
@testable import AutomntCore

/// 挂载范围策略（T117 / FR-027）的核心契约。
///
/// 覆盖：默认策略保持升级前行为、`all_reachable` 按保存顺序处理所有可达主机、
/// 任一主机不可达不阻止其余主机、以及恢复轮次的卷枚举与策略一致。
struct MountPolicyTests {
    private struct Probe: ReachabilityProbe {
        let reachable: Set<String>
        func isReachable(host: String, port: Int, timeoutMilliseconds: Int) async throws -> Bool {
            reachable.contains(host)
        }
    }

    private func configuration(hosts: [(String, String)]) -> AutomntConfig {
        var configuration = AutomntConfig()
        configuration.hosts = hosts.map { host, share in
            HostConfig(host: host,
                shares: [SMBShareConfig(name: share, smbURL: "smb://\(host)/\(share)",
                    mountPoint: "/Volumes/\(share)")])
        }
        return configuration
    }

    @Test func defaultPolicyKeepsFirstReachableBehaviour() {
        let config = configuration(hosts: [("a.example", "A"), ("b.example", "B")])
        #expect(config.effectiveMountPolicy == .firstReachable)
        #expect(!config.isMountAllEnabled)
        #expect(config.mountPolicy == nil)
    }

    @Test func allReachableWalksEveryReachableHostInSavedOrder() async throws {
        let config = configuration(hosts: [("a.example", "A"), ("b.example", "B"), ("c.example", "C")])
        let probe = Probe(reachable: ["a.example", "c.example"])
        let reached = try await HostPriorityEvaluator.reachableHosts(in: config,
            deadline: ContinuousClock.now.advanced(by: .seconds(5)), probe: probe, stopAfterFirst: false)
        #expect(reached.map(\.host) == ["a.example", "c.example"])
        // 单个不可达主机不阻止后续主机。
        #expect(!reached.contains { $0.host == "b.example" })
        let firstOnly = try await HostPriorityEvaluator.reachableHosts(in: config,
            deadline: ContinuousClock.now.advanced(by: .seconds(5)), probe: probe, stopAfterFirst: true)
        #expect(firstOnly.map(\.host) == ["a.example"])
    }

    @Test func allReachableIncludesLaterServersWhenTheFirstIsOffline() async throws {
        let config = configuration(hosts: [("a.example", "A"), ("b.example", "B")])
        let probe = Probe(reachable: ["b.example"])
        let reached = try await HostPriorityEvaluator.reachableHosts(in: config,
            deadline: ContinuousClock.now.advanced(by: .seconds(5)), probe: probe, stopAfterFirst: false)
        #expect(reached.map(\.host) == ["b.example"])
        let firstOnly = try await HostPriorityEvaluator.reachableHosts(in: config,
            deadline: ContinuousClock.now.advanced(by: .seconds(5)), probe: probe, stopAfterFirst: true)
        #expect(firstOnly.map(\.host) == ["b.example"])
    }

    @Test func recoveryRoundEnumeratesAllVolumesUnderAllReachable() {
        let hosts = [("a.example", "A"), ("b.example", "B")]
        var config = configuration(hosts: hosts)
        config.mountPolicy = .allReachable
        let volumes = RecoveryRoundPlanner.relevantVolumes(configuration: config,
            mountedIdentities: [], probe: { host, _ in host == "a.example" })
        #expect(volumes.map(\.host) == ["a.example", "b.example"])
        // 不可达主机的卷仍在列表里：逐卷判定会把它落为「等待恢复」，不静默丢失。
        #expect(volumes.count == 2)

        config.mountPolicy = .firstReachable
        let firstOnly = RecoveryRoundPlanner.relevantVolumes(configuration: config,
            mountedIdentities: [], probe: { _, _ in true })
        #expect(firstOnly.map(\.host) == ["a.example"])
    }

    @Test func disabledServersAreNeverMountedUnderAnyPolicy() async throws {
        var config = configuration(hosts: [("a.example", "A"), ("b.example", "B")])
        config.mountPolicy = .allReachable
        config.hosts[1].enabled = false
        let probe = Probe(reachable: ["a.example", "b.example"])
        let reached = try await HostPriorityEvaluator.reachableHosts(in: config,
            deadline: ContinuousClock.now.advanced(by: .seconds(5)), probe: probe, stopAfterFirst: false)
        #expect(reached.map(\.host) == ["a.example"])
        let volumes = RecoveryRoundPlanner.relevantVolumes(configuration: config,
            mountedIdentities: [], probe: { _, _ in true })
        #expect(volumes.map(\.host) == ["a.example"])
    }
}
