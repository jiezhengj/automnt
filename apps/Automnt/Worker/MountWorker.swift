import Foundation
import os
import AutomntCore
import AutomntPlatform

@main
struct MountWorker {
    /// The worker binary is retained only as the durable nested-code seal for the mount
    /// path; App Sandbox no longer allows it to perform NetFS work in a child process.
    /// Diagnostics stay secret-free: failure kind only, never a target or credential.
    private static let logger = Logger(subsystem: "org.automnt.automnt", category: "worker")

    static func main() async {
        signal(SIGPIPE, SIG_IGN)
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
            // The worker resolves its own persistent authorization; a scope held by the
            // caller is never treated as transferable.
            let directory = try PermissionStore().resolve()
            response = try MountExecutionService.execute(request: request, credential: credential,
                                                          directory: directory, deadline: deadline)
        } catch {
            let issue = error as? AutomntIssue ?? .signalUnavailable
            logger.error("worker failed issue=\(issue.rawValue, privacy: .public) kind=\(String(describing: type(of: error)), privacy: .public)")
            response = WorkerMountResponse(issue: issue,
                requiresReconciliation: issue == .timeout || issue == .pathConflict || issue == .signalUnavailable)
        }
        do { try FileHandle.standardOutput.write(contentsOf: WorkerPipeProtocol.encode(response: response)) }
        catch {
            logger.error("worker response write failed kind=\(String(describing: type(of: error)), privacy: .public)")
            exit(EXIT_FAILURE)
        }
    }
}
