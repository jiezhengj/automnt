import Foundation

/// SMB2 `NEGOTIATE` 请求帧与响应判定（CLI 与 Platform 共用的唯一实现）。
///
/// 用途：可达性探测的证伪。TCP 连接成功不足以证明对端是 SMB 服务器——本机的
/// TUN/fake-ip 代理会接受任意地址的连接并立刻关闭。因此探测在 TCP 就绪后发送一次
/// `NEGOTIATE`，只要求收到合法的 SMB2 响应头（`\xfeSMB`）即认定可达。
///
/// 契约：
/// - 不认证、不建立会话、不写任何状态；请求后关闭连接。
/// - 判定只看响应头魔数，不解析 body、不校验 status（`STATUS_INVALID_PARAMETER`
///   也说明对端是真 SMB 服务）。
/// - 报文极小且固定，禁止在此处加入根据配置变化的内容。
public enum SMB2NegotiateFrame {
    /// SMB2 协议魔数（响应头前四字节）。
    public static let responseMagic = Data([0xFE, 0x53, 0x4D, 0x42])

    /// NetBIOS session service 头长度。
    public static let netBIOSHeaderLength = 4

    /// 请求支持的方言：SMB 2.0.2 / 2.1 / 3.0 / 3.1.1。
    private static let dialects: [UInt16] = [0x0202, 0x0210, 0x0300, 0x0311]

    /// 完整的一帧：NetBIOS 长度前缀 + SMB2 头 + NEGOTIATE body。
    public static func request() -> Data {
        var message = Data([0xFE, 0x53, 0x4D, 0x42])   // ProtocolId
        message.append(contentsOf: littleEndian(UInt16(64)))   // StructureSize
        message.append(contentsOf: littleEndian(UInt16(1)))    // CreditCharge
        message.append(contentsOf: littleEndian(UInt32(0)))    // Status
        message.append(contentsOf: littleEndian(UInt16(0)))    // Command = NEGOTIATE
        message.append(contentsOf: littleEndian(UInt16(1)))    // CreditRequest
        message.append(contentsOf: littleEndian(UInt32(0)))    // Flags
        message.append(contentsOf: littleEndian(UInt32(0)))    // NextCommand
        message.append(contentsOf: littleEndian(UInt64(0)))    // MessageId
        message.append(contentsOf: littleEndian(UInt32(0xFEFF)))   // ProcessId
        message.append(contentsOf: littleEndian(UInt32(0)))    // TreeId
        message.append(contentsOf: littleEndian(UInt64(0)))    // SessionId
        message.append(contentsOf: [UInt8](repeating: 0, count: 16))   // Signature

        var body = Data()
        body.append(contentsOf: littleEndian(UInt16(36)))      // StructureSize
        body.append(contentsOf: littleEndian(UInt16(dialects.count)))
        body.append(contentsOf: littleEndian(UInt16(1)))       // SecurityMode = signing enabled
        body.append(contentsOf: littleEndian(UInt16(0)))       // Reserved
        body.append(contentsOf: littleEndian(UInt32(0)))       // Capabilities
        body.append(contentsOf: [UInt8](repeating: 0, count: 16))   // ClientGuid
        body.append(contentsOf: [UInt8](repeating: 0, count: 8))    // ClientStartTime
        for dialect in dialects { body.append(contentsOf: littleEndian(dialect)) }

        let payload = message + body
        return netBIOSHeader(length: payload.count) + payload
    }

    /// 响应是否以 SMB2 魔数开头（允许只有魔数四字节）。
    public static func isResponseHeader(_ data: Data) -> Bool {
        data.count >= responseMagic.count && Data(data.prefix(responseMagic.count)) == responseMagic
    }

    /// NetBIOS session header：`0x00` + 24 位大端长度。
    public static func netBIOSHeader(length: Int) -> Data {
        let value = UInt32(clamping: length) & 0x00FF_FFFF
        return Data([0x00,
                     UInt8((value >> 16) & 0xFF),
                     UInt8((value >> 8) & 0xFF),
                     UInt8(value & 0xFF)])
    }

    /// 解析 NetBIOS 长度前缀；不足四字节时返回 nil。
    public static func payloadLength(fromNetBIOSHeader header: Data) -> Int? {
        guard header.count >= netBIOSHeaderLength else { return nil }
        let bytes = [UInt8](header.prefix(netBIOSHeaderLength))
        return (Int(bytes[1]) << 16) | (Int(bytes[2]) << 8) | Int(bytes[3])
    }

    private static func littleEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }
}
