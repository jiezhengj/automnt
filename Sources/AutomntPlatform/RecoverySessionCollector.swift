import Foundation
import Darwin
import SystemConfiguration
import AutomntCore

/// Public local APIs only; no subprocess, network request, or persistent observer.
public enum RecoverySessionCollector {
    public static func collect(previous: String?) -> RecoverySessionIdentity? {
        guard let login = loginEpoch() else { return nil }
        return RecoverySessionIdentity(network: networkIdentity(), loginEpoch: login, previous: previous)
    }

    public static func networkIdentity() -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }
        var elements: [String] = []
        var cursor = addresses
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) || address.pointee.sa_family == UInt8(AF_INET6) else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer,
                socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
            let value = String(cString: buffer)
            if value.lowercased().hasPrefix("fe80:") { continue }
            elements.append("if:\(String(cString: entry.pointee.ifa_name)):\(address.pointee.sa_family == UInt8(AF_INET) ? "v4" : "v6"):\(value)")
        }
        guard let store = SCDynamicStoreCreate(nil, "AutomntSession" as CFString, nil, nil),
              let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let gateway = ipv4["Router"] as? String, !gateway.isEmpty else {
            // Absence and denied collection are indistinguishable here; retain prior protection.
            return nil
        }
        elements.append("gw:\(gateway)")
        return elements.sorted().joined(separator: ";")
    }

    /// Boot time always changes on restart and stays readable inside the App Sandbox; the
    /// console utmpx record additionally separates logout/login within one boot. The sandbox
    /// denies the utmpx file (`getutxent` yields no console record), so the boot time alone
    /// must remain a usable epoch: returning nil here would keep the session boundary
    /// unestablished forever and a restart would look like the session that ejected a volume.
    public static func loginEpoch() -> String? {
        guard let boot = bootTimeSeconds() else { return nil }
        guard let console = consoleSessionStart() else { return "\(boot)-console-unreadable" }
        return "\(boot)-\(console)"
    }

    private static func bootTimeSeconds() -> Int64? {
        var boot = timeval()
        var length = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boot, &length, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        return Int64(boot.tv_sec)
    }

    private static func consoleSessionStart() -> Int64? {
        setutxent()
        defer { endutxent() }
        var latest: Int64 = 0
        while let entry = getutxent() {
            guard entry.pointee.ut_type == USER_PROCESS else { continue }
            let line = withUnsafeBytes(of: entry.pointee.ut_line) {
                String(cString: $0.bindMemory(to: CChar.self).baseAddress!)
            }
            guard line.hasPrefix("console") else { continue }
            latest = max(latest, Int64(entry.pointee.ut_tv.tv_sec))
        }
        guard latest > 0 else { return nil }
        return latest
    }
}
