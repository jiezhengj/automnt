// 设计 demo：全部虚构数据仅存内存。无网络、配置、Keychain、挂载或服务调用。
// 唯一系统交互是只读订阅卷宗挂载/卸载通知，用于演示“重新激活时刷新”；不执行挂载。
// 使用 macOS 27 SDK 的真实 SwiftUI 控件；仅加载本目录现有图标资产。
import SwiftUI
import AppKit

struct DemoShare: Identifiable, Equatable {
    var id = UUID()
    var url: String
    var location: String
    var managed: Bool
    var automatic = true
    var status = "已挂载"
    var host: String { URLComponents(string: url)?.host?.lowercased() ?? "服务器" }
    var name: String { URLComponents(string: url)?.path.split(separator: "/").first.map(String.init) ?? "共享" }
    var actualLocation: String? = nil
    var mounted: Bool { ["已挂载", "路径不符", "需要核对"].contains(status) }
    var problem: Bool { ["服务器离线", "认证失败", "路径不符"].contains(status) }
}

enum ReviewScene: String, CaseIterable, Identifiable {
    case discovered = "已管理与可添加", empty = "空态", healthy = "全部健康"
    case offline = "服务器离线", authentication = "认证失败", manyServers = "多服务器 · 长名单"
    case ejected = "主动弹出", notSelected = "本轮未选中", pathMismatch = "路径不符", approval = "后台待批准"
    var id: String { rawValue }
}
struct ServerConnection: Equatable {
    var address: String
    var port = 445
    var timeoutMs = 1000
}
struct OrderUndo {
    let order: [String]
    let savedRevision: Int
}

enum SaveResult: String, CaseIterable, Identifiable {
    case success = "成功", failure = "保存失败", conflict = "保存冲突"
    var id: String { rawValue }
}

@Observable final class DemoModel {
    static func examples() -> [DemoShare] {
        // .example 为保留示例域名；这些数据永远不用于实际连接。
        [DemoShare(url: "smb://studio.example/Documents", location: "/Volumes/Documents", managed: true),
         DemoShare(url: "smb://studio.example/Archive", location: "/Volumes/Archive", managed: false),
         DemoShare(url: "smb://library.example/Media", location: "/Volumes/Media", managed: false)]
    }
    static func manyServerExamples() -> [DemoShare] {
        (1...5).flatMap { server in
            (1...6).map { volume in
                DemoShare(url: "smb://server\(server).example/Share\(volume)",
                          location: "/Volumes/Example-\(server)-Share\(volume)",
                          managed: volume <= 4,
                          status: volume == 3 ? "服务器离线" : volume == 4 ? "认证失败" : "已挂载")
            }
        }
    }
    var shares = examples()
    var hosts: [String: Bool] = [:]
    var automatic = true
    var recovery = true
    var menu = false
    var login = false
    var notificationAuthorization = "尚未请求"
    var sound = true
    var serverIndex: [String: Bool] = [:]
    var addErrors: [UUID: String] = [:]
    var scene: ReviewScene = .discovered
    var saveResult: SaveResult = .success
    var reviewLog = "打开时已完成模拟发现；未连接服务器。"
    var refreshCount = 0
    var information: String?
    var priority = ["studio.example"]
    var serverNames: [String: String] = [:]
    var background = "正在运行"
    var roundSummary = "尚未进行本轮评估"
    var roundResults: [String] = []
    var reachability: [String: Bool] = [:]
    var retry = 3
    var feedback: String?
    var unselectToken = 0
    var revision = 1
    var orderUndo: OrderUndo?
    var orderFeedback: String?
    var searchText = ""
    var serverConnections: [String: ServerConnection] = [:]
    func connection(_ host: String) -> ServerConnection { serverConnections[host] ?? ServerConnection(address: host) }
    func matchesSearch(_ host: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || displayName(host).localizedCaseInsensitiveContains(query) || host.localizedCaseInsensitiveContains(query) || shares.contains { $0.host == host && $0.name.localizedCaseInsensitiveContains(query) }
    }
    var isFiltering: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    func simulateConcurrentSave() {
        // 模拟另一入口已成功提交；不伪造本次操作成功。
        priority = Array(managedServers.reversed())
        revision += 1
        reviewLog = "其他入口模拟保存了最新顺序，revision \(revision)。撤销不能覆盖它。"
    }
    var servers: [String] { managedServers + unmanagedServers }
    var managedServers: [String] {
        let managed = Set(shares.filter(\.managed).map(\.host))
        return priority.filter { managed.contains($0) } + managed.subtracting(priority).sorted()
    }
    var unmanagedServers: [String] { Set(shares.map(\.host)).subtracting(managedServers).sorted() }
    func displayName(_ host: String) -> String { serverNames[host, default: host] }
    func save(_ operation: () -> Void) {
        if saveResult != .success { feedback = saveResult == .failure ? "未能保存，已恢复原值。请重试。" : "设置已在其他地方更改，已恢复原值。请检查后重试。"; return }
        operation()
        revision += 1
    }
    func setting(_ key: ReferenceWritableKeyPath<DemoModel, Bool>) -> Binding<Bool> {
        Binding(get: { self[keyPath: key] }, set: { value in self.save { self[keyPath: key] = value } })
    }
    func moveServers(_ source: IndexSet, to destination: Int) {
        guard !isFiltering else { orderFeedback = "清除搜索后才能调整完整顺序。"; return }
        let before = managedServers
        var order = before
        order.move(fromOffsets: source, toOffset: destination)
        guard order != before else { return }
        if saveResult == .failure { orderFeedback = "顺序未能保存；仍显示已保存顺序。"; return }
        if saveResult == .conflict {
            simulateConcurrentSave()
            orderFeedback = "其他入口已修改顺序；已显示最新顺序，本次移动未保存。"
            return
        }
        priority = order; revision += 1
        orderUndo = OrderUndo(order: before, savedRevision: revision)
        orderFeedback = "顺序已保存；只影响下一轮评估。"
    }
    func undoServerOrder() {
        guard let undo = orderUndo else { return }
        if saveResult == .conflict { simulateConcurrentSave() }
        guard revision == undo.savedRevision else {
            orderFeedback = "设置已有后续修改，不能撤销旧顺序；已保留最新配置。"
            orderUndo = nil; return
        }
        guard saveResult != .failure else { orderFeedback = "撤销未能保存；当前顺序保留，可重试。"; return }
        priority = undo.order; revision += 1; orderUndo = nil
        orderFeedback = "已撤销本次顺序调整。"
    }
    func pathOccupant(_ target: DemoShare) -> DemoShare? {
        shares.first { $0.id != target.id && $0.mounted && Self.pathIdentity($0.actualLocation ?? $0.location) == Self.pathIdentity(target.location) }
    }
    func evaluate() {
        roundResults = []
        var selected: String?
        for host in managedServers {
            if !hosts[host, default: true] {
                roundResults.append("\(displayName(host))：自动挂载已关闭，未检查")
                continue
            }
            if selected != nil {
                roundResults.append("\(displayName(host))：未检查，本轮未选中")
                for share in shares where share.host == host && share.managed {
                    roundResults.append("  \(share.name)：\(share.mounted ? "现有挂载保留" : share.status == "已弹出" ? "本次会话暂停" : "未挂载，等待后续评估")")
                }
                for i in shares.indices where shares[i].host == host && shares[i].managed && !shares[i].mounted && shares[i].status != "已弹出" {
                    shares[i].status = "本轮未选中"
                }
                continue
            }
            let reachable = reachability[host, default: scene != .offline]
            roundResults.append("\(displayName(host))：\(reachable ? "可达，已选中" : "不可达")")
            if reachable { selected = host }
            for i in shares.indices where shares[i].host == host && shares[i].managed {
                let share = shares[i]
                let enabled = automatic && hosts[host, default: true] && share.automatic && background == "正在运行"
                if !reachable {
                    if !share.mounted { shares[i].status = "服务器离线" }
                    roundResults.append("  \(share.name)：\(share.mounted ? "现有挂载保留，服务器不可达" : "未挂载，服务器不可达")")
                } else if share.mounted {
                    if Self.pathIdentity(share.actualLocation ?? share.location) != Self.pathIdentity(share.location) && share.status != "需要核对" { shares[i].status = "路径不符" }
                    roundResults.append("  \(share.name)：\(shares[i].status)，实际位置 \(share.actualLocation ?? share.location)")
                } else if share.status == "已弹出" {
                    roundResults.append("  \(share.name)：本次会话暂停自动挂载")
                } else if !enabled {
                    shares[i].status = "等待连接"
                    roundResults.append("  \(share.name)：自动挂载未安排")
                } else if scene == .authentication {
                    shares[i].status = "认证失败"
                    roundResults.append("  \(share.name)：认证失败，请在 Finder 连接")
                } else if let occupant = pathOccupant(share) {
                    roundResults.append("  \(share.name)：位置被 \(displayName(occupant.host))/\(occupant.name) 占用；保留现有挂载")
                } else {
                    shares[i].status = "已挂载"
                    shares[i].actualLocation = share.location
                    roundResults.append("  \(share.name)：已挂载到 \(share.location)")
                }
            }
        }
        roundSummary = selected.map { "本轮选择：\(displayName($0))" } ?? "本轮无可达服务器"
        reviewLog = "完成整轮内存评估；没有执行网络探测或挂载。"
    }
    func arrangement(_ share: DemoShare) -> String {
        if !share.managed { return "尚未管理" }
        if share.status == "已弹出" { return "本次会话暂停；网络变化或重新登录后恢复" }
        if !automatic || !hosts[share.host, default: true] || !share.automatic { return "自动挂载已关闭" }
        if background != "正在运行" { return "等待后台批准" }
        if share.status == "本轮未选中" { return "等待后续评估选择此服务器" }
        return recovery ? "后台自动挂载与恢复已安排" : "登录或网络变化时自动挂载；意外断开不自动恢复"
    }
    func primary(_ id: UUID) {
        guard let i = shares.firstIndex(where: { $0.id == id }) else { return }
        let target = shares[i]
        if target.mounted {
            if target.status == "需要核对" { feedback = "地址已修改，现有挂载身份尚未核对；不能将它当作新目标打开或挂载。请查看详情。"; return }
            reviewLog = "仅模拟打开实际位置 \(target.actualLocation ?? target.location)；路径不符状态保持，不执行 Finder。"
            return
        }
        guard target.managed else { return }
        if let occupant = pathOccupant(target) {
            feedback = "约定位置被 \(displayName(occupant.host))/\(occupant.name) 的现有挂载占用。请先查看该目标；不会挤占或弹出它。"
            return
        }
        guard reachability[target.host, default: scene != .offline] else { shares[i].status = "服务器离线"; return }
        guard scene != .authentication else { shares[i].status = "认证失败"; return }
        shares[i].status = "已挂载"; shares[i].actualLocation = target.location
        reviewLog = "仅模拟挂载 \(target.url)，解除该目标会话暂停；其他共享和自动策略保持原状。"
    }
    func eject(_ id: UUID) {
        guard let i = shares.firstIndex(where: { $0.id == id }), shares[i].mounted else { return }
        guard shares[i].status != "需要核对" else { feedback = "现有挂载身份尚未核对；不会弹出不确定的目标。"; return }
        shares[i].status = "已弹出"; shares[i].actualLocation = nil
        reviewLog = "模拟健康弹出；不执行系统卸载。"
    }
    func collision(_ candidate: DemoShare) -> Bool {
        shares.contains { $0.managed && $0.id != candidate.id && (Self.identity($0.url) == Self.identity(candidate.url) || ($0.host == candidate.host && Self.pathIdentity($0.location) == Self.pathIdentity(candidate.location))) }
    }
    func refresh(_ reason: String) {
        refreshCount += 1
        if scene != .empty {
            let samples = scene == .manyServers ? Self.manyServerExamples() : Self.examples()
            for sample in samples where !shares.contains(where: { Self.identity($0.url) == Self.identity(sample.url) }) {
                shares.append(sample)
            }
        }
        reviewLog = "\(reason)：第 \(refreshCount) 次模拟发现。已管理项保留，未连接服务器。"
    }
    func setScene(_ value: ReviewScene) {
        scene = value
        revision += 1; orderUndo = nil; orderFeedback = nil
        shares = value == .empty ? [] : value == .manyServers ? Self.manyServerExamples() : Self.examples()
        addErrors = [:]; reachability = [:]
        priority = Array(Set(shares.filter(\.managed).map(\.host))).sorted()
        background = value == .approval ? "等待系统批准" : "正在运行"
        roundSummary = "尚未进行本轮评估"; roundResults = []
        if value == .notSelected { unselectToken += 1 }
        for i in shares.indices {
            if value == .healthy { shares[i].managed = true }
            if shares[i].managed && value != .manyServers {
                shares[i].status = value == .offline ? "服务器离线" : value == .authentication ? "认证失败" : "已挂载"
            }
        }
        if value == .ejected, !shares.isEmpty { shares[0].status = "已弹出" }
        if value == .pathMismatch, !shares.isEmpty { shares[0].status = "路径不符"; shares[0].actualLocation = "/Volumes/Documents-1" }
        if value == .notSelected {
            shares.append(DemoShare(url: "smb://backup.example/Documents", location: "/Volumes/Documents", managed: true, status: "本轮未选中"))
            priority = ["studio.example", "backup.example"]
            roundSummary = "本轮选择：studio.example"; roundResults = ["studio.example：可达，已选中", "backup.example：未检查，本轮未选中"]
        }
        reviewLog = "已切换到\(value.rawValue)（内存模拟）。"
    }
    var saveError: String? {
        switch saveResult {
        case .success: nil
        case .failure: "未能保存。输入已保留，请重试。"
        case .conflict: "设置已在其他地方更改。输入已保留，请检查后重试。"
        }
    }
    @discardableResult func add(_ id: UUID) -> String? {
        guard let i = shares.firstIndex(where: { $0.id == id }) else { return "此共享已移除，请检查最新列表。" }
        let candidate = shares[i]
        let error: String?
        if candidate.managed || collision(candidate) {
            error = "地址或位置与已管理共享冲突，请检查最新列表。"
        } else { error = saveError }
        if let error { addErrors[id] = error; return error }
        if !managedServers.contains(candidate.host) { priority.removeAll { $0 == candidate.host }; priority.append(candidate.host) }
        shares[i].managed = true
        revision += 1
        addErrors[id] = nil
        reviewLog = "\(shares[i].name) 已添加（内存模拟）。"
        return nil
    }
    func update(_ share: DemoShare) {
        guard let i = shares.firstIndex(where: { $0.id == share.id }) else { return }
        var saved = share
        if shares[i].mounted && (shares[i].url != share.url || shares[i].location != share.location) {
            saved.actualLocation = shares[i].actualLocation ?? shares[i].location
            saved.status = shares[i].url != share.url ? "需要核对" : "路径不符"
        }
        shares[i] = saved
        revision += 1
    }
    static func validURL(_ value: String) -> Bool {
        guard let u = URLComponents(string: value), u.scheme?.lowercased() == "smb",
              let host = u.host, !host.isEmpty, u.user == nil, u.password == nil,
              u.query == nil, u.fragment == nil else { return false }
        let parts = u.path.split(separator: "/")
        return parts.count == 1 && u.path.hasPrefix("/") && !parts[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parts[0] != "." && parts[0] != ".."
    }
    static func identity(_ value: String) -> String? {
        guard validURL(value), let u = URLComponents(string: value) else { return nil }
        return "\(u.host!.lowercased()):\(u.port ?? 445)/\(u.path.split(separator: "/").first!)"
    }
    static func pathIdentity(_ value: String) -> String {
        (value.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).standardizingPath
    }
    static func validPath(_ value: String) -> Bool {
        let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") && pathIdentity(path) != "/"
    }
}

@main struct NativeDesignPreview: App {
    @State private var model = DemoModel()
    init() {
        // 只读取现有本地图标，不生成或改写资产。
        let sourceDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        if let image = NSImage(contentsOf: sourceDirectory.appendingPathComponent("app-icon-1024.png")) {
            NSApplication.shared.applicationIconImage = image
        }
    }
    var body: some Scene {
        WindowGroup("Automnt · 设计预览", id: "main") { DemoRoot(model: model) }
            .defaultSize(width: 820, height: 660)
        Settings { DemoSettings(model: model) }
        Window("关于 Automnt", id: "about") { SupportPage(model: model, kind: "关于 Automnt") }
        Window("Automnt 帮助", id: "help") { SupportPage(model: model, kind: "帮助与支持") }
        Window("设计审阅工具", id: "review") { ReviewTools(model: model) }
            .defaultSize(width: 520, height: 540)
        MenuBarExtra("Automnt", systemImage: "folder.badge.gearshape", isInserted: $model.menu) {
            DemoMenu(model: model)
        }
        .commands {
            CommandGroup(replacing: .appInfo) { WindowButton(title: "关于 Automnt", destination: "about") }
            CommandGroup(replacing: .help) { WindowButton(title: "Automnt 帮助", destination: "help") }
            CommandMenu("设计审阅") {
                OpenReviewButton()
                Button("模拟重新激活刷新") { model.refresh("重新激活") }
                Button("模拟卷变化刷新") { model.refresh("卷变化") }
            }
        }
    }
}

struct OpenReviewButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button("设计审阅工具…") { openWindow(id: "review") } }
}

enum DemoRoute: Hashable {
    case server(String), share(UUID)
}

struct DemoRoot: View {
    @Bindable var model: DemoModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedServer: String?
    @State private var path: [DemoRoute] = []
    @State private var manual = false
    var body: some View {
        GeometryReader { geometry in
            // macOS 不会自动把窄窗口折叠成 iOS 导航；窄窗使用原生栈和返回按钮。
            if geometry.size.width < 680 {
                NavigationStack(path: $path) {
                    serverList(compact: true)
                        .navigationDestination(for: DemoRoute.self) { route in
                            switch route {
                            case .server(let server): ServerShares(model: model, server: server, compact: true)
                            case .share(let id): ShareDetails(model: model, id: id)
                            }
                        }
                }
            } else {
                NavigationSplitView {
                    serverList(compact: false)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
                } detail: {
                    NavigationStack {
                        if let server = selectedServer, model.servers.contains(server) {
                            ServerShares(model: model, server: server)
                                .navigationDestination(for: DemoRoute.self) { route in
                                    if case .share(let id) = route { ShareDetails(model: model, id: id) }
                                }
                        } else {
                            ContentUnavailableView("选择服务器", systemImage: "server.rack", description: Text("选择服务器以查看已管理与可添加的共享。"))
                        }
                    }.id(selectedServer)
                }
            }
        }
        .frame(minWidth: 340, minHeight: 360)
        .toolbar {
            ToolbarItem { Button("刷新", systemImage: "arrow.clockwise") { model.refresh("手动刷新") } }
            ToolbarItem { Button("手动添加…", systemImage: "plus") { manual = true } }
            ToolbarItem { SettingsLink { Label("设置", systemImage: "gearshape") } }
            ToolbarItem { Button("立即重试", systemImage: "arrow.triangle.2.circlepath") { model.evaluate() } }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("后台：\(model.background) · 自动挂载\(model.automatic ? "已开启" : "已关闭")")
                Text(model.roundSummary).foregroundStyle(.secondary)
                if model.background != "正在运行" { Button("查看后台设置") { model.reviewLog = "模拟打开系统后台项目设置；没有系统调用。" } }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }
        .alert("未能完成", isPresented: Binding(get: { model.feedback != nil }, set: { if !$0 { model.feedback = nil } })) {
            Button("好", role: .cancel) { model.feedback = nil }
        } message: { Text(model.feedback ?? "") }
        .onChange(of: model.unselectToken) { _, _ in selectedServer = nil; path = [] }
        .onAppear {
            model.refresh("窗口打开")
            if selectedServer == nil { selectedServer = model.servers.first }
        }
        .onChange(of: selectedServer) { _, server in
            if case .server(let previous) = path.first, previous != server { path = [] }
        }
        .onChange(of: path) { _, routes in
            if case .server(let server) = routes.first { selectedServer = server }
        }
        .onChange(of: model.servers) { _, servers in
            // 仅当已选服务器消失时清理导航；异常、刷新和添加均不抢选中项。
            if let selectedServer, !servers.contains(selectedServer) {
                self.selectedServer = servers.first
                path = []
            }
        }
        .onChange(of: scenePhase) { _, value in if value == .active { model.refresh("窗口重新激活") } }
        // 真实卷变化只作为刷新触发，不读取卷信息；发现结果始终是虚构样例。
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification, object: nil)) { _ in model.refresh("卷变化") }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification, object: nil)) { _ in model.refresh("卷变化") }
        .sheet(isPresented: $manual) { ManualShare(model: model) }
    }
    @ViewBuilder private func serverItem(_ server: String, compact: Bool) -> some View {
        Group {
            if compact { NavigationLink(value: DemoRoute.server(server)) { ServerSummary(model: model, server: server) } }
            else { ServerSummary(model: model, server: server).tag(server) }
        }.contextMenu {
            if let index = model.managedServers.firstIndex(of: server) {
                Button("上移") { model.moveServers(IndexSet(integer: index), to: index - 1) }.disabled(index == 0 || model.isFiltering)
                Button("下移") { model.moveServers(IndexSet(integer: index), to: index + 2) }.disabled(index == model.managedServers.count - 1 || model.isFiltering)
            }
        }
    }
    private func serverList(compact: Bool) -> some View {
        List(selection: $selectedServer) {
            Section("已管理 · 按优先级") {
                ForEach(model.managedServers.filter { model.matchesSearch($0) }, id: \.self) { server in serverItem(server, compact: compact) }
                    .onMove { source, destination in model.moveServers(source, to: destination) }
                    .moveDisabled(model.isFiltering)
                if model.isFiltering { Text("清除搜索后可调整顺序").foregroundStyle(.secondary) }
                if let result = model.orderFeedback { Text(result).foregroundStyle(.secondary) }
                if model.orderUndo != nil { Button("撤销顺序调整") { model.undoServerOrder() } }
            }
            Section("未管理") {
                ForEach(model.unmanagedServers.filter { model.matchesSearch($0) }, id: \.self) { server in serverItem(server, compact: compact) }
            }
        }
        .navigationTitle("服务器")
        .searchable(text: $model.searchText, prompt: "搜索服务器或共享名称")
        .overlay {
            if model.servers.isEmpty {
                ContentUnavailableView("先在 Finder 中连接服务器", systemImage: "externaldrive.badge.plus", description: Text("在 Finder 按 ⌘K，连接需要使用的 SMB 共享，然后返回 Automnt 刷新；也可手动输入完整 SMB 地址。"))
            }
        }
    }
}

struct ServerSummary: View {
    let model: DemoModel
    let server: String
    private var shares: [DemoShare] { model.shares.filter { $0.host == server } }
    private var exceptions: Int { shares.filter { $0.managed && $0.problem }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(model.displayName(server), systemImage: "server.rack").lineLimit(1).help(server)
            Text("已管理 \(shares.filter(\.managed).count) · 可添加 \(shares.filter { !$0.managed }.count)")
                .foregroundStyle(.secondary)
            if exceptions > 0 {
                Label("\(exceptions) 个共享需要处理", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}

struct ServerShares: View {
    @Bindable var model: DemoModel
    let server: String
    var compact = false
    @State private var settings = false
    @State private var information: String?
    private var shares: [DemoShare] { model.shares.filter { $0.host == server } }
    var body: some View {
        List {
            Section {
                Toggle("自动挂载此服务器的共享", isOn: Binding(
                    get: { model.hosts[server, default: true] },
                    set: { value in model.save { model.hosts[server] = value } }))
                Text("关闭后，不再自动挂载此服务器的共享；已经挂载的卷宗仍可使用。")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("已管理") {
                ForEach(shares.filter(\.managed)) { share in
                    ShareRow(model: model, share: share, error: nil, compact: compact) {
                        model.primary(share.id)
                    }
                }
                if !shares.contains(where: \.managed) { Text("尚未添加共享").foregroundStyle(.secondary) }
            }
            Section("可添加") {
                ForEach(shares.filter { !$0.managed }) { share in
                    ShareRow(model: model, share: share, error: model.addErrors[share.id], compact: compact) { model.add(share.id) }
                }
                if shares.allSatisfy(\.managed) { Text("没有可添加的共享").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(server)
        .toolbar { ToolbarItem { Button("服务器设置…", systemImage: "gearshape") { settings = true } } }
        .sheet(isPresented: $settings) { ServerSettings(model: model, server: server) }
        .alert("操作结果", isPresented: Binding(get: { information != nil }, set: { if !$0 { information = nil } })) {
            Button("好", role: .cancel) { information = nil }
        } message: { Text(information ?? "") }
    }
}

struct ShareRow: View {
    let model: DemoModel
    let share: DemoShare
    let error: String?
    var compact: Bool
    let primary: () -> Void
    @State private var details = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack { identity; Spacer(); action }
                VStack(alignment: .leading) { identity; action }
            }
            if let error {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("添加错误：\(error)")
            }
        }.padding(.vertical, 3)
        .sheet(isPresented: $details) {
            VStack {
                ShareDetails(model: model, id: share.id)
                HStack { Spacer(); Button("完成") { details = false }.keyboardShortcut(.cancelAction) }.padding()
            }.frame(minWidth: 340, idealWidth: 560, minHeight: 440)
        }
    }
    @ViewBuilder private var identity: some View {
        if compact {
            NavigationLink(value: DemoRoute.share(share.id)) { shareIdentity }
        } else {
            Button { details = true } label: { shareIdentity }.buttonStyle(.plain)
        }
    }
    private var shareIdentity: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(share.name).help(share.name)
            Text(share.managed ? share.status : "Finder 已连接").foregroundStyle(.secondary)
        }
    }
    private var action: some View {
        HStack {
            Button(share.managed ? (share.mounted ? "在 Finder 中打开" : "重试") : "添加", action: primary)
            if share.mounted { Button("弹出") { model.eject(share.id) } }
        }.buttonStyle(.borderless)
    }
}

struct ServerSettings: View {
    @Bindable var model: DemoModel
    let server: String
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    @State private var editingConnection = false
    var body: some View {
        VStack {
            Form {
                Section("服务器名称") {
                    TextField("名称", text: $name)
                    Button("确认名称") {
                        if let failure = model.saveError { error = failure }
                        else { model.save { model.serverNames[server] = name.isEmpty ? server : name }; error = nil }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                Section("连接参数") {
                    LabeledContent("地址", value: model.connection(server).address)
                    LabeledContent("端口", value: "\(model.connection(server).port)")
                    LabeledContent("探测超时", value: "\(model.connection(server).timeoutMs) 毫秒")
                    Button("编辑连接参数…") { editingConnection = true }
                }
                Section(server) {
                    Toggle("尝试阻止 Spotlight 索引", isOn: Binding(
                        get: { model.serverIndex[server, default: false] },
                        set: { value in model.save { model.serverIndex[server] = value } }))
                    Text("仅适用于此服务器的共享。尝试减少磁盘与网络活动，但 Spotlight 搜索可能受限；系统限制可能使尝试无法生效，不会自动删除现有索引。")
                        .foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction) }.padding()
        }.frame(minWidth: 340, idealWidth: 520, minHeight: 280)
        .onAppear { name = model.displayName(server) }
        .sheet(isPresented: $editingConnection) { ServerConnectionEditor(model: model, server: server) }
        .alert("未能保存", isPresented: Binding(get: { model.feedback != nil }, set: { if !$0 { model.feedback = nil } })) { Button("好") { model.feedback = nil } } message: { Text(model.feedback ?? "") }
    }
}

struct ServerConnectionEditor: View {
    @Bindable var model: DemoModel
    let server: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ServerConnection
    @State private var baseline: ServerConnection
    @State private var baseRevision: Int
    @State private var error: String?
    @State private var discard = false
    init(model: DemoModel, server: String) {
        self.model = model; self.server = server
        _draft = State(initialValue: model.connection(server))
        _baseline = State(initialValue: model.connection(server))
        _baseRevision = State(initialValue: model.revision)
    }
    var body: some View {
        VStack {
            Form {
                Section("编辑服务器连接参数") {
                    TextField("服务器地址", text: $draft.address)
                    TextField("端口", value: $draft.port, format: .number)
                    TextField("探测超时（毫秒）", value: $draft.timeoutMs, format: .number)
                    Text("整体保存此服务器的参数；其他服务器参数保持原值。已有挂载不会迁移或变成已修复。").foregroundStyle(.secondary)
                }
                Section("受影响的已管理共享") {
                    ForEach(model.shares.filter { $0.host == server && $0.managed }) { share in
                        LabeledContent(share.name, value: share.url)
                    }
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("重新载入已保存参数") {
                            draft = model.connection(server); baseline = draft; baseRevision = model.revision; self.error = nil
                        }
                    }
                }
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消") { if draft != baseline { discard = true } else { dismiss() } }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }.keyboardShortcut(.defaultAction)
            }.padding()
        }.frame(minWidth: 340, idealWidth: 560, minHeight: 400)
        .interactiveDismissDisabled(draft != baseline)
        .alert("放弃尚未保存的修改？", isPresented: $discard) {
            Button("继续编辑", role: .cancel) { }
            Button("放弃修改", role: .destructive) { dismiss() }
        }
    }
    private func save() {
        let address = draft.address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let parsed = URLComponents(string: "smb://\(address)/share"), parsed.host == address,
              parsed.user == nil, parsed.password == nil, parsed.port == nil,
              (1...65535).contains(draft.port), (100...30000).contains(draft.timeoutMs) else {
            error = "请输入有效服务器主机地址、1–65535 端口和 100–30000 毫秒超时。"; return
        }
        if model.saveResult == .conflict { model.simulateConcurrentSave() }
        guard baseRevision == model.revision else { error = "配置已由其他入口更改，草稿保留；请重新载入后核对。"; return }
        guard model.saveResult != .failure else { error = "未能保存；现有连接参数保持原值，草稿已保留。"; return }
        guard address == server || !model.servers.contains(address) else { error = "已有同地址服务器；不会自动合并它们。"; return }
        var changed = model.shares
        for i in changed.indices where changed[i].host == server && changed[i].managed {
            var url = URLComponents(string: changed[i].url)!
            url.host = address; url.port = draft.port == 445 ? nil : draft.port
            changed[i].url = url.string!
            if changed[i].mounted && changed[i].url != model.shares[i].url {
                changed[i].actualLocation = model.shares[i].actualLocation ?? model.shares[i].location
                changed[i].status = "需要核对"
            }
        }
        let managed = changed.filter(\.managed)
        guard Set(managed.compactMap { DemoModel.identity($0.url) }).count == managed.count else { error = "地址修改会产生重复共享；未保存。"; return }
        draft.address = address
        // 单个原子内存事务，仅迁移目标服务器属性，保留其他服务器与每个共享的实际挂载事实。
        model.shares = changed
        model.serverConnections.removeValue(forKey: server); model.serverConnections[address] = draft
        model.priority = model.priority.map { $0 == server ? address : $0 }
        if address != server {
            if let value = model.hosts.removeValue(forKey: server) { model.hosts[address] = value }
            if let value = model.serverNames.removeValue(forKey: server) { model.serverNames[address] = value }
            if let value = model.serverIndex.removeValue(forKey: server) { model.serverIndex[address] = value }
        }
        model.revision += 1; baseline = draft; baseRevision = model.revision
        model.reviewLog = "仅内存保存目标服务器关联参数；未连接网络或改变实际挂载。"
        dismiss()
    }
}

struct ShareDetails: View {
    @Bindable var model: DemoModel
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var remove = false
    @State private var editing: DemoShare?
    @State private var information: String?
    private var share: DemoShare? { model.shares.first { $0.id == id } }
    var body: some View {
        VStack(alignment: .leading) {
            if let share {
                Text(share.name).font(.title2).padding(.horizontal)
                Form {
                    Section("状态与位置") {
                        Label(share.status, systemImage: share.status == "已挂载" ? "checkmark.circle" : "exclamationmark.triangle")
                        Text(share.status == "认证失败" ? "请在 Finder 中重新连接此服务器，使用系统认证完成登录后返回重试。" : share.status == "服务器离线" ? "请检查网络和服务器。网络变化后会再次尝试自动挂载。" : share.status == "路径不符" ? "共享已挂载到其他位置；可打开现有卷宗，或弹出后重新连接。" : share.mounted ? "可以在 Finder 中访问此共享。" : "共享当前未挂载。")
                            .foregroundStyle(.secondary)
                        LabeledContent("自动安排", value: model.arrangement(share))
                            .foregroundStyle(.secondary)
                        LabeledContent("SMB 地址") { Text(share.url).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                        LabeledContent("挂载位置") { Text(share.location).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                        LabeledContent("实际位置", value: share.mounted ? (share.actualLocation ?? share.location) : "未挂载")
                        Toggle("自动挂载此共享", isOn: Binding(get: { self.share?.automatic ?? false }, set: { value in
                            model.save { if var current = self.share { current.automatic = value; model.update(current) } }
                        })).disabled(!share.managed)
                        Text("关闭后，此共享不再自动挂载；已经挂载的共享仍可使用。服务器和全局自动挂载也须开启。")
                            .foregroundStyle(.secondary)
                        if share.mounted {
                            Button("在 Finder 中打开") { model.primary(id) }
                            Button("弹出") { model.eject(id) }
                        } else if share.managed { Button("重试") { model.primary(id) } }
                        if share.status == "已弹出" { Text("普通弹出后本次会话不会自动重挂。挂载只恢复此目标，不触发整轮评估。").foregroundStyle(.secondary) }
                    }
                    Section("索引尝试") {
                        Text(model.serverIndex[share.host, default: false] ? "已尝试，但无法确认系统索引状态。" : "未启用")
                        Text("索引尝试结果与挂载健康分别查看，不能保证系统已停止索引。")
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        if share.managed {
                            Button("编辑地址与位置…") { editing = share }
                            Button("移除共享…", role: .destructive) { remove = true }
                        } else {
                            Button("添加") { information = model.add(share.id) }
                        }
                        Text("已有挂载不会卸载，远程文件不会删除。")
                            .foregroundStyle(.secondary)
                    }
                }.formStyle(.grouped)
            }
        }.padding(.top)
        .onChange(of: model.feedback) { _, value in
            if let value { information = value; model.feedback = nil }
        }
        .navigationTitle(share?.name ?? "共享详情")
        .sheet(item: $editing) { share in EditShare(model: model, original: share) }
        .alert("移除此共享？", isPresented: $remove) {
            Button("取消", role: .cancel) { }
            Button("移除", role: .destructive) {
                if let error = model.saveError { information = error; return }
                if var current = share { current.managed = false; model.update(current) }
                dismiss()
            }
        } message: { Text("Automnt 将不再自动挂载此共享。已有挂载不会卸载，远程文件不会删除。") }
        .alert("操作结果", isPresented: Binding(get: { information != nil }, set: { if !$0 { information = nil } })) {
            Button("好", role: .cancel) { information = nil }
        } message: { Text(information ?? "") }
    }
}

struct EditShare: View {
    @Bindable var model: DemoModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DemoShare
    @State private var baseline: DemoShare
    @State private var error: String?
    @State private var discard = false
    @State private var reload = false
    init(model: DemoModel, original: DemoShare) {
        self.model = model
        _draft = State(initialValue: original)
        _baseline = State(initialValue: original)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑共享").font(.title2)
            Form {
                Text("已有挂载保持原状；下一次连接使用保存的地址和位置。")
                    .foregroundStyle(.secondary)
                TextField("完整 SMB 地址", text: $draft.url)
                    .onChange(of: draft.url) { _, value in
                        if DemoModel.validURL(value) { draft.location = "/Volumes/" + (URLComponents(string: value)?.path.split(separator: "/").first.map(String.init) ?? "共享") }
                    }
                TextField("挂载位置", text: $draft.location)
                Text("标准位置由共享名称推导。不同服务器可复用位置；同一服务器内不能重复。").foregroundStyle(.secondary)
                if let error {
                    Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("保存错误：\(error)")
                    if model.saveResult == .conflict {
                        Button("重新载入已保存设置") { reload = true }
                    }
                }
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消") { cancel() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }.keyboardShortcut(.defaultAction)
            }
        }.padding().frame(minWidth: 340, idealWidth: 520, minHeight: 310)
        .interactiveDismissDisabled(draft != baseline)
        .alert("放弃尚未保存的修改？", isPresented: $discard) {
            Button("继续编辑", role: .cancel) { }
            Button("放弃修改", role: .destructive) { draft = baseline; dismiss() }
        } message: { Text("放弃后，这些输入将丢失。") }
        .alert("重新载入已保存设置？", isPresented: $reload) {
            Button("继续编辑", role: .cancel) { }
            Button("重新载入", role: .destructive) {
                if let latest = model.shares.first(where: { $0.id == draft.id }) {
                    draft = latest; baseline = latest; error = nil
                }
            }
        } message: { Text("重新载入会放弃当前草稿。") }
    }
    private func cancel() { if draft != baseline { discard = true } else { dismiss() } }
    private func save() {
        draft.url = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.location = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DemoModel.validURL(draft.url) else { error = "请输入不含登录信息的完整 smb://host/share 地址。"; return }
        guard DemoModel.validPath(draft.location) else { error = "请输入非根目录的绝对挂载位置。"; return }
        guard model.shares.contains(where: { $0.id == draft.id }) else { error = "此共享已移除。草稿已保留，请取消并检查最新列表。"; return }
        guard !model.collision(draft) else {
            error = "地址或位置与另一个已管理共享冲突。输入已保留，请调整后重试。"; return
        }
        switch model.saveResult {
        case .failure: error = "未能保存。输入已保留，请重试。"
        case .conflict: error = "设置已在其他地方更改。输入已保留，可重试或重新载入。"
        case .success:
            model.update(draft)
            baseline = draft // 更新已保存基线，Cancel 不再重复提示保存。
            error = nil
            model.reviewLog = "已保存并关闭编辑（内存模拟）。"
            dismiss()
        }
    }
}

struct ManualShare: View {
    @Bindable var model: DemoModel
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("手动添加共享").font(.title2)
            Form {
                TextField("完整 SMB 地址", text: $url, prompt: Text("smb://host/share"))
                Text("认证由 Finder 和系统处理。添加后可编辑挂载位置。")
                    .foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("添加") {
                    let value = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard DemoModel.validURL(value) else { error = "请输入完整 smb://host/share 地址，不含用户名或密码。"; return }
                    if let existing = model.shares.first(where: { DemoModel.identity($0.url) == DemoModel.identity(value) }) {
                        if let failure = model.add(existing.id) { error = failure; return }
                    } else {
                        let name = URLComponents(string: value)?.path.split(separator: "/").first.map(String.init) ?? "共享"
                        let location = "/Volumes/" + name
                        let candidate = DemoShare(url: value, location: location, managed: true, status: "等待连接")
                         guard !model.collision(candidate) else {
                            error = "挂载位置与已管理共享冲突，请检查最新列表。"; return
                        }
                        if let failure = model.saveError { error = failure; return }
                        if !model.managedServers.contains(candidate.host) { model.priority.removeAll { $0 == candidate.host }; model.priority.append(candidate.host) }
                        model.shares.append(candidate)
                        model.revision += 1
                    }
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }.padding().frame(minWidth: 340, idealWidth: 500, minHeight: 260)
    }
}

struct DemoSettings: View {
    @Bindable var model: DemoModel
    var body: some View {
        Form {
            Section("自动挂载") {
                Toggle("自动挂载", isOn: model.setting(\.automatic))
                LabeledContent("后台状态", value: model.background)
                if model.background != "正在运行" { Button("打开后台项目设置") { model.reviewLog = "模拟打开系统设置，未执行。" } }
                Text("关闭后，已经挂载的共享仍可使用。")
                    .foregroundStyle(.secondary)
                Toggle("自动恢复", isOn: model.setting(\.recovery))
                    .disabled(!model.automatic)
                Text("共享意外断开后尝试恢复；关闭后仍在登录或网络变化时自动挂载。自动挂载开启时生效。")
                    .foregroundStyle(.secondary)
            }
            Section("菜单栏与登录") {
                Toggle("在菜单栏中显示 Automnt", isOn: model.setting(\.menu))
                Toggle("登录时显示菜单栏", isOn: model.setting(\.login))
                    .disabled(!model.menu)
                Text("登录时不打开主窗口；需同时开启菜单栏选项。后台自动恢复独立运行。")
                    .foregroundStyle(.secondary)
            }
            Section("通知") {
                LabeledContent("系统授权", value: model.notificationAuthorization)
                if model.notificationAuthorization == "尚未请求" {
                    Button("允许失败通知…") { model.notificationAuthorization = "已允许"; model.reviewLog = "模拟通知批准；未请求真实系统授权。" }
                } else {
                    Button("打开系统通知设置") { model.reviewLog = "模拟打开系统通知设置；未执行。" }
                }
                Toggle("通知声音", isOn: model.setting(\.sound))
                Text("声音同时受系统通知设置控制；失败通知按系统实际授权发送。")
                    .foregroundStyle(.secondary)
            }
            Section("高级") {
                Stepper("每轮最多尝试 \(model.retry) 次", value: Binding(get: { model.retry }, set: { value in model.save { model.retry = value } }), in: 1...5)
                Text("仅限制当前一轮；空闲时不持续轮询。").foregroundStyle(.secondary)
            }
            Section("支持") {
                WindowButton(title: "帮助与支持", destination: "help")
                WindowButton(title: "关于 Automnt", destination: "about")
                Text("帮助与支持窗口包含使用帮助、诊断预览与导出、支持与隐私、离线开源许可四项，离线可读并支持键盘关闭返回。")
                    .foregroundStyle(.secondary)
            }
            Section("索引与帮助") {
                Text("在主窗口选择服务器后，打开“服务器设置”调整“尝试阻止 Spotlight 索引”，分别控制每台服务器的共享。")
                    .foregroundStyle(.secondary)
                Text("索引尝试结果与挂载健康分别查看，不能保证系统已停止索引。")
                    .foregroundStyle(.secondary)
                Text("认证失败时，请在 Finder 重新连接服务器并完成系统认证。Automnt 不提供密码管理。")
                    .foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(minWidth: 340, idealWidth: 560, minHeight: 400)
        .alert("未能保存", isPresented: Binding(get: { model.feedback != nil }, set: { if !$0 { model.feedback = nil } })) { Button("好") { model.feedback = nil } } message: { Text(model.feedback ?? "") }
    }
}

struct ReviewTools: View {
    @Bindable var model: DemoModel
    var body: some View {
        Form {
            Section("独立设计审阅工具 · 不属于产品界面") {
                Text("Automnt 仅为当前暂用名。全部为虚构的内存数据，发现和刷新为模拟，不访问网络、配置、Keychain 或服务。")
                    .foregroundStyle(.secondary)
                Picker("场景", selection: Binding(get: { model.scene }, set: { model.setScene($0) })) {
                    ForEach(ReviewScene.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("下次保存", selection: $model.saveResult) {
                    ForEach(SaveResult.allCases) { Text($0.rawValue).tag($0) }
                }
                Button("模拟重新激活刷新") { model.refresh("重新激活") }
                Button("模拟卷变化刷新") { model.refresh("卷变化") }
                Button("模拟整轮评估") { model.evaluate() }
                LabeledContent("配置 revision", value: "\(model.revision)")
                Button("模拟其他入口并发保存") { model.simulateConcurrentSave() }
                Button("模拟撤销最近排序") { model.undoServerOrder() }.disabled(model.orderUndo == nil)
                Text("排序审阅：成功移动后撤销；保存失败保留当前顺序；并发保存后旧撤销失效。搜索任意名称时拖放与移动菜单禁用。").foregroundStyle(.secondary)
                Button("模拟网络变化") {
                    for i in model.shares.indices where model.shares[i].status == "已弹出" { model.shares[i].status = "等待连接" }
                    model.evaluate()
                }
                Picker("通知实际授权", selection: $model.notificationAuthorization) {
                    Text("尚未请求").tag("尚未请求"); Text("已允许").tag("已允许"); Text("已拒绝").tag("已拒绝")
                }
                ForEach(model.managedServers, id: \.self) { host in
                    Toggle("\(host) 可达", isOn: Binding(get: { model.reachability[host, default: model.scene != .offline] }, set: { model.reachability[host] = $0 }))
                }
                Section("完整本轮结果") {
                    Text(model.roundSummary)
                    ForEach(Array(model.roundResults.enumerated()), id: \.offset) { _, result in Text(result).textSelection(.enabled) }
                }
                Button("重置示例") { model.setScene(.discovered); model.saveResult = .success }
                Text(model.reviewLog).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            Section("审阅边界") {
                Text("真实卷通知和窗口重新激活只触发示例刷新；不扫描卷、不发现服务器。空态场景保持空态。")
                Text("Finder、认证、通知、登录项、索引和挂载不执行。设置只存内存，关闭进程后恢复示例。")
                Text("使用系统控件、语义字体和默认 sheet/alert 行为，无自定义动画或声音。可缩窄主窗口并滚动；字段不随窗口 inactive 状态禁用。")
                Text("macOS 27 SDK 编译不等于完成 VoiceOver、较大文字、浅深色、减少动态效果或 inactive 窗口的真实交互验收。")
                Text("CLI 不提供弹出入口。共享配置、GUI/CLI 后台 owner 仲裁与系统认证未在本 demo 验证，不能作为真实运行证据。诊断导出只显示脱敏样例与结果，不写文件。")
            }
        }.formStyle(.grouped).frame(minWidth: 340, minHeight: 360)
    }
}

struct DemoMenu: View {
    @Bindable var model: DemoModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.automatic ? "自动挂载已开启" : "自动挂载已关闭")
        ForEach(model.servers, id: \.self) { server in
            Section(server) {
                ForEach(model.shares.filter { $0.host == server && $0.managed }) { share in
                    Menu("\(share.name) · \(share.status)") {
                        Button(share.mounted ? "在 Finder 中打开" : "重试") { model.primary(share.id) }
                        if share.mounted { Button("弹出") { model.eject(share.id) } }
                    }
                }
            }
        }
        Button("打开 Automnt") { openWindow(id: "main") }
        SettingsLink { Text("设置…") }
        WindowButton(title: "帮助与支持", destination: "help")
        WindowButton(title: "关于 Automnt", destination: "about")
    }
}

struct WindowButton: View {
    let title: String
    let destination: String
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button(title) { openWindow(id: destination) } }
}

struct SupportPage: View {
    @Bindable var model: DemoModel
    let kind: String
    @State private var exported = false
    var body: some View {
        Form {
            Section(kind) {
                Text("Automnt").font(.title)
                Text("在服务器可达、配置及凭据有效时，后台自动挂载并恢复 SMB 共享。")
                Text("认证失败时请在 Finder 按 ⌘K 连接服务器，完成系统登录后重试。路径不符时可打开当前卷宗，或弹出后重试。")
                Text("自动挂载按服务器优先级选择首个可达服务器。刷新只更新状态；立即重试会重新评估本轮服务器。")
            }
            Section("隐私 · 离线可读") {
                Text("连接地址和位置用于共享管理。诊断预览默认隐藏服务器、共享名称、账户与完整路径；发送支持资料前请再次检查。")
            }
            Section("开源许可 · 离线可读") {
                Text("MIT License · Copyright (c) 2026 jiezhengj")
                Text("Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the Software), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.").textSelection(.enabled)
            }
            Section("诊断") {
                Text("后台：\(model.background)\n服务器：<server-1>\n共享：<share-1>\n位置：<mount-location>\n账户：<redacted>\n配置来源：活动配置\n后台所有权：待验证")
                    .textSelection(.enabled)
                Button("导出诊断…") { exported = true; model.reviewLog = "诊断导出模拟完成；没有文件写入。" }
                if exported { Text("诊断已准备好。").foregroundStyle(.secondary) }
            }
        }.formStyle(.grouped).frame(minWidth: 340, idealWidth: 600, minHeight: 440)
    }
}
