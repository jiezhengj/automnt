import Foundation

/// Describes eligibility from durable ownership facts, not service liveness.
public enum ManualActionReadiness: Equatable, Sendable {
    case eligible, cliManaged, needsSetup, needsApproval, transitioning, needsRepair

    /// ServiceManagement reports registration/approval, not helper health or mount success.
    public static func classify(_ state: BackendState, revision: ConfigRevision,
                                requiredServices: [BackendState.ServiceStatus]) -> Self {
        let ownership = classify(state, revision: revision)
        guard ownership == .eligible else { return ownership }
        guard !requiredServices.isEmpty else { return .needsRepair }
        if requiredServices.contains(.unavailable) { return .needsRepair }
        // An active journal cannot resume approval or initial setup. Reconcile
        // the durable owner through a fresh stop/register transition instead.
        if requiredServices.contains(.requiresApproval) || requiredServices.contains(.stopped) {
            return .needsRepair
        }
        return .eligible
    }

    /// Mounting while automation is disabled requires both registrations to be
    /// stopped, in addition to the durable stop evidence checked by the worker.
    public static func canMount(_ state: BackendState, revision: ConfigRevision,
                                automationEnabled: Bool,
                                baseline: BackendState.ServiceStatus,
                                recovery: BackendState.ServiceStatus) -> Bool {
        guard state.schemaVersion == 1, state.revision == revision,
              ManualOperationOwnership.permits(state, automationEnabled: automationEnabled)
        else { return false }
        if state.owner == .none {
            return baseline == .stopped && recovery == .stopped
        }
        return (baseline == .enabled && recovery == .stopped) ||
            (recovery == .enabled && baseline == .stopped)
    }

    public static func classify(_ state: BackendState, revision: ConfigRevision) -> Self {
        guard state.schemaVersion == 1 else { return .needsRepair }
        guard state.revision == revision else { return .needsRepair }
        if state.phase == .awaitingApproval {
            guard state.desiredOwner == .app, state.transitionID != nil,
                  state.lastVerifiedServiceStatus == .requiresApproval else { return .needsRepair }
            return .needsApproval
        }
        if state.phase == .stopping || state.phase == .activating { return .transitioning }
        if state.phase == .failed { return .needsRepair }
        // Completed journals retain transitionID for crash auditing. Only a
        // matching confirmed terminal state may treat that identifier as complete.
        if state.transitionID != nil {
            if state.phase == .active {
                guard state.desiredOwner == state.owner, state.owner != .none,
                      state.lastVerifiedServiceStatus == .enabled else { return .needsRepair }
            } else {
                guard state.phase == .stopped, state.owner == .none,
                      state.lastVerifiedServiceStatus == .stopped else { return .needsRepair }
            }
        }
        if state.phase == .stopped || state.owner == .none { return .needsSetup }
        return state.owner == .cli ? .cliManaged : .eligible
    }
}
