**当前规范（2026-10-13；保留方案 A 架构，撤回目录选择例外）**：程序决定并准备固定目录，GUI/CLI 使用真实用户的唯一活动配置及单后台 owner。首次、设置、CLI 共用和恢复均不让用户选择、寻找或手工创建内部目录；之前 NSOpenPanel/父目录选择例外撤回。仅在真实系统授权需要时允许/拒绝，普通应用 alert 不产生沙盒文件权限；免目录选择机制尚未证实，不承诺通用 Allow/Deny API。失败不创建平行配置、不显示零目标、不新挂载或接管，已有快照只读。历史 290 项测试、签名与中文首次窗口不证明当前权限、独立 helper 生命周期、MAS 或九语验收。本轮仅文档，最新规格覆盖旧实现与历史评审。

# 入口与阅读行为

Settings → 帮助 → 支持与隐私，打开原生可滚动 sheet。标题后先显示正文语言选择“中文 / English”，其他界面语言注明正文为中文和英文；切换语言保留阅读入口，关闭回发起按钮。正文离线可读，支持链接和完整政策链接为次级动作，浏览器打开失败给出可复制地址及重试，不阻止阅读。实际地址尚未确定，原型不展示伪链接；T041/T047 必须交付有效地址后验收。

HTML现提供全部四段中文/English候选切换及支持/政策链接失败审阅控件，错误持续可读且重试保留正文。没有正式地址时复制按钮禁用，旁边设计标注说明原因；正式应用只有取得实际地址后提供链接和复制动作，不显示审阅工具。Swift预览现有同样四段双语正文，SDK类型检查通过；真实原生正文布局与系统浏览器/剪贴板行为未验证。

# 中文内容候选

Automnt 在后台自动挂载已配置的 SMB 共享文件夹。需要服务器可达、配置与登录信息有效，并具备实际所需访问权限。退出界面后，已启用的自动挂载仍会继续运行。

Automnt 在本机管理设置，程序准备所需位置，你不需要选择内部文件夹。如果已经使用命令行版本，具备所需访问后会自动显示已有设置，无需导入。需要系统许可时，你可以允许或拒绝；有效权限复用，拒绝不创建另一份设置。权限失效可按实际原因恢复。连接共享使用 macOS SMB 登录及系统保存凭据，无独立密码管理；需要登录时请在 Finder 中连接服务器。密码不写入设置或诊断。诊断由你预览并决定导出，不自动上传；所连接的服务器会处理连接请求。

遇到连接问题，请先在共享详情中查看原因与修复建议。如需寻求支持，可以导出并检查诊断信息，再决定是否发送。发送前请确认内容中没有你不愿共享的信息。不要发送密码。

命令行版本免费开源；Mac App Store 图形版本一次购买。图形版本独立可用，不需要安装命令行版本。许可与第三方声明可从设置的“开源许可”阅读。

# English content candidate

Automnt automatically mounts configured SMB shares in the background when the server is reachable, the configuration and sign-in details are valid, and the required access is available. Enabled automatic mounting continues after you quit the app.

Automnt manages your settings on this Mac and prepares the location it needs. You do not need to choose an internal folder. If you already use the command-line version, existing settings appear automatically once the required access is available, without importing them. When system permission is needed, you can allow or decline it. Valid access is reused; declining does not create another copy of your settings. If access is lost, follow the steps for the reported cause. Connections use macOS SMB authentication and credentials saved by the system, without separate password management. If you need to sign in, connect to the server in Finder. Passwords are excluded from settings and diagnostics. You can review diagnostics and decide whether to export them. Diagnostics are not uploaded automatically. The server you connect to processes the connection request.

For connection problems, open the share details to review the cause and suggested steps. If you need support, export and review diagnostics before deciding whether to send them. Check for information you do not want to share. Do not send passwords.

The command-line version is free and open source. The Mac App Store app is a one-time purchase and works without installing the command-line version. Open Source Licenses in Settings provides license and third-party notices.

# 定稿与资源缺口

以上为设计候选，不冒充发布的法律政策或已实现能力。Automnt 暂时保留为显示名；维护者质疑此前品牌来源，品牌尚未最终确认，不新增“自动挂载助手”。sandbox/helper 复用系统凭据未验证，已有访问、CAS 和 owner 协调本地实现，但免目录选择机制、跨身份访问与完整实际闭环未证实；中英文候选须在能力实证后再定稿。正式支持联系方式、政策 URL、运营方身份、数据收集/保留/删除声明及第三方服务说明须以实际实现和发布主体核对，由 T041/T047/T048 落实。不得根据候选文字提前填写 App Store 隐私申报。中英文须可靠复核。

资源语境：help.bodyLanguage；四段顺序为support.purpose、support.dataHandling、support.help、support.product；链接为support.openSupport、support.openPolicy、support.linkFailure、support.copyAddress；正文按完整段落本地化，不在代码拼接句子。链接错误需要可访问的持续反馈。

# 全产品帮助覆盖

原生 Help 与 About 及设置支持入口提供离线用途/自动恢复条件、首可达服务器顺序、直接排序撤销、单共享兜底与刷新区别、退出仍后台运行、移除不弹出、程序准备设置、真实许可允许/拒绝及按原因恢复（首次/设置/恢复均不选择或寻找内部目录）、系统认证、后台许可、通知授权/声音、共享重试及升级/显式接管说明。支持/许可正文离线可读，诊断先脱敏预览再主动导出；不要求应用自定义语言/外观设置，不声称九语客服。

正式文本须在系统认证、透明 CLI 配置和 owner 协调实证后定稿，候选说明不能用来宣称实现通过。


# 授权候选与当前资料边界

产品正文为待实证候选，不证明已有免目录选择 API。当前 Apple [App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)、[user-selected entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-write)、[helper](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app) 和 [App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups) 资料支持已核查的沙盒/用户选择/helper 身份及组配置边界，未证明对现有外部固定目录通用持久 Allow/Deny。2018 归档指南不作当前机制证明，普通 alert 不授予访问，组容器不自动解决独立 CLI 身份。未来 T083/T084 验机制与影响，T093 验真实后台，T091/T094 复核正文及全界面九语。正式支持/法律/政策 URL、主体及数据声明未确认，不以候选填写商店申报或宣称 MAS通过。T083–T094 已追加至[主任务清单](../tasks.md)，全部未完成；本文件引用其编号，不表示实现或验收通过。依次覆盖授权架构、统一访问、图标、发现合并、编辑 CAS/dirty/身份、实际退出草稿、生命周期刷新、无选择/窄导航、字段校验文案、owner 中断恢复、真实后台矩阵和全界面原生九语验收。
