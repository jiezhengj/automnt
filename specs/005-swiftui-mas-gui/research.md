**方案 A 当前裁定（2026-10-13）**：保留固定真实目录、GUI/CLI 唯一配置和单后台 owner；仅撤回固定目录选择面板例外。正常首次、设置、共用和恢复由程序确定目录，用户不识别/选择目录；必要许可只决定允许或拒绝。合法免目录选择访问机制尚未证实，不把普通 Alert、TCC/FDA、POSIX 权限、书签或 helper 签名当作沙盒通行证。本轮先修文档与任务；历史本地实现、测试/构建和 CLI SMB 证据不证明新流程可用。

**日期**：2026-10-07

**范围**：Feature 005 Plan 的只读研究；未构建 GUI、试挂载、注册服务或改变业务配置。本阶段解决设计选型，不把公开 API 的存在当成集成成功。

# 共同核心与构建

**决定**：用 Swift Package 的 AutomntCore 承载配置、策略顺序、服务探测、挂载身份、恢复状态机、会话抑制、冲突控制与诊断脱敏；CLI、SwiftUI 应用、短命后台与隔离工作器链接同一核心。渠道安装、权限、凭据绑定、系统服务注册和更新通过适配接口注入。

**理由**：现有 [源码](../../automnt.swift) 是约 6070 行单文件，既包含业务规则，也包含终端、安装、自更新与自测。直接把整个 CLI 嵌入 GUI 会把自搬迁、Shell 修改和 GitHub 自更新带入商店版。先以现有内置自测和真实 CLI 行为作为回归基线，再分离入口，不能同时重写恢复语义。

**替代**：两套业务实现拒绝；GUI 执行外部 CLI 拒绝；应用内签名工作器可用于时限隔离，但不是外部 CLI 依赖。版本继续唯一声明在现有源码顶部，构建脚本提取该声明生成核心版本常量与应用元数据，生成文件不手改、不成为新真理来源。源码迁移后根入口保留版本声明，构建必先校验仅一个声明。

**工具证据**：本机 Swift 6.4、Xcode 27.0（27A266a）、macOS 27 SDK、arm64。独立评审补充只读 `otool -l ./automnt`：当前工作区 CLI 3.3.2 的 `LC_BUILD_VERSION minos 27.2 / sdk 27.0`，与源码和 README/ARCHITECTURE 声明的 27.0 不一致；这是既有产物差异，不能据 SDK 27.0 推断支持 27.0，T040 必须明确构建目标并同步各声明/产物、实测复验。本轮不重建 CLI、不更改源码平台常量。Swift 6 并发检查约束核心可变全局状态；UI 主线程不执行 NetFS、钥匙串或卷访问。

# 沙盒挂载与凭据

**2026-10-11 最新纠正**：GUI 不增加独立密码管理，复用系统 SMB 认证及系统已保存凭据；现有 CLI 的 NetFS 调用传 nil user/password。移除普通用户的密码录入、验证、删除入口，不创建应用私有 SMB 密码项。sandbox GUI/helper 能否复用系统凭据尚未验证，不能由 CLI 成功或 API 存在推断成立。缺少有效认证时引导用户到 Finder 连接服务器，完成系统认证后回到应用重试。

**决定**：选择 NetFS 公共 API，标准路径首先使用系统管理挂载点；共享核心统一 SMB 身份匹配并消费返回的实际挂载路径，检查路径冲突，不能把成功码直接等同约定路径已可用。后台禁止弹认证 UI。下述显式凭据管道、应用 Keychain 选型及“拒绝 Finder 前置”的记录属于被上述纠正替代的旧方案研究，不作为现行实现要求。

**理由**：已读 SDK NetFS.h 的 NoUI、显式 user/password、返回 mountpoints、MountAtMountDir、异步与取消接口。当前实现传 nil 凭据并丢弃实际路径，需要适配；API 不证明 sandbox 能挂载 /Volumes 或指定目录。选用可终止的签名短命工作器执行同步 NetFS，保留已有有界隔离方式；凭据只通过受控匿名管道在内存传递，不进入 argv、环境、临时文件或日志。超时终止后核对内核挂载表；终止请求不代表系统挂载事务已回滚，不叠加竞争重试。

钥匙串选现代 SecItem/Data Protection Keychain 能力，LAContext.interactionNotAllowed 保证后台不弹认证；不新增已弃用的 kSecUseAuthenticationUIFail 设计。GUI/自身 helper 的访问身份与凭据传递须实测，独立 community CLI 不假定拥有同一 Keychain access group。入口的凭据绑定可以不同，共享目标、挂载规则及唯一配置不能不同；首次渠道授权可说明，正常升级不能反复授权。

**替代**：要求用户先安装 CLI 或在 Finder 手动连接才具备核心能力拒绝；密码写入 plist、命令行或诊断拒绝；仅凭 network.client entitlement 推断拥有挂载权限拒绝；异步取消并未给出系统事务硬截止证明，不替代本轮保留的隔离与事后收敛。

**证据**：[网络客户端权限](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client)、[Keychain Services](https://developer.apple.com/documentation/security/keychain-services)、[Data Protection Keychain](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain)、[禁止认证交互](https://developer.apple.com/documentation/localauthentication/lacontext/interactionnotallowed)。SDK：`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/NetFS.framework/Versions/A/Headers/NetFS.h`；同 SDK Security.framework 的 SecItem.h。网上 NetFS 文档请求未获得有效页面，未假称已读取。

# 活动配置与权限

## 2026-10-11 修订记录（历史决定，当前约束见文末）

维护者明确否定普通用户首次启动必须选择内部配置目录的思路；不是文案问题。以下旧决定不再作为 GUI-only 首次流程实施依据，历史实证仍保留。暂停推动用户授权 Library/Application Support/automnt 来完成正常首次启动；已实现的临时书签绑定仅属于旧方案技术探针，不代表产品方案通过。

当时修订方向（历史研究）：GUI 不要求用户选择内部目录，也不提供 CLI 导入/检查。已有 CLI 目标应自动呈现，保持单配置/单 owner；后来已有固定路径、仓库 CAS、访问状态和协调代码，实际授权与运行闭环仍未证实，不能说这些全部未实现。App Group 内部存储候选后来撤回；容器与非成员 CLI 的兼容影响仅属历史研究。共用核心、CAS/稳定锁和退出后自动挂载不变。

Apple 当前文档说明 macOS App Group 可用 `<team identifier>.<group name>`，无需网站注册，并可用于sandboxed/nonsandboxed应用间通信。原先“任意CLI不能作为发行者组成员”仍成立，但不能据此否定GUI/helper内部共享容器。免费Apple Development的真实容器读写/签名连续性、helper独立launchd访问，以及非成员CLI对同一活动存储的安全兼容和原目录迁移，都仍须实证。不能只把PermissionStore默认路径改为容器并跳过迁移/所有权契约。

证据：[App Groups Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups)、[Configuring app groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)，本轮读取官方全文。现有 GUI 仍显示旧目录选择入口；修订未实施完成，尚未宣称新的无选择流程可用。

## 固定路径授权研究（历史面板方案，目录选择要求已撤回）

**决定**：保留用户真实的 `~/Library/Application Support/automnt/automnt.plist`，通过系统文件选择授权该 automnt 文件夹；GUI 私有容器存权限书签和纯界面偏好，不另存可独立编辑的活动目标；需后台读取的 GUI 通知声音偏好另存 同一固定授权目录内 gui-notification-preferences.plist（分文件，不含业务目标），数据格式与失败处理见 data-model.md NotificationPreferences，双方自身持久目录授权须由 T016 实证。GUI-only 初次运行通过用户授权的系统目录选择/创建操作定位同一文件夹，程序随后生成配置；取消就保持待授权，不显示真实未配置空态。核心接受解析后的真实目录，不能用沙盒中的 home/Application Support 推导另一份配置。

**理由**：任意签名的开源 CLI 无法被要求加入发行者 App Group。目录授权才能覆盖原子替换、配置锁、恢复状态等同目录数据；选择单个 plist 不保证原子替换后授权有效。选择错误目录、符号链接、多个副本必须明确拒绝或引导，不能悄悄回退。文件权限保持 0600，目录及锁仅当前用户访问。

**替代**：所有配置搬入发行者 App Group 拒绝；两个配置定时同步拒绝；自动猜测并读取用户 Library 拒绝。App Group 最多可作为发行者 GUI/helper 的权限元数据通道，需单独证明免费账号可运行和跨身份兼容，不把它作为任意 CLI 的依赖，也不预设它是已经可用的解决方案。

**关键验证**：显式 app-scoped bookmark 不保证另一身份 helper 可跨登录直接使用；已读文档提供 live implicit bookmark 传递给 launch agent/XPC 的机制，但不证明重启后持久授权。实现前段必须验证 helper 建立自己的持久授权/自身权限存储方式，以及 GUI 退出、重启、已卸载目标时无 UI 解析。不能用只在 GUI 开着时有效的授权通过验收。

**证据**：[沙盒文件访问与书签](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)、[App Groups](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups)、[沙盒 helper](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app)。

# 系统事件与后台注册

**决定**：CLI 保留传统 LaunchAgent 渠道；商店版以 SMAppService.agent 注册包内签名 helper，RunAtLoad，固定系统网络配置路径；恢复开启版本加入 StartOnMount 与 /Volumes WatchPaths，关闭版本只保留登录/网络事件。两份 plist 都在构建时固定，运行期按开关注销旧版本再注册新版本，禁止修改签名 bundle。没有 KeepAlive、StartInterval、固定轮询或常驻网络监听器。

**理由**：SMAppService 要求 plist 位于 Contents/Library/LaunchAgents，支持 BundleProgram 相对路径。现有 CLI 的用户特定 mountWatchPaths 无法直接移植为可变 bundle 内容。WatchPaths 有竞态且不保证每次网络/卸载事件，StartOnMount 只表示 mount。候选固定 /Volumes 方案必须证明约定路径与恢复场景；非标准目录监听不能凭空声称已覆盖。

**替代**：运行期改签名 plist 拒绝；常驻 NWPathMonitor/SCDynamicStore 作为替代唤醒拒绝；KeepAlive NetworkState 已无有效实现；自己发明 LaunchEvents 插件拒绝。统一超集触发并在恢复关闭时空跑会改变既有两源事件契约，本方案不采用。

**证据**：[SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)、[更新旧 helper](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)、本机 `/usr/share/man/man5/launchd.plist.5`；SDK ServiceManagement.framework/Headers/SMAppService.h 明确 register、unregister、签名、登录与 BundleProgram 行为。

**能力门槛**：验证系统网络路径监听、VPN/网络上下文、/Volumes 弹出及重挂、两源/三源开关、GUI 退出后唤醒。自定义 mount_point 的精确监听和稳定路径是尚未实测的集成门槛，必须在早期验证中解决；不得静默禁用已有 CLI 的有效自定义目标或宣布等价。如果无合规且不常驻的办法，报告核心能力失败，重新审阅范围/渠道，不能归因账号或改为手动挂载。

# 服务接管与并发

**决定**：配置旁持久化 owner/generation 和接管日志，使用稳定侧文件锁保护全部评估与转换，而不仅现有恢复 round；每次动作核对当前所有者。先冻结新动作、停止并确认旧服务退出，再授权注册新服务；成功才提交新所有者并评估，失败恢复旧服务或进入明确停用。OS 注册状态是事实依据，磁盘 owner 不能冒充系统状态。

**理由**：CLI 安装自愈当前会重新创建旧 agent，必须所有者感知。GUI 不执行目录里的 CLI，也不靠它逃离沙盒；已安装场景可能需用户通过升级后的 CLI 释放旧服务或对旧服务目录显式授权。GUI-only 不需要这一步。反向接管由 GUI 通过自身 SMAppService 注销，CLI 可以通过有界控制请求打开 GUI 完成，不能声称独立 CLI 可直接注销别的应用注册。

**替代**：依赖相同 launchd Label 自然互斥拒绝；只在挂载前检测卷不足以避免竞态；两个 active 服务靠锁长期竞争拒绝。未知旧版本/任意改造二进制不遵守协议，产品检测并要求兼容升级、停用旧服务；不能承诺对任意外部工具实现绝对互斥。

# 可选菜单栏与主动卸载

**决定**：100% SwiftUI Window/Settings/MenuBarExtra；isInserted 默认 false，主应用按需打开。菜单开启时同一 GUI 进程显示菜单并可在明确同意后登录打开该 UI；这不是评估循环。关闭窗口不移除已开启菜单；⌘Q 退出 GUI 与菜单，后台继续，偏好保留，下次打开恢复。菜单可单独关闭而自动化继续。登录 UI 启动只显示菜单，正常用户启动显示配置。

快捷卸载用 DiskArbitration 默认普通卸载，不强制升级；繁忙则显示失败并保留挂载。共享维护锁贯穿卸载请求及确认，成功提交会话抑制，避免卸载与后台重挂竞争。SDK DADiskCreateFromVolumePath 可能返回 nil，SMB 与沙盒可用性须实测；不支持不能假称成功。死卷修复独立于用户普通卸载。

**证据**：[MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)、[DADiskUnmount](https://developer.apple.com/documentation/diskarbitration/dadiskunmount(_:_:_:_:))、[从卷路径建立 DADisk](https://developer.apple.com/documentation/diskarbitration/dadiskcreatefromvolumepath(_:_:_:))。

# 视觉、隐私与发布

**决定**：原生列表/详情布局、系统语义字体、SF Symbols、克制材料、清楚状态文案；视觉设计和实际状态覆盖随主流程交付，最终维护者审美审阅与修复复验必做。默认无遥测/广告/第三方分析，诊断脱敏、预览后导出；日志保留/清理数值在实现前作为维护者待确认隐私决定，不凭行业默认值落地。

复用公开项目托管资源准备中英文 privacy/support 页面，商店 URL 用最终固定版本文件路径并检查可达；本阶段不发布页面。已用 gh 验证公开仓库 jiezhengj/AutoMount，无现有 homepage，不需购买域名。支持入口用项目公开 Issues，提示不要公开敏感诊断；不捏造邮箱/法律姓名、不承诺终身更新。维护者所需身份资料在账号无关准备阶段收集，账号专属账户登记才置最后。

**证据**：[Apple 审核指南](https://developer.apple.com/app-store/review/guidelines/) 2.4.5 的 sandbox、自包含、后台用户同意、禁止下载代码/提权，5.1.1 隐私政策要求；源码/免费 CLI 推荐只是对条款的解释，并非预批准。

# 当前发现与编辑规则

2026-10-11 文档/demo 要求：主界面打开、挂载变化及应用重新激活时发现本地当前已挂载 SMB，宽窗左侧平铺服务器名、已管理/可添加数量与异常摘要；右侧选中服务器标题、独立开关及说明、紧凑已管理/可添加共享组，无固定第三列。共享行保留名称/状态/Finder或修复或添加，URL/路径/索引/编辑/移除按需 sheet；工具栏 fullURL 完整 SMB URL 入口，Finder 指导为次级空状态。窄窗服务器→共享→详情系统导航及返回保留选择与滚动，刷新/添加保留身份、焦点与滚动；多主机多卷示例用于审阅。这里不是扫描远端全部共享。每行“添加”立即校验并持久化，不使用选择 toggle 加“添加所选”。零结果提供 Finder“连接服务器”指引，工具栏手动入口只接受完整 `smb://host/share`；缺 URL、空共享和重复规范化身份均拒绝添加。

编辑 Save 成功关闭编辑界面并重置 dirty，随后 Cancel 不再次提示保存；失败保留 draft 和 dirty。服务器开关标签为“自动挂载此服务器的共享”，辅助说明关闭不影响已挂载共享。Spotlight 文案说明尝试减少索引活动、可能限制搜索且不自动删除现有索引，不承诺一定阻止索引。保留 Automnt 暂时显示；品牌来源受到维护者质疑，尚未最终确认，不新增“自动挂载助手”。本段是本轮设计要求，不是 runtime 通过记录。

# 研究结论与证据边界

所有技术未知已分类为上述设计选择、明确维护者决定或实现验证门槛，没有用 NEEDS CLARIFICATION 占位符隐藏问题。设计可以进入后续质量检查与任务拆解；**沙盒核心能力尚未通过，不能认定完整实现方案已被实机证明**。

本轮公开只读请求使用此前授权的 developer.apple.com 获取例外：默认 TLS 校验证书，无登录，不自动跟随重定向；web_fetch 因代理非公网解析失败的页面采用 Python urllib 读取官方 Markdown/DocC。API、条文和 SDK 是选型证据，不是 App Store 接受证明。

# 全产品决定与剩余证据

维护者当前决定：侧栏分管理/发现两组；管理组直接拖放即存、可撤销且并发保护，键盘提供等价操作；首个共享使服务器追加末尾。保留首可达策略，不并行多 NAS。界面选择、评估服务器及既有挂载分开，刷新/完整评估/单共享操作范围分开。开关即时保存、名称行内确认、相关地址/路径成组提交；普通弹出无例行确认，移除不弹出且最后共享移除服务器。

详情与设置、系统语言/外观、原生关于/帮助、离线支持/许可、诊断预览、最新状态通知、退出/升级与显式接管属于全产品范围。共同核心操作与 CLI 单共享/弹出入口已于 2026-10-12 实现（`--mount`/`--eject`，含回归测试；内核调用按构建方式分置、词汇须与 Platform 一致），且 T078 留有部分真实 CLI 挂载/普通弹出证据（见 [交互审阅](design/interaction-review.md) 与 [任务](tasks.md)）；**GUI/helper 的相应能力未实测，CLI 证据不能外推**。旧排序 Draft/Save 与例行弹出确认为被替代方案，且已从应用代码删除；不改写历史运行证据。系统认证、透明配置、owner 协调和真实原生验收仍未通过。

# 方案 A 保留架构与免目录选择边界

维护者保留方案 A 的固定真实 CLI 目录、唯一配置和单 owner，最新纠正只撤回首次/恢复的目录选择例外。旧 NSOpenPanel、临时父 scope 与子目录书签已有代码，均不是新产品流程。新访问来源须覆盖 GUI/CLI/helper 的读写、原子替换、稳定锁、状态及偏好；目录不存在由程序依法准备。App Group 不作为活动业务配置候选；不迁移、双写、静默换渠道或改变 CLI 签名/协议。

GUI 和独立 launchd helper 的权限不可直接等同。先证明 helper 自身持久授权及 launchd 启动后读写同一真实目录，覆盖 GUI 退出、重新登录、重启和稳定签名升级；live bookmark、GUI 启动子进程、App Group 可读均不足以通过。现有文档/API 只支持设计候选，尚无方案 A 全链路运行证据。若系统或商店边界不允许必要能力，记录具体门槛失败，再评估渠道；不默认迁移 App Group、移除沙盒或引入特权 helper。

# 当前 Apple 资料核查与任务输入

2026-10-13 已获取当前官方页面及相应 DocC JSON；仅有标题的页面不作全文证据，能力与弃用状态核对自 JSON。当前资料可以约束候选，不能直接证明 macOS 27/MAS 集成成功或判定必然不可行。

| 当前官方资料 | 已核查范围 | 不能据此推出 |
| --- | --- | --- |
| [App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox) | 容器与受保护资源的访问边界 | 普通应用“允许”按钮授予外部文件访问 |
| [User-selected read-write](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-write) | 用户通过 Open/Save dialog 选择文件的访问 | 预先指定或隐藏目录即可免选择授予 |
| [Security-scoped resource](https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource()) / [bookmark](https://developer.apple.com/documentation/foundation/nsurl/bookmarkcreationoptions/withsecurityscope) | 使用与恢复既有 scope | 创造新的授权或任意独立身份长期共用 |
| [Sandboxed helper](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app) | 嵌入工具的构建、签名、沙盒边界 | GUI 退出、登录/重启后独立 launchd 的持久权限 |
| [App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups) / [Group containers](https://developer.apple.com/documentation/xcode/accessing-app-group-containers) | 组成员与共享容器访问 | 任意 Homebrew/ad-hoc CLI 已是成员，或能访问固定外部配置 |
| [All files entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.all) | DocC 标为 macOS 10.11 起 deprecated | macOS 27/MAS 通用全文件访问 |
| [Privileged file operations](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.security.privileged-file-operations) / [NSWorkspace authorization](https://developer.apple.com/documentation/appkit/nsworkspace/authorizationtype) | 需申请的 entitlement 与 createSymbolicLink/replaceFile/setAttributes 特定操作 | 普通持续读写、锁访问及独立 helper 的持久许可 |

FileManager 的授权初始化 API 不提供上述通用能力：当前 macOS 27 SDK 明确限定三类操作，其他方法照常执行；授权还可能过期、无效或被系统策略拒绝。home-relative temporary exception 的专属当前 DocC 页面仍未取得有效内容，但本轮已取得当前 App Store Connect 的例外申报说明，并在当前 macOS 27.2 的沙盒规则中找到该 key 与目录读写规则，详见下节。这构成精确目录候选的静态证据，不能表述为已获 MAS 接受或全生命周期实测通过。2018 归档指南仅为历史背景，Alfred 位置选择不能证明本项目权限。

T083 产出真实机制、各身份/生命周期边界及用户可见流程；涉及迁移、CLI 签名/协议或发行渠道时先记录影响与兼容/回滚，再由维护者作新决定。研究未得许可来源时准确记录尚未证实，不把旧面板改文案视为方案完成。T084/T093 在机制裁定后实施与实测，其他独立修复可按依赖并行。

当前源码审计及 T085–T094 追溯见 [问题台账](../../release/evidence/feature-005-gap-audit.md)。图标内容、发现合并、编辑身份/revision、真实退出保护、刷新、窄导航、精确校验和 CLI 中断恢复均有具体任务；运行反馈与推导风险保持区分。系统凭据、后台真实恢复及九语原生验收仍未完成。

# T083 精确目录例外候选与当前核查

2026-10-13 本轮仅进行官方资料与本机静态只读核查；宿主 `sw_vers -productVersion` 为 27.2，安装 SDK 的 `SDKSettings.plist` 声明 macOS 27.0。未运行权限探针，未构建、改签名、注册 helper、准备业务配置或改变发行渠道。**结论：发现可进入 T084 验证的具体免目录选择候选，尚未证明完整方案 A 可用；不以缺少专属当前页面判定必然不可行。**

## NSWorkspace 与 FileManager 的实际权限范围

已取得当前 [requestAuthorization](https://developer.apple.com/documentation/appkit/nsworkspace/requestauthorization(to:completionhandler:))、[FileManager.init(authorization:)](https://developer.apple.com/documentation/foundation/filemanager/init(authorization:)) 与 [privileged-file-operations entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.security.privileged-file-operations) 的 DocC JSON；前两项 macOS 10.14 起、后一项 10.15 起，当前数据均未标记 deprecated。privileged-file-operations 页面要求先向 Apple [申请该 entitlement](https://developer.apple.com/contact/request/privileged-file-operations/)，不是所有签名身份自动可用。

本机 SDK [NSWorkspace.h:240–279](/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSWorkspace.h#L240-L279) 逐项限定：`createSymbolicLink`、`setAttributes`、`replaceFile`。属性仅覆盖 owner/group ID 与 POSIX permissions；替换忽略 `backupItemName` 和 `options`；授权可过期或无效，操作可因系统策略失败。277 行明确其他 FileManager 方法照常执行。没有据此获得普通读取、创建目录或临时文件、打开锁文件、`flock`、CAS 操作或独立 helper 的长期访问。即使其中一次 replace 成功，也不能补齐本产品需要的完整事务。

传统 Authorization Services 与 NSWorkspace 上述专门 API 不能混称。当前 [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox) 将 Authorization Services API 列为沙盒不兼容活动；本机 SDK [sandbox.h:7–49](/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/sandbox.h#L7-L49) 也明确旧 profile 初始化接口 deprecated / no longer supported。两者均不作为本轮免选择方案。

## 当前例外证据与精确声明

当前 [App Store Connect：App Sandbox information](https://developer.apple.com/help/app-store-connect/reference/app-uploads/app-sandbox-information/) 正文仍说明通过编辑 `.entitlements` 添加 temporary exception，并要求提供 entitlement key、评估方法、必要性、启用的功能及数组每个值的说明；若用于绕过缺失的 App Sandbox 功能，要求 Feedback Assistant bug ID。该正文经默认 TLS 的只读请求提取，未仅依据导航或搜索摘要。它证明当前仍有例外申报流程，未承诺本项目这个 key/用途必获审核接受。

当前宿主 [application.sb:953–958](/System/Library/Sandbox/Profiles/application.sb#L953-L958) 明确读取 `com.apple.security.temporary-exception.files.home-relative-path.read-write`，对目录调用 `read-write-and-issue-extensions`；[appsandbox-common.sb:72–93](/System/Library/Sandbox/Profiles/appsandbox-common.sb#L72-L93) 对匹配路径允许 `file-read*`、`file-write*` 等；[791–794 行](/System/Library/Sandbox/Profiles/appsandbox-common.sb#L791-L794) 按末尾 `/` 选择 subpath，否则仅 literal。home 相对路径经 [284–289 行](/System/Library/Sandbox/Profiles/appsandbox-common.sb#L284-L289) 与 `_HOME` 参数组合。**该规则文件首部明确声明 Apple System Private Interface、随时可变**：这里只作为当前系统的静态实现证据，不修改规则、不调用私有接口，也不将其当成公开稳定契约。`_HOME` 的实际身份映射与 sandboxed 程序真实用户目录的一致性仍须实测。

进入验证的最小候选声明为：

```xml
<key>com.apple.security.temporary-exception.files.home-relative-path.read-write</key>
<array>
    <string>/Library/Application Support/automnt/</string>
</array>
```

末尾 `/` 有意义：业务事务需要目录内的配置、同目录临时替换文件、稳定锁与状态，不只一个 plist。候选仅声明现有唯一目录，不扩大到整个 Application Support 或用户 home。GUI 与独立沙盒 helper 各自需要实际生效的精确声明；它是在签名中声明的能力，不是一个“允许”按钮或 OS 文件授权提示。程序仍根据真实账户 `getpwuid(getuid())` 确定唯一配置位置，不能因 sandbox home/容器解析差异而静默创建第二份配置。该候选未改变 CLI 的配置路径、格式、免费分发或签名/访问协议；现有同用户非沙盒 CLI 仍受其本来 POSIX、ACL 与系统隐私边界约束。

## 各权限层与独立身份

当前官方 [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) 的 DocC 全文核查提供以下边界：

| 机制 | 实际覆盖 | 本产品仍须证明 |
| --- | --- | --- |
| 精确目录 entitlement | 候选沙盒文件访问来源，随签名声明存在 | GUI/helper 各自生效、真实 home 映射、目录创建与所有事务 |
| POSIX / ACL | 同用户访问、0700 目录与 0600 文件等权限 | 获得沙盒范围仍可能被 POSIX/ACL 拒绝；不能放宽权限冒充授权 |
| TCC / FDA | 系统隐私层的用户选择；官方明确 FDA 不能由代码或 entitlement 自动授予，需系统设置 | 不把 FDA 当成精确目录沙盒声明的替代证明；当前目录是否触发隐私限制尚未实测，不预先要求用户授予 FDA |
| User-selected / scoped bookmark | 当前官方要求 Open/Save 等标准选择；书签延续已有 scope | 未授权路径不能因创建 URL 或普通 Alert 获权；本产品无目录选择，故不是首次来源 |
| IPC / implicit bookmark | 当前官方明确可将隐式 scope bookmark 传给 launch agent / XPC，接收者尝试扩展沙盒 | 不能创造最初授权；一次进程间传递不能证明 GUI 退出、独立重启后持久访问 |
| App Groups | 组身份及共享容器，当前官方含签名/分发/授权条件 | 不赋予固定外部目录访问；现有 Homebrew/ad-hoc CLI 不能直接假定为成员 |
| SMAppService | 控制登录项/LaunchAgent/LaunchDaemon 与后台运行批准 | 批准后台运行不是文件权限；必须独立证明 helper 的实际身份与读写 |

当前 [Embedding a helper tool in a sandboxed app](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app) 明确 GUI 启动的继承型命令行工具只带 `com.apple.security.app-sandbox` 与 `com.apple.security.inherit`，另加 entitlement 可能导致签名错误。不能给这种工具直接叠加目录例外来声称验证了独立 launchd helper。本候选需要独立 sandbox 身份及自身范围，继承型工具与独立后台的打包/签名方案须分开验证；本轮未改 helper 架构。

当前 [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) 与 SDK [SMAppService.h:19–62](/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/ServiceManagement.framework/Versions/A/Headers/SMAppService.h#L19-L62) 明确应用需代码签名、`requiresApproval` 为用户需在系统设置批准/已撤回运行许可，agent/executable 更新需重新注册。这可提供用户允许或拒绝的后台运行流程，不产生普通文件通行证。当前 [App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups) 与 [Group containers](https://developer.apple.com/documentation/xcode/accessing-app-group-containers) 明确团队身份与容器授权边界，也不能替代真实 CLI 目录。

## T084/T093 验证输入与用户流程

用户正常首次操作为添加共享与开启后台自动挂载，程序确定固定目录并在已有合法范围内准备它；若系统确实需要后台运行或资源许可，使用对应系统流程，用户只作允许或拒绝。后台运行拒绝时保留真实状态及恢复入口，不显示正在恢复；文件访问失败则准确分类原因，不弹内部目录选择器、不生成容器/组中的平行配置、不自动换渠道或提权。产品说明不伪装为系统授予目录权限。

T084 可围绕上述精确声明继续本地实现与验证，优先既有免费 Apple Development 身份；该身份仅用于验证实际运行，不等于 MAS 接受。T083 本轮没有签名/runtime 结论，不勾选完成核心授权链路。剩余证据按以下顺序取得：

1. GUI 与独立 helper 各自实际签名 entitlement / designated requirement、沙盒启用状态及同用户真实目录一致；既有 CLI 不重签。
2. 既有目录与目录缺失两种情况，程序自身依法创建 0700/0600 内容；拒绝、父路径不可创建、符号链接或错误 owner 时不能扩大范围或写入第二个配置。
3. 三个入口对同一配置执行读取、revision CAS、同目录临时文件与原子替换、稳定锁 inode / `flock` 竞争和状态/偏好；失权限或写入失败不能破坏旧配置。
4. GUI 退出后独立 helper、真实重新登录与重启、稳定签名升级/重新注册、许可撤回和恢复均实测；单 owner、generation 及中断恢复保持既有协议，不能用前台重试替代后台恢复。
5. 分别记录免费开发身份的结果与 MAS distribution/审核例外证据。当前官方未专门确认该精确 key 在 macOS 27 SDK 的公开稳定契约，现有静态证据也未证明 MAS 批准；2018 指南、专属页面 404、SDK entitlement 文件未列 key 都不能单独推出支持或不支持。

若候选实际被签名策略、运行时访问或审核拒绝，记录具体身份、操作与拒绝证据，再交维护者决定渠道或兼容影响。本轮保留唯一配置和单后台 owner，不以迁移 App Group、改变 CLI 协议或特权 helper 填补未知。

