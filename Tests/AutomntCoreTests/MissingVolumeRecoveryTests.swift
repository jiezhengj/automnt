import Foundation
import Testing
@testable import AutomntCore

struct MissingVolumeRecoveryTests {
    @Test func missingSessionBaselinePreservesExplicitUserEject() {
        let key = UUID().uuidString
        let login = UUID().uuidString
        var configuration = AutomntConfig()
        configuration.autoMountRecovery = true
        for initialNetwork: String? in [nil, UUID().uuidString] {
            var state = MountRecoveryStateFile(volumes: [key:
                MountRecoveryVolumeRecord(volumeKey: key, state: .suppressed,
                    attemptCount: 3, notificationCount: 2)])
            let first = RecoverySessionIdentity(network: initialNetwork, loginEpoch: login, previous: nil)
            RecoverySessionPolicy.advance(&state, to: first, mountedKeys: [])
            #expect(state.volumes[key]?.state == .suppressed)
            #expect(state.volumes[key]?.suppressionBoundary == first.combined)
            #expect(state.volumes[key]?.attemptCount == 3)
            #expect(state.volumes[key]?.notificationCount == 2)
            #expect(BaselineMountDecision.decide(identity: key, path: .absent, recovery: .loaded(state),
                configuration: configuration, allowRecovery: true) == .suppressed)
            let changedLogin = RecoverySessionIdentity(network: initialNetwork,
                loginEpoch: UUID().uuidString, previous: first.combined)
            RecoverySessionPolicy.advance(&state, to: changedLogin, mountedKeys: [])
            #expect(state.volumes[key]?.state == .pendingRecovery)
            #expect(state.volumes[key]?.attemptCount == 0)
            #expect(state.volumes[key]?.notificationCount == 0)
            #expect(BaselineMountDecision.decide(identity: key, path: .absent, recovery: .loaded(state),
                configuration: configuration, allowRecovery: true) == .mount)
        }
    }

    @Test func evidenceAndSwitchAreBothRequiredForMissingHistoricalVolume() {
        let identity = UUID().uuidString
        var configuration = AutomntConfig()
        configuration.autoMountRecovery = true
        for state in [
            MountRecoveryStateFile(volumes: [identity: MountRecoveryVolumeRecord(volumeKey: identity, state: .pendingRecovery)]),
            MountRecoveryStateFile(volumes: [identity: MountRecoveryVolumeRecord(volumeKey: identity, repairEjectEvidence: true)]),
            MountRecoveryStateFile(cleanupLedger: [identity: 1])
        ] {
            #expect(BaselineMountDecision.decide(identity: identity, path: .absent, recovery: .loaded(state),
                configuration: configuration, allowRecovery: true) == .mount)
            #expect(BaselineMountDecision.decide(identity: identity, path: .absent, recovery: .loaded(state),
                configuration: configuration) == .suppressed)
            var disabled = configuration
            disabled.autoMountRecovery = false
            #expect(BaselineMountDecision.decide(identity: identity, path: .absent, recovery: .loaded(state),
                configuration: disabled, allowRecovery: true) == .suppressed)
        }
        for record in [MountRecoveryVolumeRecord(volumeKey: identity, everHealthyMounted: true),
            MountRecoveryVolumeRecord(volumeKey: identity, state: .suppressed, repairEjectEvidence: true)] {
            #expect(BaselineMountDecision.decide(identity: identity, path: .absent,
                recovery: .loaded(MountRecoveryStateFile(volumes: [identity: record])),
                configuration: configuration, allowRecovery: true) == .suppressed)
        }
        #expect(BaselineMountDecision.decide(identity: identity, path: .absent, recovery: .corrupt(reason: "damaged"),
            configuration: configuration, allowRecovery: true) == .suppressed)
        configuration.autoMountRecovery = false
        #expect(BaselineMountDecision.decide(identity: identity, path: .absent, recovery: .absent,
            configuration: configuration, allowRecovery: true) == .mount)
        #expect(!MissingVolumeRecoveryPolicy.mayMount(signal: .deadButPresent, enabled: true))
    }

    @Test func failedAndInterruptedRecoveryReservationsConsumeFiniteBudget() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = UUID().uuidString
        var configuration = AutomntConfig()
        configuration.retryPolicy = RetryPolicy(maxAttempts: 2)
        let repository = RecoveryStateRepository(url: directory.appendingPathComponent("mount-recovery-state.plist"))
        try repository.save(MountRecoveryStateFile(cleanupLedger: [key: 1]))
        let lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
        try withExtendedLifetime(lock) {
            for count in 1...2 {
                try RecoveryAttemptCommit.reserve(identity: key, directory: directory, configuration: configuration,
                    observedAt: Date(timeIntervalSince1970: Double(count)))
                #expect(repository.read().file.volumes[key]?.attemptCount == count)
            }
            let exhausted = try PrivateAtomicFile.read(repository.url)
            #expect(throws: AutomntIssue.configurationConflict) {
                try RecoveryAttemptCommit.reserve(identity: key, directory: directory, configuration: configuration)
            }
            #expect(try PrivateAtomicFile.read(repository.url) == exhausted)
            #expect(BaselineMountDecision.decide(identity: key, path: .absent, recovery: repository.read(),
                configuration: configuration, allowRecovery: true) == .suppressed)
            let healthy = RecoveryHealthPolicy.observation(identity: key, actualPath: directory.path,
                hostReachable: true, health: .healthy, observedAt: Date())
            try RecoveryHealthCommit.apply(healthy, directory: directory, stillMounted: true)
            #expect(repository.read().file.volumes[key]?.attemptCount == 0)
            let firstMount = UUID().uuidString
            let before = try PrivateAtomicFile.read(repository.url)
            try RecoveryAttemptCommit.reserve(identity: firstMount, directory: directory, configuration: configuration)
            #expect(try PrivateAtomicFile.read(repository.url) == before)
        }
    }

    @Test func actualSessionBoundaryGrantsRecoveryButFirstReadableBaselineDoesNot() {
        let key = UUID().uuidString
        let login = UUID().uuidString
        var configuration = AutomntConfig()
        configuration.autoMountRecovery = true
        let unknown = RecoverySessionIdentity(network: nil, loginEpoch: login, previous: nil)
        var state = MountRecoveryStateFile(sessionBoundary: unknown.combined, volumes: [key:
            MountRecoveryVolumeRecord(volumeKey: key, state: .suppressed, suppressionBoundary: unknown.combined,
                everHealthyMounted: true, attemptCount: 10, notificationCount: 2)])
        let first = RecoverySessionIdentity(network: UUID().uuidString, loginEpoch: login, previous: unknown.combined)
        RecoverySessionPolicy.advance(&state, to: first, mountedKeys: [])
        #expect(BaselineMountDecision.decide(identity: key, path: .absent, recovery: .loaded(state),
            configuration: configuration, allowRecovery: true) == .suppressed)
        #expect(state.volumes[key]?.attemptCount == 10)
        #expect(state.volumes[key]?.notificationCount == 2)
        let next = RecoverySessionIdentity(network: UUID().uuidString, loginEpoch: login, previous: first.combined)
        RecoverySessionPolicy.advance(&state, to: next, mountedKeys: [])
        #expect(state.volumes[key]?.attemptCount == 0)
        #expect(state.volumes[key]?.notificationCount == 0)
        #expect(BaselineMountDecision.decide(identity: key, path: .absent, recovery: .loaded(state),
            configuration: configuration, allowRecovery: true) == .mount)
        #expect(BaselineMountDecision.decide(identity: key, path: .occupied, recovery: .loaded(state),
            configuration: configuration, allowRecovery: true) == .blocked(.pathConflict))
    }
}
