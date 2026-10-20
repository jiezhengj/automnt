import Foundation
import Testing
@testable import AutomntCore

struct ConfigurationContractTests {
    private func model() -> AutomntConfig {
        let host = UUID().uuidString.lowercased()
        let share = UUID().uuidString
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(share).path
        return AutomntConfig(hosts: [HostConfig(host: host, shares: [
            SMBShareConfig(name: share, smbURL: "smb://\(host)/\(share)", mountPoint: path)
        ])])
    }

    @Test func validationRejectsLocalConflictsButAllowsBackupPaths() {
        let valid = model()
        #expect(ConfigurationValidation.problems(in: valid).isEmpty)
        var backup = valid
        let alternate = UUID().uuidString.lowercased()
        var second = valid.hosts[0]
        second.host = alternate
        second.shares[0].smbURL = "smb://\(alternate)/\(second.shares[0].name)"
        backup.hosts.append(second)
        #expect(ConfigurationValidation.problems(in: backup).isEmpty)
        var duplicate = valid
        duplicate.hosts[0].shares.append(duplicate.hosts[0].shares[0])
        let reasons = ConfigurationValidation.problems(in: duplicate).map(\.reason)
        #expect(reasons.contains(.duplicateShare))
        #expect(reasons.contains(.duplicateMountPath))
        for port in [0, 65536] {
            var invalid = valid
            invalid.hosts[0].port = port
            #expect(ConfigurationValidation.problems(in: invalid).contains { $0.reason == .invalidPort })
        }
        var credentials = valid
        credentials.hosts[0].shares[0].smbURL = "smb://\(UUID().uuidString)@\(credentials.hosts[0].host)/\(credentials.hosts[0].shares[0].name)"
        #expect(ConfigurationValidation.problems(in: credentials).contains { $0.reason == .embeddedCredentials })
    }

    @Test func validationDistinguishesRequiredFieldsFromInvalidAddresses() {
        var missing = model()
        missing.hosts[0].shares[0].smbURL = " \n "
        missing.hosts[0].shares[0].name = "  "
        let reasons = ConfigurationValidation.problems(in: missing).map(\.reason)
        #expect(reasons.contains(.emptySMBURL))
        #expect(reasons.contains(.emptyShareName))
        #expect(!reasons.contains(.invalidSMBURL))
        for address in ["smb://", "smb://server/", "smb://server/share?query", "smb://server/share#fragment", "https://server/share"] {
            var invalid = model()
            invalid.hosts[0].shares[0].smbURL = address
            #expect(ConfigurationValidation.problems(in: invalid).contains { $0.reason == .invalidSMBURL })
        }
    }

    @Test func unknownFieldsAndLegacyIntentSurviveManagedMerge() throws {
        var configuration = model()
        configuration.automationEnabled = nil
        configuration.autoMountRecovery = nil
        configuration.retryPolicy = RetryPolicy(maxAttempts: 5, intervalMs: 1500, maxTotalWindowMs: 12000)
        let encoder = PropertyListEncoder()
        var original = try #require(PropertyListSerialization.propertyList(from: encoder.encode(configuration), format: nil) as? [String: Any])
        let extensionKey = "extension_" + UUID().uuidString
        let value = UUID().uuidString
        original[extensionKey] = value
        var hosts = try #require(original["hosts"] as? [[String: Any]])
        hosts[0][extensionKey] = value
        var shares = try #require(hosts[0]["shares"] as? [[String: Any]])
        shares[0][extensionKey] = value
        hosts[0]["shares"] = shares
        original["hosts"] = hosts
        let decoded = try PropertyListDecoder().decode(AutomntConfig.self, from: PropertyListSerialization.data(fromPropertyList: original, format: .binary, options: 0))
        #expect(decoded.isAutomationEnabled)
        configuration.automationEnabled = false
        configuration.autoMountRecovery = true
        configuration.mountPolicy = .allReachable
        let merged = try #require(mergeConfigPlistValue(original: original,
            generated: PropertyListSerialization.propertyList(from: encoder.encode(configuration), format: nil), context: .root) as? [String: Any])
        #expect(merged[extensionKey] as? String == value)
        let mergedHosts = try #require(merged["hosts"] as? [[String: Any]])
        #expect(mergedHosts[0][extensionKey] as? String == value)
        let mergedShares = try #require(mergedHosts[0]["shares"] as? [[String: Any]])
        #expect(mergedShares[0][extensionKey] as? String == value)
        let roundtrip = try PropertyListDecoder().decode(AutomntConfig.self, from: PropertyListSerialization.data(fromPropertyList: merged, format: .binary, options: 0))
        #expect(!roundtrip.isAutomationEnabled)
        #expect(roundtrip.isAutoMountRecoveryEnabled)
        #expect(roundtrip.isMountAllEnabled)
        #expect(roundtrip.retryPolicy == configuration.retryPolicy)
        #expect(roundtrip.hosts == configuration.hosts)
        var legacy = AutomntConfig()
        legacy.profiles = [NetworkProfile(id: UUID().uuidString, host: configuration.hosts[0].host,
            targets: [MountTarget(url: configuration.hosts[0].shares[0].smbURL, mountPath: configuration.hosts[0].shares[0].mountPoint)])]
        let legacyRoundtrip = try PropertyListDecoder().decode(AutomntConfig.self, from: encoder.encode(legacy))
        #expect(legacyRoundtrip.profiles == legacy.profiles)
        #expect(ConfigurationValidation.problems(in: legacyRoundtrip).isEmpty)
        var forbidden = original
        forbidden["password"] = UUID().uuidString
        #expect(throws: (any Error).self) { try ConfigurationPrivacy.validate(forbidden) }
    }

    @Test func repositoryRoundtripRejectsInvalidDraftWithoutLosingChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let first = try repository.create(model())
        #expect(first.configuration.effectiveMountPolicy == .firstReachable)
        #expect(throws: AutomntIssue.configurationConflict) { try repository.create(model()) }
        var draft = first.configuration
        draft.hosts[0].shares.append(draft.hosts[0].shares[0])
        #expect(throws: AutomntIssue.invalidConfiguration) { try repository.save(draft, baseRevision: first.revision) }
        #expect(draft.hosts[0].shares.count == 2)
        #expect(try repository.read().revision == first.revision)
        var switches = first.configuration
        switches.automationEnabled = false
        switches.autoMountRecovery = true
        switches.mountPolicy = .allReachable
        let saved = try repository.save(switches, baseRevision: first.revision)
        let reopened = try FileConfigRepository(authorizedDirectory: directory).read()
        #expect(reopened.revision == saved.revision)
        #expect(!reopened.configuration.isAutomationEnabled)
        #expect(reopened.configuration.isAutoMountRecoveryEnabled)
        #expect(reopened.configuration.isMountAllEnabled)
        switches.automationEnabled = true
        switches.autoMountRecovery = false
        switches.mountPolicy = nil
        _ = try repository.save(switches, baseRevision: reopened.revision)
        let final = try repository.read()
        #expect(final.configuration.isAutomationEnabled)
        #expect(!final.configuration.isAutoMountRecoveryEnabled)
        #expect(final.configuration.effectiveMountPolicy == .firstReachable)
        #expect(final.configuration.hosts == first.configuration.hosts)
    }

    /// 未来版本写入未知 mount_policy 时，旧版本仍须能读取配置并使用默认策略，
    /// 不能因一个枚举值让整个配置不可读。
    @Test func unknownMountPolicyValueFallsBackToDefault() throws {
        let plist: [String: Any] = [
            "version": AutomntBuildVersion.value,
            "mount_policy": "serial_then_parallel",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let decoded = try PropertyListDecoder().decode(AutomntConfig.self, from: data)
        #expect(decoded.mountPolicy == nil)
        #expect(decoded.effectiveMountPolicy == .firstReachable)
    }
}
