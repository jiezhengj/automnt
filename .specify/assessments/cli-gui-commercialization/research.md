# 研究范围与证据等级

- **Slug**: cli-gui-commercialization
- **Revised**: 2026-10-07T21:16:00+08:00
- **Evidence confidence (overall)**: medium
- **输入**：[intake](intake.md)、维护者直接体验、现有产品文档、2026-10-07 实际读取的 Apple 官方文档和竞品商店正文。
- **研究目标**：判断自动挂载 GUI 的商店买断发行是否有可信平台路径和付费市场先例；不以公开研究冒充 automnt 的运行测试或上架批准。
- 用户要求“进一步调研，以彻底判断是 go 还是 kill”，授权继续修订已有 Assessment 产物。

# 用户与需求

- 维护者直接报告文件任务因 SMB 卷宗未挂载先失败，再手动去 Finder 连接。核心需求是配置后自动就绪与恢复，不是终端操作替代。来源：[intake](intake.md)、[产品背景](../../../README.zh.md)；confidence: high，cited，针对直接体验。
- [AutoMounter 中国区商店正文](https://apps.apple.com/cn/app/%E8%87%AA%E5%8A%A8%E5%AE%89%E8%A3%85%E5%99%A8/id1160435653?mt=12)明确宣传自动挂载网络共享、卸载后快速重新挂载、WiFi/VPN 挂载规则。说明已有厂商围绕同类需求提供收费产品；confidence: high，cited，针对公开产品与价格，非效果实测。
- 该页面有用户在 2024-11-02 表示使用后购买支持开发者；另有 2023-10-08 更新后不能使用、2025-07-06 锁屏恢复后 SMB 不可用的评论。付费与可靠性需求均有独立于维护者的陈述信号，但评论不可核验交易和运行过程，也不能代表总体用户；confidence: medium，cited，self-report。
- 中国区页面明确提示评分不足，不能从此推算活跃用户、销量或市场总量。automnt 自身转化率与付费意愿仍无直接测量；confidence: high，cited，针对缺少数据。

# 先例与竞争

- AutoMounter 中国区标价 **¥68.00**，另有 **¥28.00 专业版设置内购**。自动挂载和快速恢复列在基础功能；专业版增加挂载后打开文件、运行脚本和托管配置等。来源：同一商店页；confidence: high，cited，2026-10-07 读取的中国区价格，不能直接当作美元价格或 automnt 最优价。
- 页面披露挂载到 `/Volumes` 和自定义位置需要帮助程序。版本 1.12.0 的记录称 macOS 26.4 改变了 `/Volumes` 外挂载行为：默认 User Library Folder 可能触发系统确认，安装 Helper 后将挂载转到 `/Volumes` 避免该确认。当前 1.14.1 记录 macOS 27 支持、重复挂载及超时修复。来源：同上；confidence: high，cited，针对厂商公开记录，尚未实际安装验证。
- 因而已有商店自动挂载产品，且当前系统下继续维护；但先例不能证明 automnt 可以把现有 CLI 直接打包上架，也不能证明竞品 Helper 的权限、来源、审核理由和内部实现。后者仍未知。
- [Mountain Duck 购买页](https://mountainduck.io/buy/)可读取：按用户席位销售，许可证限定一个 major version，未来大版本提供升级折扣。页面文本出现 50、币种 $/€，但文本抽取不足以确认默认币种与完整最终结算，不使用它给出精确可比美元售价。它是相邻挂载产品，协议和产品模式不同；confidence: high，cited，针对许可范围；价格可比性 low。
- 免费 CLI 已有预编译分发和后台自动化，MIT 允许再分发。这对 GUI 定价形成替代压力，不代表无人购买商店产品。来源：[产品文档](../../../README.zh.md)、[LICENSE](../../../LICENSE)；前半 confidence: high，cited；购买影响 ASSUMPTION，confidence: medium。

# Apple 平台与发行要求

## 后台自动运行

- [App Review Guidelines 2.4.5](https://developer.apple.com/app-store/review/guidelines/)要求 Mac App Store 应用适当沙盒化；禁止未经同意的启动、登录运行和退出后持续进程。条文不是全面禁止用户同意后的后台运行；confidence: high，cited，针对条文，非审核保证。
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice.md)明确可管理 bundle 内的 LoginItems、LaunchAgents 和 LaunchDaemons。它替代手动安装 LaunchAgent plist 的方式。
- [register()](https://developer.apple.com/documentation/servicemanagement/smappservice/register().md)说明 LoginItem helper 会立即启动和后续登录启动；LaunchAgent 注册后立即 bootstrap 并在后续登录 bootstrap；未经用户批准会报错。confidence: high，cited。
- 这为“首次设置时授权，之后不逐次点挂载”提供正式后台运行机制。关闭设置窗口不应混淆成撤销后台授权；真正退出/停用必须尊重用户意图。产品具体退出语义留待规格。平台路径推导为 ASSUMPTION，confidence: medium，尚非 automnt 验证。

## 沙盒、网络与文件权限

- [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox.md)明确 Mac App Store 必须启用沙盒。
- [network.client](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client.md)允许沙盒应用建立到服务器的出站连接；这支持 TCP 探测的权限路径，但**不能据此推导 NetFS 挂载、强制卸载或 Keychain 访问已经获准**。confidence: high，cited。
- [用户选择文件读写权限](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-write.md)以用户在 Open/Save 对话框选择为依据，不是任意访问现有 CLI 配置路径的授权。confidence: high，cited。
- 2.4.5 同时要求商店应用不请求 root 提权或 setuid；通过商店更新；不可下载安装独立应用或附加代码来新增功能。**SMAppService 不解除沙盒，也不构成使用不受限 Helper 的通行证。** helper 是否合规必须逐项核实，不能拿竞品存在作为绕过理由。confidence: high，cited，条文；应用于本项目的风险判断 medium。

## 共同演进的官方先例

- [Embedding a command-line tool in a sandboxed app](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app.md)明确展示商店应用内嵌 CLI 工具，且支持外部构建系统生成的工具；示例 helper 继承沙盒。这支持代码和构建成果复用的合法路径，**不支持以 helper 逃逸沙盒**。confidence: high，cited。
- [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox.md)说明用户选择的文件可以通过 security-scoped bookmarks 持久授权，并可传给 launch agent / XPC service；App Group 文件共享要求正确标识、签名与分发条件。共享配置有正式权限路径，但现有任意签名的社区 CLI 并不自动符合 App Group 条件。confidence: high，cited。
- 因而同项目、共同能力可以复用；具体配置位置和授权方式仍须设计验证。无需把商业 GUI 和社区 CLI 拆成长期业务分叉；该产品可行性判断为 ASSUMPTION，confidence: medium。

## 当前 CLI 的适配范围

现有 CLI 直接写入 LaunchAgent、安装到用户 Application Support、注入 Shell 路径、从 GitHub 自升级，NetFS 无凭据 UI 挂载，使用 diskutil/umount 清理死卷并尝试 mdutil。来源：[源码](../../../automnt.swift)、[架构](../../../ARCHITECTURE.zh.md)、[产品文档](../../../README.zh.md)；confidence: high，cited，文档与此前只读检查。

商店发行必须改变安装、服务注册和更新方式。共享自动挂载规则不等于共享全部系统集成，也不要求两种入口对同一个磁盘配置文件有无条件权限。沙盒凭据、指定路径挂载、死卷清理及事件响应需目标环境验证；confidence: medium，ASSUMPTION，依据上述规则。

# 许可、成本与商业数据

- MIT 允许销售，保留通知即可；也允许别人构建、修改和再分发。来源：[LICENSE](../../../LICENSE)；confidence: high，cited。不能用收费二进制宣称分发独占。
- [Apple Developer Program](https://developer.apple.com/programs/)标明 **US$99 年费**；地区实际币种与收费另确认。confidence: high，cited。
- [Small Business Program](https://developer.apple.com/app-store/small-business-program/)明确符合条件并获批的付费应用与 IAP 抽成 **15%**，此前总 proceeds 不超过 US$1 million 的既有开发者及新开发者可能符合；须申请、计入关联账号，并非自动生效。页面还说明超过阈值后适用 standard commission，但本轮不把未核实的具体标准率写成已适用事实。confidence: high，cited。
- 盈利不能从商店先例推断。示例：ASSUMPTION，售价 US$9.99、已获 15% 资格，不计税费、退款和支持，单份 US$8.4915；覆盖 US$99 年费至少 12 份。这只是会员费覆盖示例，**不包含开发回本**，不是销量预测。若再假设一年支持 40 小时、机会成本 US$30/小时，则需至少 153 份才覆盖 US$1,299；工时和时薪均是假设，非现有数据。
- macOS 27+ Apple silicon 的范围明确，收窄可服务用户；本轮没有真实装机或用户规模统计。来源：[产品文档](../../../README.zh.md)；confidence: high，cited；市场影响 ASSUMPTION，confidence: medium。

# 最强反对证据

1. **已有成熟直接竞品**：多协议、规则与多年更新；单纯另做同样菜单和挂载按钮不足以证明差异价值。公开评论和更新记录同时显示可靠性问题；它们提示测试重点，不能证明 automnt 更可靠。来源：AutoMounter 商店页；confidence: high，cited，效果优劣 unknown。
2. **路径与授权风险是核心风险**：任务依赖确定的卷路径；沙盒内挂载不能自动视为成功。竞品新系统挂载限制与 Helper 依赖说明此项有实际成本。来源：竞品版本记录及 Apple 沙盒规则；confidence: high，cited。
3. **现有 CLI 不能原样包装**：安装、后台注册、更新和系统维护操作与商店规则存在适配范围。来源：现有文档与 2.4.5；confidence: high，cited，具体替代是否可行未验证。
4. **支持可能吃掉买断收入**：网络、NAS、凭据与 OS 更新边界复杂，竞品持续修复有实际记录；automnt 支持成本未知。来源：竞品记录；成本判断 ASSUMPTION，confidence: medium。
5. **无 automnt 自身购买证据**：开源免费替代、狭窄平台范围，均限制销售假设。来源：现有分发和平台要求；confidence: medium，ASSUMPTION。

# 剩余未知与证据边界

- 未制作、安装或测试沙盒 GUI；未验证 NetFS、凭据授权持久化、任务使用路径、事件唤醒、断网死卷清理与两入口共存。
- 未获得 automnt 的审核批准。Apple 条文和第三方产品只支持可信候选路线，不提供承诺。
- 未取得真实销量、automnt 转化率、支持工时或预算上限。公开付费先例足以证明存在收费类别，不足以证明项目必然盈利。
- Finder 入口消失仍未解决；任意网络路径访问时即时连接仍不是现有能力。

# 来源访问记录

上述 developer.apple.com、apps.apple.com、automounter.app、mountainduck.io 均为此前用户授权的公开只读域名，policy: confirmed-by-user。所有实际采用的 URL 已在正文列出；无凭据参数。

本轮用户明确允许覆盖 research 技能的公网 peer 验证限制。DNS 返回 198.18/15 等代理保留地址，web_fetch 自身仍拒绝；随后使用系统 urllib HTTPS、保持证书校验、不自动跟随重定向、不登录、不提交取得正文。美国/原中国区商店 URL 返回重定向；单独读取已显示的同域 canonical 中国区 URL。Apple Markdown 文档与 review/program 页面成功；automounter.app 及 www 版本 TLS 失败，未取得帮助程序文档；旧版沙盒归档返回 301 未自动跟随，改读现行官方文档。网络错误未被冒充为证据，未访问 GitHub 服务。
