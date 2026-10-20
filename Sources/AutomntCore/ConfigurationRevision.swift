import Foundation
import CryptoKit

public enum ConfigurationRevision {
    public static func of(_ data: Data) -> ConfigRevision {
        ConfigRevision(digest: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }
}
