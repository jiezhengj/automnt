import Foundation
import AutomntCore

public enum ManualEject {
    /// Explicit single-share request. The child rechecks ownership, revision and path.
    public static func mount(applicationURL: URL, directory: AuthorizedDirectory,
                             snapshot: ConfigSnapshot, host: HostConfig, share: SMBShareConfig) -> WorkerMountResponse {
        do {
            guard LegacyServicePresence.inspect() == .absent else { throw AutomntIssue.incompatibleOwner }
            guard snapshot.configuration.hosts.contains(host), host.shares.contains(share),
                  let bundle = Bundle(url: applicationURL) else { throw AutomntIssue.configurationConflict }
            let repository = FileConfigRepository(authorizedDirectory: directory.url)
            let store = BackendStateStore(authorizedDirectory: directory.url)
            let backend = try store.read()
            do {
                let permit = try EvaluationPermit(directory: directory.url, repository: repository,
                    expected: snapshot, owner: .app, generation: backend.generation,
                    explicitManualAppOperation: true, readBackend: store.read)
                try permit.perform { _ in
                    let stoppedLease = try StoppedManualOperation.acquireIfNeeded(state: store.read(), directory: directory.url)
                    defer { withExtendedLifetime(stoppedLease) {} }
                    try WorkerOperationStore(authorizedDirectory: directory.url).verifyIdle()
                    try UserEjectCommit.verifyReadable(directory: directory.url)
                }
            }
            let credential = try KeychainCredentialProvider().read(identity: smbResourceIdentity(share.smbURL) ?? "")
            let request = WorkerMountRequest(host: host, share: share,
                expiresAtUptime: ProcessInfo.processInfo.systemUptime + 30,
                revision: snapshot.revision, generation: backend.generation, manuallyRequested: true)
            return try MountWorkerRunner(applicationBundle: bundle).mount(request: request,
                credential: credential, authorizedDirectory: directory)
        } catch { return WorkerMountResponse(issue: error as? AutomntIssue ?? .signalUnavailable) }
    }

    /// Runs away from the GUI actor. Worker revalidates every input under evaluation.lock.
    public static func perform(applicationURL: URL, directory: AuthorizedDirectory,
                               snapshot: ConfigSnapshot, host: HostConfig, share: SMBShareConfig) -> WorkerMountResponse {
        do {
            guard snapshot.configuration.hosts.contains(host), host.shares.contains(share),
                  let bundle = Bundle(url: applicationURL) else { throw AutomntIssue.configurationConflict }
            let repository = FileConfigRepository(authorizedDirectory: directory.url)
            guard LegacyServicePresence.inspect() == .absent
            else { throw AutomntIssue.incompatibleOwner }
            let backendStore = BackendStateStore(authorizedDirectory: directory.url)
            let backend = try backendStore.read()
            do {
                let permit = try EvaluationPermit(directory: directory.url, repository: repository,
                    expected: snapshot, owner: .app, generation: backend.generation,
                    explicitManualAppOperation: true, readBackend: backendStore.read)
                try permit.perform { _ in
                    let stoppedLease = try StoppedManualOperation.acquireIfNeeded(state: backendStore.read(), directory: directory.url)
                    defer { withExtendedLifetime(stoppedLease) {} }
                    try WorkerOperationStore(authorizedDirectory: directory.url).verifyIdle()
                    try UserEjectCommit.verifyReadable(directory: directory.url)
                }
            } // Release the operation lock before launching the child that acquires it.
            let runner = try MountWorkerRunner(applicationBundle: bundle)
            let request = WorkerMountRequest(host: host, share: share,
                expiresAtUptime: ProcessInfo.processInfo.systemUptime + 5,
                revision: snapshot.revision, generation: backend.generation, operation: .unmount, manuallyRequested: true)
            return runner.unmount(request: request, authorizedDirectory: directory)
        } catch {
            return WorkerMountResponse(issue: error as? AutomntIssue ?? .signalUnavailable)
        }
    }
}
