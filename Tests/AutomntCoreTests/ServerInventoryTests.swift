import Foundation
import Testing
@testable import AutomntCore

struct ServerInventoryTests {
    private var configuration: AutomntConfig {
        var config = AutomntConfig(hosts: [
            HostConfig(host: "a.example", alias: "Studio", shares: [
                SMBShareConfig(name: "Docs", smbURL: "smb://a.example/Docs", mountPoint: "/Volumes/Docs"),
                SMBShareConfig(name: "Media", smbURL: "smb://a.example/Media", mountPoint: "/Volumes/Media")
            ]),
            HostConfig(host: "b.example", shares: [
                SMBShareConfig(name: "Archive", smbURL: "smb://b.example/Archive", mountPoint: "/Volumes/Archive")
            ])
        ])
        config.autoMountRecovery = true
        return config
    }

    @Test func managedServersKeepSavedOrderAndDiscoveryDoesNotReorderThem() {
        let discovered = [
            ServerInventory.DiscoveredShare(host: "zzz.example", name: "Late", smbURL: "smb://zzz.example/Late", mountPoint: "/Volumes/Late"),
            ServerInventory.DiscoveredShare(host: "a.example", name: "Extra", smbURL: "smb://a.example/Extra", mountPoint: "/Volumes/Extra")
        ]
        let inventory = ServerInventory.build(configuration: configuration, discovered: discovered, mounted: [])
        #expect(inventory.managed.map(\.host) == ["a.example", "b.example"])
        #expect(inventory.managed.map(\.managedIndex) == [0, 1])
    }

    @Test func alreadyManagedShareIsNotOfferedAgainAsAddable() {
        let discovered = [
            // Same identity as a managed share.
            ServerInventory.DiscoveredShare(host: "a.example", name: "Docs", smbURL: "smb://a.example/Docs", mountPoint: "/Volumes/Docs"),
            // Genuinely new share on the same server.
            ServerInventory.DiscoveredShare(host: "a.example", name: "Extra", smbURL: "smb://a.example/Extra", mountPoint: "/Volumes/Extra")
        ]
        let inventory = ServerInventory.build(configuration: configuration, discovered: discovered, mounted: [])
        // a.example is already managed, so its new share is not a separate addable server.
        #expect(inventory.addable.isEmpty)
        #expect(inventory.managed[0].managedShares.map(\.name) == ["Docs", "Media"])
        #expect(inventory.managed[0].addableShares.map(\.name) == ["Extra"])
        #expect(inventory.managed[0].summary.addableCount == 1)
    }

    @Test func normalizedServerDiscoveryDeduplicatesSharesAndSeparatesPorts() {
        let discovered = [
            ServerInventory.DiscoveredShare(host: " A.EXAMPLE ", name: "Extra", smbURL: "smb://a.example/Extra", mountPoint: "/Volumes/Extra"),
            ServerInventory.DiscoveredShare(host: "a.example", name: "Extra duplicate", smbURL: "smb://A.EXAMPLE:445/extra", mountPoint: "/Volumes/Extra2"),
            ServerInventory.DiscoveredShare(host: "a.example", port: 1445, name: "Other", smbURL: "smb://a.example:1445/Extra", mountPoint: "/Volumes/Other"),
            ServerInventory.DiscoveredShare(host: "b.example", name: "New", smbURL: "smb://b.example/New", mountPoint: "/Volumes/New")
        ]
        let inventory = ServerInventory.build(configuration: configuration, discovered: discovered, mounted: [])
        #expect(inventory.managed.map(\.identity) == ["a.example:445", "b.example:445"])
        #expect(inventory.managed[0].addableShares.map(\.name) == ["Extra"])
        #expect(inventory.managed[1].addableShares.map(\.name) == ["New"])
        #expect(inventory.addable.map(\.identity) == ["a.example:1445"])
        #expect(inventory.addable[0].addableShares.count == 1)
    }

    @Test func unmanagedDiscoveredServerBecomesAddableAndNeverSortable() {
        let discovered = [
            ServerInventory.DiscoveredShare(host: "new.example", name: "Photos", smbURL: "smb://new.example/Photos", mountPoint: "/Volumes/Photos"),
            ServerInventory.DiscoveredShare(host: "new.example", name: "Audio", smbURL: "smb://new.example/Audio", mountPoint: "/Volumes/Audio")
        ]
        let inventory = ServerInventory.build(configuration: configuration, discovered: discovered, mounted: [])
        #expect(inventory.addable.count == 1)
        #expect(inventory.addable[0].host == "new.example")
        #expect(inventory.addable[0].managedIndex == nil)
        #expect(!inventory.addable[0].isManaged)
        #expect(inventory.addable[0].addableShares.map(\.name) == ["Audio", "Photos"])
        #expect(inventory.managed.map(\.host) == ["a.example", "b.example"])
    }

    @Test func managedShareStaysListedWhenNotMounted() {
        let inventory = ServerInventory.build(configuration: configuration, discovered: [], mounted: [])
        #expect(inventory.managed.count == 2)
        #expect(inventory.managed[0].managedShares.allSatisfy { !$0.mounted })
        #expect(inventory.managed[0].summary == ServerInventory.Summary(managedCount: 2, addableCount: 0, problemCount: 0))
    }

    @Test func mountedFlagComesOnlyFromObservedKernelIdentity() {
        let identity = smbResourceIdentity("smb://a.example/Docs")!
        let inventory = ServerInventory.build(configuration: configuration, discovered: [], mounted: [identity])
        let docs = inventory.managed[0].managedShares.first { $0.name == "Docs" }
        let media = inventory.managed[0].managedShares.first { $0.name == "Media" }
        #expect(docs?.mounted == true)
        #expect(media?.mounted == false)
    }

    @Test func aliasIsUsedForDisplayButHostRemainsTheIdentity() {
        let inventory = ServerInventory.build(configuration: configuration, discovered: [], mounted: [])
        #expect(inventory.managed[0].displayName == "Studio")
        #expect(inventory.managed[0].identity == "a.example:445")
    }

    @Test func bonjourServiceSuffixIsHiddenFromDisplayOnly() {
        var config = AutomntConfig()
        config.hosts = [HostConfig(host: "Nas._smb._tcp.local", port: 445,
            shares: [SMBShareConfig(name: "Docs", smbURL: "smb://Nas._smb._tcp.local/Docs",
                                    mountPoint: "/Volumes/Docs")])]
        let inventory = ServerInventory.build(configuration: config, discovered: [], mounted: [])
        #expect(inventory.managed[0].displayName == "Nas")
        #expect(inventory.managed[0].identity == "nas._smb._tcp.local:445")
    }

    @Test func problemsAreDeclaredNotInferred() {
        let identity = smbResourceIdentity("smb://a.example/Media")!
        let inventory = ServerInventory.build(configuration: configuration, discovered: [], mounted: [],
                                              foundProblems: [identity])
        #expect(inventory.managed[0].summary.problemCount == 1)
        #expect(inventory.managed[1].summary.problemCount == 0)
    }

    @Test func noConfigurationStillShowsDiscoveredCandidates() {
        let discovered = [
            ServerInventory.DiscoveredShare(host: "only.example", name: "Docs", smbURL: "smb://only.example/Docs", mountPoint: "/Volumes/Docs")
        ]
        let inventory = ServerInventory.build(configuration: nil, discovered: discovered, mounted: [])
        #expect(inventory.managed.isEmpty)
        #expect(inventory.addable.map(\.host) == ["only.example"])
    }

    @Test func configurationWithoutDiscoveryShowsNoAddableGroup() {
        let inventory = ServerInventory.build(configuration: AutomntConfig(), discovered: [], mounted: [])
        #expect(inventory.managed.isEmpty)
        #expect(inventory.addable.isEmpty)
    }

    @Test func firstShareAddLandsAtTheEndOfManagedOrder() {
        let snapshot = ServerInventory.build(configuration: configuration, discovered: [], mounted: [])
        let candidate = ManagedMembership.Candidate(host: "new.example", name: "Photos",
            smbURL: "smb://new.example/Photos", mountPoint: "/Volumes/Photos")
        let updated = ManagedMembership.adding(candidate, to: configuration).configuration!
        let after = ServerInventory.build(configuration: updated, discovered: [], mounted: [])
        #expect(after.managed.map(\.host) == snapshot.managed.map(\.host) + ["new.example"])
        #expect(after.managed.last?.managedIndex == 2)
    }
}
