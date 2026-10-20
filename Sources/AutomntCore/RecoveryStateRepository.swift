import Foundation

public struct RecoveryStateRepository: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func read() -> MountRecoveryStoreLoad {
        let data: Data
        do { data = try PrivateAtomicFile.read(url) }
        catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == 2 { return .absent }
        catch { return .corrupt(reason: "state file unreadable") }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any], let version = dict["schema_version"] as? Int,
              version == mountRecoverySchemaVersion else {
            return .corrupt(reason: "unsupported state schema")
        }
        var compatible = dict
        if compatible["attempts"] == nil { compatible["attempts"] = [String: Any]() }
        guard let bytes = try? PropertyListSerialization.data(fromPropertyList: compatible, format: .binary, options: 0),
              var value = try? PropertyListDecoder().decode(MountRecoveryStateFile.self, from: bytes) else {
            return .corrupt(reason: "state schema decode failed")
        }
        for (key, var record) in value.volumes {
            guard record.volumeKey == key, record.attemptCount >= 0, record.notificationCount >= 0 else {
                return .corrupt(reason: "inconsistent state record")
            }
            if record.state == .suppressed && record.suppressionBoundary == nil { record.suppressionBoundary = "" }
            value.volumes[key] = record
        }
        return .loaded(value)
    }

    /// The evaluator must retain its operation permit through this commit.
    public func save(_ value: MountRecoveryStateFile) throws {
        guard value.schemaVersion == mountRecoverySchemaVersion else { throw AutomntIssue.invalidConfiguration }
        try PrivateAtomicFile.replace(PropertyListEncoder().encode(value), at: url)
    }
}
