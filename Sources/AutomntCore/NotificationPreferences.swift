import Foundation

public struct NotificationPreferences: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var notificationSoundEnabled: Bool
    public init(notificationSoundEnabled: Bool = true) {
        schemaVersion = 1
        self.notificationSoundEnabled = notificationSoundEnabled
    }
    enum CodingKeys: String, CodingKey { case schemaVersion, notificationSoundEnabled }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        notificationSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationSoundEnabled) ?? true
    }
}

public struct NotificationPreferenceReading: Sendable {
    public let soundEnabled: Bool
    public let needsRepair: Bool
}

public struct NotificationPreferenceStore: Sendable {
    public let directory: URL
    public init(authorizedDirectory: URL) { directory = authorizedDirectory }
    private var url: URL { directory.appendingPathComponent("gui-notification-preferences.plist") }

    public func readForDelivery() -> NotificationPreferenceReading {
        do {
            let value = try PropertyListDecoder().decode(NotificationPreferences.self, from: PrivateAtomicFile.read(url))
            guard value.schemaVersion == 1 else { return NotificationPreferenceReading(soundEnabled: false, needsRepair: true) }
            return NotificationPreferenceReading(soundEnabled: value.notificationSoundEnabled, needsRepair: false)
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == 2 {
            return NotificationPreferenceReading(soundEnabled: true, needsRepair: false)
        } catch {
            return NotificationPreferenceReading(soundEnabled: false, needsRepair: true)
        }
    }

    /// Caller commits the visible toggle only after this succeeds.
    public func save(_ preferences: NotificationPreferences) throws {
        guard preferences.schemaVersion == 1 else { throw AutomntIssue.invalidConfiguration }
        let lock = try StableFileLock(url: directory.appendingPathComponent("config.lock"))
        try withExtendedLifetime(lock) {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            try PrivateAtomicFile.replace(encoder.encode(preferences), at: url)
        }
    }
}
