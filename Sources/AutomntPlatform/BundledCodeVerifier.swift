import Foundation
import Security
import AutomntCore

/// Rejects unsigned/ad-hoc entries. Worker and containing application must be
/// Apple-anchored code signed by the caller's team with fixed product identities.
public enum BundledCodeVerifier {
    public static func verify(applicationURL: URL, workerURL: URL) throws {
        try verifyEntry(applicationURL: applicationURL, entryURL: workerURL, identifier: "org.automnt.automntworker")
    }

    public static func verifyHelper(applicationURL: URL, helperURL: URL) throws {
        try verifyEntry(applicationURL: applicationURL, entryURL: helperURL, identifier: "org.automnt.automnthelper")
        var helperCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(helperURL as CFURL, [], &helperCode) == errSecSuccess,
              let helperCode else { throw AutomntIssue.authorizationRequired }
        let group = try teamIdentifier(of: helperCode) + ".org.automnt.shared"
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(helperCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              entitlements["com.apple.security.app-sandbox"] as? Bool == true,
              entitlements["com.apple.security.application-groups"] as? [String] == [group],
               entitlements[PermissionStore.fixedDirectoryExceptionKey] as? [String] == [PermissionStore.fixedDirectoryHomeRelativePath],
              entitlements["com.apple.security.inherit"] == nil else {
            throw AutomntIssue.authorizationRequired
        }
    }

    private static func verifyEntry(applicationURL: URL, entryURL: URL, identifier: String) throws {
        var ownCode: SecCode?
        guard SecCodeCopySelf([], &ownCode) == errSecSuccess, let ownCode else {
            throw AutomntIssue.authorizationRequired
        }
        var ownStatic: SecStaticCode?
        guard SecCodeCopyStaticCode(ownCode, [], &ownStatic) == errSecSuccess, let ownStatic else {
            throw AutomntIssue.authorizationRequired
        }
        let team = try teamIdentifier(of: ownStatic)
        guard !team.isEmpty, team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw AutomntIssue.authorizationRequired
        }
        try check(applicationURL, identifier: "org.automnt.automnt", team: team)
        try check(entryURL, identifier: identifier, team: team)
    }

    private static func check(_ url: URL, identifier: String, team: String) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            throw AutomntIssue.authorizationRequired
        }
        var requirement: SecRequirement?
        let expression = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), requirement) == errSecSuccess,
              try teamIdentifier(of: code) == team else { throw AutomntIssue.authorizationRequired }
    }

    private static func teamIdentifier(of code: SecStaticCode) throws -> String {
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String else {
            throw AutomntIssue.authorizationRequired
        }
        return team
    }
}
