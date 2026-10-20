import Foundation
import Darwin
import AppKit
import UserNotifications
import AutomntCore

/// Delivery identity of the process that owns the GUI notification channel.
///
/// `UNUserNotificationCenter.current()` raises an uncaught `NSException`
/// (`bundleProxyForCurrentProcess is nil`) in a process whose bundle identity cannot be
/// resolved, for example an executable placed in `Contents/Helpers` or
/// `Contents/Library/LoginItems`. Measured behavior:
/// `Contents/MacOS/Automnt` and `Contents/MacOS/AutomntHelper` resolve to the app bundle,
/// while `Contents/Helpers/AutomntHelper` resolves to nil and aborts with exit 134.
///
/// Every entry point that can run inside a helper must therefore ask this type first and
/// must never touch `UNUserNotificationCenter` when the answer is negative.
public enum NotificationBundleIdentity {
    /// The single app bundle identity that owns Automnt notifications.
    public static let applicationBundleIdentifier = "org.automnt.automnt"

    public enum Role: Equatable, Sendable {
        case deliverable
        case missingIdentity
        case foreignIdentity(String)
    }

    public static func role(of bundle: Bundle = .main) -> Role {
        guard let identifier = bundle.bundleIdentifier, !identifier.isEmpty else { return .missingIdentity }
        return identifier == applicationBundleIdentifier ? .deliverable : .foreignIdentity(identifier)
    }

    /// True only for the Automnt app identity. Callers must treat every other answer as
    /// "no notification capability here" instead of probing the system framework.
    public static func isDeliverable(_ bundle: Bundle = .main) -> Bool {
        role(of: bundle) == .deliverable
    }

    /// `Contents/MacOS/<CFBundleExecutable>` of the app bundle, if it is declared and executable.
    public static func applicationExecutable(in bundle: Bundle) -> URL? {
        guard let name = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String, !name.isEmpty else {
            return nil
        }
        let candidate = bundle.bundleURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(name)
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else { return nil }
        return candidate
    }
}

/// Exit codes of the `--deliver-notification` child. The parent reports exactly what the
/// identified app process reported; other codes, timeouts and launch failures are `failed`.
public enum NotificationExitCode {
    public static let delivered: Int32 = 0
    public static let suppressedForeground: Int32 = 3
    public static let denied: Int32 = 4
    public static let unavailable: Int32 = 5
    public static let failed: Int32 = 6

    public static func child(for delivery: NotificationDelivery) -> Int32 {
        switch delivery {
        case .delivered: return delivered
        case .suppressedForeground: return suppressedForeground
        case .denied: return denied
        case .unavailable: return unavailable
        case .failed: return failed
        }
    }

    public static func delivery(for status: Int32) -> NotificationDelivery {
        switch status {
        case delivered: return .delivered
        case suppressedForeground: return .suppressedForeground
        case denied: return .denied
        case unavailable: return .unavailable
        default: return .failed
        }
    }
}

/// Arguments of the bounded child that delivers on behalf of the app identity.
public struct NotificationDeliveryRequest: Equatable, Sendable {
    public static let flag = "--deliver-notification"
    public static let countFlag = "--count"
    public static let soundFlag = "--sound"
    /// Upper bound for one delivery count. Prevents absurd payloads from an external caller.
    public static let maximumCount = 10_000

    public let count: Int
    public let soundEnabled: Bool
    public init(count: Int, soundEnabled: Bool) {
        self.count = min(max(count, 1), Self.maximumCount)
        self.soundEnabled = soundEnabled
    }

    public var childArguments: [String] {
        var arguments = [Self.flag, Self.countFlag, String(count)]
        if soundEnabled { arguments.append(Self.soundFlag) }
        return arguments
    }
}

/// What the current process's command line asks for.
///
/// "Is this a delivery invocation?" and "are its arguments usable?" are deliberately two
/// separate answers. A delivery invocation must always exit within budget, so a malformed one
/// reports `malformedArguments` and the caller exits with the failure code; it must never fall
/// through to the resident GUI path. (DEF-2: a failable parser that returned nil on a bad
/// `--count` let the app start its normal window and stay alive.)
public enum NotificationDeliveryInvocation: Equatable, Sendable {
    /// No `--deliver-notification` in argv: an ordinary app launch.
    case notRequested
    /// Delivery was requested with usable arguments.
    case request(NotificationDeliveryRequest)
    /// Delivery was requested but the arguments are unusable. Still a delivery invocation:
    /// the caller must exit with `NotificationExitCode.failed` and a redacted diagnostic.
    case malformedArguments

    public init(arguments: [String]) {
        guard arguments.contains(NotificationDeliveryRequest.flag) else {
            self = .notRequested
            return
        }
        let countPrefix = NotificationDeliveryRequest.countFlag + "="
        var count = 1
        var sound = false
        var sawCount = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case NotificationDeliveryRequest.countFlag:
                // A repeated `--count` is ambiguous rather than "last one wins".
                guard !sawCount else { self = .malformedArguments; return }
                sawCount = true
                index += 1
                guard index < arguments.count, let parsed = Self.validCount(arguments[index]) else {
                    self = .malformedArguments
                    return
                }
                count = parsed
            case NotificationDeliveryRequest.soundFlag:
                sound = true
            default:
                // `--count=<value>` is accepted as an explicit alternative to the space
                // separated form; an unusable value is malformed, never a silent count=1.
                if argument.hasPrefix(countPrefix) {
                    guard !sawCount else { self = .malformedArguments; return }
                    sawCount = true
                    guard let parsed = Self.validCount(String(argument.dropFirst(countPrefix.count))) else {
                        self = .malformedArguments
                        return
                    }
                    count = parsed
                }
                // Every other value is ignored. The parent only ever sends canonical
                // arguments, and leniency here cannot let a delivery invocation reach the
                // GUI path; macOS may also inject `-psn_0_...` when an app is opened.
            }
            index += 1
        }
        self = .request(NotificationDeliveryRequest(count: count, soundEnabled: sound))
    }

    /// Positive, in-range integer or nil. Shared by both `--count` spellings.
    private static func validCount(_ value: String) -> Int? {
        guard let parsed = Int(value),
              parsed > 0, parsed <= NotificationDeliveryRequest.maximumCount else { return nil }
        return parsed
    }

    /// Redacted outcome for a delivery invocation whose arguments are unusable.
    public static let malformedOutcome = NotificationDispatchOutcome(delivery: .failed,
                                                                     reason: .malformedArguments)
}

/// One bounded delivery attempt. Injected in tests so no real notification is ever posted.
public protocol NotificationDeliveryExecutor: Sendable {
    func deliver(_ notification: FailureNotification, soundEnabled: Bool) async -> NotificationDelivery
}

/// Launches the app's own main executable as a short-lived child and maps its exit code.
///
/// The child is the only process allowed to talk to `UNUserNotificationCenter`; if the app is
/// already running, LaunchServices may route the request to that instance, so the parent still
/// waits for this child's real exit code and never reports a delivery it did not observe.
public struct AppNotificationDelivery: NotificationDeliveryExecutor {
    private let executable: URL?
    private let timeout: Duration
    private let terminationGrace: Duration

    public init(applicationBundle: Bundle = .main,
                timeout: Duration = .seconds(8),
                terminationGrace: Duration = .milliseconds(500)) {
        executable = NotificationBundleIdentity.applicationExecutable(in: applicationBundle)
        self.timeout = timeout
        self.terminationGrace = terminationGrace
    }

    /// Test seam: any bundle URL; a bundle without a declared executable fails closed.
    public init(applicationURL: URL,
                timeout: Duration = .seconds(8),
                terminationGrace: Duration = .milliseconds(500)) {
        executable = Bundle(url: applicationURL).flatMap { NotificationBundleIdentity.applicationExecutable(in: $0) }
        self.timeout = timeout
        self.terminationGrace = terminationGrace
    }

    public func deliver(_ notification: FailureNotification, soundEnabled: Bool) async -> NotificationDelivery {
        let request = NotificationDeliveryRequest(count: notification.count, soundEnabled: soundEnabled)
        // Blocking process control stays off the cooperative pool; the helper is short-lived.
        return await Task.detached { Self.runChild(executable: executable, request: request,
            timeout: timeout, terminationGrace: terminationGrace) }.value
    }

    private static func runChild(executable: URL?, request: NotificationDeliveryRequest,
                                 timeout: Duration, terminationGrace: Duration) -> NotificationDelivery {
        guard let executable else { return .failed }
        let process = Process()
        process.executableURL = executable
        process.arguments = request.childArguments
        // Allowlist only: no caller secrets, credentials or target data travel through env.
        process.environment = restrictedEnvironment()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failed }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while process.isRunning, ContinuousClock.now < deadline {
            usleep(20_000)
        }
        guard process.isRunning else {
            process.waitUntilExit()
            return NotificationExitCode.delivery(for: process.terminationStatus)
        }
        process.terminate()
        let graceDeadline = ContinuousClock.now.advanced(by: terminationGrace)
        while process.isRunning, ContinuousClock.now < graceDeadline {
            usleep(20_000)
        }
        if process.isRunning {
            _ = kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
        // A child that had to be stopped never proves a delivery.
        return .failed
    }

    private static func restrictedEnvironment() -> [String: String] {
        let current = ProcessInfo.processInfo.environment
        var environment: [String: String] = [:]
        for key in ["HOME", "TMPDIR", "LANG"] {
            if let value = current[key] { environment[key] = value }
        }
        return environment
    }
}

/// The only place a helper's frontmost-app question is answered.
public enum ApplicationForegroundQuery {
    /// nil means the query could not identify a frontmost application. Unknown is never
    /// treated as background, so the caller suppresses instead of delivering.
    public static func current() -> Bool? {
        NSWorkspace.shared.frontmostApplication
            .map { $0.bundleIdentifier == NotificationBundleIdentity.applicationBundleIdentifier }
    }
}

/// Machine-readable cause of a delivery result. Never user-facing copy, never carries
/// target metadata; it exists so the exit-code mapping stays auditable.
public enum NotificationDispatchReason: String, Codable, Sendable {
    case posted
    case foregroundSuppressed
    case frontmostApplicationUnknown
    case permissionDenied
    case permissionNotDetermined
    case identityMissing
    case notificationCenterRejected
    case timedOut
    /// `--deliver-notification` was given with unusable arguments.
    case malformedArguments
}

/// The child side of the channel: runs inside the app main executable and reports the
/// observed result as an exit code.
public struct NotificationDispatchOutcome: Equatable, Sendable {
    public let delivery: NotificationDelivery
    public let reason: NotificationDispatchReason
    public var exitCode: Int32 { NotificationExitCode.child(for: delivery) }
    public init(delivery: NotificationDelivery, reason: NotificationDispatchReason) {
        self.delivery = delivery
        self.reason = reason
    }
}

public enum AppNotificationDispatcher {
    /// Bounded budget for one child delivery. Never unbounded, never a poll.
    public static let defaultDeadline: Duration = .seconds(8)

    /// Safe to call from any process: without the app identity this returns `unavailable`
    /// before any system notification API is touched.
    public static func dispatch(count: Int, soundEnabled: Bool, bundle: Bundle = .main,
                                deadline: Duration = defaultDeadline) async -> NotificationDispatchOutcome {
        guard NotificationBundleIdentity.isDeliverable(bundle) else {
            return NotificationDispatchOutcome(delivery: .unavailable, reason: .identityMissing)
        }
        let work = Task { await performDelivery(count: count, soundEnabled: soundEnabled) }
        let result = await withTaskGroup(of: NotificationDispatchOutcome?.self) { group in
            group.addTask { await work.value }
            group.addTask {
                try? await Task.sleep(for: deadline)
                return NotificationDispatchOutcome(delivery: .failed, reason: .timedOut)
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        work.cancel()
        // A watchdog that fires first cannot have observed a delivery.
        return result ?? NotificationDispatchOutcome(delivery: .failed, reason: .timedOut)
    }

    private static func performDelivery(count: Int, soundEnabled: Bool) async -> NotificationDispatchOutcome {
        // Re-checked in the delivering process; the identity above is the guard that matters.
        guard let foreground = ApplicationForegroundQuery.current() else {
            return NotificationDispatchOutcome(delivery: .unavailable, reason: .frontmostApplicationUnknown)
        }
        guard !foreground else {
            return NotificationDispatchOutcome(delivery: .suppressedForeground, reason: .foregroundSuppressed)
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .denied:
            return NotificationDispatchOutcome(delivery: .denied, reason: .permissionDenied)
        case .authorized, .provisional:
            break
        default:
            return NotificationDispatchOutcome(delivery: .unavailable, reason: .permissionNotDetermined)
        }
        let text = NotificationCopy.text(count: count, language: Locale.preferredLanguages.first ?? "en")
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.message
        if soundEnabled, settings.soundSetting == .enabled { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            // Accepted by the notification center, not proof the user saw it.
            try await center.add(request)
            return NotificationDispatchOutcome(delivery: .delivered, reason: .posted)
        } catch {
            return NotificationDispatchOutcome(delivery: .failed, reason: .notificationCenterRejected)
        }
    }
}

/// What the process that owns this command line must do next.
///
/// This is the decision DEF-2/DEF-5 both hinge on: the app main executable may start its GUI
/// **only** when the command line carries no delivery flag. The decision lives here, with test
/// coverage, so that "malformed delivery arguments must exit" cannot silently regress into
/// "fall through to the resident window" — a regression that only a real device run could
/// otherwise catch, because the GUI target is outside the SwiftPM test target.
///
/// The app entry point must only translate this value into an action:
/// `startGUI` → continue normal startup; `exitWithOutcome` → print the diagnostic, then exit.
public enum NotificationLaunchDisposition: Equatable, Sendable {
    case startGUI
    case exitWithOutcome(NotificationDispatchOutcome, count: Int)
}

/// Synchronous entry for the app main executable.
///
/// Blocks the calling thread for at most `budget` so the short delivery process can exit even
/// when the notification center never answers. Must not be called from a helper, which has no
/// notification identity.
public enum NotificationDeliveryEntry {
    /// Pure routing decision. `execute` is called only for a valid delivery request and is
    /// injected so tests never post a real notification.
    ///
    /// Guarantee under test: a command line containing `--deliver-notification` never yields
    /// `.startGUI`, whatever its arguments look like.
    public static func disposition(for arguments: [String],
                                   execute: (NotificationDeliveryRequest) -> NotificationDispatchOutcome)
        -> NotificationLaunchDisposition {
        switch NotificationDeliveryInvocation(arguments: arguments) {
        case .notRequested:
            return .startGUI
        case .malformedArguments:
            // Still a delivery invocation: bounded failure exit, never the GUI path.
            return .exitWithOutcome(NotificationDeliveryInvocation.malformedOutcome, count: 1)
        case .request(let request):
            return .exitWithOutcome(execute(request), count: request.count)
        }
    }

    /// Real decision used by the app entry point.
    public static func disposition(for arguments: [String]) -> NotificationLaunchDisposition {
        disposition(for: arguments) { run($0) }
    }

    public static func run(_ request: NotificationDeliveryRequest,
                           budget: Duration = .seconds(10)) -> NotificationDispatchOutcome {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var outcome = NotificationDispatchOutcome(delivery: .failed, reason: .timedOut)
        Task.detached {
            outcome = await AppNotificationDispatcher.dispatch(count: request.count,
                soundEnabled: request.soundEnabled)
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + budget.timeInterval) == .success else {
            return NotificationDispatchOutcome(delivery: .failed, reason: .timedOut)
        }
        return outcome
    }

    /// Bounded diagnostic line for launchd logs: result and cause, never target metadata.
    public static func diagnosticLine(_ outcome: NotificationDispatchOutcome, count: Int) -> String {
        "automnt notification delivery=\(outcome.delivery.rawValue) reason=\(outcome.reason.rawValue) count=\(max(count, 1))\n"
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

/// Structured, credential-free record of the last delivery attempt. This is not business
/// configuration and never rewrites it.
public struct NotificationDeliveryRecord: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public let delivery: NotificationDelivery
    public let count: Int
    public let soundEnabled: Bool
    public let soundPreferenceNeedsRepair: Bool
    public let attemptedAt: Date

    public init(delivery: NotificationDelivery, count: Int, soundEnabled: Bool,
                soundPreferenceNeedsRepair: Bool, attemptedAt: Date = Date()) {
        self.delivery = delivery
        self.count = max(count, 1)
        self.soundEnabled = soundEnabled
        self.soundPreferenceNeedsRepair = soundPreferenceNeedsRepair
        self.attemptedAt = attemptedAt
    }
}

public struct NotificationDeliveryRecordStore: Sendable {
    public let directory: URL
    public init(authorizedDirectory: URL) { directory = authorizedDirectory }
    private var url: URL { directory.appendingPathComponent("notification-delivery.plist") }

    public func read() -> NotificationDeliveryRecord? {
        guard let data = try? PrivateAtomicFile.read(url) else { return nil }
        guard let record = try? PropertyListDecoder().decode(NotificationDeliveryRecord.self, from: data),
              record.schemaVersion == 1 else { return nil }
        return record
    }

    public func save(_ record: NotificationDeliveryRecord) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try PrivateAtomicFile.replace(encoder.encode(record), at: url)
    }
}
