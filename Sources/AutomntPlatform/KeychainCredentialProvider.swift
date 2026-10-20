import Foundation
import Security
import LocalAuthentication
import AutomntCore

/// Intentionally not Codable or CustomStringConvertible. Never put this in diagnostics.
public struct MemoryCredential: Sendable {
    public let username: String
    public let password: Data
    public init(username: String, password: Data) { self.username = username; self.password = password }
}

public enum KeychainSigningError: Error, Sendable {
    case missingEntitlement
}

public struct KeychainCredentialProvider: Sendable {
    private let service: String
    public init() { service = "org.automnt.smb" }
    private init(service: String) { self.service = service }

    /// Uses an isolated service and random account, never an SMB identity.
    /// Emits only phase/result; cleanup failure is an explicit failed probe.
    public static func probe() -> Int32 {
        let provider = Self(service: "org.automnt.keychain-probe")
        let identity = UUID().uuidString
        var phase = "initial-absence"
        do {
            guard try !provider.contains(identity: identity) else { throw AutomntIssue.credentialFailure }
            phase = "insert"
            let first = MemoryCredential(username: UUID().uuidString, password: Data(UUID().uuidString.utf8))
            try provider.save(identity: identity, credential: first)
            phase = "metadata"
            guard try provider.metadata(identity: identity)?.username == first.username else { throw AutomntIssue.credentialFailure }
            phase = "read"
            let loaded = try provider.read(identity: identity)
            guard loaded.username == first.username, loaded.password == first.password else { throw AutomntIssue.credentialFailure }
            phase = "update"
            let second = MemoryCredential(username: UUID().uuidString, password: Data(UUID().uuidString.utf8))
            try provider.save(identity: identity, credential: second)
            let updated = try provider.read(identity: identity)
            guard updated.username == second.username, updated.password == second.password,
                  try provider.metadata(identity: identity)?.username == second.username else { throw AutomntIssue.credentialFailure }
            phase = "delete"
            try provider.delete(identity: identity)
            guard try !provider.contains(identity: identity) else { throw AutomntIssue.credentialFailure }
            print("keychain-probe=passed; insert,metadata,read,update,delete; cleanup=verified")
            return 0
        } catch {
            let issue = error as? AutomntIssue ?? .credentialFailure
            if error is KeychainSigningError {
                print("keychain-probe-issue=missingEntitlement")
            } else {
                print("keychain-probe-issue=\(issue.rawValue)")
            }
            do {
                try provider.delete(identity: identity)
                guard try !provider.contains(identity: identity) else { throw AutomntIssue.credentialFailure }
                print("keychain-probe=failed; phase=\(phase); cleanup=verified")
            } catch { print("keychain-probe=failed; phase=\(phase); cleanup=unverified") }
            return 1
        }
    }

    /// Applies the same memory/pipe limits before Keychain access. No storage side effects.
    public static func validate(identity: String, credential: MemoryCredential) throws {
        guard !identity.isEmpty, identity.utf8.count <= 4096, !identity.contains("\0"),
              !credential.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              credential.username.utf8.count <= WorkerPipeProtocol.maximumCredentialBytes,
              !credential.username.contains("\0"), !credential.password.isEmpty,
              credential.password.count <= WorkerPipeProtocol.maximumCredentialBytes,
              !credential.password.contains(0), String(data: credential.password, encoding: .utf8) != nil else {
            throw AutomntIssue.credentialFailure
        }
    }

    private func query(identity: String) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: identity,
                kSecUseDataProtectionKeychain as String: true,
                kSecUseAuthenticationContext as String: context]
    }

    /// Checks presence without retrieving or decoding the stored secret payload.
    /// An inaccessible Keychain is an error, never proof that credentials are absent.
    public func contains(identity: String) throws -> Bool {
        try metadata(identity: identity) != nil
    }

    public struct Metadata: Sendable {
        public let username: String?
    }

    /// Older items have no username attribute; do not read their password payload
    /// merely to populate the credentials sheet.
    public func metadata(identity: String) throws -> Metadata? {
        guard !identity.isEmpty, identity.utf8.count <= 4096, !identity.contains("\0") else {
            throw AutomntIssue.credentialFailure
        }
        var request = query(identity: identity)
        request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try requireSuccess(status)
        guard let attributes = result as? [String: Any] else { throw AutomntIssue.credentialFailure }
        let username = attributes[kSecAttrLabel as String] as? String
        return Metadata(username: username)
    }

    public func read(identity: String) throws -> MemoryCredential {
        var request = query(identity: identity)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        try requireSuccess(status)
        guard let data = result as? Data, data.count <= WorkerPipeProtocol.maximumFrameBytes,
              let payload = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let username = payload["username"] as? String,
              let password = payload["password"] as? Data, !username.isEmpty, !password.isEmpty else {
            throw AutomntIssue.credentialFailure
        }
        let credential = MemoryCredential(username: username, password: password)
        try Self.validate(identity: identity, credential: credential)
        return credential
    }

    /// The foreground flow validates server acceptance separately; storage success is not acceptance.
    public func save(identity: String, credential: MemoryCredential) throws {
        try Self.validate(identity: identity, credential: credential)
        let data = try PropertyListSerialization.data(fromPropertyList:
                    ["username": credential.username, "password": credential.password], format: .binary, options: 0)
        let request = query(identity: identity)
        let status = SecItemUpdate(request as CFDictionary, [kSecValueData as String: data, kSecAttrLabel as String: credential.username] as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = request
            insertion[kSecValueData as String] = data
            insertion[kSecAttrLabel as String] = credential.username
            insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            try requireSuccess(SecItemAdd(insertion as CFDictionary, nil))
        } else { try requireSuccess(status) }
    }

    /// Called only by an independent, explicitly confirmed credentials action.
    public func delete(identity: String) throws {
        let status = SecItemDelete(query(identity: identity) as CFDictionary)
        if status != errSecItemNotFound { try requireSuccess(status) }
    }

    private func requireSuccess(_ status: OSStatus) throws {
        if service == "org.automnt.keychain-probe", status != errSecSuccess {
            print("keychain-probe-osstatus=\(status)")
        }
        switch status {
        case errSecSuccess: return
        case errSecMissingEntitlement: throw KeychainSigningError.missingEntitlement
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecNotAvailable:
            throw AutomntIssue.authorizationRequired
        default: throw AutomntIssue.credentialFailure
        }
    }
}
