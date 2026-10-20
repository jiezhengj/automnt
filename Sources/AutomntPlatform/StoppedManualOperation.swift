import Foundation
import AutomntCore

/// Caller holds evaluation.lock. Keep the helper lifetime lock until the operation
/// finishes, so a newly launched helper cannot begin evaluating this directory.
public enum StoppedManualOperation {
    /// Unknown launchd visibility is never evidence of a unique registered owner.
    public static func activeServicesPermit(baseline: LaunchAgentPresence,
                                            recovery: LaunchAgentPresence) -> Bool {
        (baseline == .registered && recovery == .absent) ||
            (recovery == .registered && baseline == .absent)
    }

    public static func acquireIfNeeded(state: BackendState, directory: URL) throws -> HelperExecutionLease? {
        guard state.owner == .none else {
            guard state.owner == .app,
                  activeServicesPermit(baseline: LegacyServicePresence.inspectBaseline(),
                                       recovery: LegacyServicePresence.inspectRecovery())
            else { throw AutomntIssue.serviceTransitionFailed }
            return nil
        }
        let lease = try HelperExecutionLease(authorizedDirectory: directory)
        guard LegacyServicePresence.inspect(label: "org.automnt.automnt.baseline") == .absent,
              LegacyServicePresence.inspect(label: "org.automnt.automnt.recovery") == .absent
        else { throw AutomntIssue.serviceTransitionFailed }
        return lease
    }
}
