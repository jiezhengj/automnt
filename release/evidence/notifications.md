> 2026-10-11 本轮历史范围说明（仅 Feature005）：本轮仅修改文档与 demo；独立密码 CRUD、8 步向导、多选、用户 CLI 导入/检查、内部配置目录选择已撤销，现行要求以 [spec](../../specs/005-swiftui-mas-gui/spec.md) 与 [contracts](../../specs/005-swiftui-mas-gui/contracts/gui-and-release.md) 为准。系统认证在 sandbox/helper 中的复用未验证；已有 CLI 配置自动呈现与共享配置 owner 尚未实现。Automnt 暂用。以下历史正文与测试结果保留，旧资源、截图与测试不证明新版通过；CLI Feature001–004 的证据语义不变。

# B1 通知投递管线实测记录

本轮实现共享任务 task-2（B1 通知投递管线：进程角色守卫 + 应用内投递子进程）。所有命令均在 `/Users/jiezhengj/Documents/Project/automnt` 实际执行，下列退出码与耗时来自真实进程，不是推断。

## 问题结论（采信 Lead 实测）

`UNUserNotificationCenter.current()` 在 bundle 身份不可解析的进程里抛未捕获 `NSException`（`bundleProxyForCurrentProcess is nil`）并以 exit 134 终止。因此 `Contents/Helpers`、`Contents/Library/LoginItems` 下的 helper 不能直接投递通知，必须改成以 app 主可执行文件身份在子进程里投递。

## 改动

| 文件 | 改动 |
| --- | --- |
| `Sources/AutomntPlatform/NotificationChannel.swift`（新增） | `NotificationBundleIdentity`（用 `Bundle.main.bundleIdentifier` 与 Info.plist `CFBundleExecutable` 判定，nil 即不可投递且绝不触碰系统 API）；`NotificationExitCode`（0/3/4/5/6 双向映射）；`NotificationDeliveryRequest`（`--deliver-notification --count N [--sound]`）；`AppNotificationDelivery`（`Process` 启动 app 主可执行文件，stdin/stdout/stderr 全部丢弃、白名单环境、有界超时、超时先 SIGTERM 后 SIGKILL、以退出码为准）；`ApplicationForegroundQuery`；`AppNotificationDispatcher`（子进程侧实现，带结构化原因）；`NotificationDeliveryEntry`（app 侧同步有界入口 + 脱敏诊断行）；`NotificationDeliveryRecord/Store`（0600 原子结构化投递结果，非业务配置） |
| `Sources/AutomntPlatform/SystemUserNotifier.swift` | 删除 helper 内直接调用 `UNUserNotificationCenter` 的崩溃路径；改为注入式（前台查询 + 投递执行器），默认执行器为 `AppNotificationDelivery`；保留「前台为 Automnt → suppressedForeground」「查询不可用 → unavailable」「未授权与拒绝区分」「sound 需偏好且系统允许」。`NotificationCopy` 九语文案保持共享原样，未新增第二套 |
| `apps/Automnt/AutomntApp.swift` | `AutomntApp.init()` 处理 `--deliver-notification`：静默判定 → 授权状态（denied=4、非 authorized/provisional=5）→ `add` 成功=0 → 异常=6；不建窗口、不索权、不写配置，有界退出 |
| `apps/Automnt/Service/HelperEntry.swift` | 评估与观测提交之后接线：`BackgroundNotificationPreparation.prepare`（保留 EvaluationPermit 与预算语义）→ `NotificationPreferenceStore.readForDelivery`（读失败时 sound=nil 且不伪装成功）→ `SystemUserNotifier` → 只写 `notification-delivery.plist` 结构化结果，不写业务配置；prepare 返回 nil 或抛错即不投递。另加 `--probe-notification-channel` 有界诊断入口，消费 0 预算、不写配置 |
| `Tests/AutomntPlatformTests/NotificationChannelTests.swift`（新增） | 8 项：退出码双向映射与未知码→failed；参数解析；身份缺失/外来身份不可投递；无身份时 dispatch 返回 unavailable 且不触碰系统 API；前台/未知/后台三种注入执行器行为；真实 shell 子进程退出码映射；超时与启动失败→failed 不冒充 delivered；投递记录往返且不写 automnt.plist |

## 实际验证

| 验证 | 命令 | 结果 |
| --- | --- | --- |
| 平台目标构建 | `swift build --target AutomntPlatform` | Build complete，无 error |
| 全包构建 | `swift build` | Build complete! (3.81秒) |
| 全包测试 | `swift test` | 两次运行：43 tests / 16 suites 与 73 tests / 25 suites，全部通过，0 failed（合计 116 项） |
| 通知专项测试 | `swift test --filter Notification` | NotificationChannelTests 8 项 + NotificationCopyTests 1 项 + Core 通知相关 5 项，全部 passed |
| 原生 Release 无签名构建 | `xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt -configuration Release -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build` | `** BUILD SUCCEEDED **`（app + 嵌入 helper/worker） |

### 真实子进程实测（原始命令与退出码）

A）app 主可执行文件投递路径：

```
$ .build/xcode/Build/Products/Release/Automnt.app/Contents/MacOS/Automnt --deliver-notification --count 1
exit=5  elapsed=0.057s
stderr: automnt notification delivery=unavailable reason=permissionNotDetermined count=1
```

B）带声音参数、多计数：

```
$ .build/xcode/Build/Products/Release/Automnt.app/Contents/MacOS/Automnt --deliver-notification --count 3 --sound
exit=5  elapsed=0.017s
stderr: automnt notification delivery=unavailable reason=permissionNotDetermined count=3
```

退出码 5 属验收允许集合 {0,3,4,5,6}；未签名、未授权环境下即预期值。进程均在 ≤10s（实测约 0.02–0.06s）内退出，无崩溃、无 exit 134。重复运行 3 次（count 2 且带 --sound）稳定得到 exit=5，耗时 0.015–0.019s。

C）`Contents/Helpers/AutomntHelper` 走通知适配（原崩溃路径）：

```
$ .build/xcode/Build/Products/Release/Automnt.app/Contents/Helpers/AutomntHelper --probe-notification-channel
exit=5  elapsed=0.232s
stderr:
probe: bundleID=missingIdentity
probe: helper-direct-child=unavailable
probe: notifier=unavailable
```

确认为 `missingIdentity`（正是会 exit 134 的场景），现在以 exit 5（unavailable）有界返回，不再崩溃；且未直接调用系统通知 API。

D）同一 helper 传入 app 侧投递参数（应被 helper 拒绝，不得崩溃）：

```
$ .build/xcode/Build/Products/Release/Automnt.app/Contents/Helpers/AutomntHelper --deliver-notification --count 1
exit=1  elapsed=0.012s
```

helper 只接受单个诊断参数，其余参数一律 `EXIT_FAILURE`，因此不存在 helper 借道投递或崩溃的路径。

父进程侧语义（`AppNotificationDelivery`）用真实 shell 子进程验证：脚本 `exit 0/3/4/5/42` 分别映射为 `delivered/suppressedForeground/denied/unavailable/failed`；`sleep 30` 在 300ms 超时后被先 SIGTERM 后 SIGKILL，结果为 `failed` 且整体耗时 <5s；无可执行文件与声明可执行文件缺失均为 `failed`，任何情况都不会返回 delivered。

## 复测（冻结产物）

在 `swift build`、`swift test` 与 xcodebuild Release 全绿后，对同一冻结产物再跑一轮，结果与上表一致：app 路径 exit=5（`reason=permissionNotDetermined`，0.015–0.045s）；helper 探测 exit=5（`missingIdentity` → `unavailable`，0.215s）；helper 传投递参数 exit=1（0.009s）；`--count 5` 连跑三次均 exit=5。

期间一次 `swift build` 曾因队友正在写入 `Sources/AutomntCLI/Entry.swift`（`updatePolicy` 参数未改完）而失败；该文件不在本轮改动范围内，队友完成写入后整包 `swift build` 立即通过。本轮未修改 `Sources/AutomntCLI/Entry.swift`、`Sources/AutomntCore/`、`Package.swift` 或 `apps/Automnt/Automnt.xcodeproj/project.pbxproj`。

## 仍未验证的边界

- 真实投递链路只有在本机完成通知授权并签名后才会走到 `add` 成功（exit 0）；本轮无签名环境实测为 exit 5，`delivered` 路径**未在真机投递并验证用户可见性**（`delivered` 只表示通知中心接受，本就不等于用户看见）。
- 前台静默的退出码 3、拒绝的退出码 4 只经注入执行器与真实子进程脚本映射验证；真实系统前台切换与拒绝状态下的端到端投递**未验证**。
- LaunchServices 把请求转交给已在运行的 app 实例时的实际路由与退出码**未验证**（父进程已按「以子进程退出码为准」实现，不会返回虚假 delivered，但真实转交行为未实测）。
- helper 经 launchd 身份运行时的目录授权（`PermissionStore.resolve`）与投递记录落盘**未验证**；`--probe-notification-channel` 是显式诊断入口，不是 launchd 路径。
- `Contents/Library/LoginItems` 下的身份缺失同样被 `NotificationBundleIdentity` 覆盖，但本轮只实测了 `Contents/Helpers` 路径。
- 九语通知文案沿用既有 `NotificationCopy`，其母语审校与系统通知展示**未在本轮验证**。

# 第 2 轮：DEF-2 修复（畸形投递参数必须有界失败退出）

## 缺陷与成因

独立验证者（task-4）在 `release/evidence/round-verification.md` 记录 DEF-2：`Contents/MacOS/Automnt --deliver-notification --count abc|0|99999999` 不进入投递路径，而是正常启动 SwiftUI GUI 并常驻，6s 后仍存活，违反该入口「有界、无窗口」的设计意图。

成因是「是否投递调用」与「参数是否合法」被合并成一个可失败解析：`NotificationDeliveryRequest.init?(arguments:)` 在 `--count` 非法时 `return nil`，`AutomntApp.init()` 的 `guard let ... else { return }` 于是静默放行到 GUI 场景。

修复前用当时 `.build/xcode` 产物自行复现，确认三条全部存活：

```
--count abc      -> still alive after 6s: yes
--count 0        -> still alive after 6s: yes
--count 99999999 -> still alive after 6s: yes
```

## 修复

- `Sources/AutomntPlatform/NotificationChannel.swift`：新增 `NotificationDeliveryInvocation`，把两个问题分开回答——`.notRequested`（命令行不含 `--deliver-notification`，即普通启动）、`.request(...)`（含标志且参数可用）、`.malformedArguments`（含标志但参数不可用，**仍是投递调用**）。原可失败构造器删除；`NotificationDeliveryRequest` 改为只用 `count:soundEnabled:` 构造并夹限到 `[1, 10000]`。`--count` 缺失值、非整数、≤0、超上限、重复出现均判为 `malformedArguments`；无关参数（如 macOS 注入的 `-psn_0_...`）忽略，不使合法调用失效。新增 `NotificationDispatchReason.malformedArguments` 与 `NotificationDeliveryInvocation.malformedOutcome`（`failed` + 失败码 6）。
- `apps/Automnt/AutomntApp.swift`：`init()` 改为对三分支 `switch`，只有 `.notRequested` 才继续启动 GUI；`.malformedArguments` 打印脱敏诊断行后 `exit(6)`；`.request` 行为不变。
- `Tests/AutomntPlatformTests/NotificationChannelTests.swift`：原解析测试替换为两项——`deliveryInvocationIsSeparatedFromArgumentValidity`（覆盖 `abc`/`0`/`-1`/`99999999`/缺值/`3.5`/重复 `--count`，以及「无标志→notRequested」「注入参数不破坏合法调用」）与 `canonicalChildArgumentsRoundTripThroughTheInvocationParser`（父进程生成的规范参数能原样解析回同一 request，保证内部链路未变）。

退出码语义未变：0=delivered、3=suppressedForeground、4=denied、5=unavailable、6=failed；畸形参数复用 6，未新增码位。

## 第 2 轮实际验证

| 验证 | 命令 | 结果 |
| --- | --- | --- |
| 通知专项测试 | `swift test --filter Notification` | 10 tests / 2 suites 与 5 tests / 3 suites 全部 passed |
| 整包构建 | `swift build` | Build complete |
| 整包测试 | `swift test` | 44 tests / 16 suites 与 79 tests / 25 suites 全部 passed，0 failed（合计 123 项） |
| 原生 Release 无签名构建 | `xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt -configuration Release -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build` | `** BUILD SUCCEEDED **` |

### 修复后畸形参数实测（新构建产物，逐条 ≤10s 有界退出）

```
--count abc        -> exit=6  elapsed=0.121s  stderr: automnt notification delivery=failed reason=malformedArguments count=1
--count 0          -> exit=6  elapsed=0.124s  stderr: automnt notification delivery=failed reason=malformedArguments count=1
--count 99999999   -> exit=6  elapsed=0.125s  stderr: automnt notification delivery=failed reason=malformedArguments count=1
--count (missing)  -> exit=6  elapsed=0.127s  stderr: automnt notification delivery=failed reason=malformedArguments count=1
```

补充畸形形式同样有界失败：`--count -1`、`--count 3.5`、`--count 1e9`、`--count 1 --count 2` 均 exit=6（0.008–0.015s）。四条与补充项全部远低于 10s 预算，无 6s 后存活，诊断行只含结果、原因与计数，不含任何用户数据。

### 回归确认

```
--deliver-notification --count 1         -> exit=5  elapsed=0.021s  reason=permissionNotDetermined
--deliver-notification --count 3 --sound -> exit=5  elapsed=0.014s  reason=permissionNotDetermined
Contents/Helpers/AutomntHelper --probe-notification-channel -> exit=5  elapsed=0.243s
    probe: bundleID=missingIdentity / helper-direct-child=unavailable / notifier=unavailable
无任何参数直接启动 app -> 4s 后仍常驻（GUI 正常启动，预期行为）
```

合法调用仍为 exit=5（未签名环境预期值，属 {0,3,4,5,6}），helper 探测仍为非 134 的 exit=5，普通启动仍进入 GUI，均未被本次修复改变。

## 第 2 轮仍未验证的边界

- 第 1 轮列出的边界在本轮同样成立（真实签名/授权下的 exit 0 与用户可见性、exit 3/4 端到端、LaunchServices 转交路由、helper 经 launchd 身份的目录授权、`Contents/Library/LoginItems` 路径、九语母语审校）。
- 畸形参数的判定边界由单元测试与真实进程共同覆盖，但**未穷举**所有可能的 argv 组合；`--sound` 重复出现目前被接受（幂等），未判为畸形。

# 第 3 轮：DEF-5/DEF-6 修复

## DEF-5：投递路由决策移入可测平台层

**问题**（task-7 复验记录）：`AutomntApp.swift` 中把 `.malformedArguments` 接到 `exit(6)` 的分支不在任何自动化测试范围内（GUI target 不进 SwiftPM 测试目标）。验证者实测把该分支改成 `return` 后 `swift test` 仍全绿，只有重新 xcodebuild 才复现「6s 后存活」——与 V1 发现 DEF-2 的模式相同：解析层有保护，但「必须据此退出、绝不落入 GUI」这一**决定**没有。

**修复**：在 `Sources/AutomntPlatform/NotificationChannel.swift` 新增 `NotificationLaunchDisposition`（`.startGUI` / `.exitWithOutcome(_:count:)`）与 `NotificationDeliveryEntry.disposition(for:execute:)`，把路由判定做成纯函数并可注入执行器（测试中不投真实通知）。`apps/Automnt/AutomntApp.swift` 的 `init()` 现在只做「取决定 → 执行」，不再内联 `switch`/`exit`，并加注释禁止再次内联该策略。

保证的不变式：**任何包含 `--deliver-notification` 的命令行都不会得到 `.startGUI`**。

## DEF-6：`--count=<value>` 等号形式

**问题**：`default: break` 使 `--count=5` 被当作无关参数忽略，最终按 count=1 成功投递。

**修复**：在解析器中显式识别 `--count=<value>`（合法则取该值，非法则 `.malformedArguments`），空格分隔形式不变；两种拼写混用（`--count 2 --count=3` 或反之）判为畸形。`-psn_0_...` 等无关参数容忍保持不变，无参数启动仍进入 GUI。

## 第 3 轮实际验证

| 验证 | 命令 | 结果 |
| --- | --- | --- |
| 通知专项测试 | `swift test --filter Notification` | 12 tests / 2 suites 与 5 tests / 3 suites 全部 passed |
| 整包构建 | `swift build` | Build complete |
| 整包测试 | `swift test` | 46 tests / 16 suites 与 85 tests / 26 suites 全部 passed，0 failed（合计 131 项）。注：Core 套件计数在本轮期间由队友并发新增用例从 84 变为 85；Platform 套件（含本任务的 12 项通知测试）为 46 项，未受他人改动影响 |
| 原生 Release 无签名构建 | `xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt -configuration Release -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build` | `** BUILD SUCCEEDED **` |

### 真实产物回归（新构建产物，逐条记录）

```
--deliver-notification --count abc        -> exit=6  0.126s  reason=malformedArguments count=1
--deliver-notification --count 0          -> exit=6  0.125s  reason=malformedArguments count=1
--deliver-notification --count 99999999   -> exit=6  0.126s  reason=malformedArguments count=1
--deliver-notification --count            -> exit=6  0.127s  reason=malformedArguments count=1
--deliver-notification --count=5          -> exit=5  0.125s  reason=permissionNotDetermined count=5   ← DEF-6 修复点
--deliver-notification --count=abc        -> exit=6  0.126s  reason=malformedArguments count=1
--deliver-notification --count=0          -> exit=6  0.126s  reason=malformedArguments count=1
--deliver-notification --count=           -> exit=6  0.126s  reason=malformedArguments count=1
--deliver-notification --count 1          -> exit=5  0.021s  reason=permissionNotDetermined count=1
--deliver-notification --count 3 --sound  -> exit=5  0.014s  reason=permissionNotDetermined count=3
Contents/Helpers/AutomntHelper --probe-notification-channel -> exit=5  0.237s（非 134）
```

修复前 `--count=5` 会按 count=1 投递；现在正确取 5（诊断行 `count=5`）。全部畸形形式 ≤10s 有界失败，无 6s 存活。

**GUI 容忍回归**：`app -psn_0_12345`（模拟 macOS 注入参数）4s 后仍常驻；无任何参数启动 4s 后仍常驻——两者均正常进入 GUI，未被本轮修改误伤。实测结束后 `pgrep` 确认残留 Automnt GUI 进程为 0。

## 变异自证（/tmp 副本，工作区源码零改动）

在 `/tmp/r3-mut`（`rsync` 副本，排除 `.build`/`.git`）上做两次独立变异，证明新测试层真的挡得住 DEF-5、DEF-6 的回归：

| 变异 | 位置 | `swift test --filter Notification` 结果 |
| --- | --- | --- |
| M1：把 `.malformedArguments` 的 disposition 返回值改成 `.startGUI`（即恢复 DEF-5 的静默放行） | `NotificationChannel.swift` disposition | **红灯**：`deliveryCommandLinesNeverDisposeToStartGUI` 10+ issues、`realDispositionKeepsBoundedFailureForMalformedArguments` 1 issue，`swift test` exit=1 |
| M2：删除 `--count=<value>` 识别分支（即恢复 DEF-6） | `NotificationChannel.swift` 解析器 | **红灯**：两个测试共 18 issues（`--count=abc/0/-1/99999999/空/3.5 must be malformed`），`swift test` exit=1 |

M1 还额外做了真实进程闭环：用变异副本 `xcodebuild` 出产物后，`--count abc|0|99999999` 三条**全部 6s 后仍存活**（DEF-2 的原始症状重现）。也就是说，同一处退化现在**同时**触发单测红灯与真实症状——二者终于被同一断言层锁住，不再依赖人工真机反例。

每次变异后副本已还原，并与工作区逐文件 sha256 逐一比对一致（`NotificationChannel.swift`、`AutomntApp.swift`、`NotificationChannelTests.swift` 三项 OK）；基线副本重跑 `Test run with 12 tests / 5 tests passed`。`/tmp/r3-mut`、`/tmp/r3-mut-xcode` 及临时备份均已删除，工作区未被变异触及。

## 第 3 轮仍未验证的边界

- 第 1、2 轮列出的边界在本轮同样成立（真实签名/授权下的 exit 0 与用户可见性、exit 3/4 端到端、LaunchServices 转交路由、helper 经 launchd 身份的目录授权、`Contents/Library/LoginItems` 路径、九语母语审校）。
- argv 组合仍未穷举；`--sound` 重复出现按幂等接受、`--COUNT`（大小写不符）仍按无关参数忽略，均未判畸形——这是有意的宽松，且不会退回 GUI 常驻。
- 本轮只做单元/变异层面的决策锁定；GUI target 仍不进 SwiftPM 测试目标，因此「`init()` 只搬运决定、不重新内联策略」目前靠代码注释与 disposition 单测共同约束，**没有编译期强制**。



## 第 4 轮：GUI 通知横幅文案（task-12 / F1–F3 修复）

独立复验 V4（[localization-verification.md](localization-verification.md)）发现：GUI 通知横幅的整套九语文案由 `Sources/AutomntPlatform/SystemUserNotifier.swift:35` 的 `NotificationCopy` 手写分支产生，**不在 catalog、也不在 `scripts/verify-localization.py` 的扫描范围内**，因此从未被任何门保护。本轮按渠道契约修复三处。

### 渠道区分（本轮最容易改错的地方）

`specs/005-swiftui-mas-gui/contracts/core-and-channels.md:21`：「共同 CLI 基础文案使用 automnt，GUI 显示 Automnt」。据此：

| 渠道 | 文件 | 品牌 | 本轮处理 |
| --- | --- | --- | --- |
| CLI | `Sources/AutomntCore/FailureNotification.swift:14,17` | 小写 `automnt` | **不改**（符合契约）。sha256 `2897bdc6…` 未变 |
| GUI | `Sources/AutomntPlatform/SystemUserNotifier.swift:35` `NotificationCopy` | **`Automnt`** | 九语 title 与正文全部改大写 |

调用链确认 GUI 渠道走的就是 `NotificationCopy`：`apps/Automnt/Service/HelperEntry.swift:38` `deliverFailureNotification` → `SystemUserNotifier.deliver` → 应用内子进程 → `NotificationChannel.swift:340-343` 写入 `content.title`/`content.body`。GUI 侧无 `osascript`（`grep -rn osascript apps/ Sources/AutomntPlatform/` 为空），与契约「GUI/helper 采用 UserNotifications 原生渠道」一致。

### 三处修复

| 缺陷 | 修复前 | 修复后 |
| --- | --- | --- |
| F1 品牌 | `automnt：自动恢复未完成`（九语 title 全部小写） | `Automnt：自动恢复未完成` 等九语 |
| F2 es 术语 | `Restauración automática incompleta` / `restaurar automáticamente` | `Recuperación automática incompleta` / `montar automáticamente`（与 catalog 基线一致；pt-BR/fr/de 已核对与 catalog 同术语） |
| F3 不实引导 | 九语正文均要求「打开 automnt 配置并选择『立即重新挂载 / Remount now』」 | 改为「N 个共享文件夹未能自动挂载。打开 Automnt 查看详情。」——只承诺 GUI 真有的动作 |

F3 是**用户可见错误**：`grep -rn "Remount" apps/Automnt` 为空，该动作只在 `Sources/AutomntCLI/Entry.swift` 存在，用户按通知指引找不到入口。本轮只修改文案，**不实现 GUI 内重试按钮**（T032/T033）。

### 实测（独立探针，非测试内断言）

把源码里的 `NotificationCopy` enum 直接抽取为独立 `swiftc` 探针编译运行，实测九语输出：

```text
[en]      title=Automnt: Automatic recovery incomplete
          msg  =3 shared folders could not be mounted automatically. Open Automnt to review.
[zh-Hans] title=Automnt：自动恢复未完成
          msg  =3 个共享文件夹未能自动挂载。请打开 Automnt 查看详情。
[zh-Hant] title=Automnt：自動復原未完成
          msg  =3 個共享檔案夾未能自動掛載。請打開 Automnt 查看詳細資訊。
[ja]      title=Automnt：自動復旧が完了していません
          msg  =3 個の共有フォルダを自動でマウントできませんでした。Automnt を開いて詳細を確認してください。
[ko]      title=Automnt: 자동 복구 미완료
          msg  =공유 폴더 3개를 자동으로 마운트하지 못했습니다. Automnt를 열어 자세히 확인하세요.
[de]      title=Automnt: Automatische Wiederherstellung unvollständig
          msg  =3 freigegebene Ordner konnten nicht automatisch verbunden werden. Öffne Automnt, um die Details zu prüfen.
[fr]      title=Automnt : Rétablissement automatique incomplet
          msg  =3 dossiers partagés n’ont pas pu être montés automatiquement. Ouvrez Automnt pour consulter les détails.
[es]      title=Automnt: Recuperación automática incompleta
          msg  =No se han podido montar automáticamente 3 carpetas compartidas. Abre Automnt para consultar los detalles.
[pt-BR]   title=Automnt: Recuperação automática incompleta
          msg  =Não foi possível montar automaticamente 3 pastas compartilhadas. Abra o Automnt para ver os detalhes.
```

机器扫描探针输出：

```text
remount / 重新挂载 / 再マウント / 다시 마운트 / erneut verbinden / reconnecter / reconectar / volver a conectar : NONE FOUND
小写品牌 automnt : NONE FOUND
es restauraci|restaurar : NONE FOUND
大写品牌 Automnt 出现次数 : 18   (9 语 × title+message)
```

回归：`swift test` 50 tests/16 suites（Platform，`NotificationCopyTests` 1 → 5 项）+ 86 tests/26 suites（Core）全绿；`scripts/build.sh /tmp/automnt-l10n2` → 3.4.0、`--self-test` 295 passed 0 failed；`xcodebuild Release` → `** BUILD SUCCEEDED **`。

新构建产物中同时可解析到 GUI 新文案（`shared folders could not be mounted automatically. Open Automnt to review.`）与 CLI 旧文案（`Open automnt configuration and choose "Remount now".`）。后者来自 CLI 渠道的 `FailureNotification`，被链接进同一 app 可执行文件属正常，**不违反渠道契约**——判断渠道文案不能只靠 `strings` 扫二进制。

### 防回归门已覆盖此路径

`scripts/verify-localization.py` 新增第 4 类检查：静态解析 `NotificationCopy` 的九语分支，断言 title/message 非空、title 互不相同、九语选择分支齐全、品牌为 `Automnt` 且不含小写 `automnt`、不含私有目标、不含 GUI 不提供的动作、es 不得出现 `Restauración/restaurar`。变异实证（`/tmp/l10n2/repo` 副本）：小写品牌回填、`Remount now` 回填、`Restauración` 回填、删除 ko 分支，四种退化**全部 exit 1**。详见 [localization.md](localization.md) 的「第二轮：V4 缺陷修复」。

### 第 4 轮仍未验证的边界

- **未在真实通知中心观察到横幅**：只验证 `NotificationCopy` 取值与调用路径，未在授权环境实测弹出、点击行为与前台去重。
- **未验证真实系统 locale 的语言解析**：`Locale.preferredLanguages.first` 对 `zh-TW`/`zh-HK`/`pt-PT` 的映射依赖系统，测试只注入语言字符串。
- **F3 只保证文案不谎称**：GUI 内仍无重试入口；用户打开 Automnt 后能否处理，取决于 T032/T033。
- **通知文案仍为未获母语审校的草稿**：es/de/fr/pt-BR 选词按基线表取值，未获母语确认。
- 本轮未改退出码、投递管线、偏好读取与预算语义；第 1–3 轮的通知投递边界全部继续成立。

## 第 5 轮：GUI 通知复数与 locale 数字格式（task-22 / T030b）

承接 Lead 的实测缺陷：`NotificationCopy.text(count:language:)` 用手写 `number == 1` 分支与裸插值 `\(number)`，导致 ① 数字不按用户 locale 分组；② fr/es/pt-BR 的 CLDR `many`（百万倍数）分支缺失。设计契约 `design/localization.md`「数量、变量与复数资源」要求「类别由系统 locale 规则选择，不在业务代码中自行判断」。

### 先回答「当前结构能否表达 plural」——能，且不需要改 Package.swift

Lead 特别要求：若判定结构无法表达 plural，须上报方案而不是近似。因此先用独立探针把可行性问清楚，结论与依据如下（全部实测，非推断）：

| 候选方案 | 实测结果 | 结论 |
| --- | --- | --- |
| `Locale` 暴露 CLDR plural 类别 API | macOS 27 SDK 中**不存在**：Foundation swiftinterface 无 `PluralCategory`/`pluralCategory`/`pluralRule`，`Locale` 无 plural 成员；公开头文件无 `NSPlural*`；SDK 不含公开 `unicode/plurrule.h` | 不可用 |
| `Morphology` + `InflectionRule.explicit` | 有 `Morphology.number`，但它只影响**词形变化**，不返回类别，也不选句子变体 | 不可用 |
| `String(localized:)` 的 `^[…](inflect: true)` 自动语法一致 | 在**没有 catalog** 时**原样输出**（`^[1 000 000 dossier partagé](inflect: true)`），不解析 | 需 catalog |
| **String Catalog plural variations（`Localizable.xcstrings`）** | **可行**：`String(localized:)` 经 catalog 时由系统按 CLDR 规则选 `one`/`many`/`other`，并做 locale 数字替换 | **采用** |

关键实测（SwiftPM 探针，`fr 1000000`）：

```text
未加 catalog 时：(inflect:) 原样返回，不解析
加上 plural variations 后：
  fr 1000000 -> 1 000 000 de dossiers partagés n'ont pas pu être montés…   ← many 分支 + U+202F 分组
  fr 2       -> 2 dossiers partagés n'ont pas pu être montés…               ← other 分支（无 "de"）
  fr 0/1     -> Un dossier partagé n'a pas pu être monté…                    ← one 分支（fr 的 0 属 one）
```

**架构影响评估（Lead 点名的风险点）**：新增 `Sources/AutomntPlatform/Resources/Localizable.xcstrings` 会产生 SwiftPM 资源 bundle `Automnt_AutomntPlatform.bundle`。实测确认：

- **`Package.swift` 无需改动**：SwiftPM 会自动发现未声明的 `Sources/<Target>/Resources/` 并将其处理为资源（实测 `swift build --target AutomntPlatform` 通过，且 `Bundle.module` 可用）。任务写范围不含 `Package.swift`，因此这一点是本方案能落地的前提。
- **Xcode 会自动把该 bundle 嵌入 app**：`xcodebuild Release` 后产物含 `Automnt.app/Contents/Resources/Automnt_AutomntPlatform.bundle`，内含九个 `.lproj/Localizable.stringsdict`（plural 编译产物）。**子进程投递路径不受影响**——通知子进程就是 app 主可执行文件，`Bundle.main.resourceURL` 即 app 的 `Contents/Resources`。
- **不用 `Bundle.module`**：SwiftPM 生成的 `Bundle.module` 是 `static let`，找不到 bundle 时调 `fatalError`（已在生成的 `resource_bundle_accessor.swift` 中读到）。那会把打包失误变成不可恢复崩溃，正是本渠道一直在避免的崩溃类别（exit 134 同类）。改为自写 `NotificationCatalog.bundle()`：按同样候选路径查找，找不到返回 `nil`，绝不 `fatalError`。

### 实现

新增 `Sources/AutomntPlatform/Resources/Localizable.xcstrings`（2 键 × 9 语）：

- `Automnt: Automatic recovery incomplete`（title，无复数变化）
- `%lld shared folders could not be mounted automatically. Open Automnt to review.`（message，**plural variations**）

各语言提供的类别严格按其 CLDR 基数规则，不提供不存在的类别：

| 语言 | 提供的类别 |
| --- | --- |
| en、de | `one`、`other` |
| fr、es、pt-BR | `one`、`many`、`other` |
| zh-Hans、zh-Hant、ja、ko | `other` |

`SystemUserNotifier.swift` 改动：

1. `NotificationCatalog`：安全解析资源 bundle（`nil` 而非 `fatalError`）；显式按语言加载 `.lproj`（SwiftPM 生成的 bundle 没有 `defaultLocalization`，只传 `locale:` 会让 fr/es/pt-BR 静默回落英文——已实测）；查不到键时对非英文表返回 `nil`，绝不把英文显示在本地化应用里。
2. `NotificationCopy.text`：**优先走 catalog**（系统选类别 + locale 数字），catalog 不可用时回落到既有九语手写字面量（保底，只表达 `one`/`other`）。
3. `NotificationCopy.localizedCount`：用 `formatted(.number.grouping(.automatic).locale(_:))` 做 locale 分组，供回落路径使用。

### 独立探针实测（36 格，在**真实构建出的 app bundle 内**运行）

裸命令行二进制找不到 SwiftPM bundle（会走回落路径），因此把探针可执行文件放进真实产物 `Automnt.app/Contents/MacOS/` 后运行，`Bundle.main` 即该 app——与通知子进程的实际上下文一致：

```text
$ .build/xcode-plural/Build/Products/Release/Automnt.app/Contents/MacOS/AutomntPluralProbe
```

九语 × count ∈ {0,1,2,1000000} 全部 36 格原始输出（节选关键格）：

```text
en     1000000 | 1,000,000 shared folders could not be mounted automatically. Open Automnt to review.
de     1000000 | 1.000.000 freigegebene Ordner konnten nicht automatisch verbunden werden. …
fr     1000000 | 1 000 000 de dossiers partagés n’ont pas pu être montés automatiquement. …   ← many + U+202F
es     1000000 | No se han podido montar automáticamente 1.000.000 de carpetas compartidas. … ← many
pt-BR  1000000 | Não foi possível montar automaticamente 1.000.000 de pastas compartilhadas. … ← many
fr     2       | 2 dossiers partagés n’ont pas pu être montés automatiquement. …                ← other（无 de）
es     2       | No se han podido montar automáticamente 2 carpetas compartidas. …               ← other（无 de）
ja     1000000 | 1,000,000 個の共有フォルダを自動でマウントできませんでした。…
zh-Hans 1000000| 1,000,000 个共享文件夹未能自动挂载。请打开 Automnt 查看详情。
```

Lead 点名的三项逐一确认已修复：

| Lead 实测（修复前） | 本轮实测（修复后） |
| --- | --- |
| `fr 1000000 => 1000000 dossiers partagés` | `1 000 000 de dossiers partagés`（U+202F 分组 + many 的 `de`） |
| `es 1000000 => 1000000 carpetas compartidas` | `1.000.000 de carpetas compartidas`（many） |
| `pt-BR 1000000 => 1000000 pastas compartilhadas` | `1.000.000 de pastas compartilhadas`（many） |

分组字符用 unicode scalar 核对过：fr 用 **U+202F**（narrow no-break space），不是普通空格；de/es/pt-BR 用 `.`；en/ja/ko/zh 用 `,`。

### 测试

`NotificationCopyTests` 5 → 10 项，既有 5 项全部保留通过（硬约束未放宽）：

- 新增 `numeralUsesLocaleGroupingRules`：逐语断言 `1,000,000` / `1.000.000` / `1 000 000`（fr 精确到 U+202F），并断言**不出现**裸 `1000000`。
- 新增 `fallbackNumeralFormattingIsLocaleAware`：直接测 `localizedCount`。**这一项是变异实验逼出来的**（见 M4）：上面那条走 catalog 的断言由 catalog 的 `%lld` 替换完成分组，完全测不到回落路径的格式化函数。
- 新增 `millionUsesTheManyCategoryWording`：fr/es/pt-BR 在 1,000,000 必须含 many 措辞，且在 2/3/1,000/999,999 必须**不含**——这才证明类别是规则选的而不是恒取 many。
- 新增 `oneCategoryKeepsSingularAndZeroClampsToOne`：count=1 单数正确；count=0 断言「与 count=1 文案相同且不出现 0」。**原写法一度误判**：我起初断言 0 应走各语言的 zero 类别，实测发现 `text(count:)` 有意把 0 夹到 1（N=0 从不投递，契约「N = 0 不生成失败通知」），于是改为断言这一真实契约，而不是删掉断言。
- **修改了 1 条既有断言并说明理由**：`payloadStaysCountOnlyAndRedacted` 原断言 `combined.contains("\(count)")`，即要求出现裸 `1000000`。数字按 locale 分组后该前提不再成立。未删除该断言，而是**加强**为「剥掉分组字符后必须含该数字序列」，从而保留「右侧数量确实在文案里」的保证且与分隔符无关。

### 变异自证（/tmp 副本，工作区源码零改动）

在 `/tmp/t030b-mut`（rsync 副本，排除 `.build`/`.git`）上逐条变异，每条后跑 `swift test --filter NotificationCopyTests`。**7/7 全部被捕获**：

| # | 变异 | 结果 |
| --- | --- | --- |
| M1 | 删除 catalog 中 fr 的 `many` 分支 | 红灯 1 issue |
| M2 | 删除 fr/es/pt-BR 三个 `many` 分支 | 红灯 3 issues |
| M3 | 停用 catalog 路径（强制走回落） | 红灯 3 issues |
| M4 | 把 `localizedCount` 的分组格式化换成 `String(value)` | 红灯 10 issues |
| M5 | 把分组 locale 硬编码为 `en`（模拟手写逗号分隔） | 红灯 4 issues |
| M6 | 让 `tableName` 恒返回 `en`（模拟不显式加载 `.lproj`） | 红灯 143 issues |
| M7 | 删除 catalog 中 fr 的 title | 红灯 1 issue |

M4 是**先发现缺口再补测试**的实证：加强前的测试套件对 M4 是**全绿**的，说明回落路径当时无保护；补上 `fallbackNumeralFormattingIsLocaleAware` 后才红灯。副本每条变异后已还原并与工作区 sha256 一致（三个文件 OK），沙箱已删除。

### 本轮实际验证

| 验证 | 命令 | 结果 |
| --- | --- | --- |
| 整包构建 | `swift build` | Build complete（`Package.swift` 未改，资源自动发现） |
| 整包测试 | `swift test` | 70 tests / 18 suites 与 108 tests / 30 suites 全部 passed，0 failed |
| 通知文案专项 | `swift test --filter NotificationCopyTests` | 10 tests / 1 suite passed |
| 本地化门 | `python3 scripts/verify-localization.py` | exit 0（102 字符串 / 102 键，九语全非空；未改该脚本） |
| CLI 构建 | `bash scripts/build.sh /tmp/automnt-plural` | 成功 |
| CLI 版本 / 自测 | `/tmp/automnt-plural --version` / `--self-test` | `3.4.0` / **295 passed, 0 skipped, 0 failed** |
| 原生 Release | `xcodebuild … -derivedDataPath .build/xcode-plural CODE_SIGNING_ALLOWED=NO build` | `** BUILD SUCCEEDED **` |
| 资源嵌入 | 检查 app 产物 | `Contents/Resources/Automnt_AutomntPlatform.bundle` 内含九个 `.lproj/Localizable.stringsdict` |

**通知投递管线回归**（本轮给 app 增加了资源 bundle，故必须复测）：

```text
--deliver-notification --count 1    -> exit=5  0.128s  reason=permissionNotDetermined count=1
--deliver-notification --count abc  -> exit=6  0.125s  reason=malformedArguments count=1
--deliver-notification --count=5    -> exit=5  0.126s  reason=permissionNotDetermined count=5
Contents/Helpers/AutomntHelper --probe-notification-channel -> exit=5  0.218s（非 134）
```

第 2–4 轮的退出码语义、畸形参数有界失败、helper 身份守卫全部保持不变。

### 本轮仍未验证的边界

- **未在真实通知横幅上目视确认**：探针验证的是 `NotificationCopy` 的取值与 app bundle 内资源解析，未在授权环境弹出系统通知并肉眼核对横幅文本与换行。
- **`Locale.preferredLanguages.first` 的真实映射未验证**：`zh-TW`/`zh-HK`/`pt-PT` 等在系统侧如何映射到哪个语言表依赖运行环境；测试与探针都显式注入语言字符串。`tableName` 已为这些标签给出确定映射，但未在真实系统语言设置下核对。
- **九语 many 分支译文仍是未获母语审校的草稿**：`\u202F` 等格式来自系统 locale 数据（可信），但 fr/es/pt-BR 的 `many` 用词（如 `de` 的插入位置与动词变位）未经母语确认。契约本就区分「系统分支正确」与「译文已审校」，本轮只证明前者。
- **未穷举 CLDR 类别组合**：只覆盖 `one`/`many`/`other` 与契约点名的 0/1/2/较大值/1,000,000；`few`/`two` 等类别对这九种语言不适用，未构造。
- **`verify-localization.py` 未扩展以扫描新 catalog**：本轮未新增用户可见裸字符串（文案进了平台目录，且 gate 的手写分支检查继续通过），因此未改该脚本（也不在必须范围内）。新 catalog 的键覆盖目前由 `scripts/build.sh` 里既有的 catalog 检查覆盖的是 **app** catalog；平台 catalog 的完整性由本轮新增单测保护。这是防回归门的一处已知盲区。
