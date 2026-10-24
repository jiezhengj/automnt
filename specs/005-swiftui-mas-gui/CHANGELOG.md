# 用途

本文件保存 Feature 005 的授权与逐轮验收历史。此前这些内容被逐轮追加进 `AGENTS.md` 的“Feature 005 当前授权”条目，单条达到 1.2 万字符、占该文件一半以上，导致每次会话都要加载大量历史。现在 `AGENTS.md` 只保留稳定规则与一行现状摘要；新的逐轮记录写在本文件。

# 历史记录（2026-10-12 至 2026-10-24，原文迁出）

**Feature 005 当前授权（2026-10-12 更新，本轮纠正优先）**：维护者先要求修订全部相关文档与 demo（2026-10-11），随后授权“继续 Implement”。因此已按新设计完成**本地**应用/CLI 代码实现、构建、签名与门禁验证，并已撤销自行增加的独立密码管理、八步向导、多选添加、普通用户 CLI 导入/检查和内部配置目录选择。仍未授权且未执行：对外推送、GitHub Release、商店提交、版本号递增。**不得**用可编译 demo、单元测试或本地门禁代替真实应用、系统认证、共享配置、后台恢复与真实窗口交互的运行验收（这些仍待实测）。后续恢复完整实施时仍优先已有免费 Apple Development 身份，付费账号不能成为完整界面实施的前置。2026-10-20 维护者明确授权将 Feature 005 完整推送 GitHub 并发布新 Release；版本由 3.3.2 按 MINOR 晋级为 3.4.0。
  - **Feature 005 当前范围（2026-10-13，保留方案 A 架构，撤回目录选择例外）**：维护者要求先逐项审计未修复反馈并修订文档；本轮只更新规格、设计、任务与审计记录，不修改应用/CLI 代码、图标或原型资产，不构建或发布。正常首次使用、设置访问、CLI 共用和权限恢复均不得要求用户识别内部配置路径或通过 Finder 式面板选择配置文件夹；此前方案 A 的固定目录面板例外撤回，不能只隐藏应用内路径而仍让用户选择目录。真实资源许可仅在需要时使用相应系统机制，普通应用 Alert 不产生沙盒文件访问权限。保留现有 CLI 的唯一活动配置与单后台 owner；若免目录选择方案需要迁移、改变 CLI 签名/访问协议或发行渠道，先记录影响，不擅自实施或建立平行配置。当前目录面板代码和 290 项测试/签名构建是历史实现证据，不代表新要求通过；独立 helper、GUI 退出/真实登录/重启与九语原生体验仍待实证。后续实施以最新规格为准；版本号递增、提交推送、Release 和商店提交仍未授权。
  - **Feature 005 完成（2026-10-22）**：维护者确认 Feature 005 完成。GUI 最终布局见 `specs/005-swiftui-mas-gui/design/interaction-architecture.md`；GUI 源码按 MIT 开源、可自行编译，不随 GitHub Release 分发（见 `release/RELEASE_POLICY.md`）。未验证项（浅色、较大文字、VoiceOver、九语母语审校、真实后台/App Store 沙盒与商店提交）以 `specs/005-swiftui-mas-gui/spec.md` 的 Status 为准，不因“完成”而视为已通过。后续 GUI Feature 按 `docs/gui-interaction-principles.md` 重新推导布局。
  - **Feature 005 重开（2026-10-23）**：维护者要求重新打开 Feature 005，修复后做完整收敛与验收。2026-10-23 实测确认两个真实缺陷：①bundled LaunchAgent 以相对 `BundleProgram`（`Contents/Helpers/AutomntHelper`）启动，launchd 传入的 argv[0] 是相对字符串，helper 在 `apps/Automnt/Service/HelperEntry.swift:56` 反推 app bundle，而沙盒 cwd 为 `~/Library/Containers/org.automnt.automnthelper/Data`，导致 applicationURL 错误、bundle identity 校验失败、退出码 1（该轮触发 3 次，未写状态、无挂载、无通知）；②即使修正 argv，helper 进程内 `Bundle.main.bundleURL` 为 `Contents/Helpers/`、`SMAppService.agent(plistName:)` 返回 error 22，被误判为待批准后退出，不评估不挂载，而 App 进程内查询正常，界面可能仍显示后台已开启。因此 2026-10-22 的“完成”只对界面交互与本地工程成立，不涵盖后台跨登录/重启自动挂载；旧结论不删除，但不再作为该能力的通过依据。修复方向已裁定：helper 不再从 argv[0] 反推 app bundle，改用自身可执行文件绝对路径向上定位并校验 `.app`；helper 就绪判定改为“固定 LaunchAgent 定义校验 + launchd 期望身份（`XPC_SERVICE_NAME`）+ 已提交 backend-state（owner=app、phase=active、lastVerifiedServiceStatus=enabled、generation）”，App 仍以 SMAppService 为真实状态源并保持两服务互斥。第一轮只更新文档（`specs/005-swiftui-mas-gui/spec.md`、`tasks.md`、`contracts/background-service.md`、`design/2026-10-23-helper-readiness.md`、`release/offline/known-limitations.zh.md`/`.en.md` 与本文件）。

**第三轮（2026-10-23 晚）结论**：继续实测确认缺陷 C——App Sandbox 下 worker 子进程无法执行 NetFS（inherit 无网络授权→authorizationRequired；inherit+network.client→secinit container/persona 卡死 30s 被杀；独立沙盒→`deny(1) forbidden-sandbox-reinit` SIGTRAP），即“可强杀子进程负责挂载”不可实现。已按裁定本地修改代码：新增 `Sources/AutomntPlatform/MountExecutionService.swift` 在调用进程内执行挂载/弹出/健康/清理；`Sources/AutomntPlatform/MountWorkerRunner.swift` 不再 spawn `AutomntWorker`，保留 `WorkerOperationStore` 意图/`EvaluationPermit`/revision-generation 与响应校验，`AutomntWorker` 二进制仅保留为嵌套代码封印；`apps/Automnt/Service/HelperEntry.swift:83` 启动时在可取得 evaluation.lock 时清除遗留 pending；沙盒健康语义改为“挂载身份已核验 + opendir/readdir 返回 EACCES/EPERM + 本进程带 app-sandbox”判 healthy（`Sources/AutomntPlatform/VolumeHealthWorkerOperation.swift:34-40`，CLI 不放宽）。已重建签名构建并安装 `/Applications/Automnt.app`，`swift test` 330 项/83 suite、CLI `--self-test` 302 项、本地化/Swift 6/签名门通过；recovery agent 注册启用，baseline 按互斥设计未注册。GUI 未运行时 `launchctl kickstart` 触发两卷挂载成功，background-observations.plist 两卷 status=healthy。**仍受限/未验证，不得写成已通过**：真实重启与重新登录后的自动挂载及会话抑制清除（T138）、失败通知投递（helper 经派生 App 可执行文件投递属同一沙盒子进程限制，方向待维护者决定，T137；第四轮已选定方案 A）、GUI 运行期交互、进程内执行在 NetFS 卡死时的 deadline 行为；沙盒进程无法读取已挂载网络卷内容属已确认限制（内容可读性由用户自己的非沙盒应用验证）；CLI 3.5.0 不受缺陷 A/B/C 影响，但本轮未安装 CLI 且 backend owner=app，CLI 后台自动挂载仍未验证。

**第四轮（2026-10-23 深夜，方案 A）**：维护者选定失败通知由常驻 App 投递、helper 只记录，并接受单向依赖——要后台失败通知，必须在登录时运行并常驻菜单栏图标；反向不要求（菜单栏可常驻而通知关闭/被拒）。沙盒下派生 App 借用通知身份已被 `forbidden-sandbox-reinit` 实测拒绝（Automnt crash 报告），helper 不再尝试投递。本地实现：新增 `Sources/AutomntPlatform/PendingNotificationStore.swift`（单槽位 `pending-notification.plist`：count、soundEnabled、soundPreferenceNeedsRepair、createdAt，10 分钟过期丢弃，不重写业务配置）；`apps/Automnt/Service/HelperEntry.swift` 改为 `recordFailureNotification`（只写 pending、失败仅日志），`--probe-notification-channel` 报告 `helper-delivery=unsupported-by-design`/`delivery-owner=app-when-running` 并 exit 0；`apps/Automnt/AutomntApp.swift:1424-1456` 增加 `bootstrapResidentServices()` 与 20 秒投递循环（`AppNotificationDispatcher`，写 `notification-delivery.plist`），并在 `init()`（:1632）启动，因为登录项启动会抑制主窗口；`apps/Automnt/Views/DetailViews.swift` 设置界面补齐依赖链说明、前置条件、禁用态、警示与关闭确认（菜单栏/登录项），菜单栏退出前说明退出后不再通知；九语文案为草稿。

**2026-10-24 第五轮文案收敛**：按 agy 全量九语审计与维护者批准执行——通知卡片改为“收益句 + 通知权限行 + 单一前置条件块 + 单一动作”五态，删除长依赖句、重复警告与双按钮；第二个开关改名 `Open Automnt at Login`（登录时打开 Automnt）；关闭确认标题改为对应用户动作，正文说明退出后通知停止、自动挂载继续；菜单栏下拉菜单移除 `Hide Menu Bar Icon`；同批修复路径 `..` 粘连、fr 漏译 sign in、CLI 冲突提示、权限状态值、Background Mounting 误译、zh-Hant/ja 术语分裂与德语通知区 du/einbinden。门禁：本地化 267 条 × 9 语言、Release 构建安装、签名 5 项、Swift 6 通过；本机已实测（macOS 27、简体中文、深色）：设置窗口真实打开；通知区“已允许未常驻”显示收益句/权限行/单一原因/“在登录项中开启”；菜单栏图标开关与关闭确认弹窗真实点击（标题“从菜单栏隐藏 Automnt？”、正文、关闭/取消），关闭后图标移除且开关复原；菜单栏菜单项经辅助功能读取，含“退出后…”说明且已无 Hide 项。九语仍为草稿；登录项批准与常驻启动、菜单栏菜单真实点击、VoiceOver/浅色/较大文字/九语审校未验证（T141）。验证：`swift test` 335 项（105+197+33）0 失败、Release 构建并安装 `/Applications/Automnt.app`、`verify-signature.sh` 5 项 PASS、Swift 6 与本地化门禁通过（第五轮后 267 条源字符串 × 9 语言）、helper 探针如上、App 身份 `--deliver-notification --count 1` → delivered/posted/count=1（仅证明 App 能投递）。**未验证，不得写成已通过**：真实后台失败 → pending → 常驻 App 20 秒内投递的端到端链路（T140）、登录项（窗口抑制）启动后投递循环运行、系统拒绝/paused/前台抑制/10 分钟过期在真实链路的行为、菜单栏常驻后的真实窗口/菜单/VoiceOver/浅色/较大文字/九语审校（T141）；登录项当前未启用（`menuBarEnabled` 为 false、`SMAppService.mainApp` 未注册），重启后默认无常驻 App 与后台通知（自动挂载不受影响），验收需手动开启“Show Automnt in the Menu Bar”与“Open Automnt at Login”（第五轮改名）。

**2026-10-24 第六轮（重启后未挂载 + Dock 行为修复）**：2026-10-24 02:00 真实重启登录后两卷未自动挂载（`mount | grep smb` 为空；recovery agent runs=3、最后退出码 0；background-observations.plist 两卷 status=suppressed、retrySuggested=false；mount-recovery-state.plist 两卷 attached 且修复前无 session_boundary 键）。新增 `AutomntHelper --probe-session` 证实沙盒 helper 读不到 utmpx（`utmpx-console-records=0`、`login-epoch=unreadable`、`session=unavailable`，network-identity/boot-time 可读），旧 `loginEpoch()` 返回 nil 使 session_boundary 从未写入，跨重启旧 attached 被恢复判定当成健康弹出（healthyEject→sessionSuppressed）而跳过自动挂载。本地修复（未提交/未推送/未递增版本）：`Sources/AutomntPlatform/RecoverySessionCollector.swift:47-50` 在 console 不可读时退回 boot time（`sysctl KERN_BOOTTIME`，:53-59）返回 `<boot>-console-unreadable`，仅 boot 不可读才 nil；`Sources/AutomntCore/RecoverySession.swift:34-50` 的 establishing 分支把陈旧 `.attached` 改为 `.pendingRecovery` 并清零 attempt/notification 计数、`.suppressed` 保留并绑定新边界，`:24-33` 增加“同 boot + 同 network 仅为 console 可读性差异，不算新会话、不改写边界、不清抑制”保护；Dock 行为：`apps/Automnt/Resources/Info.plist:16-17` 设 `LSUIElement=true`，`apps/Automnt/AutomntApp.swift:10,23-43` 由 `DraftTerminationDelegate` 按“可见 titled 普通窗口”在 regular/accessory 间切换，`:48-50` `applicationShouldTerminateAfterLastWindowClosed = !menuBarEnabled`。证据：修复后探针 `login-epoch=readable`、`session=available`；02:09 kickstart 后两卷挂载、observations 两卷 healthy、state 写回 session_boundary/volumes=attached；02:16 与最终构建 02:19（observations 写入 02:19:31） 各做一次模拟重启（diskutil unmount → 伪造旧边界 `old-network|1700000000-old-console`、attached、attempt_count=2 → kickstart），两卷重新挂载并回到 attached/attempt_count=0、session_boundary 更新为当前 `<network>|1792778275-console-unreadable`；最终安装构建真实 UI（macOS 27、简体中文、深色）有窗口时 `background only=false`（regular、有 Dock 图标）、全部关窗后 `background only=true` 窗口 0 且菜单栏图标 1（无 Dock 图标）、从菜单栏重开窗口后恢复 regular。门禁：`swift test` 339 项（105+201+33）0 失败、CLI `--self-test` 302 项 0 失败、Release 构建并安装 `/Applications/Automnt.app`、`verify-signature.sh` 5 项 PASS、`verify-localization.py` PASS（267 条源字符串 × 9 语言）、`verify-swift6-concurrency.py` 通过。

**2026-10-24 19:00 真实重启验收（通过）**：boot 1792839587（18:59:47）；登录项 19:00:23 启动 App（0 窗口、`background only=true` 无 Dock 图标、菜单栏图标 1）；recovery agent runs=2、退出码 0；无人工操作下两卷自动挂载，19:02:11 observations 两卷 healthy；state session_boundary=`<network>|1792839587-console-unreadable`、attached/attempt_count=0；backend owner=app/active、worker-operation pending=false、无第二 helper；`ls` 可读；无新增崩溃报告。附加等价验证：同会话 diskutil unmount 后 kickstart 不挂载（suppressed，符合设计）；伪造旧边界后 kickstart 两卷重新挂载、healthy。**仍未验证/不得写成已通过**：真实“注销再登录”轮（沙盒限制：同 boot 边界不刷新，属已记录限制）、真实重启前 suppressed 状态的清除未直接观测（仅等价模拟）、T140 真实后台失败端到端通知、T141 菜单栏真实点击/VoiceOver/浅色/较大文字/九语审校；沙盒读不到 utmpx 属已确认限制——同一 boot 内“退出登录再登录”不会刷新会话边界（只有重启会），该会话弹出抑制持续到重启，可用界面中的“立即尝试自动挂载”或对单个共享“挂载/重试”恢复（已写入 known-limitations）。本轮未提交、未推送、未发布、未递增版本号。

**2026-10-24 第七轮（T140 端到端通知与 T141 验收项修订/执行）**：为闭合验收，经产品 UI 临时添加不存在的共享触发真实失败，暴露并修复两个真实缺陷：①确定性挂载失败后 `MountWorkerRunner` 的 launch intent 仍为 pending，`RecoveryAttemptCommit.rejected`/`RecoveryNotificationPolicy.commit` 的 `verifyIdle()` 抛 `signalUnavailable`，失败观测与通知被吞；修复为 catch 分支在非 timeout/pathConflict/signalUnavailable 时完成 intent（`Sources/AutomntPlatform/MountWorkerRunner.swift`）。②常驻 App 投递循环 weak self，引导实例被 SwiftUI 替换后空转，pending 生成 60 秒仍不被消费；修复为强引用 `residentServicesOwner` + 单 owner 保护（`apps/Automnt/AutomntApp.swift`），启动/投递各留 `NSLog`。最终安装构建实测：真实 shareRejected → 观测 failed + `pending-notification.plist` → 常驻 App 17–22 秒内投递，`notification-delivery.plist`=`delivered`/count=1，系统横幅“Automnt：自动恢复未完成 / 1 个共享文件夹未能自动挂载。请打开 Automnt 查看详情。”；前台另测 `suppressedForeground`。T141 按维护者指示把 Agent 绝对做不到的四项改为可执行等价验收并执行：真实注销/登录 → 真实重启轮 + 同 boot 边界保留/幂等重触发 + 限制文档化；母语审校 → 本地化门禁 + 九语真实启动核对；VoiceOver 朗读 → 辅助功能树审计并记录缺口；系统“较大文字” → 窄/宽窗与长译文截图 + 限制。已实测菜单栏真实点击（打开/设置/立即检查）、浅深色切换、九语真实启动渲染、GUI 内弹出/挂载、设置窗口。门禁：`swift test` 339 项 0 失败、CLI `--self-test` 302 项、Release 构建安装、签名 5 项、本地化 267×9、Swift 6 通过；临时共享与派生状态已清理，`automnt.plist` SHA-256 恢复 `911ed030…5808e16`。新增未完成项：T143 共享行/图标可访问名称（辅助功能审计发现）；T144 人工/母语者验收（母语审校、VoiceOver 听感、较大文字矩阵、真实注销登录）。本轮未提交、未推送、未发布、未递增版本号。

**2026-10-24 第八轮（T143/T144 闭环，维护者授权 Lead + agy 代理验收）**：①审计方法纠正——第七轮 System Events 读不到 SwiftUI 的 `AXTitle`/`AXDescription`，误判共享行按钮/开关/链接无名；改用本机 `AXUIElement` 审计确认共享行按钮/开关/链接与菜单栏图标均有名称，真实缺口为服务器页开关与设置窗口 5 个开关（自动挂载、自动恢复、在菜单栏中显示、登录时打开、通知声音）及 Spotlight 开关/尝试次数 Stepper 只有 AXValue。②修复：`apps/Automnt/Views/MainWindowView.swift`、`apps/Automnt/Views/DetailViews.swift` 为 8 个控件（服务器页 1 个开关、设置窗口 6 个开关与 1 个步进器）补 `.accessibilityLabel(Text(现有本地化 key))`，不新增文案、不改布局；重建安装后同一审计产品控件无名数为 0（剩余为系统窗口按钮/滚动条/菜单分隔项）。③VoiceOver 真实开启并用 VO 键导航，旁白字幕面板读出“此服务器参与自动挂载…”“已管理”“finalhome, 可用 按钮 …”“personal_folder … 开关按钮 …”，截图 `specs/005-swiftui-mas-gui/evidence/2026-10-24/voiceover-spoken-captions.png`。④系统“文字大小”滑块（默认 4→6）对 App 无效（不在支持列表内，动态字体未采纳，列改进项），改用显示器 1024×666（更大文字）截图验证布局可读并还原 1470×956。⑤九语代理审校：agy 全量审校 460 条 × 9 语（`evidence/2026-10-24/agy-nine-language-review.txt`），本机核对现值后应用 24 条高置信修订（fr/es 从句、de Einbindung/freigegeben、pt-BR Ajustes、ja 復旧、zh-Hant 檔案夾/圖示/復原、zh-Hans 句式、ko 하세요），本地化门禁 267×9 通过，真机 ja 抽查一致（`copy-fixes-applied.txt`）；未应用的人称/术语统一留维护者裁定。⑥真实注销/再登录仍不可执行（注销终止会话），以 19:00 真实重启轮为等价证据。证据汇总 `evidence/2026-10-24/t144-proxy-acceptance.txt`。门禁：`swift test` 339 项、CLI `--self-test` 302 项、本地化 267×9、Swift 6、签名 5 项 PASS、Release 构建安装 `/Applications/Automnt.app`。本轮未提交、未推送、未发布、未递增版本号。

**2026-10-24 深夜（第九轮，文案与文字大小裁定）**：维护者要求“你和 agy 讨论后确定”两项遗留。①九语人称/术语：以 Apple 自带本地化核对修正 agy 两处建议——德语系统设置实际用 du（“Personalisiere den Mac so, wie es für dich am besten funktioniert …”），目标语气为 du 而非 Sie；登录项面板以 `LoginItems.appex` 本地化为准（fr « Ouverture »、es «Ítems de inicio »、de “Anmeldeobjekte”）。已应用 63 处机械且语义安全的译文统一（de freigegeben/einbinden/Befehlszeile、pt-BR Ajustes 与 iniciar a sessão、ja 独立名词 App 与网络復旧、ko 하세요/세부사항、zh-Hant 檔案夾/回復、fr/es 登录项名称、大小写重复 key 对齐；zh-Hans App/应用 因多为动词不改）；德语 du/Sie 逐句重写约 60 条，记为润色项，不新增 Feature 任务。②动态字体：系统“文字大小”面板不含 Automnt、滑块无效，未找到第三方注册入口（未验证 Apple 是否有限开放），自建缩放无法进入系统面板且破坏九语窄窗风险高；裁定**不单开任务**，记为平台限制与未来候选，替代为显示器“较大文字”缩放（1024×666 实测可读并还原）。记录 `specs/005-swiftui-mas-gui/design/2026-10-24-copy-and-text-size-decisions.md`，证据 `evidence/2026-10-24/copy-decisions-round8b.txt`；本地化门禁 267×9 通过、Release 重建安装、签名 5 项 PASS、真机抽查 de “Automatisches Einbinden”、ja “自動マウントと自動復旧が実行中です。”、pt-BR “Ajustes de Automnt”。本轮未提交、未推送、未发布、未递增版本号。

**2026-10-24 深夜（第十轮，完成收口与德国语气统一）**：维护者接受“真实注销/登录以重启轮 + 同 boot 边界等价”的结论；确认动态字体“不再支持这个需求”（不列为改进、不以改显示器分辨率代替）；要求德语 du/Sie 由 Lead 与 agy 一起完成；要求修订 T133/T134 与 Status 后收口。执行：agy 对 67 条含敬称德语文案逐条改写，本机校验 key/占位符后应用 65 条，剩余 3 处 Sie 为第三人称指代（Adresse/Reihenfolge/Einstellungen），真机德语设置页确认无 Sie 形式；动态字体在 known-limitations 与 spec 中改为“已记录边界、非已支持、不设替代”；tasks.md 的 T133 按等价标准（真实重启 + 端到端失败通知 + 运行期界面 + 注销等价证据 + 单 owner）改为通过并勾选，T134 文档收敛并勾选；spec.md 增加“完成结论（2026-10-24，第十轮）”，保留真实注销/登录（等价标准）、动态字体（不支持）、App Store/推送/Release/版本递增（未授权）为边界。门禁：本地化 267×9、`swift test` 339、CLI `--self-test` 302、Swift 6、签名 5 项 PASS、Release 构建安装。本轮未提交、未推送、未发布、未递增版本号。

# 迁出说明

- 2026-10-24：历史原文整体迁入本文件，未改写；其中各轮结尾的“本轮未提交/未推送/未递增版本号”是各轮当时的状态，不代表当前状态。
- 当前能力、未验证项与完成边界以 `spec.md` 的 Status 与“完成结论（2026-10-24，第十轮）”为准。

# spec.md 重开与逐轮记录（2026-10-23 至 2026-10-24，原文迁出）

# 2026-10-23 重开与验收修正

2026-10-23，维护者要求重新打开 Feature 005，修复并做完整收敛与验收。本次重开只针对后台自动挂载能力，不推翻已通过的界面交互验收；界面布局、宽窄窗、推送/返回、sheet 与设置窗口的真实窗口证据（截图 39–44）继续有效，本次不重做界面。

## 现象

- 2026-10-23 19:04 用户登录后，系统按 RunAtLoad 触发 bundled recovery 后台任务，同一轮内实际触发 3 次（runs=3，最后一次退出码 1）。
- 该轮没有任何后台状态写入、没有共享被挂载、也没有投递失败通知。
- 对比 App 进程内查询正常（baseline=notFound、recovery=enabled），界面仍可能显示“自动挂载：运行中”。
- 用户可见后果：Mac 重新登录或重启后，配置好的共享不会自动出现，文件任务仍会先报错——产品核心承诺（登录/重启后自动挂载）当前不成立。

## 根因 A：helper 从 argv[0] 反推 app bundle 失败

- bundled LaunchAgent 用 `BundleProgram = Contents/Helpers/AutomntHelper`（apps/Automnt/Resources/LaunchAgents/automnt.baseline.plist:5、automnt.recovery.plist:5、automnt.authorization.plist:5），launchd 传给 helper 的 argv[0] 是这个相对字符串，而不是可执行文件的绝对路径。
- helper 在 apps/Automnt/Service/HelperEntry.swift:56 用 `URL(fileURLWithPath: CommandLine.arguments[0])` 反推自身路径，并在 :57 连续三次 `deletingLastPathComponent()` 推导 app bundle。
- 沙盒进程的工作目录实测为 `~/Library/Containers/org.automnt.automnthelper/Data`，相对 argv[0] 因此被解析到容器内不存在的路径，推导出的 applicationURL 错误。
- 结果：apps/Automnt/Service/HelperEntry.swift:59-60 的 bundle identity 校验（要求可执行文件名为 AutomntHelper、bundle identifier 为 `org.automnt.automnt`）必然失败，helper 以退出码 1 结束，未进入评估。

## 根因 B：helper 进程内无法用 SMAppService 判定服务状态

- 即使修正 argv，helper 进程内实测 `Bundle.main.bundleURL = /Applications/Automnt.app/Contents/Helpers/`，即落在 Helpers 目录而不是 app bundle 根。
- helper 内查询 `SMAppService.agent(plistName:)`（Sources/AutomntPlatform/ServiceController.swift:16）返回 error 22（Unable to find service status），拿不到 enabled 等真实状态。
- 就绪检查把“非 enabled”统一映射为 `backgroundApprovalRequired` 并退出（Sources/AutomntPlatform/BackgroundEvaluationTrigger.swift:53），因此不评估、不挂载。
- 后果是状态分裂：App 进程认为后台已开启，真正执行挂载的 helper 却认为未获准。界面显示不能作为后台可用的证据。

## 修复方向

- helper 不再从 argv[0] 推导 app bundle：改用自身可执行文件的绝对路径向上定位 `.app`，并继续校验 bundle identity（bundle identifier 与 helper 可执行文件名）。
- helper 的就绪判定不依赖 SMAppService，改为三组证据同时成立：解析后 app bundle 内固定 LaunchAgent 定义校验（固定 Label、`BundleProgram`、无 `Program`/`ProgramArguments`、模式与配置期望一致）；launchd 期望身份（`XPC_SERVICE_NAME` 与配置期望的服务模式一致）；已提交 backend-state（owner=app、phase=active、`lastVerifiedServiceStatus=enabled`、generation 一致）。
- App 仍以 SMAppService 为真实状态源，负责注册、批准判断与展示；两服务互斥、单 owner、事件触发方式均不变。
- 任一组证据缺失时 helper 有界退出，写出结构化原因供 App 显示“待批准/未运行/无法确认”；不得用界面显示“运行中”代替真实可用性，也不得把未验证的判定写成通过。

## 验收定义

修复后必须同时满足以下条件，才算后台跨登录/重启自动挂载能力成立；单元测试、可编译或 GUI 在场时的挂载都不算：

1. 无 GUI 运行时，由 launchd 触发（登录、重启、网络或挂载事件）后，配置中启用的共享真实自动挂载。挂载身份由 helper/GUI 通过内核挂载表核验；内容可读性由用户自己的非沙盒应用真实读写确认（App Sandbox 进程无法读取自己挂载的网络卷，见“缺陷 C”，因此不得要求沙盒进程自己读文件来“证明可用”）。
2. 真实重启与真实重新登录后同样成立，不依赖 GUI 常驻、不依赖用户点击重试。
3. 失败时由常驻 App 投递系统通知（记录与投递分离）：helper 只写 pending 记录，App 在运行且权限允许时按既有合并与限额投递，成功后静默、不重复弹窗。App 未运行、被退出、未设为登录项或通知权限被拒/撤销时不发通知，这是明示的单向依赖（要后台失败通知 ⇒ 登录时运行并常驻菜单栏图标；菜单栏可常驻而通知关闭），不是缺陷。10 分钟过期记录不补发。
4. 任意时刻只有一个评估 owner：无第二 owner、无重复挂载、无第二常驻评估进程。
5. 每项记录实际签名身份、时间线、触发来源与证据；未执行或失败的项目如实标注，不合并成“已通过”。

## 缺陷 C：沙盒下 worker 子进程无法挂载（2026-10-23 第三轮）

- 沙盒 helper 自己在进程内用 NetFS 复用 macOS 已保存的 SMB 登录可以挂载成功：本轮连续 3 次 status:0，实测挂载 `/Volumes/finalhome`、`/Volumes/personal_folder`。
- 但 helper 派生的 worker 子进程无法完成同一操作，三种方案都失败：
  1. `inherit` 子进程（仅 app-sandbox + inherit）没有网络授权，NetFS 返回 authorizationRequired；
  2. `inherit` 子进程加入 `com.apple.security.network.client` 后，内核/containermanager 初始化卡住或崩溃（secinit 报 container/persona），进程 30s 挂起后被父进程杀掉；
  3. 子进程改为独立沙盒（app-sandbox + network.client + 固定目录例外）后，内核报 `deny(1) forbidden-sandbox-reinit`，进程 SIGTRAP 崩溃（崩溃报告 asiSignatures 明确记录）。
- 结论：App Sandbox 下“可强杀的子进程负责挂载”不可实现；NetFS 挂载必须由沙盒 helper/App 自身执行。这一结论与 worker 子进程的原有设计（可超时强杀）冲突，属于实际平台限制，不是实现遗漏。

## 修复方式（2026-10-23 第三轮，本地代码，未推送）

- 新增 Sources/AutomntPlatform/MountExecutionService.swift：把原 worker 的挂载/弹出/健康/清理逻辑移入平台层，在调用进程内执行；保留 WorkerOperationStore 意图记录、EvaluationPermit、revision/generation 与恢复提交纪律。
- Sources/AutomntPlatform/MountWorkerRunner.swift 改为进程内执行（:65 仍以 BundledCodeVerifier 校验嵌套的 AutomntWorker 代码封印，:66 `store.begin`、:68 调用 MountExecutionService、:70 响应校验、:71 完成策略、:75 `store.complete`），不再派生 AutomntWorker 子进程。
- apps/Automnt/Service/HelperEntry.swift:83 在启动时调用 `abandonPendingForRepair()`：仅在能取得 evaluation.lock 时清除遗留 pending，取不到锁则保守失败、留待修复。
- 沙盒健康语义：Sources/AutomntPlatform/VolumeHealthWorkerOperation.swift:34-40 在挂载身份已核验、opendir/readdir 返回 EACCES/EPERM 且本进程确带 app-sandbox 权限时判为 healthy；CLI 不在此路径、仍严格校验。
- AutomntWorker 二进制保留为嵌套代码封印（仍被嵌入并校验），当前不再被 spawn；这是现状，后续可清理，清理前需同步修改 seal 校验与签名门禁。

## 实测证据（2026-10-23 第三轮）

- GUI 未运行，仅 `launchctl kickstart` 触发 recovery/baseline 时，两卷成功挂载；background-observations.plist 两卷 status=healthy，说明进程内执行 + 沙盒健康语义在真实 launchd 上下文可用。代码路径已无子进程派生，但未额外以进程快照逐次复核。
- 手工 `diskutil unmount` 会产生“本会话已弹出”抑制，同会话不再自动挂载（符合既有设计）；重启后新会话边界应清除该抑制，本轮未执行真实重启，属未验证项。
- 门禁：`swift test` 330 项测试、83 个 suite 全通过（100+197+33，三次 Test run）；CLI 构建成功、`--self-test` 302 passed/0 failed；verify-localization.py、verify-swift6-concurrency.py 通过；verify-signature.sh 对安装于 /Applications/Automnt.app 的构建通过（app/helper/worker/bundle 全 PASS）。
- 安装状态：/Applications/Automnt.app 已用本轮构建替换；launchd recovery agent 已注册启用，baseline 按互斥设计为未注册/未运行（预期）。

## 未验证项（2026-10-23 第三轮）

- 真实重启与真实重新登录后的自动挂载：未执行（T138）。kickstart 触发不等于登录/重启事件验证。
- 失败通知投递：第三轮时 helper 通过派生 App 可执行文件（Sources/AutomntPlatform/NotificationChannel.swift:186 `AppNotificationDelivery`，`Process` 子进程）投递，与 worker 同属“沙盒子进程”限制；**2026-10-23 第四轮已实测**该派生被 `forbidden-sandbox-reinit` 拒绝（Automnt crash 报告），并按维护者选定的方案 A 改为 helper 记录、常驻 App 投递（见下文“失败通知：常驻 App 投递与单向依赖”）；端到端链路仍未验证（T140）。
- GUI 运行期交互（打开窗口、手动检查/挂载/弹出、状态显示）在本轮构建上未验收。
- 沙盒进程无法读取已挂载网络卷内容（同一沙盒原因）：GUI/helper 只能核验挂载身份，不能证明内容可读；用户自己的非沙盒应用可正常读取（实测 `ls` 正常）。这是已确认限制，不是待修缺陷。

## CLI 侧审计（2026-10-23，回答维护者追问）

- CLI 3.5.0 不共享缺陷 A/B/C：CLI 是非沙盒扁平单二进制，不派生 AutomntWorker 子进程，也不使用 SMAppService 查询后台服务状态，因此 A（argv 推导）、B（helper 内 SMAppService）、C（沙盒子进程挂载）都不适用于它。
- 但 CLI 后台自动挂载仍未验证：本轮构建未安装 CLI，且 backend owner=app，CLI 自己的后台注册与自动挂载矩阵未执行。不得把“CLI 不受 A/B/C 影响”写成 CLI 后台能力已通过。
- CLI 与 GUI 的内核调用实现仍按各自构建方式分置（CLI 不依赖 AutomntPlatform），修改任一处仍需同步核对另一处。

## 失败通知：常驻 App 投递与单向依赖（2026-10-23 第四轮，方案 A）

- 维护者决定（2026-10-23 晚）：失败通知由常驻 App 投递，helper 只记录；接受界面依赖——想要后台失败通知，就必须让 App 在登录时运行并常驻菜单栏图标。反向不要求：菜单栏图标可常驻而通知关闭或被系统拒绝。这是单向依赖，界面必须把“意图 vs 实际”表达清楚。
- 依赖链：后台失败通知 ⇒ App 登录时运行 ⇒ 菜单栏图标常驻。缺少任一环时，后台失败不通知，但自动挂载照常进行；界面需在设置中说明并给出开启入口，而不是把“已允许通知”当成“后台会通知”。
- 实现（本地代码，未推送）：`Sources/AutomntPlatform/PendingNotificationStore.swift:39-62` 单槽位派生状态 `pending-notification.plist`（count、soundEnabled、soundPreferenceNeedsRepair、createdAt；:16 有效期 600 秒，:34 过期判定；覆盖写、损坏/版本不符丢弃、删除；不重写业务配置）。`apps/Automnt/Service/HelperEntry.swift:99,116-131` 改为 `recordFailureNotification`，只做预算提交后写 pending 记录，失败仅写日志；探针 `--probe-notification-channel`（:146-152）报告 `helper-delivery=unsupported-by-design`、`delivery-owner=app-when-running` 并以 0 退出，不再尝试派生 App。`apps/Automnt/AutomntApp.swift:1424-1456` 新增 `bootstrapResidentServices()`（restore + 启动投递循环、:1436 每 20 秒）与 `deliverPendingNotification()`（读取→删除→过期丢弃→`AppNotificationDispatcher.dispatch`→写 `notification-delivery.plist`），并在 `init()` 的 GUI 路径调用（:1632），因为登录项启动时主窗口被抑制、窗口任务不会运行。
- 设置界面（apps/Automnt/Views/DetailViews.swift:796-808,894-1010）：通知区显示前置条件与“Show Automnt in the Menu Bar at Login”；未常驻时禁用“Allow Notifications…”并显示警示（:995）；关闭菜单栏/登录项且通知已允许时弹一次确认（:932-933 标题，正文说明关闭 App 后失败通知停止、自动挂载继续）；菜单栏“退出”前说明退出后不再通知（:1179）；“菜单栏与登录”说明同时解释通知依赖（:908）。 第五轮（2026-10-24）已改为：通知区五态单动作（无重复警告/双按钮）、开关改名 `Open Automnt at Login`、关闭确认标题对应用户动作、菜单栏下拉菜单移除 `Hide Menu Bar Icon`；详见 Status 第五轮段落。
- 文案：`apps/Automnt/Resources/Localizable.xcstrings` 新增/改写九语条目（en、zh-Hans、zh-Hant、ja、ko、de、fr、es、pt-BR），全部为草稿；`scripts/verify-localization.py` 报告 269 条源字符串 × 9 语言覆盖通过（含通知横幅九语），母语审校仍是独立未完成门禁。
- 证据（本轮已执行）：`swift test` 335 项（105+197+33）、0 失败；`xcodebuild Release` BUILD SUCCEEDED 并已安装 `/Applications/Automnt.app`；`scripts/verify-signature.sh` 5 项全 PASS；`verify-swift6-concurrency.py` exit 0；`verify-localization.py` PASS；helper 探针输出与退出码如上；App 身份投递实测 `/Applications/Automnt.app/Contents/MacOS/Automnt --deliver-notification --count 1` → `delivery=delivered reason=posted count=1`（系统弹出测试通知），仅证明 App 身份能投递，不代表后台失败链路已验证；App 正常启动无新崩溃日志（最新崩溃报告仍为 22:10/22:11 的子进程实验产物）。
- 未验证项：真实后台失败 → helper 写 pending → 常驻 App 20 秒内投递 → 记录去重的完整端到端链路（需真实共享被拒绝/挂载失败场景，本轮未制造）；登录项启动（窗口抑制）后投递循环真的运行（只验证了代码路径与 App 正常启动，未做真实重启/重新登录）；通知被系统拒绝、paused、前台抑制、10 分钟过期在真实链路中的行为；菜单栏常驻后的真实窗口/菜单交互、VoiceOver、浅深色、较大文字、九语母语审校；关闭菜单栏/登录项确认弹窗的真实点击路径。
- 登录项当前未启用（`menuBarEnabled` 未设置、`SMAppService.mainApp` 未注册），所以重启后默认不会有常驻 App 与后台通知；自动挂载不受影响。验收时需由用户手动开启“Show Automnt in the Menu Bar”和“Open Automnt at Login”（第五轮改名）。

## 失败通知端到端与常驻投递（2026-10-24 第七轮）

- 现象：要验收“真实后台失败 → 通知”，必须让真实 NetFS 拒绝一次挂载。用产品 UI 临时添加不存在的共享（`automnt-notify-verify-20261024`）并 `launchctl kickstart -k gui/$UID/org.automnt.automnt.recovery`，最初得到：helper 日志先 `mount runner failed issue=shareRejected`、紧接着 `evaluation failed issue=signalUnavailable`；`background-observations` 只有 `issue=signalUnavailable`，无 `pending-notification.plist`，也没有投递。
- 根因 1（失败被吞）：`MountWorkerRunner` 在 `store.begin` 之后、挂载失败返回前只会在成功路径 `store.complete`，确定性失败（shareRejected/authorizationRequired/credentialFailure/offline 等）也把 intent 留在 pending；下一提交步骤（`RecoveryAttemptCommit.rejected`、`RecoveryNotificationPolicy.commit`、`RecoverySessionCommit.advance`）都以 `verifyIdle()` 为前提，于是抛 `signalUnavailable`，失败观测与通知预算提交都无法完成。修复：`Sources/AutomntPlatform/MountWorkerRunner.swift` 的 catch 分支在 `requiresReconciliation == false` 时用同一 id/revision/generation 完成 intent；timeout/pathConflict/signalUnavailable 保持 pending 交给修复。
- 根因 2（投递循环空转）：常驻 App 的 20 秒循环用 `Task { [weak self] ... }` 引用引导实例；SwiftUI 的状态实例若与之不同，引导实例释放后循环只剩空转（`self` 为 nil），pending 永不被消费（实测 pending 文件生成 60 秒后仍在，且 `notification-delivery.plist` 不存在）。修复：`apps/Automnt/AutomntApp.swift` 在 `bootstrapResidentServices()` 里以 `residentServicesOwner` 强引用引导实例并加“只允许一个 owner”保护（避免重复投递同一槽位），启动与投递各写一条 `NSLog` 以便诊断（不写业务配置、不含目标信息）。
- 修复后证据（macOS 27、简体中文、最终安装构建）：临时共享真实挂载失败（helper `PID 15435` 等）→ 观测 `status=failed`、`issue=shareRejected`，两卷 `healthy`；`pending-notification.plist` 生成；常驻 App 于 20:41:16 / 20:50:06 两次将 pending 消费，`notification-delivery.plist` 为 `delivery=delivered`、`count=1`、`soundEnabled=true`，系统横幅显示“Automnt：自动恢复未完成 / 1 个共享文件夹未能自动挂载。请打开 Automnt 查看详情。”；前台时另测一次得到 `delivery=suppressedForeground`（设计行为）。证据截图见 `specs/005-swiftui-mas-gui/evidence/2026-10-24/`。
- 清理与回归：临时共享经产品 UI 移除，派生状态 `mount-recovery-state.plist` 中该 identity 记录与 pending/delivery 测试文件删除；`automnt.plist` SHA-256 恢复为 `911ed030cf395fd1e564bfe98ba1914c1617fc4f154fc98394a60d8275808e16`（4 个共享）；重新 kickstart 后 observations 两卷 healthy、`mount` 两卷在位。
- 限制：模糊结果（timeout/pathConflict/signalUnavailable）仍把 intent 留给 helper 启动时的 `abandonPendingForRepair` 修复；该路径下失败观测可能延后一轮，属既有“失败关闭”语义，本轮未改变。

## 重启后未挂载：会话边界不可读（2026-10-24 第六轮）

- 现象（2026-10-24 02:00 登录后，macOS 27）：两卷均未自动挂载——`mount | grep smb` 为空；recovery agent `runs=3`、最后退出码 0（helper 正常结束但未挂载）；`background-observations.plist` 两卷均为 `status=suppressed`、`retrySuggested=false`；`mount-recovery-state.plist` 两卷仍为 `state=attached`，且修复前该文件没有 `session_boundary` 键。
- 证据（新增诊断入口 `AutomntHelper --probe-session`，apps/Automnt/Service/HelperEntry.swift:31,169-173）：

  ```
probe: login-epoch=unreadable
probe: network-identity=readable
probe: boot-time=readable
probe: utmpx-console-records=0
probe: session=unavailable
  ```

- 根因：沙盒 helper 读不到 utmpx，`getutxent()` 只得到 0 条 console 记录，旧 `RecoverySessionCollector.loginEpoch()` 因此返回 nil → `collect(previous:)` 返回 nil → session_boundary 从未写入。跨重启后旧 `state=attached`（实际无挂载）被恢复判定当成“本会话健康弹出”：absent + everHealthyMounted → healthyEject → sessionSuppressed，于是观测写 suppressed、自动挂载被跳过。
- 修复（本地代码，未提交/未推送/未递增版本）：
  1. Sources/AutomntPlatform/RecoverySessionCollector.swift:47-50：`loginEpoch()` 在 console 记录不可读时退回 boot time，返回 `"<boot>-console-unreadable"`；boot time 经 `sysctl KERN_BOOTTIME`（:53-59），沙盒可读；只有 boot time 也不可读才返回 nil（此时才保守不推进边界）。
  2. Sources/AutomntCore/RecoverySession.swift:34-50：`RecoverySessionPolicy.advance` 的 establishing 分支把 `.attached` 且不在挂载表的卷改为 `.pendingRecovery` 并清零会话尝试/通知计数；`.suppressed` 用户弹出记录不动，但 `suppressionBoundary` 绑定新边界（:36-37）；非 establishing 分支维持原重置逻辑（:51-63）。
  3. 同 boot 保护（：24-33）：同网络且登录纪元的 boot 段相同（沙盒 `console-unreadable` 与 CLI 可读 console 只是同一启动内的写法差异）时直接返回，不改写边界、不清抑制，避免把同一启动误判为新会话。
  4. Dock 行为见下节。
- 验证（本轮已执行，macOS 27、arm64、简体中文、深色）：
  - 修复后探针：`login-epoch=readable`、`session=available`。
  - 02:09 `launchctl kickstart -k gui/$UID/org.automnt.automnt.recovery`：两卷挂载成功（`//jiezhengj@DX4600._smb._tcp.local/finalhome`、`.../personal_folder` on `/Volumes/...`），observations 两卷 status=healthy，state 写回 session_boundary、volumes=attached。
  - 重启会话模拟（等价真实重启路径；02:16 与最终构建 02:19（observations 写入 02:19:31） 各一次）：`diskutil unmount` 两卷 → 把 state 的 session_boundary 改为伪造旧会话 `old-network|1700000000-old-console`、两卷改回 attached、attempt_count=2 → kickstart → 两卷重新挂载、状态回到 attached/attempt_count=0、observations health、session_boundary 更新为当前 `<network>|1792778275-console-unreadable`。
  - 门禁：`swift test` 339 项（105+201+33）0 失败（RecoverySessionTests 新增 4 例：establishing 恢复陈旧 attached、仍在表内保持 attached、同 boot 仅 console 可读性不同不算新会话、同 network 新 boot 重置陈旧 attached；RecoveryBoundaryConsistencyTests 的 planner 断言改为与 establish 后状态一致）；CLI `scripts/build.sh` 与 `.build/automnt --self-test` 302 项 0 失败；Release 构建并安装 `/Applications/Automnt.app`；`verify-signature.sh` 5 项 PASS；`verify-localization.py` PASS（267 条源字符串 × 9 语言）；`verify-swift6-concurrency.py` 通过。
- 未验证/限制：
  - **真实重启（2026-10-24 19:00，已通过）**：boot 1792839587（18:59:47）；登录项 19:00:23 启动 App（0 窗口、`background only=true`、菜单栏图标 1）；recovery agent runs=2、退出码 0；无人工操作下两卷自动挂载，19:02:11 observations 两卷 healthy，state session_boundary=`<network>|1792839587-console-unreadable`、两卷 attached/attempt_count=0；owner=app/phase=active、无第二 helper；`ls` 可读；无新增崩溃报告。
  - **真实登录项启动的 Dock 行为（同日重启，已通过）**：App 由登录项启动后无窗口、无 Dock 图标（accessory），菜单栏图标常驻；从菜单栏打开窗口后才恢复 regular。菜单栏菜单真实点击/VoiceOver/浅色/较大文字/九语审校仍归 T141。
  - **同一 boot 内注销再登录**：沙盒读不到 utmpx，边界不刷新（见 known-limitations），本轮未做真实注销轮；属已记录限制，不是新缺陷。
  - **抑制清除的等价验证（2026-10-24 19:2x）**：同会话 `diskutil unmount` 后 kickstart → observations suppressed 且不挂载（符合设计）；伪造旧会话边界后 kickstart → 两卷重新挂载、healthy、attached/attempt_count=0。真实重启前处于 suppressed 状态的清除未直接观测。
  - 沙盒读不到 utmpx 属已确认限制：同一 boot 内“退出登录再登录”不会刷新会话边界（只有重启会改变 boot 段），该会话的弹出抑制会持续到下次重启；用户可用界面中的“立即尝试自动挂载”或对单个共享“挂载/重试”恢复（见 known-limitations）。

### Dock 图标与窗口行为（2026-10-24 第六轮）

- 维护者反馈：设置窗口没打开时 Dock 栏不该激活图标。
- 决定与实现：`apps/Automnt/Resources/Info.plist:16-17` 增加 `LSUIElement=true`（默认 accessory、无 Dock 图标）；`apps/Automnt/AutomntApp.swift` 的 `DraftTerminationDelegate`（:10,23-43）监听窗口 didBecomeKey/didDeminiaturize/willClose，按“是否存在可见的 titled 普通窗口”（:35-38）在 `.regular` / `.accessory` 间切换；`applicationShouldTerminateAfterLastWindowClosed`（:48-50）返回 `!menuBarEnabled`——菜单栏常驻时可关掉最后一个窗口而不退出，未常驻时仍按普通窗口 App 退出。
- 取舍：登录项启动或仅菜单栏常驻时无 Dock 图标；窗口出现（主窗口或设置）才有 Dock 图标；关最后一个窗口是否退出取决于菜单栏图标是否开启。设计记录见 [2026-10-24-session-identity-and-dock.md](design/2026-10-24-session-identity-and-dock.md)。
- 验证（最终安装构建，macOS 27、简体中文、深色）：从 `/Applications` 启动 → 主窗口打开时 `background only=false`（regular、有 Dock 图标）；关闭全部窗口后 `background only=true`、窗口数 0、菜单栏图标仍为 1（无 Dock 图标）；从菜单栏“打开 Automnt”重开窗口后 `background only=false`。2026-10-24 19:00 真实登录项启动复验：App 无窗口、`background only=true`（无 Dock 图标）、菜单栏图标 1；菜单栏菜单真实点击/VoiceOver/浅色/较大文字/九语审校仍归 T141。

任务拆解见 [tasks.md](tasks.md) 的“2026-10-23 重开”（T129–T142），helper 就绪判定与挂载执行契约见 [background-service.md](contracts/background-service.md) 的“2026-10-23 helper 就绪判定修正”“挂载执行位置”与“失败通知：记录与投递分离”，设计记录见 [2026-10-23-helper-readiness.md](design/2026-10-23-helper-readiness.md)、[2026-10-23-sandbox-mount-execution.md](design/2026-10-23-sandbox-mount-execution.md) 与 [product-design.md](design/product-design.md)。截至本轮：挂载路径已改为进程内执行并经 kickstart 实测两卷挂载成功；失败通知已改为常驻 App 投递并经 App 身份实测可投递；真实重启/重新登录、端到端失败通知链路、菜单栏常驻界面与 GUI 运行期交互仍未验证，不得表述为已通过。

### 可访问名称、VoiceOver 实读与九语代理验收（2026-10-24 第八轮）

- 触发：第七轮把 T143（共享行/图标可访问名称）与 T144（人工/母语者验收）留作未完成；维护者要求“去完成”，并指示“没有母语者，你和 agy 共同完成后，就代表了我”。
- 审计方法纠正：第七轮用 System Events 读取 AX 名称，该桥读不到 SwiftUI 的 `AXTitle`/`AXDescription`，导致“共享行按钮/开关/链接无名”的误判。第八轮改用本机 `AXUIElement`（`AXIsProcessTrusted=true`）审计，确认共享行按钮 `finalhome, 可用`、开关 `自动挂载此共享文件夹, finalhome`、链接 `编辑共享文件夹`/`从 Automnt 中移除…`、菜单栏 `MenuBarIcon` 均有名称；真实缺口是服务器页“此服务器参与自动挂载”开关与设置窗口 5 个开关（自动挂载、自动恢复、在菜单栏中显示、登录时打开、通知声音）只有 AXValue，另加 Spotlight 开关与尝试次数 Stepper。
- 修复：`apps/Automnt/Views/MainWindowView.swift` 与 `apps/Automnt/Views/DetailViews.swift` 为上述开关/Stepper 补 `.accessibilityLabel(Text(现有本地化 key))`，不新增文案、不改布局；重建安装后同一审计产品控件无名数为 0（剩余无名项均为系统窗口按钮、滚动条箭头、菜单分隔项）。
- VoiceOver 实读（真实开启，非模拟）：开启“旁白”并用 VO 键在 App 内导航，旁白字幕面板实时显示朗读文本，截图见 `evidence/2026-10-24/voiceover-spoken-captions.png`；读到“此服务器参与自动挂载…”“已管理”“挂载位置, /Volumes/finalhome, …”“finalhome, 可用 按钮 打开此共享文件夹的详情。”“personal_folder … 开关按钮 自动挂载此共享文件夹”。
- 系统“较大文字”：系统设置 > 无障碍 > 显示 > 文字大小滑块（0–14，默认 4）调到 6 并重启 App 后文字无变化——Automnt 不在该功能支持列表内；已还原 4。改用显示器 1024×666（等效更大文字）截图验证布局可读、无截断，随后还原 1470×956。结论：系统级放大下布局成立；App 尚未采用动态字体。该限制的最终裁定见下节“文案与文字大小裁定”。
- 九语代理审校：agy 对 `apps/Automnt/Resources/Localizable.xcstrings` 460 条 × 9 语全量审校（40 条问题 + 术语分裂清单，`evidence/2026-10-24/agy-nine-language-review.txt`）；本机逐条核对现值后应用 24 条高置信修订（fr/es 从句、de Einbindung/freigegeben、pt-BR Ajustes、ja 復旧、zh-Hant 檔案夾/圖示/復原、zh-Hans 句式、ko 하세요 等，`copy-fixes-applied.txt`），本地化门禁 267×9 通过；真机抽查 ja 设置页显示“自動マウントと自動復旧が実行中です。”。未应用的人称/术语统一（de du/Sie、pt-BR 其余分裂、ja 剩余アプリ、ko 个别语气、zh-Hans App/应用、fr/es 登录项名称）保留待维护者裁定，未静默改动。
- 真实注销/再登录：仍不可执行（注销终止本会话）；等价证据为 19:00 真实重启轮与同 boot 边界不刷新限制，已写入 known-limitations。
- 结论：T143 关闭；T144 按维护者授权的代理方式关闭（可执行项全部完成，无法执行项如实保留）；门禁：`swift test` 339、CLI `--self-test` 302、本地化 267×9、Swift 6、签名 5 项、Release 构建安装。

### 文案与文字大小裁定（2026-10-24 深夜，第九轮）

- 触发：维护者把第八轮遗留的两项交给 Lead 与 agy 共同决定——“未应用的九语人称/术语统一是否照改”与“是否单独开一项采用动态字体的改进”。
- 依据：agy 给出可执行建议；本机以 Apple 自带本地化核对，修正两处：德语系统设置实际用 du（“Personalisiere den Mac so, wie es für dich am besten funktioniert …”“Erlaube die Verwendung von Befehlszeilen-Werkzeugen …”），因此目标语气是 du 而非 agy 建议的 Sie；登录项面板名称以系统 `LoginItems.appex` 本地化为准——fr “Ouverture et extensions”、es “Ítems de inicio y extensiones”、de “Anmeldeobjekte & Erweiterungen”。
- 决定一（已执行）：对机械且语义安全的 63 处译文统一，不新增 key、不改代码与布局——德语 freigegeben/einbinden/Befehlszeile（保留动词“mit dem Befehlszeilenwerkzeug geteilt”）、巴西葡语 Ajustes 与 iniciar a sessão、日语独立名词 App 与网络重连復旧（保留「アプリケーション」与安装包“復元”）、韩语 하세요 与 세부사항、繁中檔案夾与回復、法语/西语登录项名称、大小写重复 key 漂移。决定不做 zh-Hans App/应用替换（多为动词“应用”与既有术语）。
- 决定一（已执行，第十轮）：德语 du/Sie 语气已由 Lead 与 agy 逐句统一为 du——agy 对 67 条含敬称的文案逐条改写，本机校验占位符与 key 完全一致后应用 65 条；剩余 3 处 Sie 是第三人称指代（“…die Adresse”“…die Reihenfolge”“…die Einstellungen”），不是敬称。依据 Apple 德语系统设置原文“Personalisiere den Mac so, wie es für dich am besten funktioniert …”。简体中文 App/应用仍不替换（动词“应用更改”与既有术语）。
- 决定二（维护者确认“不再支持这个需求”）：动态字体不作为需求。系统“文字大小”面板只列支持的 App，Automnt 不在其中，滑块调大并重启后文字不变（实测），且没有公开方式让第三方原生 App 注册进该面板。因此不单开任务、不列改进项、也不设替代（不通过修改显示器分辨率来假装支持）。写入 known-limitations 作为已记录边界，不标成已支持。
- 验证：本地化门禁 267×9 通过；重建安装并签名 5 项 PASS；真机抽查 de “Automatisches Einbinden”“Freigegebenen Ordner hinzufügen…”、ja “自動マウントと自動復旧が実行中です。”、pt-BR “Ajustes de Automnt”“Ao iniciar a sessão…”。
- 记录：`design/2026-10-24-copy-and-text-size-decisions.md`；证据 `evidence/2026-10-24/copy-decisions-round8b.txt`。

# 迁移记录：known-limitations 长篇原文（2026-10-24）

以下为精简前的中英原文，保留以便追溯。

## 中文原文

- 独立 helper 的后台挂载（原 T095/T096）：2026-10-23 已确认是实际缺陷链——登录后后台任务触发 3 次均退出码 1、无状态无挂载无通知；根因依次为 helper 用 launchd 传入的相对 argv[0] 反推 app 路径失败、helper 内 SMAppService 查询返回 error 22 被误判待批准、以及沙盒下 worker 子进程无法执行 NetFS（inherit 无网络授权 / inherit+network.client 初始化卡死 / 独立沙盒 `forbidden-sandbox-reinit` 崩溃，见 design/2026-10-23-sandbox-mount-execution.md）。现已改为在 helper/App 进程内执行挂载（Sources/AutomntPlatform/MountExecutionService.swift）并安装签名构建；GUI 未运行时由 `launchctl kickstart` 触发 recovery/baseline，两卷成功挂载，background-observations.plist 两卷 status=healthy。**2026-10-24 更新**：真实重启后的自动挂载已通过（19:00 由登录项启动、无人工操作两卷自动挂载、观测 healthy）；GUI 运行期手动“弹出/挂载”已在第七轮实测；真实注销/重新登录轮不可由 Agent 执行（需 GUI 密码且会话会中断），且同一 boot 内会话边界不刷新属设计限制，详见下文。

- 失败通知：2026-10-23 已按维护者选定的方案 A 实现“helper 记录、常驻 App 投递”——helper 只写 `pending-notification.plist`（10 分钟过期丢弃），App 在运行且通知权限允许时轮询投递；helper 不再派生 App、不再调用通知中心。**明示限制**：App 被退出、未设为登录项或通知权限被拒/撤销时，后台失败不会通知；10 分钟过期的记录不补发。想要后台失败通知，必须在登录时运行并常驻菜单栏图标（单向依赖，菜单栏可常驻而通知关闭）。**端到端已于 2026-10-24 第七轮实测通过**（T140）：用产品 UI 临时添加不存在的共享制造真实 `shareRejected` 失败，helper 写 pending，常驻 App 在 17–22 秒内投递（`notification-delivery.plist` 为 `delivered`，系统横幅“自动恢复未完成 / 1 个共享文件夹未能自动挂载”），两轮复现；前台时另测为 `suppressedForeground`（设计行为）。该轮同时修复两个真实缺陷：确定性挂载失败后 launch intent 未清除导致失败观测/通知被 `signalUnavailable` 吞掉；常驻投递循环 weak self 导致 pending 永不被消费。**仍未逐项复验**：系统拒绝/paused/10 分钟过期在真实链路中的各自表现（实现有单测覆盖）。

- 菜单栏图标是常驻进程的唯一可见入口：登录项启动只显示菜单栏、不打开主窗口。2026-10-24 第五轮在 macOS 27、简体中文、深色外观下实测：设置窗口真实打开；通知区“已允许但未常驻”显示收益句、权限行、单一原因与“在登录项中开启”；菜单栏图标开关真实点击；关闭图标的确认弹窗真实点击（标题“从菜单栏隐藏 Automnt？”、正文与关闭/取消按钮）；菜单栏菜单项经辅助功能读取（含“退出后…”说明，已无 Hide 项）。**2026-10-24 第七轮更新**：登录项常驻启动由 19:00 真实重启覆盖（0 窗口、无 Dock 图标、菜单栏图标 1）；菜单栏真实点击（打开 Automont/设置…/立即检查）、浅色与深色真实切换、九语真实启动渲染、GUI 内弹出/挂载均已实测并存证（`specs/005-swiftui-mas-gui/evidence/2026-10-24/`）。**第八轮（维护者授权 Lead + agy 代理验收）**：VoiceOver 真实开启并用 VO 键导航，旁白字幕面板读出“服务器开关”“已管理”“finalhome, 可用 按钮 …”“personal_folder …”等，已截图存证；可访问名称经 `AXUIElement` 审计纠正——共享行按钮/开关/链接本就有名称，真实缺口是服务器页 1 个开关、设置窗口 6 个开关与 1 个步进器（仅 AXValue），已补 `accessibilityLabel` 并复测为 0 个无名产品控件；系统“文字大小”滑块（默认 4）调大后本 App 文字不变（不在支持列表内，属动态字体未采纳的已知限制），改用显示器“更大文字”缩放截图验证布局可读且已还原；九语由 agy 全量审校、本机核对后应用 24 条高置信修订（其余人称/术语统一留维护者裁定）；真实注销/再登录仍不可执行（会终止会话），以 19:00 真实重启轮为等价证据。细节见 `specs/005-swiftui-mas-gui/evidence/2026-10-24/`（accessibility-audit、voiceover-spoken-captions、agy-nine-language-review、copy-fixes-applied、t144-proxy-acceptance）。

## English originals

- Background mounting by the independent helper (formerly T095/T096): confirmed on 2026-10-23 as a chain of real defects. After login the background job ran 3 times, exited with code 1 and wrote no state, mounted nothing and sent no notification. Causes in order: the helper derived the app path from the relative argv[0] launchd passes; the helper's in-process SMAppService query returned error 22 and was misread as "approval required"; and under App Sandbox a spawned worker child cannot perform NetFS at all (inherit child has no network entitlement; inherit + network.client hangs in secinit; a child with its own profile is rejected with `forbidden-sandbox-reinit`, see design/2026-10-23-sandbox-mount-execution.md). Mounting now runs inside the helper/app process (Sources/AutomntPlatform/MountExecutionService.swift) and the signed build is installed; with the GUI not running, `launchctl kickstart` of recovery/baseline mounted both volumes and background-observations.plist records status=healthy for both. **Update 2026-10-24**: automatic mounting after a real restart now passes (launched by the login item at 19:00, both volumes mounted with no interaction, healthy observations); GUI runtime manual eject/mount was exercised in round seven. A real log-out/log-in round cannot be executed by an agent (it needs GUI credentials and ends the session mid-turn), and the session boundary does not refresh within one boot by design; see below.

- Failure notifications: on 2026-10-23 the maintainer chose option A, so the helper records and the resident app delivers. The helper only writes `pending-notification.plist` (a 10-minute TTL; expired notices are dropped); while the app runs with notification permission it polls and delivers. The helper no longer spawns the app and never calls the notification center. **Explicit limits**: if the app is quit, not set as a login item, or notification permission is denied/revoked, background failures are not notified; expired notices are not replayed. Receiving background failure notifications therefore requires the app to run at login with a resident menu bar icon (one-way dependency; the menu bar icon may stay resident with notifications off). **End-to-end verified in round seven (2026-10-24)** (T140): a nonexistent share added through the product UI produced a real `shareRejected` failure; the helper wrote the pending notice and the resident app delivered it in 17-22 seconds (`notification-delivery.plist` = `delivered`; system banner "自动恢复未完成 / 1 个共享文件夹未能自动挂载"), reproduced twice; while the app was frontmost the outcome was `suppressedForeground` (by design). That round also fixed two real defects: a definitive mount failure left the launch intent pending so the failure observation/notification were swallowed as `signalUnavailable`; and the delivery loop held the bootstrapping model weakly so pending notices were never consumed. **Not re-verified individually**: system-denied/paused/10-minute-expiry behaviour in the real chain (unit-tested only).

- The menu bar icon is the only visible entry of the resident process: a login-item launch shows the menu bar and never opens the main window. **Update 2026-10-24**: login-item resident launch was covered by the real 19:00 restart (0 windows, no Dock icon, one menu bar item); real menu-bar clicks (Open Automnt / Settings… / Check Now), real light/dark switching, nine-language launch rendering and GUI eject/mount were exercised in round seven and stored under `specs/005-swiftui-mas-gui/evidence/2026-10-24/`. **Round eight (maintainer authorised Lead + agy to accept on their behalf)**: VoiceOver was really enabled and navigated with VO keys; its caption panel showed the spoken server switch, "已管理", "finalhome, 可用 按钮 …" and "personal_folder …" (screenshots stored). The AXUIElement audit corrected round seven: share-row buttons/toggles/links do have names; the real gaps were the server-page and five Settings switches (AXValue only), now labelled and re-audited to zero unnamed product controls. The system Text Size slider (default 4) does not change this app's text (it is not in the supported list - dynamic type is an open improvement), so a display "Larger Text" scaling check was used and the layout held (restored afterwards). agy reviewed all nine languages; 24 high-confidence fixes were verified against current values and applied (remaining pronoun/terminology unification is left to the maintainer). A real log-out/log-in round is still not executable (it ends the session); the 19:00 real restart is the equivalent evidence. Details in `specs/005-swiftui-mas-gui/evidence/2026-10-24/`.

- Session boundary and session suppression (2026-10-24, sixth round): the sandboxed process cannot read utmpx, so the helper falls back to the system boot time (`sysctl KERN_BOOTTIME`, recorded as `<boot>-console-unreadable`) as its session boundary. Only a restart therefore starts a new session: logging out and back in within the same boot does not refresh the boundary, and shares recorded as user-ejected in that session stay out of automatic mounting until a restart. Use "Try Automatic Mounting Now", or Mount/Try Again on a single share, to recover immediately. Restart-driven boundary refresh was verified with an equivalent simulation and with a real restart on 2026-10-24 19:00 (both volumes auto-mounted, observations healthy, boundary updated to the current session); clearing a suppressed state that existed before a restart was not observed directly.

# 2026-10-25 第十一轮（SDD converge 收口与隐私清单）

- 背景：实现与验收已收口，但 Feature SDD 的官方 converge 阶段此前未运行（仓库无 Converge 产物）。按 `speckit-converge` 执行评估：以 spec/plan/tasks 为唯一意图来源，核对代码当前状态。
- 评估结论：授权范围内唯一真实缺口是 FR-015 要求的 `PrivacyInfo.xcprivacy` 不存在，而 T044 已勾选（记录与事实不符）。商店材料（store-copy、pricing、submission、截图等）按维护者决定随渠道延后 T100；真实“注销再登录”为等价标准；动态字体由维护者确认不再支持——这三类不作为本轮可执行缺口。
- 处理：追加 T145 并完成——审计 required-reason API（App 使用 `UserDefaults` CA92.1；App/helper 使用 `ProcessInfo.systemUptime` 35F9.1），创建清单并加入 Automnt target resources phase，`plutil -lint` 通过；Release 构建产物 `Contents/Resources/PrivacyInfo.xcprivacy` 存在，签名 5 项 PASS，`swift test` 339 项、本地化门禁通过。T044 补记复核说明。
- 结果：Converge 后 tasks.md 无未完成项；授权范围内实现满足 spec/plan/tasks。

# 2026-10-25 第十二轮（tasks.md 瘦身）

- 维护者要求 `tasks.md` 只保留“任务状态 + 一句验收结论”，把每条任务的根因、命令输出、截图证据迁到归档。执行：把原 249,754 字节中的逐条过程记录（311 条日期化子条目与 21 节背景长文）逐字迁至 `evidence/tasks-detail-archive-2026-10-25.md`（251,745 字节），`tasks.md` 压缩为 57,340 字节。
- 保留：全部 154 个任务 ID、[x]/[ ] 状态、[P]/[USn] 标记、21 个阶段标题与各阶段首句背景结论；无过程记录的任务改为给出原“通过条件”的首句，或标注“无独立过程记录”。
- 校验：新旧任务 ID 与勾选状态逐一相等；归档包含全部原任务标题与全部子条目原文；`tasks.md` 未完成任务数仍为 0。
