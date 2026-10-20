**方案 A 当前裁定（2026-10-13，保留固定目录架构，撤回目录选择例外）**：唯一活动配置仍为真实用户 `~/Library/Application Support/automnt/automnt.plist`，GUI/CLI 共用单配置和单后台 owner。程序定位并在合法权限内准备目录；首次、设置、CLI 共用和权限恢复均不要求用户识别内部路径或选择目录。需要授权时，用户只在真实系统许可机制中允许或拒绝；普通 Alert 不产生文件访问权限。当前 user-selected entitlement 与 security-scoped bookmark 不证明任意固定外部目录可免选择授权；通用 Allow/Deny 机制及各身份的访问架构尚未验证，不能冒充已实现。取消、权限失效或读取失败保留原因与只读旧快照，不显示虚假零目标、不创建替代配置、不发起新挂载或后台接管。配置访问、SM 后台许可、SMB 认证分别核对。

历史目录面板代码、289/290 项测试、签名构建和中文首次窗口仅保留当时实施范围，见[历史方案 A 实施证据](../../../release/evidence/option-a-authorization.md)；T079–T082 的原 ID、状态和面板验收条目属于历史追溯，不能充当本轮无目录选择要求。独立 helper 在 GUI 退出、登录、重启、稳定签名升级后的访问及真实 SMB 能力仍待验收。本轮仅修订文档；T083–T094 已追加至主任务清单，全部未完成，不表示实现或验收通过。

# 注册与唤醒

CLI 使用既有用户 LaunchAgent；App 使用两个不可运行期修改的 bundled LaunchAgent 定义，以 SMAppService.agent 注册当前所需版本。BundleProgram 指向 app 内稳定签名 helper。恢复开启：RunAtLoad、系统网络配置固定 WatchPaths、StartOnMount、/Volumes WatchPaths；关闭：仅 RunAtLoad/网络路径。具体 plist 标签固定并分别诊断；任何时刻只允许一个 active 评估服务。

禁止 KeepAlive、StartInterval、StartCalendarInterval、轮询、常驻评估器和运行期 bundle 改写。fixed WatchPaths 不证明系统事件覆盖，用户特定目录无法直接加入 bundle；非标准挂载路径覆盖必须早期实证，否则属于未通过的核心门槛。不能把 StartOnMount 当作卸载事件。

helper：以自身经验证的合法访问能力解析真实用户固定目录并读取同一活动配置 → 核对 owner → 未获准/错误 owner 时有界退出 → 统一 evaluation 锁 → 核对 generation → 同核心评估/恢复 → 发布结构化脱敏状态 → 释放权限/锁并退出。若已验证架构使用 security scope，则逐操作正确开启/释放；不预设 GUI 私有书签可跨身份移交，也不要求用户选内部目录。GUI 退出、登录、重启与稳定签名升级后的独立目录读写、原子替换、稳定锁及 SMB/系统凭据能力均待验收；live bookmark 或容器 CRUD 不算通过。配置拒绝、失效或读取失败不得发起新挂载/接管，不后台弹授权/认证 UI、不创建替代配置。CLI 保留默认 3 次、间隔 1s、调度窗口 10s，现有范围 1–10 次、100–5000ms、1000–30000ms；实际操作时限由隔离 worker 控制，取消/终止后须核对，不启动竞争操作。

GUI启用前只执行本地预检：核验App/helper的Apple锚、固定身份、同团队签名、helper独立sandbox及精确共享组声明，并核对GUI自身对真实固定配置目录的授权、目录身份及读取结果；App Group 私有元数据访问另行核对。禁止从沙盒GUI用Process启动独立sandbox helper作为权限预检；当前真实运行证据表明该路径在main前libsecinit初始化失败。预检通过不等于helper已运行或后台健康，独立进程启动交由SMAppService/launchd；登记状态及本轮真实helper观测共同决定运行结论。

当前SDK真机首次未登记服务可能返回notFound并记录BTM record not found。仅在App/helper严格签名验证通过、随包定义可解析、固定Label/BundleProgram匹配且无Program/ProgramArguments时，将该状态映射为stopped；定义缺失/签名无效/未知系统状态仍unavailable。enabled与requiresApproval保留互斥保护；原始SDK状态另供诊断，不以stopped证明进程收敛或注册成功。

# 系统 SMB 认证边界

GUI/helper 复用系统 SMB 认证及已保存凭据，不增加独立密码管理。当前 CLI NetFS 传 nil user/password，sandbox/helper 的复用能力尚未验证。后台禁止认证 UI；认证失效留结构化失败，下次打开指引用户到 Finder 完成系统连接后重试。普通用户无应用密码录入、验证、删除入口，不以应用 Keychain 密码项或秘密管道兜底。主界面本地已挂载 SMB 发现是前台打开/挂载变化/重新激活时的呈现需求，不新增后台轮询或第二评估 owner。

# 用户同意与停用

首次说明登录/网络事件后执行、关闭窗口或 ⌘Q 之后仍执行；用户明确启用再注册。SM requiresApproval 显示待系统批准并提供系统设置入口，不能当 enabled。用户撤销时不自动重新开启；磁盘偏好为 true 也不能覆盖系统撤销。

明确停用先保存根级 automation_enabled=false（全局控制，与单个共享 enabled 不同），防止任何入口发起新动作，再注销当前服务；停止 UI 显示前核对实际状态。已有健康卷保留，不当作卸载。停用/切换时有在途操作，先等有界完成或安全取消并核对，不能声称所有请求均可瞬时撤销。

恢复开关改变使用同样停旧/启新流程，回退失败保留一致配置/状态并显示修复动作。用户批准、新注册、重新注册的实际体验须记录，不能保证零系统提示；正常版本升级不能仅因替换 binary 反复索取已有权限。

# 通知前台判定与去重

设计采用事件时即时查询，不用心跳文件、常驻 XPC 或新增轮询。GUI 渠道的短命 helper 在准备投递时通过 AppKit `NSWorkspace.shared.frontmostApplication` 查询当前前台应用，以签名应用的稳定 bundle identifier 判断是否为 Automnt；这属于后台系统适配，不改变界面 100% SwiftUI 的要求。窗口在后台、应用隐藏或仅菜单栏存在不视为前台；菜单交互期间若系统将 Automnt 报告为前台，则同样静默。CLI 渠道不采用此 GUI 判断。

当轮核对结果和核心通知限额先记录，再进行展示决策；GUI 本身不重复投递同一结果。投递前最后一次查询为 Automnt 时，只保留失败状态，不请求通知与声音；查到其他应用时可按限额投递。查询返回 nil、身份无法核对或系统能力受限时，本轮保守静默并记录脱敏诊断，不将未知当后台。切回后台不补发已消费事件。nil可能来自没有可识别前台应用，也可能来自系统能力限制，当前不能可靠区分，均不视为已确认后台；最新失败留在状态和脱敏诊断，下次打开显示检查/重试入口。首次用途说明不承诺失败通知必达；查询持续不可用属于T016机制门槛失败，需要修订方案后才进入实施。应用崩溃/退出后直接重新查询系统状态，不依赖需清理的磁盘前台标记。

查询与投递不能构成原子操作：GUI 运行时设置 `UNUserNotificationCenterDelegate`，在 `willPresent` 中对到达前台的 GUI 失败通知返回空 presentation options，不显示横幅、不播放声音；若前台查询后 GUI 转入后台，此次已抑制提醒不补发，最新失败仍可查看。退出后 helper 独立投递的身份和系统前台路由仍须实证，不能仅凭 API 可编译宣布成立。

T016/T021 必须在签名 sandbox helper 的 launchd 身份下验证查询可用性，以及前台/后台/隐藏/菜单交互/退出/崩溃和投递竞态；验证 delegate 实际抑制横幅与声音、计数不重复且不补发。若目标系统无法提供所需查询或前台回调，停止此机制的通过结论并修订设计；不自行增加轮询或常驻服务作为兜底。

# 所有权转换

1. 自动呈现已有 CLI 配置，内部检查兼容版本和当前系统状态；由程序定位固定目录并复用有效访问能力，首次/恢复均无内部目录选择，不提供 CLI 导入/检查向导。需要转换后台所有权时明确解释结果并取得该动作同意；不能把自动呈现误当已完成 owner 转换。已有路径、CAS 与 owner 协调基础，新的访问机制及真实共存闭环尚未验证。
2. 转换日志与 generation 记录待接管，冻结新评估；有界等在途动作排空。
3. 由拥有旧服务管理权限的入口注销/停用，验证旧 job 不再 eligible/running。
4. 注册新服务；立即运行的 helper 不执行未提交 owner 的挂载，不能堵塞注册等待锁。
5. 新服务真实 enabled 后提交 owner 并显式评估；requiresApproval 则保持 awaitingApproval，无第二 active 服务。
6. 中断/失败依据日志和实际系统状态收敛；恢复原 owner，或保持明确 stopped 并提供显式恢复/接管入口。通用中断恢复已有实现基础，但正式 GUI 恢复入口未接入 CLI 身份的相应路径，CLI stopping/activating 门禁可能持续返回 transitionInFlight；拟由 T092 收敛并原生复验，不把 owner 恢复写成完全不存在。无自动静默接管、无 owner-blind 自愈。

旧 CLI 服务释放可以由用户使用兼容 CLI 管理操作完成，GUI 不能执行外部 executable。兼容 CLI 提供显式 `--disable-automation`：参数严格校验后、任何搬迁/自愈之前执行，保存 automation_enabled=false，随后经统一协调器冻结/排空/注销与明确系统缺失核查，成功才返回0；失败返回1并保留关闭偏好，不移除CLI/Shell入口或配置、不弹出共享。该命令不是已迁移证明，也不能用于覆盖app owner。反向由 GUI 自己注销 SM 服务后 CLI 注册；控制 UI 可被有界打开，用户不需要长期保持 GUI。旧版本不协作即提示升级/停用，拒绝并行注册。

# 运行证据与失效处理

系统服务状态、当前进程、配置 revision、owner generation、权限和最新观测时间共同展示，不能仅凭 state file 宣称健康。应用删除/移动、权限失效、旧服务残留、开关转换中断分别实测。

无事件角落如实说明等待下一事件/登录/手动重试，不能承诺固定恢复时间。若 sandbox 不支持核心自动恢复，停止后续发布准备的“通过”结论，记录实际错误、可行替代及需要审阅的范围变化；账号购买不是默认解决办法。

# 全产品状态与操作收敛

配置添加、后台启用、目标实际可用分别回报；automation_enabled=true 不是运行证明。GUI 展示最近实际查询时间、批准/撤销/停止失败/未知原因及显式恢复动作；读取失败不能显示空配置。退出 GUI 保持已启用后台，升级保留意图与偏好，接管明确征求选择并先排空旧 owner。

fullEvaluation、singleShare 与 normalEject 共享操作锁、owner/generation 和有界预算；statusRefresh 仅重读。进度绑定实际目标，失败在对应 scope 合并，不移动 UI 选择。通知以当前结果摘要合并多问题，点击重读最新状态，不执行旧通知操作；系统授权状态与声音偏好分别核查。

# 当前权限机制与待执行验收

参照[体验契约的当前 Apple 依据](experience-design.md#官方资料与证据限度)，分别论证 App Sandbox、user-selected entitlement、App Group 成员与独立 helper；GUI 授权、SM 后台批准、SMB 认证、TCC/FDA、POSIX 权限不互相替代。程序固定位置与无目录选择是当前要求，generic Allow/Deny 访问尚未证明，普通 Alert 不可伪装系统授权。T083→T084 拟负责机制与入口；T092 拟负责中断 owner 恢复；T093 拟负责 GUI 退出/真实登录/重启/稳定签名升级/网络变化下独立目录与真实 SMB 矩阵。这些为已追加、未完成任务；T079–T082 面板条目只保留历史范围，不要求当前用户验证 picker。
