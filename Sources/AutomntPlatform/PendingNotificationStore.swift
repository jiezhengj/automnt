import Foundation
import AutomntCore

/// A failure notice the background helper recorded while the GUI was not running.
///
/// Under App Sandbox the helper has no notification identity and may not spawn the app
/// process to borrow it (`forbidden-sandbox-reinit`), so it cannot call
/// `UNUserNotificationCenter` itself. The resident app owns the identity, and delivers a
/// recorded notice the next time its delivery loop runs.
///
/// This is derived, disposable state: it never rewrites business configuration, and it has
/// a short lifetime so a notice from days ago is not presented as current after a launch.
public struct PendingNotification: Codable, Equatable, Sendable {
    /// A failure notice is only useful promptly. A longer lifetime would surface stale
    /// failures at the next login and misrepresent the current state.
    public static let maximumAge: TimeInterval = 600
    public static let schemaVersion = 1

    public var schemaVersion = Self.schemaVersion
    public let count: Int
    public let soundEnabled: Bool
    public let soundPreferenceNeedsRepair: Bool
    public let createdAt: Date

    public init(count: Int, soundEnabled: Bool, soundPreferenceNeedsRepair: Bool,
                createdAt: Date = Date()) {
        self.count = max(count, 1)
        self.soundEnabled = soundEnabled
        self.soundPreferenceNeedsRepair = soundPreferenceNeedsRepair
        self.createdAt = createdAt
    }

    public func isExpired(now: Date = Date()) -> Bool {
        now.timeIntervalSince(createdAt) > Self.maximumAge
    }
}

/// The one-slot mailbox between the helper (records) and the app (delivers).
public struct PendingNotificationStore: Sendable {
    public let directory: URL
    public init(authorizedDirectory: URL) { directory = authorizedDirectory }
    private var url: URL { directory.appendingPathComponent("pending-notification.plist") }

    /// Returns nil for a missing, undecodable or version-mismatched record; a corrupt
    /// notice is discarded rather than guessed at.
    public func read() -> PendingNotification? {
        guard let data = try? PrivateAtomicFile.read(url),
              let notification = try? PropertyListDecoder().decode(PendingNotification.self, from: data),
              notification.schemaVersion == PendingNotification.schemaVersion else { return nil }
        return notification
    }

    /// Writes atomically and replaces an earlier notice: a notice states the current number
    /// of failed shared folders, so only the newest one is worth delivering.
    public func enqueue(_ notification: PendingNotification) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try PrivateAtomicFile.replace(encoder.encode(notification), at: url)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
