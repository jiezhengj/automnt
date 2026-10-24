import Foundation
import os
import AutomntCore

/// Executes one bounded mount/eject/health operation for the background agent or the app.
///
/// App Sandbox cannot start a usable child for NetFS: an `inherit` child has no network
/// entitlement, and a child with its own profile is rejected by the kernel. The operation
/// therefore runs in this process (see `MountExecutionService`). The durable launch intent
/// is still recorded before execution and completed only by a verified response, so a
/// killed or timed-out attempt leaves the intent pending for the next repair.
public struct MountWorkerRunner {
    /// Secret-free diagnostics: operation outcome and failure kind only.
    private static let logger = Logger(subsystem: "org.automnt.automnt", category: "mount-runner")
    private let executable: URL
    private let applicationURL: URL
    public init(applicationBundle: Bundle) throws {
        guard applicationBundle.bundleIdentifier == "org.automnt.automnt" else {
            throw AutomntIssue.authorizationRequired
        }
        applicationURL = applicationBundle.bundleURL
        executable = applicationBundle.bundleURL.appendingPathComponent("Contents/Helpers/AutomntWorker")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw AutomntIssue.signalUnavailable
        }
    }

    public func mount(request: WorkerMountRequest, credential: MemoryCredential,
                      authorizedDirectory: AuthorizedDirectory) -> WorkerMountResponse {
        guard request.operation == .mount else { return WorkerMountResponse(issue: .invalidConfiguration) }
        return execute(request: request, credential: credential, authorizedDirectory: authorizedDirectory)
    }

    public func unmount(request: WorkerMountRequest,
                        authorizedDirectory: AuthorizedDirectory) -> WorkerMountResponse {
        guard request.operation == .unmount else { return WorkerMountResponse(issue: .invalidConfiguration) }
        return execute(request: request, credential: MemoryCredential(username: "", password: Data()),
                       authorizedDirectory: authorizedDirectory)
    }

    public func health(request: WorkerMountRequest,
                       authorizedDirectory: AuthorizedDirectory) -> WorkerMountResponse {
        guard request.operation == .health else { return WorkerMountResponse(issue: .invalidConfiguration) }
        return execute(request: request, credential: MemoryCredential(username: "", password: Data()),
                       authorizedDirectory: authorizedDirectory)
    }

    public func cleanup(request: WorkerMountRequest,
                        authorizedDirectory: AuthorizedDirectory) -> WorkerMountResponse {
        guard request.operation == .cleanup else { return WorkerMountResponse(issue: .invalidConfiguration) }
        return execute(request: request, credential: MemoryCredential(username: "", password: Data()),
                       authorizedDirectory: authorizedDirectory)
    }

    private func execute(request: WorkerMountRequest, credential: MemoryCredential,
                         authorizedDirectory: AuthorizedDirectory) -> WorkerMountResponse {
        let remaining = request.expiresAtUptime - ProcessInfo.processInfo.systemUptime
        guard remaining > 0, remaining <= 30 else {
            return WorkerMountResponse(issue: .timeout, requiresReconciliation: true)
        }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(Int64(remaining * 1000)))
        let store = WorkerOperationStore(authorizedDirectory: authorizedDirectory.url)
        var pendingIntent: (id: UUID, revision: ConfigRevision, generation: UInt64)?
        do {
            // The nested-code seal still proves this mount path belongs to the signed app.
            try BundledCodeVerifier.verify(applicationURL: applicationURL, workerURL: executable)
            let operationID = try store.begin(revision: request.revision, generation: request.generation,
                                              id: request.operationID)
            pendingIntent = (operationID, request.revision, request.generation)
            let response = try MountExecutionService.execute(request: request, credential: credential,
                                                             directory: authorizedDirectory, deadline: deadline)
            try WorkerPipeProtocol.validate(response: response, for: request)
            guard WorkerCompletionPolicy.mayComplete(request: request, response: response, exitedNormally: true,
                path: NetFSWorkerOperation.mountPathState(at: request.share.mountPoint)) else {
                return WorkerMountResponse(issue: response.issue ?? .signalUnavailable, requiresReconciliation: true)
            }
            try store.complete(id: operationID, revision: request.revision, generation: request.generation)
            return response
        } catch {
            let issue = error as? AutomntIssue ?? .signalUnavailable
            let requiresReconciliation = issue == .timeout || issue == .pathConflict || issue == .signalUnavailable
            // A definitive failure means the kernel state is known (nothing was mounted).
            // Leaving the launch intent pending would make the next state or observation
            // commit reject with `signalUnavailable`, hiding the failure from the round and
            // from the failure notification. Ambiguous outcomes keep the intent for repair.
            if !requiresReconciliation, let pendingIntent {
                do {
                    try store.complete(id: pendingIntent.id, revision: pendingIntent.revision,
                                       generation: pendingIntent.generation)
                } catch {
                    Self.logger.error("launch intent not cleared after definitive failure kind=\(String(describing: type(of: error)), privacy: .public)")
                }
            }
            Self.logger.error("mount runner failed issue=\(issue.rawValue, privacy: .public) kind=\(String(describing: type(of: error)), privacy: .public)")
            return WorkerMountResponse(issue: issue, requiresReconciliation: requiresReconciliation)
        }
    }
}
