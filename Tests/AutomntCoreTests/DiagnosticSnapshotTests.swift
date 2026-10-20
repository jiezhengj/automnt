import Foundation
import Testing
@testable import AutomntCore

/// Builds a configuration through the product API only; no hand-written plist, no private data
/// baked into source. The values below are synthetic test fixtures, not a user's environment.
private func makeConfiguration() -> AutomntConfig {
    var configuration = AutomntConfig()
    configuration.hosts = [
        HostConfig(host: "fileserver.example.internal", alias: "Studio NAS", port: 445, shares: [
            SMBShareConfig(name: "Design Assets", smbURL: "smb://fileserver.example.internal/Design%20Assets",
                           mountPoint: "/Volumes/Design Assets"),
            SMBShareConfig(name: "Archive", smbURL: "smb://10.20.30.40/Archive",
                           mountPoint: "/Volumes/Archive", enabled: false)
        ]),
        HostConfig(host: "backup.local", shares: [
            SMBShareConfig(name: "Vault", smbURL: "smb://backup.local/Vault",
                           mountPoint: "/Volumes/Vault"),
            // A custom mount point outside /Volumes, with no share-name substring inside it, so
            // only explicit mount-point registration can redact it (the residual path pattern
            // covers /Volumes, /Users, /private, /var and /tmp only).
            SMBShareConfig(name: "Team", smbURL: "smb://backup.local/Team",
                           mountPoint: "/srv/mounts/vol-7f3a")
        ])
    ]
    return configuration
}

/// Every raw value that must never appear in an export. Kept in one place so the negative
/// assertions and the leak audit cannot drift apart.
private let forbiddenValues = [
    "fileserver.example.internal", "Studio NAS", "Design Assets", "Design%20Assets",
    "/Volumes/Design Assets", "Archive", "10.20.30.40", "/Volumes/Archive",
    "backup.local", "Vault", "/Volumes/Vault", "svc-mount-user",
    "Team", "/srv/mounts/vol-7f3a", "printer-2f.local",
    "private-nas.example", "old-server.example", "standalone-nas"
]

private func makeInputs() -> DiagnosticBuildInputs {
    DiagnosticBuildInputs(
        configuration: makeConfiguration(),
        observations: [
            VolumeObservation(identity: "smb://fileserver.example.internal/Design%20Assets",
                              status: .failed, actualPath: "/Volumes/Design Assets", observedAt: Date(),
                              issue: .shareRejected),
            VolumeObservation(identity: "smb://10.20.30.40/Archive", status: .healthy,
                              actualPath: "/Volumes/Archive", observedAt: Date(), issue: nil)
        ],
        channel: .app,
        signature: DiagnosticSignatureSummary(state: .verified, requirementSatisfied: true),
        authorization: DiagnosticAuthorizationSummary(directoryAuthorized: true, bookmarkPresent: true,
                                                      scopedAccessGranted: true),
        notificationSoundEnabled: true,
        events: [
            .init(at: Date(), category: .recovery,
                  detail: "recovery failed for /Volumes/Design Assets on fileserver.example.internal"),
            .init(at: Date(), category: .authorization,
                  detail: "mounted smb://backup.local/Vault as svc-mount-user"),
            .init(at: Date(), category: .other, detail: "reachability probe to 10.20.30.40 timed out"),
            // Bare occurrences, with no URL or path wrapper to catch them: these are what give
            // the share-name and alias registrations their own discriminating power.
            .init(at: Date(), category: .mount,
                  detail: "share Vault rejected while Studio NAS reported offline"),
            .init(at: Date(), category: .other, detail: "share Archive is disabled"),
            // A custom mount point under /srv: no residual pattern covers it, so explicit
            // mount-point registration is the only thing that can redact it.
            .init(at: Date(), category: .mount,
                  detail: "mount point /srv/mounts/vol-7f3a was occupied by an unrelated volume"),
            .init(at: Date(), category: .unmount, detail: "ejected mounted volume at /srv/mounts/vol-7f3a"),
            // A host that is neither in the configuration nor an IP, so only the residual
            // `.local` hostname pattern can redact it. This gives that pattern its own
            // discriminating power instead of riding on registered values.
            .init(at: Date(), category: .other, detail: "probe to printer-2f.local was refused"),
            // Endpoints that appear only here: not in the configuration, not an IP, not .local.
            // Only the residual smb:// and UNC patterns can redact these, which is what gives
            // those two patterns discriminating power of their own.
            .init(at: Date(), category: .mount, detail: "retry smb://private-nas.example/Projects failed"),
            .init(at: Date(), category: .other, detail: "legacy path //old-server.example/Legacy was rejected"),
            // A bare `smb://` endpoint with no path: the UNC pattern requires a `/` after the
            // authority, so only the smb:// pattern can catch this one.
            .init(at: Date(), category: .other, detail: "smb endpoint smb://standalone-nas was unreachable")
        ],
        additionalSensitiveValues: ["svc-mount-user"])
}

private func previewText(_ build: DiagnosticSnapshotBuild, format: DiagnosticExportFormat) throws -> String {
    try DiagnosticExporter().preview(build.snapshot, format: format,
                                     sensitiveValues: build.sensitiveValues).text
}

/// Serialized on purpose: `previewWritesNothingToDisk` compares a before/after listing of the
/// process temp directory, and a sibling test calling `preview` concurrently would create the
/// very file being watched for. Serial execution makes that assertion deterministic.
@Suite(.serialized)
struct DiagnosticSnapshotTests {
    // MARK: Negative redaction assertions (the core privacy gate)

    @Test func exportContainsNoRawSensitiveValueInAnyFormat() throws {
        let build = DiagnosticSnapshotBuilder.build(makeInputs())
        for format in [DiagnosticExportFormat.json, .text] {
            let text = try previewText(build, format: format)
            for forbidden in forbiddenValues {
                #expect(text.range(of: forbidden, options: .caseInsensitive) == nil,
                        "\(format) export leaked \(forbidden)")
            }
            // Residual shapes: no address, no .local host, no mount path may survive.
            #expect(!text.contains("smb://"))
            #expect(text.range(of: #"\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"#, options: .regularExpression) == nil)
            #expect(text.range(of: #"[A-Za-z0-9.-]+\.local\b"#, options: .regularExpression) == nil)
            #expect(!text.contains("/Volumes/"))
        }
    }

    @Test func placeholdersAreStableWithinOneExportAndDistinctAcrossValues() throws {
        // Same real value repeated in one export → one identical token (correlation preserved).
        var inputs = makeInputs()
        inputs.events.append(.init(at: Date(), category: .mount,
                                   detail: "retrying fileserver.example.internal for /Volumes/Design Assets"))
        let build = DiagnosticSnapshotBuilder.build(inputs)
        let text = try previewText(build, format: .text)
        #expect(text.contains("<host#1>"))
        #expect(text.components(separatedBy: "<host#1>").count - 1 >= 2,
                "the same host must render as the same token everywhere")
        #expect(text.components(separatedBy: "<path#1>").count - 1 >= 2,
                "the same path must render as the same token everywhere")

        // Different real values → different tokens, so two targets stay distinguishable.
        var redactor = DiagnosticRedactor()
        let hostA = redactor.placeholder(for: "alpha.example.internal", kind: .host)
        let hostB = redactor.placeholder(for: "beta.example.internal", kind: .host)
        #expect(hostA != hostB)
        #expect(redactor.placeholder(for: "alpha.example.internal", kind: .host) == hostA)
        // Keyed by value, not by (value, kind): one real value must never appear under two
        // tokens, or the same target would look like two different ones in one export.
        #expect(redactor.placeholder(for: "alpha.example.internal", kind: .share) == hostA)
        #expect(redactor.substitutedValueCount == 2)
        // The declared audit list covers every substituted value the caller can hand to the
        // exporter, so the leak gate has something real to check against.
        #expect(build.sensitiveValues.contains("fileserver.example.internal"))
        #expect(build.sensitiveValues.contains("/Volumes/Design Assets"))
        #expect(build.sensitiveValues.contains("svc-mount-user"))
    }

    @Test func repeatedBuildsUseTheirOwnMappingAndDoNotPersistState() throws {
        // Two separate exports must not share a mapping table (no cross-export tracking).
        let first = DiagnosticSnapshotBuilder.build(makeInputs())
        let second = DiagnosticSnapshotBuilder.build(makeInputs())
        let firstText = try previewText(first, format: .text)
        let secondText = try previewText(second, format: .text)
        // Deterministic assignment order makes them equal here; the guarantee under test is that
        // nothing carries over from the first build into the second.
        #expect(firstText == secondText)
        // A brand-new redactor knows nothing about values assigned by a previous one.
        var fresh = DiagnosticRedactor()
        #expect(fresh.placeholder(for: "fileserver.example.internal", kind: .host) == "<host#1>")
        #expect(fresh.substitutedValueCount == 1)
    }

    @Test func credentialBearingFieldsNeverAppear() throws {
        var inputs = makeInputs()
        // Even if a credential-ish token reaches an event detail, its value must not be exported.
        inputs.events.append(.init(at: Date(), category: .other,
                                   detail: "authorization failed for user svc-mount-user with password hunter2xyz"))
        inputs.additionalSensitiveValues.append("hunter2xyz")
        let build = DiagnosticSnapshotBuilder.build(inputs)
        let text = try previewText(build, format: .json)
        // The secret values themselves never survive; the surrounding prose may mention the word.
        for secret in ["hunter2xyz", "svc-mount-user"] {
            #expect(text.range(of: secret, options: .caseInsensitive) == nil, "leaked \(secret)")
        }
        // The model itself has no credential field at all: no key names a credential.
        let encoded = try JSONEncoder().encode(build.snapshot)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in object.keys {
            #expect(!["password", "passwd", "username", "credential", "credentials",
                      "bookmark", "keychain", "secret", "token"].contains(key.lowercased()))
        }
        // And no bookmark/keychain bytes are reachable through the encoded form.
        #expect(!text.contains("bookmarkData") && !text.contains("SecKeychain"))
    }

    // MARK: Preview does not write; export requires an explicit destination

    @Test func previewWritesNothingToDisk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("automnt-diagnostic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)

        // Baselines must be captured BEFORE the first preview call, or a preview that writes
        // during the first call would be present in both snapshots and go unnoticed. Only
        // regular files count: sibling tests create same-prefixed *directories* in parallel,
        // and counting those would make this assertion flaky. Leftovers from earlier runs are
        // cleared first so the comparison is absolute rather than relative.
        let strayDirectory = FileManager.default.temporaryDirectory
        func diagnosticFiles() -> [URL] {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: strayDirectory, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])) ?? []
            return entries.filter { url in
                url.lastPathComponent.hasPrefix("automnt-diagnostic")
                    && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        for leftover in diagnosticFiles() { try? FileManager.default.removeItem(at: leftover) }
        #expect(diagnosticFiles().isEmpty)

        let build = DiagnosticSnapshotBuilder.build(makeInputs())
        for format in [DiagnosticExportFormat.json, .text] {
            _ = try previewText(build, format: format)
        }
        // The declared destination must not exist…
        let destination = directory.appendingPathComponent("automnt-diagnostics.json")
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        // …and the preview must not have written anywhere in its own working directory either.
        let after = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(after.isEmpty, "preview wrote \(after)")
        // …nor left anything in the process temp directory under this feature's naming. The
        // directory was verified empty above, so any file here was created by this preview.
        #expect(diagnosticFiles().isEmpty,
                "preview left \(diagnosticFiles().map(\.lastPathComponent)) in the temp directory")
    }

    @Test func exportWritesOnlyToTheExplicitDestination() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("automnt-diagnostic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("automnt-diagnostics.json")
        #expect(!FileManager.default.fileExists(atPath: destination.path))

        let build = DiagnosticSnapshotBuilder.build(makeInputs())
        let preview = try DiagnosticExporter().preview(build.snapshot, format: .json,
                                                       sensitiveValues: build.sensitiveValues)
        // Still nothing on disk until the caller names a destination.
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        try DiagnosticExporter().export(preview, to: destination)
        let written = try String(contentsOf: destination, encoding: .utf8)
        #expect(written == preview.text)
        for forbidden in forbiddenValues {
            #expect(written.range(of: forbidden, options: .caseInsensitive) == nil)
        }
    }

    // MARK: Empty / unconfigured state

    @Test func emptyAndUnconfiguredStatesStillExportWithoutCrashing() throws {
        for inputs in [DiagnosticBuildInputs(),
                       DiagnosticBuildInputs(configuration: AutomntConfig()),
                       DiagnosticBuildInputs(configuration: nil, observations: [],
                                             events: [.init(at: Date(), category: .other, detail: "")])] {
            let build = DiagnosticSnapshotBuilder.build(inputs)
            for format in [DiagnosticExportFormat.json, .text] {
                let preview = try DiagnosticExporter().preview(build.snapshot, format: format,
                                                               sensitiveValues: build.sensitiveValues)
                #expect(!preview.text.isEmpty)
            }
            #expect(build.snapshot.automation.configuredHostCount == 0)
            #expect(build.snapshot.volumes.isEmpty)
        }
    }

    // MARK: Leak gate

    @Test func leakGateRejectsAnOutputThatStillContainsADeclaredValue() throws {
        // Simulate the regression this gate exists for: redaction failed, so the snapshot itself
        // still carries a raw private value. Preview must refuse to hand it back.
        let build = DiagnosticSnapshotBuilder.build(makeInputs())
        var leaking = build.snapshot
        leaking = DiagnosticSnapshot(
            generatedAt: leaking.generatedAt, product: leaking.product, signature: leaking.signature,
            system: leaking.system, authorization: leaking.authorization, automation: leaking.automation,
            volumes: leaking.volumes,
            events: [DiagnosticEvent(at: Date(), category: .recovery,
                                     detail: "failed smb://fileserver.example.internal/Design%20Assets")])
        #expect(throws: DiagnosticExportError(reason: .leakDetected)) {
            _ = try DiagnosticExporter().preview(leaking, format: .text,
                sensitiveValues: ["fileserver.example.internal"])
        }

        // The detector is directly testable, and reports only the fact of a leak, not the value.
        #expect(DiagnosticExporter.containsSensitiveValue("failed for fileserver.example.internal",
                                                          values: ["fileserver.example.internal"]))
        #expect(DiagnosticExporter.containsSensitiveValue("failed for FILESERVER.EXAMPLE.INTERNAL",
                                                          values: ["fileserver.example.internal"]))
        // Very short values are ignored so a port or single letter cannot cause false positives.
        #expect(!DiagnosticExporter.containsSensitiveValue("port 445 is open", values: ["44"]))
        #expect(!DiagnosticExporter.containsSensitiveValue("clean output", values: [""]))

        // A snapshot that *did* redact correctly passes the same gate.
        _ = try DiagnosticExporter().preview(build.snapshot, format: .text,
                                             sensitiveValues: build.sensitiveValues)
    }

    @Test func redactorHandlesValuesItWasNotToldAbout() throws {
        var redactor = DiagnosticRedactor()
        let text = redactor.redact(text: "connect to 192.168.7.9 and /Volumes/Client Work now")
        #expect(!text.contains("192.168.7.9"))
        #expect(!text.contains("/Volumes/Client Work"))
        #expect(text.contains("<host#"))
        #expect(text.contains("<path#"))
        // Same value twice → same token.
        var repeatRedactor = DiagnosticRedactor()
        let twice = repeatRedactor.redact(text: "a /Volumes/Shared b /Volumes/Shared")
        #expect(twice.components(separatedBy: "<path#1>").count - 1 == 2)
    }

    @Test func modelCarriesOnlyTheContractedSummaryFields() throws {
        let build = DiagnosticSnapshotBuilder.build(makeInputs())
        let encoded = try JSONEncoder().encode(build.snapshot)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DiagnosticSnapshot.self, from: encoded)
        #expect(decoded == build.snapshot)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(object.keys) == ["schemaVersion", "generatedAt", "product", "signature",
                                     "system", "authorization", "automation", "volumes", "events"])
        #expect(build.snapshot.product.version == AutomntBuildVersion.value)
        #expect(build.snapshot.schemaVersion == DiagnosticSnapshot.currentSchemaVersion)
    }
}
