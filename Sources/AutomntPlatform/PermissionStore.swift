import Foundation
import Darwin
import AutomntCore
import Security

public final class AuthorizedDirectory: @unchecked Sendable {
    public let url: URL
    /// Describes the active grant, without exposing bookmark bytes or paths.
    public let scoped: Bool
    fileprivate init(url: URL, scoped: Bool) { self.url = url; self.scoped = scoped }
    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}

/// Each signed entry stores its own authorization in its own private preferences.
/// Bookmark bytes are never copied into shared business configuration or diagnostics.
public struct PermissionStore {
    private let preferences: UserDefaults
    private let key = "authorizedAutomntDirectoryBookmark"
    public static var expectedDirectory: URL {
        // Sandbox HOME can name a container. Resolve the account's real home instead.
        guard let record = getpwuid(getuid()), let path = record.pointee.pw_dir else { return URL(fileURLWithPath: "/") }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
            .appendingPathComponent("Library/Application Support/automnt", isDirectory: true)
    }

    public static let fixedDirectoryExceptionKey = "com.apple.security.temporary-exception.files.home-relative-path.read-write"
    public static let fixedDirectoryHomeRelativePath = "/Library/Application Support/automnt/"

    static func grantsFixedDirectoryAccess(_ entitlements: [String: Any]) -> Bool {
        entitlements["com.apple.security.app-sandbox"] as? Bool == true &&
        entitlements[fixedDirectoryExceptionKey] as? [String] == [fixedDirectoryHomeRelativePath]
    }

    /// `AutomntWorker` is signed with `com.apple.security.inherit`: its effective sandbox
    /// (fixed-directory exception and network access included) comes from the verified
    /// helper that spawned it, so its own static entitlements never list the exception.
    /// Accepting inheritance only hands the decision to real filesystem validation below.
    static func inheritsSandbox(_ entitlements: [String: Any]) -> Bool {
        entitlements["com.apple.security.app-sandbox"] as? Bool == true &&
        entitlements["com.apple.security.inherit"] as? Bool == true
    }

    private static var ownEntitlements: [String: Any]? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else { return nil }
        return entitlements
    }

    /// A declared entitlement is a candidate capability. Actual filesystem operations
    /// must still succeed; this check does not grant access or prove MAS acceptance.
    public static var hasFixedDirectoryEntitlement: Bool {
        ownEntitlements.map(grantsFixedDirectoryAccess) ?? false
    }

    public static var hasInheritedSandboxEntitlement: Bool {
        ownEntitlements.map(inheritsSandbox) ?? false
    }

    /// App Sandbox blocks reading a network volume the process itself mounted: the kernel
    /// mount exists and is authenticated, but directory contents are outside the sandbox.
    /// Callers must therefore distinguish sandbox denial from server-side failure.
    public static var hasAppSandboxEntitlement: Bool {
        ownEntitlements.map { $0["com.apple.security.app-sandbox"] as? Bool == true } ?? false
    }

    /// Foreground only: prepare the program-owned canonical directory, without a
    /// picker, a business configuration, service registration or mount request.
    public func prepareFixedSettings() throws -> AuthorizedDirectory {
        guard Self.hasFixedDirectoryEntitlement else { throw AutomntIssue.authorizationRequired }
        let target = Self.expectedDirectory.standardizedFileURL
        guard target.resolvingSymlinksInPath().standardizedFileURL == target else { throw AccessError.wrongDirectory }
        var info = stat()
        if lstat(target.path, &info) != 0 {
            guard errno == ENOENT else { throw AccessError.permissionRevoked }
            do {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700])
            } catch {
                // A concurrent creator is accepted only after the same identity checks.
                guard lstat(target.path, &info) == 0 else { throw error }
            }
        }
        try validateDirectory(target)
        guard chmod(target.path, 0o700) == 0 else { throw AccessError.permissionRevoked }
        return AuthorizedDirectory(url: target, scoped: false)
    }

    public enum AccessError: Error, Sendable, Equatable {
        case wrongDirectory, directoryMissing, bookmarkStale, permissionRevoked
    }

    public func validateDirectory(_ url: URL) throws {
        let expected = Self.expectedDirectory.standardizedFileURL
        guard url.standardizedFileURL == expected,
              url.resolvingSymlinksInPath().standardizedFileURL == expected else {
            throw AccessError.wrongDirectory
        }
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw errno == ENOENT ? AccessError.directoryMissing : AccessError.permissionRevoked
        }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(),
              access(url.path, R_OK | W_OK | X_OK) == 0 else { throw AccessError.permissionRevoked }
    }
    public init(preferences: UserDefaults = .standard) { self.preferences = preferences }

    public func authorize(selectedDirectory: URL) throws -> AuthorizedDirectory {
        let scoped = selectedDirectory.startAccessingSecurityScopedResource()
        do {
            try validateDirectory(selectedDirectory)
            let bookmark = try selectedDirectory.bookmarkData(options: .withSecurityScope,
                                                              includingResourceValuesForKeys: nil, relativeTo: nil)
            preferences.set(bookmark, forKey: key)
            return AuthorizedDirectory(url: selectedDirectory, scoped: scoped)
        } catch {
            if scoped { selectedDirectory.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    /// The system panel may authorize the fixed parent when first-run settings
    /// do not exist yet. Use that scope only to prepare our own directory, then
    /// persist a narrower bookmark. Never create or copy business configuration.
    public func prepareSettings(selectedParent: URL) throws -> AuthorizedDirectory {
        let parent = Self.expectedDirectory.deletingLastPathComponent().standardizedFileURL
        guard selectedParent.standardizedFileURL == parent,
              selectedParent.resolvingSymlinksInPath().standardizedFileURL == parent else {
            throw AccessError.wrongDirectory
        }
        let scoped = selectedParent.startAccessingSecurityScopedResource()
        defer { if scoped { selectedParent.stopAccessingSecurityScopedResource() } }
        var info = stat()
        guard lstat(parent.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(),
              access(parent.path, R_OK | W_OK | X_OK) == 0 else {
            throw AccessError.permissionRevoked
        }
        let target = Self.expectedDirectory
        if lstat(target.path, &info) != 0 {
            guard errno == ENOENT else { throw AccessError.permissionRevoked }
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
        }
        let directory = try authorize(selectedDirectory: target)
        return try withExtendedLifetime(directory) { try resolve() }
    }

    /// A temporary user-selected grant to inspect the canonical legacy location.
    /// No bookmark or configuration is written and no directory is created.
    public func authorizeLegacyInspection(selectedDirectory: URL) throws -> AuthorizedDirectory {
        let scoped = selectedDirectory.startAccessingSecurityScopedResource()
        do {
            let expected = Self.expectedDirectory.deletingLastPathComponent()
            guard selectedDirectory.standardizedFileURL == expected.standardizedFileURL,
                  selectedDirectory.resolvingSymlinksInPath().standardizedFileURL == expected.standardizedFileURL,
                  try selectedDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw AutomntIssue.authorizationRequired
            }
            return AuthorizedDirectory(url: selectedDirectory, scoped: scoped)
        } catch {
            if scoped { selectedDirectory.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    /// Compatibility for diagnostic callers; never creates a container configuration.
    public func internalDirectory() throws -> AuthorizedDirectory { try resolve() }

    /// Background resolution cannot display UI or mount a network volume.
    /// A stale bookmark is renewed only while its grant still resolves to the fixed directory.
    public func resolve() throws -> AuthorizedDirectory {
        // The verified helper and its inherit-signed worker both resolve the fixed directory;
        // real filesystem validation below is the capability proof in either case.
        if Self.hasFixedDirectoryEntitlement || Self.hasInheritedSandboxEntitlement {
            let target = Self.expectedDirectory
            try validateDirectory(target)
            return AuthorizedDirectory(url: target, scoped: false)
        }
        guard let data = preferences.data(forKey: key) else { throw AutomntIssue.authorizationRequired }
        var stale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: data,
                          options: [.withSecurityScope, .withoutUI, .withoutMounting],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch { throw AccessError.bookmarkStale }
        guard url.startAccessingSecurityScopedResource() else { throw AccessError.permissionRevoked }
        do {
            try validateDirectory(url)
            if stale {
                do {
                    let renewed = try url.bookmarkData(options: .withSecurityScope,
                        includingResourceValuesForKeys: nil, relativeTo: nil)
                    preferences.set(renewed, forKey: key)
                } catch { throw AccessError.bookmarkStale }
            }
            return AuthorizedDirectory(url: url, scoped: true)
        } catch {
            url.stopAccessingSecurityScopedResource()
            throw error
        }
    }

    public var hasSavedBookmark: Bool { preferences.data(forKey: key) != nil }

    public func forget() { preferences.removeObject(forKey: key) }
}
