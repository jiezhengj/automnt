import Foundation

/// A launch intent is written before a child can touch the kernel. Any crash or
/// ambiguous outcome leaves it pending, blocking subsequent launches until repair.
public struct WorkerOperationStore: Sendable {
    private struct Record: Codable {
        let schema: Int
        let id: UUID
        let revision: ConfigRevision
        let generation: UInt64
        var pending: Bool
    }
    private let directory: URL
    private var url: URL { directory.appendingPathComponent("worker-operation.plist") }
    public init(authorizedDirectory: URL) { directory = authorizedDirectory }

    public func begin(revision: ConfigRevision, generation: UInt64, id: UUID = UUID()) throws -> UUID {
        let lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
        return try withExtendedLifetime(lock) {
            do {
                let previous = try read()
                guard !previous.pending else { throw AutomntIssue.signalUnavailable }
            } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == 2 { }
            let record = Record(schema: 1, id: id, revision: revision, generation: generation, pending: true)
            try write(record)
            return record.id
        }
    }

    /// Atomically records intent, then invokes Process.run. A throwing launch must
    /// mean no child was created; never include pipe I/O or child work in this closure.
    public func launch(revision: ConfigRevision, generation: UInt64, id: UUID,
                       start: () throws -> Void) throws -> UUID {
        let operationID = try begin(revision: revision, generation: generation, id: id)
        do { try start() }
        catch {
            let launchError = error
            // If clearing intent fails, keep reporting uncertainty; do not hide it.
            try complete(id: operationID, revision: revision, generation: generation)
            throw launchError
        }
        return operationID
    }

    /// Only a normally exited worker with a verified matching mount response can
    /// complete here. Timeout, transport failure, or interrupted parent stays pending.
    public func complete(id: UUID, revision: ConfigRevision, generation: UInt64) throws {
        let lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
        try withExtendedLifetime(lock) {
            var record = try read()
            guard record.id == id, record.pending, record.revision == revision, record.generation == generation else { throw AutomntIssue.configurationConflict }
            record.pending = false
            try write(record)
        }
    }
    /// Caller holds evaluation.lock. Ties the pipe request to the durable launch intent.
    public func verifyPending(id: UUID, revision: ConfigRevision, generation: UInt64) throws {
        let record = try read()
        guard record.pending, record.id == id, record.revision == revision,
              record.generation == generation else { throw AutomntIssue.configurationConflict }
    }
    /// Caller holds evaluation.lock; a pending child forbids session/state advancement too.
    public func verifyIdle() throws {
        do {
            guard try !read().pending else { throw AutomntIssue.signalUnavailable }
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == 2 { }
    }

    private func read() throws -> Record {
        let record = try PropertyListDecoder().decode(Record.self, from: PrivateAtomicFile.read(url))
        guard record.schema == 1 else { throw AutomntIssue.signalUnavailable }
        return record
    }
    private func write(_ record: Record) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try PrivateAtomicFile.replace(encoder.encode(record), at: url)
    }
}
