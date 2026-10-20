import Foundation
import AutomntCore

/// Only nonsecret operation metadata is Codable. Credential bytes have a separate
/// bounded binary section and must only travel through inherited anonymous pipes.
public enum WorkerOperation: String, Codable, Sendable { case mount, unmount, health, cleanup }

public struct WorkerMountRequest: Codable, Sendable {
    public let schema: Int
    public let operation: WorkerOperation
    public let host: HostConfig
    public let share: SMBShareConfig
    public let expiresAtUptime: TimeInterval
    public let revision: ConfigRevision
    public let generation: UInt64
    public let operationID: UUID
    public let manuallyRequested: Bool?
    public init(host: HostConfig, share: SMBShareConfig, expiresAtUptime: TimeInterval,
                revision: ConfigRevision, generation: UInt64, operationID: UUID = UUID(), operation: WorkerOperation = .mount, manuallyRequested: Bool = false) {
        self.manuallyRequested = manuallyRequested ? true : nil
        self.operation = operation
        self.operationID = operationID
        self.revision = revision
        self.generation = generation
        schema = 1
        self.host = host
        self.share = share
        self.expiresAtUptime = expiresAtUptime
    }
}

public struct WorkerMountResponse: Codable, Sendable {
    public let schema: Int
    public let observation: VolumeObservation?
    public let postMount: PostMountResult
    public let issue: AutomntIssue?
    /// Any timeout/path mismatch requires kernel reconciliation before another mount.
    public let requiresReconciliation: Bool
    public init(observation: VolumeObservation? = nil, postMount: PostMountResult = .notRequested,
                issue: AutomntIssue? = nil, requiresReconciliation: Bool = false) {
        schema = 1
        self.observation = observation
        self.postMount = postMount
        self.issue = issue
        self.requiresReconciliation = requiresReconciliation
    }
}

public enum WorkerPipeProtocol {
    public static let maximumFrameBytes = 128 * 1024
    public static let maximumMetadataBytes = 64 * 1024
    public static let maximumCredentialBytes = 16 * 1024

    public static func encode(request: WorkerMountRequest, credential: MemoryCredential) throws -> Data {
        let metadata = try JSONEncoder().encode(request)
        let username = Data(credential.username.utf8)
        guard metadata.count <= maximumMetadataBytes,
              username.count <= maximumCredentialBytes,
              credential.password.count <= maximumCredentialBytes,
              request.operation == .mount ? (!username.isEmpty && !credential.password.isEmpty) : (username.isEmpty && credential.password.isEmpty) else { throw AutomntIssue.invalidConfiguration }
        var body = Data()
        for part in [metadata, username, credential.password] {
            appendLength(part.count, to: &body)
            body.append(part)
        }
        return try frame(body)
    }

    public static func decodeRequest(_ framed: Data) throws -> (WorkerMountRequest, MemoryCredential) {
        let body = try unframe(framed)
        var offset = 0
        let metadata = try field(body, offset: &offset, maximum: maximumMetadataBytes)
        let usernameBytes = try field(body, offset: &offset, maximum: maximumCredentialBytes, allowEmpty: true)
        let password = try field(body, offset: &offset, maximum: maximumCredentialBytes, allowEmpty: true)
        guard offset == body.count, let username = String(data: usernameBytes, encoding: .utf8),
              !username.contains("\0"),
              let passwordText = String(data: password, encoding: .utf8), !passwordText.contains("\0") else {
            throw AutomntIssue.invalidConfiguration
        }
        let request = try JSONDecoder().decode(WorkerMountRequest.self, from: metadata)
        guard request.schema == 1, request.expiresAtUptime.isFinite,
              request.operation == .mount ? (!username.isEmpty && !password.isEmpty) : (username.isEmpty && password.isEmpty) else { throw AutomntIssue.invalidConfiguration }
        return (request, MemoryCredential(username: username, password: password))
    }

    public static func encode(response: WorkerMountResponse) throws -> Data {
        try frame(JSONEncoder().encode(response))
    }
    public static func decodeResponse(_ data: Data) throws -> WorkerMountResponse {
        let response = try JSONDecoder().decode(WorkerMountResponse.self, from: unframe(data))
        guard response.schema == 1,
              !(response.observation != nil && response.issue != nil),
              response.observation != nil || response.issue != nil else { throw AutomntIssue.invalidConfiguration }
        return response
    }

    /// Accept success only for the requested operation, identity and exact path.
    public static func validate(response: WorkerMountResponse, for request: WorkerMountRequest) throws {
        guard let observation = response.observation else { return }
        guard response.issue == nil,
              (request.operation == .health || observation.issue == nil),
              observation.identity == smbResourceIdentity(request.share.smbURL) else { throw AutomntIssue.pathConflict }
        switch request.operation {
        case .mount:
            guard observation.actualPath == URL(fileURLWithPath: request.share.mountPoint).standardizedFileURL.path,
                  observation.status == .evaluating else { throw AutomntIssue.pathConflict }
        case .health:
            guard observation.actualPath == URL(fileURLWithPath: request.share.mountPoint).standardizedFileURL.path,
                  response.postMount == .notRequested,
                  (observation.status == .healthy && observation.issue == nil) ||
                  (observation.status == .failed && observation.issue == .shareRejected) ||
                  (observation.status == .evaluating && observation.issue == .signalUnavailable) else {
                throw AutomntIssue.pathConflict
            }
        case .unmount, .cleanup:
            guard observation.actualPath == nil, observation.status == .stopped,
                  response.postMount == .notRequested else { throw AutomntIssue.pathConflict }
        }
    }

    /// Reads a single exact frame; callers close the pipe immediately afterwards.
    /// Blocking pipe reads belong only in the child or an independently bounded I/O task.
    public static func readFrame(from handle: FileHandle) throws -> Data {
        let header = try readExactly(4, from: handle)
        let count = try length(header, at: 0)
        guard count > 0, count <= maximumFrameBytes else { throw AutomntIssue.invalidConfiguration }
        return header + (try readExactly(count, from: handle))
    }
    private static func readExactly(_ count: Int, from handle: FileHandle) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let part = try handle.read(upToCount: count - result.count), !part.isEmpty else {
                throw AutomntIssue.invalidConfiguration
            }
            result.append(part)
        }
        return result
    }
    private static func frame(_ body: Data) throws -> Data {
        guard !body.isEmpty, body.count <= maximumFrameBytes else { throw AutomntIssue.invalidConfiguration }
        var data = Data()
        appendLength(body.count, to: &data)
        data.append(body)
        return data
    }
    private static func unframe(_ data: Data) throws -> Data {
        let count = try length(data, at: 0)
        guard count > 0, count <= maximumFrameBytes, data.count == count + 4 else {
            throw AutomntIssue.invalidConfiguration
        }
        return Data(data.dropFirst(4))
    }
    private static func appendLength(_ count: Int, to data: inout Data) {
        let value = UInt32(count)
        data.append(contentsOf: [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255),
                                 UInt8((value >> 8) & 255), UInt8(value & 255)])
    }
    private static func length(_ data: Data, at offset: Int) throws -> Int {
        guard offset >= 0, data.count - offset >= 4 else { throw AutomntIssue.invalidConfiguration }
        return data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
    }
    private static func field(_ data: Data, offset: inout Int, maximum: Int, allowEmpty: Bool = false) throws -> Data {
        let count = try length(data, at: offset)
        offset += 4
        guard (count > 0 || allowEmpty), count <= maximum, count <= data.count - offset else {
            throw AutomntIssue.invalidConfiguration
        }
        let value = Data(data[offset..<(offset + count)])
        offset += count
        return value
    }
}
