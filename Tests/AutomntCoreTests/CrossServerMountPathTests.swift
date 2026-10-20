import Foundation
import Testing
@testable import AutomntCore

struct CrossServerMountPathTests {
    @Test func sharedLocalFolderRemainsAvailableForBackupServers() {
        let path = "/Volumes/" + UUID().uuidString
        var configuration = AutomntConfig()
        configuration.hosts = (0..<2).map { _ in
            let host = UUID().uuidString
            let share = UUID().uuidString
            return HostConfig(host: host, shares: [SMBShareConfig(name: share, smbURL: "smb://" + host + "/" + share, mountPoint: path)])
        }
        let problems = ConfigurationValidation.problems(in: configuration)
        #expect(problems.isEmpty)
        configuration.hosts[1].shares.append(configuration.hosts[1].shares[0])
        #expect(ConfigurationValidation.problems(in: configuration).contains {
            $0.reason == .duplicateMountPath && $0.hostIndex == 1 && $0.shareIndex == 1
        })
        configuration.hosts[1].shares.removeLast()
        configuration.hosts[1].shares[0].mountPoint = "/Volumes/" + UUID().uuidString
        #expect(ConfigurationValidation.problems(in: configuration).isEmpty)
    }
}
