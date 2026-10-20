import UserNotifications
import AutomntCore

public enum NotificationPermission: String, Sendable {
    case notRequested, allowed, denied, unavailable
}

public enum NotificationAuthorization {
    public static func current() async -> NotificationPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notRequested
        case .authorized, .provisional: return .allowed
        case .denied: return .denied
        default: return .unavailable
        }
    }

    /// Call only from an explicit GUI action, never a background evaluation.
    public static func request() async throws -> NotificationPermission {
        let permission = await current()
        guard permission == .notRequested else { return permission }
        _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        return await current()
    }
}

public extension NotificationPermission {
    /// Core-level state for the settings surface, so the GUI does not invent its own mapping.
    var authorizationState: NotificationAuthorizationState {
        switch self {
        case .notRequested: return .notRequested
        case .allowed: return .allowed
        case .denied: return .denied
        case .unavailable: return .unavailable
        }
    }
}
