import Foundation

public enum RecoveryFailureObservation {
    /// A definitive mount rejection is a failure, never proof that a present volume is dead.
    public static func mount(identity: String, issue: AutomntIssue, requiresReconciliation: Bool,
                             observedAt: Date = Date()) -> VolumeObservation? {
        guard issue == .shareRejected, !requiresReconciliation else { return nil }
        return VolumeObservation(identity: identity, status: .failed, actualPath: nil,
                                 observedAt: observedAt, issue: issue)
    }
}
