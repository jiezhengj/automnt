# Bug Fix: 无证据的挂载丢失被判成“用户弹出”，整段会话不再自动恢复

- **Slug**: mount-loss-misjudged-as-eject
- **Fixed**: 2026-11-25
- **Assessment**: [`assessment.md`](assessment.md)（verdict: valid，severity: high）
- **Authorized by**: 维护者 2026-11-25「好」（回应 m01851 结尾的三条修复提议）

## Summary

缺失判定原先只有一条证据：`everHealthyMounted == true` 即视为“使用者在卷健康时弹出”，进入会话级抑制。它只证明该卷曾经挂成功过，不证明是谁移除的，于是任何一次会话级死亡（SMB 空闲会话失效、Tailscale 中继抖动、睡眠唤醒后会话丢失）都被当作使用者意图，整段可达会话内不再恢复。抑制的解除条件只有会话边界变化或重新登录，同一天同一 Wi-Fi 下两者都不会发生，所以卷一整天不回来，界面也不解释。

修复把“弹出”从一条推断改成两类可观测证据，并把证据不足的方向翻转为“按丢失处理”：

1. **证据化弹出**：`UserEjectCommit.apply`（产品自身的弹出动作）与新增的应用内卸载事件记录 `recordObservedUnmount`，两者都写 `suppressionHasEvidence = true`。缺少证据的抑制不再成立。
2. **无证据即恢复**：新增信号 `.lostWhileHealthy`（缺失 + 曾健康 + 无证据），`MissingVolumeRecoveryPolicy` 按可恢复处理；判定层第 2 步只在 `suppressionHasEvidence || !hostReachable` 时短路成会话抑制，于是“抑制期网络恢复后重试一次”由判定自然得出，不引入新字段、不新增写入路径，也不形成持续重试（仍受既有尝试上限与重试间隔约束）。
3. **探活预算**：默认 1000 → 3000 毫秒，读到的旧默认值 1000 视为“未自定义”并静默迁移，显式取值原样保留。中继路径（单程 300–700 毫秒）上 1 秒预算必然超时。
4. **快捷挂载的解释**：`.suppressedForThisSession` 从“不计入”改为 `.ejected` 原因，被本会话弹出的共享会出现在摘要与明细子菜单里，而不是点了没反应。

## Changes

| 文件 | 变更 |
| --- | --- |
| `Sources/AutomntCore/RecoveryState.swift` | 新增信号 `case lostWhileHealthy`（`isRecoverable == true`、`isSuppressed == false`）；`judgeRecoverySignal` 缺失分支的 `everHealthyMounted == true → .healthyEject` 改为 `→ .lostWhileHealthy`；`MountRecoveryVolumeRecord` 新增 `suppressionHasEvidence: Bool = false`（CodingKey `suppression_has_evidence`），手写 `init(from:)` 全字段 `decodeIfPresent ?? 默认`，公开 `init` 同步补参数 |
| `Sources/AutomntCore/MissingVolumeRecoveryPolicy.swift` | `.lostWhileHealthy` 与 `.productCleanup`/`.repairEject` 同组：`enabled` 时可挂 |
| `Sources/AutomntCore/RecoveryVolumeDecision.swift` | `judge` 第 2 步（缺失 + `record.state == .suppressed`）增加条件：`record.suppressionHasEvidence || !facts.hostReachable` 才回 `.sessionSuppressed`，否则继续走信号判定 |
| `Sources/AutomntCore/RecoverySession.swift` | `protectedByPeer` 只认 `suppressionHasEvidence` 的同边界 `.suppressed` 记录，其余（含仅有曾健康记录）不保护对端 |
| `Sources/AutomntCore/UserEjectCommit.swift` | `apply` 写 `suppressionHasEvidence = true`；新增 `recordObservedUnmount(identity:directory:observedAt:)`，不校验在途 worker 意图，写抑制 + 当前边界 + 证据位并清清理账 |
| `Sources/AutomntCore/Configuration.swift` | `defaultProbeTimeoutMs = 3000`、`legacyProbeTimeoutMs = 1000`；`HostConfig` / `NetworkProfile` 的默认值与解码统一经 `migratedProbeTimeout(_:)` |
| `Sources/AutomntCLI/Entry.swift` | 新建主机与帮助输出里的 `?? 1000` 改为 `?? defaultProbeTimeoutMs` |
| `Sources/AutomntCore/QuickMountOutcome.swift` | `Failure.Reason` 新增 `.ejected`；`.suppressedForThisSession → .ejected`（原为 nil） |
| `apps/Automnt/AutomntApp.swift` | 新增 `unmountObserver`、`startUnmountObservation()`（应用级 `NSWorkspace.didUnmountNotification`，在 `bootstrapResidentServices()` 里注册，不挂窗口）、`recordObservedEject(atPath:)`、`lastRoundObservedHealthy(_:in:)`、`configurationShares(atPath:in:)` |
| `apps/Automnt/Views/MainWindowView.swift` | `ShareRowView.quickMountReasonLabel` 增加 `.ejected` → “Ejected in this session” |
| `apps/Automnt/Resources/Localizable.xcstrings` | 新增 `Ejected in this session` × 9 语言（460 → 470 key） |
| `specs/004-mount-loss-recovery/spec.md` | FR-002 拆出“弹出证据”口径（④ 曾健康无证据＝丢失、⑤ 从未挂载）、FR-003 证据不足方向翻转、FR-004 无证据抑制即时放行、新增 FR-011 探活预算下限与静默迁移，追加变更记录 |
| `specs/004-mount-loss-recovery/contracts/mount-recovery-contract.md` | 判别表重写为 7 行（新增证据位判定与丢失分支），补充弹出证据口径与无证据抑制放行 |
| `specs/004-mount-loss-recovery/data-model.md` | 新增 `suppressionHasEvidence` 字段说明，`everHealthyMounted` 语义改为“不再单独构成弹出证据”，状态映射表与守恒规则同步 |
| `Tests/**` | 见下节 |

## Diff Highlights

```swift
// Sources/AutomntCore/RecoveryState.swift — 曾健康不再是弹出证据
if record?.everHealthyMounted == true { return .lostWhileHealthy }
```

```swift
// Sources/AutomntCore/RecoveryVolumeDecision.swift — 无证据的抑制不再生效
if !facts.presentInMountTable, let record, record.state == .suppressed {
    if record.suppressionHasEvidence || !facts.hostReachable {
        return RecoveryVolumeJudgment(signal: .healthyEject, decision: .sessionSuppressed)
    }
}
```

```swift
// apps/Automnt/AutomntApp.swift — 卸载事件：本轮见过健康、宿主可达、属于已配置共享
let healthy = candidates.filter { lastRoundObservedHealthy($0.identity, in: authorization.url) }
for candidate in healthy where try await probe(candidate.host) { chosen = candidate; break }
```

## Tests

`swift test`：AutomntCoreTests 109、AutomntPlatformTests 221、AutomntCLITests 33，全部通过。

新增：

- `RecoverySuppressedRecordTests.legacyStateFileDecodesWithoutEvidenceFlag` — 旧状态文件缺 `suppression_has_evidence` 解码为 false，写入后读回 true。
- `RecoverySuppressedRecordTests.suppressionWithoutEvidenceRecoversOnceTheHostIsReachable` — 无证据抑制 + 宿主可达 → 挂载一次。
- `ConfigurationContractTests.legacyProbeTimeoutIsRaisedButExplicitValuesAreKept` — 缺失 → 3000；等于旧默认 1000 → 3000；5000 / 500 原样保留；`NetworkProfile` 同样迁移。
- `QuickMountOutcomeTests.sessionEjectIsExplainedRatherThanSilent` — `.suppressedForThisSession → .ejected`，与 `.refused` 混排时各自保留原因。

修改（原断言锁定的是旧规则）：

- `MissingVolumeRecoveryTests`：「仅 everHealthy」由 `.suppressed` 改为 `.mount`，有证据抑制单独断言。
- `BaselineDecisionTests`、`ManualMountCommitTests`、`RecoveryCleanupTests`、`RecoveryDecisionBindingTests`、`RecoveryNotificationTests`、`RecoveryRoundTests`、`RecoverySessionCommitTests`、`RecoverySessionTests`、`RecoverySuppressedRecordTests` 等 10 个文件的夹具补 `suppressionHasEvidence: true`（共 18 处），区分“有证据弹出”与“仅有曾健康记录”。
- `BaselineDelegationEquivalenceTests` 的对照预言机改为“`.suppressed` 且带证据才抑制”，文件头注明这是 2026-11-25 的有意规则变更。
- `Tests/AutomntPlatformTests/RecoveryBoundaryConsistencyTests`：新增“仅曾健康不再保护对端”。
- `RecoveryRoundTests.corruptStateNeverFallsThroughToRemountOnceReadableAgain` 重写为“保守抑制无证据 → 第二轮转 recover，信号 `.lostWhileHealthy`”。

## Local Verification

- `swift build` / `swift test` 全绿（见上）。
- `bash scripts/build.sh`：本地化闸门 PASS（277 条源字符串 × 9 语言）、签名 `Apple Development: jie.zhengj@qq.com (8SDSF987N2)`、版本仍 3.6.0（未递增）。
- `./automnt --self-test`：305 passed, 0 skipped, 0 failed。
- `bash scripts/build-app.sh`：BUILD SUCCEEDED，bundle 密封与指定要求校验 PASS；产物装入 `/Applications/Automnt.app`（旧包备份 `/tmp/automnt-backup-3.6.0/`）。
- **实机正向验证**（现场正是被误判的两卷，未手动挂回）：安装新包启动后两卷均未挂载、菜单显示“已手动弹出”；点「快捷挂载」1 次 → `finalhome` 被尝试（状态 `pending-recovery`，`attempt_count 1`）并在路径转暖后挂上，第 3 次触发后两卷均 `attached`、`background-observations.plist` 两条 `healthy`。旧版本在这里会整日不动。
- **实机反向验证**（弹出不被覆盖）：`diskutil unmount /Volumes/personal_folder` 模拟用户弹出 → 应用级观察者写入 `//100.113.52.52/personal_folder | suppressed | suppression_has_evidence: True` → 再点「快捷挂载」**没有**重挂 personal_folder（只保留 finalhome）。
- **清理与复原**：把该记录改回“无证据待恢复”后再点「快捷挂载」，两卷均挂回、状态 `attached`、`attempt_count 0`、观测 `healthy`，现场回到两卷可用。

## Deviations from Assessment

1. **不新增 `last_connectivity_loss_at` 字段**（assessment 首选修复 2）。用“证据位 + 判定层 `!hostReachable` 放行”替代：效果等价（抑制期宿主恢复可达即重试一次，之后受既有上限约束），但避免在两条轮次路径上盖时间戳、避免与 `advance` 的消费逻辑竞态，也不需要状态文件加字段。
2. **`Evaluator` 未加 `max(host.timeoutMs, 1500)` 硬下限**（assessment 首选修复 3 的后半句）。改为只提升默认值与迁移旧默认值：显式把超时调到 500 毫秒是使用者在局域网内的有意选择，硬下限会覆盖该意图。
3. **摘要不拆成“未能挂载 N 个 / 已弹出 M 个”两行**（assessment 首选修复 4）。本会话弹出的共享作为一个 `.ejected` 原因进入同一摘要与明细子菜单，文案由原因标签区分；实现更小，且与既有“一个摘要 + 一个明细子菜单”的交互契约一致。
4. **对端抑制收紧**（assessment 未列）：`RecoverySession.protectedByPeer` 改为只认带证据的抑制，否则同一挂载点下另一台主机的记录会替无证据抑制兜底，修复不彻底。

## Follow-ups

- 残余边界（维护者已接受）：应用未运行期间用 Finder 弹出 → 下次评估按丢失处理并重挂一次。已在 `specs/004-mount-loss-recovery/spec.md` 的 FR-003 变更记录中写明。
- 中继路径探活仍偏紧：3000 毫秒在本机实测中偶尔仍在冷握手时失败（`nc` 预热后 1.3 秒可通）。是否改为“失败后延迟重试一次”留待后续评估，未纳入本次修复。
- 现场遗留脏记录 `//100.113.52.52/no-such-share-006`（Feature 006 测试残留，已从配置移除）仍在状态文件中，无对外影响；清理需另做。
- 本会话只改代码与文档，未提交、未推送、未递增版本号（维护者未授权）。
