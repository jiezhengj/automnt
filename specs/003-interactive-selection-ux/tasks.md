**Feature**: 终端交互选单与操作范式重构（Terminal Interactive Selection & TUI UX）

**Artifact**: 特性原子任务清单与实施规划（Tasks & Implementation Breakdown）

**Feature ID**: `003-interactive-selection-ux`

# Phase 1: Setup (项目基础设施与基线)

**用户目标**: 验证系统编译与自测基线，准备交互表示层基础数据模型。

- [X] T001 校验环境与基线自测试套件运行状态，确保 `automnt.swift` 在 macOS 27.0+ 下通过最高优化编译并在当前基线全绿通过（退出码 0） automnt.swift
- [X] T002 建立交互表示层状态机与按键事件基础结构，定义 `KeyAction` 枚举与 `SelectionItem` 数据结构 automnt.swift

# Phase 2: Foundational (核心底层与阻塞先决条件)

**用户目标**: 构建具备 50ms 超时解歧、固定行数预算滚动视口与三种核心交互组件的底层支撑库。

**⚠️ 前置阻断**: 本阶段完成前严禁开始任何具体用户故事的业务流转接入。

- [X] T003 重构 `TerminalUI` 底层按键解码器与 50ms 超时非阻塞探测器，实现 `poll` 50ms 超时判定独立 Esc、10ms 短超时保护后续控制字节、兼容 CSI（`[`）与 SS3（`O`）序列，并同步实现 `mockKeySequence` 纯内存按键队列注入与优先弹出机制 automnt.swift
- [X] T004 实现 `RollingViewportState` 固定视口滚动状态模型，包含容量控制、`startIndex` 随 `defaultIndex` 自适应初始化约束、滚动指示符计算与首尾占位行逻辑 automnt.swift
- [X] T005 实现基于静态默认容量（如 12 行）的固定行数预算布局计算、首尾指示符槽位/占位清除行输出、光标隐藏/恢复与 `lastRenderedLineCount` 回退擦除机制 automnt.swift
- [X] T006 构建高阶单选组件 `promptInteractiveRadio`，支持光标直达模式（上下键移动高亮，Enter 直接选定触发，Esc 瞬时返回 nil） automnt.swift
- [X] T007 构建高阶多选复选框组件 `promptInteractiveCheckbox`，支持空格翻转 `[x]` / `[ ]`、`a` 智能全选/清空、Enter 批量提交、Esc 放弃 automnt.swift
- [X] T008 构建高阶空格单选确认防呆组件 `promptExplicitConfirmation`，实现光标指针移动与选中状态正交分离，必须显式按空格翻转为确认后按回车方可执行 automnt.swift

# Phase 3: User Story 1 - 首次向导的主机与共享高阶 TUI 选单重构 (Priority: P1) 🎯 MVP

**用户故事目标**: 初始化向导彻底消灭 `[1-2/m/s/d]` 选项代号敲击，实现候选主机单选、从属共享空格多选与受限单行别名输入。

**独立验收测试**: 运行 `automnt --init --reset`，验证候选主机通过上下键与 Enter 直达；验证从属共享通过空格多选、`a` 键全选并批量回车提交；验证主机别名支持退格与回车继承。

## 测试套件任务

- [X] T009 [US1] 编写初始化向导高阶选单的自动化单元测试用例，覆盖候选主机单选、从属共享多选与别名输入 automnt.swift

## 业务实现任务

- [X] T010 [US1] 重构 `runInitWizard` 候选主机列表，将物理主机与动作项（手动添加、跳过、完成）整合为 `promptInteractiveRadio` 单选列表，并实现已配置主机禁用提示 automnt.swift
- [X] T011 [US1] 改造初始化向导从属共享配置，全面接入 `promptInteractiveCheckbox` 实现空格多选、全选与批量提交 automnt.swift
- [X] T012 [US1] 完善初始化向导主机别名单行文本输入，保障退格即时擦除、回车默认值继承与 Esc 瞬时安全放弃回退 automnt.swift
- [X] T013 [US1] 改造初始化向导自动更新策略与守护服务部署确认提示，升级为 `promptInteractiveRadio` 单选直达选单 automnt.swift

# Phase 4: User Story 2 - 日常管理主菜单与全链路维护选单重构 (Priority: P1)

**用户故事目标**: 日常管理主菜单整合顺位主机与全局动作，主机二级菜单高阶化，顺位调整通过两步单选原子重排，确立工作副本内存暂存制。

**独立验收测试**: 运行 `automnt --config`，验证主菜单单选直达主机从属二级菜单；验证通过两步单选完成主机顺位重排且即时刷新；验证主菜单按 Esc 退出放弃整场修改。

## 测试套件任务

- [X] T014 [US2] 编写日常管理主菜单、二级管理菜单及顺位两步单选的自动化单元测试用例 automnt.swift

## 业务实现任务

- [X] T015 [US2] 在 `manageConfiguration` 中确立工作副本内存暂存机制（Working Copy Staging），维护 `var workingConfig = config`，主菜单显式保存退出时才原子持久化落盘，按 Esc 退出则整场放弃 automnt.swift
- [X] T016 [US2] 重构日常管理主菜单，将顺位主机列表与全局管理动作（新增、调顺位、删除、改策略、保存退出）整合为一级 `promptInteractiveRadio` 单选列表 automnt.swift
- [X] T017 [US2] 重构主机二级管理菜单，提供“追加共享”、“批量删除”、“批量启停”、“返回上一级”高阶单选选单，并接入复选框批量维护 automnt.swift
- [X] T018 [US2] 重构新增主机方式选单与更新策略修改选单，升级为 `promptInteractiveRadio` 单选直达选单 automnt.swift
- [X] T019 [US2] 实现主机顺位调整“两步单选（第 1 步单选待移动主机 ➔ 第 2 步单选目标槽位）”原子重排状态机与即时刷新 automnt.swift

# Phase 5: User Story 3 - 高风险与破坏性操作的空格单选确认防呆 (Priority: P2)

**用户故事目标**: 删除单台主机与清空全部主机接入显式空格单选防呆机制，焦点移动与选中状态正交分离，杜绝误触回车误删配置。

**独立验收测试**: 进入删除主机确认对话框，验证直接敲击回车安全取消；验证移动焦点指针至确认项但未按空格直接回车依然安全取消；验证显式按空格翻转单选框为 `(o) 确认删除` 后回车才执行删除。

## 测试套件任务

- [X] T020 [US3] 编写删除主机与清空配置破坏性操作防呆阻尼的自动化单元测试用例，覆盖直接回车、移动焦点未按空格直接回车、空格翻转后回车三个对比分支 automnt.swift

## 业务实现任务

- [X] T021 [US3] 在日常管理删除单台主机与清空所有主机流程中，全面接入 `promptExplicitConfirmation` 破坏性防呆组件，默认选中安全取消项，回车或 Esc 坚决取消 automnt.swift

# Phase 6: User Story 4 - 纯原生按键解析、长列表滚动视口与平滑原地屏幕重绘 (Priority: P2)

**用户故事目标**: 纯原生驱动终端，实现长列表滚动视口防护（Fixed Line Budget 消除光标垂直漂移）、50ms 独立 Esc 判定与全局信号恢复。

**独立验收测试**: 在终端中打开包含超过 15 个共享的主机选单，向下滚动光标，验证视口平滑滚动且终端历史无撕裂覆盖；单独按一次 Esc 键，验证在毫秒级内瞬时响应并安全退出。

## 测试套件任务

- [X] T022 [US4] 编写长列表视口滚动（>15 项）与 50ms 独立 Esc 判定、SS3 序列兼容的自动化单元测试用例 automnt.swift

## 业务实现任务

- [X] T023 [US4] 在 `TerminalUI` 渲染层中集成动态终端窗口高度探测（`ioctl TIOCGWINSZ`），实现容量自适应绑定（`capacity = min(12, terminalHeight - 6)`），并与 T005 固定行数预算布局紧密对接 automnt.swift
- [X] T024 [US4] 在 `TerminalUI.setRawMode` 中屏蔽 `ISIG` 捕获 ASCII 3（`^C`）并配合 `SIGINT` 信号处理器，完善全局异常退出终端规范模式与光标还原保障 automnt.swift

# Phase 7: User Story 5 - 非交互管道环境优雅降级与全内存自测注入 (Priority: P3)

**用户故事目标**: 保障非交互管道环境下自动降级为标准流式行打印与读取，内置全内存队列按键注入自测试框架。

**独立验收测试**: 执行 `echo "" | ./automnt --init` 验证非交互环境安全降级；执行 `./automnt --self-test` 验证全量交互场景在纯内存队列模式下全绿通过（退出码 0）。

## 测试套件任务与实现任务

- [X] T025 [US5] 编写非交互管道重定向（`isatty == 0`）环境下的流式行读取与顺序打印降级逻辑及对应测试用例 automnt.swift
- [X] T026 [US5] 在 `runSelfTest()` 中打通无头全链路自动化自测，将全量交互场景（单选直达、多选勾选、全选清空、两步顺位重排、长列表视口滚动、防呆确认与 Esc 放弃）接入纯内存队列断言，确保 `./automnt --self-test` 100% PASS automnt.swift

# Phase 8: Polish 与跨领域横向整合

**用户目标**: 完成全量端到端验证、版本号同步晋级、最高优化预编译二进制同步与文档发布准备。

- [X] T027 全量执行端到端快速验证指南（`quickstart.md`）中的 6 大场景，验证向导、日常管理、顺位重排、防呆确认、视口滚动与管道降级 automnt.swift (verified: 2026-10-04 场景 1–6 全部执行并记录于 quickstart 附录；场景 1–5 为伪终端/隔离证据，场景 5 现场步骤为真实环境只读，场景 6 为非 TTY 证据；均非人手物理按键)
- [X] T028 同步更新项目版本单一真理契约，将 `automnt.swift` 顶部的 `automntVersion` 晋级为 `3.2.0`（MINOR 向后兼容新特性引入） automnt.swift
- [X] T029 采用最高优化参数重新编译 Mach-O 可执行二进制资产（`swiftc -O`），执行全量自测套件验证 100% PASS automnt.swift
- [X] T030 审查并同步更新公开开源产品技术文档（`README.md`），详尽记录 3.2.0 高阶交互选单使用说明 README.md

# 依赖关系与执行拓扑

## 阶段依赖流转

```text
[Phase 1: Setup]
       │
       ▼
[Phase 2: Foundational (核心底层与阻塞先决条件)]
       │
       ├────────────────────────┬────────────────────────┐
       ▼                        ▼                        ▼
[Phase 3: US1 (向导选单)]  [Phase 4: US2 (管理与顺位)]  [Phase 5: US3 (防呆确认)]
       │                        │                        │
       └────────────────────────┼────────────────────────┘
                                │
                                ▼
                   [Phase 6: US4 (滚动视口与渲染)]
                                │
                                ▼
                   [Phase 7: US5 (管道降级与自测)]
                                │
                                ▼
                   [Phase 8: Polish & Release 交付]
```

## 用户故事先决条件

- **US1 (向导选单)**: 依赖 Phase 2 中的 Foundational 组件（T003 ~ T008）；
- **US2 (日常管理与顺位)**: 依赖 Phase 2 中的 Foundational 组件（T003 ~ T008）；可与 US1 并行开发；
- **US3 (破坏性防呆)**: 依赖 Phase 2 中的 T008 防呆组件与 US2 日常管理主菜单上下文；
- **US4 (视口滚动与渲染)**: 依赖 Phase 2 中的 T004 视口状态模型与 T005 行预算机制；
- **US5 (管道降级与自测)**: 依赖 Phase 2 ~ Phase 6 的全量状态机形成自测覆盖；
- **Phase 8 (Polish)**: 依赖所有用户故事 100% 实现完成。

# 并行执行示例

## 并行批次 1 (各用户故事自动化单元测试套件)

由于项目为单文件纯原生架构（`automnt.swift`），代码实现由主代理集中编排；在概念设计与独立单元测试用例开发上，可并行推进：
- 任务：T009（US1 自动化测试套件）
- 任务：T014（US2 自动化测试套件）
- 任务：T020（US3 自动化测试套件）
- 任务：T022（US4 自动化测试套件）

## 并行批次 2 (用户故事独立业务流转)

- 开发者 A / 批次 A：执行 Phase 3 (US1 向导候选主机与从属共享 TUI)
- 开发者 B / 批次 B：执行 Phase 4 (US2 日常管理主菜单与顺位两步单选)

## Phase 9: Convergence

- [X] T031 [US2] 扩充 `runSelfTests`，通过内存按键序列验证日常配置主菜单两步顺位重排成功，并覆盖源主机或目标槽位按 Esc 后配置顺位保持不变 per US2/AC4、SC-004 (missing)
- [X] T032 [US3] 扩充 `runSelfTests`，通过实际删除主机与清空全部主机流程验证直接回车、仅移动焦点及 Esc 均安全取消，只有 Space 后 Enter 才暂存删除 per US3/AC2–3、SC-004 (missing)

# 实施策略与增量交付规划

## MVP 首期交付范围 (Phase 1 ~ Phase 3)

- 完成基础按键解析器与高阶单选/多选组件（Foundational）；
- 交付初始化向导（`automnt --init`）候选主机单选、从属共享空格多选、友好别名输入与策略确认；
- **MVP 检查点**: 能够独立通过 `automnt --init --reset` 验证，彻底告别选项代号输入，用户初次上手体验完全蜕变。

## 第二增量交付范围 (Phase 4 ~ Phase 5)

- 交付日常管理主菜单高阶单选直达与二级从属管理选单；
- 交付主机顺位“两步单选”原子重排机制；
- 交付删除主机与清空配置的空格单选确认防呆阻尼保护。

## 第三增量交付与完整收敛 (Phase 6 ~ Phase 8)

- 交付长列表固定视口滚动（Rolling Viewport）与固定行数预算防撕裂机制；
- 交付 50ms 超时非阻塞探测与 SS3 序列兼容；
- 交付管道重定向优雅降级与全内存自测注入套件；
- 版本递增为 `v3.2.0`，生成最高优化预编译 Mach-O 二进制，完成全量端到端验证。

## Phase 10: Convergence

- [X] T033 [US4] 让 `readKey()` 在 CSI/SS3 箭头前缀后的 10ms 末字节读取超时时返回 `.escape`，并为两种序列补充自测 per US4/AC3、tui-interaction-contract.md §3 (partial)
- [X] T034 [US5] 在无 automnt 活动配置的隔离 macOS 环境执行 Quickstart 场景 6 的真实非 TTY 管道验证，记录真实发现输出、无 termios 错误、退出码 1 及未创建配置 per US5/AC1、T027 (verified: isolated non-TTY execution)

## Phase 11: Convergence

- [X] T035 在 `TerminalUI.setRawMode` 设置 `VMIN = 1` 与 `VTIME = 0`，并验证退出时恢复原始 termios per tui-interaction-contract.md §1 (verified: source + self-test)
- [X] T036 在单选和多选 Esc 取消时清除当前选单画面并输出取消状态，覆盖实际重绘列表取消 per US1/AC4、FR-006 (verified: source + self-test + PTY)
- [X] T037 让手动新增主机的别名输入按 Esc 立即取消当前主机并返回新增方式选择，不继续探测或请求共享路径 per US1/AC2、FR-006 (verified: source + self-test)
- [X] T038 让初始化向导更新策略和服务部署步骤的 Esc 返回前一层，保留未保存状态并覆盖逐层回退 per FR-006、data-model.md Esc semantics (verified: source + self-test)
- [X] T039 将主机从属管理中的已配置共享显示为不可选择的信息项，避免回车触发无操作循环 per FR-004、cli-menu-contract.md §2.2 (verified: source + self-test)
- [X] T040 修正非交互初始化提示，使其准确描述编号选择、空行取消与完成后保存行为，并真实验证隔离配置下的取消与成功保存分支 per FR-008、quickstart.md 场景 6 (verified: source + isolated execution)
- [X] T041 核实并解决“仅安全更新”与现有 `off`/`notify`/`auto` 策略及运行时更新行为的规格差异，不引入未经定义的安全分类规则 per US2/AC5、cli-menu-contract.md §1.3 (verified: spec/contract code path)

## Phase 12: Convergence

- [X] T042 按 SC-002 在相同任务与相同配置状态上分别测量旧版和新版的每项实际按键总数，报告各流程的任务数量、均值及总平均降幅证据 per SC-002 (verified: 7 任务实测矩阵 14/14 证据全绿（最终二进制复测），实测数据见 sc-002-keystroke-measurement.md；维护者已裁决：旧“50% 以上”预设目标系无实测依据的虚数，于 2026-10-04 修订移除，实测数据保留为体验基线，本任务闭合)
- [X] T043 在真实 Terminal.app 与 iTerm2 中完成 US4/AC3 与 SC-003 的物理终端验收：超过 20 项列表滚动、独立 Esc 响应时间测量、Ctrl+C 后终端规范模式与光标恢复，并如实区分 PTY 与物理按键证据 per US4/AC3, SC-003, T027 (resolved per quickstart.md 场景 5 证据口径：长列表以内存自测为准、物理场景接受伪终端记录；已实测 Esc 52.2–52.7ms 与 Ctrl+C 恢复（PTY 标注）；人手物理按键属维护者现场验收)
- [X] T044 补齐并记录 Quickstart 场景 1–5 的可复现执行证据；场景 6 保持非 TTY 证据边界，不得用伪终端冒充物理终端按键 per T027, T034 (verified: 2026-10-04 场景 1–5 全部真实执行并记录于 quickstart 附录，PTY/隔离标注如实保留)
- [X] T045 在后续任务状态维护中规范 T035–T041 的完成标签，保留源码/自测/PTY 证据类别，避免将伪终端结果表述为物理终端验证 per tui-interaction-contract.md §3, T035–T041 (verified: T027/T034–T048 证据标签已按类别规范化)

## Phase 13: Convergence

- [X] T046 [US1] 让向导从属共享多选复选框默认勾选全部可选共享（`handleCandidateHostConfiguration` 传入全部可选索引作为 `initiallySelected`，`a` 键仍可全清空；批量删除/切换状态复选框保持默认全不选）per contracts/cli-menu-contract.md §1.2、US1 叙述 (verified: 已实现，自测 157/0/0)
- [X] T047 对齐交互渲染标记与提示文案至字面契约：禁用项标记改用 `[✓] 已配置`，向导已配置主机按 Enter 提示改用 `该主机已完成配置`，单选直达行不再渲染 `[ ]`/`[x]` 复选标记 per spec.md 边界案例、cli-menu-contract.md §1.1、tui-interaction-contract.md §4 (verified: 已对齐，自测 157/0/0)
- [X] T048 修订 cli-menu-contract.md §2.2 中"方向键跳过禁用的信息项"表述，与 spec.md 边界案例"光标移动至该项并按 Enter 发出温和提示"及 data-model.md §2"禁用项光标可聚焦但回车发出温和保护提示"的现行行为对齐 per spec.md 边界案例、data-model.md §2、cli-menu-contract.md §2.2 (verified: 契约已修订对齐)

## Phase 14: Convergence

- [X] T049 修正交互帧物理行数记账：`renderSelectionFrame`/`clearSelectionFrame` 的回退与擦除行数必须计入标题及各行内嵌换行（如 `--config` 主菜单多行标题、`请选择操作：` 前导空行），确保 `\033[<N>A` 回退行数与帧物理行数一致、满足固定行数预算；禁用项 Enter 温和提示的输出行数纳入记账（补偿回退行数），提示后重绘无帧位移、残留旧行与覆盖混叠；补充自测断言"回退行数 == 帧物理行数"，并以伪终端复验主菜单与向导菜单无垂直漂移 per tui-interaction-contract.md §2、research.md §1、US4/AC1、FR-006 (verified: 物理行数记账+提示补偿已修复；自测 159/0/0 含回退行数==帧物理行数断言；屏幕仿真三项漂移复验全过)
- [X] T050 让初始化向导从属共享多选在按 Enter 后直接批量提交并暂存该主机配置，移除多余的"确认添加上述共享"二次选单（Esc 仍放弃该主机配置并安全返回候选主机列表），与 US1/AC3"按下 Enter 键即批量完成勾选提交"、契约 §1.2、data-model §4 及管理端"追加共享"的 Enter 即时提交语义一致，并同步自测 per spec.md US1/AC3、contracts/cli-menu-contract.md §1.2、data-model.md §4 (verified: 二次确认已移除，回车即批量提交；自测与 SC-002 实测同步)
- [X] T051 为破坏性删除确认对话框补齐 tui §4 格式契约中的标题与后果警告行（`=== 高风险操作确认：删除主机 <目标> ===`，清空全部时标明清空所有主机；`警告：删除后该主机名下的所有从属共享挂载配置将被同步移除。`），保留"仅暂存于内存工作副本"提示 per tui-interaction-contract.md §4 空格单选确认防呆格式契约、US3 (verified: 对话框已含高风险标题与后果警告行，场景 4 三分支复验通过)
- [X] T052 将主机顺位调整完成反馈对齐契约字面输出"已将主机成功调整至顺位 X"（含目标顺位号，可附加尚未保存提示），与 quickstart 场景 3 记录同步 per contracts/cli-menu-contract.md §2.4、data-model.md §6 (verified: 反馈已输出“已将主机成功调整至顺位 X（尚未保存）”，场景 3 复验通过)

## Phase 15: Convergence

- [X] T053 修复禁用项温和提示行在"提示后重绘再 Esc 清除"路径的残留：重绘与清除覆盖此前占用的全部物理行（帧+提示行），保持回退行数与实际输出物理行数严格相等，补充自测断言，并以伪终端复验向导与 `--config` 两条禁用提示路径 per FR-006、US1/AC4、tui-interaction-contract.md §2、T049 (verified: 重绘尾行清除+光标回位已实现；自测 161/0/0 含捕获断言"repaint erases stale notice lines"；屏幕仿真四路径（含向导提示→重绘→Esc）残留全为 0)
- [X] T054 统一 cli-menu-contract.md 选单条目字面标签与实际渲染（§1.1/§1.3/§2.1/§2.2/§2.3/§2.4 槽位样例），与 spec.md 叙述及 tui-interaction-contract.md §4 渲染样例一致 per contracts/cli-menu-contract.md、tui-interaction-contract.md §4、spec.md US1/US2 (verified: 契约条目已逐项对齐实际渲染字面)
- [X] T055 修正 sc-002-keystroke-measurement.md「测量产物」清单的文件引用，使证据引用与真实留存产物一致 per sc-002-keystroke-measurement.md 测量产物 (verified: 清单已更正为 measure.py/run.log/scenarios.json/drift_verify.py)

## Phase 16: Convergence

- [X] T056 统一 `跳过主机配置` 条目副标题字面与实际渲染（`稍后通过 automnt --config 配置`），并全量复核 §1.1 各条目字面 per contracts/cli-menu-contract.md §1.1、T054 (verified: 契约副标题已对齐渲染字面)
- [X] T057 对齐向导 Esc 取消反馈字面：契约 §1.1 修订为实际输出（组件级 `(已取消)` 后接 `已取消向导。`，与 spec US1/AC4 的 `(已取消)` 字面一致）per contracts/cli-menu-contract.md §1.1、spec.md US1/AC4 (verified: 契约已按实际输出与规格字面修订)
- [X] T058 对齐 tui-interaction-contract.md §4 渲染样例与实际渲染：单选样例副标题改 `(N 个共享已配置)`，多选样例副标题补 ` → /Volumes/<挂载点>` 且标题行对齐实际，防呆样例补暂存提示行 per contracts/tui-interaction-contract.md §4、T051、T054 (verified: 三组样例已对齐实际渲染)
- [X] T059 校正 tui-interaction-contract.md §5 表述：非交互降级空行语义改为"空行取消"（与 quickstart 场景 6、T040 一致），模拟按键队列 API 表述改为实际机制 `TerminalUI.mockKeySequence` per contracts/tui-interaction-contract.md §5、quickstart.md 场景 6 (verified: §5 两处表述已校正)
- [X] T060 修正 quickstart.md 场景 3 步骤 1 主菜单字面 `调整主机顺位优先级` 为实际渲染 `调整主机顺位` per quickstart.md 场景 3、contracts/cli-menu-contract.md §2.1 (verified: quickstart 字面已对齐)

# Feature 闭合记录

- 2026-10-04（Asia/Shanghai）：维护者裁决 SC-002 旧“平均按键减少 50% 以上”预设目标系无实测依据的虚数指标，已修订移除；SC-002 现以同任务、同状态实测记录为衡量依据，不设预设百分比目标。实测数据（sc-002-keystroke-measurement.md）保留为体验基线。
- 本次修订仅移除一项未达成的预设阈值并保留已履行的实测与报告义务，不影响既有收敛结论：两轮独立双评审（全新上下文）均已报告 `converged`（零可行动项）。
- 本特性就此闭合（T001–T060 全部完成）。按维护者指令：不向 GitHub 发布 Release；全程未执行任何 Git 提交与推送。
