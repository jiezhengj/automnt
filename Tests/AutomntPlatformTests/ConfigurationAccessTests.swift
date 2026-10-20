import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

@Suite struct ConfigurationAccessTests {
    @Test func mutationGateRequiresConfirmedRead() {
        for state in [ConfigurationAccessState.awaitingAuthorization, .cancelled, .wrongDirectory,
                      .directoryMissing, .bookmarkStale, .permissionRevoked, .readFailed] {
            #expect(!state.allowsChanges)
        }
        #expect(ConfigurationAccessState.ready.allowsChanges)
        #expect(ConfigurationAccessState.authorizedUnconfigured.allowsChanges)
    }

    @Test func fixedAccessDeclarationRequiresExactDirectoryAndSandbox() {
        let key = PermissionStore.fixedDirectoryExceptionKey
        let path = PermissionStore.fixedDirectoryHomeRelativePath
        #expect(PermissionStore.grantsFixedDirectoryAccess(["com.apple.security.app-sandbox": true, key: [path]]))
        for declarations: [String: Any] in [
            [key: [path]],
            ["com.apple.security.app-sandbox": false, key: [path]],
            ["com.apple.security.app-sandbox": true],
            ["com.apple.security.app-sandbox": true, key: ["/Library/"]],
            ["com.apple.security.app-sandbox": true, key: [path, "/Documents/"]],
            ["com.apple.security.app-sandbox": true, key: path]
        ] {
            #expect(!PermissionStore.grantsFixedDirectoryAccess(declarations))
        }
    }

    @Test func noBookmarkRequiresAuthorizationWithoutCreatingStore() throws {
        let suite = "org.automnt.permission-test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PermissionStore(preferences: defaults)
        #expect(!store.hasSavedBookmark)
        #expect(throws: AutomntIssue.authorizationRequired) { try store.resolve() }
        #expect(throws: AutomntIssue.authorizationRequired) { try store.internalDirectory() }
        #expect(!store.hasSavedBookmark)
    }

    @Test func corruptBookmarkHasDistinctRepairState() throws {
        let suite = "org.automnt.permission-test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([0, 1, 2]), forKey: "authorizedAutomntDirectoryBookmark")
        let store = PermissionStore(preferences: defaults)
        #expect(throws: PermissionStore.AccessError.bookmarkStale) { try store.resolve() }
        #expect(store.hasSavedBookmark)
        store.forget()
        #expect(!store.hasSavedBookmark)
    }

    @Test func alternateParentCannotPrepareSettings() throws {
        let suite = "org.automnt.permission-test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PermissionStore(preferences: defaults)
        #expect(throws: PermissionStore.AccessError.wrongDirectory) {
            try store.prepareSettings(selectedParent: FileManager.default.temporaryDirectory)
        }
        #expect(!store.hasSavedBookmark)
    }

    @Test func alternateDirectoryIsRejectedBeforeBookmarkPersistence() throws {
        let suite = "org.automnt.permission-test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PermissionStore(preferences: defaults)
        #expect(throws: PermissionStore.AccessError.wrongDirectory) {
            try store.authorize(selectedDirectory: FileManager.default.temporaryDirectory)
        }
        #expect(!store.hasSavedBookmark)
    }
}
