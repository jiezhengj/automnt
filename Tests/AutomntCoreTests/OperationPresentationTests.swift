import Foundation
import Testing
@testable import AutomntCore

struct EvaluationSelectionTests {
    @Test func viewedServerIsNotTheRoundSelectionNorAMountFact() {
        let selection = EvaluationSelection(roundSelectedServer: "a.example:445",
            checkedServers: ["a.example:445"], skippedServers: ["b.example:445", "c.example:445"],
            observedAt: Date())
        #expect(selection.status(forServer: "a.example:445") == .selected)
        #expect(selection.status(forServer: "b.example:445") == .notSelected)
        // A skipped server must never be reported as offline.
        #expect(selection.status(forServer: "b.example:445") != .selected)
        #expect(selection.status(forServer: "unknown.example:445") == .notSelected)
    }

    @Test func roundSelectionSurvivesReorderButNotReselection() {
        // Reordering only affects the next round; this round's choice is unchanged.
        let before = EvaluationSelection(roundSelectedServer: "b.example:445", checkedServers: ["b.example:445"],
            skippedServers: ["a.example:445"], observedAt: Date())
        let after = EvaluationSelection(roundSelectedServer: "b.example:445", checkedServers: ["b.example:445"],
            skippedServers: ["a.example:445"], observedAt: Date())
        #expect(before.roundSelectedServer == after.roundSelectedServer)
    }
}

struct OperationLedgerTests {
    @Test func duplicateRequestForSameObjectIsNotStartedTwice() {
        var ledger = OperationLedger()
        let first = ledger.begin(.singleShareMount, targetIdentity: "//445/a.example/docs")
        #expect(!first.isDuplicate)
        let second = ledger.begin(.singleShareMount, targetIdentity: "//445/a.example/docs")
        #expect(second.isDuplicate)
        #expect(second.operation.id == first.operation.id)
        #expect(ledger.activeCount == 1)
        ledger.finish(first.operation)
        #expect(ledger.activeCount == 0)
    }

    @Test func differentScopesAndTargetsRunIndependently() {
        var ledger = OperationLedger()
        _ = ledger.begin(.fullEvaluation, targetIdentity: nil)
        _ = ledger.begin(.statusRefresh, targetIdentity: nil)
        _ = ledger.begin(.singleShareMount, targetIdentity: "//445/a.example/docs")
        #expect(ledger.activeCount == 3)
        #expect(ledger.isActive(.singleShareMount, targetIdentity: "//445/a.example/docs"))
        #expect(!ledger.isActive(.singleShareMount, targetIdentity: "//445/a.example/media"))
    }

    @Test func statusRefreshNeverBlocksOrStandsInForAMount() {
        var ledger = OperationLedger()
        _ = ledger.begin(.statusRefresh, targetIdentity: nil)
        #expect(ledger.isActive(.statusRefresh, targetIdentity: nil))
        #expect(!ledger.isActive(.singleShareMount, targetIdentity: "//445/a.example/docs"))
    }

    @Test func failuresMergeWithinScopeAndTargetOnly() {
        let merged = OperationLedger.merge([
            (.singleShareMount, "//445/a.example/docs", "Docs could not be mounted."),
            (.singleShareMount, "//445/a.example/docs", "Docs could not be mounted."),
            (.singleShareMount, "//445/a.example/media", "Media could not be mounted."),
            (.fullEvaluation, nil, "The round could not reach any server.")
        ])
        #expect(merged.count == 3)
        #expect(merged.contains("Docs could not be mounted."))
        #expect(merged.contains("Media could not be mounted."))
    }
}

struct OutcomeDistinctionTests {
    @Test func savedConfigurationIsNotTheSameAsEnabledOrUsable() {
        let savedOnly = AvailabilityReport(configurationSaved: true, setting: .savedButNotEnabled,
            availability: .notMounted, observedAt: nil)
        #expect(savedOnly.configurationSaved)
        #expect(savedOnly.availability == .notMounted)

        let pending = AvailabilityReport(configurationSaved: true, setting: .savedButApprovalPending,
            availability: .notEvaluatedThisRound, observedAt: Date())
        #expect(pending.setting == .savedButApprovalPending)

        let usable = AvailabilityReport(configurationSaved: true, setting: .savedAndEnabled,
            availability: .usable, observedAt: Date())
        #expect(usable.availability == .usable)

        let failed = AvailabilityReport(configurationSaved: false, setting: .saveFailed,
            availability: .notMounted, observedAt: nil)
        #expect(!failed.configurationSaved)
    }
}
