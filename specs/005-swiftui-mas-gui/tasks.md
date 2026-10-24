# 阶段 0：实施前体验设计（本轮新增）
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：2026-10-08 维护者要求设计与 SDD 绑定；历史第 9 轮双 CLI PASS 只覆盖当时材料；当前体验修订必须重新评审，状态以 spec.md 与本轮实质报告为准。
- [x] T057 [US3] 在 `specs/005-swiftui-mas-gui/contracts/experience-design.md` 修订现行逐页布局与交互契约 —— 验收：按任务状态闭合；通过条件原为：不含独立密码 CRUD、8 步 wizard、多选、普通用户 CLI 导入/检查
- [x] T058 [US3] 在 `specs/005-swiftui-mas-gui/design/interaction-prototype.html` 修订可点击文档 demo —— 验收：按任务状态闭合；通过条件原为：现行主流程可评审，模拟/未验证信息放设计标注，不宣称原生或 runtime 通过
- [x] T059 [P] [US3] 在 `specs/005-swiftui-mas-gui/design/visual-system.md` 及同目录 demo 资产修订浅深左右两区主界面，… —— 验收：按任务状态闭合；通过条件原为：维护者可评审现行 demo，资产来源与缺口如实记录，HTML/历史 SDK 编译不作为当前原生视觉验收
- [x] T060 [P] [US3] 在 `specs/005-swiftui-mas-gui/design/localization.md` 修订现行九语 SMB 文案与品牌记录 —— 验收：现行九语文案与品牌记录以 Automnt 暂用；八语实机窗口检查；历史 agreement 仍缺失但不阻塞；未把机器审校冒充母语人工。
# 阶段 1：项目与验证基线
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：T006 本地检查点（2026-10-11）：新增 App/独立 helper/继承式 worker 三份 entitlement 声明，六处 Xcode 配置均接入；Signing.xcconfig 包含唯一版本派生配置，团队/精确身份保留构建参数，未选个人团队。
- [x] T001 在 `release/evidence/baseline.md` 记录现有 CLI 版本、优化构建入口、自测、配置/恢复兼容范围和 Xcode/SDK/签名环境 —— 验收：按任务状态闭合；通过条件原为：实际执行结果及未知资源如实列出，不触发挂载/服务变更
- [x] T002 [P] 在 `release/evidence/resources.md` 清点真实 SMB 测试目标、现有免费签名身份、授权/网络操作方式和审核资源 —— 验收：2026-10-19 待维护者决定（详见 design/maintainer-decisions.md）：A 授权继续使用现有 NAS/Tailscale 并脱敏记录（建议）；B 提供独立测试服务器；C 改写为仅资源清点。
- [x] T003 [P] 在 `specs/005-swiftui-mas-gui/contracts/gui-and-release.md` 明确日志保留期限、容量/清理、删除入口… —— 验收：2026-10-19 待维护者决定（详见 design/maintainer-decisions.md）：A 保留 7 天/5 MB 并自动清理+设置清除（建议）；B 不自动删除；C 30 天/50 MB。
- [x] T004 建立 `Package.swift`、`apps/Automnt/Automnt.xcodeproj` 和 `scripts/build.sh` 的 CLI… —— 验收：第七十九轮经独立复验（V10，release/evidence/swift6-verification.md）并补齐防回归门：V10 确认迁移目标达成（两文件顺序 typecheck 均 0 error；V3 冻结副本强制 v6 后 Entry-first=37、ServiceAdapter-fir…
- [x] T005 在 `scripts/generate-version.py`、`apps/Automnt/Resources/Info.plist` 实现根 `autom… —— 验收：按任务状态闭合；通过条件原为：Core/CLI/app/发行元数据一致，构建编号自动派生，无第二手维护营销版本
- [x] T006 在 `apps/Automnt/Resources/Signing.xcconfig` 与 `scripts/verify-signature.sh` 建立… —— 验收：本地可独立完成部分=三目标签名/entitlement/seal、固定目录真实读写、GUI 启动退出；真实登录/重启后 helper 持久授权与跨设备分发延后 T095。
# 阶段 2：共用基础与操作边界
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：本阶段完成后才开始故事级实施。
- [x] T007 在 `Sources/AutomntCore/Configuration.swift` 提取配置模型、解析与校验，保留 hosts/shares、profi… —— 验收：按任务状态闭合；通过条件原为：旧合法配置不丢失，密码字段拒绝，version 不作 revision，自动化开关 false/true 经保存、重读及未知字段合并真正生效，恢复开关与自动化开关互不覆盖
- [x] T008 在 `Sources/AutomntCore/ConfigRepository.swift` 实现唯一真实目录、0600 原子替换、内容摘要 revisio… —— 验收：按任务状态闭合；通过条件原为：冲突保留 Draft、无容器回退配置，业务配置只经产品生成
- [x] T009 在 `Sources/AutomntCore/Evaluator.swift`、`RecoveryState.swift` 提取主机顺序排他、健康判定、网络… —— 验收：主机顺位、健康/会话/抑制、恢复清理账与通知额度由 Sources/AutomntCore 的 RecoveryVolumeDecisionPolicy、RecoveryRoundPlanner、RecoveryNotificationPolicy 等单一实现承担，planner / Baselin…
- [x] T010 在 `Sources/AutomntCore/BackendOwnership.swift` 实现 backend-state/transition-jou… —— 验收：BackendStateStore 使用固定 evaluation.lock（BackendStateStore.swift:184）并核对 generation/revision；owner/phase 与转换日志 0600 原子持久化，CLI 入口在动作前后复核。
- [x] T011 在 `Sources/AutomntCore/PlatformContracts.swift` 定义结构化评估结果、实际路径、观测时间及契约错误类别，隔离凭… —— 验收：PlatformContracts.swift 提供结构化 issue、实际路径/观测时间、挂载后处理与 UserNotifier 契约；FailureNotification 载荷仅 count，自测断言私有值不进入载荷；应用源码不解析 CLI 文本。
- [x] T012 在 `Sources/AutomntCLI/Entry.swift`、根 `automnt.swift` 连接共用核心并迁移现有自测至 `Tests/Aut… —— 验收：scripts/build.sh 从 Package target 派生源清单，以 swiftc -O -swift-version 6 编译并清理临时目录；--version 3.4.0、--self-test 295/0/0，Package 299 项测试通过。
# T009–T012剩余实施检查点
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：以下子项细化原任务，父任务保持未完成直至原通过条件全部满足；不替代后续真机验收。
- [x] T009-a 共享主机顺位与单调有限重试，关闭/过期不探测 —— 验收：（无独立过程记录）
- [x] T009-b 将CLI健康判定、网络/登录会话及抑制规则提取为共用核心，接入helper —— 验收：CLI 健康判定、网络/登录会话与抑制已委托共享核心，helper 使用同一判定；RecoveryBoundaryConsistencyTests 覆盖 nil/空串/抑制一致，295 自测与 299 Package 测试通过。
- [x] T009-b1 提取会话identity构造/边界推进、健康证据映射及同路径备用弹出保护 —— 验收：（无独立过程记录）
- [x] T009-b2 完成helper自身网络/登录采集及持锁状态推进、隔离文件健康探测和结果提交 —— 验收：第十八至十九轮接入公开API网络/登录采集、EvaluationPermit状态推进及无凭据health worker。
- [x] T009-c 提取恢复清理账与完整轮次编排，健康读写经隔离worker，接入合并/限额通知策略并覆盖共享失败不切备用 —— 验收：第七十六至七十九轮提取共享恢复轮次协调器，闭合 c 的规则部分：新增 Sources/AutomntCore/RecoveryRound.swift 的 RecoveryRoundPlanner（配置启用卷枚举、主机顺位、重试窗口夹限、健康证据映射、整轮 deferRound 一并迁入 Core；逐…
- [x] T010-a 将所有CLI baseline/recovery/manual入口接入统一evaluation.lock、owner/generation与持锁后revis… —— 验收：第七十七及八十轮闭合其代码部分：新增 Sources/AutomntCore/CLIOwnershipGate.swift（纯决策：permitted/needsInitialization/refusedAppOwner/requiresRepair/transitionInFlight/stal…
- [x] T010-b 将普通弹出及pending operation修复接入同一锁，确认child实际退出与内核收敛后才允许下一操作 —— 验收：第四十二轮明确共享拒绝完成持久提交后继续同主机其他共享，汇总失败与成功并建议重试，未知/待对账仍停止。
- [x] T011-a 完成两个渠道的UserNotifier接线、统一通知投递结果与失败载荷，保留前台静默及原限额 —— 验收：第七十五、七十七至七十九轮闭合其代码与崩溃修复：V1 独立实测确认 UNUserNotificationCenter.current() 在 bundle 身份不可解析的进程（Contents/Helpers、Contents/Library/LoginItems）抛未捕获 NSException …
- [x] T012-a 在上述共用规则接通后删除CLI重复编排，重跑优化命令及恢复回归 —— 验收：CLI runRecoveryRound 已删除第二份判定/账本/通知计数，只调用 RecoveryRoundPlanner；优化 CLI 自测 295/0/0、Package 299 项测试与 diff 检查通过。
# 阶段 3：US1 配置后自动可用（P1，核心增量）
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：后续独立验收：GUI-only，经逐行添加创建真实配置、系统 SMB 认证/已有凭据复用及必要访问授权后完成文件访问；GUI 退出、登录、网络及挂载丢失场景有实证，正常恢复零人工连接。
- [x] T061 [US1] 修订并后续实现方案 A：CLI-only、GUI-only、共同安装均使用真实 `~/Library/Application Support/automnt… —— 验收：以签名 entitlement 精确固定目录、无内部目录面板为验收；NSOpenPanel/父 scope/子书签步骤不再适用；真实登录/重启延后 T095。
- [x] T013 [US1] 后续在 `apps/Automnt/AutomntApp.swift` 与 `Sources/AutomntPlatform/PermissionStore… —— 验收：2026-10-19 真实运行（本机签名 app）：首次启动无配置、无目录面板，读取固定目录并显示本机已挂 SMB 的服务器分组（已管理/可添加）；单行添加 personal_folder 立即落盘 0600 配置，重复地址被就地拒绝且配置未变。
- [x] T014 [US1] 定义并后续接入系统 SMB 认证与已有系统凭据复用 —— 验收：按任务状态闭合；通过条件原为：无 argv/env/plist/日志泄露，真实签名 sandbox GUI/helper 的已有凭据复用与缺凭据/取消/失效行为有证据，不假定 CLI 与 app 同组权限
- [x] T015 [US1] 后续在 `apps/Automnt/Worker/MountWorker.swift`、`Sources/AutomntPlatform/NetFSMoun… —— 验收：按任务状态闭合；通过条件原为：配置路径真实文件访问、超时终止后内核收敛且无竞争重试
- [x] T016 [US1] 在 `apps/Automnt/Service/PermissionBinding.swift` 建立独立 helper/worker 的配置及网络卷访问授… —— 验收：PermissionBindingTests 3/3使用真实匿名管道验证空/截断/零长度/超长拒绝、完整载荷EOF及写端不发数据截止（100ms预算实测110ms）；最终Apple Development Release/全签名/九语言覆盖通过。
- [x] T017 [US1] 在 `apps/Automnt/Resources/LaunchAgents/automnt.baseline.plist`、`automnt.recove… —— 验收：第四十五轮register增加另一固定service必须stopped的执行前检查，拒绝enabled/approval/未知，1项Core矩阵；65项Package、原生Release/diff通过。
- [x] T018 [US1] 在 `apps/Automnt/Service/HelperEntry.swift` 实现一次读取授权/owner、加锁、评估、结构化状态与退出，接入新注册… —— 验收：按任务状态闭合；通过条件原为：待批准不宣称启用、无认证 UI、停用等有界在途操作收敛
- [x] T019 [US1] 在 `Sources/AutomntPlatform/DiskArbitrationBackend.swift` 实现普通卸载、繁忙失败及死卷清理适配 —— 验收：按任务状态闭合；通过条件原为：SMB/沙盒实际可用，普通操作不 force，卸载成功核对后才提交会话抑制，失败不标已卸载，未知健康不误清理
- [x] T020 [US1] 在 `release/evidence/core-gates.md` 执行固定网络触发、VPN/上下文、/Volumes 与真实自定义路径覆盖、健康弹出/失… —— 验收：按任务状态闭合；通过条件原为：自定义路径功能未静默丢失，缺口由合规产品代码解决或报告核心阻塞并审阅，禁止用账号等待/手动工具/隐藏轮询代替
- [x] T021 [US1] 在 `release/evidence/us1.md` 按 `quickstart.md` 完成首次/登录/网络恢复/丢挂载真实文件任务及离线/密码/权限/… —— 验收：按任务状态闭合；通过条件原为：SC-001 与 US1 对应 SC-002 有实际证据、后台短命退出、首次授权后正常恢复零人工连接
# 阶段 4：US2 两入口共同演进（P1）
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：独立验收：CLI-only、GUI-only、共同安装分别成立，同意图结果一致，旧配置和恢复状态保留，双向接管不重复服务/操作。
- [x] T022 [US2] 在 `Sources/AutomntCLI/ServiceAdapter.swift` 更新传统 LaunchAgent 安装、自愈与评估为 owner-a… —— 验收：按任务状态闭合；通过条件原为：CLI-only 原能力及免费预编译契约保留，app owner 时不自愈抢占，无常驻新进程
- [x] T023 [US2] 在 `Sources/AutomntCore/HandoffCoordinator.swift` 与 `apps/Automnt/Service/Hando… —— 验收：第五十九轮helper/app统一持锁BackgroundObservationCommit，旧代结果不得覆盖；1项Platform切换后拒绝/保留原字节，修正首测错误类型期望后82项Package、原生Release/diff通过。
- [x] T024 [US2] 在 `Sources/AutomntCLI/ControlCommands.swift` 与 `apps/Automnt/Service/ControlRo… —— 验收：第七十三轮active记录/SM停用或待批准不一致归repair，真正awaitingApproval保持continue；既有Core矩阵/store回归补断言，95项Package、原生Release/diff通过。
- [x] T025 [US2] 在 `Tests/AutomntCoreTests/OwnershipConflictTests.swift` 验证已有 CLI 配置自动呈现及唯一活动配置… —— 验收：第七十九至八十轮建立该文件的本地可通过部分：Tests/AutomntCoreTests/OwnershipConflictTests.swift（7 项）覆盖——在途 permit 持锁期间产品编辑/保存 mount_point 后操作锁与 config.lock inode 不变且旧快照被拒、在…
- [x] T026 [US2] 后续在 `apps/Automnt/Views/HandoffView.swift` 呈现底层检测到的旧未知/不兼容版本或无法释放服务的异常及可行下一步 —— 验收：第六十六轮旧定义限1MiB/fd nofollow/读后核mtime/ctime，链接未知；1项Platform。
- [x] T027 [US2] 在 `release/evidence/us2.md` 执行三种安装形态、已有 CLI 配置自动呈现、唯一配置/owner 双向协调、并发保存（普通用户首次… —— 验收：按任务状态闭合；通过条件原为：SC-003、原 CLI 自测和真实同意图行为通过，CLI/GUI 交替停用/启用并重读后开关一致，停用禁止新动作且保留已有健康卷
# 阶段 5：US3 原生视觉与完整交互（P1）
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：独立验收：首次/空/探测/授权/健康/离线/失败/编辑与菜单状态，真实浅深色和尺寸证据，鼠标/键盘/VoiceOver 主要流程及维护者审美复验。
- [x] T028 [US3] 在 `apps/Automnt/Views/MainWindow.swift` 建立真实列表/详情、首次/空状态视觉方向，输出 `release/evide… —— 验收：A 以本轮真实窗口截图作为视觉方向基线进入 T036/T037（建议）；B 逐项修改后再确认；C 外部视觉评审。
- [x] T029 [P] [US3] 后续在 `apps/Automnt/Resources/Assets.xcassets` 使用用户替换图标制作当前 Xcode 支持产物 —— 验收：第八十三轮完成资产与接入部分：新建 apps/Automnt/Resources/Assets.xcassets/AppIcon.appiconset（macOS 全部 10 个尺寸：16/32/128/256/512 各 @1x/@2x，由设计侧 design/app-icon-1024.png …
- [x] T030 [P] [US3] 在 `apps/Automnt/Resources/Localizable.xcstrings` 建立九语用户文案、通知、菜单与辅助功能资源及可理解错误/下一步 —— 验收：第八十七轮补齐复数与 locale 数字格式（此前该项为未完成项）：Lead 用独立探针实测确认硬编码 number == 1 分支下 fr/es/pt-BR 在 N=1,000,000 时输出裸 1000000（既未按 locale 分组，也缺 CLDR many 分支），违反 design/lo…
- [x] T031 [US3] 后续在 `apps/Automnt/Views/TargetEditor.swift`、`TargetDetail.swift` 按现行契约实现 serve… —— 验收：核查目标 SDK 与 Apple dismissalConfirmationDialog 官方正文（https://developer.apple.com/tutorials/data/documentation/swiftui/view/dismissalconfirmationdialog(_:…
- [x] T032 [US3] 在 `apps/Automnt/Views/StatusView.swift` 接入全部结构化状态、实际路径/观测时间、授权修复与异常重试 —— 验收：共享列表读取真实系统挂载位置和 SMB 身份，二者一致才显示“已挂载”并启用 Finder 入口；区分未挂载、位置冲突和无法确认，显示检查时间并提供显式重查；弹出后重新核对状态。
- [x] T033 [US3] 在 `apps/Automnt/Views/MenuBarView.swift` 与 `apps/Automnt/AutomntApp.swift` 完成可… —— 验收：View details 改为携带完整 host/share 与当前 revision，不再按裸主机名取首项；主窗口首次出现及已有窗口均消费请求，核对目标后通过原生 ScrollViewReader 定位共享行。
- [x] T034 [US3] 在 `Sources/AutomntCore/DiagnosticSnapshot.swift` 与 `apps/Automnt/Views/Diagnos… —— 验收：第八十六轮完成 Core 脱敏引擎与用户导出部分：新建 Sources/AutomntCore/DiagnosticSnapshot.swift（DiagnosticSnapshot 顶层恰 9 个契约字段：schemaVersion/generatedAt/product(version/chan…
- [x] T035 [US3] 在 `apps/AutomntUITests/PrimaryFlows.swift` 增加关键保存/取消/焦点/退出提示与菜单主要流程的有限 UI 回归 —— 验收：按任务状态闭合；通过条件原为：覆盖用户可见数据保护行为，UI 自动化不点击安全授权，不替代实机视觉/VoiceOver
- [x] T036 [US3] 在 `release/evidence/us3.md` 实机走查全部关键状态、菜单、九语长文本/复数/系统语言切换与关键译文复核、浅深/窄正常、对比度/减少… —— 验收：以窗口矩阵、八语实机截图、键盘焦点、AX 标签与设置/详情走查为可独立完成项；VoiceOver 朗读与系统较大文字延后 T099。
- [x] T037 [US3] 按 T036 缺陷修改 `apps/Automnt/Views/`、`apps/Automnt/Resources/` 并更新 `release/evide… —— 验收：按任务状态闭合；通过条件原为：阻止发布的布局/字级/间距/图标/材料/动画/输入/焦点/关闭缺陷归零，维护者审美反馈闭环
# 阶段 6：US5 账号无关发布候选（P1）
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：独立验收：免费身份本机升级授权、最终 OS 证据、全部成品与资源完成，缺陷归零；账号专属动作另列未执行。
- [x] T038 [US5] 在 `scripts/archive.sh`、`release/mas/build-guide.zh.md` 完成可复现 GUI 构建/归档及优化 CLI/… —— 验收：新增 scripts/archive.sh（Package 测试→优化 CLI+自测→签名 Release→验签/本地化/Swift6→zip+sha256+manifest）与 release/offline/build-guide.zh.md；实际归档 Automnt-3.4.0-offline…
- [x] T039 [US5] 在 `release/evidence/development-upgrade.md` 用两次稳定身份真实构建执行原地升级、授权后后台/GUI及钥匙串/目录… —— 验收：按任务状态闭合；通过条件原为：签名/DR 兼容且正常升级不重复授权，记录 GUI/helper/worker/CLI 实际身份、启动归属及 TCC 网络卷授权日志/可见提示，专门核对 AUTHREQ_PROMPTING、Failed to mat…
- [x] T040 [US5] 在 `release/mas/platform-audit.md` 审计实际 API/能力与 OS 证据并同步 `apps/Automnt/Resource… —— 验收：第八十八轮核实该「minos 27.2 与声明 27.0 已知差异」在当前源码构建产物上已不存在（Lead 用 vtool -show-build 实测）：scripts/build.sh /tmp/... 产出的优化 CLI 为 platform MACOS / minos 27.0 / sdk …
- [x] T041 [P] [US5] 在 `docs/privacy.zh.md`、`docs/privacy.en.md`、`docs/support.zh.md`、`docs/support… —— 验收：按任务状态闭合；通过条件原为：批准政策与实际行为一致、Issues 提醒敏感数据风险，不捏造身份/邮箱
- [x] T042 [P] [US5] 在 `release/mas/review-notes.zh.md`、`review-notes.en.md` 准备真实审核复现和 SMB 资源安全边界 —— 验收：按任务状态闭合；通过条件原为：无虚假公共服务器/账号，必要外部环境在此落实授权和实际可用性，不留到账号之后
- [x] T043 [US5] 在 `release/mas/screenshots/` 获取最终实际运行脱敏截图，必要独立展示模式在 `apps/Automnt/Views/Previe… —— 验收：按任务状态闭合；通过条件原为：无个人网络/用户名/文件内容，无展示数据写入活动配置，无占位素材，截取内容与完整产品一致
- [x] T044 [US5] 在 `release/mas/privacy-declaration.md`、`release-notes.zh.md`、`release-notes.en… —— 验收：清单 apps/Automnt/Resources/PrivacyInfo.xcprivacy 已存在并随 app bundle 嵌入（审计与验证见 T145；T044 的申报候选文档仍随商店渠道延后 T100）。
# 阶段 7：US4 US$1.99 与开源透明说明（P2）
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：独立验收：九语商品候选、关于/许可、自行编译和免费 CLI 指引事实准确，政策对照可追溯，无额外付费解锁。
- [x] T045 [P] [US4] 在 `release/mas/store-copy.zh.md`、`store-copy.en.md`、其他七语 `store-copy.<locale>.… —— 验收：按任务状态闭合；通过条件原为：无订阅/内购/外部激活，无把源码免费当商店免费下载或成本价证明，不在不适当元数据字段宣传价格，最终定稿依赖 T044
- [x] T046 [P] [US4] 在根 `README.md`、`README.zh.md`、`README.en.md`、`ARCHITECTURE.zh.md`、`ARCHITECTUR… —— 验收：根 README.md、README.zh.md、README.en.md、ARCHITECTURE.zh.md、ARCHITECTURE.en.md 五份同步 GUI/CLI 共用边界、普通弹出、免费预编译/可选源码编译、离线分发与已知限制；LICENSE 保留。
- [x] T047 [US4] 在 `apps/Automnt/Views/AboutView.swift` 承载 Settings 帮助组的“支持与隐私”sheet，集成开源、买断成品定… —— 验收：按任务状态闭合；通过条件原为：事实准确、无外部收费解锁、免费 CLI 不成为功能依赖
- [x] T048 [US4] 在 `release/evidence/us4.md` 审阅最终九语商品/关于及双语许可/支持材料及免费 CLI/源码链接政策与功能一致性 —— 验收：按任务状态闭合；通过条件原为：SC-007 候选材料通过，记录审核可能替换的文案，不宣称 Apple 已批准或已配置价格
# 阶段 8：账号无关收敛与公开资源
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：本阶段属于最终品质/跨故事收敛，不是补做主要视觉。
- [x] T049 在 `release/evidence/final-local.md` 对同一候选重跑必要构建、自测及全故事关键真实场景，核对 SC-001–011、FR-… —— 验收：按任务状态闭合；通过条件原为：核心、共存、升级、视觉、材料缺陷逐项修复复验，账号专属项仍未执行，不把文档覆盖当测试通过
- [x] T050 在 `release/mas/support-resources.md` 完成已准备 support/privacy 页的授权发布及最终稳定 URL 验证，… —— 验收：按任务状态闭合；通过条件原为：真实可达内容一致，无未发布 workspace URL/占位链接
- [x] T051 在 `release/mas/cli-release-guide.md` 准备遵守根规则的 CLI 发行动作与资源，必要更新根 `automnt.swift… —— 验收：按任务状态闭合；通过条件原为：升级类型有依据、优化预编译与源码同步、自测和实际渠道证据齐备，main 代码推送必须伴随版本晋级与 gh Release
- [x] T052 在 `release/evidence/readiness.md` 对所有账号无关工作最终收敛并列明剩余账号专属步骤 —— 验收：按任务状态闭合；通过条件原为：实际产品/签名/资源/授权/视觉缺口均归零才可报告唯一账号前置，否则继续具体修复并如实报告
# 阶段 9：最后账号边界与正式渠道动作
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：本阶段在所有账号无关工作完成后执行；只在真实付费账号及外部发行授权到位时开展，不在账号缺失时勾选，不承诺 Apple 审核结果。
- [x] T053 在 `release/mas/account-runbook.md` 执行付费账号、正式团队证书/profile、App Store Connect 实体/… —— 验收：当前范围改为免费账号+线下分发——签署免费 Apple Development、同机安装与限制说明；付费账号/App Store Connect 延后 T100。
- [x] T054 在 `release/evidence/mas-upgrade.md` 验证真实商店目标身份首次安装/升级权限连续性及渠道接受性 —— 验收：当前范围改为同机原地替换升级与配置/目录连续性；商店目标身份升级连续性延后 T100。
- [x] T055 在 `release/mas/submission.md` 配置 US$1.99 USD/地区价格点、隐私申报与准备好的九语元数据，归档上传并提交审核 —— 验收：当前范围改为生成离线分发包（zip/dmg）、校验和、版本说明与安装指引；商店价格/元数据/提交延后 T100。
- [x] T056 在 `release/mas/review-result.md` 处理真实审核反馈并记录最终状态，若涉及能力或范围变更先审阅，若代码修复重跑相应回归/签名/材料 —— 验收：当前范围改为记录线下分发已知限制与反馈处理；App Store 审核结果延后 T100（待维护者后续发起付费账号需求）。
# 依赖与并行安排
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：| 增量 | 进入条件 | 可独立验收结果 | | --- | --- | --- | | 体验设计 | T057→T058/T059/T060；维护者交互/视觉审阅 | SC-010 设计门槛，T013/T028 前置 | | 共用基础 | T001–T006；日志政策 T00…。
# 实施策略与验收覆盖
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：当前先完成文档/demo 的主界面与交互纠正，后续 app 实施另按维护者明确指令推进。
# 本轮纠正后的具体待办与 runtime 验收
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：T061 编号已存在并保留；以下从 T062 追加，全部未勾选。
- [x] T062 [US3] 文档/demo 定稿本机当前已挂 SMB 主界面 —— 验收：按任务状态闭合；通过条件原为：真实新增/弹出 SMB 后分组和单行状态正确，刷新不覆盖编辑 draft，不用周期轮询，未挂载局域网服务器不冒充发现结果
- [x] T063 [US1] 定义并后续实现单行添加的即时持久化 —— 验收：真实单行添加立即持久化、重开仍已管理、重复添加拒绝且无部分写入；跨服务器同路径由单元测试覆盖，真实双主机延后 T098。
- [x] T064 [US3] 文档/demo 定稿次级零结果 Finder 连接指引及工具栏完整 SMB URL 输入 —— 验收：按任务状态闭合；通过条件原为：Finder 连接后重新激活/卷变化可发现，缺 URL/名称/path、含凭据 URL、非法 URL/路径及 duplicate 都就地拒绝并保留 draft，完整有效输入成功持久化
- [x] T065 [US1] 形成并后续执行系统 SMB 认证/已有系统凭据复用真实矩阵 —— 验收：按任务状态闭合；通过条件原为：系统认证成功后可真实文件访问，已有凭据可复用且后台不反复要求认证，无 app 独立密码 CRUD/新匿名管道密码要求，无泄露
- [x] T066 [US2] 定稿并后续实现已有 CLI 配置自动呈现及唯一配置/owner 协调 —— 验收：按任务状态闭合；通过条件原为：普通用户首次授权固定配置文件夹后，打开即可看到已有配置，首次固定配置文件夹授权后无导入/检查向导，两入口更新后重读一致，停止/批准/失败/并发保存无双 owner、双活动副本或重复挂载
- [x] T067 [US3] 定稿并后续验证编辑 Save 成功关闭或重置 baseline、失败留 draft —— 验收：按任务状态闭合；通过条件原为：保存成功后的再次关闭无旧 dirty 确认，留页则 baseline 与新持久配置一致，失败不清 draft、不关闭或退出，刷新不覆盖输入，单行添加即时持久化不被整页草稿保存替代
- [x] T068 [US3] 文档/demo 修订右侧服务器标题中的“自动挂载此服务器的共享”toggle 独立标签与附近影响说明 —— 验收：按任务状态闭合；通过条件原为：成功保存后重读一致、失败不误报生效，九语/键盘/VoiceOver 可读，不将相反动作或内部 owner 分类塞入标签
- [x] T069 [US3] 在设计记录中核对用户替换图标的来源、可用尺寸及采用映射，并后续按 T029 核对实际产物/Finder/Dock —— 验收：按任务状态闭合；通过条件原为：图标实际来自用户替换且无虚构许可/审阅，品牌找回明确 agreement 或由维护者后续明确决定前不宣称已定稿
- [x] T070 [US1] 汇总本轮 runtime 证据矩阵并后续在同一真实签名候选复验 —— 验收：（无独立过程记录）
# 全产品修订任务与后续实现覆盖
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：2026-10-12 本轮进展：文档/demo 修订后，维护者授权“继续 Implement”，已完成本地代码实现、构建、签名与验证（未推送、未发布、未改版本号）。
- [x] T071 [US3] 在体验契约、数据模型和 demo 定稿侧栏已管理/发现两组、管理服务器直接拖放与键盘排序即存/撤销 —— 验收：Sources/AutomntCore/ManagedServerOrder.swift 新增 ManagedServerOrder（managedServerIdentity 以 host:port 为身份、moving、restoring）、ServerOrderUndo、ServerOrder…
- [x] T072 [US1] 定稿全局实际后台、界面选中、本轮评估服务器与已有挂载独立状态 —— 验收：OperationPresentation.swift 新增 OperationScope、EvaluationSelection（status(forServer:) 区分 selected/checked/notSelected，未检查不判离线）、AvailabilityReport/Setti…
- [x] T073 [US3] 在体验契约与 demo 定稿完整评估、单共享挂载/重试、只读刷新及对象进度/范围失败去重 —— 验收：OperationLedger 按 scope|target 键合并重复请求与失败（statusRefresh 与 singleShareMount 互不阻塞、不同共享不共用一行），GUI 用 begin/end 包裹操作。
- [x] T074 [US3] 定稿简单开关即时保存、名称行内确认、相关地址/路径成组提交 —— 验收：ManagedMembership.swift 新增 ManagedMembership（adding 复用已有服务器身份/参数/顺序、新服务器追加末尾、同服务器重复身份或路径拒绝、跨服务器复用同一约定路径允许）与 ManagedMembershipController（同 CAS 规则）。
- [x] T075 [US3] 定稿详情顺序及移除/弹出区别 —— 验收：详情顺序/状态/位置/自动安排/动作/移除后果/Spotlight 复验；确认移除后配置 hosts 为空且该卷仍挂载；最后共享随服务器同次移除。
- [x] T076 [US3] 在设计资源和 demo 补齐 Settings 实际后台/恢复、菜单/登录、通知授权/独立声音、共享重试、支持及原生 About/Help/离线许可/诊断预览 —— 验收：SettingsSurface.swift 新增 backendStatus（running/awaitingApproval/stopped/transitioning/unavailable/governedByCLI，仅确认运行才显示运行中）、AutomaticMounting、Notific…
- [x] T077 [US2] 在共同核心契约定义单共享/普通弹出共享操作及 CLI 新入口设计 —— 验收：Sources/AutomntCLI/Entry.swift 新增面向用户 --mount <smb-url> 与 --eject <smb-url>（T077 段自 5388 行起）。
- [x] T078 [US1] 在 quickstart 建立全产品追溯并后续真实复验主窗/首次/添加编辑/排序撤销/详情/设置/菜单/通知/关于帮助/诊断/退出升级和显式接管 —— 验收：仍未验证：真实重启/登录系统事件（以 bootstrap + 派生状态清除等效模拟）、GUI 拖放/焦点/滚动/窄窗/VoiceOver、九语实机布局、浅深色/较大文字、通知投递与前台抑制、诊断真实导出、认证失效恢复。
# 方案 A 文档修订后的实施任务
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：2026-10-13 本地实施增量：T079 的固定真实路径、前台系统面板、私有持久书签及 stale 更新已有代码；T080 的访问状态、无错误零目标/空态、写入/新挂载限制、可滚动授权页和九语资源已接入；T081 已通过独立授权 LaunchAgent 接入 bind → u…。
- [x] T079 [US2] 在固定配置仓库与 PermissionStore 实现真实用户固定路径身份、系统目录面板授权、GUI 自身持久书签、有效复用及安全 stale 更新 —— 验收：以签名 GUI 的 entitlement 固定目录准备/访问证明为验收；系统面板选择/父 scope/子书签不再适用。
- [x] T080 [US3] 在主窗口/设置修复入口及本地化资源接入 configAccess.*，首次原生 ContentUnavailableView 标题“开始使用 Automnt… —— 验收：以无面板访问状态、程序生成 0600 配置、只读失败快照与统一门禁为验收；系统面板步骤不再适用。
- [x] T081 [US1] 在独立 launchd helper/worker 权限绑定及后台预检实现各身份对固定目录的可证明访问 —— 验收：本地部分=helper/worker 两阶段预检可运行、needsAuthorization 有界退出、不后台索权；GUI 退出/真实登录/重启后持久访问延后 T095。
- [x] T082 [US1] 按 quickstart 方案 A 矩阵在真实稳定签名 sandbox GUI/helper 复验 —— 验收：以签名 GUI 本地矩阵（无面板、程序生成配置、添加/移除/重开、退出确认、helper 预检）为验收；真实登录/重启/后台 SMB 延后 T095/T096。
# 阶段 10：全产品收敛与最新纠正
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：2026-10-13，依据当前 [规格](spec.md)、[计划](plan.md)、[问题台账](../../release/evidence/feature-005-gap-audit.md) 和代码追加剩余工作。
- [x] T083 [US2] 裁定固定真实路径/唯一配置/单 owner 的免内部目录选择访问机制 —— 验收：2026-10-19 复核补记（代码文件时间 2026-10-13 18:20–18:37）：apps/Automnt/Resources/Automnt.entitlements 与 Service/Helper.entitlements 已声明 com.apple.security.tempor…
- [x] T084 [US2] 依赖 T083，在 [PermissionStore](../../Sources/AutomntPlatform/PermissionStore.swif… —— 验收：签名 GUI 在无目录面板下准备/读取固定目录并创建 0600 配置，应用重启后复用同一配置；未验证拒绝/stale/revoked/读失败与后台动作就绪。
- [x] T085 [P] [US3] 在 [图标脚本](../../scripts/generate-app-icon.sh) 与 [AppIcon](../../apps/Automnt/Re… —— 验收：退出确认面板显示最新 infinity 文件夹图标；Finder/Dock/浅深色/小尺寸与维护者审美确认未验证。
- [x] T086 [P] [US3] 在 [ServerInventory](../../Sources/AutomntCore/ServerInventory.swift) 修复受管 host… —— 验收：已管理服务器下新发现共享仍出现在可添加组（personal_folder 已管理后 finalhome 仍可添加，计数 1/1），重复 URL 被拒；未验证跨端口与多主机。
- [x] T087 [P] [US3] 在 [DetailViews](../../apps/Automnt/Views/DetailViews.swift) 与 [应用保存](../../app… —— 验收：EditShareView 打开时固定 editBase 快照与目标身份，保存只使用该 revision；目标消失或并发写入按冲突报错并保留输入。
- [x] T088 [P] [US3] 把 [DraftTerminationDelegate](../../apps/Automnt/AutomntApp.swift) 的请求和完成/取消回调接… —— 验收：⌘Q/菜单退出在脏表单时弹出原生确认（保存并退出/放弃并退出/取消）；保存失败保持窗口与字段错误；取消与无脏草稿直接退出（修复了无草稿退出被静默取消的问题）。
- [x] T089 [P] [US3] 在 [应用场景](../../apps/Automnt/AutomntApp.swift)、[卷发现](../../Sources/AutomntPlatf… —— 验收：MainWindowView 监听 scenePhase == .active 与 NSWorkspace.didMountNotification/didUnmountNotification，调用 refreshObservedState() 重新读取配置、内核挂载、发现与最后一轮摘要；不触发评…
- [x] T090 [P] [US3] 在 [MainWindowView](../../apps/Automnt/Views/MainWindowView.swift) 补齐未选服务器时的任务下… —— 验收：主窗口改为宽度自适应：<700pt 使用原生 NavigationStack 按服务器→共享→详情分层，宽窗保留左右两列；最小宽度降为 380；compactPath 在对象消失时收缩，选择按身份回退或保持；空态在两种布局共用。
- [x] T091 [P] [US3] 在 [ConfigurationValidation](../../Sources/AutomntCore/ConfigurationValidation.… —— 验收：空表单提交显示地址/名称/挂载位置三条字段错误并聚焦首个错误；重复地址在地址字段就地拒绝且配置未写；8 条九语文案通过完整性门。
- [x] T092 [US2] 在 [CLIOwnershipGate](../../Sources/AutomntCore/CLIOwnershipGate.swift)、[Handof… —— 验收：Sources/AutomntCLI/TransitionRecovery.swift 提供 CLI 中断转换的严格语法、锁/状态校验与有界恢复，CLITransitionRecoveryTests 6 项覆盖语法拒绝、中断收敛、活动锁拒绝、陈旧 generation、app owner 拒绝与 p…
- [x] T093 [US1] 依赖 T084/T092 与后台实现，按 [quickstart](quickstart.md) 在 [授权证据](../../release/eviden… —— 验收：本机签名 GUI 真实读取/创建固定目录配置、单行添加/移除、窄窗导航与退出确认；CLI --mount/--eject 本次因持久状态返回 requiresRepair 被拒（owner=none/phase=stopped 却拒绝，见 implementation.md），未完成 helper/…
- [x] T094 [US3] 依赖 T085–T093 及相关实现，按 [体验契约](contracts/experience-design.md)、[交互审阅](design/inte… —— 验收：宽/窄窗、详情、Settings、退出确认、字段校验与真实 SMB 加入/移除的截图存档于 .build/automnt-runtime-2026-10-19/；九语/大字/VoiceOver/全界面审美矩阵未执行。
# 阶段 11：延后项（当前环境不可独立完成）
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：2026-10-19，维护者要求：不能独立完成的测试必须改写并明确延后，不得用锁定/勾选掩盖。
- [x] T095 [US1] 在真实登录/注销/重启与稳定签名下验证独立 helper/worker 对固定目录的持久访问及后台真实 SMB 文件读写 —— 验收：（无独立过程记录）
- [x] T096 [US2] 验证 GUI 退出后后台自动挂载、系统 SMB 认证复用与 GUI/CLI 双向 owner 协调 —— 验收：（无独立过程记录）
- [x] T097 [US3] 实现并验证主窗口 ⌘W/红色关闭按钮的草稿保护（保存/放弃/取消），与 ⌘Q 共用同一 revision 校验与失败保留 —— 验收：为真实 NSWindow 安装关闭守卫，并以 ⌘W 本地事件拦截覆盖 sheet（sheet 关闭不经过窗口委托）；保存/放弃/取消复用同一草稿与 revision 校验。
- [x] T098 [US3] 以第二台真实主机/第二端口验证跨端口、多主机与跨服务器同路径的真实矩阵 —— 验收：（无独立过程记录）
- [x] T099 [US3] 以真实 VoiceOver 朗读与系统较大文字设置复验全界面辅助功能 —— 验收：（无独立过程记录）
- [x] T100 [US5] 付费 Apple 账号、正式证书/profile、App Store Connect、商店元数据与提交审核 —— 验收：（无独立过程记录）
- [x] T101 [US2] 修复 CLI 注册失败被误报 `requiresRepair` 的错误映射，并在 launchd 可注册环境验证 `--mount`/`--eject` 的… —— 验收：在 PTY 交互终端下 CLI 成功注册 LaunchAgent（com.user.automnt，owner=cli/active）并完成真实 --mount/--eject；此前非 TTY 环境被 DaemonRuntime.isDaemon() 判为守护态导致 requiresRepair/注…
- [x] T102 [US3] 在应用后台控制已配置的条件下验证 GUI 普通弹出与繁忙卷弹出（不 force、繁忙如实失败、成功后会话抑制与恢复） —— 验收：（无独立过程记录）
- [x] T103 [US3] 实现日志保留政策（T003 方案 A）：按 7 天/5 MB 滚动清理本机日志，在设置或诊断提供“清除日志”，记录实际清理结果 —— 验收：Sources/AutomntCore/LogRetention.swift（7 天/5 MB、行边界裁剪、清除）、CLI 正常启动与 App 读取时执行、诊断页面“清除日志”入口与九语文案；LogRetentionTests 3 项与 CLI 分类测试通过，Package 306 项测试全绿。
- [x] T104 [US3] 修正首次启动/设置读取失败的文案与按钮布局：固定目录缺失自动准备，不再显示“访问 Automnt 设置/允许访问” —— 验收：restore/reload/authorize 统一经 openSettingsDirectory() 准备固定目录；新增 isFirstRun 欢迎页；更新 configAccess/状态九语文案；ContentUnavailableView 动作按钮加 fixedSize 并保留横/纵回退。
- [x] T105 [US1] 首屏优先呈现已发现的“可添加”服务器：选中后显示其共享及逐行添加动作，欢迎/手动输入仅在无服务器时作为兜底 —— 验收：调整详情优先级为“访问错误 → 选中服务器 → 欢迎空页”；首次发现 DX4600 时自动选中并显示两个可添加共享及“添加”，不再被欢迎页覆盖。
- [x] T106 [US3] 主窗口默认尺寸采用维护者确认的 1103×692，并记住用户调整后的尺寸/位置 —— 验收：NSWindow frame autosave（主/设置独立 key）+ 首选帧保存/恢复；主窗口实测 1103×692，设置 680×620 并位于主窗口中心（3075,48）；设置场景允许 contentMinSize 调整。
- [x] T107 [US3] 重写设置中的登录项与通知文案：移除常驻且含义不明的“检查登录设置/检查通知授权”，登录项不可用时给出“退出并从应用程序重新打开→检查一次” —— 验收：登录项未启用时不再显示“不可用”，只有实际登录项变更失败才显示 loginIssue 与上下文“检查一次”；通知 purpose/denied/unavailable/sound 文案九语重写；状态标签改为“通知权限：未开启/已允许/已关闭/暂时无法读取”；SDD copy-resources/pr…
- [x] T108 [US3] 将菜单栏图标从随意 SF Symbol 改为从应用 SVG 派生的 18pt template 图标，修正大小、垂直居中与浅深色适配 —— 验收：新增 MenuBarIcon.imageset（18/36/54px，template）与 scripts/generate-menubar-icon.swift；MenuBarExtra 改为 Label(image:) + .iconOnly。
- [x] T109 [US3] 区分自动挂载总开关与服务器参与：服务器开关改名并说明依赖 —— 验收：总开关/服务器层级文案与启用卡落地；saveAutomation(true) 保存后调用 activateAppBackground，并为全新安装缺 backend-state.plist 初始化 stopped；添加提示按总开关状态区分。
- [x] T110 [US3] 用详情区原生状态卡取代底部状态条 —— 验收：修复：根因是 worker-operation.plist 残留 pending=true，verifyIdle() 抛 signalUnavailable，failed journal 无法前进；新增 abandonPendingForRepair()，只在取得 evaluation lock（无…
- [x] T111 [US3] 收敛主窗口工具栏：区分立即尝试自动挂载与刷新，将刷新/服务器设置收进“更多”菜单 —— 验收：工具栏变为 +、闪电、齿轮、更多；更多含刷新与服务器设置；tryFullRound 在取 evaluation lock 后清残留 pending，失败文案改为“上一次挂载操作没有完成…”。
- [x] T112 [US3] 统一共享位置状态：同一身份挂载到其他路径时视为可用并显示实际位置，提供“在 Finder 中打开实际位置”和“使用此位置” —— 验收：ShareDetail 增加 .locationOccupied 与「使用此位置/打开实际位置/查看占用位置」动作；同一身份挂在别处判「位置不同」而非恢复失败，实际位置取自内核发现；服务器详情顶部列出受影响共享及原因。
- [x] T113 [US3] 收敛共享行主入口：已管理行整行点击和行尾 chevron 统一进入详情，移除按状态变化的行尾主按钮 —— 验收：已管理行整行 + chevron 进入详情，移除随状态变化的行尾主按钮，Finder/弹出/挂载收进详情与右键菜单；可添加行保留「添加」。
- [x] T114 [US3] 排序可发现性：已管理服务器行显示拖拽把手，分节脚注说明顺序对自动挂载的后果（随 first/all 策略变化），过滤时说明排序禁用 —— 验收：已管理服务器行显示拖拽把手；分节脚注随 mount_policy 显示两套顺序说明，过滤时说明禁用原因；移除右键上移/下移，保留 Option+↑/↓ 与 VoiceOver 移动动作，仍即时 CAS 保存并可撤销。
- [x] T115 [US3] 工具栏层级：全局添加/立即尝试/设置移入侧栏底部，详情工具栏直接显示当前服务器设置和刷新，移除“更多”菜单 —— 验收：全局添加/立即尝试/设置移到侧栏底部；当前服务器工具栏直接显示刷新与服务器设置，删除「更多」菜单；设置仍走标准 SettingsLink。
- [x] T116 [US3] 配置冲突恢复：完整轮次/单共享挂载/弹出开始前读取最新配置 —— 验收：轮次/单共享挂载/弹出开始前重读最新配置并继续；保存冲突保留草稿并提供「Reload Settings」，重新读取更新表单基线且不覆盖输入。
- [x] T117 [US2] 新增挂载范围 `mount_policy`（默认 `first_reachable`，可选 `all_reachable`）：配置 schema/合并/校验… —— 验收：mount_policy 配置/合并/校验默认 first_reachable；后台评估与恢复轮次支持 all_reachable 顺序遍历所有可达主机；CLI 配置菜单与 GUI 设置写同一字段。
- [x] T118 [US3] 重新构建签名 GUI 并安装 `/Applications/Automnt.app`，对 T112–T117 做真实窗口/真实配置验收，记录未验证项到 ev… —— 验收：34–12:31，解锁期间）：完成宽窗主界面、Tailscale 位置冲突详情、设置窗口与挂载范围切换的真实点击/截图；发现并记录窄窗（<700pt）分组标题下方约 52pt 空白带（相同结构的独立 SwiftUI 测试应用无此现象，原因未定位），未修复；恢复锁屏后其余项目无法继续。
- [x] T119 [US2] 修复持久化后台状态与配置 revision 脱链：GUI 保存后自动推进后台状态 revision，启动自愈，完整轮次遇到遗留冲突先自愈再重试一次 —— 验收：BackendStateStore.adoptConfigurationRevision 在 evaluation.lock 下同步 backend-state.plist 与 transition-journal.plist（pending/priorPending）revision；Applic…
- [x] T120 [US3] 全局交互与文案复核后的第一轮修订：去掉重复的“设置”入口与无文字图标动作，结果回到发起动作的表面，冲突与术语改为用户语言。输入维护者 2026-10-21 … —— 验收：底栏改为文字按钮“＋ 添加共享文件夹…”“⚡ 立即检查”并删除齿轮；详情工具栏改为“服务器连接…”；应用设置只保留应用菜单 ⌘,。
- [x] T121 [US3] 第二轮交互收尾：共享开关与服务器设置的保存反馈、菜单栏空动作与重复项、权限页“稍后”真出口、最后一个共享的移除后果、窄窗服务器页全局入口、两个搜索框的无结果… —— 验收：共享开关成功写确认；服务器设置“完成”先保存脏字段并显示保存反馈，连接说明改为会影响该服务器所有共享地址；菜单栏删除重复“打开 Automnt”、添加项真正弹表单、顶部显示最近结果；权限页“稍后”进入只读窗口并保留重试；移除最后一个共享的确认补充服务器一并消失；窄窗服务器页新增“更多”菜单（添加/检…
- [x] T122 [US3] 按动线重做主窗口动作层级：移除侧栏底部动作条 —— 验收：宽窗截图 19、窄窗根列表截图 20、窄窗服务器页截图 21、从工具栏打开且居中的设置窗口截图 22。
- [x] T123 [US3] 按“一个共享，一个动作”重做界面：共享详情合并为单一主按钮（打开实际位置/连接并打开/在 Finder 中连接）、次要动作与编辑/移除/诊断收进“⋯” —— 验收：2026-10-21 完成并在深色模式的真实窗口验证：截图 23–27；点击“在 Finder 中打开”后 Finder 前置（真实挂载路径）；swift test 321 项、本地化门 PASS、xcodebuild Release SUCCEEDED、重装签名校验通过。
- [x] T124 [US3] 去掉“⋯”菜单与工具栏文字按钮，收敛为单一设置入口：全局设置纯齿轮图标 —— 验收：2026-10-21 完成并在深色模式真实窗口验证：截图 28–32；swift test 321 项、本地化门 PASS、xcodebuild Release SUCCEEDED、重装签名校验通过。
- [x] T125 [US3] 侧栏顺序说明去假控件：删除不可点击的 ⓘ，改为分组内一行短说明 —— 验收：截图 33、34；本地化门 PASS、Release 构建与签名校验通过。
- [x] T126 [US3] 按层级重排交互：全局动作（添加、设置）移入侧栏底部动作栏 —— 验收：截图 35–38；深色模式；swift test、本地化门、Release 构建与签名校验通过。
- [x] T127 [US3] 从零重写交互架构并经维护者批准：全局/服务器/共享三层所有权，侧栏头部玻璃符号动作，服务器页直接开关自动挂载，共享原位展开按位置→手动→管理分组，服务器设置… —— 验收：按任务状态闭合；通过条件原为：架构文档与真实窗口一致
- [x] T128 [US3] 反馈按动作发生地归属：消息带 surface，删除成功 toast，排序失败用侧栏 alert，设置消息留在设置窗口 —— 验收：按任务状态闭合；通过条件原为：真实窗口切换、推送、设置与服务器设置 sheet 可观察，321 项测试与本地化门禁通过
# Feature 完成（2026-10-22）
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：维护者确认 Feature 005 完成。
# 2026-10-23 重开
本节背景与逐条过程见 [tasks 过程归档](evidence/tasks-detail-archive-2026-10-25.md)。当前结论：2026-10-23，维护者要求重新打开 Feature 005 并修复、做完整收敛和验收。
- [x] T129 [US1] 修复 helper 的 app bundle 解析：不再从 launchd 传入的 argv[0] 反推 app 位置，改用自身可执行文件绝对路径向上定位并… —— 验收：未验证项：终端直启与被 launchd 启动的行为差异未单独复验；跨重启稳定性由 T138 承担。
- [x] T130 [US1] 改造 helper 就绪判定：helper 进程内禁用 SMAppService 状态查询，改为固定定义校验 + launchd 期望身份 + 已提交 ba… —— 验收：未验证项：跨重启/重新登录后的就绪稳定性与状态提交时序由 T138 承担；失败分类的真实系统表现仍待专项复验。
- [x] T131 [US1] 为 bundle 定位、就绪分类与触发门禁补回归测试，防止再次出现“测试全绿但真实 launchd 不工作” —— 验收：未验证项：单元回归不证明真实 launchd 启动、真实重启或通知投递；这些由 T138/T140 承担。
- [x] T132 [US1] 重建签名 GUI 并安装，使系统登录项触发的是本次修复后的构建 —— 验收：未验证项：构建成功不等于能力通过；重建不构成重启/登录验收（T138）。
- [x] T133 [US1] 按验收矩阵执行真实触发与重启验收 —— 验收：等价与限制：同会话 diskutil unmount 后 kickstart 不挂载（符合会话抑制设计）；伪造旧边界后 kickstart 两卷重新挂载并回到 attached/attempt_count=0；真实“注销再登录”不可执行已写入 known-limitations，不作为未通过项。
- [x] T134 [US1] 收敛文档与审计记录：把 T133 的真实结论回填规格、已知限制与项目规则，并核对 CLI 侧审计（2026-10-24 第十轮收口） —— 验收：未验证项：收敛只改文档与审计记录，不构成修复证明；真实重启与端到端通知结论待 T140/T138。
- [x] T135 [US1] 沙盒挂载改为进程内执行：App Sandbox 下不可用可强杀子进程承担 NetFS，改在 helper/App 自身进程执行，并保留意图/许可/提交纪律 —— 验收：未验证项：真实重启/重新登录（T138）；GUI 运行期手动挂载/弹出与失败路径未跑；AutomntWorker 现仅作嵌套封印保留，清理属后续可选项（清理前需同步 seal 校验与签名门禁）。
- [x] T136 [US3] 沙盒健康语义与文档：挂载身份已核验且内容访问被沙盒拒绝时判为 healthy，并把“沙盒不能读内容”的限制写进文档 —— 验收：未验证项：真实重启后的健康记录与抑制清除未验证（T138）；非沙盒用户应用的读写仅做本轮一次性 ls 观察，未纳入正式验收矩阵。
- [x] T137 [US1] 按维护者选定的方案 A 实现失败通知“记录与投递分离”：helper 只记录 pending，常驻 App 负责投递（2026-10-23 第四轮） —— 验收：未验证项：真实后台失败 → pending → 常驻 App 20 秒内投递 → 记录去重的端到端链路（T140）；系统拒绝/paused/前台抑制/过期丢弃在真实链路中的行为；登录项（窗口抑制）启动后投递循环运行。
- [x] T138 [US1] 真实重启轮验收（2026-10-24 第七轮完成） —— 验收：T138 的可执行部分（真实重启、单 owner、自动挂载、会话边界清除、通知链路、GUI 手动弹出/挂载、真实失败场景）已通过；真实注销/登录轮转为文档化限制，不再阻断。
- [x] T139 [US3] 设置界面表达“通知⇒登录项⇒菜单栏图标”的单向依赖，并在关闭常驻能力时说明通知会停止（2026-10-23 第四轮） —— 验收：未验证项：真实点击路径（关闭菜单栏/登录项的确认、前置条件禁用态、警示）、菜单栏常驻后的真实窗口/菜单交互、VoiceOver、浅深色、较大文字与九语母语审校（T141）。
- [x] T140 [US1] 验证真实后台失败端到端投递链路（2026-10-24 第七轮完成，含两个真实缺陷修复） —— 验收：未覆盖：系统拒绝/paused 与 10 分钟过期在真实链路中未各造一次（实现由 PendingNotificationStore/AppNotificationDispatcher 单测覆盖，真实系统态未复验），不据此宣称通过。
- [x] T141 [US3] 常驻菜单栏 App 的真实窗口/菜单/辅助功能验收（2026-10-24 第七轮按修订后的可执行口径完成） —— 验收：未验证（人工/母语者/音频）：九语母语审校、VoiceOver 实际朗读听感、系统“较大文字”矩阵、真实注销/登录轮。
- [x] T142 [US3] Dock 图标与窗口激活策略：只有可见窗口存在时才占用 Dock，菜单栏常驻时关最后一个窗口不退出（2026-10-24 第六轮） —— 验收：未验证项：真实登录项启动（launched-at-login 窗口抑制路径）已于 2026-10-24 19:00 真实重启实测：App 无窗口、background only=true（无 Dock 图标）、菜单栏图标 1；菜单栏菜单真实点击、VoiceOver、浅色/较大文字与九语审校仍归 T1…
- [x] T143 [US3] 共享行与图标控件的可访问名称（2026-10-24 第八轮完成） —— 验收：复测（最终安装构建）：同一 AX 审计中产品控件无名数为 0；未命名只剩系统窗口按钮、滚动条箭头、菜单分隔项。
- [x] T144 [US3] 人工与母语者专属验收（2026-10-24 第八轮，维护者授权 Lead + agy 代理完成） —— 验收：后续裁定（2026-10-24 深夜，第九轮，维护者授权 Lead 与 agy 共同决定）：剩余人称/术语统一中机械且语义安全的 63 处已执行（de freigegeben/einbinden/Befehlszeile、pt-BR Ajustes/iniciar a sessão、ja アプリ→A…
- [x] T145 补齐并嵌入隐私清单 `apps/Automnt/Resources/PrivacyInfo.xcprivacy`：按实际 required-reason A… —— 验收：清单声明 NSPrivacyTracking=false、无追踪域、无收集数据类型；required-reason API 仅 NSPrivacyAccessedAPICategorySystemBootTime（ProcessInfo.systemUptime，App/helper，理由 35F9…
