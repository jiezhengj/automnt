> 2026-10-11 本轮历史范围说明（仅 Feature005）：本轮仅修改文档与 demo；独立密码 CRUD、8 步向导、多选、用户 CLI 导入/检查、内部配置目录选择已撤销，现行要求以 [spec](../../specs/005-swiftui-mas-gui/spec.md) 与 [contracts](../../specs/005-swiftui-mas-gui/contracts/gui-and-release.md) 为准。系统认证在 sandbox/helper 中的复用未验证；已有 CLI 配置自动呈现与共享配置 owner 尚未实现。Automnt 暂用。以下历史正文与测试结果保留，旧资源、截图与测试不证明新版通过；CLI Feature001–004 的证据语义不变。

# 实际环境与验证

Feature005 Implement 已获维护者明确授权。以下为修改业务代码前的本机基线，不代表 GUI、沙盒或发布通过。

| 项目 | 实际结果 |
| --- | --- |
| CLI 版本 | 工作区预编译程序 `--version` 为 3.3.2 |
| 内置自测 | `./automnt --self-test`：267 passed，0 skipped，0 failed |
| 优化源码编译 | `/usr/bin/swiftc -O -sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -target arm64-apple-macosx27.0 automnt.swift -o /tmp/automnt-005-baseline`：退出 0 |
| 系统 | macOS 27.2，26B5101f；arm64 |
| Xcode | 27.0，27A266a |
| SDK / Swift | macOS SDK 27.0；Swift 6.4 |
| 签名资源 | 系统报告 3 个有效 Apple Development 身份；未选择/使用发行身份 |

自测包含终端菜单、保存与取消、旧配置迁移、未知字段保留、签名校验、有限重试、主机顺序排他、挂载身份、会话抑制与恢复通知规则。测试配置由现有程序保存 API 在临时目录生成，未编辑活动业务配置。自测中的守护运行态拒绝服务定义重建警告为既有覆盖场景。

# 兼容范围与未知项

保留 hosts/shares 与旧 profiles 桥接、retry_policy、恢复开关缺省启用、未知字段和原命令退出语义；版本仍以根源码声明为唯一来源。新构建入口需显式指定 macOS 27.0，既有二进制 minos 27.2 与公开声明 27.0 的差异留待 T040 最终复验。

真实 SMB 目标、目录授权、后台服务、钥匙串、TCC、普通卸载及 GUI 退出/登录后的恢复尚未验证。此次基线命令未触发产品挂载、安装或服务注册。预编译二进制不在此步骤替换或对外发布。
