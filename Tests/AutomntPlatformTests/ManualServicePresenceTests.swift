import Testing
import AutomntCore
@testable import AutomntPlatform

struct ManualServicePresenceTests {
    @Test func activeManualOperationRequiresExactlyOneRegisteredJob() {
        let states: [LaunchAgentPresence] = [.registered, .absent, .unknown]
        for baseline in states {
            for recovery in states {
                let expected = (baseline == .registered && recovery == .absent) ||
                    (recovery == .registered && baseline == .absent)
                #expect(StoppedManualOperation.activeServicesPermit(baseline: baseline, recovery: recovery) == expected)
            }
        }
    }
}
