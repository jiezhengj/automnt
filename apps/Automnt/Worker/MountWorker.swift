import Foundation
import Darwin
import AutomntCore
import AutomntPlatform

@main
struct MountWorker {
    static func main() async {
        signal(SIGPIPE, SIG_IGN)
        // No argv/env target or secrets, no stderr diagnostics with payload content.
        let response: WorkerMountResponse
        do {
            var inputInfo = stat()
            var outputInfo = stat()
            guard CommandLine.arguments.count == 1,
                  fstat(STDIN_FILENO, &inputInfo) == 0, inputInfo.st_mode & S_IFMT == S_IFIFO,
                  fstat(STDOUT_FILENO, &outputInfo) == 0, outputInfo.st_mode & S_IFMT == S_IFIFO else {
                throw AutomntIssue.invalidConfiguration
            }
            let frame = try WorkerPipeProtocol.readFrame(from: .standardInput)
            let (request, credential) = try WorkerPipeProtocol.decodeRequest(frame)
            let remaining = request.expiresAtUptime - ProcessInfo.processInfo.systemUptime
            guard remaining > 0, remaining <= 30 else { throw AutomntIssue.timeout }
            let deadline = ContinuousClock.now.advanced(by: .milliseconds(Int64(remaining * 1000)))
            // The worker resolves its own persistent authorization. A GUI bookmark
            // or authorization held by the helper is never treated as transferable.
            let directory = try PermissionStore().resolve()
            let repository = FileConfigRepository(authorizedDirectory: directory.url)
            let snapshot = try repository.read()
            let explicitManualMount = request.operation == .mount && request.manuallyRequested == true
            let explicitManualOperation = explicitManualMount ||
                (request.operation == .unmount && request.manuallyRequested == true)
            if explicitManualOperation {
                guard LegacyServicePresence.inspect() == .absent else { throw AutomntIssue.incompatibleOwner }
            }
            guard snapshot.revision == request.revision,
                  request.operation == .unmount || explicitManualMount || snapshot.configuration.isAutomationEnabled,
                  snapshot.configuration.hosts.contains(where: {
                      $0 == request.host && $0.shares.contains(request.share) &&
                       (request.operation == .unmount ||
                         (request.operation == .mount && request.manuallyRequested == true) ||
                         ($0.enabled && request.share.enabled))
                  }) else { throw AutomntIssue.configurationConflict }
            let state = BackendStateStore(authorizedDirectory: directory.url)
            let permit = try EvaluationPermit(directory: directory.url, repository: repository,
                expected: snapshot, owner: .app, generation: request.generation,
                explicitManualAppOperation: explicitManualOperation, readBackend: state.read)
            let mounted = try permit.perform { _ in
                let stoppedLease = explicitManualOperation
                    ? try StoppedManualOperation.acquireIfNeeded(state: state.read(), directory: directory.url) : nil
                defer { withExtendedLifetime(stoppedLease) {} }
                if explicitManualOperation {
                    guard LegacyServicePresence.inspect() == .absent else { throw AutomntIssue.incompatibleOwner }
                }
                try WorkerOperationStore(authorizedDirectory: directory.url).verifyPending(
                    id: request.operationID, revision: request.revision, generation: request.generation)
                if request.operation == .health {
                    return MountResult(observation: try VolumeHealthWorkerOperation.probe(share: request.share, deadline: deadline),
                                       postMount: .notRequested)
                }
                if request.operation == .cleanup {
                    guard let identity = smbResourceIdentity(request.share.smbURL) else { throw AutomntIssue.invalidConfiguration }
                    let recovery = RecoveryStateRepository(url: directory.url.appendingPathComponent("mount-recovery-state.plist")).read()
                    guard RecoveryCleanupCommit.permits(configuration: snapshot.configuration, recovery: recovery,
                        identity: identity, health: .failed) else { throw AutomntIssue.configurationConflict }
                    // Re-probe inside the same locked child; the parent's earlier failure can be stale.
                    let health = try VolumeHealthWorkerOperation.probe(share: request.share, deadline: deadline)
                    guard health.status == .failed, health.issue == .shareRejected else { throw AutomntIssue.signalUnavailable }
                    return MountResult(observation: try DiskArbitrationWorkerOperation.unmount(health, deadline: deadline),
                                       postMount: .notRequested)
                }
                if request.operation == .unmount {
                    guard let identity = smbResourceIdentity(request.share.smbURL) else { throw AutomntIssue.invalidConfiguration }
                    try UserEjectCommit.verifyReadable(directory: directory.url)
                    let observation = VolumeObservation(identity: identity, status: .evaluating,
                        actualPath: request.share.mountPoint, observedAt: Date())
                    let stopped = try DiskArbitrationWorkerOperation.unmount(observation, deadline: deadline)
                    try UserEjectCommit.apply(stopped, directory: directory.url,
                        path: NetFSWorkerOperation.mountPathState(at: request.share.mountPoint),
                        operationID: request.operationID, revision: request.revision, generation: request.generation)
                    return MountResult(observation: stopped, postMount: .notRequested)
                }
                guard let identity = smbResourceIdentity(request.share.smbURL) else { throw AutomntIssue.invalidConfiguration }
                let recovery = RecoveryStateRepository(url: directory.url.appendingPathComponent("mount-recovery-state.plist")).read()
                let path = NetFSWorkerOperation.mountPathState(at: request.share.mountPoint)
                if request.manuallyRequested == true {
                    guard recovery.isReadable else { throw AutomntIssue.signalUnavailable }
                    switch BaselineMountDecision.block(path: path, identity: identity) {
                    case .blocked(let issue): throw issue
                    case .inspectExisting:
                        try UserEjectCommit.resumeAfterManualMount(identity: identity, directory: directory.url, path: path)
                        return MountResult(observation: VolumeObservation(identity: identity, status: .evaluating,
                            actualPath: request.share.mountPoint, observedAt: Date()), postMount: .notRequested)
                    case nil: break
                    default: throw AutomntIssue.signalUnavailable
                    }
                    let result = try NetFSWorkerOperation.mount(share: request.share, host: request.host,
                        credential: credential, deadline: deadline)
                    try UserEjectCommit.resumeAfterManualMount(identity: identity, directory: directory.url,
                        path: NetFSWorkerOperation.mountPathState(at: request.share.mountPoint))
                    return result
                }
                switch BaselineMountDecision.decide(identity: identity,
                    path: NetFSWorkerOperation.mountPathState(at: request.share.mountPoint), recovery: recovery,
                    configuration: snapshot.configuration, mountPoint: request.share.mountPoint, allowRecovery: true) {
                case .mount: break
                case .blocked(let issue): throw issue
                case .suppressed, .deferred: throw AutomntIssue.configurationConflict
                case .inspectExisting:
                    return MountResult(observation: VolumeObservation(identity: identity, status: .evaluating,
                        actualPath: request.share.mountPoint, observedAt: Date()), postMount: .notRequested)
                }
                try RecoveryAttemptCommit.reserve(identity: identity, directory: directory.url,
                    configuration: snapshot.configuration, operationID: request.operationID)
                return try NetFSWorkerOperation.mount(share: request.share, host: request.host,
                                              credential: credential, deadline: deadline)
            }
            let post: PostMountResult
            if request.operation == .mount, request.host.preventSpotlightIndex, let path = mounted.observation.actualPath {
                post = await VolumeMarkerPostMountBackend().preventIndexing(at: path, deadline: deadline)
            } else { post = .notRequested }
            response = WorkerMountResponse(observation: mounted.observation, postMount: post)
            // Keep descriptor lock and security scope through post-processing.
            withExtendedLifetime((permit, directory)) {}
        } catch {
            let issue = error as? AutomntIssue ?? .signalUnavailable
            response = WorkerMountResponse(issue: issue,
                requiresReconciliation: issue == .timeout || issue == .pathConflict || issue == .signalUnavailable)
        }
        do { try FileHandle.standardOutput.write(contentsOf: WorkerPipeProtocol.encode(response: response)) }
        catch { exit(EXIT_FAILURE) }
    }
}
