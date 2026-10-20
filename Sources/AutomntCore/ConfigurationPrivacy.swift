import Foundation

/// Unknown extensions may survive, but credential-bearing keys never do.
public enum ConfigurationPrivacy {
    public static func validate(_ value: Any) throws {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
                if ["password", "passwd", "pwd", "username", "credential", "credentials", "secret", "token", "accesstoken", "refreshtoken"].contains(normalized) {
                    throw AutomntIssue.credentialFailure
                }
                try validate(child)
            }
        } else if let array = value as? [Any] {
            for child in array { try validate(child) }
        } else if let string = value as? String {
            let clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.lowercased().hasPrefix("smb://") || clean.hasPrefix("//"),
               let url = URLComponents(string: clean.hasPrefix("//") ? "smb:\(clean)" : clean),
               url.user != nil || url.password != nil {
                throw AutomntIssue.credentialFailure
            }
        }
    }
}
