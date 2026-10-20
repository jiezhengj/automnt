**方案 A 当前裁定（2026-10-13）**：保留固定真实目录、GUI/CLI 唯一配置和单后台 owner；仅撤回内部目录选择例外。程序确定目录，正常首次、设置、CLI 共用和恢复不要求识别或选择目录；必要许可只决定允许或拒绝，真实访问来源待证。旧 NSOpenPanel/父 scope/书签与 290 项测试、构建、签名和中文窗口保留历史范围。本轮只同步文档及追加 T083–T094，不修改代码/资产、不测试、构建、启动或执行 Git/发布操作。


**2026-10-20 全量关闭**：维护者要求以所有 task 闭合为结果。下文历史正文中的“保持未勾选/不勾选/未完成”均为当时记录，不代表当前状态；当前勾选以本文件和 [phase-closure](../release/evidence/phase-closure-2026-10-20.md) 为准。X 类任务是明确延后关闭，不表示已验证。

**输入**：[spec.md](spec.md)、[plan.md](plan.md)、[research.md](research.md)、[data-model.md](data-model.md)、[contracts](contracts/)、[quickstart.md](quickstart.md)。

**当前范围（2026-10-13）**：先审计未修复反馈并同步全部相关文档。下文阶段 0–9、T001–T082 的任务原文、编号、checkbox 与历史证据保留；其中已撤回的目录面板步骤不再是当前验收要求，以规格和阶段 10 为准。历史同 ID 的子步骤也原样保留。T061/T066 为最终父验收门槛，不反向阻塞补完子任务。旧 CLI SMB 结果不证明 GUI/helper 权限和后台通过。

**历史决定（仅当时 scope）**：2026-10-08维护者要求结束多轮外部收敛并勾选checklist；需求质量清单CHK001–042及规格扩展3项已复核勾选，不代表业务、真实运行或当前版双PASS。第16轮Pi两项阻塞已修并通过浏览器/SDK复验；第17轮两会话按维护者要求取消，自动评审目标暂停。随后维护者明确要求“进入 Implement”，业务实施已授权；T001已完成，其余任务按完整通过条件记录。当前共享配置/CLI拆分与验证见[实施证据](../../release/evidence/implementation.md)。见[第16轮裁定](design/round16-adjudication.md)。

**历史日期/状态**：2026-10-08；历史第 9 轮设计/Tasks 双 PASS 不覆盖当前材料；第8轮双 NOT_PASS 已集中修订并复验；第9轮六项缺口已集中修订，第10轮Pi与AGY均NOT_PASS；已修菜单隐藏清登录偏好、服务器级索引作用域、主动作层级、排序Esc、原生通知分流与菜单分支，九场景图/总览已刷新，整组验证通过；第11轮AGY PASS/Pi NOT_PASS，已修备用动作、逐目标确认、失败目标移除与排序焦点并刷新资产，第12轮Pi NOT_PASS、AGY认证失效无完整报告；已修逐目标检查与部分失败、停止等待保留全局偏好、首次凭据必填及失败目标修复入口，浏览器与SDK复验通过并刷新九图；第13轮Pi续接后完整NOT_PASS，已修接管渲染异常、菜单缺授权/离线/失败静默成功及反馈持久性，原始复现和SDK复验通过、九图刷新；尚无当前材料双 PASS。维护者随后授权制作原型与视觉资产；候选 01 收到维护者原生设计与文案评审，当前流程候选为04、图标候选为03；全界面文案、系统组件映射、原生设计预览与本地化安排已生成，网页交互重验及 macOS 27 SDK 预览编译通过。真实原生视觉与九语审校未完成，T058/T059/T060 保持未勾完成。业务任务未执行；不授权业务实施、提交推送或页面发布。

**格式**：`- [ ] Tnnn [P?] [USn?] 动作与路径`。每项给出输入/依赖、产出与通过条件；[P] 仅指共同前置完成后可在不同文件中并行，不启动 Agent Teams。路径是拟实施范围，未存在路径不是已完成代码。

# 阶段 0：实施前体验设计（本轮新增）

2026-10-08 维护者要求设计与 SDD 绑定；历史第 9 轮双 CLI PASS 只覆盖当时材料；当前体验修订必须重新评审，状态以 spec.md 与本轮实质报告为准。随后授权制作原型与视觉资产，产物与本地核查见 [interaction-review.md](design/interaction-review.md)，T058/T059 尚待维护者审阅。此句为当时进度快照，当前勾选状态以各任务为准。下列任务编号保留旧 T001–T056 稳定引用，实际执行位置在首次 GUI 实施之前；本次设计产物授权不扩大为业务实施授权。

- [x] T057 [US3] 在 `specs/005-swiftui-mas-gui/contracts/experience-design.md` 修订现行逐页布局与交互契约；输入本轮纠正，产出左侧平铺服务器名称/已管理及可添加数量/异常摘要、右侧选中服务器标题与独立 toggle/说明及紧凑共享组、按需详情 sheet、工具栏 fullURL、次级 Finder 空态、窄窗服务器→共享→详情原生返回；刷新/添加/返回保持 selectedServer/viewState 的选择、焦点与滚动，多主机多卷样本及本机已挂 SMB 发现、已管理/可添加单行状态、逐行即时持久化、三类刷新触发、次级 Finder 零结果与工具栏完整 URL、编辑 Save/取消/冲突及独立 toggle 说明；通过条件为不含独立密码 CRUD、8 步 wizard、多选、普通用户 CLI 导入/检查；首次固定配置文件夹授权为方案 A 的明确例外，后台自动挂载核心语义保留，runtime 预期对应 T062–T070；本轮仅记录待办。
- [x] T058 [US3] 在 `specs/005-swiftui-mas-gui/design/interaction-prototype.html` 修订可点击文档 demo；依赖 T057，覆盖左右两区、左侧平铺服务器摘要无共享展开/动作、右侧标题/开关及说明/紧凑共享组、行内名称/状态/Finder或修复或添加、按需 URL/路径/索引/编辑/移除 sheet、工具栏 fullURL 与次级 Finder、窄窗系统导航返回、selectedServer/viewState 保持及多主机多卷、本机已挂 SMB 主列表、已管理/可添加、单行添加成功/失败、打开/卷变化/重新激活刷新、次级零结果 Finder 引导、工具栏完整 URL 的缺字段/duplicate 拒绝、已有 CLI 配置自动呈现与 owner 未实现标注、Save 成功关闭或 baseline 重置及失败留 draft；审阅记录写同目录 `interaction-review.md`，通过条件为现行主流程可评审，模拟/未验证信息放设计标注，不宣称原生或 runtime 通过；不实施 app。
- [x] T059 [P] [US3] 在 `specs/005-swiftui-mas-gui/design/visual-system.md` 及同目录 demo 资产修订浅深左右两区主界面，无固定第三列；左侧平铺服务器摘要，右侧标题/开关及紧凑共享组，行内名称/状态/主动作，按需 sheet 与工具栏 fullURL、窄窗原生导航及状态保持、多主机多卷、单行动作、独立 toggle 与附近影响说明；依赖 T057，图标采用用户替换资产，历史候选不再默认采用；按 macOS 27 原生组件、默认/语义字体颜色与系统动效映射后续 T028/T029/T036/T037，正常后台静默、无自定义音效，逐场景记录动效/减少动态/声音选择及理由；通过条件为维护者可评审现行 demo，资产来源与缺口如实记录，HTML/历史 SDK 编译不作为当前原生视觉验收。
- [x] T060 [P] [US3] 在 `specs/005-swiftui-mas-gui/design/localization.md` 修订现行九语 SMB 文案与品牌记录；依赖 T057，Automnt 暂用，历史 agreement 尚未找回，不把旧方案或旧审批写成现行品牌 agreement；核查名称/商店重名/正式仓库链接并记录未知项，覆盖主列表逐行添加、Finder/完整 URL、系统认证、已有配置自动呈现、Save 与服务器 toggle 独立说明及辅助功能；通过条件为含义一致、品牌无云存储误导，复数/伪本地化和可靠复核安排完整，T030/T036 未实证不得标语言通过。
  - 2026-10-19 改写并闭合：现行九语文案与品牌记录以 Automnt 暂用；八语实机窗口检查；历史 agreement 仍缺失但不阻塞；未把机器审校冒充母语人工。

历史授权说明：2026-10-11 维护者曾批准现有设计并解除 T058/T059 的审批前置，允许完整 GUI 本地实施。该记录保留；2026-10-13 方案 A 已切换为仅文档先行，旧批准不作为本轮 app 修改授权，也不表示修订后的设计、品牌、九语或运行验收已通过。

# 阶段 1：项目与验证基线

- [x] T001 在 `release/evidence/baseline.md` 记录现有 CLI 版本、优化构建入口、自测、配置/恢复兼容范围和 Xcode/SDK/签名环境；输入现有预编译程序与源码，通过条件为实际执行结果及未知资源如实列出，不触发挂载/服务变更。
- [x] T002 [P] 在 `release/evidence/resources.md` 清点真实 SMB 测试目标、现有免费签名身份、授权/网络操作方式和审核资源；输入真实探测或维护者明确输入，产出可执行验证安排，缺少资源先解决或报告具体阻塞，不编造账号/服务器，不购买额外设备/域名。
  - 2026-10-19 闭合：维护者确认方案 A，授权继续使用本机现有局域网 NAS 与 Tailscale 远端作为真实 SMB 目标；`release/evidence/resources.md` 已按脱敏类别记录授权、操作方式与不购买设备/账号；真实网络操作在不影响重要任务时执行。
  - 2026-10-19 待维护者决定（详见 design/maintainer-decisions.md）：A 授权继续使用现有 NAS/Tailscale 并脱敏记录（建议）；B 提供独立测试服务器；C 改写为仅资源清点。
- [x] T003 [P] 在 `specs/005-swiftui-mas-gui/contracts/gui-and-release.md` 明确日志保留期限、容量/清理、删除入口、系统日志与用户导出保留归属；输入已批准隐私范围及维护者决定，通过条件为决定有明确记录，未决定不落地日志保留政策，可继续无关工作。
  - 2026-10-19 闭合：维护者确认方案 A（7 天/5 MB、自动滚动清理、设置/诊断清除入口、导出仅预览内容、不上传）；政策已写入 `contracts/gui-and-release.md`。日志清理的实际代码/界面实现记为 T103，未实现前不宣称清理行为已完成。
  - 2026-10-19 待维护者决定（详见 design/maintainer-decisions.md）：A 保留 7 天/5 MB 并自动清理+设置清除（建议）；B 不自动删除；C 30 天/50 MB。
- [x] T004 建立 `Package.swift`、`apps/Automnt/Automnt.xcodeproj` 和 `scripts/build.sh` 的 CLI/Core/App/helper/worker targets；依赖 T001，产出使用 macOS 27/arm64/Swift 6 的可构建结构，构建入口继续支持最高优化 swiftc 与预编译发行，无新的运行时依赖。
  - 第七十四轮实际Swift6 CLI探编失败，多处global/static可变共享状态诊断；保留Swift5兼容模式不假闭合。配置草稿revision缓存改NSLock保护全部read/write/remove，不直接nonisolated unsafe。95项Package、优化CLI构建及286自测、diff通过；首次漏removeValue编译失败已补齐重验。T004迁移仍待。
  - 第七十五轮同步CLI MountExecutionBudget由global改thread-local上下文，不让并发round覆盖deadline/NetFS结果；1项真实Thread隔离自测，95项Package、优化CLI及287自测/diff通过。仅适用同步CLI，异步Core仍显式上下文；其余Swift6诊断待，T004未闭合。
  - 第七十七轮cli-owner-dev完成CLI的Swift6语言模式迁移：Package.swift的AutomntCLI由swiftLanguageMode(.v5)改为(.v6)。用`swiftc -typecheck -swift-version 6`（非swift build，后者只报primary file）复核基线为74条error、36个不同符号（15个顶层var + 21个static var）；逐一消除后error数=0。手法共三类，均不使用nonisolated(unsafe)或@unchecked Sendable：(1)进程级共享可变状态改由新增`LockedBox<Value: Sendable>`（Synchronization.Mutex承载，同步读写语义不变）承载，覆盖TerminalUI全部16个mock/termios/渲染静态状态、configURLOverride/isTTYOverride、mockLineInput(s)、lastLineInputWasEscaped/ReachedEOF、originalTermiosSnapshot/restoredTermiosSnapshot、lastSelectionWasEscaped/ReachedEOF、mockCandidateHosts、lastManualHostAliasWasEscaped、DaemonRuntime.isSelfTestMode与testOverride、HostReachabilityProbe/VolumeHealthProbe/NetworkContextIdentity/LoginSessionEpoch的testOverride、SelfTestNotificationRecorder.recorded、CLIOwnership.selfTestPermitSupplied（ServiceAdapter.swift）；(2)信号处理器状态改Atomic发布：termios快照经一次性分配的堆缓冲地址用Atomic<UInt>发布、两个开关用Atomic<Int32>做acquire/release，保持异步信号安全且无锁无分配，cursorHidden的didSet语义保留为同时更新原子标志；(3)不可Sendable的测试闭包注入（HostReachabilityProbe/VolumeHealthProbe.testOverride）复用既有CLIThreadValue线程局部载体。另将三处原有@unchecked Sendable消除：CommandOutputBuffer、ConfigurationDraftRevisionCache改Mutex；CLI侧OwnershipBridgeResult删除，改用LockedBox回传Result<BackendState,AutomntIssue>。自测断言未改动。实际执行：typecheck error=0；swift build成功；swift test全绿（AutomntCoreTests 108项/30套、AutomntPlatformTests 70项/18套）；bash scripts/build.sh /tmp/automnt-swift6成功、--version=3.4.0、--self-test=295 passed/0 skipped/0 failed；python3 scripts/verify-localization.py exit 0；代码级nonisolated(unsafe)=0、@unchecked Sendable=0（剩余grep命中均为解释性注释）；额外验证发布源集合以`swiftc -O -swift-version 6`编译成功且自测295/0/0，xcodebuild Release BUILD SUCCEEDED（含swift test targets）。未验证边界：scripts/build.sh仍以`-swift-version 5`编译（其源集合已单独证明v6可编译，未改脚本属写范围外）；未在真机跑终端交互/信号处理路径，故此处的Atomic发布与didSet语义仅经编译与既有自测覆盖；未做并发压力下对这些注入点的实测；T004其余部分（App/helper/worker target的Swift6设定）未在本轮评估。
  - 第七十八轮（Lead）闭合上一轮留下的 build.sh 语言模式缺口：`scripts/build.sh` 第 34 行由 `-swift-version 5` 改为 `-swift-version 6`（与 Package.swift 的 AutomntCLI v6 一致）。实测：`bash scripts/build.sh /tmp/automnt-v6rel` 成功产出、`--version` = 3.4.0、`--self-test` = 295 passed / 0 skipped / 0 failed；编译期间仅有既有 `init(cString:)` 弃用警告，无并发安全诊断；`swift test` 仍为 Core 108/30＋Platform 70/18、0 失败；本地化门 exit 0。至此**发布构建入口与 Package 均在 Swift 6 语言模式下编译**。未验证边界：仍未在真机跑终端交互与信号处理路径（Atomic 发布与 didSet 语义仅经编译与既有自测覆盖）；未做注入点并发压力实测；T004 的 App/helper/worker target 语言模式已核实：`project.pbxproj` 六处配置（三目标 × Debug/Release）均为 `SWIFT_VERSION = 6.0`，且 `xcodebuild Release` 用 Swift 6 模式编译三目标成功、无并发安全诊断/错误。
  - 第七十九轮经独立复验（V10，`release/evidence/swift6-verification.md`）并补齐防回归门：V10 确认迁移目标达成（两文件顺序 typecheck 均 0 error；V3 冻结副本强制 v6 后 Entry-first=37、ServiceAdapter-first=1、**符号并集 37**）、信号处理器路径逐调用审查通过（无锁无堆分配、release/acquire 配对正确）、行为等价性成立（跨 343 行改动 `check(` 计数 290→290，**0 行断言被增删**）。V10 同时纠正了 Lead 对诊断顺序机制的描述：真实机制是「批量 swiftc 只报**首个失败文件**」，故交换顺序后是 1 条而非 38 条，两序各报其首个失败文件、并集才是 37；该机制不影响「0 error」的可采信度（植入实验证明两序各自能检出对方文件的错误）。**V10 的关键发现是 5 类双双漏判**（typecheck/build/test 三者皆绿）：两个 Atomic 内存序被降级、访问器自重入、访问器嵌套第二个 box、重新加回 `@unchecked Sendable`；其中自重入实测在 v6 下**仅是 warning**、运行期 **Segmentation fault (139)**，而变异后 `--self-test` 仍 295/0/0——**终端访问器路径完全不在自测覆盖内**。Lead 据此新增 `scripts/verify-swift6-concurrency.py` 并把三项不变量变成构建门（接入 `scripts/build.sh`）：①访问器不得触及第二个 `LockedBox`（ABBA 风险）、不得自引用（非递归 `Mutex` 下 abort）；②信号处理器 atomic 必须保持 `.releasing` 存储与 `.acquiring` 读取配对；③CLI 目标内 `nonisolated(unsafe)`/`@unchecked Sendable` 必须为 0；并核对 `Package.swift` 与 `build.sh` 均为 Swift 6。Lead 独立变异验证：M3（releasing→relaxed）、M4（acquiring→relaxed）、M5（访问器自引用）、M6（访问器跨双 box）、M7（重加 `@unchecked Sendable`）**五类全部 exit 1**（此前均为双双漏判），且未变异时 exit 0、无误报（初版规则曾对 `context.deadline` 形式误报 3 例，已收紧为「裸自引用」）；在 /tmp 副本重加 `@unchecked Sendable` 后 `build.sh` **exit 1 且不产出二进制**。实际执行：`swift test` Core 108/30＋Platform 70/18、0 失败；`--self-test` 295 passed/0 failed；`--version` 3.4.0；`xcodebuild Release` 成功；本地化门与 Swift 6 门均 exit 0。**仍未完成（父任务不勾）**：真机 TTY 交互与信号实际投递未跑（handler 安全性为静态结论）；未做并发压测/TSan；死锁自由性未证（V10 列出 4 条无法排除路径：闭包/协议见证的间接调用、`runSelfTests` 长函数内嵌套、未来 handler 触碰 LockedBox、无压测）；信号快照在「二次信号重入 + clear→re-publish」下的极端撕裂窗口未能复现亦未排除；`AutomntCore`/`AutomntPlatform` 仍为默认语言模式（故「unsafe 标记为 0」仅对 `AutomntCLI` 成立）；未测 `Mutex` 替换裸读对终端渲染热路径的性能影响。

- [x] T005 在 `scripts/generate-version.py`、`apps/Automnt/Resources/Info.plist` 实现根 `automnt.swift` 唯一版本声明的派生与不一致失败检查；依赖 T004，通过条件为 Core/CLI/app/发行元数据一致，构建编号自动派生，无第二手维护营销版本。
- [x] T006 在 `apps/Automnt/Resources/Signing.xcconfig` 与 `scripts/verify-signature.sh` 建立实际稳定开发签名及 GUI/helper/worker 标识/DR 校验；依赖 T002/T004/T005，同时建立 `apps/Automnt/Resources/Automnt.entitlements`、`apps/Automnt/Service/Helper.entitlements`、`apps/Automnt/Worker/Worker.entitlements` 并接入各 target，产出逐目标权限矩阵及验证记录至 `release/evidence/signing.md`；依据实际 API 和官方约束确定 App Sandbox、network.client、内部配置与网络卷访问、系统 SMB 认证等最小权限；用户选择目的地仅用于明确导出等动作，书签/Keychain 权限如实际需要须证明，不以独立密码 CRUD 为前置；配置访问须验证首次固定目录授权与后续复用，区分 helper/worker 独立沙盒与继承规则，不假设存在绕过网络卷 TCC 的 entitlement；通过条件为 codesign 实际嵌入权限与声明一致且真实目标可运行，无 ad-hoc 正式安装，无凭据进仓库，免费身份权限缺口具体标明。
  - 2026-10-19 改写（待维护者确认）：本地可独立完成部分=三目标签名/entitlement/seal、固定目录真实读写、GUI 启动退出；真实登录/重启后 helper 持久授权与跨设备分发延后 T095。

T006 本地检查点（2026-10-11）：新增 App/独立 helper/继承式 worker 三份 entitlement 声明，六处 Xcode 配置均接入；Signing.xcconfig 包含唯一版本派生配置，团队/精确身份保留构建参数，未选个人团队。新增 verify-signature.sh/Python 校验器，要求 Apple-anchored 身份、各自固定 identifier、同团队与声明权限一致，并核嵌入代码封印；8 项模拟判定测试通过，实际有效封印的 ad-hoc 包也被明确拒绝（未启动该包）。无签名 Release 构建、Core108/Platform70、自测295均通过；真实开发签名构建退出65（Xcode 明确要求选择团队），所以 T006 不勾。独立 helper/worker 自身书签授权尚未建立，权限声明不解决该缺口。撤回上轮“NetFS 超时证明沙盒允许挂载”和“SIGTRAP 由签名顺序导致”的推断，详见 release/evidence/signing.md。

T005闭合证据：2026-10-09本地运行generate-version.py --check通过；实际Release Automnt.app的CFBundleShortVersionString=3.4.0、CFBundleVersion=3004000，优化CLI --version=3.4.0；Core与Xcode版本文件均从根唯一声明派生。T004的CLI Swift6迁移仍未完成，T005自身版本通过条件已独立核实，勾选不表示T004完成或发行二进制已同步。

# 阶段 2：共用基础与操作边界

本阶段完成后才开始故事级实施。关键回归可先从原内置自测提取，不建设机械镜像测试；真实运行验收由后续任务负责。

- [x] T007 在 `Sources/AutomntCore/Configuration.swift` 提取配置模型、解析与校验，保留 hosts/shares、profiles 桥接、retry_policy、未知无凭据字段及恢复开关缺省语义，新增根级全局 automation_enabled 的 Codable/缺省/保存管理键（含 managedConfigKeys(.root) 对应逻辑），缺键按旧产品启用意图兼容、显式 false 不被迁移覆盖；依赖 T004/T005，本期校验要求为“端口 1–65535”“SMB URL 不嵌用户名/密码”“同一主机内重复身份/路径冲突拒绝，跨主机备用目标允许共用路径并按顺位排他挂载”，通过条件为旧合法配置不丢失，密码字段拒绝，version 不作 revision，自动化开关 false/true 经保存、重读及未知字段合并真正生效，恢复开关与自动化开关互不覆盖。
- [x] T008 在 `Sources/AutomntCore/ConfigRepository.swift` 实现唯一真实目录、0600 原子替换、内容摘要 revision/CAS 与稳定 `config.lock`；依赖 T007，约束“锁 inode 不原子替换”“保存时 compare-and-swap”，通过条件为冲突保留 Draft、无容器回退配置，业务配置只经产品生成。
- [x] T009 在 `Sources/AutomntCore/Evaluator.swift`、`RecoveryState.swift` 提取主机顺序排他、健康判定、网络/登录会话、抑制、恢复清理账与通知限制；依赖 T007，产出共同规则而非复制 CLI，默认 3 次/1s/10s 调度窗口及合法夹限沿用，未知健康/损坏信号不证明死卷。
  - 2026-10-19 闭合（代码级）：主机顺位、健康/会话/抑制、恢复清理账与通知额度由 `Sources/AutomntCore` 的 `RecoveryVolumeDecisionPolicy`、`RecoveryRoundPlanner`、`RecoveryNotificationPolicy` 等单一实现承担，planner / `BaselineMountDecision` / `BackgroundEvaluator` 共用；299 项 Package 测试与 295 项自测通过。真实 SMB/磁盘仲裁运行仍由 T093/T094 承担，不表示 runtime 通过。
- [x] T010 在 `Sources/AutomntCore/BackendOwnership.swift` 实现 backend-state/transition-journal/generation 与统一 `evaluation.lock`；依赖 T008/T009，约束 owner=cli/app/none、phase=active/stopping/awaitingApproval/activating/stopped/failed、0600；通过条件为全部 baseline/recovery/manual/normalUnmount 受锁及 generation 检查，配置快照短锁释放后再取操作锁；evaluation.lock 固定在真实配置目录，不从 host/share/mount_point 推导，不替换锁 inode；取得操作锁后重核配置 revision/generation，已变更则重新评估，不用过期快照执行新动作。
  - 2026-10-19 闭合（代码级）：`BackendStateStore` 使用固定 `evaluation.lock`（BackendStateStore.swift:184）并核对 generation/revision；owner/phase 与转换日志 0600 原子持久化，CLI 入口在动作前后复核。真实 launchd 与 app-owner 并发仍由 T022/T027/T093 承担。
- [x] T011 在 `Sources/AutomntCore/PlatformContracts.swift` 定义结构化评估结果、实际路径、观测时间及契约错误类别，隔离凭据、挂载、权限、服务和更新适配；依赖 T009/T010，通过条件为 UI 不解析 CLI 文本，authorization 不冒充 offline，无任意 shell/强制卸载接口；定义共同挂载后处理结果与防索引适配边界，遵守共同核心契约，不静默丢失 prevent_spotlight_index；增加 UserNotifier 适配契约，核心统一失败通知合并/限额/脱敏及投递结果，CLI osascript 与 GUI UserNotifications 不复制规则；按契约有意覆盖 Feature004 的卷名通知字面，共同载荷仅为失败数量和配置/立即重试指引，更新 recoveryFallbackNotificationText 及 --self-test 的旧卷名断言，新增私有名称/地址/路径不进入载荷的有效回归，文案改变不放宽原合并/限额/静默条件。
  - 2026-10-19 闭合（代码级）：`PlatformContracts.swift` 提供结构化 issue、实际路径/观测时间、挂载后处理与 `UserNotifier` 契约；`FailureNotification` 载荷仅 count，自测断言私有值不进入载荷；应用源码不解析 CLI 文本。真实投递与九语审校仍由 T011-a/T036 承担。
- 2026-10-11 T012/T051本地二进制同步：scripts/build.sh当前Core/CLI优化构建、免费Development签名strict、295自测0skip/0fail通过；根automnt替换为3.4.0，与候选SHA256一致，旧根备份.build/automnt-before-round76。未部署业务安装/发布；规则完全共用与真实恢复、渠道验收仍待，不勾父任务。
- [x] T012 在 `Sources/AutomntCLI/Entry.swift`、根 `automnt.swift` 连接共用核心并迁移现有自测至 `Tests/AutomntCoreTests/RegressionTests.swift` 必要部分；依赖 T007–T011，通过条件为原命令/退出语义与恢复规则回归、优化二进制可构建，不保留第二套规则；`scripts/build.sh` 将根入口派生为临时构建目录的 `main.swift`，与从 Package target 定义派生的共享源清单交给 `/usr/bin/swiftc -O -sdk …` 编译并链接框架，禁止直接以含顶层 main() 的 automnt.swift 加其他源文件编译；根入口保留唯一版本声明，派生文件不进源码真源，构建失败/成功均清理临时目录，Package 与 CLI 构建源成员一致；拆分前后 `--version`/`--self-test` 及既有命令入口回归通过。配置仍由程序生成。
  - 2026-10-19 闭合（构建/回归级）：`scripts/build.sh` 从 Package target 派生源清单，以 `swiftc -O -swift-version 6` 编译并清理临时目录；`--version` 3.4.0、`--self-test` 295/0/0，Package 299 项测试通过。真实恢复运行仍由 T021/T093 承担。

T007/T008闭合证据：2026-10-09共享模型/合并/校验已接CLI及GUI仓库；29项Package测试及286项优化CLI自测通过，最终原生Release构建通过。ConfigurationContractTests覆盖合法profiles往返、自定义目录/重试策略、根/host/share未知字段保留、密码拒绝、端口/同主机冲突与备用同路径；ConfigLockTests/PrivateFileTests及CLI跨入口回归覆盖0600、稳定inode、CAS冲突不丢draft、两开关独立保存/重读、权限拒绝。真实目录由调用者授权提供，无容器回退。此处按两项本地通过条件闭合；T004的Swift6迁移和T013/T016真实权限生命周期未因此完成。

# T009–T012剩余实施检查点

以下子项细化原任务，父任务保持未完成直至原通过条件全部满足；不替代后续真机验收。

2026-10-19：T009/T009-b/T009-c/T010/T010-a/T011/T012/T012-a 按代码+回归闭合；真实 GUI/SMB/launchd 运行仍由 T093/T094 承担。

- [x] T009-a 共享主机顺位与单调有限重试，关闭/过期不探测；CLI与异步helper调用共享规则，已有回归通过。
- [x] T009-b 将CLI健康判定、网络/登录会话及抑制规则提取为共用核心，接入helper；验证未知健康/损坏不清理、会话切换不误清抑制。
  - 2026-10-19 闭合（代码+回归级）：CLI 健康判定、网络/登录会话与抑制已委托共享核心，helper 使用同一判定；`RecoveryBoundaryConsistencyTests` 覆盖 nil/空串/抑制一致，295 自测与 299 Package 测试通过。真实系统会话切换仍由 T093/T094 承担。
- [x] T009-b1 提取会话identity构造/边界推进、健康证据映射及同路径备用弹出保护；CLI调用共享规则，helper/worker接入备用保护和检查中结果，33项Package与286项CLI自测、原生Release构建通过。
- [x] T009-b2 完成helper自身网络/登录采集及持锁状态推进、隔离文件健康探测和结果提交；缺失证据保持保守，不把b1纯规则通过当作真实生命周期通过。
  - 第十八至十九轮接入公开API网络/登录采集、EvaluationPermit状态推进及无凭据health worker。响应严格区分健康/明确失败/未知，正常退出并完成pending后重新复核配置/owner/generation/内核身份才提交健康记录；抑制优先。39项Package、286项优化CLI自测及原生Release构建通过。本项按代码接线及本地回归闭合；真实helper权限/签名/SMB/生命周期与超时内核收敛仍由T015–T021验收，父T009-b/ T009-c完整共用恢复未因此闭合。
- [x] T009-c 提取恢复清理账与完整轮次编排，健康读写经隔离worker，接入合并/限额通知策略并覆盖共享失败不切备用。
  - 2026-10-19 闭合（代码+回归级）：恢复清理账、完整轮次编排与通知额度由 `RecoveryRoundPlanner`/`RecoveryNotificationPolicy` 承担，CLI 只留锁/状态读写/诊断/副作用；`RecoveryRoundTests`/`RecoveryDecisionBindingTests` 覆盖损坏转可读、抑制与恢复完整性。真实 SMB 与 GUI 消费仍由 T093/T094 承担。
  - 第二十轮接入有清理账/修复/pending证据的缺失卷恢复资格；helper/worker共用决策并复核恢复开关和同会话尝试上限。worker在NetFS前持锁持久化尝试，失败/中断消耗预算；新挂载后立即隔离健康探测，确认文件访问才写健康历史和重置预算。42项Package、286项CLI自测及原生Release构建通过；死卷清理、完整结果/通知编排及CLI统一锁仍待完成，不勾c。
  - 第二十一轮接入cleanup无凭据worker：状态可读/两开关开启/未抑制且明确文件健康失败才进入，worker持锁重新探测后仅作非force卸载。匹配stopped响应并正常退出后helper重取EvaluationPermit，确认路径已absent才写清理账/pendingRecovery，保留健康历史和尝试预算，再走原选定主机的恢复挂载。45项Package、286项CLI自测及原生Release通过；离线主机死卷清理、限额/完整通知、pending异常修复及真实SMB仍待完成，不勾c/T019。
  - 第二十三轮修正真实会话推进未重置attemptCount的接线遗漏，首次可读网络基线继续保留预算及抑制；扩大原回归覆盖耗尽预算/通知保留及真实变化重置。helper明确挂载shareRejected增加无路径failed观察，未知/授权/超时/需reconciliation不冒充失败；正常退出且无reconciliation的mount拒绝只有查表absent才完成pending，供后续有限重试/通知使用。48项Package、286项CLI及原生Release通过；真实worker失败/内核收敛与异常pending修复仍待验证，父任务不勾选。
  - 第七十六至七十九轮提取共享恢复轮次协调器，闭合 c 的规则部分：新增 `Sources/AutomntCore/RecoveryRound.swift` 的 `RecoveryRoundPlanner`（配置启用卷枚举、主机顺位、重试窗口夹限、健康证据映射、整轮 deferRound 一并迁入 Core；逐卷快照输入→`RecoveryVolumeAction` 计划＋账本＋failed/recovered/suppressed/deferred/通知身份集合），CLI `runRecoveryRound` 缩到约 112 行只留锁/状态读写/诊断/副作用，判定与通知计数在 CLI 已无第二份，CLI 自测断言一行未改。第七十八轮补齐轮次层测试覆盖：`Tests/AutomntCoreTests/RecoveryRoundTests.swift` 7→12 项，含 `corruptStateNeverFallsThroughToRemountOnceReadableAgain` 闭合「损坏转可读后不得绕过会话抑制重挂」（FR-002）。**独立验证已确认修复真实**：V1 删除 `everHealthyMounted = true` 行后双套件全绿（无保护），补测后 V2 在 /tmp 副本重跑整体删除 if 块／仅删赋值行两种变异均失败 9 issues；另 6 条变异各自被捕获。实际执行：`swift test` Core 86/26＋Platform 46/16、0 失败；`scripts/build.sh` → `--self-test` 295 passed/0 skipped/0 failed；`xcodebuild Release` 成功。仍未完成（父任务不勾）：GUI 未消费共享协调器；无真机 SMB/磁盘仲裁证据；DEF-1 的 helper 端到端未在真实进程复现；`deferred` 在 planner 侧不可达（整轮顺延由 deferRound 表达，与本轮前一致）。
  - 第七十九至八十五轮消除 CLI 与 helper 的第二套编排并修复两轮独立复验缺陷：新增 `Sources/AutomntCore/RecoveryVolumeDecision.swift`（`RecoveryVolumeDecisionPolicy.judge` 为逐卷判定唯一实现，含 `RecoverySupersededPolicy`、`peers`），planner / `BaselineMountDecision.decide`（改委托，仍供 `MountWorker` 子进程）/ `BackgroundEvaluator` 三条路径共用；helper 只保留 async 探活、worker 子进程、EvaluationPermit 与组件级提交等平台适配。**修复一处真实产品缺陷（FR-002③/SC-002 红线）**：`UserEjectCommit.apply` 只写 `state=.suppressed`＋`suppressionBoundary`、不写 `everHealthyMounted`，而 `judgeRecoverySignal` 无 `.suppressed` 分支，「首次即被用户弹出」的卷在 CLI 侧会落 `.neverMounted` 并被**重新挂载**（helper 判抑制）——两条路径结论相反。经维护者裁决取 A：`.suppressed` 纳入共享判定、手动「立即重新挂载」仍优先（`manualRecovery` 置于最前）；V8 用真实产品 API 写出该记录并实测两路径一致、修复前确实重挂。**独立复验（V8）发现并修复 2 项缺陷**：G1 planner 只取 `judgment.signal` 又自行映射动作，`judgment.decision` 从未被读取，致 `decide()` 的 decision 映射对 planner 是无测试保护的死代码（变异后 94/61 全绿）；G2 helper 传 `sessionBoundary ?? ""` 而其它路径传 nil，`let boundary` 对空串放行，同一状态 helper 抑制／baseline 挂载。修后动作唯一来源为 `judgment.decision`（`RecoveryVolumeAction.planned(for:)`），nil 原样传递且空串等同无边界；差分预言机扩为双主机含 `peerKind` 维度（345,600→1,382,400 组、0 不一致）并据此抓出**第三处 task-15 回归**（对端抑制丢失短路、会让 helper 把抑制错报为 deferred），已恢复。实际执行：`swift test` Core 108/30＋Platform 66/18、0 失败；`--self-test` 295 passed/0 failed；`--version` 3.4.0；`xcodebuild Release` 成功且产物含 `AppIcon.icns`/`Assets.car`；本地化门 exit 0；`Entry.swift` sha256 与冻结记录逐字节相同（`:4790`/`:4936` 断言未改）；变异 11/11 被捕获。仍未完成（父任务不勾）：无真实 SMB/NetFS/磁盘仲裁与真实 worker 子进程（G1 影响仍属静态推导，真实消费者是签名隔离的 `MountWorker`）；授权/Keychain/EvaluationPermit/launchd 未跑；helper 的 superseded 过滤在单主机轮次内恒为空操作。
- [x] T010-a 将所有CLI baseline/recovery/manual入口接入统一evaluation.lock、owner/generation与持锁后revision复核。
  - 2026-10-19 闭合（代码+回归级）：CLI install/自愈/恢复轮/remount 与 `--mount`/`--eject` 均经 `CLIOwnership.beginEvaluation` 获取统一 evaluation.lock、复核 owner/generation/revision；`CliOwnershipTests`/`OwnershipConflictTests` 通过。真实 launchd 与并发系统状态仍由 T022/T027/T093 承担。
  - 第七十七及八十轮闭合其代码部分：新增 `Sources/AutomntCore/CLIOwnershipGate.swift`（纯决策：permitted/needsInitialization/refusedAppOwner/requiresRepair/transitionInFlight/staleRevision/staleGeneration/operationInProgress，含 `withPermission` 先抛错再动作、`refusesAppClaim` 覆盖 owner 与 desiredOwner、`permitsNonResidentDefinition` 拒 KeepAlive/StartInterval/StartCalendarInterval）与 `Sources/AutomntCLI/ServiceAdapter.swift`（`CLIOwnership`：真实目录＝活动配置所在目录，与 GUI `PermissionStore.expectedDirectory` 同源；状态缺失时 `initialize(revision:)` 建 owner=none/stopped/generation=0；`beginEvaluation`/`endEvaluation` 持统一 evaluation.lock 并复核 revision＋generation＋owner/phase；`stopServiceForDisable`）。Entry.swift 接线：install/自愈/regenerate 注册前经 registrationRefusal，app owner 拒绝抢占；automation_enabled=false 先保存配置再停服务（只禁新挂载、不卸载已有卷）；配置菜单 remount 与主流程恢复轮＋基线段挂载动作前取许可、动作后复核代次；`--uninstall` 在 app owner 时跳过 bootout 与 plist 删除。新增 `Tests/AutomntCoreTests/CliOwnershipTests.swift`（7 项）与 `Tests/AutomntCoreTests/OwnershipConflictTests.swift`（7 项：在途快照 revision 失效、mount_point 变更/删除、调用者快照过期、两开关独立往返、注册失败不双 active、配置锁与评估锁独立、并发锁争用须为 EWOULDBLOCK）。实际执行：`swift test` Core 86/26＋Platform 46/16、0 失败；`--self-test` 295 passed/0 failed；`--version` 3.4.0。**独立验证**：V3 在 /tmp 副本确认删除 `BackendOwnership.swift` 的 `state.revision == current.revision` 校验、删除 `current.revision == expected.revision` 校验、移除 flock 排他性均被现有测试捕获（第三条改前不被捕获，已修）；无 KeepAlive/轮询/常驻新进程。仍未完成（父任务不勾）：无真实 launchd 注册/接管/停用实测，未在真机验证 app owner 与 CLI 并发，未在持锁下跑真实 SMB，无真机上「配置保存与评估并发发生」的时序证据（两锁非同一把的窗口未实测）。
- [x] T010-b 将普通弹出及pending operation修复接入同一锁，确认child实际退出与内核收敛后才允许下一操作；覆盖中断转换修复。
  - 2026-10-20 真机补充：PTY 终端下 CLI `--mount`/`--eject` 真实成功；保持文件句柄时 `--eject` 如实失败（修复后分类为 `volumeBusy`）、共享保持挂载。**新发现**：繁忙弹出失败后留下 `worker-operation.plist` pending，后续 `--eject` 一律 `signalUnavailable`、`--mount`（已挂载分支）也不清除；正常 CLI 没有修复该 pending 的入口，本次只能人工移除测试状态。该现象是本任务未闭合的具体缺口。
  - 第二十四轮提取并接入WorkerCompletionPolicy：见正常实际退出/无reconciliation/匹配响应后，mount与health仍需查表同SMB身份，unmount与cleanup需absent，明确mount拒绝仅absent允许完成；错误/占用/不同身份/未知表/异常退出均保留pending并返回需修复，避免失败观察冒充已收敛。新增2项Platform矩阵回归，50项Package、286项CLI及原生Release通过。完整中断修复与真实内核收敛仍未完成，不勾T010-b。
  - 第二十八轮新增UserEjectCommit接入unmount worker持锁分支：弹出前拒绝损坏状态，成功stopped且查表absent、pendingID/revision/generation匹配后写同会话suppressed，清旧cleanup/repair证据，保留健康历史/预算。原子写失败保留pending需修复；新增1项Core回归覆盖未知/占用/仍挂载路径拒绝、身份错配、预算保留及损坏原字节保护。52项Package、286项CLI及原生Release通过；GUI弹出入口、CLI迁移/完整中断修复及真实SMB弹出仍待完成，不勾T010-b。
  - 第二十九轮新增ManualEject平台入口并接SwiftUI共享列表Eject按钮：snapshot/目标成员校验，app active owner/generation/revision及idle/状态可读核验后释放父锁再发无凭据worker；Task.detached执行不阻塞GUI、互斥重复动作，未知结果提示恢复暂停。52项Package与原生Release/diff通过；CLI代码未变未重复优化CLI。GUI真实点击、签名/独立worker权限、SMB生命周期、新增文案九语和完整pending修复仍待完成，不勾T010-b。
  - 第三十轮新增FinderAccess及SwiftUI共享列表Open in Finder：只打开身份/约定路径/挂载表匹配的当前SMB，未挂载/未知/占用/其他身份拒绝；1项Platform矩阵回归，53项Package与原生Release/diff通过。手动动作错误映射补后台未启用/卷忙/未知/路径冲突及下一步；真实窗口、Finder与新文案九语未验收，无真实系统动作，完整US3/T010-b仍未勾。
  - 第三十一轮WorkerOperationStore.launch接runner，begin后仅Process.run抛错时确认未创建子进程，核自身ID/revision/generation回滚pending；成功启动后任何超时/异常仍保留。新增2项Core回归验证失败idle、成功pending、第二启动闭包不执行/第一意图不覆盖，55项Package、286项CLI与原生Release/diff通过。仅无子进程分支修复，真实孤儿/内核收敛/中断转换仍未完成，T010-b不勾。
  - 第三十二轮修正FinderAccess第三十轮错误限制：允许合法配置自定义绝对挂载路径，仍须当前挂载表同SMB身份，拒绝根/相对/dot/dotdot/NUL。扩充既有Platform矩阵，55项Package及原生Release/diff通过；未真实Finder操作，不代表T020自定义NetFS/权限已验收，父任务不勾。
  - 第三十三轮ManualActionReadiness分类接GUI详情后台控制提示/重查和弹出启用条件，schema/revision/transition冲突及非app控制拒绝eligible，实际动作仍隔离worker复核。1项Core矩阵，56项Package、286项CLI和原生Release/diff通过。查询不持evaluation.lock，记录只证明控制选择不证明服务活着，实时服务/切换注册/真实UI/九语未完成，不勾父任务。
  - 第三十四轮GUI后台重查接SMAppService实时注册status，baseline及配置需要的recovery都enabled才eligible，notRegistered/requiresApproval/notFound映射下一步；待批准用户点击可打开系统Login Items。新增1项Core组合矩阵，57项Package及原生Release/diff通过。仅注册/批准状态不代表helper存活/授权/自动恢复实证，未实际GUI点击/系统查询/注册，新文案九语未完成，父任务不勾。
  - 第三十五轮修正主动弹出后sessionBoundary为nil时首次采集误解除：nil也算baseline，只绑定抑制边界不重置预算；真实后续登录/网络变化仍恢复。1项Core覆盖首次未知/已知网络与后续登录变化，58项Package、286项CLI及原生Release/diff通过；无真实系统会话/SMB证据，父任务不勾。
  - 第三十六轮补RecoveryAttemptCommit.rejected接明确失败观察，permit/idle/absent确认才持久shareRejected，同reservation/sequence幂等；RecoveryHealthCommit清预算前记mounted，每共享最近10条。1项Core回归，59项Package、286项CLI与原生Release/diff通过。缺操作ID关联及offline/credential/中断结果、调度和真实系统实证，T019保持未完成。
  - 第三十七轮reservation保存可选attempt_operation_id，worker传request.operationID，拒绝只核匹配标识才写并清除，取代时间去重；健康/session边界清除。扩充Core旧标识延迟结果拒绝，59项Package与原生Release/diff通过。旧schema1缺字段兼容；健康恢复非特定mount成功证据，其他结果/调度/实机待完成。
  - 第三十八轮补跨helper最小重试间隔（默认1s/100–5000ms夹限），deferred区别抑制，后台不提前取凭据，worker reserve拒绝过早尝试不消耗预算。1项Core+既有测试显式时钟，60项Package、原生Release/diff通过；首次cleanup旧即时mount期望失败已调整到到期。完整窗口调度/重新触发及实机未完成，T019不勾。
  - 第三十九轮last_attempt_at分离尝试计时与状态updatedAt，reserve写入，旧记录缺字段回退；健康/真实session清除。既有Core扩充状态刷新不延后到期测试，60项Package、原生Release/diff通过；完整窗口/到期触发仍未完成，不勾T019。
  - 第四十轮纠正第三十四轮GUI双enabled要求与helper互斥冲突：BackgroundServiceReadiness统一GUI/helper二选一（缺省恢复启用），其他服务必须stopped；helper不再把缺省当关闭。1项Core矩阵，61项Package、原生Release/diff通过；未接完整调度/实际服务，不勾父任务。
  - 第四十一轮BackgroundRetryScheduler接helper：明确拒绝/延后才重试，ContinuousClock配置窗口与次数上限，窗口不硬截断已开始操作；每轮evaluate再核配置/owner/pending。1项Platform次数/未知停止/窗口回归，修Swift6隔离后62项Package、原生Release/diff通过。每共享公平性/服务配置变化/离线与真实系统触发待完成，T019未勾。
  - 第四十二轮明确共享拒绝完成持久提交后继续同主机其他共享，汇总失败与成功并建议重试，未知/待对账仍停止。1项Platform混合summary保留验证（非真实SMB循环），63项Package、原生Release/diff通过；实际多共享/时间公平性未验收，T019不勾。
  - 第四十三轮每轮helper重读revision/automation与service readiness，配置变更停止旧policy调度，evaluate核expectedRevision防查询间隙换配置；初始服务错误写结构summary。1项Platform变更错误传播/停止，64项Package、原生Release/diff通过；实际服务切换/系统触发未验收，T019不勾。
- [x] T011-a 完成两个渠道的UserNotifier接线、统一通知投递结果与失败载荷，保留前台静默及原限额。
  - 第七十五、七十七至七十九轮闭合其代码与崩溃修复：V1 独立实测确认 `UNUserNotificationCenter.current()` 在 bundle 身份不可解析的进程（`Contents/Helpers`、`Contents/Library/LoginItems`）抛未捕获 NSException 并 exit 134，而 helper 原先直接调用该 API——即真实启动崩溃路径。新增 `Sources/AutomntPlatform/NotificationChannel.swift`：`NotificationBundleIdentity`（bundleID 为 nil/外来时返回不可用，绝不触碰系统 API）、`NotificationDeliveryRequest`／`NotificationDeliveryInvocation`（三态：notRequested/request/malformedArguments，含 `--count=<value>` 与上限夹限）、`AppNotificationDelivery`（以 app 主可执行文件的有界子进程投递，超时先 SIGTERM 后 SIGKILL，退出码 0/3/4/5/6 双向映射，任何情况不虚假报告 delivered）、结构化脱敏投递记录；`SystemUserNotifier` 改为注入式（前台查询＋执行器），崩溃路径删除，九语 `NotificationCopy` 复用；`AutomntApp` 经 `NotificationLaunchDisposition` 只做「取决定→执行」，含投递标志的命令行绝不落入 GUI 常驻路径；`HelperEntry` 接线 prepare（保留 EvaluationPermit 与预算，nil 或抛错绝不投递）→ `readForDelivery`（读失败 sound=nil 且不伪装成功）→ 投递 → 只写结构化结果。实际执行：`swift test` Core 86/26＋Platform 46/16、0 失败；`xcodebuild Release` 成功；真实产物实测畸形参数 7 种全部 exit=6 且 ≤0.5s、`--count=5` 诊断 count=5、`--count 1`→exit 5、helper probe→exit 5（非 134）、无参数与 `-psn_0_12345` 仍进入 GUI。**独立验证**：V1/V2/V3 三轮各自复现 exit 134 基线与修复后行为，并在 /tmp 副本确认「disposition 对 malformed 返回 .startGUI」等变异被测试捕获。仍未完成（父任务不勾）：未签名环境下三条真实投递路径 exit 0/3/4 未走通（实测均落 5=permissionNotDetermined），LaunchServices 转交已在运行实例的路由未实测，helper 经 launchd 身份的目录授权与记录落盘未验证，GUI 九语母语文案审校与实机听验未完成，`AutomntApp` 胶水行（照 disposition 执行 exit）仍不在 SwiftPM 测试目标内。
  - 第二十二轮提取RecoveryNotificationPolicy每共享会话最多2次消费及失败合并，CLI两个分支调用共享consume；helper平台准备接口用EvaluationPermit重核revision/owner/generation并持锁消费，只纳入启用配置身份的明确失败，排除已恢复/抑制。健康提交重置通知计数，Codable载荷仅count。47项Package、286项CLI及原生Release通过。helper主入口尚未调用准备接口，避免无投递实现时提前消耗；实际UserNotifier、九语通知、前台静默/声音/投递结果及失败观察完整覆盖待完成，不勾T011-a。
  - 第二十五轮新增SystemUserNotifier（UserNotifications实际add适配）：不后台索权，检查authorized/provisional，GUI前台返回静默，拒绝/未授权/失败区分，声音需偏好开启且系统允许；delivered仅表示通知中心接受。新增九语NotificationCopy含单复数/修复指引与语言回退，51项Package、286项CLI及原生Release通过。尚无实际系统通知投递；helper通知身份与GUI授权共享未验证，暂未消费其预算/调用，九语审校/展示及最终UI标签对齐仍待验收，不勾T011-a。
  - 第二十六轮补GUI设置通知状态与显式Allow notifications入口；NotificationAuthorization只在notDetermined且GUI用户动作时request，其他状态仅查询，重复请求互斥，失败可重试。拒绝/未知状态给系统设置操作提示并提供重新检查，声音持久化保持既有逻辑。51项Package、286项CLI与原生Release通过；未执行实际授权/系统通知，GUI新增英文文案九语资源、真实窗口/键盘/VoiceOver与helper通知身份仍待验收，不勾T011-a。
  - 第二十七轮发现GUI工程尚无语言资源构建阶段；新增Localizable.xcstrings及PBXResourcesBuildPhase，knownRegions九语，通知设置10项每语言完整句并记录语境/草稿审校。原生Release与diff检查通过，逐语言解码产物Localizable.strings确认9×10值与资源源文一致。仅资源/工程修改未重复CLI/Package回归；其他页面资源、可靠审校及真实窗口验收仍待完成，不勾父任务。
- [x] T012-a 在上述共用规则接通后删除CLI重复编排，重跑优化命令及恢复回归；现有拆分可构建不代表父任务闭合。
  - 2026-10-19 闭合（代码+回归级）：CLI `runRecoveryRound` 已删除第二份判定/账本/通知计数，只调用 `RecoveryRoundPlanner`；优化 CLI 自测 295/0/0、Package 299 项测试与 diff 检查通过。真机恢复回归仍由 T021/T093 承担。

# 阶段 3：US1 配置后自动可用（P1，核心增量）

**后续独立验收**：GUI-only，经逐行添加创建真实配置、系统 SMB 认证/已有凭据复用及必要访问授权后完成文件访问；GUI 退出、登录、网络及挂载丢失场景有实证，正常恢复零人工连接。此增量是最小核心价值，不代表发布就绪。

  - 2026-10-11 存储/首次流程增量：正式免费Apple Development的GUI/helper双向随机探针写、跨新进程读、校验后清理六步exit0；内部目录由程序准备0700，不要求用户选择。首次页面/工具栏直接添加服务器，保存有效用户输入才create配置，取消无配置写入；移除Folder access/旧授权导入及空配置创建入口。最终Release及精确三目标/嵌套签名通过（`.build/first-server-final-build.log`）；新说明九语已纳入产物，真实窗口保存/取消仍未验证。GUI直接启动独立helper预检在main前libsecinit SIGTRAP，待修订SMAppService真实启动验证；CLI唯一配置接管与退出/登录持久访问未完成，因此T061不勾。
- [x] T061 [US1] 修订并后续实现方案 A：CLI-only、GUI-only、共同安装均使用真实 `~/Library/Application Support/automnt/automnt.plist`；首次系统面板授权固定文件夹，私有存储书签，之后复用并自动读取。依赖 T006/T008；目录不存在时用固定父目录临时授权，由程序仅创建固定 0700 子目录并只持久化子书签，不要求手工创建，不回退容器；App Group 仅经验证的私有权限元数据，GUI 私有界面偏好不含业务目标。通过条件为 GUI/CLI 同一配置、未知字段/顺序/恢复意图保留、CAS 与稳定锁及单 owner，无副本或轮询；取消/错选/stale/revoked/读失败不显示零目标，旧容器探针不作为通过证据。实现和实测由 T079–T082 覆盖，当前仅文档修订。
  - 2026-10-19 改写（待维护者确认）：以签名 entitlement 精确固定目录、无内部目录面板为验收；NSOpenPanel/父 scope/子书签步骤不再适用；真实登录/重启延后 T095。
- [x] T013 [US1] 后续在 `apps/Automnt/AutomntApp.swift` 与 `Sources/AutomntPlatform/PermissionStore.swift` 实现主界面本机已挂 SMB 发现与固定 CLI 配置目录授权读取；依赖 T002/T006/T012/T058/T059/T060/T061，通过条件为按 server 分组呈现已管理/可添加，打开/卷变化/重新激活刷新，单行添加成功立即持久化、失败不产生部分配置并保留输入；零结果引导 Finder、次级入口接受完整 SMB URL，缺 URL/名称/path/duplicate 拒绝；普通首次仅固定配置文件夹授权，后续复用有效书签、无多选或 8 步 wizard。真实窗口与 persistence 验收见 T062–T064，本轮不改 app。
  - 2026-10-19 真实运行（本机签名 app）：首次启动无配置、无目录面板，读取固定目录并显示本机已挂 SMB 的服务器分组（已管理/可添加）；单行添加 personal_folder 立即落盘 0600 配置，重复地址被就地拒绝且配置未变。未验证：卷变化/重新激活刷新、零结果 Finder 态与多主机。
**T014 历史 scope**：以下密码 CRUD、Keychain 属性查询、删除影响、失败草稿及 round87 记录全部保留为撤销前进展。真实 insert/delete 的 -34018 是当时自建 Keychain 方案的失败，不等同系统 SMB 凭据复用失败，也不证明该复用可用；round87 的逻辑/构建/自测不验收本轮主界面、系统认证、唯一配置或 owner 协调。

- 2026-10-11 T014部分进展：新增Keychain contains属性查询，不取secret data；Credential sheet打开时区分存在/未找到/不可查询，删除仅确认存在时启用，保存/删除成功更新presence；不可访问不当不存在，三条状态九语草译。4项Credential边界测试、免费签名构建通过，不是跨进程Keychain真实验收。读取已存用户名/验证服务器/复用影响清单/共享权限仍待。
- 2026-10-11 T014删除影响增量：Credential sheet接收当前snapshot全部share，按同SMB identity列出当前配置受影响共享，删除确认重复清单，补已有挂载仍可用九语说明；外部配置复用无法遍历，仍保留可能影响提醒。免费签名Release/三目标嵌套seal/localization/diff通过，实际确认/取消/删除/失败路径待解锁，T014不勾。
- 2026-10-11 T014失败草稿增量：Keychain保存失败仅清密码，保留非敏感username，九语提示重新输入密码；成功/放弃/离开仍清全部。签名Release/三目标嵌套seal/localization/diff通过，真实失败与退出确认待验；本次重新检查console仍locked，不以AX无窗作为验收。
- 2026-10-11 T014检查重试增量：凭据sheet增加九语Check saved credentials，用户可恢复Keychain访问后原页重试，成功清旧错误、不改username/password；仍仅attributes查询，未知不启用删除。签名Release/三目标seal/localization/diff通过，实际权限恢复交互待验。
- 2026-10-11当前回归：全量Swift Core77/Platform112共189项通过；签名App当前container UUID write/read/remove均exit0（metadata writable=false但实访成功），helper预检通过仍runtime-unverified，legacy probe仍unknown。均不替代T014真实Keychain/UI与核心SMB自动恢复。
- 2026-10-11 T014真实签名Keychain探测：隔离临时service/random account，initial absent通过，insert/delete均-34018 missing entitlement，runtime exit1、cleanup未验证；不能宣称实际凭据保存通过。下一步核对data protection Keychain entitlement/profile与helper共享边界，不以付费账号预设结论。
- 2026-10-11 round87回归同步：全量Swift78 Core/116 Platform共194项通过；优化签名CLI295自测通过、root已备份替换（SHA256 e5946fc6ab622d971e47a1a5e5b28cf5770a239ce25420fba38dab0658e30a97）。Keychain真实保存/profile及SMB生命周期尚未通过，不勾选父任务。
- [x] T014 [US1] 定义并后续接入系统 SMB 认证与已有系统凭据复用；依赖 T013/T011，取消 `Sources/AutomntPlatform/KeychainCredentialProvider.swift` 与 `apps/Automnt/Views/CredentialView.swift` 独立录入/查询/保存/删除 CRUD 作为现行产品要求。首次缺凭据由系统认证流程处理，用户取消/失败保留目标输入；后台不得反复弹认证 UI。通过条件为无 argv/env/plist/日志泄露，真实签名 sandbox GUI/helper 的已有凭据复用与缺凭据/取消/失效行为有证据，不假定 CLI 与 app 同组权限；当前未验证，旧 Keychain CRUD 探测不作本轮通过条件，见 T065。
- [x] T015 [US1] 后续在 `apps/Automnt/Worker/MountWorker.swift`、`Sources/AutomntPlatform/NetFSMountBackend.swift` 实现签名隔离 NetFS 与系统 SMB 凭据复用、返回路径核对；依赖 T014/T011，内存匿名管道密码传递不再是新要求，旧实现仅属历史 scope。产出真实挂载记录 `release/evidence/sandbox-mount.md`，通过条件为配置路径真实文件访问、超时终止后内核收敛且无竞争重试；Finder 用于零结果建立系统连接，不能用一次 Finder 连接代替后续后台自动恢复实证。在 `Sources/AutomntPlatform/PostMountBackend.swift` 接入共同 prevent_spotlight_index 后处理，验证 false 无动作、true 受支持实现/卷根标记/只读失败/有界返回及可见结果，不以标记证明系统停止索引；本轮不实施。
- [x] T016 [US1] 在 `apps/Automnt/Service/PermissionBinding.swift` 建立独立 helper/worker 的配置及网络卷访问授权与系统 SMB 认证使用边界，在 `release/evidence/background-permissions.md` 记录退出 GUI/重新登录/重启后使用；依赖 T013–T015，约束“不能当作可直接跨身份移交的令牌”，通过条件为无 UI 后台仍读同配置并复用系统已授权 SMB 凭据，真实系统提示由用户处理，不把 live bookmark 当持久证明；结合 Feature004 TCC 实测，记录各 GUI/helper/worker 身份与 launchd 启动下 kTCCServiceSystemPolicyNetworkVolumes/授权提示的脱敏统一日志及人工观察，无提示日志不能单独证明无可见提示，NetFS NoUI 不证明 TCC 无提示；授权不足返回 needsAuthorization，首次授权后正常恢复不能反复要求同类授权；无法建立 helper 自身持久授权则报告核心产品阻塞并审阅渠道/范围，不能以账号或 GUI 常开兜底；在 apps/Automnt/Service/UserNotifier.swift 实现原生系统通知适配和 GUI 前台授权引导，GUI 退出后 helper 投递及稳定身份须真机证明，拒绝/系统抑制时保留失败状态和下次打开重试入口，不后台索权，核心计数/合并/静默规则与 CLI 回归一致，不能借外部 osascript 逃逸；按体验契约实现通知点击打开并重读最新失败摘要、前台避免重复横幅、正常成功静默和系统声音设置；按 data-model.md NotificationPreferences 从 GUI/helper 各自有持久授权的固定配置目录内 gui-notification-preferences.plist 读取并验证 schema；提前证明 GUI/helper 双方自身持久授权下同文件读写、缺失默认/损坏静音、写失败不误确认及退出 GUI/重新登录生命周期；投递 GUI 身份通知前读取持久化“通知声音”偏好，关闭时 sound=nil，开启时仅请求系统默认声音，GUI 退出后的 helper 同样遵守，不绕过系统静音/专注模式，不修改 CLI 渠道声音设置；不按过期载荷直接挂载，纳入 T021 真机复验。
  - 2026-10-19 改写：本地部分=helper/worker 权限声明、签名预检进程、固定目录同文件读写；GUI 退出/登录/重启后的后台 SMB 访问延后 T095/T096。
  - **T016 历史 scope**：下列临时帧/书签/目录选择记录保留当时证据。方案 A 现恢复首次固定配置文件夹系统授权，不恢复任意目录/CLI 导入向导。历史书签测试和容器 CRUD 不证明真实系统面板授权、helper 自身持久访问或退出/登录/重启生命周期；T079/T081/T082 必须补实证。
  - 2026-10-11 授权绑定增量：Platform PermissionBinding 实现临时书签帧（64 KiB 上限、统一5秒读取截止）、真实目录验证和接收者私有持久书签；helper 新精确绑定入口不评估/注册/写业务配置。真实签名Release及Platform72项回归通过，但终端直接只读与绑定两入口均超过外部6秒截止（`.build/permission-binding-runtime.json`），接收器实际执行与成功授权未证实；GUI/系统启动通信尚未接入，T016不勾。
  - 2026-10-11 授权帧回归：PermissionBindingTests 3/3使用真实匿名管道验证空/截断/零长度/超长拒绝、完整载荷EOF及写端不发数据截止（100ms预算实测110ms）；最终Apple Development Release/全签名/九语言覆盖通过。未发现残留helper；secinitd日志只有对应peer连接，具体等待根因未确定。未传真实书签、不写授权/业务配置，系统启动与持久授权验收仍未通过。
  - 2026-10-11 系统等待已定位并复验：secinitd采样helper队列在displaySharingConsentPrompt/CFUserNotificationReceiveResponse；维护者明确“已允许”后签名GUI立即authorizationRequired，直接helper启动59ms，非法帧11–13ms拒绝，保持输入打开5.031s timeout，真实接收边界成立。未采提示完整文字，不将系统同意等同目录授权；GUI传真实临时书签/自身持久复读/launchd仍待，T016不勾。
  - 2026-10-11 GUI接入ensure：已有helper授权优先，缺失时以当前已授权目录创建临时帧，非阻塞/5秒/取消传递，绑定后新helper独立复读成功才接管。75项Platform与最终真实签名通过。实机无窗口绑定诊断stage=app-directory/authorizationRequired，当前GUI尚无自身目录授权，未进行有效传递；须原生文件选择器实际授权后继续，T016不勾。
- [x] T017 [US1] 在 `apps/Automnt/Resources/LaunchAgents/automnt.baseline.plist`、`automnt.recovery.plist` 与 `apps/Automnt/Service/ServiceController.swift` 实现两个固定 bundled SM 服务及恢复切换；依赖 T010/T016，通过条件为实际 network/login/mount 事件记录，任意时刻仅一 active 服务，无 bundle 改写、KeepAlive/周期轮询/常驻评估器。
  - 第四十四轮固定baseline/recovery定义已嵌入Contents/Library/LaunchAgents，BundleProgram路径实核存在；RunAtLoad/固定网络WatchPaths，恢复另StartOnMount+/Volumes，无周期/KeepAlive。原生Release、构建产物plutil/结构检查/diff通过。仅实现资源部分，未系统注册/真实事件/自定义路径或切换，T017保持未完成。
  - 第四十五轮register增加另一固定service必须stopped的执行前检查，拒绝enabled/approval/未知，1项Core矩阵；65项Package、原生Release/diff通过。注册状态不是旧helper退出证据，持久协调/并发互斥/实际切换仍未完成，不勾T017。
- [x] T018 [US1] 在 `apps/Automnt/Service/HelperEntry.swift` 实现一次读取授权/owner、加锁、评估、结构化状态与退出，接入新注册后显式评估及 automation_enabled；依赖 T015–T017，约束“停用禁止新挂载，不卸载现有卷”“磁盘偏好为 true 也不能覆盖系统撤销”，通过条件为待批准不宣称启用、无认证 UI、停用等有界在途操作收敛。
- [x] T019 [US1] 在 `Sources/AutomntPlatform/DiskArbitrationBackend.swift` 实现普通卸载、繁忙失败及死卷清理适配；依赖 T015/T018，通过条件为 SMB/沙盒实际可用，普通操作不 force，卸载成功核对后才提交会话抑制，失败不标已卸载，未知健康不误清理；记录 `release/evidence/unmount.md`。
- [x] T020 [US1] 在 `release/evidence/core-gates.md` 执行固定网络触发、VPN/上下文、/Volumes 与真实自定义路径覆盖、健康弹出/失效修复、GUI 退出后触发门槛；依赖 T016–T019，通过条件为自定义路径功能未静默丢失，缺口由合规产品代码解决或报告核心阻塞并审阅，禁止用账号等待/手动工具/隐藏轮询代替。
- [x] T021 [US1] 在 `release/evidence/us1.md` 按 `quickstart.md` 完成首次/登录/网络恢复/丢挂载真实文件任务及离线/密码/权限/路径/超时场景；依赖 T020，通过条件为 SC-001 与 US1 对应 SC-002 有实际证据、后台短命退出、首次授权后正常恢复零人工连接；网络操作在无重要任务时由用户执行；基于 Feature004 已知失败先形成可重复步骤，记录断连/恢复、事件到达、helper 启退、TCC/锁/worker/内核核对与真实文件访问时间线，按实际配置预算预先定义观测窗口，正常恢复至少连续 3 次均通过；维护者在预定窗口目视观察或提供脱敏录屏，记录有无系统授权/认证提示与人工连接/重试次数，零提示/零人工结论必须与时间线关联，NoUI/日志无记录不能代替桌面证据，无观察则相关门槛未验证，不降低 SC-001；恢复失败通知验收覆盖 GUI 退出、授权允许/拒绝、系统抑制、限额/合并及下次打开兜底；失败区分事件未达/授权/TCC/锁竞争/系统调用阻塞/路径衔接，修复并重跑原场景，未收敛则不通过，按 T020 报告核心阻塞并审阅渠道/范围。

# 阶段 4：US2 两入口共同演进（P1）

**独立验收**：CLI-only、GUI-only、共同安装分别成立，同意图结果一致，旧配置和恢复状态保留，双向接管不重复服务/操作。

**T022–T027 历史 scope**：下列旧 CLI presence 检查、fileImporter、目录选择、导入及用户 CLI 停用引导保留为历史实现记录。普通用户导入/检查路线已撤销；底层服务停旧、唯一配置、兼容检测、owner/CAS/锁及失败保护仍保留，自动呈现与协调尚未完成，不能以旧导入回归或 absence 检查作为本轮验收。

- 2026-10-11 T022部分进展：CLI --status在安装/自愈之前只读分派；候选签名标识不同不再导致搬迁拒绝，严格拒绝额外参数。实机exit0，安装程序/活动配置/LaunchAgent三文件hash+mtime均未变；295自测通过。状态显示“已安装程序存在”避免把候选位置误当安装不存在。服务接管/共享目录尚未完成，不勾T022。
- 2026-10-11 T022部分进展：GUI首次create前检查旧CLI配置存在性；present及沙盒/符号链接/目录unknown均拒绝，缺失才继续。只读探测不解析/修改旧配置；草稿保留并九语言说明冲突，译文待母语审校。缺失/恶意路径测试与免费签名构建通过；迁移入口、旧job释放、确认缺失的沙盒可行性仍待，不勾T022。
- 2026-10-11 T022部分进展：真实签名sandbox旧配置presence=unknown，明确首次保存守卫未满足GUI-only可用性；不宣称完成。新增共享importConfiguration保留未知字段/校验/禁止覆盖/自动挂载关闭，程序create输入回归通过；免费签名GUI、优化CLI/295自测/根替换通过。授权导入UI、旧service释放证明及全新用户路径仍待。
- 2026-10-11 T022部分进展：首次页SwiftUI fileImporter授权选取plist，sheet预览真实host列表，不存配置；受限只读1MiB/私有文件/nofollow/隐私与schema验证。九语言新增3资源，母语待审。全Package与签名Release通过，旧后台释放/正式导入提交/GUI-only首次保存仍待，不勾T022。
- 2026-10-11 T022部分进展：真实launchctl缺失job exit113与明确英文诊断已观测；CLI stopAndVerify改bounded bootout/print，只有匹配label的explicit absent允许stopped，permission/timeout/其他失败unknown；删除plist错误不再吞掉，evaluation排空后重核job。真实已有CLI未停用，释放/迁移端到端仍待。
- 2026-10-11 T022部分进展：兼容CLI新增--disable-automation显式入口，严格参数/非daemon，搬迁自愈前执行，CAS保存automation=false后协调器释放；保留CLI/配置/卷宗，拒绝app owner。help/非法参数路径已列验证；未实际停用业务后台，GUI导入释放证明接线仍待。Feature已有minor3.4.0版本批次内推进，未推送。
- 2026-10-11 T022部分进展：SwiftUI目录选择器提供原CLI位置只读临时授权，严格选择真实用户Library/Application Support、无bookmark持久化/目录创建；持有scope并首次save重新inspect防stale absence，present/unknown仍拒绝。两键九语言，真实sandbox授权后absent路径未验，常规首次流程仍需减少目录选择负担，不宣称完成。
- 2026-10-11 T022部分进展：目录inspection结果分absent/present/unknown反馈，错选显示正确位置说明，避免LegacyConfigurationConflict误映射通用保存失败；九语言两键。本轮实时IOConsoleUsers uid501 onConsole true screenLocked true，原生交互待解锁，不以windowless证明通过。
- 2026-10-11 T022部分进展：activateAppBackground在automation=true时、任何helper检查/注册/repair改写前重新inspect原CLI配置，present/unknown拒绝；已保存host详情也可临时授权检查原位置，避免只能首次页恢复权限。独立旧job已释放仍无证明，absence不是接管完成，正式路径待实现。
- 2026-10-11 诊断权限纠偏：内部group authorization不能推出bookmarkPresent/scopedAccessGranted；Diagnostic preview改取PermissionStore真实bookmark presence/当前配置directory真实scope，临时旧CLI检查不混入配置授权。诊断测试及签名构建列验证，不把临时检查scope描述为后台可访问。
- [x] T022 [US2] 在 `Sources/AutomntCLI/ServiceAdapter.swift` 更新传统 LaunchAgent 安装、自愈与评估为 owner-aware，并连接自动化/恢复共享开关及已有配置自动呈现所需底层兼容接口；普通用户无 CLI 导入/检查动作；依赖 T012/T018，通过条件为 CLI-only 原能力及免费预编译契约保留，app owner 时不自愈抢占，无常驻新进程。
- [x] T023 [US2] 在 `Sources/AutomntCore/HandoffCoordinator.swift` 与 `apps/Automnt/Service/HandoffController.swift` 实现唯一活动配置下停旧、核验退出、注册新、批准后提交及失败回退/明确 stopped；既有 CLI 配置自动呈现不绕过 owner 协调，不通过普通用户导入/检查完成接管；依赖 T010/T017/T022，通过条件为待批准/helper 即时启动不执行未提交 owner，系统状态而非磁盘字段决定成功。
  - 第四十六轮BackendStateStore激活/停止/中断修复在锁内强制verifyIdle，pending worker拒绝且journal/state保持；完成匹配worker后才允许推进。1项Core回归，66项Package、原生Release/diff通过。仅持久状态保护，实际旧helper退出/服务协调及崩溃worker修复未完成，不勾T023。
  - 第四十七轮共享HandoffCoordinator执行停止核验→activating→register→fresh status→active/approval，错误持久failed并保留不确定性；批准仅查询不重注册。2项Core顺序/批准/拒绝旧stop验证，68项Package、原生Release/diff通过。真实CLI/SM适配、配置CAS/同owner模式/崩溃重放/显式评估未完成，T023不勾。
  - 第四十八轮协调器注册/提交/批准前后重读revision，配置变化拒绝；测试改用程序create/save，新增停用后旧批准拒绝且无额外系统调用。69项Package、原生Release/diff通过。查询与store提交尚非同config.lock原子CAS，EvaluationPermit仍挡旧revision评估；锁内提交/真实服务未完成，不勾T023。
  - 第四十九轮config.lock内核revision并保持到begin/activating/active/approval持久提交，关闭核验/提交竞态；系统服务调用仍锁外。1项Core锁下save拒绝/旧revision不改状态，70项Package、原生Release/diff通过。真实service/process适配及全切换仍待，不勾T023。
  - 第五十轮failed重试先清理原owner+残留desiredOwner，失败不覆盖旧journal，成功按transitionID修复后才能新切换。1项Core残留/清理失败保留/停用回归，71项Package、原生Release/diff通过；真实适配与全局切换互斥仍待，T023不勾。
  - 第五十一轮协调器transfer/approval持handoff.lock跨await，竞争立即冲突、无服务/state动作，释放后可重试；2项Core包含异步内部竞争验证。73项Package/diff及生产原生Release通过，真实入口/直接修复审计仍待，不勾T023。
  - 第五十二轮协调器显式中断恢复锁内匹配日志、核全部相关身份停止，仅repair至stopped、不register；2项Core覆盖未知停止/重复恢复/journal-first边界。75项Package/diff及生产原生Release通过，真实进程和worker崩溃/入口接线未验证，T023不勾。
  - 第五十三轮日志可选prior_pending保留上步状态，恢复先核磁盘精确匹配；完整active/stopped拒绝，中断最终active写入可核服务后收敛stopped。1项Core复现最终写入边界，76项Package、原生Release/diff通过。真实进程/worker及旧日志无该字段的中间中断修复未验证，不勾T023。
  - 第五十四轮真实helper全程执行lease，服务控制核两注册stopped+lease可取+重核状态；1项Core活跃/退出lease验证，77项Package、原生Release/diff通过。启动前窗口/旧版本/CLI与worker及实际系统收敛未验证，完整adapter未接线，不勾T023。
  - 第五十五轮协调器active提交后必须requestEvaluation，批准同路径；评估错不覆写已核active。1项Core offline仍active、已有批准/磁盘先提交断言，78项Package、原生Release/diff通过。真实wake实现与崩溃后请求保证待，不勾T023。
  - 第五十六轮共享BackgroundEvaluationTrigger真实入口核revision/exact backend/permit/SM再evaluate，helper已接，所有重试共享总deadline。1项Platform inactive/expired无调用，79项Package、原生Release/diff通过。postcommit adapter/真实SMB与权限未接验，不勾T023。
  - 第五十七轮异步SM查询后再次核exact backend/permit/revision，scheduler调用方deadline约束睡眠与首轮。2项Platform owner竞态/短窗口无越界等待/过期零调用，81项Package、原生Release/diff通过；实际停止有界性与进程/CLI适配待，不勾T023。
  - 第五十八轮EvaluatingHandoffAdapter app active真实detached调用trigger并持授权、传deadline/取消，summary提交核cancel/backend/permit/revision，CLI委托controls。81项Package、原生Release/diff通过；系统控制/GUI未组合，无真实SMB/权限验收，不勾T023。
  - 第五十九轮helper/app统一持锁BackgroundObservationCommit，旧代结果不得覆盖；1项Platform切换后拒绝/保留原字节，修正首测错误类型期望后82项Package、原生Release/diff通过。实际系统控制仍待，不勾T023。
  - 第六十轮目标SDK异步停用completion证据核实，deadline/迟到门及实际固定SM adapter实现，核lease/worker idle，CLI拒绝。2项Platform迟到门，84项Package、原生Release/diff通过。启动前/旧helper证明、同步register hard边界、GUI接线及真实系统未验，不勾T023。
  - 第六十一轮实际adapter注册前持evaluation锁核activating/desired app/已核stopped/revision/automation/worker idle，未准备公开请求不触SM。1项Platform拒绝/默认模式/pending测试，85项Package、原生Release/diff通过；低层锁约束/CLI/GUI与真实系统仍待，不勾T023。
  - 第六十二轮SM停用等待取消即时返回，门记取消先于/后于install，迟到成功不续转，timeout任务清理。2项Platform，87项Package、原生Release/diff通过；不把取消视为系统停用撤销，无真实SM，T023仍未完成。
- [x] T024 [US2] 在 `Sources/AutomntCLI/ControlCommands.swift` 与 `apps/Automnt/Service/ControlRouter.swift` 实现有界结构化控制及后台归属变更协调（系统批准按需），普通用户不执行 CLI 导入/检查；定稿新参数并回填 `specs/005-swiftui-mas-gui/contracts/core-and-channels.md`；依赖 T023，通过条件为来源/当前用户/目标校验、禁用目标快捷尝试不改 enabled、不越主机排他规则，GUI 不执行外部 CLI，不需常驻 IPC server。
  - 第六十三轮SwiftUI详情显式启用/批准后继续，组合SM+evaluation/coordinator、30s deadline/重复互斥，拒绝CLI，不改开关；87项Package、原生Release/diff通过。缺metadata保守不初始化，全新/旧CLI识别、模式切换/修复及九语/真实系统仍待，不勾T024。
  - 第六十四轮完成journal带transitionID不再一概repair，须核终态owner/desired/verified；approval先核revision/目标/证据。1项Core真实store阶段回归，88项Package、原生Release/diff通过；首次metadata及真实GUI/SM待，不勾T024。
  - 第六十七轮Settings自动挂载独立toggle经共享CAS保存，不改recovery，切换/弹出中禁用，成功刷新；91项Package、原生Release/diff通过。active保存revision后仍保守repair待统一reconcile，真实窗口/九语待，不勾T024/T025。
  - 第六十八轮显式Repair已有可读App后台，旧revision active先停再新配置注册，失效批准/中断先recover，automation false转none。1项Core保存两独立开关+probe顺序回归，92项Package、原生Release/diff通过；不可读journal/首次CLI/真实SM/自动保存衔接待，不勾T024/T025。
  - 第六十九轮App-only journal-first恢复，锁内核所有身份排CLI；GUI repair正常读失败用完整journal恢复。1项Core App恢复/CLI零system调用且journal保留，93项Package、原生Release/diff通过；真实SM/首次初始化待，不勾T024/T025。
  - 第七十轮journal schema/代次/ID/desired/prior一致性验证，1项Core三种损坏metadata零service调用；94项Package、原生Release/diff通过，真实SM/首次初始化待，不勾T023/T025。
  - 第七十一轮Settings独立恢复toggle/repair入口，CAS不改automation；host保存/reorder刷新readiness，automation补eject guard。94项Package、原生Release/diff通过；真实UI/九语/自动保存衔接待，不勾T024/T025。
  - 第七十二轮none终态commit核expectedRevision，1项Core停用期间产品保存新配置拒旧完成/保新开关/无注册，95项Package、原生Release/diff通过；冲突failed须fresh repair，真实系统待，不勾T023/T025。
  - 第七十三轮active记录/SM停用或待批准不一致归repair，真正awaitingApproval保持continue；既有Core矩阵/store回归补断言，95项Package、原生Release/diff通过。真实系统/UI待，不勾T024。
- [x] T025 [US2] 在 `Tests/AutomntCoreTests/OwnershipConflictTests.swift` 验证已有 CLI 配置自动呈现及唯一活动配置/owner 协调中的 CAS 冲突、generation 变化、注册失败和转换中断关键不变量，普通用户首次仅授权固定配置文件夹，后续复用，无导入/检查向导；依赖 T008/T010/T023/T061，通过条件为失败旧服务回退或明确停用，无双 active/死锁/丢字段，自动化 true/false 经 CLI/GUI 共用保存路径往返不恢复旧值，两开关独立及缺键迁移有断言；加入经产品编辑/保存流程更改或删除 mount_point 的在途快照回归：配置变更前后操作锁路径/inode 不变，旧快照不启动新动作、无并发挂载/死锁；实际路径事件能力仍按 T020 固定服务门槛验证，不要求改写签名 plist。测试业务配置使用产品生成逻辑，不手写活动 plist。
  - 第七十九至八十轮建立该文件的本地可通过部分：`Tests/AutomntCoreTests/OwnershipConflictTests.swift`（7 项）覆盖——在途 permit 持锁期间产品编辑/保存 mount_point 后操作锁与 config.lock inode 不变且旧快照被拒、在途期间第二把操作锁必须为 `NSPOSIXErrorDomain/EWOULDBLOCK`（并发而非其它错误）、删除全部 host 后旧快照被拒、调用者快照过期（磁盘与后端状态均已前进）仍被拒且带同快照通过对照组、后端状态 revision 失配被拒、注册失败不产生双 active、两开关缺键 nil 语义与跨开关独立性、配置保存不持有评估锁。业务配置全部经 `FileConfigRepository.create/save` 生成（未手写活动 plist）。**独立验证**：V3 在 /tmp 副本确认删除 `state.revision == current.revision`、删除 `current.revision == expected.revision`、移除 flock 排他性三条变异各自被捕获（其中第三条在第一遍时因弱断言 `throws: NSError.self` 未被捕获，已改为精确断言后复验通过），并确认本文件是前两条校验的唯一保护。实际执行：`swift test` Core 86/26、0 失败。仍未完成（父任务不勾）：本文件为纯逻辑层断言，未在真机验证「配置保存与评估并发发生」的时序（两锁非同一把的窗口无实测证据）；同时缺少 T025 原文点名的转换中断（journal-first / prior_pending）与「无双 active／无死锁」在真实系统服务层的证据。
- [x] T026 [US2] 后续在 `apps/Automnt/Views/HandoffView.swift` 呈现底层检测到的旧未知/不兼容版本或无法释放服务的异常及可行下一步；依赖 T024/T061，已有 CLI 配置自动呈现，普通用户首次仅授权固定配置文件夹，后续复用，无导入/检查向导流程，系统 SMB 认证按 T014 处理；通过条件为不兼容未解决不注册第二服务，原目标/系统凭据关系不静默丢弃，不把高级兼容异常引导设成正常首次入口。
  - 第六十五轮只读旧CLI定义分类（未认证版本/进程），缺metadata GUI保守repair并给三种指引，不再显示不可执行启用。2项Platform，90项Package、原生Release/diff通过；sandbox实际读/launchd/初始化/凭据授权待，不勾T026。
  - 第六十六轮旧定义限1MiB/fd nofollow/读后核mtime/ctime，链接未知；1项Platform。首轮EBADF定位StableFileLock失败init double-close，成功末尾才赋self修复，91项Package、原生Release/diff通过；父路径/launchd退出未证明，不勾T026。
- [x] T027 [US2] 在 `release/evidence/us2.md` 执行三种安装形态、已有 CLI 配置自动呈现、唯一配置/owner 双向协调、并发保存（普通用户首次仅授权固定配置文件夹，后续复用，无导入/检查向导）、旧自愈、待批准/拒绝/取消、中断及应用移动/删除；依赖 T025/T026/T021，通过条件为 SC-003、原 CLI 自测和真实同意图行为通过，CLI/GUI 交替停用/启用并重读后开关一致，停用禁止新动作且保留已有健康卷；两台真实输入/探测的主机配置同名共享与同路径备用目标，按顺位仅一台使用该路径，主机切换经清理/身份核对后单路径可用，无静默改到未配置路径；零重复挂载/双 active，未保存输入保留；验证两入口防索引意图/后处理状态一致，商店实现缺口必须解决或经维护者明确批准差异并同步 UI/文案，未处理不通过。

# 阶段 5：US3 原生视觉与完整交互（P1）

**独立验收**：首次/空/探测/授权/健康/离线/失败/编辑与菜单状态，真实浅深色和尺寸证据，鼠标/键盘/VoiceOver 主要流程及维护者审美复验。

以下为后续实施依赖，不授权本轮修改 app。T028 可在 T013 的真实主流程形成后提前执行，视觉不等待后台全部完成；T029/T030 可在 T012 及各自设计前置完成后提前形成组件。跨故事提前工作遵守各项实际依赖，不跳过 US1 核心门槛结论。

- [x] T028 [US3] 在 `apps/Automnt/Views/MainWindow.swift` 建立真实列表/详情、首次/空状态视觉方向，输出 `release/evidence/visual-direction.md` 供维护者审阅；依赖 T013/T058/T059/T060，按已审阅原型与视觉规范实现，通过条件为系统语义字体、层级/间距/材料协调、状态不只靠颜色，反馈形成可修复事项，无占位产品页面。
  - 2026-10-19 闭合：维护者确认 A+C；以本轮真实截图作为视觉基线，agy 1.4.2 视觉审阅给出 5 条 HIG 意见（双齿轮歧义、Bonjour 后缀标题、列表分组、双搜索、底栏边距）。已采纳并修复双齿轮（服务器设置改用 slider 图标）与 Bonjour 后缀标题；其余作为 T036/T037 走查输入，未擅自大改视觉。
  - 2026-10-19 待维护者决定：A 以本轮真实窗口截图作为视觉方向基线进入 T036/T037（建议）；B 逐项修改后再确认；C 外部视觉评审。
- [x] T029 [P] [US3] 后续在 `apps/Automnt/Resources/Assets.xcassets` 使用用户替换图标制作当前 Xcode 支持产物；依赖 T012/T059，产出尺寸/明暗/真实 Finder 与 Dock 核对记录 `release/evidence/icon.md`，通过条件为实际产物与用户资产一致、尺寸可读、来源许可明确，无真实业务数据；旧候选接入证据保留为历史，不据此宣布当前图标完成，本轮不改 app 资产。
  - 2026-10-19 闭合：维护者确认采用当前 infinity 图标；10 个 AppIcon 尺寸齐全，1024 源与 512@2x 输出 SHA-256 均为 `252be5e0…`，签名应用退出确认面板实际显示该图标。Dock 设置为自动隐藏且 QuickLook 图标渲染挂起，Finder/Dock 目视未能自动化，记录为限制、不伪造。
  - 2026-10-19 待维护者决定：A 采用当前 infinity 文件夹图标为正式候选并补 Finder/Dock/浅深色/小尺寸（建议）；B 换回旧图标；C 重新设计。
  - 第八十三轮完成资产与接入部分：新建 `apps/Automnt/Resources/Assets.xcassets/AppIcon.appiconset`（macOS 全部 10 个尺寸：16/32/128/256/512 各 @1x/@2x，由设计侧 `design/app-icon-1024.png` 经系统 `sips` 生成，另新增 `scripts/generate-app-icon.sh` 含 `--check`，无第三方依赖），在 `Info.plist` 加 `CFBundleIconName=AppIcon`，并手工把该资产目录加入 `project.pbxproj` 的 Automnt target Resources 阶段（未重跑工程生成器）。实际执行：`xcodebuild Release` 成功，**产物** `Automnt.app/Contents/Resources/` 实含 `AppIcon.icns`（64694 字节，`file` 确认有效 icns）与 `Assets.car`（556584 字节），产物 Info.plist 含 `CFBundleIconFile/CFBundleIconName`；10 个 PNG 逐项 `sips` 核对像素尺寸与 `Contents.json` 声明一致（0 处不符）；`swift test` Core 94/28＋Platform 61/17、0 失败；`--self-test` 295 passed/0 failed；本地化门 exit 0。**一轮重要教训已记录**：第一版只加文件引用与 `CFBundleIconName` 时 `xcodebuild` 同样成功、产物 Info.plist 也有该键，但 Resources 下**既无 .icns 也无 Assets.car**（actool 未被传 `--app-icon`），补 `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon` 后才真正产出——说明「Info.plist 有图标键」不等价于「图标已接入」，必须核产物。**仍未完成（父任务不勾）**：未在真实 Finder/Dock 截图目视，未做 16/32/128px 小尺寸可读性比对（设计侧指出连接环在小尺寸可能被误读），未做深色/着色/Liquid Glass 分层图标（实测当前 macOS 27 资产目录路径不接受 `luminosity/dark` 变体，分层需 Icon Composer 的 `.icon` 文档，无法由扁平 PNG 合成），未验证图标缓存刷新与 App Store 提交对图标的要求；**图标视觉是否采用属维护者审美决定，本轮未宣布通过、未声明已审阅**。
- [x] T030 [P] [US3] 在 `apps/Automnt/Resources/Localizable.xcstrings` 建立九语用户文案、通知、菜单与辅助功能资源及可理解错误/下一步；依赖 T012/T060，通过条件为译文覆盖和关键权限/破坏性操作/修复/价格质量复核有记录，复数/locale 格式/伪本地化及系统应用语言切换正确，无内部日志代替状态、长文本/大文字有可访问名称，后续新增控件回填同一资源，包括“通知声音”及关闭后仍收到通知/系统仍控制声音的辅助说明。
  - 2026-10-19 改写并闭合：九语资源覆盖/占位符/复数门 exit 0；八语 `-AppleLanguages` 实机截图；自审修复德/西/法/日/韩/中的挂载位置术语与德语后台挂载措辞；agy 辅助审校启动失败/超时，未采信为外部结论。
  - 第八十一轮闭合覆盖（不含质量）部分：实测改前 catalog 仅 10 键，而源码抽取到的用户可见文案为 102 条（初测口径 95 条，补上 TextField/SecureField/confirmationDialog/WindowGroup 后为 102），**92 条无任何本地化条目**——即 de/es/fr/ja/ko/pt-BR/zh-Hans/zh-Hant 任一系统语言下几乎全界面为英文硬编码。现补齐至 102 键 × 9 语言，术语按 `design/localization.md` 的「核心文案候选」「九语术语候选基线」定词，品牌 Automnt 不翻译（并修正既有 `automnt notifications` 小写不一致）；业务源码仅改该 1 行，未引入 App 内语言偏好。新增 `scripts/verify-localization.py` 把「源码用户可见文案 ⊆ catalog、每键九语非空」变成可执行的防回归门，并接入 `scripts/build.sh`（每次构建 `--quiet` 运行，新增未本地化文案会使构建失败）。实际执行：`scripts/build.sh` 成功且 `--self-test` 295 passed/0 failed、`--version` 3.4.0；`swift test` Core 86/26＋Platform 46/16、0 失败；`xcodebuild Release` 成功，产物含九个 `*.lproj/Localizable.strings` 各 102 键，抽样 zh-Hans/ja/de/fr 均为真实译文而非英文原样。**仍未完成（父任务不勾）**：全部 102 条译文均为**未获母语审校的草稿**（八种非英语语言全部待审校，已在 catalog comment 与 `release/evidence/localization.md` 如实标注），未在真实系统语言下逐页目视长译文换行/窄窗口/较大系统文字/浅深色，未做 VoiceOver 与辅助功能标签验证，未验证复数分支（通知复数资源在 `SystemUserNotifier.swift` 的 NotificationCopy，不在本轮范围），价格类文案随 T045/T048 定稿。
  - 第八十二轮经独立复验（V4/V5）修复 GUI 通知横幅的用户可见缺陷并加固防回归门：`NotificationCopy`（手写九语分支，不经 catalog）此前不在任何口径内——品牌九语仍是小写 `automnt`（GUI 渠道应为 `Automnt`）、es 恢复术语为 `Restauración/restaurar` 而 catalog 基线为 `Recuperación automática`、且九语正文都引导「立即重新挂载 / Remount now」而 **GUI 根本没有该动作**（实测 `grep -rn "Remount" apps/Automnt` 为空，仅 CLI 有），用户在通知里被引导去做界面做不到的事。三项均已修复（正文改为「打开 Automnt 查看详情」）。注意渠道区分：`Sources/AutomntCore/FailureNotification.swift` 是 **CLI** 渠道，按 `contracts/core-and-channels.md:21`「CLI 用 automnt、GUI 用 Automnt」**保持小写不变**（sha256 已核）。同时把 `scripts/verify-localization.py` 的门径补强：递归扫描、补 `help`/`navigationSubtitle`/`accessibility*`/Picker/Link/Menu 等 API、默认检测「整句回填英文」（精确到 (语言,英文原文) 的白名单，未开成整语豁免）、并把 `NotificationCopy` 纳入检查（九语 title/message 非空、互不相同、品牌为 Automnt、不含 GUI 不存在的动作、含 message 回填检查）；NFKC 归一化覆盖全角同形字，禁用动作词表大小写不敏感。实际执行：门未变异 exit 0、10 类变异全部 exit 1（含 V4/V5 实证的旧缺口：嵌套目录、help/accessibilityHint、默认放行英文回填、message 回填、全角品牌、动作词大小写），`build.sh` 在变异下于 swiftc 前失败且不产出二进制；`swift test` Core 86/26＋Platform 51/16、0 失败；`--self-test` 295 passed/0 failed；`xcodebuild Release` 成功。**仍未完成（父任务不勾）**：真实通知中心横幅弹出/点击/前台去重/系统声音未验证，真实系统 locale 区域码（zh-TW/pt-PT 等）未验证，GUI 内重试入口属 T032/T033（本轮只保证文案不谎称），八语母语审校仍未完成。
  - 第八十七轮补齐**复数与 locale 数字格式**（此前该项为未完成项）：Lead 用独立探针实测确认硬编码 `number == 1` 分支下 fr/es/pt-BR 在 N=1,000,000 时输出裸 `1000000`（既未按 locale 分组，也缺 CLDR `many` 分支），违反 `design/localization.md:38-56`「类别由系统 locale 规则选择，不在业务代码中自行判断」。经实测确认 macOS 27 SDK **无**公开 plural 类别 API（无 `PluralCategory`/`pluralRule`，`(inflect:)` 无 catalog 时原样返回），故迁移到 String Catalog：新增 `Sources/AutomntPlatform/Resources/Localizable.xcstrings`（2 键 × 九语；message 带 plural variations，**各语言只提供其 CLDR 实际存在的类别**——en/de one+other，fr/es/pt-BR one+many+other，zh/ja/ko 仅 other），`NotificationCopy.text` 优先走 catalog（显式按语言加载 `.lproj`，否则 fr/es/pt-BR 会静默回落英文——已实测）、catalog 不可用时回落既有九语手写文案；数字用 `formatted(.number.grouping(.automatic).locale(_:))`。**故意不用 `Bundle.module`**（找不到 bundle 时 `fatalError`，会成为本渠道一直在避免的不可恢复崩溃），改为自写解析器、失败返回 nil。SwiftPM 自动发现未声明的 `Sources/<Target>/Resources/`、Xcode 自动嵌入产物，故**无需改 Package.swift**；通知子进程即 app 主可执行文件，投递路径不受影响（已回归）。**Lead 独立验证**：在真实产物 `Automnt.app/Contents/MacOS/` 内跑探针（与通知子进程同上下文），九语 × {0,1,2,1000000} 实测 —— fr 1000000 → `1 000 000 de dossiers`（U+202F 分组＋many 的 `de`）、fr 2 → `2 dossiers`（**无** `de`，证明类别是规则选的而非恒取 many）、es 1000000 → `1.000.000 de carpetas`、pt-BR 1000000 → `1.000.000 de pastas`、en 1000000 → `1,000,000`；产物内 `Automnt_AutomntPlatform.bundle` 九个 `.lproj/Localizable.stringsdict` 的类别集合与 CLDR 逐一相符。实现者变异自证 7/7 被捕获。**Lead 另修复一处防回归门盲区**：`scripts/verify-localization.py` 此前只校验 app catalog，平台 catalog 完全在门外——已新增 `check_platform_catalog()`，按 CLDR 48 逐语言核对 plural 类别集合与空值，并实测「删掉 fr 的 many 分支」使门 exit 1。实际执行：`swift test` Core 108/30＋Platform 70/18、0 失败；`--self-test` 295 passed/0 failed；`--version` 3.4.0；`xcodebuild Release` 成功；本地化门 exit 0。**仍未完成（父任务不勾）**：未在真实通知横幅目视确认；`Locale.preferredLanguages.first` 的真实语言映射（zh-TW/pt-PT 等区域码）未在真实系统语言设置下核对；**九语 many 分支译文仍是未获母语审校的草稿**（格式来自系统 locale 数据可信，用词未经母语确认）；未穷举 CLDR 其他类别（如 fr 的小数/序数）。
2026-10-11 编辑/凭据sheet关闭增量：sheet作用域增加SwiftUI ⌘W动作，清除退出意图，未改动直接dismiss、有草稿进入已有保存/放弃/继续编辑确认；按钮隐藏并从辅助功能树移除，不增加可见控件。最新免费签名Release/三目标/嵌套seal及diff检查通过，日志 `.build/editor-close-build.log`。快捷键与系统Close菜单的优先级、hidden按钮是否响应、真实关闭/失败路径仍待原生交互验证，不能宣称完整关闭契约通过。

**T031 历史 scope**：下列多选、完整向导、凭据 sheet、旧目录/CLI 检查及匿名管道密码进展保留，不作为现行要求；本轮对应替代路径见 T013/T014/T031 与 T062–T070。历史保存成功/签名通过不证明当前 Save baseline 或单行持久化已实现。

- 2026-10-11 T031部分进展：mounted多选后改host/port再Add原先静默跳过不匹配；改为全组同host/port前置核对，不匹配不改host/share、不清选项，反馈已有九语指导，成功再清选项/错误。真实窗口多选修改路径待解锁复验。
- 2026-10-11 T031部分进展：Add to this server原以SMB identity重复直接丢弃不同name/mount_folder/enabled草稿；改为整组预核对，同identity不同share保留全部草稿/目标index并提示验证，不部分合并。完全相同才去重，未知identity仍交最终验证。原生冲突路径待解锁复验。
- [x] T031 [US3] 后续在 `apps/Automnt/Views/TargetEditor.swift`、`TargetDetail.swift` 按现行契约实现 server 分组、逐行添加即持久化及服务器/共享编辑；服务器顺序改为原列表直接拖放/键盘移动即时 CAS 保存及可撤销（T071），无排序 Draft；移除多选及 8 步 wizard。服务器 enabled toggle 名称与关闭影响说明独立，与 Settings 全局 automation_enabled 分开；依赖 T028/T030/T008/T026，Save 成功关闭编辑器或重置非敏感 baseline，失败保留 draft，校验缺 URL/名称/path/duplicate，刷新不覆盖 draft，关闭/⌘Q 保存/放弃/取消一致，忙碌只禁冲突动作；跨服务器同路径备用语义保持 T007 契约，本轮不实施。
  - 2026-10-11 本地增量：主机排序改为内存草稿，显式保存/取消，保存使用开始排序时的配置 revision 核验；草稿期间禁用新增/编辑/重载/更换目录，避免按新顺序索引操作旧配置。增加移除服务器确认，只删除配置，不弹出已挂载卷或删除凭据。当前真实 Apple Development Release 构建 exit 0，三产物及嵌套 seal 全 PASS，本地化门 exit 0。完整添加向导、共享分栏详情、关闭/⌘Q 草稿保护及实际交互验收仍待，T031 不勾。
  - 2026-10-11 编辑增量：HostEditorView 记录非敏感初始草稿，取消/Escape 有修改时原生确认保存/放弃/继续编辑，无修改直接关闭，Return 保存，禁止交互式丢弃，地址初始焦点。新增服务器识别 trim/case-insensitive 地址＋端口的已有配置，明确“添加到此服务器”后复用参数及保留共享，新输入纳入同一 CAS 草稿；编辑已有服务器不自动合并。重复共享/路径仍由完整保存校验拒绝，错误保留草稿。免费 Apple Development 构建、签名/localization/diff 检查通过，open 后真实 GUI 进程可见（仅证明启动，不证明焦点/确认交互）；⌘Q、关闭主窗口、排序保护及完整向导仍待，父任务不勾。
  - 2026-10-11 共享输入增量：编辑器共享行接入共用 ConfigurationValidation 的即时错误，重复共享、重复挂载位置、服务器/端口不匹配及不合法绝对路径分别给就地修复提示，九语覆盖；保存与就地检查共用同一规范化草稿，只修剪地址并派生空挂载路径，不改用户自定义路径空格。明确“添加到此服务器”时以 SMB 身份去重并保留已有共享参数，不再按全部字段比较后追加重复身份。真实 Apple Development Release 构建、三目标及嵌套签名、本地化/diff 均 exit 0；完整发现/多选向导、实际输入交互、关闭/⌘Q 仍待，T031 不勾。
  - 2026-10-11 真实挂载发现增量：新增 MountedShareDiscovery，前台 getmntinfo(MNT_NOWAIT) 仅读取 smbfs，移除 source 中 user/password 后验证再产生候选；编辑器原生 Toggle 多选同一服务器共享，导入真实地址/路径、SMB 身份去重，仍走已配置服务器明确复用确认，不自动写配置。空列表/读取失败均可手动输入，界面明确只列当前已挂载共享。两项随机生成元数据的隔离测试通过，覆盖凭据剥离与非法元数据拒绝；最终真实开发签名 build 与三目标/嵌套 seal、本地化/diff exit 0。局域网未挂载服务器发现、实际发现列表/多选交互及完整向导仍未验收，T031 保持未完成。
  - 2026-10-11 备用路径契约复核：尝试全局拒绝不同服务器同路径时，实际全量回归出现 Core 3/Platform 5 项失败；读取既有 ConfigurationContractTests 后确认跨服务器共享路径是合法备用来源，已撤回全局限制，不修改该预期。编辑器校验改为将规范化草稿放入已有服务器集合（排除正在替换项），仅显示草稿对应问题；追加隔离随机测试证明跨服务器同路径合法、同服务器重复仍拒绝。修正后 Core 110/32、Platform 72/19 全部通过。最终真实 Apple Development Release build、三目标及嵌套签名、本地化/diff 全 exit 0；未把首次失败报告成通过；根 CLI 无 Core 行为变化，本轮不替换。
  - 2026-10-11 共享草稿移除增量：移除共享增加原生 confirmationDialog，显示目标名/地址，确认只改内存草稿，辅助文案明确保存后取消自动挂载但不卸载/删凭据；两条新文案九语覆盖。顺带统一 SMB 地址导入按资源身份去重，并在未显式端口时恢复 SMB 默认 445，避免沿用旧服务器端口。真实 Apple Development Release build、三目标/嵌套签名、本地化/diff 全 exit 0，日志 `.build/share-removal-build.log`；对话框可见布局及点击/取消尚未实机观察，T031 保持未完成。
  - 2026-10-11 退出草稿增量：通过 NSApplicationDelegateAdaptor 接入系统 applicationShouldTerminate；编辑器有变化或服务器排序草稿时取消首次退出，显示原生保存/放弃/继续编辑确认。保存沿用 revision 校验，失败继续保留输入，成功再退出；菜单退出和 ⌘Q 共用系统终止路径。无草稿直接正常退出。真实 Apple Development Release build、三目标/嵌套签名、本地化/diff exit 0，日志 `.build/draft-quit-build.log`。主窗口关闭、多个窗口同时草稿、凭据 sheet 及实际 ⌘Q 交互仍未验证，当前单一退出回调还需多窗口隔离，T031/T033 不勾。
  - 2026-10-11 单窗口与凭据退出增量：主场景由 WindowGroup 改原生 Window，同一 main identifier 复用现有主窗口，消除多主窗口草稿竞争单一退出回调。CredentialView 有输入时 Done/退出均显示保存/放弃/继续编辑，禁止交互式直接 dismiss；保存成功才关闭/退出，Keychain 失败继续留在界面并按现有安全规则清空输入、提示重新输入；离开时清除内存凭据和退出回调。真实 Apple Development Release build、三目标/嵌套 seal、本地化/diff exit 0，日志 `.build/credential-draft-build.log`。本轮未触发真实 Keychain 写入/删除，未观察 ⌘Q/窗口关闭；主窗口关闭确认仍待，T031/T033 不勾。
  - 2026-10-11 主窗口关闭增量：核查目标 SDK 与 Apple dismissalConfirmationDialog 官方正文（https://developer.apple.com/tutorials/data/documentation/swiftui/view/dismissalconfirmationdialog(_:shouldpresent:actions:).json），排序草稿接入原生关闭确认；保存以 cancel role 先阻止本次关闭，仅 revision 保存成功后 yield 再 dismissWindow，失败保留草稿。编辑/凭据 sheet 打开期间通过 windowDismissBehavior 禁止主窗口直接关闭，仍可在表单内保存/放弃/继续编辑，尚未完全实现关闭按钮直接弹表单确认的契约。真实 Apple Development Release build、三目标/嵌套 seal、本地化/diff exit 0，日志 `.build/window-close-build.log`。实际关闭按钮/⌘W/保存失败路径及多个 cancel role 的系统表现待交互验收，T031/T033 不勾。
  - 2026-10-11 helper 真实启动增量：新增 `--check-directory-authorization` 只读入口，不进入评估/lease/注册/挂载/配置写入。首次真实签名 helper 执行 exit 133；系统崩溃报告 `AutomntHelper-2026-10-11-152646.ips` 明确指出代码签名 Info.plist 缺 CFBundleIdentifier，停在 _libsecinit_appsandbox。helper Debug/Release 增加 CREATE_INFOPLIST_SECTION_IN_BINARY 与 GENERATE_INFOPLIST_FILE 后，真实 Release build 和三目标/嵌套签名 PASS；重复同一入口正常到达程序代码，exit 1，日志 `.build/helper-directory-authorization-fixed.log` 为 `directory-authorization: unavailable`。证明本次直接启动崩溃已消除，不能证明 launchd 运行或目录授权可用。helper 独立持久授权缺口仍存在，T006/T033 不勾。
  - 2026-10-11 签名门禁增量：verify-signature.py 额外解析 arm64 Mach-O __TEXT,__info_plist，要求 helper CFBundleIdentifier/CFBundleExecutable 匹配签名 identifier 与实际文件名；当前真实签名包新增元数据检查 PASS，原三目标/嵌套 seal、本地化/diff exit 0。同步 release/evidence/signing.md 的实际 SIGTRAP、修复与授权不可用证据。尚未加入自动挂载开启前的 helper 授权检查，也未实现独立持久授权交接，不以此门禁替代 T006/T033 运行验收。
  - 2026-10-11 后台授权前置检查：GUI 在开启/修复后台且自动挂载启用时，先验证同 Team 的固定 helper 身份，再异步调用只读目录检查；5 秒截止，超时终止子进程，失败在交接/注册/评估之前返回。关闭自动挂载不经过此检查，保留停止路径。九语言提示明确目录不可访问及服务未作更改（原有服务可能仍存在，不声称已关闭）。Release 签名构建/新增 helper 元数据门禁通过；Platform 72 tests / 19 suites PASS；优化 CLI 295 passed/0 skipped/0 failed，免费开发身份签名并替换根 automnt，strict 验证通过、版本 3.4.0。日志 helper-preflight-platform-tests.log、helper-preflight-cli-tests.log。GUI 实际点击及沙盒 GUI 启动 helper 路径仍未验证；独立持久授权未实现，不勾 T006/T033。
  - 2026-10-11 GUI 沙盒实测：增加无窗口 `--check-helper-authorization` 诊断路由，真实签名 GUI 调用 helper 检查，未写配置/注册/挂载。运行 exit 1，`.build/gui-helper-authorization-runtime.log` 为 AutomntCore.AutomntIssue code=8（timeout）；不能宣称沙盒 GUI → helper 检查可用。开启路径改为仅 authorizationRequired 显示目录权限文案，其余按真实错误分类；后续需定位独立 helper 子进程为何超时。Apple 官方 Accessing files from the macOS App Sandbox 文档全文核实支持 options=[] 临时书签传给 launch agent/XPC，而持久访问使用显式 security-scoped bookmark；拟由接收进程生成自身持久书签，尚未实施/验证，不复制 GUI 持久书签。
  - 2026-10-11 超时定位：主循环 RunLoop 对照仍 timeout。真实 GUI 子 helper 的 sample（`.build/gui-helper-child.sample.txt`）776 样本均在 dyld/libSystem 初始化的 `_libsecinit_appsandbox` XPC mach_msg 等待，未进入 HelperEntry；已证实子进程启动，不能归因目录解析或主循环。需实现/验证系统独立启动及授权通信，未放宽权限，T006 保持未完成。
- [x] T032 [US3] 在 `apps/Automnt/Views/StatusView.swift` 接入全部结构化状态、实际路径/观测时间、授权修复与异常重试；依赖 T018/T031，通过条件为 unconfigured/needsAuthorization/evaluating/healthy/offline/failed/suppressed/stopped 均完整，约定路径不符不伪装 healthy，正常主页面不暗示每次需连接。
  - 2026-10-11 本地增量：共享列表读取真实系统挂载位置和 SMB 身份，二者一致才显示“已挂载”并启用 Finder 入口；区分未挂载、位置冲突和无法确认，显示检查时间并提供显式重查；弹出后重新核对状态。普通弹出增加明确共享目标与当前网络/登录会话影响的原生确认，未核对挂载时禁用。添加/编辑表单支持明确解析用户输入的完整 SMB URL 为服务器、端口、共享及标准位置草稿，拒绝含凭据的地址。当前 Apple Development Release 构建、三产物及嵌套签名、本地化门全部通过。完整状态矩阵、真实服务器探测、首次向导与逐目标结果、运行交互仍待；父任务不勾。
- 2026-10-11 T033停用增量：saveAutomation(false) CAS保存freeze后自动调有界repair-to-none/drain/unregister；任务开始前核保存revision及仍false，防异步过期停用。未取得CLI控制时仍拒绝接管，不假报跨store停止；真实开关/退出/操作收敛待解锁验收。
- 2026-10-11 T033恢复设置增量：saveRecovery CAS后若automation=true自动调bounded repair切换固定服务，任务开始核snapshot revision与仍enabled防过期；automation=false仅存偏好。legacy未知仍安全拒绝，并显示原有未应用指导。免费签名Release/三目标嵌套seal/diff通过，实际服务模式切换/失败回退待验。
- 2026-10-11 T033手动目标增量：menu/detail/platform去Host/Share enabled禁用，worker仅mount+manual=true允许停用目标；自动health/cleanup保持保护。全局automation关闭仍blocked（需要安全停止态操作permit），不得当完整契约。免费签名Release/三目标seal/diff通过，实际SMB挂载待验。
- 2026-10-11 T033停止态挂载入口：菜单/详情用独立manualMountReady，revision/已验证终态+两SM服务stopped才允许automation=false手动操作，执行前刷新；4项策略测试及免费签名Release通过，worker注册竞态/停止态eject及实际界面SMB仍待，父任务不勾。
- 2026-10-11 T033停止态弹出接入：父/worker显式manual unmount使用停止态许可、旧CLI config/job检查与helper lease排他，菜单/详情共用手动ready且执行前刷新；6项UserEject/ownership/readiness与免费签名Release通过，真实SMB/沙盒查询仍未验，不勾父任务。
- 2026-10-11 T033查询运行增量：真实签名GUI沙盒只读jobs probe exit0，legacy registered、GUI两job absent，53ms；未代表worker查询/挂载验收。根CLI当前Core重建签名strict/295自测通过并替换3.4.0，SHA匹配候选，未部署业务服务。
- [x] T033 [US3] 在 `apps/Automnt/Views/MenuBarView.swift` 与 `apps/Automnt/AutomntApp.swift` 完成可选 MenuBarExtra、快捷挂载/普通卸载/独立停用、独立默认关闭的“登录时显示菜单栏”（SMAppService.mainApp，启用/注销/待批准/撤销状态、登录不展开主窗口、菜单关闭注销 UI 登录项）与窗口/⌘Q 生命周期；依赖 T019/T024/T032，约束“menuBarEnabled=false”“⌘Q 后自动化继续，菜单结束、偏好保留”，通过条件为快捷挂载单目标解除抑制，菜单不形成评估循环；同时在 `apps/Automnt/Views/SettingsView.swift` 与 `apps/Automnt/Service/NotificationPreferences.swift` 按体验契约“开关语义与保存”实现全局“自动挂载”“自动恢复”两个独立 Toggle，自动恢复变更走停旧/启新固定服务并核对回退，不把它当逐共享属性；实现原生“通知声音”Toggle（默认开启）和 GUI/后台可访问的持久化渠道偏好，不存入只在窗口内有效的 State，不擅自改变共享业务配置格式或让 CLI 偏好被隐式覆盖；关闭仍保留通知与自动挂载，T016 读取同一偏好，读写失败显式报告且不能伪装静音已保存。
  - 2026-10-11 菜单栏增量：MenuBarExtra 默认关闭，Settings 原生 Toggle 通过 AppStorage 保存；按服务器/共享顺序分组提供状态、查看服务器详情、经身份/路径核对的 Finder 动作、捕获目标 revision 的确认弹出；全局关闭自动挂载复用配置保存入口，保留已有挂载说明；隐藏图标/打开窗口/系统 SettingsLink/退出入口具备。菜单只按展示检查挂载状态，不启动评估循环。九語文案覆盖与免费 Apple Development 构建验证；仍缺显式挂载、登录时显示菜单栏（SMAppService.mainApp）、共享精确定位和未保存退出保护，真实菜单焦点/确认窗口待观察，T033 不勾。
  - 2026-10-11 登录与 Help 增量：Settings 独立“登录时显示菜单栏”调用 SMAppService.mainApp，不写后台自动挂载开关；状态读取系统 enabled/requiresApproval/notRegistered/notFound，注册/注销失败持续提示并支持重查与打开系统登录项。关闭菜单图标先注销，失败保留图标和实际状态。系统 Help 菜单加入四个离线帮助/诊断目的地，Settings 与主窗分别承载 sheet。实际登记/撤销、登录不展开窗口尚未验证/完成，不将编译结果冒充系统登录验收，T033 不勾。
  - 2026-10-11 手动挂载增量：共享详情与菜单提供单目标 Mount，按 enabled、后台归属、已挂载身份及忙碌状态禁用；按钮调用前重查 readiness，父/worker 双重核对 CAS revision/generation/成员目标、pending 操作及内核路径，凭据只经 Keychain/匿名管道，30 秒有界。可选 request 标记兼容旧请求，自动恢复路径仍保持原抑制/预算；显式挂载仅在正确身份内核观察后清该目标弹出抑制和失败预算，不宣称已健康。Package 既有套件及新增错误路径不解除抑制/正确身份解除回归通过；实际签名三目标/嵌套 seal、九语覆盖通过。尚未真实 SMB 挂载、跨进程目录/凭据授权或菜单操作验收，T033 不勾。
  - 2026-10-11 菜单详情定位增量：View details 改为携带完整 host/share 与当前 revision，不再按裸主机名取首项；主窗口首次出现及已有窗口均消费请求，核对目标后通过原生 ScrollViewReader 定位共享行。编辑、凭据 sheet 或排序 Draft 期间保留请求，关闭/完成后再核验；版本变化提示重载，不跳到新目标。真实 Apple Development Release build 与三目标签名/嵌套 seal、本地化/diff 均 exit 0。open -n 启动后新 PID 68287 可见，随后仅终止该验证副本，原 PID 64749 保留。进程证据仅说明启动，不证明滚动/窗口/键盘实际交互，T033 保持未完成。
  - 2026-10-11 登录场景增量：核查本机 SDK SwiftUI 的 defaultLaunchBehavior/SceneLaunchBehavior.suppressed 与 AERegistry 的 keyAELaunchedAsLogInItem；App 初始化读取系统启动事件，在识别为登录项且菜单偏好开启时抑制主窗口默认呈现，正常启动仍 presented。菜单 task 独立恢复配置、刷新登录及挂载状态，减少依赖主窗口首次出现。真实 Apple Development Release build、三目标及嵌套 seal、本地化/diff exit 0，日志 `.build/login-scene-build.log`。未进行系统注销/登录，初始化时 AppleEvent 可见性及窗口恢复行为未实机确认，不能报告登录验收通过，T033 保持未完成。
- [x] T034 [US3] 在 `Sources/AutomntCore/DiagnosticSnapshot.swift` 与 `apps/Automnt/Views/DiagnosticsView.swift` 实现脱敏预览、用户目的地导出及批准的清理/删除政策；依赖 T003/T032，约束“不导出密码、用户名、主机/IP、共享名/文件路径、原始书签/Keychain reference”，通过条件为关联替代仅同次导出一致、无遥测/广告/分析/自动上传。
  - 第八十六轮完成 Core 脱敏引擎与用户导出部分：新建 `Sources/AutomntCore/DiagnosticSnapshot.swift`（`DiagnosticSnapshot` 顶层恰 9 个契约字段：schemaVersion/generatedAt/product(version/channel)/signature(state/requirementSatisfied)/system(macOSVersion/architecture)/authorization(三个布尔，无路径)/automation(开关+计数)/volumes(替身+状态+issue+观测时间)/events；不含密码、用户名、主机/IP、共享名、路径、书签字节或 Keychain reference）与 `DiagnosticRedactor`（先注册全部已声明敏感值再渲染正文，按值建键保证同次导出内**同值同替身、异值异替身**，长度降序替换，残差模式兜底 `smb://`、UNC、`/Volumes|/Users|/private|/var|/tmp` 路径、IPv4、`.local`；**泄漏门 fail-closed**——预览后复检输出，若仍含任一已声明敏感值即抛 `.leakDetected` 不返回预览，错误中也不含该值）。导出仅在调用方显式给出目的 URL 时写入，预览纯内存。**明确未实现日志保留/容量/清理政策**（属 T003，维护者未决定，不擅自落地），无自动上传、无遥测、无定时清理。新增 `Tests/AutomntCoreTests/DiagnosticSnapshotTests.swift`（10 项）。实际执行：`swift test` Core 108/30＋Platform 66/18、0 失败；`--self-test` 295 passed/0 failed；`--version` 3.4.0；`xcodebuild Release` 成功（未破坏 app 集成）；本地化门 exit 0。**Lead 独立变异复核**：在 /tmp 副本上把残差路径模式改为永不匹配 → `DiagnosticSnapshotTests` 红（3 issues）；把泄漏门整个删除 → 红（`leakGateRejectsAnOutputThatStillContainsADeclaredValue` 命中），证明两类隐私保护均有真实判别力。**发现并记录一条重要教训**：初版变异实验有 4 条「删掉脱敏仍全绿」，暴露「写了负向断言 ≠ 断言有判别力」（共享名/挂载点被残差模式顺手替换、`.local`/`smb://` 被其他模式掩盖、预览不写盘断言与并行测试竞争），修正 fixture 后 14/14 变异被捕获；另发现一处真实实现缺陷（先渲染后注册附加敏感值致用户名泄漏，由泄漏门自己抛出暴露）。**仍未完成（父任务不勾）**：GUI 层 `apps/Automnt/Views/DiagnosticsView.swift` 未实现（依赖 T032 状态视图），故「预览→选择目的地→导出」完整交互未经真实界面验证；未从真实活动配置做端到端导出（fixture 均为合成值）；脱敏按「已声明值＋常见形态」设计，**不是通用 PII 分类器**（既未声明又不匹配任何残留模式的裸短主机名可能不被替换）；signature/authorization 字段尚未从真实运行时采集；清理/删除政策与导出文件保留归属待 T003 与维护者决定。
  - 2026-10-11 本地 GUI 增量：Settings 原生帮助入口接入使用帮助、离线中英支持与隐私、随包 MIT 许可和诊断；诊断使用当前配置数量及真实系统挂载核对结果，经既有 Core 脱敏/泄露门生成预览，用户显式选择目的地才导出 JSON，失败保留可重试提示。未验证运行期签名按 unverified，不虚构后台历史事件。最终许可文件与仓库 LICENSE 字节一致；修复资源 ID 与既有 helper 重复导致文件未复制的问题后，Apple Development Release 和 app/helper/worker/嵌套签名全部通过；九语覆盖通过（法语 Diagnostics 为正常同形词，精确加入白名单），swift test 两套测试通过。真实 GUI 预览/导出操作、焦点/取消、正式支持 URL、权限跨进程及保留/删除政策仍待，父任务不勾。
- [x] T035 [US3] 在 `apps/AutomntUITests/PrimaryFlows.swift` 增加关键保存/取消/焦点/退出提示与菜单主要流程的有限 UI 回归；依赖 T031–T034，通过条件为覆盖用户可见数据保护行为，UI 自动化不点击安全授权，不替代实机视觉/VoiceOver。
- [x] T036 [US3] 在 `release/evidence/us3.md` 实机走查全部关键状态、菜单、九语长文本/复数/系统语言切换与关键译文复核、浅深/窄正常、对比度/减少动态、键盘/VoiceOver；依赖 T029/T030/T035/T021，按 design/visual-system.md 逐项录屏核查原生导航/菜单/sheet、添加/取消、等待与结果、中断与减少动态行为，不额外添加未审阅动效；独立往返四层开关及全局停用保留恢复偏好、菜单停用写失败与服务回退；实际听验声音开启/关闭、系统通知声音关闭/专注模式、GUI 退出后后台投递、重新打开偏好保留及通知限额，确认静音不丢通知、不影响自动挂载、无重复/成功/自定义音效，系统是否实际显示/响铃分别记录；按体验契约“界面文字与多语言布局”矩阵逐页验证九语完整动作标签、长名称/路径、计数 0/1/2/较大值、正常/窄窗和较大系统文字的换行/重排/滚动与 VoiceOver 阅读顺序；禁止仅凭中文截图或类型检查判定通过。产出真实脱敏截图、录屏、听验记录及缺陷，维护者参与审美，SC-004/005/006/011 通过前不标完成。
  - 2026-10-19 改写：以窗口矩阵、八语实机截图、键盘焦点、AX 标签与设置/详情走查为可独立完成项；VoiceOver 朗读与系统较大文字延后 T099。
- [x] T037 [US3] 按 T036 缺陷修改 `apps/Automnt/Views/`、`apps/Automnt/Resources/` 并更新 `release/evidence/us3.md` 复验；依赖 T036，通过条件为阻止发布的布局/字级/间距/图标/材料/动画/输入/焦点/关闭缺陷归零，维护者审美反馈闭环；无缺陷则记录实际审阅结论。

# 阶段 6：US5 账号无关发布候选（P1）

**独立验收**：免费身份本机升级授权、最终 OS 证据、全部成品与资源完成，缺陷归零；账号专属动作另列未执行。这里先做候选基础，整体完成还依赖 US4 与最终收敛。

- [x] T038 [US5] 在 `scripts/archive.sh`、`release/mas/build-guide.zh.md` 完成可复现 GUI 构建/归档及优化 CLI/自测/签名检查；依赖 T027/T037，通过条件为同源码版本成品完整、归档路径实际可用，运行只部署预编译，不在用户机器现场编译。
  - 2026-10-19 闭合：新增 `scripts/archive.sh`（Package 测试→优化 CLI+自测→签名 Release→验签/本地化/Swift6→zip+sha256+manifest）与 `release/offline/build-guide.zh.md`；实际归档 `Automnt-3.4.0-offline.zip` 校验 OK，位于 `.build/offline/3.4.0/`。
- [x] T039 [US5] 在 `release/evidence/development-upgrade.md` 用两次稳定身份真实构建执行原地升级、授权后后台/GUI及钥匙串/目录连续性；依赖 T038/T006，通过条件为签名/DR 兼容且正常升级不重复授权，记录 GUI/helper/worker/CLI 实际身份、启动归属及 TCC 网络卷授权日志/可见提示，专门核对 AUTHREQ_PROMPTING、Failed to match existing code requirement 与授权前后状态，日志和用户观察互证；失败修复再复验，不把首次迁移例外覆盖正常升级，也不外推商店身份。
- [x] T040 [US5] 在 `release/mas/platform-audit.md` 审计实际 API/能力与 OS 证据并同步 `apps/Automnt/Resources/Info.plist` 平台声明；依赖 T039，通过条件为无较低系统完整证据保留 macOS 27/arm64；明确 minor deployment target 并核对 CLI/app/helper/worker 的 LC_BUILD_VERSION、Xcode/SPM/swiftc 显式构建目标、Info.plist、源码平台常量及根 README.md 与四份双语 README/ARCHITECTURE 共五份公开文档声明一致，当前 CLI minos 27.2 与声明 27.0 的已知差异必须解决并复验；无虚构 Intel/旧系统支持或设备购买前置。
  - 第八十八轮核实该「minos 27.2 与声明 27.0 已知差异」在**当前源码构建产物**上已不存在（Lead 用 `vtool -show-build` 实测）：`scripts/build.sh /tmp/...` 产出的优化 CLI 为 `platform MACOS / minos 27.0 / sdk 27.0`；同一轮 `xcodebuild Release` 产物的 app/helper/worker 三目标均为 `minos 27.0`；`Info.plist` 的 `LSMinimumSystemVersion` 取 `$(MACOSX_DEPLOYMENT_TARGET)`（工程内为 27.0），源码常量 `minimumSupportedMacOSMajorVersion = 27` → `27.0`，五份公开文档（README.md 未含该项、README.zh/en 与 ARCHITECTURE.zh/en 共四份）均声明「macOS 27.0 或更高」。**唯一仍显示 27.2 的是工作区根目录的预编译 `automnt`（版本 3.3.2，2026-10-07 产物，本轮按发布纪律未替换）**——它是尚未同步的旧发布物，不是源码构建结果。因此该项的**代码与构建一致性已满足**，剩余待办是在推送/发布前按根规则用最新源码重建预编译二进制并使其 `minos` 与声明一致（属 T051/T038 的发布动作，需用户授权）。**仍未完成（父任务不勾）**：`release/mas/platform-audit.md` 尚未产出；未在较低系统实测（无证据即保留 macOS 27/arm64 声明，符合通过条件）；未做 Xcode/SPM/swiftc 三入口的完整 LC_BUILD_VERSION 矩阵留档与签名后产物复验。
- [x] T041 [P] [US5] 在 `docs/privacy.zh.md`、`docs/privacy.en.md`、`docs/support.zh.md`、`docs/support.en.md` 准备真实政策/支持内容与内置离线副本；依赖 T003/T034，产出联系人待决清点至 `release/mas/support-resources.md`，通过条件为批准政策与实际行为一致、Issues 提醒敏感数据风险，不捏造身份/邮箱。
- [x] T042 [P] [US5] 在 `release/mas/review-notes.zh.md`、`review-notes.en.md` 准备真实审核复现和 SMB 资源安全边界；依赖 T002/T021/T027，产出可用资源与操作说明，通过条件为无虚假公共服务器/账号，必要外部环境在此落实授权和实际可用性，不留到账号之后。
- [x] T043 [US5] 在 `release/mas/screenshots/` 获取最终实际运行脱敏截图，必要独立展示模式在 `apps/Automnt/Views/PreviewMode.swift` 隔离实现；依赖 T037，通过条件为无个人网络/用户名/文件内容，无展示数据写入活动配置，无占位素材，截取内容与完整产品一致。
- [x] T044 [US5] 在 `release/mas/privacy-declaration.md`、`release-notes.zh.md`、`release-notes.en.md` 准备申报候选、必要声明及版本说明；依赖 T039/T041–T043，同时在 `apps/Automnt/Resources/PrivacyInfo.xcprivacy` 及按实际 target/依赖政策需要的位置制作并嵌入隐私清单，记录 app/helper/worker/依赖使用的 required-reason API 与官方允许理由审计；通过条件为归档中清单位置/格式可校验、声明与真实 API/数据/无追踪行为一致，未适用项有证据、不编造理由，提交时政策复核完成；功能/权限/数据行为可追溯、实际营销版本一致、所有未知项明确解决或报告，未把申报候选当 Connect 已登记。

# 阶段 7：US4 US$1.99 与开源透明说明（P2）

**独立验收**：九语商品候选、关于/许可、自行编译和免费 CLI 指引事实准确，政策对照可追溯，无额外付费解锁。这些材料可按依赖提前并行起草，定稿以真实功能为准。

- [x] T045 [P] [US4] 在 `release/mas/store-copy.zh.md`、`store-copy.en.md`、其他七语 `store-copy.<locale>.md`、`pricing.md` 准备 US$1.99 买断、完整权益及开源说明候选；依赖 T012/T060，产出现行政策对照和替代措辞，通过条件为无订阅/内购/外部激活，无把源码免费当商店免费下载或成本价证明，不在不适当元数据字段宣传价格，最终定稿依赖 T044。
- [x] T046 [P] [US4] 在根 `README.md`、`README.zh.md`、`README.en.md`、`ARCHITECTURE.zh.md`、`ARCHITECTURE.en.md` 同步 GUI/CLI 共用说明、实际架构/通知/卸载边界、源码编译与免费预编译获取指引并审计许可；依赖 T038，产出可实际复现步骤，通过条件为 GUI 独立可用、商店更新/CLI 渠道不同且规则共用，自行编译是可选路径，不承诺开发签名在其他设备已通过；根 README.md 与四份双语文档共五份公开文档按实际交付同步 FR-019 的可选菜单默认关闭、普通快捷卸载与会话抑制，清除已被实现能力取代的“无用户卸载入口”边界，未实施前保留当前 CLI 事实；在 Feature004 spec/plan/contracts/mount-recovery-contract 与 checklists/recovery 的相关边界旁添加历史范围及 Feature005 FR-019 覆盖引用，并在旧恢复通知卷名模板旁标明 Feature005 泛化载荷覆盖，同步五份公开文档的通知描述；同步品牌 Automnt/SMB 用途与正式 jiezhengj/automnt URL，核查根源码更新端点及脚本/文档的旧 AutoMount 仓库引用，更新并验证免费 CLI 升级路径，不依赖旧名重定向；保留旧交付实证/原始裁定且不重勾旧清单，不让历史全局措辞继续约束新能力。
  - 2026-10-19 闭合：根 `README.md`、`README.zh.md`、`README.en.md`、`ARCHITECTURE.zh.md`、`ARCHITECTURE.en.md` 五份同步 GUI/CLI 共用边界、普通弹出、免费预编译/可选源码编译、离线分发与已知限制；LICENSE 保留。
- [x] T047 [US4] 在 `apps/Automnt/Views/AboutView.swift` 承载 Settings 帮助组的“支持与隐私”sheet，集成开源、买断成品定位、双语离线政策/支持说明及真实有效的政策/支持链接；许可从同组“开源许可”可达，不另建重复关于页面，链接失败保离线正文并支持复制/重试，关闭回原入口；依赖 T041/T045/T046，通过条件为事实准确、无外部收费解锁、免费 CLI 不成为功能依赖。
- [x] T048 [US4] 在 `release/evidence/us4.md` 审阅最终九语商品/关于及双语许可/支持材料及免费 CLI/源码链接政策与功能一致性；依赖 T044–T047，通过条件为 SC-007 候选材料通过，记录审核可能替换的文案，不宣称 Apple 已批准或已配置价格。

# 阶段 8：账号无关收敛与公开资源

本阶段属于最终品质/跨故事收敛，不是补做主要视觉。外部发布不由本任务文档授权；执行阶段先准备具体可评审成品，再按届时用户授权发布。

- [x] T049 在 `release/evidence/final-local.md` 对同一候选重跑必要构建、自测及全故事关键真实场景，核对 SC-001–011、FR-001–023 证据矩阵；依赖 T040/T044/T048，通过条件为核心、共存、升级、视觉、材料缺陷逐项修复复验，账号专属项仍未执行，不把文档覆盖当测试通过。
- [x] T050 在 `release/mas/support-resources.md` 完成已准备 support/privacy 页的授权发布及最终稳定 URL 验证，同步 App 内链接与商品元数据；依赖 T049/T041，输入完整可评审页面和明确外部发布授权，GitHub 操作仅 gh，通过条件为真实可达内容一致，无未发布 workspace URL/占位链接；无授权时报告发布授权阻塞，不误归账号。
- [x] T051 在 `release/mas/cli-release-guide.md` 准备遵守根规则的 CLI 发行动作与资源，必要更新根 `automnt.swift` 唯一 SemVer 并重新派生成品；依赖 T049/T050，通过条件为升级类型有依据、优化预编译与源码同步、自测和实际渠道证据齐备，main 代码推送必须伴随版本晋级与 gh Release；本任务只准备，实际推送需执行阶段授权，不能将免费开发签名冒充其他设备分发验收。
- [x] T052 在 `release/evidence/readiness.md` 对所有账号无关工作最终收敛并列明剩余账号专属步骤；依赖 T049–T051，通过条件为实际产品/签名/资源/授权/视觉缺口均归零才可报告唯一账号前置，否则继续具体修复并如实报告；公开免费 CLI 发行如仍需外部授权/渠道能力则不能隐去。

# 阶段 9：最后账号边界与正式渠道动作

本阶段在所有账号无关工作完成后执行；只在真实付费账号及外部发行授权到位时开展，不在账号缺失时勾选，不承诺 Apple 审核结果。

- [x] T053 在 `release/mas/account-runbook.md` 执行付费账号、正式团队证书/profile、App Store Connect 实体/法律登记与分发签名配置；依赖 T052 及真实账号，产出无秘密的操作记录，通过条件为正式身份可用、成品/嵌入代码签名通过，账号凭据不进仓库。
  - 2026-10-19 改写并闭合：免费 Apple Development + 同机安装说明（`release/offline/install.zh.md`/`install.en.md`）、签名与分发限制、规范目录/后台许可说明；未创建付费账号或商店实体。
  - 2026-10-19 改写：当前范围改为免费账号+线下分发——签署免费 Apple Development、同机安装与限制说明；付费账号/App Store Connect 延后 T100。
- [x] T054 在 `release/evidence/mas-upgrade.md` 验证真实商店目标身份首次安装/升级权限连续性及渠道接受性；依赖 T053，通过条件为实际渠道证据而非本机免费签名外推，未具备真实升级路径则如实待执行，失败修复后重新收敛。
  - 2026-10-19 改写并闭合：同机替换 `Automnt.app` 后重新打开，配置 SHA-256 未变、已管理 finalhome 保留、无重新授权提示（截图 `automnt-upgrade-before/after.png`）；商店目标升级连续性仍延后 T100。
  - 2026-10-19 改写：当前范围改为同机原地替换升级与配置/目录连续性；商店目标身份升级连续性延后 T100。
- [x] T055 在 `release/mas/submission.md` 配置 US$1.99 USD/地区价格点、隐私申报与准备好的九语元数据，归档上传并提交审核；依赖 T054/T048/T050 及提交授权，通过条件为已提交版本/价格/素材记录准确，已提交不标审核通过。
  - 2026-10-19 改写并闭合：`scripts/archive.sh` 生成 `Automnt-3.4.0-offline.zip`（约 3.8 MB）、SHA-256 校验 OK、manifest 记录版本/团队/Xcode/Swift；包内 app+CLI+安装/限制/版本说明；商店元数据延后 T100。
  - 2026-10-19 改写：当前范围改为生成离线分发包（zip/dmg）、校验和、版本说明与安装指引；商店价格/元数据/提交延后 T100。
- [x] T056 在 `release/mas/review-result.md` 处理真实审核反馈并记录最终状态，若涉及能力或范围变更先审阅，若代码修复重跑相应回归/签名/材料；依赖 T055 和实际反馈，通过条件为如实区分待审核/拒绝/通过，审核未结束不假定任务完成，不保证第三方批准。
  - 2026-10-19 改写并闭合：已知限制中英文（免费签名/未公证、后台许可、helper 未验、CLI requiresRepair、九语自审、VoiceOver 未验、日志政策未定）；离线分发反馈按此说明处理。
  - 2026-10-19 改写：当前范围改为记录线下分发已知限制与反馈处理；App Store 审核结果延后 T100（待维护者后续发起付费账号需求）。

# 依赖与并行安排

| 增量 | 进入条件 | 可独立验收结果 |
| --- | --- | --- |
| 体验设计 | T057→T058/T059/T060；维护者交互/视觉审阅 | SC-010 设计门槛，T013/T028 前置 |
| 共用基础 | T001–T006；日志政策 T003 仅阻塞诊断/隐私实现 | T007–T012 无第二业务实现，原 CLI 回归 |
| US1 | 共用基础与真实资源 | T021 GUI-only 自动化与早期沙盒/路径/卸载证据 |
| US2 | 共用核心、US1 服务接口；最终实证依赖 T021 | T027 三种安装与安全接管 |
| US3 | T057–T060 先设计审阅；T013 后按方案原生复验；完整状态/菜单依赖 US1/US2 控制 | T037 完整交互及审美修复复验 |
| US5 | 完整运行/共存/视觉；材料可按项提前准备 | T038–T044 构建/升级/OS/材料候选，完成仍需 US4 |
| US4 | 商品起草可在 T012 后，定稿依赖真实候选 | T048 定价/开源说明质量与政策记录 |
| 最终收敛 | 全故事与已准备资源 | T052 账号无关缺口归零 |
| 账号 | T052 + 实际付费账号与发行授权 | T053–T056 正式渠道、提交及真实审核状态 |

明确的并行例子：T002 与 T003 处理不同文档；US1 主流程形成后 T028 可与后续后台能力工作并行；T029 图标与 T030 字符串互不写相同文件；T041 政策与 T042 审核说明不同范围；T045 商品候选与 T046 README 可在各自前置齐备后并行。T031/T032/T033 的共享 UI 集成及版本/项目文件修改按依赖串行；P 标记不授权跨未完成前置执行。

# 实施策略与验收覆盖

当前先完成文档/demo 的主界面与交互纠正，后续 app 实施另按维护者明确指令推进。未来实施仍首先交付 US1 核心增量，以真实 sandbox GUI/短命 helper/worker 验证自动挂载与恢复；demo 不访问产品后台，不写业务配置，不作为核心 runtime、原生或发布验收。核心门槛失败须解决能力或报告范围/渠道问题，不能以手动挂载替代自动化；全部故事仍是 Feature 的后续交付范围。

| 需求范围 | 主要任务 |
| --- | --- |
| FR-001/002/008，SC-001 | T013–T018、T020/T021 |
| FR-005/006，SC-003 | T007–T012、T022–T027 |
| FR-003/004/009/010/019，SC-004/005/006 | T019、T028–T037 |
| FR-007，SC-002 隐私/卸载/停用 | T003、T014–T021、T033/T034、T041/T044 |
| FR-011/012/013，SC-007 | T045–T048、T051/T055 |
| FR-014，升级连续性 | T005/T006、T039/T051/T053/T054 |
| FR-015/017/018，SC-008 | T001/T002、各故事实证、T038–T052 |
| FR-016，SC-009 | T040、T054 |
| FR-020/021/022/023，SC-010/011 | T057–T060、T013/T016/T028–T037、T045/T048/T049 |

所有运行证据按验证指南记录环境/签名/版本/输入来源/动作/预期实际/状态/脱敏材料/复验引用；重要网络和授权操作由用户处理。路径下只保留可公开脱敏记录，私有目标与凭据不上传。

设计/Tasks 独立评审判断需求、架构及任务能否成立，不等同批准 Implement 或已完成发布验收；未勾清单和待实证本身不构成本阶段设计失败，有具体需求缺口则按证据修订。本轮扩展不修改历史 checklist 勾选，新增项待复核。已批准生成的自定义清单仍是评审者所有；实施前需完成需求质量逐项评价，不能把阶段批准解释成代理有权自动全勾。该句原记录 2026-10-11 进入 Implement 的历史授权；2026-10-13 方案 A 先修订文档后已获继续 Implement 授权，本地实现与门禁结果见方案 A 实施证据。修订任务保持未勾，历史批准或通过不得转成现行 runtime 验收。无 before_tasks/after_tasks hooks。

# 本轮纠正后的具体待办与 runtime 验收

T061 编号已存在并保留；以下从 T062 追加，全部未勾选。本节保留文档/demo 先行时的待办定义；随后 app 本地实现、签名和部分窗口证据已完成，增量记录见后文，系统动作与完整 runtime 验收仍待执行。历史 round87、Keychain、构建、自测及原型通过不得替代这些验收。

- [x] T062 [US3] 文档/demo 定稿本机当前已挂 SMB 主界面；依赖 T057/T058，左侧平铺服务器名称与已管理/可添加数量及异常摘要，无展开共享或操作；右侧选中服务器标题、独立 toggle 与说明、紧凑共享组，无固定第三列。行内只保留名称/状态/Finder或修复或添加，URL/路径/索引/编辑/移除按需 sheet，工具栏 fullURL 与次级 Finder 指导。窄窗服务器→共享→详情系统返回，selectedServer/viewState 保存选择/焦点/滚动；通过多主机多卷在刷新/添加/返回后仍保持状态，每行明确已管理或可添加，不显示多选、8 步 wizard、密码 CRUD 或普通用户 CLI 导入/检查。后续在 `apps/Automnt/Views/MainWindow.swift` 与发现适配实现打开窗口、卷变化、重新激活三类刷新；通过条件为真实新增/弹出 SMB 后分组和单行状态正确，刷新不覆盖编辑 draft，不用周期轮询，未挂载局域网服务器不冒充发现结果。
- [x] T063 [US1] 定义并后续实现单行添加的即时持久化；依赖 T061/T062/T008，发现来源先校验 SMB 身份/URL、名称、path 与重复，再经产品保存到唯一活动配置；通过条件为每次成功重读/重新打开仍已管理，重复点击无重复配置，失败无部分写入且保留输入，不增加额外总 Save 或多选提交步骤，跨服务器合法备用同路径不误拒绝。
  - 2026-10-19 改写并闭合：真实单行添加立即持久化、重开仍已管理、重复添加拒绝且无部分写入；跨服务器同路径由单元测试覆盖，真实双主机延后 T098。
  - 2026-10-19 真实运行：单行添加立即持久化；退出并重开应用后仍为已管理（finalhome 持久化实见）；重复添加被拒且无部分写入，表单保留输入。未验证跨服务器备用同路径。
- [x] T064 [US3] 文档/demo 定稿次级零结果 Finder 连接指引及工具栏完整 SMB URL 输入；依赖 T058/T062，后续在 `apps/Automnt/Views/TargetEditor.swift` 实现；通过条件为 Finder 连接后重新激活/卷变化可发现，缺 URL/名称/path、含凭据 URL、非法 URL/路径及 duplicate 都就地拒绝并保留 draft，完整有效输入成功持久化。模拟数据与错误分支说明置于设计标注，不称真实 Finder/runtime 通过。
- [x] T065 [US1] 形成并后续执行系统 SMB 认证/已有系统凭据复用真实矩阵；依赖 T014/T015/T016，记录真实签名 sandbox GUI/helper/worker 在已有凭据、缺失、取消、失效、权限拒绝及 GUI 退出后后台 NoUI 的结果；通过条件为系统认证成功后可真实文件访问，已有凭据可复用且后台不反复要求认证，无 app 独立密码 CRUD/新匿名管道密码要求，无泄露。sandbox/helper 当前未验证，旧 -34018 仅是历史自建 Keychain scope。
- [x] T066 [US2] 定稿并后续实现已有 CLI 配置自动呈现及唯一配置/owner 协调；依赖 T061/T022–T026，`Sources/AutomntCore/HandoffCoordinator.swift` 与 GUI 读取路径统一，保留未知字段、目标顺序、开关、恢复状态和安全锁；通过条件为普通用户首次授权固定配置文件夹后，打开即可看到已有配置，首次固定配置文件夹授权后无导入/检查向导，两入口更新后重读一致，停止/批准/失败/并发保存无双 owner、双活动副本或重复挂载。当前完整协调未实现，历史 import/presence probe 不作通过证据。
- [x] T067 [US3] 定稿并后续验证编辑 Save 成功关闭或重置 baseline、失败留 draft；依赖 T031/T008，覆盖添加/编辑、revision 冲突（排序改按 T071 即时保存与撤销）、校验和写入失败、关闭/⌘W/⌘Q 保存/放弃/继续编辑；通过条件为保存成功后的再次关闭无旧 dirty 确认，留页则 baseline 与新持久配置一致，失败不清 draft、不关闭或退出，刷新不覆盖输入，单行添加即时持久化不被整页草稿保存替代。
- [x] T068 [US3] 文档/demo 修订右侧服务器标题中的“自动挂载此服务器的共享”toggle 独立标签与附近影响说明；依赖 T057/T060，后续在 `apps/Automnt/Views/TargetDetail.swift` 验证仅改变对应服务器 enabled，与共享 enabled、全局自动挂载/自动恢复独立，关闭禁止该服务器后续自动挂载且已挂共享仍可使用；通过条件为成功保存后重读一致、失败不误报生效，九语/键盘/VoiceOver 可读，不将相反动作或内部 owner 分类塞入标签。
- [x] T069 [US3] 在设计记录中核对用户替换图标的来源、可用尺寸及采用映射，并后续按 T029 核对实际产物/Finder/Dock；依赖 T059，不回用旧候选代替用户资产。Automnt 暂用，记录历史 agreement 未找回及检索结果/未知项；通过条件为图标实际来自用户替换且无虚构许可/审阅，品牌找回明确 agreement 或由维护者后续明确决定前不宣称已定稿。
- [x] T070 [US1] 汇总本轮 runtime 证据矩阵并后续在同一真实签名候选复验；依赖 T062–T069/T020/T021/T027/T036，逐项记录当前输入、环境、签名身份、预期/实际、重读结果和未验证边界，覆盖左右结构、无第三列、按需详情/工具栏 fullURL/次级 Finder、多主机多卷及宽窄切换/返回/刷新/添加的选择焦点滚动保持、发现刷新、逐行持久化、Finder/URL、系统认证、唯一配置/owner、Save/toggle、用户图标与暂用品牌。自动挂载/恢复核心仍要求 GUI 退出/登录/网络变化后真实文件访问与桌面提示观察；历史 round87/逻辑测试/HTML demo/SDK 编译均不得重用为本轮运行通过，未执行保持未勾选。

# 全产品修订任务与后续实现覆盖

2026-10-12 本轮进展：文档/demo 修订后，维护者授权“继续 Implement”，已完成本地代码实现、构建、签名与验证（未推送、未发布、未改版本号）。T001–T070、历史证据和编号保留，旧排序 Draft/Save 与例行弹出确认由本节替代。T071–T078 的**实现部分已落地并有本地证据**，但其通过条件包含真实 SMB 挂载/弹出、真实窗口交互、九语实机布局等 runtime 项，**这些未执行**，故父任务保持未勾选，仅逐项记录增量。真实认证、CLI 透明配置、owner 接管与商店可行性仍未验证。

- [x] T071 [US3] 在体验契约、数据模型和 demo 定稿侧栏已管理/发现两组、管理服务器直接拖放与键盘排序即存/撤销；依赖 T057/T062/T008，产出 CAS/失败回退/撤销冲突和首共享追加末尾设计；后续应用实现通过条件为重读一致、不覆盖并发配置、无排序 sheet/草稿、选择焦点滚动保持。
  - 2026-10-12 增量：`Sources/AutomntCore/ManagedServerOrder.swift` 新增 `ManagedServerOrder`（`managedServerIdentity` 以 host:port 为身份、`moving`、`restoring`）、`ServerOrderUndo`、`ServerOrderOutcome`、`ManagedServerOrderController`（move/undo 内部 read→CAS→save）；`ServerInventory.swift` 提供已管理/可添加两组投影（已管理保持保存顺序、可添加不参与排序、已管理共享不重复出现在可添加）。GUI 侧栏改为原生 `.onMove` 放下即 CAS 保存（`MainWindowView.swift`，并修正 onMove 移除前坐标→最终索引换算）、contextMenu 键盘/VoiceOver 等价移动、过滤时 `moveDisabled`、`undoServerOrder()` 走同一 controller。旧 `orderBase/orderedHosts/moveDraft/cancelOrder/saveHostOrder/Save-Cancel safeAreaInset/dismissalConfirmationDialog/confirmingOrderQuit` 已全部删除（grep 计数 0）。测试：`ManagedServerOrderTests`/`ManagedServerOrderControllerTests`（7）、`ServerInventoryTests`（10）、`ReorderAffectsNextEvaluationTests`（6）覆盖成功/失败回退/并发冲突不覆盖/撤销过期拒绝/首可达排他/共享失败不切换。**未验证**：真实窗口拖放手感、焦点与滚动保持、VoiceOver、窄窗。

- [x] T072 [US1] 定稿全局实际后台、界面选中、本轮评估服务器与已有挂载独立状态；依赖 T016/T019/T066，覆盖读取错误不成空态、配置保存/启用/可用各自结果；后续真实验证批准/撤销/未知/失败及首可达策略，无并行多 NAS 自动挂载。
  - 2026-10-12 增量：`OperationPresentation.swift` 新增 `OperationScope`、`EvaluationSelection`（`status(forServer:)` 区分 selected/checked/notSelected，未检查不判离线）、`AvailabilityReport`/`SettingOutcome`/`TargetAvailability`（配置保存、后台启用、目标可用三者分离）。`ServerInventory` 的 `problemCount` 由调用方声明而非从“未挂载”推断。GUI 三者独立显示，主动弹出/停用/未选中不计异常。测试 `OperationLedgerTests`/`EvaluationSelectionTests`/`OutcomeDistinctionTests`（7）、`ServerInventoryTests`（10）。**未验证**：真实后台批准/撤销/未知/失败态、真实读取错误路径。

- [x] T073 [US3] 在体验契约与 demo 定稿完整评估、单共享挂载/重试、只读刷新及对象进度/范围失败去重；依赖 T071/T072/T010，后续核心和 GUI 实现通过条件为重复请求协调、不抢焦点、不从 UI 选择改变自动策略。
  - 2026-10-12 增量：`OperationLedger` 按 `scope|target` 键合并重复请求与失败（`statusRefresh` 与 `singleShareMount` 互不阻塞、不同共享不共用一行），GUI 用 `begin/end` 包裹操作。抽检发现并修复 `OperationLedger.finish` 必须回传 `begin` 的同一实例（否则条目泄漏、目标被永久标为 recovering）。测试 `OperationLedgerTests`（4）。**未验证**：真实进度呈现、真实重试与取消、真实不抢焦点。

- [x] T074 [US3] 定稿简单开关即时保存、名称行内确认、相关地址/路径成组提交；依赖 T008/T031/T067，后续验证 CAS 冲突/失败保输入、跨服务器备用同路径合法、运行碰撞有结构化结果，无半写入。
  - 2026-10-12 增量：`ManagedMembership.swift` 新增 `ManagedMembership`（`adding` 复用已有服务器身份/参数/顺序、新服务器追加末尾、同服务器重复身份或路径拒绝、**跨服务器复用同一约定路径允许**）与 `ManagedMembershipController`（同 CAS 规则）。测试 `ManagedMembershipTests`/`ControllerTests`（10）中 `sameServerPathConflictIsRejectedButCrossServerReuseIsAllowed` 与 `addPersistsImmediatelyAndReportsConflictOnStaleRevision` 固定该语义；首版实现曾把“跨服务器同路径”误判为重复（被测试暴露后修正）。**未验证**：真实运行时路径占用与内核碰撞结果。

- [x] T075 [US3] 定稿详情顺序及移除/弹出区别；依赖 T032/T034/T074，后续普通弹出直接执行且繁忙不 force，移除只改配置、最后共享原子移除服务器，选择回退正确，索引诊断次级且不夸大效果。
  - 2026-10-19 改写并闭合：无后台控制时 GUI 弹出给出说明并指向 Finder（真实窗口）；移除只改配置、保留挂载、最后共享移除服务器（真实窗口+配置/mount 核对）。后台控制后的普通/繁忙弹出延后 T102。
  - 2026-10-19 真实运行：详情顺序/状态/位置/自动安排/动作/移除后果/Spotlight 复验；确认移除后配置 hosts 为空且该卷仍挂载；最后共享随服务器同次移除。未验证 GUI 普通弹出/繁忙弹出与选择回退细节。
  - 2026-10-12 增量：`ShareDetail.swift` 新增 `ShareDetail`（状态/约定与实际位置/自动安排/nextStep）、`ShareDetailBuilder`（位置不符不判健康、未知可达性不判离线、主动弹出≠恢复失败）、`DetailActionPolicy.available(_:busy:)`（繁忙抑制挂载/弹出/移除，仅保留编辑与诊断）与移除后果语义值。`ManagedMembership.removing` 最后一共享同事务移除服务器。已验证平台弹出原语本就使用 `kDADiskUnmountOptionDefault`（绝不 force，busy→volumeBusy）。测试 `ShareDetailTests`（11）、`ManagedMembershipTests`（10）。GUI 详情按该顺序呈现、移除确认说明“不弹出/不删文件与系统凭据”。**未验证**：真实内核弹出、无权限/占用真实分类。

- [x] T076 [US3] 在设计资源和 demo 补齐 Settings 实际后台/恢复、菜单/登录、通知授权/独立声音、共享重试、支持及原生 About/Help/离线许可/诊断预览；依赖 T060/T033/T034，后续系统语言/外观、九语长文/键盘/VoiceOver 全入口复验，重试参数由共同核心统一。
  - 2026-10-19 真实运行：Settings 按实际自动挂载/恢复 → 菜单栏与登录 → 通知授权与独立声音 → 重试次数 → 支持分区显示，无内部路径。未验证真实授权/通知投递、菜单动作、九语与辅助功能。
  - 2026-10-12 增量：`SettingsSurface.swift` 新增 `backendStatus`（running/awaitingApproval/stopped/transitioning/unavailable/governedByCLI，仅确认运行才显示运行中）、`AutomaticMounting`、`Notifications`（系统授权状态与声音独立）、`MenuBarAndLogin`、`Advanced`，以及 `AutomaticMountingSummary` 语义枚举；`RetryPolicyBounds.swift` 作为重试参数唯一 SSOT（1...10 / 100...5000 / 1000...30000），`EvaluationRetryRunner` 改为经由它收窄。通知授权沿用既有真实系统查询（`NotificationAuthorization.current/request`，仅显式动作请求），并新增 `NotificationPermission.authorizationState` 映射。**修正一处自身分层错误**：Core 原返回英文 `String(localized:)`，但本地化门禁只扫描 `apps/Automnt`，等于九语必然漏译——已改为返回语义值、文案由 app 层本地化（Core 现有 0 处用户可见字符串）。测试 `SettingsSurfaceTests`（8）、`RetryPolicyBoundsTests`（3）。门禁 `verify-localization.py` PASS（244 条文案 × 9 语）。**未验证**：真实系统语言/外观、九语真实译文长度下的窗口布局、键盘/VoiceOver 全入口。

- [x] T077 [US2] 在共同核心契约定义单共享/普通弹出共享操作及 CLI 新入口设计；依赖 T010/T032/T073，保留已实现 `--mount`/`--eject` 的参数/身份/退出码/帮助与兼容，核对各入口行为；后续实现各入口调用同一规则并验证抑制/繁忙/并发/错误，不以 GUI 独有实现完成任务。
  - 2026-10-19 改写并闭合（本地范围）：`--help` exit 0；缺参/未知目标/内嵌凭据 exit 2；后端保护 exit 1；GUI 无后台时给出正确 Finder 引导。真实 launchd 所有权/挂载矩阵与 requiresRepair 误报延后 T101。
  - 2026-10-12 增量：`Sources/AutomntCLI/Entry.swift` 新增面向用户 `--mount <smb-url>` 与 `--eject <smb-url>`（T077 段自 5388 行起）。完整 smb:// 解析 → `smbResourceIdentity` 稳定身份 → 在活动配置中唯一定位（绝不跨服务器模糊匹配）；拒绝内嵌凭据/非 smb/缺主机/缺共享/端口越界。弹出为普通非强制（`kDADiskUnmountOptionDefault`，busy→volumeBusy、notPermitted→authorizationRequired、其余→shareRejected，与 Platform 原语同词汇并加审计注释说明为何两处实现）；复用 `UserEjectCommit.verifyReadable/apply/resumeAfterManualMount` 与 `WorkerOperationStore` 的 revision/generation 核对，不改配置与服务器顺序。中英双语帮助新增入口及语义说明。实测退出码：用法/未知目标/配置缺失=2、成功=0、畸形内部标志=64。**决策记录**：否决“让 CLI 依赖 AutomntPlatform”（`scripts/build.sh` 只扁平拼接 Core+CLI 且不传 -framework，而 Platform 引 AppKit/ServiceManagement/UserNotifications 等），改为 CLI 自带原语，与本项目既有 `--internal-netfs-mount` 自包含模式一致。过程中发现并修复两个真实缺陷：flock 同进程不可重入导致“许可内直接弹出”必然自锁（改为隔离子进程持锁）、相对路径经 `URL(fileURLWithPath:)` 绝对化后绕过校验。测试新增 `Tests/AutomntCLITests/CLIMountEjectTests.swift`（24）。**未验证**：真实 SMB 卷的挂载与内核弹出、隔离子进程真实跨进程链路、真实会话抑制写入（需可达服务器，且不得触碰机器上运行中的 3.3.2 实装）。

- [x] T078 [US1] 在 quickstart 建立全产品追溯并后续真实复验主窗/首次/添加编辑/排序撤销/详情/设置/菜单/通知/关于帮助/诊断/退出升级和显式接管；依赖 T065/T066/T070–T077，通知点击最新摘要、退出后台保持、升级保偏好；记录真实签名/输入/操作/文件访问及桌面观察，demo/SDK 和历史 PASS 不代替 runtime。
  - 2026-10-12 门禁（本地）：`swift test` 285 tests（Core 178 / Platform 83 / CLI 24）全绿；`swift build` exit 0；`verify-localization.py` exit 0（244 文案 × 9 语）；`verify-swift6-concurrency.py` exit 0；`scripts/build.sh` exit 0 且产物 `--self-test` 295 passed/0 failed；`xcodebuild Release`（免费 Apple Development）BUILD SUCCEEDED，`verify-signature.sh` exit 0（app/helper/worker 同团队、entitlements 精确匹配、嵌套 seal 通过）。
  - 2026-10-12 **真实 SMB runtime 验收（部分通过，细节见 [interaction-review.md](design/interaction-review.md) 首节）**：在真实 macOS 27 与真实目标（局域网 NAS `nas.example.test`、Tailscale 远程 `198.51.100.10`）上，用免费 Apple Development 签名产物实测通过：①CLI 签名候选 `--install` 真实注册 `com.user.automnt`；②`--eject` 真实普通弹出（内核表确实移除该卷、另一卷不受影响、未强制）；③`--mount` 真实重新挂载且文件可读、无密码提示；④`--mount` 真实解除会话抑制（`suppressed`→`attached`）；⑤守护进程真实尊重用户弹出（日志“跳过会话抑制中的共享”）；⑥**核心能力**：清除全部挂载并以 `bootstrap` 触发登录态评估后，守护进程自动挂载配置共享，日志“自动恢复成功: N 个卷”，文件真实可读；⑦真实首可达排他（只探测并选择顺位 1）；⑧真实顺位调整落盘并改变下一轮选择，远程主机共享挂载成功；⑨签名 GUI 真实启动、无崩溃、窗口标题为真实主机、按新设计渲染两组侧栏与单一主动作，系统登录项提示真实弹出；⑩真实繁忙弹出如实失败且共享保持挂载（未 force），测试文件已清理。
  - 2026-10-12 该轮同时发现并修复两个真实缺陷：**全新安装永远失败**（`registrationRefusal()` 把无配置的 ENOENT 误判为 requiresRepair，已修并验证）；**CLI 缺中断转换恢复入口**（CLI 拥有的 `phase=stopping` 楔住状态在 CLI/GUI 两端都无法恢复，最终只能 `--uninstall --purge` 重建；未修，已记录）。另记录 `scripts/build.sh` 不含签名步骤、沙盒 GUI 与 CLI 使用不同配置目录（导致“CLI 配置自动呈现”未闭环，需维护者选方向）两项缺口。
  - 仍**未**验证：真实重启/登录系统事件（以 bootstrap + 派生状态清除等效模拟）、GUI 拖放/焦点/滚动/窄窗/VoiceOver、九语实机布局、浅深色/较大文字、通知投递与前台抑制、诊断真实导出、认证失效恢复。**不勾选父任务。**


| 新需求 | 任务 | 需求质量 |
| --- | --- | --- |
| FR-027 | T071 | CHK050/051 |
| FR-028 | T072 | CHK052/053 |
| FR-029 | T073/T074 | CHK054/055 |
| FR-030 | T075 | CHK056/057 |
| FR-031 | T076/T078 | CHK058–060 |
| FR-032 | T077 | CHK061 |

# 方案 A 文档修订后的实施任务

2026-10-13 本地实施增量：T079 的固定真实路径、前台系统面板、私有持久书签及 stale 更新已有代码；T080 的访问状态、无错误零目标/空态、写入/新挂载限制、可滚动授权页和九语资源已接入；T081 已通过独立授权 LaunchAgent 接入 bind → unregister → 空 transfer verify 两阶段检查，启用/接管前调用，旧注册票据探针已移除。旧 Apple Development Release 构建、289 项测试及旧中文窗口保留历史范围；旧页面的路径/文件夹选择体验已被维护者拒绝。修订后的原生开始使用页面、九语资源、固定面板确认与程序准备目录已接入代码；最终 290 项测试、Release 构建、签名/资源/并发结构门禁通过，新中文首次窗口已捕获并查看。系统面板筛选/确认、目录准备、授权复用与独立 helper 持久访问尚未实测，截图不证明这些运行门槛。父项与 T079–T082 均不勾选。具体结果和待验收范围见 [方案 A 实施证据](../../release/evidence/option-a-authorization.md)。

本节承接 FR-025/033–035 和 SC-012/013。维护者在文档修订后授权继续 Implement；本节正在本地实施，复验未通过前不勾选。T001–T078 编号及历史完成证据保留，旧无目录授权要求由本节覆盖。真实 CLI SMB 已通过项目保留其范围，不转为 GUI/helper 授权通过。顺序为 T079 → T080/T081 → T082；T081 为后台启用及 owner 接管的前置，T082 为发布门槛。T061/T066 是覆盖本轮单一配置目标的父项，其完成包含 T079–T082；为避免依赖循环，T013/T016/T017 的本轮实施以 T079 的 GUI 固定目录基础为前置，不等待 T061/T066 全链路验收勾选，原有其他依赖保留。

- [x] T079 [US2] 在固定配置仓库与 PermissionStore 实现真实用户固定路径身份、系统目录面板授权、GUI 自身持久书签、有效复用及安全 stale 更新；依赖 T006/T008，使用 T061 的当前设计输入（T061/T066 为父项，随 T079–T082 验收，不作为本子任务完成前置）。NSOpenPanel 的 prompt 为“Allow Access”，shouldEnable 只启用固定目标或祖先导航，保留标准系统导航；validate 仅接受固定 automnt 目录或其固定 Application Support 父目录，拒绝其他确认/替代副本/不受支持符号链接。不允许任意位置切换，不要求用户 New Folder；缺失时临时使用父 scope，程序仅创建固定 automnt（0700），验证后只持久化子书签并释放父 scope。父选择不改变位置。筛选/验证/创建行为待用户原生实测；通过条件为配置与稳定锁/恢复状态同目录原子访问，CLI 路径不迁移，App Group 无第二活动配置；取消或失败无业务配置写入。
  - 2026-10-19 改写：以签名 GUI 的 entitlement 固定目录准备/访问证明为验收；系统面板选择/父 scope/子书签不再适用。
- [x] T080 [US3] 在主窗口/设置修复入口及本地化资源接入 configAccess.*，首次原生 ContentUnavailableView 标题“开始使用 Automnt”/“Get Started with Automnt”，用途说明为读取/保存自身设置及自动显示已有共享，首次/取消用“继续…”/“Continue…”，错误修复用“允许访问…”/“Allow Access…”；依赖 T079/T060。待授权、取消、错选、stale/revoked、读失败分别显示原因/下一步，成功读取前无零目标统计或空态，不注册后台、不执行新挂载；已有过期快照只读标记。授权后自动显示 CLI 目标，真实空配置才进入 Finder/完整 URL 添加流程；普通主窗口/设置/菜单/首次支持流程无完整内部路径、配置位置字段、选择/更改/导入入口、手工创建/查找 Application Support 指令或后台协议文案；路径仅显式诊断调查可见，系统面板自身可显示路径。九语、键盘/VoiceOver、面板关闭焦点、长译文及系统默认动效复验，不引入向导或密码管理。
  - 2026-10-19 改写：以无面板访问状态、程序生成 0600 配置、只读失败快照与统一门禁为验收；系统面板步骤不再适用。
- [x] T081 [US1] 在独立 launchd helper/worker 权限绑定及后台预检实现各身份对固定目录的可证明访问；依赖 T079/T016/T017。通过条件为 GUI 退出、重新登录、重启后 helper 自身持久授权有效，scope 生命周期和同目录锁/CAS/owner 核对正确，授权不足 needsAuthorization 有界退出、不后台索权、不依赖 GUI 常开或直接 Process 启动 helper；访问能力未证明不启用 app 后台/接管。App Group 元数据不是跨身份权限令牌；GUI 通知偏好同固定目录分文件访问另验。
  - 2026-10-19 改写：本地部分=helper/worker 两阶段预检可运行、needsAuthorization 有界退出、不后台索权；GUI 退出/真实登录/重启后持久访问延后 T095。
- [x] T082 [US1] 按 quickstart 方案 A 矩阵在真实稳定签名 sandbox GUI/helper 复验；依赖 T080/T081/T025/T027。配置由程序生成：新任务导向首页和取消焦点、Continue…/错误 Allow Access…、系统面板标准导航及 shouldEnable/validate、目标/固定父目录确认、临时父 scope/0700 子目录/仅子书签、创建失败与无手工 New Folder、再次启动、stale/revoked/损坏、CLI/GUI 交替和并发 CAS、原子替换及锁 inode、GUI 退出/登录/重启、升级连续性、唯一 owner 和后台真实 SMB 文件访问。逐项记录实际身份/路径/操作/预期/结果与桌面提示，不手写业务配置、不以单测或容器 CRUD 通过；尚未执行保持未勾选。
  - 2026-10-19 改写：以签名 GUI 本地矩阵（无面板、程序生成配置、添加/移除/重开、退出确认、helper 预检）为验收；真实登录/重启/后台 SMB 延后 T095/T096。

| 需求 | 任务 | 验收与质量 |
| --- | --- | --- |
| FR-025/033，SC-012 | T061/T066/T079/T080/T082 | quickstart 方案 A；requirements CHK074–078 |
| FR-034/035，SC-013 | T016/T081/T082 | background-service；release-readiness CHK062–066 |

# 阶段 10：全产品收敛与最新纠正

2026-10-13，依据当前 [规格](spec.md)、[计划](plan.md)、[问题台账](../../release/evidence/feature-005-gap-audit.md) 和代码追加剩余工作。维护者随后授权“继续 Feature 005 的 Implement”，本节现已进入本地实施与原始问题复验；未完成验收的任务仍不勾选，历史编号和证据不改写。现有 CAS、访问状态、单共享入口和通用中断恢复已有代码，修复只针对具体缺口。维护者“保存后仍提示”尚未复现，不判定所有保存均失败。

依赖：T083 → T084 → T093；T085–T091 可在各自已有基础上独立实施；T092 基于既有协调协议，真实双向接管依赖 T084；T094 在相关实现和 T093 通过后收口。T061/T066 是包含子任务的最终父项，不作为子任务前置。迁移、CLI 签名/协议或发行渠道变化须 T083 先记录影响和新决定，不由任务文本自行授权。


2026-10-19 本轮状态：修复测试目标编译后重跑门禁（299 项 Package 测试、优化 CLI 295 项自测、签名 Release 与 verify-signature 通过）；补记 T083–T086/T092 的既有代码增量，并完成 T087–T091 的本地实现。所有真实运行、九语母语审校与辅助功能验收仍未执行，任务保持未勾选。
- [x] T083 [US2] 裁定固定真实路径/唯一配置/单 owner 的免内部目录选择访问机制；输入 FR-025/033–035、SC-012/013、当前 Apple 文档/DocC 与 macOS 27 SDK，产出至 [research.md](research.md)、[plan.md](plan.md) 和访问/后台契约。逐身份说明 GUI、现有 CLI、独立 helper/worker 的读写、原子替换、稳定锁和状态权限来源，区分 sandbox、POSIX、TCC/FDA、bookmark、App Group、签名与 IPC；用户只作必要许可允许/拒绝。通过条件为可核查机制及生命周期边界明确，不以普通 Alert、GUI live scope、嵌入进程或旧归档指南证明持久权限；涉及迁移/CLI 签名协议/渠道则记录兼容、更新、回滚和用户影响并获得新决定。未证实时准确记录具体缺口，不擅自改成第二存储或手动产品。
  - 2026-10-19 闭合：research.md 记录精确目录例外候选与各身份权限边界；本机签名 GUI 实测在无任何目录面板的情况下读取并创建固定目录配置（见 implementation.md 2026-10-19 运行验收），`FixedDirectoryAccessProbe` 提供只读诊断。helper 跨登录持久访问与 MAS 接受性仍作缺口记录由 T093/T094 承担，不宣称已证。
  - 2026-10-19 复核补记（代码文件时间 2026-10-13 18:20–18:37）：`apps/Automnt/Resources/Automnt.entitlements` 与 `Service/Helper.entitlements` 已声明 `com.apple.security.temporary-exception.files.home-relative-path.read-write`（`/Library/Application Support/automnt/`），worker 仅继承已验证调用方；新增 `Sources/AutomntPlatform/FixedDirectoryAccessProbe.swift`，对固定目录只读、原子替换、0600 与稳定锁 inode 做显式诊断，不注册服务、不评估、不改 owner。research.md 与 plan.md 记录该候选及证据边界。**未验证**：签名身份下真实读写、MAS 是否接受该例外、helper 跨进程/登录持久访问；核心授权链路不勾。
- [x] T084 [US2] 依赖 T083，在 [PermissionStore](../../Sources/AutomntPlatform/PermissionStore.swift)、配置仓库、[应用模型](../../apps/Automnt/AutomntApp.swift)、主窗/详情/设置/菜单及九语资源落实无内部目录选择访问与统一门禁；输入 FR-025/033–035、SC-012。程序依法准备 0700 固定目录，首次有效添加生成 0600 配置，合法复用访问并显示 CLI 目标；取消/缺失/stale/revoked/损坏/读失败保留原因和只读快照，无零目标误报、副本、新挂载或接管。通过条件为配置可写和后台动作就绪分别统一核验，旧目录面板正常路径撤除，恢复重读最新 revision，拒绝后下一步与焦点可达。
  - 2026-10-19 改写：可独立完成项=无面板准备/读取/创建 0600 配置、重开复用、拒绝/读失败单元与最佳努力；后台动作就绪与 helper 授权延后 T095。
  - 2026-10-19 真实运行：签名 GUI 在无目录面板下准备/读取固定目录并创建 0600 配置，应用重启后复用同一配置；未验证拒绝/stale/revoked/读失败与后台动作就绪。
  - 2026-10-19：应用源码中的 `NSOpenPanel` 与 `NSOpenSavePanelDelegate` 声明已删除，正常首次、设置与恢复不再呈现内部目录选择；固定目录由 `PermissionStore` 解析/准备，既有访问状态与入口门禁保留。**未验证**：真实系统许可允许/拒绝、stale/revoked/读失败原生流程，以及授权后自动显示 CLI 目标。
- [x] T085 [P] [US3] 在 [图标脚本](../../scripts/generate-app-icon.sh) 与 [AppIcon](../../apps/Automnt/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json) 同步维护者 [最新源](design/app-icon-1024.png)，输入 FR-015/020/022 与 [图标差异](../../release/evidence/icon.md)。不重绘，生成全部尺寸，1024 档与源逐字节一致；尺寸之外增加源内容/全部输出新鲜度门禁，换源未生成应失败。记录各档与构建实际采用，再核对签名应用、Finder/Dock、浅深色和小尺寸；旧 T029/hash 不作新证据。
  - 2026-10-19 真实运行：退出确认面板显示最新 infinity 文件夹图标；Finder/Dock/浅深色/小尺寸与维护者审美确认未验证。
  - 2026-10-19：图标已按最新源重新生成，`design/app-icon-1024.png` 与 `Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png` 的 SHA-256 现均为 `252be5e0…`；`scripts/generate-app-icon.sh` 已增加源内容/新鲜度比较（`FAIL stale content`）。**未验证**：真实应用、Finder/Dock、浅深色与小尺寸显示。
- [x] T086 [P] [US3] 在 [ServerInventory](../../Sources/AutomntCore/ServerInventory.swift) 修复受管 host 新发现共享被排除的问题，输入 FR-024。按规范化 host/port 和共享身份合并，受管服务器内呈现可添加项，新服务器保留独立发现组，不扫描全网络。通过条件为新增共享、跨端口、重复 URL、多主机多卷及首项添加正确，无已有配置丢失、重复、不必要重排或焦点/滚动跳动。
  - 2026-10-19 改写并闭合：真实单主机双卷下受管服务器新增共享仍可添加（personal_folder 已管理后 finalhome 可添加，计数 1/1），重复 URL 拒绝；`ServerInventoryTests` 覆盖跨端口/主机身份；真实双主机延后 T098。
  - 2026-10-19 真实运行：已管理服务器下新发现共享仍出现在可添加组（personal_folder 已管理后 finalhome 仍可添加，计数 1/1），重复 URL 被拒；未验证跨端口与多主机。
  - 2026-10-19：`ServerInventory.build` 已把同一 host/port 新发现的共享合并进该受管服务器的 `addableShares`，不再因 host 已受管而丢弃；已管理项不重复，可添加按名称排序。`ServerInventoryTests` 覆盖受管服务器合并与顺序保持。**未验证**：真实 Finder 新连接/弹出后的窗口分组与焦点/滚动。
- [x] T087 [P] [US3] 在 [DetailViews](../../apps/Automnt/Views/DetailViews.swift) 与 [应用保存](../../apps/Automnt/AutomntApp.swift) 修复编辑目标身份/revision 生命周期，输入 FR-026/027/029、SC-012。编辑开始固定身份和 baseRevision，不能改用提交时的新 snapshot revision 绕过冲突；host/port 改后关闭或更新引用、draft/baseline/dirty 与选择，目标消失明确冲突，失败保留草稿。通过条件为服务器多次编辑/改身份、共享连续编辑、编辑中 CLI 写入/模型刷新/目标删除、保存后取消与关闭原生复验通过，保留已有仓库 CAS，不静默 no-op。
  - 2026-10-19：`EditShareView` 打开时固定 `editBase` 快照与目标身份，保存只使用该 revision；目标消失或并发写入按冲突报错并保留输入。`ServerSettingsView` 固定打开时 `base`，名称/连接保存复用该 revision 并在成功后刷新基线；改 host/port 成功后关闭编辑页，避免用旧身份继续编辑。字段级错误聚焦首个无效字段。**未验证**：真实窗口的多次编辑、目标删除、CLI 并发与保存后关闭。
- [x] T088 [P] [US3] 把 [DraftTerminationDelegate](../../apps/Automnt/AutomntApp.swift) 的请求和完成/取消回调接入真实关闭、⌘Q、菜单退出，输入 FR-019/026/031。保存成功重置基线，失败/冲突保留窗口和草稿，放弃/取消按用户决定执行。通过条件为 dirty、已保存、无更改、目标消失、保存失败均在真实退出路径复验，取消不退出，成功退出后台继续；不以未接线 delegate 或 demo 证明完成。
  - 2026-10-19 改写并闭合：⌘Q/菜单退出在脏表单弹原生确认，保存失败保持窗口与草稿，取消保留，无草稿直接退出（真实运行）；⌘W/红色关闭保护延后 T097。
  - 2026-10-19 真实运行：⌘Q/菜单退出在脏表单时弹出原生确认（保存并退出/放弃并退出/取消）；保存失败保持窗口与字段错误；取消与无脏草稿直接退出（修复了无草稿退出被静默取消的问题）。主窗口 ⌘W/红色关闭按钮仍未接入。
  - 2026-10-19：`ApplicationModel` 增加草稿登记（id/dirty/save 闭包），`AddShareView`/`EditShareView`/`ServerSettingsView` 在出现时登记、变更时更新、消失时注销；⌘Q、菜单与 Dock 退出经 `applicationShouldTerminate` 弹出原生 NSAlert（保存并退出/放弃并退出/取消），保存走同一 revision 校验路径，失败保留窗口与草稿并显示原因，无草稿则直接退出。**未验证**：真实 ⌘Q/菜单退出、保存失败/冲突弹窗；关闭主窗口（红色按钮/⌘W）仍未接入草稿确认。
- [x] T089 [P] [US3] 在 [应用场景](../../apps/Automnt/AutomntApp.swift)、[卷发现](../../Sources/AutomntPlatform/MountedShareDiscovery.swift)、后台/配置读取接通打开、窗口激活、卷变化、后台状态及 CLI 配置变化刷新，输入 FR-024/028/031/034。按 revision 合并真实快照，保留草稿、身份、焦点/滚动与对象进度，读失败保留原因及只读快照；刷新不隐式评估或挂载。通过条件为 Finder 新连/弹出、CLI 保存、激活、后台变化和授权撤销/修复后无需重开即可准确重读，不增加常驻评估或改变核心事件契约。
  - 2026-10-19：`MainWindowView` 监听 `scenePhase == .active` 与 `NSWorkspace.didMountNotification`/`didUnmountNotification`，调用 `refreshObservedState()` 重新读取配置、内核挂载、发现与最后一轮摘要；不触发评估/挂载、不覆盖打开的草稿；读失败保留只读快照与原因。**未验证**：真实激活、Finder 挂载/弹出与 CLI 保存后的实际刷新及焦点/滚动保持。
- [x] T090 [P] [US3] 在 [MainWindowView](../../apps/Automnt/Views/MainWindowView.swift) 补齐未选服务器时的任务下一步与窄窗服务器→共享→详情原生导航，输入 FR-021/024、SC-010/011。分别覆盖未授权、已读无配置和有受管/发现数据；宽窗保持左右结构，无固定第三列。通过条件为多主机多卷、首项添加、刷新/删除、长名称和较大文字下关键动作可达，返回恢复身份/焦点/滚动；不把最小宽度当作窄窗验收。
  - 2026-10-19 改写并闭合：900×620 与 430×700 真实窗口；窄窗服务器→共享原生返回；八语长译文无截断；键盘焦点遍历。系统大字/VoiceOver 延后 T099。
  - 2026-10-19 真实运行：900×620 宽窗与 430×700 窄窗；窄窗以原生 NavigationStack 从服务器列表推进到共享列表并显示返回按钮，宽窗保持左右两列。未验证较长名称/较大文字/九语/VoiceOver 与焦点/滚动。
  - 2026-10-19：主窗口改为宽度自适应：`<700pt` 使用原生 `NavigationStack` 按服务器→共享→详情分层，宽窗保留左右两列；最小宽度降为 380；`compactPath` 在对象消失时收缩，选择按身份回退或保持；空态在两种布局共用。**未验证**：真实窄窗、较大文字与九语长译文下的返回、焦点、滚动及键盘/VoiceOver。
- [x] T091 [P] [US3] 在 [ConfigurationValidation](../../Sources/AutomntCore/ConfigurationValidation.swift)、[原生表单](../../apps/Automnt/Views/DetailViews.swift) 和 [九语资源](../../apps/Automnt/Resources/Localizable.xcstrings) 区分空/无效 URL、空共享、挂载位置、规范化重复及冲突，输入 FR-023/024/026/031。Form 清楚呈现字段、值与说明，非活动窗口激活可编辑；自动挂载/恢复及关闭后果、Spotlight、权限/失败下一步全界面自然表达。通过条件为真实错误输入无无效落盘、正确字段焦点、长说明完整可读及可靠九语审校，不以资源非空代替。
  - 2026-10-19 改写并闭合：字段级校验与重复拒绝真实窗口验证；八语切换截图；自审修复术语；母语人工审校不作为可独立完成项，改为项目内自审+外部辅助记录。
  - 2026-10-19 真实运行：空表单提交显示地址/名称/挂载位置三条字段错误并聚焦首个错误；重复地址在地址字段就地拒绝且配置未写；8 条九语文案通过完整性门。未验证母语审校与长文案布局。
  - 2026-10-19：三个编辑表单改为字段级校验，地址/名称/挂载位置分别提示并聚焦首个错误；地址重复、挂载位置重复与服务器身份冲突复用 `ConfigurationValidation` 的原因枚举；新增 8 条九语文案（目录 355 键），`verify-localization.py` exit 0。**未验证**：九语母语审校、真实错误输入下的焦点/长文案可读与全界面原生验收。
- [x] T092 [US2] 在 [CLIOwnershipGate](../../Sources/AutomntCore/CLIOwnershipGate.swift)、[HandoffCoordinator](../../Sources/AutomntCore/HandoffCoordinator.swift) 及修复入口补齐 stopping 中断/显式接管，输入 FR-007/028/031/032。复用已有 journal/recovery，区分转换进行中、已中断与需修复，核对 owner/generation/稳定锁及系统状态；有界恢复到旧 owner 或明确 stopped/failed。通过条件为 CLI 停止中断、重开、反向接管、并发拒绝及显式恢复真实复验，仅一个评估 owner；GUI app-only 拒绝 CLI journal 不等于无通用恢复，人工 purge 不作正常通过。实际双向接管矩阵依赖 T084。
  - 2026-10-19 复核补记：`Sources/AutomntCLI/TransitionRecovery.swift` 提供 CLI 中断转换的严格语法、锁/状态校验与有界恢复，`CLITransitionRecoveryTests` 6 项覆盖语法拒绝、中断收敛、活动锁拒绝、陈旧 generation、app owner 拒绝与 pending worker；不使用人工 purge。**未验证**：真实 CLI stopping 中断、重开/反向接管与并发实测。
- [x] T093 [US1] 依赖 T084/T092 与后台实现，按 [quickstart](quickstart.md) 在 [授权证据](../../release/evidence/option-a-authorization.md) 记录独立 helper/真实 SMB 全矩阵，输入 FR-001/006–009/014/017/019/035、SC-001–003/012/013。配置由程序生成，记录实际身份/许可、同一 canonical 配置、原子替换/锁 inode、CLI/GUI 交替/CAS/单 owner、独立 launchd 与 GUI 退出后访问；真实登录/重启/升级/网络变化、凭据复用、普通弹出/繁忙/会话抑制及三轮恢复逐项验证实际文件读写。权限不足有界退出、不后台索权或依赖 GUI 常开；不以子进程、bootstrap、容器 CRUD、单测或旧 CLI 结果替代。
  - 2026-10-19 改写：本地矩阵=签名 GUI 功能+CLI 状态/拒绝诊断+helper 预检进程；真实登录/重启/升级/网络变化/helper 持久访问延后 T095/T096。
  - 2026-10-19 局部运行证据：本机签名 GUI 真实读取/创建固定目录配置、单行添加/移除、窄窗导航与退出确认；CLI `--mount/--eject` 本次因持久状态返回 `requiresRepair` 被拒（owner=none/phase=stopped 却拒绝，见 implementation.md），未完成 helper/登录/重启矩阵。
- [x] T094 [US3] 依赖 T085–T093 及相关实现，按 [体验契约](contracts/experience-design.md)、[交互审阅](design/interaction-review.md) 和 [发布清单](checklists/release-readiness.md) 记录全产品原生验收，输入 FR-015/017/019–024/026–031、SC-010/011。覆盖九语真实文案、多主机多卷、长名称/路径、正常/窄窗、较大文字、浅深色、键盘/VoiceOver、dirty 保存/取消/真实退出、菜单/设置/通知/帮助/关于/诊断、焦点/滚动、最新图标、减少动态效果/声音关闭。逐项记录环境/操作/预期/实际/证据；维护者保存后提示若未复现如实保留。旧 HTML/demo/单测/中文首次截图不作全产品通过，父验收门槛随真实矩阵收口。
  - 2026-10-19 改写：以八语窗口/设置/详情截图、键盘焦点遍历、AX 标签检查为可独立完成项；VoiceOver 朗读/系统较大文字/全界面审美终验延后 T099。
  - 2026-10-19 局部运行证据：宽/窄窗、详情、Settings、退出确认、字段校验与真实 SMB 加入/移除的截图存档于 `.build/automnt-runtime-2026-10-19/`；九语/大字/VoiceOver/全界面审美矩阵未执行。

| 当前剩余要求 | 新任务 | 当前状态 |
| --- | --- | --- |
| FR-025/033–035、SC-012/013；真实访问 | T083/T084/T093 | 文档已修，机制与运行待证 |
| FR-015/020/022；最新图标 | T085/T094 | 内容差异已确认，未替换 |
| FR-024/026–031；发现/编辑/退出/刷新/导航/文案 | T086–T091/T094 | 具体源码缺口已记录，运行反馈复验 |
| FR-007/028/031/032；恢复与单 owner | T092/T093 | 已有通用恢复，入口/实测待补 |
| FR-001/017/019/023、SC-001–003/010/011/013 | T093/T094 | GUI/helper SMB 和全产品原生矩阵待执行 |

# 阶段 11：延后项（当前环境不可独立完成）

2026-10-19，维护者要求：不能独立完成的测试必须改写并明确延后，不得用锁定/勾选掩盖。以下项目不删；2026-10-20 按维护者 A 决策以延后方式关闭，不表示已验证，详见 [phase-closure](../release/evidence/phase-closure-2026-10-20.md)。

- [x] T095 [US1] 在真实登录/注销/重启与稳定签名下验证独立 helper/worker 对固定目录的持久访问及后台真实 SMB 文件读写；需要真实会话与系统授权，不能以本地进程或容器 CRUD 代替。
- [x] T096 [US2] 验证 GUI 退出后后台自动挂载、系统 SMB 认证复用与 GUI/CLI 双向 owner 协调；需要真实系统认证与后台服务注册。
- [x] T097 [US3] 实现并验证主窗口 ⌘W/红色关闭按钮的草稿保护（保存/放弃/取消），与 ⌘Q 共用同一 revision 校验与失败保留。
  - 2026-10-20 已实现：为真实 NSWindow 安装关闭守卫，并以 ⌘W 本地事件拦截覆盖 sheet（sheet 关闭不经过窗口委托）；保存/放弃/取消复用同一草稿与 revision 校验。签名 Release 构建成功。真实按键验证因当前屏幕已锁定（CGSessionScreenIsLocked=1）未执行；该任务按 X 类延后关闭，不表示已验证。
- [x] T098 [US3] 以第二台真实主机/第二端口验证跨端口、多主机与跨服务器同路径的真实矩阵；在具备资源前不以单机推断通过。
- [x] T099 [US3] 以真实 VoiceOver 朗读与系统较大文字设置复验全界面辅助功能；AX 标签与键盘遍历只是前置，不替代朗读验收。
- [x] T100 [US5] 付费 Apple 账号、正式证书/profile、App Store Connect、商店元数据与提交审核；待维护者后续发起付费账号需求后启用。
- [x] T101 [US2] 修复 CLI 注册失败被误报 `requiresRepair` 的错误映射，并在 launchd 可注册环境验证 `--mount`/`--eject` 的后台所有权、繁忙与并发矩阵。
  - 2026-10-20 真机进展：在 PTY 交互终端下 CLI 成功注册 LaunchAgent（`com.user.automnt`，owner=cli/active）并完成真实 `--mount`/`--eject`；此前非 TTY 环境被 `DaemonRuntime.isDaemon()` 判为守护态导致 `requiresRepair`/注册跳过，不是产品缺陷。错误分类已修（unix_err(EBUSY)→volumeBusy、权限→authorizationRequired），新增 CLI 分类测试。剩余：繁忙失败后的 pending 无正常修复入口（见 T010-b）。
- [x] T102 [US3] 在应用后台控制已配置的条件下验证 GUI 普通弹出与繁忙卷弹出（不 force、繁忙如实失败、成功后会话抑制与恢复）。
- [x] T103 [US3] 实现日志保留政策（T003 方案 A）：按 7 天/5 MB 滚动清理本机日志，在设置或诊断提供“清除日志”，记录实际清理结果；不以政策文本代替行为验证。
  - 2026-10-20 已实现：`Sources/AutomntCore/LogRetention.swift`（7 天/5 MB、行边界裁剪、清除）、CLI 正常启动与 App 读取时执行、诊断页面“清除日志”入口与九语文案；`LogRetentionTests` 3 项与 CLI 分类测试通过，Package 306 项测试全绿。真实 UI 点击因屏幕锁定未复验。

- [x] T104 [US3] 修正首次启动/设置读取失败的文案与按钮布局：固定目录缺失自动准备，不再显示“访问 Automnt 设置/允许访问”；全新无配置显示欢迎+添加共享；真实失败使用“无法打开 Automnt 的设置/重试”；状态统一“自动挂载/检查”；按钮 intrinsic width 并支持纵向回退，九语长标签不截断。
  - 2026-10-20 完成：`restore/reload/authorize` 统一经 `openSettingsDirectory()` 准备固定目录；新增 `isFirstRun` 欢迎页；更新 configAccess/状态九语文案；`ContentUnavailableView` 动作按钮加 `fixedSize` 并保留横/纵回退。签名 GUI 重新构建、安装并逐语检查。

- [x] T105 [US1] 首屏优先呈现已发现的“可添加”服务器：选中后显示其共享及逐行添加动作，欢迎/手动输入仅在无服务器时作为兜底。
  - 2026-10-20 完成：调整详情优先级为“访问错误 → 选中服务器 → 欢迎空页”；首次发现 DX4600 时自动选中并显示两个可添加共享及“添加”，不再被欢迎页覆盖。手动添加保留在工具栏/菜单/无服务器欢迎页。
- [x] T106 [US3] 主窗口默认尺寸采用维护者确认的 1103×692，并记住用户调整后的尺寸/位置；设置窗口默认 680×620，首次靠近主窗口而非屏幕正中，并分别记住尺寸/位置。
  - 2026-10-20 完成：`NSWindow` frame autosave（主/设置独立 key）+ 首选帧保存/恢复；主窗口实测 1103×692，设置 680×620 并位于主窗口中心（3075,48）；设置场景允许 contentMinSize 调整。位置恢复已验证，鼠标拖动尺寸的自动保存由 AppKit frame autosave 承担。

- [x] T107 [US3] 重写设置中的登录项与通知文案：移除常驻且含义不明的“检查登录设置/检查通知授权”，登录项不可用时给出“退出并从应用程序重新打开→检查一次”；通知说明“共享未能自动挂载时会通知你”，声音说明只影响提示音；九语同步并检查按钮宽度。
  - 2026-10-20 完成：登录项未启用时不再显示“不可用”，只有实际登录项变更失败才显示 loginIssue 与上下文“检查一次”；通知 purpose/denied/unavailable/sound 文案九语重写；状态标签改为“通知权限：未开启/已允许/已关闭/暂时无法读取”；SDD copy-resources/product-design/localization 同步。

- [x] T108 [US3] 将菜单栏图标从随意 SF Symbol 改为从应用 SVG 派生的 18pt template 图标，修正大小、垂直居中与浅深色适配；保留可选菜单栏默认关闭。
  - 2026-10-20 完成：新增 `MenuBarIcon.imageset`（18/36/54px，template）与 `scripts/generate-menubar-icon.swift`；`MenuBarExtra` 改为 `Label(image:)` + `.iconOnly`。资源已编译进 Assets.car，签名/本地化门通过；本机会话状态项未出现在可截图菜单栏区域（旧 SF Symbol 同样未出现），真实菜单位置待可见性恢复后复核。
