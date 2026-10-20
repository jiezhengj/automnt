import Foundation
import Testing
@testable import AutomntCore

struct RecoveryFailureObservationTests {
    @Test func onlyDefinitiveRejectionBecomesNotificationFailure() {
        let identity = UUID().uuidString
        let observedAt = Date()
        let failure = RecoveryFailureObservation.mount(identity: identity, issue: .shareRejected,
            requiresReconciliation: false, observedAt: observedAt)
        #expect(failure?.identity == identity)
        #expect(failure?.status == .failed)
        #expect(failure?.actualPath == nil)
        #expect(failure?.observedAt == observedAt)
        #expect(failure?.issue == .shareRejected)
        #expect(RecoveryFailureObservation.mount(identity: identity, issue: .shareRejected,
            requiresReconciliation: true) == nil)
        for issue: AutomntIssue in [.timeout, .signalUnavailable, .authorizationRequired,
            .configurationConflict, .pathConflict, .offline, .volumeBusy] {
            #expect(RecoveryFailureObservation.mount(identity: identity, issue: issue,
                requiresReconciliation: false) == nil)
        }
    }
}
