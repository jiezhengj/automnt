import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

struct CredentialBoundaryTests {
    @Test func credentialValidationMatchesWorkerMemoryBoundsWithoutKeychainWrites() throws {
        let identity = UUID().uuidString
        let username = UUID().uuidString
        let valid = MemoryCredential(username: username, password: Data(UUID().uuidString.utf8))
        try KeychainCredentialProvider.validate(identity: identity, credential: valid)
        for secret in [Data(), Data([0]), Data([255]), Data(repeating: 65, count: WorkerPipeProtocol.maximumCredentialBytes + 1)] {
            #expect(throws: AutomntIssue.credentialFailure) {
                try KeychainCredentialProvider.validate(identity: identity,
                    credential: MemoryCredential(username: username, password: secret))
            }
        }
        #expect(throws: AutomntIssue.credentialFailure) {
            try KeychainCredentialProvider.validate(identity: identity,
                credential: MemoryCredential(username: "\0", password: valid.password))
        }
        #expect(throws: AutomntIssue.credentialFailure) {
            try KeychainCredentialProvider.validate(identity: "", credential: valid)
        }
    }
}
