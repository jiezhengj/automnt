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

// MARK: - Share detail

/// Detail for one share. Reading order is fixed: status and next step, then the
/// configured and actual location, then the automatic plan, then the actions, then
/// the indexing result and diagnostics.
struct ShareDetailSheet: View {
    @Bindable var model: ApplicationModel
    let shareIdentity: String
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmingRemoval = false
    @State private var removalError: String?
    @State private var showingDiagnostics = false

    private var managed: (host: HostConfig, share: SMBShareConfig)? {
        for host in model.snapshot?.configuration.hosts ?? [] {
            if let share = host.shares.first(where: { smbResourceIdentity($0.smbURL) == shareIdentity }) {
                return (host, share)
            }
        }
        return nil
    }

    private var discovered: ServerInventory.Share? {
        model.inventory.addable.flatMap(\.addableShares).first { $0.identity == shareIdentity }
    }

    var body: some View {
        Group {
            if let managed {
                managedDetail(host: managed.host, share: managed.share)
            } else if let discovered {
                addableDetail(discovered)
            } else {
                ContentUnavailableView("Shared Folder Unavailable", systemImage: "questionmark.folder",
                    description: Text("This shared folder is no longer in the list. Close this window and check the current list."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .sheet(isPresented: $editing, onDismiss: {
            // Editing an address changes the share identity. Close this detail rather
            // than leaving it open on an object that no longer exists.
            if managed == nil { dismiss() }
        }) {
            if let managed {
                EditShareView(model: model, host: managed.host, share: managed.share)
            }
        }
        // The same redacted preview and export the Help menu opens, reached from the
        // problem context rather than a second implementation.
        .sheet(isPresented: $showingDiagnostics) { DiagnosticsView(model: model) }
        .confirmationDialog("Remove This Shared Folder?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let managed, let failure = model.removeShare(managed.share) {
                    removalError = failure
                } else {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // The consequence is chosen by the shared policy; the wording is localized here
            // because only the app module ships the nine-language catalog.
            Text(Self.removalConsequenceText(DetailActionPolicy.removalConsequence(
                shareMounted: managed.map { model.availability(of: $0.share) == .usable } ?? false)))
        }
    }

    @ViewBuilder
    private func managedDetail(host: HostConfig, share: SMBShareConfig) -> some View {
        let detail = model.detail(of: share)
        let actions = DetailActionPolicy.available(detail, busy: model.busy)
        Form {
            Section("Status") {
                Label(statusTitle(detail.status), systemImage: statusSymbol(detail.status))
                Text(nextStepText(detail.nextStep))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let observed = detail.observedAt {
                    LabeledContent("Last Checked") { Text(observed, format: .dateTime) }
                }
            }

            Section("Location") {
                LabeledContent("Configured Location") {
                    Text(verbatim: detail.expectedMountPoint)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if detail.showsExpectedAndActualLocations {
                    LabeledContent("Actual Location") {
                        Text(verbatim: detail.actualMountPoint ?? String(localized: "Not mounted"))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                LabeledContent("SMB Address") {
                    Text(verbatim: detail.smbURL)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Automatic Mounting") {
                LabeledContent("Schedule", value: planText(detail.automaticPlan))
                Toggle("Mount This Shared Folder Automatically", isOn: Binding(
                    get: { share.enabled },
                    set: { enabled in toggleShare(host: host, share: share, enabled: enabled) }))
                    .disabled(model.busy || !(model.snapshot?.configuration.isAutomationEnabled ?? false))
                Text("When this is off, this shared folder is no longer mounted automatically. It stays available if it is already mounted. The server and global automatic mounting must also be on.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                if actions.contains(.openInFinder) {
                    Button("Open in Finder", systemImage: "folder") { model.openInFinder(share) }
                }
                if actions.contains(.mount) {
                    Button("Mount This Shared Folder", systemImage: "externaldrive.badge.plus") {
                        Task { await model.mount(host: host, share: share) }
                    }.disabled(model.busy)
                }
                if actions.contains(.eject) {
                    // Ordinary eject runs directly: no routine confirmation and never
                    // a forced eject. A busy folder is reported as a failure.
                    Button("Eject", systemImage: "eject") {
                        Task { await model.eject(host: host, share: share) }
                    }.disabled(model.busy)
                }
                if actions.contains(.editTarget) {
                    Button("Edit Address and Location…", systemImage: "pencil") { editing = true }
                }
                if actions.contains(.removeFromManagement) {
                    Button("Remove from Automnt…", systemImage: "minus.circle", role: .destructive) {
                        confirmingRemoval = true
                    }.disabled(model.busy)
                }
                if let removalError {
                    Text(removalError).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            } footer: {
                Text("Removing a shared folder changes only what Automnt mounts. It does not eject anything and does not delete files or saved sign-in details.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Spotlight Indexing") {
                Text(host.preventSpotlightIndex
                    ? String(localized: "Automnt asks the system not to index this server’s shared folders after mounting. This can reduce disk and network activity but may limit Spotlight results. Existing indexes are not deleted, and the system may not honour the request.")
                    : String(localized: "Automnt does not ask the system to stop indexing this server’s shared folders."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("View Diagnostics…") { showingDiagnostics = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(share.name)
        .navigationSubtitle(host.alias ?? host.host)
    }

    @ViewBuilder
    private func addableDetail(_ share: ServerInventory.Share) -> some View {
        Form {
            Section("Status") {
                Text("Connected in Finder")
                Text("This shared folder is mounted on this Mac but is not managed by Automnt yet. Add it to mount it automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Location") {
                LabeledContent("Location") {
                    Text(verbatim: share.mountPoint).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LabeledContent("SMB Address") {
                    Text(verbatim: share.smbURL).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                Button("Add") {
                    if let failure = model.addShare(smbURL: share.smbURL) { removalError = failure }
                    else { dismiss() }
                }.disabled(model.busy)
                if let removalError {
                    Text(removalError).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(share.name)
    }

    private func toggleShare(host: HostConfig, share: SMBShareConfig, enabled: Bool) {
        guard let base = model.snapshot, let identity = smbResourceIdentity(share.smbURL) else { return }
        model.save(base) { configuration in
            for index in configuration.hosts.indices {
                guard let shareIndex = configuration.hosts[index].shares.firstIndex(where: {
                    smbResourceIdentity($0.smbURL) == identity
                }) else { continue }
                configuration.hosts[index].shares[shareIndex].enabled = enabled
            }
        }
    }

    private func statusTitle(_ status: ShareDetail.Status) -> String {
        switch status {
        case .healthy: String(localized: "Available")
        case .mounting: String(localized: "Mounting")
        case .ejectedForThisSession: String(localized: "Ejected for this session")
        case .notSelectedThisRound: String(localized: "Not checked in the last round")
        case .automatedMountingOff: String(localized: "Mounted · automatic mounting off")
        case .serverUnreachable: String(localized: "Server not reachable")
        case .authenticationRequired: String(localized: "Sign-in required")
        case .locationMismatch: String(localized: "Mounted at a different location")
        case .recovering: String(localized: "Recovering")
        case .recoveryFailed: String(localized: "Mounting failed")
        case .unconfirmed: String(localized: "Result could not be confirmed")
        case .notMounted: String(localized: "Not mounted")
        }
    }

    private func statusSymbol(_ status: ShareDetail.Status) -> String {
        switch status {
        case .healthy: "checkmark.circle"
        case .mounting, .recovering: "arrow.triangle.2.circlepath"
        case .ejectedForThisSession: "eject.circle"
        case .automatedMountingOff: "pause.circle"
        case .locationMismatch, .serverUnreachable, .authenticationRequired,
             .recoveryFailed, .unconfirmed, .notMounted, .notSelectedThisRound:
            "exclamationmark.triangle"
        }
    }

    private func nextStepText(_ step: ShareDetail.NextStep) -> String {
        switch step {
        case .openInFinder: String(localized: "Open this shared folder in Finder to use it.")
        case .wait: String(localized: "Wait for this to finish. You can keep using the rest of the window.")
        case .mountThisShare: String(localized: "Mount it now, or turn on automatic mounting in Settings to have it mounted for you.")
        case .explainRoundSelection: String(localized: "A round checks servers in order and stops at the first reachable one, so this server was not reached. It is not an error.")
        case .checkNetwork: String(localized: "Check the network connection. Automnt waits for a network or sign-in change before trying again.")
        case .connectInFinder: String(localized: "Connect to this server in Finder and sign in, then return and try again.")
        case .reviewLocations: String(localized: "Another volume holds the configured location. Eject that volume in Finder, or open the mounted folder.")
        case .retryThisShare: String(localized: "Check the server and your sign-in, then try mounting this shared folder again.")
        }
    }

    /// Removal only changes management. Both wordings state what stays untouched.
    static func removalConsequenceText(_ consequence: DetailActionPolicy.RemovalConsequence) -> String {
        switch consequence {
        case .removedManagementOnlyMountedStays:
            String(localized: "Automnt will no longer mount this shared folder automatically. It stays mounted, and your files and saved sign-in details are not deleted.")
        case .removedManagementOnly:
            String(localized: "Automnt will no longer mount this shared folder automatically. Your files and saved sign-in details are not deleted.")
        }
    }

    private func planText(_ plan: ShareDetail.AutomaticPlan) -> String {
        switch plan {
        case .scheduled: String(localized: "Automnt mounts this shared folder when the server is available.")
        case .pausedThisSession: String(localized: "Paused after you ejected it. It stays disconnected until the network or sign-in changes, or until you mount it.")
        case .disabledForShare: String(localized: "Off for this shared folder.")
        case .disabledForServer: String(localized: "Off for this server.")
        case .disabledGlobally: String(localized: "Off because automatic mounting is off.")
        case .waitsForBackgroundApproval: String(localized: "Waiting for background mounting to be approved.")
        case .waitsForSystemEvent: String(localized: "Waiting for a network or sign-in change.")
        }
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
    /// conflict and the draft stays in the form.
    private let editBase: ConfigSnapshot?

    init(model: ApplicationModel, host: HostConfig, share: SMBShareConfig) {
        self.model = model
        self.host = host
        self.share = share
        _smbURL = State(initialValue: share.smbURL)
        _name = State(initialValue: share.name)
        _mountPoint = State(initialValue: share.mountPoint)
        editBase = model.snapshot
    }

    private var isDirty: Bool {
        smbURL.trimmingCharacters(in: .whitespacesAndNewlines) != share.smbURL
            || name.trimmingCharacters(in: .whitespacesAndNewlines) != share.name
            || mountPoint.trimmingCharacters(in: .whitespacesAndNewlines) != share.mountPoint
    }

    var body: some View {
        NavigationStack {
            Form {
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
            error = String(localized: "The configuration changed. Reload it before continuing.")
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
            error = String(localized: "The configuration changed. Reload it before continuing.")
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

    private var hasNameChange: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines) != (host.alias ?? "")
    }

    private var hasConnectionChanges: Bool {
        smbHost.trimmingCharacters(in: .whitespacesAndNewlines) != host.host
            || port != host.port
            || timeoutMs != host.timeoutMs
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $name, prompt: Text(verbatim: host.host))
                        .focused($focused, equals: .name)
                    if let nameError {
                        fieldError(nameError)
                    }
                    Button("Save Name") { saveName() }
                        .disabled(model.busy)
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
                    Text("These parameters are saved together for this server. Its shared folders keep their own addresses and locations.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let connectionError {
                        Text(connectionError).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Save Connection Parameters") { saveConnection() }
                        .disabled(model.busy)
                }

                Section("Indexing") {
                    Toggle("Try to Prevent Spotlight Indexing", isOn: Binding(
                        get: { current?.preventSpotlightIndex ?? host.preventSpotlightIndex },
                        set: { enabled in saveIndexing(enabled) }))
                        .disabled(model.busy)
                    Text("Applies to all shared folders of this server. Automnt asks the system not to index them, which can reduce disk and network activity but may limit Spotlight results. Existing indexes are not deleted, and the system may not honour the request.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(host.alias ?? host.host)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(minWidth: 440, idealWidth: 580, minHeight: 400, idealHeight: 520)
        .background(WindowAccessor { model.installWindowCloseGuard($0) })
        .onAppear { draftID = model.registerDraft(isDirty: isDirty) { saveDraft() } }
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

    private var conflictMessage: String {
        String(localized: "The configuration changed. Reload it before continuing.")
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
        if saved { self.base = model.snapshot }
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

    private var automaticMounting: SettingsSurface.AutomaticMounting? {
        guard let configuration = model.snapshot?.configuration else { return nil }
        return SettingsSurface.AutomaticMounting(intended: configuration.isAutomationEnabled,
            backend: model.backend, recoveryPreferred: configuration.isAutoMountRecoveryEnabled)
    }

    private var notifications: SettingsSurface.Notifications {
        SettingsSurface.Notifications(authorization: model.notificationPermission.authorizationState,
            soundEnabled: model.soundEnabled, soundNeedsRepair: model.soundNeedsRepair)
    }

    var body: some View {
        Form {
            automaticSection
            menuBarSection
            notificationSection
            advancedSection
            supportSection
            if let issue = model.issue {
                Section { Text(issue).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 460, idealWidth: 560, minHeight: 420)
        .task { model.refreshLoginStatus() }
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
                    set: { model.saveAutomation($0, base: base) }))
                    .disabled(model.busy)
                LabeledContent("Background Mounting", value: model.backend.label)
                Text(Self.mountingSummaryText(SettingsSurface.automaticMountingSummary(automaticMounting ?? .init(
                    intended: configuration.isAutomationEnabled, backend: model.backend,
                    recoveryPreferred: configuration.isAutoMountRecoveryEnabled))))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.backend.needsUserAction {
                    Button("Set Up or Repair Background Mounting") {
                        Task { await model.activateAppBackground(repair: true) }
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
                    .disabled(model.busy || !(automaticMounting?.recoveryEditable ?? false))
                Text("Shared folders that disconnect unexpectedly get an extra attempt when the volume setup changes. Automatic mounting after sign-in or a network change still runs when this is off.")
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
                    menuBarEnabled = enabled
                    if !enabled {
                        Task {
                            await model.setMenuLogin(false)
                            if model.loginStatus == .notRegistered || model.loginStatus == .notFound {
                                menuBarEnabled = false
                            }
                        }
                    }
                }))
                .disabled(model.changingLogin)
            Toggle("Show the Menu Bar at Login", isOn: Binding(
                get: { model.loginStatus == .enabled || model.loginStatus == .requiresApproval },
                set: { enabled in Task { await model.setMenuLogin(enabled) } }))
                .disabled(!menuBarEnabled || model.changingLogin)
            Text("This login setting opens only the menu bar item; it never opens the main window. Background automatic mounting runs separately.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.loginStatus == .requiresApproval {
                Text("Allow Automnt in Login Items in System Settings to show the menu bar at login.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
            } else if model.loginStatus == .notFound {
                Text("The login item is unavailable. Keep Automnt in its installed location and try again.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button("Check Login Setting") { model.refreshLoginStatus() }
            if let issue = model.loginIssue {
                Text(issue).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var notificationSection: some View {
        Section("Notifications") {
            LabeledContent("System Permission", value: notifications.authorization.label)
            if notifications.shouldOfferPermissionRequest {
                Text("Automnt uses notifications only for shared folders it could not mount automatically.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Allow Notifications…") { Task { await model.requestNotifications() } }
                    .disabled(model.requestingNotifications)
            } else if notifications.authorization == .denied {
                Text("Notifications are not allowed. You can still see mounting problems in Automnt.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if notifications.authorization == .unavailable {
                Text("The notification setting could not be read. Check Notifications in System Settings.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if notifications.offersSettingsShortcut {
                Button("Open Notification Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Button("Check Notification Permission") { Task { await model.refreshNotificationPermission() } }
                .disabled(model.requestingNotifications)
            if let issue = model.notificationIssue {
                Text(issue).font(.callout).foregroundStyle(.secondary)
            }
            Toggle("Notification sound", isOn: Binding(
                get: { model.soundEnabled }, set: { model.saveSound($0) }))
                .disabled(!model.configurationChangesAllowed)
            Text("When this is off, you still receive notifications.")
                .font(.callout).foregroundStyle(.secondary)
            if model.soundNeedsRepair {
                Text("Notification sound is off because its settings could not be read. Choose your preference to repair them.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if !model.configurationAccess.allowsChanges {
                Button("Open Automnt") { openWindow(id: "main") }
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
                                Button("Open in Finder") { model.openInFinder(share) }
                                    .disabled(model.availability(of: share) != .usable)
                                Button("Mount") {
                                    Task { await model.mount(host: host, share: share) }
                                }.disabled(model.busy || model.availability(of: share) == .usable)
                                // Ordinary eject runs directly, with no routine confirmation.
                                Button("Eject") {
                                    Task { await model.eject(host: host, share: share) }
                                }.disabled(model.busy || model.availability(of: share) != .usable)
                            }
                        }
                    }
                }
            } else {
                Button("Add a Shared Folder…") { openWindow(id: "main") }
            }
            Divider()
            Button("Open Automnt") { openWindow(id: "main") }
            SettingsLink()
            Button("Hide Menu Bar Icon") {
                Task {
                    await model.setMenuLogin(false)
                    if model.loginStatus == .notRegistered || model.loginStatus == .notFound {
                        menuBarEnabled = false
                    }
                }
            }.disabled(model.changingLogin)
            if let snapshot = model.snapshot, snapshot.configuration.isAutomationEnabled {
                Button("Turn Off Automatic Mounting") { model.saveAutomation(false, base: snapshot) }
                    .disabled(model.busy)
                Text("Shared folders that are already mounted stay available.")
            }
            if let issue = model.issue { Text(issue) }
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
