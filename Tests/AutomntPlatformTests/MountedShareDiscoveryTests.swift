import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

struct MountedShareDiscoveryTests {
    @Test func kernelSourceNeverExportsCredentials() {
        var components = URLComponents()
        components.scheme = "smb"
        components.host = UUID().uuidString
        components.user = UUID().uuidString
        components.password = UUID().uuidString
        components.path = "/" + UUID().uuidString
        let candidate = MountedShareDiscovery.candidate(source: components.string!, mountPoint: "/Volumes/" + UUID().uuidString)
        #expect(candidate != nil)
        let sanitized = candidate.flatMap { URLComponents(string: $0.share.smbURL) }
        #expect(sanitized?.user == nil)
        #expect(sanitized?.password == nil)
        #expect(sanitized?.host == components.host)
        #expect(sanitized?.path == components.path)
    }
    @Test func malformedMetadataCannotBecomeInput() {
        #expect(MountedShareDiscovery.candidate(source: "file:///", mountPoint: "/") == nil)
        #expect(MountedShareDiscovery.candidate(source: "smb://", mountPoint: "/") == nil)
    }
}
