import Foundation
import Testing
@testable import AutomntCore

struct ShareDetailTests {
    private let share = SMBShareConfig(name: "Docs", smbURL: "smb://a.example/Docs", mountPoint: "/Volumes/Docs")

    private func detail(mounted: Bool = false, actual: String? = nil, reachable: Bool? = true,
                        selected: Bool = true, automation: Bool = true, serverEnabled: Bool = true,
                        shareEnabled: Bool = true, suppressed: Bool = false, recovering: Bool = false,
                        locationOccupied: Bool = false, recoveryFailed: Bool = false,
                        issue: AutomntIssue? = nil) -> ShareDetail {
        ShareDetailBuilder.build(share: share, expectedMountPoint: "/Volumes/Docs", mounted: mounted,
            actualMountPoint: actual, observedAt: Date(), serverReachable: reachable,
            selectedThisRound: selected, automationEnabled: automation, serverEnabled: serverEnabled,
            shareEnabled: shareEnabled, suppressed: suppressed, recovering: recovering,
            locationOccupied: locationOccupied, recoveryFailed: recoveryFailed, issue: issue)
    }

    @Test func healthyOnlyWhenMountedAtTheExpectedPath() {
        let healthy = detail(mounted: true, actual: "/Volumes/Docs")
        #expect(healthy.status == .healthy)
        #expect(healthy.isUsableAtExpectedPath)
        #expect(healthy.nextStep == .openInFinder)
        #expect(!healthy.showsExpectedAndActualLocations)
    }

    @Test func mountedAtADifferentPathIsMismatchNotHealthy() {
        let mismatched = detail(mounted: true, actual: "/Volumes/Docs-1")
        #expect(mismatched.status == .locationMismatch)
        #expect(!mismatched.isUsableAtExpectedPath)
        #expect(mismatched.showsExpectedAndActualLocations)
        #expect(mismatched.nextStep == .reviewLocations)
        #expect(mismatched.actualMountPoint == "/Volumes/Docs-1")
        #expect(mismatched.expectedMountPoint == "/Volumes/Docs")
    }

    /// 同一身份挂在别处时，即使没有挂在配置路径，也是「位置不同」而不是「挂载失败」。
    @Test func mountedElsewhereIsMismatchNotFailure() {
        let elsewhere = detail(mounted: false, actual: "/Volumes/Docs-1")
        #expect(elsewhere.status == .locationMismatch)
        #expect(elsewhere.actualMountPoint == "/Volumes/Docs-1")
        #expect(elsewhere.status != .recoveryFailed)
        #expect(elsewhere.showsExpectedAndActualLocations)
        let actions = DetailActionPolicy.available(elsewhere, busy: false)
        #expect(actions.contains(.useActualLocation))
        #expect(actions.contains(.openActualLocation))
        #expect(!actions.contains(.mount))
    }

    /// 配置位置被另一个卷占用是独立状态：不是恢复失败，也不提供弹出/挂载主按钮。
    @Test func occupiedLocationIsNotARecoveryFailure() {
        let occupied = detail(mounted: false, locationOccupied: true, recoveryFailed: true)
        #expect(occupied.status == .locationOccupied)
        #expect(occupied.nextStep == .reviewOccupiedLocation)
        #expect(!occupied.showsExpectedAndActualLocations)
        let actions = DetailActionPolicy.available(occupied, busy: false)
        #expect(actions.contains(.openOccupyingLocation))
        #expect(!actions.contains(.eject))
        #expect(!actions.contains(.mount))
        #expect(actions.contains(.editTarget))
    }

    @Test func notSelectedThisRoundIsNotAFailure() {
        let skipped = detail(selected: false)
        #expect(skipped.status == .notSelectedThisRound)
        #expect(skipped.nextStep == .explainRoundSelection)
        #expect(skipped.issue == nil)
    }

    @Test func unreachableServerIsOnlyClaimedWithEvidence() {
        #expect(detail(reachable: false).status == .serverUnreachable)
        // Unknown reachability must not be reported as offline.
        #expect(detail(reachable: nil).status == .notMounted)
    }

    @Test func ejectedForThisSessionIsNotARecoveryFailure() {
        let ejected = detail(suppressed: true)
        #expect(ejected.status == .ejectedForThisSession)
        #expect(ejected.automaticPlan == .pausedThisSession)
        #expect(ejected.nextStep == .mountThisShare)
        // A dead/damaged volume is a different condition from a deliberate ejection.
        let damaged = detail(recoveryFailed: true)
        #expect(damaged.status == .recoveryFailed)
        #expect(damaged.status != ejected.status)
    }

    @Test func automatedMountingOffStillShowsAnAvailableMount() {
        let offButMounted = detail(mounted: true, actual: "/Volumes/Docs", automation: false)
        #expect(offButMounted.status == .automatedMountingOff)
        #expect(offButMounted.automaticPlan == .disabledGlobally)
        // Being mounted still permits normal use and an ordinary eject.
        let actions = DetailActionPolicy.available(offButMounted, busy: false)
        #expect(actions.contains(.openInFinder))
        #expect(actions.contains(.eject))
    }

    @Test func planNamesTheLevelThatDisabledIt() {
        #expect(detail(serverEnabled: false).automaticPlan == .disabledForServer)
        #expect(detail(shareEnabled: false).automaticPlan == .disabledForShare)
        #expect(detail(automation: false).automaticPlan == .disabledGlobally)
        #expect(detail().automaticPlan == .scheduled)
    }

    @Test func authenticationProblemPointsToFinderNotPasswordManagement() {
        let auth = detail(issue: .authorizationRequired)
        #expect(auth.status == .authenticationRequired)
        #expect(auth.nextStep == .connectInFinder)
    }

    @Test func busyBlocksEveryActionThatWouldRaceTheInFlightOperation() {
        let healthy = detail(mounted: true, actual: "/Volumes/Docs")
        let busy = DetailActionPolicy.available(healthy, busy: true)
        #expect(!busy.contains(.eject))
        #expect(!busy.contains(.mount))
        #expect(!busy.contains(.removeFromManagement))
        // Reading the target and diagnostics stay available while busy.
        #expect(busy.contains(.editTarget))
        #expect(busy.contains(.viewDiagnostics))
    }

    @Test func ordinaryEjectIsOfferedForMountedTargetsAndNeverForces() {
        let healthy = detail(mounted: true, actual: "/Volumes/Docs")
        #expect(DetailActionPolicy.available(healthy, busy: false).contains(.eject))
        // A share that is not mounted has nothing to eject.
        let absent = detail()
        #expect(!DetailActionPolicy.available(absent, busy: false).contains(.eject))
        #expect(DetailActionPolicy.available(absent, busy: false).contains(.mount))
        // While transitioning, neither direction is offered.
        let moving = detail(recovering: true)
        let movingActions = DetailActionPolicy.available(moving, busy: false)
        #expect(!movingActions.contains(.eject))
        #expect(!movingActions.contains(.mount))
    }

    @Test func removalIsAlwaysOfferedAndItsConsequenceSaysMountIsKept() {
        let mounted = detail(mounted: true, actual: "/Volumes/Docs")
        #expect(DetailActionPolicy.available(mounted, busy: false).contains(.removeFromManagement))
        // Core returns a semantic value; the GUI owns the localized wording.
        #expect(DetailActionPolicy.removalConsequence(shareMounted: true) == .removedManagementOnlyMountedStays)
        #expect(DetailActionPolicy.removalConsequence(shareMounted: false) == .removedManagementOnly)
    }
}
