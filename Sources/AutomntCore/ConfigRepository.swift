import Foundation
import CryptoKit
import Darwin

/// The caller must supply the resolved, authorized shared directory.
/// This repository never chooses a sandbox-container fallback.
public struct FileConfigRepository: ConfigRepository {
    public let directory: URL
    public init(authorizedDirectory: URL) { self.directory = authorizedDirectory }
    private var configurationURL: URL { directory.appendingPathComponent("automnt.plist") }

    public func read() throws -> ConfigSnapshot {
        try withConfigurationLock {
            try snapshot(data: PrivateAtomicFile.read(configurationURL))
        }
    }

    @discardableResult
    public func save(_ configuration: AutomntConfig, baseRevision: ConfigRevision) throws -> ConfigSnapshot {
        try withConfigurationLock {
            let original = try PrivateAtomicFile.read(configurationURL)
            guard revision(original) == baseRevision else { throw AutomntIssue.configurationConflict }
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let generated = try encoder.encode(configuration)
            let merged = mergeConfigPlistValue(
                original: try PropertyListSerialization.propertyList(from: original, format: nil),
                generated: try PropertyListSerialization.propertyList(from: generated, format: nil), context: .root)
            try ConfigurationPrivacy.validate(merged)
            guard ConfigurationValidation.problems(in: configuration).isEmpty else { throw AutomntIssue.invalidConfiguration }
            let data = try PropertyListSerialization.data(fromPropertyList: merged, format: .xml, options: 0)
            try replace(data)
            return try snapshot(data: data)
        }
    }

    /// Only used after foreground discovery or explicit input created the model.
    /// A competing creation is reported as a conflict, never overwritten.
    public func create(_ configuration: AutomntConfig) throws -> ConfigSnapshot {
        try withConfigurationLock {
            guard !FileManager.default.fileExists(atPath: configurationURL.path) else {
                throw AutomntIssue.configurationConflict
            }
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(configuration)
            try ConfigurationPrivacy.validate(PropertyListSerialization.propertyList(from: data, format: nil))
            guard ConfigurationValidation.problems(in: configuration).isEmpty else { throw AutomntIssue.invalidConfiguration }
            try replace(data)
            return try snapshot(data: data)
        }
    }

    /// Imports bytes selected by the user without dropping unknown fields. The
    /// caller must complete legacy service release before calling this method.
    /// Imported automation is always disabled until an explicit background setup.
    public func importConfiguration(_ source: Data) throws -> ConfigSnapshot {
        try withConfigurationLock {
            guard !FileManager.default.fileExists(atPath: configurationURL.path) else {
                throw AutomntIssue.configurationConflict
            }
            guard source.count <= 1_048_576,
                  var value = try PropertyListSerialization.propertyList(from: source, format: nil) as? [String: Any] else {
                throw AutomntIssue.invalidConfiguration
            }
            try ConfigurationPrivacy.validate(value)
            value["automation_enabled"] = false
            let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
            let imported = try snapshot(data: data)
            guard !imported.configuration.isAutomationEnabled else { throw AutomntIssue.invalidConfiguration }
            try replace(data)
            return imported
        }
    }

    /// Holds config.lock through a related durable commit. The operation must not
    /// re-enter this repository or invoke system services while holding the lock.
    func withRevision<T>(_ expected: ConfigRevision, operation: () throws -> T) throws -> T {
        try withConfigurationLock {
            let current = try snapshot(data: PrivateAtomicFile.read(configurationURL))
            guard current.revision == expected else { throw AutomntIssue.configurationConflict }
            return try operation()
        }
    }

    private func revision(_ data: Data) -> ConfigRevision {
        ConfigurationRevision.of(data)
    }

    private func snapshot(data: Data) throws -> ConfigSnapshot {
        try ConfigurationPrivacy.validate(PropertyListSerialization.propertyList(from: data, format: nil))
        let configuration = try PropertyListDecoder().decode(AutomntConfig.self, from: data)
        guard ConfigurationValidation.problems(in: configuration).isEmpty else { throw AutomntIssue.invalidConfiguration }
        return ConfigSnapshot(configuration: configuration, revision: revision(data))
    }

    private func withConfigurationLock<T>(_ operation: () throws -> T) throws -> T {
        let url = directory.appendingPathComponent("config.lock")
        let lock: StableFileLock
        do { lock = try StableFileLock(url: url) }
        catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EWOULDBLOCK) {
            throw AutomntIssue.configurationConflict
        }
        return try withExtendedLifetime(lock) { try operation() }
    }

    private func replace(_ data: Data) throws {
        try PrivateAtomicFile.replace(data, at: configurationURL)
    }

    private func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
