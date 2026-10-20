import Foundation
import Testing
@testable import AutomntCore

struct BaselineDecisionTests {
    @Test func missingVolumeRequiresReadableUnsuppressedNeverMountedState() {
        let identity = UUID().uuidString
        #expect(BaselineMountDecision.decide(identity: identity, path: .absent, recovery: .absent) == .mount)
        #expect(BaselineMountDecision.decide(identity: identity, path: .absent,
            recovery: .corrupt(reason: "unreadable")) == .suppressed)
        for record in [
            MountRecoveryVolumeRecord(volumeKey: identity, state: .suppressed),
            MountRecoveryVolumeRecord(volumeKey: identity, everHealthyMounted: true),
            MountRecoveryVolumeRecord(volumeKey: identity, repairEjectEvidence: true),
            MountRecoveryVolumeRecord(volumeKey: identity, state: .pendingRecovery)
        ] {
            let state = MountRecoveryStateFile(volumes: [identity: record])
            #expect(BaselineMountDecision.decide(identity: identity, path: .absent, recovery: .loaded(state)) == .suppressed)
        }
        #expect(BaselineMountDecision.decide(identity: identity, path: .absent,
            recovery: .loaded(MountRecoveryStateFile(cleanupLedger: [identity: Date().timeIntervalSince1970]))) == .suppressed)
    }
    @Test func occupiedOrUnknownMountTableCannotEstablishFreePath() {
        let identity = UUID().uuidString
        #expect(BaselineMountDecision.decide(identity: identity, path: .occupied, recovery: .absent) == .blocked(.pathConflict))
        #expect(BaselineMountDecision.decide(identity: identity, path: .unavailable, recovery: .absent) == .blocked(.signalUnavailable))
        #expect(BaselineMountDecision.decide(identity: identity, path: .smb(identity: UUID().uuidString), recovery: .absent) == .blocked(.pathConflict))
        #expect(BaselineMountDecision.decide(identity: identity, path: .smb(identity: identity),
            recovery: .corrupt(reason: "unreadable")) == .inspectExisting)
    }
}
