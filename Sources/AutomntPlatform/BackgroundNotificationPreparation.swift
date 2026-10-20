import Foundation
import AutomntCore

public enum BackgroundNotificationPreparation {
    /// Prepare a count-only intent. Delivery is separate and never restores consumed budget.
    public static func prepare(summary: BackgroundEvaluationSummary, directory: AuthorizedDirectory,
                               snapshot: ConfigSnapshot, generation: UInt64) throws -> FailureNotification? {
        guard snapshot.configuration.isAutomationEnabled, snapshot.configuration.isAutoMountRecoveryEnabled else { return nil }
        let configured = Set(snapshot.configuration.hosts.filter(\.enabled).flatMap { host in
            host.shares.filter(\.enabled).compactMap { smbResourceIdentity($0.smbURL) }
        })
        let recovered = Set(summary.observations.filter { $0.status == .healthy && $0.issue == nil }.map(\.identity))
        let failed = Set(summary.observations.filter {
            $0.status == .failed && $0.issue == .shareRejected
        }.map(\.identity)).intersection(configured)
        guard !failed.subtracting(recovered).isEmpty else { return nil }
        let repository = FileConfigRepository(authorizedDirectory: directory.url)
        let store = BackendStateStore(authorizedDirectory: directory.url)
        let permit = try EvaluationPermit(directory: directory.url, repository: repository,
            expected: snapshot, owner: .app, generation: generation, readBackend: store.read)
        return try permit.perform { _ in
            try RecoveryNotificationPolicy.commit(directory: directory.url, failed: failed, recovered: recovered)
        }
    }
}
