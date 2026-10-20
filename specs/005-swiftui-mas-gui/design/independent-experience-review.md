**2026-10-13 方案 A 当前范围**：下文为历史评审，正文、PASS 与原证据保留，只适用于当时版本。保留程序固定真实用户目录、GUI/CLI 唯一活动配置及单后台 owner；首次、设置、CLI 共用与恢复不要求识别、寻找或选择内部目录，此前系统目录面板例外撤回。需要许可时只使用经验证的真实系统机制允许/拒绝；免目录选择访问机制尚未证实，普通 Alert 不产生沙盒权限。当前要求见 [规格](../spec.md#方案-a-的配置授权要求)、[体验契约](../contracts/experience-design.md) 和 [验收矩阵](../quickstart.md#方案-a-固定目录与无目录选择验收矩阵)。本轮仅文档，不改代码、图标或 demo；历史测试/签名/窗口不证明当前权限、独立 helper 生命周期、MAS 或九语原生通过。

全产品修订范围（2026-10-11）：当前采用已管理/发现侧栏分组、管理服务器直接拖放即存并可撤销（含 CAS 与键盘等价操作），不采用排序 sheet/草稿/保存；普通弹出直接执行，不例行确认。界面选中、本轮评估服务器和已有挂载分别表示；完整评估/单共享/刷新、详情/设置/菜单/通知/帮助/关于/退出升级均按当前规格 FR-027–032 与体验契约复验。以下历史正文、PASS 和截图仅属于当时范围，保留原样，不覆盖本轮；应用实施已于 2026-10-12 完成本地实现与门禁验证（见交互审阅记录首节），但真实运行验收未完成；系统认证/透明 CLI 配置/owner 协调仍未验证。

历史范围说明（2026-10-11）：下文保留当时评审、测试和 evidence，不覆盖本轮文档/demo。旧独立密码录入/验证/删除、内部配置目录选择、CLI 导入/检查向导和选择 toggle＋添加所选已被替代；GUI 复用系统 SMB 认证/已保存凭据，sandbox/helper 复用未验证。当前要求主界面打开/挂载变化/重新激活发现本地已挂载 SMB，逐行添加立即持久化；已有 CLI 配置自动呈现、同一配置和后台 owner 协调实际尚未实现。历史 PASS/勾选不覆盖本轮。Automnt 暂时显示，品牌未最终确认，不新增“自动挂载助手”。 当前左右结构以体验契约为准：左侧平铺服务器名与已管理/可添加数量、异常摘要，不展开共享或放动作；右侧选中服务器标题、独立开关及说明、紧凑共享组，无固定第三列。共享行仅名称/状态/Finder或修复或添加，URL/路径/索引/编辑/移除按需 sheet，工具栏 fullURL、Finder 次级空态。窄窗服务器→共享→详情原生返回及刷新/添加保持选择、焦点与滚动，多主机多卷须重新审阅。下文历史截图、HTML 检查和 SDK 编译不覆盖该结构。

# 评审范围与证据边界

本轮为 Feature005 的独立体验设计评审，对象是设计与 SDD 材料，不实施业务、不发布、不修改产品代码。范围覆盖交互、视觉、动效、音效、全界面文案、排版、九语本地化与图标，并对四层开关、同服务器多共享与保存、主机顺序、独立 Settings、持久通知声音、登录 UI 独立 mainApp 与 helper 分工、前台通知重复策略、草稿保护与配置冲突做专项检查。

已核实并读取的材料：`README.zh.md`、`AGENTS.md`、`specs/005-swiftui-mas-gui/` 下 spec/plan/tasks/data-model/research/quickstart、四份 contracts、两份 checklists、design 下 `visual-system.md`、`interaction-review.md`、`localization.md`、`NativeDesignPreview.swift`、`interaction-prototype.html`、全部 PNG 与 `app-icon.svg`；并只读对照了根 `automnt.swift` 的恢复通知、抑制、主机排他、配置键逻辑。

证据边界：本机未执行任何真实窗口、VoiceOver、TCC/Keychain/NetFS/SMAppService、音频或签名运行。HTML 与网页 PNG 只作流程与构图模拟；SwiftUI 预览文件只做类型检查，不代表真实窗口或系统行为。SDK 类型检查通过不等于合规通过。下文凡标注“未验证”的项，一律不计入本轮通过。

# 总体结论

**结论：NOT_PASS（设计与 SDD 层）。**

文档本身已如实声明多数运行验收未执行，也明确“旧历史第 9 轮双 CLI PASS 不覆盖本轮扩展”，这一点与本轮观察一致，可确认历史 PASS 没有被当作本轮结论。但设计材料内部存在若干已核实的不一致与未定义接口，且视觉/图标/文案三项设计交付物在自身标准下不满足可审阅条件。按 SC-010“未解决阻止实施的设计问题为 0”，当前不成立。

已核实阻塞 7 项（B-01–B-07），非阻塞建议 8 项（N-01–N-08），未知/未验证 8 项（U-01–U-08）。分类结论见末节。

# 交互评审

整体方向正确：页面信息优先级、八步添加、状态与修复矩阵、退出与草稿语义均有逐页定义，且与 FR-003/004/019/021 有引用关系。以下为问题项。

## 阻塞：主窗口“后台停用”与“全局开关只在 Settings 编辑”冲突

**证据**：`contracts/experience-design.md` 明写“全局‘自动挂载’只在 Settings 中编辑，主窗口仅显示只读后台状态及设置入口，避免误停全部目标”；同一文件的页面表与状态表又把“后台停用”的下一步动作列为“启用自动挂载”。`design/interaction-prototype.html` 在 stopped 状态把主动作设为 `stopped:'开启自动挂载'`，点击后执行 `automation=true;state='healthy'`，即从主窗口直接改写全局开关。`design/NativeDesignPreview.swift` 的主窗口详情只显示“自动挂载已开启/已关闭”文本与 `SettingsLink`，没有该动作，三者不一致。

**严重度**：阻塞（设计自相矛盾，实现者无法据文档决定主窗口是否有全局启停动作，而契约本身把该动作视作“误停全部目标”的风险来源）。

**建议**：二者择一并同步 spec 状态表、体验契约、原型与原生预览。若保留主窗口启用动作，必须删去“从不编辑全局”的表述并明确权限/失败回退；若维持只读，则状态表下一步改为“打开设置”，原型删除主窗口启用按钮。

## 阻塞：前台去重所需的跨进程前台判定机制未设计

**证据**：`contracts/experience-design.md` 要求“GUI 前台时只更新应用内失败状态，不额外展示应用内横幅或系统横幅，不请求声音”“投递路径须核对前台状态，避免 helper 与窗口各自提醒”；`contracts/core-and-channels.md` 同时规定“不依赖可常驻 XPC server”，helper 是独立签名的短命进程。文档把该判定留给 T016（“无法达成时先修订设计”），但设计层没有任何可行的前台状态判定接口、存储或时序定义。

**严重度**：阻塞（这是 FR-004/022 的硬要求，且与“无常驻 IPC”约束正交；不先定接口，实现阶段只能临场发明，正是文档反复禁止的做法）。

**建议**：在 `contracts/background-service.md` 补一个明确、有界、非常驻的前台状态判定契约（例如 GUI 在前台时写入带时效的轻量标记文件于同一获授权目录，helper 投递前读取并按缺失/过期视为后台），并给出竞态、崩溃残留与 GUI 退出后的收敛规则；或明确改为“由 GUI 单一身份投递、helper 不投递”，并同步通知限额语义。

## 阻塞：独立 Settings 的次级内容在产物中缺失

**证据**：`contracts/experience-design.md` 页面表把“设置”的次级内容定义为“诊断、支持、许可”。`design/interaction-prototype.html` 的设置面板只含自动挂载、自动恢复、菜单栏、登录菜单、通知、通知声音、语言与“关闭设置”，没有诊断/支持/许可入口；`design/NativeDesignPreview.swift` 的 `PreviewSettings` 同样只有开关、通知、语言三段。

**严重度**：阻塞（页面契约与两份设计产物直接矛盾，影响 FR-003/FR-011/FR-012 的入口可达性，以及 T047 关于许可/开源的集成位置）。

**建议**：在设置窗口补诊断/支持/许可入口（或明确这些只放“关于”页并修改页面表），三份产物统一。

## 非阻塞：草稿（Draft）与即时保存两套语义并存但界面未区分

**证据**：`contracts/experience-design.md` 规定全局开关、服务器/共享 `enabled` 为“即时保存，写失败恢复原值”，而添加/编辑/服务器顺序为 Draft，受关闭与 ⌘Q 保护。`interaction-prototype.html` 中共享/服务器开关 `onchange` 直接改写状态并不置 `dirty`，与顺序/编辑路径的 `dirty` 流程并存。

**严重度**：非阻塞（语义本身合理且与 data-model 一致），但用户在同一个详情页里既能遇到“立即生效”的开关，也能遇到“保存/放弃”的草稿，缺少统一的可见提示。

**建议**：在详情页对草稿态给出就地、持续的状态提示（如“未保存的更改”），并确保 `⌘S`/`⌘Q` 只作用于草稿部分。

## 非阻塞：停用状态下的卡片副文案语义重复

**证据**：`interaction-prototype.html` 自动化卡片副文案为 `退出 Automnt 后'+(automation?'继续自动挂载':'不再自动挂载')`。当 `automation=false` 时显示“退出 Automnt 后不再自动挂载”，但此时关不关界面都已停用，句子会误导用户以为退出才是停止原因。

**严重度**：非阻塞（文案准确性问题）。

**建议**：停用状态改写为与退出无关的说明，例如“新自动挂载已停止。已经挂载的共享文件夹仍可使用。”

## 非阻塞：主机顺序说明用“尝试”可能暗示逐台重试

**证据**：`contracts/experience-design.md` 与 `NativeDesignPreview.swift` 均写“按此顺序尝试服务器；使用可用服务器后，不再同时挂载后面的备用服务器。”而根 `automnt.swift` 的 `firstReachableHost` 是“选中第一个可达主机并只处理该主机的启用共享”，并非逐台尝试到成功。

**严重度**：非阻塞（措辞与实现语义有偏差，可能让用户误以为主机 1 的某个共享失败会自动改用主机 2）。

**建议**：改成“按顺序使用第一个可达的服务器；选定后不再挂载备用服务器的共享”，并在辅助说明中说明单共享失败不会触发跨主机切换。

# 视觉评审

**结论：NOT_PASS。**

## 阻塞：没有可审阅的原生浅/深视觉稿

**证据**：`design/visual-system.md` 明确“全部是流程/构图参考，不是原生合规视觉稿”“HTML 和网页 PNG 只作流程/构图参考”；`design/interaction-review.md` 同样声明网页截图不能证明原生外观。也就是说，SC-010 要求的“浅深关键视觉稿”在本轮材料里**不存在原生版本**：现有 7 张场景 PNG 与 `visual-board.png` 都是网页渲染，`NativeDesignPreview.swift` 只通过类型检查、从未真实渲染为窗口。

**严重度**：阻塞（视觉门槛缺判据；按材料自身的证据标准，现有素材无法支撑任何原生视觉结论）。

**建议**：在 T059 增加“编译并真实运行 SwiftUI 预览，输出浅/深与窄/正常窗口的真实截图”作为交付项；在此之前不得宣称视觉审阅已具备条件。

## 非阻塞：网页稿的自绘控件与契约冲突（已披露）

**证据**：`interaction-prototype.html` 的 `.traffic` 手绘红黄绿点、复选框式开关、圆角卡片与自定义提示条；深色设置图 `dark-settings.png` 中开关呈复选框样式。契约已明确这些不是产品规范，且候选 03 已删除固定色值/字号/卡片作为标准。

**严重度**：非阻塞（已显式披露为模拟工具）。

**建议**：维持“网页只作流程/文案审阅”定位，并在评审记录中避免使用“视觉稿”指代这些 PNG。

# 动效评审

**结论：设计层 PASS；运行时验收 NOT_PASS（未执行）。**

**证据**：`design/visual-system.md` 逐场景给出采用/不采用与理由，明确“导航、sheet、菜单、按钮反馈、状态更新、添加步骤、等待”均采用系统默认并不覆盖固定时长，减少动态效果保持文字可理解；`FR-022` 同样把自定义音效与装饰动画列为不采用。原型中 `prefers-reduced-motion` 分支后由 `.main{animation:none}` 覆盖，与实际产品“无装饰动画”一致。

**非阻塞**：原型存在 3.8 秒自动消失的 toast（`setTimeout(...3800)`），而 `visual-system.md` 明确“无 3.8 秒自动消失作为唯一反馈”。该 toast 属于设计标注层，但需确保不被带入产品代码。建议评审记录中显式标注此项边界。

# 音效评审

**结论：设计层 PASS（不采用自定义音效结论完整）；声音闭环持久化验收 NOT_PASS（未执行且依赖未验证门槛）。**

**证据**：`visual-system.md` 的资产评估结论给出不采用理由与“若未来采用”的完整补充任务边界；`FR-022`、`contracts/experience-design.md`、`data-model.md`（NotificationPreferences）、`tasks.md` T016/T033/T036 形成一致闭环：失败仅请求系统默认声音、“通知声音”默认开启且持久化于 `gui-notification-preferences.plist`、关闭只影响声音、损坏/读失败静音但仍发通知、GUI 与 helper 各自需自身持久目录授权。

**已知约束（见未知项 U-05）**：该闭环依赖“helper 自身持久目录授权”这一尚未验证的核心门槛；`data-model.md` 已如实写明“目录持久授权门槛未通过不能宣称声音闭环可用”。本轮不据此判为阻塞，但结论只能是未验证。

# 全界面文案评审

**结论：NOT_PASS。**

## 阻塞：文案清单覆盖不足，无法支撑“全界面审校”

**证据**：`design/localization.md` 的“核心文案候选”表约 24 条，覆盖开关、菜单动作、弹出/离线/登录失败、权限、冲突、删除、通知、设置、退出。缺口包括：八步添加流程的步标题与逐步说明（`interaction-prototype.html` 中 `titles` 八项）、八种状态名称（未配置/待授权/评估中/健康/离线/失败/会话抑制/后台停用）、菜单项“打开 Automnt”“退出 Automnt”“隐藏菜单栏图标”、诊断页与关于页整段文案、设置页“在菜单栏中显示 Automnt”与通知/语言段落。`design/interaction-review.md` 却写“全界面审查覆盖开关后果、菜单、离线/授权/登录失败/已弹出、接管、诊断、通知、添加、冲突、取消/删除/退出”，该表述超出 `localization.md` 实际提供的清单范围。

**严重度**：阻塞（FR-023 要求“全界面按用户场景审校”，SC-011 要求九语覆盖完整；当前不存在可核对的完整中文文案清单，无法作为九语翻译的源，也无法证明覆盖）。

**建议**：先把界面字符串按页面/状态补成完整 zh-Hans 清单（含出现位置、长度约束、变量、复数需求），再据其派生九语；同步修正评审记录中“全界面覆盖”的表述，或在清单补齐前改为“部分核心语境已审”。

## 非阻塞：英文候选与 macOS 用语的对齐风险

**证据**：`localization.md` 中“在 Finder 中打开”英文候选为“Show in Finder”。macOS 对已挂载卷的常规动作是“Open”，而“Show in Finder”通常指显示所在位置。文档自身已注明“英文正式行为措辞须与最终 API 对齐”。

**严重度**：非阻塞（已披露）。

**建议**：定稿时按实际执行的系统动作选择 Open/Show in Finder，并逐语核对同类动作（弹出、连接）。

# 排版评审

**结论：PASS（Markdown 层）。**

**证据**：本轮检查 `specs/005-swiftui-mas-gui` 下全部 `.md`：正文未使用 `---` 水平分割线；每份文件首个标题即真实顶级章节（如 `# 交付状态`、`# 原生设计基线`、`# 文案语境与本地化基线`），无全局占位主标题；脚本检查“标题后是否留有空行”结果为 0 处违反。项目 Markdown 排版规则得到遵守。

未发现需要修改的排版阻塞。

# 九语本地化评审

**结论：NOT_PASS（未完成，材料亦如实声明）。**

**证据**：`design/localization.md` 明确“zh-Hans 为候选 02；en 仅核心语境候选；zh-Hant/ja/ko/de/fr/es/pt-BR 待本地化”“全部九语的 macOS 27 实际界面术语对照、母语审校和长文本/VoiceOver 验证未完成”；仓库内不存在 `.xcstrings`/`.lproj`/`.xcassets` 等资源文件（已全仓查找）。`FR-023`/`SC-011` 要求的复数、长文本、系统语言切换、商店文案均无成品。

**严重度**：阻塞（相对“发布就绪”目标；对本轮设计评审属已知缺口，材料未虚报）。

**建议**：按上节建议先补完整 zh-Hans 字符串清单，再建立每语 glossary 与复数资源；明确“可靠复核”的资源来源，否则按 FR-023 记为语言发布缺口，不得静默回退双语后宣称完整。

# 图标评审

**结论：NOT_PASS。**

## 阻塞：图标资产不符合 macOS 图标规范的可验证条件

**证据**：`design/app-icon.svg` 背景为全出血 `<rect width="1024" height="1024">`，无 `rx` 圆角、无透明边距；`design/app-icon-1024.png` 经 `sips` 检查 `hasAlpha: no`，为不透明正方形。`visual-system.md` 自述“图标 SVG/1024 PNG 已替换为候选 03‘文件夹＋连接环’……仍未获维护者批准，正式图标须在 T029 使用目标系统资产管线验证”。

**严重度**：阻塞（FR-009 要求 100% 遵循 macOS 27 原生规范，SC-006 要求图标缺陷归零；当前资产既非资产管线产物，也无真实应用内呈现证据，且存在圆角/透明度与分层（Liquid Glass）风险，无法在 T029 之前判定通过）。

**建议**：不作为本轮通过项；T029 明确要求使用当前 Xcode/Icon Composer 管线生成含系统圆角与明暗/分层要求的正式资产，并在真实 Dock/Finder 中截图核对。当前 SVG/PNG 保留为方向候选即可。

非阻塞观察：图标“文件夹＋连接环”中的连接环由两段旋转圆角矩形加连接线构成，在中小尺寸下可能被读作回形针/链条而非“挂载”；建议在 T029 于 16/32/128 px 实机比对后再定稿。

# 专项检查

## 四层开关

**结论：NOT_PASS（命名/作用域不一致）。**

**证据**：四层被定义为全局 `automation_enabled`、`auto_mount_recovery`、`HostConfig.enabled`、`SMBShareConfig.enabled`。`data-model.md` 把 `automation_enabled` 列为“自动化意图”根级键；但 `tasks.md` T007 写“新增共享 automation_enabled 的 Codable/缺省/保存管理键（含 managedConfigKeys(.root) 对应逻辑）”，`contracts/background-service.md` 写“明确停用先保存共享 automation_enabled=false”。同一键在文档中时而称“共享”、时而称根级，作用域表述不统一。此外，根 `automnt.swift` 中不存在 `automation_enabled`（已核实 0 处匹配），只有 `auto_mount_recovery`；当前 CLI 的“自动化是否在运行”实际由 LaunchAgent 是否注册决定，而设计未定义这个新键与既有服务注册状态如何调和（例如键为 true 但服务被系统停用/未注册时的显示与修复路径）。

**严重度**：阻塞（四层开关是本轮明确的产品结构，命名/作用域歧义会直接导致 T007 与 T033 实现分叉）。

**建议**：统一术语为“全局 automation_enabled”，修正 T007 与 background-service 的“共享”措辞；在 data-model 明确“配置键 + 实际服务状态”的合成判定与界面呈现（沿用 status/phase 字段），并给出缺键迁移规则。

## 同服务器多共享与保存

**结论：PASS（设计层面），附一处需要补充的机制。**

**证据**：添加流程“先服务器、后共享多选、探测失败可逐项手动输入、每共享确认挂载位置与授权、匹配已有服务器时明确‘添加到此服务器’、不静默新建重复主机”在 `contracts/experience-design.md` 完整定义；`data-model.md` 定义同主机内重复身份/路径冲突拒绝；`interaction-prototype.html` 已实现多选、逐项位置与“添加到已有服务器”提示；评审记录称完整向导双共享保存已模拟通过。

**需补充**：原型第 5 步用单一 `draft.permission` 代表全部共享的目录授权，位置为文本输入，而契约要求逐共享授权。建议在 T058 记录中明确这是模拟简化，并给出“一个共享授权失败但其他共享保存成功”的部分成功语义（当前 SDD 未定义向导的部分失败结果）。

## 主机顺序

**结论：PASS（设计层面）。**

**证据**：`contracts/experience-design.md` 定义服务器详情“上移/下移（边界禁用、键盘可操作）”、以 Draft 保存/取消、revision 冲突处理；“首个服务器追加到当前顺序末尾”。`interaction-prototype.html` 的 `move(-1)/move(1)`、`保存顺序/取消`、`serverDraft` 与 `dirty` 流程与之对应；主机排他语义与根 `automnt.swift` 的 `firstReachableHost` + `for host in config.hosts where host.enabled` 一致。

**非阻塞**：顺序说明的“尝试”措辞见交互节的 N-04。

## 独立 Settings

**结论：NOT_PASS（次级内容缺失，机制定义正确）。**

**证据**：`contracts/gui-and-release.md` 与 `contracts/experience-design.md` 正确规定 Settings 独立场景、SettingsLink 与 ⌘, 打开同一窗口、关闭返回原主窗口选中项、开关即时保存且无 Draft。缺失项见 B-03（诊断/支持/许可入口）。另外 HTML 用 `dialog` 模拟设置窗口，`dark-settings.png` 为网页浮层，两者都不能证明原生 Settings 窗口行为（已披露，不计为重复阻塞）。

## 持久通知声音

**结论：PASS（设计定义完整）；验收 NOT_PASS（依赖未验证门槛）。**

**证据**：`data-model.md` NotificationPreferences 规定文件名、位置、`schemaVersion=1`、默认开启、0600 原子替换、缺失与读失败区分、损坏时静音但仍投递、GUI 与 helper 各自自身授权读写、不共享 UserDefaults、不改写 CLI 偏好；`contracts/experience-design.md` 规定关闭仅取消后续 `sound`、不撤回已送达声音、不影响通知与自动挂载；原型与原生预览均有该开关与辅助说明。设计层无阻塞。运行时依赖 U-05。

## 登录 UI 独立 mainApp 与 helper 分工

**结论：PASS（设计分工清晰）；运行时未验证。**

**证据**：`contracts/gui-and-release.md` 明确“菜单栏启用不自动注册登录 UI”“‘登录时显示菜单栏’默认 false，仅在菜单栏开启时可选”、经 `SMAppService.mainApp` 注册、登录只显示菜单不展开主窗口、与负责有界评估的 helper LaunchAgent 分别管理、登录 UI 不执行评估、不注册第二评估服务、菜单关闭注销 UI 登录项、用户撤销不自动重注册、注册失败/待批准显示真实状态。`data-model.md` UISettings 与 `tasks.md` T033 一致。已只读 SDK 确认 `SMAppService.mainApp` 符号存在。实际注册与“登录不展开窗口”的 SwiftUI 场景行为仍未验证（U-04）。

## 前台通知重复策略

**结论：NOT_PASS（策略正确但机制未定义）。**

见 B-05。策略文本（前台不重复横幅、不请求声音、helper 与窗口不得各自提醒、不因前台抑制而在切后台补发旧提醒）本身正确且可测，缺的是可实现的跨进程判定接口。

## 草稿保护与配置冲突

**结论：PASS（设计层面），附一处产物覆盖不足。**

**证据**：`contracts/experience-design.md` 定义 Draft 与 `baseRevision`、保存冲突保留非敏感输入并提供重读/重新应用、不静默覆盖、密码不进持久草稿、关闭/⌘Q 提供保存/放弃/取消；`data-model.md` 规定 `configurationConflict` 与 CAS；`interaction-prototype.html` 实现冲突弹窗（重新载入/放弃修改＋密码清除）与退出弹窗（取消退出/放弃并退出/保存并退出）。

**需补充**：原型的编辑弹层仅演示名称修改，真实服务器/共享/路径/凭据编辑的草稿与冲突覆盖在产物中不可见；`interaction-review.md` 已承认此简化。建议 T058 记录中为其单列待补项，避免被误读为已覆盖全字段冲突。

# 已核实阻塞

| ID | 问题 | 证据位置 | 建议 |
| --- | --- | --- | --- |
| B-01 | 图标资产全出血无圆角、PNG 无 alpha，非资产管线产物，无真实应用内呈现 | `design/app-icon.svg`、`design/app-icon-1024.png`、`visual-system.md` | T029 用当前资产管线重建并在真实 Dock/Finder 截图核对 |
| B-02 | 无可审阅的原生浅/深视觉稿，现有 PNG 自述为网页参考 | `visual-system.md`、`interaction-review.md`、`NativeDesignPreview.swift` | T059 增加真实运行预览截图交付项 |
| B-03 | 独立 Settings 缺“诊断/支持/许可”次级内容，与页面表矛盾 | `contracts/experience-design.md` 页面表 vs `interaction-prototype.html`、`NativeDesignPreview.swift` | 补入口或改页面表，三份产物统一 |
| B-04 | 主窗口“后台停用”的启用动作与“全局开关只在 Settings 编辑、主窗口只读”冲突 | `contracts/experience-design.md`、`interaction-prototype.html`、`NativeDesignPreview.swift` | 择一并同步全部产物 |
| B-05 | 前台去重所需跨进程前台判定机制未设计，且与“无常驻 XPC”约束并存 | `contracts/experience-design.md`、`contracts/core-and-channels.md` | 补有界的非常驻前台状态契约或改为单一投递身份 |
| B-06 | 全界面文案清单覆盖不足，无法支撑全界面审校与九语派生；“全界面覆盖”表述超出产物 | `design/localization.md`、`design/interaction-review.md` | 补完整 zh-Hans 字符串清单并修正表述 |
| B-07 | 四层开关中全局 `automation_enabled` 命名/作用域在文档间不一致，且与既有服务注册状态的调和未定义 | `data-model.md` vs `tasks.md` T007、`contracts/background-service.md`、根 `automnt.swift`（无该键） | 统一术语并定义配置键与服务状态的合成判定 |

# 非阻塞建议

| ID | 建议 | 证据位置 |
| --- | --- | --- |
| N-01 | 界面区分“即时保存”与“草稿”两类修改 | `contracts/experience-design.md`、`interaction-prototype.html` |
| N-02 | 停用状态卡片副文案去掉“退出后不再自动挂载”的误导 | `interaction-prototype.html` |
| N-03 | 主机顺序说明改为“使用第一个可达服务器”，并说明不跨主机切换 | `contracts/experience-design.md`、`NativeDesignPreview.swift` |
| N-04 | 明确 3.8 秒 toast 仅属评审工具，不得进入产品 | `interaction-prototype.html` vs `visual-system.md` |
| N-05 | 英文“在 Finder 中打开”按实际系统动作定稿 Open/Show in Finder | `design/localization.md` |
| N-06 | 原型多共享步骤的“单一授权标志/文本位置”标注为模拟简化，并定义部分成功语义 | `interaction-prototype.html`、`contracts/experience-design.md` |
| N-07 | 图标“连接环”在 16/32/128 px 实机比对后再定稿 | `design/app-icon-1024.png` |
| N-08 | 统一候选编号（现存“候选 02 仍待审阅/候选 03 尚待审阅”混用）；修正文档中记录“编译通过”应注明 `-parse-as-library`（实测不加该参数会报 `'main' attribute cannot be used in a module that contains top-level code`，加上后类型检查通过） | `design/visual-system.md`、`design/interaction-review.md`、`design/localization.md`、`design/NativeDesignPreview.swift` |

# 未知与未验证

| ID | 未验证内容 | 说明 |
| --- | --- | --- |
| U-01 | 九语可靠复核与成品译文 | 仅 zh-Hans/en 候选；其余七语未开始 |
| U-02 | 真实窗口、浅/深、增加对比度、减少动态、窄/正常窗口、键盘与 VoiceOver | 全部未执行 |
| U-03 | 通知声音开启/关闭、系统静音、专注模式、GUI 退出后投递、听验与限额 | 全部未执行 |
| U-04 | `SMAppService.mainApp` 登录项实际注册、待批准/撤销状态、登录不展开主窗口 | SDK 符号存在不等于行为验证 |
| U-05 | helper 自身持久目录授权与 `gui-notification-preferences.plist` 双方读写 | 声音闭环的前置门槛 |
| U-06 | 沙盒挂载、Keychain、TCC 网络卷授权、NetFS、DiskArbitration 能力 | Plan 已列为早期门槛，未执行 |
| U-07 | 名称可用性、商标与 App Store 重名 | 未核查 |
| U-08 | macOS 27 图标遮罩/分层与 Liquid Glass 逐条要求 | `visual-system.md` 自述官方页面全文未能获取，未据搜索摘要下结论 |

# 未来验收门槛

以下应作为明确的未来门槛，本报告不因“SDD 已写出”而视为完成：九语可靠复核（母语审校＋复数/长文本/VoiceOver）、原生签名构建的真实运行与签名/升级授权连续性、真实窗口视觉与辅助功能走查、通知声音的开启/关闭/系统抑制/GUI 退出后投递听验。以上在本轮范围内均**未验证**，不得在后续汇报中记为通过。

# 分类结论

| 维度 | 结论 |
| --- | --- |
| 交互 | NOT_PASS |
| 视觉 | NOT_PASS |
| 动效 | 设计 PASS；运行时 NOT_PASS（未执行） |
| 音效 | 设计 PASS；闭环验收 NOT_PASS（未执行，依赖 U-05） |
| 全界面文案 | NOT_PASS |
| 排版（Markdown） | PASS |
| 九语本地化 | NOT_PASS（未完成） |
| 图标 | NOT_PASS |
| 四层开关 | NOT_PASS |
| 同服务器多共享与保存 | PASS（设计层；部分成功语义待补） |
| 主机顺序 | PASS（设计层） |
| 独立 Settings | NOT_PASS（次级内容缺失） |
| 持久通知声音 | 设计 PASS；验收 NOT_PASS |
| 登录 UI mainApp 与 helper 分工 | PASS（设计层）；运行时未验证 |
| 前台通知重复策略 | NOT_PASS（机制未定义） |
| 草稿保护与配置冲突 | PASS（设计层；字段覆盖待补） |
| 总体 | **NOT_PASS** |
