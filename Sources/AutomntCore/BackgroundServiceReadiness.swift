import Foundation

/// Baseline and recovery are mutually exclusive registrations of the same evaluator.
public enum BackgroundServiceReadiness {
    /// A stopped registration is necessary; process convergence must be checked separately.
    public static func requireOtherStopped(_ status: BackendState.ServiceStatus) throws {
        guard status == .stopped else { throw AutomntIssue.serviceTransitionFailed }
    }

    public static func classify(configuration: AutomntConfig,
                                baseline: BackendState.ServiceStatus,
                                recovery: BackendState.ServiceStatus) -> BackendState.ServiceStatus {
        let selected = configuration.isAutoMountRecoveryEnabled ? recovery : baseline
        let other = configuration.isAutoMountRecoveryEnabled ? baseline : recovery
        guard other == .stopped else { return .unavailable }
        return selected
    }
}
