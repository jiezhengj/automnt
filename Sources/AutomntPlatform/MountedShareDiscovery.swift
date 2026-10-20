import Foundation
import Darwin
import AutomntCore

/// Foreground discovery reads kernel metadata only; it never contacts or opens a share.
public enum MountedShareDiscovery {
    public struct Candidate: Identifiable, Equatable, Sendable {
        public var id: String { share.smbURL + "\n" + share.mountPoint }
        public let host: String
        public let port: Int
        public let share: SMBShareConfig
    }

    public static func candidate(source: String, mountPoint: String) -> Candidate? {
        let input = source.hasPrefix("//") ? "smb:" + source : source
        guard var components = URLComponents(string: input),
              components.scheme?.lowercased() == "smb", let host = components.host,
              !host.isEmpty, let name = extractShareName(from: input), !name.isEmpty else { return nil }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        guard let address = components.string else { return nil }
        let port = components.port ?? 445
        let share = SMBShareConfig(name: name, smbURL: address, mountPoint: mountPoint)
        var config = AutomntConfig()
        config.hosts = [HostConfig(host: host, port: port, shares: [share])]
        guard ConfigurationValidation.problems(in: config).isEmpty else { return nil }
        return Candidate(host: host, port: port, share: share)
    }

    public static func read() throws -> [Candidate] {
        var table: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&table, MNT_NOWAIT)
        guard count > 0, let table else { throw AutomntIssue.signalUnavailable }
        var result: [Candidate] = []
        for index in 0..<Int(count) {
            var entry = table[index]
            let filesystem = withUnsafePointer(to: &entry.f_fstypename) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSNAMELEN)) { String(cString: $0) }
            }
            guard filesystem == "smbfs" else { continue }
            let source = withUnsafePointer(to: &entry.f_mntfromname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            let path = withUnsafePointer(to: &entry.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            if let candidate = candidate(source: source, mountPoint: path), !result.contains(candidate) {
                result.append(candidate)
            }
        }
        return result.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    /// Kernel-observed identity for one mount path. Used to confirm that a path really
    /// carries the target identity before any eject, and to build the inventory's
    /// mounted set. Reads the mount table only; it never opens the share.
    public static func mountedIdentities() throws -> [String: String] {
        var table: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&table, MNT_NOWAIT)
        guard count > 0, let table else { throw AutomntIssue.signalUnavailable }
        var result: [String: String] = [:]
        for index in 0..<Int(count) {
            var entry = table[index]
            let filesystem = withUnsafePointer(to: &entry.f_fstypename) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSNAMELEN)) { String(cString: $0) }
            }
            guard filesystem == "smbfs" else { continue }
            let source = withUnsafePointer(to: &entry.f_mntfromname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            let path = withUnsafePointer(to: &entry.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            guard let identity = smbResourceIdentity(source) else { continue }
            result[path] = identity
        }
        return result
    }
}

public extension MountedShareDiscovery.Candidate {
    /// Maps the platform discovery result into the Core inventory input so the
    /// projection stays free of platform dependencies.
    var inventoryShare: ServerInventory.DiscoveredShare {
        ServerInventory.DiscoveredShare(host: host, port: port, name: share.name,
                                       smbURL: share.smbURL, mountPoint: share.mountPoint)
    }
}
