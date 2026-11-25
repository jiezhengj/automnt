# Bug Assessment: 无证据的挂载丢失被判成"用户弹出"，整段会话不再自动恢复

- **Slug**: mount-loss-misjudged-as-eject
- **Created**: 2026-11-25
- **Source**: 本会话现场调查（维护者提问「本次启动后卷宗有否挂载、何时丢失、原因、是否符合预期」）+ 维护者 2026-11-25 批准的修复方向（原件见交付结论 m01851、裁定 m01852）
- **Verdict**: valid
- **Severity**: high

## Report (verbatim or summarized)

维护者 2026-11-24 提问：「看一下日志，本次电脑启动后，SMB 卷宗有否挂载上，后来是什么时候丢失挂载的，什么原因，是否符合预期」。

现场取证结论（2026-11-24，全部来自系统日志与本机状态文件）：

- 09:13:29 开机；09:14:26 与 09:16:01 两个共享经 Tailscale 主机 `100.113.52.52` 挂载成功；09:18:36 `mount-recovery-state.plist` 记为 `attached` + `ever_healthy_mounted = true`。
- 10:49–10:51 Tailscale 到 DERP(sfo) 的中继反复断连重连，SMB 会话经历一次 `smb_iod_reconnect` → `Reconnected share`；此后系统日志再无任何 smbfs 活动，也没有卸载/弹出/`Reference removed` 记录。
- 18:36–18:45 维护者连续点「快捷挂载」四次。18:42 helper 探活 445 每次 SYN 后约 1.07s 被取消（当时 `tailscale ping` 报 `via DERP(sfo) in 710/330ms`，而探测超时配置为 1000ms）。
- 18:45:46 `background-observations.plist` 写入两个共享 `status = suppressed`。19:33 复查两卷仍不存在，`/Volumes` 下挂载点目录也不存在。
- `mount-recovery-state.plist` 的 `volumes` 仍写 `attached`（mtime 停在 09:18），`worker-operation.plist` `pending = false`（无未收敛的弹出意图），`cleanup_ledger` 为空。

维护者裁定（m01852，回应 m01851 结尾提议）：按三条改规则——(1) 区分「有证据的弹出」与「无证据的丢失」；(2) 抑制期网络恢复后重试一次；(3) 放宽探活超时；并把「快捷挂载在全部被抑制时无反馈」合进本次修复。

## Symptom

卷在会话中途因 SMB/网络路径抖动确实丢失了，但程序把它判成"使用者在卷健康时手动弹出"，于是整段可达会话内不再自动恢复；同时界面上没有任何地方说明"为什么明明配置了自动挂载却不挂回来"。使用者看到的现象是：自动挂载开关是开的，卷却一整天不回来，点「快捷挂载」也没有任何反应。

期望行为（维护者确认）：只有当存在"是使用者弹出"的证据时才进入会话抑制；没有证据的丢失必须按丢失处理、恢复自动挂载；抑制期间如果网络路径经历过中断再恢复，应重试一次；远程/中继路径上的探活不应因为 1 秒预算而必然失败。

## Reproduction

机器与路径条件取自现场，可稳定复现判定部分（不依赖 NAS）：

1. 让两个共享健康挂载，并让恢复状态记录成为 `state = attached, ever_healthy_mounted = true`（正常使用一段时间即可）。
2. 让挂载从挂载表消失，但不经过 automont 的弹出/卸载动作（现场是 SMB 会话随 Tailscale 中继抖动死亡；等价手段：直接 `diskutil unmount` 也不留 `UserEjectCommit` 记录，虽语义不同但可复现判定分支）。
3. 触发一轮后台评估（登录/网络变化/挂载表变化，或点「快捷挂载」）。
4. 观察 `background-observations.plist` 中该身份为 `status = suppressed`，且此后每一轮都不再尝试挂载，直到会话边界（网络身份或登录纪元）变化。

自动化层面的等价复现（已可用现有单测方式表达）：`MountRecoveryVolumeRecord(volumeKey: id, everHealthyMounted: true)` 且卷缺失 → `BaselineMountDecision.decide(...) == .suppressed`（`Tests/AutomntCoreTests/MissingVolumeRecoveryTests.swift:52`、`BaselineDecisionTests.swift:13` 正在锁定这个当前行为）。

## Suspected Code Paths

- `Sources/AutomntCore/RecoveryState.swift:163` — `judgeRecoverySignal` 的缺失分支把 `record?.everHealthyMounted == true` 直接映射为 `.healthyEject`（"使用者健康弹出"），这是**唯一**的缺失判据，没有区分"弹出"与"丢失"。
- `Sources/AutomntCore/RecoveryState.swift:162` — 同一分支里 `.pendingRecovery` 与 `repairEjectEvidence` 才走可恢复信号；`.attached`（automont 自己挂上的）缺失没有任何可恢复出口。
- `Sources/AutomntCore/RecoveryVolumeDecision.swift:161-163` — `judge` 的特例只认 `record?.state == .suppressed`（有证据），但实操中这条记录只由 `UserEjectCommit.apply` 写入；未经过 automont 弹出的丢失永远不会产生它。
- `Sources/AutomntCore/UserEjectCommit.swift:13-30` — `apply` 是"有证据的弹出"唯一落盘路径，要求 `status == .stopped && actualPath == nil && issue == nil && path == .absent`，因此**Finder 里手动弹出不会留下任何记录**。
- `Sources/AutomntCore/RecoverySession.swift:23-38` — `RecoverySessionPolicy.advance` 只在会话边界变化（`establishing` 或 `boundary != 当前`）时清理抑制；同一次启动、同一网络身份下边界不变，抑制永不自解。现场 `session_boundary` 一整天未变（`gw:192.168.40.1;…|1795482809-console-unreadable`）。
- `Sources/AutomntPlatform/BackgroundEvaluator.swift:337-345` — app 后端的 `case .sessionSuppressed:` 只产出 `VolumeObservation(status: .suppressed)`，**不回写恢复状态**；因此抑制是"每轮重新推导"的结果，状态文件里的 `attached` 永远不变（现场即如此）。
- `Sources/AutomntPlatform/BackgroundEvaluator.swift:172-176` — 每轮评估前调用 `RecoverySessionCommit.advance(...)`，这是唯一适合挂接"本轮是否发生了连接中断"的位置。
- `Sources/AutomntCore/Evaluator.swift:57-58` — 主机探测预算 `min(max(host.timeoutMs, 1), remaining)`，直接采用配置值。
- `Sources/AutomntCore/Configuration.swift:85`、`:123` — `timeoutMs` 默认 1000ms，现有配置里显式存了 `timeout_ms = 1000`。
- `apps/Automnt/Views/MainWindowView.swift:74-79` — 已有 `NSWorkspace.didMountNotification` / `didUnmountNotification` 监听，但**挂在窗口视图上**（窗口关闭即失效），且只触发 `refreshObservedState()`，不记录任何事件。
- `Sources/AutomntCore/QuickMountOutcome.swift:104` — 归类映射把 `.suppressedForThisSession` 归为 `nil`（不计入失败），于是"全部被抑制"时 `outcome == nil`，菜单既不显示摘要也不解释（`DetailViews.swift` 的 `quickMountSection` 只在 `quickMountOutcome != nil` 时渲染）。
- `specs/004-mount-loss-recovery/spec.md:84`（FR-002③）、`:85`（FR-003）、`:86`（FR-004）、`:37-41`（用户故事 2「误覆盖手动弹出 = 0」）— 现行契约把"曾健康挂载"当成弹出证据，并要求证据不足时保守按弹出处理。**本次修复需要同步修改这三条需求。**

## Root Cause Hypothesis

置信度：高（判定链每一步都已按现场数据核对，且与观察到的状态文件完全一致）。

`ever_healthy_mounted` 记录的是"这个卷曾经挂成功过"，它只证明卷曾经健康，不证明它被谁移除。现有实现把它当作"使用者健康弹出"的唯一证据（FR-002③ 的原文即如此写），于是**任何一次会话级死亡（SMB 空闲会话失效、网络路径抖动、睡眠唤醒后会话丢失）都会被判成用户意图**，进入整段会话的抑制。抑制的解除条件只有会话边界变化或重新登录，而这两者在同一天、同一 Wi-Fi 下都不会发生，所以丢失的卷会一直不回来。

叠加两个放大因素：其一，判定不落盘（app 后端只产出观测），所以下一轮仍从 `attached + everHealthy` 推出同一个抑制结论，任何轮次都不会自我纠正；其二，探活预算 1 秒在 DERP 中继路径（RTT 330–710ms）上必然超时，即使抑制被解除，当时的轮次也挂不上。

## Proposed Remediation

**Preferred**（三条规则 + 一处界面反馈，按维护者 m01852 的裁定）：

1. **区分"有证据的弹出"与"无证据的丢失"。**
   - 证据来源一：`UserEjectCommit.apply` 已写入的 `state == .suppressed` + `suppressionBoundary`（保持现有语义，优先级最高）。
   - 证据来源二（新增）：app 侧在应用生命周期内监听 `NSWorkspace.didUnmountNotification`；当被卸载的卷属于某个已启用的共享、且挂载点状态为 `.absent` 时，立刻探测该共享所在主机（放宽后的预算）；**主机仍可达**说明共享在服务器侧完好、卸载是本机意图 → 复用 `UserEjectCommit.apply` 落盘 `suppressed` 记录；**主机不可达** → 视为丢失，不写抑制。
   - `judgeRecoverySignal` 中取消"`everHealthyMounted` 单独即 `.healthyEject`"：缺失且无抑制记录时返回新的可恢复信号（例如 `.lostWhileHealthy`，`isRecoverable == true`、`isSuppressed == false`），按 `MissingVolumeRecoveryPolicy` 与其余可恢复信号同样处理。
2. **抑制期网络恢复后重试一次。** 在恢复状态文件中新增可选字段 `last_connectivity_loss_at`（schemaVersion 保持 1，旧文件缺该键按 nil 处理，旧版本读新文件忽略未知键）。每轮评估（`BackgroundEvaluator` 与 CLI 轮次）在判定主机不可达时写入该时间戳；`RecoverySessionPolicy.advance` 在"存在抑制记录且 `last_connectivity_loss_at > record.updatedAt`"时把该卷改为 `pendingRecovery` 并清 `suppressionBoundary`（等价于"网络恢复后重试一次"）。不改变"边界变化/重新登录"既有解除路径。
3. **放宽探活超时。** `HostConfig.timeoutMs` 默认 1000 → 3000（`Configuration.swift:85`、`:123` 与新建主机的默认值同步）；读取到旧默认值 1000 的配置按默认迁移为 3000（与 GUI 现有 100–30000 校验区间兼容，界面显示实际生效值）；`Evaluator.swift:57-58` 的预算取 `max(host.timeoutMs, 1500)` 作下限保护。
4. **「快捷挂载」在抑制态要有说明。** `QuickMountOutcome.Failure.Reason` 增加 `.ejected`（对应 `.suppressedForThisSession`）；摘要文案改为分别陈述"未能挂载 N 个"与"本会话已弹出 M 个"，明细子菜单逐项给出"已在本次登录中弹出，可从共享行的『挂载』恢复"；当没有任何失败但存在抑制/未评估项时，菜单显示一行解释而不是静默。

**Alternatives**：
- 只放宽探活、不改判定：无法解决"抑制误解锁"的根因，现场即使探活成功也不会重挂（不建议）。
- 引入真正的卸载事件守护进程：违反 Constitution II（不引入第二个常驻进程）；app 内的 `NSWorkspace` 监听属于既有进程内部观察，不违反。
- 用"卷缺失时共享是否仍可探测"作为唯一判据而不监听事件：无法区分"用户在服务器正常时弹出"与"卷丢失但服务器正常"，会误覆盖弹出意图（违反 FR-003 红线的方向）。

**Files likely to change**：
- `Sources/AutomntCore/RecoveryState.swift`（信号判定、状态文件新增字段）
- `Sources/AutomntCore/RecoveryVolumeDecision.swift`（判定顺序，去掉 everHealthy 单独抑制）
- `Sources/AutomntCore/RecoverySession.swift`（连接中断后的一次性重试）
- `Sources/AutomntCore/MissingVolumeRecoveryPolicy.swift`（新信号的可恢复性）
- `Sources/AutomntCore/UserEjectCommit.swift`（如事件路径需要复用，补一个不依赖 pending worker 的入口）
- `Sources/AutomntCore/Configuration.swift`（默认值与旧默认迁移）
- `Sources/AutomntCore/Evaluator.swift`（探测预算下限）
- `Sources/AutomntCore/QuickMountOutcome.swift`（`.ejected` 归类）
- `Sources/AutomntPlatform/BackgroundEvaluator.swift`（写入连接中断时间戳）
- `apps/Automnt/AutomntApp.swift`、`apps/Automnt/Views/DetailViews.swift`、`apps/Automnt/Views/MainWindowView.swift`（应用级卸载监听、门禁说明、摘要与原因行文案）
- `Sources/AutomntCLI/Entry.swift`（CLI 轮次的同一判定；不新增 CLI 入口）
- `apps/Automnt/Resources/Localizable.xcstrings`（新增文案 × 9 语言）
- `specs/004-mount-loss-recovery/spec.md`（FR-002③ / FR-003 / FR-004 修订）、`specs/004-mount-loss-recovery/contracts/mount-recovery-contract.md`（若状态字段与判定顺序在契约里有描述）

**Tests to add or update**：
- 更新 `Tests/AutomntCoreTests/MissingVolumeRecoveryTests.swift:52-55`、`Tests/AutomntCoreTests/BaselineDecisionTests.swift:13`：`everHealthyMounted` 单独存在且卷缺失 → **可恢复**（不再是 suppressed）。
- 新增：缺失 + `state == .suppressed`（有证据）→ 仍 suppressed；缺失 + 无记录 → 可恢复（既有 ④ 不变）。
- 新增：抑制记录 + `last_connectivity_loss_at` 晚于记录时间 → 下一轮变为可恢复，且只重试一次（重试后再抑制不循环）。
- 新增：`.lostWhileHealthy` 在 `MissingVolumeRecoveryPolicy.mayMount` 中的可恢复性（auto-mount-recovery 关闭时按基线段拒绝）。
- 新增：`QuickMountOutcome` 把 `.suppressedForThisSession` 归为 `.ejected` 并计入摘要；全抑制时不返回 nil。
- 新增：`HostConfig` 旧默认 1000 → 3000 的解码迁移与 GUI 校验区间。
- 平台层：`Tests/AutomntPlatformTests/BackgroundEvaluatorTests.swift` 覆盖"主机不可达轮次写入 `last_connectivity_loss_at`"。
- 端到端人工验证：制造一次"健康卷缺失但无弹出记录"，确认下一轮自动挂回；再用 Finder 弹出一次，确认抑制生效且不再重挂。

## Risks & Considerations

- **红线风险（最重要）**：取消"曾健康即弹出"后，若使用者在 app 未运行期间用 Finder 弹出，下一次评估会把它当作丢失并重挂。缓解：app 在菜单栏常驻期间监听卸载事件，正常场景都有证据；仍存在"退出应用后弹出"的残余情形，需要在 spec 里显式记录为已知取舍，并在 CHANGELOG 写明。
- 修订 FR-002③/FR-003/FR-004 属契约级变更，必须同步 `specs/004-mount-loss-recovery/` 正文与契约文档，否则代码与文档脱节。
- 探测预算从 1s 提到 3s 会让"确实不可达"的主机每轮多耗约 2–4 秒；轮次有 30 秒总预算与 `first_reachable` 提前返回，影响可控，但需在单测里锁定总预算行为不被放大。
- 状态文件新增字段要保证向前兼容：旧版本读新文件必须忽略未知键（Codable 合成解码天然忽略），新版本读旧文件按 nil 处理。
- `NSWorkspace.didUnmountNotification` 会对所有卷（含磁盘映像）触发，必须按"已配置共享的挂载点 + 状态 .absent"过滤，避免误写抑制记录。
- 应用级监听需要在 app 生命周期内注册（不能挂在窗口视图上，窗口关闭即失效），并且事件处理要串行化，避免与评估轮次并发写状态文件（应走 `EvaluationPermit`）。

## Closed Questions（2026-11-25 维护者裁定）

- **残余取舍**：接受。正常场景（Automnt 在菜单栏运行）总有卸载事件作证据；只有"退出应用后再去 Finder 弹出"会被当作丢失并重挂一次。此取舍写入 spec 与 CHANGELOG，作为已知边界，不再追加持久化证据通道。
- **探活超时迁移**：静默迁移（旧默认 1000 毫秒视为未自定义），界面显示迁移后的实际生效值，改动记录写进 CHANGELOG；不额外弹提示。
- **现场处置**：维护者选择暂不手动挂回两个卷，留作修复后的自动恢复验证用例。
