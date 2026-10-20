# 结论摘要

独立复验 task-15（T009-c2：逐卷判定统一到 `RecoveryVolumeDecisionPolicy` + Lead 裁决 A）。所有实验在 `/tmp/v8` 仓库副本上进行，工作区只读。

**总判定：未通过。** 裁决 A 的四条约束、规则唯一性的主干、差分预言机的可信度、`Entry.swift` 未改动、全部构建与既有回归——这些**均通过**；但发现 2 项缺陷，其中 G1 正是 Lead 要求「最值得攻击」的点的具体答案，G2 是 task-15 引入的真实行为回归。

| 编号 | 结论 | 依据 |
| --- | --- | --- |
| 裁决 A 四约束 (a)(b)(c)(d) | 通过 | 两路径（planner / BaselineMountDecision）实测全过，见第 3 节 |
| 规则唯一性（主干） | 通过 | `BaselineMountDecision.decide` 已委托；helper 已删除自有抑制/deferred/尝试上限分支 |
| 差分预言机恒真性 | 通过（非恒真） | 345,600 为推导值、改小循环即红；对 lost-delegation 敏感；但 peer 分支为死代码（见 5.4） |
| **G1 planner 未消费 `judgment.decision`** | **未通过** | `decide()` 的 action 映射对 planner 是死代码，退化「全绿」（6.1） |
| **G2 helper `boundary ?? ""` 语义偏移** | **未通过** | 与 `BaselineMountDecision` 及改动前 helper 行为分歧（6.2） |
| 独立变异 ≥4 类 | 通过 | 11 条中 9 条被捕获；2 条经查为等价变异（第 5 节） |
| `Entry.swift` 断言未改 | 通过 | sha256 `ede0ca41…` 与 V3 冻结记录逐字节相同 |
| 构建 / 测试 / 自测 / 本地化门 | 通过 | 94/28 + 61/17 全绿；295/0/0；BUILD SUCCEEDED；localization exit 0 |

# 验证环境

| 项目 | 值 |
| --- | --- |
| 工作目录 | `/Users/jiezhengj/Documents/Project/automnt` |
| 系统 / 架构 | macOS 27.2（26B5101f），arm64 |
| Xcode | 27.0（27A266a），SDK macosx27.0 |
| 版本 | `automnt.swift` 声明 3.4.0 |
| 实验沙箱 | `/tmp/v8`（Sources/Tests/apps/scripts 副本；所有变异只在此） |

# 1. 复跑：构建、测试、自测、本地化门、xcodebuild

```
$ swift build
Build complete! (0.70秒)

$ swift test --filter AutomntCoreTests
Test run with 94 tests in 28 suites passed after 1.076 seconds.

$ swift test --filter AutomntPlatformTests
Test run with 61 tests in 17 suites passed after 0.773 seconds.

$ grep -rc '@Test' Tests/AutomntCoreTests | awk -F: '{s+=$2} END {print s}'   → 94
$ grep -rc '@Test' Tests/AutomntPlatformTests | awk -F: '{s+=$2} END {print s}' → 61
```

静态 `@Test` 计数与 runner 报告一致，无跳过测试。数字与 task-15 声称（Core 94/28、Platform 61/17）相符。

```
$ rm -rf /tmp/automnt-t009c-v8 && bash scripts/build.sh /tmp/automnt-t009c-v8
3.4.0
EXIT=0

$ /tmp/automnt-t009c-v8 --version
3.4.0

$ /tmp/automnt-t009c-v8 --self-test | tail -1
Self-tests: 295 passed, 0 skipped, 0 failed

$ python3 scripts/verify-localization.py
catalog: apps/Automnt/Resources/Localizable.xcstrings
source strings found: 102   catalog keys: 102
languages required:   en, zh-Hans, zh-Hant, ja, ko, de, fr, es, pt-BR
swift files scanned:  5 (recursive)
PASS  all 102 source string(s) have non-empty entries in all 9 languages
PASS  no non-English value copies the English source outside the documented brand/borrowed-word allowlist
PASS  NotificationCopy has distinct, branded, redacted copy in every language and names no action the GUI lacks
LOC_EXIT=0

$ xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt -configuration Release \
    -derivedDataPath .build/xcode-t009c-v8 CODE_SIGNING_ALLOWED=NO build
** BUILD SUCCEEDED **
XCODE_EXIT=0
```

结论：`swift build`、`swift test`（0 失败）、`scripts/build.sh` + `--version` + `--self-test`、`xcodebuild Release`、`verify-localization.py` **全部通过**，本地化门未被本轮判定改动牵连。

# 2. 规则唯一性复核

## 2.1 `BaselineMountDecision.decide` 确为委托

`Sources/AutomntCore/BaselineMountDecision.swift:37` 调用 `RecoveryVolumeDecisionPolicy.judge(...)`，随后仅做 `translate(_:)` 枚举翻译（`:49-58`）。自身不再保留任何恢复分支；保留的 `block(path:identity:)`（`:16-23`）是挂载点状态前置校验，不属恢复规则。

## 2.2 三条路径确实汇聚到同一函数

```
$ grep -rn "RecoveryVolumeDecisionPolicy.judge" Sources apps
Sources/AutomntCore/RecoveryRound.swift:262        (CLI planner)
Sources/AutomntCore/BaselineMountDecision.swift:37 (worker 子进程复核)
Sources/AutomntPlatform/BackgroundEvaluator.swift:310 (helper)
```

`RecoverySupersededPolicy.supersededIdentities` 同样被 planner（`RecoveryRound.swift:383`）与 helper（`BackgroundEvaluator.swift:340`）共用。

## 2.3 helper 无第二套抑制/deferred/尝试上限

```
$ grep -rn "judgeRecoverySignal\|MissingVolumeRecoveryPolicy.mayMount\|protectedByPeer" --include=*.swift Sources apps \
    | grep -v "RecoveryVolumeDecision.swift"
Sources/AutomntCLI/Entry.swift:4763..4784   （CLI 自测的既有直接断言，非编排）
Sources/AutomntCore/RecoveryState.swift:144 （judgeRecoverySignal 定义）
Sources/AutomntCore/RecoveryAttemptCommit.swift:33,37 （reserve 的挂载前复核）
Sources/AutomntCore/RecoverySession.swift:59,66 （protectedByPeer 定义）
```

`RecoveryAttemptCommit.reserve`（`:33-43`）仍自行调 `judgeRecoverySignal` + `mayMount` + 独立夹限。它**不是**逐卷动作判定的第二套实现——它是「持久化预留一个尝试」这一副作用的前置校验，且其门（`record.state != .suppressed`、`mayMount`、`attemptCount < limit`、`RecoveryRetryInterval.permits`）与 `judge` 的缺失分支语义一致。属可接受的、已有既存组件；记录在案但不判缺陷。

结论：主干唯一性成立（G1 是「消费侧绕开」而非「实现侧重复」）。

# 3. 裁决 A 四约束实测（两路径）

用真实产品 API `UserEjectCommit.apply` 写出「首次即被弹出」记录（`state=.suppressed` + `suppressionBoundary`，**无** `everHealthyMounted`），再分别走 CLI planner 与 `BaselineMountDecision.decide`。

探针前置断言输出（证明记录确为产品 API 产物）：

```
PROBE record state=Optional(AutomntCore.MountRecoveryVolumeState.suppressed) everHealthy=Optional(false)
```

四约束结果（`/tmp/v8` 探针 `ZZFourConstraintProbeTests`）：

```
CONSTRAINT_A planner_suppressed=true mounts=0 helper_suppressed=true
CONSTRAINT_B planner_recovered=true mounts=1
CONSTRAINT_C planner_recovered=true mounts=1 helper=mount
CONSTRAINT_D planner_recovered=true mounts=1 helper=mount
Test run with 1 test in 1 suite passed after 0.006 seconds.
```

| 约束 | 要求 | 实测 | 判定 |
| --- | --- | --- | --- |
| (a) | `.suppressed` + `everHealthyMounted==false` + 缺失 → 抑制且零挂载 | planner `suppressed=[id]`、`mounts=0`；helper `=.suppressed` | 通过 |
| (b) | 同记录 + `manualRecovery==true` → 允许恢复 | planner `recovered=[id]`、`mounts=1` | 通过 |
| (c) | 会话边界变化后不再抑制 | `advance` 后 `state==.pendingRecovery`；planner 恢复、helper `=.mount` | 通过 |
| (d) | `record == nil` 仍走 FR-002④ 挂载 | planner `recovered=[id]`、`mounts=1`；helper `=.mount` | 通过 |

两路径结论在 (a)(c)(d) 上**一致**，(b) 仅 planner 有 manual 概念（`BaselineMountDecision` 硬编码 `manualRecovery: false`，与其 worker 复核定位一致），符合设计。

## 3.1 缺陷确曾真实存在（反证）

在 `/tmp` 副本上**移除** A 修复（`.suppressed` 门）后，用同一产品 API 记录重跑：

```
REVERT-A RESULT suppressed=[] recovered=["//v8regress.example/shared"] mounts=1
```

即修复前该卷**被重新挂载**，与 Lead 描述一致；修复后转抑制。裁决 A 修复的是真实产品缺陷，方向是收紧。

# 4. 为何判定「收紧」是安全方向

- 修复前 CLI 非手动轮次会重挂「首次即被用户弹出」的卷，违反 FR-002③/SC-002；helper/worker 因原有 `.suppressed` 门已判抑制——两路径**规则矛盾**。
- 修复后统一为抑制。用户可见变化仅一条：CLI 非手动轮次不再重挂首次弹出卷。
- `manualRecovery`（`--config → 立即重新挂载`）置于 `judge` 最前（`RecoveryVolumeDecision.swift:131-136`），约束 (b) 实测仍可恢复，故未把唯一的手动出口挡掉。
- 无其他可观察副作用：`--self-test` 295 项全绿、4 条「manual 仍可恢复」类断言保持绿、`swift test` 94+61 全绿。

# 5. 差分预言机攻击（Lead 指定的重点）

## 5.1 「345,600」是推导值，不是自我声明的常量

预言机用 13 层嵌套循环构造矩阵（`BaselineDelegationEquivalenceTests.swift:72-109`），`cases.count` 由循环取值集合自然得出，**断言**为 `#expect(cases.count == 345_600)`（`:148`）。我独立验证该断言确有约束力：

```
# /tmp 副本：把 attempts 循环从 [0,1,3,10] 改为 [0,1]（cases 变 172,800）
Test delegatedDecideMatchesPreRefactorBehaviorAcrossFullMatrix() recorded an issue at
    BaselineDelegationEquivalenceTests.swift:148:9: Expectation failed: cases.count == 345_600
Test run with 2 tests in 1 suite failed after 0.503 seconds with 1 issue.
```

结论：改小循环**会被发现**，矩阵规模不是无约束的自我声明。

## 5.2 矩阵覆盖了全部 6 类输出，不是同一等价类大面积重复

独立统计 oracle 输入空间下的 `BaselineMountDecision` 输出分布：

```
MATRIX total=345600
HISTOGRAM [(blocked(pathConflict), 138240), (blocked(signalUnavailable), 69120),
           (deferred, 2088), (inspectExisting, 69120), (mount, 3762), (suppressed, 63270)]
SUPPRESSED_STATE cases=69120 withoutHealth=34560
```

全部 6 个输出枚举均被触达；其中「`.suppressed` 状态且 `everHealthyMounted == false`」（即裁决 A 的目标等价类）覆盖 34,560 组。边界组合 inspect：

| 维度 | oracle 取值 | 覆盖 |
| --- | --- | --- |
| `configuration == nil` | `given ∈ {false,true}` | 有（`configurationGiven`） |
| `allowRecovery × isAutoMountRecoveryEnabled` | 2×2 | 全四种组合 |
| `updatedAt` 触发 deferred | `now-100 / now-0.2 / 0` + `intervalMs=1000` | 有（deferred 命中 2088 组） |
| `boundary` 触发对端抑制 | `nil / "n\|l" / "other\|bound"` | **形式上有，实质为死代码**（5.4） |
| `maxAttempts` 尝试上限 | `1/3/10` × `attempts 0/1/3/10` | 有 |
| `corrupt` | `false/true` | 有 |

## 5.3 预言机有判别力：能抓出「退回不委托」

Lead 声明它抓出过 4 处真实分歧。我独立验证它至少对**放弃委托**这件事敏感——把 `BaselineMountDecision.decide` 换回 legacy 内联实现：

```
=== M6: oracle alone ===
Test delegatedDecideMatchesPreRefactorBehaviorAcrossFullMatrix() failed after 0.905 seconds with 1 issue.
=== M6: full suite ===  P=61. P=1 issue.
=== which tests catch it ===  delegatedDecideMatchesPreRefactorBehaviorAcrossFullMatrix()
```

且对 A 修复本身敏感（删 `.suppressed` 门 → oracle 红）。结论：**预言机不是恒真**，在它覆盖的维度上确有判别力。声称「345,600 zero mismatch」在**委托等价性**这一命题上成立。

## 5.4 但预言机的 peer 分支是死代码（独立发现）

oracle 用 `identity = "//a.example/s"`，配置里唯一 share 也是 `//a.example/s`。`protectedByPeer` 的首个守卫是 `guard peer.identity != identity`，因此该分支**永不触发**。独立探针：

```
PEERPROBE total=40 peerBranchEngaged=0 peerIdentities=["//a.example/s"]
```

同伴（`state.sessionBoundary = "other|bound"`）与第二身份虽被塞进 state，但配置中并不存在第二个启用 share，故 `peers` 只有一个身份且与待判身份相同。

影响：预言机**没有**为「同路径对端抑制」提供等价性证据；该维度在格式上呈现为已覆盖，实质为零。不过该分支并非无测试——`Tests/AutomntCoreTests/RecoverySessionTests.swift:59 baselineBackupRespectsPeerEjectWithoutInheritingCleanup` 用双主机配置真实覆盖了它。故这属**证据文档的过度声称**（`background-service.md` 的「345,600 组输入」易被读成覆盖了对端抑制），而非功能缺陷。建议在 oracle 注释或证据文档中注明该分支未纳入矩阵。

# 6. 缺陷清单

## 6.1 G1（中等，结构性）：planner 未消费 `judgment.decision`，`decide()` 的 action 映射对 planner 是未被测试覆盖的死代码

- 位置：`Sources/AutomntCore/RecoveryRound.swift:271`（仅取 `judgment.signal`）、`:290`（自行 `switch signal` 映射 action）；对照 `Sources/AutomntCore/RecoveryVolumeDecision.swift:168-193`（`decide()` 的另一套映射）。
- 事实：`grep -n "judgment\." Sources/AutomntCore/RecoveryRound.swift` 仅命中 `:271 judgment.signal`；`judgment.decision` 在 planner 中从未被读取。planner 用 `switch signal` 自行重导出 `attachHealthy / cleanupThenRecover / recover / pendingUnreachable / suppress`。
- 直测（`/tmp` 副本把 `decide` 的 `neverMounted` 分支改为 `.sessionSuppressed`）：
  ```
  ORIGINAL: judge_decision=recover            planner_recovered=true mounts=1
  MUTATED : judge_decision=sessionSuppressed  planner_recovered=true mounts=1
  ```
  planner 完全无视 `decide()` 的变化。
- 变异证据（`decide()` 的 present 分支 `deadButPresent+不可达` 由 `.pendingUnreachable` 改为 `.sessionSuppressed`）：
  ```
  Test run with 61 tests in 17 suites passed
  Test run with 94 tests in 28 suites passed
  ```
  **全绿零失败。** 作为对照，planner 侧同语义变异（`RecoveryRound.swift:356` 的 `action = .recover` 改为 `.suppress`）被捕获 5 issues。
- 影响：`decide()` 的 action 映射是 worker 子进程路径（`apps/Automnt/Worker/MountWorker.swift:70`）的实际决策源，其退化不会被任何测试发现；而「三条路径共用同一实现」的保证在 planner 侧仅剩 `signal` 层，action 层靠人工维护两份映射。与 V1 报的 DEF-1 同类（规则在唯一实现里，消费者绕开它）。
- 最小复现：
  ```
  rm -rf /tmp/v8 && mkdir /tmp/v8 && cd /Users/jiezhengj/Documents/Project/automnt
  cp -R Sources Tests Package.swift automnt.swift apps scripts /tmp/v8/ && cd /tmp/v8
  python3 - <<'PY'
  import pathlib
  p = pathlib.Path('Sources/AutomntCore/RecoveryVolumeDecision.swift'); s = p.read_text()
  old = "            case .deadButPresent: return facts.hostReachable ? .cleanupThenRecover : .pendingUnreachable"
  assert old in s
  p.write_text(s.replace(old, "            case .deadButPresent: return facts.hostReachable ? .cleanupThenRecover : .sessionSuppressed"))
  PY
  swift test        # 期望失败，实际 94/28 与 61/17 全绿
  ```
- 建议方向（由实现者决定）：让 planner 消费 `judgment.decision` 而非自行 switch；或在包测试中补一条「`decide()` 对（present, reachable, health）全组合的动作映射」断言矩阵，把这份映射纳入保护。

## 6.2 G2（中等，行为回归）：helper 桥接把 `sessionBoundary == nil` 传成 `""`，与另两条路径分歧

- 位置（根因）：`Sources/AutomntPlatform/BackgroundEvaluator.swift:314`
  ```swift
  stateReadable: recovery.isReadable, boundary: recovery.file.sessionBoundary ?? "",
  ```
- 对照：`Sources/AutomntCore/BaselineMountDecision.swift:41` 传 `boundary: state.sessionBoundary`（nil 保持 nil）；`RecoveryRound.swift:267` 传 advance 后的确定值。同一参数**三种来源、无单一约定**。
- 机制：`Sources/AutomntCore/RecoveryVolumeDecision.swift:152` 的对端抑制判据是
  ```swift
  if !facts.presentInMountTable, let boundary = context.boundary,
  ```
  空串能通过 `let`，nil 不能。于是 nil 状态边界下：helper（`""`）会启用同路径对端抑制，`BaselineMountDecision`（nil）跳过。
- 改动前 helper 的真实行为：`BackgroundEvaluator` 原本走 `BaselineMountDecision`，其 legacy 实现（`Tests/AutomntCoreTests/BaselineDelegationEquivalenceTests.swift:25`）为
  ```swift
  if let configuration, let mountPoint, let boundary = file.sessionBoundary {
  ```
  **nil 时跳过 peer 检查**。因此 `?? ""` 是 task-15 引入的语义偏移，不是等价委托。
- 直测（单主机对端 `state=.attached, everHealthyMounted=true`、`session_boundary == nil`，判定第二身份）：
  ```
  NILBOUNDARY helper_decision=sessionSuppressed  baseline_decision=mount
  ```
  helper **抑制**，worker/`BaselineMountDecision` **挂载**——两条「共用同一实现」的路径对同一恢复状态给出相反结论。
- 可达性：`RecoverySessionCollector.collect` 在 `loginEpoch()` 为 nil 时返回 nil（`Sources/AutomntPlatform/RecoverySessionCollector.swift:8`），此时 `RecoverySessionCommit.advance` 原样返回、不建立边界（`Sources/AutomntCore/RecoverySessionCommit.swift:15`），helper 随后即以 nil 边界逐卷评估。并非纯理论输入。
- 影响方向：helper 侧偏向**抑制**（少挂载），是保守方向、非安全倒退；但与「统一判定」目标和「helper 可观察结果与改动前逐条一致」的硬门槛不符，且未在证据文档中列为有意变化（该文档只声明 1 条有意变化，即裁决 A）。
- 最小复现：见 3 节探针的构造方式；把对端记录置为 `everHealthyMounted=true`、`sessionBoundary=nil`，分别以 `boundary: nil` 与 `boundary: ""` 调 `RecoveryVolumeDecisionPolicy.judge`，得到 `mount` vs `sessionSuppressed`。
- 建议方向：helper 桥接改传可选边界（或统一以「建立边界后才做对端检查」为唯一约定），使三处调用同源。

## 6.3 提示级：证据文档的覆盖声称略有过度

`release/evidence/background-service.md` 称「345,600 组输入、0 不一致」并暗示覆盖了对端抑制，但该分支在矩阵中为死代码（5.4）。建议补一句范围说明。不构成功能缺陷。

# 7. 独立变异实验结果（≥4 类，含双双漏判排查）

全部在 `/tmp/v8` 副本、`swift test` 全量运行。`P=` 表示 `Test run with N tests ... passed`。

| # | 变异 | Core(94) | Platform(61) | 判定 |
| --- | --- | --- | --- | --- |
| M1 | 删除 `.suppressed` 门（RecoveryVolumeDecision:142-145） | failed 15 issues | failed 2 issues | 捕获 |
| M2 | 把 `.suppressed` 门移到 `everHealthyMounted` 之后 | failed 15 issues | failed 2 issues | 捕获 |
| M3 | 删除 manual 优先（:131-136） | failed 7 issues | passed | 捕获 |
| M4b | 抑制落穿为 `recover`（`guard !signal.isSuppressed` → `if ... { return .recover }`） | failed 4 issues | passed | 捕获（`MissingVolumeRecoveryTests` 3 项 + oracle） |
| M5/M11 | superseded 剔除返回 `[]` / 忽略 mountPoint | failed 4 / 17 issues | failed 1 / 6 issues | 捕获 |
| M6 | `BaselineMountDecision.decide` 退回内联 legacy（不再委托） | failed 1 issue | passed | 捕获（仅 oracle） |
| M7 | 删除尝试上限门 | failed 3 issues | passed | 捕获 |
| M8 | 删除重试间隔门（deferred） | failed 2 issues | failed 2 issues | 捕获 |
| M9 | 删除 `stateReadable` 保守门 | failed 13 issues | passed | 捕获 |
| M10 | peer 列表置空（`peers: []`） | failed 7 issues | passed | 捕获 |
| N1 | 交换 deferred 与抑制回落顺序 | failed 1 issue | passed | 捕获（oracle） |
| N2 | 把尝试上限放到 `.suppressed` 门之前 | failed 15 issues | failed 2 issues | 捕获 |
| **N3** | 健康覆盖不再要求 `hostReachable` | passed | passed | **等价变异** |
| N4 | 尝试上限不再排除 `neverMounted` | failed 1 issue | passed | 捕获 |
| **N5** | `pendingUnreachable` 落穿为 `recover` | passed | passed | **等价变异** |
| **P1** | `decide()` 的 `deadButPresent+不可达` → `.sessionSuppressed` | passed | passed | **双双漏判 → G1** |
| Q1 | planner 侧 `action = .recover` → `.suppress` | failed 5 issues | passed | 捕获（对照 P1） |

**双双漏判排查结论**：11+ 条变异中，仅 **P1** 出现「包测试与 CLI 自测双双漏判」，即 G1。N3/N5 经语义探针确认是**等价变异**而非漏判：

- N3：`RecoveryHealthPolicy.signal` 自身有 `guard base != .unknownConservative, present, hostReachable else { return base }`（`Sources/AutomntCore/RecoverySession.swift:98`），把外层 `hostReachable` 去掉后，policy 内又检查一次，**语义等价**。探针：present+不可达在 health 三种取值下均为 `pendingUnreachable`，变异前后一致。
- N5：该分支只在 `hostReachable == false` 时可达，但三个调用点传入的 `hostReachable` 均为常量 `true`——`BaselineMountDecision.swift:39`、`BackgroundEvaluator.swift:312` 硬编码 `true`；planner（`RecoveryRound.swift:265`）传入真实探测值时，`hostReachable == false` 的缺失卷在 planner 侧走 signal 层路径（`neverMounted` → `guard snapshot.hostReachable else` 单独分支）。故 `.pendingUnreachable` 在当前调用图下**不可达**，构成等价变异；同时也说明该枚举分支缺少直接覆盖。

# 8. 行为变化与 CLI 自测断言未改

## 8.1 `Entry.swift` 逐字节未改

```
$ shasum -a 256 Sources/AutomntCLI/Entry.swift
ede0ca417351f8ab2c8998c9062d21aa5c0bcb39974f1665bbc8ed5f7f2cbd19
$ grep "Entry.swift" release/evidence/final-verification.md   # V3 冻结记录
| `Sources/AutomntCLI/Entry.swift` | `ede0ca417351f8ab2c8998c9062d21aa5c0bcb39974f1665bbc8ed5f7f2cbd19` | 相同 |
$ grep -c "check(" Sources/AutomntCLI/Entry.swift
290
```

sha256 与 V3 冻结记录**逐字节相同**，`check(` 计数仍为 290。Lead 点名的两处断言原样保留：

```
:4790    check(RecoverySignal.neverMounted.isRecoverable && !RecoverySignal.neverMounted.isSuppressed,
             "never-mounted volumes are recoverable and never suppressed")
:4936    check(round(manual: true).recovered == [firstKey], "explicit Remount now restores a suppressed volume")
```

`:4936` 恰是约束 (b)「manual 仍可恢复」的 CLI 侧既有保护，未改且保持绿。

## 8.2 收紧方向无其他可观察副作用

`--self-test` 295 passed / 0 skipped / 0 failed，与 task-15 之前一致；包测试 94+61 全绿。裁决 A 的唯一用户可见变化是「CLI 非手动轮次不再重挂首次弹出卷」，属**安全收紧**（消除与 helper 的规则矛盾，向 FR-002③/SC-002 靠拢）。

# 9. 已实际验证 与 仍未验证

## 9.1 已实际验证

- 构建与回归：`swift build`、`swift test`（Core 94/28、Platform 61/17，0 失败，静态计数一致）、`scripts/build.sh` + `--version` 3.4.0 + `--self-test` 295/0/0、`xcodebuild Release` `BUILD SUCCEEDED`、`verify-localization.py` exit 0。
- 裁决 A 四约束在 planner 与 `BaselineMountDecision` 两条路径上的实测（第 3 节），记录由真实 `UserEjectCommit.apply` 产品 API 写出。
- 缺陷真实性的反证：移除 A 修复后同记录被重挂（第 3.1 节）。
- 规则唯一性：三调用点汇聚、`decide` 已委托、helper 无第二套抑制/deferred/尝试上限（第 2 节）。
- 差分预言机：矩阵规模为推导值且有断言保护（改小即红）、6 类输出全覆盖、对 lost-delegation 敏感、peer 分支为死代码（第 5 节）。
- 17 条变异（11 类）实跑，含双双漏判排查（第 7 节）。
- `Entry.swift` 与 V3 冻结 sha256 逐字节相同、`:4790`/`:4936` 未改（第 8 节）。
- 工作区完整性：实验前后 5 个关键文件 sha256 不变，`Tests/AutomntCoreTests/` 无探针残留（第 10 节）。

## 9.2 仍未验证（不得据此宣称通过）

- **真实 SMB/NetFS 与磁盘仲裁**：无任何真实挂载、卸载、清理、Spotlight 防索引操作；全部为注入 runner/探活/状态文件。
- **真实 worker 子进程**：`BaselineMountDecision` 的实际消费者是 `apps/Automnt/Worker/MountWorker.swift:70` 的签名隔离子进程，本轮未启动；G1 的影响因此只是**静态推导**出的（映射退化不被测试发现），未在真实 worker 上观察。
- **helper 真实运行**：`PermissionStore.resolve()` 的签名授权、`RecoverySessionCollector` 在真实登录/网络下返回 nil 的频率、launchd 触发时序均未跑；G2 的可达性由代码路径推导，未在真实 helper 进程重现。
- **Keychain 凭据读取**、真实 `EvaluationPermit` 争用、真实 `evaluation.lock` 跨进程互斥未验证。
- **GUI 未消费共享判定**：`apps/Automnt` 不调用 `RecoveryVolumeDecisionPolicy`；GUI 的手动弹出/重试入口仍未接入，因此裁决 A 在 GUI 侧无可观察行为。
- **跨主机 superseded**：helper 的 `supersededFiltered` 在单主机轮次内恒为空操作（配置校验禁止同主机重复挂载点），仅 CLI/planner 路径被覆盖。
- **本地化质量问题**：`verify-localization.py` 只校验存在性/品牌/回填/脱敏，不校验译文质量；母语审校未完成。

# 10. 复现材料与工作区完整性

| 内容 | 路径 |
| --- | --- |
| 变异/探针沙箱（仓库副本） | `/tmp/v8` |
| 变异脚本 | `/tmp/v8/mutate.py`、`/tmp/v8/mut2.py`、`/tmp/v8/mut3.py` |
| 源码构建 CLI 产物 | `/tmp/automnt-t009c-v8` |
| app Release 产物 | `.build/xcode-t009c-v8/Build/Products/Release/Automnt.app` |

实验前后工作区关键文件 sha256（一致）：

```
a66b0046fc2500bf93271163cd5f87199d845d73d9fca07f50152d00c4078709  Sources/AutomntCore/RecoveryVolumeDecision.swift
8f549e4220fbac803929775a3fb5eb150dee3849b4491f805346518e6c52b154  Sources/AutomntCore/BaselineMountDecision.swift
ecc2b852c1bbcc09264cebe7b6a379b28be51ce1339f11bcb44e1173848ab71f  Sources/AutomntCore/RecoveryRound.swift
a2cdd33b88b9a38fbc9e1be56059db4370a52caa6401a5cfc1dcd052df84ac71  Sources/AutomntPlatform/BackgroundEvaluator.swift
ede0ca417351f8ab2c8998c9062d21aa5c0bcb39974f1665bbc8ed5f7f2cbd19  Sources/AutomntCLI/Entry.swift
```

`git status --short` 与验证开始时一致；`Tests/AutomntCoreTests/` 无 `ZZ*` 探针文件；所有变异仅存在于 `/tmp/v8`。

# 附：R5 修复与复验（core-round-dev 追加，未改写上文验证者原文）

由实现者（`core-round-dev`，共享任务 task-19/R5）追加，只记录针对 G1/G2 与「预言机覆盖过度声称」的修复与复验；上文验证结论、原始输出与缺陷描述一律未改动。本轮未触碰 `Sources/AutomntCLI/Entry.swift`（sha256 与 V3/V8 冻结记录一致：`ede0ca41…`，`:4790`/`:4936` 断言原样保留），也未改 `apps/`、`scripts/`、`specs/`。

## G1 修复：planner 的动作以 `judgment.decision` 为唯一依据

- `Sources/AutomntCore/RecoveryVolumeDecision.swift` 新增 `RecoveryVolumeAction.planned(for:)`：**「共享 decision → 计划动作」的唯一映射函数**（六种决策一一对应）。
- `Sources/AutomntCore/RecoveryRound.swift` 的逐卷分派由 `switch signal` 改为 **`switch judgment.decision`**；各分支的 `action` 一律取 `.planned(for: judgment.decision)`。`signal` 仅剩两处非动作用途：`unknownConservative` 的保守 `everHealthyMounted` 账本标记、以及 superseded/通知额度**结算**（注释已写明「动作唯一来源是 judgment.decision」）。
- 唯一例外并有注释：`cleanupThenRecover` 的清理**执行失败**时按 `.pendingUnreachable` 记录（这是执行结果覆盖，不是第二套映射）。
- 顺带修正一处 R5 之前就存在的同类问题：`judgment` 由 `var` 改回 `let`（不再被二次改写）。

## G2 修复：nil 边界必须原样传递，且空串等同「无边界」

- `Sources/AutomntPlatform/BackgroundEvaluator.swift:317`：`boundary: recovery.file.sessionBoundary ?? ""` → **`recovery.file.sessionBoundary`**（nil 保持 nil）。
- `Sources/AutomntCore/RecoveryVolumeDecision.swift` 的 peer 门：`if !present, let boundary = context.boundary` → 追加 **`!boundary.isEmpty`**。有效边界标识形如 `"<network>|<loginEpoch>"`（`RecoverySessionIdentity.combined`），故 `nil` 与 `""` 都表示「尚未建立边界」，二者给出同一结论（跳过对端检查）。
- 另一处**本轮新发现并修复**的一致性缺陷：改动前 `BaselineMountDecision` 的对端抑制是**短路返回 `suppressed`**（在尝试上限/重试间隔门**之前**），而 task-15 的共享实现把它降级为「改 signal 后继续走门」。这会让 helper 把「对端抑制」错报成 `deferred`。现已恢复短路语义（返回 `.sessionSuppressed` 判定）。该缺陷是扩大预言机矩阵（加入真实对端身份）后由差分预言机自己抓出来的。

## 三处调用点的一致约定（已用断言固定）

| 路径 | 边界传参 | nil / `""` 结论 |
| --- | --- | --- |
| planner | `RecoverySessionPolicy.advance` 后的具体标识（恒非 nil/空） | 永不出现 nil；由 `plannerUsesPostAdvanceConcreteBoundary` 固定 |
| `BaselineMountDecision` | `state.sessionBoundary`（原样） | 均可挂载 |
| helper 桥接 | `recovery.file.sessionBoundary`（原样，**不再 `?? ""`**） | 均可恢复 |

新增 `Tests/AutomntPlatformTests/RecoveryBoundaryConsistencyTests.swift`（5 项）覆盖：共享门对 nil/`""` 结论一致、`BaselineMountDecision` 一致、helper 桥接一致、helper 原样传 nil，并以**真实边界仍抑制**作反证（防真空断言）。

## 预言机覆盖订正（Lead 追加项，选 (b) 扩矩阵）

`Tests/AutomntCoreTests/BaselineDelegationEquivalenceTests.swift`：

- 配置由单共享扩为**两个主机/共享**（`//a.example/s` 与 `//b.example/t`），新增 `peerKind` 维度（0=同边界 suppressed、1=everHealthyMounted、2=无记录、3=不同挂载点），使 `RecoverySuppressionPolicy.protectedByPeer` 的 `peer.identity != identity` 守卫**真正被触发**（此前该分支恒为死代码——V8 的 5.4 节判断成立）。
- 矩阵由 345,600 扩为 **1,382,400**（`#expect(cases.count == 1_382_400)`），**0 不一致**。
- 判别力复验：改小 `peerKind` 维度 → 红（1 issue）；退回 legacy 内联 → 红（27 issues）。即扩大后仍非恒真。

## 防回归断言（G1 关键）

新增 `Tests/AutomntCoreTests/RecoveryDecisionBindingTests.swift`（4 项）：

- `planningMapBindsEveryDecisionToOneAction`：六种 decision ↔ 动作逐项绑定，并断言映射**单射**（不塌缩）。
- `plannerActionIsBoundToSharedDecisionForAllReachableCases`：planner 可达的五种 decision，断言 `judgment.decision == 预期` 且 `计划动作 == .planned(for: decision)`，并断言**副作用与 decision 一致**（仅 recover/cleanupThenRecover 挂载、仅 cleanupThenRecover 清理，其余零副作用）。
- `deferredDecisionConsumesNoBudgetOrSideEffects`：deferred 零挂载、零预算、零账本/通知改动。
- `cleanupFailureFallsBackToPendingWithoutMounting`：清理失败退回 pending 且零挂载。

**关于 deferred 的一处诚实说明**：逐卷 `deferred` 在 planner 侧**不可达**（planner 未启用 `appliesRetryInterval`/`appliesAttemptLimit`，该门只在 helper 桥接与 `BaselineMountDecision` 启用；整轮顺延由 `RecoveryRoundPlanner.deferRound` 表达）。这与 R5 之前一致，非本轮引入；测试按实际可达性覆盖五种 + 由映射单测与 helper 路径覆盖 deferred，未用假输入凑数。

## 变异自证（`/tmp/r5-mutation.py`，/tmp 副本；仓库 `shasum` 校验未变异）

**11/11 全部被捕获，基线 PASS-OK（issues=0）**：

| 变异 | 结果 |
| --- | --- |
| G1-a V8 原始复现：`decide()` present+不可达 → `.sessionSuppressed` | **CAUGHT（9 issues）**，此前为 0 |
| G1-b `decide()` 缺失分支 → `.sessionSuppressed` | CAUGHT（70） |
| G1-c `planned(for:)` 把 `.sessionSuppressed` 映射为 `.recover` | CAUGHT（8） |
| G1-d planner 由 `signal` 重新推导动作（第二套映射） | CAUGHT（40） |
| G2-a helper `?? ""` + 空串门同时恢复（pre-R5 状态） | CAUGHT（7） |
| G2-a-guard 仅移除 `!boundary.isEmpty` | CAUGHT（6） |
| G2-a2 helper 用合成非空兜底替代 nil | CAUGHT（5） |
| G2-b 空串重新被接受 | CAUGHT（6） |
| G2-c 对端抑制不再短路 | CAUGHT（1） |
| 预言机矩阵缩小 | CAUGHT（1） |
| 预言机退回不委托 | CAUGHT（27） |

**两条最初报 NOT-CAUGHT 的变异已逐个查清，均非漏判**：① 「planner 改用 `RecoveryVolumeAction` 做 switch」是**编译失败**（枚举成员不存在），非行为变异；等价的合法变异（G1-d）实测 40 issues 被捕获。② 「仅恢复 `?? ""`」在当前实现下是**等价变异**——因为新增的 `!boundary.isEmpty` 门已把空串规范化，故单改这一行不改变结论；G2-a 因此改为「`?? ""` + 移除空串门」的配对变异（对应真实的 pre-R5 状态），实测被捕获。G2-a2 进一步证明「合成非空兜底」也会被捕获。

## 验收原文

- `swift build` → `Build complete!`
- `swift test` → **AutomntCoreTests 108 tests in 30 suites passed** + **AutomntPlatformTests 66 tests in 18 suites passed**（V8 基线 94/28、61/17；本轮新增 Core 14 项、Platform 5 项）
- `bash scripts/build.sh /tmp/automnt-g` → exit 0，`--version` **3.4.0**，`--self-test` → **295 passed, 0 skipped, 0 failed**
- `xcodebuild … -configuration Release -derivedDataPath .build/xcode-g CODE_SIGNING_ALLOWED=NO build` → **BUILD SUCCEEDED**；产物含 `Contents/Resources/AppIcon.icns` 与 `Assets.car`，`Info.plist` 的 `CFBundleIconFile`/`CFBundleIconName` 均为 `AppIcon`
- `python3 scripts/verify-localization.py` → **exit 0**

## 行为变化（逐条）

1. **G1**：planner 的动作来源由「`signal` 二次推导」改为「`judgment.decision` 唯一映射」。对既有可观察行为**无语义变化**（两种映射在改动前一致，差异只在「哪一份是权威」）；变化在于退化现在**可被测试发现**。
2. **G2**：`sessionBoundary == nil` 时 helper 不再启用同路径对端抑制（回到改动前 helper 经 `BaselineMountDecision` 的行为）；`""` 亦不启用。方向是**收紧一致性**且与 `BaselineMountDecision` 对齐；用户可见效果是「尚未建立会话边界时，同路径备用身份不再被误抑制」，属恢复能力的小幅恢复，未放宽任何安全条件。
3. **短路语义恢复**：对端抑制重新先于尝试上限/重试间隔返回 `suppressed`，消除 helper 把它错报为 `deferred` 的可能。

## R5 仍未覆盖（不得据此宣称闭合）

- 无真实 SMB/NetFS/磁盘仲裁；所有断言均为注入 runner/探活/状态文件。
- 未启动真实 worker 子进程、未跑 `PermissionStore.resolve()` 签名授权、Keychain 凭据、真实 `EvaluationPermit` 争用、真实 launchd 触发。
- **G1 的影响仍是静态推导**：`BaselineMountDecision` 的真实消费者是签名隔离的 `MountWorker` 子进程，本轮未启动；「映射退化不会被发现」已由包测试闭合，但未在真实 worker 上观察。
- helper 的 `supersededFiltered` 在单主机轮次内仍恒为空操作；跨主机 superseded 仅由 CLI/planner 覆盖。
- GUI 未消费共享判定（本轮未改 `apps/`）。
