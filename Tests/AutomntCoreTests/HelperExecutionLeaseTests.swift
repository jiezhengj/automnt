import Foundation
import Testing
@testable import AutomntCore

struct HelperExecutionLeaseTests {
    @Test func liveHelperPreventsStoppedProofAndExitReleasesLease() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let live = try HelperExecutionLease(authorizedDirectory: directory)
            try live.perform {
                #expect(throws: AutomntIssue.serviceTransitionFailed) {
                    try HelperExecutionLease(authorizedDirectory: directory)
                }
            }
        }
        let stoppedProof = try HelperExecutionLease(authorizedDirectory: directory)
        stoppedProof.perform { #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("helper-execution.lock").path)) }
    }
}
