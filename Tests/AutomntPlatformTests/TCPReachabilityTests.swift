import Foundation
import Network
import Testing
import AutomntCore
@testable import AutomntPlatform

private final class LocalListener: @unchecked Sendable {
    let listener: NWListener
    private let queue = DispatchQueue(label: "org.automnt.test-listener")
    /// 连接建立后立即写回的字节；nil 表示像 fake-ip 代理那样立刻关闭连接。
    private let reply: Data?
    init(reply: Data? = nil) throws {
        self.reply = reply
        listener = try NWListener(using: .tcp, on: .any)
    }
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
            listener.newConnectionHandler = { [self] connection in
                connection.start(queue: self.queue)
                guard let reply = self.reply else {
                    connection.cancel()
                    return
                }
                connection.send(content: reply, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
            listener.start(queue: queue)
        }
    }
    deinit { listener.cancel() }
}

/// 最小的 SMB2 `NEGOTIATE` 响应头（NetBIOS 长度 + `\xfeSMB`），用于证明「只连上 TCP」不足。
private let smb2NegotiateResponseHeader = SMB2NegotiateFrame.netBIOSHeader(length: 4)
    + SMB2NegotiateFrame.responseMagic

struct TCPReachabilityTests {
    /// 只接受 TCP 立即关闭的对端（fake-ip 代理的典型行为）不得算作可达。
    @Test func tcpOnlyEndpointIsNotReachable() async throws {
        let listener = try LocalListener()
        let port = try await listener.start()
        let probe = TCPReachabilityProbe()
        #expect(try await probe.isReachable(host: "localhost", port: Int(port), timeoutMilliseconds: 1000) == false)
    }

    /// 真正应答 SMB2 `NEGOTIATE` 的对端才算可达。
    @Test func smb2NegotiateResponderIsReachable() async throws {
        let listener = try LocalListener(reply: smb2NegotiateResponseHeader)
        let port = try await listener.start()
        let probe = TCPReachabilityProbe()
        #expect(try await probe.isReachable(host: "localhost", port: Int(port), timeoutMilliseconds: 1000))
    }

    @Test func cancelledProbeThrowsCancellation() async throws {
        let listener = try LocalListener(reply: smb2NegotiateResponseHeader)
        let port = try await listener.start()
        let probe = TCPReachabilityProbe()
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
