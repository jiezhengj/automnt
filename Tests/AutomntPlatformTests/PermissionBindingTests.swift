import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

struct PermissionBindingTests {
    @Test func rejectsIncompleteAndOversizedFrames() throws {
        for input in [Data(), Data([0, 0]), Data([0, 0, 0, 0]), Data([0, 1, 0, 1]), Data([0, 0, 0, 3, 1])] {
            let pipe = Pipe()
            try pipe.fileHandleForWriting.write(contentsOf: input)
            try pipe.fileHandleForWriting.close()
            defer { try? pipe.fileHandleForReading.close() }
            #expect(throws: AutomntIssue.authorizationRequired) {
                try PermissionBinding.receiveFrame(descriptor: pipe.fileHandleForReading.fileDescriptor,
                    deadline: ContinuousClock.now.advanced(by: .seconds(1)))
            }
        }
    }

    @Test func openPipeCannotWaitPastDeadline() throws {
        let pipe = Pipe()
        defer { try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
        let started = ContinuousClock.now
        #expect(throws: AutomntIssue.timeout) {
            try PermissionBinding.receiveFrame(descriptor: pipe.fileHandleForReading.fileDescriptor,
                deadline: started.advanced(by: .milliseconds(100)))
        }
        #expect(ContinuousClock.now - started < .seconds(1))
    }

    @Test func readsFramedPayloadWithoutTreatingEOFAsTimeout() throws {
        let pipe = Pipe()
        try pipe.fileHandleForWriting.write(contentsOf: Data([0, 0, 0, 3, 10, 20, 30]))
        try pipe.fileHandleForWriting.close()
        defer { try? pipe.fileHandleForReading.close() }
        let received = try PermissionBinding.receiveFrame(descriptor: pipe.fileHandleForReading.fileDescriptor,
            deadline: ContinuousClock.now.advanced(by: .seconds(1)))
        #expect(received == Data([10, 20, 30]))
    }
}
