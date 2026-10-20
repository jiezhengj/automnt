import Foundation
import AppKit
import AutomntCore

public enum FinderAccess {
    public static func verify(share: SMBShareConfig, path: MountPathState) throws {
        let components = share.mountPoint.split(separator: "/")
        guard let identity = smbResourceIdentity(share.smbURL),
              share.mountPoint.hasPrefix("/"), share.mountPoint != "/",
              !components.contains("."), !components.contains(".."), !share.mountPoint.contains("\0") else {
            throw AutomntIssue.invalidConfiguration
        }
        switch path {
        case .smb(let mounted) where mounted == identity: return
        case .absent: throw AutomntIssue.offline
        case .unavailable: throw AutomntIssue.signalUnavailable
        default: throw AutomntIssue.pathConflict
        }
    }

    @MainActor public static func open(share: SMBShareConfig) throws {
        try verify(share: share, path: NetFSWorkerOperation.mountPathState(at: share.mountPoint))
        guard NSWorkspace.shared.open(URL(fileURLWithPath: share.mountPoint, isDirectory: true)) else {
            throw AutomntIssue.signalUnavailable
        }
    }
}
