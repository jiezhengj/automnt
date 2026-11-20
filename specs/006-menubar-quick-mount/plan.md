**Feature**：006-menubar-quick-mount | **规格**：[spec.md](spec.md) | **Created**：2026-11-20 | **Status**：Draft（计划待维护者过目；未改代码）

# 技术概要

三件事，全部落在 GUI 层与一个纯逻辑模块，不动挂载内核：

1. **改名**：菜单栏菜单与主窗口「服务器」菜单里的 `Check Now` 换成 `Quick Mount`／「快捷挂载」，两处都调用同一个 `tryFullRound`，行为不变。
2. **门禁可见**：现在该项只在"无配置／配置不可改／忙碌"时置灰，其余情况点下去由 `tryFullRound` 内部发现"后台挂载没在跑"再写一句 notice，用户点完才知道不行。改为**动作前就判定**四种阻塞原因，置灰并在菜单里紧贴一行原因与下一步。
3. **结果摘要**：`tryFullRound` 现在"成功无提示、失败也无提示"。改为轮次结束后把"尝试过但没挂上"的共享归类，在菜单里给一行摘要（可展开逐项与原因），主窗口消息区显示同一句；全成功零文案。

# 现状与改动点

| 位置 | 现状 | 改动 |
| --- | --- | --- |
| `apps/Automnt/Views/DetailViews.swift:1184` | `Button("Check Now") { Task { await model.tryFullRound(surface: .menuBar) } }.disabled(!model.configurationChangesAllowed \|\| !model.hasConfiguration)` | 文案改「快捷挂载」；`disabled` 改由 `model.quickMountGate` 统一判定；紧贴一行原因；下方新增结果摘要区 |
| `apps/Automnt/AutomntApp.swift:1751` | `CommandMenu("Servers")` 内 `Button("Check Now")` + `.keyboardShortcut("r", .command)` + 同款 `disabled` | 文案与门禁同步；⌘R 保留 |
| `apps/Automnt/AutomntApp.swift:998` | `func tryFullRound(surface:) async`：`guard configurationChangesAllowed`、`guard let base`、`begin(.fullEvaluation)`、要求 `state.owner == .app && state.phase == .active`（否则写 notice）、`requestEvaluation` 30s、`defer { refreshStatus() }`、结尾注释"成功无提示" | 轮次结束后调用新增的结果汇总并把结果写进 `quickMountOutcome`；成功后清空旧结果；"后台没在跑"这类阻塞改由门禁前置拦住，这里的 notice 保留为兜底 |
| 新文件 `Sources/AutomntCore/QuickMountOutcome.swift` | 无 | 纯逻辑：输入（共享标识、名称、可用性、本轮观测的问题类别）→ 输出（摘要计数、按原因分组的失败项、用户措辞的原因类别）。可单测 |
| `apps/Automnt/Resources/Localizable.xcstrings` | 有 `Check Now` 与说明句，九语齐全 | 删 `Check Now` 及其译文；新增标签、四种阻塞原因、摘要（复数）、原因类别共约 8 个 key × 九语 |
| `specs/005-swiftui-mas-gui/spec.md`、`design/localization.md` | 005 里"快捷挂载"指逐共享定向挂载；文案基线禁止给挂载动作加"快捷" | 各补一句消歧与偏离记录（流程文档，不涉代码） |
| `specs/006-menubar-quick-mount/CHANGELOG.md` | 无 | 新建，记录本 Feature 的逐轮修订 |

# 判定规则（实现契约）

失败集合 = 同时满足：该共享**已启用**、所在服务器**本轮被检查过**、`availability` 属于失败类。

以既有的 `TargetAvailability`（`Sources/AutomntCore/OperationPresentation.swift:68`）为准，避免另建一套判定：

| `availability` | 归类 | 用户措辞方向 |
| --- | --- | --- |
| `.failed` | 失败 | 按本轮 `issue` 细分：凭据失效／共享被拒／路径冲突／超时或中断／其他 |
| `.authenticationRequired` | 失败 | 需要重新登录该服务器 |
| `.locationOccupied` | 失败 | 配置的挂载位置被其他卷占用 |
| `.unreachable`、`.notEvaluatedThisRound`、`.suppressedForThisSession`、`.notMounted`、`.locationMismatch`、`.usable`、`.availableViaPeer` | **不计入** | — |

`.notMounted` 不计入是关键：它表示"本轮没尝试或没结果"，把它算失败会制造假警报。

# 交互设计

- **门禁**（`QuickMountGate`，`ApplicationModel` 上的只读计算属性）：
  - `.ready`：可点。
  - `.noConfiguration`：无已配置共享 → 置灰，行下说明"先添加共享文件夹"。
  - `.automaticMountingOff`：配置里自动挂载未启用 → 置灰，说明"需要先开启自动挂载"，指向设置。
  - `.backgroundNotReady`：`BackendStateStore` 的 owner/phase 不是 `app`/`active`（含待批准、过渡中、CLI 接管）→ 置灰，说明指向"检查自动挂载状态"。
  - `.busy`：`busy == true` → 置灰，不排队。
- **结果摘要**（`quickMountOutcome: QuickMountOutcome?`，内存态，不落盘）：
  - 无失败：`nil`，菜单里什么都不出现。
  - 有失败：一行 `Text`（"2 个共享文件夹未能挂载"），其下 `Menu("查看未挂载的共享文件夹")`，每项 `Button("名称 — 原因")`，点击打开该共享在主窗口的详情（复用 `model.requestedDetail` + `openWindow(id: "main")`）。子菜单解决长名称在菜单里被截断的问题（菜单项文字无法换行）。
  - 生命周期：下一次运行结束即覆盖；配置变更后清空，避免拿旧结果说新配置。
- **主窗口消息区**：`surface == .window` 时把同一句摘要写进 `notice`，复用 `MainWindowView.swift:451/865` 的既有显示位；不开新的消息通道。

# 已决事项：不发系统通知（相对 spec 早稿的修订）

spec 早稿写过"通知已授权时发一条"，实现侧核对后改为**不发**，理由：

- 既有通知通道的唯一文案是「Automnt：自动恢复未完成 / N 个共享文件夹未能自动挂载」，服务于后台自动恢复失败；用户主动点「快捷挂载」收到这句话，等于被告知"自动恢复没完成"，讲错了故事。
- 复用它需要给 `FailureNotification`／`NotificationCatalog` 增加第二种通知类型，等于同时改 Core、Platform、CLI 与两处 xcstrings 的九语复数，属于独立改动，与"加一个菜单项"不成比例。
- 菜单摘要常驻内存直到结果变化，所以"点了不知道结果"的问题已由摘要 + 明细子菜单解决；主窗口消息区也能看到同一句。

因此 spec 的 FR-007 与「已定事项」会同步改成"仅菜单与窗口内显示，不发通知"，并把"独立的通知类型"记为后续可选项。

# 文案与本地化

- 英文标签：`Quick Mount`；简体「快捷挂载」、繁体「快捷掛載」、日「クイックマウント」、韩「빠른 마운트」、德「Schnell einbinden」、法「Montage rapide」、西「Montaje rápido」、葡「Montagem rápida」。
- 摘要行用复数变体（en one/other，de/fr/es/pt 的 many），中文用「N 个共享文件夹未能挂载」不写"一轮/评估"。
- 原因类别只用用户词汇：需要重新登录／位置被占用／服务器拒绝该共享／未完成，请重试／其他原因。
- 门禁说明不用"后台服务/owner/phase"等内部词，写"自动挂载"与"设置"。
- 全部走 `scripts/verify-localization.py --require-translated`；非英文不得与英文逐字相同。

# 已识别的风险

- **菜单点完即关闭**：摘要只能"下次打开菜单才看见"。已用"摘要常驻 + 窗口内同一句"缓解；这属于原生行为限制，已在 spec 边界情景记录。
- **置灰行常驻**：自动挂载关闭时菜单里会一直多一行说明。这是 FR-008 的要求（不能静默置灰），但需在实机上确认菜单不明显变长、不遮挡既有项。
- **`Text` 在菜单里的呈现**：macOS 把纯文本渲染为灰色不可点项，既有代码已用同一手法显示 notice/issue，属沿用而非新发明；需实机确认深色模式与 VoiceOver 可读。
- **删除 `Check Now` key**：若还有别处引用（文档不算）会导致漏译。已确认代码只有两处引用，删 key 前再全仓 grep 一次。
- **回归面**：`tryFullRound` 被两个入口共用，改动其尾部结果汇总不得影响单共享挂载、弹出与后台轮次；`swift test` 与 CLI `--self-test` 必须全绿。

# 实施顺序

1. `QuickMountOutcome` 纯逻辑 + 单测（`Tests/AutomntCoreTests/QuickMountOutcomeTests.swift`），先把归类规则钉死。
2. `ApplicationModel`：`quickMountGate`、`quickMountOutcome`、轮次结束后汇总、配置变更清空。
3. 菜单栏视图：改名、门禁、原因行、摘要与明细子菜单。
4. 主窗口「服务器」菜单改名与门禁同步（⌘R 保留）。
5. 九语文案与本地化闸门。
6. 文档：005 消歧与基线偏离、006 CHANGELOG、spec FR-007 修订。
7. 验证：`swift test`、`scripts/verify-localization.py --require-translated`、`bash scripts/build-app.sh`、实机菜单真实点击（全部成功／部分失败／四种置灰）。

# 边界

不做出、不推送、不递增版本号（推送/Release 需另行授权）。不改 CLI 文案与行为、不改配置文件与格式、不新增常驻进程、不引入新依赖、不改菜单栏图标默认关闭策略。
