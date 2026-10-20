import Foundation

/// Add/remove of managed membership. Both operations keep the server identity and
/// order stable, never touch system credentials, and never eject a mounted volume.
public enum ManagedMembership {
    public struct Candidate: Equatable, Sendable {
        public let host: String
        public let port: Int
        public let alias: String?
        public let timeoutMs: Int
        public let name: String
        public let smbURL: String
        public let mountPoint: String

        public init(host: String, port: Int = 445, alias: String? = nil, timeoutMs: Int = 1000,
                    name: String, smbURL: String, mountPoint: String) {
            self.host = host
            self.port = port
            self.alias = alias
            self.timeoutMs = timeoutMs
            self.name = name
            self.smbURL = smbURL
            self.mountPoint = mountPoint
        }
    }

    public enum Problem: Equatable, Sendable {
        case invalidTarget
        case duplicateShare
        case duplicateMountPath
        case unknownTarget
    }

    public struct Outcome: Sendable {
        public let configuration: AutomntConfig?
        public let problem: Problem?
        /// True when this add created the server and appended it to the managed order.
        public let appendedServer: Bool

        init(configuration: AutomntConfig? = nil, problem: Problem? = nil, appendedServer: Bool = false) {
            self.configuration = configuration
            self.problem = problem
            self.appendedServer = appendedServer
        }
    }

    /// Adds one share. A matching existing server keeps its identity, parameters and
    /// order; a new server is appended to the end of the managed order.
    public static func adding(_ candidate: Candidate, to configuration: AutomntConfig) -> Outcome {
        let identity = "\(normalizedHost(candidate.host)):\(candidate.port)"
        if var hostIndex = configuration.hosts.firstIndex(where: { managedServerIdentity($0) == identity }) {
            var updated = configuration
            if duplicateShare(candidate, in: updated.hosts[hostIndex].shares) {
                return Outcome(problem: .duplicateShare)
            }
            // Path uniqueness is per server: another server may legitimately reuse
            // the configured path as a fallback target, and runtime still checks occupancy.
            if updated.hosts[hostIndex].shares.contains(where: { sameMountPath($0.mountPoint, candidate.mountPoint) }) {
                return Outcome(problem: .duplicateMountPath)
            }
            updated.hosts[hostIndex].shares.append(share(from: candidate))
            return Outcome(configuration: updated)
        }
        var updated = configuration
        updated.hosts.append(HostConfig(
            host: candidate.host, alias: candidate.alias, port: candidate.port,
            timeoutMs: candidate.timeoutMs, shares: [share(from: candidate)]))
        return Outcome(configuration: updated, appendedServer: true)
    }

    /// Removes one share. Removing the last share removes the server in the same
    /// change; the configured mount and any live mount are left untouched.
    public static func removing(smbURL: String, from configuration: AutomntConfig) -> Outcome {
        guard let identity = smbResourceIdentity(smbURL) else { return Outcome(problem: .invalidTarget) }
        guard let hostIndex = configuration.hosts.firstIndex(where: { host in
            host.shares.contains { smbResourceIdentity($0.smbURL) == identity }
        }) else { return Outcome(problem: .unknownTarget) }
        var updated = configuration
        updated.hosts[hostIndex].shares.removeAll { smbResourceIdentity($0.smbURL) == identity }
        if updated.hosts[hostIndex].shares.isEmpty { updated.hosts.remove(at: hostIndex) }
        return Outcome(configuration: updated)
    }

    /// Removing by server identity drops the server and its shares together.
    public static func removingServer(identity: String, from configuration: AutomntConfig) -> Outcome {
        guard configuration.hosts.contains(where: { managedServerIdentity($0) == identity }) else {
            return Outcome(problem: .unknownTarget)
        }
        var updated = configuration
        updated.hosts.removeAll { managedServerIdentity($0) == identity }
        return Outcome(configuration: updated)
    }

    private static func normalizedHost(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()
    }

    private static func sameMountPath(_ lhs: String, _ rhs: String) -> Bool {
        URL(fileURLWithPath: lhs).standardizedFileURL.path == URL(fileURLWithPath: rhs).standardizedFileURL.path
    }

    private static func duplicateShare(_ candidate: Candidate, in shares: [SMBShareConfig]) -> Bool {
        guard let identity = smbResourceIdentity(candidate.smbURL) else { return true }
        return shares.contains { smbResourceIdentity($0.smbURL) == identity }
    }

    private static func share(from candidate: Candidate) -> SMBShareConfig {
        SMBShareConfig(name: candidate.name, smbURL: candidate.smbURL, mountPoint: candidate.mountPoint)
    }
}

/// Persists membership changes with the same CAS rule as ordering.
public struct ManagedMembershipController: Sendable {
    private let repository: ConfigRepository

    public init(repository: ConfigRepository) { self.repository = repository }

    public func add(_ candidate: ManagedMembership.Candidate, baseRevision: ConfigRevision) -> ServerOrderOutcome {
        mutate(baseRevision: baseRevision) { ManagedMembership.adding(candidate, to: $0).configuration }
    }

    public func remove(smbURL: String, baseRevision: ConfigRevision) -> ServerOrderOutcome {
        mutate(baseRevision: baseRevision) { ManagedMembership.removing(smbURL: smbURL, from: $0).configuration }
    }

    public func removeServer(identity: String, baseRevision: ConfigRevision) -> ServerOrderOutcome {
        mutate(baseRevision: baseRevision) { ManagedMembership.removingServer(identity: identity, from: $0).configuration }
    }

    private func mutate(baseRevision: ConfigRevision, _ change: (AutomntConfig) -> AutomntConfig?) -> ServerOrderOutcome {
        let current: ConfigSnapshot
        do { current = try repository.read() }
        catch let issue as AutomntIssue { return ServerOrderOutcome(issue: issue) }
        catch { return ServerOrderOutcome(issue: .configurationConflict) }
        guard current.revision == baseRevision else { return ServerOrderOutcome(issue: .configurationConflict) }
        guard let updated = change(current.configuration) else { return ServerOrderOutcome(issue: nil) }
        do {
            return ServerOrderOutcome(snapshot: try repository.save(updated, baseRevision: baseRevision))
        } catch let issue as AutomntIssue {
            return ServerOrderOutcome(issue: issue)
        } catch {
            return ServerOrderOutcome(issue: .signalUnavailable)
        }
    }
}
