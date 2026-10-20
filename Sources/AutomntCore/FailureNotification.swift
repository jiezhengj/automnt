import Foundation

/// Notification payload contains counts and recovery guidance, never target metadata.
public struct FailureNotification: Codable, Equatable, Sendable {
    public let count: Int
    public init?(failed: Set<String>, recovered: Set<String>, eligible: Set<String>) {
        let remaining = failed.subtracting(recovered).intersection(eligible)
        guard !remaining.isEmpty else { return nil }
        count = remaining.count
    }

    public func text(english: Bool) -> (title: String, subtitle: String, message: String) {
        if english {
            return ("automnt: Mounts Not Automatically Restored", "Automatic recovery incomplete",
                    "\(count) shared folder(s) could not be restored automatically. Open automnt configuration and choose \"Remount now\".")
        }
        return ("automnt：挂载未自动恢复", "自动恢复未完成",
                "\(count) 个共享文件夹未能自动恢复。请打开 automnt 配置并选择“立即重新挂载”。")
    }
}
