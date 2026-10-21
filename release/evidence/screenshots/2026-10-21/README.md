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
| 17-settings-centered-over-main.png | 设置窗口每次打开都居中于主窗口（主窗口 300,150 900×650；设置窗口 410,165 680×620） |
| 18-share-search-empty-state.png | 共享搜索无结果：显示“没有匹配的共享文件夹 / 没有共享文件夹匹配“zzqqq”。/ 清除搜索”，不再只剩空列表 |
| 19-global-actions-toolbar-wide.png | 宽窗：全局动作全部在窗口工具栏——＋添加、立即检查（带字）、设置（齿轮＋文字）；侧栏底部无动作条；干货区底部为“服务器”分组的可见动作行 |
| 20-compact-window-actions.png | 窄窗根列表：同一组工具栏动作保留，标签未被截断；侧栏/列表底部无动作条 |
| 21-compact-server-page.png | 窄窗进入服务器后：返回、＋、立即检查、设置、搜索仍在；对象动作在页面内“服务器”分组（服务器连接…、刷新状态） |
| 22-settings-from-toolbar.png | 从工具栏齿轮打开设置，窗口居中于主窗口；设置是唯一带齿轮的入口 |
| 23-server-page-simplified.png | 服务器页：侧栏 1/2 序号 + “已管理 · 按顺序 ⓘ”；共享行绿色对勾与“可用”；底部不再有“服务器连接/刷新状态”按钮堆 |
| 24-share-detail-one-action.png | 共享详情：单一“在 Finder 中打开”主按钮 + “弹出”；位置、自动挂载各一段；编辑/移除/诊断收进右上“⋯”；无“实际位置/配置位置”双按钮 |
| 25-compact-list-plain.png | 窄窗服务器列表用 plain 列表消除“已管理”下方空白带；序号与顺序说明一行 |
| 26-compact-server-page-simplified.png | 窄窗进入服务器：设置与“服务器设置…”在工具栏，页面内只有自动挂载开关与共享列表 |
| 27-server-settings-simplified.png | 服务器设置：名称/连接/索引三段，底部只有一个“完成”（名称与连接参数随“完成”一起保存）；索引说明压到一句 |
| 28-server-settings-row.png | 服务器页收敛：工具栏只剩 ＋、标题、⚙ 图标、搜索；服务器身份行右侧是“服务器设置 ›”；无“撤销顺序调整” |
| 29-server-settings-sheet.png | 服务器设置标题化：标题“服务器设置”、副标题为地址；自动挂载（此服务器参与）并入设置首段 |
| 30-share-detail-icons.png | 共享详情去掉 ⋯ 菜单：编辑=铅笔、移除=垃圾桶，均为图标按钮；主按钮与弹出保留 |
| 31-compact-list-no-undo.png | 窄窗服务器列表：无“撤销顺序调整”，序号与“已管理 · 按顺序 ⓘ”保持 |
| 32-compact-server-settings-row.png | 窄窗服务器页：同一“服务器设置 ›”行，工具栏无文字按钮 |
| 33-sidebar-order-caption.png | 侧栏顺序改为一行可见说明“从上到下尝试，首个可用即停。”，不再有点了没反应的 ⓘ |
| 34-compact-order-caption.png | 窄窗同样一行说明，作为“已管理”分组的脚注显示；列表无空白带 |
| 35-sidebar-owns-actions.png | 侧栏承担全局动作：底部 ＋ 与 ⚙；窗口工具栏只剩标题与搜索；右侧服务器行有独立的“服务器设置”按钮 |
| 36-inline-share-wide.png | 共享在主界面原位展开：打开/弹出、自动挂载开关、挂载位置、编辑与移除图标，不再先开弹窗 |
| 37-compact-actions.png | 窄窗根视图同样的底部 ＋/⚙，列表无空白带 |
| 38-inline-share-compact.png | 窄窗内共享原位展开，编辑仍是唯一一层 sheet |
| 39-sidebar-header-actions.png | 宽窗：侧栏头部“服务器”+ 两个系统玻璃符号按钮（添加、设置）；窗口工具栏不再放全局动作；服务器页顶部为自动挂载开关与共享行开关 |
| 40-inline-share-expanded.png | 宽窗：共享原位展开，顺序为挂载位置 → 在 Finder 中打开/弹出 → 分隔线 → 编辑/移除；开关留在行内 |
| 41-compact-list.png | 窄窗根列表：同一组全局符号在工具栏，搜索在尾部；无底部动作条、无顶部空白带 |
| 42-compact-server.png | 窄窗服务器页：返回、标题、服务器设置符号、搜索；页面直接显示服务器开关与每行共享开关，展开区同上 |
| 43-server-settings-sheet.png | 服务器设置 sheet：名称、连接、索引，底部一个“完成”；已移除与页面重复的自动挂载开关 |
| 44-settings-window.png | 设置窗口：自动挂载、恢复、范围、菜单栏；不再显示主窗口的排序或详情消息 |
