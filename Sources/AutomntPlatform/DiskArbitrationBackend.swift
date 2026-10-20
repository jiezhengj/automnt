import Foundation
import DiskArbitration
import Darwin
import AutomntCore

/// Isolated-worker primitive. Caller must hold evaluation.lock and validate the
/// current configuration/generation. The parent supervises the worker deadline.
/// A timeout does not cancel the kernel request and requires reconciliation.
public enum DiskArbitrationWorkerOperation {
    public static func unmount(_ volume: VolumeObservation,
                               deadline: ContinuousClock.Instant) throws -> VolumeObservation {
        guard ContinuousClock.now < deadline else { throw AutomntIssue.timeout }
        try Task.checkCancellation()
        guard let path = volume.actualPath, path.hasPrefix("/"), path != "/",
              !path.contains("\0"),
              URL(fileURLWithPath: path).standardizedFileURL.path == path,
              NetFSWorkerOperation.mountedIdentity(at: path) == volume.identity else {
            throw AutomntIssue.pathConflict
        }
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, URL(fileURLWithPath: path) as CFURL) else {
            throw AutomntIssue.signalUnavailable
        }
        let queue = DispatchQueue(label: "org.automnt.unmount-worker")
        DASessionSetDispatchQueue(session, queue)
        let completion = UnmountCompletion(session: session)
        let context = Unmanaged.passRetained(completion).toOpaque()
        // Default options only: never force or eject the entire device.
        DADiskUnmount(disk, DADiskUnmountOptions(kDADiskUnmountOptionDefault), { _, dissenter, context in
            guard let context else { return }
            let completion = Unmanaged<UnmountCompletion>.fromOpaque(context).takeRetainedValue()
            completion.finish(dissenter.map { DADissenterGetStatus($0) })
        }, context)
        let remaining = ContinuousClock.now.duration(to: deadline)
        let seconds = Double(remaining.components.seconds) + Double(remaining.components.attoseconds) / 1e18
        guard seconds > 0,
              completion.wait(seconds: min(seconds, 30)) else {
            // Completion retains the session until the late callback. If no callback
            // arrives, parent termination of this isolated process releases resources.
            throw AutomntIssue.timeout
        }
        if let status = completion.status {
            switch status {
            case DAReturn(kDAReturnBusy), DAReturn(kDAReturnExclusiveAccess): throw AutomntIssue.volumeBusy
            case DAReturn(kDAReturnNotPermitted), DAReturn(kDAReturnNotPrivileged): throw AutomntIssue.authorizationRequired
            default:
                let raw = status
                let errno = raw - 0xC000
                if errno == EBUSY { throw AutomntIssue.volumeBusy }
                if errno == EACCES || errno == EPERM { throw AutomntIssue.authorizationRequired }
                throw AutomntIssue.shareRejected
            }
        }
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw AutomntIssue.timeout }
        guard try !hasMount(at: path) else { throw AutomntIssue.pathConflict }
        // 'stopped' records observed absence only. Session suppression is committed
        // by the shared coordinator after current revision/generation revalidation.
        return VolumeObservation(identity: volume.identity, status: .stopped,
                                 actualPath: nil, observedAt: Date())
    }

    private static func hasMount(at path: String) throws -> Bool {
        var table: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&table, MNT_NOWAIT)
        guard count > 0, let table else { throw AutomntIssue.signalUnavailable }
        for index in 0..<Int(count) {
            var entry = table[index]
            let mountPath = withUnsafePointer(to: &entry.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            if mountPath == path { return true }
        }
        return false
    }
}

private final class UnmountCompletion: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private let session: DASession
    private var outcome: DAReturn?
    init(session: DASession) { self.session = session }
    var status: DAReturn? { lock.withLock { outcome } }
    func finish(_ status: DAReturn?) {
        lock.withLock { outcome = status }
        DASessionSetDispatchQueue(session, nil)
        semaphore.signal()
    }
    func wait(seconds: Double) -> Bool { semaphore.wait(timeout: .now() + seconds) == .success }
}
