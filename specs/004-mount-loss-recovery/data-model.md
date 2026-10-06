**Feature**: 挂载丢失自动恢复（Mount Loss Auto-Recovery）

**Artifact**: 数据模型与状态机（Data Model & State Machine）

**Feature ID**: `004-mount-loss-recovery`

**Created**: 2026-10-05

# 1. 卷恢复状态 (MountRecoveryState)

## 实体定义

按**卷粒度**记录每个“配置启用的共享卷”的自动恢复资格与当前状态；存于独立附属状态文件 `mount-recovery-state.plist`（与活动配置同目录、0600、程序独占），**不是**活动配置的一部分，可整体丢弃重建（FR-010）。

| 字段 | 类型 | 约束与说明 |
| :--- | :--- | :--- |
| `volumeKey` | 标识（主机 + 共享资源标识） | 指向活动配置中的启用卷；配置删除后其状态条目在下次重建时清除 |
| `state` | 枚举：`attached` / `lost` / `pending-recovery` / `recovering` / `suppressed` | 与 §4 状态机逐一对应（`lost`=卷在表但失效；`recovering`=本轮正在尝试恢复）；信号缺失/状态损坏的缺失卷不引入独立枚举，一律归入 `suppressed`（保守方向，§4 守恒规则） |
| `suppressionBoundary` | 会话边界引用（见 §3） | `suppressed` 时必填：解除条件 = 网络上下文或登录会话变化（先到者） |
| `repairEjectEvidence` | 布尔 / 证据摘要 | 缺失前存在会话丢失证据 → 修复性弹出，禁止进入 `suppressed` |
| `everHealthyMounted` | 布尔 | **挂载账的持久表示（FR-002③/④ 的判别字段）**：一旦观察到该卷处于健康挂载即置 `true`，此后**不再自动清除**（除配置删除）。缺失卷只有在此字段为 `true`（=“曾健康挂载过”）时才可进入 `suppressed`（FR-002③）；为 `false`（=从未挂载过）时按 FR-002④ 走基线段挂载并 MUST NOT 进入 `suppressed`。**该字段必须持久化**，不得仅由当前快照推导——卷已缺失时快照无法回溯历史 |
| `attemptCount` | 整数 | 当前恢复判定轮已尝试次数；成功或边界解禁时归零；受有界重试上限约束 |
| `updatedAt` | 时间戳 | 每次状态迁移刷新 |

## 校验与降级规则

- 文件权限 0600；程序独占读写；使用者手工修改视为无效输入。
- 含 `schemaVersion` 字段：版本未知或解析失败 → **丢弃全部状态**并按保守方向重建（绝不依据坏状态恢复）。**丢弃重建的正确方向**：状态不可读 → 该卷按 `suppressed`（保守，本会话不自动重挂，交兜底入口），**MUST NOT** 被当作 FR-002④ 的“从未挂载过”而自动挂载（否则状态损坏会变成误恢复通道，违背 FR-010）。
- **文件不存在 ≠ 状态损坏**：全新安装/首次运行时状态文件缺失属正常空态，此时配置中的启用卷尚无任何记录，按 FR-002④ 正常挂载。
- **`everHealthyMounted=false` 只允许在状态可读时成立**：状态不可读时一律按保守方向处理，不得推断为“从未挂载过”。
- 任何字段缺失/自相矛盾（如 `suppressed` 缺边界）→ 该条目降级为 `suppressed`（保守方向）。
- 状态丢失的后果上限：多恢复一次的判断被推迟、或少恢复一次——永远不是“覆盖使用者弹出”。

# 2. 恢复尝试记录 (RecoveryAttempt)

| 字段 | 类型 | 约束与说明 |
| :--- | :--- | :--- |
| `volumeKey` | 标识 | 同 §1 |
| `timestamp` | 时间戳 | 一次恢复判定轮的一次尝试 |
| `outcome` | 枚举：`mounted` / `host-unreachable` / `share-rejected` / `credential-failure` / `suppressed-skipped`（后四项为失败/跳过类，`suppressed-skipped` 用于会话抑制跳过的去重） | 供有界重试与通知去重判定；规格 §关键实体中的“结果类别”即此枚举 |
| `sequence` | 整数 | 同一轮内递增；达到上限即停（FR-005） |

- 保留策略：每卷仅保留最近 5 轮摘要（滚动丢弃），可整体丢弃，不影响恢复资格判定。仅保留必要字段（状态、边界引用、计数、时间戳），不含凭据与配置数据副本。

# 3. 会话边界 (SessionBoundary)

| 字段 | 类型 | 约束与说明 |
| :--- | :--- | :--- |
| `networkIdentity` | 网络上下文标识 | **新建**能力的产物（现状无可复用的网络身份机制，见 spec.md §Assumptions）；与 `loginEpoch` 并列构成边界 |
| `loginEpoch` | 登录会话纪元 | 登录时递增/重置 |
| `activeBoundary` | 二者并存 | 任一变化即构成“边界事件”：清除全部 `suppressed` 条目，卷恢复可评估资格（FR-004） |

# 4. 恢复生命周期状态机

```text
[attached 挂载健康]
   │ 主机/网络不可达，卷失效（挂载仍在）
   ▼
[lost 死卷滞留] ──产品超时强制清理（写清理账）──▶ [pending-recovery 待恢复]
   │                                                      │
   │ 主机可达 + 事件评估                                  │ 主机可达 + 事件评估
   ▼                                                      ▼
[recovering 恢复中] ──成功──▶ [attached]    有界重试用尽 ──▶ 失败 → 通知/一键兜底

[attached] ──使用者健康时弹出（本会话）──▶ [suppressed 会话抑制]
                                              │ 网络上下文变化 或 重新登录（先到者）
                                              ▼
                                    [清除抑制 → 缺失待评估 → 恢复]

[lost 死卷滞留] ──使用者弹掉死卷（修复动作，repairEjectEvidence=true）──▶ [pending-recovery]
```

- **守恒规则**：`recovering` 只由事件评估发起（无时钟/轮询路径）；`suppressed` **只能**由“健康时被弹出”进入，且**必须同时满足 `everHealthyMounted=true` 与状态可读**（FR-002③）——`everHealthyMounted=false` 的缺失卷按 FR-002④ 走基线段挂载，状态不可读者按 FR-010 走保守方向，二者均**绝不**进入 `suppressed`；信号缺失时缺失卷一律按 `suppressed` 处理（保守方向）。**任何原因导致的成功挂载都必须清除该卷的 `suppressed` 条目**，避免陈旧抑制在边界之前长期阻断后续恢复，并将 `everHealthyMounted` 置为 `true`。

- **FR-002 信号 → 状态映射（逐条对应，消除歧义）**：

| FR-002 来源 | 判别前提 | 目标状态 | 后继迁移 |
| :--- | :--- | :--- | :--- |
| ① 卷在表但失效 | 健康探测失败/会话丢失 | `lost` | → 清理（写清理账）→ `pending-recovery` |
| ② 卷缺失 + 在清理账 | 产品自清记录命中 | `pending-recovery` | → 主机可达 → `recovering` |
| ③ 卷缺失 + 健康弹出 | 状态可读 且 `everHealthyMounted=true` 且无修复证据 | `suppressed` | → 边界事件 → 清除抑制 → 重新评估 |
| ④ 卷缺失 + 从未挂载 | 状态可读 且 `everHealthyMounted=false` | 不进状态机（无历史），按基线段挂载 | 挂载成功 → `attached` 且置 `everHealthyMounted=true` |
| 信号不可读/状态损坏 | 解析失败/schemaVersion 未知 | `suppressed`（保守） | → 边界事件或手动入口兜底 |

- `unknown` 不是独立状态：信号不可读统一归入 `suppressed`，故枚举与 FR-002 全部分类一一覆盖、无遗漏、无命名冲突。

# 5. 活动配置新增字段 (AutomntConfig 扩展)

| 字段 | 类型 | 默认值 | 说明 |
| :--- | :--- | :--- | :--- |
| `auto_mount_recovery` | 布尔（缺省视为 true） | `true` | FR-008 开关；`false` 时恢复判定与抑制不执行，挂载评估回落至基线行为；随既有原地升舱迁移 |

- 该字段是唯一获准的配置结构增量（规格 §排除边界 明确豁免 FR-008 开关与 FR-010 最小状态两项）；不改变既有字段、不迁移既有语义。
- **实现陷阱（必须处理）**: 配置写回走“白名单 + 保留未知键”合并路径（`managedConfigKeys(.root)` → `mergeConfigPlistValue` / `encodeConfigPreservingUnknownFields`）。若 `auto_mount_recovery` 未加入该白名单，写回时会被当作未知键而**保留原值**，开关将静默失效——T002 必须同步更新白名单并断言开关可真正落盘生效。

# 6. 关系与正交性保障

- `MountRecoveryState` / `RecoveryAttempt` 与活动配置**仅通过卷身份引用**关联，不内嵌、不复制配置数据——恢复执行读取的永远是同一份活动配置（Constitution III）。
- 状态文件与配置文件分路径、分职责：配置 = 使用者可编辑的业务真理；状态 = 程序可丢弃的运行时记忆。
- 通知去重依据 `RecoveryAttempt.sequence`（每轮至多一条，US3 AC3），不引入额外消息队列。
