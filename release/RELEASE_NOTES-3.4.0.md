Automnt 3.4.0 完成 Feature 005：原生 SwiftUI 图形界面、GUI/CLI 共用配置与离线分发。本次为兼容新增功能的 MINOR 版本。

# 主要变化

- 新增 macOS 27 原生 SwiftUI 图形界面：服务器分组、共享添加/编辑/移除、自动挂载开关、共享详情、设置、帮助、诊断与退出草稿保护。
- GUI 与 CLI 使用同一份配置和挂载规则；配置目录由程序准备，首次启动不再要求用户选择内部文件夹。
- 窄窗口使用服务器 → 共享 → 详情原生导航；宽窗口保持左右两列，并保留选择、焦点与滚动。
- 九种界面语言：英语、简体中文、繁体中文、日语、韩语、德语、法语、西班牙语、巴西葡萄牙语。
- CLI 新增 `--mount <smb-url>` / `--eject <smb-url>` 单共享入口；普通弹出不强制，繁忙时如实失败。
- 修复 DiskArbitration 的 `unix_err(EBUSY)` 分类，繁忙卷不再被误报为“共享被服务器拒绝”。
- 本机日志按 7 天 / 单文件 5 MB 保留，并可在诊断页清除；诊断导出仍需用户主动预览和触发。
- 免费 Apple Development 签名的离线构建，附带 GUI、CLI、安装说明与已知限制。

# 下载

- `automnt`：预编译命令行二进制（macOS 27 / Apple silicon）。单独下载后需先 `chmod +x automnt`；zip 内的 `payload/automnt` 保留执行权限。
- `Automnt-3.4.0-offline.zip`：签名 GUI + CLI + 安装/限制/版本说明。
- `Automnt-3.4.0-offline.zip.sha256`：离线包校验值。

# 已知限制

- 构建使用免费 Apple Development 签名，未公证、未提交 App Store；其他 Mac 首次打开可能需要在 Finder 中右键“打开”，或在系统设置中允许。
- 后台自动挂载仍需要系统允许后台项目；真实注销/重启、helper 跨会话持久访问、系统 SMB 认证复用、VoiceOver 朗读、系统大字、多主机与后台繁忙弹出等矩阵未在当前环境完成，详见仓库 `release/evidence/phase-closure-2026-10-20.md` 的 X 类记录。
- 当前发行范围为免费离线分发；付费账号、App Store Connect、商店审核与定价未包含。
- 支持 macOS 27.0 或更高版本，仅 Apple silicon (arm64)。

# 验证

签名 Release 构建通过；`swift test` 306 项、优化 CLI `--self-test` 295 项、签名/本地化/Swift 6 结构门通过。任务清单与证据见仓库 `specs/005-swiftui-mas-gui/` 与 `release/evidence/`。
