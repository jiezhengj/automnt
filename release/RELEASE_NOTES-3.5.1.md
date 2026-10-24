# Automnt 3.5.1：后台恢复修正

本次为修复版本（PATCH）。GitHub Release 只提供 CLI 预编译二进制，不含 GUI App。

# CLI 可感知的变化

- 重启后的恢复更可靠：沙盒内后台读不到 console 登录记录时，会话边界回退到系统 boot time；跨重启遗留的“已挂载”记录不再被当作健康卷弹出，而是进入恢复重试。
- 同一 boot 内仅网络变化不再被误判为新会话，不会误清会话弹出抑制；真正的重启才会刷新边界。
- 配置、命令与默认策略保持兼容，无需迁移。

# 同仓库源码修复（不随本 Release 分发）

- 独立 helper 就绪判定改为固定 LaunchAgent 定义 + launchd 期望身份 + 已提交 backend-state，修复登录后后台服务误判待批准。
- 沙盒内挂载改为在调用进程执行，修复 worker 子进程无法执行 NetFS 导致的挂载失败。
- 失败通知改为“helper 记录、常驻 App 投递”，修复失败被吞与常驻循环空转。
- 菜单栏/Dock 行为、8 个控件的辅助功能名称、九语文案与德语 du 统一、隐私清单 `PrivacyInfo.xcprivacy` 均已补齐。
- GUI 源码按 MIT 开源，可自行编译；本 Release 不提供构建好的 App。

# 下载

- `automnt`：预编译 CLI（macOS 27 / Apple silicon），下载后先 `chmod +x`。
- `automnt-3.5.1.sha256`：CLI 的 SHA-256 校验值。

# 升级

替换旧 `automnt` 即可，配置与后台状态沿用；如之前由 App 持有后台所有权，CLI 后台自动挂载仍按既有 owner 规则处理。
