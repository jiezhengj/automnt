import Foundation
import Security
import AutomntCore

/// Resolves the team's macOS group container without a user-selected directory.
/// No business data is created by this lookup.
public enum SharedContainer {
    public static func locate() throws -> URL {
        var ownCode: SecCode?
        var ownStatic: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &ownCode) == errSecSuccess, let ownCode,
              SecCodeCopyStaticCode(ownCode, [], &ownStatic) == errSecSuccess, let ownStatic,
              SecCodeCopySigningInformation(ownStatic, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty, team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw NSError(domain: "AutomntSharedContainer", code: 1)
        }
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: team + ".org.automnt.shared") else {
            throw NSError(domain: "AutomntSharedContainer", code: 2)
        }
        return container
    }

    /// Explicit development probe: isolated random sentinel, never business configuration.
    public static func probe(arguments: [String]) -> Int32 {
        guard arguments.count == 4, let token = UUID(uuidString: arguments[3]),
              ["write", "read", "remove"].contains(arguments[2]) else { return 2 }
        do {
            let container = try locate().standardizedFileURL
            let file = container.appendingPathComponent("automnt-probe-" + token.uuidString + ".txt")
            let expected = Data(token.uuidString.utf8)
            guard file.deletingLastPathComponent() == container else { return 2 }
            switch arguments[2] {
            case "write": try expected.write(to: file, options: [.withoutOverwriting])
            case "read":
                guard try Data(contentsOf: file) == expected else { return 4 }
            case "remove":
                guard try Data(contentsOf: file) == expected else { return 4 }
                try FileManager.default.removeItem(at: file)
            default: return 2
            }
            FileHandle.standardOutput.write(Data("shared-container-probe: \(arguments[2])-verified\n".utf8))
            return 0
        } catch {
            let failure = error as NSError
            FileHandle.standardError.write(Data("shared-container-probe: failed; domain=\(failure.domain); code=\(failure.code)\n".utf8))
            return 1
        }
    }

    public static func check() -> Int32 {
        do {
            let container = try locate()
            let values = try container.resourceValues(forKeys: [.isDirectoryKey, .isWritableKey])
            guard values.isDirectory == true else { throw NSError(domain: "AutomntSharedContainer", code: 3) }
            let writable = values.isWritable.map(String.init) ?? "unknown"
            FileHandle.standardOutput.write(Data("shared-container: directory; writable-metadata=\(writable)\n".utf8))
            FileHandle.standardOutput.write(Data("shared-container: located\n".utf8))
            return 0
        } catch {
            let failure = error as NSError
            FileHandle.standardError.write(Data("shared-container: unavailable; domain=\(failure.domain); code=\(failure.code)\n".utf8))
            return 1
        }
    }
}
