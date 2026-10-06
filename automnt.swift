#!/usr/bin/env swift
// automnt.swift
// 自动挂载 NAS 工具 (macOS 原生单活动配置与事件驱动架构)
//
// 核心架构与特性：
// 1. 目标服务可达性路由 (HostReachabilityProbe)：
//    - 基于原生 POSIX 非阻塞 Socket 直连探测主机 TCP 445 端口判定网络环境。
//    - 彻底废除网关 MAC 与 ARP 链路层地址依赖。
// 2. 事件驱动响应式守护与有限重试：
//    - LaunchAgent 由系统网络配置变化事件 (WatchPaths) 驱动，杜绝轮询 (无 StartInterval)。
//    - 单轮网络评估由 EvaluationRetryRunner 在有限重试窗口 (默认 3 次, 间隔 1s, 上限 10s) 内执行。
// 3. 失效 SMB 挂载超时清理：
//    - Darwin 原生 MNT_NOWAIT 内核挂载表非阻塞快照查询，杜绝 stat() 阻塞。
//    - 自动比对同源性，有时限的 diskutil 与 umount -f 强制清理。
// 4. Spotlight 索引防护：挂载后请求 mdutil -i off 并尝试创建 .metadata_never_index。
// 5. 单用户规范安装与单一活动配置：
//    - 规范安装于 ~/Library/Application Support/automnt/bin/automnt。
//    - 单一活动配置 ~/Library/Application Support/automnt/automnt.plist (0600 权限)。
//    - 首次下载运行自搬迁并 unlink 临时副本，自动向当前 Shell 配置文件注入定界 CLI 入口。
// 6. 免本地编译预编译升级：从 GitHub Release 获取预编译 Mach-O 二进制原子替换，零本地编译。

import Foundation
import SystemConfiguration
import NetFS
import Darwin

// MARK: - 基础辅助函数与国际化 (i18n)

var isEnglish: Bool {
    let env = ProcessInfo.processInfo.environment["AUTOMNT_LANG"]
    if let envLang = env?.lowercased() {
        if envLang.starts(with: "en") { return true }
        if envLang.starts(with: "zh") { return false }
    }
    if let preferred = Locale.preferredLanguages.first?.lowercased() {
        if preferred.starts(with: "zh") { return false }
        return true
    }
    if let lang = ProcessInfo.processInfo.environment["LANG"]?.lowercased() {
        if lang.starts(with: "zh") { return false }
    }
    return true
}

func tr(_ zh: String, _ en: String) -> String {
    return isEnglish ? en : zh
}

var configURLOverride: URL?
var isTTYOverride: Bool?

func isInteractiveTerminal() -> Bool {
    if let override = isTTYOverride {
        return override
    }
    return isatty(STDIN_FILENO) != 0
}

func getActiveInstalledDir() -> URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return appSupport.appendingPathComponent("automnt")
}

func getActiveInstalledBinaryURL() -> URL {
    getActiveInstalledDir().appendingPathComponent("bin").appendingPathComponent("automnt")
}

func getActiveConfigURL() -> URL {
    if let override = configURLOverride {
        return override
    }
    return getActiveInstalledDir().appendingPathComponent("automnt.plist")
}

func getConfigURL() -> URL {
    return getActiveConfigURL()
}

func getLaunchAgentPlistURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.user.automnt.plist")
}

let launchAgentLabel = "com.user.automnt"

func writeLog(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let timestamp = formatter.string(from: Date())
    let logLine = "[\(timestamp)] \(message)\n"
    let installDir = getActiveInstalledDir()
    let logURL = installDir.appendingPathComponent("automnt.log")

    try? FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        if let data = logLine.data(using: .utf8) {
            handle.write(data)
        }
        try? handle.close()
    } else {
        try? logLine.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - 外部命令执行辅助

final class CommandOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var standardOutput = Data()
    private var standardError = Data()

    func storeStandardOutput(_ data: Data) {
        lock.lock()
        standardOutput = data
        lock.unlock()
    }

    func storeStandardError(_ data: Data) {
        lock.lock()
        standardError = data
        lock.unlock()
    }

    func snapshot() -> (standardOutput: Data, standardError: Data) {
        lock.lock()
        defer { lock.unlock() }
        return (standardOutput, standardError)
    }
}

@discardableResult
func runCommand(executable: String, arguments: [String]) -> (status: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    do {
        try process.run()
        outPipe.fileHandleForWriting.closeFile()
        errPipe.fileHandleForWriting.closeFile()

        let readGroup = DispatchGroup()
        let outputBuffer = CommandOutputBuffer()
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            outputBuffer.storeStandardOutput(data)
            readGroup.leave()
        }
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            outputBuffer.storeStandardError(data)
            readGroup.leave()
        }
        process.waitUntilExit()
        readGroup.wait()
        let captured = outputBuffer.snapshot()
        let outStr = String(data: captured.standardOutput, encoding: .utf8) ?? ""
        let errStr = String(data: captured.standardError, encoding: .utf8) ?? ""
        return (process.terminationStatus, outStr, errStr)
    } catch {
        return (-1, "", error.localizedDescription)
    }
}

struct BoundedCommandResult {
    let status: Int32?
    let timedOut: Bool
    let processStopped: Bool
    let error: String?
}

func runCommandDiscardingOutputWithTimeout(
    executable: String,
    arguments: [String],
    timeout: TimeInterval
) -> BoundedCommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return BoundedCommandResult(status: nil, timedOut: false, processStopped: true,
                                   error: error.localizedDescription)
    }

    let waitGroup = DispatchGroup()
    waitGroup.enter()
    DispatchQueue.global(qos: .utility).async {
        process.waitUntilExit()
        waitGroup.leave()
    }

    let boundedTimeout = timeout.isFinite ? max(timeout, 0) : 0
    guard waitGroup.wait(timeout: .now() + boundedTimeout) == .timedOut else {
        return BoundedCommandResult(status: process.terminationStatus, timedOut: false,
                                   processStopped: true, error: nil)
    }

    process.terminate()
    if waitGroup.wait(timeout: .now() + 0.5) == .timedOut {
        _ = kill(process.processIdentifier, SIGKILL)
        return BoundedCommandResult(status: nil, timedOut: true, processStopped: false, error: nil)
    }
    return BoundedCommandResult(status: process.terminationStatus, timedOut: true,
                               processStopped: true, error: nil)
}

// MARK: - 版本与数据结构定义

let automntVersion = "3.2.0"
let minimumSupportedMacOSMajorVersion = 27
let minimumSupportedMacOSVersion = "\(minimumSupportedMacOSMajorVersion).0"
let githubRepo = "jiezhengj/automnt"

func normalizedArchitecture(_ architecture: String) -> String {
    architecture.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

func platformSupportIssue(macOSMajorVersion: Int, architecture: String) -> String? {
    guard normalizedArchitecture(architecture) == "arm64" else { return "architecture" }
    guard macOSMajorVersion >= minimumSupportedMacOSMajorVersion else { return "macOS_version" }
    return nil
}

struct RetryPolicy: Codable, Equatable {
    var maxAttempts: Int?
    var intervalMs: Int?
    var maxTotalWindowMs: Int?

    init(maxAttempts: Int? = 3, intervalMs: Int? = 1000, maxTotalWindowMs: Int? = 10000) {
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

func extractShareName(from urlString: String) -> String? {
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

func deriveStandardMountPoint(from urlString: String) -> String? {
    guard let shareName = extractShareName(from: urlString) else { return nil }
    return "/Volumes/\(shareName)"
}

// MARK: - 核心配置实体 (v3.1.0 规范与向下兼容桥接)

struct SMBShareConfig: Codable, Equatable {
    var name: String
    var smbURL: String
    var mountPoint: String
    var enabled: Bool = true

    enum CodingKeys: String, CodingKey {
        case name
        case smbURL = "smb_url"
        case mountPoint = "mount_point"
        case enabled
    }

    init(name: String, smbURL: String, mountPoint: String, enabled: Bool = true) {
        self.name = name
        self.smbURL = smbURL
        self.mountPoint = mountPoint
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.smbURL = try container.decode(String.self, forKey: .smbURL)
        self.mountPoint = try container.decode(String.self, forKey: .mountPoint)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(smbURL, forKey: .smbURL)
        try container.encode(mountPoint, forKey: .mountPoint)
        try container.encode(enabled, forKey: .enabled)
    }
}

struct HostConfig: Codable, Equatable {
    var host: String
    var alias: String?
    var port: Int = 445
    var timeoutMs: Int = 1000
    var preventSpotlightIndex: Bool = true
    var enabled: Bool = true
    var shares: [SMBShareConfig] = []

    enum CodingKeys: String, CodingKey {
        case host
        case alias
        case port
        case timeoutMs = "timeout_ms"
        case preventSpotlightIndex = "prevent_spotlight_index"
        case enabled
        case shares
    }

    init(
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.host = try container.decode(String.self, forKey: .host)
        self.alias = try container.decodeIfPresent(String.self, forKey: .alias)
        self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 445
        self.timeoutMs = try container.decodeIfPresent(Int.self, forKey: .timeoutMs) ?? 1000
        self.preventSpotlightIndex = try container.decodeIfPresent(Bool.self, forKey: .preventSpotlightIndex) ?? true
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.shares = try container.decodeIfPresent([SMBShareConfig].self, forKey: .shares) ?? []
    }

    func encode(to encoder: Encoder) throws {
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

struct MountTarget: Codable, Equatable {
    var url: String
    var mountPath: String

    var smbURL: String {
        get { url }
        set { url = newValue }
    }

    init(url: String, mountPath: String) {
        self.url = url
        self.mountPath = mountPath
    }

    enum CodingKeys: String, CodingKey {
        case url
        case smbURL = "smb_url"
        case mountPath = "mount_path"
    }

    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(url, forKey: .smbURL)
        try container.encode(mountPath, forKey: .mountPath)
    }
}

struct NetworkProfile: Codable, Equatable {
    var id: String
    var description: String?
    var host: String
    var port: Int?
    var timeoutMs: Int?
    var preventSpotlightIndex: Bool?
    var targets: [MountTarget]

    init(
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.host = try container.decodeIfPresent(String.self, forKey: .host) ?? "localhost"
        self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 445
        self.timeoutMs = try container.decodeIfPresent(Int.self, forKey: .timeoutMs) ?? 1000
        self.preventSpotlightIndex = try container.decodeIfPresent(Bool.self, forKey: .preventSpotlightIndex) ?? true
        self.targets = try container.decodeIfPresent([MountTarget].self, forKey: .targets) ?? []
    }

    var effectiveProbeHost: String {
        return host
    }
}

struct AutomntConfig: Codable, Equatable {
    var version: String
    var updateChannel: String?                 // "off" (默认), "notify", "auto"
    var retryPolicy: RetryPolicy?
    var lastUpdateCheckTimestamp: Double?     // 更新检查最近一次尝试时间戳
    var updateRetryAfterTimestamp: Double? = nil
    var lastNotifiedVersion: String?          // 单版本仅提醒 1 次防打扰
    var hosts: [HostConfig] = []
    var profiles: [NetworkProfile] = []

    enum CodingKeys: String, CodingKey {
        case version
        case updateChannel = "update_channel"
        case retryPolicy = "retry_policy"
        case lastUpdateCheckTimestamp = "last_update_check_timestamp"
        case updateRetryAfterTimestamp = "update_retry_after_timestamp"
        case lastNotifiedVersion = "last_notified_version"
        case hosts
        case profiles
    }

    init(
        version: String = automntVersion,
        updateChannel: String? = "off",
        retryPolicy: RetryPolicy? = RetryPolicy(),
        lastUpdateCheckTimestamp: Double? = nil,
        updateRetryAfterTimestamp: Double? = nil,
        lastNotifiedVersion: String? = nil,
        hosts: [HostConfig] = [],
        profiles: [NetworkProfile] = []
    ) {
        self.version = version
        self.updateChannel = updateChannel
        self.retryPolicy = retryPolicy
        self.lastUpdateCheckTimestamp = lastUpdateCheckTimestamp
        self.updateRetryAfterTimestamp = updateRetryAfterTimestamp
        self.lastNotifiedVersion = lastNotifiedVersion
        self.hosts = hosts
        self.profiles = profiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(String.self, forKey: .version)
        self.updateChannel = try container.decodeIfPresent(String.self, forKey: .updateChannel)
        self.retryPolicy = try container.decodeIfPresent(RetryPolicy.self, forKey: .retryPolicy)
        self.lastUpdateCheckTimestamp = try container.decodeIfPresent(Double.self, forKey: .lastUpdateCheckTimestamp)
        self.updateRetryAfterTimestamp = try container.decodeIfPresent(Double.self, forKey: .updateRetryAfterTimestamp)
        self.lastNotifiedVersion = try container.decodeIfPresent(String.self, forKey: .lastNotifiedVersion)
        self.hosts = try container.decodeIfPresent([HostConfig].self, forKey: .hosts) ?? []
        self.profiles = try container.decodeIfPresent([NetworkProfile].self, forKey: .profiles) ?? []
    }

    func encode(to encoder: Encoder) throws {
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
    }
}

enum ConfigFileState: Equatable {
    case missing
    case usable
    case invalid
    case futureVersion(String)
    case inaccessible
}

struct ConfigFileInspection {
    let url: URL
    let state: ConfigFileState
    let config: AutomntConfig?
    let contents: Data?
    let diagnostic: String?
}

func inspectConfigFile(at url: URL) -> ConfigFileInspection {
    var fileInfo = stat()
    let statResult = url.path.withCString { Darwin.lstat($0, &fileInfo) }
    guard statResult == 0 else {
        let errorCode = errno
        let isMissing = errorCode == ENOENT
        let diagnostic = String(cString: strerror(errorCode))
        return ConfigFileInspection(url: url, state: isMissing ? .missing : .inaccessible,
                                    config: nil, contents: nil,
                                    diagnostic: isMissing ? nil : diagnostic)
    }

    guard fileInfo.st_mode & S_IFMT == S_IFREG else {
        return ConfigFileInspection(url: url, state: .inaccessible, config: nil, contents: nil,
                                    diagnostic: "Configuration path is not a regular file")
    }

    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        return ConfigFileInspection(url: url, state: .inaccessible, config: nil, contents: nil,
                                    diagnostic: error.localizedDescription)
    }

    guard var config = try? PropertyListDecoder().decode(AutomntConfig.self, from: data),
          !parseSemanticVersion(config.version).isEmpty else {
        return ConfigFileInspection(url: url, state: .invalid, config: nil, contents: data,
                                    diagnostic: "Configuration is malformed")
    }
    guard !isNewerVersion(config.version, than: automntVersion) else {
        return ConfigFileInspection(url: url, state: .futureVersion(config.version), config: config,
                                    contents: data, diagnostic: nil)
    }
    config.version = config.version.trimmingCharacters(in: .whitespacesAndNewlines)
    return ConfigFileInspection(url: url, state: .usable, config: config, contents: data, diagnostic: nil)
}

func configInspectionMatches(_ expected: ConfigFileInspection, _ current: ConfigFileInspection) -> Bool {
    expected.url.standardizedFileURL == current.url.standardizedFileURL
        && expected.state == current.state
        && expected.contents == current.contents
}

func configBackupURL(for configURL: URL, now: Date = Date()) -> URL {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let timestamp = formatter.string(from: now).replacingOccurrences(of: ":", with: "")
    let parentURL = configURL.deletingLastPathComponent()
    let baseName = "\(configURL.lastPathComponent).backup-\(timestamp)"
    var candidate = parentURL.appendingPathComponent(baseName)
    var suffix = 2
    while FileManager.default.fileExists(atPath: candidate.path) {
        candidate = parentURL.appendingPathComponent("\(baseName)-\(suffix)")
        suffix += 1
    }
    return candidate
}

func backUpConfigFile(_ inspection: ConfigFileInspection) throws -> URL? {
    guard let contents = inspection.contents else { return nil }
    let backupURL = configBackupURL(for: inspection.url)
    try atomicWrite(contents, to: backupURL, permissions: 0o600)
    return backupURL
}

func pruneConfigBackups(for configURL: URL, maxToKeep: Int = 1) {
    let parentURL = configURL.deletingLastPathComponent()
    let prefix = "\(configURL.lastPathComponent).backup-"
    guard let contents = try? FileManager.default.contentsOfDirectory(at: parentURL, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
    let backups = contents.filter { $0.lastPathComponent.hasPrefix(prefix) }
    guard backups.count > maxToKeep else { return }

    let sorted = backups.sorted { url1, url2 in
        let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
        let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
        return date1 > date2
    }

    for url in sorted.dropFirst(maxToKeep) {
        try? FileManager.default.removeItem(at: url)
    }
}

func atomicWrite(_ data: Data, to url: URL, permissions: Int? = nil) throws {
    let parentDir = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
    let tempURL = parentDir.appendingPathComponent(".tmp.\(UUID().uuidString)")
    try data.write(to: tempURL)
    let targetPermissions = permissions ?? 0o600
    try FileManager.default.setAttributes([.posixPermissions: targetPermissions], ofItemAtPath: tempURL.path)
    _ = Darwin.rename(tempURL.path, url.path)
}

struct StagedFileReplacement {
    let sourceURL: URL
    let destinationURL: URL
    let permissions: Int
}

func replaceFilesTransactionally(
    _ replacements: [StagedFileReplacement],
    postReplaceAction: (() throws -> Void)? = nil
) throws {
    var backups: [(backupURL: URL, destinationURL: URL, originalPermissions: Int?)] = []
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("automnt-atomic-txn-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    do {
        for replacement in replacements {
            let dest = replacement.destinationURL
            if FileManager.default.fileExists(atPath: dest.path) {
                let backup = tempDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.copyItem(at: dest, to: backup)
                let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
                let originalPerms = (attrs[.posixPermissions] as? NSNumber)?.intValue
                backups.append((backup, dest, originalPerms))
            }
        }

        for replacement in replacements {
            let tempStaged = replacement.destinationURL.deletingLastPathComponent()
                .appendingPathComponent(".tmp.\(UUID().uuidString)")
            try FileManager.default.copyItem(at: replacement.sourceURL, to: tempStaged)
            try FileManager.default.setAttributes([.posixPermissions: replacement.permissions], ofItemAtPath: tempStaged.path)
            _ = Darwin.rename(tempStaged.path, replacement.destinationURL.path)
        }

        if let postReplaceAction {
            try postReplaceAction()
        }
    } catch {
        for backup in backups.reversed() {
            _ = Darwin.rename(backup.backupURL.path, backup.destinationURL.path)
            if let perms = backup.originalPermissions {
                try? FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: backup.destinationURL.path)
            }
        }
        throw error
    }
}

// MARK: - 配置文件原地迁移 (In-Place Schema Migration)

func configVersionCanBeMigrated(_ configVersion: String) -> Bool {
    !isNewerVersion(configVersion, than: automntVersion)
}

func configNeedsMigration(_ config: AutomntConfig) -> Bool {
    if config.version != automntVersion { return true }
    if config.updateChannel == nil { return true }
    if !config.profiles.isEmpty { return true }
    for host in config.hosts {
        for share in host.shares {
            if let cleanMount = deriveStandardMountPoint(from: share.smbURL), cleanMount != share.mountPoint {
                return true
            }
        }
    }
    return false
}

func migrateConfigIfNeeded(config: inout AutomntConfig, at configURL: URL) -> Bool {
    guard configVersionCanBeMigrated(config.version) else {
        fputs(tr("✗ 配置版本 v\(config.version) 高于当前程序 v\(automntVersion)，为避免降级破坏配置，已停止运行。\n",
                 "✗ Config version v\(config.version) is newer than program v\(automntVersion); refusing to downgrade the config.\n"), stderr)
        writeLog("Refused to migrate newer config version \(config.version) with program \(automntVersion)")
        return false
    }

    guard configNeedsMigration(config) else { return true }

    // 迁移前备份并限制最多保留 1 份 (FR-024, SC-016)
    let inspection = inspectConfigFile(at: configURL)
    if let _ = try? backUpConfigFile(inspection) {
        pruneConfigBackups(for: configURL, maxToKeep: 1)
    }

    var modified = false
    if config.version != automntVersion {
        config.version = automntVersion
        modified = true
    }
    if config.updateChannel == nil {
        config.updateChannel = "off"
        modified = true
    }

    // 存量 profiles 升舱为 hosts (US6) 并深度清洗历史挂载路径
    if !config.profiles.isEmpty {
        var migratedHosts: [HostConfig] = config.hosts
        for p in config.profiles {
            var shares: [SMBShareConfig] = []
            for t in p.targets {
                let cleanMount = deriveStandardMountPoint(from: t.url) ?? t.mountPath
                let sName = extractShareName(from: t.url) ?? "share"
                shares.append(SMBShareConfig(
                    name: sName,
                    smbURL: t.url,
                    mountPoint: cleanMount,
                    enabled: true
                ))
            }
            let hostConfig = HostConfig(
                host: p.host,
                alias: p.description,
                port: p.port ?? 445,
                timeoutMs: p.timeoutMs ?? 1000,
                preventSpotlightIndex: p.preventSpotlightIndex ?? true,
                enabled: true,
                shares: shares
            )
            if !migratedHosts.contains(where: { $0.host == hostConfig.host }) {
                migratedHosts.append(hostConfig)
            }
        }
        config.hosts = migratedHosts
        config.profiles = []
        modified = true
    }

    // 检查并清洗现有 hosts 中的历史挂载点路径（防止历史 -1 污染残留）
    for hIdx in 0..<config.hosts.count {
        for sIdx in 0..<config.hosts[hIdx].shares.count {
            let share = config.hosts[hIdx].shares[sIdx]
            if let cleanMount = deriveStandardMountPoint(from: share.smbURL), cleanMount != share.mountPoint {
                config.hosts[hIdx].shares[sIdx].mountPoint = cleanMount
                modified = true
            }
        }
    }

    guard modified else { return true }
    guard saveConfig(config, to: configURL) else {
        fputs(tr("✗ 配置已迁移到内存，但未能完整写入配置文件。\n",
                 "✗ Configuration was migrated in memory, but could not be fully saved.\n"), stderr)
        writeLog("Configuration migration to v\(automntVersion) could not be persisted")
        return false
    }
    print(tr("✓ 配置文件已自动平滑升级至 v\(automntVersion) 格式规范",
             "✓ Configuration automatically upgraded to v\(automntVersion) schema"))
    writeLog("Configuration auto-migrated to v\(automntVersion)")
    return true
}

@discardableResult
func migrateActiveConfigIfNeeded() -> Bool {
    let configURL = getActiveConfigURL()
    guard FileManager.default.fileExists(atPath: configURL.path) else { return true }
    guard var config = loadConfig(from: configURL, migrate: false) else { return false }
    return migrateConfigIfNeeded(config: &config, at: configURL)
}

func loadConfig(from configURL: URL? = nil, migrate: Bool = true) -> AutomntConfig? {
    let targetURL = configURL ?? getConfigURL()
    guard FileManager.default.fileExists(atPath: targetURL.path) else { return nil }
    guard let data = try? Data(contentsOf: targetURL) else { return nil }
    let decoder = PropertyListDecoder()
    guard var config = try? decoder.decode(AutomntConfig.self, from: data) else { return nil }
    if migrate && configNeedsMigration(config) {
        _ = migrateConfigIfNeeded(config: &config, at: targetURL)
    }
    return config
}

enum ConfigPlistContext: Equatable {
    case root
    case profiles
    case profile
    case targets
    case target
    case hosts
    case host
    case shares
    case share
    case other
}

func canonicalProfileID(_ value: String) -> String {
    switch value {
    case "home_lan": return "local_lan"
    case "tailscale_remote": return "remote_network"
    default: return value
    }
}

func managedConfigKeys(for context: ConfigPlistContext) -> Set<String> {
    switch context {
    case .root:
        return ["version", "update_channel", "retry_policy", "last_update_check_timestamp",
                "update_retry_after_timestamp", "last_notified_version", "hosts", "profiles"]
    case .profile:
        return ["id", "description", "host", "port", "timeout_ms",
                "prevent_spotlight_index", "targets"]
    case .target:
        return ["url", "mount_path"]
    case .host:
        return ["host", "alias", "port", "timeout_ms", "prevent_spotlight_index", "enabled", "shares"]
    case .share:
        return ["name", "smb_url", "mount_point", "enabled"]
    case .profiles, .targets, .hosts, .shares, .other:
        return []
    }
}

func childConfigPlistContext(parent: ConfigPlistContext, key: String) -> ConfigPlistContext {
    switch (parent, key) {
    case (.root, "profiles"): return .profiles
    case (.profile, "targets"): return .targets
    case (.root, "hosts"): return .hosts
    case (.host, "shares"): return .shares
    default: return .other
    }
}

func configPlistIdentity(_ value: Any, context: ConfigPlistContext) -> String? {
    guard let dict = value as? [String: Any] else { return nil }
    switch context {
    case .profiles, .profile:
        return (dict["id"] as? String).map(canonicalProfileID)
    case .targets, .target:
        return (dict["mount_path"] as? String) ?? (dict["mountPath"] as? String)
    case .hosts, .host:
        return dict["host"] as? String
    case .shares, .share:
        return (dict["mount_point"] as? String) ?? (dict["smb_url"] as? String)
    case .root, .other:
        return nil
    }
}

func mergeConfigPlistValue(original: Any, generated: Any, context: ConfigPlistContext) -> Any {
    if let originalDict = original as? [String: Any],
       let generatedDict = generated as? [String: Any] {
        var merged = generatedDict
        let managed = managedConfigKeys(for: context)
        for (key, originalValue) in originalDict where !managed.contains(key) {
            merged[key] = originalValue
        }
        for (key, generatedValue) in generatedDict {
            if let originalChild = originalDict[key] {
                let childContext = childConfigPlistContext(parent: context, key: key)
                merged[key] = mergeConfigPlistValue(original: originalChild, generated: generatedValue, context: childContext)
            }
        }
        return merged
    }

    if let originalArray = original as? [[String: Any]],
       let generatedArray = generated as? [[String: Any]] {
        var originalByID: [String: [String: Any]] = [:]
        for item in originalArray {
            if let id = configPlistIdentity(item, context: context) {
                originalByID[id] = item
            }
        }
        var mergedArray: [[String: Any]] = []
        let childContext: ConfigPlistContext
        switch context {
        case .profiles: childContext = .profile
        case .targets: childContext = .target
        case .hosts: childContext = .host
        case .shares: childContext = .share
        default: childContext = .other
        }
        for item in generatedArray {
            if let id = configPlistIdentity(item, context: context), let originalItem = originalByID[id] {
                let mergedItem = mergeConfigPlistValue(original: originalItem, generated: item, context: childContext) as? [String: Any] ?? item
                mergedArray.append(mergedItem)
            } else {
                mergedArray.append(item)
            }
        }
        return mergedArray
    }

    return generated
}

func encodeConfigPreservingUnknownFields(_ config: AutomntConfig, at configURL: URL) throws -> Data {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .xml
    let generatedData = try encoder.encode(config)

    guard FileManager.default.fileExists(atPath: configURL.path),
          let originalData = try? Data(contentsOf: configURL),
          let originalPlist = try? PropertyListSerialization.propertyList(from: originalData, options: [], format: nil),
          let generatedPlist = try? PropertyListSerialization.propertyList(from: generatedData, options: [], format: nil) else {
        return generatedData
    }

    let mergedPlist = mergeConfigPlistValue(original: originalPlist, generated: generatedPlist, context: .root)
    return try PropertyListSerialization.data(fromPropertyList: mergedPlist, format: .xml, options: 0)
}

func saveConfig(
    _ config: AutomntConfig,
    to configURL: URL? = nil,
    preserveUnknownFields: Bool = true
) -> Bool {
    let resolvedURL = configURL ?? getConfigURL()
    do {
        let parentDir = resolvedURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
        let data: Data
        if preserveUnknownFields {
            data = try encodeConfigPreservingUnknownFields(config, at: resolvedURL)
        } else {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            data = try encoder.encode(config)
        }
        try atomicWrite(data, to: resolvedURL, permissions: 0o600)
        print(tr("✓ 配置已即时保存至: \(resolvedURL.path)",
                 "✓ Config saved to: \(resolvedURL.path)"))
        return true
    } catch {
        fputs("✗ Failed to save config: \(error.localizedDescription)\n", stderr)
        writeLog("Failed to save config: \(error.localizedDescription)")
        return false
    }
}

// MARK: - 主机可达性探测器与网络辅助函数

struct HostReachabilityProbe {
    static var testOverride: ((String, Int, Int) -> Bool)? = nil

    static func canConnect(host: String, port: Int = 445, timeoutMs: Int = 1000) -> Bool {
        if let testOverride { return testOverride(host, port, timeoutMs) }
        guard !host.isEmpty else { return false }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var res: UnsafeMutablePointer<addrinfo>?
        let portString = "\(port)"
        guard getaddrinfo(host, portString, &hints, &res) == 0, let firstAddr = res else {
            return false
        }
        defer { freeaddrinfo(res) }

        var curr: UnsafeMutablePointer<addrinfo>? = firstAddr
        while let ai = curr {
            let sock = socket(ai.pointee.ai_family, ai.pointee.ai_socktype, ai.pointee.ai_protocol)
            if sock >= 0 {
                let flags = fcntl(sock, F_GETFL, 0)
                _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

                let connRes = connect(sock, ai.pointee.ai_addr, ai.pointee.ai_addrlen)
                if connRes == 0 {
                    close(sock)
                    return true
                }
                if errno == EINPROGRESS {
                    var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
                    let pollRes = poll(&pfd, 1, Int32(max(timeoutMs, 10)))
                    if pollRes > 0 && (pfd.revents & Int16(POLLOUT)) != 0 {
                        var err: Int32 = 0
                        var errLen = socklen_t(MemoryLayout<Int32>.size)
                        if getsockopt(sock, SOL_SOCKET, SO_ERROR, &err, &errLen) == 0 && err == 0 {
                            close(sock)
                            return true
                        }
                    }
                }
                close(sock)
            }
            curr = ai.pointee.ai_next
        }
        return false
    }
}

struct EvaluationRetryRunner {
    let policy: RetryPolicy

    init(policy: RetryPolicy = RetryPolicy()) {
        self.policy = policy
    }

    func run(block: () -> Bool) -> Bool {
        let maxAttempts = min(max(policy.maxAttempts ?? 3, 1), 10)
        let intervalMs = min(max(policy.intervalMs ?? 1000, 100), 5000)
        let maxTotalWindowMs = min(max(policy.maxTotalWindowMs ?? 10000, 1000), 30000)

        let startTime = Date()
        for attempt in 1...maxAttempts {
            if block() {
                return true
            }
            if attempt == maxAttempts {
                break
            }
            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
            if elapsedMs + intervalMs > maxTotalWindowMs {
                break
            }
            usleep(useconds_t(intervalMs * 1000))
        }
        return false
    }
}

func isIPv4Address(_ value: String) -> Bool {
    var address = in_addr()
    return value.withCString { inet_pton(AF_INET, $0, &address) } == 1
}

func isIPAddress(_ value: String) -> Bool {
    if isIPv4Address(value) { return true }
    var address6 = in6_addr()
    return value.withCString({ inet_pton(AF_INET6, $0, &address6) }) == 1
}

func extractHost(from string: String) -> String {
    var clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let componentInput = clean.hasPrefix("//") ? "smb:\(clean)" : clean
    if let components = URLComponents(string: componentInput),
       let host = components.host, !host.isEmpty {
        return host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
    }
    if clean.hasPrefix("smb://") {
        clean = String(clean.dropFirst(6))
    } else if clean.hasPrefix("//") {
        clean = String(clean.dropFirst(2))
    }
    if let atIndex = clean.firstIndex(of: "@") {
        clean = String(clean[clean.index(after: atIndex)...])
    }
    if let slashIndex = clean.firstIndex(of: "/") {
        clean = String(clean[..<slashIndex])
    }
    if clean.hasPrefix("["), let closingBracket = clean.firstIndex(of: "]") {
        return String(clean[clean.index(after: clean.startIndex)..<closingBracket]).lowercased()
    }
    if let colonIndex = clean.firstIndex(of: ":") {
        clean = String(clean[..<colonIndex])
    }
    return clean.lowercased()
}

func smbResourceIdentity(_ value: String) -> String? {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let componentInput = clean.hasPrefix("//") ? "smb:\(clean)" : clean
    guard let components = URLComponents(string: componentInput),
          let host = components.host, !host.isEmpty else {
        return nil
    }
    let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
    let rawPath = components.percentEncodedPath
    let segments = rawPath.split(separator: "/").filter { !$0.isEmpty }
    guard let share = segments.first else { return nil }
    let normalizedShare = String(share).removingPercentEncoding?.lowercased() ?? String(share).lowercased()
    return "//\(normalizedHost)/\(normalizedShare)"
}

func redactedSMBURL(_ value: String) -> String {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let componentInput = clean.hasPrefix("//") ? "smb:\(clean)" : clean
    guard var components = URLComponents(string: componentInput) else {
        if let atIndex = clean.firstIndex(of: "@"),
           let schemeIndex = clean.range(of: "://")?.upperBound {
            return String(clean[..<schemeIndex]) + String(clean[clean.index(after: atIndex)...])
        }
        return clean
    }
    components.user = nil
    components.password = nil
    if let urlString = components.string {
        return urlString
    }
    return clean
}

func validateMountTargetURL(_ value: String) -> String? {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.hasPrefix("smb://") || clean.hasPrefix("//") else {
        return tr("挂载地址必须以 'smb://' 或 '//' 开头", "Mount URL must start with 'smb://' or '//'")
    }
    if clean.contains("@") {
        return tr("挂载地址不得内嵌用户名或密码，SMB 凭据必须由系统钥匙串保管",
                  "Mount URL must not contain embedded username or password; SMB credentials must be managed by macOS Keychain")
    }
    guard let identity = smbResourceIdentity(clean), !identity.isEmpty else {
        return tr("挂载地址必须包含有效的主机名与共享名称 (例如 smb://server.local/share)",
                  "Mount URL must include a valid host and share name (e.g., smb://server.local/share)")
    }
    return nil
}

func validateMountPath(_ value: String) -> String? {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.hasPrefix("/") else {
        return tr("本地挂载路径必须是绝对路径 (以 / 开头)", "Local mount path must be an absolute path (starting with /)")
    }
    let components = clean.split(separator: "/")
    if components.contains("..") || components.contains(".") {
        return tr("本地挂载路径不得包含相对路径跳转符号 (..) 或 (.)", "Local mount path must not contain relative traversal symbols (..) or (.)")
    }
    let url = URL(fileURLWithPath: clean).standardizedFileURL
    let path = url.path
    if path == "/" || path == "/Volumes" {
        return tr("不能直接使用系统根目录或 /Volumes 作为挂载点", "Cannot use root or /Volumes directly as a mount point")
    }
    return nil
}

func usesSystemManagedMountPoint(_ target: MountTarget) -> Bool {
    let standardized = URL(fileURLWithPath: target.mountPath).standardizedFileURL
    let parent = standardized.deletingLastPathComponent().path
    guard parent == "/Volumes" else { return false }
    guard let identity = smbResourceIdentity(target.url) else { return false }
    let share = identity.split(separator: "/").last.map(String.init) ?? ""
    return standardized.lastPathComponent.lowercased() == share.lowercased()
}

// MARK: - 内核挂载表快照与 NetFS 框架挂载

struct KernelMountEntry {
    let source: String
    let mountPoint: String
    let fileSystemType: String
}

func getKernelMountEntries() -> [KernelMountEntry] {
    let count = getfsstat(nil, 0, MNT_NOWAIT)
    guard count > 0 else { return [] }

    var statfsList = Array(repeating: Darwin.statfs(), count: Int(count))
    let byteSize = Int(count) * MemoryLayout<Darwin.statfs>.size
    let resultCount = statfsList.withUnsafeMutableBufferPointer { buffer -> Int32 in
        guard let baseAddress = buffer.baseAddress else { return 0 }
        return getfsstat(baseAddress, Int32(byteSize), MNT_NOWAIT)
    }

    guard resultCount > 0 else { return [] }
    var entries: [KernelMountEntry] = []
    for i in 0..<Int(resultCount) {
        var item = statfsList[i]
        let mountPoint = withUnsafePointer(to: &item.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) { String(cString: $0) }
        }
        let source = withUnsafePointer(to: &item.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) { String(cString: $0) }
        }
        let fsType = withUnsafePointer(to: &item.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
        }
        entries.append(KernelMountEntry(source: source, mountPoint: mountPoint, fileSystemType: fsType))
    }
    return entries
}

func getKernelMountSource(for mountPath: String) -> String? {
    let target = URL(fileURLWithPath: mountPath).standardizedFileURL.path
    for entry in getKernelMountEntries() {
        if URL(fileURLWithPath: entry.mountPoint).standardizedFileURL.path == target {
            return entry.source
        }
    }
    return nil
}

func discoverActiveSMBMounts() -> [(url: String, path: String, host: String)] {
    var results: [(url: String, path: String, host: String)] = []
    for entry in getKernelMountEntries() {
        if entry.fileSystemType.lowercased() == "smbfs" {
            let host = extractHost(from: entry.source)
            results.append((url: entry.source, path: entry.mountPoint, host: host))
        }
    }
    return results
}

func forceUnmountWithTimeout(path: String, timeoutSeconds: Double = 3.0) -> Bool {
    let diskutilRes = runCommandDiscardingOutputWithTimeout(
        executable: "/usr/sbin/diskutil",
        arguments: ["unmount", "force", path],
        timeout: timeoutSeconds
    )
    if diskutilRes.status == 0 {
        return true
    }
    let umountRes = runCommandDiscardingOutputWithTimeout(
        executable: "/sbin/umount",
        arguments: ["-f", path],
        timeout: timeoutSeconds
    )
    return umountRes.status == 0
}

enum MountPointStatus {
    case alreadyMountedHealthy
    case readyToMount
    case unmountFailed
}

func ensureMountPointReady(target: MountTarget) -> MountPointStatus {
    let stdPath = URL(fileURLWithPath: target.mountPath).standardizedFileURL.path
    if let currentSource = getKernelMountSource(for: stdPath) {
        if smbResourceIdentity(currentSource) == smbResourceIdentity(target.url) {
            return .alreadyMountedHealthy
        } else {
            let unmounted = forceUnmountWithTimeout(path: stdPath)
            if unmounted {
                return .readyToMount
            } else {
                return .unmountFailed
            }
        }
    }
    return .readyToMount
}

func disableSpotlightIndex(at mountPath: String) {
    _ = runCommand(executable: "/usr/bin/mdutil", arguments: ["-i", "off", mountPath])
    let neverIndexPath = URL(fileURLWithPath: mountPath).appendingPathComponent(".metadata_never_index").path
    if !FileManager.default.fileExists(atPath: neverIndexPath) {
        _ = FileManager.default.createFile(atPath: neverIndexPath, contents: Data(), attributes: nil)
    }
}

func netFSMountOptions(hasExplicitMountPoint: Bool) -> NSMutableDictionary? {
    if hasExplicitMountPoint {
        let dict = NSMutableDictionary()
        dict.setObject(true, forKey: kNetFSMountAtMountDirKey as NSString)
        return dict
    }
    return nil
}

func silentMount(urlString: String, mountPath: String) -> Bool {
    guard let url = URL(string: urlString) else { return false }
    let cfURL = url as CFURL
    let stdPath = URL(fileURLWithPath: mountPath).standardizedFileURL.path
    let cfMountPoint = URL(fileURLWithPath: stdPath) as CFURL
    let explicitPoint = !usesSystemManagedMountPoint(MountTarget(url: urlString, mountPath: mountPath))
    let options = netFSMountOptions(hasExplicitMountPoint: explicitPoint)

    if explicitPoint && !FileManager.default.fileExists(atPath: stdPath) {
        try? FileManager.default.createDirectory(atPath: stdPath, withIntermediateDirectories: true, attributes: nil)
    }

    var mountPoints: Unmanaged<CFArray>?
    let status = NetFSMountURLSync(
        cfURL,
        explicitPoint ? cfMountPoint : nil,
        nil,
        nil,
        nil,
        options,
        &mountPoints
    )

    if status == 0 {
        mountPoints?.release()
        return true
    } else {
        writeLog("NetFS error \(status) for \(redactedSMBURL(urlString))")
        return false
    }
}

struct DiscoveredTailscalePeer {
    let name: String
    let magicDNS: String
    let ip: String
    let os: String
}

func discoverTailscalePeers() -> [DiscoveredTailscalePeer] {
    let res = runCommand(executable: "/usr/bin/which", arguments: ["tailscale"])
    guard res.status == 0 else { return [] }
    let tsPath = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    let statusRes = runCommand(executable: tsPath, arguments: ["status", "--json"])
    guard statusRes.status == 0,
          let data = statusRes.stdout.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let peerMap = json["PeerStatus"] as? [String: [String: Any]] else {
        return []
    }

    var peers: [DiscoveredTailscalePeer] = []
    for (_, peer) in peerMap {
        let name = peer["HostName"] as? String ?? "unknown"
        let magicDNS = peer["DNSName"] as? String ?? ""
        let osName = peer["OS"] as? String ?? ""
        let addrs = peer["TailscaleIPs"] as? [String] ?? []
        let ip = addrs.first ?? ""
        if !ip.isEmpty {
            peers.append(DiscoveredTailscalePeer(name: name, magicDNS: magicDNS, ip: ip, os: osName))
        }
    }
    return peers.sorted { $0.name < $1.name }
}

func remoteSMBAcceptanceURL(_ urlString: String, peers: [DiscoveredTailscalePeer]) -> (url: String, usesTailscaleAddress: Bool) {
    let host = extractHost(from: urlString)
    for peer in peers {
        if !peer.magicDNS.isEmpty && peer.magicDNS.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() == host {
            let replaced = urlString.replacingOccurrences(of: host, with: peer.ip)
            return (replaced, true)
        }
    }
    return (urlString, false)
}

// MARK: - 终端 ANSI 交互式菜单组件

enum KeyAction: Equatable {
    case up, down, enter, space, selectAll, escape, interrupt, backspace, character(UInt8), unknown
}

struct SelectionItem {
    let id: String
    let title: String
    let subtitle: String?
    let isEnabled: Bool

    init(id: String? = nil, title: String, subtitle: String? = nil, isEnabled: Bool = true) {
        self.id = id ?? title
        self.title = title
        self.subtitle = subtitle
        self.isEnabled = isEnabled
    }
}

typealias SelectionOption = SelectionItem

struct RollingViewportState {
    let totalCount: Int
    let capacity: Int
    private(set) var startIndex: Int
    private(set) var cursorIndex: Int

    init(totalCount: Int, capacity: Int, defaultIndex: Int = 0) {
        self.totalCount = max(0, totalCount)
        self.capacity = max(1, capacity)
        self.cursorIndex = min(max(0, defaultIndex), max(0, totalCount - 1))
        self.startIndex = defaultIndex >= capacity
            ? max(0, min(defaultIndex - capacity + 1, max(0, totalCount - capacity)))
            : 0
        normalize()
    }

    var endIndex: Int { min(totalCount, startIndex + capacity) }
    var visibleRange: Range<Int> { startIndex..<endIndex }
    var canScrollUp: Bool { startIndex > 0 }
    var canScrollDown: Bool { endIndex < totalCount }
    var cursorOffset: Int { cursorIndex - startIndex }
    var itemsAbove: Int { startIndex }
    var itemsBelow: Int { max(0, totalCount - endIndex) }

    mutating func move(by delta: Int, wraps: Bool = true) {
        guard totalCount > 0 else { return }
        var next = cursorIndex + delta
        if wraps {
            next = (next % totalCount + totalCount) % totalCount
        } else {
            next = min(max(0, next), totalCount - 1)
        }
        cursorIndex = next
        normalize()
    }

    private mutating func normalize() {
        guard totalCount > 0 else { startIndex = 0; cursorIndex = 0; return }
        cursorIndex = min(max(0, cursorIndex), totalCount - 1)
        let maxStart = max(0, totalCount - capacity)
        startIndex = min(max(0, startIndex), maxStart)
        if cursorIndex < startIndex { startIndex = cursorIndex }
        if cursorIndex >= startIndex + capacity { startIndex = cursorIndex - capacity + 1 }
        startIndex = min(startIndex, maxStart)
    }
}

private var terminalSignalRestoreTermios = termios()
private var terminalSignalRestoreEnabled: Int32 = 0
private var terminalSignalCursorHidden: Int32 = 0
private let terminalSignalCursorSequence: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (27, 91, 63, 50, 53, 104)

private func terminalSignalHandler(_ signalNumber: Int32) {
    if terminalSignalRestoreEnabled != 0 {
        _ = tcsetattr(STDIN_FILENO, TCSANOW, &terminalSignalRestoreTermios)
        if terminalSignalCursorHidden != 0 {
            withUnsafePointer(to: terminalSignalCursorSequence) { pointer in
                _ = write(STDOUT_FILENO, pointer, 6)
            }
        }
    }
    let exitCode: Int32 = signalNumber == SIGTERM ? 143 : (signalNumber == SIGHUP ? 129 : 130)
    _exit(exitCode)
}

struct TerminalUI {
    static var mockKeySequence: [KeyAction]? = nil
    static var mockInputBytes: [UInt8]? = nil
    static var mockPendingInputResults: [Bool]? = nil
    static var mockedPollTimeouts: [Int] = []
    static var lastRenderedLineCount = 0
    static var lastRenderedVisibleRange: Range<Int>?
    static var originalTermios: termios?
    static var signalHandlersInstalled = false
    static var termiosTestMode = false
    static var mockOriginalTermios: termios?
    static var mockRawTermios: termios?
    static var mockRestoredTermios: termios?
    static var mockTermiosOriginalAfterRestore: termios?
    static var mockOriginalTermiosBytes: [UInt8]?
    static var termiosLastRestoreMatchedOriginal = false
    static var cursorHidden = false {
        didSet { terminalSignalCursorHidden = cursorHidden ? 1 : 0 }
    }
    static var mockInputActive: Bool { mockKeySequence != nil }

    static func restoreTerminal() {
        if termiosTestMode {
            termiosLastRestoreMatchedOriginal = false
            mockRestoredTermios = mockOriginalTermios
            mockTermiosOriginalAfterRestore = mockOriginalTermios
            let restoredBytes = mockRestoredTermios.map { withUnsafeBytes(of: $0) { Array($0) } }
            termiosLastRestoreMatchedOriginal = restoredBytes == mockOriginalTermiosBytes
            mockOriginalTermios = nil
            mockOriginalTermiosBytes = nil
            cursorHidden = false
            return
        }
        if cursorHidden {
            let showCursor: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (27, 91, 63, 50, 53, 104)
            withUnsafePointer(to: showCursor) { pointer in
                _ = write(STDOUT_FILENO, pointer, 6)
            }
            cursorHidden = false
        }
        if var original = originalTermios {
            _ = tcsetattr(STDIN_FILENO, TCSANOW, &original)
            originalTermios = nil
            terminalSignalRestoreEnabled = 0
        }
        fflush(stdout)
    }

    static func setRawMode(_ enable: Bool) {
        if !termiosTestMode, isTTYOverride == true {
            originalTermiosSnapshot = nil
            restoredTermiosSnapshot = nil
        }
        if termiosTestMode {
            if enable {
                var original = termios()
                _ = withUnsafeMutableBytes(of: &original) { bytes in bytes.initializeMemory(as: UInt8.self, repeating: 0) }
                mockOriginalTermios = original
                mockOriginalTermiosBytes = withUnsafeBytes(of: original) { Array($0) }
                var raw = original
                raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG)
                withUnsafeMutableBytes(of: &raw.c_cc) { controlChars in
                    controlChars[Int(VMIN)] = 1
                    controlChars[Int(VTIME)] = 0
                }
                mockRawTermios = raw
            } else {
                restoreTerminal()
            }
            return
        }
        if enable {
            guard originalTermios == nil else { return }
            var original = termios()
            guard tcgetattr(STDIN_FILENO, &original) == 0 else { return }
            originalTermios = original
            if isTTYOverride == true { originalTermiosSnapshot = original }
            terminalSignalRestoreTermios = original
            terminalSignalRestoreEnabled = 1
            var raw = original
            raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG)
            withUnsafeMutableBytes(of: &raw.c_cc) { controlChars in
                controlChars[Int(VMIN)] = 1 // Return after at least one byte.
                controlChars[Int(VTIME)] = 0 // Do not add a read timeout.
            }
            if isTTYOverride == true { restoredTermiosSnapshot = raw }
            guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else {
                originalTermios = nil
                terminalSignalRestoreEnabled = 0
                return
            }
            if !signalHandlersInstalled {
                _ = signal(SIGINT, terminalSignalHandler)
                _ = signal(SIGTERM, terminalSignalHandler)
                _ = signal(SIGHUP, terminalSignalHandler)
                signalHandlersInstalled = true
            }
        } else {
            restoreTerminal()
        }
    }

    static func readByte() -> UInt8? {
        if var bytes = mockInputBytes {
            guard !bytes.isEmpty else { return nil }
            let byte = bytes.removeFirst()
            mockInputBytes = bytes
            return byte
        }
        var b: UInt8 = 0
        let n = read(STDIN_FILENO, &b, 1)
        return n > 0 ? b : nil
    }

    static func hasPendingInput(timeoutMs: Int = 0) -> Bool {
        if var results = mockPendingInputResults {
            mockedPollTimeouts.append(timeoutMs)
            guard !results.isEmpty else { return false }
            let result = results.removeFirst()
            mockPendingInputResults = results
            return result
        }
        var pfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let res = poll(&pfd, 1, Int32(timeoutMs))
        return res > 0 && (pfd.revents & Int16(POLLIN)) != 0
    }

    static func decodeArrowSequence(prefix: UInt8, suffix: UInt8) -> KeyAction? {
        guard prefix == 91 || prefix == 79 else { return nil }
        switch suffix {
        case 65: return .up
        case 66: return .down
        default: return nil
        }
    }

    static func readKey() -> KeyAction? {
        if var queue = mockKeySequence {
            guard !queue.isEmpty else { return nil }
            let next = queue.removeFirst()
            mockKeySequence = queue
            return next
        }
        guard let byte = readByte() else { return nil }
        switch byte {
        case 3: return .interrupt
        case 10, 13: return .enter
        case 32: return .space
        case 8, 127: return .backspace
        case 27:
            guard hasPendingInput(timeoutMs: 50) else { return .escape }
            guard let prefix = readByte(), prefix == 91 || prefix == 79 else { return .unknown }
            guard hasPendingInput(timeoutMs: 10), let suffix = readByte() else { return .escape }
            return decodeArrowSequence(prefix: prefix, suffix: suffix) ?? .unknown
        case 97, 65: return .selectAll
        case 106, 74: return .down
        case 107, 75: return .up
        default: return byte >= 32 ? .character(byte) : .unknown
        }
    }
}

// MARK: - POSIX termios 轻量安全行输入 (Esc 放弃与退格擦除)

var mockLineInput: String? = nil
var mockLineInputs: [String]? = nil
var lastLineInputWasEscaped = false
var lastLineInputReachedEOF = false
var originalTermiosSnapshot: termios?
var restoredTermiosSnapshot: termios?
var lastSelectionWasEscaped = false
var lastSelectionReachedEOF = false

func promptLineWithEsc(prompt: String, defaultValue: String? = nil) -> String? {
    lastLineInputWasEscaped = false
    lastLineInputReachedEOF = false
    if mockLineInputs != nil && !mockLineInputs!.isEmpty {
        let next = mockLineInputs!.removeFirst()
        if next == "\u{1B}" { // 模拟 Esc 放弃
            print("\r\u{1B}[K" + tr("(已取消)", "(Cancelled)"))
            lastLineInputWasEscaped = true
            return nil
        }
        let trimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, let def = defaultValue {
            return def
        }
        return trimmed
    }
    if let mock = mockLineInput {
        if mock == "\u{1B}" { // 模拟 Esc 放弃
            print("\r\u{1B}[K" + tr("(已取消)", "(Cancelled)"))
            lastLineInputWasEscaped = true
            return nil
        }
        let trimmed = mock.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, let def = defaultValue {
            return def
        }
        return trimmed
    }

    if !isInteractiveTerminal() {
        print(prompt, terminator: "")
        fflush(stdout)
        guard let line = readLine() else {
            lastLineInputReachedEOF = true
            return nil
        }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, let def = defaultValue {
            return def
        }
        return trimmed
    }

    print(prompt, terminator: "")
    fflush(stdout)
    TerminalUI.setRawMode(true)
    defer {
        TerminalUI.setRawMode(false)
    }

    var buffer: [UInt8] = []

    while true {
        guard let b = TerminalUI.readByte() else {
            // STDIN 流终止 (EOF) 或错误，安全退出并返回 nil
            lastLineInputReachedEOF = true
            return nil
        }
        if b == 27 { // ASCII 27: Esc 键
            if TerminalUI.hasPendingInput(timeoutMs: 50) {
                // 逃逸序列 (如方向键)，读取并丢弃后续控制字节
                _ = TerminalUI.readByte()
                if TerminalUI.hasPendingInput(timeoutMs: 10) {
                    _ = TerminalUI.readByte()
                }
                continue
            }
            // 独立 Esc 键：立即清除当前行并安全返回 nil
            print("\r\u{1B}[K" + tr("(已取消)", "(Cancelled)"))
            lastLineInputWasEscaped = true
            return nil
        } else if b == 10 || b == 13 { // 回车键
            print("")
            let str = String(bytes: buffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if str.isEmpty, let def = defaultValue {
                return def
            }
            return str
        } else if b == 127 || b == 8 { // 退格键 (ASCII 127 / ASCII 8)
            if !buffer.isEmpty {
                if var currentStr = String(bytes: buffer, encoding: .utf8) {
                    currentStr.removeLast()
                    buffer = Array(currentStr.utf8)
                    print("\r\u{1B}[K\(prompt)\(currentStr)", terminator: "")
                    fflush(stdout)
                } else {
                    buffer.removeLast()
                    print("\r\u{1B}[K\(prompt)", terminator: "")
                    fflush(stdout)
                }
            }
        } else if b == 3 { // Ctrl+C 中断
            TerminalUI.setRawMode(false)
            exit(130)
        } else if b >= 32 { // 可打印字符与多字节 UTF-8 序列
            buffer.append(b)
            if let str = String(bytes: buffer, encoding: .utf8) {
                print("\r\u{1B}[K\(prompt)\(str)", terminator: "")
                fflush(stdout)
            }
        }
    }
}

// MARK: - 运行期卷宗发现与候选主机倒推

struct DiscoveredMount: Equatable {
    var mountPoint: String       // 实际本地挂载路径（可能带 -1 临时冲突后缀）
    var rawSmbUrl: String        // 内核挂载表返回的原始 URL
    var host: String             // 提取解析出的主机 IP 或域名
    var shareName: String        // 从 URL 提取的标准真实共享名
    var cleanMountPoint: String  // 推导出的标准规整路径 /Volumes/<shareName>
    var standardSMBURL: String   // 标准 smb://<host>/<shareName>
    var smbURL: String { standardSMBURL }
}

struct DiscoveredHostGroup: Equatable {
    var host: String
    var mounts: [DiscoveredMount]
    var isConfigured: Bool = false
}

var mockCandidateHosts: [DiscoveredHostGroup]? = nil

func discoverCandidateHosts() -> [DiscoveredHostGroup] {
    if let mock = mockCandidateHosts {
        return mock
    }
    let entries = getKernelMountEntries().filter { $0.fileSystemType.lowercased() == "smbfs" }
    var hostMap: [String: [DiscoveredMount]] = [:]
    var hostOrder: [String] = []

    for entry in entries {
        let rawURL = entry.source
        let host = extractHost(from: rawURL)
        guard !host.isEmpty else { continue }
        guard let shareName = extractShareName(from: rawURL) else { continue }
        let cleanMount = "/Volumes/\(shareName)"
        let stdURL = "smb://\(host)/\(shareName)"

        let item = DiscoveredMount(
            mountPoint: entry.mountPoint,
            rawSmbUrl: rawURL,
            host: host,
            shareName: shareName,
            cleanMountPoint: cleanMount,
            standardSMBURL: stdURL
        )

        if hostMap[host] == nil {
            hostMap[host] = []
            hostOrder.append(host)
        }
        if !hostMap[host]!.contains(where: { $0.shareName.lowercased() == shareName.lowercased() }) {
            hostMap[host]!.append(item)
        }
    }

    return hostOrder.map { h in
        DiscoveredHostGroup(host: h, mounts: hostMap[h] ?? [], isConfigured: false)
    }
}

func terminalSelectionCapacity() -> Int {
    guard isInteractiveTerminal() else { return 12 }
    var size = winsize()
    guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_row > 0 else { return 12 }
    return max(1, min(12, Int(size.ws_row) - 6))
}

func selectionCapacity(usingInjectedKeys injected: Bool) -> Int {
    injected ? 12 : terminalSelectionCapacity()
}

func renderSelectionFrame(title: String, options: [SelectionItem], viewport: RollingViewportState,
                          selected: Set<Int>, explicit: Bool, checkedIndex: Int = 0, multiple: Bool = false) {
    let capacity = viewport.capacity
    var rows: [String] = []
    rows.append(title)
    rows.append(viewport.canScrollUp
        ? tr("▲ 向上还有 \(viewport.itemsAbove) 项", "▲ \(viewport.itemsAbove) items above") : "")
    for visibleIndex in 0..<capacity {
        if viewport.startIndex + visibleIndex < viewport.totalCount {
            let index = viewport.startIndex + visibleIndex
            let item = options[index]
            let pointer = index == viewport.cursorIndex ? "❯ " : "  "
            let state: String
            if explicit { state = index == checkedIndex ? "(o) " : "( ) " }
            else if multiple { state = selected.contains(index) ? "[x] " : "[ ] " }
            else { state = "" }
            let enabled = item.isEnabled ? "" : tr(" [✓] 已配置", " [✓] already configured")
            rows.append(pointer + state + item.title + (item.subtitle.map { " (\($0))" } ?? "") + enabled)
        } else {
            rows.append("")
        }
    }
    rows.append(viewport.canScrollDown
        ? tr("▼ 向下还有 \(viewport.itemsBelow) 项", "▼ \(viewport.itemsBelow) items below") : "")
    rows.append(explicit
        ? tr("(上下键移动光标，空格键切换单选状态，回车确认，Esc 取消)", "(Arrow keys move the cursor, Space switches selection, Enter confirms, Esc cancels)")
        : multiple
            ? tr("(上下键移动，空格翻转单项，a 全选/清空，回车提交，Esc 取消)", "(Arrow keys move, Space toggles an item, a selects all/none, Enter submits, Esc cancels)")
            : tr("(上下键移动，回车确定，Esc 取消)", "(Arrow keys move, Enter confirms, Esc cancels)"))

    let physicalLines = rows.flatMap { $0.components(separatedBy: "\n") }
    let eraseCount = TerminalUI.lastRenderedLineCount
    if eraseCount > 0 {
        print("\u{001B}[\(eraseCount)A", terminator: "")
    }
    for line in physicalLines { print("\u{001B}[2K\(line)") }
    // Any lines previously occupied beyond the new frame (e.g. notice lines
    // printed under the frame) must be erased too, then the cursor returns.
    let staleTail = eraseCount - physicalLines.count
    if staleTail > 0 {
        for _ in 0..<staleTail { print("\u{001B}[2K") }
        print("\u{001B}[\(staleTail)A", terminator: "")
    }
    fflush(stdout)
    TerminalUI.lastRenderedLineCount = physicalLines.count
    TerminalUI.lastRenderedVisibleRange = viewport.visibleRange
}

func clearSelectionFrame() {
    guard TerminalUI.lastRenderedLineCount > 0 else { return }
    print("\u{001B}[\(TerminalUI.lastRenderedLineCount)A", terminator: "")
    for _ in 0..<TerminalUI.lastRenderedLineCount {
        print("\u{001B}[2K")
    }
    TerminalUI.lastRenderedLineCount = 0
    TerminalUI.lastRenderedVisibleRange = nil
    fflush(stdout)
}

func printSelectionNotice(_ text: String) {
    // Fixed-line-budget compensation: notice lines are printed below the live
    // frame, so the next repaint must retreat over them as well.
    print(text)
    fflush(stdout)
    TerminalUI.lastRenderedLineCount += text.components(separatedBy: "\n").count
}

func runSelectionFallback(title: String, options: [SelectionItem], multiple: Bool) -> [Int]? {
    lastSelectionReachedEOF = false
    print(title)
    for (index, option) in options.enumerated() {
        let disabled = option.isEnabled ? "" : tr(" [已配置，不能选择]", " [already configured, unavailable]")
        print("  [\(index + 1)] \(option.title)" + (option.subtitle.map { " (\($0))" } ?? "") + disabled)
    }
    while true {
        print(tr("请输入编号\(multiple ? "（多个编号用逗号分隔）" : "")；直接回车取消：", "Enter \(multiple ? "comma-separated indices" : "an index"); press Enter to cancel: "), terminator: "")
        fflush(stdout)
        let line: String?
        if let mocks = mockLineInputs, !mocks.isEmpty {
            line = mockLineInputs!.removeFirst()
        } else if let mock = mockLineInput {
            line = mock
        } else {
            line = readLine()
        }
        guard let line else {
            lastSelectionReachedEOF = true
            return nil
        }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed != "\u{1B}" else {
            print(tr("(已取消)", "(Cancelled)"))
            return nil
        }
        if let selection = parseSelectionFallback(trimmed, options: options, multiple: multiple), !selection.isEmpty {
            guard multiple else { return selection }
            return selection.reduce(into: [Int]()) { unique, index in
                if !unique.contains(index) { unique.append(index) }
            }
        }
        print(tr("输入无效，请输入列表中可选项目的编号。", "Invalid input; enter the number of an available item."))
        if mockLineInputs != nil && mockLineInputs!.isEmpty { return nil }
        if mockLineInput != nil { return nil }
    }
}

func parseSelectionFallback(_ line: String, options: [SelectionItem], multiple: Bool) -> [Int]? {
    guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    let values = line.split(separator: ",").compactMap { part -> Int? in
        guard let value = Int(part.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return value - 1
    }
    let valid = values.filter { options.indices.contains($0) && options[$0].isEnabled }
    return multiple ? valid : valid.first.map { [$0] }
}

func promptInteractiveCheckbox(title: String, options: [SelectionItem], initiallySelected: Set<Int> = []) -> [Int]? {
    lastSelectionWasEscaped = false
    lastSelectionReachedEOF = false
    guard !options.isEmpty else { return [] }
    let injected = TerminalUI.mockInputActive
    guard isInteractiveTerminal() || injected else { return runSelectionFallback(title: title, options: options, multiple: true) }
    var selected = Set(initiallySelected.filter { options.indices.contains($0) && options[$0].isEnabled })
    let initialCursor = options.firstIndex(where: \.isEnabled) ?? 0
    var viewport = RollingViewportState(totalCount: options.count, capacity: selectionCapacity(usingInjectedKeys: injected), defaultIndex: initialCursor)
    TerminalUI.lastRenderedLineCount = 0
    TerminalUI.lastRenderedVisibleRange = nil
    if !injected {
        TerminalUI.setRawMode(true)
        print("\u{001B}[?25l", terminator: "")
        TerminalUI.cursorHidden = true
    }
    defer {
        if !injected {
            print("\u{001B}[?25h", terminator: "")
            TerminalUI.setRawMode(false)
        }
        fflush(stdout)
    }
    renderSelectionFrame(title: title, options: options, viewport: viewport, selected: selected, explicit: false, multiple: true)
    while let key = TerminalUI.readKey() {
        switch key {
        case .up: viewport.move(by: -1); renderSelectionFrame(title: title, options: options, viewport: viewport, selected: selected, explicit: false, multiple: true)
        case .down: viewport.move(by: 1); renderSelectionFrame(title: title, options: options, viewport: viewport, selected: selected, explicit: false, multiple: true)
        case .space:
            if options[viewport.cursorIndex].isEnabled {
                if selected.contains(viewport.cursorIndex) { selected.remove(viewport.cursorIndex) } else { selected.insert(viewport.cursorIndex) }
            }
            renderSelectionFrame(title: title, options: options, viewport: viewport, selected: selected, explicit: false, multiple: true)
        case .selectAll:
            let enabled = Set(options.indices.filter { options[$0].isEnabled })
            selected = selected == enabled ? [] : enabled
            renderSelectionFrame(title: title, options: options, viewport: viewport, selected: selected, explicit: false, multiple: true)
        case .enter: return selected.sorted()
        case .escape:
            lastSelectionWasEscaped = true
            clearSelectionFrame()
            print(tr("(已取消)", "(Cancelled)"))
            return nil
        case .interrupt: TerminalUI.setRawMode(false); exit(130)
        default: continue
        }
    }
    lastSelectionReachedEOF = true
    return nil
}

func promptInteractiveRadio(title: String, options: [SelectionItem], defaultIndex: Int = 0, disabledHint: String? = nil) -> Int? {
    lastSelectionWasEscaped = false
    lastSelectionReachedEOF = false
    guard !options.isEmpty else { return nil }
    let injected = TerminalUI.mockInputActive
    guard isInteractiveTerminal() || injected else {
        return runSelectionFallback(title: title, options: options, multiple: false)?.first
    }
    let initial = options.indices.contains(defaultIndex) && options[defaultIndex].isEnabled
        ? defaultIndex : (options.firstIndex(where: \.isEnabled) ?? 0)
    var viewport = RollingViewportState(totalCount: options.count, capacity: selectionCapacity(usingInjectedKeys: injected), defaultIndex: initial)
    TerminalUI.lastRenderedLineCount = 0
    TerminalUI.lastRenderedVisibleRange = nil
    if !injected {
        TerminalUI.setRawMode(true)
        print("\u{001B}[?25l", terminator: "")
        TerminalUI.cursorHidden = true
    }
    defer {
        if !injected {
            print("\u{001B}[?25h", terminator: "")
            TerminalUI.setRawMode(false)
        }
        fflush(stdout)
    }
    renderSelectionFrame(title: title, options: options, viewport: viewport, selected: [], explicit: false)
    while let key = TerminalUI.readKey() {
        switch key {
        case .up: viewport.move(by: -1); renderSelectionFrame(title: title, options: options, viewport: viewport, selected: [], explicit: false)
        case .down: viewport.move(by: 1); renderSelectionFrame(title: title, options: options, viewport: viewport, selected: [], explicit: false)
        case .enter:
            guard options[viewport.cursorIndex].isEnabled else {
                printSelectionNotice("\n" + (disabledHint ?? tr("该项目已配置，不能重复选择。", "This item is already configured and cannot be selected again.")))
                continue
            }
            return viewport.cursorIndex
        case .escape:
            lastSelectionWasEscaped = true
            clearSelectionFrame()
            print(tr("(已取消)", "(Cancelled)"))
            return nil
        case .interrupt: TerminalUI.setRawMode(false); exit(130)
        default: continue
        }
    }
    lastSelectionReachedEOF = true
    return nil
}

func promptExplicitConfirmation(title: String, options: [SelectionItem]) -> Int? {
    lastSelectionWasEscaped = false
    lastSelectionReachedEOF = false
    guard options.count >= 2 else { return nil }
    let injected = TerminalUI.mockInputActive
    guard isInteractiveTerminal() || injected else {
        print(title)
        print(tr("非交互模式下已安全取消。", "Canceled safely in non-interactive mode."))
        return nil
    }
    var viewport = RollingViewportState(totalCount: options.count, capacity: selectionCapacity(usingInjectedKeys: injected))
    var checkedIndex = 0
    TerminalUI.lastRenderedLineCount = 0
    TerminalUI.lastRenderedVisibleRange = nil
    if !injected {
        TerminalUI.setRawMode(true)
        print("\u{001B}[?25l", terminator: "")
        TerminalUI.cursorHidden = true
    }
    defer {
        if !injected {
            print("\u{001B}[?25h", terminator: "")
            TerminalUI.setRawMode(false)
        }
        fflush(stdout)
    }
    renderSelectionFrame(title: title, options: options, viewport: viewport, selected: [], explicit: true, checkedIndex: checkedIndex)
    while let key = TerminalUI.readKey() {
        switch key {
        case .up: viewport.move(by: -1); renderSelectionFrame(title: title, options: options, viewport: viewport, selected: [], explicit: true, checkedIndex: checkedIndex)
        case .down: viewport.move(by: 1); renderSelectionFrame(title: title, options: options, viewport: viewport, selected: [], explicit: true, checkedIndex: checkedIndex)
        case .space:
            checkedIndex = viewport.cursorIndex == checkedIndex ? 0 : viewport.cursorIndex
            renderSelectionFrame(title: title, options: options, viewport: viewport, selected: [], explicit: true, checkedIndex: checkedIndex)
        case .enter:
            if checkedIndex == 0 { return nil }
            return checkedIndex
        case .escape:
            lastSelectionWasEscaped = true
            clearSelectionFrame()
            print(tr("(已取消)", "(Cancelled)"))
            return nil
        case .interrupt: TerminalUI.setRawMode(false); exit(130)
        default: continue
        }
    }
    lastSelectionReachedEOF = true
    return nil
}

// MARK: - 初始化向导 (--init) 与日常配置管理 (--config)

func handleCandidateHostConfiguration(candidate: DiscoveredHostGroup) -> HostConfig? {
    print(tr("\n--- 配置主机: \(candidate.host) ---", "\n--- Configure Host: \(candidate.host) ---"))
    let aliasPrompt = tr("请输入该主机的人类友好别名 (直接回车保持默认 [\(candidate.host)], 按 Esc 取消): ",
                         "Enter alias for host (Enter for default [\(candidate.host)], Esc to cancel): ")
    guard let aliasInput = promptLineWithEsc(prompt: aliasPrompt) else {
        print(tr("(已取消主机配置)", "(Host configuration canceled)"))
        return nil
    }
    let trimmedAlias = aliasInput.trimmingCharacters(in: .whitespacesAndNewlines)
    let alias: String? = trimmedAlias.isEmpty ? nil : trimmedAlias

    let shareOptions = candidate.mounts.map { mount in
        let stdMountPoint = deriveStandardMountPoint(from: mount.smbURL) ?? "/Volumes/\(mount.shareName)"
        return SelectionItem(id: mount.smbURL, title: mount.shareName,
                             subtitle: "\(redactedSMBURL(mount.smbURL)) → \(stdMountPoint)")
    }
    guard let selectedList = promptInteractiveCheckbox(
        title: tr("\n请选择需要自动挂载的共享文件夹：", "\nSelect shared folders to mount automatically:"),
        options: shareOptions,
        initiallySelected: Set(shareOptions.indices)
    ) else {
        print(tr("(已取消主机配置)", "(Host configuration canceled)"))
        return nil
    }
    let selectedIndices = Set(selectedList)
    guard !selectedIndices.isEmpty else {
        print(tr("未选择任何共享文件夹，已取消该主机配置。", "No shares selected, canceled host configuration."))
        return nil
    }

    for idx in 0..<candidate.mounts.count {
        let mount = candidate.mounts[idx]
        let stdMountPoint = deriveStandardMountPoint(from: mount.smbURL) ?? "/Volumes/\(mount.shareName)"
        let checkMark = selectedIndices.contains(idx) ? "[✓]" : "[ ]"
        print("  \(checkMark) \(idx + 1). \(mount.shareName) (\(redactedSMBURL(mount.smbURL)) -> \(stdMountPoint))")
    }

    var shares: [SMBShareConfig] = []
    for idx in selectedIndices.sorted() {
        let mount = candidate.mounts[idx]
        let stdMountPoint = deriveStandardMountPoint(from: mount.smbURL) ?? "/Volumes/\(mount.shareName)"
        shares.append(SMBShareConfig(
            name: mount.shareName,
            smbURL: mount.smbURL,
            mountPoint: stdMountPoint,
            enabled: true
        ))
    }

    return HostConfig(
        host: candidate.host,
        alias: alias,
        port: 445,
        timeoutMs: 1000,
        preventSpotlightIndex: true,
        enabled: true,
        shares: shares
    )
}

var lastManualHostAliasWasEscaped = false

func handleManualHostEntry(existingHosts: [HostConfig]) -> HostConfig? {
    lastManualHostAliasWasEscaped = false
    print(tr("\n--- 手动添加主机 ---", "\n--- Manually Add Host ---"))
    let hostPrompt = tr("请输入主机 IP 地址或域名 (按 Esc 取消): ", "Enter host IP or domain (Esc to cancel): ")
    guard let hostInput = promptLineWithEsc(prompt: hostPrompt) else { return nil }
    let host = hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
    if host.isEmpty { return nil }

    let aliasPrompt = tr("请输入该主机的人类友好别名 (直接回车保持默认 [\(host)], 按 Esc 取消当前主机并返回新增方式选择): ",
                         "Enter alias for host (Enter for default [\(host)], Esc to cancel this host and return to add method selection): ")
    guard let aliasInput = promptLineWithEsc(prompt: aliasPrompt) else {
        lastManualHostAliasWasEscaped = lastLineInputWasEscaped
        lastLineInputReachedEOF = lastLineInputReachedEOF || (!lastLineInputWasEscaped && !isInteractiveTerminal())
        print(tr("已取消手动主机录入。", "Manual host entry canceled."))
        return nil
    }
    let trimmedAlias = aliasInput.trimmingCharacters(in: .whitespacesAndNewlines)
    let alias: String? = trimmedAlias.isEmpty ? nil : trimmedAlias

    print(tr("正在测试主机 \(host) 的 SMB 服务端口 (445)...", "Testing SMB service port (445) on \(host)..."))
    let reachable = HostReachabilityProbe.canConnect(host: host, port: 445, timeoutMs: 1500)
    if reachable {
        print(tr("连接测试成功。\n", "Connection test succeeded.\n"))
    } else {
        print(tr("""
        ⚠️ 警告: 无法连通目标主机 \(host) 的 445 端口 (连接超时或网络不可达)。
        该主机可能当前处于离线状态，或当前网络无法直连。
        """, """
        ⚠️ Warning: Cannot connect to TCP port 445 on \(host) (timeout or unreachable).
        The host may be offline or unreachable on this network.
        """))
        let offlineOptions = [
            SelectionItem(id: "cancel", title: tr("取消添加", "Cancel adding")),
            SelectionItem(id: "add", title: tr("仍然添加离线主机", "Add the offline host anyway"))
        ]
        guard let offlineIndex = promptInteractiveRadio(
            title: tr("是否仍然添加该主机？", "Add this offline host anyway?"), options: offlineOptions
        ), offlineOptions[offlineIndex].id == "add" else {
            print(tr("已取消添加未连通主机。", "Canceled adding unreachable host."))
            return nil
        }
        print(tr("已确认添加离线主机 \(host)。\n", "Confirmed adding offline host \(host).\n"))
    }

    print(tr("系统未在该主机下检测到已挂载卷宗，请手动录入共享路径：",
             "No active mounts detected for this host. Please enter share path manually:"))
    let sharePrompt = tr("请输入从属 SMB 共享路径 (格式如 smb://\(host)/Backup, 按 Esc 取消): ",
                         "Enter SMB share path (e.g. smb://\(host)/Backup, Esc to cancel): ")
    guard let shareInput = promptLineWithEsc(prompt: sharePrompt) else { return nil }
    let rawURL = shareInput.trimmingCharacters(in: .whitespacesAndNewlines)
    if rawURL.isEmpty { return nil }
    if let err = validateMountTargetURL(rawURL) {
        print("✗ \(err)")
        return nil
    }

    let stdMountPoint = deriveStandardMountPoint(from: rawURL) ?? "/Volumes/share"
    print(tr("标准目标挂载点将设置为: \(stdMountPoint)", "Standard mount point will be set to: \(stdMountPoint)"))
    let confirmOptions = [
        SelectionItem(id: "confirm", title: tr("确认添加该共享", "Add this share")),
        SelectionItem(id: "cancel", title: tr("取消并返回", "Cancel and return"))
    ]
    guard let confirmIndex = promptInteractiveRadio(
        title: tr("确认添加该共享？", "Add this share?"), options: confirmOptions
    ), confirmOptions[confirmIndex].id == "confirm" else {
        print(tr("已取消添加共享。", "Canceled adding share."))
        return nil
    }

    let shareName = extractShareName(from: rawURL) ?? "share"
    let shares = [
        SMBShareConfig(name: shareName, smbURL: rawURL, mountPoint: stdMountPoint, enabled: true)
    ]

    print(tr("\n提示：对于手动添加的新网络共享，请确保已在 macOS 系统中成功连接过一次并勾选“在我的钥匙串中记住此密码”，认证凭据将由系统钥匙串自动安全管理。",
             "\nNote: For manually added network shares, ensure you have connected at least once in macOS and checked 'Remember password in Keychain'. Credentials are managed securely by Keychain."))

    let aliasDisplay = alias ?? host
    print(tr("已成功添加主机 [\(aliasDisplay)] 及其从属共享。\n",
             "Successfully added host [\(aliasDisplay)] and its shares.\n"))

    return HostConfig(
        host: host,
        alias: alias,
        port: 445,
        timeoutMs: 1000,
        preventSpotlightIndex: true,
        enabled: true,
        shares: shares
    )
}

func runInitWizard(offerServiceInstallation: Bool = true) -> Bool {
    print(tr("""
    automnt - 初始化配置向导 (v\(automntVersion))
    ======================================
    """, """
    automnt - Setup Wizard (v\(automntVersion))
    ====================================
    """))

    print(tr("正在检测系统当前挂载的网络存储...", "Detecting currently mounted network storage..."))
    var candidateHosts = discoverCandidateHosts()
    var configuredHosts: [HostConfig] = []
    var selectedChannel = "off"
    var shouldInstallService = false
    var returnToHostSelection = true

    wizardFlow: while true {
        if returnToHostSelection {
            hostSelection: while true {
                let options = candidateHosts.enumerated().map { index, candidate in
                    let matching = configuredHosts.first(where: { $0.host == candidate.host })
                    let aliasText = matching?.alias.map { " [\($0)]" } ?? ""
                    let count = matching?.shares.count ?? candidate.mounts.count
                    let subtitle = candidate.isConfigured
                        ? tr("\(count) 个共享已配置", "\(count) shares configured")
                        : tr("检测到 \(count) 个已挂载共享", "\(count) mounted shares detected")
                    return SelectionItem(id: "host:\(index)", title: candidate.host + aliasText,
                                         subtitle: subtitle, isEnabled: !candidate.isConfigured)
                } + [
                    SelectionItem(id: "manual", title: tr("手动添加新主机地址", "Manually add a host address")),
                    SelectionItem(id: "skip", title: tr("跳过主机配置", "Skip host configuration"),
                                  subtitle: tr("稍后通过 automnt --config 配置", "Configure later via automnt --config")),
                    SelectionItem(id: "done", title: tr("完成主机配置并继续", "Finish host configuration and continue"))
                ]
                guard let selected = promptInteractiveRadio(
                    title: tr("\n请选择操作：", "\nChoose an action:"), options: options,
                    disabledHint: tr("该主机已完成配置", "This host is already configured")
                ) else {
                    if lastSelectionWasEscaped {
                        print(tr("已取消向导。", "Setup wizard canceled."))
                    } else {
                        print(tr("输入已结束，向导未完成。", "Input ended; setup was not completed."))
                    }
                    return false
                }
                let selectionID = options[selected].id
                if selectionID == "skip" {
                    print(tr("已跳过主机配置。", "Skipped host configuration."))
                    break hostSelection
                } else if selectionID == "done" {
                    break hostSelection
                } else if selectionID == "manual" {
                    if let newHost = handleManualHostEntry(existingHosts: configuredHosts) {
                        configuredHosts.append(newHost)
                        if let cIdx = candidateHosts.firstIndex(where: { $0.host == newHost.host }) {
                            candidateHosts[cIdx].isConfigured = true
                        }
                    } else if lastLineInputWasEscaped {
                        continue hostSelection
                    } else if lastLineInputReachedEOF {
                        return false
                    }
                } else if selectionID.hasPrefix("host:"),
                          let candidateIdx = Int(selectionID.dropFirst("host:".count)),
                          candidateHosts.indices.contains(candidateIdx) {
                    let candidate = candidateHosts[candidateIdx]
                    if let hostConfig = handleCandidateHostConfiguration(candidate: candidate) {
                        configuredHosts.append(hostConfig)
                        candidateHosts[candidateIdx].isConfigured = true
                        let aliasDisplay = hostConfig.alias ?? hostConfig.host
                        print(tr("已暂存主机 [\(aliasDisplay)] 的配置。", "Staged configuration for host [\(aliasDisplay)]."))
                    } else if lastLineInputWasEscaped || lastSelectionWasEscaped {
                        continue hostSelection
                    } else if lastLineInputReachedEOF || lastSelectionReachedEOF {
                        return false
                    }
                }
            }
            returnToHostSelection = false
        }

        print(tr("\n[2/3] 软件更新策略设置", "\n[2/3] Software Update Channel"))
        let channelOptions = [
            SelectionItem(id: "off", title: "off", subtitle: tr("关闭自动检查（可手动运行 automnt --update）", "Disable checks; update manually with automnt --update")),
            SelectionItem(id: "notify", title: "notify", subtitle: tr("发现新版本时发送系统通知", "Send a system notification when an update is available")),
            SelectionItem(id: "auto", title: "auto", subtitle: tr("自动下载并安装预编译更新", "Download and install prebuilt updates automatically"))
        ]
        policyFlow: while true {
            guard let channelIndex = promptInteractiveRadio(
                title: tr("选择更新策略：", "Choose update policy:"), options: channelOptions
            ) else {
                if lastSelectionWasEscaped {
                    print(tr("已返回主机选择选单；配置尚未保存。", "Returned to host selection; configuration was not saved."))
                    returnToHostSelection = true
                    break policyFlow
                }
                print(tr("输入已结束，向导未完成；配置尚未保存。", "Input ended; setup was not completed and no configuration was saved."))
                return false
            }
            selectedChannel = channelOptions[channelIndex].id
            guard offerServiceInstallation else { break policyFlow }

            let deployOptions = [
                SelectionItem(id: "deploy", title: tr("立即部署 LaunchAgent", "Install LaunchAgent now"),
                              subtitle: tr("网络变化时自动探测并挂载共享", "Automatically evaluate mounts when network state changes")),
                SelectionItem(id: "skip", title: tr("仅保存配置", "Save configuration only"),
                              subtitle: tr("不注册后台服务", "Do not register a background service"))
            ]
            guard let deployIndex = promptInteractiveRadio(
                title: tr("是否立即部署后台服务？", "Install the background service now?"), options: deployOptions
            ) else {
                if lastSelectionWasEscaped {
                    print(tr("已返回更新策略选单。", "Returned to update policy selection."))
                    continue policyFlow
                }
                print(tr("输入已结束，向导未完成；配置尚未保存。", "Input ended; setup was not completed and no configuration was saved."))
                return false
            }
            shouldInstallService = deployOptions[deployIndex].id == "deploy"
            break policyFlow
        }
        if returnToHostSelection { continue wizardFlow }
        break wizardFlow
    }

    let config = AutomntConfig(
        version: automntVersion,
        updateChannel: selectedChannel,
        retryPolicy: RetryPolicy(),
        lastUpdateCheckTimestamp: nil,
        lastNotifiedVersion: nil,
        hosts: configuredHosts,
        profiles: []
    )
    guard saveConfig(config) else {
        fputs(tr("✗ 保存配置失败。\n", "✗ Failed to save configuration.\n"), stderr)
        return false
    }
    print(tr("\n✓ 恭喜！automnt 配置已顺利完成！", "\n✓ Configuration completed successfully!"))

    if offerServiceInstallation && shouldInstallService {
        print("")
        installLaunchAgent()
    } else if offerServiceInstallation {
        print(tr("  ✓ 已跳过后台服务部署。", "  ✓ Skipped background service deployment."))
        let activeConfigURL = getActiveConfigURL()
        print(tr("  配置已成功保存至: \(activeConfigURL.path)", "  Config successfully saved to: \(activeConfigURL.path)"))
        print(tr("  后续可通过运行 'automnt' 手动执行挂载，或使用 'automnt --config' 管理配置。\n",
                 "  You can run 'automnt' anytime to mount manually, or 'automnt --config' to manage.\n"))
    }
    return true
}

func runInitCommand(resetExistingConfig: Bool = false, offerServiceInstallation: Bool = true) -> Bool {
    let activeConfigURL = getActiveConfigURL()
    let inspection = inspectConfigFile(at: activeConfigURL)

    if !resetExistingConfig {
        switch inspection.state {
        case .usable:
            print(tr("✓ 已找到有效的活动配置文件；`--init` 未重建它。请用 `automnt --config` 管理配置，或用 `automnt --init --reset` 重建。",
                     "✓ A usable active config already exists; `--init` left it intact. Use `automnt --config` to edit it or `automnt --init --reset` to rebuild."))
            return true
        case .futureVersion(let v):
            fputs(tr("✗ 配置文件版本 v\(v) 高于当前程序 v\(automntVersion)；未重置配置。请先使用兼容版本，或明确运行 `automnt --init --reset`。\n",
                     "✗ The config v\(v) is newer than program v\(automntVersion); it was not reset. Use a compatible newer program or explicitly run `automnt --init --reset`.\n"), stderr)
            return false
        case .inaccessible:
            fputs(tr("✗ 无法安全读取或备份配置文件；未启动初始化向导。\n",
                     "✗ The config cannot be safely read or backed up; setup wizard not started.\n"), stderr)
            return false
        case .missing, .invalid:
            break
        }
    }

    guard isInteractiveTerminal() else {
        fputs(tr("当前输入不是交互终端；初始化向导使用编号列表，输入有效编号继续，直接回车取消。完成向导后会保存配置。\n",
                 "Input is not interactive; setup uses numbered lists. Enter a valid number to continue or press Enter to cancel. Completing the wizard saves the config.\n"), stderr)
        return runInitWizard(offerServiceInstallation: false)
    }
    return runInitWizard(offerServiceInstallation: offerServiceInstallation)
}

func prepareManagementConfigURL() -> URL? {
    let activeConfigURL = getActiveConfigURL()
    let inspection = inspectConfigFile(at: activeConfigURL)
    switch inspection.state {
    case .usable:
        return activeConfigURL
    case .missing:
        guard isInteractiveTerminal() else {
            fputs(tr("✗ 没有可用配置。请在交互式 Terminal 中运行 `automnt --init`。\n",
                     "✗ No usable config exists. Run `automnt --init` in an interactive Terminal.\n"), stderr)
            return nil
        }
        guard runInitWizard(offerServiceInstallation: false) else { return nil }
        return activeConfigURL
    case .futureVersion(let v):
        fputs(tr("✗ 配置文件版本 v\(v) 高于当前程序 v\(automntVersion)；未修改配置。请先使用兼容版本。\n",
                 "✗ The config v\(v) is newer than program v\(automntVersion); no config was changed. Use a compatible newer program first.\n"), stderr)
        return nil
    case .inaccessible, .invalid:
        fputs(tr("✗ 配置文件损坏或无法访问 (\(inspection.diagnostic ?? ""))；请先运行 `automnt --init --reset`。\n",
                 "✗ Config file is invalid or inaccessible; please run `automnt --init --reset` first.\n"), stderr)
        return nil
    }
}

func firstRegexCapture(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          match.numberOfRanges > 1,
          let range = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[range])
}

struct LaunchAgentDiagnostic {
    let isRegistered: Bool
    let state: String
    let lastExitCode: String
}

func getLaunchAgentDiagnostic() -> LaunchAgentDiagnostic {
    let serviceTarget = "gui/\(getuid())/\(launchAgentLabel)"
    let result = runCommand(executable: "/bin/launchctl", arguments: ["print", serviceTarget])
    let state = firstRegexCapture(#"(?m)^\s*state = (.+)$"#, in: result.stdout)
    let lastExitCode = firstRegexCapture(#"(?m)^\s*last exit code = (-?\d+)\s*$"#, in: result.stdout)
    return LaunchAgentDiagnostic(
        isRegistered: result.status == 0,
        state: state ?? tr("未知", "unknown"),
        lastExitCode: lastExitCode ?? tr("无", "none")
    )
}

func getLaunchAgentStatusSummary() -> String {
    let plistURL = getLaunchAgentPlistURL()
    if !FileManager.default.fileExists(atPath: plistURL.path) {
        return tr("未安装 (可运行 'automnt --install' 部署)", "Not installed (Run 'automnt --install' to deploy)")
    }
    let diagnostic = getLaunchAgentDiagnostic()
    if !diagnostic.isRegistered {
        return tr("描述文件存在但未被 launchd 注册", "Plist exists but service is not registered")
    }
    var details: [String] = []
    if !diagnostic.state.isEmpty {
        details.append(diagnostic.state)
    }
    if diagnostic.lastExitCode != tr("无", "none") {
        details.append("last exit: \(diagnostic.lastExitCode)")
    }
    return tr("已就绪 (事件驱动)", "Ready (event-driven)") + (details.isEmpty ? "" : " [\(details.joined(separator: ", "))]")
}

func getUpdateChannelDisplay(_ channel: String) -> String {
    switch channel {
    case "auto": return tr("自动静默更新 (auto)", "Automatic Silent Update (auto)")
    case "notify": return tr("通知提醒 (notify)", "Notify Only (notify)")
    default: return tr("已关闭 (off)", "Disabled (off)")
    }
}

func pauseForUser() {
    print(tr("\n按回车键继续...", "\nPress Enter to continue..."))
    _ = readLine()
}

func hostShareManagementOptions(for hostConfig: HostConfig) -> [SelectionItem] {
    let configuredShares = hostConfig.shares.map { share in
        SelectionItem(id: share.smbURL, title: share.name,
                      subtitle: "\(share.mountPoint) · \(share.enabled ? tr("启用", "Enabled") : tr("禁用", "Disabled"))",
                      isEnabled: false)
    }
    return configuredShares + [
        SelectionItem(id: "add", title: tr("追加共享", "Add shares")),
        SelectionItem(id: "delete", title: tr("批量删除共享", "Delete shares in batch")),
        SelectionItem(id: "toggle", title: tr("批量切换启用状态", "Toggle shares in batch")),
        SelectionItem(id: "back", title: tr("返回上一级", "Return to previous menu"))
    ]
}

func manageHostShares(hostConfig: inout HostConfig, allHosts: [HostConfig]) {
    while true {
        let hostDisplay = hostConfig.alias.map { "\($0) (\(hostConfig.host))" } ?? hostConfig.host
        let options = hostShareManagementOptions(for: hostConfig)
        guard let choice = promptInteractiveRadio(
            title: tr("\n主机管理：\(hostDisplay)", "\nHost management: \(hostDisplay)"), options: options,
            disabledHint: tr("该共享已配置，此行为信息展示项", "This share is already configured; this row is informational")
        ) else { return }
        let action = options[choice].id
        if action == "back" { return }
        if action.hasPrefix("smb://") {
            continue
        } else if action == "add" {
            let sourceOptions = [
                SelectionItem(id: "mounted", title: tr("从当前挂载卷追加", "Add from active mounts")),
                SelectionItem(id: "manual", title: tr("手动录入共享路径", "Enter a share path manually"))
            ]
            guard let sourceIndex = promptInteractiveRadio(title: tr("选择追加方式：", "Choose how to add shares:"), options: sourceOptions) else { continue }
            if sourceOptions[sourceIndex].id == "manual" {
                guard let path = promptLineWithEsc(prompt: tr("请输入 SMB 共享路径：", "Enter SMB share URL: ")) else { continue }
                let rawURL = path.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = extractShareName(from: rawURL) ?? "share"
                let mount = deriveStandardMountPoint(from: rawURL) ?? "/Volumes/\(name)"
                guard validateMountTargetURL(rawURL) == nil else { print(tr("无效的 SMB 共享路径。", "Invalid SMB share URL.")); continue }
                guard !hostConfig.shares.contains(where: { $0.smbURL.lowercased() == rawURL.lowercased() || $0.mountPoint == mount }) else {
                    print(tr("该共享已存在。", "This share is already configured.")); continue
                }
                hostConfig.shares.append(SMBShareConfig(name: name, smbURL: rawURL, mountPoint: mount, enabled: true))
            } else {
                let mounts = discoverCandidateHosts().first(where: { $0.host == hostConfig.host })?.mounts ?? []
                let existing = Set(hostConfig.shares.map { smbResourceIdentity($0.smbURL) })
                let candidates = mounts.filter { !existing.contains(smbResourceIdentity($0.smbURL)) }
                guard !candidates.isEmpty else { print(tr("没有可追加的新挂载共享。", "No new mounted shares are available.")); continue }
                let items = candidates.map { SelectionItem(id: $0.smbURL, title: $0.shareName, subtitle: redactedSMBURL($0.smbURL)) }
                guard let selected = promptInteractiveCheckbox(title: tr("选择要追加的共享：", "Select shares to add:"), options: items), !selected.isEmpty else { continue }
                for index in selected where candidates.indices.contains(index) {
                    let mount = candidates[index]
                    hostConfig.shares.append(SMBShareConfig(name: mount.shareName, smbURL: mount.smbURL,
                        mountPoint: deriveStandardMountPoint(from: mount.smbURL) ?? "/Volumes/\(mount.shareName)", enabled: true))
                }
            }
        } else if action == "delete" || action == "toggle" {
            guard !hostConfig.shares.isEmpty else { print(tr("当前没有共享。", "No shares configured.")); continue }
            let items = hostConfig.shares.map { SelectionItem(id: $0.smbURL, title: $0.name, subtitle: $0.mountPoint) }
            guard let selected = promptInteractiveCheckbox(title: action == "delete" ? tr("选择要删除的共享：", "Select shares to delete:") : tr("选择要切换状态的共享：", "Select shares to toggle:"), options: items), !selected.isEmpty else { continue }
            if action == "delete" {
                for index in selected.sorted(by: >) where hostConfig.shares.indices.contains(index) { hostConfig.shares.remove(at: index) }
            } else {
                for index in selected where hostConfig.shares.indices.contains(index) { hostConfig.shares[index].enabled.toggle() }
            }
        }
    }
}

func manageUpdateChannel(config: inout AutomntConfig) {
    let options = [
        SelectionItem(id: "off", title: "off", subtitle: tr("关闭自动检查", "Disable automatic checks")),
        SelectionItem(id: "notify", title: "notify", subtitle: tr("发现更新时发送系统通知", "Send a system notification when an update is available")),
        SelectionItem(id: "auto", title: "auto", subtitle: tr("自动下载并安装更新", "Download and install updates automatically"))
    ]
    guard let index = promptInteractiveRadio(title: tr("选择更新策略：", "Choose update policy:"), options: options,
                                             defaultIndex: options.firstIndex(where: { $0.id == config.updateChannel }) ?? 0) else { return }
    config.updateChannel = options[index].id
    let selectedChannel = config.updateChannel ?? "off"
    print(tr("✓ 更新信道已暂存为: \(selectedChannel)", "✓ Update channel staged as: \(selectedChannel)"))
}

func manageConfiguration() {
    guard let configURL = prepareManagementConfigURL(),
          var workingConfig = loadConfig(from: configURL) else { return }

    while true {
        print(tr("按 Esc 放弃未保存修改并退出。", "Press Esc to discard unsaved changes and exit."))
        let hostOptions = workingConfig.hosts.enumerated().map { index, host in
            let alias = host.alias.map { " [\($0)]" } ?? ""
            let enabledCount = host.shares.filter(\.enabled).count
            return SelectionItem(id: "host:\(index)", title: host.host + alias,
                subtitle: tr("\(host.shares.count) 个共享，\(enabledCount) 个启用", "\(host.shares.count) shares, \(enabledCount) enabled"))
        }
        let actions = [
            SelectionItem(id: "add", title: tr("新增主机", "Add host")),
            SelectionItem(id: "reorder", title: tr("调整主机顺位", "Reorder hosts")),
            SelectionItem(id: "delete", title: tr("删除主机", "Delete hosts")),
            SelectionItem(id: "channel", title: tr("修改更新策略", "Change update policy")),
            SelectionItem(id: "save", title: tr("保存并退出", "Save and exit"),
                          subtitle: tr("写入本次会话的所有修改", "Write all changes from this session"))
        ]
        let options = hostOptions + actions
        guard let selected = promptInteractiveRadio(
            title: tr("\n=== automnt 日常配置管理 ===\n活动配置：\(configURL.path)\n主机顺位：",
                      "\n=== automnt Daily Configuration ===\nActive config: \(configURL.path)\nHost priority:"),
            options: options
        ) else {
            print(tr("已放弃本次会话的所有未保存修改。", "Discarded all unsaved changes from this session."))
            return
        }
        let action = options[selected].id

        if action == "save" {
            guard saveConfig(workingConfig, to: configURL) else {
                fputs(tr("✗ 保存失败；配置管理仍保持打开。\n", "✗ Save failed; configuration management remains open.\n"), stderr)
                continue
            }
            print(tr("✓ 配置已保存并退出。", "✓ Configuration saved and exited."))
            return
        } else if action == "add" {
            addHostFlow: while true {
                let methods = [
                    SelectionItem(id: "mounted", title: tr("扫描当前挂载", "Scan active mounts")),
                    SelectionItem(id: "manual", title: tr("手动录入主机", "Enter host manually"))
                ]
                guard let method = promptInteractiveRadio(title: tr("选择新增主机方式：", "Choose how to add a host:"), options: methods) else { break addHostFlow }
                if methods[method].id == "manual" {
                    if let host = handleManualHostEntry(existingHosts: workingConfig.hosts) {
                        workingConfig.hosts.append(host)
                    } else if lastManualHostAliasWasEscaped {
                        continue addHostFlow
                    } else if lastLineInputReachedEOF || lastSelectionReachedEOF {
                        return
                    }
                    break addHostFlow
                }
                let configured = Set(workingConfig.hosts.map(\.host))
                let candidates = discoverCandidateHosts().filter { !configured.contains($0.host) }
                let candidateItems = candidates.map {
                    SelectionItem(id: $0.host, title: $0.host,
                                  subtitle: tr("\($0.mounts.count) 个已挂载共享", "\($0.mounts.count) mounted shares"))
                }
                if let index = promptInteractiveRadio(title: tr("选择要添加的主机：", "Select a host to add:"), options: candidateItems),
                   candidates.indices.contains(index),
                   let host = handleCandidateHostConfiguration(candidate: candidates[index]) {
                    workingConfig.hosts.append(host)
                }
                break addHostFlow
            }
        } else if action == "reorder" {
            guard workingConfig.hosts.count > 1 else {
                print(tr("至少需要两台主机才能调整顺位。", "At least two hosts are required to reorder."))
                continue
            }
            let hosts = workingConfig.hosts.enumerated().map { index, host in
                SelectionItem(id: "host:\(index)",
                              title: host.alias.map { "\($0) (\(host.host))" } ?? host.host,
                              subtitle: tr("当前顺位 \(index + 1)", "Current priority \(index + 1)"))
            }
            guard let source = promptInteractiveRadio(title: tr("第 1 步：选择要移动的主机", "Step 1: Select the host to move"), options: hosts) else { continue }
            let destinations = workingConfig.hosts.indices.map { index in
                SelectionItem(id: "slot:\(index)", title: tr("顺位 \(index + 1)", "Priority \(index + 1)"))
            }
            guard let destination = promptInteractiveRadio(title: tr("第 2 步：选择目标顺位", "Step 2: Select the destination priority"), options: destinations) else { continue }
            if source != destination {
                let host = workingConfig.hosts.remove(at: source)
                workingConfig.hosts.insert(host, at: destination)
                print(tr("✓ 已将主机成功调整至顺位 \(destination + 1)（尚未保存）。", "✓ Host successfully moved to priority \(destination + 1) (not saved yet)."))
            }
        } else if action == "delete" {
            guard !workingConfig.hosts.isEmpty else {
                print(tr("当前无主机可删除。", "No hosts to delete."))
                continue
            }
            let targets = workingConfig.hosts.enumerated().map { index, host in
                SelectionItem(id: "host:\(index)",
                              title: host.alias.map { "\($0) (\(host.host))" } ?? host.host)
            } + [SelectionItem(id: "all", title: tr("清空全部主机", "Delete all hosts"))]
            guard let targetIndex = promptInteractiveRadio(title: tr("选择要删除的目标：", "Select deletion target:"), options: targets) else { continue }
            let targetID = targets[targetIndex].id
            let confirmation = [
                SelectionItem(id: "cancel", title: tr("取消并返回", "Cancel and return")),
                SelectionItem(id: "confirm", title: tr("确认删除", "Confirm deletion"))
            ]
            let heading: String
            if targetID == "all" {
                heading = tr("=== 高风险操作确认：清空所有主机 ===", "=== HIGH-RISK CONFIRMATION: clear all hosts ===")
            } else if let index = Int(targetID.dropFirst("host:".count)), workingConfig.hosts.indices.contains(index) {
                heading = tr("=== 高风险操作确认：删除主机 \(workingConfig.hosts[index].host) ===",
                             "=== HIGH-RISK CONFIRMATION: delete host \(workingConfig.hosts[index].host) ===")
            } else {
                heading = tr("=== 高风险操作确认 ===", "=== HIGH-RISK CONFIRMATION ===")
            }
            let dialogTitle = heading + "\n" +
                tr("警告：删除后该主机名下的所有从属共享挂载配置将被同步移除。",
                   "Warning: all dependent share mount configurations of this host will be removed as well.") + "\n" +
                tr("删除仅修改内存工作副本，保存后才会生效。", "Deletion changes only the in-memory working copy until saved.")
            guard promptExplicitConfirmation(
                title: dialogTitle,
                options: confirmation
            ) == 1 else {
                print(tr("已安全取消删除。", "Deletion safely canceled."))
                continue
            }
            if targetID == "all" {
                workingConfig.hosts.removeAll()
            } else if let index = Int(targetID.dropFirst("host:".count)), workingConfig.hosts.indices.contains(index) {
                workingConfig.hosts.remove(at: index)
            }
            print(tr("✓ 删除已暂存，保存并退出后生效。", "✓ Deletion staged; save and exit to apply it."))
        } else if action == "channel" {
            manageUpdateChannel(config: &workingConfig)
        } else if action.hasPrefix("host:"),
                  let index = Int(action.dropFirst("host:".count)), workingConfig.hosts.indices.contains(index) {
            manageHostShares(hostConfig: &workingConfig.hosts[index], allHosts: workingConfig.hosts)
        }
    }
}

// MARK: - 自搬迁、Shell 注入与自检自愈 (Installation & Healing)

struct ShellSnippetManager {
    static let beginMarker = "# >>> automnt CLI begin >>>"
    static let endMarker = "# <<< automnt CLI end <<<"

    static func snippet(binaryDir: String) -> String {
        return """
        \(beginMarker)
        export PATH="\(binaryDir):$PATH"
        \(endMarker)
        """
    }

    static func isPresent(in content: String) -> Bool {
        return content.contains(beginMarker) && content.contains(endMarker)
    }

    static func inject(into content: String, binaryPath: String) -> String {
        let binDir = URL(fileURLWithPath: binaryPath).deletingLastPathComponent().path
        let newSnippet = snippet(binaryDir: binDir)
        var cleaned = remove(from: content)
        if !cleaned.isEmpty && !cleaned.hasSuffix("\n") {
            cleaned.append("\n")
        }
        return cleaned + newSnippet + "\n"
    }

    static func remove(from content: String) -> String {
        let pattern = "(?s)\\n?\(NSRegularExpression.escapedPattern(for: beginMarker)).*?\(NSRegularExpression.escapedPattern(for: endMarker))\\n?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return content }
        let range = NSRange(content.startIndex..., in: content)
        return regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "\n")
            .trimmingCharacters(in: .newlines) + "\n"
    }
}

struct InstallationManager {
    static func currentExecutablePhysicalURL() -> URL {
        var buffer = [CChar](repeating: 0, count: 4096)
        let pid = getpid()
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            let path = String(cString: buffer)
            return URL(fileURLWithPath: path).resolvingSymlinksInPath()
        }
        return URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    }

    static func detectShellProfileURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [".zshrc", ".bash_profile", ".bashrc"]
        for candidate in candidates {
            let url = home.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return home.appendingPathComponent(".zshrc")
    }

    @discardableResult
    static func relocateIfNeeded() -> Bool {
        let currentURL = currentExecutablePhysicalURL()
        let targetURL = getActiveInstalledBinaryURL()
        if currentURL.standardizedFileURL.path == targetURL.standardizedFileURL.path {
            return false
        }

        let targetDir = targetURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try? FileManager.default.removeItem(at: targetURL)
        }
        do {
            try FileManager.default.copyItem(at: currentURL, to: targetURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetURL.path)
            let isDevRepo = FileManager.default.fileExists(
                atPath: currentURL.deletingLastPathComponent().appendingPathComponent("automnt.swift").path
            )
            if !isDevRepo {
                _ = Darwin.unlink(currentURL.path)
            }
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func injectShellEntry() -> Bool {
        guard let profileURL = detectShellProfileURL() else { return false }
        let currentContent = (try? String(contentsOf: profileURL, encoding: .utf8)) ?? ""
        let binaryPath = getActiveInstalledBinaryURL().path
        let updated = ShellSnippetManager.inject(into: currentContent, binaryPath: binaryPath)
        do {
            try updated.write(to: profileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func removeShellEntry() -> Bool {
        guard let profileURL = detectShellProfileURL(),
              FileManager.default.fileExists(atPath: profileURL.path) else { return false }
        guard let currentContent = try? String(contentsOf: profileURL, encoding: .utf8) else { return false }
        let updated = ShellSnippetManager.remove(from: currentContent)
        do {
            try updated.write(to: profileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}

struct InstallState: Equatable {
    var currentExecutablePath: String
    var installedBinaryPath: String
    var activeConfigPath: String
    var launchAgentPlistPath: String
    var detectedShellProfile: String?
    var isRelocated: Bool
    var isCliEntryPresent: Bool
    var isServiceRegistered: Bool
    var isServicePlistValid: Bool

    var isHealthy: Bool {
        isRelocated && isCliEntryPresent && isServiceRegistered && isServicePlistValid
    }

    static func current() -> InstallState {
        let currentExec = InstallationManager.currentExecutablePhysicalURL().path
        let canonicalBinary = getActiveInstalledBinaryURL().path
        let activeConfig = getActiveConfigURL().path
        let plistURL = getLaunchAgentPlistURL()
        let profileURL = InstallationManager.detectShellProfileURL()
        let isRelocated = currentExec == canonicalBinary

        var isCliEntryPresent = false
        if let profileURL, let content = try? String(contentsOf: profileURL, encoding: .utf8) {
            isCliEntryPresent = ShellSnippetManager.isPresent(in: content)
        }

        var isServicePlistValid = false
        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            let label = plist["Label"] as? String
            let args = plist["ProgramArguments"] as? [String]
            let hasStartInterval = plist["StartInterval"] != nil
            if label == launchAgentLabel && args == [canonicalBinary] && !hasStartInterval {
                isServicePlistValid = true
            }
        }

        let serviceTarget = "gui/\(getuid())/\(launchAgentLabel)"
        let printResult = runCommand(executable: "/bin/launchctl", arguments: ["print", serviceTarget])
        let isServiceRegistered = printResult.status == 0

        return InstallState(
            currentExecutablePath: currentExec,
            installedBinaryPath: canonicalBinary,
            activeConfigPath: activeConfig,
            launchAgentPlistPath: plistURL.path,
            detectedShellProfile: profileURL?.path,
            isRelocated: isRelocated,
            isCliEntryPresent: isCliEntryPresent,
            isServiceRegistered: isServiceRegistered,
            isServicePlistValid: isServicePlistValid
        )
    }

    func healIfNeeded() -> Bool {
        var healed = false
        if !isCliEntryPresent {
            _ = InstallationManager.injectShellEntry()
            healed = true
        }
        if !isServicePlistValid || !isServiceRegistered {
            _ = registerOrUpdateLaunchAgent()
            healed = true
        }
        return healed
    }
}

func generateLaunchAgentDictionary(binaryURL: URL, logDir: URL) -> [String: Any] {
    let stdoutLog = logDir.appendingPathComponent("stdout.log").path
    let stderrLog = logDir.appendingPathComponent("stderr.log").path
    let sysConfigDir = "/Library/Preferences/SystemConfiguration"

    return [
        "Label": launchAgentLabel,
        "ProgramArguments": [binaryURL.path],
        "RunAtLoad": true,
        "WatchPaths": [
            "\(sysConfigDir)/NetworkInterfaces.plist",
            "\(sysConfigDir)/com.apple.airport.preferences.plist",
            sysConfigDir
        ],
        "StandardOutPath": stdoutLog,
        "StandardErrorPath": stderrLog
    ]
}

func registerOrUpdateLaunchAgent(targetBinaryURL: URL? = nil, targetPlistURL: URL? = nil) -> Bool {
    let binary = targetBinaryURL ?? getActiveInstalledBinaryURL()
    let plistURL = targetPlistURL ?? getLaunchAgentPlistURL()
    let logDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/automnt", isDirectory: true)

    try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    let agentDict = generateLaunchAgentDictionary(binaryURL: binary, logDir: logDir)

    do {
        let parentDir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: agentDict, format: .xml, options: 0)
        try atomicWrite(data, to: plistURL, permissions: 0o644)
    } catch {
        return false
    }

    let uid = getuid()
    let serviceTarget = "gui/\(uid)/\(launchAgentLabel)"
    _ = runCommand(executable: "/bin/launchctl", arguments: ["bootout", serviceTarget])
    let bootinResult = runCommand(executable: "/bin/launchctl", arguments: ["bootstrap", "gui/\(uid)", plistURL.path])
    return bootinResult.status == 0
}

func installLaunchAgent() {
    print(tr("""
    automnt - 安装并启用自启动守护服务
    ===========================================
    """, """
    automnt - Install LaunchAgent Daemon
    ============================================
    """))

    let binary = getActiveInstalledBinaryURL()
    if !FileManager.default.fileExists(atPath: binary.path) {
        InstallationManager.relocateIfNeeded()
    }
    InstallationManager.injectShellEntry()
    let success = registerOrUpdateLaunchAgent()
    let plistURL = getLaunchAgentPlistURL()
    if success {
        print(tr("✓ 已生成服务描述文件:\n  \(plistURL.path)", "✓ Generated LaunchAgent plist:\n  \(plistURL.path)"))
        print(tr("✓ 成功注册并加载至系统 launchd 守护进程 (gui/\(getuid()))",
                 "✓ Successfully registered and loaded into system launchd (gui/\(getuid()))"))
        print(tr("""

        服务详情:
          • 标识 (Label): \(launchAgentLabel)
          • 执行命令: \(binary.path)
          • 触发时机: 登录启动与系统网络配置变化事件驱动
          • 日志路径: ~/Library/Logs/automnt/stdout.log

        自启动与网络监听服务已生效。
        """, """

        Service Details:
          • Label: \(launchAgentLabel)
          • Command: \(binary.path)
          • Trigger: Login and network change event-driven
          • Log file: ~/Library/Logs/automnt/stdout.log

        LaunchAgent is loaded and will evaluate the configured network policy.
        """))
    } else {
        fputs(tr("✗ 注册守护服务失败，请检查 launchd 权限。\n",
                 "✗ Failed to register daemon service.\n"), stderr)
    }
}

func uninstallLaunchAgent(purge: Bool = false) {
    print(tr("""
    automnt - 卸载自启动服务
    =================================
    """, """
    automnt - Uninstall LaunchAgent Daemon
    ==============================================
    """))

    let uid = getuid()
    let serviceTarget = "gui/\(uid)/\(launchAgentLabel)"
    let plistURL = getLaunchAgentPlistURL()
    let appSupportDir = getActiveInstalledDir()
    let canonicalBinaryURL = getActiveInstalledBinaryURL()
    let activeConfig = getActiveConfigURL()

    let bootResult = runCommand(executable: "/bin/launchctl", arguments: ["bootout", serviceTarget])
    if bootResult.status == 0 {
        print(tr("✓ 成功从系统 launchd 中卸载服务 (\(serviceTarget))",
                 "✓ Unloaded service from system launchd (\(serviceTarget))"))
    }

    if FileManager.default.fileExists(atPath: plistURL.path) {
        do {
            try FileManager.default.removeItem(at: plistURL)
            print(tr("✓ 已删除服务描述文件: \(plistURL.path)", "✓ Removed LaunchAgent plist: \(plistURL.path)"))
        } catch {
            fputs(tr("✗ 删除描述文件失败: \(error.localizedDescription)\n",
                     "✗ Failed to remove plist: \(error.localizedDescription)\n"), stderr)
        }
    }

    if InstallationManager.removeShellEntry() {
        print(tr("✓ 已从 Shell 配置文件中清除 automnt CLI 入口",
                 "✓ Removed automnt CLI snippet from shell profile"))
    }

    if FileManager.default.fileExists(atPath: canonicalBinaryURL.path) {
        try? FileManager.default.removeItem(at: canonicalBinaryURL)
        print(tr("✓ 已删除规范安装目录可执行文件", "✓ Removed canonical executable"))
    }

    if purge {
        if FileManager.default.fileExists(atPath: appSupportDir.path) {
            try? FileManager.default.removeItem(at: appSupportDir)
            print(tr("✓ 已彻底删除 Application Support 目录: \(appSupportDir.path)",
                     "✓ Purged Application Support directory: \(appSupportDir.path)"))
        }
        let logDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/automnt")
        if FileManager.default.fileExists(atPath: logDir.path) {
            try? FileManager.default.removeItem(at: logDir)
            print(tr("✓ 已彻底删除日志目录: \(logDir.path)", "✓ Purged log directory: \(logDir.path)"))
        }
        print(tr("\n✓ automnt 已全量彻底卸载清理。", "\n✓ automnt fully purged."))
    } else {
        print(tr("""

        注意：您的配置文件已保留在:
          \(activeConfig.path)
        如需彻底删除配置与历史日志，请执行:
          automnt --uninstall --purge
        或直接删除: rm -rf "\(appSupportDir.path)"
        """, """

        Note: Your configuration has been preserved at:
          \(activeConfig.path)
        To completely remove configuration and logs, run:
          automnt --uninstall --purge
        Or manually remove: rm -rf "\(appSupportDir.path)"
        """))
    }
}

func checkServiceStatus() {
    print(tr("""
    automnt - 运行状态总览 (v\(automntVersion))
    ====================================
    """, """
    automnt - Service Status Overview (v\(automntVersion))
    =============================================
    """))

    let activeConfigURL = getActiveConfigURL()
    let installState = InstallState.current()

    print(tr("安装与自愈状态:", "Installation & Health State:"))
    print(tr("  • 规范路径就绪: \(installState.isRelocated ? "✓ 是" : "✗ 否")",
             "  • Relocated: \(installState.isRelocated ? "✓ Yes" : "✗ No")"))
    print(tr("  • Shell CLI 入口: \(installState.isCliEntryPresent ? "✓ 正常" : "✗ 缺失")",
             "  • Shell CLI Snippet: \(installState.isCliEntryPresent ? "✓ Present" : "✗ Missing")"))
    print(tr("  • 守护服务登记: \(installState.isServiceRegistered ? "✓ 已注册" : "✗ 未注册")",
             "  • Service Registered: \(installState.isServiceRegistered ? "✓ Registered" : "✗ Not Registered")"))
    print(tr("  • 描述文件合规: \(installState.isServicePlistValid ? "✓ 合规" : "✗ 异常")",
             "  • Plist Valid: \(installState.isServicePlistValid ? "✓ Valid" : "✗ Invalid")"))

    print(tr("\n配置与守护服务:", "\nConfiguration & Daemon:"))
    print(tr("  • 唯一活动配置: \(activeConfigURL.path)", "  • Active Config: \(activeConfigURL.path)"))
    print(tr("  • 守护服务状态: \(getLaunchAgentStatusSummary())", "  • Service Summary: \(getLaunchAgentStatusSummary())"))

    if let config = loadConfig(from: activeConfigURL, migrate: false) {
        if config.hosts.isEmpty && config.profiles.isEmpty {
            print(tr("\n当前未配置任何主机 (安全休眠状态)。", "\nNo hosts configured (safe dormant sleep state)."))
        } else if !config.hosts.isEmpty {
            print(tr("\n已配置主机顺位 (\(config.hosts.count) 个)：", "\nConfigured Host Pipeline (\(config.hosts.count)):"))
            for (idx, h) in config.hosts.enumerated() {
                let aliasText = h.alias.map { " '\($0)'" } ?? ""
                print(tr("  [\(idx + 1)]\(aliasText) -> 主机: \(h.host):\(h.port), 超时: \(h.timeoutMs)ms, 共享: \(h.shares.count) 个",
                         "  [\(idx + 1)]\(aliasText) -> Host: \(h.host):\(h.port), Timeout: \(h.timeoutMs)ms, Shares: \(h.shares.count)"))
                for s in h.shares {
                    let mounted = getKernelMountSource(for: s.mountPoint) != nil
                    let statusStr = mounted ? tr("已挂载", "Mounted") : tr("未挂载", "Unmounted")
                    let enabledStr = s.enabled ? tr("启用", "Enabled") : tr("禁用", "Disabled")
                    print("      - \(s.name) (\(s.mountPoint)) [\(statusStr), \(enabledStr)] -> \(redactedSMBURL(s.smbURL))")
                }
            }
        } else {
            print(tr("\n已配置策略流水线 (\(config.profiles.count) 个)：", "\nConfigured Profile Pipeline (\(config.profiles.count)):"))
            for (idx, p) in config.profiles.enumerated() {
                print(tr("  [\(idx + 1)] '\(p.id)' (\(p.description ?? "")) -> 主机: \(p.host):\(p.port ?? 445), 超时: \(p.timeoutMs ?? 1000)ms, 挂载目标: \(p.targets.count) 个",
                         "  [\(idx + 1)] '\(p.id)' (\(p.description ?? "")) -> Host: \(p.host):\(p.port ?? 445), Timeout: \(p.timeoutMs ?? 1000)ms, Targets: \(p.targets.count)"))
                for t in p.targets {
                    let mounted = getKernelMountSource(for: t.mountPath) != nil
                    let statusStr = mounted ? tr("已挂载", "Mounted") : tr("未挂载", "Unmounted")
                    print("      - \(t.mountPath) [\(statusStr)] -> \(redactedSMBURL(t.url))")
                }
            }
        }
    } else {
        print(tr("\n未找到有效配置，建议运行: automnt --init", "\nNo valid config found. Recommended command: automnt --init"))
    }
}

// MARK: - 预编译二进制升级系统 (Self-Update via Prebuilt Binary)

func quoteAppleScript(_ str: String) -> String {
    "\"" + str.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

func showMacOSNotification(title: String, subtitle: String, message: String) {
    let script = "display notification \(quoteAppleScript(message)) with title \(quoteAppleScript(title)) subtitle \(quoteAppleScript(subtitle))"
    _ = runCommand(executable: "/usr/bin/osascript", arguments: ["-e", script])
}

func parseSemanticVersion(_ versionStr: String) -> [Int] {
    let clean = versionStr.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "v", with: "")
        .replacingOccurrences(of: "V", with: "")
    let parts = clean.split(separator: "-").first.map(String.init) ?? clean
    return parts.split(separator: ".").compactMap { Int($0) }
}

func isNewerVersion(_ remote: String, than current: String) -> Bool {
    let r = parseSemanticVersion(remote)
    let c = parseSemanticVersion(current)
    let maxLen = max(r.count, c.count)
    for i in 0..<maxLen {
        let rVal = i < r.count ? r[i] : 0
        let cVal = i < c.count ? c[i] : 0
        if rVal > cVal { return true }
        if rVal < cVal { return false }
    }
    return false
}

struct GitHubReleaseInfo {
    let tagName: String
    let name: String
    let body: String
    let htmlURL: String
}

enum ReleaseFetchResult {
    case success(GitHubReleaseInfo)
    case rateLimited
    case noRelease
    case networkError(String)
}

func fetchLatestReleaseInfo() -> ReleaseFetchResult {
    let urlString = "https://api.github.com/repos/\(githubRepo)/releases/latest"
    guard let url = URL(string: urlString) else { return .networkError("Invalid URL") }
    var request = URLRequest(url: url)
    request.timeoutInterval = 10
    request.setValue("automnt/\(automntVersion)", forHTTPHeaderField: "User-Agent")

    let semaphore = DispatchSemaphore(value: 0)
    var fetchResult: ReleaseFetchResult = .noRelease

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }
        if let error = error {
            fetchResult = .networkError(error.localizedDescription)
            return
        }
        guard let http = response as? HTTPURLResponse else {
            fetchResult = .networkError("Invalid response")
            return
        }
        if http.statusCode == 403 || http.statusCode == 429 {
            fetchResult = .rateLimited
            return
        }
        guard http.statusCode == 200, let data = data else {
            fetchResult = .noRelease
            return
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tag = json["tag_name"] as? String {
            let name = json["name"] as? String ?? tag
            let body = json["body"] as? String ?? ""
            let htmlURL = json["html_url"] as? String ?? ""
            fetchResult = .success(GitHubReleaseInfo(tagName: tag, name: name, body: body, htmlURL: htmlURL))
        }
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + 15)
    return fetchResult
}

func downloadLatestBinary(tag: String) -> Data? {
    let cleanTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    let urlString = "https://github.com/\(githubRepo)/releases/download/\(cleanTag)/automnt"
    guard let url = URL(string: urlString) else { return nil }

    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    request.setValue("automnt/\(automntVersion)", forHTTPHeaderField: "User-Agent")

    let semaphore = DispatchSemaphore(value: 0)
    var resultData: Data?

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }
        if let http = response as? HTTPURLResponse, http.statusCode == 200, let d = data, !d.isEmpty {
            resultData = d
        }
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + 35)
    return resultData
}

func performSelfUpdateWithBinary(newVersion: String, binaryData: Data, isSilent: Bool) -> Bool {
    let targetURL = getActiveInstalledBinaryURL()
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("automnt-update-\(UUID().uuidString)")
    let stagedBinary = tempDir.appendingPathComponent("automnt")

    do {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try binaryData.write(to: stagedBinary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagedBinary.path)

        let valResult = runCommand(executable: stagedBinary.path, arguments: ["--version"])
        guard valResult.status == 0, valResult.stdout.contains(newVersion) else {
            writeLog("Prebuilt binary validation failed for v\(newVersion)")
            return false
        }

        try replaceFilesTransactionally([
            StagedFileReplacement(sourceURL: stagedBinary, destinationURL: targetURL, permissions: 0o755)
        ])

        writeLog("Successfully updated automnt to v\(newVersion)")
        if !isSilent {
            print(tr("✓ 成功升级 automnt 至 v\(newVersion)", "✓ Successfully updated automnt to v\(newVersion)"))
        }
        return true
    } catch {
        writeLog("Self-update failed: \(error.localizedDescription)")
        return false
    }
}

func handleManualUpdateCommand() {
    print(tr("正在检查新版本...", "Checking for updates..."))
    let res = fetchLatestReleaseInfo()
    switch res {
    case .success(let info):
        let remoteVer = info.tagName.replacingOccurrences(of: "v", with: "")
        if isNewerVersion(remoteVer, than: automntVersion) {
            print(tr("发现新版本: v\(remoteVer) (当前: v\(automntVersion))",
                     "New version available: v\(remoteVer) (Current: v\(automntVersion))"))
            print(tr("正在下载预编译二进制...", "Downloading prebuilt binary..."))
            if let binaryData = downloadLatestBinary(tag: info.tagName) {
                if performSelfUpdateWithBinary(newVersion: remoteVer, binaryData: binaryData, isSilent: false) {
                    print(tr("升级完成！请重新运行 'automnt'。", "Update complete! Please run 'automnt' again."))
                } else {
                    print(tr("✗ 升级安装失败。", "✗ Update installation failed."))
                }
            } else {
                print(tr("✗ 下载二进制文件失败，请检查网络连接。", "✗ Failed to download binary. Please check network connection."))
            }
        } else {
            print(tr("已是最新版本 (v\(automntVersion))。", "Already up to date (v\(automntVersion))."))
        }
    case .rateLimited:
        print(tr("GitHub API 速率限制，请稍后再试。", "GitHub API rate limited. Please try again later."))
    case .noRelease:
        print(tr("未找到 Release 资产。", "No release assets found."))
    case .networkError(let err):
        print(tr("网络错误: \(err)", "Network error: \(err)"))
    }
}

func triggerBackgroundUpdateCheckIfNeeded(config: inout AutomntConfig) {
    let channel = config.updateChannel ?? "off"
    guard channel != "off" else { return }

    let now = Date().timeIntervalSince1970
    if let lastCheck = config.lastUpdateCheckTimestamp, now - lastCheck < 86400 {
        return
    }
    config.lastUpdateCheckTimestamp = now
    _ = saveConfig(config)

    let fetchRes = fetchLatestReleaseInfo()
    guard case .success(let info) = fetchRes else { return }
    let remoteVer = info.tagName.replacingOccurrences(of: "v", with: "")
    guard isNewerVersion(remoteVer, than: automntVersion) else { return }

    if channel == "notify" {
        if config.lastNotifiedVersion != remoteVer {
            showMacOSNotification(
                title: "automnt",
                subtitle: tr("发现新版本 \(remoteVer) (当前: v\(automntVersion))", "New version \(remoteVer) available"),
                message: tr("运行 'automnt --update' 升级", "Run 'automnt --update' to upgrade")
            )
            config.lastNotifiedVersion = remoteVer
            _ = saveConfig(config)
        }
    } else if channel == "auto" {
        if let data = downloadLatestBinary(tag: info.tagName) {
            _ = performSelfUpdateWithBinary(newVersion: remoteVer, binaryData: data, isSilent: true)
        }
    }
}

// MARK: - 内置自动化测试套件 (--self-test)

func runSelfTests(includeNetworkChecks: Bool = false) -> Bool {
    var passed = 0
    var failed = 0
    let skipped = 0

    func check(_ condition: Bool, _ name: String) {
        if condition {
            passed += 1
            print("PASS \(name)")
        } else {
            failed += 1
            print("FAIL \(name)")
        }
        fflush(stdout)
    }

    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("automnt-selftest-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // 1. Config inspection tests
    let missingConfig = inspectConfigFile(at: tempDir.appendingPathComponent("missing.plist"))
    check(missingConfig.state == .missing, "config inspection distinguishes a missing file")

    let invalidURL = tempDir.appendingPathComponent("invalid.plist")
    try? Data("not a plist".utf8).write(to: invalidURL)
    let invalidConfig = inspectConfigFile(at: invalidURL)
    check(invalidConfig.state == .invalid, "config inspection distinguishes a malformed file")

    let dirURL = tempDir.appendingPathComponent("is-a-dir")
    try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
    let dirConfig = inspectConfigFile(at: dirURL)
    check(dirConfig.state == .inaccessible, "config inspection refuses a directory")

    // 2. Backup & Prune tests (FR-024, SC-016)
    let sampleData = Data("<plist version=\"1.0\"><dict><key>test</key><string>val</string></dict></plist>".utf8)
    let sampleURL = tempDir.appendingPathComponent("sample.plist")
    try? sampleData.write(to: sampleURL)
    let sampleInspection = inspectConfigFile(at: sampleURL)
    let b1 = try? backUpConfigFile(sampleInspection)
    check(b1 != nil && FileManager.default.fileExists(atPath: b1!.path), "config backup creates file")
    let b1Perms = (try? FileManager.default.attributesOfItem(atPath: b1!.path)[.posixPermissions] as? NSNumber)?.intValue
    check(b1Perms == 0o600, "config backup preserves 0600 permissions")

    let b2 = try? backUpConfigFile(sampleInspection)
    check(b2 != nil, "second backup creates file")
    pruneConfigBackups(for: sampleURL, maxToKeep: 1)
    let backupFiles = (try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil))?.filter {
        $0.lastPathComponent.hasPrefix("sample.plist.backup-")
    } ?? []
    check(backupFiles.count == 1, "pruneConfigBackups strictly retains at most 1 backup")

    // 3. NetworkProfile & AutomntConfig models
    let testProfile = NetworkProfile(
        id: "test_lan",
        description: "Test Profile",
        host: "nas.invalid",
        port: 445,
        timeoutMs: 1000,
        preventSpotlightIndex: true,
        targets: [MountTarget(url: "smb://nas.invalid/share", mountPath: "/Volumes/share")]
    )
    check(testProfile.host == "nas.invalid" && testProfile.port == 445, "NetworkProfile fields are properly mapped")

    let testConfig = AutomntConfig(
        version: automntVersion,
        updateChannel: "auto",
        retryPolicy: RetryPolicy(),
        lastUpdateCheckTimestamp: nil,
        lastNotifiedVersion: nil,
        hosts: [HostConfig(host: "nas.local", alias: "本地局域网直连", shares: [SMBShareConfig(name: "share", smbURL: "smb://nas.local/share", mountPoint: "/Volumes/share")])],
        profiles: []
    )
    check(!configNeedsMigration(testConfig), "modern config does not need migration")

    var oldConfig = testConfig
    oldConfig.version = "2.7.1"
    check(configNeedsMigration(oldConfig), "older version config needs migration")

    var legacyProfileConfig = testConfig
    legacyProfileConfig.profiles = [testProfile]
    check(configNeedsMigration(legacyProfileConfig), "legacy profiles need migration")

    // 4. Migration & Unknown fields retention
    let migrationURL = tempDir.appendingPathComponent("migration_test.plist")
    let legacyXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \t<key>version</key>
    \t<string>2.7.1</string>
    \t<key>update_channel</key>
    \t<string>auto</string>
    \t<key>custom_root_field</key>
    \t<string>custom_value</string>
    \t<key>profiles</key>
    \t<array>
    \t\t<dict>
    \t\t\t<key>id</key>
    \t\t\t<string>home_lan</string>
    \t\t\t<key>description</key>
    \t\t\t<string>家庭局域网直连</string>
    \t\t\t<key>host</key>
    \t\t\t<string>nas.local</string>
    \t\t\t<key>targets</key>
    \t\t\t<array>
    \t\t\t\t<dict>
    \t\t\t\t\t<key>mount_path</key>
    \t\t\t\t\t<string>/Volumes/share-1</string>
    \t\t\t\t\t<key>url</key>
    \t\t\t\t\t<string>smb://nas.local/share</string>
    \t\t\t\t</dict>
    \t\t\t</array>
    \t\t</dict>
    \t</array>
    </dict>
    </plist>
    """
    try? legacyXML.data(using: .utf8)?.write(to: migrationURL)
    var loadedLegacy = loadConfig(from: migrationURL, migrate: false)!
    let migrationSuccess = migrateConfigIfNeeded(config: &loadedLegacy, at: migrationURL)
    check(migrationSuccess, "config migration executes successfully")
    check(loadedLegacy.version == automntVersion, "migrated version is updated to current")
    check(loadedLegacy.hosts.first?.host == "nas.local", "migrated host is updated to hosts")
    check(loadedLegacy.hosts.first?.shares.first?.mountPoint == "/Volumes/share", "migrated share mountPoint is /Volumes/share with -1 cleaned")
    let postMigrationString = (try? String(contentsOf: migrationURL, encoding: .utf8)) ?? ""
    check(postMigrationString.contains("custom_root_field") && postMigrationString.contains("custom_value"),
          "migration preserves unknown plist fields")

    // 5. SMB URL & Path validations
    check(smbResourceIdentity("smb://user:pass@NAS.local/Share") == smbResourceIdentity("//nas.local/share"),
          "SMB identity ignores credentials and casing")
    check(smbResourceIdentity("smb://nas.local/share1") != smbResourceIdentity("smb://nas.local/share2"),
          "different shares have different identities")
    check(extractHost(from: "smb://[fd00::1]/share") == "fd00::1", "IPv6 SMB host is correctly extracted")
    check(validateMountTargetURL("smb://nas.local/share") == nil, "valid SMB URL is accepted")
    check(validateMountTargetURL("https://nas.local/share") != nil, "non-SMB URL is rejected")
    check(validateMountTargetURL("smb://nas.local") != nil, "SMB URL without share is rejected")
    check(validateMountTargetURL("smb://user:pass@nas.local/share") != nil, "embedded credentials in SMB URL are rejected")
    check(validateMountTargetURL("smb://user@nas.local/share") != nil, "embedded username in SMB URL are rejected")
    check(validateMountPath("/Volumes/share") == nil, "absolute mount path is accepted")
    check(validateMountPath("relative/share") != nil, "relative mount path is rejected")
    check(validateMountPath("/Volumes/../root") != nil, "traversal mount path is rejected")

    let redacted = redactedSMBURL("smb://alice:secret@nas.local/share")
    check(!redacted.contains("alice") && !redacted.contains("secret"), "SMB URL credentials are redacted")

    // 6. LaunchAgent dictionary (WatchPaths & No StartInterval)
    let agentDict = generateLaunchAgentDictionary(binaryURL: URL(fileURLWithPath: "/usr/local/bin/automnt"), logDir: tempDir)
    check(agentDict["RunAtLoad"] as? Bool == true, "LaunchAgent dictionary includes RunAtLoad = true")
    check(agentDict["WatchPaths"] as? [String] != nil, "LaunchAgent dictionary includes WatchPaths")
    check(agentDict["StartInterval"] == nil, "LaunchAgent dictionary strictly excludes StartInterval")

    // 7. Atomic transaction file replacement & rollback
    let txnDir = tempDir.appendingPathComponent("txn")
    try? FileManager.default.createDirectory(at: txnDir, withIntermediateDirectories: true)
    let src1 = txnDir.appendingPathComponent("src1")
    let dst1 = txnDir.appendingPathComponent("dst1")
    try? Data("new content".utf8).write(to: src1)
    try? Data("original content".utf8).write(to: dst1)
    try? replaceFilesTransactionally([StagedFileReplacement(sourceURL: src1, destinationURL: dst1, permissions: 0o600)])
    check((try? String(contentsOf: dst1, encoding: .utf8)) == "new content", "transactional file replacement succeeds")

    var rollbackPassed = false
    do {
        try replaceFilesTransactionally([
            StagedFileReplacement(sourceURL: src1, destinationURL: dst1, permissions: 0o600)
        ]) {
            throw NSError(domain: "AutomntTest", code: 1, userInfo: nil)
        }
    } catch {
        rollbackPassed = (try? String(contentsOf: dst1, encoding: .utf8)) == "new content"
    }
    check(rollbackPassed, "transactional file replacement rolls back on action error")

    // 8. Child runner non-deadlock & timeout
    let pipeTest = runCommand(
        executable: "/bin/sh",
        arguments: ["-c", "/usr/bin/yes x | /usr/bin/head -c 131072 >&2; printf stdout"]
    )
    check(pipeTest.status == 0 && pipeTest.stdout == "stdout" && pipeTest.stderr.utf8.count == 131072,
          "child stdout and large stderr are drained without deadlock")

    let timedOutCommand = runCommandDiscardingOutputWithTimeout(
        executable: "/bin/sleep", arguments: ["2"], timeout: 0.05
    )
    check(timedOutCommand.timedOut && timedOutCommand.processStopped,
          "bounded child runner terminates and reaps a timed-out command")

    // 9. Shell snippet injection & removal
    let profileContent = "export VAR=foo\nalias ll='ls -l'\n"
    let injected = ShellSnippetManager.inject(into: profileContent, binaryPath: "/custom/bin/automnt")
    check(ShellSnippetManager.isPresent(in: injected), "Shell snippet is detected after injection")
    check(injected.contains("/custom/bin"), "Shell snippet contains binary directory")
    check(injected.contains("export VAR=foo"), "Shell snippet preserves original user variables")
    let reinjected = ShellSnippetManager.inject(into: injected, binaryPath: "/new/bin/automnt")
    check(reinjected.contains("/new/bin") && !reinjected.contains("/custom/bin"), "Shell snippet injection is idempotent")
    let stripped = ShellSnippetManager.remove(from: reinjected)
    check(!ShellSnippetManager.isPresent(in: stripped), "Shell snippet is cleanly removed")
    check(stripped.contains("export VAR=foo") && stripped.contains("alias ll='ls -l'"), "Shell snippet removal restores original profile")

    // 10. EvaluationRetryRunner tests
    var runnerAttempts = 0
    let retryRunner = EvaluationRetryRunner(policy: RetryPolicy(maxAttempts: 3, intervalMs: 10, maxTotalWindowMs: 500))
    let retrySuccess = retryRunner.run {
        runnerAttempts += 1
        return runnerAttempts == 2
    }
    check(retrySuccess && runnerAttempts == 2, "EvaluationRetryRunner retries and succeeds within window")

    var failAttempts = 0
    let failRunner = EvaluationRetryRunner(policy: RetryPolicy(maxAttempts: 2, intervalMs: 10, maxTotalWindowMs: 100))
    let failResult = failRunner.run {
        failAttempts += 1
        return false
    }
    check(!failResult && failAttempts == 2, "EvaluationRetryRunner exhausts attempts cleanly")

    // 11. HostReachabilityProbe tests
    check(!HostReachabilityProbe.canConnect(host: ""), "HostReachabilityProbe rejects empty host")
    check(!HostReachabilityProbe.canConnect(host: "127.0.0.1", port: 59999, timeoutMs: 50),
          "HostReachabilityProbe handles unreachable host gracefully")

    // 12. Active Canonical Paths & Environment Simulation tests
    let customConfigURL = tempDir.appendingPathComponent("custom_test.plist")
    configURLOverride = customConfigURL
    check(getActiveConfigURL() == customConfigURL, "getActiveConfigURL respects configURLOverride")
    configURLOverride = nil
    check(getActiveConfigURL().lastPathComponent == "automnt.plist", "getActiveConfigURL targets automnt.plist")
    check(getActiveInstalledBinaryURL().lastPathComponent == "automnt", "getActiveInstalledBinaryURL targets automnt executable")

    isTTYOverride = false
    check(!isInteractiveTerminal(), "isInteractiveTerminal respects isTTYOverride = false")
    isTTYOverride = true
    check(isInteractiveTerminal(), "isInteractiveTerminal respects isTTYOverride = true")
    isTTYOverride = nil

    // 13. InstallationManager & InstallState
    let downloadBin = tempDir.appendingPathComponent("downloads/automnt")
    try? FileManager.default.createDirectory(at: downloadBin.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data("binary bytes".utf8).write(to: downloadBin)
    check(FileManager.default.fileExists(atPath: downloadBin.path), "Download copy exists before relocation")

    let mockTargetBin = tempDir.appendingPathComponent("canonical/bin/automnt")
    try? FileManager.default.createDirectory(at: mockTargetBin.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.copyItem(at: downloadBin, to: mockTargetBin)
    _ = Darwin.unlink(downloadBin.path)
    check(!FileManager.default.fileExists(atPath: downloadBin.path), "Original download copy is unlinked after relocation")
    check(FileManager.default.fileExists(atPath: mockTargetBin.path), "Target binary exists at canonical path")

    let healthyState = InstallState(
        currentExecutablePath: "/canonical/bin/automnt",
        installedBinaryPath: "/canonical/bin/automnt",
        activeConfigPath: "/canonical/automnt.plist",
        launchAgentPlistPath: "/LaunchAgents/com.user.automnt.plist",
        detectedShellProfile: "/Users/test/.zshrc",
        isRelocated: true,
        isCliEntryPresent: true,
        isServiceRegistered: true,
        isServicePlistValid: true
    )
    check(healthyState.isHealthy, "InstallState reports healthy when all components intact")

    var unhealthyState = healthyState
    unhealthyState.isServicePlistValid = false
    check(!unhealthyState.isHealthy, "InstallState detects unhealthy state when service plist is invalid")

    // 14. Feature 002 Foundational tests (T003 - T008)
    // Mount point derivation (T005)
    check(deriveStandardMountPoint(from: "smb://192.168.1.100/Public") == "/Volumes/Public",
          "deriveStandardMountPoint extracts clean /Volumes/Public")
    check(deriveStandardMountPoint(from: "smb://192.168.1.100/data-1") == "/Volumes/data-1",
          "deriveStandardMountPoint strictly preserves legal data-1 share name")
    check(deriveStandardMountPoint(from: "//user@192.168.1.100/Work") == "/Volumes/Work",
          "deriveStandardMountPoint strips credentials and normalizes to /Volumes/Work")
    check(deriveStandardMountPoint(from: "smb://server.local/My%20Data") == "/Volumes/My Data",
          "deriveStandardMountPoint decodes percent-encoded share name")

    // Zero-host config inspection (T004)
    let zeroHostConfig = AutomntConfig(version: automntVersion, hosts: [])
    let zeroHostURL = tempDir.appendingPathComponent("zero_host.plist")
    if let data = try? PropertyListEncoder().encode(zeroHostConfig) {
        try? data.write(to: zeroHostURL)
        check(inspectConfigFile(at: zeroHostURL).state == .usable,
              "inspectConfigFile treats zero-host config as usable rather than invalid")
    }

    // HostConfig & SMBShareConfig serialization (T003)
    let testShare = SMBShareConfig(name: "Data", smbURL: "smb://10.0.0.1/Data", mountPoint: "/Volumes/Data")
    let testHost = HostConfig(host: "10.0.0.1", alias: "My NAS", port: 445, timeoutMs: 1200, shares: [testShare])
    let multiHostConfig = AutomntConfig(version: automntVersion, hosts: [testHost])
    let multiHostURL = tempDir.appendingPathComponent("multi_host.plist")
    if let data = try? PropertyListEncoder().encode(multiHostConfig) {
        try? data.write(to: multiHostURL)
        let loaded = inspectConfigFile(at: multiHostURL).config
        check(loaded?.hosts.first?.alias == "My NAS", "HostConfig alias is preserved across plist encode/decode")
        check(loaded?.hosts.first?.port == 445 && loaded?.hosts.first?.timeoutMs == 1200, "HostConfig port and timeoutMs preserved across encode/decode")
    }

    // promptLineWithEsc non-TTY fallback & simulation (T006)
    mockLineInput = ""
    check(promptLineWithEsc(prompt: "", defaultValue: "default_fallback") == "default_fallback",
          "promptLineWithEsc returns defaultValue when input is empty")
    mockLineInput = "  Custom NAS  "
    check(promptLineWithEsc(prompt: "", defaultValue: "default_fallback") == "Custom NAS",
          "promptLineWithEsc trims and returns valid user input")
    mockLineInput = "\u{1B}"
    check(promptLineWithEsc(prompt: "") == nil,
          "promptLineWithEsc returns nil on Esc cancel")
    mockLineInput = nil

    // Feature 003 in-memory interaction component coverage
    check(TerminalUI.decodeArrowSequence(prefix: 91, suffix: 65) == .up, "CSI up arrow decodes")
    check(TerminalUI.decodeArrowSequence(prefix: 79, suffix: 66) == .down, "SS3 down arrow decodes")
    check(TerminalUI.decodeArrowSequence(prefix: 91, suffix: 67) == nil, "unsupported arrow suffix is ignored")
    TerminalUI.mockInputBytes = [27]
    TerminalUI.mockPendingInputResults = [false]
    TerminalUI.mockedPollTimeouts = []
    check(TerminalUI.readKey() == .escape, "readKey treats a lone Esc byte as cancellation")
    check(TerminalUI.mockedPollTimeouts == [50], "readKey probes a lone Esc byte with the 50 ms timeout")
    TerminalUI.mockInputBytes = [27, 91, 65]
    TerminalUI.mockPendingInputResults = [true, true]
    TerminalUI.mockedPollTimeouts = []
    check(TerminalUI.readKey() == .up, "readKey decodes a complete CSI arrow byte sequence")
    check(TerminalUI.mockedPollTimeouts == [50, 10], "arrow parsing uses the 50 ms and 10 ms bounded probes")
    TerminalUI.mockInputBytes = [27, 79, 66]
    TerminalUI.mockPendingInputResults = [true, true]
    check(TerminalUI.readKey() == .down, "readKey decodes a complete SS3 arrow byte sequence")
    TerminalUI.mockInputBytes = [27, 91]
    TerminalUI.mockPendingInputResults = [true, false]
    check(TerminalUI.readKey() == .escape, "readKey treats a truncated CSI arrow sequence as cancellation")
    TerminalUI.mockInputBytes = [27, 79]
    TerminalUI.mockPendingInputResults = [true, false]
    check(TerminalUI.readKey() == .escape, "readKey treats a truncated SS3 arrow sequence as cancellation")
    TerminalUI.mockInputBytes = nil
    TerminalUI.mockPendingInputResults = nil
    TerminalUI.mockedPollTimeouts = []
    TerminalUI.termiosTestMode = true
    TerminalUI.termiosLastRestoreMatchedOriginal = false
    TerminalUI.setRawMode(true)
    let rawControlChars = withUnsafeBytes(of: TerminalUI.mockRawTermios!.c_cc) { Array($0) }
    check(rawControlChars[Int(VMIN)] == 1 && rawControlChars[Int(VTIME)] == 0,
          "raw terminal mode sets VMIN=1 and VTIME=0")
    let originalTermiosBytes = TerminalUI.mockOriginalTermiosBytes
    TerminalUI.setRawMode(false)
    let restoredTermiosBytes = TerminalUI.mockTermiosOriginalAfterRestore.map {
        withUnsafeBytes(of: $0) { Array($0) }
    }
    check(TerminalUI.termiosLastRestoreMatchedOriginal && originalTermiosBytes == restoredTermiosBytes &&
          TerminalUI.mockOriginalTermios == nil,
          "terminal restoration restores the original termios snapshot")
    TerminalUI.termiosTestMode = false
    let fallbackOptions = [SelectionItem(id: "first", title: "First"),
                            SelectionItem(id: "second", title: "Second"),
                            SelectionItem(id: "disabled", title: "Disabled", isEnabled: false)]
    isTTYOverride = false
    TerminalUI.mockKeySequence = [.escape]
    check(promptInteractiveRadio(title: "escape repaint", options: fallbackOptions) == nil,
          "radio selection cancels with Escape after rendering")
    check(TerminalUI.lastRenderedLineCount == 0 && TerminalUI.lastRenderedVisibleRange == nil,
          "radio Escape clears its rendered frame")
    TerminalUI.mockKeySequence = [.escape]
    check(promptInteractiveCheckbox(title: "escape repaint", options: fallbackOptions) == nil,
          "checkbox selection cancels with Escape after rendering")
    check(TerminalUI.lastRenderedLineCount == 0 && TerminalUI.lastRenderedVisibleRange == nil,
          "checkbox Escape clears its rendered frame")
    let physicalViewport = RollingViewportState(totalCount: 2, capacity: 2, defaultIndex: 0)
    TerminalUI.lastRenderedLineCount = 0
    renderSelectionFrame(title: "line1\nline2\nline3", options: fallbackOptions,
                         viewport: physicalViewport, selected: [], explicit: false)
    check(TerminalUI.lastRenderedLineCount == 8,
          "frame line accounting counts embedded title newlines as physical lines")
    TerminalUI.lastRenderedLineCount = 5
    printSelectionNotice("\nnotice")
    check(TerminalUI.lastRenderedLineCount == 7,
          "notice output is compensated in frame line accounting")
    let captureURL = tempDir.appendingPathComponent("frame_tail_capture.txt")
    fflush(stdout)
    let savedStdout = dup(STDOUT_FILENO)
    freopen(captureURL.path, "w", stdout)
    renderSelectionFrame(title: "t", options: [SelectionItem(id: "a", title: "A")],
                         viewport: RollingViewportState(totalCount: 1, capacity: 1, defaultIndex: 0),
                         selected: [], explicit: false)
    clearSelectionFrame()
    fflush(stdout)
    dup2(savedStdout, STDOUT_FILENO)
    close(savedStdout)
    let capturedFrameOutput = (try? String(contentsOf: captureURL, encoding: .utf8)) ?? ""
    check(capturedFrameOutput.contains("\u{1B}[2K\n\u{1B}[2K\n\u{1B}[2A"),
          "repaint erases stale notice lines below the frame and returns the cursor")
    check(TerminalUI.lastRenderedLineCount == 0,
          "clear after notice-aware repaint leaves no frame state")
    TerminalUI.lastRenderedLineCount = 0
    TerminalUI.mockKeySequence = nil
    isTTYOverride = nil
    check(parseSelectionFallback("2, 1, 9, nope", options: fallbackOptions, multiple: true) == [1, 0],
          "non-TTY multi-selection fallback filters invalid and disabled indices")
    isTTYOverride = false
    mockLineInputs = ["2"]
    check(promptInteractiveRadio(title: "fallback radio", options: fallbackOptions) == 1,
          "non-TTY radio fallback reads and selects a numbered line")
    mockLineInputs = ["2, 1, 2"]
    check(promptInteractiveCheckbox(title: "fallback checkbox", options: fallbackOptions) == [1, 0],
          "non-TTY checkbox fallback reads a line and deduplicates numbered selections")
    mockLineInputs = [""]
    check(promptInteractiveRadio(title: "fallback cancel", options: fallbackOptions) == nil,
          "non-TTY fallback treats an empty input line as cancellation")
    mockLineInputs = nil
    isTTYOverride = nil

    let interactiveOptions = [SelectionItem(id: "first", title: "First"),
                              SelectionItem(id: "second", title: "Second"),
                              SelectionItem(id: "disabled", title: "Disabled", isEnabled: false)]
    isTTYOverride = false
    TerminalUI.mockKeySequence = [.down, .enter]
    check(promptInteractiveRadio(title: "radio", options: interactiveOptions) == 1,
          "in-memory radio selection follows cursor and Enter")
    TerminalUI.mockKeySequence = [.down, .space, .enter]
    check(promptInteractiveCheckbox(title: "checkbox", options: interactiveOptions, initiallySelected: [0]) == [0, 1],
          "in-memory checkbox toggles items and preserves initial selection")
    TerminalUI.mockKeySequence = [.selectAll, .enter]
    check(promptInteractiveCheckbox(title: "checkbox", options: interactiveOptions) == [0, 1],
          "checkbox select-all excludes disabled options")
    TerminalUI.mockKeySequence = [.selectAll, .selectAll, .enter]
    check(promptInteractiveCheckbox(title: "checkbox", options: interactiveOptions) == [],
          "checkbox select-all toggles between all and none")
    TerminalUI.mockKeySequence = [.down, .enter]
    check(promptExplicitConfirmation(title: "confirm", options: [SelectionItem(title: "Cancel"), SelectionItem(title: "Confirm")]) == nil,
          "explicit confirmation cancels when focus moves without Space")
    TerminalUI.mockKeySequence = [.down, .space, .enter]
    check(promptExplicitConfirmation(title: "confirm", options: [SelectionItem(title: "Cancel"), SelectionItem(title: "Confirm")]) == 1,
          "explicit confirmation requires Space before Enter")
    TerminalUI.mockKeySequence = [.enter]
    check(promptExplicitConfirmation(title: "confirm", options: [SelectionItem(title: "Cancel"), SelectionItem(title: "Confirm")]) == nil,
          "explicit confirmation defaults to safe cancellation")

    let longSelection = (0..<20).map { SelectionItem(id: "item:\($0)", title: "Item \($0)") }
    TerminalUI.mockKeySequence = Array(repeating: .down, count: 12) + [.enter]
    _ = promptInteractiveRadio(title: "long list", options: longSelection)
    check(TerminalUI.lastRenderedVisibleRange == 1..<13,
          "rolling selection viewport scrolls while keeping cursor visible")
    TerminalUI.mockKeySequence = nil
    isTTYOverride = nil

    // 15. User Story 1 Tests (T009 - T013)
    let mockMount1 = DiscoveredMount(
        mountPoint: "/Volumes/Public-1",
        rawSmbUrl: "smb://192.168.1.100/Public",
        host: "192.168.1.100",
        shareName: "Public",
        cleanMountPoint: "/Volumes/Public",
        standardSMBURL: "smb://192.168.1.100/Public"
    )
    let mockMount2 = DiscoveredMount(
        mountPoint: "/Volumes/data-1",
        rawSmbUrl: "smb://192.168.1.100/data-1",
        host: "192.168.1.100",
        shareName: "data-1",
        cleanMountPoint: "/Volumes/data-1",
        standardSMBURL: "smb://192.168.1.100/data-1"
    )
    let mockGroup = DiscoveredHostGroup(host: "192.168.1.100", mounts: [mockMount1, mockMount2], isConfigured: false)

    // Test drill-down configuration via handleCandidateHostConfiguration
    // Inputs: alias; mounted shares default to all-selected; Enter batch-submits (no confirm step).
    mockLineInputs = ["家庭 NAS"]
    TerminalUI.mockKeySequence = [.enter]
    let drilledHost = handleCandidateHostConfiguration(candidate: mockGroup)
    TerminalUI.mockKeySequence = nil
    check(drilledHost != nil, "handleCandidateHostConfiguration succeeds with valid inputs")
    check(drilledHost?.alias == "家庭 NAS", "HostConfig alias is recorded properly")
    check(drilledHost?.shares.count == 2, "Both candidate mounts selected")
    check(drilledHost?.shares[0].mountPoint == "/Volumes/Public", "Derived mount point is /Volumes/Public without -1 suffix")
    check(drilledHost?.shares[1].mountPoint == "/Volumes/data-1", "Legal data-1 mount point strictly preserved")

    // Test skip host branch in runInitWizard with menu key sequences.
    let initWizardURL = tempDir.appendingPathComponent("init_wizard_skip.plist")
    configURLOverride = initWizardURL
    mockCandidateHosts = [mockGroup]
    TerminalUI.mockKeySequence = [.down, .down, .enter, .enter, .down, .enter]
    let initSuccess = runInitWizard(offerServiceInstallation: true)
    TerminalUI.mockKeySequence = nil
    check(initSuccess, "runInitWizard completes successfully when skipping hosts")
    let skippedConfig = inspectConfigFile(at: initWizardURL).config
    check(skippedConfig?.hosts.isEmpty == true, "Skipped wizard produces a valid 0-host configuration")
    check(skippedConfig?.updateChannel == "off", "Update channel defaults to off")

    let manualAliasEscapeURL = tempDir.appendingPathComponent("manual_alias_escape.plist")
    configURLOverride = manualAliasEscapeURL
    mockCandidateHosts = [mockGroup]
    mockLineInputs = ["manual.example.invalid", "\u{1B}"]
    var manualAliasEscapeProbeCount = 0
    HostReachabilityProbe.testOverride = { _, _, _ in
        manualAliasEscapeProbeCount += 1
        return true
    }
    TerminalUI.mockKeySequence = [.down, .enter, .down, .down, .enter, .enter, .down, .enter]
    check(runInitWizard(offerServiceInstallation: true),
          "manual host alias Escape returns to host selection and allows completing the wizard")
    check(manualAliasEscapeProbeCount == 0,
          "manual host alias Escape does not probe the host or request a share path")
    check(inspectConfigFile(at: manualAliasEscapeURL).config?.hosts.isEmpty == true,
          "manual alias Escape stages no partial host configuration")
    TerminalUI.mockKeySequence = nil
    mockLineInputs = nil
    HostReachabilityProbe.testOverride = nil

    let wizardBacktrackURL = tempDir.appendingPathComponent("init_wizard_backtrack.plist")
    configURLOverride = wizardBacktrackURL
    mockCandidateHosts = [mockGroup]
    mockLineInputs = [""]
    TerminalUI.mockKeySequence = [
        .enter, .enter,
        .down, .enter,
        .escape,
        .down, .enter,
        .down, .enter,
        .escape,
        .down, .enter,
        .down, .enter
    ]
    check(runInitWizard(offerServiceInstallation: true),
          "wizard Escape returns from policy to hosts and from deployment to policy")
    let backtrackedConfig = inspectConfigFile(at: wizardBacktrackURL).config
    check(backtrackedConfig?.hosts.count == 1 && backtrackedConfig?.hosts[0].host == mockGroup.host,
          "wizard policy and deployment backtracking preserves staged host configuration")
    check(backtrackedConfig?.updateChannel == "notify",
          "wizard accepts an update policy after repeated Escape backtracking")
    TerminalUI.mockKeySequence = nil
    mockLineInputs = nil

    let canceledInitURL = tempDir.appendingPathComponent("init_wizard_cancelled.plist")
    configURLOverride = canceledInitURL
    mockCandidateHosts = [mockGroup]
    TerminalUI.mockKeySequence = [.down, .down, .enter, .enter, .escape]
    check(!runInitWizard(offerServiceInstallation: true), "wizard EOF after deployment Escape cancels setup")
    TerminalUI.mockKeySequence = nil
    check(!FileManager.default.fileExists(atPath: canceledInitURL.path),
          "wizard cancellation before completion does not persist a config")

    configURLOverride = nil
    mockCandidateHosts = nil
    mockLineInputs = nil

    // 16. User Story 2 Tests (T014, T015)
    check(deriveStandardMountPoint(from: "smb://fileserver/Public-1") == "/Volumes/Public-1", "SMB URL with literal Public-1 is treated as standard /Volumes/Public-1")
    check(deriveStandardMountPoint(from: "smb://fileserver/Backup-2") == "/Volumes/Backup-2", "SMB URL with literal Backup-2 is treated as standard /Volumes/Backup-2")
    check(deriveStandardMountPoint(from: "smb://host/Shared%20Folder") == "/Volumes/Shared Folder", "Spaces in URL decoded cleanly")

    // 17. User Story 3 Tests (T016 - T019)
    var testHostMgmt = HostConfig(host: "192.168.1.100", alias: "Home NAS", shares: [
        SMBShareConfig(name: "Public", smbURL: "smb://192.168.1.100/Public", mountPoint: "/Volumes/Public")
    ])
    let configuredShareOptions = hostShareManagementOptions(for: testHostMgmt)
    check(configuredShareOptions.first?.id == testHostMgmt.shares[0].smbURL &&
          configuredShareOptions.first?.isEnabled == false,
          "configured share rows are informational and disabled")
    TerminalUI.mockKeySequence = [.up, .enter, .down, .enter, .escape]
    check(promptInteractiveRadio(title: "configured share disabled", options: configuredShareOptions) == 1,
          "radio selection skips configured share rows and activates the next enabled action")
    TerminalUI.mockKeySequence = nil

    // Test staged share removal through the interactive menu and checkbox.
    TerminalUI.mockKeySequence = [.down, .enter, .space, .enter,
                                  .down, .down, .down, .enter]
    manageHostShares(hostConfig: &testHostMgmt, allHosts: [testHostMgmt])
    TerminalUI.mockKeySequence = nil
    check(testHostMgmt.shares.isEmpty, "manageHostShares successfully removes selected share")

    // Test duplicate share detection and prevention
    testHostMgmt.shares = [SMBShareConfig(name: "Public", smbURL: "smb://192.168.1.100/Public", mountPoint: "/Volumes/Public")]
    mockLineInputs = ["smb://192.168.1.100/Public"]
    TerminalUI.mockKeySequence = [.down, .enter, .down, .enter,
                                  .down, .down, .down, .down, .enter]
    manageHostShares(hostConfig: &testHostMgmt, allHosts: [testHostMgmt])
    TerminalUI.mockKeySequence = nil
    check(testHostMgmt.shares.count == 1, "Duplicate share is ignored by manageHostShares")
    mockLineInputs = nil

    // 18. User Story 4 Tests (T020 - T022)
    mockLineInputs = ["\u{1B}"]
    check(promptLineWithEsc(prompt: "Test: ") == nil, "promptLineWithEsc via mockLineInputs returns nil on Esc key")
    mockLineInputs = ["   sequence test   "]
    check(promptLineWithEsc(prompt: "Test: ") == "sequence test", "promptLineWithEsc via mockLineInputs trims surrounding whitespace")
    mockLineInputs = [""]
    check(promptLineWithEsc(prompt: "Test: ", defaultValue: "seq_fallback") == "seq_fallback", "promptLineWithEsc via mockLineInputs returns fallback on empty input")
    mockLineInputs = nil

    // 19. User Story 5 Tests (T023, T024)
    let emptyHostsConfig = AutomntConfig(version: automntVersion, updateChannel: "off", hosts: [], profiles: [])
    let emptyHostsURL = tempDir.appendingPathComponent("empty_hosts.plist")
    check(saveConfig(emptyHostsConfig, to: emptyHostsURL), "0-host config saved successfully")
    let emptyInspection = inspectConfigFile(at: emptyHostsURL)
    check(emptyInspection.state == .usable, "0-host config inspected as .usable")
    check(emptyInspection.config?.hosts.isEmpty == true, "Loaded config has 0 hosts")

    // 20. User Story 6 Tests (T025, T026)
    let legacyProfile = NetworkProfile(
        id: "office_lan",
        description: "Office Direct",
        host: "office.local",
        port: 445,
        timeoutMs: 1500,
        preventSpotlightIndex: true,
        targets: [
            MountTarget(url: "smb://office.local/Finance", mountPath: "/Volumes/Finance-1")
        ]
    )
    var legacyConfig = AutomntConfig(
        version: "3.0.0",
        updateChannel: "off",
        retryPolicy: RetryPolicy(),
        hosts: [],
        profiles: [legacyProfile]
    )
    let legacyMigrationURL = tempDir.appendingPathComponent("legacy_v300_migration.plist")
    check(saveConfig(legacyConfig, to: legacyMigrationURL), "Legacy config written to file")
    check(configNeedsMigration(legacyConfig), "Legacy config with profiles requires migration")
    check(migrateConfigIfNeeded(config: &legacyConfig, at: legacyMigrationURL), "migrateConfigIfNeeded succeeds")
    check(legacyConfig.version == automntVersion, "Migrated config version is updated to current")
    check(legacyConfig.hosts.count == 1, "Profiles converted to hosts")
    check(legacyConfig.hosts[0].host == "office.local", "Host address preserved")
    check(legacyConfig.hosts[0].alias == "Office Direct", "Description mapped to alias")
    check(legacyConfig.hosts[0].shares.count == 1, "Shares preserved")
    check(legacyConfig.hosts[0].shares[0].mountPoint == "/Volumes/Finance", "Historical -1 suffix cleaned to /Volumes/Finance")
    check(legacyConfig.profiles.isEmpty, "Legacy profiles array emptied after migration")

    // Feature 003 convergence coverage: exercise configuration workflows through the public menus.
    let managementHostA = HostConfig(host: "first.example")
    let managementHostB = HostConfig(host: "second.example")
    func runManagementScenario(_ name: String, hosts: [HostConfig], keys: [KeyAction]) -> (URL, AutomntConfig?) {
        let url = tempDir.appendingPathComponent("management_\(name).plist")
        let initial = AutomntConfig(version: automntVersion, updateChannel: "off", hosts: hosts)
        check(saveConfig(initial, to: url), "management \(name) fixture is written through the program API")
        configURLOverride = url
        isTTYOverride = false
        TerminalUI.mockKeySequence = keys
        manageConfiguration()
        TerminalUI.mockKeySequence = nil
        isTTYOverride = nil
        configURLOverride = nil
        return (url, loadConfig(from: url))
    }

    let (reorderedURL, reorderedConfig) = runManagementScenario(
        "reorder_success",
        hosts: [managementHostA, managementHostB],
        keys: [.down, .down, .down, .enter, .down, .enter, .enter] +
              Array(repeating: .down, count: 6) + [.enter]
    )
    check(reorderedConfig?.hosts.map(\.host) == [managementHostB.host, managementHostA.host],
          "configuration menu reorders a selected host to the chosen priority and saves it")
    _ = reorderedURL

    let (sourceCancelURL, sourceCancelConfig) = runManagementScenario(
        "reorder_source_cancel",
        hosts: [managementHostA, managementHostB],
        keys: [.down, .down, .down, .enter, .escape, .escape]
    )
    check(sourceCancelConfig?.hosts.map(\.host) == [managementHostA.host, managementHostB.host],
          "Esc while choosing the source host leaves priority unchanged")
    _ = sourceCancelURL

    let (destinationCancelURL, destinationCancelConfig) = runManagementScenario(
        "reorder_destination_cancel",
        hosts: [managementHostA, managementHostB],
        keys: [.down, .down, .down, .enter, .enter, .escape, .escape]
    )
    check(destinationCancelConfig?.hosts.map(\.host) == [managementHostA.host, managementHostB.host],
          "Esc while choosing the destination leaves priority unchanged")
    _ = destinationCancelURL

    func hostDeletionKeys(confirmation: [KeyAction]) -> [KeyAction] {
        Array(repeating: .down, count: 4) + [.enter, .enter] + confirmation
    }
    for (name, confirmation) in [
        ("delete_enter_cancel", [KeyAction.enter]),
        ("delete_focus_cancel", [.down, .enter]),
        ("delete_escape_cancel", [.escape])
    ] {
        let (url, result) = runManagementScenario(
            name,
            hosts: [managementHostA, managementHostB],
            keys: hostDeletionKeys(confirmation: confirmation + [.escape])
        )
        check(result?.hosts.map(\.host) == [managementHostA.host, managementHostB.host],
              "host deletion \(name) leaves the persisted config unchanged")
        _ = url
    }

    let (hostDeleteURL, hostDeleteConfig) = runManagementScenario(
        "delete_confirmed",
        hosts: [managementHostA, managementHostB],
        keys: hostDeletionKeys(confirmation: [.down, .space, .enter] +
                               Array(repeating: .down, count: 5) + [.enter])
    )
    check(hostDeleteConfig?.hosts.map(\.host) == [managementHostB.host],
          "host deletion requires Space and Enter, then persists on Save and exit")
    _ = hostDeleteURL

    func clearAllKeys(confirmation: [KeyAction]) -> [KeyAction] {
        Array(repeating: .down, count: 4) + [.enter] + Array(repeating: .down, count: 2) +
        [.enter] + confirmation
    }
    for (name, confirmation) in [
        ("clear_all_enter_cancel", [KeyAction.enter]),
        ("clear_all_focus_cancel", [.down, .enter]),
        ("clear_all_escape_cancel", [.escape])
    ] {
        let (url, result) = runManagementScenario(
            name,
            hosts: [managementHostA, managementHostB],
            keys: clearAllKeys(confirmation: confirmation + [.escape])
        )
        check(result?.hosts.map(\.host) == [managementHostA.host, managementHostB.host],
              "clear-all \(name) leaves the persisted config unchanged")
        _ = url
    }

    let (clearAllURL, clearAllConfig) = runManagementScenario(
        "clear_all_confirmed",
        hosts: [managementHostA, managementHostB],
        keys: clearAllKeys(confirmation: [.down, .space, .enter] +
                           Array(repeating: .down, count: 4) + [.enter])
    )
    check(clearAllConfig?.hosts.isEmpty == true,
          "clearing all hosts requires Space and Enter, then persists on Save and exit")
    _ = clearAllURL

    // Configuration session staging: Esc discards, explicit Save writes atomically
    let stagedConfigURL = tempDir.appendingPathComponent("staged_config.plist")
    let stagedHost = HostConfig(host: "stage.example", shares: [])
    let persistedConfig = AutomntConfig(version: automntVersion, updateChannel: "off", hosts: [stagedHost])
    check(saveConfig(persistedConfig, to: stagedConfigURL), "management staging fixture saved through program API")
    let originalConfigBytes = try? Data(contentsOf: stagedConfigURL)
    configURLOverride = stagedConfigURL
    isTTYOverride = false
    TerminalUI.mockKeySequence = [.down, .down, .down, .down, .enter,
                                  .down, .enter, .escape]
    manageConfiguration()
    let discardedConfigBytes = try? Data(contentsOf: stagedConfigURL)
    check(discardedConfigBytes == originalConfigBytes, "management Escape discards staged session changes")

    TerminalUI.mockKeySequence = [.down, .down, .down, .down, .enter,
                                  .down, .enter,
                                  .down, .down, .down, .down, .down, .enter]
    manageConfiguration()
    check(inspectConfigFile(at: stagedConfigURL).config?.updateChannel == "notify",
          "management Save and exit persists staged changes")
    TerminalUI.mockKeySequence = nil
    isTTYOverride = nil
    configURLOverride = nil

    print("\nSelf-tests: \(passed) passed, \(skipped) skipped, \(failed) failed")
    return failed == 0
}

func printUsage() {
    print(tr("""
    用法: automnt [选项]

    选项:
      --init [--reset]            运行交互式初始化配置向导 (--reset 重置现有配置)
      --config                    运行日常配置管理菜单 (管理挂载目标、网络策略、更新信道)
      --install                   部署并激活当前用户的 LaunchAgent 自启动服务
      --uninstall [--purge]       卸载自启动服务与 CLI (--purge 连同配置文件与日志彻底清理)
      --status                    查看当前安装状态、守护服务运行状态与挂载详情
      --update                    检查并升级软件至最新版本 (免编译下载预编译二进制)
      --self-test                 运行内置全量自动化自测试套件
      --version, -v               查看当前软件版本号
      --help, -h                  显示帮助说明

    环境变量:
      AUTOMNT_LANG=zh|en          显式指定终端界面语言 (默认自适应系统语言)
    """, """
    Usage: automnt [options]

    Options:
      --init [--reset]            Run setup wizard (--reset rebuilds existing config)
      --config                    Daily configuration menu (shares, profiles, updates)
      --install                   Deploy and activate user LaunchAgent daemon
      --uninstall [--purge]       Uninstall daemon and CLI entry (--purge deletes config and logs)
      --status                    Show service status and active mount details
      --update                    Check and self-update to latest prebuilt release
      --self-test                 Run full automated test suite
      --version, -v               Show software version
      --help, -h                  Show this help message

    Environment Variables:
      AUTOMNT_LANG=zh|en          Explicitly set terminal UI language
    """))
}

// MARK: - 主流程执行逻辑 (Main Entry Point)

func main() {
    let args = CommandLine.arguments

    if args.contains("--self-test") {
        let success = runSelfTests(includeNetworkChecks: args.contains("--network"))
        exit(success ? 0 : 1)
    }

    if args.count > 1 {
        let first = args[1]
        if first == "--version" || first == "-v" {
            print(automntVersion)
            exit(0)
        }
        if first == "--help" || first == "-h" {
            printUsage()
            exit(0)
        }
    }

    let architectureResult = runCommand(executable: "/usr/bin/uname", arguments: ["-m"])
    let architecture = architectureResult.status == 0 ? architectureResult.stdout : "unknown"
    let platformIssue = platformSupportIssue(
        macOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        architecture: architecture
    )
    if let platformIssue {
        if platformIssue == "architecture" {
            fputs(tr("✗ automnt 仅支持 Apple silicon (arm64)；当前架构：\(architecture)。\n",
                     "✗ automnt supports Apple silicon (arm64) only; current architecture: \(architecture).\n"), stderr)
        } else {
            fputs(tr("✗ automnt 需要 macOS 27.0 或更高版本；当前系统：\(ProcessInfo.processInfo.operatingSystemVersionString)。\n",
                     "✗ automnt requires macOS 27.0 or later; current system: \(ProcessInfo.processInfo.operatingSystemVersionString).\n"), stderr)
        }
        exit(1)
    }

    // 自搬迁安装与首次运行引导 (US1)
    let justRelocated = InstallationManager.relocateIfNeeded()
    if justRelocated {
        InstallationManager.injectShellEntry()
        print(tr("✓ 成功安装 automnt 到规范目录: \(getActiveInstalledBinaryURL().path)",
                 "✓ Successfully installed automnt to canonical path: \(getActiveInstalledBinaryURL().path)"))
        print(tr("✓ 原下载临时副本已安全清理", "✓ Cleaned up temporary download copy"))
        print(tr("✓ 已配置命令行入口，可在新终端窗口直接运行: automnt",
                 "✓ Configured CLI entry point; run directly in new terminal: automnt"))
    } else {
        // 自检与自愈 (US8)
        let state = InstallState.current()
        if state.isRelocated && !state.isHealthy {
            _ = state.healIfNeeded()
            let afterState = InstallState.current()
            if !afterState.isHealthy {
                fputs(tr("⚠ 警告: 当前安装状态不完整。\n若需完全恢复，建议运行: automnt --install\n",
                         "⚠ Warning: Installation state degraded.\nRecommended repair command: automnt --install\n"), stderr)
            }
        }
    }

    if args.count > 1 {
        let arg = args[1]
        switch arg {
        case "--init":
            guard args.count == 2 || (args.count == 3 && args[2] == "--reset") else {
                fputs(tr("✗ 用法: automnt --init [--reset]\n", "✗ Usage: automnt --init [--reset]\n"), stderr)
                exit(2)
            }
            let succeeded = runInitCommand(resetExistingConfig: args.count == 3)
            exit(succeeded ? 0 : 1)
        case "--config":
            manageConfiguration()
            exit(0)
        case "--install":
            installLaunchAgent()
            exit(0)
        case "--uninstall":
            let purge = args.contains("--purge")
            uninstallLaunchAgent(purge: purge)
            exit(0)
        case "--status":
            checkServiceStatus()
            exit(0)
        case "--update":
            handleManualUpdateCommand()
            exit(0)
        default:
            fputs(tr("✗ 未知参数: '\(arg)'\n\n", "✗ Unknown option: '\(arg)'\n\n"), stderr)
            printUsage()
            exit(1)
        }
    }

    print(tr("""
    automnt (v\(automntVersion))
    ======================
    """, """
    automnt (v\(automntVersion))
    ======================
    """))

    let inspection = inspectConfigFile(at: getActiveConfigURL())
    if inspection.state == .missing {
        if isInteractiveTerminal() {
            print(tr("未检测到有效配置文件，正在自动启动初始化配置向导...\n",
                     "No valid configuration found. Starting setup wizard...\n"))
            let initSucceeded = runInitCommand()
            if !initSucceeded {
                writeLog("Init wizard canceled or failed, exiting with status 1")
                exit(1)
            }
        } else {
            fputs(tr("✗ 未找到有效配置，请在终端中运行 'automnt --init' 初始化。\n",
                     "✗ Configuration not found. Please run 'automnt --init' first.\n"), stderr)
            writeLog("Config missing, exiting with status 2")
            exit(2)
        }
    } else if inspection.state == .invalid {
        fputs(tr("✗ 配置文件损坏或无法解析，请检查配置或运行 'automnt --init' 重新生成。\n",
                 "✗ Configuration is corrupted or invalid. Please check configuration or run 'automnt --init'.\n"), stderr)
        writeLog("Config invalid: \(inspection.diagnostic ?? "unknown error"), exiting with status 2")
        exit(2)
    }

    guard var config = loadConfig() else {
        fputs(tr("✗ 无法读取配置文件，退出。\n", "✗ Unable to read config, exiting.\n"), stderr)
        writeLog("Unable to load config, exiting with status 2")
        exit(2)
    }

    // 检查 0 台主机合法空配置状态 (Safe Dormant Sleep)
    if config.hosts.isEmpty {
        let sleepMsgZh = "当前未配置任何主机，automnt 保持安全休眠状态。"
        let sleepMsgEn = "No hosts configured. automnt remains in safe dormant sleep state."
        print(tr(sleepMsgZh, sleepMsgEn))
        writeLog("No hosts configured; safe dormant sleep state entered, exiting with status 0")
        exit(0)
    }

    // 顺序评估主机顺位探测 (Host-based Priority Probing)
    print(tr("\n[1] 顺序评估主机顺位探测...", "\n[1] Evaluating host priority probing..."))
    var matchedHost: HostConfig?

    for (idx, hostConfig) in config.hosts.enumerated() {
        guard hostConfig.enabled else {
            print(tr("  跳过已禁用的主机 [\(idx + 1)] '\(hostConfig.host)'",
                     "  Skipping disabled host [\(idx + 1)] '\(hostConfig.host)'"))
            continue
        }
        let hostDisplay = hostConfig.alias.map { "'\($0)' (\(hostConfig.host))" } ?? "'\(hostConfig.host)'"
        print(tr("  正在校验顺位 [\(idx + 1)] \(hostDisplay):",
                 "  Checking priority [\(idx + 1)] \(hostDisplay):"))

        let host = hostConfig.host
        let port = hostConfig.port
        let timeout = hostConfig.timeoutMs
        let retryRunner = EvaluationRetryRunner(policy: config.retryPolicy ?? RetryPolicy())

        print(tr("    正在探测 TCP 端口 \(port): \(host) (超时: \(timeout)ms)...",
                 "    Probing TCP port \(port) on \(host) (timeout: \(timeout)ms)..."))

        let reachable = retryRunner.run {
            HostReachabilityProbe.canConnect(host: host, port: port, timeoutMs: timeout)
        }

        if reachable {
            print(tr("    ✓ 顺位命中！(目标 \(host):\(port) 可达)",
                     "    ✓ Matched! (Host \(host):\(port) is reachable)"))
            matchedHost = hostConfig
            break // 强排他性短路：首个通畅则立即停止后续探测
        } else {
            print(tr("    ✗ 目标 \(host):\(port) 不可达，评估下一顺位。",
                     "    ✗ Target \(host):\(port) unreachable, falling back to next host."))
        }
    }

    guard let host = matchedHost else {
        print(tr("\n[DONE] 当前网络状态未匹配到任何可用主机。正常退出。",
                 "\n[DONE] No matching host reachable for current network state. Exiting cleanly."))
        writeLog("No matching host reachable for current network, exiting with status 2")
        triggerBackgroundUpdateCheckIfNeeded(config: &config)
        exit(2)
    }

    let hostTitle = host.alias.map { "\($0) (\(host.host))" } ?? host.host
    print(tr("\n[2] 执行挂载命中主机: \(hostTitle)", "\n[2] Executing mounts for active host: \(hostTitle)"))
    writeLog("Executing mounts for host: \(host.host)")

    var mountedCount = 0
    var failedCount = 0
    for share in host.shares {
        guard share.enabled else {
            print(tr("  跳过已禁用共享: \(share.mountPoint)", "  Skipping disabled share: \(share.mountPoint)"))
            continue
        }
        print(tr("  目标: \(share.mountPoint) (\(redactedSMBURL(share.smbURL)))",
                 "  Target: \(share.mountPoint) (\(redactedSMBURL(share.smbURL)))"))

        let status = ensureMountPointReady(target: MountTarget(url: share.smbURL, mountPath: share.mountPoint))
        switch status {
        case .alreadyMountedHealthy:
            print(tr("    ✓ 卷宗已挂载且响应正常，跳过。", "    ✓ Already mounted and responsive, skipping."))
            mountedCount += 1
            continue

        case .readyToMount:
            print(tr("    正在通过 NetFS 系统框架静默挂载...", "    Mounting volume via NetFS..."))
            if silentMount(urlString: share.smbURL, mountPath: share.mountPoint) {
                mountedCount += 1
                if host.preventSpotlightIndex {
                    disableSpotlightIndex(at: share.mountPoint)
                }
            } else {
                failedCount += 1
                fputs(tr("    ✗ 挂载失败，请检查网络连通性或钥匙串凭据。\n",
                         "    ✗ Mount failed. Check network or Keychain credentials.\n"), stderr)
            }

        case .unmountFailed:
            print(tr("    ✗ 挂载点繁忙或无法清除，跳过此目标。", "    ✗ Mount point busy or cannot be cleared, skipping."))
            failedCount += 1
        }
    }

    print(tr("\n[DONE] 主机 '\(hostTitle)' 下已成功挂载 \(mountedCount)/\(host.shares.count) 个卷宗。",
             "\n[DONE] \(mountedCount)/\(host.shares.count) volumes mounted under '\(hostTitle)'."))
    writeLog("Finished execution of '\(host.host)': \(mountedCount)/\(host.shares.count) mounted.")
    triggerBackgroundUpdateCheckIfNeeded(config: &config)
    if failedCount > 0 {
        writeLog("Mount evaluation failed for \(failedCount) configured target(s).")
        exit(2)
    }
}

main()
