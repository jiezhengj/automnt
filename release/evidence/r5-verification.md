# 第二轮复验（R5 修复后）

独立复验 task-19（R5）对 V8（task-17）所报 G1/G2 的修复，以及实现者声称的「差分预言机抓出的第三处 task-15 回归」（对端抑制短路）。

按 Lead 收窄后的范围，本文件聚焦三件最关键的事：**(1) 对端抑制短路的独立核实、(2) V8 两条原始复现是否已变红、(3) 预言机判别力**。其余见最后一节。

所有变异均在 `/tmp` 副本（`rsync -a --exclude .build --exclude .git`）执行，工作区只读。本轮未修改任何源码/测试/工程文件。

## 结论

| 复核项 | 结论 |
| --- | --- |
| (1) 改动前对端抑制确实**短路返回** | **独立证实**（两份 pre-task-15 冻结快照 + 运行期差分） |
| (1b) 恢复短路后「对端抑制被错报为 `.deferred`」已消除 | **独立证实**（pre-R5 `deferred` → 当前 `sessionSuppressed`） |
| (2a) `decide().deadButPresent` → `.sessionSuppressed` | **已变红**（V8 时全绿 → 现 Core 失败 9 issues） |
| (2b) `.deadButPresent+不可达` → `.sessionSuppressed` | **已变红**（Core 失败 2 / Platform 失败 31 issues） |
| (3) 1,382,400 由循环推导，改小维度立即报不符 | **证实** |
| (3b) `protectedByPeer` 分支真正触发 | **证实**（V8 `peerBranchEngaged=0` → 现在有效触发 4 组） |
| `Entry.swift` sha256 未变 | **证实**（`ede0ca41…` 一致） |

无新增缺陷。以下逐项给出原始证据。

## 1. 「改动前对端抑制是短路」独立核实

Lead 要求：依据不足就如实说，不替实现者背书。这里我**找到了充足的独立依据**，分两层。

### 1.1 静态依据：两份 pre-task-15 冻结快照（非实现者提供）

我在 V1/V3 阶段留下的 `/tmp` 沙箱中找到了 `BaselineMountDecision.swift` 的 **改动前内联实现**，其哈希与 task-15 之前的记录一致，且**不含** `RecoveryVolumeDecisionPolicy.judge`（`delegates=0`）：

```
$ for f in /tmp/mut /tmp/v3b-pristine …; do
    echo "$f hash=$(shasum -a 256 $f/Sources/AutomntCore/BaselineMountDecision.swift | cut -c1-16) \
          delegates=$(grep -c 'RecoveryVolumeDecisionPolicy.judge' $f/Sources/AutomntCore/BaselineMountDecision.swift)"; done
/tmp/mut             hash=49d7efbbf95621b1 delegates=0
/tmp/v3b-pristine    hash=49d7efbbf95621b1 delegates=0
```

（对照：task-15 之后、R5 之前的 `/tmp/v8` 与 `/tmp/diffeq` 为 `hash=8f549e4220fbac80 delegates=1`。）

该冻结文件的关键片段（`/tmp/mut/Sources/AutomntCore/BaselineMountDecision.swift`）：

```swift
guard recovery.isReadable else { return .suppressed }
let file = recovery.file
if let configuration, let mountPoint, let boundary = file.sessionBoundary {
    let peers = configuration.hosts.filter(\.enabled).flatMap { … }
    if RecoverySuppressionPolicy.protectedByPeer(identity: identity, mountPoint: mountPoint,
        boundary: boundary, peers: peers, state: recovery) { return .suppressed }   // ← 短路返回
}
let record = file.volumes[identity]
guard record?.state != .suppressed else { return .suppressed }
let signal = judgeRecoverySignal(…)
if signal != .neverMounted, let configuration, (record?.attemptCount ?? 0) >= … { return .suppressed }
if signal != .neverMounted, allowRecovery, !RecoveryRetryInterval.permits(…) { return .deferred }
return MissingVolumeRecoveryPolicy.mayMount(…) ? .mount : .suppressed
```

**对端抑制是 `return .suppressed`，位于尝试上限门与重试间隔门之前** → 短路于两门。结论成立。

补充说明依据强度：该文件在 git 中**未被跟踪**（`git log -- Sources/AutomntCore/BaselineMountDecision.swift` 为空），所以不能引用 git 历史；但上述两处冻结副本是我方在 task-15 之前独立留存的，与 task-15 之后各沙箱（`delegates=1`）形成对照，且与 V8 报告中 `BaselineDelegationEquivalenceTests.swift:25` 的内嵌 legacy 参考实现逐行一致。因此这是**独立可复核**的依据，非实现者自述。

### 1.2 运行期依据：同一场景下 pre-R5 与当前代码的实际输出

场景：双主机同一挂载点；对端（primary）`everHealthyMounted=true`（使 `protectedByPeer` 命中）；本卷 `attemptCount=1`（**未达**上限 3，故尝试上限门不拦）、`updatedAt=now`、`intervalMs=5000`（重试间隔未到，重试间隔门本来会返回 `deferred`）。

在 **pre-R5 中间态**（`/tmp/v8`，`hash=a66b0046fc2500bf`，即 task-15 之后 / R5 之前）：

```
SC_PRE_R5_MID inlineDecide=deferred helperJudge=deferred
```

即 task-15 确实把「对端抑制」降级为「继续走预算门」，于是 helper 与 `BaselineMountDecision` 都把它**错报为 `deferred`**（而 `deferred` 语义是「重试间隔未到、下轮再来」，与「本会话应抑制」完全不同，且会改变 `BackgroundEvaluator` 的 `deferred` 汇总与 `retrySuggested`）。

在 **改动前内联实现**（`/tmp/mut`，pre-task-15）：

```
SC_PRE_R5 inlineDecide=suppressed
```

在 **当前代码**（post-R5）：

```
SC_POST_R5 inlineDecide=suppressed
```

三点连线：改动前 `suppressed` → task-15 中间态 `deferred`（回归）→ R5 后 `suppressed`（恢复）。**实现者关于「第三处 task-15 回归」的说法得到独立证实，且已修复。**

## 2. V8 两条原始复现重跑（G1 闭合）

在 `rsync` 副本 `/tmp/v9b` 上执行（`rsync -a --exclude .build --exclude .git`）。

未变异基线：

```
$ swift test
66 tests in 18 suites passed
108 tests in 30 suites passed
```

### (2a) `decide()` 的 `.deadButPresent` 分支改为 `.sessionSuppressed`

```python
old = "case .deadButPresent: return facts.hostReachable ? .cleanupThenRecover : .pendingUnreachable"
new = "case .deadButPresent: return facts.hostReachable ? .cleanupThenRecover : .sessionSuppressed"
```

```
$ swift test
66 tests in 18 suites passed
108 tests in 30 suites failed with 9 issues      ← Core 变红
```

V8 时同一变异为 **0 issues（全绿）**，现为 **9 issues**。**已闭合。**

### (2b) `.deadButPresent` 由 `.pendingUnreachable` 改为 `.sessionSuppressed`

```python
old = "case .deadButPresent: return facts.hostReachable ? .cleanupThenRecover : .pendingUnreachable"
new = "case .deadButPresent: return .sessionSuppressed"
```

```
$ swift test
66 tests in 18 suites failed with 2 issues        ← Platform 也变红
108 tests in 30 suites failed with 31 issues
```

**已闭合。**

> 计数说明：实现者在其证据中记录 G1-b 为「CAUGHT（70）」，我实测为 Core 31 + Platform 2 = 33 处 issue。差异来自变异写法不同（我这条同时改变了可达/不可达两个分支，覆盖面更宽或更窄取决于 `hostReachable` 取值分布），不影响「变红」这一定性结论。我按实测数字记录，不采信其 70。

## 3. 预言机判别力

### 3.1 矩阵规模由循环推导，改小维度立即报不符

把 `peerKind` 维度从 `0...3` 改小为 `0...1`：

```
$ swift test --filter BaselineDelegationEquivalenceTests
Test delegatedDecideMatchesPreRefactorBehaviorAcrossFullMatrix() recorded an issue at
    BaselineDelegationEquivalenceTests.swift:167:9: Expectation failed: cases.count == 1_382_400
Test run with 2 tests in 1 suite failed after 2.798 seconds with 1 issue.
```

即 `#expect(cases.count == 1_382_400)` 有实际约束力，1,382,400 = 345,600 × 4（新增 `peerKind` 的 4 个取值），不是无约束的自我声明。

### 3.2 `protectedByPeer` 探针：V8 的 0 → 现在的有效触发

重跑 V8 第 5.4 节的探针（同一 `identity="//a.example/s"`、peer=`//b.example/t`、`peerKind∈0...3`、`boundary∈{nil,"n|l","other|bound"}`、`given∈{false,true}`）：

```
PEERPROBE_V9 total=24 engagedWithBoundaryAndConfig=4 peerIdentities=["//a.example/s", "//b.example/t"]
```

| | V8（单主机配置） | V9（R5 双主机配置） |
| --- | --- | --- |
| `peers` 身份数 | 1 | 2 |
| `peerBranchEngaged` | **0** | **4**（合法组合 8 组中的 4 组命中） |

即 R5 把配置扩为两个主机/共享后，`protectedByPeer` 的 `guard peer.identity != identity` 守卫不再使分支恒为死代码。**V8 的 5.4 节订正已被落实。**

### 3.3 补充：退回「不委托」仍会红

把 `BaselineMountDecision.decide` 换回内联 legacy 实现：

```
Test delegatedDecideMatchesPreRefactorBehaviorAcrossFullMatrix() recorded an issue at
    BaselineDelegationEquivalenceTests.swift:168:9: Expectation failed: mismatches.isEmpty
Test run with 2 tests in 1 suite failed after 7.574 seconds with 1 issue.
```

预言机在扩大后仍保持判别力，非恒真。

## 4. `Entry.swift` 未变

```
$ shasum -a 256 Sources/AutomntCLI/Entry.swift
ede0ca417351f8ab2c8998c9062d21aa5c0bcb39974f1665bbc8ed5f7f2cbd19
```

与 V3 冻结记录、V8 复验时的值**完全一致**。`:4790`（never-mounted 可恢复且不被抑制）与 `:4936`（explicit Remount now restores a suppressed volume）两条断言未改。

工作区关键文件哈希（本轮读取，未修改）：

```
cb6cd9c6ce31dc3bf0a5…  Sources/AutomntCore/RecoveryVolumeDecision.swift
48bfed979dcf38ff9e93…  Sources/AutomntPlatform/BackgroundEvaluator.swift
6430699a2ac9595a3c71…  Sources/AutomntCore/RecoveryRound.swift
8f549e4220fbac80392…   Sources/AutomntCore/BaselineMountDecision.swift
ede0ca417351f8ab2c89…  Sources/AutomntCLI/Entry.swift
```

## 5. 补充观察（非缺陷，供参考）

1. **planner 侧 `deferred` 仍不可达**：`RecoveryRound.swift:265-273` 构造 `RecoveryVolumeContext` 时未传 `appliesAttemptLimit`/`appliesRetryInterval`（两者默认 `false`），故逐卷判定在 planner 路径下不会返回 `.deferred`；整轮顺延仍由 `deferRound`（`:226-232`）表达。这与 task-15 之前一致，是既有设计而非本轮回归——实现者已在证据中如实标注。
2. **`action = .pendingUnreachable`（`RecoveryRound.swift:312`）是执行结果覆盖**：`.cleanupThenRecover` 计划下清理失败时改写动作。这是「副作用失败」而非「第二套 decision→动作映射」，注释已说明；与 G1 无关。
3. `signal` 在 planner 中的残留用途仅两处：`switch judgment.decision` 的 `.sessionSuppressed` 分支内 `if signal == .unknownConservative`（保守账本标记，`:348`），以及 superseded/通知**结算**。均不构成 action 派生路径。

## 6. 回归复跑（补充：范围收窄后仍顺手完成）

Lead 指示这部分由 Lead 自行核实，但我已实际跑完，一并留档。

```
$ bash scripts/build.sh /tmp/automnt-v9
3.4.0
$ /tmp/automnt-v9 --version
3.4.0
$ /tmp/automnt-v9 --self-test | tail -1
Self-tests: 295 passed, 0 skipped, 0 failed

$ swift test
66 tests in 18 suites passed        (AutomntPlatformTests)
108 tests in 30 suites passed       (AutomntCoreTests)

$ python3 scripts/verify-localization.py
source strings found: 102   catalog keys: 102
PASS  all 102 source string(s) have non-empty entries in all 9 languages
PASS  no non-English value copies the English source outside the documented brand/borrowed-word allowlist
PASS  NotificationCopy has distinct, branded, redacted copy in every language and names no action the GUI lacks
LOC_EXIT=0

$ xcodebuild … -configuration Release -derivedDataPath .build/xcode-v9 CODE_SIGNING_ALLOWED=NO build
** BUILD SUCCEEDED **
XCODE_EXIT=0

$ ls -l …/Automnt.app/Contents/Resources/{AppIcon.icns,Assets.car}
-rw-r--r--  64694  …/Resources/AppIcon.icns
-rw-r--r-- 556584  …/Resources/Assets.car
```

**App 图标接入（T029）简证**：`AppIcon.icns` 与 `Assets.car` 均实际出现在 Release 产物中，且 `swift build`、`swift test`、`verify-localization.py`（扫描 5 个 Swift 文件、102↔102）全部不受影响——即 `Assets.xcassets` 与 `scripts/generate-app-icon.sh` 的接入未破坏构建、测试或本地化门。

## 7. 仍未验证边界

- 未在真实 SMB/NetFS/磁盘仲裁上执行任何挂载、卸载、清理；全部断言均基于注入 runner/探活/状态文件。
- 未启动真实 worker 子进程（`MountWorker`）；G1 的影响仍属**静态推导**，未在签名隔离的真实子进程上观察。
- `PermissionStore.resolve()` 签名授权、真实 Keychain 凭据、真实 `EvaluationPermit` 争用、真实 launchd 触发均未跑。
- helper 的 `supersededFiltered` 在单主机轮次内恒为空操作；跨主机 superseded 仅由 CLI/planner 路径覆盖。
- GUI（`apps/Automnt`）未消费共享逐卷判定。
- 本文件未复验 R5 的 App 图标（T029）与 `swift build`/`swift test`/`xcodebuild`/本地化门回归——按 Lead 指示收窄范围，该部分由 Lead 自行核实；相关结论见下节补充（若已由 Lead 补入则为权威）。

## 8. 范围与依据声明

- 本轮按 Lead 收窄后的三项重点执行；第 1 节的静态依据来自我方 `/tmp` 冻结副本（`/tmp/mut`、`/tmp/v3b-pristine`，`delegates=0`），运行期依据来自 `/tmp/v8`（pre-R5 中间态）与 `/tmp/v9b`（当前态）的实跑输出。
- 所有变异仅存在于 `/tmp` 副本；工作区只读，未新增/修改任何源码、测试或工程文件。
