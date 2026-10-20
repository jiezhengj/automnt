import Foundation

public enum RecoverySessionCommit {
    /// Call within EvaluationPermit.perform; no damaged state or pending child is replaced.
    @discardableResult
    public static func advance(directory: URL, identity: RecoverySessionIdentity?,
                               mountedKeys: Set<String>) throws -> MountRecoveryStoreLoad {
        try WorkerOperationStore(authorizedDirectory: directory).verifyIdle()
        let repository = RecoveryStateRepository(url: directory.appendingPathComponent("mount-recovery-state.plist"))
        let original = repository.read()
        guard original.isReadable else { throw AutomntIssue.signalUnavailable }
        guard let identity else { return original }
        var state = original.file
        RecoverySessionPolicy.advance(&state, to: identity, mountedKeys: mountedKeys)
        if state != original.file { try repository.save(state) }
        return .loaded(state)
    }
}
