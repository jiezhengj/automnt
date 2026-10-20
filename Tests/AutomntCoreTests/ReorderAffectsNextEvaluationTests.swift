import Foundation
import Testing
@testable import AutomntCore

/// The reorder feature is only meaningful if it changes which server the *next* round
/// picks, without breaking first-reachable exclusivity.
struct ReorderAffectsNextEvaluationTests {
    private func configuration() -> AutomntConfig {
        AutomntConfig(hosts: [
            HostConfig(host: "a.example", shares: [
                SMBShareConfig(name: "Docs", smbURL: "smb://a.example/Docs", mountPoint: "/Volumes/Docs")
            ]),
            HostConfig(host: "b.example", shares: [
                SMBShareConfig(name: "Docs", smbURL: "smb://b.example/Docs", mountPoint: "/Volumes/Docs-B")
            ])
        ], automationEnabled: true)
    }

    @Test func savedOrderDeterminesTheNextRoundSelection() throws {
        let original = configuration()
        // Both reachable: the first in saved order wins.
        #expect(HostPriorityEvaluator.firstReachable(in: original, probe: { _ in true })?.host == "a.example")

        let reordered = try #require(ManagedServerOrder.moving(original, identity: "b.example:445", to: 0))
        #expect(HostPriorityEvaluator.firstReachable(in: reordered, probe: { _ in true })?.host == "b.example")
    }

    @Test func onlyTheFirstReachableServerIsSelectedEvenWhenLaterOnesRespond() {
        let config = configuration()
        var probed: [String] = []
        let selected = HostPriorityEvaluator.firstReachable(in: config, probe: { host in
            probed.append(host.host)
            return true
        })
        #expect(selected?.host == "a.example")
        // Later servers are never consulted once one is reachable.
        #expect(probed == ["a.example"])
    }

    @Test func unreachableFirstServerFallsThroughToTheNext() {
        let config = configuration()
        let selected = HostPriorityEvaluator.firstReachable(in: config, probe: { $0.host == "b.example" })
        #expect(selected?.host == "b.example")
    }

    @Test func disabledServerIsSkippedWithoutReorderingTheConfiguration() {
        var config = configuration()
        config.hosts[0].enabled = false
        let selected = HostPriorityEvaluator.firstReachable(in: config, probe: { _ in true })
        #expect(selected?.host == "b.example")
        // The saved order itself is untouched by evaluation.
        #expect(ManagedServerOrder.identities(of: config) == ["a.example:445", "b.example:445"])
    }

    @Test func automationDisabledSelectsNothingWithoutTouchingOrder() {
        var config = configuration()
        config.automationEnabled = false
        #expect(HostPriorityEvaluator.firstReachable(in: config, probe: { _ in true }) == nil)
        #expect(ManagedServerOrder.identities(of: config) == ["a.example:445", "b.example:445"])
    }

    @Test func aShareFailureInsideTheSelectedServerDoesNotSelectAnotherServer() {
        let config = configuration()
        let selected = HostPriorityEvaluator.firstReachable(in: config, probe: { _ in true })
        #expect(selected?.host == "a.example")
        // Selection is decided before mounting, so a failing share on the selected
        // server cannot cause the round to continue to b.example.
        #expect(selected?.shares.count == 1)
        #expect(config.hosts[1].shares.count == 1)
    }
}
