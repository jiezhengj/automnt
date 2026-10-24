import Foundation
import Darwin
import os
import AutomntCore
import AutomntPlatform

@main
struct HelperEntry {
    static func main() async {
        // Diagnostic only: one bounded NetFS mount with no credential, proving whether the
        // sandboxed helper can reuse the macOS-held SMB sign-in. Writes nothing.
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--probe-netfs-mount" {
            exit(NetFSMountProbe.run(urlString: CommandLine.arguments[2]))
        }
        if CommandLine.arguments.dropFirst().first == "--probe-shared-container" {
            exit(SharedContainer.probe(arguments: CommandLine.arguments))
        }
        if CommandLine.arguments == [CommandLine.arguments[0], "--check-shared-container"] {
            exit(SharedContainer.check())
        }
        // Diagnostic only: proves the notification channel adapter is safe to call from
        // Contents/Helpers, where the bundle identity is unresolvable. It consumes no
        // notification budget and writes no configuration.
        if CommandLine.arguments.contains(NotificationChannelProbe.flag) {
            await NotificationChannelProbe.run()
            return
        }
        // Diagnostic only: reports whether the sandboxed helper can read the two inputs of
        // the session identity that expires session-scoped eject suppression across a
        // restart. Prints nothing derived from user data and writes no state.
        if CommandLine.arguments == [CommandLine.arguments[0], "--probe-session"] {
            exit(SessionProbe.run())
        }
        // Read-only runtime check: never enters evaluation, acquires an execution
        // lease, registers a service, or writes configuration/observations.
        if CommandLine.arguments == [CommandLine.arguments[0], "--check-directory-authorization"] {
            do {
                let directory = try PermissionStore().internalDirectory()
                withExtendedLifetime(directory) {}
                FileHandle.standardOutput.write(Data("directory-authorization: available\n".utf8))
                return
            } catch {
                FileHandle.standardError.write(Data("directory-authorization: unavailable\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        if CommandLine.arguments == [CommandLine.arguments[0], "--bind-directory-authorization"] {
            do {
                let directory = try PermissionBinding.receiveFromStandardInput()
                withExtendedLifetime(directory) {}
                FileHandle.standardOutput.write(Data("directory-binding: stored\n".utf8))
                return
            } catch {
                let reason = (error as? AutomntIssue)?.rawValue ?? "invalid-input"
                FileHandle.standardError.write(Data("directory-binding: \(reason)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        if CommandLine.arguments == [CommandLine.arguments[0], "--authorize-configuration"] {
            do { try HelperPermissionProbe.receive(); return }
            catch { exit(EXIT_FAILURE) }
        }
        guard CommandLine.arguments.count == 1 else { exit(EXIT_FAILURE) }
        do {
            let directory = try PermissionStore().internalDirectory()
            let executionLease = try HelperExecutionLease(authorizedDirectory: directory.url)
            defer { withExtendedLifetime(executionLease) {} }
            // launchd passes the bundle-relative `BundleProgram` value as argv[0] and the
            // sandbox runs this process with cwd inside its container. Never derive the app
            // bundle from argv[0]; resolve it from the kernel's executable path instead.
            guard let executable = ApplicationBundleLocation.currentExecutableURL(),
                  executable.lastPathComponent == "AutomntHelper",
                  let applicationURL = ApplicationBundleLocation.applicationURL(containingExecutable: executable),
                  let bundle = Bundle(url: applicationURL),
                  bundle.bundleIdentifier == ApplicationBundleLocation.applicationBundleIdentifier else {
                throw AutomntIssue.authorizationRequired
            }
            // The helper must also be launched by the registered job, not by a shell. The
            // fixed signed definition is verified once; readiness then stays a pure check.
            let launchedLabel = HelperBackgroundReadiness.launchedServiceLabel()
            try HelperBackgroundReadiness.verifyLaunchedDefinition(
                applicationURL: applicationURL, launchedServiceLabel: launchedLabel)
            let readiness = HelperBackgroundReadiness(applicationURL: applicationURL,
                launchedServiceLabel: launchedLabel, definitionVerified: true)
            let state = try BackendStateStore(authorizedDirectory: directory.url).read()
            // A worker interrupted before writing leaves a launch intent pending. The
            // evaluation lock is the liveness fence, so a free lock proves repair is safe;
            // otherwise the intent is left untouched and this round fails closed.
            _ = try? WorkerOperationStore(authorizedDirectory: directory.url).abandonPendingForRepair()
            let summary: BackgroundEvaluationSummary
            do {
                summary = try await BackgroundEvaluationTrigger.run(applicationBundle: bundle, directory: directory, expectedState: state,
                    deadline: ContinuousClock.now.advanced(by: .seconds(30)),
                    serviceStatus: { configuration in
                        readiness.status(configuration: configuration, backend: state)
                    })
            } catch {
                // Bounded, secret-free diagnostic: issue and failure kind only.
                Self.logger.error("evaluation failed issue=\(String(describing: (error as? AutomntIssue)?.rawValue ?? "unavailable"), privacy: .public) kind=\(String(describing: type(of: error)), privacy: .public)")
                summary = BackgroundEvaluationSummary(issue: error as? AutomntIssue ?? .signalUnavailable)
            }
            // Current-operation summary is private, structured and contains no credentials.
            try Task.checkCancellation()
            try BackgroundObservationCommit.commit(summary, state: state, directory: directory.url)
            recordFailureNotification(summary: summary, state: state, directory: directory)
            withExtendedLifetime(directory) {}
        } catch {
            // No authorized directory means no fallback persistence or payload logging.
            Self.logger.error("helper exited before evaluation kind=\(String(describing: type(of: error)), privacy: .public)")
            exit(EXIT_FAILURE)
        }
    }

    private static let logger = Logger(subsystem: "org.automnt.automnt", category: "helper")

    /// Consume the shared notice budget, then leave the notice for the resident app.
    ///
    /// The helper cannot deliver: under App Sandbox it has no notification identity and may
    /// not spawn the app executable to borrow one (measured: `forbidden-sandbox-reinit`).
    /// Delivery belongs to the app process; this record is the hand-off between them.
    /// A nil preparation (nothing failed, suppressed, or budget exhausted) records nothing.
    private static func recordFailureNotification(summary: BackgroundEvaluationSummary, state: BackendState,
                                                  directory: AuthorizedDirectory) {
        let repository = FileConfigRepository(authorizedDirectory: directory.url)
        guard let snapshot = try? repository.read(),
              let notification = try? BackgroundNotificationPreparation.prepare(
                summary: summary, directory: directory, snapshot: snapshot, generation: state.generation) else {
            return
        }
        // A missing preference file means sound on; an unreadable one means sound off and a
        // repair flag. Neither case invents a successful read. The app applies the preference
        // when it actually delivers.
        let reading = NotificationPreferenceStore(authorizedDirectory: directory.url).readForDelivery()
        let soundEnabled = reading.needsRepair ? false : reading.soundEnabled
        do {
            try PendingNotificationStore(authorizedDirectory: directory.url).enqueue(
                PendingNotification(count: notification.count, soundEnabled: soundEnabled,
                    soundPreferenceNeedsRepair: reading.needsRepair))
        } catch {
            Self.logger.error("failure notice not recorded kind=\(String(describing: type(of: error)), privacy: .public)")
        }
    }
}

/// Bounded, explicit probe for the notification channel from a helper identity.
///
/// A helper can never own the notification identity: `Contents/Helpers` resolves to no bundle
/// identifier, and a sandboxed helper may not spawn the app's executable to borrow it
/// (measured: the child dies with `forbidden-sandbox-reinit`). The probe reports that boundary
/// instead of pretending a helper-local delivery is possible.
enum NotificationChannelProbe {
    static let flag = "--probe-notification-channel"

    static func run() async {
        FileHandle.standardError.write(Data(
            "probe: bundleID=\(NotificationBundleIdentity.role(of: .main))\n".utf8))
        FileHandle.standardError.write(Data("probe: helper-delivery=unsupported-by-design\n".utf8))
        FileHandle.standardError.write(Data("probe: delivery-owner=app-when-running\n".utf8))
        exit(EXIT_SUCCESS)
    }
}

/// Bounded, explicit probe for the session identity inputs available inside the helper
/// sandbox. It exists because the recovery state expires eject suppression when the session
/// boundary changes: if the boundary can never be read, every restart looks like the session
/// in which the user ejected the volume, and automatic mounting stays suppressed.
enum SessionProbe {
    static func run() -> Int32 {
        FileHandle.standardError.write(Data("probe: login-epoch=\(readable(RecoverySessionCollector.loginEpoch()))\n".utf8))
        FileHandle.standardError.write(Data("probe: network-identity=\(readable(RecoverySessionCollector.networkIdentity()))\n".utf8))
        FileHandle.standardError.write(Data("probe: boot-time=\(bootTimeReadable() ? "readable" : "unreadable")\n".utf8))
        FileHandle.standardError.write(Data("probe: utmpx-console-records=\(consoleRecordCount())\n".utf8))
        FileHandle.standardError.write(Data("probe: session=\(RecoverySessionCollector.collect(previous: nil) == nil ? "unavailable" : "available")\n".utf8))
        return EXIT_SUCCESS
    }

    private static func readable(_ value: String?) -> String { value == nil ? "unreadable" : "readable" }

    private static func bootTimeReadable() -> Bool {
        var boot = timeval()
        var length = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        return sysctl(&mib, 2, &boot, &length, nil, 0) == 0 && boot.tv_sec > 0
    }

    private static func consoleRecordCount() -> Int {
        setutxent()
        defer { endutxent() }
        var count = 0
        while let entry = getutxent() {
            guard entry.pointee.ut_type == USER_PROCESS else { continue }
            let line = withUnsafeBytes(of: entry.pointee.ut_line) {
                String(cString: $0.bindMemory(to: CChar.self).baseAddress!)
            }
            if line.hasPrefix("console") { count += 1 }
        }
        return count
    }
}
