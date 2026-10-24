import Foundation
import NetFS
import Darwin
import AutomntCore

/// Synchronous NetFS primitive for the isolated worker only. The parent enforces the
/// wall-clock deadline and reconciles kernel mount state before permitting any retry.
/// Never call this primitive from the GUI or the launchd helper process.
public enum NetFSWorkerOperation {
    public static func mount(share: SMBShareConfig, host: HostConfig,
                             credential: MemoryCredential, deadline: ContinuousClock.Instant) throws -> MountResult {
        guard ContinuousClock.now < deadline else { throw AutomntIssue.timeout }
        var configuration = AutomntConfig()
        var singleHost = host
        singleHost.shares = [share]
        configuration.hosts = [singleHost]
        guard ConfigurationValidation.problems(in: configuration).isEmpty,
              let url = URL(string: share.smbURL.hasPrefix("//") ? "smb:\(share.smbURL)" : share.smbURL),
              let identity = smbResourceIdentity(share.smbURL) else { throw AutomntIssue.invalidConfiguration }
        // The product does not manage SMB passwords. An empty credential is not an error:
        // NetFS then reuses the sign-in macOS already holds for this share (the same path
        // the CLI takes). `kNAUIOptionNoUI` keeps a background miss from raising a dialog.
        let user: CFString? = credential.username.isEmpty ? nil : credential.username as CFString
        var password: CFString?
        if !credential.username.isEmpty {
            guard let text = String(data: credential.password, encoding: .utf8), !text.isEmpty else {
                throw AutomntIssue.credentialFailure
            }
            password = text as CFString
        }
        let openOptions = NSMutableDictionary(dictionary: [kNAUIOptionKey as String: kNAUIOptionNoUI])
        let mountOptions = NSMutableDictionary()
        let standard = deriveStandardMountPoint(from: share.smbURL)
        let custom = share.mountPoint != standard
        if custom { mountOptions[kNetFSMountAtMountDirKey as String] = true }
        let mountDirectory = URL(fileURLWithPath: custom ? share.mountPoint : "/Volumes", isDirectory: true)
        var mounted: Unmanaged<CFArray>?
        let status = NetFSMountURLSync(url as CFURL, mountDirectory as CFURL,
                                      user, password,
                                      openOptions, mountOptions, &mounted)
        let paths = mounted?.takeRetainedValue() as? [String] ?? []
        guard status == 0 else { throw issue(status) }
        let expectedPath = URL(fileURLWithPath: share.mountPoint).standardizedFileURL.path
        guard paths.contains(where: { URL(fileURLWithPath: $0).standardizedFileURL.path == expectedPath }) else {
            throw AutomntIssue.pathConflict
        }
        guard mountedIdentity(at: expectedPath) == identity else { throw AutomntIssue.pathConflict }
        // Success is accepted only for the configured path with matching kernel SMB identity.
        // Read/write capability and post-processing are separate worker operations.
        return MountResult(observation: VolumeObservation(identity: identity, status: .evaluating,
            actualPath: expectedPath, observedAt: Date()), postMount: .notRequested)
    }

    public static func mountedIdentity(at path: String) -> String? {
        if case .smb(let identity) = mountPathState(at: path) { return identity }
        return nil
    }

    public static func mountPathState(at path: String) -> MountPathState {
        var table: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&table, MNT_NOWAIT)
        guard count > 0, let table else { return .unavailable }
        for index in 0..<Int(count) {
            var entry = table[index]
            let mountPath = withUnsafePointer(to: &entry.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            guard mountPath == path else { continue }
            let filesystem = withUnsafePointer(to: &entry.f_fstypename) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSNAMELEN)) { String(cString: $0) }
            }
            guard filesystem == "smbfs" else { return .occupied }
            let source = withUnsafePointer(to: &entry.f_mntfromname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            guard let identity = smbResourceIdentity(source) else { return .unavailable }
            return .smb(identity: identity)
        }
        return .absent
    }

    private static func issue(_ status: Int32) -> AutomntIssue {
        switch status {
        case EACCES, EPERM: .authorizationRequired
        case EAUTH, -5999, -5045, -5046: .credentialFailure
        case ETIMEDOUT: .timeout
        case EHOSTUNREACH, ENETUNREACH, ECONNREFUSED: .offline
        case EBUSY, EEXIST: .pathConflict
        default: .shareRejected
        }
    }
}
