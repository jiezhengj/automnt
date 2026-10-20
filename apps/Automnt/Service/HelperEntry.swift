import Foundation
import Darwin
import AutomntCore
import AutomntPlatform

@main
struct HelperEntry {
    static func main() async {
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
            let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            let applicationURL = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            guard executable.lastPathComponent == "AutomntHelper",
                  let bundle = Bundle(url: applicationURL), bundle.bundleIdentifier == "org.automnt.automnt" else {
                throw AutomntIssue.authorizationRequired
            }
            let state = try BackendStateStore(authorizedDirectory: directory.url).read()
            let summary: BackgroundEvaluationSummary
            do {
                summary = try await BackgroundEvaluationTrigger.run(applicationBundle: bundle, directory: directory, expectedState: state,
                    deadline: ContinuousClock.now.advanced(by: .seconds(30)))
            } catch {
                summary = BackgroundEvaluationSummary(issue: error as? AutomntIssue ?? .signalUnavailable)
            }
            // Current-operation summary is private, structured and contains no credentials.
            try Task.checkCancellation()
            try BackgroundObservationCommit.commit(summary, state: state, directory: directory.url)
            await deliverFailureNotification(summary: summary, state: state, directory: directory, bundle: bundle)
            withExtendedLifetime(directory) {}
        } catch {
            // No authorized directory means no fallback persistence or payload logging.
            exit(EXIT_FAILURE)
        }
    }

    /// Consume the shared notice budget first, then deliver through the app identity.
    /// A nil preparation (nothing failed, suppressed, or budget exhausted) never delivers.
    private static func deliverFailureNotification(summary: BackgroundEvaluationSummary, state: BackendState,
                                                   directory: AuthorizedDirectory, bundle: Bundle) async {
        let repository = FileConfigRepository(authorizedDirectory: directory.url)
        guard let snapshot = try? repository.read(),
              let notification = try? BackgroundNotificationPreparation.prepare(
                summary: summary, directory: directory, snapshot: snapshot, generation: state.generation) else {
            return
        }
        // A missing preference file means sound on; an unreadable one means sound off and a
        // repair flag. Neither case invents a successful read.
        let reading = NotificationPreferenceStore(authorizedDirectory: directory.url).readForDelivery()
        let soundEnabled = reading.needsRepair ? false : reading.soundEnabled
        // The helper itself has no notification identity; delivery runs in the app executable.
        let notifier = SystemUserNotifier(soundEnabled: soundEnabled,
            executor: AppNotificationDelivery(applicationBundle: bundle))
        let delivery = await notifier.deliver(notification)
        // Structured result only: no business configuration is rewritten by a delivery attempt.
        try? NotificationDeliveryRecordStore(authorizedDirectory: directory.url).save(
            NotificationDeliveryRecord(delivery: delivery, count: notification.count,
                soundEnabled: soundEnabled, soundPreferenceNeedsRepair: reading.needsRepair))
    }
}

/// Bounded, explicit probe for the notification channel from a helper identity.
enum NotificationChannelProbe {
    static let flag = "--probe-notification-channel"

    static func run() async {
        guard let bundle = applicationBundle() else {
            FileHandle.standardError.write(Data("probe: app bundle unresolved\n".utf8))
            exit(NotificationExitCode.unavailable)
        }
        FileHandle.standardError.write(Data(
            "probe: bundleID=\(NotificationBundleIdentity.role(of: .main))\n".utf8))
        guard let notification = FailureNotification(failed: ["probe"], recovered: [], eligible: ["probe"]) else {
            exit(NotificationExitCode.failed)
        }
        // Exercise the real child path, independent of the frontmost-application answer.
        let delivery = await AppNotificationDelivery(applicationBundle: bundle)
            .deliver(notification, soundEnabled: false)
        FileHandle.standardError.write(Data("probe: helper-direct-child=\(delivery.rawValue)\n".utf8))
        let notifier = SystemUserNotifier(soundEnabled: false,
            executor: AppNotificationDelivery(applicationBundle: bundle))
        let notified = await notifier.deliver(notification)
        FileHandle.standardError.write(Data("probe: notifier=\(notified.rawValue)\n".utf8))
        exit(NotificationExitCode.child(for: delivery))
    }

    private static func applicationBundle() -> Bundle? {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var candidate = executable.deletingLastPathComponent()
        for _ in 0..<4 {
            if candidate.pathExtension == "app" {
                return Bundle(url: candidate)
            }
            candidate = candidate.deletingLastPathComponent()
        }
        return nil
    }
}
