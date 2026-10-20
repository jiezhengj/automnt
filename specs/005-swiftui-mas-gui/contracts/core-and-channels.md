**方案 A 当前裁定（2026-10-13，保留固定目录架构，撤回目录选择例外）**：唯一活动配置仍为真实用户 `~/Library/Application Support/automnt/automnt.plist`，GUI/CLI 共用单配置和单后台 owner。程序定位并在合法权限内准备目录；首次、设置、CLI 共用和权限恢复均不要求用户识别内部路径或选择目录。需要授权时，用户只在真实系统许可机制中允许或拒绝；普通 Alert 不产生文件访问权限。当前 user-selected entitlement 与 security-scoped bookmark 不证明任意固定外部目录可免选择授权；通用 Allow/Deny 机制及各身份的访问架构尚未验证，不能冒充已实现。取消、权限失效或读取失败保留原因与只读旧快照，不显示虚假零目标、不创建替代配置、不发起新挂载或后台接管。配置访问、SM 后台许可、SMB 认证分别核对。

历史目录面板代码、289/290 项测试、签名构建和中文首次窗口仅保留当时实施范围，见[历史方案 A 实施证据](../../../release/evidence/option-a-authorization.md)；T079–T082 的原 ID、状态和面板验收条目属于历史追溯，不能充当本轮无目录选择要求。独立 helper 在 GUI 退出、登录、重启、稳定签名升级后的访问及真实 SMB 能力仍待验收。本轮仅修订文档；T083–T094 已追加至主任务清单，全部未完成，不表示实现或验收通过。

# 共同核心边界

AutomntCore 定义配置解析/校验、未知字段保留、编辑 revision、按优先级第一个可达主机排他策略、TCP 探测预算、挂载身份、会话抑制、恢复状态、通知合并与脱敏；不依赖 SwiftUI、TTY、CLI 安装、自更新或商店注册。业务规则只存在于核心，两个入口共用相同数据与动作结果。

适配接口：ConfigRepository（读取、比较后保存）；CredentialProvider（复用系统 SMB 认证/已保存凭据，失败返回 needsAuthorization；不提供应用独立密码存储/录入/验证/删除）；MountBackend（快照、健康、有界挂载、普通卸载、死卷清理）；ServiceController（实际状态、注册、停用、接管）；PermissionStore（固定目录访问能力与真实许可状态，不要求用户选目录）；DiagnosticExporter（脱敏预览、用户导出）；UserNotifier（接收核心合并/限额后的脱敏通知与报告投递状态）；UpdatePolicy（CLI GitHub/GUI App Store）。接口名称为设计契约，不代表已经有可调用 API。

EvaluationRequest 包含 reason、target scope、deadline、owner generation。EvaluationResult 包含快照时间、每目标状态、实际路径、错误类别、是否有用户操作可用、是否预算耗尽。UI 从结构化结果展示，禁止解析 CLI 文本。单目标快捷挂载不得意外越过主机排他策略挂载其他主机；禁用目标须明确启用才进入自动运行，快捷尝试对禁用目标不静默修改 enabled。

# 系统认证与本地共享发现

GUI 不增加独立密码管理，复用系统 SMB 认证/已保存凭据；当前 CLI NetFS 传 nil user/password。sandbox GUI/helper 复用是否成立未验证。普通用户无密码录入、验证或删除入口；认证失败指引到 Finder 系统连接流程，再返回重试，不将系统凭据写入应用配置或诊断。

主界面打开、挂载卷变化及重新激活时发现本机当前已挂载 SMB，先按规范化服务器身份合并管理配置和发现快照，再按共享身份去重；已管理主机上新发现共享照样显示可添加，离线/已弹出管理成员保留。禁止因 knownHosts 已有该主机而跳过发现合并或将 managed host 的 addableShares 清空。宽窗左平铺服务器摘要，右选中服务器开关、说明及紧凑共享组，无第三列；未选择服务器时给出可采取的选择/添加引导，窄窗服务器→共享→详情使用系统返回。URL/路径/索引/编辑/移除按需 sheet，工具栏完整 SMB URL 与次级 Finder 指导保留。刷新只重读配置/后台/挂载状态，不触发评估、不改配置或覆盖 Draft，保持选择/焦点/滚动。已有单行即时添加、手动完整 SMB 入口和开关说明；缺 URL、空共享/路径、重复身份拒绝保存并保留输入。发现合并、正式 volume/activate 观察及无选择/窄导航仍有代码缺口，分别拟由 T086/T089/T090 修复，T091/T094 收敛校验文案与原生复验。

# 挂载后处理与 Spotlight

prevent_spotlight_index 是共同配置意图：false 不发起防索引动作，true 在核对实际挂载身份/路径后由共享生命周期调度有界后处理。CLI 保留当前 mdutil 尝试与 .metadata_never_index 标记行为；GUI/helper 通过受限平台适配器完成同一意图，卷根标记仅在实际目录授权及写权限具备时创建，不覆盖已有文件，不索取管理员权限，不绕过沙盒。商店渠道不得假定外部 mdutil 可用，需实际验证受支持的实现及效果。

用户说明必须包含“尝试减少 Spotlight 索引活动”、可能限制共享搜索，以及“不自动删除现有索引”；不承诺阻止所有索引。后处理结果独立记录为完成、尽力尝试未确证或受限/失败；写入标记或命令退出成功均不能推断系统已停止索引。挂载健康与该结果分别展示，不因防索引受限把可读写卷伪装为挂载失败，也不得静默忽略已选意图。若商店版无法达到已承诺的共同效果，必须报告能力缺口并由维护者审阅实现/渠道或明确用户可见差异，更新 UI/文案及回归后才能通过共同演进与发布门槛；本契约不预先批准功能降级。两入口使用同一状态和错误语义，禁止复制业务规则。

# 体验与本地化绑定

[体验设计契约](experience-design.md) 定义 FR-020–023 的品牌、通知点击/前台呈现、声音及九语资源范围；核心仅产生结构化结果与可本地化通知数量，不拼接界面字符串或复制渠道业务规则。GUI 通知点击打开最新失败摘要，不按旧载荷自动执行操作；T016/T021 验证退出后投递/点击、前台去重、拒绝/抑制和系统声音设置，T030/T036 验证九语复数/脱敏。共同 CLI 基础文案使用 automnt，GUI 暂时保留 Automnt 显示；维护者已质疑此前品牌来源，品牌尚未最终确认，不新增“自动挂载助手”。详细地址仍只在本机必要界面展示。

# 恢复失败通知

核心保留 Feature004 的实际失败通知规则：当轮结束仍有失败才发，每轮最多一条，同卷同会话最多两条，健康弹出和抑制静默；脱敏内容、计数及合并不在渠道复制。CLI 保留 osascript 适配，GUI/helper 采用 UserNotifications 原生渠道，不执行外部 osascript。前台 GUI 请求系统通知授权；短命 helper 在 GUI 退出后使用稳定应用身份投递，身份/后台投递能力须真机验证，失败报告核心能力缺口，不偷偷省略通知或令 GUI 常开兜底。系统拒绝/关闭通知或专注模式下不承诺显示，不反复授权，保留结构化失败供下次打开查看及立即重试；入队不等于用户已看见，通知内容不含私有网络/共享/路径。Feature005 明确覆盖 Feature004 通知中列出卷名的旧字面：CLI 与 GUI 共用“自动挂载失败数量＋打开配置查看或立即重试”的含义及脱敏规则，渠道采用各自真实入口措辞：CLI 为“有 N 个共享未能自动挂载，请打开 automnt 配置并立即重试”，GUI 为“N 个共享文件夹未能自动挂载。打开 Automnt 查看详情或重试。”及 design/localization.md 对应英文/复数资源；GUI 通知仅打开最新摘要，在界面提供重试，不新增通知内直接执行按钮；N 是核心核对后的失败数量，不携带目标标识。目标细节仅在用户打开本机配置/状态界面查看，不纳入通知或诊断导出。原合并/限额/触发/抑制规则保持；T009/T011/T016/T021 更新共同文案与 CLI 自测，T046 同步公开描述并给旧契约加历史范围/覆盖引用，不改写历史实证为已通过。具体 API/身份适配由早期实证确定。

Feature005 FR-019 经维护者新裁定新增 GUI 普通卸载，覆盖 Feature004 关于“永不提供卸载入口”的未来产品限制。Feature004 spec/plan/contract/checklist 记录其当时 CLI 的交付边界与实证，不回写历史验收为新功能已完成；Feature005 的未来实现/公开文档以新裁定为准，CLI 当前事实保留至实施。T046 负责建立明确历史范围提示及新契约交叉引用，不重勾旧清单。

# 渠道隔离

CLI：保留既有命令、免费预编译、终端配置、适用的安装/自愈/更新；新增结构化诊断/显式接管接口时保留旧命令退出语义。商店 GUI：自包含 bundle，内部签名 worker，不安装 Shell 入口，不下载 GitHub executable，不使用外部 CLI 执行核心或迁移。

应用内 worker 独立于 CLI entry，不含自搬迁/自更新/自愈。沙盒父进程生成的子 worker 采用 Apple 文档支持的 sandbox inheritance；独立 launchd helper 则有自身经验证的 sandbox/Keychain/目录权限，不能冒充继承 GUI 权限。嵌入可执行文件签名与用户目录授权都不能授权执行外部 CLI。

# 唯一配置与兼容

已有 CLI 配置应自动呈现，GUI-only 也使用真实用户 `~/Library/Application Support/automnt/automnt.plist`，两入口修改同一配置、协调同一后台 owner。真实 home 以账户身份解析（getpwuid/getuid），不能用沙盒 HOME 替代；程序定位/准备目录，首次、设置、CLI 共用和恢复均无内部目录选择或 CLI 导入检查。固定路径、仓库 CAS、访问状态与 helper 预检已有基础；历史书签/面板实现不证明当前无目录选择访问，T083 先证明各身份读写/锁/原子替换机制，T084 再接入，独立后台矩阵由 T093 验收。App Group 不能成为并行业务配置。目录 0700、同目录数据 0600 原子保存、稳定锁 inode 不替换，旧字段/未知无凭据字段/目标/恢复状态保留。Draft 在编辑开始捕获原目标身份、baseRevision 与 savedBaseline；提交使用原 revision，目标移除/改变或 CAS 冲突保留输入，不在保存时读取新 revision 掩盖冲突。服务器地址修改原子迁移规范化主机身份、共享地址与引用，保留顺序和导航关联。成功更新保存基线与 revision 后关闭，或保留编辑且 dirty=false；取消不重复提示，失败保持 Draft/dirty。仓库 CAS 已有而编辑事务缺口拟由 T087 修复。readFailed 等状态保留旧快照只读，禁止虚假零目标、新配置、新挂载或接管；恢复后重读最新 revision。

旧/未知二进制共存：检测版本与已有 agent；只支持协议兼容版本共同管理。需要升级/释放旧 agent 时给出准确步骤，未完成不注册第二 active 服务；GUI-only 核心不受 CLI 是否安装影响。不把任意 community CLI 的签名列为发行者 App Group 成员。

# 命令控制与结果

后续实现增加的控制入口最少覆盖 status、requestEvaluation、normalUnmount、disableAutomation、handoff、diagnosticPreview/export。CLI 现有 --init、--config、--self-test、--version 继续可用；新机器接口详细参数在实施时依据当前解析器定稿并回填，本阶段不伪造已支持命令。

控制动作只在当前用户身份内执行，校验调用来源和目标身份；凭据不进入 argv/env/plist/日志。SwiftUI 与 app helper 使用受限 IPC 或签名 app 内短命 worker；独立 CLI 的控制利用共同数据锁与显式 GUI 服务操作，不依赖可常驻 XPC server。没有执行任意 shell、任意代码或任意路径强制卸载接口。

统一错误类别：unconfigured、authorizationRequired、backgroundApprovalRequired、offline、credentialFailure、shareRejected、pathConflict、volumeBusy、timeout、configurationConflict、incompatibleOwner、serviceTransitionFailed、signalUnavailable。成功必须包含实际核对结果；needsAuthorization 不伪装 offline。

# 身份、版本与权限连续性

版本唯一声明仍在根 automnt.swift，由构建提取生成 Core 常量、CFBundleShortVersionString、CLI 输出及发行元数据；构建失败于版本不一致。CFBundleVersion 为自动派生构建编号，不成为营销版本第二来源。

CLI、GUI、helper、worker 各自稳定代码标识及兼容 designated requirement；正式产物不得 ad-hoc 替代。免费 Apple Development 用于本机验证，商店身份使用账号渠道签名。不得把本机测试外推 MAS 更新权限。权限/Keychain 首次渠道迁移与常规升级分别记录；身份迁移如无法保留需维护者明确审阅。

# 全产品操作范围与入口覆盖

共同核心负责 `reorderServers`、名称确认、相关地址/路径事务、add/remove 成员、fullEvaluation、singleShareMount/retry、normalEject 和 statusRefresh 的语义及结构化结果；以上是拟定契约名，不代表现有 API。statusRefresh 只读取；完整评估保留首可达服务器排他策略；单共享显式操作核对稳定身份、revision、owner/generation、预算和内核状态，不改变自动策略或其他共享意图。各范围重复请求和失败按 requestID/对象合并。

排序即时 CAS、可撤销；撤销冲突不覆盖最新配置。移除最后共享原子移除服务器，移除不调用 eject。普通弹出无 routine confirmation，繁忙报 volumeBusy 且不 force；成功记录共享的当前会话抑制，手动挂载只在实际身份核对后解除。

CLI 已按本节实现用户单共享/弹出命令：`automnt --mount <smb-url>` 与 `automnt --eject <smb-url>`（目标解析、退出码、双语帮助与回归测试见 `Sources/AutomntCLI/Entry.swift` 的 T077 段与 `Tests/AutomntCLITests/`），并继续兼容既有命令；GUI/helper/worker 使用同一核心操作，不通过执行外部 CLI 实现能力。**两处内核调用实现按构建方式分置**：CLI 走扁平单二进制（`scripts/build.sh` 只拼接 Core+CLI、不传 `-framework`），故自带 DiskArbitration 普通弹出原语而不依赖 `AutomntPlatform`；其分类词汇（busy→volumeBusy、notPermitted→authorizationRequired、其余→shareRejected）必须与 `AutomntPlatform.DiskArbitrationBackend` 保持一致，修改其一须同步核对另一处。部分真实 CLI 挂载与普通内核弹出已有 T078 实证；GUI/helper 相应能力及方案 A 持久授权仍未实测。

# 当前机制依据与新增任务

以[体验契约的当前 Apple 依据及限度](experience-design.md#官方资料与证据限度)为准；user-selected entitlement/书签不证明无 picker 授权，普通 Alert、SM 批准和 SMB 认证不产生固定目录的 sandbox 访问能力。继承 worker、独立 helper、独立 CLI 的签名/成员/IPC/权限分别论证，不擅自迁移配置或更换渠道。T083→T084、T086/T087/T089–T092/T093/T094 仅为已追加且未完成的收敛任务；历史 T079–T082 不构成当前面板验收要求。
