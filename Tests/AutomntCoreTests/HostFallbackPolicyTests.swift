import Foundation
import Testing
@testable import AutomntCore

/// 同轮回退规则的唯一实现（`HostFallbackPolicy`）的行为契约。
///
/// 覆盖：只有连接类失败才回退、候选必须同名同挂载点、按保存顺序、排除失败主机自身、
/// 每个候选主机只带能配对的共享，以及「同一共享已由另一身份挂载」的识别。
/// 业务配置全部经产品 API（`FileConfigRepository`）生成，不手写 plist。
struct HostFallbackPolicyTests {

    private func makeConfiguration(_ hosts: [(String, [(String, String)])],
                                   at directory: URL) throws -> AutomntConfig {
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let configuration = AutomntConfig(hosts: hosts.map { host, shares in
            HostConfig(host: host, shares: shares.map { share, mount in
                SMBShareConfig(name: share, smbURL: "smb://\(host)/\(share)", mountPoint: mount)
            })
        })
        _ = try repository.create(configuration)
        return try repository.read().configuration
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("automnt-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - 失败分类

    @Test func onlyConnectionIssuesTriggerFallback() {
        #expect(HostFallbackPolicy.isConnectionFailure(.offline))
        #expect(HostFallbackPolicy.isConnectionFailure(.timeout))
        // 换一条主机解决不了的结论：不得回退。
        for issue: AutomntIssue in [.shareRejected, .credentialFailure, .pathConflict,
                                    .volumeBusy, .authorizationRequired, .signalUnavailable,
                                    .invalidConfiguration, .configurationConflict] {
            #expect(!HostFallbackPolicy.isConnectionFailure(issue))
        }
        #expect(HostFallbackPolicy.isConnectionFailure(RecoveryAttemptOutcome.hostUnreachable))
        #expect(!HostFallbackPolicy.isConnectionFailure(RecoveryAttemptOutcome.shareRejected))
        #expect(!HostFallbackPolicy.isConnectionFailure(RecoveryAttemptOutcome.credentialFailure))
    }

    /// NetFS 用等价正值状态码表达失败：只有连接类码才值得换主机。
    @Test func netFSStatusCodesClassifyConnectionFailures() {
        // ENETDOWN / ENETUNREACH / ETIMEDOUT / ECONNREFUSED / EHOSTDOWN / EHOSTUNREACH
        for status: Int32 in [50, 51, 60, 61, 64, 65] {
            #expect(HostFallbackPolicy.isConnectionFailure(netFSStatus: status))
        }
        // ENOENT（共享不存在）/ EACCES / EAUTH / 未知码都不是连接类失败。
        for status: Int32 in [2, 13, 80, 0, -5999, -5045, -5046] {
            #expect(!HostFallbackPolicy.isConnectionFailure(netFSStatus: status))
        }
    }

    // MARK: - 候选选择

    @Test func candidatesRequireSameShareAndSameMountPoint() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = try makeConfiguration([
            ("lan.example", [("Shared", "/Volumes/Shared")]),
            ("tail.example", [("Shared", "/Volumes/Shared")])
        ], at: directory)
        let targets = HostFallbackPolicy.targets(for: configuration.hosts[0].shares[0],
            mountPoint: "/Volumes/Shared", from: configuration.hosts[0], in: configuration)
        #expect(targets.map(\.host.host) == ["tail.example"])

        // 共享名不同 → 不是同一份数据，不得回退。
        var renamed = configuration
        renamed.hosts[1].shares[0] = SMBShareConfig(name: "Other",
            smbURL: "smb://tail.example/Other", mountPoint: "/Volumes/Shared")
        #expect(HostFallbackPolicy.targets(for: configuration.hosts[0].shares[0],
            mountPoint: "/Volumes/Shared", from: configuration.hosts[0], in: renamed).isEmpty)

        // 挂载点不同 → 会造成同一共享两份挂载，不得回退。
        var remounted = configuration
        remounted.hosts[1].shares[0] = SMBShareConfig(name: "Shared",
            smbURL: "smb://tail.example/Shared", mountPoint: "/Volumes/Shared-Tail")
        #expect(HostFallbackPolicy.targets(for: configuration.hosts[0].shares[0],
            mountPoint: "/Volumes/Shared", from: configuration.hosts[0], in: remounted).isEmpty)
    }

    @Test func savedOrderIsRespectedAndFailedHostExcluded() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = try makeConfiguration([
            ("lan.example", [("Shared", "/Volumes/Shared")]),
            ("relay.example", [("Shared", "/Volumes/Shared")]),
            ("backup.example", [("Shared", "/Volumes/Shared")])
        ], at: directory)
        let targets = HostFallbackPolicy.targets(for: configuration.hosts[0].shares[0],
            mountPoint: "/Volumes/Shared", from: configuration.hosts[0], in: configuration)
        #expect(targets.map(\.host.host) == ["relay.example", "backup.example"])
        #expect(!targets.contains { $0.host.host == "lan.example" })
    }

    /// 候选主机只带可与失败共享配对的共享：回退不得顺带挂载无关共享。
    @Test func candidateHostsCarryOnlyPairedShares() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = try makeConfiguration([
            ("lan.example", [("Shared", "/Volumes/Shared")]),
            ("tail.example", [("Shared", "/Volumes/Shared"), ("Media", "/Volumes/Media")])
        ], at: directory)
        let candidates = HostFallbackPolicy.candidates(for: configuration.hosts[0], in: configuration)
        #expect(candidates.count == 1)
        #expect(candidates[0].shares.map(\.name) == ["Shared"])
        #expect(candidates[0].host == "tail.example")
    }

    /// 已由另一身份挂载同一共享时不得当作缺失：否则 CLI 会卸载可用卷、helper 会报冲突。
    @Test func sameShareMountRecognisedAcrossHostIdentities() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = try makeConfiguration([
            ("lan.example", [("Shared", "/Volumes/Shared")]),
            ("tail.example", [("Shared", "/Volumes/Shared")])
        ], at: directory)
        let lan = configuration.hosts[0].shares[0]
        let tail = configuration.hosts[1].shares[0]
        let tailIdentity = try #require(smbResourceIdentity(tail.smbURL))
        #expect(smbResourceIdentity(lan.smbURL) != tailIdentity)
        #expect(HostFallbackPolicy.isSameShareMount(identity: tailIdentity, shareURL: lan.smbURL))
        // 同名但不同挂载点：调用方用卷重载判断时必须拒绝。
        let volume = RecoveryRoundConfiguredVolume(identity: tailIdentity, url: tail.smbURL,
            mountPoint: "/Volumes/Shared", host: "tail.example", port: 445,
            preventSpotlightIndex: true)
        #expect(HostFallbackPolicy.isSameShareMount(identity: tailIdentity, mountPoint: "/Volumes/Shared",
                                                    volume: volume))
        #expect(!HostFallbackPolicy.isSameShareMount(identity: tailIdentity, mountPoint: "/Volumes/Elsewhere",
                                                     volume: volume))
        #expect(!HostFallbackPolicy.isSameShareMount(identity: smbResourceIdentity("smb://x.example/Other"),
                                                     shareURL: lan.smbURL))
        #expect(!HostFallbackPolicy.isSameShareMount(identity: nil, shareURL: lan.smbURL))
    }

    /// 回退卷视角与 `configuredRecoveryVolumes` 同源：身份、主机、挂载点均取自配置。
    /// 兄弟主机身份识别只认「配置内另一条主机的同名同挂载点共享」。
    @Test func peerIdentityRequiresConfiguredSiblingShareAtSameMountPoint() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = try makeConfiguration([
            ("lan.example", [("Shared", "/Volumes/Shared")]),
            ("tail.example", [("Shared", "/Volumes/Shared")])
        ], at: directory)
        let lanShare = configuration.hosts[0].shares[0]
        let tailShare = configuration.hosts[1].shares[0]
        let tailIdentity = smbResourceIdentity(tailShare.smbURL)!
        #expect(HostFallbackPolicy.peerIdentityProvidingSameShare(lanShare,
            mountedIdentity: tailIdentity, in: configuration) == tailIdentity)
        // 本身份由首选条目自己表示，不算兄弟挂载。
        let lanIdentity = smbResourceIdentity(lanShare.smbURL)!
        #expect(HostFallbackPolicy.peerIdentityProvidingSameShare(lanShare,
            mountedIdentity: lanIdentity, in: configuration) == nil)
        // 未配置的身份（例如用户自己的同名卷）不得冒认成兄弟主机。
        #expect(HostFallbackPolicy.peerIdentityProvidingSameShare(lanShare,
            mountedIdentity: "//elsewhere.example/Shared", in: configuration) == nil)
        // 同名但挂载点不同不构成同一份数据。
        var moved = configuration
        moved.hosts[1].shares[0] = SMBShareConfig(name: "Shared",
            smbURL: "smb://tail.example/Shared", mountPoint: "/Volumes/Elsewhere")
        #expect(HostFallbackPolicy.peerIdentityProvidingSameShare(lanShare,
            mountedIdentity: tailIdentity, in: moved) == nil)
    }

    @Test func fallbackVolumesMirrorConfiguredVolumes() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = try makeConfiguration([
            ("lan.example", [("Shared", "/Volumes/Shared")]),
            ("tail.example", [("Shared", "/Volumes/Shared")])
        ], at: directory)
        let volumes = configuredRecoveryVolumes(from: configuration)
        let fallbacks = HostFallbackPolicy.fallbackVolumes(for: volumes[0], in: configuration)
        #expect(fallbacks.map(\.identity) == [volumes[1].identity])
        #expect(fallbacks[0].host == "tail.example")
        #expect(fallbacks[0].mountPoint == "/Volumes/Shared")
        // 没有配对共享时为空，不得退化成「任意其他主机」。
        #expect(HostFallbackPolicy.fallbackVolumes(for: volumes[1], in: configuration)
            == volumes.filter { $0.identity == volumes[0].identity })
    }
}
