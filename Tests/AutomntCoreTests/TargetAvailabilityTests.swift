import Testing
@testable import AutomntCore

/// 目标可用性的动作边界：兄弟主机承载的挂载可打开，但弹出/挂载仍归承载条目。
struct TargetAvailabilityTests {
    @Test func peerCarriedMountIsAvailableButNotMountedByIdentity() {
        #expect(TargetAvailability.availableViaPeer.isAvailableAtConfiguredPath)
        #expect(!TargetAvailability.availableViaPeer.isMountedByIdentity)
        #expect(TargetAvailability.usable.isAvailableAtConfiguredPath)
        #expect(TargetAvailability.usable.isMountedByIdentity)
        #expect(!TargetAvailability.locationOccupied.isAvailableAtConfiguredPath)
        #expect(!TargetAvailability.notMounted.isAvailableAtConfiguredPath)
    }
}
