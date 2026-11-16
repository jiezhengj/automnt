import Foundation

/// 一条回退目标：把失败共享改挂到另一条启用主机上的同一共享。
public struct HostFallbackTarget: Equatable, Sendable {
    /// 回退目标在配置里的卷身份（主机不同，身份自然不同）。
    public let identity: String
    /// 目标主机（`shares` 已收窄为能配对的共享）。
    public let host: HostConfig
    /// 目标共享（与失败共享同名且同挂载点）。
    public let share: SMBShareConfig

    public init(identity: String, host: HostConfig, share: SMBShareConfig) {
        self.identity = identity
        self.host = host
        self.share = share
    }

    /// 与 `configuredRecoveryVolumes` 同形状的卷视图，供恢复轮直接使用。
    public var volume: RecoveryRoundConfiguredVolume {
        RecoveryRoundConfiguredVolume(identity: identity, url: share.smbURL,
            mountPoint: share.mountPoint, host: host.host, port: host.port,
            preventSpotlightIndex: host.preventSpotlightIndex)
    }
}

/// 同轮回退规则（唯一实现，CLI 与后台 helper 共用）。
///
/// 背景：家里走局域网地址、外面走 Tailscale 地址，是同一份配置里的两条主机条目。
/// 选路错误（例如本机代理把任意地址都「连上」）或链路中途断开时，本轮挂载会以连接类
/// 失败结束；此时改试同一共享在另一条主机上的条目，往往能当场恢复，不必等下一次系统事件。
///
/// 边界（维护者 2026-11-14 确认）：
/// - **只对连接类失败回退**（`offline` / `timeout`）。共享被拒、凭据失败、挂载点冲突
///   换一条主机也解决不了，回退只会推迟并模糊真实错误，因此**不回退**。
/// - 只在**同一轮**内回退，保持整轮 30 秒窗口不变，不引入每主机子预算。
/// - 候选必须**共享名相同且挂载点相同**：挂载点不同会让同一共享出现两份挂载。
/// - 按配置保存顺序尝试，成功即停，不重复挂两份。
public enum HostFallbackPolicy {
    /// 连接类失败：换一条主机可能解决。
    public static func isConnectionFailure(_ issue: AutomntIssue) -> Bool {
        issue == .offline || issue == .timeout
    }

    /// 恢复账本里的连接类结论同样只由这两类构成。
    public static func isConnectionFailure(_ outcome: RecoveryAttemptOutcome) -> Bool {
        outcome == .hostUnreachable
    }

    /// NetFS 挂载状态码的连接类失败判定（CLI 子进程与父进程共用）。
    ///
    /// NetFS 不返回 errno 常量，而是返回等价的正值状态码：实测「无路由 / 不应答」
    /// 返回 60（ETIMEDOUT）或 65（EHOSTUNREACH），共享被拒返回 2（ENOENT）。
    /// 只有连接类失败才值得换主机重试。
    public static func isConnectionFailure(netFSStatus: Int32) -> Bool {
        // ENETDOWN / ENETUNREACH / ETIMEDOUT / ECONNREFUSED / EHOSTDOWN / EHOSTUNREACH
        [50, 51, 60, 61, 64, 65].contains(Int(netFSStatus))
    }

    /// 两条共享是否指向同一份数据：共享名相同（不区分大小写）且挂载点相同。
    public static func sharesMatch(_ share: SMBShareConfig, _ other: SMBShareConfig) -> Bool {
        guard share.mountPoint == other.mountPoint,
              let name = extractShareName(from: share.smbURL)?.lowercased(),
              let otherName = extractShareName(from: other.smbURL)?.lowercased() else { return false }
        return name == otherName
    }

    /// 失败共享之后的回退目标（按保存顺序，排除失败主机自身）。
    ///
    /// 每个目标主机只带能与失败共享配对的那个共享，避免回退时顺带挂载无关共享。
    /// 已有 kernel 卷占用该挂载点（身份属于**另一条**主机）时也纳入：这通常是上一轮
    /// 已由回退挂上、而当前顺位主机改回可达；目标卷会因「同一共享已挂载」直接判定健康，
    /// 不会重复挂载。
    public static func targets(for share: SMBShareConfig, mountPoint: String,
                               from host: HostConfig,
                               in configuration: AutomntConfig) -> [HostFallbackTarget] {
        guard share.enabled else { return [] }
        let source = SMBShareConfig(name: share.name, smbURL: share.smbURL,
                                    mountPoint: mountPoint, enabled: share.enabled)
        var targets: [HostFallbackTarget] = []
        for candidate in configuration.hosts where candidate.enabled {
            guard !(candidate.host == host.host && candidate.port == host.port) else { continue }
            for other in candidate.shares where other.enabled && sharesMatch(source, other) {
                guard let identity = smbResourceIdentity(other.smbURL) else { continue }
                var narrowed = candidate
                narrowed.shares = [other]
                targets.append(HostFallbackTarget(identity: identity, host: narrowed, share: other))
            }
        }
        return targets
    }

    /// 失败主机整机的回退清单（按保存顺序；每个候选主机只保留可与失败主机配对的共享）。
    ///
    /// helper 侧按主机做一轮评估，因此需要「收窄后的候选主机」而不是单个共享。
    public static func candidates(for host: HostConfig,
                                  in configuration: AutomntConfig) -> [HostConfig] {
        let wanted = host.shares.filter(\.enabled)
        guard !wanted.isEmpty else { return [] }
        var result: [HostConfig] = []
        for candidate in configuration.hosts where candidate.enabled {
            guard !(candidate.host == host.host && candidate.port == host.port) else { continue }
            let paired = candidate.shares.filter { other in
                other.enabled && wanted.contains { sharesMatch($0, other) }
            }
            guard !paired.isEmpty else { continue }
            var narrowed = candidate
            narrowed.shares = paired
            result.append(narrowed)
        }
        return result
    }

    /// 恢复轮视角：失败卷的回退目标（与 `configuredRecoveryVolumes` 同源规则）。
    public static func targets(for volume: RecoveryRoundConfiguredVolume,
                               from host: HostConfig,
                               in configuration: AutomntConfig) -> [HostFallbackTarget] {
        guard let share = host.shares.first(where: { smbResourceIdentity($0.smbURL) == volume.identity })
            ?? host.shares.first(where: { extractShareName(from: $0.smbURL)?.lowercased()
                == extractShareName(from: volume.url)?.lowercased() }) else { return [] }
        return targets(for: share, mountPoint: volume.mountPoint, from: host, in: configuration)
            .filter { $0.identity != volume.identity }
    }

    /// 恢复轮视角：某卷的回退目标卷（用于同轮改试另一条主机）。
    public static func fallbackVolumes(for volume: RecoveryRoundConfiguredVolume,
                                       in configuration: AutomntConfig) -> [RecoveryRoundConfiguredVolume] {
        guard let host = configuration.hosts.first(where: {
            $0.host == volume.host && $0.port == volume.port
        }) else { return [] }
        return targets(for: volume, from: host, in: configuration).map(\.volume)
    }

    /// 目标卷是否已由「同一共享、同一挂载点」的另一身份挂载（回退成功后的常态）。
    ///
    /// 回退把同一共享挂到了另一条主机的身份上（如局域网失败、Tailscale 成功）。
    /// 此时挂载点有东西、但身份与配置里的首选主机不同；若把它当作「缺失」处理，
    /// CLI 的重新挂载会先卸载正在使用的卷再尝试挂回失败路径，helper 也会把它误报为
    /// 挂载点冲突。
    public static func isSameShareMount(identity: String?, shareURL: String) -> Bool {
        guard let identity,
              let mounted = extractShareName(from: identity)?.lowercased(),
              let expected = extractShareName(from: shareURL)?.lowercased() else { return false }
        return mounted == expected
    }

    /// 同上，入参为配置卷（额外要求挂载点与卷一致）。
    public static func isSameShareMount(identity: String?, mountPoint: String,
                                        volume: RecoveryRoundConfiguredVolume) -> Bool {
        guard mountPoint == volume.mountPoint else { return false }
        return isSameShareMount(identity: identity, shareURL: volume.url)
    }

    /// 配置内另一条主机是否正承载着「同一共享、同一挂载点」。
    ///
    /// 回退（或兄弟主机条目）把同一共享挂到另一条主机的身份上之后，首选主机条目在
    /// 内核挂载表里看到的是「挂载点是另一个 SMB 身份」。界面若把它当作第三方卷占用，
    /// 就会把已经可用的共享报成冲突。本函数只认「该身份确属配置内另一条主机的共享、
    /// 共享名与挂载点都和当前共享相同」的情况；用户自己的同名卷、未配置身份都不算。
    /// 仅做配置与身份比对，不访问网络。返回承载该挂载的身份（即配置里的兄弟条目）。
    public static func peerIdentityProvidingSameShare(_ share: SMBShareConfig,
                                                      mountedIdentity: String,
                                                      in configuration: AutomntConfig) -> String? {
        guard let ownIdentity = smbResourceIdentity(share.smbURL),
              mountedIdentity != ownIdentity else { return nil }
        for host in configuration.hosts {
            for other in host.shares {
                guard let identity = smbResourceIdentity(other.smbURL),
                      identity == mountedIdentity,
                      sharesMatch(share, other) else { continue }
                return identity
            }
        }
        return nil
    }
}
