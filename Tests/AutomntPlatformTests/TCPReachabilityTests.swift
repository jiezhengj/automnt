import Foundation
import Network
import Testing
import AutomntCore
@testable import AutomntPlatform

private final class LocalListener: @unchecked Sendable {
    let listener: NWListener
    private let queue = DispatchQueue(label: "org.automnt.test-listener")
    init() throws { listener = try NWListener(using: .tcp, on: .any) }
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: listener.port!.rawValue)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { connection in
                connection.start(queue: self.queue)
                connection.cancel()
            }
            listener.start(queue: queue)
        }
    }
    deinit { listener.cancel() }
}

struct TCPReachabilityTests {
    @Test func localTCPConnectionAndCancellation() async throws {
        let listener = try LocalListener()
        let port = try await listener.start()
        let probe = TCPReachabilityProbe()
        #expect(try await probe.isReachable(host: "localhost", port: Int(port), timeoutMilliseconds: 1000))
        listener.listener.cancel()
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await probe.isReachable(host: "localhost", port: Int(port), timeoutMilliseconds: 1000)
        }
        do { _ = try await cancelled.value }
        catch is CancellationError { return }
        Issue.record("Cancelled probe must throw cancellation")
    }

    @Test func markerDoesNotOverwriteExistingContents() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = VolumeMarkerPostMountBackend()
        #expect(await backend.preventIndexing(at: directory.path, deadline: ContinuousClock.now.advanced(by: .seconds(1))) == .markerCreated)
        let marker = directory.appendingPathComponent(".metadata_never_index")
        let contents = Data(UUID().uuidString.utf8)
        try contents.write(to: marker)
        #expect(await backend.preventIndexing(at: directory.path, deadline: ContinuousClock.now.advanced(by: .seconds(1))) == .markerAlreadyPresent)
        #expect(try Data(contentsOf: marker) == contents)
        #expect(await backend.preventIndexing(at: directory.path, deadline: ContinuousClock.now.advanced(by: .seconds(-1))) == .timedOut)
    }

    @Test func expiredNetFSMountNeverInvokesSystemMount() throws {
        let host = HostConfig(host: UUID().uuidString)
        let share = SMBShareConfig(name: UUID().uuidString, smbURL: "", mountPoint: "")
        #expect(throws: AutomntIssue.timeout) {
            try NetFSWorkerOperation.mount(share: share, host: host,
                credential: MemoryCredential(username: "", password: Data()),
                deadline: ContinuousClock.now.advanced(by: .seconds(-1)))
        }
        #expect(NetFSWorkerOperation.mountedIdentity(at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path) == nil)
    }

    @Test func invalidPortCannotStartConnection() async {
        do {
            _ = try await TCPReachabilityProbe().isReachable(host: UUID().uuidString, port: 65536, timeoutMilliseconds: 100)
            Issue.record("Invalid endpoint accepted")
        } catch { #expect(error as? AutomntIssue == .invalidConfiguration) }
    }
}
