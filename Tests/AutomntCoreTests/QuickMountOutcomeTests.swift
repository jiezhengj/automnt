import Testing
@testable import AutomntCore

struct QuickMountOutcomeTests {
    private func target(_ name: String, _ availability: TargetAvailability,
                        issue: AutomntIssue? = nil, enabled: Bool = true) -> QuickMountTarget {
        QuickMountTarget(identity: "smb://server/\(name)", name: name,
                         enabled: enabled, availability: availability, issue: issue)
    }

    @Test func sharesThisActionDidNotOwnAreNotFailures() {
        // Unreachable, never checked, never attempted: none of these are the quick mount's
        // failure, and reporting them would blame the user for something it never tried.
        let targets = [
            target("a", .usable),
            target("b", .availableViaPeer),
            target("c", .notMounted),
            target("d", .locationMismatch),
            target("f", .notEvaluatedThisRound),
            target("g", .unreachable)
        ]
        #expect(QuickMountOutcome.make(from: targets) == nil)
    }

    @Test func sessionEjectIsExplainedRatherThanSilent() {
        // A folder ejected in this session is skipped by design. Staying silent made the
        // click look like it did nothing, so it is reported with its own reason.
        let outcome = QuickMountOutcome.make(from: [
            target("a", .usable),
            target("e", .suppressedForThisSession)
        ])
        #expect(outcome?.failures.map(\.name) == ["e"])
        #expect(outcome?.failures.map(\.reason) == [.ejected])
        // 与真正的失败区分：混在一起时两者各自保留自己的原因。
        let mixed = QuickMountOutcome.make(from: [
            target("e", .suppressedForThisSession),
            target("bad", .failed, issue: .shareRejected)
        ])
        #expect(mixed?.count == 2)
        #expect(mixed?.failures.map(\.reason).contains(.ejected) == true)
        #expect(mixed?.failures.map(\.reason).contains(.refused) == true)
    }

    @Test func attemptedFailuresAreReportedWithAUserFacingReason() {
        let targets = [
            target("creds", .authenticationRequired),
            target("occupied", .locationOccupied),
            target("rejected", .failed, issue: .shareRejected),
            target("stale", .failed, issue: .credentialFailure),
            target("busy", .failed, issue: .volumeBusy),
            target("conflict", .failed, issue: .pathConflict),
            target("slow", .failed, issue: .timeout),
            target("quiet", .failed, issue: .signalUnavailable),
            target("other", .failed, issue: .offline)
        ]
        let outcome = QuickMountOutcome.make(from: targets)
        #expect(outcome?.failures.map(\.reason) == [
            .credentials, .locationBusy, .refused, .credentials, .locationBusy,
            .locationBusy, .notFinished, .notFinished, .other
        ])
        #expect(outcome?.count == targets.count)
    }

    @Test func failureOrderFollowsConfigurationOrder() {
        let outcome = QuickMountOutcome.make(from: [
            target("third", .usable),
            target("first", .authenticationRequired),
            target("second", .locationOccupied)
        ])
        #expect(outcome?.failures.map(\.name) == ["first", "second"])
        #expect(outcome?.failures.first?.id == "smb://server/first")
    }

    @Test func disabledSharesAreExcludedFromTheReport() {
        let outcome = QuickMountOutcome.make(from: [
            target("kept", .authenticationRequired),
            target("off", .failed, issue: .shareRejected, enabled: false)
        ])
        #expect(outcome?.failures.map(\.name) == ["kept"])
        #expect(QuickMountOutcome.make(from: [
            target("off", .authenticationRequired, enabled: false)
        ]) == nil)
    }

    @Test func gateReportsTheFirstThingTheUserMustFix() {
        #expect(QuickMountGate.evaluate(hasConfiguration: false, automaticMountingEnabled: true,
                                        backend: .running, busy: false) == .noConfiguration)
        #expect(QuickMountGate.evaluate(hasConfiguration: true, automaticMountingEnabled: false,
                                        backend: .running, busy: false) == .automaticMountingOff)
        for backend in [SettingsSurface.BackendStatus.stopped, .awaitingApproval,
                        .transitioning, .unavailable, .governedByCLI] {
            #expect(QuickMountGate.evaluate(hasConfiguration: true, automaticMountingEnabled: true,
                                            backend: backend, busy: false) == .backgroundNotReady)
        }
        #expect(QuickMountGate.evaluate(hasConfiguration: true, automaticMountingEnabled: true,
                                        backend: .running, busy: true) == .busy)
        let ready = QuickMountGate.evaluate(hasConfiguration: true, automaticMountingEnabled: true,
                                            backend: .running, busy: false)
        #expect(ready == .ready)
        #expect(ready.isReady)
    }
}
