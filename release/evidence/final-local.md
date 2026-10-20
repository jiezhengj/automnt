公开仓库中的真实主机、IP、邮箱、Team ID 与证书编号均为占位符；真实值只保留在本机运行配置中，不随仓库分发。

2026-10-20 本机最终本地验证汇总；真实登录/重启、helper 持久访问与商店路径仍为明确延后项。

# 门禁

- `swift test`：306 项通过（Core 184/49、Platform 89/25、CLI 33/3）。
- 优化 CLI：`--version` 3.4.0、`--self-test` 295/0/0。
- 签名 Release：BUILD SUCCEEDED；`verify-signature`、`verify-localization`（359 键）、`verify-swift6-concurrency` 通过。
- 离线包：`Automnt-3.4.0-offline.zip` SHA-256 校验 OK，manifest 记录版本/团队/Xcode/Swift。

# 真实运行证据

签名 GUI：无面板固定目录读写、单行添加/移除、重复拒绝、重开持久化、窄窗原生导航、Settings、字段校验、退出确认；八语实机窗口；同机替换升级配置哈希不变。CLI（PTY）：真实 `--mount`/`--eject`、LaunchAgent 注册、繁忙弹出如实失败且共享保持挂载、错误分类修复。

# 延后项

真实注销/重启、helper 跨会话持久访问、GUI 退出后后台 SMB、系统 SMB 认证复用、VoiceOver 朗读/系统大字、⌘W 实机复验（屏幕锁定）、双主机/跨端口、后台普通/繁忙弹出、付费账号与商店。见 tasks.md 阶段 11。
