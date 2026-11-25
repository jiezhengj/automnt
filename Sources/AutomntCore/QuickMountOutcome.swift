import Foundation

/// One configured shared folder, described in the terms a quick mount result needs.
///
/// The model resolves this from the same availability rules the rows use, so the
/// menu and the window cannot disagree about what happened.
public struct QuickMountTarget: Equatable, Sendable {
    public var identity: String
    public var name: String
    /// A disabled shared folder is not part of automatic mounting, so a quick mount
    /// must not report it as a failure.
    public var enabled: Bool
    public var availability: TargetAvailability
    public var issue: AutomntIssue?

    public init(identity: String, name: String, enabled: Bool,
                availability: TargetAvailability, issue: AutomntIssue?) {
        self.identity = identity
        self.name = name
        self.enabled = enabled
        self.availability = availability
        self.issue = issue
    }
}

/// A shared folder that a quick mount tried and could not mount.
public struct QuickMountFailure: Equatable, Sendable, Identifiable {
    /// User-facing cause. Never an internal issue code: the menu shows these.
    public enum Reason: String, Equatable, Sendable {
        /// The server wants credentials again, or rejected the stored ones.
        case credentials
        /// The mount point is taken by something else, or the volume is busy.
        case locationBusy
        /// The server refused this shared folder.
        case refused
        /// The attempt did not finish in time, or the background worker went quiet.
        case notFinished
        /// The shared folder was ejected for this session, so quick mounting leaves it
        /// alone by design. Reported so a click never looks like it did nothing.
        case ejected
        case other
    }

    public let identity: String
    public let name: String
    public let reason: Reason

    public var id: String { identity }

    public init(identity: String, name: String, reason: Reason) {
        self.identity = identity
        self.name = name
        self.reason = reason
    }
}

/// The result of a quick mount, as the user needs to read it.
///
/// Only outcomes this action can be held responsible for are reported. A shared
/// folder whose server was unreachable or whose attempt never started is left alone:
/// telling someone "3 shared folders failed" when two were never attempted raises an
/// alarm nobody can resolve. A folder the user ejected for this session is reported
/// with its own reason, because silence would make the click look ineffective.
public struct QuickMountOutcome: Equatable, Sendable {
    public let failures: [QuickMountFailure]

    public var count: Int { failures.count }
    public var isEmpty: Bool { failures.isEmpty }

    public init(failures: [QuickMountFailure]) {
        self.failures = failures
    }

    /// `nil` means there is nothing to report: every enabled shared folder is now
    /// usable, or none of them was this action's to mount.
    public static func make(from targets: [QuickMountTarget]) -> QuickMountOutcome? {
        let failures = targets.filter(\.enabled).compactMap(failure(for:))
        return failures.isEmpty ? nil : QuickMountOutcome(failures: failures)
    }

    static func failure(for target: QuickMountTarget) -> QuickMountFailure? {
        guard let reason = reason(for: target) else { return nil }
        return QuickMountFailure(identity: target.identity, name: target.name, reason: reason)
    }

    /// The availability model already answers "is it mounted now". This only decides
    /// whether the answer is worth reporting, and in which words.
    static func reason(for target: QuickMountTarget) -> QuickMountFailure.Reason? {
        switch target.availability {
        case .authenticationRequired:
            return .credentials
        case .locationOccupied:
            return .locationBusy
        case .failed:
            switch target.issue {
            case .credentialFailure:
                return .credentials
            case .shareRejected:
                return .refused
            case .pathConflict, .volumeBusy:
                return .locationBusy
            case .timeout, .signalUnavailable:
                return .notFinished
            default:
                return .other
            }
        case .suppressedForThisSession:
            return .ejected
        case .usable, .availableViaPeer, .notMounted, .locationMismatch,
             .notEvaluatedThisRound, .unreachable:
            return nil
        }
    }
}

/// Why a quick mount cannot run right now, ordered by what the user should fix first.
public enum QuickMountGate: Equatable, Sendable {
    case ready
    case noConfiguration
    case automaticMountingOff
    case backgroundNotReady
    case busy

    public static func evaluate(hasConfiguration: Bool, automaticMountingEnabled: Bool,
                                backend: SettingsSurface.BackendStatus, busy: Bool) -> Self {
        guard hasConfiguration else { return .noConfiguration }
        guard automaticMountingEnabled else { return .automaticMountingOff }
        guard backend == .running else { return .backgroundNotReady }
        // Transient: it becomes available again on its own, so it ranks after the
        // states that need the user to change a setting.
        guard !busy else { return .busy }
        return .ready
    }

    public var isReady: Bool { self == .ready }
}
