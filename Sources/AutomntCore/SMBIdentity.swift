import Foundation

/// Stable recovery/mount identity. Default port retains the pre-3.4 serialized form.
/// Credential rejection belongs to configuration validation; mount table sources may contain user names.
public func smbResourceIdentity(_ value: String) -> String? {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let input = clean.hasPrefix("//") ? "smb:\(clean)" : clean
    guard let components = URLComponents(string: input), components.scheme?.lowercased() == "smb",
          let host = components.host, !host.isEmpty else { return nil }
    let hostname = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
    guard let share = components.percentEncodedPath.split(separator: "/").first else { return nil }
    let name = String(share).removingPercentEncoding?.lowercased() ?? String(share).lowercased()
    let port = components.port ?? 445
    guard (1...65535).contains(port) else { return nil }
    let authority = hostname.contains(":") ? "[\(hostname)]" : hostname
    return "//\(port == 445 ? authority : "\(authority):\(port)")/\(name)"
}
