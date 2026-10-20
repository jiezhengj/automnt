import Foundation

/// System notification authorization as reported by the OS. Declared in Core so the
/// settings surface does not depend on a platform notification framework.
public enum NotificationAuthorizationState: String, Codable, Sendable {
    case notRequested, allowed, denied, unavailable
}

/// Settings presentation. The whole point is that the saved switch, the background
/// service that is actually running, and the system notification authorization are
/// three separate facts, each reported independently.
public enum SettingsSurface {
    public struct AutomaticMounting: Equatable, Sendable {
        public let intended: Bool
        public let backend: BackendStatus
        public let recoveryPreferred: Bool
        /// Recovery only adds the volume-change response; it never replaces login or
        /// network-change mounting, so the control is disabled while automation is off.
        public var recoveryEditable: Bool { intended && backend != .unavailable }
        public var recoveryEffective: Bool { recoveryPreferred && intended }

        public init(intended: Bool, backend: BackendStatus, recoveryPreferred: Bool) {
            self.intended = intended
            self.backend = backend
            self.recoveryPreferred = recoveryPreferred
        }
    }

    public enum BackendStatus: String, Equatable, Sendable {
        case running
        case awaitingApproval
        case stopped
        case transitioning
        case unavailable
        case governedByCLI

        /// Only a confirmed running service may be presented as active.
        public var isConfirmedRunning: Bool { self == .running }

        /// The interface must offer a concrete repair entry for these.
        public var needsUserAction: Bool {
            switch self {
            case .awaitingApproval, .unavailable, .governedByCLI: return true
            case .running, .stopped, .transitioning: return false
            }
        }
    }

    public struct Notifications: Equatable, Sendable {
        public let authorization: NotificationAuthorizationState
        public let soundEnabled: Bool
        public let soundNeedsRepair: Bool

        public init(authorization: NotificationAuthorizationState, soundEnabled: Bool, soundNeedsRepair: Bool) {
            self.authorization = authorization
            self.soundEnabled = soundEnabled
            self.soundNeedsRepair = soundNeedsRepair
        }

        /// Sound is an independent preference; it never gates whether notices arrive.
        public var canDeliver: Bool { authorization == .allowed }
        public var offersSettingsShortcut: Bool { authorization == .allowed || authorization == .denied }
        public var shouldOfferPermissionRequest: Bool { authorization == .notRequested }
    }

    public struct MenuBarAndLogin: Equatable, Sendable {
        public let menuBarPreferred: Bool
        public let loginPreferred: Bool
        public let loginRegistration: LoginRegistration

        public init(menuBarPreferred: Bool, loginPreferred: Bool, loginRegistration: LoginRegistration) {
            self.menuBarPreferred = menuBarPreferred
            self.loginPreferred = loginPreferred
            self.loginRegistration = loginRegistration
        }

        /// Declaring "show at login" is meaningless when the menu bar item is hidden.
        public var loginEditable: Bool { menuBarPreferred }
    }

    public enum LoginRegistration: String, Equatable, Sendable {
        case registered, requiresApproval, notRegistered, notFound

        public var isConfirmedRegistered: Bool { self == .registered }
        public var needsUserAction: Bool { self == .requiresApproval }
    }

    public struct Advanced: Equatable, Sendable {
        public let attempts: Int
        public let intervalMs: Int
        public let windowMs: Int
        public var problems: [RetryPolicyBounds.Problem] {
            RetryPolicyBounds.problems(attempts: attempts, intervalMs: intervalMs, windowMs: windowMs)
        }
    }

    /// Reports saved-intent versus actual-service disagreement instead of hiding it.
    public static func backendStatus(state: BackendState?, intended: Bool) -> BackendStatus {
        guard intended else { return .stopped }
        guard let state else { return .unavailable }
        switch state.phase {
        case .awaitingApproval: return .awaitingApproval
        case .stopping, .activating: return .transitioning
        case .failed: return .unavailable
        case .stopped: return .stopped
        case .active:
            // Another owner may be the one actually running the service.
            return state.owner == .cli ? .governedByCLI : (state.owner == .app ? .running : .unavailable)
        }
    }

    /// The settings summary as a semantic value. Core deliberately returns no
    /// user-visible text: the GUI owns all copy so every string is checked by the
    /// nine-language catalog gate, which scans the app module only.
    public enum AutomaticMountingSummary: String, Equatable, Sendable {
        case offWhileMountedStayAvailable
        case runningWithRecovery
        case runningWithoutRecovery
        case awaitingApproval
        case transitioning
        case savedButNotRunning
        case couldNotBeConfirmed
        case governedByCLI
    }

    /// Turns the three facts into the summary the settings pane must show.
    public static func automaticMountingSummary(_ value: AutomaticMounting) -> AutomaticMountingSummary {
        if !value.intended { return .offWhileMountedStayAvailable }
        switch value.backend {
        case .running: return value.recoveryEffective ? .runningWithRecovery : .runningWithoutRecovery
        case .awaitingApproval: return .awaitingApproval
        case .transitioning: return .transitioning
        case .stopped: return .savedButNotRunning
        case .unavailable: return .couldNotBeConfirmed
        case .governedByCLI: return .governedByCLI
        }
    }
}
