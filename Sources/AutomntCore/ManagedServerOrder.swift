import Foundation

/// Stable identity for a managed server. Port is part of the identity because
/// the same host name on a different port is a different SMB endpoint.
public func managedServerIdentity(_ host: HostConfig) -> String {
    let name = host.host
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        .lowercased()
    return "\(name):\(host.port)"
}

/// The ordered set of managed servers persisted in the single active configuration.
/// Undiscovered but still-managed servers stay in this array; discovered candidates
/// are observation-only and never enter it until their first share is added.
public enum ManagedServerOrder {
    public static func identities(of configuration: AutomntConfig) -> [String] {
        configuration.hosts.map(managedServerIdentity)
    }

    /// Returns the configuration with `identity` moved to `destination`, or nil when
    /// the identity is absent or the destination is unchanged/out of range.
    public static func moving(_ configuration: AutomntConfig, identity: String, to destination: Int) -> AutomntConfig? {
        var hosts = configuration.hosts
        guard let current = hosts.firstIndex(where: { managedServerIdentity($0) == identity }) else { return nil }
        guard hosts.indices.contains(destination), destination != current else { return nil }
        let moved = hosts.remove(at: current)
        hosts.insert(moved, at: destination)
        var updated = configuration
        updated.hosts = hosts
        return updated
    }

    /// Restores a previously captured identity order, ignoring identities that no
    /// longer exist and leaving unknown-to-the-capture hosts in place at the end.
    public static func restoring(_ configuration: AutomntConfig, order: [String]) -> AutomntConfig? {
        var remaining = configuration.hosts
        var rebuilt: [HostConfig] = []
        for identity in order {
            guard let index = remaining.firstIndex(where: { managedServerIdentity($0) == identity }) else { continue }
            rebuilt.append(remaining.remove(at: index))
        }
        let proposed = rebuilt + remaining
        guard proposed.map(managedServerIdentity) != configuration.hosts.map(managedServerIdentity) else { return nil }
        var updated = configuration
        updated.hosts = proposed
        return updated
    }
}

/// Captures the order before a change plus the revision the change produced, so an
/// undo can prove nothing else was saved in between.
public struct ServerOrderUndo: Sendable {
    public let previousOrder: [String]
    public let savedRevision: ConfigRevision
    public init(previousOrder: [String], savedRevision: ConfigRevision) {
        self.previousOrder = previousOrder
        self.savedRevision = savedRevision
    }
}

public struct ServerOrderOutcome: Sendable {
    public let snapshot: ConfigSnapshot?
    public let undo: ServerOrderUndo?
    public let issue: AutomntIssue?

    public var didSave: Bool { snapshot != nil }
    public var savedOrder: [String]? { snapshot.map { ManagedServerOrder.identities(of: $0.configuration) } }

    init(snapshot: ConfigSnapshot? = nil, undo: ServerOrderUndo? = nil, issue: AutomntIssue? = nil) {
        self.snapshot = snapshot
        self.undo = undo
        self.issue = issue
    }
}

/// Immediate, revision-checked persistence for server ordering and membership.
/// The GUI drag, keyboard move and CLI all drive the same rules; nothing here
/// keeps a local draft order.
public struct ManagedServerOrderController: Sendable {
    private let repository: ConfigRepository

    public init(repository: ConfigRepository) { self.repository = repository }

    /// Moves one managed server to `destination` and persists atomically. A
    /// revision mismatch is reported as a conflict and never overwrites the file.
    public func move(identity: String, to destination: Int, baseRevision: ConfigRevision) -> ServerOrderOutcome {
        let current: ConfigSnapshot
        do { current = try repository.read() }
        catch let issue as AutomntIssue { return ServerOrderOutcome(issue: issue) }
        catch { return ServerOrderOutcome(issue: .configurationConflict) }
        guard current.revision == baseRevision else { return ServerOrderOutcome(issue: .configurationConflict) }
        guard let updated = ManagedServerOrder.moving(current.configuration, identity: identity, to: destination) else {
            return ServerOrderOutcome(issue: nil)
        }
        return persist(updated, previousOrder: ManagedServerOrder.identities(of: current.configuration), baseRevision: baseRevision)
    }

    /// Applies the inverse of a captured move. The undo only succeeds when the
    /// configuration still sits at the revision the original move produced.
    public func undo(_ undo: ServerOrderUndo) -> ServerOrderOutcome {
        let current: ConfigSnapshot
        do { current = try repository.read() }
        catch let issue as AutomntIssue { return ServerOrderOutcome(issue: issue) }
        catch { return ServerOrderOutcome(issue: .configurationConflict) }
        guard current.revision == undo.savedRevision else { return ServerOrderOutcome(issue: .configurationConflict) }
        guard let updated = ManagedServerOrder.restoring(current.configuration, order: undo.previousOrder) else {
            return ServerOrderOutcome(issue: nil)
        }
        return persist(updated, previousOrder: ManagedServerOrder.identities(of: current.configuration), baseRevision: current.revision)
    }

    private func persist(_ configuration: AutomntConfig, previousOrder: [String], baseRevision: ConfigRevision) -> ServerOrderOutcome {
        do {
            let saved = try repository.save(configuration, baseRevision: baseRevision)
            return ServerOrderOutcome(snapshot: saved, undo: ServerOrderUndo(previousOrder: previousOrder, savedRevision: saved.revision))
        } catch let issue as AutomntIssue {
            return ServerOrderOutcome(issue: issue)
        } catch {
            return ServerOrderOutcome(issue: .signalUnavailable)
        }
    }
}
