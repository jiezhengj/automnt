# 活动意图

**存储（方案 A）**：CLI-only、GUI-only 与共同安装均以真实用户 `~/Library/Application Support/automnt/automnt.plist` 为唯一活动业务配置。真实 home 由账户身份（getpwuid/getuid）解析，不使用沙盒 HOME/Application Support 或 App Group 业务副本。程序定位并在合法权限内准备目录；首次、设置、CLI 共用和权限恢复均不要求识别内部路径或选目录，必要授权仅真实系统许可下允许/拒绝。目录 0700、配置 0600、同目录原子替换，稳定锁 inode 不替换。保留 hosts/shares、profiles 兼容桥接、retry_policy、auto_mount_recovery、mount_policy、version 和无凭据未知字段，缺恢复开关仍为启用、缺挂载范围仍为 `first_reachable`。首次有效添加才生成配置；取消、未授权/读取失败不写配置、不新挂载或接管，旧快照过期只读。目录缺失时由程序在已获合法权限内准备；权限不足显示准确原因与重试，不临时要求选择父目录或回退容器。固定真实路径、目录身份/符号链接核对、仓库 CAS 与访问状态保护已有基础；user-selected entitlement/书签仅恢复合法选择授权，不证明任意外部目录的 generic Allow/Deny。T083 先论证各身份读写/锁/原子替换机制，T084 再实现入口，T093 验证独立后台；均为已追加未完成任务。方案 A 架构保留，NSOpenPanel/父 scope/子书签属于历史实施范围，不迁移 CLI 至 App Group、不建第二来源或轮询同步、不静默停旧服务。

| 对象 | 字段与关系 | 校验 |
| --- | --- | --- |
| HostConfig | host、alias、port、timeout_ms、enabled、prevent_spotlight_index、shares | 主机明确输入/探测；端口 1–65535；探测时限有界；保持现有顺序与排他语义 |
| SMBShareConfig | name、smb_url、mount_point、enabled，归属一个 host | SMB URL 必填且包含合法 host 与非空 share，禁止用户名/密码、查询或片段；共享名及有效挂载位置不可空；添加/编辑先验证，缺 URL 不能写入。挂载身份规范化；同一主机内重复身份/挂载路径冲突拒绝；跨主机备用目标允许共用路径，按主机顺序排他，不同时挂载；路径来自产品推导或明确选择 |
| 活动配置快照 | 原配置数据及内容摘要 revision | 保存时 compare-and-swap；并发改动提示重新读取/审阅，不覆盖别人修改 |
| 自动化意图 | automation_enabled，缺省沿用已有启用状态 | 与 auto_mount_recovery 区分；停用禁止新挂载，不卸载现有卷；两入口同一键 |
| 挂载范围 | mount_policy：first_reachable（缺省）/all_reachable | CLI 配置菜单与 GUI 设置写同一字段；all_reachable 仍按保存顺序顺序检查、有界时间窗、单 owner，不并行探测 |

保留未知字段只能保留无凭据的既有扩展；密码进入配置即拒绝。version 是产品版本字段，不当作 schema revision 或并发 token。旧 CLI 的兼容读取/保存及新字段保留须回归验证；未协作版本接管先升级或停用，不允许盲目并发。

# 服务所有权与操作

**存储**：配置旁 backend-state.plist、transition-journal.plist、稳定 config.lock/evaluation.lock。具体新增文件名在实现中固定后写入契约；权限 0600；锁 inode 不原子替换。它们承载运行状态，不是另一业务配置。

BackendState：schemaVersion、owner（cli/app/none）、generation、phase（active/stopping/awaitingApproval/activating/stopped/failed）、desiredOwner、lastVerifiedServiceStatus、transitionID。系统 SM 状态/旧 agent 状态与 generation 不一致时保守停止动作并要求修复。

状态转换：active → stopping → 旧服务确认退出 → activating → active；授权未完成 → awaitingApproval（不宣称运行）；失败 → 恢复旧 owner 或 stopped/failed。转换日志记录先前 owner、阶段、失败类别，不包含凭据。维护锁短时串行，注册即时启动的 helper 在 owner 未提交时只退出/记录待激活，不占锁等待 GUI；提交后显式发起一次评估。

MountOperation：operationID、targetIdentity、ownerGeneration、reason（login/network/mountNamespace/manual/recovery）、deadline、result。所有 baseline/recovery/manual/normalUnmount 动作统一经过 evaluation.lock；操作前后验证 generation。配置保存与 evaluator 的锁顺序固定为配置快照短锁 → 释放 → evaluation 锁，不能持有 UI 编辑锁等待长操作。

# 全局意图与实际服务的呈现

automation_enabled 是根级全局期望，不能独自证明服务在运行。缺键迁移只在产品首次读取时核对旧渠道实际注册/启用及合法配置，得出兼容意图；无法核对时保留未知、提示确认，不凭未知注册新服务。显式 false 永不被迁移或系统状态覆盖。

| 配置意图与系统核对结果 | 界面状态 / 下一步 |
| --- | --- |
| false；服务确认停止 | 自动挂载已关闭；打开设置；已有挂载保留 |
| false；服务仍在停用或停止失败 | 正在关闭 / 未能关闭自动挂载；说明真实服务状态，重试停用，不显示已关闭 |
| true；同一owner/generation且系统enabled | 自动挂载已开启；显示最近核对时间，卷健康另行判定 |
| true；requiresApproval | 等待后台运行许可；打开系统登录项设置查看并允许；返回后重新核对，不自动接管 |
| true；未注册/系统撤销/确认停止 | 自动挂载未运行；检查后台设置或由用户显式恢复。恢复失败保留真实状态，不静默注册 |
| true；转换中 | 正在启用 / 正在切换；有界等待后查看结果，禁用重复转换 |
| 任意；系统查询失败/owner不一致/陈旧状态 | 无法确认自动挂载状态；显示观测时间，重新检查或诊断；不将已挂载卷等同后台已运行 |

主窗口只读摘要与 Settings 的意图开关分开展示。开关成功落盘不冒充服务动作成功；写入失败恢复保存值，服务失败保留已保存意图并显示可修复差异。T007/T016/T033/T036验证全部组合。手动挂载保持独立有界动作，不作为自动化服务健康证据。

# 权限与凭据

PermissionBinding：canonicalDirectoryIdentity、accessMechanism、authorizationStatus、lastVerifiedAccess；bookmarkData/bookmarkStale/scopeStatus 仅用于已验证采用 security scope 的机制，不当作当前所有身份已具备的权限。GUI/helper 各自保存合法访问绑定，不能直接把 GUI 私有书签当跨身份令牌。解析后核对固定目录身份，确需 scope 时开启并在结束释放；stale 仅实际权限仍有效时安全更新，不扩大授权。撤销/解析失败返回 needsAuthorization，后台不弹 UI、不创建配置；前台通过 T083 证明的真实机制恢复，无内部目录选择、普通 Alert 假授权或 TCC/FDA 替代 sandbox。独立 launchd helper 的读写/锁/原子替换和 SMB/凭据在 GUI 退出、登录、重启及稳定签名升级后均待验收。机制字段为契约模型，不代表现有 API/schema 已实现；当前官方依据见[体验契约](contracts/experience-design.md#官方资料与证据限度)。

SystemAuthenticationState：目标身份、系统认证观测类别及时间，不保存密码、用户名或 Keychain reference 为应用业务数据。默认复用 macOS SMB 认证及系统已保存凭据；CLI NetFS nil 用户名/密码是现有行为，沙盒 GUI/helper 实际复用未验证。无独立密码录入、验证或删除模型；认证失败前台给 Finder 系统连接指引。移除管理成员不删除系统凭据，不把共享配置等同跨签名认证权限。

MountedShareCandidate：规范化共享身份、服务器身份、完整 SMB URL、实际挂载位置、发现时间；候选来自本机挂载卷，不是活动配置或远端共享枚举。先按服务器身份合并管理配置与观测，再按共享身份去重；已管理主机上新发现未管理共享仍为候选，离线/弹出管理成员保留。打开、卷变化、重新激活及后台/CLI 状态重读触发只读刷新，不评估、不改意图/配置、不覆盖 Draft。已有本机发现和单行添加；managed host addableShares=[]/knownHosts 排除与正式生命周期观察缺口拟由 T086/T089 修复。每行添加完整校验及 CAS 成功才变管理成员，失败保留候选/输入及错误。禁用共享仅改 enabled，移除删成员但不卸载或删除远端文件。

# 挂载与恢复状态

沿用既有恢复附属状态的健康历史、清理账、网络/登录会话、抑制、通知计数和结果；新旧读取兼容，不因分模块清空。

| 状态 | 判定和下一步 |
| --- | --- |
| unconfigured | 已获有效固定目录授权且成功读取确认无配置/目标，主界面显示可添加共享或 Finder 连接指引 |
| needsAuthorization | 后台/目录/凭据缺失，前台修复，后台不弹窗 |
| evaluating | 有界操作中，禁止同目标重复提交 |
| healthy | 内核身份与真实健康证据一致；记录实际路径与观测时间 |
| offline | 服务不可达，等待下一有效系统事件，不承诺固定恢复时间 |
| failed | 权限/凭据/共享拒绝/路径冲突/超时等明确类别，保留输入 |
| suppressed | 健康主动弹出/卸载；会话变化或快捷挂载解除 |
| stopped | automation_enabled=false 或未获准服务；已挂卷可继续使用 |

实际路径与约定路径不同不得伪装 healthy；展示原因并处理路径冲突。卷健康未知/信号损坏按既有保守规则抑制，不能以超时证明死卷。

快捷卸载在同一维护操作内检查健康与身份、普通卸载、确认内核状态、记录会话抑制。失败不写“已卸载”；进程中断后用账与实际表收敛，未知结果保守抑制而非误重挂。快捷挂载解除单目标抑制并有界执行；并非强制卸载。

# 界面与诊断

UISettings：menuBarEnabled=false、loginMenuEnabled=false；后者是独立主应用登录项偏好，按 gui-and-release.md 使用 SMAppService.mainApp，不能凭偏好声称系统已注册；关闭菜单栏同时注销该登录项并清除 loginMenuEnabled，系统撤销不自动重注册。appearance 使用系统；窗口/导航偏好可私有保存，不影响后台挂载意图。

NavigationViewState（仅界面状态）：selectedServer 为规范化稳定服务器身份，selectedShare 为可选共享身份；viewState 保存服务器列表/选中服务器共享/按需详情层级、sheet 目标、焦点身份及服务器和共享列表滚动位置。宽窗左列表不展开共享，右侧由 selectedServer 派生已管理/可添加组；窄窗服务器→共享→详情与返回复用同一身份。刷新或单行添加只更新发现快照与分组，不重置选择、焦点或滚动；添加成功让焦点跟随同一共享进入已管理组，失败保留原行。仅当选中身份消失才回退相邻项或空状态。此状态不写入活动配置、owner/generation 或挂载意图，保存 draft 基线仍独立。

NotificationPreferences：GUI 渠道专用 `gui-notification-preferences.plist`，位于同一固定授权配置目录，与业务配置分文件；`schemaVersion=1`、`notificationSoundEnabled=true`（缺失文件/字段时默认开启）。它不含目标、凭据或自动化意图，不是第二活动配置。0600、原子替换；GUI 与负责 GUI 身份通知的 helper 各自通过自身持久目录授权访问同一文件，不共享 GUI 私有 UserDefaults，不改变 CLI 通知偏好。GUI 在成功落盘后才确认开关值；写入失败保留上次值并显示可重试错误。后台每次投递前读取；损坏、未知 schema 或读取失败时仍可发送符合限额的失败通知，但 `sound=nil`，记录脱敏偏好错误供下次打开修复，不在后台请求权限。缺失与读失败必须区分。T016 先验证双方读写及 GUI 退出/重新登录，T033 集成设置，T036 实际听验；固定目录自身持久授权与通知投递门槛未通过不能宣称声音闭环可用。

未保存编辑为内存 Draft，在开始编辑时绑定 originalTargetIdentity、baseRevision 与 savedBaseline；提交必须使用该起始 revision，目标已消失/变化或 CAS 冲突保留输入并供审阅/重载，不在提交时读取新 revision 掩盖冲突。服务器地址编辑以一个 CAS 事务迁移规范化服务器身份、共享地址与引用，保留顺序并让导航跟随新身份。仅 Draft 与已保存基线不同时，真实关闭/⌘Q 入口提示保存、放弃、取消。成功更新 Draft、基线及 revision 后关闭，保留编辑则 dirty=false；失败/冲突保持 Draft/dirty 并取消退出。放弃或保存成功后实际完成退出，不为已保存值重复询问。当前仓库 CAS 已实现；编辑起始 revision/主机身份迁移、quit delegate request/finish 接线拟由 T087/T088 修复。维护者反馈的成功后重复提示尚未复现。⌘Q 后后台继续，菜单结束、偏好保留。

DiagnosticSnapshot：版本、渠道、签名校验摘要、系统版本、后台授权、脱敏状态/错误类别、事件与时间；不导出密码、用户名、主机/IP、共享名/文件路径、原始书签/Keychain reference。脱敏替代保持同次导出一致以定位关联，不长期跟踪用户。导出预览 → 明确选择目的地 → 写入；不自动上传。

隐私日志保留/清理数值待维护者在实施前确认；实现不得擅自落地未批准保留政策。系统诊断与用户导出文件的保留归属必须写清。发布材料使用真实脱敏截图或与活动配置隔离的展示模式，不伪造业务配置。

# 全产品对象与修改事务

`ManagedServerOrder` 是唯一活动配置的有序服务器身份数组；未管理发现候选独立保存于观测快照，不参与策略顺序。首个共享加入候选服务器时将其追加末尾；移除最后共享时同一原子事务移除服务器。拖放或键盘移动立即以 baseRevision CAS 提交，不建立排序 Draft。`OrderUndo` 保存本次移动身份、前后顺序及提交 revision；撤销重新核对最新 revision，冲突保留结果与说明、不盲写旧数组。持久化失败恢复保存顺序，保持选中身份/焦点/滚动。

导航选中身份、本轮 `evaluationSelectedServer` 与 `observedMounts` 分别建模；不从界面选择推导评估目标，也不把既有挂载推断成本轮成功。`OperationPresentation` 包含 requestID、scope（fullEvaluation/singleShare/statusRefresh/normalEject）、目标身份、进度、结构化结果和观测时间；按请求/对象合并失败，刷新不创建挂载请求。

简单布尔修改即时保存，名称有行内确认基线，相关地址/挂载位置编辑共用一个 Draft 与 CAS 事务。配置提交结果、后台实际启用结果和目标可用结果分别保存。通知授权来自系统实际查询，声音为独立持久偏好；重试设置引用共享 retry_policy，不建立 GUI 专有重试规则。语言/外观随系统，不新增应用覆盖字段。

# 配置访问结果

`ConfigurationAccessState` 独立于挂载与后台：awaitingAuthorization、cancelled、wrongDirectory、directoryMissing、bookmarkStale、permissionRevoked、readFailed、ready、authorizedUnconfigured。首次、设置、CLI 共用与恢复使用同一检查/恢复入口，无内部路径识别或目录选择；真正需要许可时仅使用已验证系统允许/拒绝机制。directoryMissing 由程序在合法权限内准备固定 0700 目录，权限不足保留真实原因与重试，不要求选择父目录、不当作无配置。wrongDirectory 表示绑定/目录身份核对失败，不是要求用户重选；不保存错误绑定或替代副本。stale 与 revoked 分别诊断，书签不能创造授权。readFailed 保留原因及过期只读快照，禁止业务写入、新挂载和接管，不重建空配置。ready 才计算真实已管理数量；authorizedUnconfigured 须合法访问并确认文件不存在或合法空目标，配置损坏为 readFailed。恢复后重读最新 revision，保留其他入口更改。已有状态保护并非全无；T083→T084 拟收敛新访问机制及一致入口，T093/T094 拟执行真实后台与九语原生验收，尚未完成。
