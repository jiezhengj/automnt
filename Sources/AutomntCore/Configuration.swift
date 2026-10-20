import Foundation

public struct RetryPolicy: Codable, Equatable, Sendable {
    public var maxAttempts: Int?
    public var intervalMs: Int?
    public var maxTotalWindowMs: Int?

    public init(maxAttempts: Int? = 3, intervalMs: Int? = 1000, maxTotalWindowMs: Int? = 10000) {
        self.maxAttempts = maxAttempts
        self.intervalMs = intervalMs
        self.maxTotalWindowMs = maxTotalWindowMs
    }

    enum CodingKeys: String, CodingKey {
        case maxAttempts = "max_attempts"
        case intervalMs = "interval_ms"
        case maxTotalWindowMs = "max_total_window_ms"
    }
}

// MARK: - SMB URL 与标准挂载点推导 (SSOT)

public func extractShareName(from urlString: String) -> String? {
    let clean = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    let componentInput = clean.hasPrefix("//") ? "smb:\(clean)" : clean
    guard let components = URLComponents(string: componentInput),
          let host = components.host, !host.isEmpty else {
        return nil
    }
    let rawPath = components.percentEncodedPath
    let segments = rawPath.split(separator: "/").filter { !$0.isEmpty }
    guard let share = segments.first else { return nil }
    let decoded = String(share).removingPercentEncoding ?? String(share)
    return decoded.isEmpty ? nil : decoded
}

public func deriveStandardMountPoint(from urlString: String) -> String? {
    guard let shareName = extractShareName(from: urlString) else { return nil }
    return "/Volumes/\(shareName)"
}

// MARK: - 核心配置实体 (v3.1.0 规范与向下兼容桥接)

public struct SMBShareConfig: Codable, Equatable, Sendable {
    public var name: String
    public var smbURL: String
    public var mountPoint: String
    public var enabled: Bool = true

    enum CodingKeys: String, CodingKey {
        case name
        case smbURL = "smb_url"
        case mountPoint = "mount_point"
        case enabled
    }

    public init(name: String, smbURL: String, mountPoint: String, enabled: Bool = true) {
        self.name = name
        self.smbURL = smbURL
        self.mountPoint = mountPoint
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.smbURL = try container.decode(String.self, forKey: .smbURL)
        self.mountPoint = try container.decode(String.self, forKey: .mountPoint)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(smbURL, forKey: .smbURL)
        try container.encode(mountPoint, forKey: .mountPoint)
        try container.encode(enabled, forKey: .enabled)
    }
}

public struct HostConfig: Codable, Equatable, Sendable {
    public var host: String
    public var alias: String?
    public var port: Int = 445
    public var timeoutMs: Int = 1000
    public var preventSpotlightIndex: Bool = true
    public var enabled: Bool = true
    public var shares: [SMBShareConfig] = []

    enum CodingKeys: String, CodingKey {
        case host
        case alias
        case port
        case timeoutMs = "timeout_ms"
        case preventSpotlightIndex = "prevent_spotlight_index"
        case enabled
        case shares
    }

    public init(
        host: String,
        alias: String? = nil,
        port: Int = 445,
        timeoutMs: Int = 1000,
        preventSpotlightIndex: Bool = true,
        enabled: Bool = true,
        shares: [SMBShareConfig] = []
    ) {
        self.host = host
        self.alias = alias
        self.port = port
        self.timeoutMs = timeoutMs
        self.preventSpotlightIndex = preventSpotlightIndex
        self.enabled = enabled
        self.shares = shares
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.host = try container.decode(String.self, forKey: .host)
        self.alias = try container.decodeIfPresent(String.self, forKey: .alias)
        self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 445
        self.timeoutMs = try container.decodeIfPresent(Int.self, forKey: .timeoutMs) ?? 1000
        self.preventSpotlightIndex = try container.decodeIfPresent(Bool.self, forKey: .preventSpotlightIndex) ?? true
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.shares = try container.decodeIfPresent([SMBShareConfig].self, forKey: .shares) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encodeIfPresent(alias, forKey: .alias)
        try container.encode(port, forKey: .port)
        try container.encode(timeoutMs, forKey: .timeoutMs)
        try container.encode(preventSpotlightIndex, forKey: .preventSpotlightIndex)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(shares, forKey: .shares)
    }
}

public struct MountTarget: Codable, Equatable, Sendable {
    public var url: String
    public var mountPath: String

    public var smbURL: String {
        get { url }
        set { url = newValue }
    }

    public init(url: String, mountPath: String) {
        self.url = url
        self.mountPath = mountPath
    }

    enum CodingKeys: String, CodingKey {
        case url
        case smbURL = "smb_url"
        case mountPath = "mount_path"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mountPath = try container.decode(String.self, forKey: .mountPath)
        if let s = try container.decodeIfPresent(String.self, forKey: .smbURL) {
            self.url = s
        } else if let u = try container.decodeIfPresent(String.self, forKey: .url) {
            self.url = u
        } else {
            self.url = ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(url, forKey: .smbURL)
        try container.encode(mountPath, forKey: .mountPath)
    }
}

public struct NetworkProfile: Codable, Equatable, Sendable {
    public var id: String
    public var description: String?
    public var host: String
    public var port: Int?
    public var timeoutMs: Int?
    public var preventSpotlightIndex: Bool?
    public var targets: [MountTarget]

    public init(
        id: String,
        description: String? = nil,
        host: String,
        port: Int? = 445,
        timeoutMs: Int? = 1000,
        preventSpotlightIndex: Bool? = true,
        targets: [MountTarget] = []
    ) {
        self.id = id
        self.description = description
        self.host = host
        self.port = port
        self.timeoutMs = timeoutMs
        self.preventSpotlightIndex = preventSpotlightIndex
        self.targets = targets
    }

    enum CodingKeys: String, CodingKey {
        case id
        case description
        case host
        case port
        case timeoutMs = "timeout_ms"
        case preventSpotlightIndex = "prevent_spotlight_index"
        case targets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.host = try container.decodeIfPresent(String.self, forKey: .host) ?? "localhost"
        self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 445
        self.timeoutMs = try container.decodeIfPresent(Int.self, forKey: .timeoutMs) ?? 1000
        self.preventSpotlightIndex = try container.decodeIfPresent(Bool.self, forKey: .preventSpotlightIndex) ?? true
        self.targets = try container.decodeIfPresent([MountTarget].self, forKey: .targets) ?? []
    }

    public var effectiveProbeHost: String {
        return host
    }
}

public struct AutomntConfig: Codable, Equatable, Sendable {
    public var version: String
    public var updateChannel: String?                 // "off" (默认), "notify", "auto"
    public var retryPolicy: RetryPolicy?
    public var lastUpdateCheckTimestamp: Double?     // 更新检查最近一次尝试时间戳
    public var updateRetryAfterTimestamp: Double? = nil
    public var lastNotifiedVersion: String?          // 单版本仅提醒 1 次防打扰
    public var hosts: [HostConfig] = []
    public var profiles: [NetworkProfile] = []
    /// FR-008 自动恢复开关。nil 与 true 等价（缺省启用）；仅显式 false 关闭。
    public var autoMountRecovery: Bool?
    /// Missing key preserves existing CLI automation intent.
    public var automationEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case version
        case updateChannel = "update_channel"
        case retryPolicy = "retry_policy"
        case lastUpdateCheckTimestamp = "last_update_check_timestamp"
        case updateRetryAfterTimestamp = "update_retry_after_timestamp"
        case lastNotifiedVersion = "last_notified_version"
        case hosts
        case profiles
        case autoMountRecovery = "auto_mount_recovery"
        case automationEnabled = "automation_enabled"
    }

    public init(
        version: String = AutomntBuildVersion.value,
        updateChannel: String? = "off",
        retryPolicy: RetryPolicy? = RetryPolicy(),
        lastUpdateCheckTimestamp: Double? = nil,
        updateRetryAfterTimestamp: Double? = nil,
        lastNotifiedVersion: String? = nil,
        hosts: [HostConfig] = [],
        profiles: [NetworkProfile] = [],
        autoMountRecovery: Bool? = nil,
        automationEnabled: Bool? = nil
    ) {
        self.version = version
        self.updateChannel = updateChannel
        self.retryPolicy = retryPolicy
        self.lastUpdateCheckTimestamp = lastUpdateCheckTimestamp
        self.updateRetryAfterTimestamp = updateRetryAfterTimestamp
        self.lastNotifiedVersion = lastNotifiedVersion
        self.hosts = hosts
        self.profiles = profiles
        self.autoMountRecovery = autoMountRecovery
        self.automationEnabled = automationEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(String.self, forKey: .version)
        self.updateChannel = try container.decodeIfPresent(String.self, forKey: .updateChannel)
        self.retryPolicy = try container.decodeIfPresent(RetryPolicy.self, forKey: .retryPolicy)
        self.lastUpdateCheckTimestamp = try container.decodeIfPresent(Double.self, forKey: .lastUpdateCheckTimestamp)
        self.updateRetryAfterTimestamp = try container.decodeIfPresent(Double.self, forKey: .updateRetryAfterTimestamp)
        self.lastNotifiedVersion = try container.decodeIfPresent(String.self, forKey: .lastNotifiedVersion)
        self.hosts = try container.decodeIfPresent([HostConfig].self, forKey: .hosts) ?? []
        self.profiles = try container.decodeIfPresent([NetworkProfile].self, forKey: .profiles) ?? []
        // 缺省语义：键缺失 = 启用（FR-008 默认启用）
        self.autoMountRecovery = try container.decodeIfPresent(Bool.self, forKey: .autoMountRecovery)
        self.automationEnabled = try container.decodeIfPresent(Bool.self, forKey: .automationEnabled)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(updateChannel, forKey: .updateChannel)
        try container.encodeIfPresent(retryPolicy, forKey: .retryPolicy)
        try container.encodeIfPresent(lastUpdateCheckTimestamp, forKey: .lastUpdateCheckTimestamp)
        try container.encodeIfPresent(updateRetryAfterTimestamp, forKey: .updateRetryAfterTimestamp)
        try container.encodeIfPresent(lastNotifiedVersion, forKey: .lastNotifiedVersion)
        try container.encode(hosts, forKey: .hosts)
        if !profiles.isEmpty {
            try container.encode(profiles, forKey: .profiles)
        }
        try container.encodeIfPresent(autoMountRecovery, forKey: .autoMountRecovery)
        try container.encodeIfPresent(automationEnabled, forKey: .automationEnabled)
    }

    /// 生效值：缺省视为启用。
    public var isAutoMountRecoveryEnabled: Bool { autoMountRecovery ?? true }
    public var isAutomationEnabled: Bool { automationEnabled ?? true }
}

