# 用途

本文件记录 Feature 006（菜单栏「快捷挂载」）的逐阶段改动、决定性决定与验证证据。规则性的东西（交互原则、文案基线、门禁命令）仍在 `AGENTS.md` 与 `docs/` 中，这里只记本轮实际做了什么、为什么、证据在哪。

# 改动清单

**判定逻辑（`Sources/AutomntCore/QuickMountOutcome.swift`，新增）**

- `QuickMountTarget`：一轮里某个共享的 identity、名称、是否启用、可用性、结构化原因。
- `QuickMountFailure.Reason`：`credentials` / `locationBusy` / `refused` / `notFinished` / `other`，面向用户的原因分类。
- `QuickMountOutcome`：`make(from:)` 只取启用项、只把确实「尝试过且仍不可用」的项计入失败，空集合返回 `nil`。
- `QuickMountGate`：`ready` / `noConfiguration` / `automaticMountingOff` / `backgroundNotReady` / `busy`，`evaluate(hasConfiguration:automationEnabled:backend:busy:)`。

失败归类的取舍：`.failed`（按 `issue` 细分）、`.authenticationRequired`、`.locationOccupied` 计入；`.unreachable`、`.notEvaluatedThisRound`、`.suppressedForThisSession`、`.notMounted`、`.locationMismatch`、`.usable`、`.availableViaPeer` 一律不计入。`.notMounted` 计入会造假警报——它只表示这一轮没有轮到它。

**模型（`apps/Automnt/AutomntApp.swift`）**

- 新增 `quickMountOutcome`（当前摘要）、`quickMountNotice`（只清自己写过的那句 `notice`）、`quickMountGate`、`quickMountGateExplanation(_:)`、`quickMountSummaryText(_:)`、`hostIdentity(owningShare:)`、`reportQuickMountOutcome()`。
- `tryFullRound(surface:)`：开跑即作废旧摘要；只有 `adapter.requestEvaluation` 真的成功返回后才置 `ranRound = true`，`defer` 里据此生成摘要——被门禁挡下或抛错的路径不会留下一条"失败"假象。
- `save(_:_:)` 成功分支清空摘要：配置变了，旧摘要描述的那个集合已不存在。

**界面**

- `apps/Automnt/Views/DetailViews.swift`：`Check Now` 原位改为 `Quick Mount`，新增 `quickMountSection`（按钮 + 门禁原因一行 + 摘要一行 + 「未挂载的共享文件夹」子菜单，每项「名称 — 原因」并跳到主窗口详情）。菜单项文字不换行，长名称靠子菜单规避截断。
- `apps/Automnt/AutomntApp.swift`：主窗口 `CommandMenu("Servers")` 同名同门禁，⌘R 保留。
- `apps/Automnt/Views/MainWindowView.swift`：`ShareRowView.quickMountReasonLabel(_:)` 提供五类原因的短标签。

**文案（`apps/Automnt/Resources/Localizable.xcstrings`）**

- 新增 11 个 key × 9 语言：`Quick Mount`、四种门禁原因、两条摘要（单数与 `%lld`）、`Shared Folders Not Mounted`、`Server refused it`、`Didn’t finish`、`Couldn’t mount`。
- 移除 `Check Now` 与 `Check every shared folder now and mount what is missing.`。
- 原因标签复用既有词：`credentials` → `Sign-in required`、`locationBusy` → `Location occupied`，避免同一状态两种说法。
- **不使用复数 variations**：应用目录 460 条里一条 plural 都没有，校验脚本也只认 `stringUnit`；摘要因此写成「One shared folder couldn’t be mounted.」与「%lld shared folders couldn’t be mounted.」两条独立 key，用 `String(format:)` 取数。

# 决定性决定

- **不改名为 `Mount All`**：本会话被手动弹出的共享会被跳过，叫“全部”名不副实；`Quick Mount` 与中文「快捷挂载」（维护者指定）对应。
- **不发系统通知**（推翻 spec 初稿）：现有唯一通知文案是「Automnt：自动恢复未完成 / N 个共享文件夹未能自动挂载」，用在用户主动点击的动作上会讲错故事；新增第二种通知类型要同时改 Core/Platform/CLI 与两处九语资源，与本 Feature 规模不成比例。改为菜单内常驻摘要 + 明细子菜单。
- **自动挂载关闭时置灰而不是照跑**：`tryFullRound` 要求 `BackendStateStore` 的 owner 为 app 且 phase 为 active，关着自动挂载时根本跑不了；与其点了再解释，不如提前置灰并说明下一步（宪法原则 II 也禁止为此另开常驻进程）。
- **`--require-translated` 换成默认模式**：该模式忽略文档化的品牌/借用词 allowlist，`Automnt`、`Notifications`、`Port`、`Name` 在九语中本就不翻译，基线状态下永远无法通过。属既存约束，本 Feature 按项目实际门禁执行，spec SC-004 已修订。

# 验证证据（2026-11-20）

- `swift test`：全通过（新增 `QuickMountOutcomeTests` 5 项；CLI 套件 33 项）。
- `python3 scripts/verify-localization.py`：PASS，277 条源字符串 × 9 语言，无新增 key 落在“非英语与英语逐字相同”清单。
- `bash scripts/build-app.sh`：BUILD SUCCEEDED，5 项签名/密封校验 PASS，指定要求仍钉在 `Apple Development: jie.zhengj@qq.com (8SDSF987N2)`。
- 实机（已装 `/Applications/Automnt.app`，用辅助功能树读取真实菜单，非截图推断）：
  - 菜单出现「快捷挂载」，两卷已挂载时该轮 `background-observations.plist` 仍写 healthy，菜单**没有**任何新增文案（SC-002 的“成功 0 条”）。
  - 执行期间该项置灰并显示「另一个操作还在进行。等它结束后再试。」，约 6 秒后恢复。
  - 真实失败：临时添加 `//100.113.52.52/no-such-share-006` 后点「快捷挂载」→ 摘要「有 1 个共享文件夹未能挂载。」+ 子菜单「未挂载的共享文件夹」→「no-such-share-006 — 服务器拒绝了该共享」；点击该项打开主窗口并选中该共享。随后从界面移除该共享，配置回到 4 条 `smb_url`（两台主机各两条共享），两卷重新挂载，无残留挂载点。

# 未验证（不得写成已通过）

- 无配置、自动挂载关闭、后台未就绪三种置灰原因只有 `QuickMountGate.evaluate` 单测覆盖，未在实机分别制造（制造这三种状态需要改动机上真实的自动挂载与后台登记）。
- ⌘R 未在真实窗口按一次键实测；它与菜单项走同一 `tryFullRound` 与同一门禁。
- 九语译文为草稿，母语审校仍按既有规则单独把关。
- 未提交、未推送、未创建 Release、未递增版本号（本轮未获授权）。
