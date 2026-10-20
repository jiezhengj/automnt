import Foundation
import ServiceManagement
import AutomntCore

/// Group storage carries a short-lived implicit bookmark request, never business
/// configuration or the GUI's private explicit bookmark. A second launchd process
/// verifies the receiver's own bookmark after the transfer process has terminated.
public enum HelperPermissionProbe {
    private static let requestName = "automnt-permission-request.plist"
    private static let serviceName = "automnt.authorization.plist"
    enum Phase: String, Codable { case bind, verify }
    struct Request: Codable {
        let schema: Int
        let token: UUID
        let phase: Phase
        let expiresAtUptime: TimeInterval
        let bookmark: Data
        let revision: ConfigRevision
    }
    struct Receipt: Codable {
        let schema: Int
        let token: UUID
        let phase: Phase
        let revision: ConfigRevision
    }

    @MainActor
    public static func ensure(directory: AuthorizedDirectory) async throws {
        let revision = try FileConfigRepository(authorizedDirectory: directory.url).read().revision
        let group = try SharedContainer.locate().standardizedFileURL
        let probeLock = try StableFileLock(url: group.appendingPathComponent("automnt-permission.lock"))
        defer { withExtendedLifetime(probeLock) {} }
        let requestURL = group.appendingPathComponent(requestName)
        let service = SMAppService.agent(plistName: serviceName)
        if service.status == .enabled { try await service.unregister() }
        let token = UUID()
        let receiptURL = group.appendingPathComponent("automnt-permission-" + token.uuidString + ".plist")
        let directAccess = PermissionStore.hasFixedDirectoryEntitlement
        let bookmark = directAccess ? Data() : try directory.url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        guard directAccess || (!bookmark.isEmpty && bookmark.count <= 65_536) else { throw AutomntIssue.authorizationRequired }
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        do {
            let phases: [Phase] = directAccess ? [.verify] : [.bind, .verify]
            for phase in phases {
                // Verification receives no transferable grant. The receiver must use
                // its own fixed-directory entitlement (or a historical private bookmark).
                let request = Request(schema: 1, token: token, phase: phase,
                    expiresAtUptime: ProcessInfo.processInfo.systemUptime + 20,
                    bookmark: phase == .bind ? bookmark : Data(), revision: revision)
                try PrivateAtomicFile.replace(try PropertyListEncoder().encode(request), at: requestURL)
                if service.status != .requiresApproval { try service.register() }
                guard service.status != .requiresApproval else { throw AutomntIssue.backgroundApprovalRequired }
                guard service.status == .enabled else { throw AutomntIssue.authorizationRequired }
                try await awaitReceipt(receiptURL, token: token, phase: phase, revision: revision, deadline: deadline)
                // SDK unregister completion terminates the registered process. No
                // implicit transfer grant survives into the verification invocation.
                try await service.unregister()
            }
            guard try FileConfigRepository(authorizedDirectory: directory.url).read().revision == revision else {
                throw AutomntIssue.configurationConflict
            }
            try clean(requestURL: requestURL, receiptURL: receiptURL, token: token, group: group)
        } catch {
            if service.status == .enabled { try? await service.unregister() }
            try? clean(requestURL: requestURL, receiptURL: receiptURL, token: token, group: group)
            throw error
        }
    }

    @MainActor
    private static func awaitReceipt(_ url: URL, token: UUID, phase: Phase, revision: ConfigRevision,
                                     deadline: ContinuousClock.Instant) async throws {
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            do {
                let receipt = try PropertyListDecoder().decode(Receipt.self,
                    from: PrivateAtomicFile.read(url, maximumBytes: 4096))
                guard receipt.schema == 1, receipt.token == token, receipt.revision == revision else {
                    throw AutomntIssue.configurationConflict
                }
                if receipt.phase == phase { return }
            } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == ENOENT { }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw AutomntIssue.authorizationRequired
    }

    /// The signed authorization LaunchAgent never evaluates mounts or ownership.
    public static func receive() throws {
        let group = try SharedContainer.locate().standardizedFileURL
        let request = try PropertyListDecoder().decode(Request.self,
            from: PrivateAtomicFile.read(group.appendingPathComponent(requestName), maximumBytes: 90_000))
        let now = ProcessInfo.processInfo.systemUptime
        guard request.schema == 1, request.expiresAtUptime > now,
              request.expiresAtUptime - now <= 20 else { throw AutomntIssue.authorizationRequired }
        switch request.phase {
        case .bind:
            let grant = try PermissionBinding.authorizeTransferredBookmark(request.bookmark)
            guard try FileConfigRepository(authorizedDirectory: grant.url).read().revision == request.revision else {
                throw AutomntIssue.configurationConflict
            }
            withExtendedLifetime(grant) {}
        case .verify:
            guard request.bookmark.isEmpty else { throw AutomntIssue.authorizationRequired }
            let grant = try PermissionStore().resolve()
            guard try FileConfigRepository(authorizedDirectory: grant.url).read().revision == request.revision else {
                throw AutomntIssue.configurationConflict
            }
            withExtendedLifetime(grant) {}
        }
        let receiptURL = group.appendingPathComponent("automnt-permission-" + request.token.uuidString + ".plist")
        try PrivateAtomicFile.replace(try PropertyListEncoder().encode(
            Receipt(schema: 1, token: request.token, phase: request.phase, revision: request.revision)), at: receiptURL)
    }

    private static func clean(requestURL: URL, receiptURL: URL, token: UUID, group: URL) throws {
        guard requestURL.deletingLastPathComponent() == group, receiptURL.deletingLastPathComponent() == group else {
            throw AutomntIssue.authorizationRequired
        }
        if let data = try? PrivateAtomicFile.read(requestURL, maximumBytes: 90_000),
           let request = try? PropertyListDecoder().decode(Request.self, from: data), request.token == token {
            try FileManager.default.removeItem(at: requestURL)
        }
        if let data = try? PrivateAtomicFile.read(receiptURL, maximumBytes: 4096),
           let receipt = try? PropertyListDecoder().decode(Receipt.self, from: data), receipt.token == token {
            try FileManager.default.removeItem(at: receiptURL)
        }
    }
}
