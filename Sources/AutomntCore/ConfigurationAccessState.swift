import Foundation

/// Only a successful read (including confirmed absence) permits configuration changes.
public enum ConfigurationAccessState: String, Sendable, Equatable {
    case awaitingAuthorization, cancelled, wrongDirectory, directoryMissing
    case bookmarkStale, permissionRevoked, readFailed, ready, authorizedUnconfigured

    public var allowsChanges: Bool { self == .ready || self == .authorizedUnconfigured }
}
