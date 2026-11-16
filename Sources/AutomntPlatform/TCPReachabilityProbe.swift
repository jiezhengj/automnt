import Foundation
import Network
import AutomntCore

/// 后台可达性探测：TCP 连接 + 一次 SMB2 `NEGOTIATE` 应答校验。
///
/// **为什么不能只看 TCP**：本机可能存在 fake-ip 代理（Clash/代理软件的 TUN），它会
/// 接受任意地址的 TCP 连接并在数毫秒内关闭。此时「TCP 连上」既不能证明对端是 SMB
/// 服务器，也不能证明主机名解析到了真实地址。因此探测在连接就绪后发送一次
/// `NEGOTIATE`，只要求收到合法的 SMB2 响应头；不认证、不建会话、不写状态。
///
/// **为什么先做 DNS-SD 解析**：配置里可写成 Bonjour 实例名
/// （`<instance>._smb._tcp.local`）。`getaddrinfo` 不解析服务实例名，只会拿到代理
/// 或上游 DNS 给出的合成地址。此处先用 `BonjourServiceResolver` 解析出 SRV 目标，
/// 再对目标做 SMB 探测；解析失败即判定不可达，不回退到 `getaddrinfo(实例名)`。
public struct TCPReachabilityProbe: ReachabilityProbe {
    private let resolver: BonjourServiceResolver

    public init() { resolver = BonjourServiceResolver() }

    public func isReachable(host: String, port: Int, timeoutMilliseconds: Int) async throws -> Bool {
        guard !host.isEmpty, !host.contains("\0"), (1...65535).contains(port), timeoutMilliseconds > 0,
              let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw AutomntIssue.invalidConfiguration
        }
        try Task.checkCancellation()
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(min(timeoutMilliseconds, 30_000)))

        // 1. Bonjour 服务实例名先解析为 SRV 目标；普通主机名/IP 原样返回。
        guard let target = await resolver.resolveIfNeeded(host: host,
                                                          timeoutMilliseconds: remainingMilliseconds(until: deadline)) else {
            return false
        }
        try Task.checkCancellation()

        // 2. 对解析后的目标做 TCP + SMB2 NEGOTIATE。
        let budget = remainingMilliseconds(until: deadline)
        guard budget > 0 else { return false }
        let attempt = SMBHandshakeAttempt(host: target, port: endpointPort, milliseconds: budget)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { attempt.start($0) }
        } onCancel: { attempt.finish(.failure(CancellationError())) }
    }

    private func remainingMilliseconds(until deadline: ContinuousClock.Instant) -> Int {
        let remaining = ContinuousClock.now.duration(to: deadline).components
        let milliseconds = remaining.seconds * 1000 + remaining.attoseconds / 1_000_000_000_000_000
        return Int(max(milliseconds, 0))
    }
}

/// Network 回调、socket 事件与超时共用同一队列；锁保证只有一次结果。
private final class SMBHandshakeAttempt: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "org.automnt.smb-probe")
    private let connection: NWConnection
    private let milliseconds: Int
    private let frame = SMB2NegotiateFrame.request()
    private var continuation: CheckedContinuation<Bool, any Error>?
    private var result: Result<Bool, any Error>?
    private var timer: DispatchSourceTimer?

    init(host: String, port: NWEndpoint.Port, milliseconds: Int) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        self.milliseconds = milliseconds
    }

    func start(_ continuation: CheckedContinuation<Bool, any Error>) {
        let early = lock.withLock { () -> Result<Bool, any Error>? in
            if let result { return result }
            self.continuation = continuation
            return nil
        }
        if let early { continuation.resume(with: early); return }
        queue.async { [self] in
            guard !lock.withLock({ result != nil }) else { return }
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.sendNegotiate()
                case .failed, .waiting: self?.finish(.success(false))
                case .cancelled: self?.finish(.failure(CancellationError()))
                default: break
                }
            }
            let timeout = DispatchSource.makeTimerSource(queue: queue)
            timer = timeout
            timeout.schedule(deadline: .now() + .milliseconds(milliseconds))
            timeout.setEventHandler { [weak self] in self?.finish(.success(false)) }
            timeout.resume()
            connection.start(queue: queue)
        }
    }

    /// 连接就绪后发送一次性 `NEGOTIATE`，随后只读响应头：NetBIOS 长度 + SMB2 魔数。
    private func sendNegotiate() {
        connection.send(content: frame, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            guard error == nil else { finish(.success(false)); return }
            readNetBIOSHeader()
        })
    }

    private func readNetBIOSHeader() {
        connection.receive(minimumIncompleteLength: SMB2NegotiateFrame.netBIOSHeaderLength,
                           maximumLength: SMB2NegotiateFrame.netBIOSHeaderLength) { [weak self] data, _, _, error in
            guard let self else { return }
            guard error == nil,
                  let data, SMB2NegotiateFrame.payloadLength(fromNetBIOSHeader: data) != nil else {
                finish(.success(false))
                return
            }
            readMagic()
        }
    }

    private func readMagic() {
        let magicLength = SMB2NegotiateFrame.responseMagic.count
        connection.receive(minimumIncompleteLength: magicLength, maximumLength: magicLength) { [weak self] data, _, _, error in
            guard let self else { return }
            guard error == nil, let data else { finish(.success(false)); return }
            finish(.success(SMB2NegotiateFrame.isResponseHeader(data)))
        }
    }

    func finish(_ result: Result<Bool, any Error>) {
        let completion = lock.withLock { () -> CheckedContinuation<Bool, any Error>? in
            guard self.result == nil else { return nil }
            self.result = result
            let pending = continuation
            continuation = nil
            return pending
        }
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
        completion?.resume(with: result)
    }
}
