import Foundation
import Testing
@testable import AutomntCore

private actor RecordingProbe: ReachabilityProbe {
    var visited: [String] = []
    func isReachable(host: String, port: Int, timeoutMilliseconds: Int) async throws -> Bool {
        visited.append(host)
        return true
    }
    func calls() -> [String] { visited }
}

struct RegressionTests {
    @Test func interruptedWorkerBlocksNewLaunchAcrossStoreInstances() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let revision = ConfigRevision(digest: UUID().uuidString)
        let first = WorkerOperationStore(authorizedDirectory: directory)
        let operation = try first.begin(revision: revision, generation: 1)
        let restarted = WorkerOperationStore(authorizedDirectory: directory)
        try restarted.verifyPending(id: operation, revision: revision, generation: 1)
        #expect(throws: AutomntIssue.configurationConflict) {
            try restarted.verifyPending(id: UUID(), revision: revision, generation: 1)
        }
        #expect(throws: AutomntIssue.signalUnavailable) { try restarted.begin(revision: revision, generation: 1) }
        #expect(throws: AutomntIssue.configurationConflict) { try restarted.complete(id: operation, revision: revision, generation: 2) }
        #expect(throws: AutomntIssue.signalUnavailable) { try restarted.begin(revision: revision, generation: 2) }
        try first.complete(id: operation, revision: revision, generation: 1)
        #expect(try restarted.begin(revision: revision, generation: 2) != operation)
    }

    @Test func asyncEvaluationPreservesPriorityAndExpiredBudget() async throws {
        let first = UUID().uuidString
        let second = UUID().uuidString
        var configuration = AutomntConfig()
        configuration.hosts = [HostConfig(host: first), HostConfig(host: second)]
        let probe = RecordingProbe()
        let selected = try await HostPriorityEvaluator.firstReachable(in: configuration,
            deadline: ContinuousClock.now.advanced(by: .seconds(1)), probe: probe)
        #expect(selected?.host == first)
        #expect(await probe.calls() == [first])
        let expired = try await HostPriorityEvaluator.firstReachable(in: configuration,
            deadline: ContinuousClock.now.advanced(by: .seconds(-1)), probe: probe)
        #expect(expired == nil)
        #expect(await probe.calls() == [first])
        configuration.automationEnabled = false
        let disabled = try await HostPriorityEvaluator.firstReachable(in: configuration,
            deadline: ContinuousClock.now.advanced(by: .seconds(1)), probe: probe)
        #expect(disabled == nil)
        #expect(await probe.calls() == [first])
    }

    @Test func notificationPreferencesDistinguishMissingFromCorrupt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotificationPreferenceStore(authorizedDirectory: directory)
        #expect(store.readForDelivery().soundEnabled)
        #expect(!store.readForDelivery().needsRepair)
        try store.save(NotificationPreferences(notificationSoundEnabled: false))
        #expect(!store.readForDelivery().soundEnabled)
        #expect(!store.readForDelivery().needsRepair)
        let url = directory.appendingPathComponent("gui-notification-preferences.plist")
        try PrivateAtomicFile.replace(Data([0xff]), at: url)
        #expect(!store.readForDelivery().soundEnabled)
        #expect(store.readForDelivery().needsRepair)
        #expect(throws: (any Error).self) { try PrivateAtomicFile.read(url, maximumBytes: 0) }
    }

    @Test func transitionCannotActivateWithoutVerifiedService() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        let initial = try store.initialize(revision: snapshot.revision)
        let transition = try store.begin(desiredOwner: .app, expectedGeneration: initial.generation,
                                         revision: snapshot.revision)
        #expect(throws: AutomntIssue.incompatibleOwner) {
            try EvaluationPermit(directory: directory, repository: repository, expected: snapshot,
                                 owner: .app, generation: transition.pending.generation, readBackend: store.read)
        }
        #expect(throws: AutomntIssue.serviceTransitionFailed) {
            try store.advance(id: transition.id, to: .active, verifiedStatus: .enabled)
        }
        _ = try store.advance(id: transition.id, to: .activating, verifiedStatus: .stopped)
        _ = try store.advance(id: transition.id, to: .awaitingApproval, verifiedStatus: .requiresApproval)
        #expect(try store.read().owner == .none)
        let active = try store.advance(id: transition.id, to: .active, verifiedStatus: .enabled)
        #expect(active.owner == .app)
        let permit = try EvaluationPermit(directory: directory, repository: repository, expected: snapshot,
                                          owner: .app, generation: active.generation, readBackend: store.read)
        _ = permit.perform { _ in
            #expect(throws: (any Error).self) {
                try store.begin(desiredOwner: .cli, expectedGeneration: active.generation, revision: snapshot.revision)
            }
        }
    }

    @Test func interruptedTransitionCannotReadAsActive() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(AutomntConfig())
        let store = BackendStateStore(authorizedDirectory: directory)
        let initial = try store.initialize(revision: snapshot.revision)
        let transition = try store.begin(desiredOwner: .app, expectedGeneration: initial.generation, revision: snapshot.revision)
        // Simulate a crash after the journal reached disk but before its matching state write.
        let encoder = PropertyListEncoder()
        try PrivateAtomicFile.replace(encoder.encode(initial), at: directory.appendingPathComponent("backend-state.plist"))
        #expect(throws: AutomntIssue.serviceTransitionFailed) { try store.read() }
        #expect(try store.journal().id == transition.id)
        #expect(throws: AutomntIssue.serviceTransitionFailed) {
            try store.reconcileInterruptedTransition(verifiedStatus: .enabled)
        }
        let repaired = try store.reconcileInterruptedTransition(verifiedStatus: .stopped)
        #expect(repaired.owner == .none)
        #expect(repaired.phase == .stopped)
        #expect(repaired.generation == transition.pending.generation)
        #expect(try store.read() == repaired)
    }

    @Test func staleSnapshotCannotStartAnOperation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(AutomntConfig())
        var edited = snapshot.configuration
        edited.automationEnabled = false
        _ = try repository.save(edited, baseRevision: snapshot.revision)
        #expect(throws: AutomntIssue.configurationConflict) {
            try EvaluationPermit(directory: directory, repository: repository, expected: snapshot,
                                 owner: .cli, generation: 1) {
                BackendState(owner: .cli, phase: .active, generation: 1, revision: snapshot.revision)
            }
        }
    }

    @Test func concurrentEditsPreserveDraftAndLockIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let original = try repository.create(AutomntConfig())
        let lock = directory.appendingPathComponent("config.lock")
        let before = try FileManager.default.attributesOfItem(atPath: lock.path)[.systemFileNumber] as? NSNumber
        var first = original.configuration
        first.automationEnabled = false
        first.autoMountRecovery = true
        let committed = try repository.save(first, baseRevision: original.revision)
        #expect(!committed.configuration.isAutomationEnabled)
        #expect(committed.configuration.isAutoMountRecoveryEnabled)
        var competingDraft = original.configuration
        competingDraft.autoMountRecovery = false
        #expect(throws: AutomntIssue.configurationConflict) {
            try repository.save(competingDraft, baseRevision: original.revision)
        }
        #expect(competingDraft.autoMountRecovery == false)
        let after = try FileManager.default.attributesOfItem(atPath: lock.path)[.systemFileNumber] as? NSNumber
        #expect(before == after)
        #expect(try repository.read().revision == committed.revision)
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("automnt.plist").path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test func independentSwitchesSurviveManagedMerge() throws {
        let encoder = PropertyListEncoder()
        var original = AutomntConfig()
        original.automationEnabled = false
        original.autoMountRecovery = true
        var next = original
        next.automationEnabled = true
        next.autoMountRecovery = false
        let merged = mergeConfigPlistValue(
            original: try PropertyListSerialization.propertyList(from: encoder.encode(original), format: nil),
            generated: try PropertyListSerialization.propertyList(from: encoder.encode(next), format: nil), context: .root)
        let bytes = try PropertyListSerialization.data(fromPropertyList: merged, format: .xml, options: 0)
        let decoded = try PropertyListDecoder().decode(AutomntConfig.self, from: bytes)
        #expect(decoded.isAutomationEnabled)
        #expect(!decoded.isAutoMountRecoveryEnabled)
        #expect(AutomntConfig().isAutomationEnabled)
    }
}
