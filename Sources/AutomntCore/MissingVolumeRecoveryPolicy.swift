import Foundation

public enum MissingVolumeRecoveryPolicy {
    /// Baseline is independent of recovery. Cleanup and repair evidence require opt-in.
    public static func mayMount(signal: RecoverySignal, enabled: Bool) -> Bool {
        switch signal {
        case .neverMounted: return true
        case .productCleanup, .repairEject: return enabled
        case .healthyEject, .unknownConservative, .attachedHealthy, .deadButPresent: return false
        }
    }
}
