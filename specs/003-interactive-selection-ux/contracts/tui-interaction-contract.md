**Feature**: 终端交互选单与操作范式重构（Terminal Interactive Selection & TUI UX）

**Artifact**: 终端 TUI 交互协议契约（Terminal TUI Interaction Contract）

**Feature ID**: `003-interactive-selection-ux`

**Created**: 2026-10-03

# 1. 终端模式与光标可见性契约

## 终端配置与生命周期保障

- 在进入任何 TUI 选单前，系统读取标准输入当前终端属性（`tcgetattr(STDIN_FILENO, &origTermios)`）；
- 配置非规范模式与无回显模式：`rawTermios.c_lflag &= ~(ICANON | ECHO | ISIG)`，`rawTermios.c_cc[VMIN] = 1`，`rawTermios.c_cc[VTIME] = 0`，调用 `tcsetattr(STDIN_FILENO, TCSANOW, &rawTermios)`；
- 选单开启时隐藏光标：标准输出写入 `\033[?25l` 并刷新缓冲区；
- 退出保障机制：利用语言级保障（`defer`）无论正常退出、Esc 放弃、还是异常中断，均必定执行：
  1. 显现光标：标准输出写入 `\033[?25h` 并刷新；
  2. 还原终端：调用 `tcsetattr(STDIN_FILENO, TCSANOW, &origTermios)`。

## 信号中断契约

- 屏蔽 `ISIG` 使得 ASCII 3（`^C`）作为常规字符被解码为 `KeyAction.interrupt`，在代码逻辑中优雅还原终端模式并显现光标，随后以状态码 130 退出；注册 `SIGINT` 信号处理器作为辅助安全网，绝不留存非规范状态污染终端会话。

# 2. 原地擦除与重绘协议 (In-place Repaint Protocol)

## 固定行数预算契约 (Fixed Line Budget)

- 为彻底杜绝因滚动指示符动态插入/消失导致整屏输出行数波动、引发 `\033[RA` 向上回退行数不匹配造成光标垂直漂移与历史屏幕撕裂，系统强制确立固定行数预算：
  1. 设定视口可见容量为 `capacity`；
  2. 顶部设立固定指示符槽位（Indicator Slot）：当 `canScrollUp == true` 时输出 `▲ 向上还有 N 项`，当为假时输出清除占位行 `\033[2K\n`；
  3. 底部设立固定指示符槽位：当 `canScrollDown == true` 时输出 `▼ 向下还有 N 项`，当为假时输出清除占位行 `\033[2K\n`；
  4. 标题行、提示行固定占位；
  5. 从而确保任意一帧输出的物理总行数 $R$ 恒定不变（$R = \text{capacity} + 4$）。

## 帧间回退与重绘执行

- 渲染器内部状态机同时跟踪 `lastRenderedLineCount` 作为双重保险：每次擦除重绘时输出 ANSI 回退序列 `\033[\(lastRenderedLineCount)A`；
- 对视口内的每一行，输出 `\033[2K` 整行清除后输出最新内容；
- 渲染完毕后显式调用 `fflush(stdout)`，确保终端画面瞬间刷新，无残影、无抖动、无漂移。

# 3. 按键解码、50ms 超时探测与 SS3 兼容契约

## 字符流解码状态机契约

```text
[读取首字节 b0]
   ├── b0 == 3          -> 返回 KeyAction.interrupt (Ctrl+C)
   ├── b0 == 10 或 13   -> 返回 KeyAction.enter (回车)
   ├── b0 == 32         -> 返回 KeyAction.space (空格)
   ├── b0 == 97 或 65   -> 返回 KeyAction.selectAll ('a' / 'A')
   ├── b0 == 106 或 74  -> 返回 KeyAction.down ('j' / 'J')
   ├── b0 == 107 或 75  -> 返回 KeyAction.up ('k' / 'K')
   ├── b0 == 27 (Esc)   -> 启动 50ms 超时非阻塞探测:
   │                         ├── 50ms 内无后续字节 -> 返回 KeyAction.escape (独立 Esc)
   │                         └── 50ms 内读取 b1:
   │                               ├── (b1 == 91 '[' 或 b1 == 79 'O') -> 启动 10ms 短超时读取 b2:
   │                               │       ├── b2 读取超时或失败 -> 返回 KeyAction.escape
   │                               │       ├── b2 == 65 ('A') -> KeyAction.up
   │                               │       ├── b2 == 66 ('B') -> KeyAction.down
   │                               │       └── 其他 -> KeyAction.unknown
   │                               └── 其他 -> KeyAction.unknown
   └── 其他字节         -> 返回 KeyAction.unknown
```

## 超时探测与兼容性约束

- 首字节 Esc 解歧探测基于 POSIX `poll(&pfd, 1, 50)`，超时时间固定为 50 毫秒；
- 后续参数字节 $b_2$ 同样施加 10ms 短超时非阻塞保护，严禁无保护阻塞裸读，杜绝非标准或截断序列导致的挂起假死；
- 同时兼容标准 CSI（`b1 == 91` 即 `[`）与应用光标 SS3 模式（`b1 == 79` 即 `O`），保障在 tmux、screen 及各类标准终端仿真器下方向键 100% 精准响应。

# 4. 视口渲染视觉格式契约

## 单选直达模式格式契约

```text
  [选单标题与操作指引]
  ▲ 向上还有 3 项
  ❯ 198.51.100.10 (2 个共享已配置)
    192.168.1.100 (1 个共享已配置)
    手动添加新主机地址
  ▼ 向下还有 2 项
  (上下键移动，回车确定，Esc 取消)
```

## 空格单选确认防呆格式契约

```text
  === 高风险操作确认：删除主机 198.51.100.10 ===
  警告：删除后该主机名下的所有从属共享挂载配置将被同步移除。
  删除仅修改内存工作副本，保存后才会生效。
  ❯ (o) 取消并返回
    ( ) 确认删除
  (上下键移动光标，空格键切换单选状态，回车确认，Esc 取消)
```

## 空格多选复选框格式契约

```text
  选择要追加的共享：
  ▲ 向上还有 5 项
  ❯ [x] data (smb://198.51.100.10/data → /Volumes/data)
    [ ] media (smb://198.51.100.10/media → /Volumes/media)
    [x] backup (smb://198.51.100.10/backup → /Volumes/backup)
  ▼ 向下还有 4 项
  (上下键移动，空格翻转单项，a 全选/清空，回车提交，Esc 取消)
```

# 5. 非交互管道降级与自测注入契约

## 管道环境降级协议

- 当 `isatty(STDIN_FILENO) == 0` 时：
  - 自动禁用 ANSI 原地重绘与光标隐藏指令；
  - 选单退化为逐行顺序打印各选项，并附带序号；
  - 调用标准流式行读取 `readLine()`，解析输入的行内容（编号选择），空行直接取消当前选择；
  - 保证非交互管道流式调用不报错、不崩溃、退出码正常。

## 全内存按键序列注入契约

- 自测试套件可向 `TerminalUI` 注册模拟按键队列：`TerminalUI.mockKeySequence = [KeyAction]`（静态可选队列属性）；
- 当队列非空时，按键解码器优先从队列头部弹出 `KeyAction`，并绕过底层文件描述符读取；
- 自动化自测模式下依然执行完整的渲染重绘与状态机流转，实现对复杂 TUI 交互逻辑 100% 确定性的无头验证。
