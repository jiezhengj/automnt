# 审计范围与当前决定

审计日期：2026-10-13。维护者要求先逐项审计未修复反馈并同步既有规格、设计契约、清单、任务和证据。本轮只修改文档；允许文件读取、搜索、当前官方资料获取、只读哈希及文档一致性检查，不修改应用/CLI 代码、图标或原型资产，不测试、构建、启动、签名、递增版本、提交、推送或发布。

产品判断以 [README.zh.md 的立项背景](../../README.zh.md#立项背景与核心问题) 和 [项目规则](../../AGENTS.md#项目背景与产品判断基线) 为准：在主机可达、配置与凭据有效时，后台自动挂载并恢复配置的 SMB 卷宗，减少依赖任务访问文件前必须人工挂载的情况。状态查看、图形配置与手动重试不能替代此能力；不把问题改写为“不愿使用终端”，也不声称解决 Finder 侧栏入口消失或任意路径访问时即时连接。

最新要求保留方案 A 的固定真实目录、GUI/CLI 共用及单后台 owner，仅撤回内部目录选择面板例外。正常首次、设置、共用和恢复由程序确定位置，用户不识别或选择目录；必要许可只决定允许或拒绝，真实访问来源仍待证明。只隐藏应用内路径而保留面板选择不达标。唯一活动配置仍为 `~/Library/Application Support/automnt/automnt.plist`；迁移、CLI 签名/协议或发行渠道变动先记录影响，不擅自实施或建立平行配置。

# 证据等级与边界

| 等级 | 本文含义 | 限度 |
| --- | --- | --- |
| 源码确认 | 已读取当前实现，可确认结构或分支行为 | 不等于实际原生窗口、系统授权或 SMB 验收通过 |
| 源码推导风险 | 根据调用和状态关系推导可能发生的现象 | 不冒充本轮运行复现 |
| 历史证据 | 既有记录中的测试、构建、签名或运行结果 | 不转为最新免目录选择要求的验收结果 |
| 维护者反馈，未复现 | 保留反馈，本轮未运行应用重做 | 不宣称已修复，不强行认定所有入口都必然发生 |
| 待原生验收 | 需要实际签名身份、系统事件和真实窗口证明 | demo、静态门禁、单测及模拟事件不能替代 |

本轮使用文件读取、内容搜索、文件/图片查看、只读 SHA-256 计算与 Apple 当前官方资料获取；此次文档同步另核对前置、一致性和受保护文件哈希。行号指代码审计读取时的位置，不代表运行复现。所有历史结果保持原证明范围。

# 问题、用户现象与未来验收

| 问题 | 用户可见现象或影响 | 证据等级与定位 | 未来验收条件 |
| --- | --- | --- | --- |
| 正常设置访问仍依赖内部目录面板 | 点击首次“继续…”或权限恢复仍需选择内部配置目录，与最新要求冲突 | **源码确认**：[authorizeConfiguration](../../apps/Automnt/AutomntApp.swift#L183) 第 187–210 行创建 NSOpenPanel、接受目录并授权；[PermissionStore](../../Sources/AutomntPlatform/PermissionStore.swift#L18) 第 18–23、44–82 行固定真实路径、处理书签与父目录准备 | 首次、已有 CLI 配置、取消、失效及恢复全过程无内部目录选择；GUI、CLI、独立 helper 使用同一活动配置与锁；权限来源可证明，失败无平行配置、误报空配置、新挂载或接管 |
| 最新图标源与 Assets 同步未闭环 | 设计源已换，Assets 仍是旧图标；尺寸检查无法发现过期内容 | **本轮 Lead 只读计算哈希及图片核对**，见下节；[图标脚本](../../scripts/generate-app-icon.sh#L39) 仅检查存在性/尺寸 | T085 同步全部尺寸与源内容新鲜度门禁，再核对应用/Finder/Dock 实际显示；本轮不生成资产 |
| 已管理服务器的新发现共享丢失 | 同一服务器已有受管共享，Finder 新连接另一个共享后，“可添加”列表不出现它 | **源码确认**：[ServerInventory](../../Sources/AutomntCore/ServerInventory.swift#L112) 第 112–125 行已管理服务器固定 `addableShares: []`；第 131–147 行发现候选分组后，第 149 行排除 knownHosts，未合并回已管理服务器 | 同一 host/port 下新发现共享出现在该服务器可添加列表；已管理项保留；添加后不重复、不重排服务器、不抢选择/焦点；跨端口和重复身份正确区分 |
| 服务器连接保存后保留旧身份 | 改地址或端口后继续编辑名称/索引/连接，可能显示旧值或点击保存无实际修改 | **源码确认结构，用户现象为推导风险**：[ServerSettingsView](../../apps/Automnt/Views/DetailViews.swift#L486) 第 488–508 行捕获不可更新的 host，按旧身份查询；[saveConnection](../../apps/Automnt/Views/DetailViews.swift#L569) 第 577–593 行修改地址/端口后不关闭；第 559–566、596–602 行后续仍用旧身份。身份由 [managedServerIdentity](../../Sources/AutomntCore/ManagedServerOrder.swift#L5) 第 5–10 行 host/port 构成 | 成功后关闭编辑页，或可靠更新身份、草稿基线及选择引用；再次编辑作用于新身份。目标消失须明确冲突，不能把未找到目标的空操作报告为保存成功 |
| 编辑未固定开始时的 revision | 编辑过程中 CLI 或其他页面改配置，再保存旧输入，可能漏掉编辑冲突 | **源码确认基线位置，覆盖风险待复现**：[共享编辑](../../apps/Automnt/Views/DetailViews.swift#L403) 初始化只保存字段，第 459 行提交时取当前 snapshot；[服务器保存](../../apps/Automnt/Views/DetailViews.swift#L559) 第 560、577、597 行同样保存时取 snapshot。仓库已有 CAS，见下节 | 开始编辑固定 revision 与目标身份；期间并发修改后保存冲突、保输入并说明下一步；重新载入或明确重开后才用新基线。覆盖 CLI/GUI 并发、目标删除及未知字段保留 |
| 权限与操作准备状态在入口间不一致 | 访问失效但仍有旧快照时，菜单或编辑按钮可能仍可点，随后保存拒绝；后台状态与可执行动作也需逐入口核对 | **部分源码确认，整体体验待验收**：[菜单自动挂载](../../apps/Automnt/Views/DetailViews.swift#L917) 第 917–919 行只看 snapshot/意图并按 busy 禁用；服务器保存按钮第 515–516、533–534 行只按 busy 禁用。不能写成无保护：设置第 648 行先查 allowsChanges，底层 save 第 648 行检查 configurationChangesAllowed/authorization | 主窗、引导、详情、服务器编辑、设置、菜单及快捷键统一区分配置可写与后台操作就绪；待授权、读失败、过期快照、忙碌及 owner 转换期间条件/解释一致。底层保留实际权限验证，拒绝时保输入与已保存值 |
| 恢复加载不等于持续状态刷新 | 返回前台、Finder 挂载/弹出或后台更改后，显示可能停留在旧状态，需要手动刷新 | **源码确认缺口，运行现象待验收**：[restore](../../apps/Automnt/AutomntApp.swift#L176) 第 177–178 行已有 authorization 或无书签即返回；[主窗 task](../../apps/Automnt/AutomntApp.swift#L1082) 第 1085 行只调用 restore。应用 Swift 搜索未找到 scenePhase、didBecomeActive、didMountNotification、didUnmountNotification 接入；菜单有独立 task 刷新，但不是完整生命周期监听 | 返回前台、重开 GUI、Finder 挂载/弹出、后台状态及 CLI 配置变更后准确重读；刷新只观察，不触发完整评估，不覆盖草稿、不抢焦点/滚动。失去权限显示原因/下一步，不把旧快照判为可写或健康 |
| 退出草稿保护未接通 | 有未提交输入时，退出或 Command-Q 可能直接退出，输入丢失 | **源码确认**：[DraftTerminationDelegate](../../apps/Automnt/AutomntApp.swift#L29) 第 31–47 行 request 为空时直接允许退出；应用源码仅找到声明、delegate 安装第 970 行与退出命令第 1093 行，未找到 request 赋值或 finish 调用。菜单另见 [退出入口](../../apps/Automnt/Views/DetailViews.swift#L923) | 取消、关闭编辑页、主窗关闭与退出按设计处理真正未提交输入；继续编辑、放弃、完成退出可达；成功后无残留 dirty。退出 GUI 不停止已确认的独立后台自动挂载 |
| 窄窗原生分层导航未完成 | 小窗口及长译文下受最小宽度限制，无法按服务器→共享→详情逐层返回 | **源码确认约束，真实布局待验收**：[主窗口](../../apps/Automnt/Views/MainWindowView.swift#L38) 第 39–45 行两列 NavigationSplitView、minWidth 720；第 51–56 行详情 sheet minWidth 460；未见窄窗按层级切换实现 | 真实 macOS 27 正常/窄窗、较大文字、九语长译文、浅深色下验证原生逐层导航、返回、刷新、添加；主要动作/错误/下一步完整可读，保选择、焦点、滚动，无固定第三列或靠缩小文字强塞 |
| 保存后反复 dirty 提示 | 维护者反馈保存后仍提示未保存；入口和触发条件待定位 | **维护者反馈，本轮未复现**。不能概括为保存都不关闭：[EditShareView](../../apps/Automnt/Views/DetailViews.swift#L474) 第 474–475 行成功 dismiss；[demo](../../specs/005-swiftui-mas-gui/design/interaction-prototype.html#L37) 第 37 行 close 清除 draft，第 41、44 行共享/服务器成功保存 close。原生服务器连接编辑留在页面，与 demo 有差异 | 分别记录服务器、共享、取消后继续、失败重试及保存后退出的真实步骤；成功后基线重置或关闭，失败保输入，只有未提交变化才提示。demo 通过不代替原生编辑验收 |
| CLI owner 中断转换恢复未闭环 | 历史 `owner=cli phase=stopping` 状态可能阻止 CLI 正常操作和 GUI 接管，正常修复路径无法恢复自动挂载 | **历史反馈加源码边界，本轮未重现**：[历史任务记录](../../specs/005-swiftui-mas-gui/tasks.md#L357) 记录未修问题；[HandoffCoordinator](../../Sources/AutomntCore/HandoffCoordinator.swift#L79) 第 81–103 行已有通用恢复，第 107–114 行 GUI 专用恢复拒绝 CLI 身份；[CLIOwnershipGate](../../Sources/AutomntCore/CLIOwnershipGate.swift#L51) 第 51–66 行保留 status/特定 teardown，但转换中阻止正常操作；[GUI 接管](../../apps/Automnt/AutomntApp.swift#L504) 第 528–535 行处理 app 恢复并拒绝 CLI owner/desiredOwner | 程序正常入口制造或遇到中断后，有界核实并停止旧 owner，保配置/偏好/顺序，恢复到可明确接管状态；不能以 purge 重建当正常修复完成。复验 journal 各身份、超时、失败、重启及接管，始终唯一 owner |
| 独立后台与全产品原生体验缺运行证明 | GUI 退出、真实登录/重启/升级后能否继续自动挂载，权限/凭据恢复、九语窗口及辅助功能是否可靠，仍不能承诺完成 | **历史部分成功，最新链路待原生验收**：[历史运行记录](../../specs/005-swiftui-mas-gui/tasks.md#L354) 第 355–358 行区分 CLI SMB 结果与模拟登录事件；[方案 A 记录](option-a-authorization.md#尚需原生运行验收) 第 38–46 行保留未验项，第 62–67 行 290 项测试/签名/中文首次窗口只证明原范围 | 实际签名 sandbox GUI、独立 launchd helper/worker、程序生成真实配置，覆盖退出、真实登录、重启、升级、凭据有效/失效恢复、网络变化、同文件访问与唯一 owner；九语可靠审校、真实布局、键盘/VoiceOver、通知、帮助、诊断及焦点逐项留证 |

# 图标差异的具体证据

本轮 Lead 已只读计算 [最新设计源](../../specs/005-swiftui-mas-gui/design/app-icon-1024.png) 与 [Assets 512@2x 输出](../../apps/Automnt/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png) 的 SHA-256，查看两图并确认内容不同。两者均为 1024×1024；设计源 134216 字节，Assets 输出 149058 字节。[Contents.json](../../apps/Automnt/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json#L12) 引用该输出。本轮未生成/替换图标。

| 对象 | SHA-256 | 来源与限度 |
| --- | --- | --- |
| 最新 1024 像素设计源 | `252be5e058528ab8fe9674f237da172cbecd462cf188e010c66976753f60bad6` | 本轮 Lead 只读计算；白色层叠文件夹与连续水平 infinity |
| 当前 Assets 的 512@2x 输出 | `2cf5bb2b2dc674b027b878369adb21d8c72d9e70afe520e2a1f4cf521005c1bc` | 本轮 Lead 只读计算；旧扁平文件夹与斜向分段链，与 [历史图标证据](icon.md) 旧哈希相同 |

本轮计算的哈希不一致，图像内容也不同，确认输出尚未同步最新设计源。[生成脚本](../../scripts/generate-app-icon.sh#L64) 对 1024 像素档直接复制源字节，正常生成后应相同；其 `--check` 只查存在性/尺寸，没有源内容或新鲜度校验。本轮未运行生成或重新执行该尺寸检查。

# 已实现部分与结论限度

配置仓库已有 CAS，即“文件仍是编辑依据的版本才允许保存”的冲突保护。[ConfigRepository](../../Sources/AutomntCore/ConfigRepository.swift#L19) 第 19–34 行在稳定锁内比较 baseRevision 后原子替换，第 97–105 行使用稳定 config.lock。[应用保存](../../apps/Automnt/AutomntApp.swift#L647) 第 648–653 行检查配置访问状态、忙碌及 authorization，并传入 revision。缺口是编辑基线生命周期与身份更新，不能写成“整个配置层没有 CAS”或“自动挂载保存完全没有权限保护”。CLI 改动后若 UI snapshot 从未更新，仓库仍会拒绝旧 revision；风险是草稿仍旧而模型已刷新，提交却选择新 revision。

自动挂载、恢复开关与说明已有部分实现：[设置](../../apps/Automnt/Views/DetailViews.swift#L645) 第 653–684 行包括全局开关、实际后台状态、恢复入口和恢复说明；[首次引导](../../apps/Automnt/Views/MainWindowView.swift#L285) 第 285–293 行已有用途说明与开启动作；[共享行](../../apps/Automnt/Views/MainWindowView.swift#L500) 第 502–504 行已有逐项添加；[添加表单](../../apps/Automnt/Views/DetailViews.swift#L35) 已有 NavigationStack、Form、TextField。不能记为全部缺失，仍须对照最新要求、入口状态及真实九语原生体验。

通用中断恢复已存在，应追踪 CLI 正常修复入口、GUI 接管边界与实际停止/再接管结果，不能把 GUI 拒绝 CLI journal 写成“完全没有恢复机制”。历史 purge 是当时兜底经过，不是今后正常修复的验收标准。

# 当前 Apple 资料与免目录选择方案边界

本轮取得以下 Apple 当前人类文档页面与对应 DocC JSON。部分人类页面仅返回标题，具体能力及弃用状态核对自当前 JSON，不把标题当全文证据。引用采用正常可阅读的官方页面；资料约束方案论证，不能替代 macOS 27 上实际签名与运行证明。

| 官方资料 | 已核查事实 | 对本项目的影响 |
| --- | --- | --- |
| [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox) | 系统限制受保护资源，需明确访问能力；MAS 应用需要 App Sandbox | 普通应用 Alert 不产生沙盒文件许可，“点击允许”不证明能持续读写真实用户配置 |
| [User-selected read-write entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-write) | 能力针对通过 Open/Save dialog 选择的文件 | 现有面板是方案 A 的权限来源，撤回选择流程后必须重证合法访问来源，不能只改按钮或隐藏路径 |
| [Configuring app groups](https://developer.apple.com/documentation/xcode/configuring-app-groups) | 同团队应用可共享 group containers 与部分 IPC；macOS 支持 sandboxed/nonsandboxed 应用间通信 | 不自动授予任意真实用户目录访问，不证明现有免费 CLI 身份兼容；不能建立第二活动配置并以同步代替单配置 |
| [Embedding a command-line tool in a sandboxed app](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app) | 嵌入工具需正确构建、签名、沙盒配置；适用 App Store 或相应 Developer ID 分发路径 | 嵌入子进程可行不证明独立 launchd helper 在 GUI 退出/登录/重启后仍有访问能力；身份、许可生命周期及后台入口须分别验证 |
| [All files entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.all) | 当前 DocC 元数据 `deprecatedAt` 为 macOS 10.11，引用标记 deprecated | 不能把弃用的全文件 entitlement 当作 macOS 27/MAS 免目录选择的通行证 |
| [Privileged File Operations](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.security.privileged-file-operations) 与 [NSWorkspace.AuthorizationType](https://developer.apple.com/documentation/appkit/nsworkspace/authorizationtype) | entitlement 需向 Apple 申请；系统许可用于授权 FileManager 特定操作；类型为 createSymbolicLink、replaceFile、setAttributes | 不充分证明普通持续配置读取、稳定锁访问或独立后台持久授权，不能声称“一次系统确认即全链路访问”；获批、操作范围及 MAS 适用性需实证 |

2018-04-09 归档 File System Programming Guide 可作历史背景，不能裁定当前 macOS 27/MAS 机制是否可行。当前文档亦不支持直接断言本产品必然可行或必然不可行。

## 需要记录的方案影响

后续方案需明确正常用户流程、真实许可来源、GUI/CLI/helper 各身份及持续访问边界；先论证，再按后续授权实施。下列是影响面，不是已选架构：

- 保留固定真实路径时，说明无内部目录选择下如何访问配置、稳定锁、owner/恢复状态和通知偏好；沙盒 HOME 不得成为第二活动配置。
- 若讨论容器或 App Group 迁移，明确与“保留原活动配置”要求的冲突，记录迁移、回滚、已有 CLI 兼容、未知字段及升级影响；未经维护者新决定不能迁移或双写。
- 若访问依赖签名身份或 IPC，记录免费开源单二进制 CLI 的签名/安装、旧版兼容、并发 CAS、调用者校验及失败恢复影响；不假设所有 CLI 自动获同团队/group 权限。
- 若 MAS 无法承载核心后台自动挂载体验，记录 Developer ID 等渠道的安装/更新、签名、后台批准及收费策略影响；不能退化为手动挂载工具后称目标满足。

# 后续验收与任务追溯

[方案 A 证据](option-a-authorization.md#修订后的本地实现与真实窗口) 的 290 项测试、Apple Development Release、签名/seal、本地化结构门禁及中文首次窗口均属历史证明。本轮未重跑，不等于免目录选择、实际系统认证、唯一配置、独立后台或九语原生验收通过。CLI 真实 SMB 成功保留原范围，不能转为 GUI/helper 授权成功；bootstrap 等模拟登录态评估不替代真实登录/重启。

未来验收至少覆盖程序生成配置、已有 CLI 目标自动出现、首次/恢复无内部目录选择、CLI/GUI 交替与并发 CAS、唯一 canonical 文件与稳定锁、唯一 owner、中断修复/显式接管、GUI 退出/真实登录/重启/升级后的独立 helper 与 SMB 文件读取、凭据/网络变化、编辑身份/草稿/取消/退出、最新图标实际显示，以及多服务器多共享、九语长译文、窄窗、较大文字、浅深色、键盘/VoiceOver、通知、帮助和诊断。逐项记录实际身份、程序入口、操作、预期、结果与证据；未执行保持待验收。

实际新增任务见 [tasks.md 的阶段 10](../../specs/005-swiftui-mas-gui/tasks.md#阶段-10全产品收敛与最新纠正)：T083 访问机制裁定；T084 访问实现与入口门禁；T085 图标；T086 发现合并；T087 编辑身份/revision；T088 真实退出草稿保护；T089 生命周期刷新；T090 空态/窄导航；T091 校验/原生表单/文案；T092 中断恢复/接管；T093 独立 helper/真实 SMB 矩阵；T094 全产品九语原生矩阵。全部未勾选，旧编号、checkbox 和历史证明范围保留。

本文件是问题台账，不是修复完成报告。

# 2026-10-19 复核状态更新

本轮修复了 Package 测试目标的编译错误（`#expect(try …)` 位于非抛出闭包），重跑门禁，并补记 2026-10-13 18:20–18:37 已存在但未写入证据的代码增量。测试现为 299 项通过，优化 CLI 自测 295 项通过，签名 Release 与 `verify-signature` 通过；这些仍不是运行验收。

| 原问题 | 2026-10-19 代码状态 | 仍未验证 |
| --- | --- | --- |
| 正常设置访问依赖内部目录面板 | `NSOpenPanel` 与 delegate 已从应用源码删除；固定目录由程序解析/准备；entitlements 声明精确 home-relative 例外；`FixedDirectoryAccessProbe` 提供目录访问诊断 | 签名身份真实读写、系统许可允许/拒绝、helper 持久访问、MAS 是否接受该例外 |
| 最新图标未同步 | 1024 源与 Assets 输出哈希现已一致；生成脚本增加内容新鲜度门禁 | 真实应用、Finder/Dock、浅深色、小尺寸 |
| 已管理服务器的新发现共享丢失 | 已合并进该服务器可添加组，测试覆盖 | 真实 Finder 新连接后的窗口行为 |
| 保存后保留旧身份 | 编辑固定打开时 revision/身份；改地址成功后关闭页面；目标消失报冲突 | 真实窗口并发与失败路径 |
| 编辑未固定 revision | 三个表单固定打开时快照并只按其保存 | 真实 CLI/GUI 并发冲突 |
| 退出草稿保护未接通 | ⌘Q/菜单/Dock 退出接原生确认（保存/放弃/取消）；⌘W 关闭窗口仍未接入 | 真实退出、失败、窗口关闭路径 |
| 恢复加载不持续刷新 | 激活与卷挂载/弹出事件触发只读重读 | 真实事件下的选择/焦点/滚动 |
| 窄窗原生导航未完成 | 宽度自适应原生分层导航（服务器→共享→详情），最小 380pt | 真实窄窗、大字、九语、VoiceOver |
| 字段校验不具体 | 字段级原因与聚焦；新增 8 条九语文案 | 母语审校与真实错误输入 |
| CLI owner 中断恢复未闭环 | CLI 恢复入口与 6 项测试已存在 | 真实 stopping 中断、接管与并发 |

2026-10-13 的缺口描述保留为历史记录；上表是 2026-10-19 的代码核对结果。所有真实运行项未执行，T083/T084/T087–T092 仍未勾选，T093/T094 未开始。

# 2026-10-19 局部真实运行结果

本机签名 GUI（Apple Development，团队 TEAMID1234）在无任何目录选择面板的情况下准备并读写固定目录，单行添加真实 SMB 共享后立即生成 0600 配置；重复地址就地拒绝且不写配置；详情/移除/窄窗导航/退出确认/Settings 均已实际打开并截图。退出路径同时修复两个真实缺陷：无草稿退出被同步 `terminate` 取消、失败保存错误附加“检查文件夹访问权限”提示；主窗口 ⌘W 仍未接入草稿确认。

CLI 对真实目标执行 `--mount`/`--eject` 时返回 `cli-ownership:requiresRepair`，而 `backend-state.plist` 为 owner=none/phase=stopped，未完成动作；该不一致保留为 T092 的待诊断问题，未在本次修复。

仍未执行：独立 helper 跨登录/重启持久访问、GUI 退出后后台 SMB、真实认证复用、九语母语审校、VoiceOver、大字/浅深色全界面矩阵、繁忙卷弹出、⌘W 关闭保护。T093/T094 保持未勾选。

# 2026-10-19 九语/辅助功能与 CLI 诊断补充

- 九语：八语实机启动与主窗/添加 sheet 截图无英文回退或关键截断；自审统一了“挂载位置”术语与德语后台挂载措辞；`verify-localization.py` 通过。agy 辅助审校启动后无输出被停止，未采信其结论。
- 辅助功能：键盘焦点按工具栏搜索→详情列表→侧栏列表→侧栏搜索循环；AX 可枚举主要按钮与共享行文本。VoiceOver 朗读与系统较大文字延后 T099。
- GUI 弹出：无应用后台控制时如实提示需要后台挂载并指向 Finder，未强制弹出。
- CLI：`--help` exit 0；缺参/未知目标/内嵌凭据 exit 2；已配置目标 `--eject` 因 `requiresRepair` exit 1；`--install` 可复制签名二进制并写入 shell 入口但 launchd 注册失败。错误映射误报列为 T101。
