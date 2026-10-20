**当前规范（2026-10-13；保留方案 A 架构，撤回目录选择例外）**：程序决定并准备固定目录，GUI/CLI 使用真实用户的唯一活动配置及单后台 owner。首次、设置、CLI 共用和恢复均不让用户选择、寻找或手工创建内部目录；之前 NSOpenPanel/父目录选择例外撤回。仅在真实系统授权需要时允许/拒绝，普通应用 alert 不产生沙盒文件权限；免目录选择机制尚未证实，不承诺通用 Allow/Deny API。失败不创建平行配置、不显示零目标、不新挂载或接管，已有快照只读。历史 290 项测试、签名与中文首次窗口不证明当前权限、独立 helper 生命周期、MAS 或九语验收。本轮仅文档，最新规格覆盖旧实现与历史评审。

# 文案语境与本地化基线

本轮文案原则与完整界面语言已接入本地九语应用资源，发布级语言审校与原生布局验收尚未完成。以中文候选说明含义，各语言按该语种 macOS 表达习惯独立组织。英文示例为候选，其他语言不提供未经审校的硬译。原型仅中文；任何语言均未宣称通过母语审校。

已建立 [语义资源清单](copy-resources.md)，按导航、目标动作、服务、设置、主界面、单行添加、完整 SMB URL、状态、系统认证、确认、通知、辅助功能、商店与支持记录稳定ID和候选语境。尚需对照全部可达验证/系统错误分支补齐，九语成品和实际布局未完成；不将机械抽取或清单存在计为T060通过。

# 核心文案候选

| 资源语境 | 简体中文候选 | English candidate | 含义与边界 |
| --- | --- | --- | --- |
| 自动化开关名称 | 自动挂载 | Automatic mounting | 控制未来自动挂载，不卸载现有共享 |
| 恢复开关名称 | 自动恢复 | Automatic recovery | 独立全局 auto_mount_recovery；关闭仍保留登录/网络自动挂载 |
| 恢复辅助说明 | 共享意外断开后，额外响应卷宗变化尝试恢复。关闭后，仍在登录或网络变化时自动挂载。 | Respond to volume changes to try restoring disconnected shares. When off, automatic mounting still runs at login and when your network changes. | 不保证所有断开必有事件；主动弹出抑制不变 |
| 服务器开关 | 自动挂载此服务器的共享 | Automatically mount shares on this server | 仅该服务器后续参与；已有挂载保留 |
| 共享开关 | 启用此共享文件夹 | Enable this shared folder | 仅该共享后续参与；已有挂载保留 |
| 登录菜单开关 | 登录时显示菜单栏 | Show menu bar at login | 独立默认关闭的主应用登录项；不展开主窗口，不改变 helper |
| 关闭后辅助说明 | 已经挂载的共享文件夹仍可使用。 | Shared folders that are already mounted remain available. | 独立 secondary 说明，不能塞进动作括号 |
| 菜单关闭动作 | 关闭自动挂载 | Turn Off Automatic Mounting | 动作，区别于开关名称与状态 |
| 运行说明 | 退出 Automnt 后，已启用的自动挂载仍会继续运行。 | Enabled automatic mounting continues after you quit Automnt. | 退出结束界面/菜单，后台原状态不变 |
| 手动连接 | 挂载 | Mount | 技术概念已熟悉，不加“快捷” |
| Finder 打开 | 在 Finder 中打开 | Open in Finder | 打开已核对挂载目录；不是在父目录中选中该项，不猜路径 |
| 弹出动作 | 弹出 | Eject | 非强制；忙碌失败不转强制 |
| 弹出失败 | 共享文件夹正在使用，无法弹出。请关闭相关文件后重试。 | The shared folder is in use and can’t be ejected. Close any files you’re using, then try again. | 可操作下一步，避免“普通卸载失败” |
| 已弹出说明 | 重新登录或网络环境变化前，Automnt 不会自动挂载此共享。你也可以现在重新挂载。 | Automnt won’t mount this share automatically until you log in again or your network changes. You can mount it now if you need it. | 用户可见条件，不露出“会话抑制” |
| 离线说明 | 服务器暂时无法连接。网络变化后，Automnt 会再次尝试挂载。 | The server is unavailable. Automnt will try mounting again when your network changes. | 不将离线当密码错误，也不保证服务器恢复必有即时事件 |
| 登录失败 | 未能通过服务器认证。请先在 Finder 中连接此共享并完成登录，再重试。 | Server authentication failed. Connect to this share in Finder and sign in, then try again. | 仅用于对应结构化错误 |
| 保存冲突 | 设置已在其他地方更改。重新载入后，请检查你的修改再保存。 | These settings have changed elsewhere. Reload them, then review your changes before saving. | 不覆盖；失败保留编辑草稿 |
| 删除确认 | 移除此共享文件夹？ | Remove This Shared Folder? | 仅移除应用管理配置 |
| 删除说明 | Automnt 将不再自动挂载此共享。已经挂载的共享仍可使用，服务器上的文件不会删除。 | Automnt will stop mounting this share automatically. Mounted shares remain available, and files on the server won’t be deleted. | 明确配置/挂载/远端文件三个后果 |
| 通知 | {count} 个共享文件夹未能自动挂载。打开 Automnt 查看详情或重试。 | {count} shared folders couldn’t be mounted automatically. Open Automnt to review or retry. | 按语言 plural 资源；1 的英文单数另写；不含私有名称/地址/路径 |
| 草稿退出标题 | 要保存修改吗？ | Save Your Changes? | 按钮分别取消退出、放弃并退出、保存并退出 |
| 诊断说明 | 导出前可以查看内容。诊断信息不会自动上传。 | Review the contents before exporting. Diagnostics aren’t uploaded automatically. | 导出预览与真实用户动作，不承诺未决定的保留策略 |
| 通知声音开关 | 通知声音 | Notification Sounds | 默认开启；关闭后续声音请求，不关闭通知 |
| 声音辅助说明 | 关闭后，仍会收到通知。开启时，提醒声音仍由系统设置控制。 | You’ll still receive notifications when this is off. When it’s on, sounds also depend on your system settings. | 不保证开启必响；不覆盖系统静音或专注模式 |

# 数量、变量与复数资源

失败通知只在当轮核对后的失败共享数量 N > 0 时投递；N = 0 不生成失败通知，也不使用“0 个失败”的占位句。前台失败摘要为零时使用独立空状态“当前没有挂载失败的共享文件夹”，仍需按语言自然翻译。N 来自核心结果，不按通知历史累加。

下表约束非负整数共享数量的 String Catalog 资源分支；类别由系统 locale 规则选择，不在业务代码中自行判断。每个分支保存完整句子，其他变量使用带类型的格式参数。实际资源须以当前系统规则复验，表中类别不等于译文已通过审校。

| 语言 | 整数数量类别 | 资源要求 |
| --- | --- | --- |
| en | one（1）、other | 单数与复数句分别提供 |
| zh-Hans、zh-Hant | other | 数量与量词按完整句表达，不增加英语式复数 |
| ja、ko | other | 使用自然数量表达与量词，不套用英语单复数 |
| de | one（1）、other | 名词及相关语法随数量变化 |
| fr | one（0、1）、many（正整数百万倍数）、other | 0 只用于适用的界面计数；失败通知不投递 0；包含大数量分支 |
| es | one（1）、many（正整数百万倍数）、other | 单数、通常复数及大数量分支分别复核 |
| pt-BR | one（0、1）、many（正整数百万倍数）、other | 使用巴西葡萄牙语规则；0 不用于失败通知 |

2026-10-08 已核对 [Unicode CLDR 48 官方基数规则](https://www.unicode.org/cldr/charts/48/supplemental/language_plural_rules.html)，上述普通整数分支一致；巴西葡萄牙语使用 pt 规则，区别于 pt_PT。此证据不代替 macOS 27 String Catalog 的实际分支验证。

T030/T036 检查 N = 0、1、2、较大值与 1,000,000：核对系统分支、数字格式、完整句子及布局。长共享名称、地址、路径保留用户原文；不拼接语句或将用户值用作格式串。通知仅含数量，不加入私有目标信息。

# 九语术语候选基线

以下是设计阶段供逐语审校使用的候选映射，尚未通过九语母语审校或 macOS27 系统界面逐项对照。术语按对象和动作语境使用，不机械替换句中所有词；各语言完整句仍须独立组织。SMB、Spotlight、Automnt 保留原文。资源对应 `setting.automation` 等自动挂载语义、`target.*` 动作和 `state.*` 结果，以 copy-resources.md 实际ID为准。

| 语言 | 共享文件夹 | 挂载（动作） | 自动挂载 | 自动恢复 | 弹出 | 停用（配置） | 访问权限 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| en | Shared folder | Mount | Automatic mounting | Automatic recovery | Eject | Disable | Access permission |
| zh-Hans | 共享文件夹 | 挂载 | 自动挂载 | 自动恢复 | 弹出 | 停用 | 访问权限 |
| zh-Hant | 共享檔案夾 | 掛載 | 自動掛載 | 自動復原 | 退出 | 停用 | 存取權限 |
| ja | 共有フォルダ | マウント | 自動マウント | 自動復旧 | 取り出す | 無効にする | アクセス権 |
| ko | 공유 폴더 | 마운트 | 자동 마운트 | 자동 복구 | 추출 | 비활성화 | 접근 권한 |
| de | Freigegebener Ordner | Verbinden | Automatisches Verbinden | Automatische Wiederherstellung | Auswerfen | Deaktivieren | Zugriffsberechtigung |
| fr | Dossier partagé | Monter | Montage automatique | Rétablissement automatique | Éjecter | Désactiver | Autorisation d’accès |
| es | Carpeta compartida | Montar | Montaje automático | Recuperación automática | Expulsar | Desactivar | Permiso de acceso |
| pt-BR | Pasta compartilhada | Montar | Montagem automática | Recuperação automática | Ejetar | Desativar | Permissão de acesso |

“挂载”指共享卷在本机可访问；“弹出”指非强制移除当前挂载，不删除远端文件；“停用”只改变未来参与自动挂载的偏好。恢复说明必须包含触发范围与主动弹出例外，不能翻译成无限或即时保证。德语候选 Verbinden 须在共享挂载与一般网络连接语境中验证是否产生歧义；繁体、日语、韩语动作须与目标系统真实用语复核。T060以正式术语与全界面关键资源审校验收，表存在不计为完成。

# 九语审校安排与缺口

首发资源：en、zh-Hans、zh-Hant、ja、ko、de、fr、es、pt-BR。每种语言需建立独立 String Catalog 翻译与上下文；通知按数量处理单复数，不拼接句子。文案结构可变化，产品行为和承诺不可变。跟随系统应用语言，不添加应用内语言开关。

当前状态：en、zh-Hans、zh-Hant、ja、ko、de、fr、es、pt-BR 的应用资源均已集成，历史目录面板实现的 14 个授权键均有九语值；完整性门禁通过（258 source strings / 347 catalog keys），机器草稿未获可靠审校。全部九语的 macOS 27 实际界面术语对照、母语审校和长文本/VoiceOver 验证未完成。T060 不勾完成；T030/T036/T045 对应真实资源、系统预览和商店语言。

后续审校覆盖导航、菜单、设置、主界面与单行添加、错误、确认、通知、辅助功能标签和商店材料。记录每条字符串的出现位置、当前情况、动作结果、长度约束和变量；日德等语言不以截断关键后果换取原版宽度。品牌 Automnt 保持不翻译；SMB 等协议名保持准确；共享文件夹/卷宗的对象语义须各语种系统术语核对，不能机械统一逐词替换。

待补逐条资源清单：导航与工具栏、本机已挂载共享分组、添加/完整 SMB URL 输入与验证、各状态与服务异常、逐共享菜单与全局菜单、系统认证说明与 Finder 下一步、排序冲突、设置帮助正文与诊断导出、退出确认、通知、辅助功能名称/状态/提示、商店与支持正文。每条须有稳定资源ID、出现位置、用户语境、动作结果、完整候选句、类型化变量/复数、辅助功能及布局策略；设计标注/模拟触发器独立排除。当前核心表不是全界面完成清单，机械抽取不替代语境审校，T060保持未完成。

名称可用性、商标和 App Store 名称审核尚未完成。本文件是设计内容规范，不是额外审批状态机。

# 本轮新增语境

宽窗左侧平铺服务器名和“已管理 N / 可添加 N / 异常”摘要，计数使用完整复数资源；右侧选中服务器标题、开关“自动挂载此服务器的共享”与独立后果说明，紧凑组为“已管理”和“可添加”。共享行仅名称/状态/Finder或修复或添加主动作，URL/路径/索引/编辑/移除在按需 sheet；工具栏完整 SMB URL（fullURL）入口与次级 Finder 空状态说明分开。窄窗服务器→共享→详情和原生返回标签须按九语实际系统用语复验，长名称、计数与主动作不可互相挤掉，选择/焦点/滚动保持。每行“添加”立即保存一个共享。Finder“连接服务器…”为次级空状态指导；工具栏“输入 SMB 地址…”接受完整 URL。系统认证说明不承诺沙盒/helper 已能读取系统凭据；程序准备固定目录并具备所需真实访问后自动呈现已有 CLI 配置是目标，不让用户选择内部目录，共享配置与所有权协调已有本地实现，真实闭环仍未验证。保存成功关闭编辑器或以已保存值重置 draft/baseRevision/dirty；失败保留草稿，非活动窗口字段仍可编辑。

Spotlight 说明同时表达减少磁盘与网络索引活动和共享内容搜索受限；实际效果未验证，不自动删除已有索引。Automnt 为临时名称且来源受质疑，不另造中文品牌。

# 全产品资源补充

废弃“保存顺序/保留排序草稿”的产品文案；当前使用移动、撤销、顺序已保存/无法保存/已在其他地方改变，直接拖放与键盘移动共用语义。管理/发现组名称与首共享追加结果、完整评估/刷新/单共享操作、实际后台状态、配置保存与可用性分别建立资源。普通弹出不例行确认，移除仍明确不弹出及最后共享移除服务器。

名称行内确认、成组地址/路径提交、详情信息顺序、共享 retry_policy、实际通知授权/独立声音、原生 About/Help、离线支持/许可和最新失败摘要均纳入九语语境审校。应用跟随系统语言与外观，不提供自定义语言或主题选择。所有新增文案仍为审校候选；九语应用译文已集成，可靠语言审校与原生布局验收未完成。

# 方案 A 授权术语与范围

configAccess.* 使用“开始使用 Automnt” / “Get Started with Automnt”任务标题，解释设置保存在本机、已有共享自动出现，不要求用户理解内部目录。固定目录缺失由程序启动时自行准备，不作为错误。只有实际读取/校验失败才显示“无法打开 Automnt 的设置”，主动作“重试” / “Try Again”，不使用“允许访问 / 配置文件夹 / 权限”等系统或内部术语。首次无配置的详情区为“欢迎使用 Automnt” / “Welcome to Automnt” + 一句用途 + “添加共享文件夹…”。状态使用“自动挂载”而非“后台挂载”，使用“检查”而非“一轮”。九语保持用途、状态与行为承诺一致，并逐语检查按钮 intrinsic width、长译文换行与窄窗；德语“Erneut versuchen”等长标签不得截断。

首次、主窗口、设置、菜单及恢复支持均无内部路径、位置字段、选择/更改/导入或查找/手工创建指导，不用 folderPath/folderName 参数。程序准备位置；显式诊断可显示路径。stale/revoked 分别表达恢复访问与无法访问，读失败给自然原因与重读，拒绝不成零目标，不提书签/bind/verify。配置访问、后台运行、SMB 认证、挂载位置及通知许可独立。完整候选见[资源清单](copy-resources.md)，历史结构门禁/中文首次窗口不证明可靠语言审校或九语原生通过。未来 T084/T091/T094 验统一访问、精确字段错误、全界面九语可靠审校/长变量/宽窄窗/大字/浅深色/键盘/VoiceOver/拒绝保存退出焦点。T083–T094 已追加至[主任务清单](../tasks.md)，全部未完成；本文件引用其编号，不表示实现或验收通过。依次覆盖授权架构、统一访问、图标、发现合并、编辑 CAS/dirty/身份、实际退出草稿、生命周期刷新、无选择/窄导航、字段校验文案、owner 中断恢复、真实后台矩阵和全界面原生九语验收。


# 窗口与发现服务器交互补充（2026-10-20）

发现服务器是首屏主路径：可添加服务器行必须可选中并在详情区提供逐行添加，不得让欢迎/手动地址输入覆盖已发现目标。完整 SMB 地址输入仅作为兜底。主窗口与设置窗口分别记忆尺寸/位置；设置窗口默认比例调整为 680×620，避免扁宽居中跳变。相关文案仍按九语审校。


# 设置文案语气补充（2026-10-20）

登录项与通知文案以用户收益和触发场景为主，不写“只对失败发送、正常不发”的免责句；声音说明写成“关闭后仍会收到通知，只是没有提示音”。登录项错误给“退出并从应用程序重新打开 → 检查一次”，不保留无上下文的“检查登录设置”。通知权限状态用“未开启/已允许/已关闭/暂时无法读取”。九语同步，按钮改为“检查一次/Check Again”。


# 自动挂载层级术语（2026-10-20）

“自动挂载”不能同时指总开关和服务器参与：服务器级统一“参与自动挂载”，全局统一“自动挂载总开关/开启自动挂载”。总开关关闭时用“总开关已关闭，开启后才生效”，不让已勾选的服务器看起来已经在自动挂载。启用入口使用详情区卡片，状态栏只陈述事实。九语保持同一层级。


# 后台状态文案原则（2026-10-20）

后台状态不使用“操作无法确认”这类内部结果；按“发生了什么 + 不会发生什么 + 下一步”表达。失败用“没有完成/没有完全关闭”，恢复动作用“修复后台挂载”；等待系统用“等待系统允许”；命令行用“由命令行版本管理”。状态卡标题与按钮分开，标题不复述按钮。
