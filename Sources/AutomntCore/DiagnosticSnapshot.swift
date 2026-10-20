import Foundation

// MARK: - Redacted model
//
// DiagnosticSnapshot is the account-independent core of T034: a locally produced, redacted
// summary a user may preview and then explicitly export. It deliberately contains no password,
// user name, host/IP, share name, file path, bookmarks or Keychain references.
//
// Not implemented here, on purpose: log retention/capacity/cleanup policy (T003) is still
// undecided, and this type performs no upload, telemetry or long-term storage of any kind.

public enum DiagnosticChannel: String, Codable, Sendable {
    case cli, app, unknown
}

public enum DiagnosticSignatureState: String, Codable, Sendable {
    case verified, unverified, unavailable
}

public struct DiagnosticProductInfo: Codable, Equatable, Sendable {
    public let version: String
    public let channel: DiagnosticChannel
    public init(version: String, channel: DiagnosticChannel) {
        self.version = version
        self.channel = channel
    }
}

/// Signature verification summary. Contains no team identifier, certificate or requirement text.
public struct DiagnosticSignatureSummary: Codable, Equatable, Sendable {
    public let state: DiagnosticSignatureState
    public let requirementSatisfied: Bool?
    public init(state: DiagnosticSignatureState, requirementSatisfied: Bool?) {
        self.state = state
        self.requirementSatisfied = requirementSatisfied
    }
}

/// OS-level facts only. Never the computer name, account name or serial.
public struct DiagnosticSystemSummary: Codable, Equatable, Sendable {
    public let macOSVersion: String
    public let architecture: String
    public init(macOSVersion: String, architecture: String) {
        self.macOSVersion = macOSVersion
        self.architecture = architecture
    }

    public static func current() -> DiagnosticSystemSummary {
        DiagnosticSystemSummary(macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                                architecture: Self.architecture)
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}

/// Authorization state as booleans. The authorized directory path is never exported.
public struct DiagnosticAuthorizationSummary: Codable, Equatable, Sendable {
    public let directoryAuthorized: Bool
    public let bookmarkPresent: Bool
    public let scopedAccessGranted: Bool
    public init(directoryAuthorized: Bool, bookmarkPresent: Bool, scopedAccessGranted: Bool) {
        self.directoryAuthorized = directoryAuthorized
        self.bookmarkPresent = bookmarkPresent
        self.scopedAccessGranted = scopedAccessGranted
    }
}

/// Aggregate counts only; no target names or addresses.
public struct DiagnosticAutomationSummary: Codable, Equatable, Sendable {
    public let automationEnabled: Bool
    public let autoMountRecoveryEnabled: Bool
    public let configuredHostCount: Int
    public let configuredShareCount: Int
    public let enabledShareCount: Int
    public let notificationSoundEnabled: Bool?
    public init(automationEnabled: Bool, autoMountRecoveryEnabled: Bool, configuredHostCount: Int,
                configuredShareCount: Int, enabledShareCount: Int, notificationSoundEnabled: Bool?) {
        self.automationEnabled = automationEnabled
        self.autoMountRecoveryEnabled = autoMountRecoveryEnabled
        self.configuredHostCount = configuredHostCount
        self.configuredShareCount = configuredShareCount
        self.enabledShareCount = enabledShareCount
        self.notificationSoundEnabled = notificationSoundEnabled
    }
}

/// One observed volume, identified only by its stable substitution token.
public struct DiagnosticVolumeStatus: Codable, Equatable, Sendable {
    public let target: String
    public let status: VolumeStatus
    public let issue: AutomntIssue?
    public let observedAt: Date
    public init(target: String, status: VolumeStatus, issue: AutomntIssue?, observedAt: Date) {
        self.target = target
        self.status = status
        self.issue = issue
        self.observedAt = observedAt
    }
}

public enum DiagnosticEventCategory: String, Codable, Sendable {
    case mount, unmount, recovery, notification, authorization, service, configuration, other
}

/// One event. `detail` is free text that has already passed through the redactor.
public struct DiagnosticEvent: Codable, Equatable, Sendable {
    public let at: Date
    public let category: DiagnosticEventCategory
    public let detail: String
    public init(at: Date, category: DiagnosticEventCategory, detail: String) {
        self.at = at
        self.category = category
        self.detail = detail
    }
}

public struct DiagnosticSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let product: DiagnosticProductInfo
    public let signature: DiagnosticSignatureSummary
    public let system: DiagnosticSystemSummary
    public let authorization: DiagnosticAuthorizationSummary
    public let automation: DiagnosticAutomationSummary
    public let volumes: [DiagnosticVolumeStatus]
    public let events: [DiagnosticEvent]

    public init(schemaVersion: Int = DiagnosticSnapshot.currentSchemaVersion, generatedAt: Date,
                product: DiagnosticProductInfo, signature: DiagnosticSignatureSummary,
                system: DiagnosticSystemSummary, authorization: DiagnosticAuthorizationSummary,
                automation: DiagnosticAutomationSummary, volumes: [DiagnosticVolumeStatus],
                events: [DiagnosticEvent]) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.product = product
        self.signature = signature
        self.system = system
        self.authorization = authorization
        self.automation = automation
        self.volumes = volumes
        self.events = events
    }
}

// MARK: - Redaction

/// Stable, per-export substitution of sensitive values.
///
/// Guarantees: the same real value maps to the same placeholder across one export (so related
/// entries can be correlated), and distinct real values get distinct placeholders. The mapping
/// exists only for the lifetime of one export: it is never persisted and never spans exports,
/// so it cannot be used to track a user over time.
public struct DiagnosticRedactor: Sendable {
    public enum Kind: String, Sendable {
        case host, share, path, account, endpoint
    }

    private var assignments: [String: String] = [:]

    public init() {}

    /// Number of distinct real values substituted. Useful for tests and for a coarse audit.
    public var substitutedValueCount: Int { assignments.count }

    /// Every real value this redactor replaced, in assignment order. This is the authoritative
    /// audit list: whatever the redactor substituted is exactly what a leak check must look for.
    public var substitutedValues: [String] {
        assignments.keys.sorted { lhs, rhs in
            let left = Int(assignments[lhs]?.split(separator: "#").last?.dropLast() ?? "") ?? 0
            let right = Int(assignments[rhs]?.split(separator: "#").last?.dropLast() ?? "") ?? 0
            return left == right ? lhs < rhs : left < right
        }
    }

    /// Placeholder for a value, assigning one on first use. Repeated calls are stable.
    public mutating func placeholder(for value: String, kind: Kind) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if let existing = assignments[trimmed] { return existing }
        let ordinal = assignments.values.filter { $0.hasPrefix("<\(kind.rawValue)#") }.count + 1
        let token = "<\(kind.rawValue)#\(ordinal)>"
        assignments[trimmed] = token
        return token
    }

    /// Replaces every known value, longest first so a shorter value cannot split a longer one.
    private func substitutingKnownValues(in text: String) -> String {
        var result = text
        for value in assignments.keys.sorted(by: { $0.count > $1.count }) {
            guard let token = assignments[value] else { continue }
            result = result.replacingOccurrences(of: value, with: token, options: .caseInsensitive)
        }
        return result
    }

    /// Redacts free text: known values first, then residual patterns for anything the caller
    /// did not declare (an address or path embedded in an error message).
    public mutating func redact(text: String) -> String {
        var result = substitutingKnownValues(in: text)
        result = redactMatches(of: Self.smbURLPattern, in: result, kind: .endpoint)
        result = redactMatches(of: Self.unixPathPattern, in: result, kind: .path)
        result = redactMatches(of: Self.ipv4Pattern, in: result, kind: .host)
        result = redactMatches(of: Self.localHostPattern, in: result, kind: .host)
        result = redactMatches(of: Self.uncPathPattern, in: result, kind: .endpoint)
        return result
    }

    /// Replaces matches right-to-left so earlier ranges stay valid, via the same mapping table
    /// so a repeated match stays a repeated placeholder.
    private mutating func redactMatches(of pattern: NSRegularExpression, in text: String,
                                        kind: Kind) -> String {
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }
        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            // The token is built from the *replaced* text so it never re-matches the pattern.
            let token = placeholder(for: String(result[range]), kind: kind)
            result.replaceSubrange(range, with: token)
        }
        return result
    }

    // Patterns match the shapes a leaked value would take inside an otherwise-safe string.
    private static let smbURLPattern = makePattern(#"smb://[^\s"'<>]+"#)
    private static let unixPathPattern = makePattern(#"/(?:Volumes|Users|private|var|tmp)/[^\s"'<>]*"#)
    private static let ipv4Pattern = makePattern(#"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"#)
    private static let localHostPattern = makePattern(#"\b[A-Za-z0-9][A-Za-z0-9._-]*\.local\b"#)
    private static let uncPathPattern = makePattern(#"//[^\s"'<>/]+/[^\s"'<>]*"#)

    private static func makePattern(_ source: String) -> NSRegularExpression {
        // Literal patterns above are fixed and valid; a failure would be a programming error.
        try! NSRegularExpression(pattern: source)
    }
}

// MARK: - Export

public enum DiagnosticExportFormat: String, Codable, Sendable {
    case json, text
}

public struct DiagnosticExportError: Error, Equatable, Sendable {
    public enum Reason: String, Sendable {
        /// The rendered output still contained a value the caller declared sensitive.
        case leakDetected
        case encodingFailed
        case writeFailed
    }
    public let reason: Reason
    /// The offending value is never included; only the fact that a leak was detected.
    public init(reason: Reason) { self.reason = reason }
}

/// In-memory preview. Holding one never writes anything to disk.
public struct DiagnosticExportPreview: Equatable, Sendable {
    public let format: DiagnosticExportFormat
    public let text: String
    public let sensitiveValueCount: Int
    public init(format: DiagnosticExportFormat, text: String, sensitiveValueCount: Int) {
        self.format = format
        self.text = text
        self.sensitiveValueCount = sensitiveValueCount
    }
}

/// Contract adapter: redacted preview, then an explicit user-chosen destination.
public protocol DiagnosticExporting: Sendable {
    func preview(_ snapshot: DiagnosticSnapshot, format: DiagnosticExportFormat,
                 sensitiveValues: [String]) throws -> DiagnosticExportPreview
    func export(_ preview: DiagnosticExportPreview, to destination: URL) throws
}

public struct DiagnosticExporter: DiagnosticExporting {
    public init() {}

    public func preview(_ snapshot: DiagnosticSnapshot, format: DiagnosticExportFormat = .json,
                        sensitiveValues: [String] = []) throws -> DiagnosticExportPreview {
        let text: String
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot), let encoded = String(data: data, encoding: .utf8) else {
                throw DiagnosticExportError(reason: .encodingFailed)
            }
            text = encoded
        case .text:
            text = Self.renderText(snapshot)
        }
        // Defense in depth: fail closed rather than hand back a preview that leaks. The value
        // itself is never reported, only the fact that the gate tripped.
        guard !Self.containsSensitiveValue(text, values: sensitiveValues) else {
            throw DiagnosticExportError(reason: .leakDetected)
        }
        return DiagnosticExportPreview(format: format, text: text,
                                       sensitiveValueCount: sensitiveValues.filter { !$0.isEmpty }.count)
    }

    /// Writes only when the caller supplies an explicit destination.
    public func export(_ preview: DiagnosticExportPreview, to destination: URL) throws {
        do {
            try Data(preview.text.utf8).write(to: destination, options: .atomic)
        } catch {
            throw DiagnosticExportError(reason: .writeFailed)
        }
    }

    /// True when any declared sensitive value survives in the rendered text.
    public static func containsSensitiveValue(_ text: String, values: [String]) -> Bool {
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            // Short values would produce meaningless coincidences (a port, a single letter).
            guard trimmed.count >= 3 else { continue }
            if text.range(of: trimmed, options: .caseInsensitive) != nil { return true }
        }
        return false
    }

    private static func renderText(_ snapshot: DiagnosticSnapshot) -> String {
        var lines: [String] = []
        lines.append("automnt diagnostic snapshot (redacted)")
        lines.append("schema: \(snapshot.schemaVersion)")
        lines.append("generated: \(ISO8601DateFormatter().string(from: snapshot.generatedAt))")
        lines.append("version: \(snapshot.product.version)")
        lines.append("channel: \(snapshot.product.channel.rawValue)")
        lines.append("signature: \(snapshot.signature.state.rawValue)")
        lines.append("macOS: \(snapshot.system.macOSVersion)")
        lines.append("architecture: \(snapshot.system.architecture)")
        lines.append("authorized: \(snapshot.authorization.directoryAuthorized)")
        lines.append("automation: \(snapshot.automation.automationEnabled)")
        lines.append("hosts: \(snapshot.automation.configuredHostCount)")
        lines.append("shares: \(snapshot.automation.configuredShareCount)")
        for volume in snapshot.volumes {
            lines.append("volume \(volume.target): \(volume.status.rawValue)\(volume.issue.map { " (\($0.rawValue))" } ?? "")")
        }
        for event in snapshot.events {
            lines.append("event \(ISO8601DateFormatter().string(from: event.at)) \(event.category.rawValue): \(event.detail)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - Builder

/// Raw inputs. These may contain private targets; the builder redacts them and keeps the raw
/// set only long enough to audit its own output.
public struct DiagnosticBuildInputs: Sendable {
    public struct EventInput: Sendable {
        public let at: Date
        public let category: DiagnosticEventCategory
        public let detail: String
        public init(at: Date, category: DiagnosticEventCategory, detail: String) {
            self.at = at
            self.category = category
            self.detail = detail
        }
    }

    public var configuration: AutomntConfig?
    public var observations: [VolumeObservation]
    public var channel: DiagnosticChannel
    public var signature: DiagnosticSignatureSummary
    public var system: DiagnosticSystemSummary
    public var authorization: DiagnosticAuthorizationSummary
    public var notificationSoundEnabled: Bool?
    public var events: [EventInput]
    /// Extra values that must never appear (for example a user name seen in an error string).
    public var additionalSensitiveValues: [String]

    public init(configuration: AutomntConfig? = nil, observations: [VolumeObservation] = [],
                channel: DiagnosticChannel = .unknown,
                signature: DiagnosticSignatureSummary = DiagnosticSignatureSummary(state: .unavailable,
                                                                                   requirementSatisfied: nil),
                system: DiagnosticSystemSummary = .current(),
                authorization: DiagnosticAuthorizationSummary = DiagnosticAuthorizationSummary(
                    directoryAuthorized: false, bookmarkPresent: false, scopedAccessGranted: false),
                notificationSoundEnabled: Bool? = nil, events: [EventInput] = [],
                additionalSensitiveValues: [String] = []) {
        self.configuration = configuration
        self.observations = observations
        self.channel = channel
        self.signature = signature
        self.system = system
        self.authorization = authorization
        self.notificationSoundEnabled = notificationSoundEnabled
        self.events = events
        self.additionalSensitiveValues = additionalSensitiveValues
    }
}

public struct DiagnosticSnapshotBuild: Sendable {
    public let snapshot: DiagnosticSnapshot
    /// Every real value the redactor substituted. Callers pass this to
    /// `DiagnosticExporter.preview` so the exporter can audit its own rendered output.
    public let sensitiveValues: [String]
}

public enum DiagnosticSnapshotBuilder {
    public static func build(_ inputs: DiagnosticBuildInputs, now: Date = Date()) -> DiagnosticSnapshotBuild {
        var redactor = DiagnosticRedactor()

        // 1. Register every real value first. Registration order fixes the placeholder numbering,
        //    and registering before any text is redacted guarantees the whole mapping table is
        //    available when free text is substituted (otherwise a value registered later would
        //    survive inside an already-rendered event line).
        func register(_ value: String?, kind: DiagnosticRedactor.Kind) -> String? {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return redactor.placeholder(for: value, kind: kind)
        }

        let hosts = inputs.configuration?.hosts ?? []
        for host in hosts {
            _ = register(host.host, kind: .host)
            _ = register(host.alias, kind: .host)
            for share in host.shares {
                _ = register(share.name, kind: .share)
                _ = register(share.smbURL, kind: .endpoint)
                _ = register(share.mountPoint, kind: .path)
            }
        }
        for observation in inputs.observations {
            _ = register(observation.identity, kind: .endpoint)
            _ = register(observation.actualPath, kind: .path)
        }
        for value in inputs.additionalSensitiveValues {
            _ = register(value, kind: .account)
        }

        // 2. Redact free text only after the full mapping table exists.
        let volumes = inputs.observations.map { observation -> DiagnosticVolumeStatus in
            DiagnosticVolumeStatus(target: redactor.placeholder(for: observation.identity, kind: .endpoint),
                                   status: observation.status, issue: observation.issue,
                                   observedAt: observation.observedAt)
        }
        let events = inputs.events.map { event -> DiagnosticEvent in
            DiagnosticEvent(at: event.at, category: event.category,
                            detail: redactor.redact(text: event.detail))
        }

        let shares = hosts.flatMap(\.shares)
        let automation = DiagnosticAutomationSummary(
            automationEnabled: inputs.configuration?.isAutomationEnabled ?? false,
            autoMountRecoveryEnabled: inputs.configuration?.isAutoMountRecoveryEnabled ?? false,
            configuredHostCount: hosts.count,
            configuredShareCount: shares.count,
            enabledShareCount: shares.filter(\.enabled).count,
            notificationSoundEnabled: inputs.notificationSoundEnabled)

        let snapshot = DiagnosticSnapshot(
            generatedAt: now,
            product: DiagnosticProductInfo(version: AutomntBuildVersion.value, channel: inputs.channel),
            signature: inputs.signature,
            system: inputs.system,
            authorization: inputs.authorization,
            automation: automation,
            volumes: volumes,
            events: events)
        // The audit list is derived from the redactor, so it cannot drift from what was replaced.
        return DiagnosticSnapshotBuild(snapshot: snapshot, sensitiveValues: redactor.substitutedValues)
    }

    /// Convenience: build and immediately produce a redacted, leak-audited preview.
    public static func preview(_ inputs: DiagnosticBuildInputs,
                               format: DiagnosticExportFormat = .json) throws -> DiagnosticExportPreview {
        let build = build(inputs)
        return try DiagnosticExporter().preview(build.snapshot, format: format,
                                                sensitiveValues: build.sensitiveValues)
    }
}
