Automnt 3.5.0：CLI 与后台挂载修正。本次为兼容新增与修复的 MINOR 版本，GitHub Release 只提供 CLI，不含 GUI App。

# 主要变化

- 挂载范围新增 `all_reachable`：按侧栏顺序连接第一台可用服务器后，继续挂载其余可达服务器的共享；默认仍为 `first_reachable`。
- 不可达主机的共享在评估结果中记录 `offline`，不再对同一轮内不可达的目标反复尝试。
- 未知 `mount_policy` 值回退默认策略，配置不会因单个未知字段变得不可读。
- 修复 worker intent 残留导致评估 journal 进入 failed 的问题，后续轮次仍可正常继续。
- 共享位置状态与单共享入口继续完善：实际位置与保存位置不一致时可按需采用实际位置；单共享挂载/普通弹出沿用 3.4.0 的 CLI 入口与失败分类。
- 图形界面交互已按新架构重做（侧栏全局动作、服务器与共享自动挂载开关、共享原位展开、反馈归属），但本 Release 不发布 GUI；GUI 保留给后续 App Store 版本。

# 下载

- `automnt`：预编译 CLI（macOS 27 / Apple silicon）。单独下载后先运行 `chmod +x automnt`。
- `automnt-3.5.0.sha256`：CLI 的 SHA-256 校验值。

不提供 `Automnt-*.zip` 或 GUI App；这些产物不在 GitHub 分发范围。

# 升级

从 3.4.0 直接替换 `automnt` 二进制即可；配置格式兼容。CLI 首次从下载目录运行时会自搬迁到 `~/Library/Application Support/automnt/bin/automnt` 并更新 PATH。

# 已知限制

- 构建使用免费 Apple Development 签名，未公证；其他 Mac 首次运行可能被 Gatekeeper 阻止，需要在 Finder 中右键“打开”或在系统设置中允许。
- 后台自动挂载仍需要系统允许后台项目；真实注销/重启、helper 跨会话持久访问、系统 SMB 认证复用、VoiceOver、系统大字与多主机矩阵未在当前环境完成验证。
- 仅支持 macOS 27.0+ / Apple silicon；App Store 版本、商店审核与定价不在本次发布范围。

# 验证

签名 Release 构建通过；`swift test` 321 项、优化 CLI `--self-test`、本地化门禁与 Swift 6 结构门通过。源码与提交的预编译 CLI 版本均为 3.5.0。
