import Foundation

public struct ConfigurationProblem: Equatable, Sendable {
    public let hostIndex: Int
    public let shareIndex: Int?
    public let reason: Reason
    public enum Reason: String, Sendable {
        case invalidHost, invalidPort, emptySMBURL, invalidSMBURL, emptyShareName, embeddedCredentials, hostMismatch
        case invalidMountPath, duplicateHost, duplicateShare, duplicateMountPath
    }
}

public enum ConfigurationValidation {
    public static func problems(in configuration: AutomntConfig) -> [ConfigurationProblem] {
        var results: [ConfigurationProblem] = []
        var hosts = Set<String>()
        let legacyHosts = configuration.profiles.map { profile in
            HostConfig(host: profile.host, alias: profile.description, port: profile.port ?? 445,
                       timeoutMs: profile.timeoutMs ?? 1000,
                       preventSpotlightIndex: profile.preventSpotlightIndex ?? true,
                       shares: profile.targets.map { target in
                           SMBShareConfig(name: extractShareName(from: target.url) ?? "", smbURL: target.url,
                                          mountPoint: target.mountPath)
                       })
        }
        for (hi, host) in (configuration.hosts + legacyHosts).enumerated() {
            func report(_ reason: ConfigurationProblem.Reason, _ share: Int? = nil) {
                results.append(ConfigurationProblem(hostIndex: hi, shareIndex: share, reason: reason))
            }
            let hostname = host.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if hostname.isEmpty || hostname.contains("/") || hostname.contains("@") { report(.invalidHost) }
            if !(1...65535).contains(host.port) { report(.invalidPort) }
            if !hosts.insert("\(hostname):\(host.port)").inserted { report(.duplicateHost) }
            var shares = Set<String>()
            var paths = Set<String>()
            for (si, share) in host.shares.enumerated() {
                if share.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { report(.emptyShareName, si) }
                let address = share.smbURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !address.isEmpty else {
                    report(.emptySMBURL, si)
                    continue
                }
                let input = address.hasPrefix("//") ? "smb:\(address)" : address
                guard let url = URLComponents(string: input), url.scheme?.lowercased() == "smb",
                      let urlHost = url.host, !urlHost.isEmpty,
                      let name = extractShareName(from: share.smbURL), !name.isEmpty,
                      url.query == nil, url.fragment == nil else {
                    report(.invalidSMBURL, si)
                    continue
                }
                if url.user != nil || url.password != nil { report(.embeddedCredentials, si) }
                let port = url.port ?? 445
                if !(1...65535).contains(port) { report(.invalidPort, si) }
                let normalizedURLHost = urlHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
                let normalizedHost = hostname.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                if normalizedURLHost != normalizedHost || port != host.port { report(.hostMismatch, si) }
                let identity = name.lowercased().precomposedStringWithCanonicalMapping
                if !shares.insert(identity).inserted {
                    report(.duplicateShare, si)
                }
                let mount = share.mountPoint
                let components = mount.split(separator: "/")
                if !mount.hasPrefix("/") || mount == "/" || components.contains("..") || components.contains(".") || mount.contains("\0") {
                    report(.invalidMountPath, si)
                }
                if !paths.insert(URL(fileURLWithPath: mount).standardizedFileURL.path).inserted {
                    report(.duplicateMountPath, si)
                }
            }
        }
        return results
    }
}
