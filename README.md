# 语言导航 / Language Navigation

| 语言 / Language | 说明文档 / Documentation | 架构与技术规范 / Architecture & Standards |
| :--- | :--- | :--- |
| 中文 | [README.zh.md](./README.zh.md) | [ARCHITECTURE.zh.md](./ARCHITECTURE.zh.md) |
| English | [README.en.md](./README.en.md) | [ARCHITECTURE.en.md](./ARCHITECTURE.en.md) |

# 下载 / Download

从 [GitHub Releases](https://github.com/jiezhengj/automnt/releases) 下载：

- `automnt`：预编译 CLI（macOS 27 / Apple silicon）；单独下载后先运行 `chmod +x automnt`。
- `automnt-3.5.0.sha256`：CLI 的 SHA-256 校验值。

自 3.5.0 起，GitHub Release 只分发 CLI；GUI 源码按 MIT 开源、可自行编译，但不提供预构建 App，保留给后续 App Store 版本。详见 [发布政策](./release/RELEASE_POLICY.md)。当前 CLI 使用免费 Apple Development 签名，未公证；仅支持 macOS 27.0+ / Apple silicon。

# 简介 / Overview

macOS 原生轻量级网络存储（SMB）自动化挂载工具。基于目标主机 TCP 445 端口服务可达性探测与事件驱动响应，提供完全静默、免密码、断网自动超时清理与丢失自动恢复的稳定挂载体验。

A native, lightweight network storage (SMB) automation tool for macOS. Powered by target host TCP 445 reachability probing and event-driven daemon evaluation, providing silent, password-free, bounded cleanup, and automatic mount-loss recovery.

交互式终端菜单（3.2.0）为初始化与日常配置提供方向键选择、空格多选、长列表滚动和 Esc 取消；配置修改仅在明确选择保存并退出后写入。图形界面与 CLI 共用同一配置与自动挂载规则。

Interactive terminal menus (3.2.0) provide arrow-key selection, Space multi-selection, scrolling for long lists, and Escape cancellation during setup and configuration. Configuration changes are written only after choosing Save and exit.

挂载丢失自动恢复（3.3.0）：远程主机恢复可达后，配置启用且此前已挂载的共享卷会在下一次事件唤醒的当轮评估中自动重新挂载。自动恢复只重挂"此前确实挂载过"的卷；从未挂载过的新增卷仍按原有挂载评估逻辑处理。若使用者在卷健康时手动弹出，该卷在本可达会话内不会被自动重新挂载（会话级抑制）；网络上下文变化或重新登录（先到者为准）后抑制解除。

Automatic mount-loss recovery (3.3.0): once the remote host is reachable again, enabled shares that were previously mounted are re-mounted automatically in the same evaluation round that follows the next wake-up event. Recovery only re-mounts volumes that were genuinely mounted before; newly added shares that were never mounted keep following the existing mount-evaluation logic. A share you eject while healthy is not remounted for the rest of that reachable session (session-level suppression); suppression lifts on a network-context change or a re-login, whichever comes first.

健康弹出与会话抑制静默；仅实际恢复失败时，每轮至多一条合并通知指引至 `automnt --config` 的“立即重新挂载”；同一卷同一会话至多通知两次。“自动恢复开关”默认启用，仅在“保存并退出”后生效；Esc 放弃未保存修改。关闭后保留登录与网络配置变化评估，手动入口仍可用。

Healthy ejection and session suppression remain silent. Only actual recovery failures trigger a merged notification that points to **Remount now** in `automnt --config`, at most once per round and twice per volume per session. **Auto-recovery switch** defaults to enabled and takes effect only after **Save and exit**; Escape discards unsaved edits. Disabling it keeps login and network-change evaluation and the manual action.

**边界说明**：CLI 提供 `--mount`/`--eject`，图形界面在共享详情中提供普通弹出；两者都把强制卸载留给恢复前的死卷清理，繁忙卷如实失败。上述健康“弹出”包括使用者在系统（如 Finder）或产品入口中发起的动作。

**Boundary**: the CLI exposes `--mount`/`--eject`, and the GUI exposes ordinary eject in share details. Both leave forced unmount to dead-mount cleanup before recovery; a busy volume fails honestly. Healthy ejection includes actions initiated in the system (e.g. Finder) or in the product entry points.

仅支持 macOS 27.0 或更高版本的 Apple silicon（arm64）；不支持 Intel Mac。项目以 macOS 27 SDK 和新 API 为优先目标，不维护旧 macOS 或 Intel 的兼容代码；代码保持精简，且继续支持必要的配置升级迁移。

Supports macOS 27.0 or later on Apple silicon (arm64) only. The project prioritizes the macOS 27 SDK and APIs, keeps the implementation concise, and does not maintain compatibility code for older macOS releases or Intel Macs. Forward configuration migrations remain supported.
