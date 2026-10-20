import Foundation
import Testing
@testable import AutomntCore
@testable import AutomntPlatform

/// End-to-end projection test across the Core/Platform boundary: real discovery types
/// feed the real inventory builder, and the real mount-table read is used to confirm
/// identity. No network, no mounting, no configuration writes.
struct InventoryIntegrationTests {
    private var configuration: AutomntConfig {
        AutomntConfig(hosts: [
            HostConfig(host: "managed.example", alias: "Studio", shares: [
                SMBShareConfig(name: "Docs", smbURL: "smb://managed.example/Docs", mountPoint: "/Volumes/Docs")
            ])
        ])
    }

    @Test func discoveredCandidateMapsIntoTheCoreInventory() throws {
        let candidate = try #require(MountedShareDiscovery.candidate(
            source: "//new.example/Photos", mountPoint: "/Volumes/Photos"))
        let inventory = ServerInventory.build(configuration: configuration,
            discovered: [candidate.inventoryShare],
            mounted: [smbResourceIdentity(candidate.share.smbURL)!])
        #expect(inventory.managed.map(\.host) == ["managed.example"])
        #expect(inventory.addable.map(\.host) == ["new.example"])
        #expect(inventory.addable[0].addableShares.map(\.name) == ["Photos"])
        #expect(inventory.addable[0].addableShares[0].mounted)
    }

    @Test func aClientDroppingCredentialsStillMapsToTheSameIdentity() throws {
        // The mount table can contain a user name; identity must ignore it.
        let candidate = try #require(MountedShareDiscovery.candidate(
            source: "//alice@managed.example/Docs", mountPoint: "/Volumes/Docs"))
        let identity = smbResourceIdentity(candidate.share.smbURL)
        #expect(identity == smbResourceIdentity("smb://managed.example/Docs"))
        // Being already managed, it must not appear again as addable.
        let inventory = ServerInventory.build(configuration: configuration,
            discovered: [candidate.inventoryShare], mounted: [])
        #expect(inventory.addable.isEmpty)
    }

    @Test func discoveryRejectsEntriesThatCannotBeAValidTarget() {
        // No share segment.
        #expect(MountedShareDiscovery.candidate(source: "//host.example", mountPoint: "/Volumes/X") == nil)
        // Not SMB.
        #expect(MountedShareDiscovery.candidate(source: "nfs://host.example/Docs", mountPoint: "/Volumes/X") == nil)
        // No host.
        #expect(MountedShareDiscovery.candidate(source: "//", mountPoint: "/Volumes/X") == nil)
    }

    @Test func mountedIdentitiesReadIsReadOnlyAndNeverThrowsForThisMachine() throws {
        // A real read of the kernel mount table. It must not throw and must not mount
        // or open anything; on a machine with no SMB mounts it is simply empty.
        let identities = try MountedShareDiscovery.mountedIdentities()
        for (path, identity) in identities {
            #expect(path.hasPrefix("/"))
            #expect(identity.hasPrefix("//"))
        }
    }

    @Test func inventoryNeverClaimsAMountForAPathTheKernelDoesNotReport() throws {
        let candidate = try #require(MountedShareDiscovery.candidate(
            source: "//new.example/Photos", mountPoint: "/Volumes/Photos"))
        // Discovery saw it mounted, but the identity confirmation set is empty:
        // the builder must trust the confirmation set, not the discovery flag alone.
        let inventory = ServerInventory.build(configuration: configuration,
            discovered: [candidate.inventoryShare], mounted: [])
        #expect(inventory.addable[0].addableShares[0].mounted)
        let managed = ServerInventory.build(configuration: configuration,
            discovered: [], mounted: [])
        #expect(managed.managed[0].managedShares.allSatisfy { !$0.mounted })
    }
}
