import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

/// Records executions without ever posting a real notification.
private actor RecordingExecutor: NotificationDeliveryExecutor {
    private(set) var calls: [(count: Int, soundEnabled: Bool)] = []
    private let result: NotificationDelivery
    init(result: NotificationDelivery) { self.result = result }
    func deliver(_ notification: FailureNotification, soundEnabled: Bool) async -> NotificationDelivery {
        calls.append((notification.count, soundEnabled))
        return result
    }
    func recorded() -> [(count: Int, soundEnabled: Bool)] { calls }
}

private func makeFakeApplication(executableScript: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("automnt-notify-\(UUID().uuidString)", isDirectory: true)
    let bundle = root.appendingPathComponent("Fake.app", isDirectory: true)
    let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
    let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
    try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>Fake</string>
    <key>CFBundleIdentifier</key><string>org.automnt.automnt.fake</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    </dict></plist>
    """
    try Data(plist.utf8).write(to: contents.appendingPathComponent("Info.plist"))
    let executable = macOS.appendingPathComponent("Fake")
    try Data("#!/bin/sh\n\(executableScript)\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    return bundle
}

struct NotificationChannelTests {
    @Test func exitCodesMapToDeliveryResults() {
        let pairs: [(NotificationDelivery, Int32)] = [
            (.delivered, 0), (.suppressedForeground, 3), (.denied, 4), (.unavailable, 5), (.failed, 6)
        ]
        for (delivery, code) in pairs {
            #expect(NotificationExitCode.child(for: delivery) == code)
            #expect(NotificationExitCode.delivery(for: code) == delivery)
        }
        for unexpected: Int32 in [-9, 1, 2, 137, 134] {
            #expect(NotificationExitCode.delivery(for: unexpected) == .failed)
        }
    }

    @Test func deliveryInvocationIsSeparatedFromArgumentValidity() {
        let flag = NotificationDeliveryRequest.flag
        let countFlag = NotificationDeliveryRequest.countFlag
        let soundFlag = NotificationDeliveryRequest.soundFlag
        func invocation(_ arguments: [String]) -> NotificationDeliveryInvocation {
            NotificationDeliveryInvocation(arguments: arguments)
        }

        // Arguments without the flag are an ordinary app launch, not a delivery invocation.
        #expect(invocation(["/Applications/Automnt.app/Contents/MacOS/Automnt"]) == .notRequested)
        #expect(invocation(["--some-other-flag"]) == .notRequested)
        #expect(invocation([]) == .notRequested)
        #expect(invocation([countFlag, "3"]) == .notRequested)

        // Valid invocations keep their existing meaning.
        #expect(invocation([flag]) == .request(NotificationDeliveryRequest(count: 1, soundEnabled: false)))
        #expect(invocation([flag, soundFlag]) == .request(NotificationDeliveryRequest(count: 1, soundEnabled: true)))
        #expect(invocation([flag, countFlag, "3", soundFlag])
            == .request(NotificationDeliveryRequest(count: 3, soundEnabled: true)))
        // Unrelated injected values do not invalidate a usable invocation.
        #expect(invocation([flag, "-psn_0_12345", countFlag, "2"])
            == .request(NotificationDeliveryRequest(count: 2, soundEnabled: false)))

        // Every malformed form stays a delivery invocation: it must exit, never start the GUI.
        for arguments in [[flag, countFlag, "abc"],
                          [flag, countFlag, "0"],
                          [flag, countFlag, "-1"],
                          [flag, countFlag, "99999999"],
                          [flag, countFlag],
                          [flag, countFlag, "3.5"],
                          [flag, countFlag, "1", countFlag, "2"]] {
            #expect(invocation(arguments) == .malformedArguments, "\(arguments) must be malformed, not skipped")
        }
        #expect(NotificationDeliveryInvocation.malformedOutcome.delivery == .failed)
        #expect(NotificationDeliveryInvocation.malformedOutcome.exitCode == NotificationExitCode.failed)
        #expect(NotificationDeliveryInvocation.malformedOutcome.reason == .malformedArguments)

        // DEF-6: the `--count=<value>` spelling is recognised, not silently ignored.
        #expect(invocation([flag, "\(countFlag)=5"])
            == .request(NotificationDeliveryRequest(count: 5, soundEnabled: false)))
        #expect(invocation([flag, "\(countFlag)=1", soundFlag])
            == .request(NotificationDeliveryRequest(count: 1, soundEnabled: true)))
        for value in ["abc", "0", "-1", "99999999", "", "3.5"] {
            #expect(invocation([flag, "\(countFlag)=\(value)"]) == .malformedArguments,
                    "--count=\(value) must be malformed")
        }
        // Mixing the two spellings is still ambiguous, in either order.
        #expect(invocation([flag, countFlag, "2", "\(countFlag)=3"]) == .malformedArguments)
        #expect(invocation([flag, "\(countFlag)=2", countFlag, "3"]) == .malformedArguments)
    }

    /// DEF-5: the app entry point's routing decision must be structurally testable, because the
    /// GUI target is outside this test target. The invariant is absolute: any command line that
    /// asks for delivery exits, so it can never start the resident GUI.
    @Test func deliveryCommandLinesNeverDisposeToStartGUI() {
        let flag = NotificationDeliveryRequest.flag
        let countFlag = NotificationDeliveryRequest.countFlag
        let soundFlag = NotificationDeliveryRequest.soundFlag

        // A recorder standing in for the real delivery so no notification is ever posted.
        final class Executor: @unchecked Sendable {
            var requests: [NotificationDeliveryRequest] = []
            func execute(_ request: NotificationDeliveryRequest) -> NotificationDispatchOutcome {
                requests.append(request)
                return NotificationDispatchOutcome(delivery: .delivered, reason: .posted)
            }
        }

        func disposition(_ arguments: [String], executor: Executor) -> NotificationLaunchDisposition {
            NotificationDeliveryEntry.disposition(for: arguments) { executor.execute($0) }
        }

        // Ordinary launches keep starting the GUI.
        for arguments in [[], ["/Applications/Automnt.app/Contents/MacOS/Automnt"], ["-psn_0_12345"],
                          [countFlag, "3"], ["--some-other-flag"], ["--sound"]] {
            #expect(disposition(arguments, executor: Executor()) == .startGUI,
                    "\(arguments) must start the GUI")
        }

        // Every delivery command line — valid or malformed — must exit with a bounded outcome.
        let malformed = [[flag, countFlag, "abc"], [flag, countFlag, "0"], [flag, countFlag, "-1"],
                         [flag, countFlag, "99999999"], [flag, countFlag], [flag, countFlag, "3.5"],
                         [flag, "\(countFlag)=abc"], [flag, "\(countFlag)=0"], [flag, "\(countFlag)="],
                         [flag, countFlag, "1", countFlag, "2"]]
        for arguments in malformed {
            let decision = disposition(arguments, executor: Executor())
            guard case .exitWithOutcome(let outcome, let count) = decision else {
                Issue.record("\(arguments) must exit, never start the GUI")
                continue
            }
            #expect(outcome.delivery == .failed, "\(arguments) must report a failure result")
            #expect(outcome.exitCode == NotificationExitCode.failed)
            #expect(outcome.reason == .malformedArguments)
            #expect(count == 1)
        }

        // Valid requests exit through the executor, and are not a failure-code fallback.
        let validExecutor = Executor()
        let valid = disposition([flag, countFlag, "3", soundFlag], executor: validExecutor)
        guard case .exitWithOutcome(let validOutcome, let validCount) = valid else {
            Issue.record("a valid delivery request must exit")
            return
        }
        #expect(validCount == 3)
        #expect(validOutcome.reason == .posted)
        #expect(validOutcome.exitCode == NotificationExitCode.delivered)
        #expect(validExecutor.requests == [NotificationDeliveryRequest(count: 3, soundEnabled: true)])

        // Parity: every disposition that starts the GUI carries no delivery flag at all.
        for arguments in malformed + [[flag], [flag, countFlag, "3"], [flag, "\(countFlag)=7"]] {
            #expect(disposition(arguments, executor: Executor()) != .startGUI, "\(arguments)")
        }
    }

    /// The real (non-injected) decision for a malformed command line must still be a failure
    /// exit, and the real path for an ordinary launch must still be `.startGUI`.
    @Test func realDispositionKeepsBoundedFailureForMalformedArguments() {
        #expect(NotificationDeliveryEntry.disposition(for: ["/Applications/Automnt.app/Contents/MacOS/Automnt"])
            == .startGUI)
        #expect(NotificationDeliveryEntry.disposition(for: []) == .startGUI)
        let decision = NotificationDeliveryEntry.disposition(
            for: [NotificationDeliveryRequest.flag, NotificationDeliveryRequest.countFlag, "abc"])
        guard case .exitWithOutcome(let outcome, _) = decision else {
            Issue.record("malformed delivery arguments must exit")
            return
        }
        #expect(outcome.exitCode == NotificationExitCode.failed)
    }

    @Test func canonicalChildArgumentsRoundTripThroughTheInvocationParser() {
        for count in [1, 2, 3, 10_000] {
            for sound in [true, false] {
                let request = NotificationDeliveryRequest(count: count, soundEnabled: sound)
                #expect(NotificationDeliveryInvocation(arguments: request.childArguments) == .request(request))
            }
        }
        #expect(NotificationDeliveryRequest(count: 0, soundEnabled: false).count == 1)
        #expect(NotificationDeliveryRequest(count: -5, soundEnabled: false).count == 1)
        #expect(NotificationDeliveryRequest(count: 999_999_999, soundEnabled: false).count
            == NotificationDeliveryRequest.maximumCount)
    }

    @Test func missingOrForeignBundleIdentityIsNeverDeliverable() throws {
        #expect(NotificationBundleIdentity.role(of: .main) != .deliverable)
        let foundation = try #require(Bundle(path: "/System/Library/Frameworks/Foundation.framework"))
        #expect(NotificationBundleIdentity.role(of: foundation) == .foreignIdentity("com.apple.Foundation"))
        #expect(!NotificationBundleIdentity.isDeliverable(foundation))

        // A bundle whose Info.plist declares no CFBundleIdentifier must read as missing.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contents = root.appendingPathComponent("Empty.bundle/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict></dict></plist>".utf8)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let anonymous = try #require(Bundle(url: root.appendingPathComponent("Empty.bundle")))
        #expect(NotificationBundleIdentity.role(of: anonymous) == .missingIdentity)
        #expect(!NotificationBundleIdentity.isDeliverable(anonymous))
        #expect(NotificationBundleIdentity.applicationExecutable(in: anonymous) == nil)
    }

    @Test func dispatchWithoutIdentityReportsUnavailableAndTouchesNoSystemAPI() async {
        // The test process is not the Automnt app; this path must return before
        // UNUserNotificationCenter is ever referenced.
        let dispatched = await AppNotificationDispatcher.dispatch(count: 2, soundEnabled: true)
        #expect(dispatched.delivery == .unavailable)
        #expect(dispatched.reason == .identityMissing)
        let entry = NotificationDeliveryEntry.run(NotificationDeliveryRequest(count: 1, soundEnabled: false))
        #expect(entry.delivery == .unavailable)
        #expect(entry.reason == .identityMissing)
        let line = NotificationDeliveryEntry.diagnosticLine(entry, count: 1)
        #expect(line.contains("delivery=unavailable"))
        #expect(line.contains("count=1"))
        #expect(!line.contains("smb://") && !line.contains("/Volumes/"))
    }

    @Test func notifierSuppressesWhenForegroundAndWhenUnknown() async {
        let foregroundExecutor = RecordingExecutor(result: .delivered)
        let foregroundNotifier = SystemUserNotifier(soundEnabled: true, foreground: { true },
            executor: foregroundExecutor)
        let notification = FailureNotification(failed: ["a"], recovered: [], eligible: ["a"])!
        #expect(await foregroundNotifier.deliver(notification) == .suppressedForeground)
        #expect(await foregroundExecutor.recorded().isEmpty)

        let unknownExecutor = RecordingExecutor(result: .delivered)
        let unknownNotifier = SystemUserNotifier(soundEnabled: true, foreground: { nil },
            executor: unknownExecutor)
        #expect(await unknownNotifier.deliver(notification) == .unavailable)
        #expect(await unknownExecutor.recorded().isEmpty)

        let backgroundExecutor = RecordingExecutor(result: .denied)
        let backgroundNotifier = SystemUserNotifier(soundEnabled: true, foreground: { false },
            executor: backgroundExecutor)
        #expect(await backgroundNotifier.deliver(notification) == .denied)
        #expect(await backgroundExecutor.recorded().map(\.count) == [1])
        let muted = SystemUserNotifier(soundEnabled: false, foreground: { false },
            executor: backgroundExecutor)
        _ = await muted.deliver(notification)
        #expect(await backgroundExecutor.recorded().map(\.soundEnabled) == [true, false])
    }

    @Test func childExitCodesBecomeDeliveryResults() async throws {
        for (script, expected) in [("exit 0", NotificationDelivery.delivered),
                                   ("exit 3", .suppressedForeground),
                                   ("exit 4", .denied),
                                   ("exit 5", .unavailable),
                                   ("exit 42", .failed)] {
            let bundle = try makeFakeApplication(executableScript: script)
            defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
            let executor = AppNotificationDelivery(applicationURL: bundle, timeout: .seconds(5))
            let result = await executor.deliver(
                FailureNotification(failed: ["a"], recovered: [], eligible: ["a"])!, soundEnabled: false)
            #expect(result == expected)
        }
    }

    @Test func timeoutAndLaunchFailureReportFailedNeverDelivered() async throws {
        let slow = try makeFakeApplication(executableScript: "sleep 30")
        defer { try? FileManager.default.removeItem(at: slow.deletingLastPathComponent()) }
        let executor = AppNotificationDelivery(applicationURL: slow, timeout: .milliseconds(300),
            terminationGrace: .milliseconds(300))
        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            let result = await executor.deliver(
                FailureNotification(failed: ["a"], recovered: [], eligible: ["a"])!, soundEnabled: false)
            #expect(result == .failed)
        }
        #expect(elapsed < .seconds(5))

        // No application bundle at all: no executable, so no delivery can be claimed.
        let missing = AppNotificationDelivery(applicationURL:
            FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        #expect(await missing.deliver(
            FailureNotification(failed: ["a"], recovered: [], eligible: ["a"])!, soundEnabled: true) == .failed)

        // Declared executable that does not exist on disk is also a launch failure.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contents = root.appendingPathComponent("Broken.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("""
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
        <key>CFBundleExecutable</key><string>Missing</string>
        <key>CFBundleIdentifier</key><string>org.automnt.automnt.broken</string>
        </dict></plist>
        """.utf8).write(to: contents.appendingPathComponent("Info.plist"))
        let broken = AppNotificationDelivery(applicationURL: root.appendingPathComponent("Broken.app"))
        #expect(await broken.deliver(
            FailureNotification(failed: ["a"], recovered: [], eligible: ["a"])!, soundEnabled: false) == .failed)
    }

    @Test func deliveryRecordRoundTripsWithoutReplacingConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotificationDeliveryRecordStore(authorizedDirectory: directory)
        #expect(store.read() == nil)
        let record = NotificationDeliveryRecord(delivery: .denied, count: 3, soundEnabled: false,
            soundPreferenceNeedsRepair: true, attemptedAt: Date(timeIntervalSince1970: 1_000))
        try store.save(record)
        #expect(store.read() == record)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("automnt.plist").path))
        try PrivateAtomicFile.replace(Data([0xff]), at: directory.appendingPathComponent("notification-delivery.plist"))
        #expect(store.read() == nil)
    }
}
