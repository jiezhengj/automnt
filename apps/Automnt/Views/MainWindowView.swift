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
    @Environment(\.openSettings) private var openSettings
    @State private var selectedServer: String?
    @State private var searchText = ""
    @State private var shareSearch = ""
    @State private var showingAddShare = false
    @State private var expandedShareIdentity: String?
    @State private var compactPath: [CompactRoute] = []

    /// A sheet target identified by the share identity the user acted on, so the
    /// detail keeps pointing at the same share while the configuration is refreshed.
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
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .frame(minWidth: 380, minHeight: 480)
        .background(WindowAccessor { window in
            model.installWindowCloseGuard(window)
            model.installMainWindowFramePersistence(window)
        })
        .sheet(isPresented: addSheet) {
            AddShareView(model: model)
        }
        .alert(String(localized: "The server order could not be saved."), isPresented: orderIssuePresented) {
            Button("Dismiss", role: .cancel) { model.orderIssue = nil }
        } message: {
            if let issue = model.orderIssue { Text(issue) }
        }
        .onAppear { model.selectedServerIdentity = selectedServer }
        .onChange(of: model.requestedDetail, initial: true) { _, request in openRequestedDetail(request) }
        .onChange(of: inventory.managed.map(\.identity) + inventory.addable.map(\.identity), initial: true) { _, _ in
            reconcileSelection()
        }
        .onChange(of: selectedServer) { _, identity in
            shareSearch = ""
            model.selectedServerIdentity = identity
        }
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
    private var orderIssuePresented: Binding<Bool> {
        Binding(get: { model.orderIssue != nil }, set: { if !$0 { model.orderIssue = nil } })
    }

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

    /// Global actions belong to the sidebar level. They sit in the sidebar's own header,
    /// as system glass symbol buttons next to the level's title — not in a footer, not in
    /// the window toolbar, and not in the server content.
    private var sidebarHeader: some View {
        HStack(spacing: 12) {
            Text("Servers")
                .font(.title3.weight(.semibold))
            Spacer(minLength: 8)
            globalActions
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var globalActions: some View {
        HStack(spacing: 10) {
            Button {
                showingAddShare = true
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.medium))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .disabled(!model.configurationChangesAllowed)
            .help("Add Shared Folder…")
            .accessibilityLabel(String(localized: "Add Shared Folder…"))
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .help("Settings")
            .accessibilityLabel(String(localized: "Settings"))
        }
    }

    @ToolbarContentBuilder
    private var globalToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                showingAddShare = true
            } label: {
                Image(systemName: "plus")
            }
            .disabled(!model.configurationChangesAllowed)
            .help("Add Shared Folder…")
            .accessibilityLabel(String(localized: "Add Shared Folder…"))
        }
        ToolbarItem(placement: .navigation) {
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            .accessibilityLabel(String(localized: "Settings"))
        }
    }

    private enum CompactRoute: Hashable {
        case server(String)
    }

    private var compactLayout: some View {
        NavigationStack(path: $compactPath) {
            List {
                Section {
                    ForEach(filtered(inventory.managed)) { server in
                        NavigationLink(value: CompactRoute.server(server.identity)) {
                            ServerRow(model: model, server: server,
                                orderNumber: managedIndex(of: server) + 1,
                                showsDragHandle: !isFiltering && model.configurationChangesAllowed)
                        }
                        .accessibilityAction(named: Text("Move Earlier")) {
                            moveServer(server.identity, to: managedIndex(of: server) - 1)
                        }
                        .accessibilityAction(named: Text("Move Later")) {
                            moveServer(server.identity, to: managedIndex(of: server) + 1)
                        }
                    }
                    .onMove { source, destination in move(source, to: destination) }
                    .moveDisabled(isFiltering || !model.configurationChangesAllowed)
                } header: {
                    managedSectionHeader.background(ScrollInsetNormalizer())
                } footer: {
                    if !isFiltering {
                        Text(orderCaption)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
            }
            .listStyle(.plain)
            .navigationTitle("Servers")
            .searchable(text: $searchText, prompt: Text("Search servers"))
                .searchPresentationToolbarBehavior(.avoidHidingContent)
                .overlay {
                    if isFiltering {
                        sidebarSearchEmptyState
                    } else {
                        emptyState
                    }
                }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in handleOrderKey(press) }
            .safeAreaInset(edge: .top, spacing: 0) { resultBanner }
            .navigationDestination(for: CompactRoute.self) { route in
                compactDestination(route)
            }
            .toolbar { globalToolbar }
        }
    }

    @ViewBuilder
    private func compactDestination(_ route: CompactRoute) -> some View {
        switch route {
        case .server(let identity):
            if let server = inventory.server(identity: identity) {
                ServerSharesView(model: model, server: server, shareSearch: $shareSearch,
                    expandedShare: $expandedShareIdentity, normalizeTopInset: true)
                .onAppear { selectedServer = identity }
            } else {
                ContentUnavailableView("Choose a Server", systemImage: "server.rack",
                    description: Text("Choose a server on the left to see its shared folders."))
            }
        }
    }

    /// Selection only falls back when its identity truly disappeared; refresh, adding and
    /// ordering never move it. The compact stack drops pushed objects that are gone.
    /// The model copy feeds the Servers menu's keyboard move commands.
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
        VStack(spacing: 0) {
            sidebarHeader
            List(selection: $selectedServer) {
            Section {
                ForEach(filtered(inventory.managed)) { server in
                    ServerRow(model: model, server: server,
                        orderNumber: managedIndex(of: server) + 1,
                        showsDragHandle: !isFiltering && model.configurationChangesAllowed)
                        .tag(server.identity)
                        .accessibilityAction(named: Text("Move Earlier")) {
                            moveServer(server.identity, to: managedIndex(of: server) - 1)
                        }
                        .accessibilityAction(named: Text("Move Later")) {
                            moveServer(server.identity, to: managedIndex(of: server) + 1)
                        }
                }
                .onMove { source, destination in move(source, to: destination) }
                .moveDisabled(isFiltering || !model.configurationChangesAllowed)
                orderCaptionRow
            } header: {
                managedSectionHeader
            }
            if model.configurationAccess.allowsChanges {
                Section("Available to Add") {
                    ForEach(filtered(inventory.addable)) { server in
                        ServerRow(model: model, server: server).tag(server.identity)
                    }
                }
            }
        }
            .listStyle(.sidebar)
            .overlay { emptyState }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in handleOrderKey(press) }
        }
    }

    /// The order is shown, not explained: numbered badges plus a one-line header carry
    /// the meaning, and the long rationale lives in a tooltip for whoever wants it.
    private var managedSectionHeader: some View {
        Text("Managed · In Order")
    }

    /// One short line under the servers explains the order. A caption cannot pretend to
    /// be a button, and the numbers above carry the sequence at a glance.
    @ViewBuilder
    private var orderCaptionRow: some View {
        if !isFiltering {
            Text(orderCaption)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(orderCaption)
        }
    }

    private var orderCaption: String {
        if model.snapshot?.configuration.isMountAllEnabled == true {
            return String(localized: "Connects every reachable server, in order.")
        }
        return String(localized: "From top to bottom; stops at the first server that works.")
    }

    private func managedIndex(of server: ServerInventory.Server) -> Int {
        inventory.managed.firstIndex(where: { $0.identity == server.identity }) ?? -1
    }

    /// Option+arrow keeps keyboard order changes without a context menu. The same
    /// controller saves immediately, so keyboard, VoiceOver and drag share one path.
    private func handleOrderKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.contains(.option), model.configurationChangesAllowed, !isFiltering else {
            return .ignored
        }
        guard let identity = selectedServer,
              let index = inventory.managed.firstIndex(where: { $0.identity == identity }) else {
            return .ignored
        }
        let target = press.key == .upArrow ? index - 1 : index + 1
        guard target >= 0, target < inventory.managed.count else { return .ignored }
        moveServer(identity, to: target)
        return .handled
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
    private var sidebarSearchEmptyState: some View {
        if filtered(inventory.managed).isEmpty && filtered(inventory.addable).isEmpty {
            ContentUnavailableView {
                Label("No Matching Servers", systemImage: "magnifyingglass")
            } description: {
                Text(String(format: String(localized: "No managed or available server matches “%@”."), query))
            } actions: {
                Button("Clear Search") { searchText = "" }
            }
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
        guard !isFiltering, destination >= 0, destination < inventory.managed.count else { return }
        // The controller reports a no-op instead of saving an unchanged order.
        model.moveServer(identity: identity, to: destination)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        Group {
            if model.configurationAccess != .ready && model.configurationAccess != .authorizedUnconfigured {
                if model.accessDeferred {
                    deferredAccessView
                } else {
                    ScrollView {
                        configurationAccessView
                    }
                }
            } else if let identity = selectedServer, let server = inventory.server(identity: identity) {
                ServerSharesView(model: model, server: server, shareSearch: $shareSearch,
                    expandedShare: $expandedShareIdentity)
            } else if model.isFirstRun {
                firstRunView
            } else {
                ContentUnavailableView("Choose a Server", systemImage: "server.rack",
                    description: Text("Choose a server on the left to see its shared folders."))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // A server detail draws its own result line above its content; the other
            // states would otherwise swallow a check's result.
            if selectedServer.flatMap({ inventory.server(identity: $0) }) == nil {
                resultBanner
            }
        }
    }

    /// Result of the most recent action, shown at the surface that started it.
    @ViewBuilder
    private var resultBanner: some View {
        if model.messageSurface == .window, let issue = model.issue {
            DetailMessageCard(text: issue, systemImage: "exclamationmark.triangle.fill", tint: .orange)
        } else if model.messageSurface == .window, let notice = model.notice {
            DetailMessageCard(text: notice, systemImage: "info.circle", tint: .secondary)
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
        Button("Later") { model.accessDeferred = true }
            .keyboardShortcut(.cancelAction)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// "Later" leaves this panel instead of re-rendering it under another title: the
    /// window stays readable, and one persistent card keeps the way back visible.
    private var deferredAccessView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(model.configurationAccessTitle)
                .font(.title3.weight(.semibold))
            Text(model.configurationAccessMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("You can look at the servers on the left, but adding, changing and mounting stay unavailable until access is restored.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(model.configurationAccessButton) {
                model.accessDeferred = false
                Task { await model.authorizeConfiguration() }
            }
            .keyboardShortcut(.defaultAction)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A "View details" request from the menu bar can arrive while a sheet is open;
    /// it switches the selection and re-targets the sheet on the same share.
    private func openRequestedDetail(_ request: ApplicationModel.DetailRequest?) {
        guard let request, let snapshot = model.snapshot, snapshot.revision == request.revision else { return }
        model.requestedDetail = nil
        if let server = inventory.server(identity: request.hostIdentity) {
            selectedServer = server.identity
        }
        guard let server = (inventory.managed + inventory.addable).first(where: { server in
            (server.managedShares + server.addableShares).contains { $0.identity == request.shareIdentity }
        }) else { return }
        selectedServer = server.identity
        expandedShareIdentity = request.shareIdentity
        compactPath = [.server(server.identity)]
    }

    // MARK: - Toolbar and status

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
    /// Managed rows carry their try-order as a number, so the sequence is visible
    /// without a paragraph of explanation. Addable rows have no number.
    var orderNumber: Int?
    /// Managed rows show the system drag handle so reordering is discoverable; the
    /// whole row stays draggable. Addable rows have no order and no handle.
    var showsDragHandle = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
        if let orderNumber {
            Text(String(orderNumber))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(Circle().fill(.quaternary))
                .accessibilityHidden(true)
        }
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
        if showsDragHandle {
            Spacer(minLength: 4)
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .help("Drag to change the order")
                .accessibilityHidden(true)
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

/// Right side of the window for one server: its identity and settings, then the managed
/// and addable shares. Expanding a share in place replaces the old two-step sheet: the
/// status, actions, switch and location all appear under the row itself.
private struct ServerSharesView: View {
    @Bindable var model: ApplicationModel
    let server: ServerInventory.Server
    @Binding var shareSearch: String
    /// The expanded share lives one level up so the menu bar can reveal the same row.
    @Binding var expandedShare: String?
    /// In the compact stack the list starts below the toolbar; AppKit then adds the
    /// toolbar height a second time, so the duplicate inset is cleared there only.
    var normalizeTopInset = false
    @State private var showingServerSettings = false
    @State private var editingTarget: EditTarget?
    @State private var removingShare: SMBShareConfig?
    @State private var removalError: String?
    @Environment(\.openSettings) private var openSettings

    private struct EditTarget: Identifiable {
        let host: HostConfig
        let share: SMBShareConfig
        var id: String { share.smbURL }
    }

    private var query: String { shareSearch.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func matches(_ share: ServerInventory.Share) -> Bool {
        query.isEmpty || share.name.localizedCaseInsensitiveContains(query)
    }

    /// One definition of "can be added", shared by the list and its filtered-empty state.
    private var addableShares: [ServerInventory.Share] { server.addableShares }

    private var automationEnabled: Bool { model.snapshot?.configuration.isAutomationEnabled == true }
    private var masterOff: Bool { model.snapshot?.configuration.isAutomationEnabled == false }
    /// Automatic mounting is the product: a share switch only means something when the
    /// master switch and this server both participate. Otherwise it is shown but disabled.
    private var shareSwitchesAllowed: Bool {
        automationEnabled && (host?.enabled ?? false) && model.configurationChangesAllowed
    }

    var body: some View {
        List {
            if host != nil {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(server.host)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .background { if normalizeTopInset { ScrollInsetNormalizer() } }
                }
            }

            if let host {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Include This Server in Automatic Mounting", isOn: Binding(
                            get: { host.enabled },
                            set: { toggleServer($0) }))
                            .toggleStyle(.switch)
                            .disabled(masterOff || !model.configurationChangesAllowed)
                        Text(serverAutomationCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section("Managed") {
                let managed = server.managedShares.filter(matches)
                if managed.isEmpty && server.managedShares.isEmpty {
                    Text("No shared folders have been added yet.").foregroundStyle(.secondary)
                }
                ForEach(managed) { share in
                    managedRow(share, host: host)
                }
            }

            Section("Available to Add") {
                let addable = addableShares.filter(matches)
                if addable.isEmpty && server.addableShares.isEmpty {
                    Text("No additional shared folders were found on this Mac.").foregroundStyle(.secondary)
                }
                ForEach(addable) { share in
                    ShareRowView(model: model, host: nil, share: share)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if let attention = automationAttention {
                    AutomationStatusCard(model: model, attention: attention)
                } else if masterOff {
                    automaticMountingOffBanner
                }
                if model.messageSurface == .window, let issue = model.issue {
                    DetailMessageCard(text: issue, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                } else if model.messageSurface == .window, let notice = model.notice {
                    DetailMessageCard(text: notice, systemImage: "info.circle", tint: .secondary)
                }
            }
        }
        .searchable(text: $shareSearch, prompt: Text("Search shared folders"))
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .overlay {
            if !query.isEmpty,
               server.managedShares.filter(matches).isEmpty,
               addableShares.filter(matches).isEmpty {
                ContentUnavailableView {
                    Label("No Matching Shared Folders", systemImage: "magnifyingglass")
                } description: {
                    Text(String(format: String(localized: "No shared folder matches “%@”."), query))
                } actions: {
                    Button("Clear Search") { shareSearch = "" }
                }
            }
        }
        .navigationTitle(server.displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingServerSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Server Settings")
                .accessibilityLabel(String(localized: "Server Settings"))
                .disabled(host == nil || model.busy)
            }
        }
        .sheet(isPresented: $showingServerSettings) {
            if let host {
                ServerSettingsView(model: model, host: host)
            }
        }
        .sheet(item: $editingTarget) { target in
            EditShareView(model: model, host: target.host, share: target.share)
        }
        .confirmationDialog("Remove This Shared Folder?", isPresented: removalPresented, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let share = removingShare, let failure = model.removeShare(share) {
                    removalError = failure
                } else {
                    expandedShare = nil
                    removalError = nil
                }
                removingShare = nil
            }
            Button("Cancel", role: .cancel) { removingShare = nil }
        } message: {
            Text("Shared folders that are already mounted stay available.")
        }
    }

    private var automaticMountingOffBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Automatic Mounting Is Off")
                .font(.callout.weight(.medium))
            Spacer(minLength: 12)
            Button("Turn On Automatic Mounting") {
                if let base = model.snapshot { model.saveAutomation(true, base: base) }
            }
            .controlSize(.small)
            .disabled(model.busy || model.automationChangeInFlight)
            Button("Settings") { openSettings() }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var removalPresented: Binding<Bool> {
        Binding(get: { removingShare != nil }, set: { if !$0 { removingShare = nil } })
    }

    private var serverAutomationCaption: String {
        if masterOff {
            return String(localized: "The main automatic mounting switch is off. Turn it on to include this server.")
        }
        return String(localized: "When this is off, this server’s shared folders are no longer mounted automatically. Shared folders that are already mounted stay available.")
    }

    @ViewBuilder
    private func managedRow(_ share: ServerInventory.Share, host: HostConfig?) -> some View {
        let isExpanded = expandedShare == share.identity
        let config = host.flatMap { host in
            host.shares.first(where: { smbResourceIdentity($0.smbURL) == share.identity })
        }
        VStack(alignment: .leading, spacing: 10) {
            ShareRowView(model: model, host: host, share: share,
                isExpanded: isExpanded,
                onToggle: { withAnimation(.snappy) { expandedShare = isExpanded ? nil : share.identity } },
                automatic: config?.enabled ?? true,
                automaticAllowed: shareSwitchesAllowed,
                onToggleAutomatic: { enabled in
                    if let host, let config { setEnabled(enabled, host: host, share: config) }
                })
            if isExpanded, let host, let config {
                inlineDetail(host: host, share: config)
                    .padding(.leading, 30)
                    .padding(.bottom, 6)
            }
        }
    }

    /// The expanded block only adds what the row cannot carry: where the share is, the
    /// manual fallback actions, then the management actions — separated, never mixed.
    @ViewBuilder
    private func inlineDetail(host: HostConfig, share: SMBShareConfig) -> some View {
        let detail = model.detail(of: share)
        let actions = DetailActionPolicy.available(detail, busy: model.busy)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Mount Location")
                    .foregroundStyle(.secondary)
                Text(verbatim: detail.actualMountPoint ?? detail.expectedMountPoint)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            if detail.showsExpectedAndActualLocations {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: String(localized: "Automnt’s saved location is %@."), detail.expectedMountPoint))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button("Use This Location") {
                        if let base = model.snapshot { model.useActualMountPoint(share, base: base) }
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                    .disabled(model.busy)
                }
            }

            if detail.status == .mounting || detail.status == .recovering {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Mounting").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 10) {
                    if let primary = primaryAction(host: host, share: share, detail: detail, actions: actions) {
                        Button(primary.title) { primary.run() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(model.busy)
                    }
                    if actions.contains(.eject) {
                        Button("Eject") {
                            Task { await model.eject(host: host, share: share) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.busy)
                    }
                    Spacer(minLength: 0)
                }
            }

            Divider()

            HStack(spacing: 18) {
                Button("Edit Shared Folder") {
                    editingTarget = EditTarget(host: host, share: share)
                }
                .buttonStyle(.link)
                .disabled(model.busy)
                Button("Remove from Automnt…") {
                    removingShare = share
                }
                .buttonStyle(.link)
                .foregroundStyle(.red)
                .disabled(model.busy)
                Spacer(minLength: 0)
            }

            if let removalError {
                Text(removalError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private struct InlineAction {
        let title: String
        let run: () -> Void
    }

    /// One manual action per state; this is the fallback, not the row's identity.
    private func primaryAction(host: HostConfig, share: SMBShareConfig,
                               detail: ShareDetail, actions: Set<DetailAction>) -> InlineAction? {
        if actions.contains(.openOccupyingLocation) {
            return InlineAction(title: String(localized: "Show the Occupying Folder in Finder")) {
                model.openPathInFinder(share.mountPoint)
            }
        }
        if actions.contains(.openInFinder) {
            return InlineAction(title: String(localized: "Open in Finder")) {
                if detail.showsExpectedAndActualLocations, let actual = detail.actualMountPoint {
                    model.openPathInFinder(actual)
                } else {
                    model.openInFinder(share)
                }
            }
        }
        if actions.contains(.mount) {
            return InlineAction(title: String(localized: "Connect and Open")) {
                Task {
                    await model.mount(host: host, share: share)
                    if let actual = model.detail(of: share).actualMountPoint {
                        model.openPathInFinder(actual)
                    }
                }
            }
        }
        if detail.status == .authenticationRequired {
            return InlineAction(title: String(localized: "Connect in Finder")) {
                if let url = URL(string: share.smbURL) { NSWorkspace.shared.open(url) }
            }
        }
        return nil
    }

    private func toggleServer(_ enabled: Bool) {
        guard let base = model.snapshot else { return }
        let identity = server.identity
        model.save(base) { configuration in
            guard let index = configuration.hosts.firstIndex(where: { managedServerIdentity($0) == identity }) else { return }
            configuration.hosts[index].enabled = enabled
        }
    }

    private func setEnabled(_ enabled: Bool, host: HostConfig, share: SMBShareConfig) {
        guard let base = model.snapshot else { return }
        let serverIdentity = managedServerIdentity(host)
        let shareIdentity = smbResourceIdentity(share.smbURL)
        model.save(base) { configuration in
            guard let hostIndex = configuration.hosts.firstIndex(where: { managedServerIdentity($0) == serverIdentity }),
                  let shareIndex = configuration.hosts[hostIndex].shares.firstIndex(where: {
                      smbResourceIdentity($0.smbURL) == shareIdentity
                  }) else { return }
            configuration.hosts[hostIndex].shares[shareIndex].enabled = enabled
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

    private var host: HostConfig? {
        model.snapshot?.configuration.hosts.first { managedServerIdentity($0) == server.identity }
    }

}

/// One share row. The whole row expands or collapses its own detail underneath; the row
/// carries no state-dependent button, so its entry point never moves.
struct ShareRowView: View {
    @Bindable var model: ApplicationModel
    let host: HostConfig?
    let share: ServerInventory.Share
    var isExpanded = false
    var onToggle: (() -> Void)?
    var automatic = true
    var automaticAllowed = true
    var onToggleAutomatic: ((Bool) -> Void)?

    private var statusText: String {
        guard let config = configuredShare else { return String(localized: "Connected in Finder") }
        return Self.statusLabel(model.availability(of: config))
    }

    private var configuredShare: SMBShareConfig? {
        guard share.managed else { return nil }
        return host?.shares.first { smbResourceIdentity($0.smbURL) == share.identity }
    }

    static func statusSymbol(_ availability: TargetAvailability) -> String {
        switch availability {
        case .usable: "checkmark.circle.fill"
        case .locationMismatch: "checkmark.circle.fill"
        case .locationOccupied: "exclamationmark.circle.fill"
        case .notMounted, .suppressedForThisSession, .notEvaluatedThisRound: "circle.dashed"
        case .unreachable, .authenticationRequired, .failed: "exclamationmark.triangle.fill"
        }
    }

    static func statusTint(_ availability: TargetAvailability) -> Color {
        switch availability {
        case .usable: .green
        case .locationMismatch: .green
        case .locationOccupied: .orange
        case .notMounted, .suppressedForThisSession, .notEvaluatedThisRound: .secondary
        case .unreachable, .authenticationRequired, .failed: .orange
        }
    }

    static func statusLabel(_ availability: TargetAvailability) -> String {
        switch availability {
        case .usable: String(localized: "Available")
        case .notMounted: String(localized: "Not mounted")
        case .locationMismatch: String(localized: "Available")
        case .locationOccupied: String(localized: "Location occupied")
        case .suppressedForThisSession: String(localized: "Ejected for this session")
        case .notEvaluatedThisRound: String(localized: "Not checked in the last round")
        case .unreachable: String(localized: "Server not reachable")
        case .authenticationRequired: String(localized: "Sign-in required")
        case .failed: String(localized: "Mounting failed")
        }
    }

    var body: some View {
        if share.managed {
            HStack(spacing: 12) {
                Button { onToggle?() } label: { managedLabel }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityText)
                    .accessibilityHint(String(localized: "Opens this shared folder’s details."))
                if let onToggleAutomatic {
                    Toggle("Mount This Shared Folder Automatically", isOn: Binding(
                        get: { automatic },
                        set: { onToggleAutomatic($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!automaticAllowed)
                        .help("Mount This Shared Folder Automatically")
                        .accessibilityLabel(automaticAccessibilityLabel)
                }
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
            }
            .contextMenu { managedMenu }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                addableLabel
                Spacer(minLength: 12)
                Button("Add") { model.addShare(smbURL: share.smbURL) }
                    .disabled(model.busy)
            }
            .padding(.vertical, 2)
        }
    }

    private var managedLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let config = configuredShare {
                Image(systemName: Self.statusSymbol(model.availability(of: config)))
                    .font(.callout)
                    .foregroundStyle(Self.statusTint(model.availability(of: config)))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(share.name).lineLimit(1).help(share.name)
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var addableLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(share.name).lineLimit(1).help(share.name)
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private var accessibilityText: String {
        "\(share.name), \(statusText)"
    }

    private var automaticAccessibilityLabel: String {
        String(localized: "Mount This Shared Folder Automatically") + ", " + share.name
    }

    @ViewBuilder
    private var managedMenu: some View {
        if let config = configuredShare, let host {
            switch model.availability(of: config) {
            case .usable, .locationMismatch:
                Button("Open in Finder") { model.openInFinder(config) }
                Button("Eject") { Task { await model.eject(host: host, share: config) } }
            case .locationOccupied:
                Button("Show the Occupying Folder in Finder") { model.openPathInFinder(config.mountPoint) }
            default:
                Button("Mount This Shared Folder") { Task { await model.mount(host: host, share: config) } }
            }
        }
    }
}


/// AppKit adds the toolbar height to a list's top content inset when the window crosses
/// from the split layout into the compact one, on top of a scroll view that is already
/// placed below the toolbar. The result is a 52 pt blank band above the first section.
/// This normalizer clears that duplicate inset and keeps automatic adjustment off.
struct ScrollInsetNormalizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NormalizerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class NormalizerView: NSView {
    private var token: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        normalize()
        if let token { NotificationCenter.default.removeObserver(token) }
        token = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification,
            object: window, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.normalize() }
        }
    }

    private func normalize() {
        var view: NSView? = self
        while let current = view {
            if let scroll = current as? NSScrollView {
                if scroll.automaticallyAdjustsContentInsets || scroll.contentInsets.top != 0 {
                    scroll.automaticallyAdjustsContentInsets = false
                    scroll.contentInsets.top = 0
                }
                return
            }
            view = current.superview
        }
    }
}
