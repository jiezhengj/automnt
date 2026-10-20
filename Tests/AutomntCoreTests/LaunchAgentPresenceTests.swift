import Testing
@testable import AutomntCore

struct LaunchAgentPresenceTests {
    @Test func onlyExplicitMissingServiceProvesAbsence() {
        let label = "org.automnt.presence-test"
        let missing = "Bad request.\nCould not find service \"\(label)\" in domain for user gui: 501"
        #expect(LaunchAgentPresence.classify(status: 113, timedOut: false, processStopped: true, standardError: missing, serviceLabel: label) == .absent)
        #expect(LaunchAgentPresence.classify(status: 1, timedOut: false, processStopped: true, standardError: "Operation not permitted", serviceLabel: label) == .unknown)
        #expect(LaunchAgentPresence.classify(status: 113, timedOut: true, processStopped: false, standardError: missing, serviceLabel: label) == .unknown)
        #expect(LaunchAgentPresence.classify(status: 113, timedOut: false, processStopped: true, standardError: missing, serviceLabel: "other") == .unknown)
        #expect(LaunchAgentPresence.classify(status: 0, timedOut: false, processStopped: true, standardError: "", serviceLabel: label) == .registered)
    }
}
