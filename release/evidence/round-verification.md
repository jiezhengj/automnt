# 结论摘要

独立验证者对**当前磁盘上的最终状态**重跑了本轮三项实现（task-1 A1 共享恢复轮次协调器、task-2 B1 通知投递管线、task-3 B2 CLI owner-aware 与统一锁），不采信实现者报告的数字。

总体上三项实现的主干接线成立、构建与既有回归全绿、通知身份守卫的崩溃反例已独立复现并确认被堵住。但发现 **1 项中等缺陷**（A1 有一条对外可观察规则完全没有测试保护，且该规则在 helper 路径上真实可达）和 **1 项低危健壮性缺陷**（app 主可执行在畸形投递参数下会退回 GUI 常驻路径），另有 2 处测试断言偏弱。详见「缺陷清单」。

| 编号 | 结论 | 依据 |
| --- | --- | --- |
| 构建 | 通过 | `swift build`、`scripts/build.sh`、`xcodebuild Release` 均退出 0 |
| 测试 | 通过（0 失败） | Core 74/25、Platform 43/16；CLI 自测 295 passed / 0 skipped / 0 failed |
| B1 通知身份守卫 | 通过（含反例复现） | 崩溃机制独立复现为 exit 134；守卫路径全部返回 5，无 134 |
| A1 规则等价性 | **部分未通过** | 6 条规则中 5 条有测试保护，第 3 条 `unknownConservative` 的 `everHealthyMounted` 写入无任何测试覆盖（变异后全绿） |
| B2 owner-aware | 通过 | `beginEvaluation` 持 `evaluation.lock`、`EvaluationPermit` 核 owner/generation/revision；app owner 拒绝登记；plist 无 KeepAlive/StartInterval |
| 隐私 | 通过 | 新增源码/证据无真实私有目标；IP 字面量均为 HEAD 既有示例 |

# 验证环境

| 项目 | 值 |
| --- | --- |
| 工作目录 | `/Users/jiezhengj/Documents/Project/automnt` |
| 系统 / 架构 | macOS 27.2（26B5101f），arm64 |
| Xcode | 27.0（27A266a），SDK macosx27.0 |
| 源码版本 | `automnt.swift` 声明 `3.4.0` |

# 1. 工作区与隐私抽查

```
$ git --no-pager diff --stat
 AGENTS.md     |   26 +
 README.en.md  |   14 +
 README.zh.md  |   14 +
 automnt.swift | 6074 +--------------------------------------------------------
 4 files changed, 60 insertions(+), 6068 deletions(-)

$ git status --short
 M AGENTS.md
 M README.en.md
 M README.zh.md
 M automnt.swift
?? .agent-cli-delegation.json
?? .specify/assessments/cli-gui-commercialization/
?? Package.swift
?? Sources/
?? Tests/
?? apps/
?? release/
?? scripts/
?? specs/005-swiftui-mas-gui/

$ git --no-pager diff --check
（无输出，exit 0）
```

结论：改动范围与「CLI 拆分到 `Sources/`，根入口退化为版本声明 + 转发」一致，`automnt.swift` 减少 6068 行属预期。未跟踪文件均为本轮新增工程/源码/证据，无未申报的散落文件。`diff --check` 无空白错误。

`smb://` / IP 字面量 / 私有路径抽查（`grep -rEon '([0-9]{1,3}\.){3}[0-9]{1,3}' Sources Tests apps scripts release`）：

| 命中 | 位置 | 判定 |
| --- | --- | --- |
| `192.168.1.100` / `10.0.0.1` | `Sources/AutomntCLI/Entry.swift:4135,4137,4154,4313` | HEAD `automnt.swift` 原样保留（HEAD 内出现 14 次），非本轮新增 |
| `127.0.0.1` | `Entry.swift:4080` | 既有不可达端口自测 |
| `1.2.840.113635.100.6.1` | `Entry.swift:364` | Apple 证书扩展 OID，非主机地址 |
| `nas.local` / `nas.invalid` / `*.example` / `server.local` | 源码自测与 `Tests/**` | 通用示例主机名，非真实目标 |

`release/` 全目录无 `jiezhengj`、无 `/Users/`、无私有 IP、无 `/Volumes/<具体名>`。唯一命中为 `release/evidence/notifications.md:3` 的仓库自身绝对路径，非私有目标。

结论：隐私红线通过。新增源码未引入任何真实私有目标。

# 2. `swift build` 与 `swift test`

```
$ swift build
Build complete! (0.63秒)

$ swift test --filter AutomntCoreTests
Test run with 74 tests in 25 suites passed after 0.243 seconds.

$ swift test --filter AutomntPlatformTests
Test run with 43 tests in 16 suites passed after 0.856 seconds.
```

`grep -c '@Test'` 交叉核对：`Tests/AutomntCoreTests/**` 合计 74，`Tests/AutomntPlatformTests/**` 合计 43，与 runner 报告完全一致。全仓库无 `.disabled`、无 `withKnownIssue`、无跳过测试。

结论：**0 失败**。数字与 task-4 期望一致。

# 3. `scripts/build.sh` 与 `--self-test`

任务书要求用 `/tmp` 下的新构建，不能用仓库根目录的旧预编译产物。先确认二者确实不同：

```
$ ./automnt --version                 # 仓库根预编译（旧发布产物）
3.3.2
$ ./automnt --self-test | tail -1
Self-tests: 267 passed, 0 skipped, 0 failed

$ shasum -a 256 /tmp/automnt-005-verify automnt
bf4520e7cc58b0291da575f9b025cb4bed3ad9fbb98b852c0eab8eef395b9729  /tmp/automnt-005-verify
d495d8e06678558f138b2565ddc14ef540f3061e2d042bf3b6a2f5762586c792  automnt
```

新源码构建：

```
$ rm -rf /tmp/automnt-005-verify && bash scripts/build.sh /tmp/automnt-005-verify
3.4.0
3.4.0
3.4.0
EXIT=0
-rwxr-xr-x@ 1 jiezhengj  wheel  1618192 Oct  9 14:27 /tmp/automnt-005-verify

$ /tmp/automnt-005-verify --version
3.4.0

$ /tmp/automnt-005-verify --self-test | tail -1
Self-tests: 295 passed, 0 skipped, 0 failed
   （real 0m0.986s）
```

判定依据：`/tmp` 产物为 3.4.0、1618192 字节、包含 `refusedAppOwner` 新符号；根预编译产物为 3.3.2、1083168 字节、不含 `3.3.2` 之外的版本串。`--self-test` 的 267 → 295（+28）全部来自源码构建产物，**不是**根目录旧产物。

结论：`scripts/build.sh` 成功；源码构建产物 `--version` 3.4.0、`--self-test` **295 passed / 0 skipped / 0 failed**。

# 4. `xcodebuild` Release 与产物结构

```
$ xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt \
    -configuration Release -derivedDataPath .build/xcode-verify CODE_SIGNING_ALLOWED=NO build
...
** BUILD SUCCEEDED **
XCODE_EXIT=0
```

产物结构：

```
Automnt.app/Contents
├── Helpers
│   ├── AutomntHelper      (1277408 B, executable)
│   └── AutomntWorker      (1274240 B, executable)
├── Info.plist
├── Library/LaunchAgents
│   ├── automnt.baseline.plist  (598 B)
│   └── automnt.recovery.plist  (667 B)
├── MacOS/Automnt
├── PkgInfo
└── Resources/{de,en,es,fr,ja,ko,pt-BR,zh-Hans,zh-Hant}.lproj
```

```
$ plutil -p Automnt.app/Contents/Info.plist
{
  "CFBundleExecutable" => "Automnt"
  "CFBundleIdentifier" => "org.automnt.automnt"
  "CFBundleShortVersionString" => "3.4.0"
  "CFBundleVersion" => "3004000"
  "LSMinimumSystemVersion" => "27.0"
  ...
}
```

签名状态（任务书第 5 条要求以产物结构替代 `codesign -d --entitlements -`）：

```
$ codesign -dv Automnt.app
CodeDirectory ... flags=0x20002(adhoc,linker-signed)
Signature=adhoc
$ codesign -d --entitlements - Automnt.app
Executable=.../Contents/MacOS/Automnt      （无 entitlements，仅链接器 ad-hoc 签名）
```

LaunchAgent 定义关键键（`plutil -p` 与 `grep` 双向核对）：

| plist | BundleProgram | 触发键 | 禁用键 |
| --- | --- | --- | --- |
| `automnt.baseline.plist` | `Contents/Helpers/AutomntHelper` | `RunAtLoad`、`WatchPaths`(NetworkInterfaces/airport) | 无 |
| `automnt.recovery.plist` | `Contents/Helpers/AutomntHelper` | `RunAtLoad`、`StartOnMount`、`WatchPaths`(+`/Volumes`) | 无 |

`grep -rn "KeepAlive\|StartInterval\|StartCalendarInterval\|RunAtLoad" apps/Automnt/Resources/` 仅命中两个 `RunAtLoad`。`BundleProgram` 指向的 `Contents/Helpers/AutomntHelper` 在构建产物中确实存在且可执行。`plutil -lint` 两份均 OK。

结论：构建成功，嵌入结构与声明一致，**无 KeepAlive / 无 StartInterval / 无 StartCalendarInterval**。签名与 entitlements **未验证也不可验证**（本轮 `CODE_SIGNING_ALLOWED=NO`，仅为 ad-hoc 链接器签名）。

# 5. 通知身份守卫崩溃反例（重点）

## 5.1 独立复现底层崩溃（证明该风险真实存在）

先把「bundle 身份不可解析」这一前提独立复现，避免只依赖实现者注释：在 `/tmp/nilbundle/` 用 9 行 Swift 直接调用 `UNUserNotificationCenter.current()`：

```
$ cd /tmp/nilbundle && ./nilbundle-probe
exit=134
--- stderr ---
bundleID=nil
*** Terminating app due to uncaught exception 'NSInternalInconsistencyException',
    reason: 'bundleProxyForCurrentProcess is nil: mainBundle.bundleURL file:///private/tmp/nilbundle/'
    ... +[UNUserNotificationCenter currentNotificationCenter] ...
bash: ... Abort trap: 6
```

再把同一探针放进 app 包内的 `Contents/Helpers/`：

```
$ /tmp/appverify/Automnt.app/Contents/Helpers/nilbundle-probe
exit=134
bundleID=nil
*** ... reason: 'bundleProxyForCurrentProcess is nil: mainBundle.bundleURL file:///tmp/appverify/Automnt.app/Contents/Helpers/'
```

结论：`Contents/Helpers/` 下 `Bundle.main.bundleIdentifier == nil` 成立，且该身份下直接调用系统通知 API **确实 exit 134（SIGABRT）**。这不是推断，是本机可复现事实。

## 5.2 反例实测（防回归）

把构建出的 app 主可执行文件复制到两个 helper 身份目录，按任务书要求分别调用：

```
# 准备
$ ditto .build/xcode-verify/.../Automnt.app /tmp/appverify/Automnt.app
$ cp Contents/MacOS/Automnt Contents/Helpers/Automnt
$ mkdir -p Contents/Library/LoginItems && cp Contents/MacOS/Automnt Contents/Library/LoginItems/Automnt

A) app 主可执行（对照，应 ≤10s 且码 ∈{0,3,4,5,6}）
   MacOS/Automnt --deliver-notification --count 1     exit=5  elapsed=0.13s
   MacOS/Automnt --deliver-notification --count 1     exit=5  elapsed=0.13s   (第2次)
   MacOS/Automnt --deliver-notification --count 1     exit=5  elapsed=0.14s   (第3次)
   MacOS/Automnt --deliver-notification --count 3 --sound  exit=5  elapsed=0.14s
   MacOS/Automnt --deliver-notification              exit=5  elapsed=0.14s
   stderr: automnt notification delivery=unavailable reason=permissionNotDetermined count=1

B) 主可执行复制到 Contents/Helpers/（原崩溃场景）
   Helpers/Automnt   --deliver-notification --count 1  exit=5  elapsed=0.14s
   Helpers/Automnt   --deliver-notification --count 1  exit=5  elapsed=0.14s   (第2次)
   stderr: automnt notification delivery=unavailable reason=identityMissing count=1

C) 主可执行复制到 Contents/Library/LoginItems/
   LoginItems/Automnt --deliver-notification --count 1 exit=5  elapsed=0.14s
   LoginItems/Automnt --deliver-notification --count 1 exit=5  elapsed=0.14s   (第2次)
   stderr: automnt notification delivery=unavailable reason=identityMissing count=1

D) 真实 helper
   Helpers/AutomntHelper       --probe-notification-channel  exit=5  elapsed=0.25s
   LoginItems/AutomntHelper    --probe-notification-channel  exit=5  elapsed=0.37s
   stderr: probe: bundleID=missingIdentity
           probe: helper-direct-child=unavailable
           probe: notifier=unavailable
```

逐条判定：

| 要求 | 实测 | 结论 |
| --- | --- | --- |
| app 主可执行 ≤10s 退出 | 0.13–0.14s | 通过 |
| app 主可执行退出码 ∈{0,3,4,5,6} | 5 | 通过 |
| `Contents/Helpers/` 下为失败码而非 134 | 5（`identityMissing`） | 通过 |
| `Contents/Library/LoginItems/` 下为失败码而非 134 | 5（`identityMissing`） | 通过 |
| 真实 helper 诊断路径不崩 | 5（`missingIdentity`） | 通过 |

`identityMissing` 直接证明 `NotificationBundleIdentity.isDeliverable` 在触碰系统 API 之前就让路径短路（对照 5.1：若未短路必然 134）。

## 5.3 前置检查强度

`Sources/AutomntPlatform/NotificationChannel.swift:28-37` 的 `role(of:)` 基于 `Bundle.main.bundleIdentifier`，`AppNotificationDispatcher.dispatch`（`:247-251`）第一行即 `guard NotificationBundleIdentity.isDeliverable(bundle) else { return ...identityMissing }`，`NotificationDeliveryEntry.run`（`:307-321`）再叠一层 10s semaphore 预算。三层结构在此环境中确实生效。

## 5.4 附带发现：畸形参数会退回 GUI 常驻路径（缺陷 DEF-2，低危）

`automnt --deliver-notification --count abc` 的退出行为与任务书「≤10s 内退出」不符：

```
$ MacOS/Automnt --deliver-notification --count abc      exit=TIMEOUT(>6s)
$ MacOS/Automnt --deliver-notification --count 0        exit=TIMEOUT(>6s)
$ MacOS/Automnt --deliver-notification --count 99999999 exit=TIMEOUT(>6s)
   stderr: sandbox_extension_issue_file_to_process failed for .../Automnt.app
           （即进入了正常 GUI 启动路径，窗口常驻不退出）
```

成因：`NotificationDeliveryRequest.init?(arguments:)`（`NotificationChannel.swift:94-115`）在 `--count` 解析失败时返回 `nil`，`AutomntApp.init()`（`apps/Automnt/AutomntApp.swift:278`）的 `guard let request = ... else { return }` 于是直接放行，落入 SwiftUI 场景。**不是崩溃、不影响父进程投递链路**（`AppNotificationDelivery` 只用 `NotificationDeliveryRequest(count:soundEnabled:)` 生成规范参数），但畸形参数会拉起一个常驻 GUI 窗口。最小复现命令与位置见缺陷清单。

# 6. A1 规则等价性逐条核对（重点）

先核对「实现是否被完整搬进 Core」：`git show HEAD:automnt.swift` 与 `Sources/AutomntCLI/Entry.swift` 逐函数比对，`runRecoveryRound` 仅签名变化（`applyRecovery`/`cleanupVolume` 加 `@escaping`、新增 `ownershipPermit`），**函数体逐字节相同**；判定/账本/通知计数逻辑全部移入 `Sources/AutomntCore/RecoveryRound.swift`。`RecoveryRoundTests.swift` 全部业务配置经 `FileConfigRepository.create/save` 生成，无手写 plist。

下面逐条核对任务书点名的 6 条规则。为区分「有断言」与「断言真的挡得住改动」，我在 `/tmp/mut/` 的**仓库副本**上做变异测试（仓库源码零改动，末尾已用 `shasum` 确认还原一致）。

## 6.1 逐条结论

| # | 规则 | 实现位置 | 测试位置 | 变异是否被捕获 | 判定 |
| --- | --- | --- | --- | --- | --- |
| 1 | 同路径备用**只传播抑制**，不传播健康/修复许可 | `RecoveryRound.swift:267-276` | `RecoveryRoundTests.swift:134-187` | 是（禁用 `signal = .healthyEject` → 6 issues） | 通过 |
| 2 | superseded 路径剔除 | `RecoveryRound.swift:392-407` | `RecoveryRoundTests.swift:191-244` | 是（删除三处 `removeAll` → 2 issues） | 通过 |
| 3 | unknownConservative 不被当 neverMounted | `RecoveryRound.swift:368-379`、`RecoveryState.swift:152-153` | **仅覆盖分类层，未覆盖轮次层 `everHealthyMounted` 写入** | **否（变异后 74/25 与 295/295 全绿）** | **未通过（见缺陷 DEF-1）** |
| 4 | 预算耗尽 → 不发起尝试 | `RecoveryRound.swift:343-350` | `RecoveryRoundTests.swift:248-285` | 是（删除 `budgetRemaining() > 0` 门 → 5 issues） | 通过 |
| 5 | deferred 不耗预算与通知额度 | `RecoveryRound.swift:226-231` | `RecoveryRoundTests.swift:287-310` | 部分（`deferRound` 的 `plan` 断言偏弱，见 DEF-3） | 通过（有保留） |
| 6 | 通知上限 2 且成功恢复重置 | `RecoveryRound.swift:301-311,353-361`、`RecoveryNotificationPolicy.swift:5-9` | `RecoveryRoundTests.swift:314-360` | 是（删除成功分支 `notificationCount = 0` → 1 issue；`consume` 上限 2→3 被 CLI 自测 1 项捕获） | 通过 |

## 6.2 缺陷 DEF-1：规则 3 在轮次层无任何测试保护

规则 3 的**分类层**是有覆盖的：

- `MissingVolumeRecoveryTests.swift:63` 断言 `MissingVolumeRecoveryPolicy.mayMount(signal: .unknownConservative, ...) == false`
- CLI 自测 `Entry.swift:4782-4787` 断言 `judgeRecoverySignal(stateReadable: false) == .unknownConservative` 且 `!isRecoverable && isSuppressed`
- `RecoverySessionTests.swift:93-96` 断言健康策略不改写 unknownConservative

但轮次层那句「保守：不得被后续误判为『从未挂载』」的写入**完全没有断言**。变异实验：

```
# 在 /tmp/mut（仓库副本）删除 RecoveryRound.swift 中的：
#   if signal == .unknownConservative { working.everHealthyMounted = true }
$ swift test  →  Test run with 74 tests in 25 suites passed
$ /tmp/mut-automnt --self-test  →  Self-tests: 295 passed, 0 skipped, 0 failed
```

两套测试**全绿**，即该行被删/被改成 `false` 都不会被任何现有用例发现。`RecoveryRoundTests.unreadableStateSuppressesInsteadOfFirstUseMount` 虽然跑了 corrupt 分支，但只断言了 `state == .suppressed`、`notificationCount == 0`、`cleanupLedger == nil`、`mountCalls.isEmpty`，**没有断言 `everHealthyMounted == true`**，因此挡不住这个退化。

为什么这不是「纯内部字段」而是对外可观察行为：`everHealthyMounted` 正是 `judgeRecoverySignal` 判定 `.healthyEject` 的唯一依据（`RecoveryState.swift:163`，`record?.everHealthyMounted == true → .healthyEject`）。该行失效后，一旦恢复状态从「损坏」转为「可读」，同一个卷会得到 `.neverMounted`，而 `MissingVolumeRecoveryPolicy.mayMount(.neverMounted, enabled:) == true`（`MissingVolumeRecoveryPolicy.swift:9`），于是**绕过会话抑制被重新挂载**——正好违反 FR-002「健康弹出后本会话零重挂」红线。helper 路径真实可达：`BackgroundEvaluator` 在状态损坏时保守跳过、状态恢复可读后重新评估，同一持久记录会跨轮留存。

最小复现（不修改仓库）：

```
rm -rf /tmp/mut && mkdir /tmp/mut
cp -R Sources Tests Package.swift apps scripts automnt.swift /tmp/mut/ && cd /tmp/mut
python3 - <<'PY'
import pathlib
p = pathlib.Path('Sources/AutomntCore/RecoveryRound.swift'); s = p.read_text()
needle = "                if signal == .unknownConservative {\n                    working.everHealthyMounted = true"
assert needle in s
p.write_text(s.replace(needle, "                if false {\n                    working.everHealthyMounted = true"))
PY
swift test 2>&1 | tail -1        # 期望失败，实际：74 tests in 25 suites passed
```

相关位置：`Sources/AutomntCore/RecoveryRound.swift:368-374`（实现）、`Tests/AutomntCoreTests/RecoveryRoundTests.swift:93-130`（缺少断言的用例）。

建议（由实现者决定，本验证者不修改源码）：在 `unreadableStateSuppressesInsteadOfFirstUseMount` 内补一行
`#expect(corrupt.state.volumes[volume.identity]?.everHealthyMounted == true)`，
并补一条「损坏 → 可读后仍不重挂」的跨轮用例。

## 6.3 其余 A1 观察

- 规则 1 的「同路径备用只传播抑制」在包测试层被严格锁定，但注意判据是 `mountPoint` 相等 + 对端记录为 suppressed/healthyEject，而非 SMB 身份相等；源码注释已明确「仅同路径不足以证明两个主机是同一服务器，因此只传播抑制」——方向保守，符合任务书描述。
- 规则 5 的 `deferRound`：`RecoveryRoundTests.swift:299` 使用 `deferred.plan.allSatisfy { $0.action == .deferred }`，对空数组**真空为真**；把 `plan` 改成 `[]` 后仍全绿（变异 M9）。当前 `Entry.swift:5473` 依赖 `deferredVolumeKeys`（有独立断言）而非 `plan`，故暂无功能影响，但该断言不具保护力（DEF-3）。
- 通知上限 2 与重置在 Core 层有硬断言（`:335`、`:343`），且 `consume` 上限从 2 改为 3 会被 CLI 自测 1 项捕获，双重保险。
- 未覆盖分支（结构性，非等价性缺陷）：`RecoveryVolumeAction.attachHealthy`、`.cleanupThenRecover`、`.pendingUnreachable` 在 `Tests/**` 中无直接断言；`cleanupLedger` 的成功写入路径（`RecoveryRound.swift:295`）无包测试覆盖——删除该行后 `swift test` 与 `--self-test` 双双全绿（变异 M6），仅 `cleanupLedger` 的「未写入」边界（`:117`、`:169`）被断言。这属于覆盖盲区，记录在案。

# 7. B2：CLI owner-aware 与统一锁

## 7.1 CLI 动作确实经 `EvaluationPermit`（owner/generation/revision）

```
$ grep -rn "EvaluationPermit" Sources/AutomntCore/BackendOwnership.swift
37:public struct EvaluationPermit {
44:    public init(directory: URL, repository: any ConfigRepository, expected: ConfigSnapshot,
45:                owner: BackendState.Owner, generation: UInt64,
46:                readBackend: () throws -> BackendState) throws {
47:        lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
50:        guard current.revision == expected.revision, state.generation == generation,
51:              state.revision == current.revision else { throw AutomntIssue.configurationConflict }
52:        guard state.owner == owner, state.phase == .active else { throw AutomntIssue.incompatibleOwner }
```

`EvaluationPermit` 在构造时**先取统一 `evaluation.lock`**（`:47`），再复核 revision、generation、owner/phase 三元组；`perform` 用 `withExtendedLifetime(lock)` 把锁持有到有界操作结束（`:58-60`）。

CLI 侧接线：

| 入口 | 位置 | 是否取许可 |
| --- | --- | --- |
| 主流程挂载/恢复 | `Sources/AutomntCLI/Entry.swift:5427`（取）、`:5609`（复核） | 是 |
| 配置菜单「立即重新挂载」 | `Entry.swift:2615`（取）、`:2648`/`:2668`（复核） | 是 |
| 恢复轮本体 | `Entry.swift:3269-3272`：无许可且非自测显式许可 → 保守 `defer`、零挂载副作用 | 是（缺失即保守拒绝） |

`beginEvaluation()` 内另有 `refusesAppClaim` 预检（`ServiceAdapter.swift:152-157`）与 `endEvaluation` 代次复核（`:194-208`）。

## 7.2 app owner 时 CLI 拒绝登记、不静默自愈抢占

```
$ grep -n "refusesAppClaim" Sources/AutomntCLI/ServiceAdapter.swift Sources/AutomntCore/CLIOwnershipGate.swift
ServiceAdapter.swift:110: if CLIOwnershipGate.refusesAppClaim(current) {
ServiceAdapter.swift:153: if CLIOwnershipGate.refusesAppClaim(durable) {
ServiceAdapter.swift:207: if CLIOwnershipGate.refusesAppClaim(try durableState()) { return false }
CLIOwnershipGate.swift:101: public static func refusesAppClaim(_ state: BackendState?) -> Bool { ... owner == .app || desiredOwner == .app }
CLIOwnershipGate.swift:60-64: if appClaim(state) { return state.phase == .failed ? .requiresRepair : .refusedAppOwner(state.phase) }
```

判定逻辑：`desiredOwner` 也算 app claim；app 的 `failed` 残留映射为 `requiresRepair` 而**不是**静默接管。运行时证据（`--self-test` 原始输出）：

```
PASS first CLI run initializes an explicit owner=none/stopped state instead of bypassing the store
PASS app owner produces a structured CLI refusal instead of silent takeover
PASS app ownership survives the CLI refusal unchanged
PASS refused CLI registration leaves the durable state bytes untouched
PASS recovery round without an ownership permit defers without any mount side effect
PASS permitted recovery round still executes mounts end to end
```

包测试侧另有 `Tests/AutomntCoreTests/CliOwnershipTests.swift`（7 项）覆盖 `refusedAppOwner` + `withPermission` 抛 `incompatibleOwner`、字节不变、desiredOwner=app 的 failed 残留、generation 0→1 旧快照被拒、stale revision、`operationInProgress`。全部 passed。

## 7.3 无 KeepAlive / 无轮询 / 无常驻新进程

- 生成的 plist：`plutil -p` 与 `grep` 双向确认两份 LaunchAgent 只有 `RunAtLoad` / `WatchPaths` / `StartOnMount`，**无 KeepAlive / StartInterval / StartCalendarInterval**（见第 4 节）。
- 源码模式：`grep -rn "while true\|Timer\|DispatchSourceTimer" Sources apps` 的全部命中均为 CLI 交互菜单循环、文件读写重试循环，或 `TCPReachabilityProbe.swift:53-58` 的**一次性**超时定时器（`timeout.schedule(deadline: .now() + ...)`，无 `repeating:`），并在 `finish` 中 `timer?.cancel()`。
- `BackgroundRetryScheduler.swift:6` 明确「Runs only after an external trigger, with a bounded scheduling window and no idle polling」，循环上限 `min(max(maxAttempts,1),10)` 且受 `deadline` 截断。
- 无新增常驻守护进程：`git status` 未出现新的 launchd/daemon 目标；app 只嵌入 `AutomntHelper` 与 `AutomntWorker` 两个短命工具（`project.pbxproj` 中均为 `com.apple.product-type.tool`）。
- 守卫代码自身有断言：`CLIOwnershipGate.permitsNonResidentDefinition`（`CLIOwnershipGate.swift:93-97`）拒绝三个键，`CliOwnershipTests.swift:159-169` 与 CLI 自测 `Entry.swift:5050-5051` 各有一条断言。

结论：B2 三项要求均成立。

# 8. 「为通过自测而放宽断言」的痕迹核查（重点）

任务书要求对比 `Sources/AutomntCLI/Entry.swift` 中恢复轮次相关自测断言是否有被修改。

方法：把 `git show HEAD:automnt.swift`（拆分前的单一真相文件，含全部自测）与现在位于 `Sources/AutomntCLI/Entry.swift` 的自测逐函数比对。

```
$ git show HEAD:automnt.swift > /tmp/head-automnt.swift
$ diff /tmp/head-automnt.swift Sources/AutomntCLI/Entry.swift | wc -l
1588   （106 个 hunk；移除 936 行 / 新增 482 行）

$ grep -n 'recoveryFallbackNotificationText\|notificationKeys ==' Sources/AutomntCLI/Entry.swift
3375:func recoveryFallbackNotificationText(...)          （实现）
4945:    check(failedRound.notificationKeys == [firstKey] && round(success: false).notificationKeys == [firstKey] &&
4948:    check(recoveryFallbackNotificationText(...suppressed...) == nil, ...)
4961:          recoveryFallbackNotificationText(for: corruptRound, config: roundConfig) == nil && ...
5164:    let combinedNotice = recoveryFallbackNotificationText(...)
5171:    let sharedPathNotice = recoveryFallbackNotificationText(...)
5183:    check(recoveryFallbackNotificationText(...recovered...) == nil, ...)
5186:    check(recoveryFallbackNotificationText(...notificationKeys...) == nil, ...)
5496:           let notification = recoveryFallbackNotificationText(for: outcome, config: config) {
```

**断言数量是增加而非减少**：`check(` 出现次数 258（HEAD）→ 290（当前），净增 32；CLI 自测 267 → **295**（+28）。

`recoveryFallbackNotificationText` 的**生产者实现确实改了**（HEAD 版按挂载点末段列出可读名，现行版改为 `FailureNotification` 的纯计数文案），这属于产品文案变更，不是放宽断言。逐函数抽取比对确认改动仅为主体替换：

```
--- recoveryFallbackNotificationText: head 1187 chars / cur 541 chars
    -    let readable = affected.map { key -> String in
    -        // 以挂载点最后一段作为可读名，避免暴露主机地址。
    ...
    -    let message = tr("以下共享未能自动恢复：\(list)。请...")
    +    return FailureNotification(failed:..., recovered:..., eligible:...)?.text(english: isEnglish)
```

对应的消费侧断言**同步收紧**，而不是放宽。HEAD 版断言精确文案（列出 A、B 名字），现行版断言新的精确计数文案：

```
- check(combinedNotice?.message == tr("以下共享未能自动恢复：A、B。请...", ...),
-       "fallback notification matches exact contract text and merges unique shares")
+ check(combinedNotice?.message == tr("2 个共享文件夹未能自动恢复。请...", ...),
+       "fallback notification matches privacy-safe count contract and merges unique identities")
+ let privateValues = configuredVolumes(from: takeoverConfig).flatMap { [$0.key, $0.url, $0.mountPoint] }
+ check(!privateValues.contains(where: { !$0.isEmpty && payload.contains($0) }),
+       "private identities addresses and mount paths never enter notification payload")
```

即：坏例子从「同一路径两个主机身份只列一个名字」改为「同一路径两个身份计为 2 且不泄露私有值」，**并新增了一条隐私反向断言**。这是收紧。

敏感性验证（在 `/tmp/mut` 副本上变异，反证断言没有失去约束力）：

| 被改动的实现 | CLI 自测结果 | 结论 |
| --- | --- | --- |
| `FailureNotification.count` 由 `remaining.count` 改为 `+1`（文案数字错位） | 293 passed, **2 failed** | 断言有效 |
| `RecoveryNotificationPolicy.consume` 上限 `2` → `3` | 294 passed, **1 failed** | 断言有效 |
| `runRecoveryRound` 的 `ownershipPermit` 守卫置为 `if false, ...`（去掉缺许可 defer） | 293 passed, **2 failed** | 断言有效 |

同时确认自测其余改动均为**加强**或**无关**：多处 `try? data.write(to:)` 改为 `try? PrivateAtomicFile.replace(...)`（适配 0600 权限读取新规，属测试夹具修正）、新增 `CLIOwnership` 自测块（+5 项断言）、新增 Thread 隔离预算断言。

结论：**未发现为通过自测而放宽断言的痕迹**。恢复轮次相关断言净增加，文案变更处的断言同步按新契约收紧并新增隐私断言，且敏感性变异实验证明核心断言仍具约束力。

# 9. 已实际验证 与 仍未验证

## 9.1 已实际验证（本机真实命令与原始输出）

- 工作区范围、`git diff --check`、隐私抽查（私有 IP / 用户名 / 主机名 / 共享路径）。
- `swift build` 成功；`swift test` 0 失败（Core 74/25、Platform 43/16），与 `@Test` 静态计数一致，无跳过测试。
- `scripts/build.sh /tmp/automnt-005-verify` 成功；`--version` 3.4.0；`--self-test` 295 passed / 0 skipped / 0 failed；并证明该产物确为新源码构建（非根目录 3.3.2 / 267 项旧产物）。
- `xcodebuild` Release 无签名构建 `** BUILD SUCCEEDED **`；产物含 `Contents/Helpers/{AutomntHelper,AutomntWorker}`、`Contents/Library/LaunchAgents/{baseline,recovery}.plist`、九语 `lproj`；`Info.plist` 关键键正确；`plutil -lint` 通过；plist 无 KeepAlive/StartInterval。
- 通知身份守卫：底层崩溃机制独立复现为 exit 134；app 主可执行在 0.13–0.14s 以码 5 退出；复制进 `Contents/Helpers/` 与 `Contents/Library/LoginItems/` 均返回码 5（`identityMissing`）**而非 134**；真实 helper 诊断路径返回码 5 不崩。
- A1 规则等价性：6 条逐条核对完成，5 条经变异实验证明有测试保护，1 条（规则 3 轮次层）证明无保护。
- B2：`EvaluationPermit` 三元组复核与统一锁、app owner 拒绝登记、无 KeepAlive/轮询/常驻进程，均经源码与运行时输出双向确认。
- 断言完整性：与拆分前 HEAD 逐函数比对，自测断言净增，未发现放宽；三项敏感性变异均能被捕获。

## 9.2 仍未验证（本轮不具备条件，不得据此宣称通过）

- **真实签名与 entitlements**：本轮 `CODE_SIGNING_ALLOWED=NO`，产物仅 ad-hoc 链接器签名，`codesign -d --entitlements -` 无内容。真实 Developer ID / App Store 签名、沙盒 entitlements、Team ID 校验、`BundledCodeVerifier` 的 Apple 锚校验**未验证**。
- **真实通知投递**：全部实测为 exit 5（`permissionNotDetermined` / `identityMissing`）。`delivered`(0)、`suppressedForeground`(3)、`denied`(4) 三条路径未在真机走通；授权后通知是否用户可见、声音是否生效、前台静默是否正确，**未验证**。`AppNotificationDelivery` 的 shell 子进程映射与超时行为只由实现者以脚本验证，本轮未重跑。
- **LaunchServices 路由**：app 已运行时请求被转交给既有实例时的真实行为与退出码**未验证**。
- **真实 SMB**：无任何真实 SMB 主机/共享被挂载、卸载或探活；`NetFSMountURLSync`、死卷清理、`DiskArbitration` 普通卸载、Spotlight 防索引、worker 匿名管道与签名校验的实机路径**均未验证**。
- **TCC / 目录授权 / Keychain**：`PermissionStore.resolve` 在 launchd 身份下的授权、独立 helper 的持久权限、真实 Keychain 读写与无提示挂载**未验证**。
- **launchd 真实生命周期**：两份 LaunchAgent 未 `bootstrap`/注册，未证明 WatchPaths 事件到达、退出 GUI 后自动恢复、helper 实际启动与退出。`SMAppService` 注册/停用/批准流程**未在系统上执行**。
- **真实登录/网络会话边界**：`RecoverySessionCollector` 的 getifaddrs/utmpx 采集未在真实网络切换与重新登录下验证。
- **GUI**：未启动窗口，未做键盘/VoiceOver/浅深色/较大文字/九语验收。
- **`codesign` 结论**：任务书第 5 条以产物结构替代签名核验，本轮据此执行，签名侧的通过**不成立**。

# 10. 缺陷清单

## DEF-1（中等）：A1「unknownConservative 不得被后续误判为 neverMounted」在轮次层无任何测试保护

- 类型：测试覆盖缺口（实现本身正确，规则被真实执行；但该规则一旦退化，现有 74+43 项包测试与 295 项自测全部无法发现）。
- 位置：实现 `Sources/AutomntCore/RecoveryRound.swift:368-374`；缺断言的用例 `Tests/AutomntCoreTests/RecoveryRoundTests.swift:93-130`。
- 影响：`everHealthyMounted = true` 是该卷日后被判为 `.healthyEject`（会话抑制）的唯一依据（`Sources/AutomntCore/RecoveryState.swift:163`）。该行失效后，恢复状态由「损坏」转为「可读」时同一卷会落到 `.neverMounted`，而 `MissingVolumeRecoveryPolicy.mayMount(.neverMounted, ...) == true`（`Sources/AutomntCore/MissingVolumeRecoveryPolicy.swift:9`），即**绕过会话抑制被重新挂载**，违反 FR-002 红线。helper 路径可达（`BackgroundEvaluator` 在损坏时保守跳过、恢复可读后重新评估）。
- 最小复现：见 6.2 的 `/tmp/mut` 脚本；执行后 `swift test` 仍报 `74 tests in 25 suites passed`、`--self-test` 仍报 `295 passed`，证明无保护。
- 建议修复：在 `unreadableStateSuppressesInsteadOfFirstUseMount` 内补 `#expect(corrupt.state.volumes[volume.identity]?.everHealthyMounted == true)`，并补一条「损坏 → 恢复可读后仍不重挂」的跨轮用例。

## DEF-2（低危）：畸形 `--deliver-notification` 参数退化为主可执行的 GUI 常驻路径

- 位置：`Sources/AutomntPlatform/NotificationChannel.swift:94-115`（解析失败返回 `nil`）+ `apps/Automnt/AutomntApp.swift:278`（`guard let request = ... else { return }` 静默放行）。
- 现象：`--deliver-notification --count abc`、`--count 0`、`--count 99999999` 均不进入投递路径，而是启动正常 SwiftUI GUI 并常驻，**不满足 ≤10s 退出**。
- 最小复现：
  ```
  .build/xcode-verify/Build/Products/Release/Automnt.app/Contents/MacOS/Automnt \
      --deliver-notification --count abc     # 6s 后仍存活（需外部 kill）
  ```
- 影响面：父进程 `AppNotificationDelivery` 只经 `NotificationDeliveryRequest(count:soundEnabled:)` 生成规范参数（`count` 已被 `max(count,1)` 夹限），因此**内部投递链路不受影响**；仅当外部直接以畸形参数调用 app 可执行文件时才会拉起窗口。不构成崩溃或安全问题，但与该入口「有界、无窗口」的设计意图不符。
- 建议修复：把 `arguments.contains("--deliver-notification")` 作为路由判据，解析失败时 `exit(NotificationExitCode.failed)` 而不是返回 `nil`。

## DEF-3（低）：两条断言真空为真，不具保护力

- `Tests/AutomntCoreTests/RecoveryRoundTests.swift:299`：`#expect(deferred.plan.allSatisfy { $0.action == .deferred })` — 把 `deferRound` 的 `plan` 改成 `[]` 后断言仍通过（变异 M9，双套件全绿）。当前调用方 `Entry.swift:5473` 依赖 `deferredVolumeKeys`（有独立断言），暂无功能影响。
- `Tests/AutomntCoreTests/RecoveryRoundTests.swift:309`：`#expect(harness.mountCalls.count == volumes.count)` 依赖上一步已写入的固定值，非独立事实。
- 建议修复：改为 `#expect(deferred.plan.count == volumes.count)` 与显式集合比较。

## DEF-4（提示，非本轮缺陷）：覆盖盲区

`RecoveryVolumeAction` 的 `.attachHealthy`、`.cleanupThenRecover`、`.pendingUnreachable` 在 `Tests/**` 中无直接断言；`cleanupLedger` 的成功写入（`RecoveryRound.swift:295`）删除后双套件全绿（变异 M6）。`attachHealthy` 的 `notificationCount = 0` 清除（`RecoveryRound.swift:307`）删除后亦全绿（变异 M5）。建议后续补齐。

# 11. 复现材料位置

| 内容 | 路径 |
| --- | --- |
| 新源码构建的 CLI 产物 | `/tmp/automnt-005-verify` |
| app Release 构建产物 | `.build/xcode-verify/Build/Products/Release/Automnt.app` |
| 通知反例用 app 包副本（含 Helpers/LoginItems 注入） | `/tmp/appverify/Automnt.app` |
| 身份崩溃最小复现探针 | `/tmp/nilbundle/nilbundle-probe` |
| 变异测试沙箱副本（仓库源码未受影响） | `/tmp/mut` |
| HEAD 版自测比对基线 | `/tmp/head-automnt.swift`、`/tmp/entry-vs-head.diff` |

仓库工作区在本轮验证结束时与开始时一致（`git status --short` 无变化，`Sources/AutomntCore/RecoveryRound.swift` 与沙箱副本 `shasum` 相同），验证过程未修改任何源码、测试、`Package.swift` 或工程文件。

# 附：R1 修复与复验（core-round-dev 追加，未改写上文验证者原文）

本节由实现者（`core-round-dev`，共享任务 task-5/R1）追加，只记录针对 DEF-1/DEF-3/DEF-4 的补测与变异复验；上文的验证结论、原始输出与缺陷描述一律未改动。**实现语义未做任何修改**：`Sources/AutomntCore/RecoveryRound.swift` 一字节未变（sha256 复验见末尾）。

## DEF-1 修复：轮次层补断言 + 跨轮闭环用例

改动仅落在 `Tests/AutomntCoreTests/RecoveryRoundTests.swift`：

1. 既有 `unreadableStateSuppressesInsteadOfFirstUseMount` 补一行直接断言：
   `#expect(corrupt.state.volumes[volume.identity]?.everHealthyMounted == true)`（并对 `cleanupLedger` 仍是"不写"保持原断言）。
2. 新增跨轮用例 `corruptStateNeverFallsThroughToRemountOnceReadableAgain()`：第一轮 `load: .corrupt` 保守抑制并落账 → 把返回的 `state` 作为第二轮 `load: .loaded(state)` 输入（观测仍为"缺失 + 主机可达"）→ 断言第二轮 `plan == [.suppress]`、`plan` 不含 `.recover`、`recovered` 为空、`suppressed == [identity]`、`mountCalls` 为空、`notificationIdentities` 为空，并用 `judgeRecoverySignal` 复核为 `.healthyEject` 且 `MissingVolumeRecoveryPolicy.mayMount(...) == false`。

## DEF-3 修复：去掉真空为真

`deferredRoundDoesNotConsumeBudgetNotificationOrState` 现在先断言非空与精确相等，再保留原 `allSatisfy`：
`#expect(!deferred.plan.isEmpty)`、`#expect(deferred.plan.count == volumes.count)`、`#expect(deferred.plan == volumes.map { RecoveryVolumePlan(identity: $0.identity, mountPoint: $0.mountPoint, action: .deferred) })`。同时把 `#expect(harness.mountCalls.count == volumes.count)` 换成独立事实断言 `#expect(harness.mountCalls == volumes.map(\.identity))`，并补 `cleanupCalls.isEmpty`、`executed.recovered == volumes.map(\.identity)`、`executed.state.cleanupLedger.isEmpty`。

## DEF-4 修复：动作与清理账本直接断言

新增 4 个用例（`RoundHarness` 增可注入 `now` 以确定时间戳断言）：

- `healthyAttachedVolumePlansAttachHealthyAndClearsStaleLedgers()`：断言 `action == .attachHealthy`，并断言成功挂载清除 `attemptCount`/`notificationCount`/`suppressionBoundary`/`repairEjectEvidence` 与 `cleanupLedger`（FR-002）。
- `reachableUnhealthyVolumeCleansThenRecoversAndRecordsLedger()`：断言 `action == .cleanupThenRecover`、清理用观测路径且恰好调用一次；**清理成功但挂载失败时断言 `cleanupLedger[identity] == now.timeIntervalSince1970`**（即 `RecoveryRound.swift` 原先无覆盖的清理账成功写入行）；另用清理失败对照组断言清理账不被伪造。
- `unreachableVolumePlansPendingUnreachableWithoutCleanup()`：断言 `action == .pendingUnreachable`、零清理零挂载、`attempts` 记 `.hostUnreachable`（在表不可达与缺失不可达两种输入）。
- `missingReachableVolumePlansRecoverWithoutCleanup()`：断言 `action == .recover` 且不触发清理。

## 变异复验（在 `/tmp/mut-r1` 仓库副本上执行，仓库源码零改动）

副本由 `cp -R Sources Tests Package.swift apps scripts automnt.swift /tmp/mut-r1/` 建立；每例先还原副本再施加单点变异，跑 `swift test --filter RecoveryRoundTests`：

| 变异 | 目标 | 结果 |
| --- | --- | --- |
| 基线（无变异） | — | `Test run with 12 tests in 1 suite passed` |
| DEF-1：`if signal == .unknownConservative` → `if false` | `RecoveryRound.swift:372-374` | **失败** `12 tests ... failed with 9 issues`（`corruptStateNeverFallsThroughToRemountOnceReadableAgain` 报 `mountCalls.isEmpty`、`state == .suppressed`、`suppressionBoundary == boundary` 等） |
| DEF-1：仅删除 `everHealthyMounted = true` 行 | 同上 | **失败**（9 issues） |
| DEF-3：`deferRound` 的 `plan` → `[]` | `RecoveryRound.swift` | **失败**（3 issues） |
| DEF-4：删除清理账写入 `cleanupLedger[...] = working.updatedAt` | `RecoveryRound.swift:295` | **失败**（1 issue） |
| DEF-4：`action = .attachHealthy` → `.recover` | 同上 | **失败**（1 issue） |
| DEF-4：删除 `attachHealthy` 的 `notificationCount = 0` | `RecoveryRound.swift:307` | **失败**（1 issue） |
| DEF-4：`action = .pendingUnreachable` → `.recover` | 同上 | **失败**（1 issue） |
| DEF-4：`cleanedFirst ? .cleanupThenRecover : .recover` → 恒 `.recover` | 同上 | **失败**（2 issues） |
| DEF-4：删除恢复成功后的 `cleanupLedger.removeValue` | 同上 | **失败**（1 issue） |

即 DEF-1/3/4 点名的每一处退化现在都能被包测试挡住。同时确认：**CLI `--self-test` 对这些变异仍然全绿**（未变异的 `/tmp/automnt-r1 --self-test` 为 `295 passed, 0 skipped, 0 failed`），这也印证验证者"该规则只能靠轮次层测试保护"的判断。

## 复验命令与数字

- `swift test --filter RecoveryRoundTests` → `Test run with 12 tests in 1 suite passed`（原 7 项）。
- `swift test` → `AutomntCoreTests 79 tests in 25 suites passed` + `AutomntPlatformTests 44 tests in 16 suites passed`（验证者基线为 Core 74、Platform 43）。
- `bash scripts/build.sh /tmp/automnt-r1` → exit 0，`--version` 3.4.0；`/tmp/automnt-r1 --self-test` → `Self-tests: 295 passed, 0 skipped, 0 failed`。
- `Entry.swift` 自测断言未改动（本次唯一 CLI 相关改动为零）；`RecoveryRound.swift` 判定语义未改动。
- 源码复原校验：`shasum -a 256 -c` 对 `Sources/AutomntCore/RecoveryRound.swift` 与 `Tests/AutomntCoreTests/RecoveryRoundTests.swift` 均 `OK`，变异只发生在 `/tmp/mut-r1`。

## R1 仍未覆盖（不得据此宣称已闭合）

- 仍无真机 SMB/磁盘仲裁实跑；`RecoveryRoundPlanner` 仍未接入 `BackgroundEvaluator`（helper 依旧走 `BaselineMountDecision` + `RecoveryCleanupCommit` 组件路径），因此 DEF-1 描述的 helper 端到端路径本身未在真实进程上复现，只锁定了共享协调器层的规则。
- 未做 UI/GUI 侧断言；DEF-2（畸形 `--deliver-notification`）不在本次写范围，未处理。

# 第二轮复验（V2）：R1（task-5）/ R2（task-6）修复的独立复验

本节由独立验证者 `verifier2`（共享任务 task-7）追加，只记录对 R1/R2 修复的独立复跑结果。上文（第一轮 V1 验证、R1 实现者小节）的原文、结论与原始输出一律未改动。本轮**未采信任何实现者数字**，全部命令在 macOS 27.2 上重跑；变异实验只在 `/tmp` 仓库副本上进行，工作区源码/测试/工程文件零改动（末尾附逐文件 sha256 复核）。

## 1. 环境与工作区一致性

| 项目 | 值 |
| --- | --- |
| 系统 / 架构 | macOS 27.2（26B5101f），arm64 |
| Xcode | 27.0（27A266a），SDK macosx27.0 |
| 源码版本 | `automnt.swift` 声明 `3.4.0` |
| 复验开始前证据文件 | `release/evidence/round-verification.md` 42832 B，sha256 `fded344e…f602` |

逐文件 sha256（工作区 vs 第一轮验证时的快照 `/tmp/mut`）：

| 文件 | V1 快照 sha256 | V2 当前 sha256 | 判定 |
| --- | --- | --- | --- |
| `Sources/AutomntCore/RecoveryRound.swift` | `e5c87803…5f22ce` | `e5c87803…5f22ce` | **零改动**（R1 声明成立） |
| `Sources/AutomntCLI/Entry.swift` | `ede0ca41…2cbd19` | `ede0ca41…2cbd19` | **零改动**（R1/R2 均未碰 CLI） |
| `Package.swift` | `4b894d00…7b079c` | `4b894d00…7b079c` | 零改动 |
| `Sources/AutomntPlatform/NotificationChannel.swift` | `afb0e7bb…a0edc4` | `b9b2c13d…0bedbe` | 本轮改动（R2） |
| `apps/Automnt/AutomntApp.swift` | `491d1772…6e21cf` | `18319c6b…f60f67d` | 本轮改动（R2） |
| `Tests/AutomntCoreTests/RecoveryRoundTests.swift` | `945433b2…a5d6d8` | `c3898f4c…fac3f3` | 本轮改动（R1，仅补测试） |
| `Tests/AutomntPlatformTests/NotificationChannelTests.swift` | `f0a7e6b0…88a5dc` | `f9ebccbb…227fbb` | 本轮改动（R2） |

`diff -rq /tmp/mut/Sources <工作区>/Sources` 的文件集合完全一致，只有上表两个平台文件内容不同；`Tests/` 同样只有两个测试文件不同。即：R1/R2 的改动范围与 task-5/task-6 声明的写范围严格吻合，没有越界改动。

## 2. 构建与测试数字（工作区重跑）

```
$ swift build
Build complete! (0.43秒)

$ swift test
  Test run with 44 tests in 16 suites passed after 0.849 seconds.   （AutomntPlatformTests）
  Test run with 79 tests in 25 suites passed after 0.250 seconds.   （AutomntCoreTests）
```

- 0 失败；0 skipped；无 `.disabled` / `withKnownIssue`。
- 静态计数交叉核对：`Tests/AutomntCoreTests/**` `@Test` 合计 **79**、`Tests/AutomntPlatformTests/**` 合计 **44**，与 runner 报告一致。
- 与第一轮基线对照：Core 74 → **79**（+5）、Platform 43 → **44**（+1）；`RecoveryRoundTests.swift` 单文件 7 → **12** 项（+5）。数字与实现者声明一致，且与 `git`/快照 diff 的增行数吻合。

```
$ rm -f /tmp/automnt-v2 && bash scripts/build.sh /tmp/automnt-v2 ; echo EXIT=$?
3.4.0 / 3.4.0 / 3.4.0
EXIT=0
$ /tmp/automnt-v2 --version         → 3.4.0（exit 0，1618184 B）
$ /tmp/automnt-v2 --self-test       → Self-tests: 295 passed, 0 skipped, 0 failed（exit 0，real 1.005s）
```

复核：`/tmp/automnt-v2 --self-test` 输出末行为 `295 passed, 0 skipped, 0 failed`，与实现者声明一致；产物为 3.4.0 的新源码构建（非仓库根 3.3.2 旧预编译产物）。`scripts/build.sh` 会运行 `generate-version.py`，我在调用前后对工作区全部 1475 个非 `.build`/`.git` 文件做了 sha256 快照比对，**无任何文件变化**（含 `Sources/AutomntCore/BuildVersion.swift`，调用前后均为 `1c0327f2…`）。

## 3. R1 独立重跑变异实验（本轮最关键）

沙箱：`cp -R Sources Tests Package.swift apps scripts automnt.swift /tmp/v2-mut/`（20 MB，不含 `.build`/`.git`）。每条变异前先把原始文件复制回副本、施加**单点**修改，再用 `swift test --filter RecoveryRoundTests` 运行；副本无变异基线为 `12 tests in 1 suite passed`。

### 3.1 DEF-1 点名的两种变异（逐字复现任务书要求）

| 编号 | 变异内容 | 实际 diff | 结果 |
| --- | --- | --- | --- |
| M1 | 整体删除 `RecoveryRound.swift:372-374` 的 `if signal == .unknownConservative { … }` 块 | `372,374d371`（3 行删除） | **失败**：`12 tests ... failed with 9 issues` |
| M2 | 仅删除 `RecoveryRound.swift:373` 的赋值行 `working.everHealthyMounted = true` | `1 行删除` | **失败**：`12 tests ... failed with 9 issues` |
| M3 | 赋值改为 `= false`（额外反向验证） | `1 行替换` | **失败**：`9 issues` |

M1/M2 的 9 条 issue 原文（节选，均为期望落空而非崩溃）：

```
Test unreadableStateSuppressesInsteadOfFirstUseMount() recorded an issue at RecoveryRoundTests.swift:131:9:
    Expectation failed: corrupt.state.volumes[volume.identity]?.everHealthyMounted == true
Test corruptStateNeverFallsThroughToRemountOnceReadableAgain() recorded an issue at RecoveryRoundTests.swift:171:9:
    Expectation failed: corrupt.state.volumes[volume.identity]?.everHealthyMounted == true
Test corruptStateNeverFallsThroughToRemountOnceReadableAgain() recorded an issue at RecoveryRoundTests.swift:181:9:
    Expectation failed: readable.plan == [RecoveryVolumePlan(identity: volume.identity, …
Test corruptStateNeverFallsThroughToRemountOnceReadableAgain() recorded an issue at RecoveryRoundTests.swift:183:9:
    Expectation failed: readable.plan.contains { $0.action == .recover } == false
2026-10-09 … Expectation failed: readable.recovered.isEmpty
2026-10-09 … Expectation failed: readable.suppressed == [volume.identity]
2026-10-09 … Expectation failed: harness.mountCalls.isEmpty
2026-10-09 … Expectation failed: readable.state.volumes[volume.identity]?.state == .suppressed
2026-10-09 … Expectation failed: readable.state.volumes[volume.identity]?.suppressionBoundary == boundary
```

判定：**DEF-1 已闭合**。跨轮用例 `corruptStateNeverFallsThroughToRemountOnceReadableAgain` 确实在变异后检测到真实退化——`readable.plan` 出现 `.recover`、`recovered` 非空、`mountCalls` 非空，正是 V1 描述的「损坏→可读后绕过会话抑制被重挂」路径。

附带的独立确认（本轮新增证据）：把 M1 变异复制到副本后跑 CLI `--self-test`，仍是 `295 passed, 0 skipped, 0 failed`（exit 0），而包测试失败 9 issues。这从两侧印证 V1 的判断——该规则**只能**由轮次层包测试保护，CLI 自测对它完全无感。

### 3.2 其余关键变异（至少 3 条，实际跑了 7 条）

| 编号 | 变异 | 目标行 | 结果 |
| --- | --- | --- | --- |
| M4 | `deferRound` 的 `plan: volumes.map{…}` → `plan: []`（DEF-3） | `RecoveryRound.swift:229` | **失败** 3 issues（`!deferred.plan.isEmpty`、`count == volumes.count`、精确数组比较同时命中） |
| M5 | 删除清理账成功写入 `cleanupLedger[identity] = working.updatedAt`（DEF-4） | `RecoveryRound.swift:295` | **失败** 1 issue（`RecoveryRoundTests.swift:558` 断言账本时间戳） |
| M6 | `action = .attachHealthy` → `.recover`（DEF-4） | `RecoveryRound.swift:311` | **失败** 1 issue（`:494` 计划断言） |
| M7 | `action = .pendingUnreachable` → `.recover`（DEF-4） | `RecoveryRound.swift:321` | **失败** 1 issue |
| M8 | `cleanedFirst ? .cleanupThenRecover : .recover` → 恒 `.recover`（DEF-4） | `RecoveryRound.swift:335` | **失败** 2 issues（`:532`、`:555`） |
| M9 | 删除 `.attachHealthy` 分支的 `notificationCount = 0`（DEF-4） | `RecoveryRound.swift:307` | **失败** 1 issue（`:506` 断言 `notificationCount == 0`） |
| M2/M3 | 见 3.1 | `:373` | 失败 9 issues |

即 DEF-1/3/4 点名的每一处退化在**本轮独立重跑**中都能被包测试挡住；V1 记录的 3 个覆盖盲区（DEF-4）现在全部有硬断言。所有变异均通过脚本内 `diff` 打印确认是预期的单点修改（例如 M5 的 diff 仅 `295d294`）。

## 4. R2 反例实测（新 xcodebuild 产物，真实进程）

构建：`xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt -configuration Release -derivedDataPath /tmp/v2-xcode CODE_SIGNING_ALLOWED=NO build` → `** BUILD SUCCEEDED **`（XCODE_EXIT=0）。被测文件：`/tmp/v2-xcode/Build/Products/Release/Automnt.app/Contents/MacOS/Automnt`，sha256 `9cce3150…0c30aaf5`。判定基准：≤10s 退出、无存活进程（用 `pgrep -f` 显式检查）。

### 4.1 畸形参数（任务书点名的 4 条 + 4 条补充）

| argv | exit | 耗时 | 存活 | stderr |
| --- | --- | --- | --- | --- |
| `--deliver-notification --count abc` | **6** | 0.341s | 无 | `delivery=failed reason=malformedArguments count=1` |
| `--deliver-notification --count 0` | **6** | 0.007s | 无 | 同上 |
| `--deliver-notification --count 99999999` | **6** | 0.006s | 无 | 同上 |
| `--deliver-notification --count`（缺值） | **6** | 0.006s | 无 | 同上 |
| `--deliver-notification --count -1` | **6** | 0.005s | 无 | 同上 |
| `--deliver-notification --count 3.5` | **6** | 0.005s | 无 | 同上 |
| `--deliver-notification --count 1e9` | **6** | 0.005s | 无 | 同上 |
| `--deliver-notification --count 1 --count 2` | **6** | 0.006s | 无 | 同上 |

补充边界（同样有界、无存活）：`--count " 5"`（含空格）→ exit=6；`--count +5` → exit=5（`Int("+5")` 合法，记数 5）；`--count 5 --sound --sound` → exit=5（`--sound` 幂等）；`--COUNT 5`（未知参数，被忽略）→ exit=5 且 `count=1`；`--count=5`（`=` 形式，被忽略）→ exit=5 且 `count=1`。后三者均属「含投递标志、参数可解析」的合法调用，未退回 GUI，符合设计。

### 4.2 回归项（修复未误伤正常路径）

| 命令 | 期望 | 实测 |
| --- | --- | --- |
| `MacOS/Automnt --deliver-notification --count 1` | 5（未签名环境） | exit=**5**，0.011s，`reason=permissionNotDetermined` |
| `MacOS/Automnt --deliver-notification --count 3 --sound` | 5 | exit=**5**，0.010s，`count=3` |
| `MacOS/Automnt --deliver-notification`（无 `--count`） | 5 | exit=**5**，0.010s，`count=1` |
| `Contents/Helpers/AutomntHelper --probe-notification-channel` | 非 134 | exit=**5**，0.198s，`probe: bundleID=missingIdentity / helper-direct-child=unavailable / notifier=unavailable` |
| `MacOS/Automnt`（**无任何参数**） | 进入 GUI 并常驻 | **6.0s 后仍存活（True）**，随后 `terminate()` 退出，残留进程 0 |

「无参数启动仍进 GUI」这一关键回归**已实测通过**：进程启动 6s 后仍存活（`alive_after_6s=True`），说明 `.notRequested` 分支未被 R2 改动误伤。测试后已清理该进程，`pgrep -fl "v2-xcode…"` 返回空，全机 `pgrep -fl "Automnt|automnt"` 亦为空。

### 4.3 R2 单元测试的敏感性（变异，在 /tmp 副本）

| 编号 | 变异 | 结果 |
| --- | --- | --- |
| R2M1 | 两处 `self = .malformedArguments` → `.notRequested`（退化回 DEF-2） | **失败** 7 issues（`:86` 循环断言逐条命中） |
| R2M2 | 删除 `arguments.contains("--deliver-notification")` 标志守卫（恒真） | **失败** 4 issues（`.notRequested` 四例全部落空） |
| R2M3 | 删除 `count` 上限夹限 `min(max(count,1), maximumCount)` | **失败** 1 issue（`:102` 断言上限==10000） |
| R2M4 | 删除 `--count` 重复检测（改为后者生效） | **失败** 1 issue（重复 `--count` 未判畸形） |

判定：R2 的解析层测试对「畸形退回非投递」「标志判据丢失」「上限失效」「重复参数宽松」四类退化都有约束力。

## 5. 反向检查：是否弱化既有断言

第一轮的仓库快照 `/tmp/mut` 在本机仍完整可用，因此本轮不必依赖「`@Test` 清单记忆」，而是**逐字节 diff V1 快照与当前文件**（这是比任务书要求的更强的证据）。

### 5.1 `Tests/AutomntCoreTests/RecoveryRoundTests.swift`（R1）

- `@Test` 7 → **12**；`#expect(` 71 → **143**。
- 新增 254 行，删除 4 行（含 1 行函数签名续行）。
- 删除的 3 处实质内容及其判定：

| 被删内容 | 位置 | 判定 |
| --- | --- | --- |
| `volumes: configuredRecoveryVolumes(from: configuration))` | 请求构造 | 被替换为 `volumes: … , now: { [self] in now })`，**新增可注入时钟**，属夹具加强 |
| `_ = RecoveryRoundPlanner.run(` | deferRound 用例 | 改为 `let executed = …` 以断言返回值，属加强 |
| `#expect(harness.mountCalls.count == volumes.count)` | deferRound 用例 | 被更强的 `#expect(harness.mountCalls == volumes.map(\.identity))` 取代，属加强 |

**没有任何一条既有断言被放宽或删除。**

### 5.2 `Tests/AutomntPlatformTests/NotificationChannelTests.swift`（R2）

- `@Test` 8 → **9**；`#expect(` 41 → **48**。
- 删除 16 行，全部属于**被替换的旧解析测试** `deliveryRequestParsesOnlyItsOwnInvocation`：该测试断言的是已删除的可失败构造器 `NotificationDeliveryRequest(arguments:)`（返回 `nil`）——正是 DEF-2 的成因 API。其覆盖面被新测试 `deliveryInvocationIsSeparatedFromArgumentValidity`（含 7 种畸形形式的循环断言）与 `canonicalChildArgumentsRoundTripThroughTheInvocationParser` 取代且扩大。旧测试的本意（非法参数**必须失败**）在新三态模型下体现为 `.malformedArguments`，仍被断言。
- 第 102 行原本的 `#expect(NotificationDeliveryRequest(count: 0…).count == 1)` 保留，并新增 `count:-5`、`count:999_999_999` 两条夹限断言。

### 5.3 CLI 自测断言（`Entry.swift`）

`grep -c 'check('` 为 **290**，与第一轮记录的 290 完全一致；`Entry.swift` sha256 与 V1 快照逐字节相同（见第 1 节）。即 R1/R2 **完全没有触碰 CLI 自测断言**，不存在「为通过自测而放宽」。`--self-test` 295/0/0 与第一轮记录一致。

### 5.4 R2 的既有通知语义未被弱化

`NotificationExitCode` 五码语义（0/3/4/5/6）在第 4.2 节回归中逐条实测未变；helper 探针仍为非 134 的 5；合法投递调用仍为 5 且计数正确（`count=3` 传入即报 `count=3`）。

## 6. 已实际验证 与 仍未验证

### 6.1 本轮已实际验证（均为本机真实命令）

- 工作区 1475 个文件的 sha256 在复验前后完全一致；`RecoveryRound.swift`、`Entry.swift`、`Package.swift` 与 V1 快照逐字节相同。
- `swift build` 成功；整包 `swift test` 0 失败（Core **79**/25、Platform **44**/16），与静态 `@Test` 计数一致。
- `scripts/build.sh /tmp/automnt-v2` exit 0；`--version` 3.4.0；`--self-test` **295 passed / 0 skipped / 0 failed**。
- `xcodebuild … CODE_SIGNING_ALLOWED=NO` `** BUILD SUCCEEDED **`。
- DEF-1 两种变异（删 if 块、删赋值行）在 `/tmp` 副本上**确实失败 9 issues**，失败项指向跨轮用例；另有 M3/M4/M5/M6/M7/M8/M9 共 7 条变异全部被捕获。
- R2 畸形参数 8 条实测全部 exit=6、≤0.341s、无存活；合法调用 exit=5；helper 探针 exit=5（非 134）；**无参数启动 6s 后仍常驻（GUI 正常）**，测后进程已清理。
- R2 解析层 4 条变异全部被单测捕获。
- 断言只增不减：两个测试文件逐字节 diff 确认无既有断言被放宽；`Entry.swift` 自测 `check(` 计数 290 未变。

### 6.2 仍未验证（本轮同样不具备条件，不得据此宣称通过）

- **真实签名与 entitlements**：本轮仍是 `CODE_SIGNING_ALLOWED=NO`，产物为 ad-hoc 链接器签名。真实 Developer ID / App Store 签名、沙盒 entitlements、Team ID 校验**未验证**。
- **真实通知投递**：全部实测落在 exit 5（`permissionNotDetermined`）。`delivered`(0)、`suppressedForeground`(3)、`denied`(4) 三条路径未在真机走通；授权后通知是否用户可见、`--sound` 是否实际发声、前台静默是否正确，**未验证**。
- **LaunchServices 路由**：app 已运行时请求被转交给既有实例的真实行为与退出码**未验证**（第 4.2 节的无参数常驻与投递调用是分别单进程测量的）。
- **真实 SMB**：无任何真实 SMB 主机/共享被挂载、卸载或探活；`NetFSMountURLSync`、死卷清理、`DiskArbitration`、Spotlight 防索引、worker 匿名管道与签名校验的实机路径**均未验证**。R1 的变异实验只证明**共享协调器层**的规则被锁住；`RecoveryRoundPlanner` 仍未接入 `BackgroundEvaluator`，DEF-1 描述的 helper 端到端路径未在真实进程上复现。
- **TCC / 目录授权 / Keychain**：launchd 身份下的授权、独立 helper 的持久权限、真实 Keychain 读写**未验证**。
- **launchd 真实生命周期**：两份 LaunchAgent 未 `bootstrap`/注册，WatchPaths 事件到达、退出 GUI 后自动恢复、helper 实际启动与退出**未验证**；`SMAppService` 注册/停用/批准流程**未在系统上执行**。
- **GUI**：本轮只验证了「无参数启动会常驻」，未做窗口渲染、键盘/VoiceOver/浅深色/较大文字/九语验收。
- 畸形参数的判定边界由单测 + 真实进程共同覆盖，但**未穷举**所有 argv 组合（见第 7 节 DEF-5）。

## 7. 本轮发现（无阻塞性缺陷）

### DEF-1 / DEF-3 / DEF-4 / DEF-2：**均已闭合**（独立重跑证实）

R1 与 R2 的修复在本轮独立复跑中全部成立：DEF-1 的两种变异均被 9 issues 挡住；DEF-3、DEF-4 的 7 条变异全部被捕获；DEF-2 的 8 条畸形参数实测全部有界失败且不再退回 GUI，且无参数启动未被误伤。

### DEF-5（提示，非阻塞）：`AutomntApp.swift` 的投递路由分支不在任何自动化测试范围内

- 类型：测试覆盖缺口（GUI app 目标不进 SwiftPM 测试范围，`Package.swift` 的测试目标只依赖 `AutomntCore`/`AutomntPlatform`）。
- 位置：`apps/Automnt/AutomntApp.swift:284-287`（`.malformedArguments` 分支的 `writeDiagnostic` + `exit(6)`）；对应地 `.notRequested`（`:282`）与 `.request`（`:288`）也未被自动化覆盖。
- 独立证据（本轮实测，在 `/tmp/v2-mut` 副本上，非工作区）：把 `:285-287` 替换为 `return`（即恢复成 DEF-2 的静默放行）后——
  - `swift test` 仍 **79/25 + 44/16 全绿**（10 个 issue 一个都不报）；
  - 只有重新 `xcodebuild` 该副本后，真实进程才复现出「6s 后仍存活」：`--count abc`、`--count 0`、`--count 99999999` 三条**全部变成存活进程**（需外部 kill）。
- 影响：R2 的**解析层**（`NotificationDeliveryInvocation`）有充分保护，但把它接到 `exit(6)` 的**这一行**属于未受保护的胶水代码。将来若有人把它改回 `return`，CI/单测不会报警，只有人工真机反例才能发现——正是 V1 当初发现 DEF-2 的方式。
- 最小复现（不修改工作区）：
  ```
  cd /tmp/v2-mut
  # 把 apps/Automnt/AutomntApp.swift 中 .malformedArguments 分支的 writeDiagnostic/exit 两行替换为 return
  swift test                       # 期望红灯，实际全绿（79+44 passed）
  xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt -configuration Release \
      -derivedDataPath /tmp/v2-mut-xcode CODE_SIGNING_ALLOWED=NO build
  /tmp/v2-mut-xcode/Build/Products/Release/Automnt.app/Contents/MacOS/Automnt \
      --deliver-notification --count abc    # 6s 后仍存活
  ```
- 建议（由实现者决定，本验证者不修改源码）：把「含投递标志就必须有界退出」这一路由判定抽成可注入的纯函数（输入 `CommandLine.arguments`，输出「是否启动 GUI / 用哪个退出码」），放进 `AutomntPlatform` 并在 `NotificationChannelTests` 中断言三态分支各自的去向；或在 `scripts/build.sh` 之后加一条真实的畸形参数反例到发布前自检脚本。

### DEF-6（提示，非阻塞）：畸形参数判定偏宽松，`--count` 的 `=` 形式与未知参数被静默忽略

- 位置：`Sources/AutomntPlatform/NotificationChannel.swift:118-146`（`default: break` 忽略所有无关参数）。
- 实测：`--deliver-notification --count=5` → 被当作 `count=1` 成功投递（exit=5），而非畸形；`--COUNT 5` 同理。
- 判定：**不构成安全或阻塞问题**。宽松是有意为之（注释说明 macOS 可能注入 `-psn_0_…`），且无论如何都不会退回 GUI 常驻；父进程只发规范参数，内部链路不受影响。仅提示「外部调用者写错参数形式时会被静默当作 count=1」，与内部投递无关。实现者已在 `release/evidence/notifications.md` 自述「未穷举所有可能的 argv 组合」，与实测一致。

## 8. 复现材料位置（本轮新增）

| 内容 | 路径 |
| --- | --- |
| R1/R2 变异沙箱副本（工作区源码未受影响） | `/tmp/v2-mut` |
| 变异脚本（DEF-1/3/4 与 R2 各一套） | `/tmp/v2-mutations.sh`、`/tmp/v2-mutations2.sh`、`/tmp/v2-r2-mutations.sh` |
| 变异日志（逐条原始输出） | `/tmp/v2-mutlogs/*.log` |
| 本轮新 xcodebuild 产物 | `/tmp/v2-xcode/Build/Products/Release/Automnt.app` |
| R2 真实进程反例脚本与输出 | `/tmp/v2-r2-runtime.py` |
| 新源码 CLI 构建 | `/tmp/automnt-v2`（`--self-test` 295/0/0） |
| DEF-1 变异下的 CLI 自测反证 | `/tmp/v2-mut-automnt`（295 passed，证明 CLI 自测对该规则无感） |
| DEF-5 变异产物（证明无自动化覆盖） | `/tmp/v2-mut-xcode/Build/Products/Release/Automnt.app` |
| 第一轮快照（反向检查基线） | `/tmp/mut` |

工作区在复验开始与结束时逐文件 sha256 完全一致（1475 个非 `.build`/`.git` 文件），本轮未修改任何源码、测试、`Package.swift` 或工程文件；`/tmp/v2-mut` 副本在每条变异后已还原并与工作区逐字节一致（RecoveryRound.swift 均为 `e5c87803…5f22ce`）。所有派生的 app/GUI 进程均已清理，`pgrep` 无残留。
