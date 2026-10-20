import Foundation

public enum ConfigPlistContext: Equatable {
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

public func canonicalProfileID(_ value: String) -> String {
    switch value {
    case "home_lan": return "local_lan"
    case "tailscale_remote": return "remote_network"
    default: return value
    }
}

public func managedConfigKeys(for context: ConfigPlistContext) -> Set<String> {
    switch context {
    case .root:
        return ["version", "update_channel", "retry_policy", "last_update_check_timestamp",
                "update_retry_after_timestamp", "last_notified_version", "hosts", "profiles",
                "auto_mount_recovery", "automation_enabled", "mount_policy"]
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

public func childConfigPlistContext(parent: ConfigPlistContext, key: String) -> ConfigPlistContext {
    switch (parent, key) {
    case (.root, "profiles"): return .profiles
    case (.profile, "targets"): return .targets
    case (.root, "hosts"): return .hosts
    case (.host, "shares"): return .shares
    default: return .other
    }
}

public func configPlistIdentity(_ value: Any, context: ConfigPlistContext) -> String? {
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

public func mergeConfigPlistValue(original: Any, generated: Any, context: ConfigPlistContext) -> Any {
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

public func encodeConfigPreservingUnknownFields(_ config: AutomntConfig, at configURL: URL) throws -> Data {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .xml
    let generatedData = try encoder.encode(config)

    let originalData: Data
    do { originalData = try PrivateAtomicFile.read(configURL) }
    catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == 2 {
        return generatedData
    }
    let originalPlist = try PropertyListSerialization.propertyList(from: originalData, options: [], format: nil)
    guard originalPlist is [String: Any] else { throw AutomntIssue.invalidConfiguration }
    try ConfigurationPrivacy.validate(originalPlist)
    let generatedPlist = try PropertyListSerialization.propertyList(from: generatedData, options: [], format: nil)

    let mergedPlist = mergeConfigPlistValue(original: originalPlist, generated: generatedPlist, context: .root)
    return try PropertyListSerialization.data(fromPropertyList: mergedPlist, format: .xml, options: 0)
}

