import AppKit
import SwiftUI
import ServiceManagement
import AutomntCore
import AutomntPlatform

// MARK: - Add one shared folder

/// Shared field parsing for the manual add and edit forms. The rules mirror the shared
/// validator so the form can point at the field that failed instead of one generic error.
enum ShareFormFields {
    static func isValidSMBAddress(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "smb",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let shareName = extractShareName(from: value), !shareName.isEmpty,
              let standard = deriveStandardMountPoint(from: value) else { return false }
        return !standard.isEmpty
    }

    static func isValidAddressForServer(_ value: String, host: String, port: Int) -> Bool {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "smb",
              let addressHost = components.host,
              addressHost.lowercased() == host.lowercased(),
              (components.port ?? 445) == port,
              components.user == nil, components.password == nil,
              let shareName = extractShareName(from: value), !shareName.isEmpty else { return false }
        return true
    }

    static func isValidMountPath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path != "/", !path.contains("\0") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == "." || $0 == ".." }
    }
}

/// Manual add. A complete, credential-free SMB address is the primary input; the
/// Result line for a sheet: the action that just ran was started here, so its result has
/// to be visible here instead of in the window behind the sheet.
private struct SheetMessageCard: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(12)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// A revision conflict is recoverable: the draft stays exactly as typed and one
/// explicit button re-reads the latest settings. Reloading never mounts, ejects or
/// overwrites the input, so it is safe to press while editing.
struct ConfigurationConflictCard: View {
    @Bindable var model: ApplicationModel

    var body: some View {
        if model.configurationConflictDetected {
            VStack(alignment: .leading, spacing: 6) {
                Label("Your settings were updated elsewhere. Use the latest settings to refresh this window; what you typed is kept.",
                      systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Use Latest Settings") { model.reloadAfterConfigurationConflict() }
                    .disabled(model.busy)
                Text("Refreshing mounts or ejects nothing and does not overwrite what you typed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// shared folder name and its standard location are derived from it and can be
/// changed before the single "Add" action saves immediately.
struct AddShareView: View {
    @Bindable var model: ApplicationModel
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case address, name, mount }
    private enum DuplicateField { case address, mount }

    @State private var address = ""
    @State private var name = ""
    @State private var mountPoint = ""
    @State private var addressError: String?
    @State private var nameError: String?
    @State private var mountError: String?
    @State private var error: String?
    @State private var draftID: UUID?
    @State private var derivedName = ""
    @State private var derivedMountPoint = ""
    @FocusState private var focused: Field?

    private var parsed: (host: String, port: Int, name: String, mountPoint: String)? {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "smb",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let shareName = extractShareName(from: value), !shareName.isEmpty,
              let standard = deriveStandardMountPoint(from: value) else { return nil }
        return (host, components.port ?? 445, shareName, standard)
    }

    private var isDirty: Bool {
        let fields = [address, name, mountPoint]
        return fields.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                ConfigurationConflictCard(model: model)
                Section("SMB Address") {
                    TextField("SMB Address", text: $address, prompt: Text(verbatim: "smb://host/share"))
                        .focused($focused, equals: .address)
                        .onChange(of: address) { _, _ in applyDerivedValues() }
                    Text("Enter the complete address of one shared folder, without a user name or password. Sign-in is handled by macOS.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let addressError {
                        fieldError(addressError)
                    }
                }
                Section("Shared Folder") {
                    TextField("Name", text: $name)
                        .focused($focused, equals: .name)
                    if let nameError {
                        fieldError(nameError)
                    }
                    TextField("Mount Location", text: $mountPoint)
                        .focused($focused, equals: .mount)
                    if let mountError {
                        fieldError(mountError)
                    }
                    Text("The name and location are derived from the address. Change them if your tasks use another location.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Shared Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { submit() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 440, idealWidth: 560, minHeight: 320, idealHeight: 420)
        .background(WindowAccessor { model.installWindowCloseGuard($0) })
        .task { focused = .address }
        .onAppear { draftID = model.registerDraft(isDirty: isDirty) { submit() } }
        .onDisappear { if let draftID { model.removeDraft(draftID) } }
        .onChange(of: isDirty) { _, dirty in
            if let draftID { model.updateDraft(draftID, isDirty: dirty) }
        }
    }

    @ViewBuilder
    private func fieldError(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func applyDerivedValues() {
        guard let parsed else { return }
        // Only replace values the user has not edited away from the previous derivation.
        if name.isEmpty || name == derivedName {
            name = parsed.name
            derivedName = parsed.name
        }
        if mountPoint.isEmpty || mountPoint == derivedMountPoint {
            mountPoint = parsed.mountPoint
            derivedMountPoint = parsed.mountPoint
        }
    }

    @discardableResult
    private func submit() -> Bool {
        addressError = nil
        nameError = nil
        mountError = nil
        error = nil
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMount = mountPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        var firstInvalid: Field?
        if value.isEmpty {
            addressError = String(localized: "Enter a complete SMB address such as smb://host/share, without a user name or password.")
            firstInvalid = .address
        } else if parsed == nil {
            addressError = String(localized: "Check the address. It must be a complete smb://host/share address without sign-in details.")
            if firstInvalid == nil { firstInvalid = .address }
        }
        if trimmedName.isEmpty {
            nameError = String(localized: "Enter a name for this shared folder.")
            if firstInvalid == nil { firstInvalid = .name }
        }
        if !ShareFormFields.isValidMountPath(trimmedMount) {
            mountError = String(localized: "Use an absolute folder path without . or .. components.")
            if firstInvalid == nil { firstInvalid = .mount }
        }
        if let firstInvalid {
            focused = firstInvalid
            return false
        }
        if let duplicate = duplicateField(label: trimmedName, mount: trimmedMount, address: value) {
            let message = String(localized: "This shared folder is already listed with the same address or location.")
            switch duplicate {
            case .address: addressError = message
            case .mount: mountError = message
            }
            focused = duplicate == .address ? .address : .mount
            return false
        }
        if let failure = model.addShare(smbURL: value, name: trimmedName, mountPoint: trimmedMount) {
            // The failure message stays here; the configuration keeps its previous state.
            error = failure
            return false
        }
        dismiss()
        return true
    }

    /// Pure pre-check for the two duplicate reasons the shared validator reports on
    /// this new share. Other failures still come back from the save path.
    private func duplicateField(label: String, mount: String, address: String) -> DuplicateField? {
        guard let base = model.snapshot, let parsed else { return nil }
        var configuration = base.configuration
        if let index = configuration.hosts.firstIndex(where: {
            $0.host.lowercased() == parsed.host.lowercased() && $0.port == parsed.port
        }) {
            configuration.hosts[index].shares.append(SMBShareConfig(name: label, smbURL: address, mountPoint: mount))
        } else {
            configuration.hosts.append(HostConfig(host: parsed.host, port: parsed.port,
                shares: [SMBShareConfig(name: label, smbURL: address, mountPoint: mount)]))
        }
        let problems = ConfigurationValidation.problems(in: configuration)
        if problems.contains(where: { $0.reason == .duplicateShare }) { return .address }
        if problems.contains(where: { $0.reason == .duplicateMountPath }) { return .mount }
        return nil
    }
}

// MARK: - Edit one share

/// Editing an existing share keeps the server identity and order. The address and the
/// mount location are related fields, so they are submitted together as one draft.
struct EditShareView: View {
    @Bindable var model: ApplicationModel
    let host: HostConfig
    let share: SMBShareConfig
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case address, name, mount }

    @State private var smbURL: String
    @State private var name: String
    @State private var mountPoint: String
    @State private var addressError: String?
    @State private var nameError: String?
    @State private var mountError: String?
    @State private var error: String?
    @State private var draftID: UUID?
    @FocusState private var focused: Field?
    /// Target identity and revision captured when editing begins. Saving never takes a
    /// newer snapshot revision, so a concurrent CLI or app write is reported as a
    /// conflict and the draft stays in the form. Only the explicit "Reload Settings"
    /// action refreshes this baseline; typed values are never replaced.
    @State private var editBase: ConfigSnapshot?

    init(model: ApplicationModel, host: HostConfig, share: SMBShareConfig) {
        self.model = model
        self.host = host
        self.share = share
        _smbURL = State(initialValue: share.smbURL)
        _name = State(initialValue: share.name)
        _mountPoint = State(initialValue: share.mountPoint)
        _editBase = State(initialValue: model.snapshot)
    }

    private var isDirty: Bool {
        smbURL.trimmingCharacters(in: .whitespacesAndNewlines) != share.smbURL
            || name.trimmingCharacters(in: .whitespacesAndNewlines) != share.name
            || mountPoint.trimmingCharacters(in: .whitespacesAndNewlines) != share.mountPoint
    }

    var body: some View {
        NavigationStack {
            Form {
                ConfigurationConflictCard(model: model)
                Section("Shared Folder") {
                    TextField("SMB Address", text: $smbURL)
                        .focused($focused, equals: .address)
                    if let addressError {
                        fieldError(addressError)
                    }
                    TextField("Name", text: $name)
                        .focused($focused, equals: .name)
                    if let nameError {
                        fieldError(nameError)
                    }
                    TextField("Mount Location", text: $mountPoint)
                        .focused($focused, equals: .mount)
                    if let mountError {
                        fieldError(mountError)
                    }
                    Text("Other shared folders of this server keep their own addresses and locations. An already mounted shared folder stays where it is.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .onChange(of: model.configurationConflictDetected) { wasDetected, isDetected in
                // Reload clears the flag after refreshing the model snapshot; adopt that
                // new baseline so the next save uses the current revision. Field values
                // stay exactly as typed.
                if wasDetected && !isDetected, let latest = model.snapshot {
                    editBase = latest
                }
            }
            .navigationTitle("Edit Shared Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { submit() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 440, idealWidth: 560, minHeight: 360, idealHeight: 460)
        .background(WindowAccessor { model.installWindowCloseGuard($0) })
        .onAppear { draftID = model.registerDraft(isDirty: isDirty) { submit() } }
        .onDisappear { if let draftID { model.removeDraft(draftID) } }
        .onChange(of: isDirty) { _, dirty in
            if let draftID { model.updateDraft(draftID, isDirty: dirty) }
        }
    }

    @ViewBuilder
    private func fieldError(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    @discardableResult
    private func submit() -> Bool {
        addressError = nil
        nameError = nil
        mountError = nil
        error = nil
        let address = smbURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let position = mountPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var firstInvalid: Field?
        if !ShareFormFields.isValidAddressForServer(address, host: host.host, port: host.port) {
            addressError = String(localized: "Check the address. It must be a complete smb://host/share address without sign-in details.")
            firstInvalid = .address
        }
        if label.isEmpty {
            nameError = String(localized: "Enter a name for this shared folder.")
            if firstInvalid == nil { firstInvalid = .name }
        }
        if !ShareFormFields.isValidMountPath(position) {
            mountError = String(localized: "Use an absolute folder path without . or .. components.")
            if firstInvalid == nil { firstInvalid = .mount }
        }
        if let firstInvalid {
            focused = firstInvalid
            return false
        }
        guard let base = editBase else {
            error = String(localized: "These settings were updated elsewhere. Close this window and open it again.")
            return false
        }
        guard let identity = smbResourceIdentity(share.smbURL),
              let hostIndex = base.configuration.hosts.firstIndex(where: {
                  managedServerIdentity($0) == managedServerIdentity(host)
              }),
              let shareIndex = base.configuration.hosts[hostIndex].shares.firstIndex(where: {
                  smbResourceIdentity($0.smbURL) == identity
              }) else {
            // The target disappeared while the form was open: report a conflict and keep
            // the input instead of silently saving nothing.
            error = String(localized: "These settings were updated elsewhere. Close this window and open it again.")
            return false
        }
        var candidate = base.configuration
        candidate.hosts[hostIndex].shares[shareIndex].smbURL = address
        candidate.hosts[hostIndex].shares[shareIndex].name = label
        candidate.hosts[hostIndex].shares[shareIndex].mountPoint = position
        if let problem = ConfigurationValidation.problems(in: candidate).first(where: {
            $0.hostIndex == hostIndex && $0.shareIndex == shareIndex
        }) {
            show(problem.reason)
            return false
        }
        let saved = model.save(base) { configuration in
            for hostIndex in configuration.hosts.indices {
                guard let shareIndex = configuration.hosts[hostIndex].shares.firstIndex(where: {
                    smbResourceIdentity($0.smbURL) == identity
                }) else { continue }
                configuration.hosts[hostIndex].shares[shareIndex].smbURL = address
                configuration.hosts[hostIndex].shares[shareIndex].name = label
                configuration.hosts[hostIndex].shares[shareIndex].mountPoint = position
                return
            }
        }
        if saved {
            dismiss()
        } else {
            error = model.issue ?? String(localized: "The change could not be saved. Check folder access and try again.")
        }
        return saved
    }

    private func show(_ reason: ConfigurationProblem.Reason) {
        switch reason {
        case .emptySMBURL, .invalidSMBURL, .embeddedCredentials, .hostMismatch, .duplicateShare:
            addressError = reason == .duplicateShare
                ? String(localized: "This shared folder is already listed with the same address or location.")
                : String(localized: "Check the address. It must be a complete smb://host/share address without sign-in details.")
            focused = .address
        case .emptyShareName:
            nameError = String(localized: "Enter a name for this shared folder.")
            focused = .name
        case .invalidMountPath, .duplicateMountPath:
            mountError = reason == .duplicateMountPath
                ? String(localized: "This shared folder is already listed with the same address or location.")
                : String(localized: "Use an absolute folder path without . or .. components.")
            focused = .mount
        case .invalidHost, .invalidPort, .duplicateHost:
            error = String(localized: "Check the server address, port, SMB addresses and mount folders. Each shared folder needs a distinct address and folder on this server.")
        }
    }
}

// MARK: - Server settings

/// Server-scoped settings. The name is confirmed in place; the connection parameters
/// are related fields and are submitted together.
struct ServerSettingsView: View {
    @Bindable var model: ApplicationModel
    let host: HostConfig
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case name, address, port, timeout }

    @State private var name: String
    @State private var smbHost: String
    @State private var port: Int
    @State private var timeoutMs: Int
    @State private var nameError: String?
    @State private var addressError: String?
    @State private var portError: String?
    @State private var timeoutError: String?
    @State private var connectionError: String?
    @State private var draftID: UUID?
    @FocusState private var focused: Field?
    /// Revision captured when this page opened. Each successful inline save refreshes
    /// it; a save never adopts a newer snapshot just because the model changed.
    @State private var base: ConfigSnapshot?
    /// Inline confirmation after a save; a switch or field never looks like it did nothing.
    @State private var savedFeedback: String?

    init(model: ApplicationModel, host: HostConfig) {
        self.model = model
        self.host = host
        _name = State(initialValue: host.alias ?? "")
        _smbHost = State(initialValue: host.host)
        _port = State(initialValue: host.port)
        _timeoutMs = State(initialValue: host.timeoutMs)
        _base = State(initialValue: model.snapshot)
    }

    private var current: HostConfig? {
        base?.configuration.hosts.first { managedServerIdentity($0) == managedServerIdentity(host) }
    }

    private var isDirty: Bool { hasNameChange || hasConnectionChanges }

    private var savedAlias: String { current?.alias ?? host.alias ?? "" }
    private var savedHost: String { current?.host ?? host.host }
    private var savedPort: Int { current?.port ?? host.port }
    private var savedTimeout: Int { current?.timeoutMs ?? host.timeoutMs }

    private var hasNameChange: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines) != savedAlias
    }

    private var hasConnectionChanges: Bool {
        smbHost.trimmingCharacters(in: .whitespacesAndNewlines) != savedHost
            || port != savedPort
            || timeoutMs != savedTimeout
    }

    var body: some View {
        NavigationStack {
            Form {
                ConfigurationConflictCard(model: model)
                if let savedFeedback {
                    Label(savedFeedback, systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section("Name") {
                    TextField("Name", text: $name, prompt: Text(verbatim: host.host))
                        .focused($focused, equals: .name)
                    if let nameError {
                        fieldError(nameError)
                    }
                    Text("Leave the name empty to show the server address.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section("Connection") {
                    TextField("Server Address", text: $smbHost)
                        .focused($focused, equals: .address)
                    if let addressError {
                        fieldError(addressError)
                    }
                    TextField("Port", value: $port, format: .number.grouping(.never))
                        .focused($focused, equals: .port)
                    if let portError {
                        fieldError(portError)
                    }
                    TextField("Probe Timeout (ms)", value: $timeoutMs, format: .number.grouping(.never))
                        .focused($focused, equals: .timeout)
                    if let timeoutError {
                        fieldError(timeoutError)
                    }
                    Text("Saving these parameters also updates the SMB address of every shared folder on this server. Their mount locations stay the same.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let connectionError {
                        Text(connectionError).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Indexing") {
                    Toggle("Try to Prevent Spotlight Indexing", isOn: Binding(
                        get: { current?.preventSpotlightIndex ?? host.preventSpotlightIndex },
                        set: { enabled in saveIndexing(enabled) }))
                        .accessibilityLabel(Text("Try to Prevent Spotlight Indexing"))
                        .disabled(model.busy)
                    Text("Applies to every shared folder on this server. Spotlight results from these folders may be incomplete.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .onChange(of: model.configurationConflictDetected) { wasDetected, isDetected in
                if wasDetected && !isDetected, let latest = model.snapshot {
                    base = latest
                }
            }
            .navigationTitle(String(localized: "Server Settings"))
            .navigationSubtitle(host.alias ?? host.host)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }.keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(minWidth: 440, idealWidth: 580, minHeight: 400, idealHeight: 520)
        .background(WindowAccessor { model.installWindowCloseGuard($0) })
        .onAppear { draftID = model.registerDraft(isDirty: isDirty) { saveDraft() } }
        .onDisappear { if let draftID { model.removeDraft(draftID) } }
        .onChange(of: name) { savedFeedback = nil }
        .onChange(of: smbHost) { savedFeedback = nil }
        .onChange(of: port) { savedFeedback = nil }
        .onChange(of: timeoutMs) { savedFeedback = nil }
        .onChange(of: isDirty) { _, dirty in
            if let draftID { model.updateDraft(draftID, isDirty: dirty) }
        }
    }

    @ViewBuilder
    private func fieldError(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var conflictMessage: String {
        String(localized: "These settings were updated elsewhere. Close this window and open it again.")
    }

    /// Closing the page must not discard typed values: name and connection fields save
    /// first, and validation errors keep the page open.
    private func finish() {
        if isDirty, !saveDraft() { return }
        dismiss()
    }

    /// Used by the quit confirmation: a dirty page saves its connection fields, its name
    /// and its indexing choice through the same revision-checked path as its buttons.
    private func saveDraft() -> Bool {
        var saved = true
        if hasNameChange { saved = saveName() }
        if hasConnectionChanges { saved = saveConnection() && saved }
        return saved
    }

    @discardableResult
    private func saveName() -> Bool {
        nameError = nil
        guard let base else { nameError = conflictMessage; return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = managedServerIdentity(host)
        guard base.configuration.hosts.contains(where: { managedServerIdentity($0) == identity }) else {
            nameError = conflictMessage
            return false
        }
        let saved = model.save(base) { configuration in
            guard let index = configuration.hosts.firstIndex(where: { managedServerIdentity($0) == identity }) else { return }
            configuration.hosts[index].alias = trimmed.isEmpty ? nil : trimmed
        }
        if saved {
            self.base = model.snapshot
            savedFeedback = String(localized: "Name saved.")
        } else {
            nameError = model.issue
        }
        return saved
    }

    @discardableResult
    private func saveConnection() -> Bool {
        addressError = nil
        portError = nil
        timeoutError = nil
        connectionError = nil
        let address = smbHost.trimmingCharacters(in: .whitespacesAndNewlines)
        var firstInvalid: Field?
        guard !address.isEmpty,
              let components = URLComponents(string: "smb://\(address)/share"),
              components.host == address,
              components.user == nil, components.password == nil else {
            addressError = String(localized: "Enter a server address such as server.example, without a user name or password.")
            focused = .address
            return false
        }
        if !(1...65535).contains(port) {
            portError = String(localized: "Enter a port from 1 to 65535.")
            firstInvalid = .port
        }
        if !(100...30000).contains(timeoutMs) {
            timeoutError = String(localized: "Enter a probe timeout from 100 to 30000 ms.")
            if firstInvalid == nil { firstInvalid = .timeout }
        }
        if let firstInvalid {
            focused = firstInvalid
            return false
        }
        guard let base else { connectionError = conflictMessage; return false }
        let identity = managedServerIdentity(host)
        guard let hostIndex = base.configuration.hosts.firstIndex(where: { managedServerIdentity($0) == identity }) else {
            connectionError = conflictMessage
            return false
        }
        var candidate = base.configuration
        candidate.hosts[hostIndex].host = address
        candidate.hosts[hostIndex].port = port
        candidate.hosts[hostIndex].timeoutMs = timeoutMs
        for shareIndex in candidate.hosts[hostIndex].shares.indices {
            guard var updated = URLComponents(string: candidate.hosts[hostIndex].shares[shareIndex].smbURL) else { continue }
            updated.host = address
            updated.port = port == 445 ? nil : port
            if let value = updated.string {
                candidate.hosts[hostIndex].shares[shareIndex].smbURL = value
            }
        }
        if let problem = ConfigurationValidation.problems(in: candidate).first(where: {
            $0.hostIndex == hostIndex && $0.shareIndex == nil
        }) {
            switch problem.reason {
            case .invalidHost, .duplicateHost:
                addressError = String(localized: "Check the server address, port, SMB addresses and mount folders. Each shared folder needs a distinct address and folder on this server.")
                focused = .address
            case .invalidPort:
                portError = String(localized: "Enter a port from 1 to 65535.")
                focused = .port
            default:
                connectionError = String(localized: "Check the server address, port, SMB addresses and mount folders. Each shared folder needs a distinct address and folder on this server.")
            }
            return false
        }
        let saved = model.save(base) { configuration in
            guard let index = configuration.hosts.firstIndex(where: { managedServerIdentity($0) == identity }) else { return }
            configuration.hosts[index].host = address
            configuration.hosts[index].port = port
            configuration.hosts[index].timeoutMs = timeoutMs
            for shareIndex in configuration.hosts[index].shares.indices {
                guard var updated = URLComponents(string: configuration.hosts[index].shares[shareIndex].smbURL) else { continue }
                updated.host = address
                updated.port = port == 445 ? nil : port
                if let value = updated.string {
                    configuration.hosts[index].shares[shareIndex].smbURL = value
                }
            }
        }
        if saved {
            // Changing the address changes this server's identity. Closing the page is
            // the explicit contract; the window re-reads the list and its selection.
            dismiss()
        } else {
            connectionError = model.issue
        }
        return saved
    }

    private func saveIndexing(_ enabled: Bool) {
        guard let base else { return }
        let identity = managedServerIdentity(host)
        let saved = model.save(base) { configuration in
            guard let index = configuration.hosts.firstIndex(where: { managedServerIdentity($0) == identity }) else { return }
            configuration.hosts[index].preventSpotlightIndex = enabled
        }
        if saved {
            self.base = model.snapshot
            savedFeedback = enabled
                ? String(localized: "Automnt will ask the system not to index this server’s shared folders.")
                : String(localized: "Automnt will no longer ask the system to skip indexing this server’s shared folders.")
        } else {
            savedFeedback = nil
        }
    }
}

// MARK: - Settings

/// A native Settings window: automatic mounting with its real background status, the
/// menu bar and login item, the real notification authorization with an independent
/// sound preference, the shared retry parameters and the support entries.
struct SettingsView: View {
    @Bindable var model: ApplicationModel
    @Binding var menuBarEnabled: Bool
    @Binding var helpDestination: HelpDestination?
    @Binding var showingDiagnostics: Bool
    /// One-shot confirmation when turning off the resident app would silently end notifications.
    @State private var confirmingResidentDisable = false
    @State private var disablesMenuBar = false

    private var automaticMounting: SettingsSurface.AutomaticMounting? {
        guard let configuration = model.snapshot?.configuration else { return nil }
        return SettingsSurface.AutomaticMounting(intended: configuration.isAutomationEnabled,
            backend: model.backend, recoveryPreferred: configuration.isAutoMountRecoveryEnabled)
    }

    private var notifications: SettingsSurface.Notifications {
        SettingsSurface.Notifications(authorization: model.notificationPermission.authorizationState,
            soundEnabled: model.soundEnabled, soundNeedsRepair: model.soundNeedsRepair)
    }

    /// Background notifications are delivered by the app itself: a sandboxed helper has no
    /// notification identity and may not spawn the app to borrow one. The app must therefore
    /// run at login, and the menu bar item is the user-visible handle for that resident process.
    private var backgroundDeliveryReady: Bool {
        menuBarEnabled && model.loginStatus == .enabled
    }

    /// Registered but waiting for the user's approval in Login Items.
    private var backgroundDeliveryPendingApproval: Bool {
        menuBarEnabled && model.loginStatus == .requiresApproval
    }

    var body: some View {
        Form {
            automaticSection
            menuBarSection
            notificationSection
            advancedSection
            supportSection
            if model.messageSurface == .settings, let issue = model.issue {
                Section { Text(issue).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            } else if model.messageSurface == .settings, let notice = model.notice {
                Section { Text(notice).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 560, idealWidth: 680, minHeight: 520, idealHeight: 620)
        .task { model.refreshLoginStatus() }
        .background(WindowAccessor { model.installSettingsWindowFramePersistence($0) })
    }

    @ViewBuilder
    private var automaticSection: some View {
        Section("Automatic Mounting") {
            if !model.configurationAccess.allowsChanges {
                Text(model.configurationAccessMessage)
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(model.configurationAccessButton) { Task { await model.authorizeConfiguration() } }
                    .disabled(model.busy)
                    .fixedSize(horizontal: true, vertical: false)
            } else if let configuration = model.snapshot?.configuration, let base = model.snapshot {
                Toggle("Automatic Mounting", isOn: Binding(
                    get: { configuration.isAutomationEnabled },
                    set: { model.saveAutomation($0, base: base, surface: .settings) }))
                    .accessibilityLabel(Text("Automatic Mounting"))
                    .disabled(model.busy || model.automationChangeInFlight)
                LabeledContent("Background Mounting", value: model.backend.label)
                Text(Self.mountingSummaryText(SettingsSurface.automaticMountingSummary(automaticMounting ?? .init(
                    intended: configuration.isAutomationEnabled, backend: model.backend,
                    recoveryPreferred: configuration.isAutoMountRecoveryEnabled))))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.backend == .governedByCLI {
                    Text("The command-line version is managing automatic mounting right now. To use the app instead, stop the command-line service first.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.backend.needsUserAction {
                    Button("Set Up or Repair Background Mounting") {
                        Task { await model.activateAppBackground(repair: true, surface: .settings) }
                    }.disabled(model.busy)
                    if model.backend == .awaitingApproval {
                        Button("Open Login Items Settings") { ServiceController(mode: .baseline).openApprovalSettings() }
                    }
                }
                if let guidance = model.missingBackendGuidance {
                    Text(guidance).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Automatic Recovery", isOn: Binding(
                    get: { configuration.isAutoMountRecoveryEnabled },
                    set: { model.saveRecovery($0, base: base) }))
                    .accessibilityLabel(Text("Automatic Recovery"))
                    .disabled(model.busy || !(automaticMounting?.recoveryEditable ?? false))
                Text("Shared folders that disconnect unexpectedly get an extra attempt when the volume setup changes. Automatic mounting after sign-in or a network change still runs when this is off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Mount Scope", selection: Binding(
                    get: { configuration.effectiveMountPolicy },
                    set: { model.saveMountPolicy($0, base: base) })) {
                    Text("First Reachable Server").tag(MountPolicy.firstReachable)
                    Text("All Reachable Servers").tag(MountPolicy.allReachable)
                }
                .pickerStyle(.menu)
                .disabled(model.busy)
                Text("Servers are checked in the order shown in the sidebar. The first option stops at the first reachable server; the second also mounts the shared folders of every other reachable server.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.configurationReadFailed {
                Text("Your configuration could not be read, so its settings are not shown. Automatic mounting keeps its previous state until the configuration is readable.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Add a shared folder before turning on automatic mounting.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var menuBarSection: some View {
        Section("Menu Bar and Login") {
            Toggle("Show Automnt in the Menu Bar", isOn: Binding(
                get: { menuBarEnabled },
                set: { enabled in
                    if enabled { menuBarEnabled = true } else { requestResidentDisable(includeMenuBar: true) }
                }))
                .accessibilityLabel(Text("Show Automnt in the Menu Bar"))
                .disabled(model.changingLogin)
            Toggle("Open Automnt at Login", isOn: Binding(
                get: { model.loginStatus == .enabled || model.loginStatus == .requiresApproval },
                set: { enabled in
                    if enabled { Task { await model.setMenuLogin(true) } } else { requestResidentDisable(includeMenuBar: false) }
                }))
                .accessibilityLabel(Text("Open Automnt at Login"))
                .disabled(!menuBarEnabled || model.changingLogin)
            if model.loginStatus == .enabled || model.loginStatus == .requiresApproval {
                Text("At login, only the menu bar icon opens; the main window won’t.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.loginStatus == .requiresApproval {
                Text("Allow Automnt in Login Items in System Settings.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let issue = model.loginIssue {
                Text(issue).font(.callout).foregroundStyle(.secondary)
                Button("Check Again") { model.refreshLoginStatus() }
            }
        }
        .alert(disableResidentAlertTitle, isPresented: $confirmingResidentDisable) {
            Button("Turn Off", role: .destructive) { performResidentDisable() }
            Button("Cancel", role: .cancel) {}
        } message: {
            // Hiding the icon also removes the login item, but the already-running app keeps
            // delivering notices until it is quit; say both facts instead of claiming an
            // immediate stop.
            Text("Automnt will no longer open at login. Failure notifications while the window is closed stop once you quit. Automatic mounting continues.")
        }
    }

    private var disableResidentAlertTitle: String {
        disablesMenuBar
            ? String(localized: "Hide Automnt from the Menu Bar?")
            : String(localized: "Stop Opening Automnt at Login?")
    }

    /// Turning off the resident app while notifications are allowed is a real loss of a
    /// capability, so it asks once instead of silently going quiet.
    private func requestResidentDisable(includeMenuBar: Bool) {
        guard notifications.authorization == .allowed else {
            disablesMenuBar = includeMenuBar
            performResidentDisable()
            return
        }
        disablesMenuBar = includeMenuBar
        confirmingResidentDisable = true
    }

    private func performResidentDisable() {
        let includeMenuBar = disablesMenuBar
        if includeMenuBar { menuBarEnabled = false }
        Task {
            await model.setMenuLogin(false)
            if includeMenuBar, model.loginStatus == .notRegistered || model.loginStatus == .notFound {
                menuBarEnabled = false
            }
        }
    }

    @ViewBuilder
    private var notificationSection: some View {
        Section("Notifications") {
            Text("Automnt notifies you when a shared folder can’t be mounted automatically—even with the window closed.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("System Permission", value: notifications.authorization.label)
            notificationPrerequisite
            // Sound is an independent preference; it never gates whether notices arrive.
            Toggle("Notification sound", isOn: Binding(
                get: { model.soundEnabled }, set: { model.saveSound($0) }))
                .accessibilityLabel(Text("Notification sound"))
                .disabled(!model.configurationChangesAllowed)
            if model.soundNeedsRepair {
                Text("Notification sound is off because its settings could not be read. Choose your preference to repair them.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let issue = model.notificationIssue {
                Text(issue).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    /// Exactly one unmet prerequisite is explained and acted on at a time: the system
    /// permission first, then the resident process that is allowed to deliver the notice.
    /// The previous card used independent `if` blocks, so it could stack two explanations
    /// and two buttons, and it said "not running at login" while the login item was merely
    /// waiting for approval.
    @ViewBuilder
    private var notificationPrerequisite: some View {
        switch notifications.authorization {
        case .notRequested:
            Text("Automnt needs your permission before it can send notifications.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Allow Notifications…") { Task { await model.requestNotifications() } }
                .disabled(model.requestingNotifications)
        case .denied:
            Text("Notifications are not allowed. You can still see mounting problems in Automnt.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Notification Settings") { openNotificationSettings() }
        case .unavailable:
            Text("The notification setting could not be read. Check Notifications in System Settings.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Check Again") { Task { await model.refreshNotificationPermission() } }
                .disabled(model.requestingNotifications)
        case .allowed:
            if backgroundDeliveryPendingApproval {
                Text("Automnt is waiting for you to allow it in Login Items.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !backgroundDeliveryReady {
                Text("Automnt needs to start at login to notify you while the window is closed.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Turn On in Login Items") {
                    menuBarEnabled = true
                    Task { await model.setMenuLogin(true) }
                }
                .disabled(model.changingLogin)
            }
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
        if model.configurationAccess.allowsChanges, let configuration = model.snapshot?.configuration, let base = model.snapshot {
            Section("Advanced") {
                Stepper(value: Binding(
                            get: { RetryPolicyBounds.clamped(configuration.retryPolicy).maxAttempts ?? RetryPolicyBounds.defaultAttempts },
                            set: { value in
                                let current = RetryPolicyBounds.clamped(configuration.retryPolicy)
                                model.saveRetryPolicy(base: base, attempts: value,
                                    intervalMs: current.intervalMs ?? RetryPolicyBounds.defaultIntervalMs,
                                    windowMs: current.maxTotalWindowMs ?? RetryPolicyBounds.defaultWindowMs)
                            }),
                        in: RetryPolicyBounds.attemptRange) {
                    LabeledContent("Attempts per Round") {
                        Text(RetryPolicyBounds.clamped(configuration.retryPolicy).maxAttempts ?? RetryPolicyBounds.defaultAttempts,
                             format: .number.grouping(.never))
                    }
                }
                .accessibilityLabel(Text("Attempts per Round"))
                .disabled(model.busy)
                Text("Shared with the command-line tool. A round makes at most this many attempts and does not keep polling while idle.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var supportSection: some View {
        Section("Support") {
            Button("Diagnostics…") { showingDiagnostics = true }
            Button("User Guide") { helpDestination = .guide }
            Button("Support and Privacy") { helpDestination = .privacy }
            Button("Open Source Licenses") { helpDestination = .licenses }
        }
    }
}

extension SettingsView {
    /// The saved switch, the running service and the recovery preference are three
    /// separate facts, so "running with recovery" and "running without recovery" stay
    /// two different sentences instead of one merged line.
    static func mountingSummaryText(_ summary: SettingsSurface.AutomaticMountingSummary) -> String {
        switch summary {
        case .offWhileMountedStayAvailable:
            String(localized: "Automatic mounting is off. Shared folders that are already mounted stay available.")
        case .runningWithRecovery:
            String(localized: "Automatic mounting and recovery are running.")
        case .runningWithoutRecovery:
            String(localized: "Automatic mounting is running. Recovery of unexpected disconnections is off.")
        case .awaitingApproval:
            String(localized: "Background mounting needs your approval in Login Items.")
        case .transitioning:
            String(localized: "Applying your automatic mounting setting…")
        case .savedButNotRunning:
            String(localized: "Automatic mounting is saved but the background service is not running.")
        case .couldNotBeConfirmed:
            String(localized: "Background mounting could not be confirmed. Check the background state and try again.")
        case .governedByCLI:
            String(localized: "The command-line background service is currently in control.")
        }
    }
}

private extension SettingsSurface.BackendStatus {
    var label: String {
        switch self {
        case .running: String(localized: "Running")
        case .awaitingApproval: String(localized: "Waiting for approval")
        case .stopped: String(localized: "Off")
        case .transitioning: String(localized: "Changing")
        case .unavailable: String(localized: "Could not be confirmed")
        case .governedByCLI: String(localized: "The command-line service is in control")
        }
    }
}

private extension NotificationAuthorizationState {
    var label: String {
        switch self {
        case .notRequested: String(localized: "Not requested yet")
        case .allowed: String(localized: "Allowed")
        case .denied: String(localized: "Not allowed")
        case .unavailable: String(localized: "Could not be read")
        }
    }
}

// MARK: - Menu bar

/// Optional menu bar. Its actions bind to a stable server identity and share identity,
/// so they never depend on which row the main window happens to select.
struct AutomntMenuView: View {
    let model: ApplicationModel
    @Binding var menuBarEnabled: Bool
    var addShareRequest: AddShareRequest?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if !model.configurationAccess.allowsChanges {
                Text("Automnt needs access to its settings before it can manage shared folders.")
            } else if let snapshot = model.snapshot, !snapshot.configuration.hosts.isEmpty {
                ForEach(Array(snapshot.configuration.hosts.enumerated()), id: \.offset) { _, host in
                    Menu(displayName(host)) {
                        ForEach(host.shares, id: \.smbURL) { share in
                            Menu(menuLabel(share)) {
                                Button("View Details") {
                                    guard let identity = smbResourceIdentity(share.smbURL) else { return }
                                    model.requestedDetail = .init(revision: snapshot.revision,
                                        hostIdentity: managedServerIdentity(host), shareIdentity: identity)
                                    openWindow(id: "main")
                                }
                                Button("Open in Finder") { model.openInFinder(share, surface: .menuBar) }
                                    .disabled(model.availability(of: share) != .usable)
                                Button("Mount") {
                                    Task { await model.mount(host: host, share: share, surface: .menuBar) }
                                }.disabled(model.busy || model.availability(of: share) == .usable)
                                // Ordinary eject runs directly, with no routine confirmation.
                                Button("Eject") {
                                    Task { await model.eject(host: host, share: share, surface: .menuBar) }
                                }.disabled(model.busy || model.availability(of: share) != .usable)
                            }
                        }
                    }
                }
            } else {
                Button("Add a Shared Folder…") {
                    openWindow(id: "main")
                    addShareRequest?.present()
                }
            }
            Divider()
            if model.messageSurface == .menuBar, let notice = model.notice { Text(notice) }
            Button("Check Now") { Task { await model.tryFullRound(surface: .menuBar) } }
                .disabled(!model.configurationChangesAllowed || !model.hasConfiguration)
            Button("Open Automnt") { openWindow(id: "main") }
            SettingsLink()
            // Turning the resident app off belongs in Settings, where the consequence is
            // confirmed. A one-click item here could silently remove the login item and
            // disable window-closed notifications.
            if let snapshot = model.snapshot, snapshot.configuration.isAutomationEnabled {
                Button("Turn Off Automatic Mounting") { model.saveAutomation(false, base: snapshot, surface: .menuBar) }
                    .disabled(model.busy)
                Text("Shared folders that are already mounted stay available.")
            }
            if model.messageSurface == .menuBar, let issue = model.issue { Text(issue) }
            if model.notificationPermission == .allowed {
                Text("Quitting stops notifications while the window is closed. Automatic mounting continues.")
            }
            Button("Quit Automnt") { NSApplication.shared.terminate(nil) }
        }
        .task {
            if model.snapshot == nil { model.restore() }
            model.refreshLoginStatus()
            model.refreshStatus()
        }
    }

    private func displayName(_ host: HostConfig) -> String {
        if let alias = host.alias, !alias.isEmpty { return alias }
        return host.host
    }

    /// The label names the shared folder and its state so two same-named shares on
    /// different servers stay distinguishable in the menu.
    private func menuLabel(_ share: SMBShareConfig) -> String {
        "\(share.name) — \(ShareRowView.statusLabel(model.availability(of: share)))"
    }
}
