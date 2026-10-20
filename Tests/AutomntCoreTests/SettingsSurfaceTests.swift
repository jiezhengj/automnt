import Foundation
import Testing
@testable import AutomntCore

struct SettingsSurfaceTests {
    private func revision() -> ConfigRevision { ConfigRevision(digest: "r1") }

    private func state(owner: BackendState.Owner, phase: BackendState.Phase) -> BackendState {
        BackendState(owner: owner, phase: phase, generation: 1, revision: revision())
    }

    @Test func savedIntentIsNotReportedAsARunningService() {
        // Automation saved as on, but no durable backend state exists yet.
        #expect(SettingsSurface.backendStatus(state: nil, intended: true) == .unavailable)
        // Automation saved as on, service genuinely stopped.
        #expect(SettingsSurface.backendStatus(state: state(owner: .none, phase: .stopped), intended: true) == .stopped)
        // Automation saved as on and actually active.
        #expect(SettingsSurface.backendStatus(state: state(owner: .app, phase: .active), intended: true) == .running)
        // Automation off is reported as stopped regardless of leftover state.
        #expect(SettingsSurface.backendStatus(state: state(owner: .app, phase: .active), intended: false) == .stopped)
    }

    @Test func approvalAndFailureEachGetTheirOwnStatusAndRepairEntry() {
        #expect(SettingsSurface.backendStatus(state: state(owner: .app, phase: .awaitingApproval), intended: true) == .awaitingApproval)
        #expect(SettingsSurface.backendStatus(state: state(owner: .app, phase: .failed), intended: true) == .unavailable)
        #expect(SettingsSurface.backendStatus(state: state(owner: .app, phase: .stopping), intended: true) == .transitioning)
        #expect(SettingsSurface.BackendStatus.awaitingApproval.needsUserAction)
        #expect(SettingsSurface.BackendStatus.unavailable.needsUserAction)
        #expect(!SettingsSurface.BackendStatus.running.needsUserAction)
        // Only a confirmed running service counts as running.
        #expect(SettingsSurface.BackendStatus.running.isConfirmedRunning)
        #expect(!SettingsSurface.BackendStatus.transitioning.isConfirmedRunning)
    }

    @Test func cliOwnedBackendIsNamedInsteadOfClaimedAsTheAppsOwn() {
        #expect(SettingsSurface.backendStatus(state: state(owner: .cli, phase: .active), intended: true) == .governedByCLI)
    }

    @Test func recoveryIsDisabledWhileAutomationIsOffButKeepsItsPreference() {
        let off = SettingsSurface.AutomaticMounting(intended: false, backend: .stopped, recoveryPreferred: true)
        #expect(!off.recoveryEditable)
        #expect(!off.recoveryEffective)
        // Re-enabling restores the saved preference rather than forcing it to true.
        let back = SettingsSurface.AutomaticMounting(intended: true, backend: .running, recoveryPreferred: true)
        #expect(back.recoveryEditable)
        #expect(back.recoveryEffective)
        let declined = SettingsSurface.AutomaticMounting(intended: true, backend: .running, recoveryPreferred: false)
        // Declining recovery keeps automation running but recovery off.
        #expect(declined.recoveryEditable)
        #expect(!declined.recoveryEffective)
    }

    @Test func notificationSoundIsIndependentOfDeliveryAuthorization() {
        let deniedWithSound = SettingsSurface.Notifications(authorization: .denied, soundEnabled: true, soundNeedsRepair: false)
        #expect(!deniedWithSound.canDeliver)
        #expect(deniedWithSound.offersSettingsShortcut)
        #expect(!deniedWithSound.shouldOfferPermissionRequest)

        let undecided = SettingsSurface.Notifications(authorization: .notRequested, soundEnabled: true, soundNeedsRepair: false)
        #expect(undecided.shouldOfferPermissionRequest)

        let allowed = SettingsSurface.Notifications(authorization: .allowed, soundEnabled: false, soundNeedsRepair: false)
        #expect(allowed.canDeliver)
        #expect(allowed.offersSettingsShortcut)
    }

    @Test func loginPreferenceIsInertWithoutTheMenuBarItem() {
        let hidden = SettingsSurface.MenuBarAndLogin(menuBarPreferred: false, loginPreferred: true, loginRegistration: .notRegistered)
        #expect(!hidden.loginEditable)
        let shown = SettingsSurface.MenuBarAndLogin(menuBarPreferred: true, loginPreferred: true, loginRegistration: .requiresApproval)
        #expect(shown.loginEditable)
        #expect(shown.loginRegistration.needsUserAction)
        #expect(!SettingsSurface.LoginRegistration.registered.needsUserAction)
        #expect(shown.loginRegistration.isConfirmedRegistered == false)
        #expect(SettingsSurface.LoginRegistration.registered.isConfirmedRegistered)
    }

    @Test func advancedParametersReuseTheSharedLimits() {
        let valid = SettingsSurface.Advanced(attempts: 3, intervalMs: 1000, windowMs: 10000)
        #expect(valid.problems.isEmpty)
        let invalid = SettingsSurface.Advanced(attempts: 0, intervalMs: 50, windowMs: 10)
        #expect(invalid.problems.count == 3)
    }

    @Test func summaryNeverPresentsIntentAsAnActiveService() {
        // Core returns a semantic value so the GUI can localize it; each distinct
        // situation must map to a distinct value rather than one generic message.
        let off = SettingsSurface.automaticMountingSummary(
            .init(intended: false, backend: .running, recoveryPreferred: true))
        #expect(off == .offWhileMountedStayAvailable)

        let unconfirmed = SettingsSurface.automaticMountingSummary(
            .init(intended: true, backend: .unavailable, recoveryPreferred: true))
        #expect(unconfirmed == .couldNotBeConfirmed)

        let running = SettingsSurface.automaticMountingSummary(
            .init(intended: true, backend: .running, recoveryPreferred: true))
        #expect(running == .runningWithRecovery)

        // Recovery off while automation runs must be stated, not implied.
        let noRecovery = SettingsSurface.automaticMountingSummary(
            .init(intended: true, backend: .running, recoveryPreferred: false))
        #expect(noRecovery == .runningWithoutRecovery)
        #expect(noRecovery != running)

        #expect(SettingsSurface.automaticMountingSummary(
            .init(intended: true, backend: .awaitingApproval, recoveryPreferred: true)) == .awaitingApproval)
        #expect(SettingsSurface.automaticMountingSummary(
            .init(intended: true, backend: .stopped, recoveryPreferred: true)) == .savedButNotRunning)
        #expect(SettingsSurface.automaticMountingSummary(
            .init(intended: true, backend: .governedByCLI, recoveryPreferred: true)) == .governedByCLI)
        #expect(SettingsSurface.automaticMountingSummary(
            .init(intended: true, backend: .transitioning, recoveryPreferred: true)) == .transitioning)
    }
}
