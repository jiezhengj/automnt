import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

struct FinderAccessTests {
    @Test func onlyExactConfiguredSMBPathCanOpen() throws {
        let url = "smb://\(UUID().uuidString)/\(UUID().uuidString)"
        let identity = smbResourceIdentity(url)!
        let share = SMBShareConfig(name: UUID().uuidString, smbURL: url, mountPoint: deriveStandardMountPoint(from: url)!)
        try FinderAccess.verify(share: share, path: .smb(identity: identity))
        #expect(throws: AutomntIssue.offline) { try FinderAccess.verify(share: share, path: .absent) }
        #expect(throws: AutomntIssue.signalUnavailable) { try FinderAccess.verify(share: share, path: .unavailable) }
        for path: MountPathState in [.occupied, .smb(identity: UUID().uuidString)] {
            #expect(throws: AutomntIssue.pathConflict) { try FinderAccess.verify(share: share, path: path) }
        }
        let customPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let custom = SMBShareConfig(name: share.name, smbURL: url, mountPoint: customPath)
        try FinderAccess.verify(share: custom, path: .smb(identity: identity))
        #expect(throws: AutomntIssue.pathConflict) { try FinderAccess.verify(share: custom, path: .occupied) }
        for invalid in ["", "/", UUID().uuidString, customPath + "/../", customPath + "/./", customPath + "\0"] {
            let share = SMBShareConfig(name: custom.name, smbURL: url, mountPoint: invalid)
            #expect(throws: AutomntIssue.invalidConfiguration) { try FinderAccess.verify(share: share, path: .smb(identity: identity)) }
        }
    }
}
