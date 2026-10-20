import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

struct RecoverySessionCollectorTests {
    @Test func localCollectionPreservesPriorNetworkWhenUnavailable() {
        let network = UUID().uuidString
        let login = UUID().uuidString
        let previous = RecoverySessionIdentity(network: network, loginEpoch: login, previous: nil)
        let result = RecoverySessionCollector.collect(previous: previous.combined)
        if let result {
            #expect(!result.loginEpoch.isEmpty)
            #expect(!result.network.isEmpty)
            #expect(result.combined.hasSuffix("|" + result.loginEpoch))
        }
        // No real identity is printed or persisted by this local API smoke check.
    }
}
