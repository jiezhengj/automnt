import Foundation
import Testing
@testable import AutomntCore

struct ManualMountCommitTests {
    @Test func onlyMatchingObservedMountClearsEjectIntent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = RecoveryStateRepository(url: directory.appendingPathComponent("mount-recovery-state.plist"))
        let identity = UUID().uuidString
        var state = MountRecoveryStateFile()
        state.volumes[identity] = MountRecoveryVolumeRecord(volumeKey: identity, state: .suppressed,
            suppressionBoundary: "network|login", attemptCount: 3)
        try repository.save(state)
        for path: MountPathState in [.absent, .occupied, .unavailable, .smb(identity: UUID().uuidString)] {
            #expect(throws: AutomntIssue.self) {
                try UserEjectCommit.resumeAfterManualMount(identity: identity, directory: directory, path: path)
            }
            #expect(repository.read().file.volumes[identity]?.state == .suppressed)
        }
        try UserEjectCommit.resumeAfterManualMount(identity: identity, directory: directory, path: .smb(identity: identity))
        let record = repository.read().file.volumes[identity]
        #expect(record?.state == .attached)
        #expect(record?.suppressionBoundary == nil)
        #expect(record?.attemptCount == 0)
        #expect(record?.everHealthyMounted == false)
    }
}
