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

#if canImport(AutomntCore)
import AutomntCore
#endif

var automntVersion: String { AutomntBuildVersion.value }

import Foundation
import SystemConfiguration
import NetFS
import Darwin
import Security
import Synchronization
import DiskArbitration

// MARK: - Swift 6 并发安全注入原语

/// 进程级共享可变状态的并发安全载体（Swift 6 语言模式）。
///
/// 这些测试注入点与终端状态历史上是裸 `var`/`static var`；现在一律由 `Mutex`
/// 承载，保持原有的同步读写语义（同一进程内读改写都在锁内完成），且不使用
/// `nonisolated(unsafe)` 或 `@unchecked Sendable` 绕过检查。
///
/// 载荷受 `Sendable` 约束：这正是旧裸全局所缺乏的保证。
/// 仅测试期注入的非 `Sendable` 闭包由既有 `CLIThreadValue`（线程局部）承载。
final class LockedBox<Value: Sendable>: Sendable {
    private let storage: Mutex<Value>
    init(_ initial: Value) { storage = Mutex(initial) }
    var value: Value {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}

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

/// 自测注入：活动配置路径覆盖（`Mutex` 承载，保持既有的同步读写语义）。
private let configURLOverrideBox = LockedBox<URL?>(nil)
var configURLOverride: URL? {
    get { configURLOverrideBox.value }
    set { configURLOverrideBox.value = newValue }
}
/// 自测注入：交互终端判定覆盖。
private let isTTYOverrideBox = LockedBox<Bool?>(nil)
var isTTYOverride: Bool? {
    get { isTTYOverrideBox.value }
    set { isTTYOverrideBox.value = newValue }
}

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

/// 子进程输出缓冲：用 `Mutex` 表达内部同步，故无需 `@unchecked Sendable`。
final class CommandOutputBuffer: Sendable {
    private struct Captured: Sendable {
        var standardOutput = Data()
        var standardError = Data()
    }
    private let storage = Mutex(Captured())

    func storeStandardOutput(_ data: Data) {
        storage.withLock { $0.standardOutput = data }
    }

    func storeStandardError(_ data: Data) {
        storage.withLock { $0.standardError = data }
    }

    func snapshot() -> (standardOutput: Data, standardError: Data) {
        storage.withLock { ($0.standardOutput, $0.standardError) }
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
    timeout: TimeInterval,
    standardOutputFile: FileHandle? = nil,
    standardErrorFile: FileHandle? = nil
) -> BoundedCommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = standardOutputFile ?? FileHandle.nullDevice
    process.standardError = standardErrorFile ?? FileHandle.nullDevice
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

    // Process.terminate() may synchronize with Foundation task state.
    // Signal directly so a child blocked in SMB kernel I/O cannot delay the caller.
    _ = kill(process.processIdentifier, SIGTERM)
    if waitGroup.wait(timeout: .now() + 0.5) == .timedOut {
        _ = kill(process.processIdentifier, SIGKILL)
        return BoundedCommandResult(status: nil, timedOut: true, processStopped: false, error: nil)
    }
    return BoundedCommandResult(status: process.terminationStatus, timedOut: true,
                               processStopped: true, error: nil)
}

// MARK: - 版本与数据结构定义

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
        let lock = try StableFileLock(url: url.deletingLastPathComponent().appendingPathComponent("config.lock"))
        data = try withExtendedLifetime(lock) { try PrivateAtomicFile.read(url) }
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
    guard Darwin.rename(tempURL.path, url.path) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

/// 安装前验证系统信任的签名；升级还须满足已安装程序的指定要求。
/// 在执行下载产物的 --version 之前调用，避免先运行未经验证的代码。
enum BinarySigningPolicy {
    static func trustedCode(at url: URL) -> SecStaticCode? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var trust: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic and identifier \"automnt\" and (certificate leaf[field.1.2.840.113635.100.6.1.13] exists or certificate leaf[field.1.2.840.113635.100.6.1.12] exists)" as CFString, [], &trust) == errSecSuccess,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), trust) == errSecSuccess else { return nil }
        return code
    }

    static func permitsReplacement(candidate: URL, installed: URL?) -> Bool {
        guard let newCode = trustedCode(at: candidate) else { return false }
        guard let installed, FileManager.default.fileExists(atPath: installed.path) else { return true }
        guard let oldCode = trustedCode(at: installed) else { return false }
        var existingRequirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(oldCode, [], &existingRequirement) == errSecSuccess,
              let existingRequirement else { return false }
        return SecStaticCodeCheckValidity(newCode, SecCSFlags(rawValue: kSecCSStrictValidate), existingRequirement) == errSecSuccess
    }
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
            guard Darwin.rename(tempStaged.path, replacement.destinationURL.path) == 0 else {
                let renameError = errno
                try? FileManager.default.removeItem(at: tempStaged)
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(renameError))
            }
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

/// Preserve explicit custom locations. Only legacy numeric conflict suffixes directly
/// under /Volumes are normalized; a share whose real name ends in a number is intact.
func migratedMountPoint(url: String, path: String) -> String {
    guard let standard = deriveStandardMountPoint(from: url), path != standard,
          path.hasPrefix(standard + "-") else { return path }
    let suffix = String(path.dropFirst(standard.count + 1))
    guard !suffix.isEmpty, suffix.allSatisfy({ $0.isASCII && $0.isNumber }) else { return path }
    return standard
}

func configNeedsMigration(_ config: AutomntConfig) -> Bool {
    if config.version != automntVersion { return true }
    if config.updateChannel == nil { return true }
    if !config.profiles.isEmpty { return true }
    for host in config.hosts {
        for share in host.shares {
            if migratedMountPoint(url: share.smbURL, path: share.mountPoint) != share.mountPoint {
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

    // 存量 profiles 升舱为 hosts，保留用户配置的自定义路径。
    if !config.profiles.isEmpty {
        var migratedHosts: [HostConfig] = config.hosts
        for p in config.profiles {
            var shares: [SMBShareConfig] = []
            for t in p.targets {
                let cleanMount = migratedMountPoint(url: t.url, path: t.mountPath)
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
            if migratedMountPoint(url: share.smbURL, path: share.mountPoint) != share.mountPoint {
                config.hosts[hIdx].shares[sIdx].mountPoint = migratedMountPoint(url: share.smbURL, path: share.mountPoint)
                modified = true
            }
        }
    }

    guard modified else { return true }
    guard let migrationRevision = configurationDraftRevisions[configURL.standardizedFileURL.path],
          saveConfig(config, to: configURL, expectedRevision: migrationRevision) else {
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

// Track the exact bytes each draft read; protect even compatibility-mode callers.
// 用 `Mutex` 表达内部同步，故无需 `@unchecked Sendable`。
private final class ConfigurationDraftRevisionCache: Sendable {
    private let storage = Mutex<[String: ConfigRevision]>([:])
    @discardableResult
    func removeValue(forKey path: String) -> ConfigRevision? {
        storage.withLock { $0.removeValue(forKey: path) }
    }
    subscript(path: String) -> ConfigRevision? {
        get { storage.withLock { $0[path] } }
        set { storage.withLock { $0[path] = newValue } }
    }
}
private let configurationDraftRevisions = ConfigurationDraftRevisionCache()

func loadConfig(from configURL: URL? = nil, migrate: Bool = true) -> AutomntConfig? {
    let targetURL = configURL ?? getConfigURL()
    guard FileManager.default.fileExists(atPath: targetURL.path) else { return nil }
    guard let data = try? { () throws -> Data in
        let lock = try StableFileLock(url: targetURL.deletingLastPathComponent().appendingPathComponent("config.lock"))
        return try withExtendedLifetime(lock) { try PrivateAtomicFile.read(targetURL) }
    }(),
          (try? ConfigurationPrivacy.validate(PropertyListSerialization.propertyList(from: data, format: nil))) != nil else { return nil }
    configurationDraftRevisions[targetURL.standardizedFileURL.path] = ConfigurationRevision.of(data)
    let decoder = PropertyListDecoder()
    guard var config = try? decoder.decode(AutomntConfig.self, from: data) else { return nil }
    if migrate && configNeedsMigration(config) {
        guard migrateConfigIfNeeded(config: &config, at: targetURL) else { return nil }
    }
    return config
}

func saveConfig(
    _ config: AutomntConfig,
    to configURL: URL? = nil,
    preserveUnknownFields: Bool = true,
    expectedRevision: ConfigRevision? = nil,
    requireAbsent: Bool = false
) -> Bool {
    let resolvedURL = configURL ?? getConfigURL()
    do {
        let parentDir = resolvedURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
        let lock = try StableFileLock(url: parentDir.appendingPathComponent("config.lock"))
        try withExtendedLifetime(lock) {
            let key = resolvedURL.standardizedFileURL.path
            let expected = expectedRevision ?? configurationDraftRevisions[key]
            do {
                let existing = try PrivateAtomicFile.read(resolvedURL)
                guard !requireAbsent, let expected, ConfigurationRevision.of(existing) == expected else {
                    throw AutomntIssue.configurationConflict
                }
            } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == ENOENT {
                guard expected == nil else { throw AutomntIssue.configurationConflict }
            }
            let data: Data
            if preserveUnknownFields {
                data = try encodeConfigPreservingUnknownFields(config, at: resolvedURL)
            } else {
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .xml
                data = try encoder.encode(config)
            }
            try ConfigurationPrivacy.validate(PropertyListSerialization.propertyList(from: data, format: nil))
            guard ConfigurationValidation.problems(in: config).isEmpty else { throw AutomntIssue.invalidConfiguration }
            try PrivateAtomicFile.replace(data, at: resolvedURL)
            configurationDraftRevisions[key] = ConfigurationRevision.of(data)
        }
        print(tr("✓ 配置已即时保存至: \(resolvedURL.path)",
                 "✓ Config saved to: \(resolvedURL.path)"))
        return true
    } catch AutomntIssue.configurationConflict {
        fputs(tr("✗ 配置已被其他操作修改，或正被使用；本次输入仍保留。请退出后重新读取配置再编辑。\n", "✗ Configuration changed elsewhere or is in use. Your input is retained; exit and reload before editing again.\n"), stderr)
        return false
    } catch {
        fputs("✗ Failed to save config: \(error.localizedDescription)\n", stderr)
        writeLog("Failed to save config: \(error.localizedDescription)")
        return false
    }
}

// MARK: - 主机可达性探测器与网络辅助函数

struct HostReachabilityProbe {
    private static let testOverrideHook = CLIThreadValue<((String, Int, Int) -> Bool)?>()
    static var testOverride: ((String, Int, Int) -> Bool)? {
        get { testOverrideHook.get(or: nil) }
        set { testOverrideHook.set(newValue) }
    }

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
    let remaining = MountExecutionBudget.deadline?.timeIntervalSinceNow ?? timeoutSeconds
    guard remaining > 0 else { return false }
    let diskutilRes = runCommandDiscardingOutputWithTimeout(
        executable: "/usr/sbin/diskutil",
        arguments: ["unmount", "force", path],
        timeout: min(timeoutSeconds, remaining)
    )
    if diskutilRes.status == 0 {
        return true
    }
    let fallbackRemaining = MountExecutionBudget.deadline?.timeIntervalSinceNow ?? timeoutSeconds
    guard fallbackRemaining > 0 else { return false }
    let umountRes = runCommandDiscardingOutputWithTimeout(
        executable: "/sbin/umount",
        arguments: ["-f", path],
        timeout: min(timeoutSeconds, fallbackRemaining)
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
    let remaining = MountExecutionBudget.deadline?.timeIntervalSinceNow ?? 2
    guard remaining > 0 else { return }
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
    _ = runCommandDiscardingOutputWithTimeout(executable: executable,
        arguments: ["--internal-disable-spotlight", mountPath], timeout: min(remaining, 2))
}

func performDisableSpotlightIndex(at mountPath: String) {
    _ = runCommandDiscardingOutputWithTimeout(executable: "/usr/bin/mdutil",
        arguments: ["-i", "off", mountPath], timeout: 1)
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

func netFSOpenOptions() -> NSMutableDictionary {
    NSMutableDictionary(dictionary: [kNAUIOptionKey: kNAUIOptionNoUI])
}

enum VolumeHealthProbe {
    private static let testOverrideHook = CLIThreadValue<((String) -> Bool)?>()
    static var testOverride: ((String) -> Bool)? {
        get { testOverrideHook.get(or: nil) }
        set { testOverrideHook.set(newValue) }
    }
}

func boundedHostReachability(host: String, port: Int, timeoutMs: Int) -> Bool {
    let remaining = MountExecutionBudget.deadline?.timeIntervalSinceNow ?? 2
    guard remaining > 0 else { return false }
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
    let result = runCommandDiscardingOutputWithTimeout(executable: executable,
        arguments: ["--internal-host-probe", host, String(port), String(timeoutMs)],
        timeout: min(remaining, max(1, Double(timeoutMs) / 1000 + 0.5)))
    return !result.timedOut && result.status == 0
}

func boundedVolumeHealth(at path: String) -> Bool? {
    if let injected = VolumeHealthProbe.testOverride { return injected(path) }
    // 子进程的目录枚举不会把 SMB 阻塞传播到恢复主进程。
    let remaining = MountExecutionBudget.deadline?.timeIntervalSinceNow ?? 1
    guard remaining > 0 else { return nil }
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
    let result = runCommandDiscardingOutputWithTimeout(executable: executable,
        arguments: ["--internal-volume-health", path], timeout: min(remaining, 1))
    // 权限拒绝或超时无法证明会话丢失，保守保留卷，避免误卸健康但繁忙的卷。
    if result.timedOut || result.error != nil { return nil }
    if result.status == 74 { return false }
    return result.status == 0 ? true : nil
}

enum MountExecutionBudget {
    // The legacy CLI pipeline is synchronous. Keep each calling thread's budget
    // and result together; concurrent rounds must never change another deadline.
    // Async workers use explicit contexts in AutomntCore instead.
    private final class Context {
        var deadline: Date?
        var lastFailure: RecoveryAttemptOutcome = .shareRejected
        var netFSStatus: Int32 = 0
    }
    private static let key = "automnt.cli.mountExecutionContext"
    private static var context: Context {
        if let value = Thread.current.threadDictionary[key] as? Context { return value }
        let value = Context()
        Thread.current.threadDictionary[key] = value
        return value
    }
    static var deadline: Date? {
        get { context.deadline }
        set { context.deadline = newValue }
    }
    static var lastFailure: RecoveryAttemptOutcome {
        get { context.lastFailure }
        set { context.lastFailure = newValue }
    }
    static var netFSStatus: Int32 {
        get { context.netFSStatus }
        set { context.netFSStatus = newValue }
    }
}

func silentMount(urlString: String, mountPath: String) -> Bool {
    // NetFS 同步调用隔离在短时子进程中，超时可终止，主进程无需常驻等待。
    let timeout = max(0, MountExecutionBudget.deadline?.timeIntervalSinceNow ?? 10)
    guard timeout > 0 else { return false }
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
    let result = runCommandDiscardingOutputWithTimeout(executable: executable,
        arguments: ["--internal-netfs-mount", urlString, mountPath], timeout: timeout)
    MountExecutionBudget.lastFailure = result.status == 77 ? .credentialFailure : .shareRejected
    return result.status == 0 && !result.timedOut
}

func performNetFSMount(urlString: String, mountPath: String) -> Bool {
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
        netFSOpenOptions(),
        options,
        &mountPoints
    )

    MountExecutionBudget.netFSStatus = status
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

// MARK: - 挂载丢失自动恢复：状态持久层、会话边界与三重信号判别
//
// 对应 Feature 004（specs/004-mount-loss-recovery/）。设计约束：
// - 事件驱动短命执行，无轮询、无常驻（FR-009 / Constitution II）；
// - 状态文件可丢弃重建，损坏一律走保守方向（FR-010）；
// - 状态文件不是活动配置，不含凭据与配置数据副本（契约 §6）；
// - 卷失效判定禁止 stat() 阻塞路径，改用「挂载表在表 + 主机探活」推导（FR-001/FR-002）。

/// 附属状态文件名（与活动配置同目录、0600、程序独占）。
let mountRecoveryStateFileName = "mount-recovery-state.plist"

func getMountRecoveryStateURL() -> URL {
    // 跟随活动配置：配置被重定向（--self-test/注入）时，状态文件同样随行，
    // 保证自测绝不写入用户真实安装目录。
    getActiveConfigURL().deletingLastPathComponent().appendingPathComponent(mountRecoveryStateFileName)
}

func runSelfTestsEntry(includeNetworkChecks: Bool) -> Bool {
    // 安全闸：自测全程禁止任何真实服务定义/配置文件副作用。
    DaemonRuntime.isSelfTestMode = true
    defer { DaemonRuntime.isSelfTestMode = false }
    // 既有恢复轮自测验证的是「判定/账本」等价性，而非所有权接线本身；
    // 它们以显式免疫标记代表真实入口已持有的许可，缺许可路径由专门断言覆盖。
    // 该标记不接触真实安装，且绝不改变生产行为。
    CLIOwnership.selfTestPermitSupplied = true
    defer { CLIOwnership.selfTestPermitSupplied = false }
    return runSelfTests(includeNetworkChecks: includeNetworkChecks)
}

/// Synchronous CLI test injection belongs to its calling thread. The holder
/// carries only an immutable key; values and closures never cross threads.
private final class CLIThreadValue<Value>: Sendable {
    private let key = "automnt.cli.context." + UUID().uuidString
    private final class Box {
        var value: Value
        init(_ value: Value) { self.value = value }
    }
    func get(or defaultValue: @autoclosure () -> Value) -> Value {
        (Thread.current.threadDictionary[key] as? Box)?.value ?? defaultValue()
    }
    func set(_ value: Value) { Thread.current.threadDictionary[key] = Box(value) }
}

/// 单卷恢复状态（data-model §1）。`everHealthyMounted` 是挂载账的持久表示，
/// 卷缺失后无法由当前快照回溯，故必须落盘（FR-002③/④ 的判别依据）。
enum MountRecoveryStore {
    /// 载入并校验。未知 schemaVersion/解析失败 → corrupt（丢弃全部状态并走保守方向）。
    static func load(from url: URL? = nil) -> MountRecoveryStoreLoad {
        let target = url ?? getMountRecoveryStateURL()
        if let override = mountRecoveryStoreLoadOverride { return override }
        return RecoveryStateRepository(url: target).read()
    }

    /// 原子写入（0600、程序独占）。
    @discardableResult
    static func save(_ file: MountRecoveryStateFile, to url: URL? = nil) -> Bool {
        let target = url ?? getMountRecoveryStateURL()
        if mountRecoveryStoreSaveBlocked { return false }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try RecoveryStateRepository(url: target).save(file)
            return true
        } catch {
            return false
        }
    }

    /// 仅在测试中注入。
    private static let loadOverride = CLIThreadValue<MountRecoveryStoreLoad?>()
    private static let saveBlocked = CLIThreadValue<Bool>()
    static var mountRecoveryStoreLoadOverride: MountRecoveryStoreLoad? {
        get { loadOverride.get(or: nil) }
        set { loadOverride.set(newValue) }
    }
    static var mountRecoveryStoreSaveBlocked: Bool {
        get { saveBlocked.get(or: false) }
        set { saveBlocked.set(newValue) }
    }
}

/// 网络上下文身份快照。构成要素 = 活动网络接口的标识/地址集合 + 默认路由网关。
/// 判定规则（spec §Assumptions，可判定）：任一要素的标识变化或集合增减即构成边界事件；
/// 仅链路可达性抖动不构成边界。
struct NetworkContextSnapshot: Equatable {
    let identity: String
    let components: [String]
    var isReadable: Bool = true
}

enum NetworkContextIdentity {
    /// 测试注入点。
    private static let overrideValue = CLIThreadValue<NetworkContextSnapshot?>()
    private static let componentsValue = CLIThreadValue<(() -> [String]?)?>()
    private static let gatewayValue = CLIThreadValue<(() -> (readable: Bool, gateway: String?))?>()
    static var testOverride: NetworkContextSnapshot? {
        get { overrideValue.get(or: nil) }
        set { overrideValue.set(newValue) }
    }

    /// 内部可注入的要素采集（返回排序后的要素列表）。
    static var componentsProvider: (() -> [String]?)? {
        get { componentsValue.get(or: nil) }
        set { componentsValue.set(newValue) }
    }
    static var gatewayProvider: (() -> (readable: Bool, gateway: String?))? {
        get { gatewayValue.get(or: nil) }
        set { gatewayValue.set(newValue) }
    }

    static func current() -> NetworkContextSnapshot {
        if let override = testOverride { return override }
        guard let elements = (componentsProvider ?? collectElements)()?.sorted() else {
            return NetworkContextSnapshot(identity: "", components: [], isReadable: false)
        }
        return NetworkContextSnapshot(identity: elements.joined(separator: ";"), components: elements)
    }

    /// 以 getifaddrs 采集活动接口（非回环、有地址）的身份要素；
    /// 附加默认路由网关。仅使用公开 API，不引入第三方依赖。
    static func collectElements() -> [String]? {
        var elements: [String] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var cursor = ifaddrPtr
        while let current = cursor {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isUp && !isLoopback, let addr = current.pointee.ifa_addr {
                let family = addr.pointee.sa_family
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                         &host, socklen_t(host.count),
                                         nil, 0, NI_NUMERICHOST)
                guard result == 0 || (family != UInt8(AF_INET) && family != UInt8(AF_INET6)) else { return nil }
                if result == 0 {
                    let name = String(cString: current.pointee.ifa_name)
                    let address = String(cString: host)
                    let familyTag = (family == UInt8(AF_INET)) ? "v4" : (family == UInt8(AF_INET6) ? "v6" : "other")
                    // IPv6 link-local 随接口抖动频繁变化，作为身份要素会误判边界，故排除。
                    if !(familyTag == "v6" && address.lowercased().hasPrefix("fe80:")) {
                        elements.append("if:\(name):\(familyTag):\(address)")
                    }
                }
            }
            cursor = current.pointee.ifa_next
        }

        let route = (gatewayProvider ?? defaultGatewayIdentity)()
        guard route.readable else { return nil }
        if let gateway = route.gateway { elements.append("gw:\(gateway)") }
        return elements
    }

    /// 临时文件避免管道读取阻塞；子进程受剩余恢复预算约束。
    static func defaultGatewayIdentity() -> (readable: Bool, gateway: String?) {
        let timeout = max(0, min(1, MountExecutionBudget.deadline?.timeIntervalSinceNow ?? 1))
        guard timeout > 0 else { return (false, nil) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("automnt-route-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let output = directory.appendingPathComponent("output")
            let errors = directory.appendingPathComponent("errors")
            guard FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]),
                  FileManager.default.createFile(atPath: errors.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { return (false, nil) }
            let outHandle = try FileHandle(forWritingTo: output)
            let errHandle = try FileHandle(forWritingTo: errors)
            defer { try? outHandle.close(); try? errHandle.close() }
            let result = runCommandDiscardingOutputWithTimeout(executable: "/sbin/route",
                arguments: ["-n", "get", "default"], timeout: timeout,
                standardOutputFile: outHandle, standardErrorFile: errHandle)
            guard !result.timedOut, result.processStopped, let status = result.status else { return (false, nil) }
            let stdout = try String(contentsOf: output, encoding: .utf8)
            let stderr = try String(contentsOf: errors, encoding: .utf8)
            return parseGateway(status: status, stdout: stdout, stderr: stderr)
        } catch { return (false, nil) }
    }

    static func parseGateway(status: Int32, stdout: String, stderr: String) -> (readable: Bool, gateway: String?) {
        // route 的明确 ESRCH 结果表示真实无路由；其他退出错误不构成有效快照。
        if status != 0 {
            return (stderr.trimmingCharacters(in: .whitespacesAndNewlines) == "route: writing to routing socket: not in table", nil)
        }
        for line in stdout.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("gateway:") {
                let gateway = String(trimmed.dropFirst("gateway:".count)).trimmingCharacters(in: .whitespaces)
                return (!gateway.isEmpty, gateway.isEmpty ? nil : gateway)
            }
        }
        return (false, nil)
    }
}

/// 登录会话纪元。登录时递增/重置；用于与网络身份并列构成会话边界。
enum LoginSessionEpoch {
    private static let testOverrideBox = LockedBox<String?>(nil)
    static var testOverride: String? {
        get { testOverrideBox.value }
        set { testOverrideBox.value = newValue }
    }

    static func current() -> String {
        if let override = testOverride { return override }
        // 以「系统启动时刻」为基底：重新登录不会改变启动时刻，
        // 故再叠加控制台用户会话起始时间，二者共同标识一次登录会话。
        return "\(bootTimeSeconds())-\(consoleSessionStartSeconds())"
    }

    private static func bootTimeSeconds() -> Int64 {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        let result = sysctl(&mib, 2, &bootTime, &size, nil, 0)
        guard result == 0 else { return 0 }
        return Int64(bootTime.tv_sec)
    }

    /// 控制台登录记录起始时间（取 utmpx 中 console 行）。
    private static func consoleSessionStartSeconds() -> Int64 {
        setutxent()
        defer { endutxent() }
        var latest: Int64 = 0
        while let entry = getutxent() {
            let type = entry.pointee.ut_type
            guard type == USER_PROCESS else { continue }
            let line = withUnsafeBytes(of: entry.pointee.ut_line) { raw -> String in
                String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
            }
            guard line.hasPrefix("console") else { continue }
            let seconds = Int64(entry.pointee.ut_tv.tv_sec)
            if seconds > latest { latest = seconds }
        }
        return latest
    }
}

/// 会话边界标识（网络上下文 + 登录纪元）。
struct SessionBoundaryIdentity: Equatable {
    let network: String
    let loginEpoch: String
    var combined: String { "\(network)|\(loginEpoch)" }

    static func current(previous: String? = nil) -> SessionBoundaryIdentity {
        let snapshot = NetworkContextIdentity.current()
        let identity = RecoverySessionIdentity(network: snapshot.isReadable ? snapshot.identity : nil,
            loginEpoch: LoginSessionEpoch.current(), previous: previous)
        return SessionBoundaryIdentity(network: identity.network, loginEpoch: identity.loginEpoch)
    }
}

/// 三重信号判别结论（契约 §2 六行）。
/// 配置启用卷的可注入视图（T005）；判定与枚举的唯一来源在 AutomntCore
/// `configuredRecoveryVolumes`，CLI 不再保留第二套实现。
typealias ConfiguredVolume = RecoveryRoundConfiguredVolume

func configuredVolumes(from config: AutomntConfig) -> [ConfiguredVolume] {
    configuredRecoveryVolumes(from: config)
}

/// 判定机（T006）。纯函数式：所有输入可注入，便于全内存自测。


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

// 信号处理器状态：必须在异步信号安全的前提下可读。termios 快照经发布一次的
// 堆缓冲读取（不分配、不加锁），两个开关用 `Atomic` 做 acquire/release 发布；
// 全程不使用 `nonisolated(unsafe)` 或 `@unchecked Sendable`。
private let terminalSignalTermiosAddress = Atomic<UInt>(0)
private let terminalSignalRestoreEnabled = Atomic<Int32>(0)
private let terminalSignalCursorHidden = Atomic<Int32>(0)
private let terminalSignalCursorSequence: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (27, 91, 63, 50, 53, 104)

/// 发布一次信号处理器可读的 termios 快照（仅分配一次）。
private func publishTerminalSignalTermios(_ snapshot: termios) {
    let pointer: UnsafeMutablePointer<termios>
    if let existing = UnsafeMutableRawPointer(bitPattern: terminalSignalTermiosAddress.load(ordering: .relaxed)) {
        pointer = existing.assumingMemoryBound(to: termios.self)
    } else {
        let raw = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<termios>.stride,
                                                   alignment: MemoryLayout<termios>.alignment)
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: MemoryLayout<termios>.stride)
        terminalSignalTermiosAddress.store(UInt(bitPattern: raw), ordering: .relaxed)
        pointer = raw.assumingMemoryBound(to: termios.self)
    }
    pointer.pointee = snapshot
    terminalSignalRestoreEnabled.store(1, ordering: .releasing)
}

private func clearTerminalSignalRestore() {
    terminalSignalRestoreEnabled.store(0, ordering: .releasing)
}

private func signalHandlerTermiosSnapshot() -> termios? {
    guard terminalSignalRestoreEnabled.load(ordering: .acquiring) != 0,
          let raw = UnsafeMutableRawPointer(bitPattern: terminalSignalTermiosAddress.load(ordering: .acquiring)) else {
        return nil
    }
    return raw.assumingMemoryBound(to: termios.self).pointee
}

private func terminalSignalHandler(_ signalNumber: Int32) {
    if var snapshot = signalHandlerTermiosSnapshot() {
        _ = tcsetattr(STDIN_FILENO, TCSANOW, &snapshot)
        if terminalSignalCursorHidden.load(ordering: .acquiring) != 0 {
            withUnsafePointer(to: terminalSignalCursorSequence) { pointer in
                _ = write(STDOUT_FILENO, pointer, 6)
            }
        }
    }
    let exitCode: Int32 = signalNumber == SIGTERM ? 143 : (signalNumber == SIGHUP ? 129 : 130)
    _exit(exitCode)
}

struct TerminalUI {
    // 所有可变静态状态改由 `LockedBox` 承载（Swift 6 并发安全）。
    // 对外仍是同名 `static var`，同步读写语义与旧实现一致。
    private static let mockKeySequenceBox = LockedBox<[KeyAction]?>(nil)
    private static let mockInputBytesBox = LockedBox<[UInt8]?>(nil)
    private static let mockPendingInputResultsBox = LockedBox<[Bool]?>(nil)
    private static let mockedPollTimeoutsBox = LockedBox<[Int]>([])
    private static let lastRenderedLineCountBox = LockedBox<Int>(0)
    private static let lastRenderedVisibleRangeBox = LockedBox<Range<Int>?>(nil)
    private static let originalTermiosBox = LockedBox<termios?>(nil)
    private static let signalHandlersInstalledBox = LockedBox<Bool>(false)
    private static let termiosTestModeBox = LockedBox<Bool>(false)
    private static let mockOriginalTermiosBox = LockedBox<termios?>(nil)
    private static let mockRawTermiosBox = LockedBox<termios?>(nil)
    private static let mockRestoredTermiosBox = LockedBox<termios?>(nil)
    private static let mockTermiosOriginalAfterRestoreBox = LockedBox<termios?>(nil)
    private static let mockOriginalTermiosBytesBox = LockedBox<[UInt8]?>(nil)
    private static let termiosLastRestoreMatchedOriginalBox = LockedBox<Bool>(false)
    private static let cursorHiddenBox = LockedBox<Bool>(false)

    static var mockKeySequence: [KeyAction]? {
        get { mockKeySequenceBox.value }
        set { mockKeySequenceBox.value = newValue }
    }
    static var mockInputBytes: [UInt8]? {
        get { mockInputBytesBox.value }
        set { mockInputBytesBox.value = newValue }
    }
    static var mockPendingInputResults: [Bool]? {
        get { mockPendingInputResultsBox.value }
        set { mockPendingInputResultsBox.value = newValue }
    }
    static var mockedPollTimeouts: [Int] {
        get { mockedPollTimeoutsBox.value }
        set { mockedPollTimeoutsBox.value = newValue }
    }
    static var lastRenderedLineCount: Int {
        get { lastRenderedLineCountBox.value }
        set { lastRenderedLineCountBox.value = newValue }
    }
    static var lastRenderedVisibleRange: Range<Int>? {
        get { lastRenderedVisibleRangeBox.value }
        set { lastRenderedVisibleRangeBox.value = newValue }
    }
    static var originalTermios: termios? {
        get { originalTermiosBox.value }
        set { originalTermiosBox.value = newValue }
    }
    static var signalHandlersInstalled: Bool {
        get { signalHandlersInstalledBox.value }
        set { signalHandlersInstalledBox.value = newValue }
    }
    static var termiosTestMode: Bool {
        get { termiosTestModeBox.value }
        set { termiosTestModeBox.value = newValue }
    }
    static var mockOriginalTermios: termios? {
        get { mockOriginalTermiosBox.value }
        set { mockOriginalTermiosBox.value = newValue }
    }
    static var mockRawTermios: termios? {
        get { mockRawTermiosBox.value }
        set { mockRawTermiosBox.value = newValue }
    }
    static var mockRestoredTermios: termios? {
        get { mockRestoredTermiosBox.value }
        set { mockRestoredTermiosBox.value = newValue }
    }
    static var mockTermiosOriginalAfterRestore: termios? {
        get { mockTermiosOriginalAfterRestoreBox.value }
        set { mockTermiosOriginalAfterRestoreBox.value = newValue }
    }
    static var mockOriginalTermiosBytes: [UInt8]? {
        get { mockOriginalTermiosBytesBox.value }
        set { mockOriginalTermiosBytesBox.value = newValue }
    }
    static var termiosLastRestoreMatchedOriginal: Bool {
        get { termiosLastRestoreMatchedOriginalBox.value }
        set { termiosLastRestoreMatchedOriginalBox.value = newValue }
    }
    static var cursorHidden: Bool {
        get { cursorHiddenBox.value }
        // 保持既有 didSet 语义：切换光标状态同时更新信号处理器读取的原子标志。
        set {
            cursorHiddenBox.value = newValue
            terminalSignalCursorHidden.store(newValue ? 1 : 0, ordering: .releasing)
        }
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
            clearTerminalSignalRestore()
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
            publishTerminalSignalTermios(original)
            var raw = original
            raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG)
            withUnsafeMutableBytes(of: &raw.c_cc) { controlChars in
                controlChars[Int(VMIN)] = 1 // Return after at least one byte.
                controlChars[Int(VTIME)] = 0 // Do not add a read timeout.
            }
            if isTTYOverride == true { restoredTermiosSnapshot = raw }
            guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else {
                originalTermios = nil
                clearTerminalSignalRestore()
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

private let mockLineInputBox = LockedBox<String?>(nil)
private let mockLineInputsBox = LockedBox<[String]?>(nil)
private let lastLineInputWasEscapedBox = LockedBox<Bool>(false)
private let lastLineInputReachedEOFBox = LockedBox<Bool>(false)
private let originalTermiosSnapshotBox = LockedBox<termios?>(nil)
private let restoredTermiosSnapshotBox = LockedBox<termios?>(nil)
private let lastSelectionWasEscapedBox = LockedBox<Bool>(false)
private let lastSelectionReachedEOFBox = LockedBox<Bool>(false)

var mockLineInput: String? {
    get { mockLineInputBox.value }
    set { mockLineInputBox.value = newValue }
}
var mockLineInputs: [String]? {
    get { mockLineInputsBox.value }
    set { mockLineInputsBox.value = newValue }
}
var lastLineInputWasEscaped: Bool {
    get { lastLineInputWasEscapedBox.value }
    set { lastLineInputWasEscapedBox.value = newValue }
}
var lastLineInputReachedEOF: Bool {
    get { lastLineInputReachedEOFBox.value }
    set { lastLineInputReachedEOFBox.value = newValue }
}
var originalTermiosSnapshot: termios? {
    get { originalTermiosSnapshotBox.value }
    set { originalTermiosSnapshotBox.value = newValue }
}
var restoredTermiosSnapshot: termios? {
    get { restoredTermiosSnapshotBox.value }
    set { restoredTermiosSnapshotBox.value = newValue }
}
var lastSelectionWasEscaped: Bool {
    get { lastSelectionWasEscapedBox.value }
    set { lastSelectionWasEscapedBox.value = newValue }
}
var lastSelectionReachedEOF: Bool {
    get { lastSelectionReachedEOFBox.value }
    set { lastSelectionReachedEOFBox.value = newValue }
}

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

private let mockCandidateHostsBox = LockedBox<[DiscoveredHostGroup]?>(nil)
var mockCandidateHosts: [DiscoveredHostGroup]? {
    get { mockCandidateHostsBox.value }
    set { mockCandidateHostsBox.value = newValue }
}

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

private let lastManualHostAliasWasEscapedBox = LockedBox<Bool>(false)
var lastManualHostAliasWasEscaped: Bool {
    get { lastManualHostAliasWasEscapedBox.value }
    set { lastManualHostAliasWasEscapedBox.value = newValue }
}

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
    let targetURL = getConfigURL()
    let initialInspection = inspectConfigFile(at: targetURL)
    guard initialInspection.state != .inaccessible else {
        fputs(tr("✗ 无法安全读取配置；未启动向导。请检查文件所有者和权限。\n", "✗ Cannot safely read configuration; check its owner and permissions before setup.\n"), stderr)
        return false
    }
    let initialRevision = initialInspection.contents.map(ConfigurationRevision.of)
    configurationDraftRevisions.removeValue(forKey: targetURL.standardizedFileURL.path)
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
    guard saveConfig(config, to: targetURL, preserveUnknownFields: false, expectedRevision: initialRevision, requireAbsent: initialRevision == nil) else {
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
          var workingConfig = loadConfig(from: configURL),
          let draftRevision = configurationDraftRevisions[configURL.standardizedFileURL.path] else { return }

    // T024：既有安装的事件源收敛。MUST 在读入配置后、进入菜单之前执行，
    // MUST NOT 挂在退出路径上（否则与「未保存即 Esc 退出时服务定义不变」冲突）。
    if configURL == getActiveConfigURL() {
        convergeInstalledEventSourcesIfNeeded()
    }

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
            SelectionItem(id: "remount", title: tr("立即重新挂载", "Remount now"),
                          subtitle: tr("执行一轮挂载评估，恢复当前缺失的共享",
                                       "Run one mount evaluation to restore missing shares")),
            SelectionItem(id: "recovery_switch",
                          title: tr("自动恢复开关：\(workingConfig.isAutoMountRecoveryEnabled ? "已启用" : "已关闭")",
                                    "Auto-recovery switch: \(workingConfig.isAutoMountRecoveryEnabled ? "Enabled" : "Disabled")"),
                          subtitle: tr("回车切换；仅在“保存并退出”后落盘生效",
                                       "Press Enter to toggle; applied only after \"Save and exit\"")),
            SelectionItem(id: "mount_scope",
                          title: tr("挂载范围：\(workingConfig.isMountAllEnabled ? "所有可达服务器" : "首个可达服务器")",
                                    "Mount scope: \(workingConfig.isMountAllEnabled ? "All reachable servers" : "First reachable server")"),
                          subtitle: tr("服务器按左侧顺序检查；回车切换，保存并退出后生效",
                                       "Servers are checked in saved order; press Enter to toggle, applied after Save and exit")),
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
            guard saveConfig(workingConfig, to: configURL, expectedRevision: draftRevision) else {
                fputs(tr("✗ 保存失败；配置管理仍保持打开。\n", "✗ Save failed; configuration management remains open.\n"), stderr)
                continue
            }
            // FR-008：开关切换只在「保存并退出」落盘成功后再生服务定义。
            // 关闭「自动挂载」时先保存配置（已完成），再把服务停到明确 stopped，
            // 停用只禁止新挂载，绝不卸载已有卷宗。
            if !workingConfig.isAutomationEnabled {
                if CLIOwnership.stopServiceForDisable(revision: configurationDraftRevisions[configURL.standardizedFileURL.path] ?? draftRevision) {
                    print(tr("✓ 自动挂载已停用：后台服务已停止，已挂载共享保持可用。",
                             "✓ Automatic mounting disabled: the background service is stopped; existing mounts remain available."))
                } else {
                    fputs(tr("⚠ 自动挂载已停用，但后台服务未能确认停止；请检查服务状态后重试。\n",
                             "⚠ Automatic mounting is disabled, but the background service was not confirmed stopped; check service status and retry.\n"), stderr)
                }
            }
            // 再生失败不得静默；但配置已保存，故只报错并继续退出。
            if workingConfig.isAutomationEnabled, let error = regenerateServiceDefinitionForSwitch() {
                fputs(tr("⚠ 服务定义未同步：\(error)\n", "⚠ Service definition not synced: \(error)\n"), stderr)
            }
            print(tr("✓ 配置已保存并退出。", "✓ Configuration saved and exited."))
            return
        } else if action == "remount" {
            // T017：执行一轮完整挂载评估（开关 false 时为基线段评估），菜单保持可用。
            let configForRound = workingConfig
            // T010-a：真实动作前取得统一 evaluation.lock 许可（owner=cli / revision / generation）。
            guard let permit = CLIOwnership.beginEvaluation() else {
                fputs(tr("✗ 重新挂载已取消：后端所有权校验未通过。\n",
                         "✗ Remount cancelled: backend ownership verification did not pass.\n"), stderr)
                continue
            }
            // 持久配置与内存工作副本可能不同（未保存的编辑）；以已提交配置为准执行真实动作。
            if permit.snapshot.configuration != configForRound {
                print(tr("· 检测到未保存的修改：本轮按已保存配置执行；请先保存并退出后再验证新设置。",
                         "· Unsaved changes detected: this round uses the saved configuration; save and exit to apply the new settings."))
            }
            let committedConfig = permit.snapshot.configuration
            var mountTable: [String: String] = [:]
            for entry in getKernelMountEntries() where entry.fileSystemType.lowercased() == "smbfs" {
                if let key = smbResourceIdentity(entry.source) { mountTable[key] = entry.mountPoint }
            }
            let cache = ReachabilityCache(probe: { host, port in
                let timeout = committedConfig.hosts.first(where: { $0.host == host })?.timeoutMs ?? 1000
                return boundedHostReachability(host: host, port: port, timeoutMs: timeout)
            })
            if committedConfig.isAutoMountRecoveryEnabled {
                let outcome = runRecoveryRound(
                    config: committedConfig, mountTable: mountTable,
                    hostReachability: { host, port in cache.isReachable(host: host, port: port) },
                    applyRecovery: { volume, _ in
                        switch ensureMountPointReady(target: MountTarget(url: volume.url, mountPath: volume.mountPoint)) {
                        case .alreadyMountedHealthy: return true
                        case .readyToMount:
                            let mounted = silentMount(urlString: volume.url, mountPath: volume.mountPoint)
                            if mounted && volume.preventSpotlightIndex { disableSpotlightIndex(at: volume.mountPoint) }
                            return mounted
                        case .unmountFailed: return false
                        }
                    }, manualRecovery: true, ownershipPermit: permit)
                _ = CLIOwnership.endEvaluation(permit)
                if !outcome.deferredVolumeKeys.isEmpty {
                    print(tr("· 重新挂载暂未执行：另一轮正在运行或状态锁不可用，请稍后重试。",
                             "· Remount deferred: another evaluation is running or the state lock is unavailable; try again later."))
                } else {
                    print(tr("✓ 重新挂载完成：成功 \(outcome.recovered.count) 个，失败 \(outcome.failed.count) 个，抑制 \(outcome.suppressed.count) 个。",
                             "✓ Remount finished: \(outcome.recovered.count) recovered, \(outcome.failed.count) failed, \(outcome.suppressed.count) suppressed."))
                }
            } else {
                // 开关关闭：回退为基线段挂载评估（不执行恢复判定与会话抑制）。
                // 挂载范围与恢复轮次共用同一规则：默认只处理首个可达主机；选择
                // “所有可达主机”时按保存顺序逐个挂载其启用共享。
                var mounted = 0
                let candidates: [HostConfig]
                if committedConfig.effectiveMountPolicy == .allReachable {
                    candidates = committedConfig.hosts.filter {
                        $0.enabled && cache.isReachable(host: $0.host, port: $0.port)
                    }
                } else {
                    candidates = [firstReachableHost(in: committedConfig, probe: { cache.isReachable(host: $0, port: $1) })].compactMap { $0 }
                }
                for host in candidates {
                    for volume in configuredVolumes(from: committedConfig)
                        where volume.host == host.host && volume.port == host.port {
                        switch ensureMountPointReady(target: MountTarget(url: volume.url, mountPath: volume.mountPoint)) {
                        case .alreadyMountedHealthy: mounted += 1
                        case .readyToMount:
                            if silentMount(urlString: volume.url, mountPath: volume.mountPoint) { mounted += 1 }
                        case .unmountFailed: break
                        }
                    }
                }
                _ = CLIOwnership.endEvaluation(permit)
                print(tr("✓ 基线段挂载评估完成：\(mounted) 个卷可用（自动恢复已关闭）。",
                         "✓ Baseline mount evaluation finished: \(mounted) volume(s) available (auto-recovery disabled)."))
            }
            continue
        } else if action == "recovery_switch" {
            // T023：切换只改内存工作副本，Esc 退出即完整丢弃。
            workingConfig.autoMountRecovery = !workingConfig.isAutoMountRecoveryEnabled
            print(tr("✓ 自动恢复已切换为\(workingConfig.isAutoMountRecoveryEnabled ? "启用" : "关闭")（尚未保存，保存并退出后生效）。",
                     "✓ Auto-recovery toggled \(workingConfig.isAutoMountRecoveryEnabled ? "on" : "off") (not saved yet; applies after Save and exit)."))
            continue
        } else if action == "mount_scope" {
            // T117：挂载范围只改内存工作副本，与自动恢复开关一样随“保存并退出”落盘。
            workingConfig.mountPolicy = workingConfig.isMountAllEnabled ? .firstReachable : .allReachable
            print(tr("✓ 挂载范围已切换为\(workingConfig.isMountAllEnabled ? "所有可达服务器" : "首个可达服务器")（尚未保存，保存并退出后生效）。",
                     "✓ Mount scope switched to \(workingConfig.isMountAllEnabled ? "all reachable servers" : "first reachable server") (not saved yet; applies after Save and exit)."))
            continue
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

    /// Explicit one-time migration from an ad-hoc installation; never used by the updater.
    static func migrateAdHocInstallation(expectedTeam: String, source: URL = currentExecutablePhysicalURL(),
                                         target: URL = getActiveInstalledBinaryURL()) -> Bool {
        guard source.path != target.path, !expectedTeam.isEmpty,
              let candidate = BinarySigningPolicy.trustedCode(at: source) else { return false }
        var candidateInfo: CFDictionary?
        guard SecCodeCopySigningInformation(candidate, SecCSFlags(rawValue: kSecCSSigningInformation), &candidateInfo) == errSecSuccess,
              let info = candidateInfo as? [String: Any],
              info[kSecCodeInfoTeamIdentifier as String] as? String == expectedTeam else { return false }
        var old: SecStaticCode?
        var oldInfo: CFDictionary?
        guard SecStaticCodeCreateWithPath(target as CFURL, [], &old) == errSecSuccess,
              let old,
              SecStaticCodeCheckValidity(old, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess,
              SecCodeCopySigningInformation(old, SecCSFlags(rawValue: kSecCSSigningInformation), &oldInfo) == errSecSuccess,
              let oldMetadata = oldInfo as? [String: Any],
              oldMetadata[kSecCodeInfoIdentifier as String] as? String == "automnt",
              let flags = oldMetadata[kSecCodeInfoFlags as String] as? NSNumber,
              flags.uint32Value & 0x00000002 != 0 else { return false } // CS_ADHOC
        let backup = target.deletingLastPathComponent().appendingPathComponent("automnt.pre-signing-migration.\(UUID().uuidString)")
        do {
            try FileManager.default.copyItem(at: target, to: backup)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: backup.path)
            try replaceFilesTransactionally([
                StagedFileReplacement(sourceURL: source, destinationURL: target, permissions: 0o755)
            ], postReplaceAction: {
                guard BinarySigningPolicy.permitsReplacement(candidate: target, installed: source) else {
                    throw NSError(domain: "automnt.signing-migration", code: 1)
                }
            })
            print(tr("✓ 签名身份迁移完成；旧程序备份：\(backup.path)\n首次网络卷授权可能仍需用户确认。",
                     "✓ Signing identity migrated; previous binary backup: \(backup.path)\nFirst network-volume authorization may still require user consent."))
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func relocateIfNeeded() -> Bool {
        let currentURL = currentExecutablePhysicalURL()
        let targetURL = getActiveInstalledBinaryURL()
        if currentURL.standardizedFileURL.path == targetURL.standardizedFileURL.path {
            return false
        }

        guard BinarySigningPolicy.permitsReplacement(candidate: currentURL, installed: targetURL) else {
            fputs(tr("✗ 安装已停止：代码签名无效或与已安装版本身份不兼容；原程序保留。\n",
                     "✗ Installation stopped: invalid signature or incompatible installed identity; existing program preserved.\n"), stderr)
            return false
        }
        let targetDir = targetURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        do {
            try replaceFilesTransactionally([
                StagedFileReplacement(sourceURL: currentURL, destinationURL: targetURL, permissions: 0o755)
            ])
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
            let hasStartCalendarInterval = plist["StartCalendarInterval"] != nil
            if label == launchAgentLabel && args == [canonicalBinary] && !hasStartInterval && !hasStartCalendarInterval {
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
        // 守护进程运行态护栏（契约 §5）：`registerOrUpdateLaunchAgent` 会先 bootout 再
        // bootstrap 当前正在运行的作业，导致自终止。故守护运行态下绝不重生成/重载服务定义。
        if !isServicePlistValid || !isServiceRegistered {
            if DaemonRuntime.isDaemon() {
                writeLog("Daemon runtime: skipping LaunchAgent regeneration to avoid self-termination")
            } else if let refusal = CLIOwnership.registrationRefusal() {
                // T022：app 持有时 CLI 不得 owner-blind 自愈抢占。
                writeLog("Self-heal skipped: \(refusal)")
            } else {
                _ = registerOrUpdateLaunchAgent()
                healed = true
            }
        }
        return healed
    }
}

/// 守护进程运行态判定（契约 §5 MUST 可判定）。
///
/// 判据：由 launchd 启动的作业其父进程为 launchd(pid 1)，且无控制终端。
/// **禁止**以「无参数即守护进程」作为判据——`--config` 之外亦有无参数交互路径。
enum DaemonRuntime {
    /// 测试注入点（nil = 使用真实判据）。
    private static let testOverrideBox = LockedBox<Bool?>(nil)
    static var testOverride: Bool? {
        get { testOverrideBox.value }
        set { testOverrideBox.value = newValue }
    }

    /// 自测模式：置位后一律禁止任何真实服务定义/配置副作用。
    /// 这不是「守护进程」语义，而是「绝不在自测中改动用户真实安装」的安全闸。
    private static let isSelfTestModeBox = LockedBox<Bool>(false)
    static var isSelfTestMode: Bool {
        get { isSelfTestModeBox.value }
        set { isSelfTestModeBox.value = newValue }
    }

    static func isDaemon() -> Bool {
        if isSelfTestMode { return true }
        if let override = testOverride { return override }
        // 父进程为 launchd
        if getppid() == 1 { return true }
        // 无控制终端（交互式终端必有 tty）
        if isatty(STDIN_FILENO) == 0 && isatty(STDERR_FILENO) == 0 { return true }
        return false
    }
}

/// 事件源集合（契约 §5）。开关为 true = 三类；false = 仅登录 + 网络配置变化。
enum RecoveryEventSourceSet: String, Equatable {
    case threeSources
    case twoSources

    static func forSwitch(enabled: Bool) -> RecoveryEventSourceSet {
        enabled ? .threeSources : .twoSources
    }

    /// 是否启用挂载命名空间事件（`StartOnMount` 与挂载目录监听）。
    var includesMountNamespace: Bool { self == .threeSources }
}

/// 当前已安装服务定义所体现的事件源集合（用于检测过时集合）。
func installedEventSourceSet(at plistURL: URL? = nil) -> RecoveryEventSourceSet? {
    let url = plistURL ?? getLaunchAgentPlistURL()
    guard let data = try? Data(contentsOf: url),
          let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
        return nil
    }
    let hasStartOnMount = (plist["StartOnMount"] as? Bool) == true
    let watch = Set(plist["WatchPaths"] as? [String] ?? [])
    let config = loadConfig(from: getActiveConfigURL(), migrate: false) ?? AutomntConfig()
    let expectedPaths = Set(mountWatchPaths(from: config) + ["/Volumes"])
    return hasStartOnMount && expectedPaths.isSubset(of: watch) ? .threeSources : .twoSources
}

func installedServiceDefinitionMatches(config: AutomntConfig, at url: URL? = nil) -> Bool {
    guard let data = try? Data(contentsOf: url ?? getLaunchAgentPlistURL()),
          let installed = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return false }
    let expected = generateLaunchAgentDictionary(binaryURL: getActiveInstalledBinaryURL(),
        logDir: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/automnt"),
        autoMountRecoveryEnabled: config.isAutoMountRecoveryEnabled,
        mountWatchPaths: config.isAutoMountRecoveryEnabled ? mountWatchPaths(from: config) : [])
    for key in ["RunAtLoad", "StartOnMount", "WatchPaths", "StartInterval", "StartCalendarInterval", "KeepAlive"] {
        let actualValue = installed[key] as? NSObject
        let expectedValue = expected[key] as? NSObject
        if actualValue != expectedValue { return false }
    }
    return true
}

/// 生成 LaunchAgent 字典。
///
/// **唯一生成器规则**（契约 §5）：事件源集合必须由此函数依开关派生，
/// 所有注册路径（含安装自愈）都经此处，禁止在调用点各自拼装。
/// - `autoMountRecoveryEnabled == true`：登录 + 网络配置变化 + 挂载命名空间事件；
/// - `false`：仅登录 + 网络配置变化（严格回落至现状触发集）。
func generateLaunchAgentDictionary(
    binaryURL: URL,
    logDir: URL,
    autoMountRecoveryEnabled: Bool = true,
    mountWatchPaths: [String] = []
) -> [String: Any] {
    let stdoutLog = logDir.appendingPathComponent("stdout.log").path
    let stderrLog = logDir.appendingPathComponent("stderr.log").path
    let sysConfigDir = "/Library/Preferences/SystemConfiguration"

    var dict: [String: Any] = [
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

    if autoMountRecoveryEnabled {
        // 挂载侧：系统级「文件系统挂载时启动作业」键。
        dict["StartOnMount"] = true
        // 弹出侧：挂载目录增删监听（`WatchPaths` 类，官方标注竞态可能漏事件）。
        var watchPaths = dict["WatchPaths"] as? [String] ?? []
        watchPaths.append(contentsOf: mountWatchPaths)
        // 始终包含 /Volumes：标准挂载点集合的父目录，覆盖弹出/回归。
        if !watchPaths.contains("/Volumes") { watchPaths.append("/Volumes") }
        dict["WatchPaths"] = watchPaths
    }

    return dict
}

/// 由配置推导需要监听的挂载目录（标准挂载点集合，非硬编码字面）。
func mountWatchPaths(from config: AutomntConfig) -> [String] {
    var paths = Set<String>()
    for volume in configuredVolumes(from: config) {
        let standardized = URL(fileURLWithPath: volume.mountPoint).standardizedFileURL.path
        paths.insert(standardized)
        let parent = URL(fileURLWithPath: standardized).deletingLastPathComponent().path
        if !parent.isEmpty && parent != "/" { paths.insert(parent) }
    }
    return paths.sorted()
}

func registerOrUpdateLaunchAgent(targetBinaryURL: URL? = nil, targetPlistURL: URL? = nil) -> Bool {
    guard !DaemonRuntime.isDaemon() else { return false }
    let binary = targetBinaryURL ?? getActiveInstalledBinaryURL()
    let plistURL = targetPlistURL ?? getLaunchAgentPlistURL()
    let logDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/automnt", isDirectory: true)

    try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    let activeConfig = loadConfig(from: getActiveConfigURL(), migrate: false) ?? AutomntConfig()
    let switchEnabled = activeConfig.isAutoMountRecoveryEnabled
    let watchPaths = switchEnabled ? mountWatchPaths(from: activeConfig) : []
    let agentDict = generateLaunchAgentDictionary(binaryURL: binary, logDir: logDir,
                                                  autoMountRecoveryEnabled: switchEnabled,
                                                  mountWatchPaths: watchPaths)

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

/// 服务定义再生助手（T022）。
///
/// **仅在交互式入口调用**；守护运行态一律拒绝执行（会 bootout 自终止）。
/// 返回 nil 表示成功，非 nil 为面向使用者的错误说明。
func regenerateServiceDefinitionForSwitch(force: Bool = false) -> String? {
    if DaemonRuntime.isDaemon() {
        return tr("守护进程运行态禁止重生成服务定义（会自终止）",
                  "Refusing to regenerate the service definition from daemon runtime (would self-terminate)")
    }
    let config = loadConfig(from: getActiveConfigURL(), migrate: false) ?? AutomntConfig()
    if !force, installedServiceDefinitionMatches(config: config) {
        return nil // 幂等：已是目标集合，不重复 bootout/bootstrap
    }
    // T022 owner-aware：服务定义再生同样属于注册动作，app 持有时不得抢占。
    if let refusal = CLIOwnership.registrationRefusal() {
        return refusal
    }
    guard registerOrUpdateLaunchAgent() else {
        return tr("服务定义重载失败，请运行 automnt --install 修复",
                  "Failed to reload the service definition; run automnt --install to repair")
    }
    return nil
}

/// 既有安装的事件源收敛（T024）。
///
/// 自更新只替换二进制、不重写服务定义，而旧 plist 因 `isServicePlistValid`
/// 只校验 Label/args/周期键而始终判为有效，自愈因此永不触发——故须在**交互式入口**
/// 主动检测「开关为 true 但事件源集合过时」并收敛。
///
/// **MUST 在 `--config` 读入配置后、进入菜单之前调用**，不得挂在退出路径上
/// （否则与「未保存即 Esc 退出时服务定义不变」冲突）。
func convergeInstalledEventSourcesIfNeeded() {
    guard !DaemonRuntime.isDaemon() else { return }
    let config = loadConfig(from: getActiveConfigURL(), migrate: false) ?? AutomntConfig()
    let desired = RecoveryEventSourceSet.forSwitch(enabled: config.isAutoMountRecoveryEnabled)
    guard FileManager.default.fileExists(atPath: getLaunchAgentPlistURL().path),
          !installedServiceDefinitionMatches(config: config) else { return }
    if let error = regenerateServiceDefinitionForSwitch(force: true) {
        fputs(tr("⚠ 服务定义事件源收敛失败：\(error)\n", "⚠ Event-source convergence failed: \(error)\n"), stderr)
    } else {
        print(tr("✓ 已收敛服务定义事件源为\(desired == .threeSources ? "三类（含挂载命名空间）" : "两类（回落基线）")。",
                 "✓ Converged service definition event sources to \(desired == .threeSources ? "three (incl. mount namespace)" : "two (baseline fallback)")."))
    }
}

/// 主机顺位唯一来源在 AutomntCore；CLI 只保留便捷转发。
func firstReachableHost(in config: AutomntConfig, probe: (String, Int) -> Bool) -> HostConfig? {
    RecoveryRoundPlanner.firstReachableHost(in: config, probe: probe)
}

/// 单轮内的主机可达性缓存：同一主机只探测一次，避免每卷重复探测。
final class ReachabilityCache {
    private let probe: (String, Int) -> Bool
    private var cache: [String: Bool] = [:]
    init(probe: @escaping (String, Int) -> Bool) { self.probe = probe }
    func isReachable(host: String, port: Int) -> Bool {
        let key = "\(host):\(port)"
        if let cached = cache[key] { return cached }
        let result = probe(host, port)
        cache[key] = result
        return result
    }
}

/// 恢复判定轮的结果（供通知与自测）。
struct RecoveryRoundOutcome: Equatable {
    var recovered: [String] = []
    var failed: [String] = []
    var suppressed: [String] = []
    var attempted: Int = 0
    var notificationKeys: [String] = []
    var deferredVolumeKeys: [String] = []
    var stateDiagnostic: String?

    var hasVisibleFallbackTrigger: Bool { !failed.isEmpty || !suppressed.isEmpty }
}

/// 恢复判定轮编排（T011）：CLI 侧只保留 I/O 与副作用。
///
/// 判定/账本/通知额度全部由 AutomntCore `RecoveryRoundPlanner` 承担；
/// 本函数按共享计划执行清理与挂载，并用同一份账本保存状态。
/// 对外可观察行为与 `RecoveryRoundOutcome` 字段保持兼容。
func runRecoveryRound(
    config: AutomntConfig,
    mountTable: [String: String],
    hostReachability: (String, Int) -> Bool,
    stateURL: URL? = nil,
    applyRecovery: @escaping (ConfiguredVolume, AutomntConfig) -> Bool,
    writeState: Bool = true,
    manualRecovery: Bool = false,
    cleanupVolume: @escaping (String) -> Bool = { forceUnmountWithTimeout(path: $0) },
    volumeHealth: ((String) -> Bool)? = nil,
    ownershipPermit: CLIEvaluationContext? = nil
) -> RecoveryRoundOutcome {
    var outcome = RecoveryRoundOutcome()

    // 开关门：关闭时恢复判定与会话抑制不执行（FR-008）。
    guard RecoveryRoundPlanner.isPermitted(configuration: config) else { return outcome }
    // T010-a：真实 CLI 评估必须持有统一 evaluation.lock 的 owner/generation 许可。
    // 自测注入可显式免许可；真实入口缺失许可时保守 defer，绝不裸动作。
    if ownershipPermit == nil && !(DaemonRuntime.isSelfTestMode && CLIOwnership.selfTestPermitSupplied) {
        outcome.deferredVolumeKeys = RecoveryRoundPlanner.deferRound(configuration: config).deferredIdentities
        return outcome
    }
    defer { withExtendedLifetime(ownershipPermit) {} }
    // 逐卷探测与挂载共用同一轮预算窗口（与合并前顺序一致）。
    let previousDeadline = MountExecutionBudget.deadline
    let window = RecoveryRoundPlanner.retryWindowMilliseconds(config)
    MountExecutionBudget.deadline = Date().addingTimeInterval(Double(window) / 1000)
    defer { MountExecutionBudget.deadline = previousDeadline }

    let targetStateURL = stateURL ?? getMountRecoveryStateURL()
    let lockURL = targetStateURL.deletingLastPathComponent().appendingPathComponent(".mount-recovery.lock")
    try? FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let lockFD = open(lockURL.path, O_CREAT | O_RDWR, mode_t(0o600))
    guard lockFD >= 0 else {
        outcome.deferredVolumeKeys = RecoveryRoundPlanner.deferRound(configuration: config).deferredIdentities
        return outcome
    }
    defer { close(lockFD) }
    guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
        outcome.deferredVolumeKeys = RecoveryRoundPlanner.deferRound(configuration: config).deferredIdentities
        return outcome
    }
    defer { flock(lockFD, LOCK_UN) }

    // 快照：锁内载入账本与状态诊断（诊断文案留在 CLI 的本地化层）。
    let load = MountRecoveryStore.load(from: stateURL)
    if case .corrupt(let reason) = load {
        // 只呈现程序定义的类别，禁止将任意输入或凭据带入诊断。
        let category: String
        switch reason {
        case "state file unreadable or not a plist dictionary":
            category = tr("状态不可读或格式损坏", "state unreadable or invalid plist")
        case "state file missing schema_version":
            category = tr("缺少状态版本", "missing state version")
        case let value where value.hasPrefix("unknown schema_version "):
            category = tr("未知状态版本", "unknown state version")
        default:
            category = tr("状态内容损坏", "invalid state contents")
        }
        outcome.stateDiagnostic = tr("  · 恢复状态异常（\(category)）；缺失卷保守跳过，请在配置菜单选择“立即重新挂载”。",
                                     "  · Recovery state error (\(category)); missing volumes are conservatively skipped. Use Remount now in the configuration menu.")
    }

    // 会话边界与主机探活都是真实副作用，仍由 CLI 采集。
    // 单轮内按 host:port 记忆化：顺序与合并前的 ReachabilityCache 完全一致
    // （先顺位探测，再逐卷复用同一结果），同一主机不会重复探测。
    let boundaryIdentity = SessionBoundaryIdentity.current(previous: load.file.sessionBoundary)
    var reachabilityCache: [String: Bool] = [:]
    let probe: (String, Int) -> Bool = { host, port in
        let key = "\(host):\(port)"
        if let cached = reachabilityCache[key] { return cached }
        let reachable = hostReachability(host, port)
        reachabilityCache[key] = reachable
        return reachable
    }
    let sessionIdentity = RecoverySessionIdentity(network: boundaryIdentity.network,
        loginEpoch: boundaryIdentity.loginEpoch, previous: load.file.sessionBoundary)
    let volumes = RecoveryRoundPlanner.relevantVolumes(configuration: config,
        mountedIdentities: Set(mountTable.keys), probe: probe)

    let request = RecoveryRoundRequest(configuration: config, load: load,
        sessionNetwork: sessionIdentity.network, sessionLoginEpoch: sessionIdentity.loginEpoch,
        mountedIdentities: Set(mountTable.keys), manualRecovery: manualRecovery, volumes: volumes)
    let effects = RecoveryRoundEffects(
        cleanup: { path in cleanupVolume(path) },
        mount: { identity in
            guard let volume = volumes.first(where: { $0.identity == identity }) else {
                return RecoveryMountAttempt(succeeded: false, failure: MountExecutionBudget.lastFailure)
            }
            MountExecutionBudget.lastFailure = .shareRejected
            let succeeded = applyRecovery(volume, config)
            return RecoveryMountAttempt(succeeded: succeeded,
                failure: succeeded ? .mounted : MountExecutionBudget.lastFailure)
        },
        budgetRemaining: { MountExecutionBudget.deadline?.timeIntervalSinceNow ?? 0 })

    let result = RecoveryRoundPlanner.run(request: request, observe: { volume in
        let present = mountTable[volume.identity] != nil
        let reachable = hostReachability(volume.host, volume.port)
        var health: VolumeHealthEvidence = .unavailable
        if present, reachable, let path = mountTable[volume.identity] {
            let probe = volumeHealth?(path) ?? boundedVolumeHealth(at: path)
            health = RecoveryRoundPlanner.healthEvidence(probe)
        }
        return RecoveryRoundVolumeSnapshot(identity: volume.identity, mountPoint: volume.mountPoint,
            host: volume.host, port: volume.port, presentInMountTable: present,
            observedPath: mountTable[volume.identity], hostReachable: reachable, health: health)
    }, effects: effects)

    outcome.recovered = result.recovered
    outcome.failed = result.failed
    outcome.suppressed = result.suppressed
    outcome.attempted = result.attempted
    outcome.notificationKeys = result.notificationIdentities
    outcome.deferredVolumeKeys = result.deferredIdentities

    if writeState && !MountRecoveryStore.save(result.state, to: stateURL) {
        fputs(tr("⚠ 恢复状态保存失败；请使用配置菜单重新挂载。\n", "⚠ Recovery state could not be saved; use Remount now in the configuration menu.\n"), stderr)
    }
    return outcome
}

/// 兜底通知（T016）：每轮至多一条、合并列出、会话级上限 2 条、双语字面。
/// 返回 nil = 本轮不发通知。
func recoveryFallbackNotificationText(for outcome: RecoveryRoundOutcome, config: AutomntConfig) -> (title: String, subtitle: String, message: String)? {
    let unresolved = Set(outcome.failed).subtracting(outcome.recovered)
    let affected = Array(Set(outcome.notificationKeys).intersection(unresolved)).sorted()
    guard !affected.isEmpty else { return nil }
    return FailureNotification(failed: Set(outcome.failed), recovered: Set(outcome.recovered),
                               eligible: Set(affected))?.text(english: isEnglish)
}

func installLaunchAgent() {
    print(tr("""
    automnt - 安装并启用自启动守护服务
    ===========================================
    """, """
    automnt - Install LaunchAgent Daemon
    ============================================
    """))
    // T022 owner-aware：注册前先经统一 owner/generation 预检。
    // app 持有时拒绝抢占；backend-state.plist 缺失时建立明确 owner=none/stopped。
    if let refusal = CLIOwnership.registrationRefusal() {
        fputs(refusal + "\n", stderr)
        return
    }
    let binary = getActiveInstalledBinaryURL()
    if !FileManager.default.fileExists(atPath: binary.path) {
        InstallationManager.relocateIfNeeded()
    }
    guard BinarySigningPolicy.trustedCode(at: binary) != nil else {
        fputs(tr("✗ 服务安装已停止：需要标识为 automnt 的有效 Apple Development 或 Developer ID Application 签名。\n",
                 "✗ Service installation stopped: a valid Apple Development or Developer ID Application signature with identifier automnt is required.\n"), stderr)
        return
    }
    InstallationManager.injectShellEntry()
    // 经共享协调器提交 owner=cli，注册与提交都由系统真实状态判定。
    // 守护运行态按既有契约跳过注册，故不计为成功。
    let registration = CLIOwnership.performRegistration()
    let success = registration == .registered
    let plistURL = getLaunchAgentPlistURL()
    let triggerDescription = (loadConfig()?.isAutoMountRecoveryEnabled ?? true)
        ? tr("登录、系统网络配置变化与挂载命名空间变化事件驱动", "Login, network changes, and mount namespace changes")
        : tr("登录与系统网络配置变化事件驱动", "Login and network changes")
    if success {
        print(tr("✓ 已生成服务描述文件:\n  \(plistURL.path)", "✓ Generated LaunchAgent plist:\n  \(plistURL.path)"))
        print(tr("✓ 成功注册并加载至系统 launchd 守护进程 (gui/\(getuid()))",
                 "✓ Successfully registered and loaded into system launchd (gui/\(getuid()))"))
        print(tr("""

        服务详情:
          • 标识 (Label): \(launchAgentLabel)
          • 执行命令: \(binary.path)
          • 触发时机: \(triggerDescription)
          • 日志路径: ~/Library/Logs/automnt/stdout.log

        自启动与网络监听服务已生效。
        """, """

        Service Details:
          • Label: \(launchAgentLabel)
          • Command: \(binary.path)
          • Trigger: \(triggerDescription)
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

    // T022 owner-aware：后端由 app 持有时不得以 CLI 身份注销其服务定义。
    // 仅跳过服务注销与 plist 删除；CLI 自己的 Shell 入口/可执行文件/配置清理照常执行。
    let appOwned = CLIOwnershipGate.refusesAppClaim(try? CLIOwnership.durableState())
    if appOwned {
        fputs(tr("⚠ 后台服务当前由 Automnt 应用管理；已跳过后台服务注销，以免抢占。请在应用内停用后台服务。\n",
                 "⚠ The background service is managed by the Automnt app; service unregistration was skipped to avoid preemption. Disable it in the app.\n"), stderr)
    }

    let bootResult = appOwned
        ? (status: Int32(-1), stdout: "", stderr: "")
        : runCommand(executable: "/bin/launchctl", arguments: ["bootout", serviceTarget])
    if bootResult.status == 0 {
        print(tr("✓ 成功从系统 launchd 中卸载服务 (\(serviceTarget))",
                 "✓ Unloaded service from system launchd (\(serviceTarget))"))
    }

    if !appOwned, FileManager.default.fileExists(atPath: plistURL.path) {
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
    let installedBinaryPresent = FileManager.default.isExecutableFile(atPath: installState.installedBinaryPath)
    print(tr("  • 已安装程序存在: \(installedBinaryPresent ? "✓ 是" : "✗ 否")",
             "  • Installed executable present: \(installedBinaryPresent ? "✓ Yes" : "✗ No")"))
    print(tr("  • Shell CLI 入口: \(installState.isCliEntryPresent ? "✓ 正常" : "✗ 缺失")",
             "  • Shell CLI Snippet: \(installState.isCliEntryPresent ? "✓ Present" : "✗ Missing")"))
    print(tr("  • 守护服务登记: \(installState.isServiceRegistered ? "✓ 已注册" : "✗ 未注册")",
             "  • Service Registered: \(installState.isServiceRegistered ? "✓ Registered" : "✗ Not Registered")"))
    print(tr("  • 描述文件合规: \(installState.isServicePlistValid ? "✓ 合规" : "✗ 异常")",
             "  • Plist Valid: \(installState.isServicePlistValid ? "✓ Valid" : "✗ Invalid")"))

    print(tr("\n配置与守护服务:", "\nConfiguration & Daemon:"))
    print(tr("  • 唯一活动配置: \(activeConfigURL.path)", "  • Active Config: \(activeConfigURL.path)"))
    print(tr("  • 守护服务状态: \(getLaunchAgentStatusSummary())", "  • Service Summary: \(getLaunchAgentStatusSummary())"))
    print(cliRecoveryStatusLine())

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
    // 自测模式禁止真实弹窗（用户可见副作用），仅记录以便断言。
    if DaemonRuntime.isSelfTestMode {
        SelfTestNotificationRecorder.record(title: title, subtitle: subtitle, message: message)
        return
    }
    let script = "display notification \(quoteAppleScript(message)) with title \(quoteAppleScript(title)) subtitle \(quoteAppleScript(subtitle))"
    _ = runCommandDiscardingOutputWithTimeout(executable: "/usr/bin/osascript",
                                              arguments: ["-e", script], timeout: 2)
}

/// 自测期通知记录器：让通知行为可断言且不触碰用户桌面。
enum SelfTestNotificationRecorder {
    private static let recordedBox = LockedBox<[(title: String, subtitle: String, message: String)]>([])
    static var recorded: [(title: String, subtitle: String, message: String)] {
        get { recordedBox.value }
        set { recordedBox.value = newValue }
    }
    static func record(title: String, subtitle: String, message: String) {
        recorded.append((title, subtitle, message))
    }
    static func reset() { recorded.removeAll() }
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
    // 结果经受锁容器跨回调线程回传：写入在 signal 之前、读取在 wait 之后，
    // 用 `LockedBox` 显式表达该同步关系（而非依赖可变捕获）。
    let fetchResultBox = LockedBox<ReleaseFetchResult>(.noRelease)

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }
        if let error = error {
            fetchResultBox.value = .networkError(error.localizedDescription)
            return
        }
        guard let http = response as? HTTPURLResponse else {
            fetchResultBox.value = .networkError("Invalid response")
            return
        }
        if http.statusCode == 403 || http.statusCode == 429 {
            fetchResultBox.value = .rateLimited
            return
        }
        guard http.statusCode == 200, let data = data else {
            fetchResultBox.value = .noRelease
            return
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tag = json["tag_name"] as? String {
            let name = json["name"] as? String ?? tag
            let body = json["body"] as? String ?? ""
            let htmlURL = json["html_url"] as? String ?? ""
            fetchResultBox.value = .success(GitHubReleaseInfo(tagName: tag, name: name, body: body, htmlURL: htmlURL))
        }
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + 15)
    return fetchResultBox.value
}

func downloadLatestBinary(tag: String) -> Data? {
    let cleanTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    let urlString = "https://github.com/\(githubRepo)/releases/download/\(cleanTag)/automnt"
    guard let url = URL(string: urlString) else { return nil }

    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    request.setValue("automnt/\(automntVersion)", forHTTPHeaderField: "User-Agent")

    let semaphore = DispatchSemaphore(value: 0)
    // 同 `fetchLatestReleaseInfo`：受锁容器显式表达跨线程同步回传。
    let resultDataBox = LockedBox<Data?>(nil)

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }
        if let http = response as? HTTPURLResponse, http.statusCode == 200, let d = data, !d.isEmpty {
            resultDataBox.value = d
        }
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + 35)
    return resultDataBox.value
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

        guard BinarySigningPolicy.permitsReplacement(candidate: stagedBinary, installed: targetURL) else {
            writeLog("Update rejected: invalid signing identity or incompatible designated requirement")
            if !isSilent {
                fputs(tr("✗ 更新已停止：代码签名无效或身份不兼容；原版本保留。\n",
                         "✗ Update stopped: invalid signature or incompatible identity; existing version preserved.\n"), stderr)
            }
            return false
        }
        let versionOutputURL = tempDir.appendingPathComponent("version-output")
        guard FileManager.default.createFile(atPath: versionOutputURL.path, contents: nil) else { return false }
        let versionOutput = try FileHandle(forWritingTo: versionOutputURL)
        defer { try? versionOutput.close() }
        let valResult = runCommandDiscardingOutputWithTimeout(executable: stagedBinary.path,
            arguments: ["--version"], timeout: 2, standardOutputFile: versionOutput)
        guard !valResult.timedOut, valResult.status == 0,
              let outputSize = try FileManager.default.attributesOfItem(atPath: versionOutputURL.path)[.size] as? NSNumber,
              outputSize.intValue <= 128 else { return false }
        let reportedVersion = try String(contentsOf: versionOutputURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !valResult.timedOut, valResult.status == 0, reportedVersion == newVersion else {
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
    let configKey = getConfigURL().standardizedFileURL.path
    guard let initialRevision = configurationDraftRevisions[configKey] else { return }
    config.lastUpdateCheckTimestamp = now
    guard saveConfig(config, expectedRevision: initialRevision),
          let checkedRevision = configurationDraftRevisions[configKey] else { return }

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
            _ = saveConfig(config, expectedRevision: checkedRevision)
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
    try? PrivateAtomicFile.replace(Data("not a plist".utf8), at: invalidURL)
    let invalidConfig = inspectConfigFile(at: invalidURL)
    check(invalidConfig.state == .invalid, "config inspection distinguishes a malformed file")

    let dirURL = tempDir.appendingPathComponent("is-a-dir")
    try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
    let dirConfig = inspectConfigFile(at: dirURL)
    check(dirConfig.state == .inaccessible, "config inspection refuses a directory")

    // 2. Backup & Prune tests (FR-024, SC-016)
    let sampleData = Data("<plist version=\"1.0\"><dict><key>test</key><string>val</string></dict></plist>".utf8)
    let sampleURL = tempDir.appendingPathComponent("sample.plist")
    try? PrivateAtomicFile.replace(sampleData, at: sampleURL)
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
    if let legacyData = legacyXML.data(using: .utf8) { try? PrivateAtomicFile.replace(legacyData, at: migrationURL) }
    var loadedLegacy = loadConfig(from: migrationURL, migrate: false)!
    let migrationSuccess = migrateConfigIfNeeded(config: &loadedLegacy, at: migrationURL)
    check(migrationSuccess, "config migration executes successfully")
    check(loadedLegacy.version == automntVersion, "migrated version is updated to current")
    check(loadedLegacy.hosts.first?.host == "nas.local", "migrated host is updated to hosts")
    check(loadedLegacy.hosts.first?.shares.first?.mountPoint == "/Volumes/share", "migrated share mountPoint is /Volumes/share with -1 cleaned")
    let postMigrationString = (try? String(contentsOf: migrationURL, encoding: .utf8)) ?? ""
    check(postMigrationString.contains("custom_root_field") && postMigrationString.contains("custom_value"),
          "migration preserves unknown plist fields")

    let migrationShare = UUID().uuidString
    let migrationURLInput = "smb://\(UUID().uuidString)/\(migrationShare)"
    let customPath = tempDir.appendingPathComponent(migrationShare).path
    check(migratedMountPoint(url: migrationURLInput, path: customPath) == customPath,
          "migration preserves explicit custom mount directories")
    check(migratedMountPoint(url: migrationURLInput, path: "/Volumes/\(migrationShare)-1") == "/Volumes/\(migrationShare)",
          "migration normalizes only legacy standard-path numeric conflict suffixes")
    let identityHost = UUID().uuidString
    check(smbResourceIdentity("smb://\(identityHost):1445/\(migrationShare)") != smbResourceIdentity("smb://\(identityHost)/\(migrationShare)"),
          "nondefault SMB ports retain separate resource identities")
    check(smbResourceIdentity("smb://\(identityHost):445/\(migrationShare)") == smbResourceIdentity("smb://\(identityHost)/\(migrationShare)"),
          "explicit default SMB port preserves legacy recovery identity")

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

    try? Data("rollback candidate".utf8).write(to: src1)
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dst1.path)
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
    check(rollbackPassed, "transactional file replacement restores distinct original bytes on action error")
    let rollbackPermissions = ((try? FileManager.default.attributesOfItem(atPath: dst1.path))?[.posixPermissions] as? NSNumber)?.intValue
    check(rollbackPermissions == 0o700, "transactional rollback restores original executable permissions")

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

    let boundedOutputURL = tempDir.appendingPathComponent("bounded-version-output")
    FileManager.default.createFile(atPath: boundedOutputURL.path, contents: nil)
    let boundedOutputHandle = try? FileHandle(forWritingTo: boundedOutputURL)
    let boundedOutputResult = runCommandDiscardingOutputWithTimeout(executable: "/bin/sh",
        arguments: ["-c", "printf '3.3.0\\n'; exec /bin/sleep 2"], timeout: 0.05,
        standardOutputFile: boundedOutputHandle)
    try? boundedOutputHandle?.close()
    check(boundedOutputResult.timedOut && boundedOutputResult.processStopped &&
          (try? String(contentsOf: boundedOutputURL, encoding: .utf8)) == "3.3.0\n",
          "version output before a stalled child is captured but still rejected on timeout")

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
    check(!BinarySigningPolicy.permitsReplacement(candidate: downloadBin, installed: nil),
          "installation rejects unsigned non-executable content before running it")
    check(!BinarySigningPolicy.permitsReplacement(candidate: URL(fileURLWithPath: "/usr/bin/true"), installed: nil),
          "Apple platform signature alone cannot impersonate a Developer ID application")
    check(!BinarySigningPolicy.permitsReplacement(candidate: InstallationManager.currentExecutablePhysicalURL(), installed: downloadBin),
          "update rejects an unsigned existing identity without implicit migration")

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
        try? PrivateAtomicFile.replace(data, at: zeroHostURL)
        check(inspectConfigFile(at: zeroHostURL).state == .usable,
              "inspectConfigFile treats zero-host config as usable rather than invalid")
    }

    // HostConfig & SMBShareConfig serialization (T003)
    let testShare = SMBShareConfig(name: "Data", smbURL: "smb://10.0.0.1/Data", mountPoint: "/Volumes/Data")
    let testHost = HostConfig(host: "10.0.0.1", alias: "My NAS", port: 445, timeoutMs: 1200, shares: [testShare])
    let multiHostConfig = AutomntConfig(version: automntVersion, hosts: [testHost])
    let multiHostURL = tempDir.appendingPathComponent("multi_host.plist")
    if let data = try? PropertyListEncoder().encode(multiHostConfig) {
        try? PrivateAtomicFile.replace(data, at: multiHostURL)
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

    // Shared repository writes must not overwrite an older CLI draft.
    let conflictDirectory = tempDir.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: conflictDirectory, withIntermediateDirectories: false)
    let conflictURL = conflictDirectory.appendingPathComponent("automnt.plist")
    var conflictConfig = AutomntConfig(version: automntVersion)
    check(saveConfig(conflictConfig, to: conflictURL), "CLI creates configuration through shared private writer")
    if let draft = loadConfig(from: conflictURL), let captured = configurationDraftRevisions[conflictURL.path] {
        let repository = FileConfigRepository(authorizedDirectory: conflictDirectory)
        if let snapshot = try? repository.read() {
            var concurrent = snapshot.configuration
            concurrent.automationEnabled = false
            let saved = try? repository.save(concurrent, baseRevision: snapshot.revision)
            check(saved != nil, "shared repository edits CLI-created configuration")
            check(!saveConfig(draft, to: conflictURL, requireAbsent: true), "CLI initialization refuses configuration created during its wizard")
            check(!saveConfig(draft, to: conflictURL, expectedRevision: captured), "CLI refuses a stale draft after shared repository edit")
            check((try? repository.read().configuration.automationEnabled) == false, "stale CLI save preserves concurrent automation change")
            if let refreshed = loadConfig(from: conflictURL) {
                conflictConfig = refreshed
                conflictConfig.updateChannel = "notify"
                check(saveConfig(conflictConfig, to: conflictURL), "explicit CLI reload allows new save")
            }
            do {
                let held = try StableFileLock(url: conflictDirectory.appendingPathComponent("config.lock"))
                withExtendedLifetime(held) {
                    check(!saveConfig(conflictConfig, to: conflictURL), "CLI rejects an occupied shared configuration lock")
                }
            } catch { check(false, "shared configuration lock is available for contention test") }
            if var invalidDraft = loadConfig(from: conflictURL) {
                let validBytes = try? PrivateAtomicFile.read(conflictURL)
                invalidDraft.hosts = [HostConfig(host: UUID().uuidString, port: 0)]
                check(!saveConfig(invalidDraft, to: conflictURL), "CLI shared validation rejects invalid port")
                check((try? PrivateAtomicFile.read(conflictURL)) == validBytes, "CLI validation failure preserves saved configuration")
            }
            let safeBytes = try? PrivateAtomicFile.read(conflictURL)
            _ = chmod(conflictURL.path, 0o644)
            check(loadConfig(from: conflictURL) == nil, "CLI refuses broad-permission configuration reads")
            check(inspectConfigFile(at: conflictURL).state == .inaccessible, "CLI inspection exposes unsafe permission state")
            _ = chmod(conflictURL.path, 0o600)
            check((try? PrivateAtomicFile.read(conflictURL)) == safeBytes, "permission rejection leaves configuration bytes unchanged")
            if var migrationDraft = loadConfig(from: conflictURL, migrate: false), let latest = try? repository.read() {
                migrationDraft.version = "0.0.0"
                var replacement = latest.configuration
                replacement.updateChannel = "off"
                _ = try? repository.save(replacement, baseRevision: latest.revision)
                check(!migrateConfigIfNeeded(config: &migrationDraft, at: conflictURL), "CLI migration refuses stale configuration bytes")
                check((try? repository.read().configuration.updateChannel) == "off", "stale migration preserves concurrent channel change")
            }
        } else { check(false, "shared repository reads CLI-created configuration") }
    } else { check(false, "CLI captures initial configuration revision") }

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
              Array(repeating: .down, count: 9) + [.enter]
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
                               Array(repeating: .down, count: 8) + [.enter])
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
                           Array(repeating: .down, count: 7) + [.enter])
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
                                  .down, .down, .down, .down, .down, .down, .down, .down, .enter]
    manageConfiguration()
    check(inspectConfigFile(at: stagedConfigURL).config?.updateChannel == "notify",
          "management Save and exit persists staged changes")
    TerminalUI.mockKeySequence = nil
    isTTYOverride = nil
    configURLOverride = nil

    // 11. 挂载丢失自动恢复（Feature 004）：配置开关、状态层、边界与判别状态机

    // T002: 开关字段编解码、缺省语义、白名单落盘
    let defaultRecoveryConfig = AutomntConfig(version: automntVersion)
    check(defaultRecoveryConfig.isAutoMountRecoveryEnabled,
          "recovery switch defaults to enabled when the key is absent")
    let disabledRecoveryConfig = AutomntConfig(version: automntVersion, autoMountRecovery: false)
    check(!disabledRecoveryConfig.isAutoMountRecoveryEnabled,
          "recovery switch reads explicit false as disabled")

    let recoveryConfigURL = tempDir.appendingPathComponent("recovery_switch.plist")
    var switchConfig = AutomntConfig(version: automntVersion,
                                     hosts: [HostConfig(host: "switch.example",
                                                        shares: [SMBShareConfig(name: "S", smbURL: "smb://switch.example/S", mountPoint: "/Volumes/S")])])
    check(saveConfig(switchConfig, to: recoveryConfigURL), "recovery switch fixture saved through program API")
    // 关键：开关必须真正落盘生效（若未加入 managedConfigKeys 白名单会被当未知键保留原值）
    switchConfig.autoMountRecovery = false
    check(saveConfig(switchConfig, to: recoveryConfigURL), "recovery switch disabled value persisted")
    let reloadedSwitchConfig = loadConfig(from: recoveryConfigURL, migrate: false)
    check(reloadedSwitchConfig?.autoMountRecovery == false,
          "recovery switch persists false through the config whitelist (not silently dropped)")
    check(reloadedSwitchConfig?.isAutoMountRecoveryEnabled == false,
          "persisted false disables automatic recovery")
    // 既有配置（无该键）原地升舱不破坏
    let legacyNoSwitchURL = tempDir.appendingPathComponent("recovery_legacy.plist")
    check(saveConfig(AutomntConfig(), to: legacyNoSwitchURL), "legacy default config generated through program API")
    let legacyNoSwitch = loadConfig(from: legacyNoSwitchURL, migrate: false)
    check(legacyNoSwitch?.isAutoMountRecoveryEnabled == true,
          "in-place migration keeps legacy configs on the default enabled switch")

    // T117：挂载范围与 GUI 写同一 mount_policy 字段，缺省 first_reachable 保持既有行为。
    let mountScopeURL = tempDir.appendingPathComponent("mount_scope.plist")
    var scopeConfig = AutomntConfig(version: automntVersion, updateChannel: "off",
                                    hosts: [HostConfig(host: "scope.example",
                                                       shares: [SMBShareConfig(name: "S", smbURL: "smb://scope.example/S", mountPoint: "/Volumes/S")])])
    check(saveConfig(scopeConfig, to: mountScopeURL), "mount scope fixture saved through program API")
    check(!scopeConfig.isMountAllEnabled, "mount scope defaults to first reachable server")
    scopeConfig.mountPolicy = .allReachable
    check(saveConfig(scopeConfig, to: mountScopeURL), "mount scope all-reachable value persisted")
    check(loadConfig(from: mountScopeURL, migrate: false)?.isMountAllEnabled == true,
          "mount scope persists through the config whitelist (not silently dropped)")
    check(loadConfig(from: mountScopeURL, migrate: false)?.effectiveMountPolicy == .allReachable,
          "persisted all-reachable resolves as the effective policy")
    // 菜单入口：与自动恢复开关一样只改工作副本，保存并退出后才落盘。
    let scopeMenuURL = tempDir.appendingPathComponent("mount_scope_menu.plist")
    check(saveConfig(AutomntConfig(version: automntVersion, updateChannel: "off",
                                   hosts: [HostConfig(host: "scope-menu.example")]), to: scopeMenuURL),
          "mount scope menu fixture saved through program API")
    configURLOverride = scopeMenuURL
    isTTYOverride = false
    TerminalUI.mockKeySequence = Array(repeating: .down, count: 7) + [.enter] +
        Array(repeating: .down, count: 8) + [.enter]
    manageConfiguration()
    TerminalUI.mockKeySequence = nil
    isTTYOverride = nil
    configURLOverride = nil
    check(loadConfig(from: scopeMenuURL, migrate: false)?.isMountAllEnabled == true,
          "configuration menu switches mount scope and persists it on Save and exit")

    // T003: 附属状态文件读写、0600、损坏降级、absent 与 corrupt 区分
    let stateURL = tempDir.appendingPathComponent("recovery_state_isolated").appendingPathComponent(mountRecoveryStateFileName)
    check(MountRecoveryStore.load(from: stateURL) == .absent,
          "missing state file is treated as a normal empty state (not corruption)")
    check(MountRecoveryStore.load(from: stateURL).isReadable,
          "missing state file stays readable so FR-002④ may apply")
    var stateFixture = MountRecoveryStateFile()
    stateFixture.volumes["//nas.example/share"] = MountRecoveryVolumeRecord(
        volumeKey: "//nas.example/share", state: .suppressed,
        suppressionBoundary: "boundary-a", everHealthyMounted: true, updatedAt: 1)
    stateFixture.cleanupLedger["//nas.example/other"] = 2
    check(MountRecoveryStore.save(stateFixture, to: stateURL), "recovery state file saved atomically")
    let perms = (try? FileManager.default.attributesOfItem(atPath: stateURL.path)[.posixPermissions] as? NSNumber)?.intValue
    check(perms == 0o600, "recovery state file is written with 0600 permissions")
    if case .loaded(let loadedFixture) = MountRecoveryStore.load(from: stateURL) {
        check(loadedFixture.volumes["//nas.example/share"]?.everHealthyMounted == true,
              "everHealthyMounted persists across reload (mount ledger survives a missing volume)")
        check(loadedFixture.cleanupLedger["//nas.example/other"] != nil, "cleanup ledger persists across reload")
    } else {
        check(false, "recovery state file round-trips through the loader")
    }
    // 损坏文件 → corrupt（保守方向），绝非 absent
    try? Data("not a plist".utf8).write(to: stateURL)
    let corruptLoad = MountRecoveryStore.load(from: stateURL)
    check(!corruptLoad.isReadable, "corrupt state file is reported as unreadable (conservative path)")
    check(corruptLoad != .absent, "corrupt state file is never mistaken for a normal empty state")
    // 未知 schemaVersion → corrupt
    let unknownVersion = MountRecoveryStateFile(schemaVersion: 999, sessionBoundary: nil, volumes: [:], cleanupLedger: [:])
    if let data = try? PropertyListEncoder().encode(unknownVersion) {
        try? data.write(to: stateURL)
    }
    check(!MountRecoveryStore.load(from: stateURL).isReadable,
          "unknown schemaVersion discards state and goes conservative")

    // T004: 会话边界——要素变化算边界，仅链路抖动不算
    let snapshotA = NetworkContextSnapshot(identity: "a", components: ["v4:1.1.1.1", "gw:10.0.0.1"])
    let snapshotSameElements = NetworkContextSnapshot(identity: "a", components: ["v4:1.1.1.1", "gw:10.0.0.1"])
    NetworkContextIdentity.testOverride = snapshotA
    let boundaryA = SessionBoundaryIdentity.current()
    NetworkContextIdentity.testOverride = snapshotSameElements
    let boundarySame = SessionBoundaryIdentity.current()
    check(boundaryA.combined == boundarySame.combined,
          "identical network context does not constitute a session boundary")
    NetworkContextIdentity.testOverride = NetworkContextSnapshot(identity: "b", components: ["v4:2.2.2.2", "gw:10.0.0.1"])
    let boundaryChanged = SessionBoundaryIdentity.current()
    check(boundaryChanged.combined != boundaryA.combined,
          "changed interface element constitutes a session boundary")
    LoginSessionEpoch.testOverride = "epoch-2"
    let boundaryRelogin = SessionBoundaryIdentity.current()
    check(boundaryRelogin.combined != boundaryChanged.combined,
          "re-login constitutes a session boundary (whichever comes first)")
    LoginSessionEpoch.testOverride = nil
    NetworkContextIdentity.testOverride = nil

    // T005: 可注入判定输入（挂载表存在性 + 主机可达性）
    check(getKernelMountEntries().count >= 0, "kernel mount snapshot stays non-blocking and injectable")

    // T006: 三重信号判别状态机全分支
    let ledgerKey = "//nas.example/share"
    let cleanupOnly: [String: Double] = [ledgerKey: 1]
    let healthyRecord = MountRecoveryVolumeRecord(volumeKey: ledgerKey, everHealthyMounted: true)
    let neverRecord = MountRecoveryVolumeRecord(volumeKey: ledgerKey, everHealthyMounted: false)
    let repairRecord = MountRecoveryVolumeRecord(volumeKey: ledgerKey,
                                                 repairEjectEvidence: true, everHealthyMounted: true)
    check(judgeRecoverySignal(volumeKey: ledgerKey, presentInMountTable: true, hostReachable: false,
                              record: healthyRecord, cleanupLedger: [:], stateReadable: true) == .deadButPresent,
          "signal 1: present-but-unreachable volume is classified as network loss")
    check(judgeRecoverySignal(volumeKey: ledgerKey, presentInMountTable: true, hostReachable: true,
                              record: healthyRecord, cleanupLedger: [:], stateReadable: true) == .attachedHealthy,
          "signal 1 inverse: healthy reachable mount requires no recovery")
    check(judgeRecoverySignal(volumeKey: ledgerKey, presentInMountTable: false, hostReachable: true,
                              record: healthyRecord, cleanupLedger: cleanupOnly, stateReadable: true) == .productCleanup,
          "signal 2: missing volume recorded in the cleanup ledger is recoverable")
    check(judgeRecoverySignal(volumeKey: ledgerKey, presentInMountTable: false, hostReachable: true,
                              record: repairRecord, cleanupLedger: [:], stateReadable: true) == .repairEject,
          "signal 3: repair ejection is recoverable")
    check(judgeRecoverySignal(volumeKey: ledgerKey, presentInMountTable: false, hostReachable: true,
                              record: healthyRecord, cleanupLedger: [:], stateReadable: true) == .healthyEject,
          "signal 4: healthy ejection enters session suppression")
    check(judgeRecoverySignal(volumeKey: ledgerKey, presentInMountTable: false, hostReachable: true,
                              record: neverRecord, cleanupLedger: [:], stateReadable: true) == .neverMounted,
          "signal 5: never-mounted enabled volume is not treated as user intent to eject")
    check(judgeRecoverySignal(volumeKey: ledgerKey, presentInMountTable: false, hostReachable: true,
                              record: healthyRecord, cleanupLedger: [:], stateReadable: false) == .unknownConservative,
          "signal 6: unreadable state goes conservative instead of auto-mounting")
    check(judgeRecoverySignal(volumeKey: ledgerKey, presentInMountTable: false, hostReachable: true,
                              record: neverRecord, cleanupLedger: [:], stateReadable: false) == .unknownConservative,
          "FR-010: corrupt state is never reinterpreted as the never-mounted branch")
    check(!RecoverySignal.unknownConservative.isRecoverable && RecoverySignal.unknownConservative.isSuppressed,
          "unknown signal falls back to suppression (conservative direction)")
    check(RecoverySignal.neverMounted.isRecoverable && !RecoverySignal.neverMounted.isSuppressed,
          "never-mounted volumes are recoverable and never suppressed")
    check(RecoverySignal.healthyEject.isSuppressed && !RecoverySignal.healthyEject.isRecoverable,
          "healthy ejection is suppressed within the session")

    // 恢复编排回归：只在隔离目录/内存执行，不访问真实 SMB 或 launchd。
    VolumeHealthProbe.testOverride = { _ in true }
    defer { VolumeHealthProbe.testOverride = nil }
    let roundURL = tempDir.appendingPathComponent("round-state.plist")
    let roundConfig = AutomntConfig(retryPolicy: RetryPolicy(maxAttempts: 2, intervalMs: 100, maxTotalWindowMs: 1000), hosts: [
        HostConfig(host: "first.example", shares: [SMBShareConfig(name: "A", smbURL: "smb://first.example/A", mountPoint: "/Volumes/A")]),
        HostConfig(host: "second.example", shares: [SMBShareConfig(name: "B", smbURL: "smb://second.example/B", mountPoint: "/Volumes/B")])])
    let firstKey = configuredVolumes(from: roundConfig)[0].key
    let secondKey = configuredVolumes(from: roundConfig)[1].key
    LoginSessionEpoch.testOverride = "round-login"
    NetworkContextIdentity.testOverride = snapshotA
    let roundBoundary = SessionBoundaryIdentity.current().combined
    var calls = 0
    func round(_ table: [String: String] = [:], manual: Bool = false, success: Bool = true) -> RecoveryRoundOutcome {
        runRecoveryRound(config: roundConfig, mountTable: table, hostReachability: { _, _ in true },
                         stateURL: roundURL, applyRecovery: { _, _ in calls += 1; return success },
                         manualRecovery: manual)
    }
    let contentionDir = tempDir.appendingPathComponent("lock-contention")
    try? FileManager.default.createDirectory(at: contentionDir, withIntermediateDirectories: true)
    let contentionState = contentionDir.appendingPathComponent("state.plist")
    let contentionLock = contentionDir.appendingPathComponent(".mount-recovery.lock")
    let heldFD = open(contentionLock.path, O_CREAT | O_RDWR, mode_t(0o600))
    let held = heldFD >= 0 && flock(heldFD, LOCK_EX | LOCK_NB) == 0
    var contentionCalls = 0
    let deferred = runRecoveryRound(config: roundConfig, mountTable: [:], hostReachability: { _, _ in true },
        stateURL: contentionState, applyRecovery: { _, _ in contentionCalls += 1; return true })
    check(held && Set(deferred.deferredVolumeKeys) == Set([firstKey, secondKey]) && deferred.suppressed.isEmpty,
          "held recovery lock defers evaluation without claiming manual-eject suppression")
    check(contentionCalls == 0 && !deferred.hasVisibleFallbackTrigger && deferred.notificationKeys.isEmpty &&
          !FileManager.default.fileExists(atPath: contentionState.path),
          "lock contention performs no mount, notification, or state write")
    if heldFD >= 0 { _ = flock(heldFD, LOCK_UN); close(heldFD) }
    let invalidLockDir = tempDir.appendingPathComponent("invalid-lock")
    try? FileManager.default.createDirectory(at: invalidLockDir.appendingPathComponent(".mount-recovery.lock"), withIntermediateDirectories: true)
    let unavailable = runRecoveryRound(config: roundConfig, mountTable: [:], hostReachability: { _, _ in true },
        stateURL: invalidLockDir.appendingPathComponent("state.plist"), applyRecovery: { _, _ in contentionCalls += 1; return true })
    check(unavailable.deferredVolumeKeys.count == 2 && unavailable.suppressed.isEmpty && contentionCalls == 0,
          "unopenable recovery lock preserves safe deferral without false suppression")
    var historical = MountRecoveryStateFile(sessionBoundary: roundBoundary)
    historical.volumes[firstKey] = MountRecoveryVolumeRecord(volumeKey: firstKey, everHealthyMounted: true)
    check(MountRecoveryStore.save(historical, to: roundURL), "round history is saved through state API")
    let ejected = round()
    check(ejected.suppressed == [firstKey] && calls == 0, "healthy eject stays suppressed and other hosts are excluded")
    check(ejected.notificationKeys.isEmpty, "healthy eject produces no failure notification")
    check(round().notificationKeys.isEmpty && round().notificationKeys.isEmpty &&
          MountRecoveryStore.load(from: roundURL).file.volumes[firstKey]?.notificationCount == 0,
          "repeated healthy eject evaluations remain silent without consuming notification budget")
    let stableSnapshot = NetworkContextIdentity.testOverride
    var protectedState = MountRecoveryStore.load(from: roundURL).file
    protectedState.volumes[firstKey]?.notificationCount = 2
    _ = MountRecoveryStore.save(protectedState, to: roundURL)
    NetworkContextIdentity.testOverride = NetworkContextSnapshot(identity: "", components: [], isReadable: false)
    let failedCollection = round()
    check(failedCollection.suppressed == [firstKey] && calls == 0 &&
          MountRecoveryStore.load(from: roundURL).file.sessionBoundary == protectedState.sessionBoundary &&
          MountRecoveryStore.load(from: roundURL).file.volumes[firstKey]?.notificationCount == 2,
          "unreadable network preserves eject protection, boundary and notification budget")
    NetworkContextIdentity.testOverride = stableSnapshot
    check(round().suppressed == [firstKey] && calls == 0,
          "collection recovery with unchanged identity never releases suppression")
    NetworkContextIdentity.testOverride = nil
    NetworkContextIdentity.componentsProvider = { nil }
    check(!NetworkContextIdentity.current().isReadable, "interface collection failure is distinct from a valid empty network")
    NetworkContextIdentity.componentsProvider = { [] }
    check(NetworkContextIdentity.current().isReadable && NetworkContextIdentity.current().identity.isEmpty,
          "successful empty network is a valid identity")
    NetworkContextIdentity.componentsProvider = nil
    NetworkContextIdentity.gatewayProvider = { (false, nil) }
    check(!NetworkContextIdentity.current().isReadable, "route failure invalidates the entire network snapshot")
    NetworkContextIdentity.gatewayProvider = nil
    check(!NetworkContextIdentity.parseGateway(status: 1, stdout: "", stderr: "permission denied").readable &&
          NetworkContextIdentity.parseGateway(status: 1, stdout: "", stderr: "route: writing to routing socket: not in table").readable,
          "explicit absent route is distinguished from route command failure")
    check(NetworkContextIdentity.parseGateway(status: 0, stdout: "gateway: 192.0.2.1", stderr: "").gateway == "192.0.2.1" &&
          !NetworkContextIdentity.parseGateway(status: 0, stdout: "unexpected", stderr: "").readable,
          "gateway parsing requires a complete successful route response")
    let savedDeadline = MountExecutionBudget.deadline
    MountExecutionBudget.deadline = Date().addingTimeInterval(-1)
    let routeStart = Date()
    check(!NetworkContextIdentity.defaultGatewayIdentity().readable && Date().timeIntervalSince(routeStart) < 0.2,
          "exhausted recovery budget prevents route launch and returns immediately")
    let savedStatus = MountExecutionBudget.netFSStatus
    MountExecutionBudget.netFSStatus = 42
    let savedNetworkOverride = NetworkContextIdentity.testOverride
    let savedSaveBlocked = MountRecoveryStore.mountRecoveryStoreSaveBlocked
    NetworkContextIdentity.testOverride = NetworkContextSnapshot(identity: "main-context", components: [])
    MountRecoveryStore.mountRecoveryStoreSaveBlocked = true
    let isolatedBudgetFinished = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        NetworkContextIdentity.testOverride = NetworkContextSnapshot(identity: "other-context", components: [])
        MountRecoveryStore.mountRecoveryStoreSaveBlocked = false
        MountExecutionBudget.deadline = Date().addingTimeInterval(60)
        MountExecutionBudget.netFSStatus = 77
        isolatedBudgetFinished.signal()
    }
    let isolatedBudgetCompleted = isolatedBudgetFinished.wait(timeout: .now() + 2) == .success
    check(isolatedBudgetCompleted && (MountExecutionBudget.deadline?.timeIntervalSinceNow ?? 0) < 0 &&
          MountExecutionBudget.netFSStatus == 42,
          "concurrent CLI thread cannot replace another operation deadline or NetFS result")
    check(isolatedBudgetCompleted && NetworkContextIdentity.current().identity == "main-context" &&
          MountRecoveryStore.mountRecoveryStoreSaveBlocked,
          "concurrent CLI thread cannot replace network or recovery-store injection")
    NetworkContextIdentity.testOverride = savedNetworkOverride
    MountRecoveryStore.mountRecoveryStoreSaveBlocked = savedSaveBlocked
    MountExecutionBudget.netFSStatus = savedStatus
    MountExecutionBudget.deadline = savedDeadline
    let timeoutStart = Date()
    let timeoutResult = runCommandDiscardingOutputWithTimeout(executable: "/bin/sleep", arguments: ["2"], timeout: 0.01)
    check(timeoutResult.timedOut && Date().timeIntervalSince(timeoutStart) < 0.8,
          "route subprocess timeout primitive stops waiting within its bounded termination allowance")
    var unknownBaseline = protectedState
    unknownBaseline.sessionBoundary = "<unreadable>|\(LoginSessionEpoch.current())"
    unknownBaseline.volumes[firstKey]?.suppressionBoundary = unknownBaseline.sessionBoundary
    _ = MountRecoveryStore.save(unknownBaseline, to: roundURL)
    NetworkContextIdentity.testOverride = stableSnapshot
    check(round().suppressed == [firstKey] && calls == 0 &&
          MountRecoveryStore.load(from: roundURL).file.volumes[firstKey]?.notificationCount == 2,
          "first readable identity establishes baseline without releasing an existing suppression")
    _ = MountRecoveryStore.save(protectedState, to: roundURL)
    NetworkContextIdentity.testOverride = NetworkContextSnapshot(identity: "", components: [])
    check(round().recovered == [firstKey], "confirmed empty network constitutes a real identity change")
    _ = MountRecoveryStore.save(protectedState, to: roundURL)
    NetworkContextIdentity.testOverride = NetworkContextSnapshot(identity: "gateway-changed", components: ["gw:192.0.2.2"])
    check(round().recovered == [firstKey], "confirmed gateway change releases suppression")
    calls = 0
    _ = MountRecoveryStore.save(protectedState, to: roundURL)
    NetworkContextIdentity.testOverride = NetworkContextSnapshot(identity: "", components: [], isReadable: false)
    let savedEpoch = LoginSessionEpoch.current()
    LoginSessionEpoch.testOverride = "independent-relogin"
    check(round().recovered == [firstKey], "re-login independently releases protection during network collection failure")
    LoginSessionEpoch.testOverride = savedEpoch
    NetworkContextIdentity.testOverride = stableSnapshot
    _ = MountRecoveryStore.save(protectedState, to: roundURL)
    calls = 0
    NetworkContextIdentity.testOverride = NetworkContextSnapshot(identity: "new-network", components: ["new-network"])
    check(round().recovered == [firstKey] && calls == 1, "network boundary releases suppression without clearing healthy history")
    check(MountRecoveryStore.load(from: roundURL).file.volumes[firstKey]?.everHealthyMounted == true,
          "healthy history remains sticky after boundary recovery")
    check(round([firstKey: "/Volumes/A"]).attempted == 0 && calls == 1,
          "self-generated mount event is idempotent and adds no attempt")
    check(round().suppressed == [firstKey], "fresh healthy eject after recovery is suppressed again")
    check(round(manual: true).recovered == [firstKey], "explicit Remount now restores a suppressed volume")
    check(round([firstKey: "/Volumes/A"]).notificationKeys.isEmpty, "healthy observation resets notification budget")
    historical.sessionBoundary = SessionBoundaryIdentity.current().combined
    historical.volumes[firstKey]?.repairEjectEvidence = true
    check(MountRecoveryStore.save(historical, to: roundURL), "repair evidence fixture saved")
    let beforeFailures = calls
    let failedRound = round(success: false)
    check(failedRound.failed == [firstKey] && calls - beforeFailures == 2 && failedRound.attempted == 2,
          "mount failures exhaust exactly the configured bounded retry count")
    check(failedRound.notificationKeys == [firstKey] && round(success: false).notificationKeys == [firstKey] &&
          round(success: false).notificationKeys.isEmpty,
          "actual failures still notify at most twice per volume and session")
    check(recoveryFallbackNotificationText(for: RecoveryRoundOutcome(suppressed: [firstKey], notificationKeys: [firstKey]), config: roundConfig) == nil,
          "notification renderer rejects stale suppressed notification keys from previous policy")
    let attempts = MountRecoveryStore.load(from: roundURL).file.attempts[firstKey] ?? []
    check(attempts.last?.outcome == .shareRejected && attempts.last?.sequence == 2,
          "failed recovery records outcome and sequence")
    check(MountRecoveryStore.load(from: roundURL).file.volumes[secondKey] == nil,
          "lower-priority reachable host never enters recovery")
    MountRecoveryStore.mountRecoveryStoreLoadOverride = .corrupt(reason: "injected")
    let beforeCorrupt = calls
    let corruptRound = round()
    check(corruptRound.suppressed == [firstKey] && calls == beforeCorrupt,
          "corruption never falls through to first-use mounting")
    check(corruptRound.stateDiagnostic != nil && corruptRound.notificationKeys.isEmpty &&
          recoveryFallbackNotificationText(for: corruptRound, config: roundConfig) == nil &&
          !(corruptRound.stateDiagnostic?.contains("injected") ?? true),
          "corrupt state has safe distinct diagnostics with no failure notification or raw input")
    MountRecoveryStore.mountRecoveryStoreLoadOverride = .corrupt(reason: "unknown schema_version 999")
    let unknownVersionRound = round()
    check(unknownVersionRound.stateDiagnostic == tr("  · 恢复状态异常（未知状态版本）；缺失卷保守跳过，请在配置菜单选择“立即重新挂载”。",
        "  · Recovery state error (unknown state version); missing volumes are conservatively skipped. Use Remount now in the configuration menu."),
        "unknown schema diagnostics match bilingual text exactly")
    check(round(manual: true).recovered == [firstKey], "manual fallback remains available after state corruption")
    MountRecoveryStore.mountRecoveryStoreLoadOverride = nil
    var disabledRoundConfig = roundConfig
    disabledRoundConfig.autoMountRecovery = false
    check(runRecoveryRound(config: disabledRoundConfig, mountTable: [:], hostReachability: { _, _ in true },
                           stateURL: roundURL, applyRecovery: { _, _ in calls += 1; return true }).attempted == 0,
          "disabled recovery performs no classification or mount attempt")
    check(firstReachableHost(in: disabledRoundConfig, probe: { _, _ in true })?.host == "first.example",
          "disabled manual baseline retains first-host exclusivity")
    let fallbackURL = tempDir.appendingPathComponent("priority-fallback-state.plist")
    var fallbackCalls: [String] = []
    let fallbackRound = runRecoveryRound(config: roundConfig, mountTable: [:],
        hostReachability: { host, _ in host == "second.example" }, stateURL: fallbackURL,
        applyRecovery: { volume, _ in fallbackCalls.append(volume.host); return true })
    check(fallbackCalls == ["second.example"] && fallbackRound.recovered == [secondKey],
          "unreachable first host falls back exclusively to reachable second host")
    check(fallbackRound.notificationKeys.isEmpty && fallbackRound.failed.isEmpty,
          "successful priority fallback never reports the unavailable nonselected host as failed")
    var takeoverConfig = roundConfig
    takeoverConfig.hosts[1].shares[0].mountPoint = "/Volumes/A"
    let takeoverURL = tempDir.appendingPathComponent("priority-takeover-state.plist")
    let takeoverRound = runRecoveryRound(config: takeoverConfig, mountTable: [firstKey: "/Volumes/A"],
        hostReachability: { host, _ in host == "second.example" }, stateURL: takeoverURL,
        applyRecovery: { _, _ in true })
    check(takeoverRound.recovered == [secondKey] && takeoverRound.failed.isEmpty && takeoverRound.notificationKeys.isEmpty,
          "successful same-path fallback removes stale first-host failure notifications")
    check(MountRecoveryStore.load(from: takeoverURL).file.volumes[firstKey]?.repairEjectEvidence == true,
          "same-path fallback retains old-host repair evidence for future evaluation")
    let peerEjectURL = tempDir.appendingPathComponent("peer-eject-state.plist")
    _ = runRecoveryRound(config: takeoverConfig, mountTable: [firstKey: "/Volumes/A"],
        hostReachability: { _, _ in true }, stateURL: peerEjectURL,
        applyRecovery: { _, _ in false }, volumeHealth: { _ in true })
    var peerMountCalls = 0
    let peerEjectRound = runRecoveryRound(config: takeoverConfig, mountTable: [:],
        hostReachability: { host, _ in host == "second.example" }, stateURL: peerEjectURL,
        applyRecovery: { _, _ in peerMountCalls += 1; return true })
    check(peerMountCalls == 0 && peerEjectRound.suppressed.contains(secondKey),
          "fallback identity cannot bypass a healthy eject at the same mount point")
    let peerRepeatedRound = runRecoveryRound(config: takeoverConfig, mountTable: [:],
        hostReachability: { host, _ in host == "second.example" }, stateURL: peerEjectURL,
        applyRecovery: { _, _ in peerMountCalls += 1; return true })
    check(peerMountCalls == 0 && peerRepeatedRound.suppressed.contains(secondKey),
          "same-path eject protection persists across repeated fallback evaluations")
    let peerCappedRound = runRecoveryRound(config: takeoverConfig, mountTable: [:],
        hostReachability: { host, _ in host == "second.example" }, stateURL: peerEjectURL,
        applyRecovery: { _, _ in peerMountCalls += 1; return true })
    check(peerEjectRound.notificationKeys.isEmpty && peerRepeatedRound.notificationKeys.isEmpty && peerCappedRound.notificationKeys.isEmpty,
          "same-path fallback respects healthy eject silently across every event")
    let peerBoundaryURL = tempDir.appendingPathComponent("peer-boundary-state.plist")
    try? FileManager.default.copyItem(at: peerEjectURL, to: peerBoundaryURL)
    let previousNetworkOverride = NetworkContextIdentity.testOverride
    NetworkContextIdentity.testOverride = NetworkContextSnapshot(identity: "peer-new-network", components: ["peer-new-network"])
    let peerBoundaryRound = runRecoveryRound(config: takeoverConfig, mountTable: [:],
        hostReachability: { host, _ in host == "second.example" }, stateURL: peerBoundaryURL,
        applyRecovery: { _, _ in true })
    check(peerBoundaryRound.recovered == [secondKey],
          "network boundary releases same-path fallback eject protection")
    NetworkContextIdentity.testOverride = previousNetworkOverride
    let peerManualRound = runRecoveryRound(config: takeoverConfig, mountTable: [:],
        hostReachability: { host, _ in host == "second.example" }, stateURL: peerEjectURL,
        applyRecovery: { _, _ in true }, manualRecovery: true)
    check(peerManualRound.recovered == [secondKey],
          "explicit manual recovery releases same-path fallback suppression")
    check(MountRecoveryStore.load(from: peerEjectURL).file.volumes[firstKey]?.state == .pendingRecovery,
          "manual same-path recovery clears stale suppression on the alternate identity")
    var disabledHistoryConfig = roundConfig
    disabledHistoryConfig.hosts[0].shares[0].enabled = false
    _ = runRecoveryRound(config: disabledHistoryConfig, mountTable: [:], hostReachability: { _, _ in true },
        stateURL: roundURL, applyRecovery: { _, _ in false })
    check(MountRecoveryStore.load(from: roundURL).file.volumes[firstKey]?.everHealthyMounted == true,
          "temporary disable preserves sticky healthy history")
    let generatorBinary = tempDir.appendingPathComponent("automnt")
    let enabledAgent = generateLaunchAgentDictionary(binaryURL: generatorBinary, logDir: tempDir,
        autoMountRecoveryEnabled: true, mountWatchPaths: mountWatchPaths(from: roundConfig))
    let disabledAgent = generateLaunchAgentDictionary(binaryURL: generatorBinary, logDir: tempDir,
        autoMountRecoveryEnabled: false, mountWatchPaths: [])
    check(enabledAgent["StartOnMount"] as? Bool == true &&
          (enabledAgent["WatchPaths"] as? [String])?.contains("/Volumes/A") == true,
          "enabled generator includes mount event and config-derived mount paths")
    check(disabledAgent["StartOnMount"] == nil && !(disabledAgent["WatchPaths"] as? [String] ?? []).contains("/Volumes"),
          "disabled generator removes mount namespace event sources")
    check(enabledAgent["StartInterval"] == nil && enabledAgent["StartCalendarInterval"] == nil && enabledAgent["KeepAlive"] == nil,
          "recovery generator has neither periodic wakeups nor resident KeepAlive")
    check(!registerOrUpdateLaunchAgent(targetBinaryURL: generatorBinary, targetPlistURL: tempDir.appendingPathComponent("guarded-agent.plist")),
          "daemon predicate blocks registration before file writes or launchctl")
    let agentFixture = tempDir.appendingPathComponent("generated-agent.plist")
    let generatedData = try? PropertyListSerialization.data(fromPropertyList: enabledAgent, format: .binary, options: 0)
    try? generatedData?.write(to: agentFixture)
    check(installedServiceDefinitionMatches(config: roundConfig, at: agentFixture),
          "matching generated service is detected as converged for idempotent reload")
    let outdatedData = try? PropertyListSerialization.data(fromPropertyList: disabledAgent, format: .binary, options: 0)
    try? outdatedData?.write(to: agentFixture)
    check(!installedServiceDefinitionMatches(config: roundConfig, at: agentFixture),
          "older two-source service is detected before entering config menu")

    // T010-a / T022：CLI owner-aware 接线回归（隔离目录，绝不触碰真实安装或 launchd）。
    do {
        let ownershipDir = tempDir.appendingPathComponent("cli-ownership")
        try FileManager.default.createDirectory(at: ownershipDir, withIntermediateDirectories: true)
        let ownershipConfigURL = ownershipDir.appendingPathComponent("automnt.plist")
        configURLOverride = ownershipConfigURL
        check(saveConfig(AutomntConfig(version: automntVersion), to: ownershipConfigURL),
              "CLI ownership fixture is written through the program API")
        let ownershipStore = BackendStateStore(authorizedDirectory: CLIOwnership.directory)
        let ownershipRevision = ConfigurationRevision.of(try PrivateAtomicFile.read(ownershipConfigURL))
        // 状态缺失 → 预检建立明确 owner=none/stopped，而不是被当作已授权。
        let noRefusal = CLIOwnership.registrationRefusal()
        let initialized = try ownershipStore.read()
        check(noRefusal == nil && initialized.owner == .none && initialized.phase == .stopped,
              "first CLI run initializes an explicit owner=none/stopped state instead of bypassing the store")
        // app owner 时 CLI 拒绝注册/自愈抢占，并给出结构化提示。
        let appJournal = try ownershipStore.begin(desiredOwner: .app, expectedGeneration: 0,
            revision: ownershipRevision, verifyConfiguration: true)
        _ = try ownershipStore.advance(id: appJournal.id, to: .activating, verifiedStatus: .stopped)
        _ = try ownershipStore.advance(id: appJournal.id, to: .active, verifiedStatus: .enabled,
            expectedRevision: ownershipRevision)
        let stateFileURL = ownershipDir.appendingPathComponent("backend-state.plist")
        let appStateBytes = try PrivateAtomicFile.read(stateFileURL)
        let appRefusal = CLIOwnership.registrationRefusal()
        check(appRefusal?.contains("cli-ownership:refusedAppOwner") == true,
              "app owner produces a structured CLI refusal instead of silent takeover")
        check(try ownershipStore.read().owner == .app,
              "app ownership survives the CLI refusal unchanged")
        check(try PrivateAtomicFile.read(stateFileURL) == appStateBytes,
              "refused CLI registration leaves the durable state bytes untouched")
        // 无许可的恢复轮不得做任何挂载副作用（owner=app 时保守 defer）。
        CLIOwnership.selfTestPermitSupplied = false
        var unauthorizedMounts = 0
        let unauthorized = runRecoveryRound(config: roundConfig, mountTable: [:],
            hostReachability: { _, _ in true },
            stateURL: ownershipDir.appendingPathComponent("round.plist"),
            applyRecovery: { _, _ in unauthorizedMounts += 1; return true })
        check(unauthorizedMounts == 0 && unauthorized.suppressed.isEmpty && unauthorized.recovered.isEmpty &&
              Set(unauthorized.deferredVolumeKeys) == Set(configuredVolumes(from: roundConfig).map(\.key)),
              "recovery round without an ownership permit defers without any mount side effect")
        // 真实入口已持有许可时同一轮必须完整执行（证明上面拒绝的是缺许可，不是永久停摆）。
        CLIOwnership.selfTestPermitSupplied = true
        var authorizedMounts = 0
        let authorized = runRecoveryRound(config: roundConfig, mountTable: [:],
            hostReachability: { _, _ in true },
            stateURL: ownershipDir.appendingPathComponent("round.plist"),
            applyRecovery: { _, _ in authorizedMounts += 1; return true })
        check(authorizedMounts >= 1 && authorized.recovered.count == authorizedMounts &&
              authorized.deferredVolumeKeys.isEmpty,
              "permitted recovery round still executes mounts end to end")
        configURLOverride = nil
    } catch {
        configURLOverride = nil
        check(false, "CLI ownership self-test fixture failed: \(error)")
    }

    let compatibleURL = tempDir.appendingPathComponent("compatible-state.plist")
    var oldState = (try? PropertyListSerialization.propertyList(from: PropertyListEncoder().encode(historical), options: [], format: nil)) as? [String: Any] ?? [:]
    oldState.removeValue(forKey: "attempts")
    if let encoded = try? PropertyListSerialization.data(fromPropertyList: oldState, format: .binary, options: 0) { try? PrivateAtomicFile.replace(encoded, at: compatibleURL) }
    check(MountRecoveryStore.load(from: compatibleURL).isReadable,
          "older schema-one state without attempt records remains readable")
    var unsaved = reloadedSwitchConfig!
    unsaved.autoMountRecovery = true
    check(loadConfig(from: recoveryConfigURL, migrate: false)?.autoMountRecovery == false,
          "unsaved switch toggle leaves disk configuration unchanged")
    check(netFSOpenOptions()[kNAUIOptionKey] as? String == kNAUIOptionNoUI,
          "NetFS explicitly forbids credential UI")
    let cleanupURL = tempDir.appendingPathComponent("cleanup-state.plist")
    var cleanedPaths: [String] = []
    let deadRound = runRecoveryRound(config: roundConfig, mountTable: [firstKey: "/Volumes/A-1"],
        hostReachability: { _, _ in false }, stateURL: cleanupURL,
        applyRecovery: { _, _ in check(false, "unreachable dead volume is never mounted"); return false },
        cleanupVolume: { path in cleanedPaths.append(path); return true })
    check(cleanedPaths.isEmpty && deadRound.attempted == 0,
          "offline dead volume retains evidence without blocking on forced unmount")
    check(MountRecoveryStore.load(from: cleanupURL).file.cleanupLedger[firstKey] == nil,
          "deferred cleanup never fabricates a successful cleanup ledger")
    check(MountRecoveryStore.load(from: cleanupURL).file.volumes[firstKey]?.repairEjectEvidence == true,
          "session loss leaves readable repair-eject evidence")
    let reconnected = runRecoveryRound(config: roundConfig, mountTable: [firstKey: "/Volumes/A-1"],
        hostReachability: { _, _ in true }, stateURL: cleanupURL,
        applyRecovery: { _, _ in check(false, "healthy reconnect never remounts"); return false }, writeState: false,
        cleanupVolume: { _ in check(false, "healthy reconnect never unmounts"); return false },
        volumeHealth: { _ in true })
    check(reconnected.recovered.isEmpty && reconnected.failed.isEmpty,
          "fresh healthy probe overrides historical repair evidence after reconnect")
    let repaired = runRecoveryRound(config: roundConfig, mountTable: [firstKey: "/Volumes/A-1"],
        hostReachability: { _, _ in true }, stateURL: cleanupURL,
        applyRecovery: { _, _ in true }, cleanupVolume: { _ in true }, volumeHealth: { _ in false })
    check(repaired.recovered == [firstKey] && repaired.attempted == 1,
          "reachable but unhealthy retained volume is cleaned and restored in the same round")
    check(MountRecoveryStore.load(from: cleanupURL).file.volumes[firstKey]?.repairEjectEvidence == false,
          "successful recovery clears stale repair evidence before a future healthy eject")
    let failedCleanupURL = tempDir.appendingPathComponent("failed-cleanup.plist")
    _ = runRecoveryRound(config: roundConfig, mountTable: [firstKey: "/Volumes/A-1"],
        hostReachability: { _, _ in false }, stateURL: failedCleanupURL,
        applyRecovery: { _, _ in false }, cleanupVolume: { _ in false })
    check(MountRecoveryStore.load(from: failedCleanupURL).file.cleanupLedger[firstKey] == nil,
          "failed cleanup never fabricates product cleanup evidence")
    let combinedNotice = recoveryFallbackNotificationText(for: RecoveryRoundOutcome(failed: [firstKey, secondKey],
        notificationKeys: [firstKey, secondKey, firstKey]), config: roundConfig)
    check(combinedNotice?.title == tr("automnt：挂载未自动恢复", "automnt: Mounts Not Automatically Restored") &&
          combinedNotice?.subtitle == tr("自动恢复未完成", "Automatic recovery incomplete") &&
          combinedNotice?.message == tr("2 个共享文件夹未能自动恢复。请打开 automnt 配置并选择“立即重新挂载”。",
              "2 shared folder(s) could not be restored automatically. Open automnt configuration and choose \"Remount now\"."),
          "fallback notification matches privacy-safe count contract and merges unique identities")
    let sharedPathNotice = recoveryFallbackNotificationText(for: RecoveryRoundOutcome(
        failed: [firstKey, secondKey], notificationKeys: [firstKey, secondKey]), config: takeoverConfig)
    check(sharedPathNotice?.message == tr("2 个共享文件夹未能自动恢复。请打开 automnt 配置并选择“立即重新挂载”。",
        "2 shared folder(s) could not be restored automatically. Open automnt configuration and choose \"Remount now\"."),
        "fallback notification reports failed identities without private mount names")
    let privateValues = configuredVolumes(from: takeoverConfig).flatMap { [$0.key, $0.url, $0.mountPoint] }
    let payload = [sharedPathNotice?.title, sharedPathNotice?.subtitle, sharedPathNotice?.message].compactMap { $0 }.joined(separator: " ")
    check(!privateValues.contains(where: { !$0.isEmpty && payload.contains($0) }),
          "private identities addresses and mount paths never enter notification payload")
    LoginSessionEpoch.testOverride = nil
    NetworkContextIdentity.testOverride = nil
    MountRecoveryStore.mountRecoveryStoreSaveBlocked = false
    check(recoveryFallbackNotificationText(for: RecoveryRoundOutcome(recovered: [firstKey],
        failed: [firstKey], notificationKeys: [firstKey]), config: roundConfig) == nil,
        "success at round end excludes stale notification keys even if failure bookkeeping remains")
    check(recoveryFallbackNotificationText(for: RecoveryRoundOutcome(notificationKeys: [firstKey]),
        config: roundConfig) == nil, "notification keys alone cannot report a resolved or healthy volume")

    print("\nSelf-tests: \(passed) passed, \(skipped) skipped, \(failed) failed")
    return failed == 0
}

// MARK: - T077：单共享挂载与普通弹出（共同核心语义的 CLI 入口）
//
// 本段只做两件事：
// 1. 把 `--mount <smb-url>` / `--eject <smb-url>` 解析成活动配置中的唯一稳定身份；
// 2. 复用共同核心的所有权/修订/身份核对与状态提交规则执行真实动作。
//
// 明确不做：
// - 不新建第二套配置/恢复规则；身份用 `smbResourceIdentity`，会话抑制一律经
//   `UserEjectCommit`，在途意图一律经 `WorkerOperationStore`；
// - 不通过执行外部 CLI 实现能力（`diskutil`/`umount` 均不用于普通弹出）；
// - 不因为“用户点了弹出”就升级为强制弹出，也不因失败而伪造成功。

/// 单共享动作的意图。两个入口都只影响该共享，绝不改变服务器顺序或其它共享意图。
enum CLISingleShareIntent: Equatable {
    case mount
    case eject
}

/// 参数解析结果。`problem` 非 nil 表示拒绝，且必须给出非 0 退出码。
struct CLISingleShareRequest: Equatable {
    /// 规范化前的原始地址（用于回显；凭据地址在解析阶段即被拒绝，不会走到这里）。
    let rawURL: String
    /// `smbResourceIdentity` 的稳定身份；定位活动配置目标的唯一依据。
    let identity: String
    let intent: CLISingleShareIntent
}

/// 参数解析失败类别。每类都对应一条明确的用户可见错误，绝不模糊匹配。
/// 之所以符合 `Error`：`Result` 的失败类型需要它；它不携带任何用户数据。
enum CLISingleShareParseProblem: Error, Equatable {
    case missingArgument
    case unexpectedExtraArgument
    case notSMB
    case embeddedCredentials
    case missingHost
    case missingShare
    case invalidPort
    case unresolvableIdentity

    /// 稳定的机器可读标签，便于回归断言；不含任何用户数据。
    var tag: String {
        switch self {
        case .missingArgument: return "missingArgument"
        case .unexpectedExtraArgument: return "unexpectedExtraArgument"
        case .notSMB: return "notSMB"
        case .embeddedCredentials: return "embeddedCredentials"
        case .missingHost: return "missingHost"
        case .missingShare: return "missingShare"
        case .invalidPort: return "invalidPort"
        case .unresolvableIdentity: return "unresolvableIdentity"
        }
    }
}

/// 纯解析：把 `smb://host/share` 变成稳定身份。
///
/// 校验顺序刻意与 `validateMountTargetURL` 的既有语义一致（协议 → 凭据 → 身份），
/// 使两个入口对同一地址给出一致的判定。这里不接受 `//host/share` 简写：
/// 面向用户的子命令要求完整 `smb://` 地址，避免与命令行路径混淆。
func parseSingleShareTarget(_ arguments: [String], intent: CLISingleShareIntent) -> Result<CLISingleShareRequest, CLISingleShareParseProblem> {
    guard let raw = arguments.first else { return .failure(.missingArgument) }
    guard arguments.count == 1 else { return .failure(.unexpectedExtraArgument) }
    let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    // URLComponents 对 `smb:` 大小写不敏感，但“非 smb 协议”必须显式拒绝。
    guard let components = URLComponents(string: clean), let scheme = components.scheme?.lowercased() else {
        return .failure(.notSMB)
    }
    guard scheme == "smb" else { return .failure(.notSMB) }
    // 内嵌用户名/密码一律拒绝：SMB 凭据只由系统钥匙串保管，绝不进 argv 解析结果。
    if components.user != nil || components.password != nil || clean.contains("@") {
        return .failure(.embeddedCredentials)
    }
    guard let host = components.host, !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return .failure(.missingHost)
    }
    if let port = components.port, !(1...65535).contains(port) { return .failure(.invalidPort) }
    guard let shareName = extractShareName(from: clean), !shareName.isEmpty else {
        return .failure(.missingShare)
    }
    // 稳定身份是唯一定位依据：即使 address 形态不同（大小写/端口省略/百分号编码），
    // 同一目标必须得到同一身份。
    guard let identity = smbResourceIdentity(clean), !identity.isEmpty else {
        return .failure(.unresolvableIdentity)
    }
    return .success(CLISingleShareRequest(rawURL: clean, identity: identity, intent: intent))
}

/// 目标定位结果。`unknownTarget` 必须给出非 0 退出码，绝不猜测其它服务器/共享。
enum CLISingleShareTarget: Equatable {
    case found(host: HostConfig, share: SMBShareConfig, hostIndex: Int, shareIndex: Int)
    case unknownTarget
}

/// 在活动配置中按稳定身份定位唯一目标。
///
/// 同一身份在配置内出现两次属于配置异常（`ConfigurationValidation` 已在保存时拒绝），
/// 此处仍以“首个匹配唯一目标”处理：不跨服务器合并，也不做模糊匹配。
func locateSingleShareTarget(identity: String, in configuration: AutomntConfig) -> CLISingleShareTarget {
    for (hostIndex, host) in configuration.hosts.enumerated() {
        for (shareIndex, share) in host.shares.enumerated() {
            guard let shareIdentity = smbResourceIdentity(share.smbURL) else { continue }
            if shareIdentity == identity {
                return .found(host: host, share: share, hostIndex: hostIndex, shareIndex: shareIndex)
            }
        }
    }
    return .unknownTarget
}

/// 单个共享动作的结果。失败绝不写成成功，分类沿用 `AutomntIssue`。
struct CLISingleShareOutcome {
    let issue: AutomntIssue?
    /// 给人看的补充说明（已本地化）；仅在成功或需要下一步时非 nil。
    let detail: String?

    static func success(_ detail: String? = nil) -> CLISingleShareOutcome {
        CLISingleShareOutcome(issue: nil, detail: detail)
    }
    static func failure(_ issue: AutomntIssue, detail: String? = nil) -> CLISingleShareOutcome {
        CLISingleShareOutcome(issue: issue, detail: detail)
    }
    var succeeded: Bool { issue == nil }
}

// MARK: CLI 侧普通弹出原语（非强制）

/// 普通（非强制）弹出结果。
enum CLINormalEjectResult: Equatable {
    case unmounted
    case failure(AutomntIssue)

    var issue: AutomntIssue? {
        if case .failure(let issue) = self { return issue }
        return nil
    }
}

/// 判定某路径当前是否确实是目标 SMB 身份。
///
/// 只信实际路径非空是不够的：路径可能被其它身份的卷占用。这里复用 CLI 既有的
/// `getmntinfo` 挂载表读取（`getKernelMountSource`）与 `smbResourceIdentity`，
/// 与 `ensureMountPointReady` 使用同一来源，避免第二套判定。
func cliMountedIdentity(at path: String) -> String? {
    guard let source = getKernelMountSource(for: URL(fileURLWithPath: path).standardizedFileURL.path) else {
        return nil
    }
    return smbResourceIdentity(source)
}

/// 普通弹出：`kDADiskUnmountOptionDefault`，**绝不 force**。
///
/// 与 `AutomntPlatform.DiskArbitrationWorkerOperation.unmount` 是同一内核语义的
/// 两处实现：CLI 走扁平单二进制构建（scripts/build.sh 只拼接 Core+CLI 源码、
/// 不传 -framework），因此不依赖 AutomntPlatform。两处必须保持同一分类：
/// busy → volumeBusy、notPermitted → authorizationRequired、其余 → shareRejected。
/// 审计时请对照修改，不要误认为这里是独立分叉的规则。
func performNormalEject(mountedIdentity: String, path: String, deadline: Date) -> CLINormalEjectResult {
    guard !path.isEmpty, path.hasPrefix("/"), path != "/" else { return .failure(.pathConflict) }
    guard Date() < deadline else { return .failure(.timeout) }
    // 身份核对：路径必须当前就是目标身份，且必须是 smbfs。
    guard cliMountedIdentity(at: path) == mountedIdentity else { return .failure(.pathConflict) }
    guard let session = DASessionCreate(kCFAllocatorDefault),
          let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, URL(fileURLWithPath: path) as CFURL) else {
        return .failure(.signalUnavailable)
    }
    let queue = DispatchQueue(label: "org.automnt.cli-normal-eject")
    DASessionSetDispatchQueue(session, queue)
    let completion = CLINormalEjectCompletion(session: session)
    let context = Unmanaged.passRetained(completion).toOpaque()
    // 仅默认选项：与 worker 一致，绝不 DADiskUnmountOptionForce、绝不弹出整个设备。
    DADiskUnmount(disk, DADiskUnmountOptions(kDADiskUnmountOptionDefault), { _, dissenter, context in
        guard let context else { return }
        let completion = Unmanaged<CLINormalEjectCompletion>.fromOpaque(context).takeRetainedValue()
        completion.finish(dissenter.map { DADissenterGetStatus($0) })
    }, context)
    let remaining = deadline.timeIntervalSinceNow
    guard remaining > 0, completion.wait(seconds: min(remaining, 30)) else {
        // 超时不代表内核已收敛；保留为需修复状态，绝不谎报已弹出。
        return .failure(.timeout)
    }
    if let status = completion.status {
        writeLog("Single-share eject dissenter status \(status)")
        return .failure(cliNormalEjectIssue(forDissenterStatus: status))
    }
    // 只有内核表确实不再挂载该路径才认成功（与 WorkerCompletionPolicy 的 absent 要求一致）。
    guard getKernelMountSource(for: URL(fileURLWithPath: path).standardizedFileURL.path) == nil else {
        return .failure(.pathConflict)
    }
    return .unmounted
}

/// DiskArbitration dissenter 状态 → `AutomntIssue` 的**纯分类**（可单测）。
///
/// 分类必须与 `AutomntPlatform.DiskArbitrationBackend` 保持一致：
/// busy → volumeBusy；notPermitted → authorizationRequired；其余 → shareRejected。
/// `nil` 表示配对错误（例如目标不是可卸载的卷）；它绝不代表“已弹出”，
/// 因此调用方仍必须核对内核表确实缺席后才认成功。
func cliNormalEjectIssue(forDissenterStatus status: DAReturn) -> AutomntIssue {
    switch status {
    case DAReturn(kDAReturnBusy), DAReturn(kDAReturnExclusiveAccess): return .volumeBusy
    case DAReturn(kDAReturnNotPermitted), DAReturn(kDAReturnNotPrivileged): return .authorizationRequired
    default:
        // DiskArbitration encodes a BSD errno with unix_err(errno) = 0xC000 + errno.
        // A busy share is the common case here and must not be reported as a share rejection.
        if let errno = cliUnixErrno(forDissenterStatus: status) {
            switch errno {
            case EBUSY: return .volumeBusy
            case EACCES, EPERM: return .authorizationRequired
            default: return .shareRejected
            }
        }
        return .shareRejected
    }
}

/// Decodes the BSD errno embedded by DiskArbitration's unix_err() encoding.
func cliUnixErrno(forDissenterStatus status: DAReturn) -> Int32? {
    let raw = status
    let candidate = raw - 0xC000
    guard candidate > 0, candidate < 0x1000 else { return nil }
    return candidate
}

/// DiskArbitration 回调的同步等待容器。回调可能在任意队列到达，故用锁保护结果。
///
/// 本类型刻意不声明 `Sendable`，也不使用 `@unchecked Sendable`（CLI target 的
/// 结构性并发检查禁止后者）：它只经 `Unmanaged` 裸指针在 C 回调间传递，
/// 从不作为值跨越隔离域，因此无需（也不应）伪造并发安全承诺。
/// 这与 `DiskArbitrationBackend.UnmountCompletion` 的语义一致。
private final class CLINormalEjectCompletion {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private let session: DASession
    private var outcome: DAReturn?

    init(session: DASession) { self.session = session }

    var status: DAReturn? { lock.withLock { outcome } }

    func finish(_ status: DAReturn?) {
        lock.withLock { outcome = status }
        DASessionSetDispatchQueue(session, nil)
        semaphore.signal()
    }

    func wait(seconds: Double) -> Bool { semaphore.wait(timeout: .now() + seconds) == .success }
}

// MARK: CLI 单共享动作执行

/// 在已持有的评估许可内执行单共享挂载。
///
/// 挂载复用现有 `--internal-netfs-mount` 子进程路径（与基线挂载同一 NetFS/钥匙串语义），
/// 只影响该共享；成功后经 `UserEjectCommit.resumeAfterManualMount` 解除本会话抑制，
/// 与 worker 的手动挂载分支完全同一规则。
private func performCLISingleShareMount(directory: URL,
                                        context: CLIEvaluationContext,
                                        target: CLISingleShareTarget) -> CLISingleShareOutcome {
    guard case .found(let host, let share, _, _) = target else { return .failure(.configurationConflict) }
    let mountPath = share.mountPoint
    let identity = smbResourceIdentity(share.smbURL) ?? ""
    // 内核状态门与基线一致：占用/其它身份一律阻断，不覆盖、不强制。
    switch NetFSMountPathState.inspect(at: mountPath, expectedIdentity: identity) {
    case .blocked(let issue): return .failure(issue)
    case .alreadyMounted:
        // 已按同一身份挂载：视为成功并解除抑制（幂等）。
        do {
            try UserEjectCommit.resumeAfterManualMount(identity: identity, directory: directory,
                                                       path: .smb(identity: identity))
        } catch let issue as AutomntIssue { return .failure(issue) }
        catch { return .failure(.signalUnavailable) }
        return .success(tr("该共享已挂载。", "This share is already mounted."))
    case .readyToMount:
        break
    }
    // 有界预算：复用配置中的共享重试窗口，绝不无限等待。
    let windowMs = RecoveryRoundPlanner.retryWindowMilliseconds(context.snapshot.configuration)
    let previousDeadline = MountExecutionBudget.deadline
    MountExecutionBudget.deadline = Date().addingTimeInterval(Double(windowMs) / 1000)
    defer { MountExecutionBudget.deadline = previousDeadline }
    let mounted = silentMount(urlString: share.smbURL, mountPath: mountPath)
    guard mounted else {
        // 失败分类沿用既有 `MountExecutionBudget.lastFailure`（凭据失败 vs 共享拒绝）。
        switch MountExecutionBudget.lastFailure {
        case .credentialFailure: return .failure(.credentialFailure)
        case .hostUnreachable: return .failure(.offline)
        default: return .failure(.shareRejected)
        }
    }
    // 成功必须核对实际身份，不能只信 NetFS 返回值。
    guard cliMountedIdentity(at: mountPath) == identity else { return .failure(.pathConflict) }
    if host.preventSpotlightIndex {
        disableSpotlightIndex(at: mountPath)
    }
    // 手动挂载只在实际身份核对后解除会话抑制（Core 规则）。
    do {
        try UserEjectCommit.resumeAfterManualMount(identity: identity, directory: directory,
                                                   path: .smb(identity: identity))
    } catch let issue as AutomntIssue {
        // 卷已挂载但抑制状态未解除：如实报告，不谎报完全成功。
        return .failure(issue, detail: tr("共享已挂载，但会话抑制状态未能解除；本轮评估后可能重复尝试。",
                                          "The share is mounted, but the session suppression state could not be cleared; the next evaluation may retry it."))
    } catch {
        return .failure(.signalUnavailable)
    }
    return .success()
}

/// 弹出前的许可内预检结果。
enum CLIEjectPrecheck {
    case proceed(CLIEjectPlan)
    case refused(CLISingleShareOutcome)
}

/// 通过预检后交给隔离子进程的弹出计划（只含非敏感事实）。
struct CLIEjectPlan: Equatable {
    let path: String
    let identity: String
}

/// 在已持有的评估许可内完成弹出自检；**不做任何会再取 `evaluation.lock` 的调用**。
///
/// `WorkerOperationStore.begin/complete` 与 `EvaluationPermit` 取的是同一把
/// `evaluation.lock`，而 `flock` 在同一进程内**不可重入**（已实测：第二次
/// `LOCK_EX | LOCK_NB` 直接返回 EWOULDBLOCK）。因此真实的弹出必须与 worker 走
/// 同一种锁纪律：子进程自己持锁执行内核动作，父进程只在“未持锁”时登记/清理在途意图。
private func precheckSingleShareEject(directory: URL,
                                      context: CLIEvaluationContext,
                                      target: CLISingleShareTarget) -> CLIEjectPrecheck {
    guard case .found(_, let share, _, _) = target else {
        return .refused(.failure(.configurationConflict))
    }
    guard let identity = smbResourceIdentity(share.smbURL) else {
        return .refused(.failure(.invalidConfiguration))
    }
    let mountPath = URL(fileURLWithPath: share.mountPoint).standardizedFileURL.path
    // 未挂载即无可弹出目标：如实报告，不制造假成功。
    guard let currentIdentity = cliMountedIdentity(at: mountPath) else {
        return .refused(.failure(.pathConflict, detail: tr("该共享当前未挂载，无需弹出。",
                                                           "This share is not mounted; there is nothing to eject.")))
    }
    guard currentIdentity == identity else {
        return .refused(.failure(.pathConflict, detail: tr("该路径当前由其它共享占用，未做任何改动。",
                                                           "That path is currently occupied by a different share; nothing was changed.")))
    }
    do {
        try UserEjectCommit.verifyReadable(directory: directory)
        // 在途意图必须为空，否则可能有未收敛的上一次操作（与 ManualEject 一致）。
        try WorkerOperationStore(authorizedDirectory: directory).verifyIdle()
    } catch let issue as AutomntIssue {
        return .refused(.failure(issue))
    } catch {
        return .refused(.failure(.signalUnavailable))
    }
    return .proceed(CLIEjectPlan(path: mountPath, identity: identity))
}

/// 父进程侧监督：登记在途意图 → 隔离子进程持锁执行普通弹出 → 只在内核确认缺席后清账。
///
/// 与 `MountWorkerRunner` 的父进程纪律一致：**等待子进程期间绝不持有
/// `evaluation.lock`**；任何超时/异常退出都保留在途意图（需显式修复），
/// 绝不当成成功清账，也绝不伪造已弹出。
private func launchSupervisedNormalEject(revision: ConfigRevision, generation: UInt64,
                                         plan: CLIEjectPlan) -> CLISingleShareOutcome {
    let directory = CLIOwnership.directory
    let store = WorkerOperationStore(authorizedDirectory: directory)
    let operationID = UUID()
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
    let resultURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("automnt-cli-eject-\(UUID().uuidString)")
    guard FileManager.default.createFile(atPath: resultURL.path, contents: nil,
                                         attributes: [.posixPermissions: 0o600]) else {
        return .failure(.signalUnavailable)
    }
    defer { try? FileManager.default.removeItem(at: resultURL) }
    guard let handle = try? FileHandle(forWritingTo: resultURL) else {
        return .failure(.signalUnavailable)
    }
    // 子进程边界：与 `--internal-netfs-mount` 同一既有模式（自身可执行的内部模式，
    // 不是外部 CLI，也不是 shell）。
    var bounded: BoundedCommandResult?
    do {
        try store.launch(revision: revision, generation: generation, id: operationID) {
            let result = runCommandDiscardingOutputWithTimeout(
                executable: executable,
                arguments: ["--internal-normal-eject", plan.path, plan.identity, operationID.uuidString],
                timeout: 30,
                standardOutputFile: handle)
            // `error != nil` 只可能来自 process.run() 失败，即“未创建子进程”；
            // 按 store.launch 的契约抛错以回滚意图，绝不留下次不可启动的悬挂意图。
            if result.error != nil { throw AutomntIssue.signalUnavailable }
            bounded = result
        }
    } catch let issue as AutomntIssue {
        try? handle.close()
        return .failure(issue)
    } catch {
        try? handle.close()
        return .failure(.signalUnavailable)
    }
    try? handle.close()
    guard let bounded else { return .failure(.signalUnavailable) }
    guard !bounded.timedOut else {
        // 超时不证明内核已收敛；保留在途意图，要求人工核验。
        return .failure(.timeout, detail: tr("弹出未在时限内确认收敛；已保留需修复状态，请查看状态后重试。",
                                             "The eject did not confirm convergence in time; a repair-required state is retained. Check status and retry."))
    }
    guard bounded.error == nil, bounded.processStopped else {
        return .failure(.signalUnavailable)
    }
    let reported = (try? PrivateAtomicFile.read(resultURL)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    guard let childIssue = cliChildEjectIssue(fromChildOutput: reported) else {
        // 子进程确认普通弹出成功：父进程仍须核对内核表确实缺席后才清账。
        let standardized = URL(fileURLWithPath: plan.path).standardizedFileURL.path
        guard getKernelMountSource(for: standardized) == nil else {
            return .failure(.pathConflict)
        }
        do {
            try store.complete(id: operationID, revision: revision, generation: generation)
        } catch let issue as AutomntIssue {
            return .failure(issue, detail: tr("共享已弹出，但在途意图未能清除；下次操作前可能需要显式修复。",
                                              "The share was ejected, but the in-flight intent could not be cleared; an explicit repair may be needed before the next operation."))
        } catch {
            return .failure(.signalUnavailable)
        }
        return .success()
    }
    // 子进程报告失败：与 worker 一致保留在途意图（需修复），绝不当作成功。
    return .failure(childIssue, detail: tr("弹出未完成；已保留需修复状态，自动恢复在修复前不会重复尝试。",
                                           "The eject did not complete; a repair-required state is retained and automatic recovery will not retry before repair."))
}

/// 解析隔离子进程的结论行。
///
/// 约定：stdout 的**最后一行**为 `ok` 或 `issue:<AutomntIssue rawValue>`。
/// 取最后一行是为了容忍子进程路径上可能出现的其它提示文本。
/// 返回 nil 表示“确认成功”；非 nil 为失败分类。无法解析一律视为
/// `signalUnavailable`（保守，绝不当作成功）。
func cliChildEjectIssue(fromChildOutput output: String) -> AutomntIssue? {
    let last = output.split(whereSeparator: \.isNewline).last.map(String.init)?
        .trimmingCharacters(in: .whitespaces) ?? ""
    if last == "ok" { return nil }
    let prefix = "issue:"
    guard last.hasPrefix(prefix) else { return .signalUnavailable }
    let raw = String(last.dropFirst(prefix.count))
    return AutomntIssue(rawValue: raw) ?? .signalUnavailable
}

/// `--internal-normal-eject <mountPath> <identity> <operationID>`：
/// 单共享普通弹出的隔离子进程，**自己持有 `evaluation.lock`**（与 worker 同一锁纪律）。
///
/// 之所以必须是独立进程而不是父进程内联执行：`EvaluationPermit` 与
/// `WorkerOperationStore` 取同一把不可重入的 `evaluation.lock`，同进程内联必然
/// 自锁。子进程持锁覆盖「身份核对 → 在途意图复核 → 普通弹出 → 会话抑制提交」
/// 整段，正是 `apps/Automnt/Worker/MountWorker.swift` 的 `unmount` 分支所做的。
func runInternalNormalEject(arguments: [String]) -> Int32 {
    guard arguments.count == 3, let operationID = UUID(uuidString: arguments[2]) else { return 64 }
    // 先校验原始参数再标准化：`URL(fileURLWithPath:)` 会把相对路径拼成绝对路径，
    // 若先标准化就会让 "relative" 之类的输入绕过绝对路径检查。
    let rawPath = arguments[0]
    guard rawPath.hasPrefix("/"), !rawPath.contains("\0") else { return 64 }
    let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
    let identity = arguments[1]
    // 身份必须是 `smbResourceIdentity` 形态（以 "//" 开头），否则必然是调用方出错。
    guard path != "/", !identity.isEmpty, identity.hasPrefix("//") else { return 64 }
    guard let context = CLIOwnership.beginEvaluation() else {
        print("issue:\(AutomntIssue.incompatibleOwner.rawValue)")
        return 1
    }
    let directory = CLIOwnership.directory
    do {
        // 持锁后重新核对身份：许可前的观察可能已过期。
        guard cliMountedIdentity(at: path) == identity else { throw AutomntIssue.pathConflict }
        try UserEjectCommit.verifyReadable(directory: directory)
        try WorkerOperationStore(authorizedDirectory: directory).verifyPending(
            id: operationID, revision: context.snapshot.revision, generation: context.expectedGeneration)
        let deadline = Date().addingTimeInterval(30)
        if let issue = performNormalEject(mountedIdentity: identity, path: path, deadline: deadline).issue {
            print("issue:\(issue.rawValue)")
            return 1
        }
        let observation = VolumeObservation(identity: identity, status: .stopped,
                                            actualPath: nil, observedAt: Date())
        try UserEjectCommit.apply(observation, directory: directory,
                                  path: NetFSMountPathState.state(at: path),
                                  operationID: operationID,
                                  revision: context.snapshot.revision,
                                  generation: context.expectedGeneration)
        print("ok")
        return 0
    } catch let issue as AutomntIssue {
        print("issue:\(issue.rawValue)")
        return 1
    } catch {
        print("issue:\(AutomntIssue.signalUnavailable.rawValue)")
        return 1
    }
}

/// 内核路径状态门（不涉及恢复判定）。与 `BaselineMountDecision.block` 同序：
/// 不可用/占用/其它身份一律阻断，仅“缺失”与“同身份在表”放行。
enum NetFSMountPathState {
    case readyToMount
    case alreadyMounted
    case blocked(AutomntIssue)

    static func inspect(at path: String, expectedIdentity: String) -> NetFSMountPathState {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard let source = getKernelMountSource(for: standardized) else { return .readyToMount }
        guard let actual = smbResourceIdentity(source) else { return .blocked(.pathConflict) }
        return actual == expectedIdentity ? .alreadyMounted : .blocked(.pathConflict)
    }

    /// 提交给 Core 的路径状态（供 `UserEjectCommit.apply` 的 `.absent` 断言使用）。
    static func state(at path: String) -> MountPathState {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard let source = getKernelMountSource(for: standardized) else { return .absent }
        guard let identity = smbResourceIdentity(source) else { return .unavailable }
        return .smb(identity: identity)
    }
}

/// 单共享入口的完整流程：解析 → 定位 → 所有权/修订核对 → 执行 → 分类输出。
///
/// 退出码约定：
/// - 0：动作被确认成功（挂载后实际身份匹配；弹出后内核表确实缺席）。
/// - 2：用法错误（缺参、多余参数、地址非法、目标不在活动配置中）。
/// - 1：执行失败（所有权/并发/凭据/繁忙/超时等），分类文本写入 stderr。
func runSingleShareCommand(intent: CLISingleShareIntent, arguments: [String]) -> Int32 {
    let parsed: CLISingleShareRequest
    switch parseSingleShareTarget(arguments, intent: intent) {
    case .success(let request):
        parsed = request
    case .failure(let problem):
        fputs(singleShareParseMessage(problem, intent: intent) + "\n", stderr)
        return 2
    }

    // 读取活动配置：缺失/损坏时给出明确指引，绝不隐式初始化。
    let inspection = inspectConfigFile(at: getActiveConfigURL())
    switch inspection.state {
    case .missing:
        fputs(tr("✗ 未找到有效配置，请先运行 'automnt --init'。\n",
                 "✗ No valid configuration found. Run 'automnt --init' first.\n"), stderr)
        return 2
    case .invalid, .inaccessible, .futureVersion:
        fputs(tr("✗ 配置文件损坏或版本不受支持；未做任何改动。\n",
                 "✗ Configuration is invalid or its version is unsupported; nothing was changed.\n"), stderr)
        return 2
    case .usable:
        break
    }
    // 许可之前的预筛：目标必须已在活动配置中，否则立即以退出码 2 结束（无副作用）。
    if locateSingleShareTarget(identity: parsed.identity, in: inspection.config ?? AutomntConfig()) == .unknownTarget {
        fputs(tr("✗ 目标不在活动配置中：\(redactedSMBURL(parsed.rawURL))。本命令只作用于已配置共享，不会猜测或匹配其它服务器。\n",
                 "✗ Target is not in the active configuration: \(redactedSMBURL(parsed.rawURL)). This command only acts on configured shares and never guesses another server.\n"), stderr)
        return 2
    }

    // ⚠️ 锁纪律（已实测，勿改）：`CLIOwnership.beginEvaluation()` 返回的许可**持有**
    // `evaluation.lock` 直到该值释放；而 `WorkerOperationStore.begin/complete` 会再次
    // 获取同一把锁，而 `flock` 在同进程内**不可重入**（第二次 LOCK_EX|LOCK_NB 立刻
    // EWOULDBLOCK）。因此许可被限制在下面这个显式作用域里：离开作用域即解锁，
    // 之后父进程才能安全地登记/清理在途意图。
    var outcome: CLISingleShareOutcome?
    var ejectPlan: CLIEjectPlan?
    var ejectRefusal: CLISingleShareOutcome?
    var revision: ConfigRevision?
    var generation: UInt64 = 0
    var ownershipHeld = true
    do {
        guard let context = CLIOwnership.beginEvaluation() else {
            fputs(tr("✗ 已拒绝本次操作：后端所有权、配置修订或操作锁校验未通过。请检查服务状态后重试。\n",
                     "✗ Operation refused: backend ownership, configuration revision or the operation lock did not verify. Check service status and retry.\n"), stderr)
            return 1
        }
        // 许可内以已提交快照为准重新定位：许可前的读取可能已过期。
        let target = locateSingleShareTarget(identity: parsed.identity, in: context.snapshot.configuration)
        guard case .found = target else {
            _ = CLIOwnership.endEvaluation(context)
            fputs(tr("✗ 配置在操作期间已变更，目标不再存在；未做任何改动。\n",
                     "✗ The configuration changed during the operation and the target no longer exists; nothing was changed.\n"), stderr)
            return 1
        }
        revision = context.snapshot.revision
        generation = context.expectedGeneration
        switch parsed.intent {
        case .mount:
            // 挂载在许可内完成；它只使用读表与子进程调用，不会再次获取 evaluation.lock。
            outcome = performCLISingleShareMount(directory: CLIOwnership.directory, context: context, target: target)
        case .eject:
            // 弹出必须由隔离子进程持锁执行（同进程内联会与许可自锁）。
            // 许可内只做无副作用预检；真正的动作在许可释放后交给子进程。
            switch precheckSingleShareEject(directory: CLIOwnership.directory, context: context, target: target) {
            case .proceed(let plan): ejectPlan = plan
            case .refused(let refusal): ejectRefusal = refusal
            }
        }
        ownershipHeld = CLIOwnership.endEvaluation(context)
    }
    // 许可已随作用域结束释放；以下调用会再次获取 evaluation.lock，故必须在此之后。
    guard let revision else { return 1 }
    if let ejectRefusal {
        outcome = ejectRefusal
    } else if let ejectPlan {
        outcome = launchSupervisedNormalEject(revision: revision, generation: generation, plan: ejectPlan)
    }
    guard let outcome else {
        fputs(tr("✗ 未能确定操作结果；未做任何改动。\n",
                 "✗ The operation result could not be determined; nothing was changed.\n"), stderr)
        return 1
    }

    if let issue = outcome.issue {
        let verb = parsed.intent == .mount ? tr("挂载", "mount") : tr("弹出", "eject")
        fputs(tr("✗ \(verb)失败 [\(issue.rawValue)]: \(redactedSMBURL(parsed.rawURL))\n",
                 "✗ \(verb) failed [\(issue.rawValue)]: \(redactedSMBURL(parsed.rawURL))\n"), stderr)
        if let detail = outcome.detail { fputs("  \(detail)\n", stderr) }
        fputs(singleShareIssueRemedy(issue, intent: parsed.intent) + "\n", stderr)
        writeLog("Single-share \(parsed.intent) failed with \(issue.rawValue)")
        return 1
    }
    if !ownershipHeld {
        fputs(tr("⚠ 动作已执行，但后端状态/配置在操作期间发生变化；结果可能已过期，请重新查看状态。\n",
                 "⚠ The action ran, but backend state or configuration changed during it; the result may be stale. Check status again.\n"), stderr)
    }
    let shareName = extractShareName(from: parsed.rawURL) ?? parsed.identity
    if parsed.intent == .mount {
        print(tr("✓ 已挂载共享: \(shareName)", "✓ Mounted share: \(shareName)"))
    } else {
        print(tr("✓ 已弹出共享（普通弹出，未强制）: \(shareName)",
                 "✓ Ejected share (ordinary eject, not forced): \(shareName)"))
    }
    if let detail = outcome.detail { print("  \(detail)") }
    writeLog("Single-share \(parsed.intent) succeeded")
    return 0
}

/// 参数拒绝文案（中英双语，与现有风格一致）。
func singleShareParseMessage(_ problem: CLISingleShareParseProblem, intent: CLISingleShareIntent) -> String {
    switch problem {
    case .missingArgument:
        return tr("✗ 用法: automnt --\(intent == .mount ? "mount" : "eject") <smb://server.example/share>\n",
                  "✗ Usage: automnt --\(intent == .mount ? "mount" : "eject") <smb://server.example/share>\n")
    case .unexpectedExtraArgument:
        return tr("✗ 本命令一次只接受一个共享地址。\n", "✗ This command accepts exactly one share address.\n")
    case .notSMB:
        return tr("✗ 地址必须以 'smb://' 开头。\n", "✗ The address must start with 'smb://'.\n")
    case .embeddedCredentials:
        return tr("✗ 地址不得内嵌用户名或密码；SMB 凭据由系统钥匙串保管。\n",
                  "✗ The address must not embed a username or password; SMB credentials are managed by Keychain.\n")
    case .missingHost:
        return tr("✗ 地址缺少主机名 (例如 smb://server.example/share)。\n",
                  "✗ The address is missing a host name (e.g. smb://server.example/share).\n")
    case .missingShare:
        return tr("✗ 地址缺少共享名称 (例如 smb://server.example/share)。\n",
                  "✗ The address is missing a share name (e.g. smb://server.example/share).\n")
    case .invalidPort:
        return tr("✗ 地址端口超出有效范围。\n", "✗ The address port is out of range.\n")
    case .unresolvableIdentity:
        return tr("✗ 无法解析该地址的稳定身份；未做任何改动。\n",
                  "✗ The stable identity of that address could not be resolved; nothing was changed.\n")
    }
}

/// 失败后的下一步指引，分类沿用 `AutomntIssue`。
func singleShareIssueRemedy(_ issue: AutomntIssue, intent: CLISingleShareIntent) -> String {
    switch issue {
    case .volumeBusy:
        return tr("  → 该共享正在使用中。请关闭占用它的文件或应用后重试；automnt 不会强制弹出。",
                  "  → The share is in use. Close the files or apps using it and retry; automnt never forces an eject.")
    case .credentialFailure:
        return tr("  → 认证失败。请在 Finder 中连接一次并勾选“在我的钥匙串中记住此密码”。",
                  "  → Authentication failed. Connect once in Finder and select 'Remember password in Keychain'.")
    case .authorizationRequired:
        return tr("  → 权限不足，无法完成该操作。",
                  "  → Permission was denied for this operation.")
    case .offline:
        return tr("  → 主机不可达。请检查网络连接与该服务器是否在线。",
                  "  → The host is unreachable. Check the network and whether the server is online.")
    case .configurationConflict:
        return tr("  → 配置或后端状态已被其它操作修改。请重新查看状态后再试；本次未覆盖任何改动。",
                  "  → Configuration or backend state changed elsewhere. Check status and retry; nothing was overwritten.")
    case .incompatibleOwner:
        return tr("  → 后台服务当前由 Automnt 应用管理。请在应用内停用后台服务后再使用命令行。",
                  "  → The background service is managed by the Automnt app. Disable it in the app before using the command line.")
    case .timeout:
        return tr("  → 操作超时且未确认收敛；保留需修复状态。请查看状态后重试。",
                  "  → The operation timed out without confirmed convergence; a repair-required state is retained. Check status and retry.")
    case .pathConflict:
        return intent == .eject
            ? tr("  → 该路径当前未挂载或由其它共享占用；未做任何改动。",
                 "  → That path is not mounted or is occupied by a different share; nothing was changed.")
            : tr("  → 该挂载点被其它卷占用或不可用；未做任何改动。",
                 "  → The mount point is occupied by another volume or unavailable; nothing was changed.")
    case .signalUnavailable:
        return tr("  → 系统未返回可确认的结果；保留需修复状态，请查看状态后重试。",
                  "  → The system did not return a confirmable result; a repair-required state is retained. Check status and retry.")
    case .shareRejected:
        return tr("  → 共享被服务器拒绝。请确认共享名称与访问权限。",
                  "  → The share was rejected by the server. Verify the share name and access permission.")
    case .unconfigured, .backgroundApprovalRequired, .serviceTransitionFailed, .invalidConfiguration:
        return tr("  → 请先运行 'automnt --status' 查看状态并按提示修复。",
                  "  → Run 'automnt --status' to inspect the current state and follow its guidance.")
    }
}

/// 帮助正文（中英双语）。抽成独立值以便回归断言两个新入口与弹出语义不被删改。
func usageText() -> String {
    tr("""
    用法: automnt [选项]

    选项:
      --init [--reset]            运行交互式初始化配置向导 (--reset 重置现有配置)
      --config                    运行日常配置管理菜单 (管理挂载目标、网络策略、挂载范围、更新信道)
      --mount <smb-url>           只挂载一个已在配置中的共享 (例如 smb://server.example/share)
      --eject <smb-url>           普通弹出该共享 (非强制；占用时如实失败，尊重本次会话的弹出意愿)
      --install                   部署并激活当前用户的 LaunchAgent 自启动服务
      --uninstall [--purge]       卸载自启动服务与 CLI (--purge 连同配置文件与日志彻底清理)
      --disable-automation        关闭自动挂载并停用后台，保留配置、共享和 CLI
      --recover-transition UUID --generation N  显式恢复已中断的 CLI 后台转换至停用 (参数见 --status)
      --status                    查看当前安装状态、守护服务运行状态与挂载详情
      --update                    检查并升级软件至最新版本 (免编译下载预编译二进制)
      --migrate-signing --team ID  从临时签名显式迁移至指定 Team（可能需要首次授权）
      --self-test                 运行内置全量自动化自测试套件
      --version, -v               查看当前软件版本号
      --help, -h                  显示帮助说明

    --mount / --eject 说明:
      两个命令一次只作用于一个共享，地址必须完整且不含用户名或密码，
      且该共享必须已在活动配置中，否则报告错误并以非 0 退出码结束。
      --mount 只影响这一个共享，不改变服务器顺序与其它共享的设置。
      --eject 是普通弹出：不会强制，也不会升级为强制弹出。若共享正被
      占用（有文件或应用在使用），弹出会失败并如实报告，共享保持挂载。
      弹出成功后，本次网络与登录会话内不再自动重挂该共享；手动再次
      --mount 会解除该会话内的弹出意愿。

    环境变量:
      AUTOMNT_LANG=zh|en          显式指定终端界面语言 (默认自适应系统语言)
    """, """
    Usage: automnt [options]

    Options:
      --init [--reset]            Run setup wizard (--reset rebuilds existing config)
      --config                    Daily configuration menu (shares, profiles, mount scope, updates)
      --mount <smb-url>           Mount one configured share only (e.g. smb://server.example/share)
      --eject <smb-url>           Ordinary eject of that share (never forced; busy fails honestly and your intent is respected)
      --install                   Deploy and activate user LaunchAgent daemon
      --uninstall [--purge]       Uninstall daemon and CLI entry (--purge deletes config and logs)
      --disable-automation        Disable background mounting; preserve config, shares and CLI
      --recover-transition UUID --generation N  Explicitly recover an interrupted CLI transition to stopped (see --status)
      --status                    Show service status and active mount details
      --update                    Check and self-update to latest prebuilt release
      --migrate-signing --team ID  Explicit ad-hoc identity migration (initial consent may be needed)
      --self-test                 Run full automated test suite
      --version, -v               Show software version
      --help, -h                  Show this help message

    --mount / --eject notes:
      Each command acts on exactly one share. The address must be complete,
      must not embed a username or password, and the share must already be in
      the active configuration; otherwise an error is reported and the command
      exits non-zero. --mount affects only that share and never reorders
      servers or changes other shares' settings. --eject is an ordinary eject:
      it is never forced and never escalates to a forced eject. If the share is
      in use, the eject fails and says so, and the share stays mounted. After a
      successful eject the share is not mounted again automatically for the
      current network and login session; mounting it again with --mount clears
      that session intent.

    Environment Variables:
      AUTOMNT_LANG=zh|en          Explicitly set terminal UI language
    """)
}

func printUsage() {
    print(usageText())
}

// MARK: - 主流程执行逻辑 (Main Entry Point)

public func runAutomntCLI() {
    let args = CommandLine.arguments

    // Recovery has an exact grammar even when mixed with --self-test/help or
    // another command; malformed input must not relocate or heal the installation.
    if args.dropFirst().contains("--recover-transition") {
        guard args.count > 1, args[1] == "--recover-transition",
              CLIRecoveryRequest.parse(Array(args.dropFirst(2))) != nil else {
            fputs("Usage: automnt --recover-transition UUID --generation N\n", stderr)
            exit(64)
        }
    }

    if args.count == 3 && args[1] == "--internal-disable-spotlight" {
        performDisableSpotlightIndex(at: args[2])
        exit(0)
    }

    if args.count == 3 && args[1] == "--internal-volume-health" {
        guard let directory = opendir(args[2]) else {
            let failure = errno
            exit([EIO, ENXIO, ENOTCONN, ESTALE, ETIMEDOUT].contains(failure) ? 74 : 75)
        }
        errno = 0
        _ = readdir(directory)
        let failure = errno
        closedir(directory)
        exit(failure == 0 ? 0 : ([EIO, ENXIO, ENOTCONN, ESTALE, ETIMEDOUT].contains(failure) ? 74 : 75))
    }

    if args.count == 5 && args[1] == "--internal-host-probe" {
        guard let port = Int(args[3]), let timeout = Int(args[4]) else { exit(1) }
        exit(HostReachabilityProbe.canConnect(host: args[2], port: port, timeoutMs: timeout) ? 0 : 1)
    }

    if args.count == 4 && args[1] == "--internal-netfs-mount" {
        let mounted = performNetFSMount(urlString: args[2], mountPath: args[3])
        let credentialFailure = [Int32(EACCES), Int32(EAUTH), Int32(ENEEDAUTH), -5000, -5023].contains(MountExecutionBudget.netFSStatus)
        exit(mounted ? 0 : (credentialFailure ? 77 : 1))
    }

    // T077：单共享普通弹出的隔离子进程，自己持有 evaluation.lock。
    // 父进程在等待期间不持锁，因此这里不会与父进程的许可自锁。
    //
    // 与其它内部标志不同，这里对参数个数做显式拒绝而不是静默落空：该标志一旦
    // 落到用户主流程，就会对真实配置执行完整的挂载评估。畸形调用必须是用法错误。
    if args.count > 1 && args[1] == "--internal-normal-eject" {
        guard args.count == 5 else { exit(64) }
        exit(runInternalNormalEject(arguments: Array(args[2...])))
    }

    if args.contains("--self-test") {
        let success = runSelfTestsEntry(includeNetworkChecks: args.contains("--network"))
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

    // Approved local policy: 7 days / 5 MB per file. Help, version and self-test
    // paths returned above and never touch user logs.
    try? LogRetention.enforce(files: LogRetention.defaultLogFiles(
        configurationDirectory: getActiveInstalledDir()))

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

    if args.count > 1 && args[1] == "--migrate-signing" {
        guard args.count == 4, args[2] == "--team" else {
            fputs("Usage: automnt --migrate-signing --team TEAM_ID\n", stderr)
            exit(2)
        }
        guard InstallationManager.migrateAdHocInstallation(expectedTeam: args[3]) else {
            fputs(tr("✗ 签名迁移被拒绝或失败；检查候选签名、指定 Team 与旧程序身份。\n",
                     "✗ Signing migration rejected or failed; check candidate signature, specified team and previous identity.\n"), stderr)
            exit(1)
        }
        exit(0)
    }

    // Explicit repair never relocates, self-heals, mounts, or enables a service.
    if args.count > 1 && args[1] == "--recover-transition" {
        exit(runCLIRecoveryCommand(arguments: Array(args.dropFirst(2))))
    }

    // Status is a read-only inspection of the canonical installation, even when
    // this executable is a downloaded candidate with a different signing identity.
    // Never relocate, replace the installation or heal its service on this path.
    if args.count > 1 && args[1] == "--status" {
        guard args.count == 2 else {
            fputs(tr("✗ 用法: automnt --status\n", "✗ Usage: automnt --status\n"), stderr)
            exit(2)
        }
        checkServiceStatus()
        exit(0)
    }

    // Explicit release must run before relocation/healing so it never re-enables
    // the service it is about to stop or replaces the existing installation.
    if args.count > 1 && args[1] == "--disable-automation" {
        guard args.count == 2 else {
            fputs("Usage: automnt --disable-automation\n", stderr)
            exit(2)
        }
        guard !DaemonRuntime.isDaemon() else { exit(1) }
        do {
            try CLIOwnership.disableAutomation()
            print(tr("✓ 自动挂载已关闭，后台服务已停用；配置与已挂载共享保留。",
                     "✓ Automatic mounting disabled and background service stopped; configuration and mounted shares preserved."))
            exit(0)
        } catch {
            fputs(tr("✗ 未能确认后台服务已停用。请检查状态后重试；不要启用第二个后台服务。\n",
                     "✗ Background service release was not confirmed. Check status and retry before enabling another service.\n"), stderr)
            exit(1)
        }
    }

    // T077：单共享挂载与普通弹出。与 --status 同理，动作必须作用于规范安装目录的
    // 单一活动配置，因此在本进程自搬迁之前处理：搬迁会替换当前可执行文件，
    // 绝不能在“正在执行动作”的进程中发生。
    if args.count > 1 && (args[1] == "--mount" || args[1] == "--eject") {
        let intent: CLISingleShareIntent = args[1] == "--mount" ? .mount : .eject
        exit(runSingleShareCommand(intent: intent, arguments: Array(args.dropFirst(2))))
    }

    // 自搬迁安装与首次运行引导 (US1)
    let justRelocated = InstallationManager.relocateIfNeeded()
    if !justRelocated && InstallationManager.currentExecutablePhysicalURL().standardizedFileURL.path != getActiveInstalledBinaryURL().standardizedFileURL.path {
        // 搬迁失败必须停止，不能继续从下载副本写配置或注册服务。
        exit(1)
    }
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

    guard config.isAutomationEnabled else {
        print(tr("自动挂载已关闭，已挂载共享保持可用。", "Automatic mounting is off; existing mounted shares remain available."))
        exit(0)
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

    // T010-a：真实挂载/恢复动作前取得统一 evaluation.lock 许可。
    // 许可在整段有界操作期间有效；owner、revision、generation 任一变化即拒绝，
    // 绝不用过期快照执行新动作。被拒绝时不进行任何挂载副作用。
    guard let ownershipPermit = CLIOwnership.beginEvaluation() else {
        fputs(tr("✗ 已取消本次挂载评估：后端所有权或配置代次校验未通过。请检查服务状态后重试。\n",
                 "✗ Mount evaluation cancelled: backend ownership or configuration generation verification failed. Check service status and retry.\n"), stderr)
        exit(1)
    }
    // 以许可核验过的已提交配置为准执行真实动作。
    config = ownershipPermit.snapshot.configuration

    // Feature 004：恢复判定轮先于基线段挂载执行。
    // 关键：会话抑制的卷必须在基线段被跳过，否则「健康弹出后零重挂」红线不成立。
    var suppressedVolumeKeys: Set<String> = []
    var recoveredVolumeKeys: Set<String> = []
    var protectedVolumeKeys: Set<String> = []
    var deferredVolumeKeys: Set<String> = []
    if config.isAutoMountRecoveryEnabled {
        var mountTable: [String: String] = [:]
        for entry in getKernelMountEntries() where entry.fileSystemType.lowercased() == "smbfs" {
            if let key = smbResourceIdentity(entry.source) {
                mountTable[key] = entry.mountPoint
            }
        }
        let reachabilityCache = ReachabilityCache(
            probe: { host, port in
                let timeout = config.hosts.first(where: { $0.host == host })?.timeoutMs ?? 1000
                return boundedHostReachability(host: host, port: port, timeoutMs: timeout)
            })
        let outcome = runRecoveryRound(
            config: config,
            mountTable: mountTable,
            hostReachability: { host, port in reachabilityCache.isReachable(host: host, port: port) },
            applyRecovery: { volume, cfg in
                let status = ensureMountPointReady(target: MountTarget(url: volume.url, mountPath: volume.mountPoint))
                switch status {
                case .alreadyMountedHealthy:
                    return true // 幂等：已挂载即跳过，且自身动作不产生新的恢复尝试
                case .readyToMount:
                    let mounted = silentMount(urlString: volume.url, mountPath: volume.mountPoint)
                    if mounted && volume.preventSpotlightIndex {
                        disableSpotlightIndex(at: volume.mountPoint)
                    }
                    return mounted
                case .unmountFailed:
                    return false
                }
            }, ownershipPermit: ownershipPermit)
        // 恢复轮已处理的目标不再进入基线段重复尝试。
        suppressedVolumeKeys = Set(outcome.suppressed + outcome.failed + outcome.recovered + outcome.deferredVolumeKeys)
        recoveredVolumeKeys = Set(outcome.recovered)
        protectedVolumeKeys = Set(outcome.suppressed)
        deferredVolumeKeys = Set(outcome.deferredVolumeKeys)
        if !outcome.deferredVolumeKeys.isEmpty {
            print(tr("  · 恢复评估暂未执行（另一轮正在运行或状态锁不可用）",
                     "  · Recovery evaluation deferred (another evaluation is running or the state lock is unavailable)"))
        }
        if !outcome.recovered.isEmpty {
            print(tr("  ✓ 自动恢复成功: \(outcome.recovered.count) 个卷",
                     "  ✓ Auto-recovered \(outcome.recovered.count) volume(s)"))
        }
        if let diagnostic = outcome.stateDiagnostic { print(diagnostic) }
        if !outcome.suppressed.isEmpty && outcome.stateDiagnostic == nil {
            print(tr("  · 会话抑制中（尊重手动弹出）: \(outcome.suppressed.count) 个卷",
                     "  · Session-suppressed (respecting manual eject): \(outcome.suppressed.count) volume(s)"))
        }
        if !outcome.failed.isEmpty {
            print(tr("  · 本轮未恢复: \(outcome.failed.count) 个卷",
                     "  · Not restored this round: \(outcome.failed.count) volume(s)"))
        }
        // 仅实际失败发通知；抑制保持静默（每轮至多一条，会话级上限）。
        if outcome.hasVisibleFallbackTrigger,
           let notification = recoveryFallbackNotificationText(for: outcome, config: config) {
            showMacOSNotification(title: notification.title,
                                  subtitle: notification.subtitle,
                                  message: notification.message)
        }
    }

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
            boundedHostReachability(host: host, port: port, timeoutMs: timeout)
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
        _ = CLIOwnership.endEvaluation(ownershipPermit)
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
        // 会话抑制的卷在基线段必须跳过（SC-002 红线：健康弹出后本会话零重挂）。
        if let key = smbResourceIdentity(share.smbURL), suppressedVolumeKeys.contains(key) {
            if recoveredVolumeKeys.contains(key) {
                mountedCount += 1
                print(tr("  已在本轮恢复: \(share.mountPoint)", "  Already restored this round: \(share.mountPoint)"))
            } else if deferredVolumeKeys.contains(key) {
                print(tr("  评估暂未执行，跳过并发挂载: \(share.mountPoint)",
                         "  Evaluation deferred; skipping concurrent mount: \(share.mountPoint)"))
            } else if protectedVolumeKeys.contains(key) {
                print(tr("  跳过会话抑制中的共享: \(share.mountPoint)",
                         "  Skipping session-suppressed share: \(share.mountPoint)"))
            } else {
                failedCount += 1
                print(tr("  本轮恢复已失败，跳过重复尝试: \(share.mountPoint)",
                         "  Recovery failed this round; skipping duplicate attempt: \(share.mountPoint)"))
            }
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
    // 动作后在持锁上下文内复核代次：变化即报告，绝不复用过期快照执行新动作。
    _ = CLIOwnership.endEvaluation(ownershipPermit)
    triggerBackgroundUpdateCheckIfNeeded(config: &config)
    if failedCount > 0 {
        writeLog("Mount evaluation failed for \(failedCount) configured target(s).")
        exit(2)
    }
}

