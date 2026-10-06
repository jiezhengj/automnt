**Feature**: 终端交互选单与操作范式重构（Terminal Interactive Selection & TUI UX）

**Artifact**: 数据模型与交互状态机（Data Model & Interaction State Machine）

**Feature ID**: `003-interactive-selection-ux`

**Created**: 2026-10-03

# 1. 交互按键事件模型 (KeyAction)

## 实体定义

表示终端按键解析引擎从原始字节流或模拟注入队列中解码出的离散按键意图。

| 动作类型 | 对应按键 / 字节序列 | 业务语义 |
| :--- | :--- | :--- |
| `up` | 上箭头序列（`ESC [ A` 或 `ESC O A`）或 `k` / `K` | 光标焦点向上移动一位 |
| `down` | 下箭头序列（`ESC [ B` 或 `ESC O B`）或 `j` / `J` | 光标焦点向下移动一位 |
| `enter` | 回车键（ASCII 10 / 13） | 确认当前焦点项（单选）或提交勾选集合（多选） |
| `space` | 空格键（ASCII 32） | 翻转当前项勾选状态（多选）或翻转单选选中项（防呆确认） |
| `selectAll` | `a` / `A` 键 | 智能全选或清空全部多选项 |
| `escape` | 独立 Esc 键（ASCII 27 且 50ms 内无后续） | 取消当前操作并安全回退上一级 |
| `interrupt` | `Ctrl+C`（ASCII 3） | 中断程序运行并保障终端模式恢复 |
| `unknown` | 其他未捕获或无效控制字符 | 忽略并维持当前状态 |

# 2. 选单通用条目模型 (SelectionItem)

## 实体定义

驱动单选、多选与破坏性防呆选单渲染的基础数据结构。

| 属性名称 | 类型 | 说明与约束 |
| :--- | :--- | :--- |
| `id` | 字符串 | 选项唯一业务标识符（如主机地址、共享名称、动作标识） |
| `title` | 字符串 | 列表显示的主要文字标题 |
| `subtitle` | 可选字符串 | 次要辅助描述文字（如主机别名、已挂载共享数、状态说明） |
| `isEnabled` | 布尔值 | 是否允许选择；禁用项光标可聚焦但回车发出温和保护提示 |

# 3. 固定视口滚动状态模型 (RollingViewportState)

## 实体定义

负责在列表条目总数超出终端安全可视行数时，计算渲染切片与滚动指示符的核心算法状态机。

| 字段名称 | 类型 | 说明与算法约束 |
| :--- | :--- | :--- |
| `totalCount` | 整数 | 候选项目总数 |
| `capacity` | 整数 | 视口当前允许显示的最大可见项数（通常为 10~15） |
| `startIndex` | 整数 | 当前视口在总条目列表中的起始截取索引 |
| `cursorIndex` | 整数 | 使用者当前光标绝对索引（`0 <= cursorIndex < totalCount`） |

## 初始状态对齐算法约束

当初始化视口并指定默认聚焦项 `defaultIndex`（`0 <= defaultIndex < totalCount`）时，系统执行自适应视口对齐计算：
```text
cursorIndex = defaultIndex
if defaultIndex >= capacity {
    startIndex = max(0, min(defaultIndex - capacity + 1, totalCount - capacity))
} else {
    startIndex = 0
}
```
此约束确保首帧渲染时光标绝对位置必处于 `startIndex ..< startIndex + capacity` 可视切片之内，绝不发生光标落入视口外部的界面错位。

## 视口动态推导属性

- `visibleRange`: 计算当前渲染的切片索引区间 `startIndex ..< min(startIndex + capacity, totalCount)`；
- `canScrollUp`: 当 `startIndex > 0` 时为真，需在顶部槽位渲染指示符 `▲ 向上还有 (startIndex) 项`；当为假时渲染占位空白行保持总行数固定；
- `canScrollDown`: 当 `startIndex + capacity < totalCount` 时为真，需在底部槽位渲染指示符 `▼ 向下还有 (totalCount - endIndex) 项`；当为假时渲染占位空白行保持总行数固定；
- `cursorOffset`: 光标在当前视口内部的相对行号 `cursorIndex - startIndex`。

## 光标移动与视口滚动边界处理

- 光标下移：若 `cursorIndex + 1 < totalCount`，`cursorIndex` 递增；若递增后 `cursorIndex >= startIndex + capacity`，则 `startIndex` 同步递增 1；
- 光标上移：若 `cursorIndex > 0`，`cursorIndex` 递减；若递减后 `cursorIndex < startIndex`，则 `startIndex` 同步递减 1；
- 循环环绕：若在首项上移且启用环绕，光标跳转至末项，`startIndex` 重置为 `max(0, totalCount - capacity)`；若在末项下移，光标跳转至首项，`startIndex` 重置为 0。

# 4. 多选复选框状态机 (CheckboxGroupState)

## 实体定义

用于管理主机从属共享勾选、批量删除与批量启停的复选框状态。

| 字段名称 | 类型 | 业务规则 |
| :--- | :--- | :--- |
| `items` | `[SelectionItem]` | 所有待选条目 |
| `selectedIndices` | 整数集合 (`Set<Int>`) | 当前被选中的条目索引集合 |
| `viewport` | `RollingViewportState` | 视口滚动状态机 |

## 状态转换矩阵

- 接收 `space`：若 `cursorIndex` 处于选中集合，则从中移除；否则加入集合；
- 接收 `selectAll`：若已选数量等于可选总数，则清空已选集合；否则将所有有效条目索引加入集合；
- 接收 `enter`：状态机结束，向调用方返回所有选中条目的业务数据；
- 接收 `escape`：状态机结束，向调用方返回安全取消信号（`nil`）。

# 5. 单选与防呆单选状态机 (RadioGroupState)

## 实体定义

统一承载“光标单选直达”与“空格单选确认防呆”两种范式的核心状态机。

| 字段名称 | 类型 | 业务规则 |
| :--- | :--- | :--- |
| `items` | `[SelectionItem]` | 单选项列表 |
| `isExplicitConfirmation` | 布尔值 | 是否启用空格显式防呆模式（破坏性操作专用） |
| `focusedIndex` | 整数 | 当前光标高亮项索引（显示 `❯` 指针） |
| `checkedIndex` | 可选整数 | 当前显式选中的单选框索引（显示 `(o)`） |
| `viewport` | `RollingViewportState` | 视口滚动状态机 |

## 两种模式的状态转换对比

### 模式 A：光标单选直达模式（isExplicitConfirmation == false）

- 上下方向键移动 `focusedIndex`；
- 选项前仅呈现光标高亮指示（如 `❯ [选项标题]`）；
- 按下 `enter`：直接选定当前 `focusedIndex` 并返回；
- 按下 `escape`：返回安全取消信号（`nil`）。

### 模式 B：空格单选确认防呆模式（isExplicitConfirmation == true）

- 初始状态：`checkedIndex = 0`（安全项 `(o) 取消并返回`），`focusedIndex = 0`；破坏性操作项为 `( ) 确认删除`；
- 上下方向键：仅移动 `focusedIndex`（指针 `❯` 移动），`checkedIndex` 绝对保持不变；
- 按下 `space`：将 `checkedIndex` 更新为当前的 `focusedIndex`（单选框状态翻转）；
- 按下 `enter`：
  - 若 `checkedIndex` 对应安全项（取消项）：执行取消并返回 `nil`；
  - 若 `checkedIndex` 对应破坏项（确认删除）：执行删除操作并返回确认标识；
  - 若使用者未按 `space` 翻转状态、直接敲击 `enter`：按当前 `checkedIndex` 执行（即取消并返回 `nil`）；
- 按下 `escape`：在任何时刻均执行取消并返回 `nil`。

# 6. 主机顺位两步原子调整状态机 (TwoStepReorderState)

## 实体定义

负责在日常配置管理中将多台主机的顺位以直观的两步单选方式重新排布。

```text
[初始状态]
   │
   ▼ 选择操作："调整主机顺位"
[第一步：选择源主机] ──(按 Esc 放弃)──> [返回主菜单 (无修改)]
   │ (单选直达：选中待移动主机)
   ▼
[第二步：选择目标槽位] ──(按 Esc 放弃)──> [返回主菜单 (无修改)]
   │ (单选直达：选中目标位置槽位)
   ▼
[执行原子顺位重排] ──> 更新内存主机队列 ──> [返回主菜单 (即时呈现新顺位)]
```

## 状态转换数据契约

1. 第一步输入：当前已配置主机列表 `[HostConfig]`；
2. 第一步输出：选定的源主机索引 `sourceIndex`；
3. 第二步输入：生成 N 个顺位槽位选项（例如 `[1] 顺位 1 (替换首选)`、`[2] 顺位 2` 等）；
4. 第二步输出：选定的目标槽位索引 `targetIndex`；
5. 原子重排操作：`let item = hosts.remove(at: sourceIndex); hosts.insert(item, at: targetIndex)`；
6. 结果反馈：输出“已将主机成功调整至顺位 X”，主菜单立即以最新顺位重绘。

# 7. 领域实体正交性保障

交互状态机（`KeyAction`、`SelectionItem`、`RollingViewportState`、`RadioGroupState`、`CheckboxGroupState`）严格限定在表示层（Presentation Layer），与底层核心业务实体（`HostConfig`、`SMBShareConfig`、`AutomntConfig`）保持完全正交解耦：
- 交互组件不感知配置文件的 XML/Plist 序列化细节；
- 业务配置层仅接收纯数据转换结果（如选中索引数组、调整后的主机队列）；
- 配置文件结构与存储版本保持 100% 稳定兼容，零模式断代风险。
