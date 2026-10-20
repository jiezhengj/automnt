import Testing
@testable import AutomntCore

struct StoppedMountReadinessTests {
    @Test func stoppedMountRequiresBothRegistrationsAndMatchingRevision() {
        let revision = ConfigRevision(digest: "stopped-readiness")
        var state = BackendState(owner: .none, phase: .stopped, generation: 1, revision: revision)
        state.lastVerifiedServiceStatus = .stopped
        #expect(ManualActionReadiness.canMount(state, revision: revision, automationEnabled: false,
            baseline: .stopped, recovery: .stopped))
        for status in [BackendState.ServiceStatus.enabled, .requiresApproval, .unavailable] {
            #expect(!ManualActionReadiness.canMount(state, revision: revision, automationEnabled: false,
                baseline: status, recovery: .stopped))
            #expect(!ManualActionReadiness.canMount(state, revision: revision, automationEnabled: false,
                baseline: .stopped, recovery: status))
        }
        #expect(!ManualActionReadiness.canMount(state, revision: ConfigRevision(digest: "stale"),
            automationEnabled: false, baseline: .stopped, recovery: .stopped))
        #expect(!ManualActionReadiness.canMount(state, revision: revision, automationEnabled: true,
            baseline: .stopped, recovery: .stopped))
        state.lastVerifiedServiceStatus = nil
        #expect(!ManualActionReadiness.canMount(state, revision: revision, automationEnabled: false,
            baseline: .stopped, recovery: .stopped))
    }
}
