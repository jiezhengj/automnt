import Foundation

public let mountRecoverySchemaVersion = 1

public enum MountRecoveryVolumeState: String, Codable, Equatable, Sendable {
    case attached
    case lost
    case pendingRecovery = "pending-recovery"
    case recovering
    case suppressed
}

public struct MountRecoveryVolumeRecord: Codable, Equatable, Sendable {
    public init(volumeKey: String, state: MountRecoveryVolumeState = .attached,
                suppressionBoundary: String? = nil, repairEjectEvidence: Bool = false,
                everHealthyMounted: Bool = false, attemptCount: Int = 0, updatedAt: Double = 0,
                notificationCount: Int = 0) {
        self.volumeKey = volumeKey; self.state = state; self.suppressionBoundary = suppressionBoundary
        self.repairEjectEvidence = repairEjectEvidence; self.everHealthyMounted = everHealthyMounted
        self.attemptCount = attemptCount; self.updatedAt = updatedAt; self.notificationCount = notificationCount
    }
    public var volumeKey: String
    public var state: MountRecoveryVolumeState = .attached
    public var suppressionBoundary: String?
    public var repairEjectEvidence: Bool = false
    public var everHealthyMounted: Bool = false
    public var lastAttemptAt: Double?
    public var attemptOperationID: UUID?
    public var attemptCount: Int = 0
    public var updatedAt: Double = 0
    /// 同一可达会话内的通知计数（契约 §4 会话级上限：至多 2 条）。
    public var notificationCount: Int = 0

    public enum CodingKeys: String, CodingKey {
        case volumeKey = "volume_key"
        case state
        case suppressionBoundary = "suppression_boundary"
        case repairEjectEvidence = "repair_eject_evidence"
        case everHealthyMounted = "ever_healthy_mounted"
        case lastAttemptAt = "last_attempt_at"
        case attemptOperationID = "attempt_operation_id"
        case attemptCount = "attempt_count"
        case updatedAt = "updated_at"
        case notificationCount = "notification_count"
    }
}

public enum RecoveryAttemptOutcome: String, Codable, Sendable {
    case mounted
    case hostUnreachable = "host-unreachable"
    case shareRejected = "share-rejected"
    case credentialFailure = "credential-failure"
    case suppressedSkipped = "suppressed-skipped"
}

public struct RecoveryAttempt: Codable, Equatable, Sendable {
    public init(timestamp: Double, outcome: RecoveryAttemptOutcome, sequence: Int) {
        self.timestamp = timestamp; self.outcome = outcome; self.sequence = sequence
    }
    public var timestamp: Double
    public var outcome: RecoveryAttemptOutcome
    public var sequence: Int
}

/// 附属状态文件根结构。
public struct MountRecoveryStateFile: Codable, Equatable, Sendable {
    public init(schemaVersion: Int = mountRecoverySchemaVersion, sessionBoundary: String? = nil,
                volumes: [String: MountRecoveryVolumeRecord] = [:], cleanupLedger: [String: Double] = [:],
                attempts: [String: [RecoveryAttempt]] = [:]) {
        self.schemaVersion = schemaVersion; self.sessionBoundary = sessionBoundary
        self.volumes = volumes; self.cleanupLedger = cleanupLedger; self.attempts = attempts
    }
    public var schemaVersion: Int = mountRecoverySchemaVersion
    /// 当前会话边界标识（网络身份 + 登录纪元）。
    public var sessionBoundary: String?
    public var volumes: [String: MountRecoveryVolumeRecord] = [:]
    /// 清理账：automnt 自身清理过的死卷集合（volumeKey → 时间戳）。
    public var cleanupLedger: [String: Double] = [:]
    public var attempts: [String: [RecoveryAttempt]] = [:]

    public enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessionBoundary = "session_boundary"
        case volumes
        case cleanupLedger = "cleanup_ledger"
        case attempts
    }
}

/// 状态载入结果。**关键语义**：`absent`（文件不存在，全新安装的正常空态）
/// 与 `corrupt`（不可读/损坏/版本未知，走保守方向）必须区分——
/// 二者混淆会让「状态损坏」变成误恢复通道，违背 FR-010。
public enum MountRecoveryStoreLoad: Equatable, Sendable {
    case absent
    case loaded(MountRecoveryStateFile)
    case corrupt(reason: String)

    /// 状态是否可读。不可读时缺失卷一律保守抑制，绝不套用 FR-002④。
    public var isReadable: Bool {
        if case .corrupt = self { return false }
        return true
    }

    public var file: MountRecoveryStateFile {
        if case .loaded(let file) = self { return file }
        if case .absent = self { return MountRecoveryStateFile() }
        return MountRecoveryStateFile()
    }
}

public enum RecoverySignal: String, Equatable, Sendable {
    /// ① 卷仍在挂载表但主机不可达 → 网络丢失：清理死卷并纳入恢复。
    case deadButPresent
    /// ② 卷缺失且在清理账中 → 产品自清：纳入恢复。
    case productCleanup
    /// ③ 卷缺失且有修复性弹出证据 → 使用者修复动作：纳入恢复。
    case repairEject
    /// ④ 卷缺失且状态可读、曾健康挂载 → 使用者健康弹出：会话抑制。
    case healthyEject
    /// ⑤ 卷缺失且状态可读、从未挂载 → 非弃用：按基线段挂载，不进抑制。
    case neverMounted
    /// ⑥ 信号不可读/状态损坏 → 保守抑制（绝不当作 ⑤）。
    case unknownConservative
    /// 卷已健康挂载（无需动作）。
    case attachedHealthy

    /// 是否纳入自动恢复。
    public var isRecoverable: Bool {
        switch self {
        case .deadButPresent, .productCleanup, .repairEject, .neverMounted: return true
        case .healthyEject, .unknownConservative, .attachedHealthy: return false
        }
    }

    /// 是否进入会话抑制。
    public var isSuppressed: Bool {
        switch self {
        case .healthyEject, .unknownConservative: return true
        default: return false
        }
    }
}

public func judgeRecoverySignal(
    volumeKey: String,
    presentInMountTable: Bool,
    hostReachable: Bool,
    record: MountRecoveryVolumeRecord?,
    cleanupLedger: [String: Double],
    stateReadable: Bool
) -> RecoverySignal {
    // ⑥ 状态不可读优先：保守方向，绝不因状态损坏而误判为「从未挂载」。
    if !stateReadable { return .unknownConservative }

    if presentInMountTable {
        // ① 在表但主机不可达 = 会话丢失/死卷；主机可达 = 健康挂载。
        return hostReachable ? .attachedHealthy : .deadButPresent
    }

    // 缺失：按 ② → ③ → ④/⑤ 顺序判别。
    if cleanupLedger[volumeKey] != nil { return .productCleanup }
    if record?.repairEjectEvidence == true || record?.state == .pendingRecovery { return .repairEject }
    if record?.everHealthyMounted == true { return .healthyEject }
    return .neverMounted
}
