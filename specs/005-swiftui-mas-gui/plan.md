**方案 A 当前裁定（2026-10-13，保留固定目录架构，撤回目录选择例外）**：程序确定内部目录，用户不寻找或选择目录；需要系统许可时只决定允许或拒绝。保留真实用户的固定配置、GUI/CLI 共用和单后台 owner。合法免目录选择访问机制尚未证实，普通应用 Alert 不授予沙盒权限。此前 NSOpenPanel/书签实现与 290 项测试、构建、签名、中文首次窗口只保留历史证明范围。

**Feature**：005-swiftui-mas-gui | **修订**：2026-10-13 | **规格**：[spec.md](spec.md)

**完成说明（2026-10-22）**：Feature 已完成。下方早期布局描述中“Finder/修复作为共享行主动作、URL/路径/索引/编辑/移除进入 sheet”已被 2026-10-21 的从零交互架构取代；最终布局以 [interaction-architecture.md](design/interaction-architecture.md)、[spec.md](spec.md) 的 Status 与真实窗口为准。

**当前范围**：维护者已授权继续 Implement，执行 T083–T094 及可执行的历史未完成任务，允许本地源码、图标、构建、签名与真实运行验证；不递增版本，不执行提交、推送、发布或商店提交。已有真实 CLI SMB 结果仍不证明 GUI/helper 授权、认证或后台恢复通过。

**访问验证候选**：依据 [当前 T083 研究](research.md#t083-精确目录例外候选与当前核查)，GUI 与独立 sandbox helper 各自声明精确 `com.apple.security.temporary-exception.files.home-relative-path.read-write` 数组 `/Library/Application Support/automnt/`；真实 home 仍由账户解析，CLI 的配置、签名和访问协议不变。工作器仅继承已验证调用方的 sandbox，不叠加该例外。声明不是许可弹窗，必须验证实际签名和各身份的文件操作；当前官方仍提供例外申报流程，不代表本用途已获商店审核接受。

# 产品实现方向

CLI、SwiftUI GUI、系统按需启动的 helper 和短命 worker 共用 AutomntCore 的配置、挂载、恢复、冲突及脱敏规则。GUI 按需打开，退出后后台继续；可选菜单栏默认关闭，不运行另一评估循环。macOS 27、arm64、Swift 6.4 与 Xcode 27 为当前开发基线。版本仅从 [根入口](../../automnt.swift) 的 automntVersion 派生。

宽窗左侧平铺已管理与未管理发现服务器，呈现名称、数量及异常摘要；右侧显示选中服务器、独立开关及紧凑已管理/可添加共享组，无固定第三列。行内只保留名称、状态与 Finder/修复/添加主动作；URL、路径、索引、编辑和移除按需进入 sheet。工具栏提供完整 SMB URL 入口，Finder 指引为次级空态。窄窗按服务器→共享→详情原生导航，返回保留身份、焦点和滚动。

发现仅来自本机当前已挂载 SMB，不扫描全网络；已有受管服务器的新共享必须合并进该服务器可添加组，不能因 host 已受管而丢弃。打开、窗口激活、卷变化、后台状态和 CLI 配置变化后重读；刷新不隐式评估或覆盖草稿。逐行添加原子保存成员，自动挂载开关独立。未选中服务器时按实际已读数据给出下一步，不只显示“选择服务器”。

认证使用系统 SMB 认证及已保存凭据，CLI NetFS nil username/password 为现有参照。撤销独立密码录入、验证、删除和匿名管道传密码的产品要求。沙盒 GUI/helper/worker 的实际复用能力待验证；认证失败前台指向 Finder 系统连接，后台不弹认证 UI、不循环重试。手动兜底不能代替 GUI 独立自动挂载及退出后恢复。

# 单一配置与后台协调

唯一活动配置仍为真实账户 `~/Library/Application Support/automnt/automnt.plist`，通过 getpwuid/getuid 解析真实 home。GUI-only 和已有 CLI 用户使用同一位置，不引入导入/检查向导、内部目录选择或另一个活动业务存储。程序负责目录准备，首次有效添加才生成业务配置；不得先假定沙盒可写。目录 0700、业务文件 0600、原子替换、未知字段保留、CAS revision 和稳定锁继续有效。

T083 先核查当前 Apple 文档及 SDK，确定无内部目录选择下 GUI、CLI、独立 helper 的真实访问来源，覆盖读写、原子替换、锁、owner/恢复状态和通知偏好。user-selected entitlement 依赖用户选择；书签复用既有授予；TCC/FDA、POSIX 权限、App Group 成员资格、签名和 IPC 各有边界，不能相互代替。未验证前不承诺存在通用“允许/拒绝”文件授权 API，也不判定方案必然不可行。

App Group 只可作为经验证的 GUI/helper 私有元数据候选，不迁移 CLI 业务配置。若候选需要改变 CLI 签名/访问协议、迁移或发行渠道，必须记录旧版兼容、安装/更新、调用者校验、回滚及用户可见影响，再取得新决定；不擅自实施或双写。容器 sentinel CRUD、GUI live scope 和嵌入子进程成功均不证明独立 launchd helper 的登录/重启持久访问。

访问状态保留未授权、取消、历史错选、目录缺失、stale/revoked、读失败、ready 和已授权无配置的区别；历史 wrongDirectory 不对应新的正常用户步骤。读失败保留只读快照，禁止误报零目标、业务写入、新挂载及 owner 接管。权限恢复后重读最新 revision，只有成功读取确认无目标才呈现真实空态。主窗、详情、服务器编辑、设置、菜单和快捷键统一配置可写与后台操作就绪条件，底层仍核验实际权限。

owner/generation、稳定 config.lock/evaluation.lock、transition journal、helper lease 和 worker 有界执行规则继续有效。登录、网络、恢复、手动挂载与普通弹出受同一 owner 协调；失败收敛到旧 owner 或明确 stopped/failed。通用中断恢复已经存在，补齐 CLI stopping 中断后的正常修复入口及显式接管验收，不能把状态拒绝当作恢复完成。

# 界面与资源

编辑开始即固定目标身份和 baseRevision，保存不得改取提交时的最新 snapshot 来覆盖冲突。服务器改 host/port 后成功关闭编辑，或可靠更新目标身份、draft/baseRevision/dirty 及选择引用。目标消失明确冲突；失败保留草稿，成功后取消/关闭不重复提示。现有仓库 CAS 保留，不重新发明并发层。把草稿保护接入真实关闭、⌘Q 和菜单退出，并核对保存、放弃、取消结果。

完整 URL、空 URL、空共享、挂载位置及规范化身份错误各有精确提示，原生 Form 区分字段、值和说明。非活动窗口激活后可编辑。服务器开关“自动挂载此服务器的共享”附近解释关闭不影响现有卷。Spotlight 说明尝试减少索引活动、可能限制搜索，不删除既有索引。

使用维护者提供的 [最新图标源](design/app-icon-1024.png)，不重绘。当前源与 [Assets 的 1024 像素输出](../../apps/Automnt/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png) 哈希不同，[生成脚本](../../scripts/generate-app-icon.sh) 的尺寸检查不识别内容过期。T085 同步全尺寸、增加内容新鲜度检查，再核对实际应用/Finder/Dock 显示；详见 [图标证据](../../release/evidence/icon.md)。

SwiftUI 使用系统导航、列表、表单、设置、sheet/alert、语义字体和 SF Symbols；HTML 只审阅流程。默认系统动效，无装饰动画或自定义音效；通知声音可关闭并须验证持久化及后台读取。Automnt 暂作现名，历史品牌约定未找回，不宣称最终确认。九语 en、zh-Hans、zh-Hant、ja、ko、de、fr、es、pt-BR 均需可靠审校和原生长文本验收。

# 实施顺序与验收门槛

| 顺序 | 工作及任务 | 通过条件 |
| --- | --- | --- |
| A | T083 当前免目录选择访问机制与影响裁定 | 当前官方/SDK 依据，各身份及访问边界明确；没有证据时准确记录能力缺口及具体方案影响 |
| B | T084 访问与统一入口门禁；T085–T091 图标、发现、编辑、退出、刷新、导航、校验 | 获后续实施授权后按实际依赖执行；每项原始问题复验，数据/焦点/草稿保持 |
| C | T092 中断恢复与显式接管 | CLI/GUI 双向恢复、CAS、锁与单 owner 实测，无人工 purge 兜底冒充正常流程 |
| D | T093 独立 helper、系统凭据及后台恢复 | GUI 退出、真实登录/重启/升级、网络变化后真实 SMB 文件访问；稳定签名与权限生命周期记录 |
| E | T094 全产品原生验收 | 九语、长名称、多服务器多共享、窄窗/较大文字、浅深色、键盘/VoiceOver、通知/帮助/诊断与最新图标 |
| F | 历史发行准备及账号专属动作 | 账号无关产品与材料先完成；随后实际 profile、Connect、US$1.99、提交及审核结果 |

T061/T066 等是最终父验收门槛，不作为其补完子任务的前置，避免循环依赖。图标和独立界面修复不因权限研究被错误串行阻塞；T084 和 T093 依赖访问机制裁定及后续实施授权。

# 历史实现与当前证据边界

2026-10-11 文档/demo 同步、2026-10-12 本地实现和部分真实 CLI SMB 结果保留原范围。T071–T078 的直接排序、CLI `--mount`/`--eject` 等已有实现；旧排序草稿已撤销。T079–T082 的 NSOpenPanel/父 scope/子书签实现属于被纠正的历史交互，原任务和 checkbox 不改写。GUI/helper 两阶段权限预检已有代码，但未证明独立持久权限。

[方案 A 历史证据](../../release/evidence/option-a-authorization.md) 的 290 项测试、Apple Development Release、签名/seal 与中文首次窗口不证明最新要求、真实系统授权、后台 SMB 或九语原生验收通过。T083–T094 保持待实施；[审计台账](../../release/evidence/feature-005-gap-audit.md) 区分源码确认、推导风险、维护者反馈与待原生验收。日志保留数值未确定，不擅自新增政策。

# 当前资料与验证边界

当前依据见 [research.md](research.md) 和 [体验契约](contracts/experience-design.md#官方资料与证据限度)：当前 App Sandbox、user-selected entitlement、helper、App Groups 与书签文档，以及 macOS 27 SDK。2018 归档指南与 Alfred 高级位置选择示例只保留历史背景，不裁定当前 API/MAS 可行性；NSOpenPanel 筛选/验证能力不满足最新免内部目录选择要求。本轮未执行测试、构建、启动或新原生验收。

# 2026-10-19 范围调整与改写

维护者指示：当前先用免费 Apple 账号、假设线下分发而非 App Store；不能独立完成的真实登录/重启/商店测试必须改写并明确延后，不得悬空或伪造勾选。

- 账号/商店：T053–T056 改写为免费签名与线下分发范围；付费账号、App Store Connect、商店提交与真实审核结果延后 T100，待维护者后续单独发起。
- 真实系统/登录/重启：T006/T016/T081/T082/T084/T093 改写为本地可验证矩阵（签名/固定目录读写/GUI 启动退出/helper 预检）；真实登录/重启/helper 持久访问、GUI 退出后后台 SMB 与认证复用延后 T095/T096。
- 已撤回目录面板：T061/T079/T080/T082 改写为签名 entitlement 精确固定目录、无面板首次体验；NSOpenPanel/父 scope/子书签不再作为验收步骤。
- 局部不可测项：T077 真实 launchd 所有权与 requiresRepair 误报、T086/T063 真实双主机、T090/T036/T094 VoiceOver 与系统大字、T075/T102 后台繁忙弹出、T088 ⌘W 关闭保护，分别延后 T101/T098/T099/T102/T097。
- 决策事项与选项见 [maintainer-decisions.md](design/maintainer-decisions.md)；延后项见 tasks.md 阶段 11。
- 本轮已按改写条件闭合 T030/T060/T063/T075/T077/T086/T088/T090/T091；未勾选任务不得因本轮改写被视为通过。


2026-10-20：tasks.md 全部任务已闭合；真实登录/重启、helper、VoiceOver、双主机、商店等以 X 类延后关闭，不表示已验证。逐项依据见 [phase-closure](../release/evidence/phase-closure-2026-10-20.md)。
