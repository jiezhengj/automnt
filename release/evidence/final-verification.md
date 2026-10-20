# 结论摘要

独立验证者 `verifier3`（共享任务 task-9）对**冻结后的工作区**做第三轮（V3）最终复验：重跑构建、整包测试、CLI 自测、`xcodebuild Release`、通知路由反例，并对 R3（task-8）修复的 DEF-5/DEF-6 与 Lead 新增的 `Tests/AutomntCoreTests/OwnershipConflictTests.swift` 做独立变异复核。

本轮**未采信任何实现者或前两轮验证者的数字**，全部命令在本机重跑；变异实验只在 `/tmp` 的 `rsync` 副本上进行。工作区 1597 个非 `.build`/`.git` 文件在复验开始与结束时逐文件 sha256 **完全一致**，未修改任何源码、测试、`Package.swift` 或工程文件；唯一新增文件为本文件。

**最终判定：通过（无阻塞性缺陷）。** 全部构建、测试、自测、App 构建与通知路由反例通过；三条点名变异全部仍被测试捕获。

> **阅读须知（两遍复验）**
> 本文件分两遍写成，请以**第二遍（增量复验，见第 12 节）**的数字与结论为准。
> - **第一遍**（第 1-11 节）：针对 Lead 修改测试文件**之前**的磁盘状态。该遍发现 DEF-7（`BackendOwnership.swift:50` 调用者快照过期校验无测试保护）、DEF-8（`OwnershipConflictTests.swift:70` 弱断言）、DEF-9（重复覆盖）。**这三项已由 Lead 在测试文件内修复，并已在本文件第 12 节独立复验通过**；第 1-11 节保留为修复前的原始记录，故其中的 Core **85**/26、`OwnershipConflictTests` **6** 项等数字**已过期**，不作为最终结论。
> - **第二遍（第 12 节）**：针对 Lead 修改后的当前磁盘状态。最终基线为 Core **86**/26 + Platform **46**/16、`OwnershipConflictTests` **7** 项、`--self-test` **295 passed / 0 failed**；变异 (A)(B) 及 (a)(b)(c) 全部复跑通过。

| 编号 | 第一遍结论 | 最终状态（第 12 节） |
| --- | --- | --- |
| 1 构建与测试 | 通过（Platform 46/16、Core 85/26） | **通过**（Platform 46/16、Core **86**/26） |
| 2 CLI 构建与自测 | 通过（`--version` 3.4.0、`--self-test` 295/0/0） | **通过**（同上） |
| 3 xcodebuild Release | 通过 | **通过** |
| 4 通知路由不变式 | 通过 | **通过**（新产物复跑一致） |
| 5 变异 (a)(b)(c) | 全部被捕获（21 / 1 / 9 issues） | **全部被捕获** |
| 6 新测试复核 | 4 项断言具约束力；1 条弱断言、1 个重复用例 | **DEF-7/8/9 已修复并复验通过**；新增断言无真空/无过弱/无重复 |
| 7 隐私抽查 | 通过（附预先存在项） | **通过**（结论不变） |
| 8 覆盖缺口 DEF-7 | **发现 1 项** | **已由 Lead 修复并复验闭合** |

# 验证环境

| 项目 | 值 |
| --- | --- |
| 系统 / 架构 | macOS 27.2（26B5101f），arm64 |
| Xcode | 27.0（27A266a），SDK macosx27.0 |
| 声明版本 | `automnt.swift` 内 `let automntVersion = "3.4.0"` |
| 复验沙箱 | `/tmp/v3-mut`（`rsync -a --exclude .build --exclude .git` 副本） |

工作区关键文件 sha256（复验前后未变）：

| 文件 | sha256 |
| --- | --- |
| `Sources/AutomntCore/BackendOwnership.swift` | `4c9dc46d81d5bcf3ce342757520979757825c80864548c07aa1de8eaed7370a8` |
| `Sources/AutomntCore/RecoveryRound.swift` | `e5c878033bb11756fe2eadfefc244e10d4de7a1b01b3afd99fce62a45a5f22ce` |
| `Sources/AutomntPlatform/NotificationChannel.swift` | `a71aea31f7b6d582aee9674fc0a6dc3f6784dca020a3dcd18ced0c4e69e6c789` |
| `Tests/AutomntCoreTests/OwnershipConflictTests.swift` | `dded46ae3493cf06de61fbd0e40e497564c31e45226b5a5bb7bdd90978a4c010` |
| `Tests/AutomntPlatformTests/NotificationChannelTests.swift` | `7ecd8ea8fb14561b6b303f7d0d6923bc0c1a125076309aca3cbf0d4676f605ff` |
| `apps/Automnt/AutomntApp.swift` | `b0a990c341e4bb9d6dd4e03ddce0c797e09fc80a53d255e353c9ca72ed1cc61b` |
| `automnt.swift` | `f519025a670c09e6d3ec6649e680e1004f12b3afffd9fb41cc1231dd90e10ba0` |
| `Package.swift` | `4b894d00f50a83478017848e0f64a4133867a88bdd4b812d501cc2aa0f7b079c` |

`Sources/AutomntCore/RecoveryRound.swift` 与 V1 快照 sha256 逐字节相同（`e5c87803…5f22ce`），R3 未触碰该文件，与 task-8 声明吻合。

# 1. `swift build` 与整包 `swift test`

```
$ swift build
Build complete! (0.79秒)
BUILD_EXIT=0

$ swift test
Test run with 46 tests in 16 suites passed after 1.804 seconds.   (AutomntPlatformTests)
Test run with 85 tests in 26 suites passed after 0.246 seconds.   (AutomntCoreTests)
```

- **0 失败**：以 `grep -c '✘'` 复核运行日志为 `0`；`swift test` 自身 exit 0。
- **0 skipped / 0 disabled**：全仓库 `grep -rniE '\.disabled|withKnownIssue' Tests/` 命中 `0`。
- 静态计数交叉核对（锚定行首的 `^\s*@Test\b`，非子串计数）：`Tests/AutomntCoreTests/**` 合计 **85**、`Tests/AutomntPlatformTests/**` 合计 **46**；suite 数 `26` / `16`，与 runner 报告**完全一致**。
- 与 V2 基线对照：Core 79 → **85**（+6，即 Lead 新增的 `OwnershipConflictTests` 6 项）、Platform 44 → **46**（+2，R3 的 DEF-5 测试层）。数字与 git diff/快照差异吻合。

判定：**通过**。

# 2. `scripts/build.sh`、`--version` 与 `--self-test`

```
$ rm -f /tmp/automnt-final-v && bash scripts/build.sh /tmp/automnt-final-v
3.4.0
3.4.0
3.4.0
BUILD_SH_EXIT=0
-rwxr-xr-x@ 1 <user>  wheel  1618192 Oct  9 15:04 /tmp/automnt-final-v

$ /tmp/automnt-final-v --version
3.4.0        (exit 0)

$ time /tmp/automnt-final-v --self-test | tail -1
Self-tests: 295 passed, 0 skipped, 0 failed
SELFTEST_EXIT=0     real 0m1.002s
```

判定依据：`/tmp/automnt-final-v` 为 1618192 字节、`--version` 3.4.0，即由当前源码经 `swiftc -O` 新构建，**不是**仓库根目录的旧预编译产物（根产物为 3.3.2）。`scripts/build.sh` 内部先跑 `generate-version.py` 并 `--check` 自校验；我在调用前后对工作区全部 1597 个文件做 sha256 比对，**无任何文件变化**（含 `Sources/AutomntCore/BuildVersion.swift`）。

判定：**通过**（`--version` 3.4.0、`--self-test` 0 failed）。

# 3. `xcodebuild` Release

```
$ xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt \
    -configuration Release -derivedDataPath .build/xcode-final-verify \
    CODE_SIGNING_ALLOWED=NO build
** BUILD SUCCEEDED **
XCODE_EXIT=0
```

产物与元数据（本轮实测）：

| 项目 | 实测 |
| --- | --- |
| `Contents/MacOS/Automnt` | 2191560 B，sha256 `74205538…95ea5` |
| `Contents/Helpers/AutomntHelper` | sha256 `97c0727c…598e10` |
| `Contents/Helpers/AutomntWorker` | 存在且可执行 |
| `Contents/Library/LaunchAgents/` | `automnt.baseline.plist`、`automnt.recovery.plist` |
| `CFBundleShortVersionString` / `CFBundleVersion` | `3.4.0` / `3004000` |
| `CFBundleIdentifier` / `LSMinimumSystemVersion` | `org.automnt.automnt` / `27.0` |
| `Resources/*.lproj` | de, en, es, fr, ja, ko, pt-BR, zh-Hans, zh-Hant（九语） |
| `plutil -lint` | 三份 plist 均 `OK` |
| `KeepAlive` / `StartInterval` / `StartCalendarInterval` | **无命中** |
| `codesign -dv` | `flags=0x20002(adhoc,linker-signed)`，`Signature=adhoc` |

判定：**构建成功**。真实签名与 entitlements **未验证也不可验证**（本轮 `CODE_SIGNING_ALLOWED=NO`）。

# 4. 通知路由不变式反例（真实进程）

被测可执行文件：`.build/xcode-final-verify/…/Automnt.app/Contents/MacOS/Automnt`。判据：≤10s 退出、不残留进程。

## 4.1 畸形参数（task-9 点名 7 条）

| argv | exit | 耗时 | 存活 | stderr 末行 |
| --- | --- | --- | --- | --- |
| `--deliver-notification --count abc` | **6** | 0.504s | 无 | `delivery=failed reason=malformedArguments count=1` |
| `--deliver-notification --count 0` | **6** | 0.014s | 无 | 同上 |
| `--deliver-notification --count 99999999` | **6** | 0.010s | 无 | 同上 |
| `--deliver-notification --count`（缺值） | **6** | 0.009s | 无 | 同上 |
| `--deliver-notification --count=abc` | **6** | 0.007s | 无 | 同上 |
| `--deliver-notification --count=0` | **6** | 0.007s | 无 | 同上 |
| `--deliver-notification --count=` | **6** | 0.006s | 无 | 同上 |

七条全部满足「≤10s 退出且为失败码」，且**没有一条退回 GUI 常驻**。DEF-5 的真实症状（6s 后仍存活）未复现。

## 4.2 正例与 helper

| 命令 | 期望 | 实测 |
| --- | --- | --- |
| `--deliver-notification --count=5` | 诊断行 `count=5` | exit=**5**，0.012s，`reason=permissionNotDetermined count=5` ✅ DEF-6 生效 |
| `--deliver-notification --count 1` | exit 5 | exit=**5**，0.010s，`count=1` |
| `Contents/Helpers/AutomntHelper --probe-notification-channel` | 非 134 | exit=**5**，0.217s；`probe: bundleID=missingIdentity` / `helper-direct-child=unavailable` / `notifier=unavailable` |

## 4.3 关键反向回归：无参数与 `-psn_0_12345` 仍进 GUI

| 命令 | 8s 后存活 | 结论 |
| --- | --- | --- |
| `Contents/MacOS/Automnt`（无参数） | **true** | 进入 GUI 并常驻，`.notRequested` 分支未被误伤 |
| `Contents/MacOS/Automnt -psn_0_12345` | **true** | macOS 注入的 `-psn_` 参数未被误判为投递调用 |

两条均在预算到期后由测试脚本 `terminate()` 清理，并额外 `kill` 兜底。

## 4.4 残留进程清理

```
$ pgrep -fl Automnt
（空）
```

测后显式核对全机 `Automnt` 进程为空，**无残留**。测试过程中另发现一个挂在 `/private/tmp/v3-mut` 下、由被中断的变异实验遗留的 `swiftpm-testing-helper` 进程，已 `kill -9` 清理；该进程不属于工作区产物。

判定：**通过**。

# 5. 独立变异实验（`/tmp` 副本）

沙箱：`rsync -a --exclude .build --exclude .git <工作区>/ /tmp/v3-mut/`（26 MB）。每条变异前先还原副本，施加**单点**修改，再跑整包 `swift test`。副本无变异基线为 `46/16 + 85/26 passed`。

| 编号 | 变异 | 目标 | 结果 |
| --- | --- | --- | --- |
| (a) | `.malformedArguments` → `return .startGUI`（恢复 DEF-5 静默放行） | `NotificationChannel.swift:388-390` | **失败**：Platform 46/16 failed with **21 issues**（`deliveryCommandLinesNeverDisposeToStartGUI` 20 + `realDispositionKeepsBoundedFailureForMalformedArguments` 1） |
| (b) | 删除 `state.revision == current.revision` 子句 | `BackendOwnership.swift:50-51` | **失败**：Core 85/26 failed with **1 issue**（`OwnershipConflictTests.swift:210`） |
| (c) | 删除 `working.everHealthyMounted = true` 赋值行 | `RecoveryRound.swift:373` | **失败**：Core 85/26 failed with **9 issues**（`RecoveryRoundTests.swift:131/171/181/183-188`） |

(c) 的 9 条 issue 原文（节选）与 V1/V2 记录一致，仍是跨轮用例 `corruptStateNeverFallsThroughToRemountOnceReadableAgain` 检测到「损坏 → 可读后绕过会话抑制被重挂」的真实退化：

```
Expectation failed: corrupt.state.volumes[volume.identity]?.everHealthyMounted == true
Expectation failed: readable.plan.contains { $0.action == .recover } == false
Expectation failed: readable.recovered.isEmpty
Expectation failed: harness.mountCalls.isEmpty
```

即：**三条点名的退化在冻结后的工作区上仍全部被测试捕获，防回归成立。**

## 5.1 （b）的关键补充：新文件是唯一保护

Lead 新增 `OwnershipConflictTests.swift` 是否真的增强了 (b)，我做了对照实验——在副本中**删除该测试文件**后重跑同一 (b) 变异：

```
== (b) 变异 + 删除 OwnershipConflictTests.swift ==
Test run with 46 tests in 16 suites passed
Test run with 79 tests in 25 suites passed      ← 完全无感
（exit 0）

== (b) 变异 + 保留 OwnershipConflictTests.swift ==
Test run with 85 tests in 26 suites failed with 1 issue   ← :210 报出
```

**结论：在 Lead 新增该文件之前，(b) 所示的 `state.revision == current.revision` 校验没有任何测试保护**；删除该文件后整包与 CLI 自测对该退化完全无感。新文件对 (b) 的增强是真实且唯一的。

## 5.2 新文件对其它退化的边际价值

| 变异 | 保留新文件 | 删除新文件 | 判定 |
| --- | --- | --- | --- |
| `HandoffCoordinator` catch 分支 `.failed` → `.active`（`verifiedStatus: .enabled`） | 9 issues（新文件 2 条 + HandoffTests 7 条） | 7 issues（全在 HandoffTests） | 新文件**新增** 2 条精确断言（`:183`、`:184`），但非唯一保护 |
| 同上，`verifiedStatus: .unavailable`（保持原样） | 6 issues | 6 issues（全在 HandoffTests） | 新文件**未**额外报错 |
| `ConfigRepository` 也去取 `evaluation.lock`（锁独立性退化） | 4 issues（新文件） | 8 issues（全在既有测试） | 新文件非唯一保护 |
| `StableFileLock` 排他性移除（flock 变 no-op） | 0 issues（**新文件 6/6 通过**） | 16 issues（全在既有测试） | 新文件**未**捕获 |

即：新文件对 (b) 是唯一保护，对「双 active」有增量但非唯一，对锁排他性退化的捕获能力**弱于**既有测试。

## 5.3 额外施加的 4 条敏感性变异（用于压力测试新文件）

| 编号 | 变异 | 结果 |
| --- | --- | --- |
| X2 | `StableFileLock.init` 在 open 前先 `removeItem`（原子替换锁文件） | **失败** 2 issues（`:79`、`:80` inode 断言） |
| X3 | `ConfigRepository` 额外取 `evaluation.lock` | **失败** 4 issues |
| X4 | catch 分支写 `.active/.enabled` + 放宽 `advance` 的 phase 守卫 | **失败** 2 issues（`:183`、`:184`）——真正的双 active 被新测试的「无双 active」断言挡住 |
| Z1 | `isAutoMountRecoveryEnabled` 改为 `isAutomationEnabled`（两开关耦合） | **失败** 3 issues（新文件 2 条，但与既有测试重复，见第 6 节） |

另有一条 Y1（把 `EvaluationPermit` 的锁改为阻塞获取）导致测试进程**挂死**（`flock` 无 `LOCK_NB` 即无限等待），本身印证该处断言依赖真实锁争用；该实验已终止并还原副本。

所有变异均在 `/tmp/v3-mut` 内完成，工作区文件 shasum 与实验前一致（见第 8 节）。

# 6. `OwnershipConflictTests.swift` 断言强度复核（严格挑刺）

逐条核对它声称覆盖的 6 项不变量。方法：读源码 + 在副本上施加针对性变异，确认断言是否真的**挡得住**改动。

## 6.1 逐条判定

| # | 用例 | 声称的不变量 | 变异验证 | 判定 |
| --- | --- | --- | --- | --- |
| 1 | `inFlightSnapshotRejectsMountPointChangeWithoutReplacingOperationLock` | 在途锁 inode 不变；旧快照不启动新动作 | X2（锁被替换）→ `:79`/`:80` 报错 | **有效** |
| 2 | `inFlightSnapshotRejectsDeletedMountPointTarget` | 删除 mount_point 后旧快照被拒 | (b) 变异组相关；`:112` 断言 `configurationConflict` | **有效** |
| 3 | `automationAndRecoverySwitchesStayIndependentAcrossRoundTrips` | 两开关独立往返 | Z1 → 报错，但**与既有测试重复** | 有效但重复 |
| 4 | `failedRegistrationNeverLeavesTwoActiveOrDeadlocks` | 无双 active、无死锁 | X4 → `:183`/`:184` 报错 | **有效**（关键断言） |
| 5 | `backendStateRevisionMismatchIsRejectedEvenWhenCallerSnapshotMatches` | 后端状态 revision 失配被拒 | (b) → `:210` 报错 | **有效，且是该规则唯一保护** |
| 6 | `configurationSaveDoesNotHoldEvaluationLock` | 配置保存不持评估锁 | X3 → 报错 | **有效** |

**没有发现真空断言**：该文件不含 `allSatisfy`，唯一 `isEmpty` 断言（`:110`）作用于刚赋值 `hosts = []` 的对象，是「赋值确实生效」的正向确认，非真空。inode 断言我做了专门的真空性排查——若 `url` 不存在，`attributesOfItem` 会 `throw` 导致用例失败；我把 `inode` 辅助函数改成显式 `Issue.record` + 缺失即报错的版本后重跑，6/6 **仍然通过**，证明两处 inode 取值均来自**真实存在**的文件，断言非真空。

## 6.2 弱断言 DEF-7（低）：`:70` 的 `#expect(throws: NSError.self)`

```swift
// OwnershipConflictTests.swift:70-74
#expect(throws: NSError.self) {
    _ = try EvaluationPermit(...)   // 期望因并发抢锁失败
}
```

- 问题：Swift 中**任意** `Error` 都能桥接到 `NSError`（本机编译验证：`(e as? NSError)` 恒成功，`.configurationConflict` → `main.MyIssue/0`）。因此该断言无法区分「并发抢锁被拒」与任意其它错误。
- 证据：施加上文 Y2 变异（移除 `flock` 排他性，锁退化为 no-op）后，该断言**仍然通过**（`OwnershipConflictTests` 6/6 passed）。我在变异副本中用探针替换该断言，观察到此时抛出的其实是 `.configurationConflict`——即 **revision 先行失败**，与「并发」无关。
- 现状影响：无功能影响。未变异时探针确认它观察到的确是 `NSPOSIXErrorDomain/35 (EWOULDBLOCK)`，真正的并发保护由 `StableFileLock` 实现提供，且既有测试（`ConfigLockTests`、`HandoffTests:289`、`CliOwnershipTests:193` 等 7 个用例）在锁失效时会报错。仅是该处断言**没有锁定「并发」这一语义**。
- 建议（由实现者决定，本验证者不修改源码）：改为断言域名与错误码，例如
  `#expect(throws: NSError.self)` → 捕获后断言 `error.domain == NSPOSIXErrorDomain && error.code == EWOULDBLOCK`。

## 6.3 重复覆盖提示 DEF-8（提示）

`:125-158` 的开关独立性用例与既有 `ConfigurationContractTests.swift:95-109` 高度重叠：把保存路径改成「恢复开关跟随自动开关」后，删除新文件仅剩 `RegressionTests:157` + `ConfigurationContractTests:69/:102/:108` 报错——17 处症状中 7 处与新文件无关。更关键的是 5.2 表中 `StableFileLock` 排他性移除时，该文件 6/6 通过、而既有测试报出 16 issues，说明**新文件的整体捕获能力并不强于既有测试**，其不可替代价值集中在 (b)（`:192-216`）与锁 inode（`:38-93`）两项。

判定：**新测试总体有效，无虚报、无真空断言**；但存在 1 条弱断言与 1 个重复用例，已如实记录。

# 7. 隐私抽查

## 7.1 新增/改动源码与测试

- `Tests/AutomntCoreTests/OwnershipConflictTests.swift:25` 使用 `smb://ownership-<suffix>.example/<suffix>`，主机名由 `ownership-\(suffix).example` 动态拼接，属通用示例域，**非真实目标**；无硬编码 IP、用户名、私有共享路径。
- `Tests/AutomntPlatformTests/NotificationChannelTests.swift:228` 有一条反向隐私断言：`#expect(!line.contains("smb://") && !line.contains("/Volumes/"))`，即诊断行**不得**含私有路径——这是本轮新增的收紧。
- 源码 IP 字面量扫描命中：`Entry.swift:364`（Apple 证书扩展 OID `1.2.840.113635.100.6.1`）、`:4080`（`127.0.0.1` 不可达端口自测）、`:4135/4137/4139/4154/4155/4313…`（`192.168.1.100`、`10.0.0.1`）。经 `git show HEAD:automnt.swift` 核对，`192.168.1.100` 在 HEAD 中出现 **14** 次、`10.0.0.1` 出现 **5** 次，均为拆分前既有示例，**非本轮引入**。
- 新增文件不含任何绝对路径与用户名。

## 7.2 `release/` 全目录

| 检查项 | 命中 | 判定 |
| --- | --- | --- |
| `/Users/` | `round-verification.md:20`（工作目录表）、`notifications.md:3` | 仓库自身绝对路径，**非私有挂载目标**；见下 |
| 本机用户名 | 同上两处 + `round-verification.md:109`（`ls -l` 输出） | 同上 |
| 私有 IP | `round-verification.md:60-62` 的 `192.168.1.100` / `10.0.0.1` / `127.0.0.1` / Apple OID | 引用源码既有示例的**检查记录**，非配置数据 |
| 真实共享路径 | 无 | 无 |
| `smb://` 私有主机 | 无 | 无 |
| 主机名关键字（nas/synology/qnap 等） | `round-verification.md:63` 的 `nas.local` / `nas.invalid` | 通用示例主机名 |

**预先存在项（非本轮引入）**：task-9 第 7 条字面要求「`release/` 不得含 `/Users/`」，但 `notifications.md:3` 与 `round-verification.md:20,109` 三处含仓库绝对路径与本机用户名（`round-verification.md` 自身第 65 行还写明「`release/` 全目录无本机用户名、无 `/Users/`」，与实际不符）。这三处均为**仓库自身路径**，不泄露私有挂载目标、凭据或主机地址，但确实与「不得含 `/Users/`」的字面要求冲突，且属 V1/V2 阶段既有内容，不在本轮写范围内。本文件按 task-9 要求未写入任何绝对路径与本机用户名（仅在第 7.2 节以「`/Users/`」这一形式指代该检查项）。

判定：**隐私红线通过**（无真实私有目标）；字面规则有预先存在的偏差，已如实记录。

# 8. 工作区完整性与清理

```
$ find . -type f -not -path './.build/*' -not -path './.git/*' -print0 | sort -z | xargs -0 shasum -a 256 > /tmp/v3-baseline-sha256.txt
$ wc -l /tmp/v3-baseline-sha256.txt
    1597
（复验结束后重跑同一命令）
$ diff /tmp/v3-baseline-sha256.txt /tmp/v3-final-sha256.txt
（无输出）
WORKSPACE_UNCHANGED
```

- 复验前后工作区 **1597 个文件逐个 sha256 完全一致**，工作区零改动。
- `/tmp/v3-mut` 副本在每条变异后还原；对 `Sources`、`Tests`、`apps`、`scripts`、`Package.swift`、`automnt.swift` 全量比对，与工作区**逐文件一致**（`COPY_CHECK_DONE` 无差异输出）。
- 变异过程中写入副本的探针文件 `Tests/AutomntCoreTests/V3ProbeTests.swift` 已删除并核对不存在。
- 派生的 GUI / helper / 测试进程已全部清理：`pgrep -fl 'Automnt|automnt|swiftpm-testing'` 为空。

结论：本验证者**未修改工作区任何源码、测试、`Package.swift` 或工程文件**；唯一新增文件为本文件。

# 9. 缺陷与提示清单（第一遍，修复前）

> DEF-7 / DEF-8 / DEF-9 已由 Lead 在 `Tests/AutomntCoreTests/OwnershipConflictTests.swift` 内修复；修复的独立复验见第 12 节。本节保留修复前的原始描述与最小复现，便于追溯。

## DEF-7（中低，**已修复**）：`EvaluationPermit` 的「调用者快照过期」校验无任何测试保护

- 类型：测试覆盖缺口（实现本身正确，与 V1 的 DEF-1 同类）。
- 位置：实现 `Sources/AutomntCore/BackendOwnership.swift:50`（`current.revision == expected.revision`）；对应新用例 `Tests/AutomntCoreTests/OwnershipConflictTests.swift:192-216` 只覆盖另一条（后端状态 revision）。
- 证据：在 `/tmp` 副本删除该子句后，`swift test` **85/26 + 46/16 全绿**，CLI `--self-test` **295 passed / 0 failed** 亦全绿（脚本 `/tmp/v3-selftest-gap.sh`）。用探针可证明此时**过期的调用者快照被接受**，`permit.snapshot.revision` 指向旧配置 A 而磁盘已是 B。
- 可达性：CLI `beginEvaluation`（`Sources/AutomntCLI/ServiceAdapter.swift:151-166`）先 `repository.read()` 取得快照，之后才构造 `EvaluationPermit`；而新测试自己证明了配置保存**不取** `evaluation.lock`（`OwnershipConflictTests.swift:219-230`），因此「保存抢在 permit 构造前」的窗口客观存在。
- 影响：该子句失效时，持有过期快照的调用者会拿到一份**已过期**的 `snapshot` 并据此继续执行（`Entry.swift:5427-5437` 直接以 `ownershipPermit.snapshot.configuration` 作为真实动作依据），即可能按已被替换的配置发起挂载/恢复动作。
- 最小复现（不修改工作区）：
  ```
  rm -rf /tmp/m && mkdir /tmp/m
  rsync -a --exclude .build --exclude .git <工作区>/ /tmp/m/ && cd /tmp/m
  python3 - <<'PY'
  import pathlib
  p = pathlib.Path('Sources/AutomntCore/BackendOwnership.swift'); s = p.read_text()
  old = "guard current.revision == expected.revision, state.generation == generation,"
  assert s.count(old) == 1
  p.write_text(s.replace(old, "guard state.generation == generation,"))
  PY
  swift test        # 期望红灯，实际 46/16 + 85/26 全绿
  ```
- 建议（由实现者决定）：在 `backendStateRevisionMismatchIsRejectedEvenWhenCallerSnapshotMatches` 之外，补一条「后端状态已前进到新 revision，但调用者仍持旧 `expected` 快照」的用例（`store` 与 `repository` revision 一致、仅 `expected` 过期），断言抛 `configurationConflict` 且 `evaluation.lock` inode 不变。

## DEF-8（低，**已修复**）：`OwnershipConflictTests.swift:70` 的 `#expect(throws: NSError.self)` 不具区分力

- 见 6.2。任意 `Error` 均可桥接为 `NSError`；移除 `flock` 排他性后该断言仍通过，此时实际抛出的是 `.configurationConflict` 而非锁争用错误。
- 建议改为断言 `NSPOSIXErrorDomain` + `EWOULDBLOCK`。

## DEF-9（提示，**已修复**）：新文件个别用例与既有测试重复

- 见 6.3。`:125-158` 与 `ConfigurationContractTests.swift:95-109` 重叠；该文件在锁排他性退化下甚至不如既有测试敏感。非缺陷，仅记录其不可替代价值集中在 (b) 与锁 inode 两项。

## DEF-10（提示）：`AutomntApp.swift` 胶水行的残余未覆盖

- `apps/Automnt/AutomntApp.swift:282-288` 仍不在 SwiftPM 测试目标内（GUI target 结构使然）。R3 已把**判定**抽到 `NotificationLaunchDisposition`（有测试），残余风险仅剩「照着 disposition 执行 `exit(outcome.exitCode)`」这一步。与 V2 的 DEF-5 相比风险已显著下降，本轮实测也确认该胶水行行为正确（第 4 节）。

# 10. 已实际验证 与 仍未验证

## 10.1 已实际验证（本机真实命令与原始输出）

- 工作区 1597 个文件 sha256 在复验前后**完全一致**；`/tmp/v3-mut` 副本逐文件还原。
- `swift build` exit 0；整包 `swift test` **0 失败 / 0 skipped**（Platform 46/16、Core 85/26），与静态 `@Test` 计数（46、85）一致。
- `scripts/build.sh /tmp/automnt-final-v` exit 0；`--version` **3.4.0**；`--self-test` **295 passed / 0 skipped / 0 failed**。
- `xcodebuild Release`（`CODE_SIGNING_ALLOWED=NO`）`** BUILD SUCCEEDED **`；产物含两个 helper、两份 LaunchAgent、九语 `lproj`；`plutil -lint` 通过；无 KeepAlive/StartInterval/StartCalendarInterval。
- 通知路由：7 条畸形参数全部 exit 6 且 ≤0.504s、无残留；`--count=5` 诊断 `count=5`；`--count 1` exit 5；helper 探针 exit 5（非 134）；**无参数与 `-psn_0_12345` 均常驻进 GUI**；测后 `pgrep` 无残留。
- 三条点名变异 (a)/(b)/(c) **全部被捕获**（21 / 1 / 9 issues），至今仍具防回归效力。
- **新增 `OwnershipConflictTests.swift` 对 (b) 的增强经对照实验证实为唯一保护**（删除后同一变异全绿）。
- 新文件 6 项用例逐条变异验证；无真空断言（含专门的 inode 真空性排查）。
- 额外 5 条敏感性变异（X2/X3/X4/Z1/Y1）结果均已记录。
- 隐私抽查：新增源码/测试无真实私有目标；`release/` 无真实共享路径。

## 10.2 仍未验证（本轮不具备条件，不得据此宣称通过）

- **真实签名与 entitlements**：`CODE_SIGNING_ALLOWED=NO`，产物为 ad-hoc 链接器签名。真实 Developer ID / App Store 签名、沙盒 entitlements、Team ID、`BundledCodeVerifier` 的 Apple 锚校验**未验证**。
- **真实通知投递**：全部实测落在 exit 5（`permissionNotDetermined`）或 exit 6（`malformedArguments`）。`delivered`(0)、`suppressedForeground`(3)、`denied`(4) 三条路径**未在真机走通**；授权后通知是否用户可见、`--sound` 是否实际发声、前台静默是否正确，**未验证**。
- **LaunchServices 路由**：app 已运行时投递请求被转交给既有实例的真实行为与退出码**未验证**（无参数常驻与投递调用是分别单进程测量的）。
- **真实 SMB / 磁盘仲裁**：无任何真实 SMB 主机或共享被挂载、卸载、探活；`NetFSMountURLSync`、死卷清理、`DiskArbitration` 普通卸载、Spotlight 防索引、worker 匿名管道与签名校验的实机路径**均未验证**。变异实验只证明**共享协调器层**规则被锁住；`RecoveryRoundPlanner` 仍未接入 `BackgroundEvaluator`。
- **TCC / 目录授权 / Keychain**：launchd 身份下的授权、独立 helper 的持久权限、真实 Keychain 读写与无提示挂载**未验证**。
- **launchd 真实生命周期**：两份 LaunchAgent 未 `bootstrap`/注册；WatchPaths 事件到达、退出 GUI 后自动恢复、helper 实际启动与退出**未验证**；`SMAppService` 注册/停用/批准流程**未在系统上执行**。
- **真实网络会话边界**：`RecoverySessionCollector` 的 getifaddrs/utmpx 采集未在真实网络切换与重新登录下验证。
- **GUI 验收**：只验证了「无参数/`-psn_` 启动会常驻」，**未做窗口渲染、键盘、VoiceOver、浅深色、较大文字与九语实机验收**；九语资源仅确认文件存在。
- **畸形参数边界未穷举**：本轮覆盖 task-9 点名的 7 条 + 正例，未穷举全部 argv 组合。

# 11. 复现材料位置

| 内容 | 路径 |
| --- | --- |
| 变异沙箱副本（工作区源码未受影响） | `/tmp/v3-mut`、`/tmp/v3-mut-pristine` |
| 变异脚本 | `/tmp/v3-mutations.py`、`/tmp/v3-own-marginal.py`、`/tmp/v3-own-sensitivity.py`、`/tmp/v3-double-active.py`、`/tmp/v3-marginal3.py`、`/tmp/v3-lock-loadbearing.py`、`/tmp/v3-lock-decisive.py`、`/tmp/v3-inode-vacuity.py`、`/tmp/v3-gap-proof.py`、`/tmp/v3-switch-unique.py` |
| 变异日志（逐条原始输出） | `/tmp/v3-mutlogs/*.log` |
| 通知路由真实进程脚本与输出 | `/tmp/v3-runtime.py` |
| helper 探针原始输出 | `/tmp/v3-helper-out.txt`、`/tmp/v3-helper-err.txt` |
| CLI 自测对覆盖缺口无感的反证 | `/tmp/v3-selftest-gap.sh` → `/tmp/v3-selftest-gap-bin` |
| 新源码 CLI 构建 | `/tmp/automnt-final-v` |
| 本轮 xcodebuild 产物 | `.build/xcode-final-verify/Build/Products/Release/Automnt.app` |
| 工作区 sha256 基线 / 终值 | `/tmp/v3-baseline-sha256.txt`、`/tmp/v3-final-sha256.txt` |
| NSError 桥接验证 | `/tmp/nserror-bridge.swift` |

工作区在复验开始与结束时逐文件 sha256 完全一致；所有派生的 GUI、helper 与测试进程均已清理，`pgrep` 无残留。

# 12. 增量复验（针对 Lead 修复后的当前磁盘状态）

本节为**最终结论**。Lead 在收到第一遍回报后，只修改了 `Tests/AutomntCoreTests/OwnershipConflictTests.swift`（新增 1 个用例、重写 1 条断言、精简 1 个用例），并要求我对当前磁盘状态重跑。以下所有数字均为**改动后**重新采集，未沿用第一遍的任何数字。

## 12.1 变更范围核实：只有测试文件变化

对工作区全量文件做 sha256 前后对照（第一遍基线 1597 个文件 vs 现在 1598 个文件）：

```
files before: 1597   after: 1598

CHANGED:
   ./Tests/AutomntCoreTests/OwnershipConflictTests.swift
ADDED:
   ./release/evidence/final-verification.md
REMOVED:
   （无）
```

即：**除 Lead 修改的测试文件外，工作区没有任何其它文件被改动**；新增文件是验证者自己的证据文件。

被要求点名的源码文件 sha256（与第一遍基线逐一相同，证明 `Sources/**` 未被触碰）：

| 文件 | sha256 | 与第一遍基线 |
| --- | --- | --- |
| `Sources/AutomntCore/BackendOwnership.swift` | `4c9dc46d81d5bcf3ce342757520979757825c80864548c07aa1de8eaed7370a8` | 相同 |
| `Sources/AutomntCore/StableFileLock.swift` | `0f6ed28c3170b635b4f6090fa9a9ca0afbf8733be5133857f5a4c9f1d1f5690c` | 相同 |
| `Sources/AutomntCore/RecoveryRound.swift` | `e5c878033bb11756fe2eadfefc244e10d4de7a1b01b3afd99fce62a45a5f22ce` | 相同 |
| `Sources/AutomntCLI/Entry.swift` | `ede0ca417351f8ab2c8998c9062d21aa5c0bcb39974f1665bbc8ed5f7f2cbd19` | 相同 |
| `Sources/AutomntCLI/ServiceAdapter.swift` | `0e19cb28ea71a9028f5ed7ce1c0cb54ca5d8eac3f05c8f84949975063d7df554` | 相同 |
| `Sources/AutomntPlatform/NotificationChannel.swift` | `a71aea31f7b6d582aee9674fc0a6dc3f6784dca020a3dcd18ced0c4e69e6c789` | 相同 |
| `apps/Automnt/AutomntApp.swift` | `b0a990c341e4bb9d6dd4e03ddce0c797e09fc80a53d255e353c9ca72ed1cc61b` | 相同 |
| `Sources/AutomntCore/BuildVersion.swift` | `1c0327f215d9b672e7d3cd633bc6b67b430420abcc981a50fcf8530c5d0a9c56` | 相同 |
| `automnt.swift` | `f519025a670c09e6d3ec6649e680e1004f12b3afffd9fb41cc1231dd90e10ba0` | 相同 |
| `Package.swift` | `4b894d00f50a83478017848e0f64a4133867a88bdd4b812d501cc2aa0f7b079c` | 相同 |

被改动的测试文件现为 `e861d45f19229f6834f7ba3197c3c555926990c630ce4c4b8db51ed7f05a2685`（第一遍为 `dded46ae…a4c010`）。

判定：Lead 的「只动测试文件、没动产品源码」声明**成立**。

## 12.2 构建、测试与自测（当前状态）

```
$ swift build
Build complete! (0.45秒)
BUILD_EXIT=0

$ swift test
Test run with 46 tests in 16 suites passed after 1.081 seconds.   (AutomntPlatformTests)
Test run with 86 tests in 26 suites passed after 0.247 seconds.   (AutomntCoreTests)
TEST_EXIT=0     issues=0     skipped/disabled=0
```

- Core **86**/26、Platform **46**/16，**0 失败 / 0 skipped**，与 Lead 给出的基线一致。
- 静态计数（锚定 `^\s*@Test\b`）：`Tests/AutomntCoreTests/**` **86**、`Tests/AutomntPlatformTests/**` **46**，与运行计数一致；`OwnershipConflictTests.swift` 单文件 **7** 项（原 6 项 + 新增 `staleCallerSnapshotIsRejectedEvenWhenBackendStateIsCurrent`）。
- 单套件复核：`swift test --filter OwnershipConflictTests` → `7 tests in 1 suite passed`，7 个用例逐条 PASS。

```
$ rm -f /tmp/automnt-final-v2 && bash scripts/build.sh /tmp/automnt-final-v2
BUILD_SH_EXIT=0
$ /tmp/automnt-final-v2 --version
3.4.0        (exit 0)
$ /tmp/automnt-final-v2 --self-test | tail -1
Self-tests: 295 passed, 0 skipped, 0 failed   (exit 0)
```

```
$ xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt \
    -configuration Release -derivedDataPath .build/xcode-final-verify2 \
    CODE_SIGNING_ALLOWED=NO build
** BUILD SUCCEEDED **
XCODE_EXIT=0
```

判定：**通过**。`--self-test` 与 Lead 预期（295 passed / 0 failed）一致。

## 12.3 通知路由反例（新产物复跑）

用 `.build/xcode-final-verify2` 的新产物重跑全部 12 条，与第一遍结论一致：

| argv / 场景 | exit | 耗时 | 存活 |
| --- | --- | --- | --- |
| `--count abc` / `0` / `99999999` / 缺值 / `--count=abc` / `--count=0` / `--count=` | 全部 **6** | 0.006–0.404s | 无 |
| `--count=5` | **5**（诊断 `count=5`） | 0.012s | 无 |
| `--count 1` | **5** | 0.010s | 无 |
| `AutomntHelper --probe-notification-channel` | **5**（非 134） | 0.210s | 无 |
| 无参数 | — | 8.005s 后仍存活 | **是（GUI）** |
| `-psn_0_12345` | — | 8.006s 后仍存活 | **是（GUI）** |

`PGREP_AFTER: ''`，测后无残留进程。判定：**通过**。

## 12.4 点名变异复跑（Lead 修复后）

在**新副本** `/tmp/v3b-mut`（由修复后的工作区 `rsync` 建立）上复跑：

### (A) 删除 `current.revision == expected.revision`（对应 DEF-7）

```
### A-stale-caller-snapshot exit=1
Test staleCallerSnapshotIsRejectedEvenWhenBackendStateIsCurrent() recorded an issue
    at OwnershipConflictTests.swift:244:9: Expectation failed: an error was expected but none was thrown
Test run with 7 tests in 1 suite failed after 0.017 seconds with 1 issue.
```

**已被捕获。** 且我进一步做了**唯一性对照**：删除 `OwnershipConflictTests.swift` 后重跑同一变异 ——

```
### A-without-own exit=0
Test run with 46 tests in 16 suites passed
Test run with 79 tests in 25 suites passed      ← 完全无感
```

说明 Lead 新增的 `staleCallerSnapshotIsRejectedEvenWhenBackendStateIsCurrent` 是该子句**唯一**的保护，DEF-7 的修复真实有效（不是靠别的测试顺带覆盖）。

### (B) `flock` 排他性移除（对应 DEF-8）

```
### B-no-exclusive-lock exit=1
Test inFlightSnapshotRejectsMountPointChangeWithoutReplacingOperationLock() recorded an issue
    at OwnershipConflictTests.swift:77:21: Expectation failed: error.domain == NSPOSIXErrorDomain
    at OwnershipConflictTests.swift:78:21: Expectation failed: error.code == Int(EWOULDBLOCK)
Test run with 7 tests in 1 suite failed after 0.017 seconds with 2 issues.
```

**已被捕获**——这正是第一遍缺失的能力：旧的 `#expect(throws: NSError.self)` 在该变异下 6/6 通过，新断言会报 2 条红灯。

我另用探针确认新断言观察到的确实是锁争用错误（而非其它错误）：

```
V3B-PROBE observed NSPOSIXErrorDomain/35
```

即 `NSPOSIXErrorDomain` + `EWOULDBLOCK`(35)，与断言逐字相符，说明该断言现在**真正锁定了「并发抢锁」这一语义**，不再被 revision 冲突等其它错误蒙混通过。

整包复跑（同一变异）：Core 86/26 failed with 15 issues（新文件 2 条 + 既有测试 13 条），Platform 全绿。

### (a)(b)(c) 三条原始点名变异（当前状态）

| 编号 | 变异 | 结果 |
| --- | --- | --- |
| (a) | `NotificationChannel.swift` disposition `.malformedArguments` → `.startGUI` | **失败** Platform 46/16 with **21 issues**（`deliveryCommandLinesNeverDisposeToStartGUI` + `realDispositionKeepsBoundedFailureForMalformedArguments`） |
| (b) | 删除 `state.revision == current.revision` | **失败** Core 86/26 with **1 issue**（`backendStateRevisionMismatchIsRejectedEvenWhenCallerSnapshotMatches`） |
| (c) | 删除 `RecoveryRound.swift:373` 的 `everHealthyMounted = true` | **失败** Core 86/26 with **9 issues**（`unreadableStateSuppressesInsteadOfFirstUseMount`、`corruptStateNeverFallsThroughToRemountOnceReadableAgain`） |

判定：**三条至今仍全部被测试捕获，防回归成立。**

## 12.5 对 Lead 新增/修改断言的严格复核

按与第一遍相同的怀疑标准逐条审。

### 12.5.1 新增用例 `staleCallerSnapshotIsRejectedEvenWhenBackendStateIsCurrent`（`:220-257`）

- **场景构造正确**：先让配置前进到新 revision，再经产品协调器 `transfer` 让后端状态**也**前进到同一 revision（`:236-240` 两行 `#expect` 显式确认），此时磁盘与后端状态一致，唯一过期的是调用者快照。这精确隔离了 `expected` 这一条校验，不会与「后端状态 revision 失配」混淆。
- **有对照断言，非单边**：`:250-256` 用与磁盘一致的快照成功取得 permit，并断言 `snapshot.revision == saved.revision`、`!snapshot.configuration.isAutoMountRecoveryEnabled`。这排除了「因为别的原因失败」的解释——是**对照组**而非真空断言。这一点比第一遍的建议更完善。
- **非真空、非过弱**：变异 (A) 下仅有此用例报错（1 issue），说明它确实承载了该子句的保护；同时它**不是唯一命中的偶然**（`backendStateRevisionMismatch…` 在 (A) 下仍通过，证明两条校验互相独立、各守一段）。这是本次修复中最有价值的一条。
- **无 `allSatisfy`/空集合真空问题**。

### 12.5.2 重写的锁争用断言（`:71-79`）

```swift
do {
    _ = try EvaluationPermit(...)
    Issue.record("a second operation lock must not be obtainable while the first is held")
} catch let error as NSError {
    #expect(error.domain == NSPOSIXErrorDomain)
    #expect(error.code == Int(EWOULDBLOCK))
}
```

- **已具备区分力**：变异 (B) 下报 2 条红灯；探针确认正常路径观察到 `NSPOSIXErrorDomain/35`。第一遍的 DEF-8 已闭合。
- **`Issue.record` 兜底得当**：若第二把锁真的取得了，会显式记录失败，而不是静默通过。这比原来的 `#expect(throws:)` 更严密。
- 残余提示（非缺陷）：`catch let error as NSError` 的 `as` 转换在 Swift 中对任意 `Error` 都成功，因此仍属「先宽后窄」，但由于紧接两条精确断言，实际区分力已足够；若要更严格可用 `catch { let ns = error as NSError; #expect(...) }`，语义等价，无需修改。

### 12.5.3 精简后的开关独立性用例（`:133-158`）

- 第一遍指出的 DEF-9（与 `ConfigurationContractTests`/`RegressionTests` 重复）已按要求精简：删去了原来与既有测试重复的「只关恢复开关」往返，只保留缺键 nil 语义（`:140-142`）与「改回自动挂载时恢复开关的显式 false 仍在」（`:151-157`）。
- **精简后仍有效，且仍有独立价值**：施加「保存时 automation=true 会丢弃显式 recovery=false」这一针对性变异后：
  - 保留新文件：2 issues（新文件 `:157` + `ConfigurationContractTests:108`）；
  - 删除新文件：1 issue（仅 `ConfigurationContractTests:108`）。
  即精简后该用例对「跨开关组合」仍有**增量**保护，不再纯重复。
- 无真空断言。判定：**有效，重复问题已消除**。

### 12.5.4 其余用例

`:38-98`（inode/在途锁）与 `:161-188`（无双 active）与 `:192-216`（后端状态 revision）经第一遍变异验证仍具约束力；本次改动未触及这三段语义（仅 `:71-79` 段被重写，`:38-98` 的 inode 断言原样保留）。

**结论：Lead 本轮新增/修改的断言无真空、无过弱、无重复；复核通过。**

## 12.6 当前缺陷清单（最终）

| 编号 | 严重度 | 状态 |
| --- | --- | --- |
| DEF-7 调用者快照过期校验无测试保护 | 中低 | **已修复并复验闭合**（变异 (A) 红灯，且为唯一保护） |
| DEF-8 `#expect(throws: NSError.self)` 不具区分力 | 低 | **已修复并复验闭合**（变异 (B) 红灯 2 issues，探针确认 `EWOULDBLOCK`） |
| DEF-9 开关用例与既有测试重复 | 提示 | **已修复并复验闭合**（精简后仍有增量保护） |
| DEF-10 `AutomntApp.swift` 胶水行残余未覆盖 | 提示 | 仍存在（结构性：GUI target 不进 SwiftPM 测试目标）；判定层已抽到可测的 `NotificationLaunchDisposition`，残余风险仅剩「照着 disposition 执行 `exit`」一步，本轮实测行为正确 |
| `release/` 中本机绝对路径（预先存在） | 提示 | 仍存在；属 V1/V2 阶段既有内容，非本轮引入 |

**当前无阻塞性缺陷。**

## 12.7 本轮增量复验的清理与完整性

- 副本 `/tmp/v3b-mut`、`/tmp/v3b-pristine` 在每条变异后均还原，并逐文件与工作区核对为 **OK**（`BackendOwnership.swift`、`StableFileLock.swift`、`ConfigRepository.swift`、`OwnershipConflictTests.swift` 全部一致）。
- 工作区最终状态：**仅** `Tests/AutomntCoreTests/OwnershipConflictTests.swift` 为 Lead 改动、`release/evidence/final-verification.md` 为验证者新增；`Sources/**`、`apps/**`、`Package.swift`、`automnt.swift` 全部未变（第 12.1 节逐文件 sha256）。
- 派生进程已清理：`pgrep -fl 'Automnt|automnt|swiftpm-testing'` 返回空。
- 本轮 xcodebuild 产物保留在 `.build/xcode-final-verify2/`（与第一遍的 `.build/xcode-final-verify/` 并存，均为构建中间产物，不影响工作区源码）。

## 12.8 仍未验证边界（与第 10.2 节相同，最终结论同样适用）

第一遍第 10.2 节列出的未验证边界**全部继续有效**，不因本轮测试修复而改变：真实签名与 entitlements、真实通知投递路径（`delivered`/`suppressedForeground`/`denied`）、LaunchServices 路由、真实 SMB 与磁盘仲裁、TCC/目录授权/Keychain、launchd 真实生命周期与 `SMAppService`、真实网络会话边界、GUI 九语与 VoiceOver 实机验收、argv 组合穷举。逐条内容见第 10.2 节，此处不重复。

特别地：本轮新增的测试全部是**纯逻辑层**（SwiftPM 测试目标内）的断言，它们能锁定 `EvaluationPermit` 的三条校验与锁争用语义，但**不能**替代真实环境中「配置保存与评估并发发生」这一时序的实机验证——该时序在真机上的窗口（配置锁与评估锁非同一把）仍未实测。
