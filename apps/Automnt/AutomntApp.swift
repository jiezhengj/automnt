import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement
import AppKit
import CoreServices
import AutomntCore
import AutomntPlatform

@MainActor
final class DraftTerminationDelegate: NSObject, NSApplicationDelegate {
    /// Returns true when quitting may proceed immediately (no unsaved draft).
    /// A dirty draft presents its confirmation asynchronously and returns false, so
    /// this callback never calls `terminate` reentrantly from inside the AppKit
    /// termination query (which AppKit ignores).
    static var request: (() -> Bool)?
    static var approved = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !Self.approved, let request = Self.request else { return .terminateNow }
        return request() ? .terminateNow : .terminateCancel
    }

    static func requestTermination() {
        if approved {
            NSApplication.shared.terminate(nil)
        } else if let request {
            if request() { NSApplication.shared.terminate(nil) }
        } else {
            NSApplication.shared.terminate(nil)
        }
    }

    static func finish() {
        approved = true
        NSApplication.shared.terminate(nil)
    }
}

/// Intercepts the main window's close button and ⌘W with the same draft protection as
/// ⌘Q. It forwards all other delegate calls to the delegate SwiftUI installed.
@MainActor
final class WindowCloseGuard: NSObject, NSWindowDelegate {
    private static var guards: [ObjectIdentifier: WindowCloseGuard] = [:]
    private weak var previousDelegate: NSWindowDelegate?
    private weak var window: NSWindow?
    private weak var model: ApplicationModel?
    private var allowNextClose = false

    static func install(on window: NSWindow, model: ApplicationModel) {
        let key = ObjectIdentifier(window)
        if let existing = guards[key], window.delegate === existing {
            existing.model = model
            return
        }
        let guardObject = WindowCloseGuard()
        guardObject.window = window
        guardObject.model = model
        guardObject.previousDelegate = window.delegate
        guards[key] = guardObject
        window.delegate = guardObject
    }

    static func closeAfterConfirmation(_ window: NSWindow) {
        guards[ObjectIdentifier(window)]?.closeAfterConfirmation()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowNextClose {
            allowNextClose = false
            return previousDelegate?.windowShouldClose?(sender) ?? true
        }
        return model?.requestWindowClose(sender) ?? true
    }

    override func responds(to selector: Selector!) -> Bool {
        if selector == #selector(NSWindowDelegate.windowShouldClose(_:)) { return true }
        return super.responds(to: selector) || (previousDelegate?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if previousDelegate?.responds(to: selector) == true { return previousDelegate }
        return super.forwardingTarget(for: selector)
    }

    func closeAfterConfirmation() {
        guard let window else { return }
        allowNextClose = true
        window.performClose(nil)
    }
}

/// Installs the close guard on the real NSWindow after SwiftUI creates it.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { if let window = nsView.window { onWindow(window) } }
    }
}

@MainActor @Observable
final class ApplicationModel {
    var snapshot: ConfigSnapshot?
    /// A failure worth showing in the window; never used to fake a state change.
    var issue: String?
    /// A save was refused because another writer changed the revision. Forms keep their
    /// draft and offer an explicit re-read; nothing is overwritten automatically.
    var configurationConflictDetected = false
    /// A confirmation of what actually happened (added, saved, ejected).
    var notice: String?
    /// A configuration exists but could not be read: not a first-run empty state.
    var configurationReadFailed = false
    var configurationAccess: ConfigurationAccessState = .awaitingAuthorization
    /// The user chose "Later" on the access panel. The window stays usable read-only and
    /// keeps one persistent way back instead of trapping them on the same panel.
    var accessDeferred = false
    var configurationChangesAllowed: Bool { configurationAccess.allowsChanges && !busy }
    var configurationAccessTitle: String {
        switch configurationAccess {
        case .awaitingAuthorization, .cancelled: String(localized: "Get Started with Automnt")
        default: String(localized: "Access to Automnt Settings")
        }
    }
    var configurationAccessButton: String {
        switch configurationAccess {
        case .awaitingAuthorization, .cancelled: String(localized: "Continue…")
        default: String(localized: "Allow Access…")
        }
    }
    var configurationAccessMessage: String {
        switch configurationAccess {
        case .awaitingAuthorization, .cancelled:
            String(localized: "Automnt keeps its settings on this Mac. Shared folders you have already added will appear automatically.")
        case .wrongDirectory, .directoryMissing, .bookmarkStale, .permissionRevoked:
            String(localized: "Access was not granted. Continue to allow access to Automnt’s settings.")
        case .readFailed:
            String(localized: "Your saved settings could not be read. Try again, or allow access again to restore permission.")
        case .ready, .authorizedUnconfigured: ""
        }
    }
    /// A clean install has no configuration yet; this is a welcome state, not an access error.
    var isFirstRun: Bool { configurationAccess == .authorizedUnconfigured && !hasConfiguration }
    var busy = false
    var actionReadiness: ManualActionReadiness = .needsSetup
    var manualMountReady = false
    var missingBackendGuidance: String?
    var backend: SettingsSurface.BackendStatus = .stopped
    /// One background transition at a time. The switch is disabled while this is true,
    /// so closing and reopening it quickly cannot leave a failed half-transition.
    var automationChangeInFlight = false

    var loginStatus = SMAppService.mainApp.status
    var changingLogin = false
    var loginIssue: String?

    var notificationPermission: NotificationPermission = .unavailable
    var requestingNotifications = false
    var notificationIssue: String?
    var soundEnabled = false
    var soundNeedsRepair = false

    /// Foreground discovery: SMB shares mounted on this Mac right now.
    var discovered: [MountedShareDiscovery.Candidate] = []
    /// Kernel mount-table fact per configured share identity. Absence only proves
    /// that this share is not mounted here.
    var mountObservations: [String: MountPathState] = [:]
    var mountObservedAt: Date?
    /// The last real round, read back from what the background actually committed.
    var roundObservations: [String: VolumeObservation] = [:]
    var roundIssue: AutomntIssue?
    var roundObservedAt: Date?
    var selection: EvaluationSelection?
    /// Shares the user ejected during this network/login session.
    var suppressedIdentities: Set<String> = []

    var orderUndo: ServerOrderUndo?

    struct DetailRequest: Equatable {
        let id = UUID()
        let revision: ConfigRevision
        let hostIdentity: String
        let shareIdentity: String
    }
    var requestedDetail: DetailRequest?

    private var authorization: AuthorizedDirectory?
    private let permissions = PermissionStore()
    private var ledger = OperationLedger()

    var hasAuthorization: Bool { authorization != nil }
    var hasConfiguration: Bool { snapshot != nil }

    // MARK: - Drafts and quitting

    /// One entry per open editable page. A page registers when it appears and updates
    /// its dirty flag as fields change; quitting asks these pages to save before the
    /// process ends. The save closures use the same revision-checked path as buttons.
    private struct DraftEntry {
        var isDirty: Bool
        let save: () -> Bool
    }
    private var drafts: [UUID: DraftEntry] = [:]

    func registerDraft(isDirty: Bool, save: @escaping () -> Bool) -> UUID {
        let id = UUID()
        drafts[id] = DraftEntry(isDirty: isDirty, save: save)
        return id
    }

    func updateDraft(_ id: UUID, isDirty: Bool) {
        drafts[id]?.isDirty = isDirty
    }

    func removeDraft(_ id: UUID) {
        drafts.removeValue(forKey: id)
    }

    var hasUnsavedDraft: Bool { drafts.values.contains { $0.isDirty } }

    /// Installed when the window appears. AppKit calls the delegate for ⌘Q, the menu
    /// Quit item and Dock Quit; a quit with no unsaved input ends the process directly.
    func installTerminationHandler() {
        DraftTerminationDelegate.request = { [weak self] in self?.requestQuit() ?? true }
    }

    /// ⌘W is handled before AppKit can close a sheet, because a SwiftUI sheet may be
    /// dismissed by the key window without consulting the window delegate. The monitor
    /// only consumes the event when an unsaved draft exists; otherwise AppKit closes
    /// the window/sheet normally.
    private static var closeMonitor: Any?
    func installWindowCloseShortcut() {
        guard Self.closeMonitor == nil else { return }
        Self.closeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isCommandW = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
                && event.charactersIgnoringModifiers?.lowercased() == "w"
            guard isCommandW, let self, self.hasUnsavedDraft else { return event }
            if let window = NSApp.keyWindow {
                _ = self.requestWindowClose(window)
            }
            return nil
        }
    }

    func installWindowCloseGuard(_ window: NSWindow) {
        WindowCloseGuard.install(on: window, model: self)
    }

    weak var mainWindow: NSWindow?
    private static var framedWindows: Set<ObjectIdentifier> = []
    private static let settingsWindowSizeKey = "AutomntSettingsWindowContentSize"
    private var settingsWindowObservers: [ObjectIdentifier: [NSObjectProtocol]] = [:]
    private var centeredSettingsWindows: Set<ObjectIdentifier> = []

    /// Restores the user's last main-window frame, or saves the approved default on
    /// first launch. AppKit keeps saving moves/resizes through the autosave name.
    func installMainWindowFramePersistence(_ window: NSWindow) {
        mainWindow = window
        installWindowFrame(window, name: "AutomntMainWindowFrameV2",
                           preferredContentSize: NSSize(width: 1103, height: 692),
                           relativeTo: nil)
    }

    /// The settings window belongs to the window the user is working in, so its position
    /// is derived from the main window every time it opens. Only its size is remembered:
    /// restoring a stale origin is what used to leave it far away from the main window.
    func installSettingsWindowFramePersistence(_ window: NSWindow) {
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame AutomntSettingsWindowFrameV2")
        let key = ObjectIdentifier(window)
        guard settingsWindowObservers[key] == nil else { return }
        Self.framedWindows.insert(key)
        if let raw = UserDefaults.standard.string(forKey: Self.settingsWindowSizeKey) {
            let size = NSSizeFromString(raw)
            if size.width >= 560, size.height >= 520 {
                window.setContentSize(size)
            }
        } else {
            window.setContentSize(NSSize(width: 680, height: 620))
        }
        let show = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) {
                [weak self, weak window] _ in
                guard let self, let window, !self.centeredSettingsWindows.contains(key) else { return }
                self.centeredSettingsWindows.insert(key)
                self.centerSettingsWindow(window)
            }
        let close = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main) {
                [weak self, weak window] _ in
                guard let self, let window else { return }
                UserDefaults.standard.set(NSStringFromSize(window.contentView?.frame.size ?? window.frame.size),
                                          forKey: Self.settingsWindowSizeKey)
                self.centeredSettingsWindows.remove(key)
                self.settingsWindowObservers.removeValue(forKey: key)?.forEach(NotificationCenter.default.removeObserver)
                Self.framedWindows.remove(key)
            }
        settingsWindowObservers[key] = [show, close]
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            if self.centerSettingsWindow(window) { self.centeredSettingsWindows.insert(key) }
        }
    }

    /// Returns whether the window was placed relative to a visible main window.
    @discardableResult
    private func centerSettingsWindow(_ window: NSWindow) -> Bool {
        if let parent = mainWindow, parent.isVisible, parent != window {
            center(window, over: parent)
            return true
        }
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            var frame = window.frame
            frame.origin = NSPoint(x: visible.midX - frame.width / 2,
                                   y: visible.midY - frame.height / 2)
            window.setFrame(frame, display: true)
        }
        return false
    }

    private func installWindowFrame(_ window: NSWindow, name: String,
                                    preferredContentSize: NSSize,
                                    relativeTo parent: NSWindow?) {
        let key = ObjectIdentifier(window)
        guard !Self.framedWindows.contains(key) else { return }
        Self.framedWindows.insert(key)
        // Read any saved frame before installing autosave: setFrameAutosaveName may
        // otherwise persist the placeholder frame and make setFrameUsingName succeed.
        if window.setFrameUsingName(name) {
            window.setFrameAutosaveName(name)
            clampOnScreen(window)
            return
        }
        window.setFrameAutosaveName(name)
        window.setContentSize(preferredContentSize)
        if let parent {
            center(window, over: parent)
        } else {
            clampOnScreen(window)
        }
        window.saveFrame(usingName: name)
    }

    private func center(_ window: NSWindow, over parent: NSWindow) {
        var frame = window.frame
        frame.origin = NSPoint(x: parent.frame.midX - frame.width / 2,
                               y: parent.frame.midY - frame.height / 2)
        if let visible = parent.screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        window.setFrame(frame, display: true)
    }

    private func clampOnScreen(_ window: NSWindow) {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        window.setFrame(frame, display: true)
    }

    /// Returns whether the window may close immediately. A dirty draft starts the
    /// native confirmation after the AppKit close query returns.
    func requestWindowClose(_ window: NSWindow) -> Bool {
        guard hasUnsavedDraft else { return true }
        Task { @MainActor in self.presentWindowCloseConfirmation(for: window) }
        return false
    }

    private func presentWindowCloseConfirmation(for window: NSWindow) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Close the window with unsaved changes?")
        alert.informativeText = String(localized: "Your edits are not saved yet. Save them before closing the window, or discard them.")
        alert.addButton(withTitle: String(localized: "Save and Close"))
        alert.addButton(withTitle: String(localized: "Discard and Close"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if saveDrafts() { WindowCloseGuard.closeAfterConfirmation(window) }
        case .alertSecondButtonReturn:
            WindowCloseGuard.closeAfterConfirmation(window)
        default:
            break
        }
    }

    func saveDrafts() -> Bool {
        for entry in drafts.values.filter(\.isDirty) {
            guard entry.save() else { return false }
        }
        return true
    }

    /// Returns whether the app may quit immediately. With a dirty draft it starts the
    /// native confirmation after the termination query returns and refuses this one.
    private func requestQuit() -> Bool {
        guard hasUnsavedDraft else { return true }
        Task { @MainActor in self.presentQuitConfirmation() }
        return false
    }

    private func presentQuitConfirmation() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Save changes before quitting?")
        alert.informativeText = String(localized: "Your edits are not saved yet. Save them before Automnt quits, or discard them.")
        alert.addButton(withTitle: String(localized: "Save and Quit"))
        alert.addButton(withTitle: String(localized: "Discard and Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveDraftsAndQuit()
        case .alertSecondButtonReturn:
            DraftTerminationDelegate.finish()
        default:
            break
        }
    }

    /// Saves every dirty page. A failure keeps the window and the draft open and shows
    /// the failure through the same `issue` channel as a failed Save button.
    func saveDraftsAndQuit() {
        // The page itself reports why it could not save (field errors or the
        // revision-checked save failure); do not replace that with a generic
        // folder-access message.
        guard saveDrafts() else { return }
        DraftTerminationDelegate.finish()
    }

    func discardDraftsAndQuit() {
        DraftTerminationDelegate.finish()
    }

    // MARK: - Projection

    /// Managed servers in saved order plus discovered servers that are not managed yet.
    /// 侧栏当前选中的服务器身份，由主窗口同步；菜单里的移动命令用它。
    var selectedServerIdentity: String?

    func canMoveSelectedServer(earlier: Bool) -> Bool {
        guard configurationChangesAllowed, let identity = selectedServerIdentity,
              let index = inventory.managed.firstIndex(where: { $0.identity == identity }) else {
            return false
        }
        let target = index + (earlier ? -1 : 1)
        return target >= 0 && target < inventory.managed.count
    }

    /// 键盘与菜单共用的顺序移动入口；保存仍由 `moveServer` 的 CAS 控制器完成。
    func moveSelectedServer(earlier: Bool) {
        guard let identity = selectedServerIdentity,
              let index = inventory.managed.firstIndex(where: { $0.identity == identity }) else { return }
        moveServer(identity: identity, to: index + (earlier ? -1 : 1))
    }

    var inventory: ServerInventory.Snapshot {
        ServerInventory.build(
            configuration: snapshot?.configuration,
            discovered: discovered.map {
                ServerInventory.DiscoveredShare(host: $0.host, port: $0.port, name: $0.share.name,
                    smbURL: $0.share.smbURL, mountPoint: $0.share.mountPoint)
            },
            mounted: mountedIdentities,
            foundProblems: problemIdentities)
    }

    private var mountedIdentities: Set<String> {
        Set((snapshot?.configuration.hosts ?? []).flatMap(\.shares).compactMap { share in
            guard let identity = smbResourceIdentity(share.smbURL) else { return nil }
            return mountObservations[identity] == .smb(identity: identity) ? identity : nil
        })
    }

    /// Only real exceptions are counted. A user eject, a disabled target, an
    /// unchecked server and a not-yet-mounted share are normal states.
    private var problemIdentities: Set<String> {
        var problems = Set<String>()
        for host in snapshot?.configuration.hosts ?? [] {
            for share in host.shares {
                guard let identity = smbResourceIdentity(share.smbURL) else { continue }
                // A disabled target is a deliberate choice, not a problem to report.
                guard share.enabled, host.enabled else { continue }
                if isException(availability(of: share)) { problems.insert(identity) }
            }
        }
        return problems
    }

    // MARK: - Loading

    /// The fixed directory is program-owned: create it on launch instead of treating a
    /// missing directory as an access failure. Bookmark-based builds keep resolving.
    private func openSettingsDirectory() throws -> AuthorizedDirectory {
        if PermissionStore.hasFixedDirectoryEntitlement {
            return try permissions.prepareFixedSettings()
        }
        return try permissions.resolve()
    }

    func restore() {
        guard authorization == nil else { return }
        do { try load(openSettingsDirectory()) }
        catch { accessFailed(error) }
    }

    func authorizeConfiguration() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try load(openSettingsDirectory()) }
        catch { accessFailed(error) }
    }

    private func accessFailed(_ error: any Error) {
        switch error as? PermissionStore.AccessError {
        case .wrongDirectory: configurationAccess = .wrongDirectory
        case .directoryMissing: configurationAccess = .directoryMissing
        case .bookmarkStale: configurationAccess = .bookmarkStale
        case .permissionRevoked: configurationAccess = .permissionRevoked
        case nil: configurationAccess = .permissionRevoked
        }
        configurationReadFailed = snapshot != nil
        authorization = nil
        manualMountReady = false
        actionReadiness = .needsSetup
    }

    func reload() {
        guard !busy else { return }
        do { try load(openSettingsDirectory()) }
        catch { accessFailed(error) }
    }

    /// Read-only refresh for a window activation, a volume mount/eject or a changed CLI
    /// configuration. It re-reads the configuration and observed state but never
    /// evaluates, mounts or overwrites an open draft.
    func refreshObservedState() {
        guard !busy else { return }
        if authorization == nil { restore() } else { reload() }
    }

    private func load(_ directory: AuthorizedDirectory) throws {
        authorization = directory
        do {
            snapshot = try FileConfigRepository(authorizedDirectory: directory.url).read()
            // A shutdown during a worker handoff can leave an intent whose child has
            // already exited. The evaluation lock is the liveness fence: clear only
            // when no worker holds it.
            try? WorkerOperationStore(authorizedDirectory: directory.url).abandonPendingForRepair()
            if let snapshot { adoptBackendRevisionIfPossible(to: snapshot.revision) }
            configurationReadFailed = false
            configurationAccess = .ready
            accessDeferred = false
            issue = nil
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == ENOENT {
            // ENOENT may refer to the directory or its lock, rather than the plist.
            // Only confirmed absence inside a still-valid grant permits creation.
            try permissions.validateDirectory(directory.url)
            snapshot = nil
            configurationReadFailed = false
            configurationAccess = .authorizedUnconfigured
            issue = nil
        } catch {
            // Preserve the last successful snapshot for read-only inspection.
            configurationReadFailed = true
            configurationAccess = .readFailed
            issue = String(localized: "Automnt couldn’t read your settings. Try again. It has not replaced them.")
        }
        let preference = NotificationPreferenceStore(authorizedDirectory: directory.url).readForDelivery()
        soundEnabled = preference.soundEnabled
        soundNeedsRepair = preference.needsRepair
        authorization = directory
        enforceLogRetention()
        refreshActionReadiness()
        refreshStatus()
    }

    // MARK: - Local logs

    /// Applies the approved local policy (7 days / 5 MB) without touching diagnostics
    /// exports or any business configuration.
    func enforceLogRetention() {
        guard let authorization else { return }
        try? LogRetention.enforce(files: LogRetention.defaultLogFiles(configurationDirectory: authorization.url))
    }

    func clearLogs() {
        guard let authorization else { return }
        do {
            try LogRetention.clear(files: LogRetention.defaultLogFiles(configurationDirectory: authorization.url))
            issue = nil
            notice = String(localized: "Local logs were cleared.")
        } catch {
            show(error)
        }
    }

    // MARK: - Read-only status

    /// Reads the kernel mount table, foreground discovery and the last committed round.
    /// It never contacts a server, writes configuration or changes the selection.
    func refreshStatus() {
        var observations: [String: MountPathState] = [:]
        for host in snapshot?.configuration.hosts ?? [] {
            for share in host.shares {
                guard let identity = smbResourceIdentity(share.smbURL) else { continue }
                observations[identity] = NetFSWorkerOperation.mountPathState(at: share.mountPoint)
            }
        }
        mountObservations = observations
        mountObservedAt = Date()
        do { discovered = try MountedShareDiscovery.read() }
        catch { discovered = [] }
        loadRoundSummary()
        loadSessionSuppression()
    }

    private func loadRoundSummary() {
        guard let authorization else { clearRound(); return }
        let url = authorization.url.appendingPathComponent("background-observations.plist")
        guard let data = try? PrivateAtomicFile.read(url),
              let summary = try? PropertyListDecoder().decode(BackgroundEvaluationSummary.self, from: data) else {
            clearRound()
            return
        }
        roundObservations = Dictionary(summary.observations.map { ($0.identity, $0) }, uniquingKeysWith: { _, last in last })
        roundIssue = summary.issue
        roundObservedAt = summary.observedAt
        rebuildSelection(observedAt: summary.observedAt)
    }

    private func clearRound() {
        roundObservations = [:]
        roundIssue = nil
        roundObservedAt = nil
        selection = nil
    }

    /// The committed round records per-share observations, not the probed server list,
    /// so a server counts as checked only when one of its shares was actually observed.
    private func rebuildSelection(observedAt: Date) {
        guard let snapshot else { selection = nil; return }
        var checked: [String] = []
        for host in snapshot.configuration.hosts {
            let identity = managedServerIdentity(host)
            let reached = host.shares.contains { share in
                guard let shareIdentity = smbResourceIdentity(share.smbURL) else { return false }
                return roundObservations[shareIdentity] != nil
            }
            if reached { checked.append(identity) }
        }
        let skipped = snapshot.configuration.hosts.map(managedServerIdentity).filter { !checked.contains($0) }
        // The shared rule checks servers in order and stops after the first reachable one,
        // so more than one reached server means the file came from another contract.
        let selected = checked.count == 1 ? checked[0] : nil
        selection = EvaluationSelection(roundSelectedServer: selected, checkedServers: checked,
            skippedServers: skipped, observedAt: observedAt)
    }

    private func loadSessionSuppression() {
        guard let authorization else { suppressedIdentities = []; return }
        let state = RecoveryStateRepository(url: authorization.url.appendingPathComponent("mount-recovery-state.plist")).read()
        guard state.isReadable else { suppressedIdentities = []; return }
        suppressedIdentities = Set(state.file.volumes.compactMap { key, record in
            record.state == .suppressed ? key : nil
        })
    }

    func roundStatus(forServer identity: String) -> EvaluationSelection.RoundServerStatus {
        selection?.status(forServer: identity) ?? .notSelected
    }

    private func serverReachable(_ identity: String) -> Bool? {
        guard let snapshot, let host = snapshot.configuration.hosts.first(where: { managedServerIdentity($0) == identity }) else {
            return nil
        }
        let observed = host.shares.compactMap { share -> VolumeObservation? in
            guard let shareIdentity = smbResourceIdentity(share.smbURL) else { return nil }
            return roundObservations[shareIdentity]
        }
        if observed.contains(where: { $0.status == .offline }) { return false }
        if selection?.checkedServers.contains(identity) == true { return true }
        return nil
    }

    // MARK: - Per-target state

    func displayName(of host: HostConfig) -> String {
        if let alias = host.alias, !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return alias }
        return host.host
    }

    /// What the user can do with one share right now. Mounted facts come from the kernel
    /// table; unreachable and failure states come only from a real round.
    func availability(of share: SMBShareConfig) -> TargetAvailability {
        guard let identity = smbResourceIdentity(share.smbURL) else { return .failed }
        let path = mountObservations[identity]
        if path == .smb(identity: identity) { return .usable }
        if suppressedIdentities.contains(identity) { return .suppressedForThisSession }
        // The same share is mounted somewhere else: usable, just not at the configured path.
        if actualMountPoint(of: share) != nil { return .locationMismatch }
        // The kernel reports another volume at the configured location, so the task path
        // is taken; this is a location conflict, not an idle "not mounted" state.
        if isLocationOccupied(share) { return .locationOccupied }
        if let observation = roundObservations[identity] {
            switch observation.status {
            case .offline: return .unreachable
            case .failed:
                return observation.issue == .credentialFailure ? .authenticationRequired : .failed
            case .suppressed: return .suppressedForThisSession
            case .healthy, .stopped, .evaluating, .unconfigured, .needsAuthorization: break
            }
        }
        // A round that reached no server probed every enabled managed server; that is the
        // only case where an absent mount may be presented as unreachable.
        if roundIssue == .offline { return .unreachable }
        if let selection, !selection.checkedServers.isEmpty,
           let host = hostOwning(share), !selection.checkedServers.contains(managedServerIdentity(host)) {
            return .notEvaluatedThisRound
        }
        return .notMounted
    }

    /// Where this exact SMB identity is mounted today, independent of the configured path.
    /// Reads the kernel-observed discovery list; it never contacts the server.
    func actualMountPoint(of share: SMBShareConfig) -> String? {
        guard let identity = smbResourceIdentity(share.smbURL) else { return nil }
        return discovered.first { smbResourceIdentity($0.share.smbURL) == identity }?.share.mountPoint
    }

    /// True when the kernel reports a different volume (SMB or not) at the configured
    /// location. That is a location conflict, not "this share happens to be unmounted".
    func isLocationOccupied(_ share: SMBShareConfig) -> Bool {
        guard let identity = smbResourceIdentity(share.smbURL) else { return false }
        let path = mountObservations[identity]
        if path == .occupied { return true }
        if case .smb(let mounted) = path { return mounted != identity }
        return false
    }

    func hostOwning(_ share: SMBShareConfig) -> HostConfig? {
        guard let identity = smbResourceIdentity(share.smbURL) else { return nil }
        return snapshot?.configuration.hosts.first { host in
            host.shares.contains { smbResourceIdentity($0.smbURL) == identity }
        }
    }

    /// Exceptions only. A user eject, a disabled target, an unchecked server, a share
    /// mounted elsewhere and a not-yet-mounted share are all normal states, not problems.
    func isException(_ availability: TargetAvailability) -> Bool {
        switch availability {
        case .unreachable, .authenticationRequired, .failed, .locationOccupied: true
        default: false
        }
    }

    func availabilityReport(of share: SMBShareConfig) -> AvailabilityReport {
        let setting: SettingOutcome
        if snapshot?.configuration.isAutomationEnabled != true {
            setting = .savedButNotEnabled
        } else {
            switch backend {
            case .running: setting = .savedAndEnabled
            case .awaitingApproval, .transitioning, .governedByCLI: setting = .savedButApprovalPending
            case .stopped: setting = .savedButNotEnabled
            case .unavailable: setting = .saveFailed
            }
        }
        return AvailabilityReport(configurationSaved: snapshot != nil, setting: setting,
            availability: availability(of: share), observedAt: mountObservedAt)
    }

    /// The detail fact sheet for one managed share, in the reading order the design fixes.
    func detail(of share: SMBShareConfig) -> ShareDetail {
        let host = hostOwning(share)
        let identity = smbResourceIdentity(share.smbURL)
        let observed = identity.flatMap { roundObservations[$0] }
        let path = identity.flatMap { mountObservations[$0] } ?? .absent
        let mounted = identity != nil && path == .smb(identity: identity!)
        let occupiedByAnotherVolume = isLocationOccupied(share)
        // The same share mounted at another path is a fact from the kernel table; the
        // configured path being taken is a different fact and must not read as failure.
        let actual = actualMountPoint(of: share)
        let issue: AutomntIssue? = observed?.issue
        let selectedThisRound: Bool
        if let selection, let host {
            selectedThisRound = selection.checkedServers.contains(managedServerIdentity(host))
        } else {
            selectedThisRound = true
        }
        return ShareDetailBuilder.build(share: share,
            expectedMountPoint: share.mountPoint,
            mounted: mounted,
            actualMountPoint: actual,
            observedAt: observed?.observedAt ?? ((mounted || actual != nil || occupiedByAnotherVolume) ? mountObservedAt : nil),
            serverReachable: host.flatMap { serverReachable(managedServerIdentity($0)) },
            selectedThisRound: selectedThisRound,
            automationEnabled: snapshot?.configuration.isAutomationEnabled ?? false,
            serverEnabled: host?.enabled ?? true,
            shareEnabled: share.enabled,
            suppressed: identity.map { suppressedIdentities.contains($0) } ?? false,
            recovering: identity.map { isWorking(.singleShareMount, target: $0) || isWorking(.normalEject, target: $0) } ?? false,
            locationOccupied: occupiedByAnotherVolume,
            recoveryFailed: observed?.status == .failed,
            issue: issue)
    }

    // MARK: - Background and actions

    func refreshActionReadiness() {
        missingBackendGuidance = nil
        manualMountReady = false
        guard configurationAccess.allowsChanges, let authorization, let snapshot else {
            actionReadiness = .needsSetup
            backend = .stopped
            return
        }
        do {
            let state = try BackendStateStore(authorizedDirectory: authorization.url).read()
            let baseline = ServiceController(mode: .baseline).status
            let recovery = ServiceController(mode: .recovery).status
            let service = BackgroundServiceReadiness.classify(configuration: snapshot.configuration,
                baseline: baseline, recovery: recovery)
            manualMountReady = ManualActionReadiness.canMount(state, revision: snapshot.revision,
                automationEnabled: snapshot.configuration.isAutomationEnabled,
                baseline: baseline, recovery: recovery)
            actionReadiness = ManualActionReadiness.classify(state, revision: snapshot.revision,
                requiredServices: [service])
            backend = SettingsSurface.backendStatus(state: state,
                intended: snapshot.configuration.isAutomationEnabled)
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == 2 {
            let home = PermissionStore.expectedDirectory.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let definition = LegacyCLIServiceDefinition.inspect(at: home.appendingPathComponent("Library/LaunchAgents/com.user.automnt.plist"))
            actionReadiness = .needsRepair
            backend = snapshot.configuration.isAutomationEnabled ? .unavailable : .stopped
            switch definition {
            case .recognized:
                missingBackendGuidance = String(localized: "An older command-line service is installed. Update or release it before enabling app background mounting.")
            case .unknown:
                missingBackendGuidance = String(localized: "The command-line service could not be checked. Confirm its installation and folder access before enabling app background mounting.")
            case .absent:
                missingBackendGuidance = String(localized: "Background control has not been set up. A running command-line service still needs to be checked before the app can take control.")
            }
        } catch {
            actionReadiness = .needsRepair
            backend = .unavailable
        }
    }

    func activateAppBackground(repair: Bool = false) async {
        guard !busy, configurationChangesAllowed, let authorization, let base = snapshot else { return }
        busy = true
        defer { busy = false; refreshActionReadiness(); refreshStatus() }
        do {
            if base.configuration.isAutomationEnabled {
                do { try await HelperAuthorizationCheck.ensure(applicationURL: Bundle.main.bundleURL, directory: authorization) }
                catch {
                    if (error as? AutomntIssue) == .authorizationRequired {
                        issue = String(localized: "Background mounting cannot access the configuration folder. Keep Automnt open to manage your configuration; the background service has not been changed.")
                    } else { show(error) }
                    return
                }
            }
            let store = BackendStateStore(authorizedDirectory: authorization.url)
            if repair, let state = try? store.read(), state.phase == .failed {
                // A failed transition can be fenced by a launch intent left by a worker
                // that already exited. The lock proves no worker is still holding it.
                try? WorkerOperationStore(authorizedDirectory: authorization.url).abandonPendingForRepair()
            }
            let controls = AppServiceHandoffAdapter(authorizedDirectory: authorization.url, revision: base.revision)
            let adapter = EvaluatingHandoffAdapter(controls: controls,
                applicationURL: Bundle.main.bundleURL, directory: authorization)
            let coordinator = HandoffCoordinator(authorizedDirectory: authorization.url)
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            var state: BackendState
            do { state = try store.read() }
            catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == ENOENT {
                // First activation on a fresh install has no backend-state file yet.
                // Initialize a stopped owner instead of treating absence as damage.
                state = try store.initialize(revision: base.revision)
            } catch {
                guard repair else { throw error }
                state = try await coordinator.recoverAppInterruptedTransition(adapter: adapter, deadline: deadline)
            }
            guard state.owner != .cli, state.desiredOwner != .cli else {
                throw AutomntIssue.incompatibleOwner
            }
            if repair, state.phase == .awaitingApproval || state.phase == .stopping || state.phase == .activating {
                guard state.transitionID != nil else { throw AutomntIssue.configurationConflict }
                state = try await coordinator.recoverAppInterruptedTransition(adapter: adapter, deadline: deadline)
            }
            let result: BackendState
            if !repair, state.phase == .awaitingApproval, let id = state.transitionID {
                result = try await coordinator.completeApproval(id: id, adapter: adapter, deadline: deadline)
            } else {
                guard state.phase == .stopped || state.phase == .failed || (repair && state.phase == .active) else {
                    throw AutomntIssue.configurationConflict
                }
                result = try await coordinator.transfer(to: base.configuration.isAutomationEnabled ? .app : .none, expectedGeneration: state.generation,
                    revision: base.revision, adapter: adapter, deadline: deadline)
            }
            snapshot = try FileConfigRepository(authorizedDirectory: authorization.url).read()
            switch result.phase {
            case .awaitingApproval:
                issue = String(localized: "Allow Automnt in Login Items in System Settings, then check again.")
                notice = nil
            case .stopped:
                issue = nil
                notice = String(localized: "App background mounting is off. Mounted shared folders remain available.")
            case .active:
                issue = nil
                notice = String(localized: "App background mounting is enabled. Shared folders will mount when the server and credentials are available.")
            default:
                issue = String(localized: "Background mounting could not be changed. Check the service state and try again.")
                notice = nil
            }
        } catch let error as AutomntIssue where error == .signalUnavailable || error == .timeout {
            issue = String(localized: "Automatic mounting didn’t finish. Repair the background service and try again.")
        } catch { show(error) }
    }

    /// A full round runs the same bounded evaluation the background service uses and
    /// reports its real result; it does not simulate one.
    func tryFullRound() async {
        guard configurationChangesAllowed, let authorization else { return }
        guard let base = latestSnapshotForAction() else { return }
        // A previous round may have left a launch intent whose child exited. Clear it
        // only when the evaluation lock proves no worker is still alive.
        try? WorkerOperationStore(authorizedDirectory: authorization.url).abandonPendingForRepair()
        guard let operation = begin(.fullEvaluation, target: nil) else { return }
        busy = true
        defer { busy = false; end(operation); refreshActionReadiness(); refreshStatus() }
        do {
            let store = BackendStateStore(authorizedDirectory: authorization.url)
            var state = try store.read()
            guard state.owner == .app, state.phase == .active else {
                notice = String(localized: "A full round needs app background mounting to be active. Turn on automatic mounting in Settings, or mount one shared folder from its row.")
                return
            }
            if state.revision != base.revision {
                // The app saved while this backend stayed active; its state must catch up
                // instead of turning into a conflict the user cannot act on.
                _ = try? store.adoptConfigurationRevision(expected: state.revision, new: base.revision)
                state = try store.read()
            }
            let controls = AppServiceHandoffAdapter(authorizedDirectory: authorization.url, revision: base.revision)
            let adapter = EvaluatingHandoffAdapter(controls: controls,
                applicationURL: Bundle.main.bundleURL, directory: authorization)
            do {
                try await adapter.requestEvaluation(state: state, deadline: ContinuousClock.now.advanced(by: .seconds(30)))
            } catch let error as AutomntIssue where error == .configurationConflict {
                state = try store.read()
                if state.owner == .app, state.phase == .active {
                    _ = try? store.adoptConfigurationRevision(expected: state.revision, new: base.revision)
                    state = try store.read()
                }
                try await adapter.requestEvaluation(state: state, deadline: ContinuousClock.now.advanced(by: .seconds(30)))
            }
            notice = String(localized: "The round finished. Each shared folder shows its own result and the time it was checked.")
        } catch let error as AutomntIssue where error == .signalUnavailable || error == .timeout {
            issue = String(localized: "A previous mount attempt didn’t finish. Repair background mounting, then try the round again.")
        } catch { show(error) }
    }

    func openInFinder(_ share: SMBShareConfig) {
        do { try FinderAccess.open(share: share); issue = nil }
        catch {
            switch error as? AutomntIssue {
            case .offline: issue = String(localized: "This shared folder is not mounted yet. Check the server connection and automatic mounting.")
            case .pathConflict: issue = String(localized: "Another volume occupies this shared folder’s location. Eject that volume in Finder before continuing.")
            default: issue = String(localized: "This shared folder could not be opened. Check its mount status and folder access.")
            }
        }
    }

    /// Opens a concrete mount path without assuming it is this share's configured path.
    /// Used for "open the actual location" and for inspecting an occupied location.
    func openPathInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            issue = String(localized: "That folder is no longer available. Refresh the list and check the current location.")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        issue = nil
    }

    /// Adopts the location where the same SMB identity is already mounted as the
    /// configured mount point. One revision-checked save; nothing is ejected or moved.
    @discardableResult
    func useActualMountPoint(_ share: SMBShareConfig, base: ConfigSnapshot) -> Bool {
        guard let identity = smbResourceIdentity(share.smbURL),
              let actual = actualMountPoint(of: share), actual != share.mountPoint,
              ShareFormFields.isValidMountPath(actual) else { return false }
        // Start from the latest revision so a save in another window is not reported as
        // a conflict for an action the user just took in this one.
        let saved = save(latestSnapshotForAction() ?? base) { configuration in
            for hostIndex in configuration.hosts.indices {
                guard let shareIndex = configuration.hosts[hostIndex].shares.firstIndex(where: {
                    smbResourceIdentity($0.smbURL) == identity
                }) else { continue }
                configuration.hosts[hostIndex].shares[shareIndex].mountPoint = actual
            }
        }
        if saved { notice = String(localized: "Using the current mount location. Future mounts use the new location.") }
        return saved
    }

    func mount(host: HostConfig, share: SMBShareConfig) async {
        guard let base = latestSnapshotForAction(),
              let identity = smbResourceIdentity(share.smbURL) else { return }
        guard !busy, let operation = begin(.singleShareMount, target: identity) else { return }
        refreshActionReadiness()
        guard let authorization, manualMountReady else {
            end(operation)
            notice = String(localized: "Mounting one shared folder needs app background mounting. Set it up in Settings first.")
            return
        }
        busy = true
        defer { busy = false; end(operation); refreshActionReadiness(); refreshStatus() }
        let applicationURL = Bundle.main.bundleURL
        let response = await Task.detached {
            ManualEject.mount(applicationURL: applicationURL, directory: authorization,
                snapshot: base, host: host, share: share)
        }.value
        if response.requiresReconciliation {
            issue = String(localized: "The mount result could not be confirmed. Check the shared folder before trying again.")
        } else if let error = response.issue {
            show(error)
        } else {
            issue = nil
            notice = String(localized: "The shared folder is mounted. Open it in Finder to use it.")
        }
    }

    /// Normal eject: non-forced, with no routine confirmation. A busy volume is
    /// reported as a failure and is never escalated to a forced eject.
    func eject(host: HostConfig, share: SMBShareConfig) async {
        guard let base = latestSnapshotForAction(),
              let identity = smbResourceIdentity(share.smbURL) else { return }
        guard !busy, let operation = begin(.normalEject, target: identity) else { return }
        refreshActionReadiness()
        guard let authorization, manualMountReady else {
            end(operation)
            notice = String(localized: "Ejecting here needs app background mounting. Set it up in Settings first; you can still eject the folder in Finder.")
            return
        }
        busy = true
        defer { busy = false; end(operation); refreshActionReadiness(); refreshStatus() }
        let applicationURL = Bundle.main.bundleURL
        let response = await Task.detached {
            ManualEject.perform(applicationURL: applicationURL, directory: authorization,
                snapshot: base, host: host, share: share)
        }.value
        if response.requiresReconciliation {
            issue = String(localized: "The eject result could not be confirmed. Automatic recovery is paused until the operation is repaired.")
        } else if let error = response.issue {
            show(error)
        } else {
            notice = String(localized: "Shared folder ejected. It will stay disconnected until the network or login session changes.")
        }
    }

    // MARK: - Configuration changes

    /// Immediate, revision-checked save. Views read their value back from `snapshot`,
    /// so a failed save leaves the previously saved value on screen.
    @discardableResult
    func save(_ base: ConfigSnapshot, _ change: (inout AutomntConfig) -> Void) -> Bool {
        guard configurationChangesAllowed, let authorization else { return false }
        do {
            var configuration = base.configuration
            change(&configuration)
            let saved = try FileConfigRepository(authorizedDirectory: authorization.url).save(
                configuration, baseRevision: base.revision)
            snapshot = saved
            adoptBackendRevision(from: base.revision, to: saved.revision)
            issue = nil
            refreshActionReadiness()
            refreshStatus()
            return true
        } catch {
            if (error as? AutomntIssue) == .configurationConflict {
                configurationConflictDetected = true
            }
            show(error)
            return false
        }
    }

    /// Re-reads the latest configuration after a revision conflict. The form keeps every
    /// typed value; only the baseline for the next save changes. This never mounts,
    /// ejects, or writes anything.
    func reloadAfterConfigurationConflict() {
        guard let authorization else { return }
        do {
            snapshot = try FileConfigRepository(authorizedDirectory: authorization.url).read()
            configurationConflictDetected = false
            issue = nil
            notice = String(localized: "Reloaded the latest settings. Your input is kept; check it before saving.")
            refreshActionReadiness()
            refreshStatus()
        } catch {
            show(error)
        }
    }

    /// Re-reads the configuration right before an action. A revision saved elsewhere is
    /// not an error: the action continues on the latest snapshot. Returns nil only when
    /// the configuration really cannot be read, and shows that failure.
    private func latestSnapshotForAction() -> ConfigSnapshot? {
        guard let authorization else { return snapshot }
        do {
            snapshot = try FileConfigRepository(authorizedDirectory: authorization.url).read()
            configurationConflictDetected = false
            return snapshot
        } catch {
            show(error)
            return nil
        }
    }

    /// The durable backend state carries the configuration revision it was activated for.
    /// After a save it must advance with the configuration, otherwise the next evaluation is
    /// rejected as a stale conflict and the app tells the user about a change that never
    /// happened. Best effort: a backend owned by the CLI, still transitioning, or stopped is
    /// left to the regular repair path.
    private func adoptBackendRevision(from previous: ConfigRevision?, to revision: ConfigRevision) {
        guard let authorization else { return }
        let expected = previous ?? revision
        do {
            try BackendStateStore(authorizedDirectory: authorization.url)
                .adoptConfigurationRevision(expected: expected, new: revision)
        } catch {
            // Not an active app-owned backend; nothing to advance.
        }
    }

    private func adoptBackendRevisionIfPossible(to revision: ConfigRevision) {
        guard let authorization else { return }
        let store = BackendStateStore(authorizedDirectory: authorization.url)
        guard let state = try? store.read(), state.owner == .app, state.phase == .active,
              state.revision != revision else { return }
        _ = try? store.adoptConfigurationRevision(expected: state.revision, new: revision)
    }

    func saveAutomation(_ enabled: Bool, base: ConfigSnapshot) {
        guard !automationChangeInFlight else {
            notice = String(localized: "Applying automatic mounting settings. Please wait.")
            return
        }
        guard !busy else {
            notice = String(localized: "Applying automatic mounting settings. Please wait.")
            return
        }
        guard save(base, { $0.automationEnabled = enabled }) else { return }
        automationChangeInFlight = true
        notice = enabled
            ? String(localized: "Turning on automatic mounting…")
            : String(localized: "Automatic mounting is off. Mounted shared folders remain available.")
        // Turning the master switch on is not just a preference: it must register the
        // background owner. Persist intent first, then run the same activation path as
        // Settings uses. Turning it off drains the service through the same coordinator.
        let savedRevision = snapshot?.revision
        Task {
            defer { automationChangeInFlight = false }
            guard snapshot?.revision == savedRevision,
                  snapshot?.configuration.isAutomationEnabled == enabled else { return }
            await activateAppBackground(repair: true)
        }
    }

    func saveRecovery(_ enabled: Bool, base: ConfigSnapshot) {
        guard save(base, { $0.autoMountRecovery = enabled }) else { return }
        notice = String(localized: "Automatic recovery settings were saved. Check background mounting to apply the change.")
        if snapshot?.configuration.isAutomationEnabled == true {
            let savedRevision = snapshot?.revision
            Task {
                guard snapshot?.revision == savedRevision,
                      snapshot?.configuration.isAutomationEnabled == true else { return }
                await activateAppBackground(repair: true)
            }
        }
    }

    /// 挂载范围（FR-027）。改变它只写配置；下一轮评估、排序说明与 CLI 共用同一字段。
    /// 默认 `first_reachable` 保持升级前行为，因此不需要在保存时触发额外副作用。
    func saveMountPolicy(_ policy: MountPolicy, base: ConfigSnapshot) {
        guard save(base, { $0.mountPolicy = policy }) else { return }
        notice = String(localized: "Mount scope saved. The next round checks servers in this scope.")
    }

    /// Retry limits come from the shared bounds; invalid input is reported per field
    /// instead of being silently widened or clamped.
    @discardableResult
    func saveRetryPolicy(base: ConfigSnapshot, attempts: Int, intervalMs: Int, windowMs: Int) -> Bool {
        guard let policy = RetryPolicyBounds.policy(attempts: attempts, intervalMs: intervalMs, windowMs: windowMs) else {
            return false
        }
        return save(base) { $0.retryPolicy = policy }
    }

    func saveSound(_ enabled: Bool) {
        guard configurationChangesAllowed, let authorization else { return }
        do {
            try NotificationPreferenceStore(authorizedDirectory: authorization.url).save(
                NotificationPreferences(notificationSoundEnabled: enabled))
            soundEnabled = enabled
            soundNeedsRepair = false
            issue = nil
        } catch { show(error) }
    }

    /// Adds one share from a complete, credential-free SMB address. The first share
    /// creates the configuration; later shares keep the server identity and order.
    @discardableResult
    func addShare(smbURL: String, name: String? = nil, mountPoint: String? = nil) -> String? {
        let value = smbURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var candidate = shareCandidate(from: value) else {
            return fail(String(localized: "Enter a complete SMB address such as smb://host/share, without a user name or password."))
        }
        // The name and location are derived from the address but the user may change
        // them; the saved values are exactly what the form showed.
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidate = ManagedMembership.Candidate(host: candidate.host, port: candidate.port,
                alias: candidate.alias, timeoutMs: candidate.timeoutMs,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                smbURL: candidate.smbURL,
                mountPoint: mountPoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? candidate.mountPoint)
        } else if let mountPoint, !mountPoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidate = ManagedMembership.Candidate(host: candidate.host, port: candidate.port,
                alias: candidate.alias, timeoutMs: candidate.timeoutMs, name: candidate.name,
                smbURL: candidate.smbURL,
                mountPoint: mountPoint.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard configurationChangesAllowed, let authorization else {
            return fail(String(localized: "The change could not be saved. Check folder access and try again."))
        }
        guard !busy else { return fail(String(localized: "The change could not be saved. Check folder access and try again.")) }
        if let base = snapshot {
            let outcome = ManagedMembershipController(repository: FileConfigRepository(authorizedDirectory: authorization.url))
                .add(candidate, baseRevision: base.revision)
            if let saved = outcome.snapshot {
                snapshot = saved
                adoptBackendRevision(from: base.revision, to: saved.revision)
                issue = nil
                notice = saved.configuration.isAutomationEnabled
                    ? String(localized: "The shared folder was added. Automatic mounting mounts it when the server is available.")
                    : String(localized: "The shared folder was added. Turn on automatic mounting to mount your shared folders in the background.")
                refreshActionReadiness()
                refreshStatus()
                return nil
            }
            if let issue = outcome.issue {
                return fail(message(for: issue))
            }
            return fail(String(localized: "This shared folder is already listed with the same address or location."))
        }
        // Confirmed absence in the authorized canonical directory; create uses CAS.
        var configuration = AutomntConfig()
        configuration.automationEnabled = false
        configuration.hosts = [HostConfig(host: candidate.host, port: candidate.port,
            timeoutMs: candidate.timeoutMs, shares: [SMBShareConfig(name: candidate.name,
                smbURL: candidate.smbURL, mountPoint: candidate.mountPoint)])]
        do {
            snapshot = try FileConfigRepository(authorizedDirectory: authorization.url).create(configuration)
            if let created = snapshot { adoptBackendRevision(from: nil, to: created.revision) }
            configurationAccess = .ready
            configurationReadFailed = false
            issue = nil
            notice = String(localized: "The shared folder was added. Turn on automatic mounting to mount your shared folders in the background.")
            refreshActionReadiness()
            refreshStatus()
            return nil
        } catch {
            return fail(message(for: (error as? AutomntIssue) ?? .signalUnavailable))
        }
    }

    /// Records a failure where every entry point can show it and returns it for the form.
    @discardableResult
    private func fail(_ message: String) -> String {
        issue = message
        return message
    }

    /// Removal changes management only: it never ejects and never deletes credentials.
    /// Removing the last share of a server removes that server in the same save.
    @discardableResult
    func removeShare(_ share: SMBShareConfig) -> String? {
        guard configurationChangesAllowed, let authorization, let base = snapshot else {
            return String(localized: "The change could not be saved. Check folder access and try again.")
        }
        let outcome = ManagedMembershipController(repository: FileConfigRepository(authorizedDirectory: authorization.url))
            .remove(smbURL: share.smbURL, baseRevision: base.revision)
        if let saved = outcome.snapshot {
            snapshot = saved
            adoptBackendRevision(from: base.revision, to: saved.revision)
            issue = nil
            notice = String(localized: "The shared folder was removed from Automnt. Its mounted folder and saved sign-in details were left untouched.")
            refreshActionReadiness()
            refreshStatus()
            return nil
        }
        if let issue = outcome.issue {
            let message = message(for: issue)
            self.issue = message
            return message
        }
        return String(localized: "This shared folder is no longer managed.")
    }

    /// Drag, keyboard move and the CLI all persist through the same controller, so no
    /// draft order exists and a conflict never overwrites another entry point.
    @discardableResult
    func moveServer(identity: String, to destination: Int) -> String? {
        guard configurationChangesAllowed, let authorization, let base = snapshot else {
            return String(localized: "The change could not be saved. Check folder access and try again.")
        }
        let outcome = ManagedServerOrderController(repository: FileConfigRepository(authorizedDirectory: authorization.url))
            .move(identity: identity, to: destination, baseRevision: base.revision)
        return applyOrder(outcome)
    }

    @discardableResult
    func undoServerOrder() -> String? {
        guard configurationChangesAllowed, let authorization, let undo = orderUndo else { return nil }
        let outcome = ManagedServerOrderController(repository: FileConfigRepository(authorizedDirectory: authorization.url)).undo(undo)
        return applyOrder(outcome)
    }

    private func applyOrder(_ outcome: ServerOrderOutcome) -> String? {
        if let saved = outcome.snapshot {
            let previous = snapshot?.revision
            snapshot = saved
            adoptBackendRevision(from: previous, to: saved.revision)
            orderUndo = outcome.undo
            issue = nil
            notice = String(localized: "The order was saved. It changes which server the next round checks first.")
            refreshActionReadiness()
            return nil
        }
        if let issue = outcome.issue {
            orderUndo = nil
            let message = message(for: issue)
            self.issue = message
            reload()
            return message
        }
        // The move was a no-op (the destination equals the current position).
        return nil
    }

    private func shareCandidate(from value: String) -> ManagedMembership.Candidate? {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "smb",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let name = extractShareName(from: value), !name.isEmpty,
              let mountPoint = deriveStandardMountPoint(from: value) else { return nil }
        return ManagedMembership.Candidate(host: host, port: components.port ?? 445,
            name: name, smbURL: value, mountPoint: mountPoint)
    }

    // MARK: - Notifications and login

    func refreshLoginStatus() { loginStatus = SMAppService.mainApp.status }

    func setMenuLogin(_ enabled: Bool) async {
        guard !changingLogin else { return }
        changingLogin = true
        defer { changingLogin = false; refreshLoginStatus() }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try await SMAppService.mainApp.unregister() }
            loginIssue = nil
        } catch {
            loginIssue = String(localized: "The login setting could not be changed. Check Login Items in System Settings and try again.")
        }
    }

    func refreshNotificationPermission() async {
        notificationPermission = await NotificationAuthorization.current()
    }

    func requestNotifications() async {
        guard !requestingNotifications else { return }
        requestingNotifications = true
        defer { requestingNotifications = false }
        do {
            notificationPermission = try await NotificationAuthorization.request()
            notificationIssue = nil
        } catch {
            notificationIssue = String(localized: "Notification access could not be requested. Try again or check Notifications in System Settings.")
        }
    }

    // MARK: - Diagnostics

    func diagnosticPreview() throws -> DiagnosticExportPreview {
        let observations = (snapshot?.configuration.hosts ?? []).flatMap(\.shares).compactMap { share -> VolumeObservation? in
            guard let identity = smbResourceIdentity(share.smbURL) else { return nil }
            let path = NetFSWorkerOperation.mountPathState(at: share.mountPoint)
            let status: VolumeStatus
            let failure: AutomntIssue?
            do {
                try FinderAccess.verify(share: share, path: path)
                status = .healthy
                failure = nil
            } catch {
                failure = error as? AutomntIssue ?? .signalUnavailable
                // Absence proves only that the share is not mounted, not that its server is offline.
                status = .failed
            }
            return VolumeObservation(identity: identity, status: status,
                actualPath: status == .healthy ? share.mountPoint : nil, observedAt: Date(), issue: failure)
        }
        return try DiagnosticSnapshotBuilder.preview(DiagnosticBuildInputs(
            configuration: snapshot?.configuration, observations: observations, channel: .app,
            authorization: DiagnosticAuthorizationSummary(directoryAuthorized: hasAuthorization,
                bookmarkPresent: permissions.hasSavedBookmark,
                scopedAccessGranted: authorization?.scoped == true),
            notificationSoundEnabled: hasAuthorization ? soundEnabled : nil))
    }

    // MARK: - Operation ledger

    /// Claims the ledger entry for this object. `nil` means an operation for the same
    /// scope and target is already in flight, so a second click must not stack work.
    private func begin(_ scope: OperationScope, target: String?) -> OperationPresentation? {
        let (operation, duplicate) = ledger.begin(scope, targetIdentity: target)
        return duplicate ? nil : operation
    }

    /// Ends exactly the entry `begin` handed out; the ledger clears it by identity.
    private func end(_ operation: OperationPresentation) {
        ledger.finish(operation)
    }

    func isWorking(_ scope: OperationScope, target: String? = nil) -> Bool {
        ledger.isActive(scope, targetIdentity: target)
    }

    // MARK: - Messages

    func message(for issue: AutomntIssue) -> String {
        switch issue {
        case .configurationConflict: String(localized: "The configuration changed in another window or from the command line. Reload the latest settings; your input is kept.")
        case .authorizationRequired: String(localized: "Choose the Automnt folder in your Library/Application Support folder and grant access.")
        case .incompatibleOwner: String(localized: "App background mounting is not active. Set up the app’s background service before using this action.")
        case .volumeBusy: String(localized: "The shared folder is in use. Close files and apps using it, then try ejecting again.")
        case .timeout, .signalUnavailable: String(localized: "The operation could not be confirmed. Check background service status before trying again.")
        case .pathConflict: String(localized: "Another volume occupies this shared folder’s location. Eject that volume in Finder before continuing.")
        case .credentialFailure: String(localized: "The server did not accept the saved sign-in details. Reconnect this shared folder in Finder, then try again.")
        case .offline: String(localized: "The server was not reachable. Check the network, then try again.")
        case .shareRejected: String(localized: "The server refused this shared folder. Check the name and that your account may use it.")
        case .invalidConfiguration: String(localized: "Check the server address and mount folder. Each shared folder needs a distinct address and folder on this server.")
        case .backgroundApprovalRequired: String(localized: "Allow Automnt in Login Items in System Settings, then check again.")
        case .serviceTransitionFailed: String(localized: "Background mounting could not be changed. Check the configuration and background service before continuing.")
        case .unconfigured: String(localized: "Add a shared folder before using this action.")
        }
    }

    func show(_ error: Error) {
        if error is LegacyConfigurationConflict {
            issue = String(localized: "Automnt could not confirm that no CLI configuration exists. Your input is preserved. Resolve the CLI configuration before saving in the app.")
            return
        }
        issue = message(for: (error as? AutomntIssue) ?? .signalUnavailable)
    }
}

@main
struct AutomntApp: App {
    @NSApplicationDelegateAdaptor(DraftTerminationDelegate.self) private var terminationDelegate
    /// The app main executable is the only Automnt process allowed to own notification
    /// delivery. A helper in `Contents/Helpers` has no resolvable bundle identity and would
    /// abort with exit 134; it delegates here as a bounded child instead.
    init() {
        launchedAtLogin = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
        if CommandLine.arguments.dropFirst().first == "--probe-shared-container" {
            exit(SharedContainer.probe(arguments: CommandLine.arguments))
        }
        if CommandLine.arguments == [CommandLine.arguments[0], "--probe-keychain-storage"] {
            exit(KeychainCredentialProvider.probe())
        }
        if CommandLine.arguments == [CommandLine.arguments[0], "--check-background-job-presence"] {
            let clock = ContinuousClock()
            let started = clock.now
            print("legacy-job-presence=\(LegacyServicePresence.inspect())")
            let baselinePresence = LegacyServicePresence.inspectBaseline()
            let recoveryPresence = LegacyServicePresence.inspectRecovery()
            print("baseline-job-presence=\(baselinePresence)")
            print("recovery-job-presence=\(recoveryPresence)")
            print("probe-duration=\(started.duration(to: clock.now))")
            exit(EXIT_SUCCESS)
        }
        if CommandLine.arguments == [CommandLine.arguments[0], "--check-legacy-configuration"] {
            let presence = LegacyConfigurationPresence.inspect(
                at: PermissionStore.expectedDirectory.appendingPathComponent("automnt.plist"))
            print("legacy-configuration-presence=\(presence)")
            exit(EXIT_SUCCESS)
        }
        if CommandLine.arguments == [CommandLine.arguments[0], "--check-shared-container"] {
            exit(SharedContainer.check())
        }
        if CommandLine.arguments == [CommandLine.arguments[0], "--probe-background-registration"] {
            Task { @MainActor in
                do {
                    let directory = try PermissionStore().resolve()
                    try await HelperAuthorizationCheck.ensure(applicationURL: Bundle.main.bundleURL, directory: directory)
                    FileHandle.standardOutput.write(Data("authorization-probe: independent-helper-persisted-access-verified; mounts-unverified\n".utf8))
                    exit(EXIT_SUCCESS)
                } catch {
                    let failure = error as NSError
                    FileHandle.standardError.write(Data("authorization-probe: failed; domain=\(failure.domain); code=\(failure.code)\n".utf8))
                    exit(EXIT_FAILURE)
                }
            }
            RunLoop.main.run()
            exit(EXIT_FAILURE)
        }
        if CommandLine.arguments == [CommandLine.arguments[0], "--check-background-service-status"] {
            Task { @MainActor in
                for mode in [ServiceController.Mode.baseline, .recovery] {
                    let controller = ServiceController(mode: mode)
                    FileHandle.standardOutput.write(Data("background-service: mode=\(mode.rawValue); system-status=\(controller.systemStatusDescription); runtime-unverified\n".utf8))
                }
                exit(EXIT_SUCCESS)
            }
            RunLoop.main.run()
            exit(EXIT_FAILURE)
        }
        let checkHelper = CommandLine.arguments == [CommandLine.arguments[0], "--check-helper-authorization"]
        if checkHelper {
            let applicationURL = Bundle.main.bundleURL
            Task.detached {
                let stage = "helper-preflight"
                do {
                    try await HelperAuthorizationCheck.verify(applicationURL: applicationURL)
                    FileHandle.standardOutput.write(Data("helper-preflight: signature-and-group-verified; runtime-unverified\n".utf8))
                    exit(EXIT_SUCCESS)
                } catch {
                    let reason = (error as? AutomntIssue)?.rawValue ?? "check-failed"
                    let failure = error as NSError
                    let diagnostic = "helper-authorization: \(reason); stage=\(stage); domain=\(failure.domain); code=\(failure.code)\n"
                    FileHandle.standardError.write(Data(diagnostic.utf8))
                    exit(EXIT_FAILURE)
                }
            }
            // Keep the main run loop alive for the no-window diagnostic task.
            RunLoop.main.run()
            exit(EXIT_FAILURE)
        }
        // Routing policy lives in AutomntPlatform and is covered by tests; this code only acts
        // on the decision. A command line containing `--deliver-notification` always exits
        // here, including a malformed one, and never reaches the resident window path
        // (DEF-2/DEF-5). Do not inline this policy again: it is not covered by the tests here.
        switch NotificationDeliveryEntry.disposition(for: CommandLine.arguments) {
        case .startGUI:
            return
        case .exitWithOutcome(let outcome, let count):
            // No window, no permission prompt and no configuration write on this path.
            writeDiagnostic(outcome, count: count)
            exit(outcome.exitCode)
        }
    }

    private func writeDiagnostic(_ outcome: NotificationDispatchOutcome, count: Int) {
        guard let data = NotificationDeliveryEntry.diagnosticLine(outcome, count: count).data(using: .utf8) else {
            return
        }
        FileHandle.standardError.write(data)
    }

    // Read the system launch event; a normal Finder launch still presents the window.
    private let launchedAtLogin: Bool
    @State private var model = ApplicationModel()
    @State private var helpDestination: HelpDestination?
    @State private var showingDiagnostics = false
    @State private var settingsHelpDestination: HelpDestination?
    @State private var settingsDiagnostics = false
    @AppStorage("menuBarEnabled") private var menuBarEnabled = false
    @State private var addShareRequest = AddShareRequest()
    @Environment(\.openWindow) private var openWindow

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        Window("Automnt", id: "main") {
            MainWindowView(model: model, addShareRequest: addShareRequest)
                .task {
                    model.installTerminationHandler()
                    model.installWindowCloseShortcut()
                    model.restore()
                }
                .sheet(item: $helpDestination) { destination in OfflineHelpView(destination: destination) }
                .sheet(isPresented: $showingDiagnostics) { DiagnosticsView(model: model) }
        }
        .defaultSize(width: 1103, height: 692)
        .defaultLaunchBehavior(launchedAtLogin && menuBarEnabled ? .suppressed : .presented)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Automnt") { DraftTerminationDelegate.requestTermination() }
                    .keyboardShortcut("q", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Add Shared Folder…") {
                    openMainWindow()
                    addShareRequest.present()
                }
                    .disabled(!model.configurationChangesAllowed)
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Servers") {
                // 不使用右键“上移/下移”，但保留可发现的菜单与 Option+方向键等价操作。
                Button("Move Earlier") { model.moveSelectedServer(earlier: true) }
                    .keyboardShortcut(.upArrow, modifiers: [.option])
                    .disabled(!model.canMoveSelectedServer(earlier: true))
                Button("Move Later") { model.moveSelectedServer(earlier: false) }
                    .keyboardShortcut(.downArrow, modifiers: [.option])
                    .disabled(!model.canMoveSelectedServer(earlier: false))
            }
            CommandGroup(after: .help) {
                Button("User Guide") { openMainWindow(); helpDestination = .guide }
                Button("Support and Privacy") { openMainWindow(); helpDestination = .privacy }
                Button("Open Source Licenses") { openMainWindow(); helpDestination = .licenses }
                Button("Diagnostics") { openMainWindow(); showingDiagnostics = true }
            }
        }
        MenuBarExtra(isInserted: $menuBarEnabled) {
            AutomntMenuView(model: model, menuBarEnabled: $menuBarEnabled, addShareRequest: addShareRequest)
        } label: {
            Label("Automnt", image: "MenuBarIcon")
                .labelStyle(.iconOnly)
        }
        Settings {
            SettingsView(model: model, menuBarEnabled: $menuBarEnabled, helpDestination: $settingsHelpDestination,
                showingDiagnostics: $settingsDiagnostics)
                .sheet(item: $settingsHelpDestination) { destination in OfflineHelpView(destination: destination) }
                .sheet(isPresented: $settingsDiagnostics) { DiagnosticsView(model: model) }
                .task { await model.refreshNotificationPermission() }
        }
        .defaultSize(width: 680, height: 620)
        .windowResizability(.contentMinSize)
    }
}

/// Lets the File menu open the same manual add sheet as the toolbar without a second form.
@MainActor @Observable
final class AddShareRequest {
    var isPresented = false
    func present() { isPresented = true }
}

private struct DiagnosticDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct DiagnosticsView: View {
    let model: ApplicationModel
    @Environment(\.dismiss) private var dismiss
    @State private var preview: DiagnosticExportPreview?
    @State private var exporting = false
    @State private var confirmingClear = false
    @State private var feedback: String?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review the redacted diagnostics before exporting. Nothing is uploaded automatically.")
                    .foregroundStyle(.secondary)
                if let preview {
                    ScrollView {
                        Text(verbatim: preview.text).font(.system(.body, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button("Export diagnostics…") { exporting = true }
                }
                if let feedback { Text(feedback).foregroundStyle(.secondary) }
                Button("Refresh diagnostics") { refresh() }
                Button("Clear Logs…") { confirmingClear = true }
            }
            .confirmationDialog("Clear Local Logs?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { model.clearLogs() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes Automnt's local log files. Saved diagnostic exports are not affected.")
            }
            .padding()
            .navigationTitle("Diagnostics")
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            } }
        }
        .frame(minWidth: 420, idealWidth: 650, minHeight: 350, idealHeight: 550)
        .task { refresh() }
        .fileExporter(isPresented: $exporting, document: preview.map { DiagnosticDocument(text: $0.text) },
            contentType: .json, defaultFilename: "Automnt-diagnostics") { result in
                switch result {
                case .success: feedback = String(localized: "Diagnostics exported.")
                case .failure: feedback = String(localized: "Diagnostics could not be exported. Choose another folder and try again.")
                }
            }
    }
    private func refresh() {
        do { preview = try model.diagnosticPreview(); feedback = nil }
        catch {
            preview = nil
            feedback = String(localized: "Diagnostics could not be prepared safely. Check folder access and try again.")
        }
    }
}

enum HelpDestination: String, Identifiable {
    case guide, privacy, licenses
    var id: String { rawValue }
    var title: String {
        switch self {
        case .guide: String(localized: "User Guide")
        case .privacy: String(localized: "Support and Privacy")
        case .licenses: String(localized: "Open Source Licenses")
        }
    }
}

struct OfflineHelpView: View {
    let destination: HelpDestination
    @Environment(\.dismiss) private var dismiss
    @State private var chinese = Locale.current.language.languageCode?.identifier == "zh"
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch destination {
                    case .guide:
                        Text("Automnt mounts your shared folders in the background when the server is reachable and the saved sign-in details are valid.")
                        Text("Enter an SMB address without a user name or password. The mount location is derived from the shared folder name and can be changed.")
                        Text("Sign-in is handled by macOS. If a server asks for sign-in again, connect to it in Finder and return to Automnt.")
                        Text("Enabled background mounting continues after you quit Automnt. Turn off automatic mounting in Settings to stop future automatic mounts; mounted shared folders remain available.")
                        Text("While automatic mounting is off, you can still mount a shared folder from its row. Ejecting there needs app background control; otherwise eject it in Finder.")
                    case .privacy:
                        Picker("Body language", selection: $chinese) {
                            Text(verbatim: "中文").tag(true)
                            Text(verbatim: "English").tag(false)
                        }.pickerStyle(.segmented)
                        Text(verbatim: chinese ? Self.privacyChinese : Self.privacyEnglish)
                    case .licenses:
                        if let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"),
                           let license = try? String(contentsOf: url, encoding: .utf8) {
                            Text(verbatim: license)
                        } else {
                            Text("The license could not be loaded. Reinstall Automnt to restore its bundled resources.")
                        }
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(destination.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(minWidth: 420, idealWidth: 600, minHeight: 350, idealHeight: 550)
    }

    private static let privacyChinese = """
    Automnt 在后台自动挂载已配置的 SMB 共享文件夹。需要服务器可达、配置有效，并且系统已有可用的登录信息。退出界面后，已启用的自动挂载仍会继续运行。

    Automnt 在本机管理配置。首次使用时，程序准备并使用固定的配置目录；已有 CLI 配置会自动显示。系统可能要求你允许后台项目或访问；拒绝时会如实说明状态，不会创建第二份配置。登录信息由 macOS 与系统钥匙串处理，Automnt 不单独收集或保存密码，也不写入配置或诊断。诊断信息由你预览并选择是否导出，不会自动上传。连接共享时，所连接的服务器会处理连接请求。

    遇到连接问题，请先在共享详情中查看原因与修复建议。发送诊断前请确认内容中没有你不愿共享的信息。不要发送密码。
    """
    private static let privacyEnglish = """
    Automnt automatically mounts configured SMB shares in the background when the server is reachable, the configuration is valid, and macOS has usable sign-in details. Enabled automatic mounting continues after you quit the app.

    Automnt manages your configuration on this Mac. On first use, the app prepares and uses the fixed configuration directory; existing CLI targets appear automatically. macOS may ask you to allow the background item or access; a refusal is reported honestly and never creates a second configuration. Sign-in is handled by macOS and the system Keychain; Automnt keeps no separate password and writes none into the configuration or diagnostics. Diagnostics are not uploaded automatically. When connecting to a share, the server you connect to processes the connection request.

    For connection problems, open the share details to review the cause and suggested steps. Check diagnostics for information you do not want to share before sending them. Do not send passwords.
    """
}
