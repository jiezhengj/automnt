import Foundation

/// One share's presentation facts, ordered the way the detail view must read them:
/// status and next step, then expected versus actual location, then the automatic
/// plan, then the actions. Nothing here performs an action.
public struct ShareDetail: Equatable, Sendable {
    public let identity: String
    public let name: String
    public let smbURL: String
    public let expectedMountPoint: String
    public let actualMountPoint: String?
    public let observedAt: Date?
    public let status: Status
    public let automaticPlan: AutomaticPlan
    public let issue: AutomntIssue?

    public init(identity: String, name: String, smbURL: String, expectedMountPoint: String,
                actualMountPoint: String?, observedAt: Date?, status: Status,
                automaticPlan: AutomaticPlan, issue: AutomntIssue?) {
        self.identity = identity
        self.name = name
        self.smbURL = smbURL
        self.expectedMountPoint = expectedMountPoint
        self.actualMountPoint = actualMountPoint
        self.observedAt = observedAt
        self.status = status
        self.automaticPlan = automaticPlan
        self.issue = issue
    }

    /// Distinguishes a session-scoped user ejection from a damaged/dead mount and
    /// from "this round simply did not pick this server".
    public enum Status: String, Equatable, Sendable {
        case healthy
        case mounting
        case ejectedForThisSession
        case notSelectedThisRound
        case automatedMountingOff
        case serverUnreachable
        case authenticationRequired
        /// The same SMB identity is mounted, but somewhere other than the configured
        /// path. It is usable; tasks that rely on the configured path may not find it.
        case locationMismatch
        /// Another volume (or another share) occupies the configured path. This is a
        /// conflict to inspect, not a failed mount of this share.
        case locationOccupied
        case recovering
        case recoveryFailed
        case unconfirmed
        case notMounted
    }

    public enum AutomaticPlan: String, Equatable, Sendable {
        case scheduled
        case pausedThisSession
        case disabledForShare
        case disabledForServer
        case disabledGlobally
        case waitsForBackgroundApproval
        case waitsForSystemEvent
    }

    /// The user-facing next step. `nil` means the healthy primary action applies.
    public var nextStep: NextStep {
        switch status {
        case .healthy: return .openInFinder
        case .mounting, .recovering: return .wait
        case .ejectedForThisSession: return .mountThisShare
        case .notSelectedThisRound: return .explainRoundSelection
        case .automatedMountingOff, .notMounted: return .mountThisShare
        case .serverUnreachable: return .checkNetwork
        case .authenticationRequired: return .connectInFinder
        case .locationMismatch: return .reviewLocations
        case .locationOccupied: return .reviewOccupiedLocation
        case .recoveryFailed, .unconfirmed: return .retryThisShare
        }
    }

    public enum NextStep: String, Equatable, Sendable {
        case openInFinder, wait, mountThisShare, explainRoundSelection
        case checkNetwork, connectInFinder, reviewLocations, reviewOccupiedLocation
        case retryThisShare
    }

    /// A healthy share whose actual location differs from the configured one is not
    /// healthy for tasks using the configured path.
    public var isUsableAtExpectedPath: Bool {
        status == .healthy && actualMountPoint == expectedMountPoint
    }

    public var showsExpectedAndActualLocations: Bool {
        status == .locationMismatch || (actualMountPoint != nil && actualMountPoint != expectedMountPoint)
    }

    /// True when the mounted copy is usable and only its path differs; the user may
    /// adopt that path or open it, but nothing failed.
    public var offersActualLocationActions: Bool {
        status == .locationMismatch
    }
}

public enum ShareDetailBuilder {
    /// Builds the detail fact sheet from observations. Absence of a mount proves only
    /// that this share is not mounted here; it never proves the server is offline.
    public static func build(share: SMBShareConfig,
                             expectedMountPoint: String,
                             mounted: Bool,
                             actualMountPoint: String?,
                             observedAt: Date?,
                             serverReachable: Bool?,
                             selectedThisRound: Bool,
                             automationEnabled: Bool,
                             serverEnabled: Bool,
                             shareEnabled: Bool,
                             suppressed: Bool,
                             recovering: Bool,
                             locationOccupied: Bool,
                             recoveryFailed: Bool,
                             issue: AutomntIssue?) -> ShareDetail {
        let identity = smbResourceIdentity(share.smbURL) ?? share.smbURL
        let status: ShareDetail.Status
        let mountedElsewhere = actualMountPoint != nil && actualMountPoint != expectedMountPoint
        if recovering { status = .recovering }
        else if suppressed && !mounted { status = .ejectedForThisSession }
        else if !automationEnabled { status = mounted ? .automatedMountingOff : .notMounted }
        else if serverReachable == false && !mounted { status = .serverUnreachable }
        else if issue == .authorizationRequired || issue == .credentialFailure { status = .authenticationRequired }
        else if mountedElsewhere { status = .locationMismatch }
        else if locationOccupied { status = .locationOccupied }
        else if mounted { status = .healthy }
        else if recoveryFailed { status = .recoveryFailed }
        else if !selectedThisRound { status = .notSelectedThisRound }
        else { status = .notMounted }

        var plan: ShareDetail.AutomaticPlan
        if suppressed { plan = .pausedThisSession }
        else if !automationEnabled { plan = .disabledGlobally }
        else if !serverEnabled { plan = .disabledForServer }
        else if !shareEnabled { plan = .disabledForShare }
        else if serverReachable == false { plan = .waitsForSystemEvent }
        else { plan = .scheduled }

        return ShareDetail(identity: identity, name: share.name, smbURL: share.smbURL,
            expectedMountPoint: expectedMountPoint, actualMountPoint: actualMountPoint,
            observedAt: observedAt, status: status, automaticPlan: plan, issue: issue)
    }
}

/// Removal and ordinary ejection are different operations with different consequences.
public enum DetailAction: String, Equatable, Sendable {
    case openInFinder
    case mount
    case eject
    case editTarget
    case removeFromManagement
    case viewDiagnostics
    /// Opens the path where this share is actually mounted (location mismatch only).
    case openActualLocation
    /// Adopts the actual mounted path as the configured location (CAS-checked save).
    case useActualLocation
    /// Reveals the path that another volume occupies (location conflict inspection).
    case openOccupyingLocation
}

public enum DetailActionPolicy {
    /// Ordinary ejection is a direct, non-forced action. It is offered only for a
    /// verified mounted target and is never escalated to a force eject.
    ///
    /// While an operation is in flight for this target, every action that would change
    /// the configuration revision (mount, eject, removal) is withheld so it cannot race
    /// that operation; reading the detail and opening diagnostics remain available.
    public static func available(_ detail: ShareDetail, busy: Bool) -> Set<DetailAction> {
        var actions: Set<DetailAction> = [.editTarget, .viewDiagnostics]
        if busy { return actions }
        switch detail.status {
        case .healthy, .automatedMountingOff:
            actions.insert(.eject)
            if detail.actualMountPoint != nil { actions.insert(.openInFinder) }
        case .locationMismatch:
            // Mounted somewhere else: usable, never a mount failure. Offer opening and
            // adopting the actual path; ordinary ejection stays available.
            actions.insert(.eject)
            if detail.actualMountPoint != nil {
                actions.insert(.openInFinder)
                actions.insert(.openActualLocation)
                actions.insert(.useActualLocation)
            }
        case .locationOccupied:
            // Another volume owns the configured path. Ejecting it from here would
            // target the wrong object, so only inspection and an explicit edit remain.
            actions.insert(.openOccupyingLocation)
        case .ejectedForThisSession, .notMounted, .notSelectedThisRound,
             .serverUnreachable, .recoveryFailed, .unconfirmed:
            actions.insert(.mount)
        case .mounting, .recovering:
            break
        case .authenticationRequired:
            break
        }
        // Removal only changes management, and never ejects.
        actions.insert(.removeFromManagement)
        return actions
    }

    /// Removal never ejects, and the wording must name what is and is not affected.
    /// Returned as a semantic value because Core holds no user-visible copy; the GUI
    /// maps it to localized text so it passes the nine-language catalog gate.
    public enum RemovalConsequence: String, Equatable, Sendable {
        case removedManagementOnlyMountedStays
        case removedManagementOnly
    }

    public static func removalConsequence(shareMounted: Bool) -> RemovalConsequence {
        shareMounted ? .removedManagementOnlyMountedStays : .removedManagementOnly
    }
}
