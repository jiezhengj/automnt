本文记录 2026-10-23 第三轮对“App Sandbox 下谁来执行 NetFS 挂载”的实测结论与替代方案：三次子进程实验、失败原因、改为调用进程内执行的设计与取舍、沙盒健康语义，以及尚未解决的失败通知问题。本文只记录设计与证据，不代表全部验收通过；未验证项见文末。

# 问题

缺陷 A（argv 推导）与 B（helper 内 SMAppService 查询）修复后，后台 helper 能定位 app bundle、通过就绪判定，但挂载动作本身仍由 helper 派生的 `AutomntWorker` 子进程执行。沙盒 helper 在进程内可以直接挂载成功，子进程却必然失败，导致整轮后台评估无法产出真实挂载。因此需要回答：App Sandbox 下挂载动作应该在哪里执行。

# 三次子进程实验

沙盒 helper 自身在进程内用 NetFS 复用 macOS 已保存的 SMB 登录，可连续挂载成功（本轮连续 3 次 status:0，实测挂载 `/Volumes/finalhome`、`/Volumes/personal_folder`）。以此为前提，对 worker 子进程尝试三种沙盒配置：

## 实验一：inherit 子进程（app-sandbox + inherit）

- 配置：仅 `com.apple.security.app-sandbox` 与 `com.apple.security.inherit`，继承父进程沙盒。
- 现象：子进程没有自己的网络客户端授权，NetFS 调用被拒，返回 authorizationRequired。
- 结论：inherit 不能补上网络授权，无法复用系统 SMB 登录完成挂载。

## 实验二：inherit 子进程 + network.client

- 配置：在实验一基础上增加 `com.apple.security.network.client`。
- 现象：内核/containermanager 初始化卡住或崩溃，secinit 报 container/persona 问题；进程 30s 挂起后被父进程杀掉，未进入挂载代码。
- 结论：inherit 与 network.client 组合在启动阶段即失效，不可用。

## 实验三：独立沙盒子进程（app-sandbox + network.client + 固定目录例外）

- 配置：子进程使用自己的沙盒 profile，包含 app-sandbox、network.client 与固定配置目录的 home-relative 例外。
- 现象：内核报 `deny(1) forbidden-sandbox-reinit`，进程 SIGTRAP 崩溃；崩溃报告 asiSignatures 明确记录该拒绝。
- 结论：沙盒进程不能再为自己的子进程重新初始化沙盒，App Sandbox 明确禁止这条路径。

# 结论

- App Sandbox 下“可强杀的子进程负责挂载”不可实现；NetFS 挂载必须由沙盒 helper/App 自身进程执行。
- 这不是实现疏漏，而是平台约束：三种子进程方案分别缺授权、启动崩溃、内核拒绝，没有可用组合。
- 该结论同时解释了为什么此前“父进程等子进程退出码”的 worker 纪律无法在沙盒形态下继续沿用。

# 替代方案：调用进程内执行

## 改动

- 新增 Sources/AutomntPlatform/MountExecutionService.swift：把原 worker 的挂载/弹出/健康/清理逻辑移入平台层，在调用进程内执行。
- Sources/AutomntPlatform/MountWorkerRunner.swift 改为进程内执行：不再 `Process` 派生 AutomntWorker，改为直接调用 MountExecutionService；仍保留 `WorkerOperationStore.begin`（:67）、响应校验（:71）、完成策略（:73）、`store.complete`（:77），并以 BundledCodeVerifier 校验嵌套 AutomntWorker 代码封印（:63）。
- apps/Automnt/Service/HelperEntry.swift:83 启动时调用 `abandonPendingForRepair()`：仅在能取得 evaluation.lock 时清除遗留 pending，取不到锁则保守失败。
- App 侧手动弹出等入口同样经 MountWorkerRunner，因此自动与手动操作共用同一进程内执行路径。

## 保留的纪律

- 先落盘意图（WorkerOperationStore），再执行；执行前重读配置并核对 revision/generation/permit；只有通过校验的响应才允许 complete。
- 超时、被杀或异常留下 pending，由下一次 repair 处理；不允许失败观察冒充完成。
- deadline 仍从请求的 `expiresAtUptime` 推导（上限 30s），保持有界。

## 取舍

- 失去强杀隔离：进程内执行无法像子进程那样被父进程超时强杀；卡在系统调用时只能依赖有界 deadline、短命 helper 退出与下次调度。当前设计假设 NetFS 调用可被 deadline 约束，**该假设未验证**。
- 换取可用性：只有进程内执行能复用系统 SMB 登录完成挂载，这是产品核心能力的前置。
- AutomntWorker 二进制保留为嵌套代码封印（仍被嵌入并校验），当前不再被 spawn；保留它是为了让封印校验与签名门禁保持连续，清理它属于后续可选项，清理前必须同步修改封印校验与签名门禁。

# 沙盒健康语义

- App Sandbox 进程挂载网络卷后，读取卷内容会被拒绝（EACCES/EPERM）；这是沙盒策略，不是服务器失败。
- Sources/AutomntPlatform/VolumeHealthWorkerOperation.swift:34-40：挂载身份已由内核挂载表核验、`opendir/readdir` 返回 EACCES/EPERM 且本进程带 app-sandbox 权限时，判为 healthy。
- 内容可读性由用户自己的非沙盒应用验证（本轮一次性观察 `ls` 正常）；沙盒 GUI/helper 不以“能读文件”作为健康证据。
- CLI 不在此路径，仍严格校验，不因该语义放宽。

# 通知投递同受沙盒限制

- helper 没有通知身份，原先经 `AppNotificationDelivery`（Sources/AutomntPlatform/NotificationChannel.swift:186）派生 App 主可执行文件投递；这与 worker 子进程同属“借用 App 身份”的沙盒子进程路径。
- 2026-10-23 第四轮实测：派生 App 主可执行文件被内核以 `forbidden-sandbox-reinit` 拒绝，产生 Automnt crash 报告（与 22:10/22:11 的子进程实验同批），helper 无法自行投递。结论与挂载一致：沙盒下所有“借用 App 身份”的路径都不可用。

# 方案 A：helper 记录、常驻 App 投递（维护者 2026-10-23 选定）

- 维护者选择方案 A，并接受由此产生的界面依赖：想要后台失败通知，就必须让 App 在登录时运行并常驻菜单栏图标；反向不要求——菜单栏图标可以常驻而通知关闭或被系统拒绝。这是单向依赖，界面必须把“意图 vs 实际”说清楚。
- 实现：Sources/AutomntPlatform/PendingNotificationStore.swift 单槽位 `pending-notification.plist`（count、soundEnabled、soundPreferenceNeedsRepair、createdAt；10 分钟过期丢弃，不重写业务配置）；helper 只写 pending、只报告边界；常驻 App 通过 apps/Automnt/AutomntApp.swift:1424-1456 的 20 秒投递循环读取、删除、过期丢弃，再经 `AppNotificationDispatcher` 投递并写 `notification-delivery.plist`。
- 取舍：得到“后台失败仍能通知”的能力，代价是常驻进程、菜单栏图标与登录项；App 被退出或未设登录项时后台不通知（明示限制），但自动挂载照常。菜单栏图标是常驻进程的唯一可见入口，其窗口/菜单/辅助功能验收单列（T141）。
- 未验证：真实后台失败 → pending → 常驻 App 20 秒内投递的端到端链路（T140）、登录项启动（窗口抑制）后投递循环运行、系统拒绝/paused/前台抑制/10 分钟过期在真实链路的行为、登录项关闭确认与九语母语审校（菜单栏图标的关闭确认已在第五轮实测）。App 身份 `--deliver-notification --count 1` 实测只证明 App 能投递，不证明该链路。
- 其他备选（未采用）：B. 接受后台无通知，仅保留状态与下次打开提示；C. 其他渠道级方案（需重新审阅渠道、审核风险与隐私说明）。

# 实测证据与门禁

- GUI 未运行，仅 `launchctl kickstart` 触发 recovery/baseline：两卷成功挂载；background-observations.plist 两卷 status=healthy。
- 手工 `diskutil unmount` 产生“本会话已弹出”抑制、同会话不再自动挂载，符合既有会话抑制设计；重启后是否清除未验证。
- `swift test` 330 项测试、83 个 suite 全通过（100+197+33）；CLI `--self-test` 302 passed/0 failed；verify-localization.py、verify-swift6-concurrency.py 通过；verify-signature.sh 对安装于 /Applications/Automnt.app 的构建 PASS（app/helper/worker/bundle）。
- 安装状态：/Applications/Automnt.app 已替换为本轮构建；recovery agent 已注册启用，baseline 按互斥设计未注册/未运行（预期）。
- 第四轮补充：`swift test` 335 项（105+197+33）、0 失败；Release 构建 BUILD SUCCEEDED 并已安装；`verify-signature.sh` 5 项 PASS；Swift 6 与本地化门禁通过（269 条源字符串 × 9 语言）；helper 探针输出 `bundleID=foreignIdentity("org.automnt.automnthelper")`、`helper-delivery=unsupported-by-design`、`delivery-owner=app-when-running`、exit 0；App 身份 `--deliver-notification --count 1` → `delivery=delivered reason=posted count=1`（仅证明 App 能投递）。

# 未验证项

- 真实重启与真实重新登录后的自动挂载、会话抑制清除、单 owner：未执行（T138）。
- 失败通知端到端链路（真实后台失败 → helper 写 pending → 常驻 App 20 秒内投递 → 记录去重）：未验证（T140）；登录项启动（窗口抑制）后投递循环运行、系统拒绝/paused/前台抑制/10 分钟过期在真实链路的行为同样未验证。
- 常驻菜单栏 App 的真实窗口/菜单交互、关闭菜单栏/登录项的确认弹窗、VoiceOver、浅深色、较大文字与九语母语审校：未验证（T141）。
- GUI 运行期交互（打开窗口、手动检查/挂载/弹出、状态显示）：本轮构建未验收。
- 进程内执行在 NetFS 卡死时的 deadline 行为：未验证；当前仅有设计假设与短命 helper 缓解。
- 沙盒内容读取限制下“用户应用可读写”只做了一次性 `ls` 观察，未纳入正式验收矩阵。
- App Store 渠道、菜单栏常驻形态与商店审核接受性：未验证。
