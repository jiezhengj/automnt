import Foundation
import ServiceManagement
import AutomntCore

/// The agent plist is a fixed, signed bundle resource. No generated launchd plist.
@MainActor
public final class ServiceController {
    private let service: SMAppService
    public enum Mode: String, Sendable {
        case baseline, recovery
        public var plistName: String { "automnt.\(rawValue).plist" }
    }
    public let mode: Mode
    public init(mode: Mode) {
        self.mode = mode
        service = SMAppService.agent(plistName: mode.plistName)
    }

    /// Preserve the SDK result for diagnostics without implying execution.
    public var systemStatusDescription: String {
        switch service.status {
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .notRegistered: "notRegistered"
        case .notFound: "notFound"
        @unknown default: "unknown"
        }
    }

    public var status: BackendState.ServiceStatus {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .stopped
        case .notFound: hasVerifiedBundledDefinition ? .stopped : .unavailable
        @unknown default: .unavailable
        }
    }

    /// On this SDK a never-registered agent returns notFound (BTM record absent).
    /// Interpret that as stopped only for our exact, valid signed definition.
    private var hasVerifiedBundledDefinition: Bool {
        let application = Bundle.main.bundleURL
        let helper = application.appendingPathComponent("Contents/Helpers/AutomntHelper")
        let definition = application.appendingPathComponent("Contents/Library/LaunchAgents/" + mode.plistName)
        do {
            try BundledCodeVerifier.verifyHelper(applicationURL: application, helperURL: helper)
            let data = try Data(contentsOf: definition)
            guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  plist["Label"] as? String == "org.automnt.automnt." + mode.rawValue,
                  plist["BundleProgram"] as? String == "Contents/Helpers/AutomntHelper",
                  plist["Program"] == nil, plist["ProgramArguments"] == nil else { return false }
            return true
        } catch { return false }
    }

    /// The caller owns the durable transition and checks existing CLI ownership first.
    public func register() throws -> BackendState.ServiceStatus {
        let other = ServiceController(mode: mode == .baseline ? .recovery : .baseline)
        try BackgroundServiceReadiness.requireOtherStopped(other.status)
        do { try service.register() }
        catch { throw AutomntIssue.serviceTransitionFailed }
        let observed = status
        guard observed == .enabled || observed == .requiresApproval else {
            throw AutomntIssue.serviceTransitionFailed
        }
        return observed
    }

    public func unregister() async throws -> BackendState.ServiceStatus {
        if status == .stopped { return .stopped }
        do { try await service.unregister() }
        catch { throw AutomntIssue.serviceTransitionFailed }
        guard status == .stopped else { throw AutomntIssue.serviceTransitionFailed }
        return .stopped
    }

    /// The SDK completion contract confirms the launched process was killed.
    /// Deadline failure never authorizes the coordinator to register a replacement.
    public func unregister(deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus {
        guard ContinuousClock.now < deadline else { throw AutomntIssue.timeout }
        try Task.checkCancellation()
        if status == .stopped { return .stopped }
        let completion = ServiceStopCompletion()
        let timeout = Task {
            do {
                try await ContinuousClock().sleep(until: deadline)
                completion.finish(.timeout)
            } catch { }
        }
        defer { timeout.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                completion.install(continuation)
                guard !Task.isCancelled else { completion.cancel(); return }
                service.unregister { error in
                    completion.finish(error == nil ? nil : .serviceTransitionFailed)
                }
            }
        } onCancel: {
            completion.cancel()
        }
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw AutomntIssue.timeout }
        guard status == .stopped else { throw AutomntIssue.serviceTransitionFailed }
        return .stopped
    }

    /// Only after both fixed registrations are removed. This is a cooperative
    /// helper-lifetime check, separate from pending mount-worker convergence.
    public static func verifyHelperStopped(authorizedDirectory: URL) throws {
        guard ServiceController(mode: .baseline).status == .stopped,
              ServiceController(mode: .recovery).status == .stopped else {
            throw AutomntIssue.serviceTransitionFailed
        }
        let lease = try HelperExecutionLease(authorizedDirectory: authorizedDirectory)
        defer { withExtendedLifetime(lease) {} }
        // Recheck registrations while holding the execution lease.
        guard ServiceController(mode: .baseline).status == .stopped,
              ServiceController(mode: .recovery).status == .stopped else {
            throw AutomntIssue.serviceTransitionFailed
        }
    }

    /// A foreground action only; never invoked by background evaluation.
    public func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
