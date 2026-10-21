# 输入与决定

维护者在 2026-10-21 明确要求停止逐点修补，把所有反馈汇总，从零重做交互设计。设计文档 `specs/005-swiftui-mas-gui/design/interaction-architecture.md` 先固化了三层所有权、窗口结构、侧栏全局动作、服务器页、共享展开区、反馈归属、状态矩阵、无障碍与迁移顺序；维护者随后批准实施。

本轮实现按该文档一次完成，不在旧结构上继续挪控件。

# 实现要点

- 侧栏：头部标题“服务器”，右侧两个 28 pt 系统玻璃符号按钮（`plus`、`gearshape`，`.buttonStyle(.glass)`、圆形、大尺寸）。删除侧栏底部动作栏和窗口工具栏里的全局项；窄窗把同一组符号放在根层工具栏最前。
- 服务器页：保留身份行；服务器自动挂载开关直接可见；每行共享显示状态、名称、状态文字、自动挂载开关和展开箭头；删除重复的“需要注意”列表。
- 共享展开区：挂载位置 → 手动操作（按状态一个主按钮 + 弹出）→ 分隔线 → 编辑/移除。展开区不重复开关、不重复状态；编辑/移除与位置分开，移除仍用确认对话框。
- 服务器设置：工具栏尾端 `slider.horizontal.3` 符号 + 原生 sheet；从 sheet 删除与页面重复的“参与自动挂载”开关。
- 反馈：`ApplicationModel.messageSurface` 取 window / sidebar / settings / menuBar；视图只显示自己的 surface。删除排序、添加、移除、挂载、弹出、整轮、使用当前位置等成功 toast；排序失败用 `orderIssue` 侧栏 alert；设置消息只在设置窗口显示；菜单栏只显示菜单栏动作的消息。
- 窄窗顶部空白：宽窗跨到窄窗时，AppKit 在已位于工具栏下方的列表上再叠加 52 pt 顶部内容 inset。`ScrollInsetNormalizer` 只清除窄窗根列表与窄窗服务器页的重复 inset，宽窗仍保留系统 inset。宽度来回切换、窄窗推送后均已验证无空白带。

# 验证

- 真机窗口：宽窗 1100×700、窄窗 620×700，在 macOS 27 上运行安装后的 Release 构建；验证侧栏头部、服务器页、共享展开/收起、服务器设置 sheet、设置窗口；宽→窄→宽反复切换与窄窗推送后无顶部空白带。
- 截图：`release/evidence/screenshots/2026-10-21/39-44`，索引已写入同目录 README。
- 构建：`xcodebuild ... Release build` 返回 `BUILD SUCCEEDED`；安装到 `/Applications/Automnt.app`。
- 测试：`swift test` 全部通过（Core 197、Platform 91、CLI 33，共 321 项）。
- 本地化：`python3 scripts/verify-localization.py` 通过（新增“服务器顺序无法保存”与“关闭”按钮的九语文案；草稿仍待原生审校）。
- 未验证：浅色外观、较大系统文字、VoiceOver 实际朗读、九语原生审校、总开关关闭/服务器关闭时子开关禁用与说明的真实窗口状态（本轮未改动维护者的真实配置）、排序失败 alert 的真实触发、拖拽排序成功静默的行为（仅代码与状态路径核对）。
