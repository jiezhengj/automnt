import Foundation
import Darwin
import AutomntCore

/// Synchronous bounded child I/O for the short-lived helper, never the GUI actor.
/// Worker takes evaluation.lock itself; the parent must not hold that lock while waiting.
/// No automatic retry follows timeout/termination: kernel reconciliation is required.
public struct MountWorkerRunner {
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
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = []
        // No caller environment, secrets, or target data are inherited through env.
        process.environment = [:]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        defer {
            try? input.fileHandleForWriting.close()
            try? input.fileHandleForReading.close()
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
        }
        do {
            try BundledCodeVerifier.verify(applicationURL: applicationURL, workerURL: executable)
            let frame = try WorkerPipeProtocol.encode(request: request, credential: credential)
            let writer = input.fileHandleForWriting.fileDescriptor
            let reader = output.fileHandleForReading.fileDescriptor
            guard fcntl(writer, F_SETFL, O_NONBLOCK) == 0,
                  fcntl(reader, F_SETFL, O_NONBLOCK) == 0,
                  fcntl(writer, F_SETNOSIGPIPE, 1) == 0 else { throw AutomntIssue.signalUnavailable }
            let operationStore = WorkerOperationStore(authorizedDirectory: authorizedDirectory.url)
            let operationID = try operationStore.launch(revision: request.revision,
                generation: request.generation, id: request.operationID) { try process.run() }
            try input.fileHandleForReading.close()
            try output.fileHandleForWriting.close()
            var sent = 0
            var received = Data()
            var inputClosed = false
            var eof = false
            var buffer = [UInt8](repeating: 0, count: 8192)
            while ContinuousClock.now < deadline {
                if sent < frame.count {
                    let count = frame.withUnsafeBytes {
                        Darwin.write(writer, $0.baseAddress!.advanced(by: sent), frame.count - sent)
                    }
                    if count > 0 { sent += count }
                    else if count < 0 && errno != EAGAIN && errno != EINTR { throw AutomntIssue.signalUnavailable }
                }
                if sent == frame.count && !inputClosed {
                    try input.fileHandleForWriting.close()
                    inputClosed = true
                }
                if !eof {
                    let count = Darwin.read(reader, &buffer, buffer.count)
                    if count > 0 {
                        guard received.count + count <= WorkerPipeProtocol.maximumFrameBytes + 4 else {
                            throw AutomntIssue.signalUnavailable
                        }
                        received.append(contentsOf: buffer.prefix(count))
                    } else if count == 0 { eof = true }
                    else if errno != EAGAIN && errno != EINTR { throw AutomntIssue.signalUnavailable }
                }
                if !process.isRunning && eof {
                    guard process.terminationStatus == 0 else { throw AutomntIssue.signalUnavailable }
                    let response = try WorkerPipeProtocol.decodeResponse(received)
                    try WorkerPipeProtocol.validate(response: response, for: request)
                    guard WorkerCompletionPolicy.mayComplete(request: request, response: response,
                        exitedNormally: true, path: NetFSWorkerOperation.mountPathState(at: request.share.mountPoint)) else {
                        return WorkerMountResponse(issue: response.issue ?? .signalUnavailable, requiresReconciliation: true)
                    }
                    try operationStore.complete(id: operationID, revision: request.revision, generation: request.generation)
                    return response
                }
                // Bounded I/O monitoring only. This is not a service trigger or network poll.
                var descriptor = pollfd(fd: reader, events: Int16(POLLIN), revents: 0)
                if eof { descriptor.fd = -1 }
                _ = poll(&descriptor, 1, 10)
            }
            stop(process)
            return WorkerMountResponse(issue: .timeout, requiresReconciliation: true)
        } catch {
            stop(process)
            return WorkerMountResponse(issue: error as? AutomntIssue ?? .signalUnavailable,
                                       requiresReconciliation: true)
        }
    }

    private func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        // SIGKILL is limited to this launched child; no force-unmount or external PID.
        if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
        // Never waitUntilExit: kernel calls may delay process reap. Caller must verify
        // actual exit and kernel mount convergence before granting another operation.
    }
}
