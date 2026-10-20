> 2026-10-11 本轮历史范围说明（仅 Feature005）：本轮仅修改文档与 demo；独立密码 CRUD、8 步向导、多选、用户 CLI 导入/检查、内部配置目录选择已撤销，现行要求以 [spec](../../specs/005-swiftui-mas-gui/spec.md) 与 [contracts](../../specs/005-swiftui-mas-gui/contracts/gui-and-release.md) 为准。系统认证在 sandbox/helper 中的复用未验证；已有 CLI 配置自动呈现与共享配置 owner 尚未实现。Automnt 暂用。以下历史正文与测试结果保留，旧资源、截图与测试不证明新版通过；CLI Feature001–004 的证据语义不变。

# 已确认资源

2026-10-08 本机实际环境为 macOS27.2/arm64、Xcode27/macOS SDK27、Swift6.4。security find-identity -v -p codesigning 实际报告3个有效 Apple Development 身份，覆盖两个团队；尚未指定本项目长期采用的团队，未使用任何身份签名或注册服务。

免费开发身份只能支持本地开发验证，不证明 Mac App Store 分发资格。本机未验证 Apple Distribution/MAS provisioning 能力；不购买账号、设备或域名。

# 待补足的验证安排

真实 SMB 目标和账号应从本机实际挂载探测或维护者显式提供后经产品生成，不能从既有自测中的模拟值推导。服务、目录授权、Keychain、网络卷 TCC 和失败恢复必须在实际目标验证。2026-10-19 维护者确认方案 A：授权继续使用本机现有局域网 NAS 与 Tailscale 远端作为真实 SMB 测试目标；本文件按脱敏类别记录，不写具体主机名、地址或账号。网络中断、重连、健康弹出与忙卷操作安排在不影响重要任务时由维护者执行。不购买设备、账号或域名。T002 按此授权与资源清点闭合。

目录选择和系统权限提示由维护者通过实际系统界面完成。网络中断、登录验证和忙卷操作需要安排实际环境；不自动点击权限、不绕过TCC、不将开发签名当作商店许可。日志保留期限/容量/清理仍待维护者决定，T003保持未完成；独立共享结构工作继续。
