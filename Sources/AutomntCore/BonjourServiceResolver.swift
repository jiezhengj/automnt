import Foundation
import dnssd

/// Bonjour 服务实例名（`<instance>._smb._tcp.local`）的解析。
///
/// 背景：`getaddrinfo` 对 `*._smb._tcp.local` 这类**服务实例名**不做 DNS-SD 解析，
/// 只会把它当成普通主机名查询；本机若存在 fake-ip 代理（返回 `198.18.x.x`）或
/// 上游 DNS 返回合成答案，就会拿到一个「能连上但不是 SMB 服务器」的地址。
/// 因此配置里写成 Bonjour 实例名的服务器必须先经 DNS-SD 解析出 SRV 目标
/// （如 `DX4600.local.`），再把该主机名交给后续连接与探测。
public enum BonjourServiceName {
    /// SMB 服务的 DNS-SD 类型（不含前导下划线差异）。
    public static let serviceType = "_smb._tcp"
    /// Bonjour 局域网域。
    public static let localDomain = "local"

    /// 解析结果为 DNS-SD 三元组。
    public struct Reference: Equatable, Sendable {
        public let instance: String
        public let type: String
        public let domain: String
        public init(instance: String, type: String = BonjourServiceName.serviceType,
                    domain: String = BonjourServiceName.localDomain) {
            self.instance = instance
            self.type = type
            self.domain = domain
        }
    }

    /// 若 `host` 是 `<instance>._smb._tcp.local[.]` 形式，返回其 DNS-SD 引用；否则 nil。
    ///
    /// 判定基于大小写不敏感的固定后缀，实例名本身保留原始大小写（Bonjour 实例名大小写
    /// 有意义，匹配由 DNS-SD 负责）。普通主机名、IP（含 IPv6 字面量）一律返回 nil。
    public static func reference(for host: String) -> Reference? {
        var name = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("[") && name.hasSuffix("]") { return nil }
        if name.hasSuffix(".") { name.removeLast() }
        guard !name.isEmpty else { return nil }
        let suffix = ".\(serviceType).\(localDomain)"
        guard name.lowercased().hasSuffix(suffix), name.count > suffix.count else { return nil }
        let instance = String(name.dropLast(suffix.count))
        guard !instance.isEmpty else { return nil }
        return Reference(instance: instance)
    }
}

/// DNS-SD SRV 解析：把 Bonjour 服务实例名解析为其目标主机名。
///
/// 只做单播查询（经 `mDNSResponder`），不监听、不扫描、不注册服务；不缓存结果
/// （每次探测都在同一轮预算内重新解析，避免拿到已失效的目标）。
public struct BonjourServiceResolver: Sendable {
    public init() {}

    /// 解析 SRV 目标主机名（如 `DX4600.local.`）。失败、超时或取消时返回 nil。
    public func targetHost(for reference: BonjourServiceName.Reference,
                           timeoutMilliseconds: Int) async -> String? {
        guard timeoutMilliseconds > 0 else { return nil }
        let attempt = BonjourResolveAttempt(reference: reference,
                                            milliseconds: min(timeoutMilliseconds, 5000))
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                attempt.start { continuation.resume(returning: $0) }
            }
        } onCancel: {
            attempt.finish(nil)
        }
    }

    /// 供同步调用点（CLI 子进程内探测）使用的阻塞包装：不占协作线程池。
    public func targetHostBlocking(for reference: BonjourServiceName.Reference,
                                   timeoutMilliseconds: Int) -> String? {
        guard timeoutMilliseconds > 0 else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        let box = BlockingResultBox()
        DispatchQueue.global(qos: .userInitiated).async {
            let attempt = BonjourResolveAttempt(reference: reference,
                                                milliseconds: min(timeoutMilliseconds, 5000))
            attempt.start { value in
                box.set(value)
                semaphore.signal()
            }
        }
        guard semaphore.wait(timeout: .now() + .milliseconds(timeoutMilliseconds)) == .success else {
            return nil
        }
        return box.value
    }

    /// 若 `host` 是 Bonjour 实例名则解析出目标主机名；否则原样返回。
    ///
    /// 解析失败时返回 nil——不得回退到 `getaddrinfo(实例名)`，那正是本缺陷的来源。
    public func resolveIfNeeded(host: String, timeoutMilliseconds: Int) async -> String? {
        guard let reference = BonjourServiceName.reference(for: host) else { return host }
        return await targetHost(for: reference, timeoutMilliseconds: timeoutMilliseconds)
    }
}

private final class BlockingResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    func set(_ value: String?) { lock.withLock { stored = value } }
    var value: String? { lock.withLock { stored } }
}

/// 一次 DNS-SD 解析；回调、socket 事件与超时共用一个队列，锁保证只完成一次。
private final class BonjourResolveAttempt: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "org.automnt.bonjour-resolve")
    private let reference: BonjourServiceName.Reference
    private let milliseconds: Int
    private var continuation: ((String?) -> Void)?
    private var finished = false
    private var serviceRef: DNSServiceRef?
    private var source: DispatchSourceRead?
    private var timer: DispatchSourceTimer?

    init(reference: BonjourServiceName.Reference, milliseconds: Int) {
        self.reference = reference
        self.milliseconds = milliseconds
    }

    func start(_ continuation: @escaping (String?) -> Void) {
        let early = lock.withLock { () -> Bool in
            if finished { return true }
            self.continuation = continuation
            return false
        }
        if early { continuation(nil); return }
        queue.async { [self] in run() }
    }

    private func run() {
        guard !lock.withLock({ finished }) else { return }
        var ref: DNSServiceRef?
        let context = Unmanaged.passUnretained(self).toOpaque()
        let error = DNSServiceResolve(&ref, 0, UInt32(kDNSServiceInterfaceIndexAny),
                                      reference.instance, reference.type, reference.domain,
                                      { _, _, _, errorCode, _, hostTarget, _, _, _, context in
            guard let context else { return }
            let attempt = Unmanaged<BonjourResolveAttempt>.fromOpaque(context).takeUnretainedValue()
            guard errorCode == kDNSServiceErr_NoError, let hostTarget else {
                attempt.finish(nil)
                return
            }
            attempt.finish(String(cString: hostTarget))
        }, context)
        guard error == kDNSServiceErr_NoError, let ref else {
            finish(nil)
            return
        }
        let fileDescriptor = DNSServiceRefSockFD(ref)
        guard fileDescriptor >= 0 else {
            DNSServiceRefDeallocate(ref)
            finish(nil)
            return
        }
        serviceRef = ref
        let readSource = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        readSource.setEventHandler { [self] in
            guard let serviceRef else { return }
            if DNSServiceProcessResult(serviceRef) != kDNSServiceErr_NoError { finish(nil) }
        }
        source = readSource
        readSource.resume()

        let timeout = DispatchSource.makeTimerSource(queue: queue)
        timer = timeout
        timeout.schedule(deadline: .now() + .milliseconds(milliseconds))
        timeout.setEventHandler { [self] in finish(nil) }
        timeout.resume()
    }

    func finish(_ target: String?) {
        let completion = lock.withLock { () -> ((String?) -> Void)? in
            guard !finished else { return nil }
            finished = true
            let pending = continuation
            continuation = nil
            return pending
        }
        guard let completion else { return }
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            source?.cancel()
            source = nil
            if let serviceRef {
                DNSServiceRefDeallocate(serviceRef)
                self.serviceRef = nil
            }
        }
        completion(target)
    }
}
