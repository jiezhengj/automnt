import Foundation

/// What a refresh-shaped action is allowed to do. Keeping the scope explicit stops a
/// status read from being reported as a successful mount, and stops one failing share
/// from being merged into an unrelated target's message.
public enum OperationScope: String, Codable, Sendable {
    case statusRefresh
    case fullEvaluation
    case singleShareMount
    case normalEject
    case membershipChange
}

/// The three server notions the interface must never collapse into one: the row the
/// user is looking at, the server this evaluation round actually selected, and the
/// shares that are already mounted regardless of either.
public struct EvaluationSelection: Codable, Equatable, Sendable {
    public let roundSelectedServer: String?
    public let checkedServers: [String]
    public let skippedServers: [String]
    public let observedAt: Date

    public init(roundSelectedServer: String?, checkedServers: [String],
                skippedServers: [String], observedAt: Date) {
        self.roundSelectedServer = roundSelectedServer
        self.checkedServers = checkedServers
        self.skippedServers = skippedServers
        self.observedAt = observedAt
    }

    /// A server this round never reached is not offline; it was simply not selected.
    public func status(forServer identity: String) -> RoundServerStatus {
        if roundSelectedServer == identity { return .selected }
        if checkedServers.contains(identity) { return .checked }
        return .notSelected
    }

    public enum RoundServerStatus: String, Codable, Sendable {
        case selected, checked, notSelected
    }
}

/// Presentation state for one user-requested operation, carrying the stable target
/// identity so results attach to the object the user acted on.
public struct OperationPresentation: Identifiable, Sendable {
    public let id: UUID
    public let scope: OperationScope
    public let targetIdentity: String?
    public let startedAt: Date

    public init(id: UUID = UUID(), scope: OperationScope, targetIdentity: String?, startedAt: Date = Date()) {
        self.id = id
        self.scope = scope
        self.targetIdentity = targetIdentity
        self.startedAt = startedAt
    }
}

/// Distinguishes a saved configuration change from the background actually running
/// and from the share being usable right now. These are three separate answers.
public enum SettingOutcome: String, Codable, Sendable {
    case savedButNotEnabled
    case savedAndEnabled
    case savedButApprovalPending
    case saveFailed
}

public enum TargetAvailability: String, Codable, Sendable {
    case usable
    case notMounted
    case locationMismatch
    case suppressedForThisSession
    case notEvaluatedThisRound
    case unreachable
    case authenticationRequired
    case failed
}

public struct AvailabilityReport: Sendable {
    public let configurationSaved: Bool
    public let setting: SettingOutcome
    public let availability: TargetAvailability
    public let observedAt: Date?

    public init(configurationSaved: Bool, setting: SettingOutcome,
                availability: TargetAvailability, observedAt: Date?) {
        self.configurationSaved = configurationSaved
        self.setting = setting
        self.availability = availability
        self.observedAt = observedAt
    }
}

/// Collapses repeated requests for the same object so a double click does not stack
/// duplicate work, and merges failures only within the same scope and target.
public struct OperationLedger: Sendable {
    private var active: [String: OperationPresentation] = [:]

    public init() {}

    private func key(_ scope: OperationScope, _ targetIdentity: String?) -> String {
        "\(scope.rawValue)|\(targetIdentity ?? "*")"
    }

    /// Returns the existing in-flight operation when the same object is already being
    /// handled; otherwise records and returns the new one.
    public mutating func begin(_ scope: OperationScope, targetIdentity: String?) -> (operation: OperationPresentation, isDuplicate: Bool) {
        let key = key(scope, targetIdentity)
        if let existing = active[key] { return (existing, true) }
        let created = OperationPresentation(scope: scope, targetIdentity: targetIdentity)
        active[key] = created
        return (created, false)
    }

    public mutating func finish(_ operation: OperationPresentation) {
        let key = key(operation.scope, operation.targetIdentity)
        if active[key]?.id == operation.id { active.removeValue(forKey: key) }
    }

    public func isActive(_ scope: OperationScope, targetIdentity: String?) -> Bool {
        active[key(scope, targetIdentity)] != nil
    }

    public var activeCount: Int { active.count }

    /// Merges messages by scope and target: two different shares never share one line.
    public static func merge(_ failures: [(scope: OperationScope, target: String?, message: String)]) -> [String] {
        var order: [String] = []
        var grouped: [String: String] = [:]
        for failure in failures {
            let key = "\(failure.scope.rawValue)|\(failure.target ?? "*")"
            if grouped[key] == nil { order.append(key); grouped[key] = failure.message }
        }
        return order.compactMap { grouped[$0] }
    }
}
