import Foundation
import Darwin
import AutomntCore

/// Read-only probe. A registered but idle legacy job can still respond to events.
public enum LegacyServicePresence {
    public static func inspect() -> LaunchAgentPresence {
        inspect(label: "com.user.automnt")
    }

    public static func inspectBaseline() -> LaunchAgentPresence {
        inspect(label: "org.automnt.automnt.baseline")
    }

    public static func inspectRecovery() -> LaunchAgentPresence {
        inspect(label: "org.automnt.automnt.recovery")
    }

    public static func inspect(label: String) -> LaunchAgentPresence {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("automnt-service-probe-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
            attributes: [.posixPermissions: 0o600]) else { return .unknown }
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["print", "gui/\(getuid())/\(label)"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = handle
            try process.run()
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while process.isRunning && ContinuousClock.now < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            let timedOut = process.isRunning
            if timedOut {
                process.terminate()
                let stopDeadline = ContinuousClock.now.advanced(by: .milliseconds(200))
                while process.isRunning && ContinuousClock.now < stopDeadline {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
                let killDeadline = ContinuousClock.now.advanced(by: .milliseconds(200))
                while process.isRunning && ContinuousClock.now < killDeadline {
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }
            let stopped = !process.isRunning
            guard stopped else { return .unknown }
            let data = try PrivateAtomicFile.read(url, maximumBytes: 65_536)
            return LaunchAgentPresence.classify(status: process.terminationStatus,
                timedOut: timedOut, processStopped: stopped,
                standardError: String(decoding: data, as: UTF8.self), serviceLabel: label)
        } catch { return .unknown }
    }
}
