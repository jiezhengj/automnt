# 方案 A 独立权限状态

2026-10-13 已接入独立授权 LaunchAgent 的 bind → unregister → 空 transfer verify 两阶段预检；它不挂载或改 owner，后台启用/接管以前必须成功。最终 Apple Development 构建和签名门禁通过，真实签名诊断当前因未授权返回失败；尚未证明 helper 自身书签在 GUI 退出/登录/重启后有效，T081/T082 保持未勾选。当前结果见 [方案 A 实施证据](option-a-authorization.md)，下述旧编排测试不能替代此验收。

# 后台服务与 helper 编排证据（T009-c2）

本文件记录 `BackgroundEvaluator`（launchd helper 单轮评估）在 T009-c2 之后的编排契约、
行为等价性证据与仍未验证边界。逐卷判定规则的唯一实现见
`Sources/AutomntCore/RecoveryVolumeDecision.swift`；本文件不重复规则定义。

## 改动前后的编排归属

| 关注点 | 改动前 | 改动后 |
| --- | --- | --- |
| 逐卷动作判定（抑制/deferred/尝试上限/重试间隔/健康覆盖） | `BaselineMountDecision.decide` 自行实现分支；planner 另有一份 | `RecoveryVolumeDecisionPolicy.judge` 单一实现，二者均委托 |
| superseded 路径剔除 | 仅 CLI planner 有；helper 缺失 | `RecoverySupersededPolicy.supersededIdentities` 单一实现，planner 与 helper 共用 |
| 挂载点状态门（occupied/unavailable/其他身份） | `BaselineMountDecision` 内联 | 保留为 `BaselineMountDecision.block(path:identity:)`，属 I/O 前置校验而非恢复规则 |
| async TCP 探活、worker 子进程、EvaluationPermit、组件级持久提交 | helper 内联 | 仍归 helper，抽出可注入接缝 `BackgroundVolumeEffects` |

`BaselineMountDecision.decide` 现在只做三件事：挂载点状态门 → 构造 `RecoveryVolumeFacts/Context`
→ 翻译 `RecoveryVolumeDecision`。已核对仓库内无第二处 `judgeRecoverySignal` /
`MissingVolumeRecoveryPolicy.mayMount` / `protectedByPeer` 的编排调用（CLI 自测断言中的直接调用
属既有回归断言，不构成编排）。

## 判定优先级（与裁决 A 一致）

1. **手动恢复**（`manualRecovery && !present`）→ 强制「从未挂载」；
2. 状态不可读 → 保守抑制（FR-010）；
3. 缺失卷且账本 `.suppressed` → 会话抑制（**先于** `everHealthyMounted`，只传播 `state+boundary`）；
4. `judgeRecoverySignal`（清理账 / 修复证据 / 曾健康挂载 / 从未挂载）；
5. 同路径对端抑制（仅当会话边界存在，与改动前一致）；
6. 在表且可达 → 健康证据覆盖（未知健康不证明健康、不授予清理许可）；
7. 尝试上限 → 重试间隔 → 抑制回落 → 可达性 → 挂载许可（顺序与改动前逐条对齐）。

## 行为等价性证据

- 差分预言机：`Tests/AutomntCoreTests/BaselineDelegationEquivalenceTests.swift` 内嵌改动前
  `BaselineMountDecision.decide` 实现（仅测试用），**345,600 组输入、0 不一致**，并断言矩阵规模
  以防循环被改小后静默通过。
- 迭代中实际抓出并修正 4 处分歧（nil-config 许可、`allowRecovery` 原始值、尝试上限需配置存在、
  deferred 先于抑制回落）——预言机确实有判别力，而不是恒真。
- 有意行为变化 1 条（见下），其余 helper 可观察结果逐条不变。

## 有意行为变化（裁决 A）

`UserEjectCommit.apply` 只写 `state = .suppressed` + `suppressionBoundary`，**不写**
`everHealthyMounted`。「首次即被用户弹出」的记录在改动前：CLI 侧落 `.neverMounted` 并被重挂，
helper/worker 侧（原有 `.suppressed` 门）判抑制。本轮统一为抑制，方向是**收紧**：

- 用户可见变化：CLI 的非手动轮次不再重挂「首次即被弹出」的共享卷；`--config → 立即重新挂载`
  （manual）不受影响，仍可恢复。
- 依据：Lead 裁决 A；`BaselineMountDecision` 原有 `.suppressed` 优先门；`UserEjectCommit` 的
  写入语义；FR-002③ 与 SC-002「健康弹出后本可达会话零重挂」。
- 影响面：`--self-test` 295 项全绿、4 条「manual 仍可恢复」类断言保持绿，无断言被修改或放宽。

## 仍未验证边界

- 无真实 SMB/NetFS/磁盘仲裁客户端；表驱动测试全部注入 runner/探活/状态文件与账本。
- 未跑真实 worker 子进程、`PermissionStore.resolve()` 签名授权、Keychain 凭据读取、
  真实 `EvaluationPermit`、真实 launchd 触发。
- helper 的 `supersededFiltered` 在单主机轮次内恒为空操作（配置校验禁止同主机重复挂载点）；
  跨主机 superseded 仅由 CLI/planner 路径覆盖，未在真实 helper 进程验证。
- GUI（`apps/Automnt`）侧未消费共享判定；本任务未改 `apps/`。
