# 本轮范围与结论

**最新裁定（2026-10-13，优先于下文历史面板流程）**：保留方案 A 固定目录、GUI/CLI 共用及单 owner；撤回首次/恢复内部目录选择。程序确定目录，必要许可用户只决定允许或拒绝，实际合法访问机制仍待当前 Apple/SDK 验证。本轮仅同步文档与 T083–T094，不修改代码或资产、不测试/构建/启动。下文 NSOpenPanel、临时父 scope、子书签和相关验收步骤均属此前交互的历史记录，不作为新流程要求或通过依据。290 项测试、签名构建和中文窗口只保留原范围；最新规范见 [spec.md](../../specs/005-swiftui-mas-gui/spec.md)、当前资料见 [research.md](../../specs/005-swiftui-mas-gui/research.md)。

2026-10-13，维护者在方案 A 文档修订后授权继续 Feature 005 Implement。下文保留此前本地固定配置权限、访问状态、独立 helper 预检、签名构建与 289 项测试的原始证明范围。旧签名应用曾启动并捕获未授权窗口；维护者随后拒绝其完整内部路径与似乎更改存储位置的首次体验，因此旧截图仅为历史记录，不是当前交互验收。当时交互代码、九语资源、签名构建和中文首次窗口已更新并核对；历史最终门禁及窗口记录见下文，仍包含已撤回的目录面板。系统面板授权、过滤/验证/目录准备、已有目标及 helper 跨进程持久访问尚未实测，T079–T082 保持未勾选。

版本仍为 3.4.0。未递增版本、提交、推送、创建 Release 或提交商店；未替换已安装的 CLI 服务。历史 CLI SMB 成功证据不证明本轮 GUI/helper 的目录访问或系统认证能力。

# 固定目录与失败保护

[PermissionStore](../../Sources/AutomntPlatform/PermissionStore.swift) 使用 getpwuid/getuid 确定真实用户目录，固定解析 `~/Library/Application Support/automnt`。不使用沙盒 HOME 或 App Group 作为业务配置回退；拒绝其他目录、符号链接、其他所有者及不足的目录访问权限。系统目录面板授权后保存自身 security-scoped bookmark，复用时不打开系统面板，并在持有有效 scope 时更新可更新的 stale bookmark。

[应用模型](../../apps/Automnt/AutomntApp.swift) 与 [访问状态](../../Sources/AutomntCore/ConfigurationAccessState.swift) 区分待授权、取消、错选、目录缺失、stale、revoked、读取失败、成功和已授权无配置。只有确认目录仍有效且配置文件不存在时，才进入无配置状态；丢失目录/锁不能误报为零目标。读取失败保留上次快照并限制写入和新挂载。成功首次保存后进入 ready。通知声音偏好仍位于同一授权目录的独立文件，保存失败恢复界面值。

[主窗口](../../apps/Automnt/Views/MainWindowView.swift) 的授权内容可滚动，按钮在宽度不足时纵向重排；排序拖放、键盘移动、撤销、添加和完整评估均核对可修改状态。刷新重读真实配置及其 revision，不触发挂载。[设置与菜单栏](../../apps/Automnt/Views/DetailViews.swift) 使用同一权限条件；未成功读取时提供授权入口，不呈现首次添加空态或可编辑旧参数。离线中英文隐私说明同步首次固定目录授权。

# 独立 helper 权限预检

[HelperPermissionProbe](../../Sources/AutomntPlatform/HelperPermissionProbe.swift) 与 [独立授权 LaunchAgent](../../apps/Automnt/Resources/LaunchAgents/automnt.authorization.plist) 通过 SMAppService 执行两个阶段：首次 invocation 接收 implicit bookmark 并生成 receiver-owned 持久书签；unregister 后第二次 invocation 的 transfer payload 为空，只能依靠 helper 自身持久书签读取相同配置 revision。两阶段均不执行挂载或改 owner。请求/回执限制大小、schema、随机 token、revision 及有效期，稳定锁避免并发覆盖，错误返回后执行有界协议清理。

后台启用和 owner 接管之前调用此预检。旧 `--probe-background-registration` 诊断已改为复用该检查；旧 App Group 注册票据及“已有配置就拒绝探测”分支已移除，正常 helper 不再消费该旧票据。

以上为代码接通，不能据此宣称 launchd 已实际重新启动 helper、receiver-owned 书签能跨进程/登录/重启使用、系统后台许可已批准，或后台已成功访问 SMB 文件。

# 本地门禁证据

| 检查 | 历史实现结果 | 证据与边界 |
| --- | --- | --- |
| Swift tests | exit 0，87 + 178 + 24 = 289 项通过 | [最终测试日志](../../.build/option-a-final-tests.log)，覆盖已有核心/平台/CLI 回归及新增配置访问条件；不替代原生授权实测 |
| 签名 Release 构建 | exit 0，BUILD SUCCEEDED | [最终构建日志](../../.build/option-a-final-xcode.log)，macOS 27，Apple Development，team TEAMID1234 |
| 签名、entitlements、嵌套 seal | 通过 | verify-signature 检查 app/helper/worker 的 Apple 身份、同 team、精确 sandbox 声明和 helper 内嵌身份；不启动 executable |
| 九语资源 | 通过，252 source strings / 333 catalog keys | 九语非空、品牌/隐私及通知复数检查通过；新增非英文授权文案为 draft，仍须可靠审校 |
| Swift 6 结构门禁 | 通过 | 35 LockedBox carriers / 34 accessors / 1 atomic publication；不是死锁或压力测试证明 |
| git diff --check | 通过 | 无补丁空白错误；不代表所有未跟踪 Feature 文件已有提交 |
| 未授权的签名原生诊断 | exit 1，authorization-probe failed | [诊断日志](../../.build/option-a-native-authorization-probe.log)；当前尚无可用权限，因此未能验证 helper 持久访问，不将该失败记为预检通过 |
| 原生启动和中文未授权窗口 | 历史启动记录；UX 被维护者拒绝 | 最新签名 app 的真实进程路径与构建产物一致；直接捕获 Automnt 窗口，见 [窗口截图](../../.build/option-a-authorization-window.png)。旧图显示固定真实路径、允许访问/稍后按钮、后台“无法确认”；未显示已管理 0/首次添加空态，添加与完整评估不可用。完整路径及文件夹选择式首次体验已被维护者拒绝，此图不代表更新后页面或本轮 UX 通过 |

构建仍有既有 String(cString:) 弃用、签名 executable 不再 stripping 及无 AppIntents dependency 的提示；无本轮编译错误。

# 旧目录面板方案的待验收记录（最新步骤见 quickstart）

1. 更新代码、资源、签名构建和新“开始使用 Automnt”ContentUnavailableView 已记录于下文；首次/取消为“继续…”，错误恢复为“允许访问…”，日常工作流无内部路径、位置字段或手工创建指令。随后由维护者操作真实 NSOpenPanel（prompt “Allow Access”），验证正常导航、shouldEnable 和 validate 对目标/固定父目录的筛选及拒绝错误确认。系统面板自身可能显示路径，不承诺无面板或完全无路径。目录缺失分支验证临时父 scope、程序仅创建固定 automnt（0700）、仅持久化收窄子书签并释放父 scope；无需手动 New Folder，不在 app 添加功能前写业务配置。新首次窗口已核对；系统面板、目录准备与授权后的上述原生行为未验证。
2. 读取真实程序生成的 CLI 配置，核对目标、顺序、未知字段和同一 canonical 文件；重启 GUI 后核对自身书签复用。不得手写测试业务配置。
3. 运行两阶段 launchd helper 检查，记录 SMAppService 实际许可、bind/verify 结果和空 transfer 的第二次独立读取，再按唯一 owner 协议启用后台。
4. 实测 GUI 退出后访问、真实登录/重启、升级签名连续性、后台 SMB 挂载及文件读取；不得以 bootstrap 或容器 CRUD 代替。
5. 复验损坏/stale/revoked、读取失败、CLI/GUI CAS 并发、稳定锁 inode、通知声音持久性，以及九语窄窗/较大文字/浅深色/键盘/VoiceOver。

除下文记录的本地门禁与中文首次窗口核对外，这些运行项目未执行，保持待验收，不宣称 Feature 005 或方案 A 全链路完成。

# 历史首次交互基线与记录责任

当时页面表达用户任务：标题“开始使用 Automnt” / “Get Started with Automnt”，解释读取和保存自身设置，已经配置的共享自动出现。有效书签静默复用；取消仍未授权，无零目标统计、业务写入、新挂载或后台接管。访问记录需更新、权限失效和读取错误自然说明各自情况；不显示后台引擎协议。显式诊断/支持调查才可按需显示内部路径。固定真实 `~/Library/Application Support/automnt/automnt.plist` 单一存储不改变，父目录授权仅准备固定子目录，不更改位置。

资料、版本及限度见 [体验契约](../../specs/005-swiftui-mas-gui/contracts/experience-design.md#官方资料与证据限度)：Apple File System Programming Guide 的 2018-04-09 归档要求内部文件避免干扰用户；当前 App Sandbox 文档 JSON 于 2026-10-13 获取，确认容器与用户选择扩展权限的区别；NSOpenSavePanelDelegate API 支持筛选/验证，不保证固定不可浏览面板；Alfred 位置选择仅属于明确高级同步用例，不证明 MAS 相同沙盒。

上述历史测试表和旧截图保留原范围。以下为修订后的本地证据；系统面板确认、目录准备、持久授权和 helper 闭环仍待真实操作，T079–T082 保持未勾选。

# 修订后的本地实现与真实窗口

2026-10-13，首次页已使用原生 ContentUnavailableView：“开始使用 Automnt”、读取/保存设置及已有共享自动显示的用途、“继续…”和“稍后”。主窗口不显示内部完整路径或配置位置控件，设置和菜单不再使用配置文件夹选择式入口。NSOpenPanel 的标题和确认表达访问设置，禁止手工 New Folder；delegate 保留祖先导航，仅允许固定目录或准备所需固定父目录的确认。程序仅准备固定子目录，在临时父 scope 内重新解析新子目录书签并激活收窄的子目录 scope，再释放临时父 scope；不写业务配置、不持久化父书签。这些为已接通的代码行为，原生面板及创建分支仍未实测。

| 检查 | 历史修订结果 | 证据与限度 |
| --- | --- | --- |
| 最终 Swift tests | exit 0，88 + 178 + 24 = 290 项通过 | [测试日志](../../.build/option-a-interaction-final-tests.log)；新增错误父目录拒绝且不保存书签测试，不模拟系统授权 |
| 最终 Apple Development Release | exit 0，BUILD SUCCEEDED | [构建日志](../../.build/option-a-interaction-final-xcode.log)；包含最后的子目录 scope 激活和设置/菜单入口修订 |
| 签名及 sandbox | app/helper/worker 均通过 | verify-signature.py 校验 Apple 身份、同 team、精确 entitlements 与嵌套 seal；不证明实际授权 |
| 九语资源 | 258 source strings / 347 keys；九语完整性通过 | 14 个新授权资源均有九语值；语言质量、长译文和 VoiceOver 仍待复核 |
| Swift 6 结构门禁 | 通过，35 carriers / 34 accessors / 1 atomic publication | 与历史同一边界，不证明无死锁 |
| 实际中文首次窗口 | 已启动并直接捕获/查看，900 × 620 点 | [新窗口截图](../../.build/option-a-start-window.png)；CoreGraphics 记录窗口 4680/PID 43129；通过明确构建产物路径启动并直接捕获；未另行核验该 PID 可执行路径，随后查询进程已不存在。无内部路径、位置选择、手工创建指令或已管理 0；未自动点击继续或授予许可，不代表交互验收获批 |
| 补丁空白检查 | git diff --check 无输出 | 不提交或推送；Feature 未跟踪文件需按各自实际内容复核 |

本轮没有替换业务配置、递增版本或对外发布。曾启动并核对真实中文首次窗口；后续交互需重新打开签名构建产物。
