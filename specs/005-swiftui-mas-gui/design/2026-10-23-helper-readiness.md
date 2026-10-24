本文记录 Feature 005 于 2026-10-23 重开时裁定的 helper 启动与就绪判定修正：问题、实测证据、目标机制与拒绝条件、失败回退、验收矩阵和未验证项。本文只做设计记录与验收定义，不代表全部验收通过；结论以 tasks.md 的 T129–T138 真实验收为准。2026-10-23 第三轮的状态见文末“未验证项”中的更新说明，挂载执行位置另见 [2026-10-23-sandbox-mount-execution.md](2026-10-23-sandbox-mount-execution.md)。

# 问题

2026-10-22 的 Feature 005“完成”只对界面交互与本地工程成立。维护者要求重新打开并做完整验收后，实测发现登录后的后台自动挂载完全不工作：

- 用户重新登录或重启 Mac 后，配置中启用的 SMB 共享不会自动挂载，文件任务仍会先报错，用户只能去 Finder 手动连接。
- 界面仍可能显示“自动挂载：运行中”，与实际能力相反。
- 没有失败通知，用户无法从系统提示知道后台没有工作。

因此本次重开把“后台跨登录/重启自动挂载”当作重新验收的核心能力，界面验收结果不重做。

# 实测证据

以下为 2026-10-23 在维护者机器上执行的只读检查摘要（本轮文档工作未重新运行，也未修改任何系统状态）。取证对象是已安装的签名产物 `/Applications/Automnt.app` 与真实登录会话。

## 触发与退出

- 2026-10-23 19:04 登录后，系统按 RunAtLoad 触发 bundled recovery 服务；该轮 recovery job 触发 3 次（runs=3），最后一次 exit code = 1。
- 该轮没有写入 `backend-state.plist` 或观测记录，没有共享被挂载，也没有投递失败通知。
- 用于取证的命令（摘录）：`launchctl print gui/$(id -u)/org.automnt.automnt.recovery`，以及对应 baseline label 的同形查询。

## 根因 A：argv[0] 相对字符串导致 app bundle 解析错误

- 三个 bundled 定义都用相对路径（apps/Automnt/Resources/LaunchAgents/automnt.baseline.plist:5、automnt.recovery.plist:5、automnt.authorization.plist:5）：

  ```text
  BundleProgram = Contents/Helpers/AutomntHelper
  ```

- launchd 以该相对字符串作为 argv[0] 传给 helper，而不是可执行文件的绝对路径。
- helper 在 apps/Automnt/Service/HelperEntry.swift:56 用 `URL(fileURLWithPath: CommandLine.arguments[0])` 得到自身路径，在 :57 连续三次 `deletingLastPathComponent()` 推导 app bundle。
- 沙盒进程 cwd 实测为 `~/Library/Containers/org.automnt.automnthelper/Data`，于是“相对路径 + 容器 cwd”解析到容器内不存在的位置，applicationURL 指向错误目录。
- apps/Automnt/Service/HelperEntry.swift:59-60 接着校验可执行文件名必须为 `AutomntHelper` 且 bundle identifier 必须为 `org.automnt.automnt`；解析错误时该校验必然失败，helper 以退出码 1 结束，没有进入评估。

## 根因 B：helper 进程内无法用 SMAppService 判定服务状态

- 即使修正 argv，helper 进程内实测 `Bundle.main.bundleURL = /Applications/Automnt.app/Contents/Helpers/`，即 `Bundle.main` 指向 Helpers 目录而不是 app bundle 根。
- helper 内查询 `SMAppService.agent(plistName:)`（Sources/AutomntPlatform/ServiceController.swift:16）返回 error 22（Unable to find service status），拿不到 `enabled` 等真实状态。
- 现行 helper 就绪路径把“非 enabled”统一映射为 `backgroundApprovalRequired` 并退出（Sources/AutomntPlatform/BackgroundEvaluationTrigger.swift:53），于是 helper 不评估、不挂载。
- 对比 App 进程内同一查询正常：baseline=notFound、recovery=enabled。于是出现状态分裂——App 认为后台已开启并显示“运行中”，真正执行挂载的 helper 认为未获准而退出。这是“界面正常、能力不生效”的直接来源，也说明任何“界面显示成功”都不能当作后台可用证据。

# 机制与拒绝条件

## helper 定位 app bundle

- 不再从 argv[0] 推导：以当前进程可执行文件的绝对路径为起点（解析符号链接后），逐级向上查找 `.app`，并要求该目录同时含 `Contents/Helpers/AutomntHelper` 与 `Contents/Info.plist`。
- 保持身份校验：bundle identifier 必须为 `org.automnt.automnt`，可执行文件名必须为 `AutomntHelper`。
- 解析失败：按结构化 `authorizationRequired` 有界退出；不回退容器内同名副本、不扫描其他路径、不尝试启动 GUI、不读系统认证 UI。

## helper 就绪判定（三组证据）

helper 内禁用 SMAppService 查询，改为三组证据同时成立才继续评估：

1. 固定定义校验：解析后的 app bundle 内 `Contents/Library/LaunchAgents/` 的对应定义存在，Label 与模式（基线/恢复）匹配，`BundleProgram = Contents/Helpers/AutomntHelper`，且无 `Program`/`ProgramArguments`；定义模式必须与配置期望（自动恢复开关）一致。
2. launchd 期望身份：进程环境中的 `XPC_SERVICE_NAME` 与配置期望的服务标签一致，证明本次执行来自注册的固定服务，而不是终端直启或其他来源。
3. 已提交 backend-state：owner=app、phase=active、`lastVerifiedServiceStatus=enabled`、generation 与当前配置/状态一致。

App 侧仍以 SMAppService 为真实状态源，负责注册、批准判断与展示；两服务互斥、单 owner、事件触发方式（RunAtLoad、固定 WatchPaths、StartOnMount）与“禁止 KeepAlive/间隔轮询/常驻评估器”均不变。

## 拒绝条件与输出

- 任一组证据缺失即拒绝，且有界退出：不评估、不挂载、不后台索权、不写“已批准”类结论。
- 拒绝原因必须写成结构化状态供 App 显示（待批准/未运行/无法确认），区分“证据缺失”与“系统明确拒绝”，避免继续出现“App 认为已开启、helper 认为待批准”的分裂。
- 不得在未取得三组证据时伪造 `backgroundApprovalRequired` 结论，也不得把“未验证”写成“通过”。

# 回退

- 三组证据无法同时满足时，helper 保持有界退出；前台 App 继续按 SMAppService 显示真实待批准/未运行状态，并提供系统设置与修复入口，不用界面状态掩盖 helper 不可用。
- 若新判定在真实环境被证伪（例如 `XPC_SERVICE_NAME` 在 launchd 上下文中不可靠，或 bundled 定义在真实安装中不可解析），回到“以 App 查询结果为准”的保守路径：App 只展示真实状态并明确提示后台不可用，同时重新裁定判定证据，不引入轮询、第二常驻进程或 GUI 常开作为兜底。
- 修复不得改变注册定义、`BundleProgram` 取值与事件触发方式；若必须改变，先记录影响并单列审批，不擅自扩大范围。

# 验收矩阵

| 编号 | 场景 | 操作 | 通过判据 |
| --- | --- | --- | --- |
| M1 | launchd 触发 | `launchctl kickstart -k gui/$(id -u)/org.automnt.automnt.recovery`（及对应固定 label） | helper 实际启动，退出码 0 语义（有界完成），写出结构化状态；不再因 argv/cwd 或 error 22 退出 1 |
| M2 | 无 GUI 自动挂载 | 退出 GUI，仅保留后台服务，等待/触发事件 | 启用共享真实挂载，真实文件读写成功；无 GUI 进程参与 |
| M3 | 真实重启 | 真实重启 Mac 后登录 | M2 结果再次成立，不依赖手动重试 |
| M4 | 真实重新登录 | 真实注销并重新登录 | M2 结果再次成立 |
| M5 | 失败通知 | 让目标不可达或凭据失效后触发 | 按既有合并/限额投递失败通知，成功轮静默，不重复弹窗 |
| M6 | 单 owner | 上述各轮同时检查 backend-state 与进程 | owner=app/phase=active、无第二 owner、无第二常驻评估进程、无重复挂载 |

表中每项都要记录签名身份、时间、触发来源、实际输出与桌面观察；不得用单元测试、可编译、GUI 在场时的挂载或 `bootstrap` 模拟替代 M2–M4。M1–M6 全部满足才算后台跨登录/重启能力通过。

# 未验证项

- 修复实现、重建签名产物与安装：已于 2026-10-23 第三轮完成（T129–T132）：签名构建安装于 `/Applications/Automnt.app`，`launchctl kickstart` 触发下 helper 通过就绪并完成挂载。
- 真实 launchd 上下文下 `XPC_SERVICE_NAME`：kickstart 触发实测有值且就绪通过；跨重启/重新登录后的稳定性仍未验证（T138）。
- helper 三组证据在真实重启/登录后的稳定性、backend-state 提交时序与 generation 一致性：未验证。
- 挂载与健康：kickstart 触发下两卷真实挂载、background-observations.plist 记录 healthy 已实测（T135/T136）；真实重启/登录后的自动挂载、用户应用真实读写、失败通知端到端投递（T140）与单 owner 观察仍未验证（T138）。
- 旧结论不受影响的部分：界面布局、宽窄窗、推送/返回、sheet 与设置窗口的真实窗口验收（截图 39–44）继续有效，本次不重做；浅色、较大文字、VoiceOver、九语母语审校与商店提交仍未验证。
