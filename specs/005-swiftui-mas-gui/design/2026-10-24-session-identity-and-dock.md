本文记录 2026-10-24 第六轮对“重启后未自动挂载”的诊断与修复，以及同期 Dock 图标/窗口行为决定的依据与取舍。它说明机制与限制，不构成验收通过：真实重启与真实登录项启动已于 2026-10-24 19:00 实测（见“实测证据与门禁”），其余未验证项见文末。

# 会话边界的数据流

- 采集：`RecoverySessionCollector.collect(previous:)`（Sources/AutomntPlatform/RecoverySessionCollector.swift:8-11）先取 `loginEpoch()`，再取 `networkIdentity()`，组装 `RecoverySessionIdentity`（network + loginEpoch）。
- 判定：`RecoverySessionPolicy.advance`（Sources/AutomntCore/RecoverySession.swift:16-65）把状态推进到新边界，并在“新会话”时重置会话级计数与抑制（见下）。
- 判定后由 `RecoveryVolumeDecisionPolicy.judge` 依据“是否在挂载表、是否有用户弹出记录、everHealthyMounted”等给出挂载/抑制决定；本轮缺陷正出在 advance 之前的边界缺失，导致 judge 把陈旧 attached 当成健康弹出。
- 边界格式：`<network>|<loginEpoch>`；loginEpoch 形如 `<boot>-<consoleStart|console-unreadable>`（RecoverySession.swift:67-70 的 `bootComponent` 明确“重启才会改变前段”）。

# 沙盒可读性约束与降级

- 沙盒 helper 读不到 utmpx：新增诊断入口 `AutomntHelper --probe-session`（apps/Automnt/Service/HelperEntry.swift:31,169-173）实测 `utmpx-console-records=0`、`login-epoch=unreadable`、`session=unavailable`；`network-identity=readable`、`boot-time=readable`。
- 旧实现 `loginEpoch()` 只要 console 记录不可读就返回 nil，`collect` 随之为 nil，`advance` 不被调用，`session_boundary` 从未写入——跨重启后旧的 `state=attached` 被当成“本会话健康弹出”（absent + everHealthyMounted → healthyEject → sessionSuppressed），自动挂载被跳过。
- 降级策略（RecoverySessionCollector.swift:47-50）：boot time 始终在重启时变化且沙盒可读，因此 console 不可读时返回 `"<boot>-console-unreadable"`，保持“重启即新会话”；只有 `sysctl KERN_BOOTTIME`（:53-59）也不可读才返回 nil 并保守不推进边界。console 记录仍用于区分同一 boot 内的重新登录（:61-75）。

# establishing 分支为何要恢复陈旧 attached

- `.attached` 在本项目中只表示“本应用挂载过”，不是用户弹出；若它不在挂载表、也没有用户弹出记录，说明这是上一次会话（升级/重启）留下的状态，而不是本会话的健康弹出。
- establishing 分支（RecoverySession.swift:34-50）因此把这类 `.attached` 改为 `.pendingRecovery`，清空 `lastAttemptAt`、`attemptOperationID`、`attemptCount`、`notificationCount`，使其重新参与自动挂载。
- `.suppressed`（用户确实弹出过）不动其状态，只把 `suppressionBoundary` 绑定到新边界（:36-37），保证抑制仍只属于旧会话、不误伤新会话。
- 非 establishing 分支（:51-63）维持原有“新会话重置”逻辑：suppressed 或 everHealthyMounted 且不在挂载表 → pendingRecovery 并清空 suppressionBoundary，计数一并清零。

# 同 boot 保护

- 沙盒 helper 与 CLI 对同一启动的 loginEpoch 写法不同：前者 `console-unreadable`，后者可读到 console 时间。若把这种差异当作新会话，会误清用户在本会话的弹出抑制。
- 保护（RecoverySession.swift:24-33）：非 establishing 且 network 相同、两边 loginEpoch 的 boot 段相同（`bootComponent`）时直接返回——不改写边界、不清抑制。抑制记录按边界值绑定，边界被改写会让对端抑制失配。
- 结果：同一启动内只有“重启导致 boot 段变化”才算新会话；`console-unreadable` 与可读 console 的写法差异被吸收。

# 会话抑制的已知限制

- 因为边界以 boot 时间为兜底，同一 boot 内“退出登录再登录”不会刷新边界；该会话内被记为用户弹出的共享会持续不自动挂载，直到重启。
- 这是沙盒读不到 utmpx 的直接后果，属已确认限制，不是本轮可修缺陷；用户可用界面中的“立即尝试自动挂载”，或对单个共享点“挂载/重试”恢复，已写入 release/offline/known-limitations.zh.md 与 .en.md。
- 修复后的重启会写入新边界并恢复陈旧 attached；该路径已用等价模拟与 2026-10-24 19:00 的真实重启验证（T138 的真实重启部分通过）。

# Dock 图标与窗口行为

- 维护者反馈：设置窗口没打开时 Dock 栏不该出现 Automnt 图标；同时菜单栏常驻形态不应因为关闭窗口就退出。
- 实现：
  - `apps/Automnt/Resources/Info.plist:16-17` 设 `LSUIElement=true`，默认 accessory（菜单栏 App，无 Dock 图标）。
  - `apps/Automnt/AutomntApp.swift:10,23-43` 的 `DraftTerminationDelegate` 监听窗口 didBecomeKey/didDeminiaturize/willClose，按“是否存在可见的 titled 普通窗口”（:35-38）在 `.regular` 与 `.accessory` 间切换；切到 regular 时必要时激活。
  - `applicationShouldTerminateAfterLastWindowClosed`（:45-50）返回 `!menuBarEnabled`：菜单栏常驻时关掉最后一个窗口仍继续运行；未常驻时按普通窗口 App 退出，避免“无窗口、无 Dock、无菜单栏”的隐形进程。
- 取舍：登录项启动或仅菜单栏常驻时无 Dock 图标；主窗口或设置窗口出现时才有 Dock 图标；关最后一个窗口是否退出取决于菜单栏图标是否开启。代价是 activation policy 需要随窗口增减动态切换，且登录项启动路径的 Dock 表现必须在真实登录项下复验。

# 实测证据与门禁

- 02:00 重启后故障现场：`mount | grep smb` 为空；recovery agent runs=3、最后退出码 0；observations 两卷 status=suppressed、retrySuggested=false；state 两卷 attached 且无 session_boundary。
- 修复后探针：`login-epoch=readable`、`session=available`。
- 02:09 `launchctl kickstart -k gui/$UID/org.automnt.automnt.recovery`：两卷挂载成功，observations 两卷 status=healthy，state 写回 session_boundary、volumes=attached。
- 重启模拟（02:16 与最终构建 02:19（observations 写入 02:19:31） 各一次）：diskutil unmount 两卷 → 伪造旧边界 `old-network|1700000000-old-console`、两卷 attached、attempt_count=2 → kickstart → 两卷重新挂载、attached/attempt_count=0、observations health、session_boundary 更新为 `<network>|1792778275-console-unreadable`。
- Dock 行为证据命令：`osascript -e 'tell application "System Events" to tell process "Automnt" to get {background only, count of windows, (count menu bar items of menu bar 2)}'`（`background only=true` 即 accessory/无 Dock 图标；窗口数 0 且菜单栏图标 1 表示仅菜单栏常驻）。实测（最终安装构建，macOS 27、简体中文、深色）：主窗口打开时 `background only=false`（regular、有 Dock 图标）；关闭全部窗口后 `background only=true`、窗口数 0、菜单栏图标 1（无 Dock 图标）；从菜单栏“打开 Automnt”重开窗口后恢复 regular。
- 2026-10-24 19:00 真实重启：boot 1792839587（18:59:47）；登录项 19:00:23 启动 App（PID 876，0 窗口、`background only=true` 无 Dock 图标、菜单栏图标 1）；recovery agent runs=2、退出码 0；无人工操作下两卷自动挂载，19:02:11 observations 两卷 healthy、retrySuggested=false；state session_boundary=`<network>|1792839587-console-unreadable`、两卷 attached/attempt_count=0；backend owner=app/active、worker-operation pending=false、无第二 helper；`ls` 可读；无新增崩溃报告。
- 抑制清除的等价验证（2026-10-24 19:2x）：同会话 `diskutil unmount` 两卷后 kickstart → observations suppressed、不挂载（符合设计）；把 state 边界伪造为旧会话（attached/attempt_count=2）后 kickstart → 两卷重新挂载、healthy、attached/attempt_count=0，边界回到当前 boot。
- 门禁：`swift test` 339 项（105+201+33）0 失败（RecoverySessionTests 增 4 例、RecoveryBoundaryConsistencyTests planner 断言同步）；CLI `--self-test` 302 项 0 失败；Release 构建并安装 `/Applications/Automnt.app`；`verify-signature.sh` 5 项 PASS；`verify-localization.py` PASS（267 条源字符串 × 9 语言）；`verify-swift6-concurrency.py` 通过。

# 未验证项

- 真实“注销再登录”轮未做：沙盒读不到 utmpx，边界不刷新（已验证限制），不是新缺陷（T138 仍不勾选）。
- 真实重启前处于 suppressed 状态的清除未直接观测；本轮用等价模拟覆盖同一代码路径。
- 真实登录项启动（launched-at-login）已实测无 Dock 图标、菜单栏常驻，但菜单栏菜单真实点击、VoiceOver、浅色/较大文字与九语审校仍未验证（T141）。
- 菜单栏菜单真实点击、VoiceOver、浅色、较大文字与九语母语审校（T141）。
- T140 真实后台失败端到端通知仍与本缺陷独立，未验证。
