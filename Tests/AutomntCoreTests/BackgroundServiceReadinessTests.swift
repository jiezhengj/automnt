import Testing
@testable import AutomntCore

struct BackgroundServiceReadinessTests {
    @Test func registeringRequiresOtherStoppedIncludingApprovalAndUnknownStates() throws {
        try BackgroundServiceReadiness.requireOtherStopped(.stopped)
        for status: BackendState.ServiceStatus in [.enabled, .requiresApproval, .unavailable] {
            #expect(throws: AutomntIssue.serviceTransitionFailed) {
                try BackgroundServiceReadiness.requireOtherStopped(status)
            }
        }
    }

    @Test func selectedModeUsesRecoveryDefaultAndRejectsDualRegistration() {
        var configuration = AutomntConfig()
        for value: Bool? in [nil, true, false] {
            configuration.autoMountRecovery = value
            let recoverySelected = value != false
            #expect(BackgroundServiceReadiness.classify(configuration: configuration,
                baseline: recoverySelected ? .stopped : .enabled,
                recovery: recoverySelected ? .enabled : .stopped) == .enabled)
            #expect(BackgroundServiceReadiness.classify(configuration: configuration,
                baseline: .enabled, recovery: .enabled) == .unavailable)
            #expect(BackgroundServiceReadiness.classify(configuration: configuration,
                baseline: .stopped, recovery: .stopped) == .stopped)
            #expect(BackgroundServiceReadiness.classify(configuration: configuration,
                baseline: recoverySelected ? .stopped : .requiresApproval,
                recovery: recoverySelected ? .requiresApproval : .stopped) == .requiresApproval)
        }
    }
}
