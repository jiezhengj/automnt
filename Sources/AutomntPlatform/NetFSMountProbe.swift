import Foundation
import NetFS

/// Diagnostic only: one bounded mount attempt with no credential, so macOS reuses the
/// SMB sign-in it already holds. Prints the raw NetFS status and never retries. The
/// caller owns the resulting mount and must eject it; no configuration is read or written.
public enum NetFSMountProbe {
    public static func run(urlString: String) -> Int32 {
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "smb" else {
            print("netfs-probe=invalid-url")
            return 2
        }
        let options = NSMutableDictionary(dictionary: [kNAUIOptionKey as String: kNAUIOptionNoUI])
        var mounted: Unmanaged<CFArray>?
        let status = NetFSMountURLSync(url as CFURL,
                                       URL(fileURLWithPath: "/Volumes") as CFURL,
                                       nil, nil, options, nil, &mounted)
        let paths = mounted?.takeRetainedValue() as? [String] ?? []
        print("netfs-probe=status:\(status); mounted=\(paths.count)")
        return status == 0 ? 0 : 1
    }
}
