import SwiftUI
import AppKit
import Combine
import AutomntCore
import AutomntPlatform

/// Left: managed servers in saved order plus discovered servers that are not managed
/// yet. Right: the selected server, its own automatic-mounting switch and a compact
/// managed / addable share list. Reordering is drag-and-keyboard with an immediate
/// save; there is no order draft, no Save button and no sorting sheet.
struct MainWindowView: View {
    @Bindable var model: ApplicationModel
    var addShareRequest: AddShareRequest?
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedServer: String?
    @State private var searchText = ""
    @State private var shareSearch = ""
    @State private var showingAddShare = false
    @State private var navigating: ShareNavigation?
    @State private var compactPath: [CompactRoute] = []

    /// A sheet target identified by the share identity the user acted on, so the
    /// detail keeps pointing at the same share while the configuration is refreshed.
    private struct ShareNavigation: Identifiable, Hashable {
        let id: String
    }

    /// One sheet serves both the toolbar button and the File menu command.
    private var addSheet: Binding<Bool> {
        Binding(get: { showingAddShare || addShareRequest?.isPresented == true },
            set: { presented in
                showingAddShare = presented
                if !presented { addShareRequest?.isPresented = false }
            })
    }

    private var inventory: ServerInventory.Snapshot { model.inventory }
    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isFiltering: Bool { !query.isEmpty }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width < Self.compactWidth {
                compactLayout
            } else {
                splitLayout
            }
        }
        .frame(minWidth: 380, minHeight: 480)
        .background(WindowAccessor { window in
            model.installWindowCloseGuard(window)
            model.installMainWindowFramePersistence(window)
        })
        .toolbar { toolbar }
        .sheet(isPresented: addSheet) {
            AddShareView(model: model)
        }
        .sheet(item: $navigating) { route in
            // Tapping a row opens the detail; the sheet owns its own Done button.
            NavigationStack {
                ShareDetailSheet(model: model, shareIdentity: route.id)
            }
            .frame(minWidth: 460, idealWidth: 620, minHeight: 480, idealHeight: 680)
        }
        .onChange(of: model.requestedDetail, initial: true) { _, request in openRequestedDetail(request) }
        .onChange(of: inventory.managed.map(\.identity) + inventory.addable.map(\.identity), initial: true) { _, _ in
            reconcileSelection()
        }
        .onChange(of: selectedServer) { _, _ in shareSearch = "" }
        .onChange(of: scenePhase) { _, phase in
            // Re-reading on activation catches a CLI save and a background state change
            // without a polling loop and without evaluating or mounting anything.
            if phase == .active { model.refreshObservedState() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            model.refreshObservedState()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            model.refreshObservedState()
        }
    }

    /// Below this width the window uses the native server → shared folder → detail
    /// stack. The wide window keeps the two-column layout; there is no third column.
    private static let compactWidth: CGFloat = 700

    private var splitLayout: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            detail
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: Text("Search servers"))
    }

    private enum CompactRoute: Hashable {
        case server(String)
        case share(String)
    }

    private var compactLayout: some View {
        NavigationStack(path: $compactPath) {
            List {
                Section("Managed") {
                    ForEach(filtered(inventory.managed)) { server in
                        NavigationLink(value: CompactRoute.server(server.identity)) {
                            ServerRow(model: model, server: server)
                        }
                        .contextMenu { moveMenu(server) }
                    }
                    .onMove { source, destination in move(source, to: destination) }
                    .moveDisabled(isFiltering || !model.configurationChangesAllowed)
                }
                if model.configurationAccess.allowsChanges {
                    Section("Available to Add") {
                        ForEach(filtered(inventory.addable)) { server in
                            NavigationLink(value: CompactRoute.server(server.identity)) {
                                ServerRow(model: model, server: server)
                            }
                        }
                    }
                }
                if model.orderUndo != nil, !isFiltering, model.configurationChangesAllowed {
                    Button("Undo Order Change") { model.undoServerOrder() }
                }
            }
            .listStyle(.inset)
            .navigationTitle("Servers")
            .searchable(text: $searchText, prompt: Text("Search servers"))
            .overlay { emptyState }
            .navigationDestination(for: CompactRoute.self) { route in
                compactDestination(route)
            }
        }
    }

    @ViewBuilder
    private func compactDestination(_ route: CompactRoute) -> some View {
        switch route {
        case .server(let identity):
            if let server = inventory.server(identity: identity) {
                ServerSharesView(model: model, server: server, shareSearch: $shareSearch) { share in
                    compactPath.append(.share(share.identity))
                }
                .onAppear { selectedServer = identity }
            } else {
                ContentUnavailableView("Choose a Server", systemImage: "server.rack",
                    description: Text("Choose a server on the left to see its shared folders."))
            }
        case .share(let identity):
            ShareDetailSheet(model: model, shareIdentity: identity)
        }
    }

    /// Selection only falls back when its identity truly disappeared; refresh, adding and
    /// ordering never move it. The compact stack drops pushed objects that are gone.
    private func reconcileSelection() {
        if let selectedServer, inventory.server(identity: selectedServer) == nil {
            self.selectedServer = inventory.managed.first?.identity ?? inventory.addable.first?.identity
        } else if selectedServer == nil {
            self.selectedServer = inventory.managed.first?.identity ?? inventory.addable.first?.identity
        }
        guard !compactPath.isEmpty else { return }
        for (index, route) in compactPath.enumerated() {
            let exists: Bool
            switch route {
            case .server(let identity):
                exists = inventory.server(identity: identity) != nil
            case .share(let identity):
                exists = allShares.contains { $0.identity == identity }
            }
            if !exists {
                compactPath.removeSubrange(index...)
                return
            }
        }
    }

    private var allShares: [ServerInventory.Share] {
        inventory.managed.flatMap(\.managedShares) + inventory.addable.flatMap(\.addableShares)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedServer) {
            Section("Managed") {
                ForEach(filtered(inventory.managed)) { server in
                    ServerRow(model: model, server: server)
                        .tag(server.identity)
                        .contextMenu { moveMenu(server) }
                }
                .onMove { source, destination in move(source, to: destination) }
                .moveDisabled(isFiltering || !model.configurationChangesAllowed)
            }
            if model.configurationAccess.allowsChanges {
                Section("Available to Add") {
                    ForEach(filtered(inventory.addable)) { server in
                        ServerRow(model: model, server: server).tag(server.identity)
                    }
                }
            }
            if model.orderUndo != nil, !isFiltering, model.configurationChangesAllowed {
                Button("Undo Order Change") { model.undoServerOrder() }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Servers")
        .overlay { emptyState }
    }

    /// The same empty state serves the wide sidebar and the compact server list; it is
    /// secondary guidance, not a replacement for adding a shared folder.
    @ViewBuilder
    private var emptyState: some View {
        if model.configurationAccess.allowsChanges && !model.hasConfiguration && inventory.addable.isEmpty {
            ContentUnavailableView {
                Label("No Shared Folders Yet", systemImage: "externaldrive.badge.plus")
            } description: {
                Text("Connect to a server in Finder with ⌘K, then return to Automnt. You can also add a shared folder by its complete SMB address.")
            } actions: {
                Button("Add Shared Folder…") { showingAddShare = true }
            }
        } else if model.configurationAccess.allowsChanges && model.hasConfiguration && inventory.managed.isEmpty && inventory.addable.isEmpty {
            ContentUnavailableView("No Servers", systemImage: "server.rack",
                description: Text("Add a shared folder by its complete SMB address."))
        }
    }

    @ViewBuilder
    private func moveMenu(_ server: ServerInventory.Server) -> some View {
        if let index = inventory.managed.firstIndex(where: { $0.identity == server.identity }) {
            // Keyboard and VoiceOver equivalent of the drag: the same controller saves.
            Button("Move Earlier") { moveServer(server.identity, to: index - 1) }
                .disabled(index == 0 || isFiltering || !model.configurationChangesAllowed)
            Button("Move Later") { moveServer(server.identity, to: index + 1) }
                .disabled(index >= inventory.managed.count - 1 || isFiltering || !model.configurationChangesAllowed)
        }
    }

    private func filtered(_ servers: [ServerInventory.Server]) -> [ServerInventory.Server] {
        guard isFiltering else { return servers }
        return servers.filter { server in
            server.displayName.localizedCaseInsensitiveContains(query)
                || server.host.localizedCaseInsensitiveContains(query)
        }
    }

    /// One drop persists immediately. Filtering disables dragging because the insert
    /// position would be ambiguous among the hidden rows.
    private func move(_ source: IndexSet, to destination: Int) {
        guard !isFiltering, let from = source.first else { return }
        let managed = inventory.managed
        guard managed.indices.contains(from) else { return }
        // `onMove` reports where to insert in the array's pre-removal coordinates; the
        // controller takes the row's final index, so a downward move shifts by one.
        let finalIndex = destination > from ? destination - 1 : destination
        moveServer(managed[from].identity, to: finalIndex)
    }

    private func moveServer(_ identity: String, to destination: Int) {
        guard destination >= 0, destination < inventory.managed.count else { return }
        // The controller reports a no-op instead of saving an unchanged order.
        model.moveServer(identity: identity, to: destination)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if model.configurationAccess != .ready && model.configurationAccess != .authorizedUnconfigured {
            ScrollView {
                configurationAccessView
            }
        } else if let identity = selectedServer, let server = inventory.server(identity: identity) {
            // The detail is a native sheet: address, locations, indexing, editing and
            // removal stay out of the row so the row keeps exactly one primary action.
            ServerSharesView(model: model, server: server, shareSearch: $shareSearch) { share in
                navigating = ShareNavigation(id: share.identity)
            }
        } else if model.isFirstRun {
            firstRunView
        } else {
            ContentUnavailableView("Choose a Server", systemImage: "server.rack",
                description: Text("Choose a server on the left to see its shared folders."))
        }
    }

    /// First launch after a clean install: the settings directory is ready, but no
    /// shared folder exists yet. This is a welcome, not an "access" error.
    private var firstRunView: some View {
        ContentUnavailableView {
            Label("Welcome to Automnt", systemImage: "externaldrive.badge.plus")
        } description: {
            Text("Add a shared folder to get started. Automnt will mount it automatically when the server is available.")
        } actions: {
            Button("Add Shared Folder…") { showingAddShare = true }
                .keyboardShortcut(.defaultAction)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var configurationAccessView: some View {
        ContentUnavailableView {
            Label(model.configurationAccessTitle, systemImage: "externaldrive.badge.wifi")
        } description: {
            Text(model.configurationAccessMessage)
            if model.snapshot != nil {
                Text("The last successfully read targets are shown for reference. Changes and new mounts are unavailable until access is restored.")
            }
        } actions: {
            ViewThatFits(in: .horizontal) {
                HStack { configurationAccessButtons }
                VStack { configurationAccessButtons }
            }
            .disabled(model.busy)
        }
    }

    @ViewBuilder
    private var configurationAccessButtons: some View {
        // ContentUnavailableView can compress action buttons to an equal narrow width;
        // fixedSize keeps the localized label intact so the vertical fallback can take over.
        Button(model.configurationAccessButton) { Task { await model.authorizeConfiguration() } }
            .keyboardShortcut(.defaultAction)
            .fixedSize(horizontal: true, vertical: false)
        Button("Later") { model.configurationAccess = .cancelled }
            .keyboardShortcut(.cancelAction)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// A "View details" request from the menu bar can arrive while a sheet is open;
    /// it switches the selection and re-targets the sheet on the same share.
    private func openRequestedDetail(_ request: ApplicationModel.DetailRequest?) {
        guard let request, let snapshot = model.snapshot, snapshot.revision == request.revision else { return }
        model.requestedDetail = nil
        if let server = inventory.server(identity: request.hostIdentity) {
            selectedServer = server.identity
        }
        guard (inventory.managed + inventory.addable).contains(where: { server in
            (server.managedShares + server.addableShares).contains { $0.identity == request.shareIdentity }
        }) else { return }
        navigating = ShareNavigation(id: request.shareIdentity)
    }

    // MARK: - Toolbar and status

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button("Add Shared Folder…", systemImage: "plus") { showingAddShare = true }
                .disabled(!model.configurationChangesAllowed)
        }
        ToolbarItem {
            Button("Try Automatic Mounting Now", systemImage: "arrow.triangle.2.circlepath") {
                Task { await model.tryFullRound() }
            }
            .disabled(!model.configurationChangesAllowed || !model.hasConfiguration)
        }
        ToolbarItem {
            Button("Refresh Status", systemImage: "arrow.clockwise") { model.reload() }
                .disabled(model.busy)
        }
        ToolbarItem {
            SettingsLink { Label("Settings", systemImage: "gearshape") }
        }
    }
}

/// One status surface for saved intent versus actual background service. It replaces
/// the old footer strip: normal runs are silent, and every non-healthy state gets one
/// plain-language explanation with a concrete next action.
private struct AutomationStatusCard: View {
    let model: ApplicationModel
    let attention: ServerSharesView.AutomationAttention

    private var intended: Bool { model.snapshot?.configuration.isAutomationEnabled == true }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title).font(.headline)
                    if attention == .applying {
                        ProgressView().controlSize(.small)
                    }
                }
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions.padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var statusIcon: some View {
        Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(attention == .managedByCLI ? Color.secondary : Color.orange)
            .accessibilityHidden(true)
    }

    private var icon: String {
        switch attention {
        case .applying: "arrow.triangle.2.circlepath"
        case .needsRepair, .notRunning: "exclamationmark.triangle.fill"
        case .waitingApproval: "clock.badge.questionmark"
        case .managedByCLI: "terminal"
        }
    }

    private var title: String {
        switch attention {
        case .applying:
            String(localized: "Applying Automatic Mounting Settings…")
        case .needsRepair:
            intended
                ? String(localized: "Automatic Mounting Didn’t Finish")
                : String(localized: "Background Mounting Didn’t Fully Stop")
        case .notRunning:
            String(localized: "Automatic Mounting Is On, but the Background Service Isn’t Running")
        case .waitingApproval:
            String(localized: "Automatic Mounting Is Waiting for System Approval")
        case .managedByCLI:
            String(localized: "Automatic Mounting Is Managed by the Command-Line Service")
        }
    }

    private var message: String {
        switch attention {
        case .applying:
            String(localized: "The status will update automatically when this finishes. Don’t toggle the switch again.")
        case .needsRepair:
            intended
                ? String(localized: "The background service didn’t confirm. Repairing retries the setup without mounting anything twice.")
                : String(localized: "The background service state is not confirmed. Repair it before trying again.")
        case .notRunning:
            String(localized: "Repair the background service so shared folders can mount after sign-in or network changes.")
        case .waitingApproval:
            String(localized: "Allow Automnt in Login Items; automatic mounting takes effect after that.")
        case .managedByCLI:
            String(localized: "This app doesn’t take over the background service. Check status in Settings.")
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch attention {
        case .applying:
            EmptyView()
        case .waitingApproval:
            HStack(spacing: 12) {
                Button("Open Login Items Settings") { ServiceController(mode: .baseline).openApprovalSettings() }
                    .buttonStyle(.borderedProminent)
                Button("Try Again") { Task { await model.activateAppBackground(repair: true) } }
                    .disabled(model.busy || model.automationChangeInFlight)
            }
        case .needsRepair, .notRunning:
            HStack(spacing: 12) {
                Button("Repair Background Mounting") {
                    Task { await model.activateAppBackground(repair: true) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.busy || model.automationChangeInFlight)
                SettingsLink { Text("Settings") }
            }
        case .managedByCLI:
            SettingsLink { Text("Settings") }
        }
    }
}

private struct DetailMessageCard: View {
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

/// Sidebar row: name plus the managed / addable / problem counts. It never expands
/// shares and never carries an action button.
private struct ServerRow: View {
    let model: ApplicationModel
    let server: ServerInventory.Server

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(server.displayName, systemImage: "server.rack")
                .lineLimit(1)
                .help(server.host)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if server.summary.problemCount > 0 {
                Label(problemSummary, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if roundHint != nil {
                Text(roundHint!)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Counts are formatted into whole phrases so every language gets a real resource
    /// instead of a sentence assembled around an embedded number.
    private var summary: String {
        let managed = String(format: String(localized: "Managed: %lld"), server.summary.managedCount)
        let addable = String(format: String(localized: "Available to add: %lld"), server.summary.addableCount)
        return "\(managed) · \(addable)"
    }

    private var problemSummary: String {
        String(format: String(localized: "%lld shared folders need attention"), server.summary.problemCount)
    }

    /// "Checked this round" and "not selected this round" are different from offline.
    private var roundHint: String? {
        guard server.isManaged else { return nil }
        switch model.roundStatus(forServer: server.identity) {
        case .selected, .checked: return String(localized: "Checked this round")
        case .notSelected: return nil
        }
    }

    private var accessibilityLabel: String {
        var parts = [server.displayName, summary]
        if server.summary.problemCount > 0 {
            parts.append(problemSummary)
        } else if let roundHint {
            parts.append(roundHint)
        }
        return parts.joined(separator: ", ")
    }
}

/// Right side of the window for one server: its own switch, then a compact managed and
/// addable list. Each row shows a name, a status and exactly one primary action.
private struct ServerSharesView: View {
    @Bindable var model: ApplicationModel
    let server: ServerInventory.Server
    @Binding var shareSearch: String
    let openDetail: (ServerInventory.Share) -> Void
    @State private var showingServerSettings = false
    @State private var automationPromptDismissed = false

    private var query: String { shareSearch.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func matches(_ share: ServerInventory.Share) -> Bool {
        query.isEmpty || share.name.localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        List {
            if let host {
                Section {
                    Toggle("Include This Server in Automatic Mounting", isOn: Binding(
                        get: { model.snapshot?.configuration.hosts.first(where: { managedServerIdentity($0) == server.identity })?.enabled ?? host.enabled },
                        set: { enabled in toggleServer(enabled) }))
                        .disabled(model.busy)
                    Text(automaticMountingCaption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Managed") {
                let managed = server.managedShares.filter(matches)
                if managed.isEmpty && server.managedShares.isEmpty {
                    Text("No shared folders have been added yet.").foregroundStyle(.secondary)
                }
                ForEach(managed) { share in
                    ShareRowView(model: model, host: host, share: share, openDetail: openDetail)
                }
            }

            Section("Available to Add") {
                let addable = server.addableShares.filter(matches)
                if addable.isEmpty && server.addableShares.isEmpty {
                    Text("No additional shared folders were found on this Mac.").foregroundStyle(.secondary)
                }
                ForEach(addable) { share in
                    ShareRowView(model: model, host: nil, share: share, openDetail: openDetail)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if let attention = automationAttention {
                    AutomationStatusCard(model: model, attention: attention)
                } else if showsAutomationPrompt {
                    automationPrompt
                }
                if automationAttention == nil, let issue = model.issue {
                    DetailMessageCard(text: issue, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                } else if automationAttention == nil, let notice = model.notice {
                    DetailMessageCard(text: notice, systemImage: "info.circle", tint: .secondary)
                }
            }
        }
        .searchable(text: $shareSearch, prompt: Text("Search shared folders"))
        .navigationTitle(server.displayName)
        .navigationSubtitle(server.host)
        .toolbar {
            ToolbarItem {
                Button("Server Settings…", systemImage: "slider.horizontal.3") { showingServerSettings = true }
                    .disabled(host == nil)
            }
        }
        .sheet(isPresented: $showingServerSettings) {
            if let host {
                ServerSettingsView(model: model, host: host)
            }
        }
    }

    fileprivate enum AutomationAttention: Equatable {
        case applying
        case needsRepair
        case notRunning
        case waitingApproval
        case managedByCLI
    }

    private var automationAttention: AutomationAttention? {
        guard model.configurationAccess.allowsChanges else { return nil }
        let intended = model.snapshot?.configuration.isAutomationEnabled == true
        switch model.backend {
        case .running:
            return nil
        case .transitioning:
            return .applying
        case .awaitingApproval:
            return intended ? .waitingApproval : .needsRepair
        case .unavailable:
            return .needsRepair
        case .stopped:
            return intended ? .notRunning : nil
        case .governedByCLI:
            return .managedByCLI
        }
    }

    private var showsAutomationPrompt: Bool {
        model.snapshot?.configuration.isAutomationEnabled == false &&
        automationAttention == nil &&
        !server.managedShares.isEmpty &&
        !automationPromptDismissed
    }

    private var automationPrompt: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Automatic Mounting Is Off")
                    .font(.headline)
                Text("Shared folders are added. Turn on automatic mounting so Automnt mounts them after sign-in or network changes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Turn On Automatic Mounting") {
                if let base = model.snapshot { model.saveAutomation(true, base: base) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.busy || model.automationChangeInFlight)
            .fixedSize(horizontal: true, vertical: false)
            Button("Later") { automationPromptDismissed = true }
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(12)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
        .onChange(of: server.managedShares.count) { _, _ in automationPromptDismissed = false }
    }

    private var automaticMountingCaption: String {
        if model.snapshot?.configuration.isAutomationEnabled == false {
            return String(localized: "The main automatic mounting switch is off. Turn it on to include this server.")
        }
        return String(localized: "When this is off, this server’s shared folders are no longer mounted automatically. Shared folders that are already mounted stay available.")
    }

    private var host: HostConfig? {
        model.snapshot?.configuration.hosts.first { managedServerIdentity($0) == server.identity }
    }

    private func toggleServer(_ enabled: Bool) {
        guard let base = model.snapshot else { return }
        let identity = server.identity
        model.save(base) { configuration in
            guard let index = configuration.hosts.firstIndex(where: { managedServerIdentity($0) == identity }) else { return }
            configuration.hosts[index].enabled = enabled
        }
    }
}

/// One share row: name, status and a single primary action. Address, locations,
/// indexing, editing and removal live in the detail sheet.
struct ShareRowView: View {
    @Bindable var model: ApplicationModel
    let host: HostConfig?
    let share: ServerInventory.Share
    let openDetail: (ServerInventory.Share) -> Void

    private var statusText: String {
        guard let config = configuredShare else { return String(localized: "Connected in Finder") }
        return Self.statusLabel(model.availability(of: config))
    }

    private var configuredShare: SMBShareConfig? {
        guard share.managed else { return nil }
        return host?.shares.first { smbResourceIdentity($0.smbURL) == share.identity }
    }

    static func statusLabel(_ availability: TargetAvailability) -> String {
        switch availability {
        case .usable: String(localized: "Available")
        case .notMounted: String(localized: "Not mounted")
        case .locationMismatch: String(localized: "Mounted at a different location")
        case .suppressedForThisSession: String(localized: "Ejected for this session")
        case .notEvaluatedThisRound: String(localized: "Not checked in the last round")
        case .unreachable: String(localized: "Server not reachable")
        case .authenticationRequired: String(localized: "Sign-in required")
        case .failed: String(localized: "Mounting failed")
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(share.name).lineLimit(1).help(share.name)
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            primaryAction
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { openDetail(share) }
        .contextMenu {
            Button("Show Details") { openDetail(share) }
            if let config = configuredShare, let host {
                if model.availability(of: config) == .usable {
                    Button("Eject") { Task { await model.eject(host: host, share: config) } }
                } else {
                    Button("Mount This Shared Folder") { Task { await model.mount(host: host, share: config) } }
                }
            }
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if !share.managed {
            Button("Add") { model.addShare(smbURL: share.smbURL) }
                .disabled(model.busy)
        } else if let config = configuredShare {
            switch model.availability(of: config) {
            case .usable:
                Button("Open in Finder") { model.openInFinder(config) }
            case .locationMismatch:
                Button("Review Locations") { openDetail(share) }
            case .authenticationRequired, .failed:
                // Sign-in and share failures need the cause and the next step, which the
                // detail states; opening a not-mounted folder would report the wrong reason.
                Button("Show Details") { openDetail(share) }
            case .unreachable:
                Button("Try Again") { Task { if let host { await model.mount(host: host, share: config) } } }
                    .disabled(host == nil)
            default:
                Button("Mount This Shared Folder") { Task { if let host { await model.mount(host: host, share: config) } } }
                    .disabled(host == nil)
            }
        }
    }
}
