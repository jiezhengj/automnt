import Foundation
import AutomntCore

public enum BackgroundObservationCommit {
    /// Keep observations tied to the exact active backend that produced them.
    /// Validation and atomic replacement share evaluation.lock with handoff.
    public static func commit(_ summary: BackgroundEvaluationSummary, state: BackendState,
                              directory: URL) throws {
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.read()
        guard snapshot.revision == state.revision else { throw AutomntIssue.configurationConflict }
        let store = BackendStateStore(authorizedDirectory: directory)
        let permit = try EvaluationPermit(directory: directory, repository: repository,
            expected: snapshot, owner: .app, generation: state.generation, readBackend: store.read)
        try permit.perform { _ in
            guard try store.read() == state else { throw AutomntIssue.configurationConflict }
            try PrivateAtomicFile.replace(PropertyListEncoder().encode(summary),
                at: directory.appendingPathComponent("background-observations.plist"))
        }
    }
}
