import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

struct WorkerPipeTests {
    @Test func unmountFrameHasNoCredentialAndRejectsSecrets() throws {
        let host = HostConfig(host: UUID().uuidString)
        let share = SMBShareConfig(name: UUID().uuidString, smbURL: "", mountPoint: "")
        let request = WorkerMountRequest(host: host, share: share,
            expiresAtUptime: ProcessInfo.processInfo.systemUptime + 1,
            revision: ConfigRevision(digest: UUID().uuidString), generation: 1, operation: .unmount)
        let empty = MemoryCredential(username: "", password: Data())
        let frame = try WorkerPipeProtocol.encode(request: request, credential: empty)
        let (decoded, credential) = try WorkerPipeProtocol.decodeRequest(frame)
        #expect(decoded.operation == .unmount)
        #expect(credential.username.isEmpty && credential.password.isEmpty)
        #expect(throws: AutomntIssue.invalidConfiguration) {
            try WorkerPipeProtocol.encode(request: request,
                credential: MemoryCredential(username: UUID().uuidString, password: Data(UUID().uuidString.utf8)))
        }
        let mount = WorkerMountRequest(host: host, share: share, expiresAtUptime: request.expiresAtUptime,
                                      revision: request.revision, generation: 1)
        #expect(throws: AutomntIssue.invalidConfiguration) {
            try WorkerPipeProtocol.encode(request: mount, credential: empty)
        }
    }

    @Test func cleanupUsesSecretFreeFrameAndRequiresConfirmedAbsence() throws {
        let host = HostConfig(host: UUID().uuidString)
        let url = "smb://\(host.host)/\(UUID().uuidString)"
        let share = SMBShareConfig(name: UUID().uuidString, smbURL: url, mountPoint: deriveStandardMountPoint(from: url)!)
        let request = WorkerMountRequest(host: host, share: share,
            expiresAtUptime: ProcessInfo.processInfo.systemUptime + 1,
            revision: ConfigRevision(digest: UUID().uuidString), generation: 1, operation: .cleanup)
        let frame = try WorkerPipeProtocol.encode(request: request, credential: MemoryCredential(username: "", password: Data()))
        #expect(try WorkerPipeProtocol.decodeRequest(frame).0.operation == .cleanup)
        #expect(throws: AutomntIssue.invalidConfiguration) {
            try WorkerPipeProtocol.encode(request: request,
                credential: MemoryCredential(username: UUID().uuidString, password: Data(UUID().uuidString.utf8)))
        }
        try WorkerPipeProtocol.validate(response: WorkerMountResponse(observation:
            VolumeObservation(identity: smbResourceIdentity(url)!, status: .stopped, actualPath: nil, observedAt: Date())), for: request)
        #expect(throws: AutomntIssue.pathConflict) {
            try WorkerPipeProtocol.validate(response: WorkerMountResponse(observation:
                VolumeObservation(identity: smbResourceIdentity(url)!, status: .failed,
                    actualPath: share.mountPoint, observedAt: Date(), issue: .shareRejected)), for: request)
        }
    }

    @Test func responseMustMatchRequestedOperation() throws {
        let host = HostConfig(host: UUID().uuidString)
        let url = "smb://\(host.host)/\(UUID().uuidString)"
        let share = SMBShareConfig(name: UUID().uuidString, smbURL: url,
                                  mountPoint: deriveStandardMountPoint(from: url)!)
        let request = WorkerMountRequest(host: host, share: share,
            expiresAtUptime: ProcessInfo.processInfo.systemUptime + 1,
            revision: ConfigRevision(digest: UUID().uuidString), generation: 1, operation: .unmount)
        let identity = smbResourceIdentity(url)!
        try WorkerPipeProtocol.validate(response: WorkerMountResponse(observation:
            VolumeObservation(identity: identity, status: .stopped, actualPath: nil, observedAt: Date())), for: request)
        #expect(throws: AutomntIssue.pathConflict) {
            try WorkerPipeProtocol.validate(response: WorkerMountResponse(observation:
                VolumeObservation(identity: identity, status: .evaluating, actualPath: share.mountPoint, observedAt: Date())), for: request)
        }
        #expect(throws: AutomntIssue.pathConflict) {
            try WorkerPipeProtocol.validate(response: WorkerMountResponse(observation:
                VolumeObservation(identity: UUID().uuidString, status: .stopped, actualPath: nil, observedAt: Date())), for: request)
        }
    }

    @Test func healthFrameAndEvidenceRejectSecretsAndUnrelatedResponses() throws {
        let host = HostConfig(host: UUID().uuidString)
        let url = "smb://\(host.host)/\(UUID().uuidString)"
        let share = SMBShareConfig(name: UUID().uuidString, smbURL: url, mountPoint: deriveStandardMountPoint(from: url)!)
        let request = WorkerMountRequest(host: host, share: share, expiresAtUptime: ProcessInfo.processInfo.systemUptime + 1,
            revision: ConfigRevision(digest: UUID().uuidString), generation: 1, operation: .health)
        let frame = try WorkerPipeProtocol.encode(request: request, credential: MemoryCredential(username: "", password: Data()))
        #expect(try WorkerPipeProtocol.decodeRequest(frame).0.operation == .health)
        #expect(throws: AutomntIssue.invalidConfiguration) {
            try WorkerPipeProtocol.encode(request: request,
                credential: MemoryCredential(username: UUID().uuidString, password: Data(UUID().uuidString.utf8)))
        }
        for evidence: VolumeHealthEvidence in [.healthy, .failed, .unavailable] {
            let response = WorkerMountResponse(observation: RecoveryHealthPolicy.observation(identity: smbResourceIdentity(url)!,
                actualPath: share.mountPoint, hostReachable: true, health: evidence, observedAt: Date()))
            let decoded = try WorkerPipeProtocol.decodeResponse(WorkerPipeProtocol.encode(response: response))
            try WorkerPipeProtocol.validate(response: decoded, for: request)
        }
        #expect(throws: AutomntIssue.pathConflict) {
            try WorkerPipeProtocol.validate(response: WorkerMountResponse(observation:
                VolumeObservation(identity: smbResourceIdentity(url)!, status: .evaluating, actualPath: share.mountPoint,
                    observedAt: Date())), for: request)
        }
    }

    @Test func unsignedBundleCannotPassCodeVerification() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: AutomntIssue.authorizationRequired) {
            try BundledCodeVerifier.verify(applicationURL: directory, workerURL: directory.appendingPathComponent(UUID().uuidString))
        }
    }

    @Test func boundedCredentialFrameRoundTripsAndRejectsTruncation() throws {
        let host = HostConfig(host: UUID().uuidString)
        let share = SMBShareConfig(name: UUID().uuidString, smbURL: "", mountPoint: "")
        let request = WorkerMountRequest(host: host, share: share,
            expiresAtUptime: ProcessInfo.processInfo.systemUptime + 1,
            revision: ConfigRevision(digest: UUID().uuidString), generation: 1)
        let credential = MemoryCredential(username: UUID().uuidString, password: Data(UUID().uuidString.utf8))
        let data = try WorkerPipeProtocol.encode(request: request, credential: credential)
        let (decoded, secret) = try WorkerPipeProtocol.decodeRequest(data)
        #expect(decoded.host == host)
        #expect(decoded.revision == request.revision)
        #expect(secret.username == credential.username)
        #expect(secret.password == credential.password)
        #expect(throws: (any Error).self) { try WorkerPipeProtocol.decodeRequest(Data(data.dropLast())) }
        #expect(throws: (any Error).self) { try WorkerPipeProtocol.decodeRequest(data + Data([0])) }
        #expect(throws: (any Error).self) {
            try WorkerPipeProtocol.encode(request: request,
                credential: MemoryCredential(username: credential.username,
                    password: Data(repeating: 1, count: WorkerPipeProtocol.maximumCredentialBytes + 1)))
        }
        let response = try WorkerPipeProtocol.encode(response: WorkerMountResponse(issue: .timeout, requiresReconciliation: true))
        #expect(response.range(of: credential.password) == nil)
        let restored = try WorkerPipeProtocol.decodeResponse(response)
        #expect(restored.issue == .timeout)
        #expect(restored.requiresReconciliation)
        #expect(throws: AutomntIssue.invalidConfiguration) {
            try WorkerPipeProtocol.decodeResponse(WorkerPipeProtocol.encode(response: WorkerMountResponse()))
        }
    }

    @Test func oversizedAndTruncatedPipeFramesFailBeforePayloadAllocation() throws {
        let pipe = Pipe()
        try pipe.fileHandleForWriting.write(contentsOf: Data([255, 255, 255, 255]))
        try pipe.fileHandleForWriting.close()
        #expect(throws: AutomntIssue.invalidConfiguration) {
            try WorkerPipeProtocol.readFrame(from: pipe.fileHandleForReading)
        }
        try pipe.fileHandleForReading.close()
        let truncated = Pipe()
        try truncated.fileHandleForWriting.write(contentsOf: Data([0, 0, 0, 5, 1]))
        try truncated.fileHandleForWriting.close()
        #expect(throws: AutomntIssue.invalidConfiguration) {
            try WorkerPipeProtocol.readFrame(from: truncated.fileHandleForReading)
        }
        try truncated.fileHandleForReading.close()
    }
}
