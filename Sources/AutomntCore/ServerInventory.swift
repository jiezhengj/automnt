import Foundation

/// Read-only projection of what the interface should show. It merges the single
/// active configuration (managed servers) with this machine's currently mounted SMB
/// shares (discoverable candidates). Discovery never enumerates the network, and a
/// managed share stays listed even when it is offline or ejected.
public enum ServerInventory {
    public struct Share: Identifiable, Equatable, Sendable {
        public var id: String { identity }
        public let identity: String
        public let name: String
        public let smbURL: String
        public let mountPoint: String
        public let enabled: Bool
        /// True when this share is part of the saved configuration.
        public let managed: Bool
        /// True only when the kernel actually reports this identity mounted here.
        public let mounted: Bool

        public init(identity: String, name: String, smbURL: String, mountPoint: String,
                    enabled: Bool, managed: Bool, mounted: Bool) {
            self.identity = identity
            self.name = name
            self.smbURL = smbURL
            self.mountPoint = mountPoint
            self.enabled = enabled
            self.managed = managed
            self.mounted = mounted
        }
    }

    public struct Server: Identifiable, Equatable, Sendable {
        public var id: String { identity }
        public let identity: String
        public let host: String
        public let port: Int
        public let alias: String?
        /// Position in the saved managed order; nil for a not-yet-managed candidate.
        public let managedIndex: Int?
        public let managedShares: [Share]
        public let addableShares: [Share]

        public var isManaged: Bool { managedIndex != nil }
        public var displayName: String {
            if let alias, !alias.isEmpty { return alias }
            // Bonjour SMB service names contain a protocol suffix that is not useful
            // in a row title; the full host stays available as help text/subtitle.
            if let range = host.range(of: "._smb._tcp", options: .caseInsensitive) {
                return String(host[..<range.lowerBound])
            }
            return host
        }
        public var summary: Summary {
            Summary(managedCount: managedShares.count, addableCount: addableShares.count, problemCount: problemCount)
        }
        /// Problems are declared by the caller, never inferred from absence of a mount.
        var problemCount: Int = 0

        init(identity: String, host: String, port: Int, alias: String?, managedIndex: Int?,
             managedShares: [Share], addableShares: [Share], problemCount: Int = 0) {
            self.identity = identity
            self.host = host
            self.port = port
            self.alias = alias
            self.managedIndex = managedIndex
            self.managedShares = managedShares
            self.addableShares = addableShares
            self.problemCount = problemCount
        }
    }

    public struct Summary: Equatable, Sendable {
        public let managedCount: Int
        public let addableCount: Int
        public let problemCount: Int
    }

    public struct Snapshot: Equatable, Sendable {
        /// Saved order; safe to use directly for the managed group.
        public let managed: [Server]
        /// Newly discovered servers only; never participates in ordering.
        public let addable: [Server]

        public func server(identity: String) -> Server? {
            managed.first { $0.identity == identity } ?? addable.first { $0.identity == identity }
        }
    }

    /// One locally mounted SMB share observed on this machine. Declared in Core so the
    /// projection does not depend on any platform discovery implementation.
    public struct DiscoveredShare: Equatable, Sendable {
        public let host: String
        public let port: Int
        public let name: String
        public let smbURL: String
        public let mountPoint: String

        public init(host: String, port: Int = 445, name: String, smbURL: String, mountPoint: String) {
            self.host = host
            self.port = port
            self.name = name
            self.smbURL = smbURL
            self.mountPoint = mountPoint
        }
    }

    /// Builds the projection. `discovered` is the locally mounted SMB set; any share
    /// whose identity is already managed is not repeated as addable.
    public static func build(configuration: AutomntConfig?,
                             discovered: [DiscoveredShare],
                             mounted: Set<String>,
                             foundProblems: Set<String> = []) -> Snapshot {
        var managed: [Server] = []
        var addable: [Server] = []
        var knownHosts = Set<String>()

        for (index, host) in (configuration?.hosts ?? []).enumerated() {
            let identity = managedServerIdentity(host)
            knownHosts.insert(identity)
            let shares = host.shares.map { share -> Share in
                let shareIdentity = smbResourceIdentity(share.smbURL) ?? share.smbURL
                return Share(identity: shareIdentity, name: share.name, smbURL: share.smbURL,
                             mountPoint: share.mountPoint, enabled: share.enabled, managed: true,
                             mounted: mounted.contains(shareIdentity))
            }
            managed.append(Server(
                identity: identity, host: host.host, port: host.port, alias: host.alias,
                managedIndex: index, managedShares: shares, addableShares: [],
                problemCount: shares.filter { foundProblems.contains($0.identity) }.count))
        }

        // Group discovery by server, keeping only shares that are not already managed.
        var order: [String] = []
        var grouped: [String: [Share]] = [:]
        var meta: [String: (host: String, port: Int, alias: String?)] = [:]
        for candidate in discovered {
            let identity = managedServerIdentity(HostConfig(host: candidate.host, port: candidate.port))
            let shareIdentity = smbResourceIdentity(candidate.smbURL) ?? candidate.smbURL
            let alreadyManaged = managed.contains { server in
                server.managedShares.contains { $0.identity == shareIdentity }
            }
            if alreadyManaged { continue }
            if grouped[identity] == nil {
                order.append(identity)
                grouped[identity] = []
                meta[identity] = (candidate.host, candidate.port, nil)
            }
            guard !(grouped[identity]?.contains { $0.identity == shareIdentity } ?? false) else { continue }
            grouped[identity]?.append(Share(
                identity: shareIdentity, name: candidate.name, smbURL: candidate.smbURL,
                mountPoint: candidate.mountPoint, enabled: true,
                managed: false, mounted: true))
        }
        for index in managed.indices {
            let server = managed[index]
            let shares = (grouped[server.identity] ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            managed[index] = Server(
                identity: server.identity, host: server.host, port: server.port, alias: server.alias,
                managedIndex: server.managedIndex, managedShares: server.managedShares,
                addableShares: shares,
                problemCount: server.problemCount + shares.filter { foundProblems.contains($0.identity) }.count)
        }
        for identity in order where !knownHosts.contains(identity) {
            guard let shares = grouped[identity], let info = meta[identity] else { continue }
            addable.append(Server(
                identity: identity, host: info.host, port: info.port, alias: info.alias,
                managedIndex: nil, managedShares: [], addableShares: shares.sorted { $0.name < $1.name },
                problemCount: shares.filter { foundProblems.contains($0.identity) }.count))
        }
        addable.sort { $0.host.localizedStandardCompare($1.host) == .orderedAscending }
        return Snapshot(managed: managed, addable: addable)
    }
}
