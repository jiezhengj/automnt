# 2026-10-21 真实窗口验收截图

均为已安装 GUI（3.4.0）的真实窗口截图（`screencapture` 按窗口 ID 捕获），用于 T112–T118 的界面验收；对应说明见 `release/evidence/t112-t118-2026-10-21.md`。

| 文件 | 内容 |
| --- | --- |
| 01-wide-main.png | 宽窗主界面：侧栏已管理分组、拖拽把手、行尾 chevron、详情工具栏“刷新状态/服务器设置…”、侧栏底部全局栏 |
| 02-tailscale-location-mismatch.png | 选中 Tailscale 服务器 `100.113.52.52`：两个共享显示“挂载在其他位置”，无异常计数 |
| 03-share-detail-location-and-actions.png | 共享详情：约定位置 `/Volumes/finalhome`、实际位置 `/Volumes/finalhome-1`、说明与“在 Finder 中打开实际位置” |
| 04-share-detail-use-actual-location.png | 共享详情滚动到底部：“使用此位置”动作 |
| 05-settings-mount-scope.png | 设置窗口“自动挂载”组：挂载范围“首个可达服务器”与解释 |
| 06-mount-scope-menu.png | 挂载范围菜单的两个选项 |
| 07-mount-scope-all-reachable.png | 切换到“所有可达服务器”后的设置值（该次切换是验收副作用，需改回默认） |
| 08-compact-empty-band-defect.png | 窄窗（660pt）缺陷：`已管理` 标题下约 52pt 空白带 |
| 09-sidebar-note-wraps.png | 修复后宽窗侧栏说明完整换行（挂载范围为“所有可达服务器”时的文案） |
| 10-sidebar-note-first-reachable.png | 改回“首个可达服务器”后说明文字同步变化，并出现“挂载范围已保存”提示 |
| 11-compact-launch.png | 窄窗启动（660×700）：服务器行、拖拽把手、分组页脚、底部全局栏，无空白带 |
| 12-compact-push-detail.png | 窄窗推送详情：返回按钮、主机名、刷新/服务器设置工具栏按钮、共享状态 |
| 13-japanese-wide.png | 日语界面宽窗：管理対象/追加可能/利用可能，侧栏说明四行完整显示 |
| 14-main-check-result.png | 点“立即检查”后的真实结果条（“检查完成。每个共享文件夹都显示了结果和检查时间。”），不再出现配置冲突文案；底部栏为“＋ 添加共享文件夹… / ⚡ 立即检查”文字按钮，无齿轮 |
| 15-main-labeled-actions.png | 宽窗主界面（修复后）：底栏文字按钮、工具栏“服务器连接…”带文字、侧栏说明使用“可用的服务器” |
| 16-settings-plain-status.png | 设置窗口：状态行改为“自动挂载状态 正在运行”，挂载范围说明使用“可用的服务器” |
