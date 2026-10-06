**Feature**: 终端交互选单与操作范式重构（Terminal Interactive Selection & TUI UX）

**Artifact**: 特性实施技术方案与架构计划（Implementation Plan）

**Feature ID**: `003-interactive-selection-ux`

**Branch**: `003-interactive-selection-ux` | **Date**: 2026-10-03 | **Spec**: [specs/003-interactive-selection-ux/spec.md](file:///Users/jiezhengj/Documents/Project/automnt/specs/003-interactive-selection-ux/spec.md)

# 方案概述与技术上下文

## 概述与核心路径

本计划面向 Feature 003（终端交互选单与操作范式重构），彻底淘汰向导（`--init`）与日常管理（`--config`）中让使用者手动敲入选项数字编码或字母代号（如 `[1-2 / m / s / d]`、`[1-1 / a / m / d / u / q]`）的粗糙命令行模式。在坚持纯原生单文件（`automnt.swift`）零外部依赖的前提下，全面建立并刚性落地五大高阶交互范式：

1. 光标单选直达（光标高亮移动 + `Enter` 立即触发）；
2. 空格单选确认防呆（高风险操作显式分离光标移动与选中状态，必须按 `Space` 切换单选框后按 `Enter` 确认，直接回车或按 `Esc` 坚决取消）；
3. 空格多选再回车确认（从属共享选择，`Space` 翻转 `[x]` / `[ ]`，`a` 智能全选/清空，`Enter` 批量提交）；
4. 全局 Esc 即时安全回退与 50ms 超时非阻塞判定（彻底消除单按 Esc 终端卡死假死缺陷）；
5. 必要受限单行文本输入（支持退格即时擦除、默认值回车继承与 Esc 放弃）。

方案同时确立了长列表固定视口滚动机制（Rolling Viewport），首尾滚动指示符（`▲` / `▼`），随光标移动平滑滚动视口，坚决杜绝光标向上回退溢出终端顶部撕裂屏幕的隐患；保障非交互管道（`isatty == 0`）流式行优雅降级与自动化自测试套件全内存按键序列注入验证。

## 技术上下文规范

- **开发语言与编译器**: Swift 6.0+（macOS SDK 27.0+，Apple silicon arm64，原生 `/usr/bin/swiftc -O`）；
- **核心依赖**: 纯 macOS 原生标准库（`Darwin`、`Foundation`），严格禁止引入 ncurses、curses 动态库或外部第三方 Swift Package；
- **配置持久化**: macOS 标准用户应用支持目录下的 Property List（`automnt.plist`），底层格式契约保持不变；
- **自动化测试**: 内置自动化自测试套件（`./automnt --self-test`），通过纯内存队列注入模拟按键流进行无头确定性回归验证；
- **目标运行平台**: macOS 27.0+（Apple silicon arm64）；
- **项目交付形态**: 单源码文件命令行系统工具（`automnt.swift`）与最高优化预编译二进制（`automnt`）；
- **性能与响应目标**: 交互按键解码与原地重绘延迟 < 10ms，50ms 内精准判定独立 Esc 键，无闪烁平滑刷新；
- **架构约束**: 凭据完全由系统钥匙串托管，严禁引入第二个常驻进程，坚持单一真实活动配置。

# 宪法原则与工程准则符合性检查

## 宪法原则审查

- **原则 I（配置只能来自真实探测或显式输入）**: **符合**。交互选单展示的主机与卷宗完全来自系统内核挂载表的实时探测，或来自用户通过单行输入的显式录入；代码中 100% 杜绝任何硬编码私有数据；
- **原则 II（不得引入第二个常驻运行进程）**: **符合**。本特性严格局限于 CLI 前台交互表示层优化，不增加任何辅助常驻守护进程或外部后台任务；
- **原则 III（单一活动配置来源）**: **符合**。配置存储协议与读写路径保持完全一致，不产生分叉配置文件；
- **原则 IV（版本与发布物同源）**: **符合**。源码版本号、二进制版本、配置版本及 Release 严格同步派生（SemVer）；
- **凭据管理约束**: **符合**。密码继续由 macOS 系统钥匙串统一管理，交互层仅在必要时给出温和说明，绝不采集或落盘明文密码。

## 黄金法则审查

- **黄金法则 1（严禁硬编码配置数据）**: **符合**。全量使用通用示例与真实动态探测；
- **黄金法则 2（严禁在测试时代替程序伪造配置）**: **符合**。所有端到端与自测试均通过程序内置逻辑与内存注入驱动；
- **黄金法则 3（文档客观专业无黑话）**: **符合**。全套文档面向第三方客观严谨书写，杜绝任何口语黑话与讨论代号；
- **黄金法则 4（语义化版本管理）**: **符合**。本特性引入向后兼容的高阶交互能力，版本严格规划递增为 `v3.2.0`（MINOR）；
- **黄金法则 5（推送即发布与预编译二进制同步）**: **符合**。发布前强制使用 `-O` 编译最新 Mach-O 二进制，并通过自测。

# 项目工程结构与设计产物

## 特性设计产物目录

```text
specs/003-interactive-selection-ux/
├── spec.md                         # 业务需求规格说明书（已通过双独立评审 Approved）
├── plan.md                         # 本架构实施技术计划
├── research.md                     # Phase 0 技术调研与决策（ANSI 协议、50ms Esc 判定、Rolling Viewport 等）
├── data-model.md                   # Phase 1 交互状态机、按键事件与视口模型
├── quickstart.md                   # Phase 1 端到端快速验证指南
├── contracts/
│   ├── tui-interaction-contract.md # Phase 1 终端 TUI 交互协议契约
│   └── cli-menu-contract.md        # Phase 1 命令行选单架构与流转契约
└── checklists/
    └── requirements.md             # 规格质量检查清单（16/16 全部 Approved）
```

## 代码库物理布局

本项目坚持单文件纯原生架构，所有生产代码与测试代码高度内聚在仓库根目录：

```text
automnt/
├── automnt.swift                   # 单一真理生产源码（含核心状态机、挂载调度、配置管理、TUI 控制器与自测试套件）
├── automnt                         # 最高优化预编译 Mach-O 可执行二进制资产（用于正式交付发布）
├── README.md                       # 面向终端用户的客观开源产品文档
└── specs/                          # Spec Kit 规格体系
```

# 技术设计与演进路线

## Phase 0: 技术调研与关键决策

- 决策已完整沉淀至 [research.md](file:///Users/jiezhengj/Documents/Project/automnt/specs/003-interactive-selection-ux/research.md)；
- 确立了 Darwin `termios` 原始模式与 ANSI 原地重绘标准体系；
- 确立了 50ms 超时非阻塞探测解歧独立 Esc 键机制，根除了按 Esc 假死卡死缺陷；
- 确立了固定视口滚动窗口机制（Rolling Viewport），首尾指示符（`▲` / `▼`），随光标移动滚动，彻底消除终端屏幕撕裂物理隐患；
- 确立了非交互环境管道流式降级与全内存按键序列注入机制。

## Phase 1: 契约制定与数据建模

- 数据模型已完整沉淀至 [data-model.md](file:///Users/jiezhengj/Documents/Project/automnt/specs/003-interactive-selection-ux/data-model.md)；
- 交互协议契约已沉淀至 [contracts/tui-interaction-contract.md](file:///Users/jiezhengj/Documents/Project/automnt/specs/003-interactive-selection-ux/contracts/tui-interaction-contract.md)；
- 选单流转契约已沉淀至 [contracts/cli-menu-contract.md](file:///Users/jiezhengj/Documents/Project/automnt/specs/003-interactive-selection-ux/contracts/cli-menu-contract.md)；
- 快速验证指南已沉淀至 [quickstart.md](file:///Users/jiezhengj/Documents/Project/automnt/specs/003-interactive-selection-ux/quickstart.md)。

## Phase 2: 任务分解预告 (Upcoming in tasks.md)

后续由 `$speckit-tasks` 阶段细化分解原子任务：
1. **基石层改造**: 重构 `TerminalUI` 按键解析引擎（引入 `KeyAction`、50ms 超时非阻塞 Esc 探测、内存队列注入支持）；
2. **通用 TUI 组件重构**: 打造具备 `RollingViewportState` 视口滚动能力的通用交互组件（`promptInteractiveRadio`、`promptInteractiveCheckbox`、`promptExplicitConfirmation`）；
3. **向导（`--init`）全面接入**: 候选主机与动作整合单选直达、从属共享空格多选、更新策略与部署单选；
4. **日常管理（`--config`）全面接入**: 主菜单单选直达、主机二级管理单选、新增方式选择单选、主机顺位两步单选调整、更新策略单选；
5. **破坏性操作接入**: 删除主机与清空配置接入显式空格单选确认防呆；
6. **自测套件扩充与全绿验证**: 扩充覆盖全量场景的内存按键序列注入自动化自测试用例。
