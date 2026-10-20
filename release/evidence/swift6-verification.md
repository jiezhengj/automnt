# V10 独立复验：Swift 6 语言模式迁移（T004b / task-23）

本轮由独立验证者 `verifier3` 复验共享任务 task-23：把 `AutomntCLI` target 迁移到 Swift 6 语言模式（涉及 37 个可变全局/静态状态的并发改造）。

验证方式：**只读工作区 + 只运行命令**，工作区未修改任何源码、脚本、测试或工程文件；所有变异实验只在 `/tmp/v10-mut`（`rsync -a --exclude .build --exclude .git` 副本）上进行。逐文件 sha256 在复验前后完全一致（1629 个非 `.build`/`.git` 文件，见第 8 节）。

关键事实：**实现者的三条声明经独立复跑基本成立**（74→0 的诊断消除、`--self-test` 295/0/0、真实代码 0 个 `nonisolated(unsafe)`/`@unchecked Sendable`），但其「文件顺序影响诊断」的**机制描述与实际不符**（第 1.4 节），且本轮发现 **5 类「编译与测试双双漏判」的残余缺口**（第 5 节）。

## 结论摘要

| 编号 | 项目 | 结果 |
| --- | --- | --- |
| 1 | 两种文件顺序的诊断数 | **通过**（迁移后两序均 0）；但实现者的顺序机制描述**不准确**（见 1.4） |
| 2 | 死锁 / 重入 | **当前源码未发现可达的嵌套取锁**；检索方法经**植入样本验证有效**；但**不能断言「无死锁」**（见 2.5 未能排除项） |
| 3 | 信号处理器异步信号安全 | **通过**（无锁、无分配、仅 atomic + `tcsetattr`/`write`/`_exit`）；release/acquire 配对**对首次发布成立**，信号重入下的极端窗口**未排除** |
| 4 | 行为等价性 | **通过**：`check(` 计数 290→290 不变，**0 行断言被增删**；75 行删除全部属并发管道改造 |
| 5 | 独立变异 ≥3 类 | **2 类被捕获（编译红）、5 类双双漏判**（见第 5 节，属覆盖缺口而非当前缺陷） |
| 6 | 回归 | **通过**：0 失败、295/0/0、3.4.0、`** BUILD SUCCEEDED **`、本地化门 exit 0 |
| **总体** | | **通过**（迁移目标达成、行为等价性成立）；5 类双双漏判列为**残余覆盖缺口**，未验证边界如实列出 |

## 1. 独立复算诊断数

### 1.1 命令与两种文件顺序

在 `/tmp/v10-mut` 用 `swift build` 先构建出 `AutomntCore` module，再用 `swiftc -typecheck -swift-version 6` 对 CLI 的两个源文件做**整批**类型检查：

```text
$ swiftc -typecheck -swift-version 6 -sdk <macosx27.0> -target arm64-apple-macosx27.0 \
    -I .build/out/Products/Debug <文件顺序>

顺序 A（Entry-first）：Sources/AutomntCLI/Entry.swift Sources/AutomntCLI/ServiceAdapter.swift
顺序 B（SvcAd-first）：Sources/AutomntCLI/ServiceAdapter.swift Sources/AutomntCLI/Entry.swift
```

### 1.2 迁移后（当前磁盘状态）

```text
顺序 A（Entry-first）  : exit=0  primary error 行=0  含 'error:' 行=0
顺序 B（SvcAd-first）  : exit=0  primary error 行=0  含 'error:' 行=0
```

两种顺序**均为 0 error**，与实现者声明一致。

### 1.3 迁移前（V3 冻结副本 `/tmp/v3-mut`，其 `Package.swift` 仍为 `.v5`）

为独立复现「74 条」的来源，我用**同一探针**对 V3 冻结副本强制以 `-swift-version 6` 检查：

```text
顺序 A（Entry-first）  : exit=1  primary error 行=37   其中 #MutableGlobalVariable=37   文件分布：Entry.swift 37 / ServiceAdapter.swift 0
顺序 B（SvcAd-first）  : exit=1  primary error 行=1    其中 #MutableGlobalVariable=1    文件分布：Entry.swift 0  / ServiceAdapter.swift 1
两序并集的不同符号        : 37（Entry.swift 36 个 + ServiceAdapter.swift 1 个）
```

即：**「真实符号 37 个」这一说法可以独立复现**（36 + 1 = 37，两序无重叠）。`Entry.swift` 单文件单独检查时为 212 条 primary error（含级联错误），批量时只报 37 条，属 frontend 的**首个失败文件截断**行为，见 1.5。

### 1.4 实现者「文件顺序影响诊断」的描述与实际不符（提示级）

实现者的原话是「把 `Entry.swift` 放前面时 `ServiceAdapter.swift:53` 不被诊断，**交换后多 1 条**，真实 37 个」。前半句与我的实测**完全一致**：Entry-first 时 `ServiceAdapter.swift:53` 确实不在诊断里。但「交换后多 1 条」不成立——实测交换后是 **1 条**（不是 38 条），因为它换成了只报 `ServiceAdapter.swift` 而不报 `Entry.swift`。

正确的表述应是：**批量模式下 swiftc 只报告「第一个失败文件」的诊断**，因此两序各报一半；把两序的**符号并集**才是 37。这个差别不影响「当前 0 error」的结论（理由见 1.6），但说明该机制描述是被误读的，不应据此推断「少报」的方向。

### 1.5 机制确证：植入错误同时存在于两文件时，只报一个

在副本中**同时**给两个文件各植入一个裸可变全局（`v10EntryGlobal`、`v10SAGlobal`）：

```text
Entry-first  批: exit=1  total=1  → 仅报 Entry.swift:76 'v10EntryGlobal'
SvcAd-first  批: exit=1  total=1  → 仅报 ServiceAdapter.swift:53 'v10SAGlobal'
```

**两个文件各有错误，但每次都只报其中一个**——确证 1.4 的截断机制。

补充：若错误**只在** `ServiceAdapter.swift`，则 Entry-first 批量**能**捕获（实测 exit=1 并报出该符号），说明截断不等于「第二个文件完全不检查」，而是「一旦某文件失败即停止报告后续文件」。

### 1.6 为什么「两序均 0」仍可采信

- 植入实验证明 Entry-first 能检出 `ServiceAdapter.swift` 中的错误、SvcAd-first 能检出 `Entry.swift` 中的错误（只要该文件是首个失败者）。
- 因此「两序均为 0」蕴含：Entry.swift 在 A 序被检查且干净；ServiceAdapter.swift 在 B 序被检查且干净。两者合起来覆盖了两个源文件。
- 另外用 `SwiftPM` 复核（它按 primary-file 逐文件编译）：

```text
$ swift build   （植入 ServiceAdapter.swift 单独错误）  → exit=1，报出该符号
$ swift build   （两文件同时植入）                      → exit=1，只报一个（同样是首个失败文件）
```

即 SwiftPM **会**报 ServiceAdapter.swift 的错误，并不存在「SwiftPM 结构性少报 ServiceAdapter」的问题；两者都受「首个失败文件截断」限制，这是 swiftc frontend 的共性，**不是**本迁移的缺陷。

**判定**：诊断数复算**通过**（迁移后两序 0 error 可采信）；实现者的顺序机制描述不准确，属文档/沟通问题，不改变结论。

## 2. 死锁 / 重入专项（本轮最关键）

### 2.1 前提确认：`Synchronization.Mutex` 在递归获取时是**崩溃**而非静默挂起

本机实测（探针 `/tmp/v10-probe/mutex6.swift`，退出码 137 = 被信号杀死）：

```text
异常类型 : EXC_BREAKPOINT
asi      : "BUG IN CLIENT OF LIBPLATFORM: Trying to recursively lock an os_unfair_lock"
栈顶     : _os_unfair_lock_recursive_abort → _os_unfair_lock_lock_slow
```

即：`LockedBox` 用的 `Mutex` **非递归**，同一线程二次获取会**立即 abort**（不是死锁等待）。这使「自重入」成为**可用崩溃观测**的缺陷类型。

### 2.2 检索方法（含对检索器自身的有效性验证）

我写了两级静态分析器：

1. **访问器级（R1）**：解析每个 `var` 作用域，区分 getter / setter 子句，判定其体内是否
   - 直接引用**另一个** `*Box.value`；
   - 通过**包装属性**（如 `originalTermios`）间接引用另一个 box；
   - 引用**自己的包装属性名**（自重入）。
2. **调用图级（ABBA）**：判定是否存在「某函数持有 box A 期间，调用会取 box B 的代码」。

**关键前置：我验证了分析器本身有效**，否则「0 发现」无意义。植入 4 个已知坏样本：

| 植入样本 | 分析器 | 结果 |
| --- | --- | --- |
| getter 读取**第二个** box | R1a | **检出** |
| getter **自重入**自己的属性 | R1b | **检出** |
| setter **自重入**自己的属性 | R1b | **检出** |
| getter 通过包装属性读第二个 box | R1a | **检出** |

> 说明：我的**第一版**分析器只匹配裸 `XBox.value`，对真实代码「经包装属性访问」完全失明，因而对任何源码都返回「无重入」。我据此**推翻了自己的初版结论**并重写，验证后才采用下列结果。这一点必须记录，否则读者无法判断「0 发现」的可信度。

### 2.3 结果

```text
声明 LockedBox 对象          : 33
可映射到包装属性的 box        : 31
var 作用域                   : 60
R1a 访问器子句触及【另一个】box : 0
R1b 访问器子句【自重入】自身   : 0
```

即：**当前 33 个 `LockedBox` 的访问器中，没有任何一个在持锁期间再取第二个锁（含自重入）。**

进一步核对「持锁期间是否调用其它代码」：

```text
所有 withLock 使用点（8 处）:
  Entry.swift:48,49            LockedBox.value get/set        → { $0 } / { $0 = newValue }
  Entry.swift:153,157,161      CommandOutputBuffer            → $0.standardOutput = data 等
  Entry.swift:589              ConfigurationDraftRevisionCache → $0.removeValue(forKey: path)
  Entry.swift:592,593          同上 subscript get/set
```

**8 处 `withLock` 全部是单表达式**，表达式内只有字典/元组操作，**没有任何函数调用**——因此不存在「持锁期间调用外部代码」的路径。

访问器体内唯一的调用是 `Entry.swift:1566-1574` 的 `cursorHidden` setter：

```swift
set {
    cursorHiddenBox.value = newValue                                   // ← 取锁并已释放
    terminalSignalCursorHidden.store(newValue ? 1 : 0, ordering: .releasing)  // ← 之后才执行的 Atomic 操作
}
```

`Atomic.store` 是**无锁**操作，且发生在 `cursorHiddenBox.value` 赋值**返回之后**（锁已释放），不构成嵌套。

### 2.4 结论（有保留）

- **当前源码中，未发现可达的「同锁重入」或「跨 box 嵌套取锁」路径**；ABBA 亦不成立，因为 `LockedBox.value` 的取锁范围是**单个表达式**，两把 box 只可能**串行**取用、不会同时持有。
- 这是**基于调用结构与数据流的结构性论证 + 经样本验证的静态扫描**，不是形式化证明。

### 2.5 无法完全排除的路径（如实列出，不作「无死锁」断言）

1. **动态派发 / 协议见证 / 闭包回调**：`TerminalUI` 与 `runSelfTests` 大面积使用注入闭包与 `CLIThreadValue`。我的分析器按**词法名字**解析调用边，无法追踪经闭包参数、`@escaping` 存储或协议见证发生的间接调用。若将来有访问器把锁内表达式改为「经闭包回调解引用另一 box」，静态名字匹配**可能漏检**（这也正是我初版失明的原因）。
2. **`runSelfTests` 体量过大（`Entry.swift:4024-5384`，约 1360 行）**：该函数触及 19 个 box，我的作用域解析在超长函数内的置信度低于短函数；其中是否存在跨 box 的**运行期**嵌套（例如测试夹具在未释放的场景下回调）无法仅凭静态读完确认。
3. **`signalHandlerTermiosSnapshot()` 在 handler 中被调用**：它读 atomic 与堆指针，本身不加锁；但若信号在**主线程正持有**某个 `LockedBox` 锁时投递，handler 不会去取那个锁（它只碰 3 个 Atomic 与一个裸堆指针），故**不会**因 handler 而死锁——这一条我有较高把握，但它依赖「handler 永不触碰 `LockedBox`」这一事实在**将来**保持。
4. **未做并发压力测试**：没有多线程压测或 Thread Sanitizer 运行，纯静态结论不能替代运行期验证。

**因此我的结论是：当前源码未发现可达的重入/嵌套取锁路径，但不能断言「无死锁」。** 上述 1、2 两条是残余不确定性最大的地方。

## 3. 信号处理路径

### 3.1 `terminalSignalHandler` 逐调用审查（`Entry.swift:1473-1483`）

```swift
private func terminalSignalHandler(_ signalNumber: Int32) {
    if var snapshot = signalHandlerTermiosSnapshot() {        // ①
        _ = tcsetattr(STDIN_FILENO, TCSANOW, &snapshot)       // ②
        if terminalSignalCursorHidden.load(ordering: .acquiring) != 0 {   // ③
            withUnsafePointer(to: terminalSignalCursorSequence) { pointer in
                _ = write(STDOUT_FILENO, pointer, 6)          // ④
            }
        }
    }
    let exitCode: Int32 = signalNumber == SIGTERM ? 143 : (signalNumber == SIGHUP ? 129 : 130)
    _exit(exitCode)                                            // ⑤
}
```

| 调用 | 是否加锁 | 是否堆分配 | 判定 |
| --- | --- | --- | --- |
| ① `signalHandlerTermiosSnapshot()` | 否（2 次 Atomic load + 指针解引用） | 否（返回 `termios?`，定长 C 结构栈拷贝） | 异步信号安全 |
| ② `tcsetattr` | 否 | 否 | POSIX async-signal-safe |
| ③ `Atomic.load` | 否 | 否 | 无锁原子读 |
| ④ `withUnsafePointer` + `write` | 否 | 否（取全局常量的地址） | `write` 为 async-signal-safe |
| ⑤ `_exit` | 否 | 否 | `_exit` 为 async-signal-safe（非 `exit`） |

**审查结论：handler 内无锁、无堆分配、无 Swift 运行期可能分配的调用（无字符串插值、无 `print`、无 `Array` 构造、无 `String` 操作）。** 3 个共享量为 `Atomic<UInt>` / `Atomic<Int32>`，均以 `.acquiring` 读取；`terminalSignalCursorSequence` 是**不可变元组常量**，取其地址不分配。

### 3.2 快照发布的 release/acquire 配对

发布侧（`Entry.swift:1446-1460`）：

```swift
pointer.pointee = snapshot                                    // 普通写（快照内容）
terminalSignalRestoreEnabled.store(1, ordering: .releasing)  // release 发布
```

读取侧：

```swift
guard terminalSignalRestoreEnabled.load(ordering: .acquiring) != 0,
      let raw = UnsafeMutableRawPointer(bitPattern: terminalSignalTermiosAddress.load(ordering: .acquiring)) else { return nil }
return raw.assumingMemoryBound(to: termios.self).pointee
```

**配对正确**：release store 之后的 acquire load 建立 synchronizes-with，保证 handler 在读到 `enabled==1` 时，之前对 `pointer.pointee` 的普通写已对其可见（ARM64 上 release 阻止前面的普通写被重排到 store 之后，acquire 阻止后面的读被重排到 load 之前）。地址的首次发布用 `.relaxed`，但因为 `enabled` 初始为 0、且发布顺序是「先写地址、再写 enabled」，handler 在 `enabled==1` 之前读地址只会得到 nil 并直接返回，**不会**解引用未初始化指针。

### 3.3 未能排除的极端窗口（如实记录为未验证边界）

存在一个**理论上**的撕裂读窗口：若 handler 已通过 `enabled` 的 acquire（读到 1），在**读取 `pointee` 之前**被第二次信号重入或长时间抢占，而主线程在此期间完成「`clearTerminalSignalRestore()`（enabled=0）→ 再次 `publishTerminalSignalTermios`（重写同一个 `pointee`）」，则恢复执行的 handler 可能读到**半写**的 termios 快照。

我**未能构造出可复现的实测**，并给出两点缓解事实：

- `setRawMode` 有 `guard originalTermios == nil else { return }`，同一会话内**不会重复发布**；重复发布必须先经 `restoreTerminal()`（其中 `clearTerminalSignalRestore()` 置 enabled=0）。
- handler 在通过 acquire 之后到读 `pointee` 之间只有极少量指令，需信号嵌套重入才能拉开窗口。

**判定**：不把它列为缺陷（未能复现、且需要信号嵌套这一非典型条件），但**明确标注为未验证边界**，不建议据此宣称「快照发布在所有信号交错下都无撕裂」。

## 4. 行为等价性（CLI 自测断言是否一行未改）

`Sources/` 未被 git 跟踪，故用我 V3 轮次冻结的副本作基线。**基线可用**：

```text
V3 冻结（/tmp/v3-mut、/tmp/v3b-mut、/tmp/v5-mut、/tmp/v6-mut 四处一致）
Entry.swift sha256 = ede0ca417351f8ab2c8998c9062d21aa5c0bcb39974f1665bbc8ed5f7f2cbd19
（与 task-9/V3 记录的 ede0ca41… 一致）

当前工作区
Entry.swift sha256 = 3e75b99d05edd5299ae368e9ecf13601928bf897ce43f431a20a3bfcf6be98f9
ServiceAdapter.swift sha256 = d9204827b098ff0cd22edc10ff9e9e847c76345c954b7ae870821cd525b1518a
```

**结论：确实不同**（符合本轮发生改动的预期），不是「未改动」。

### 4.1 改动量

```text
$ diff <V3 Entry.swift> <当前 Entry.swift>
hunk 数        : 38
删除行         : 75
新增行         : 268
```

### 4.2 断言完整性的独立核对（比行数更关键）

```text
check( 计数：V3 = 290，当前 = 290      ← 与 V3 记录完全一致
删除行中属于 check( 断言的：0 行
新增行中属于 check( 断言的：0 行
```

**跨 343 行改动，没有任何一行自测断言被增加或删除**——这是「自测断言一行未改」的独立证据。

### 4.3 75 行删除的分类（全部属并发管道）

| 类别 | 例 | 说明 |
| --- | --- | --- |
| 裸可变全局/静态声明 | `var configURLOverride: URL?`、`static var originalTermios: termios?` | 改为 `*Box` + 同名计算属性 |
| 手写 `NSLock` 管道 | `private let lock = NSLock()` / `lock.lock()` / `lock.unlock()` | 改为 `Mutex` + `withLock`（`CommandOutputBuffer`、`ConfigurationDraftRevisionCache`） |
| 信号状态裸变量与赋值 | `if terminalSignalRestoreEnabled != 0`、`terminalSignalRestoreTermios = original` | 改为 `Atomic` + 堆快照发布 |
| `didSet` 桥接 | `didSet { terminalSignalCursorHidden = cursorHidden ? 1 : 0 }` | 改为 setter 内显式 `Atomic.store` |
| 函数内局部可变变量 | `var resultData: Data?`、`fetchResult = .networkError(...)` | 改为 `LockedBox`（跨闭包回传） |
| 原有逃逸标记 | `@unchecked Sendable` ×2 | 删除 |

与实现者「消除三处 `@unchecked Sendable`」的说明一致；我另行核实：**CLI target 两个文件中，`nonisolated(unsafe)` 与 `@unchecked Sendable` 在真实代码里各为 0**（所有命中均为注释文字）：

```text
$ grep -n 'nonisolated(unsafe)\|@unchecked Sendable' Sources/AutomntCLI/*.swift
Entry.swift:40,144,584,1439        ← 全部为注释
ServiceAdapter.swift:302           ← 注释
（无一处是真实代码）
```

注：`Sources/AutomntPlatform/NotificationChannel.swift:404` 等处仍有 `nonisolated(unsafe)`，但 `AutomntPlatform` **不在本次迁移范围**（其 `swiftLanguageMode` 未设为 `.v6`），不属本轮缺陷。

### 4.4 入口语义

```text
$ /tmp/automnt-v10 --version   → 3.4.0（exit 0）
$ /tmp/automnt-v10 --self-test → Self-tests: 295 passed, 0 skipped, 0 failed
```

与 V3 的 295/0/0 一致，未因并发改造减少或跳过任何自测项。

**判定**：行为等价性**通过**。

## 5. 独立变异实验（7 类）与双双漏判回答

方法：每条变异在副本上单点施加，然后**同时**跑 `swiftc -typecheck -swift-version 6`、`swift build`、`swift test`。判据：三者全绿 = **双双漏判**。

| 编号 | 变异 | typecheck | swift build | swift test | 双双漏判 |
| --- | --- | --- | --- | --- | --- |
| M1 | `configURLOverride` 还原为裸全局 `var` | **红**（1 error） | **红** | 红 | 否 |
| M2 | `TerminalUI.testOverride` 还原为裸 `static var` | **红**（1 error） | **红** | 红 | 否 |
| M3 | 发布侧 `.releasing` → `.relaxed` | 绿 | 绿 | 绿 | **是** |
| M4 | handler 侧 `.acquiring` → `.relaxed` | 绿 | 绿 | 绿 | **是** |
| M5 | 访问器**自重入**自身（`cursorHidden`） | 绿 | 绿 | 绿 | **是** |
| M6 | 访问器**嵌套第二个 box** | 绿 | 绿 | 绿 | **是** |
| M7 | 重新加回 `@unchecked Sendable` | 绿 | 绿 | 绿 | **是** |

M1 的实际输出（证明 Swift 6 语言模式确实在守护核心不变量）：

```text
Entry.swift:76:5: error: var 'configURLOverride' is not concurrency-safe because it is
    nonisolated global shared mutable state [#MutableGlobalVariable]
```

**回答「是否存在双双漏判」：是，存在 5 类（M3–M7）。** 具体地：

- **M1/M2 被可靠捕获**：说明「不得有裸可变全局」这一**主要**不变量由编译器强制，迁移的核心保护是真实有效的。
- **M3/M4（Atomic 内存序）属编译器原理上无法检查**的类别（语义等价于类型系统之外），无自动化看守属预期，但确应记录。
- **M5/M6 是并发安全上的实质缺口**。我另做了运行期确证：把「访问器 getter 自重入」这一形态编成最小程序，**Swift 只给 warning（`attempting to access 'cursorHidden' within its own getter` / `function call causes an infinite recursion`），且 `-swift-version 6` 下仍是 warning 而非 error**，运行期实测 **Segmentation fault: 11（exit 139）**。也就是说：**这类崩溃不会被编译器拦住，也不会被 295 项自测拦住**。
- **M7**：`@unchecked Sendable` 是 Swift 语言**有意提供的显式逃生舱**，编译器按设计放行；本迁移刚把两处删除，却无任何看守防止重新加回。

补充证据（M5 的运行期覆盖情况）：我用变异源码（自递归访问器）成功 `build.sh` 出二进制并运行 `--self-test`，结果仍是 **295 passed / 0 skipped / 0 failed** —— 说明**终端访问器路径完全不在自测覆盖内**，这也解释了 M5/M6 为何双双漏判。

**严重度判定**：这 5 类**不是当前源码的缺陷**（第 2.3 节已用经验证的分析器确认当前 0 实例），而是**防回归缺口**。建议（由实现者决定）：

1. 为 `LockedBox` 增加一个自测断言，把「访问器不得触及第二个 box」做成可执行检查（或把静态扫描固化进 `build.sh`，类似既有的 `verify-localization.py` 模式）；
2. 为 Atomic 发布/读取加一个「同一常量」的断言测试，至少让 M3/M4 这类改动需要有人**有意**绕过；
3. 在 CI/构建脚本中加入 `grep -c 'nonisolated(unsafe)\|@unchecked Sendable' Sources/AutomntCLI` 为 0 的看守（本轮已实测为 0，作为守卫成本极低）。

## 6. 回归

```text
$ swift build
Build complete! (0.31秒)                          exit=0

$ swift test
Test run with 70 tests in 18 suites passed after 4.285 seconds.    # AutomntPlatformTests
Test run with 108 tests in 30 suites passed after 5.022 seconds.   # AutomntCoreTests
exit=0    issues=0
静态 @Test 计数：Core 108 / Platform 70，与运行计数一致

$ rm -f /tmp/automnt-v10 && bash scripts/build.sh /tmp/automnt-v10
BUILD_SH_EXIT=0        1856984 bytes
$ /tmp/automnt-v10 --version
3.4.0        (exit 0)
$ /tmp/automnt-v10 --self-test | tail -1
Self-tests: 295 passed, 0 skipped, 0 failed     (exit 0)

$ xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt \
    -configuration Release -derivedDataPath .build/xcode-v10 CODE_SIGNING_ALLOWED=NO build
** BUILD SUCCEEDED **    (XCODE_EXIT=0)

$ python3 scripts/verify-localization.py --quiet
exit=0
```

`scripts/build.sh:34` 已为 `-swift-version 6`、`Package.swift:15-16` 的 `AutomntCLI` 已为 `.swiftLanguageMode(.v6)`，两处一致。

**附带发现（非本轮缺陷，供台账参考）**：`apps/Automnt/Automnt.xcodeproj/project.pbxproj` 的 App / helper / worker 三类 target **在 V3 时期就已是 `SWIFT_VERSION = 6.0`**（V3 冻结副本与当前均为 6 处 `SWIFT_VERSION = 6.0`，无差异）。即 Xcode 侧早于本次 SwiftPM 迁移进入 Swift 6，本轮改的是 `AutomntCLI` 的 SwiftPM 语言模式与 `build.sh`。`AutomntCore`/`AutomntPlatform` 两个 target 在本轮**仍为默认（未显式设 `.v6`）**，属本轮声明的范围之外。

## 7. 缺陷与缺口清单

### G1（中，防回归缺口）：5 类并发退化「编译与测试双双漏判」

- 见第 5 节 M3–M7。位置：`Sources/AutomntCLI/Entry.swift:44-51`（`LockedBox`）、`:1437-1483`（信号发布/读取）。
- 关键风险：**访问器自重入**（M5）在本机实测为 **Segmentation fault（exit 139）**，而 Swift 6 仅给 **warning**；295 项自测**不覆盖**终端访问器路径（变异后自测仍 295/0/0）。
- 最小复现（不修改工作区）：
  ```
  rm -rf /tmp/m && mkdir /tmp/m && rsync -a --exclude .build --exclude .git <工作区>/ /tmp/m/ && cd /tmp/m
  python3 - <<'PY'
  import pathlib
  p = pathlib.Path('Sources/AutomntCLI/Entry.swift'); s = p.read_text()
  old = "    static var cursorHidden: Bool {\n        get { cursorHiddenBox.value }"
  assert old in s
  p.write_text(s.replace(old, "    static var cursorHidden: Bool {\n        get { _ = cursorHidden; return cursorHiddenBox.value }", 1))
  PY
  swift build && bash scripts/build.sh /tmp/m-bin && /tmp/m-bin --self-test   # 期望红，实际全绿（295/0/0）
  ```
- 独立确证该形态的危害（与仓库无关的最小程序）：
  ```
  swiftc -O -swift-version 6 -o /tmp/hz /tmp/hz.swift   # 仅 warning
  /tmp/hz ; echo $?                                      # 139（Segmentation fault）
  ```

### G2（低，文档不实）：实现者对「文件顺序影响诊断」的机制描述不准确

- 声明「交换后**多 1 条**」；实测交换后为 **1 条**（Entry-first 37 / SvcAd-first 1），两序**并集**才是 37。
- 影响：不改变「0 error」结论（第 1.6 节已论证可采信），但该描述会误导后续读者以为「交换后能看到 38 条」。
- 建议：改为「批量模式下 swiftc 只报首个失败文件的诊断；两序各报其首个失败文件，符号并集为 37」。

### G3（提示）：`AutomntCore` / `AutomntPlatform` 未纳入本轮语言模式

本轮只把 `AutomntCLI` 设为 `.v6`；`Sources/AutomntPlatform/NotificationChannel.swift:404` 等仍含 `nonisolated(unsafe)` 与 `@unchecked Sendable`。这与任务声明范围一致，**不是缺陷**，但「代码级 unsafe 标记为 0」这句话只对 `AutomntCLI` 成立，若对外表述需限定范围。

## 8. 工作区完整性与清理

复验前后逐文件 sha256 全量对照（1629 个非 `.build`/`.git` 文件）：

```text
before: 1629   after: 1629
CHANGED: []
ADDED:   []
REMOVED: []
```

- 工作区**零改动**；本文件为新建（在写范围内）。
- `/tmp/v10-mut` 副本在每条变异后均还原，`Sources/AutomntCLI/Entry.swift` 与 `ServiceAdapter.swift` 的副本、pristine 快照、工作区三者 sha256 **一致**。
- 派生的探针与测试进程已清理，`pgrep` 无残留。
- 所有分析器、探针与日志位于 `/tmp`（仓库外），未写入工作区。

## 9. 仍未验证的边界（不得当作已完成）

1. **真机终端交互**：未在真实 TTY 下进入原始模式/光标隐藏/选择框交互，未验证并发改造后的终端行为与旧版一致；`--self-test` 使用测试夹具覆盖，**不覆盖**真实终端路径（第 5 节已实测该路径不在 295 项内）。
2. **信号实际投递**：未真实发送 `SIGINT`/`SIGTERM`/`SIGHUP` 到运行中的 `automnt` 以观察 termios 恢复与光标还原；handler 的安全性为**静态审查**结论。
3. **并发压力**：未做多线程压测、未运行 Thread Sanitizer / Address Sanitizer；第 2 节的「未发现重入」是静态结构论证，不能替代 TSan。
4. **死锁自由性未证**：第 2.5 节列出 4 条无法完全排除的路径（间接调用/闭包回调、超长 `runSelfTests`、handler 未来触碰 `LockedBox`、无压力测试）。
5. **信号快照撕裂窗口**：第 3.3 节的极端交错未能复现，也未能证明不存在。
6. **各 target 语言模式未逐个核验语义影响**：`AutomntCore`/`AutomntPlatform` 仍为默认模式；Xcode App/helper/worker 虽已是 `SWIFT_VERSION = 6.0`（V3 起），但我**未逐 target 核对其 Swift 6 诊断是否为零**，也未验证 helper/worker 在 Swift 6 下的并发行为。
7. **App / helper / worker 的运行时并发行为**：本轮回归只到构建与 SwiftPM 测试层，未在真实 helper/worker 进程与 `launchd` 环境下验证并发改造的影响。
8. **`xcodebuild` 产物签名与 entitlements**：本轮仍为 `CODE_SIGNING_ALLOWED=NO`，签名相关结论**未验证**。
9. **性能**：用 `Mutex` 替换裸变量给终端渲染热路径引入锁开销，未做任何吞吐/延迟对比（原为无锁裸读）。

## 10. 复现材料位置

| 内容 | 路径 |
| --- | --- |
| 变异沙箱副本（工作区未受影响） | `/tmp/v10-mut`、`/tmp/v10-pristine` |
| 访问器重入分析器（经植入样本验证） | `/tmp/v10-r1d.py` |
| 调用图/ABBA 分析器 | `/tmp/v10-callgraph2.py`、`/tmp/v10-abba.py` |
| 分析器有效性验证脚本 | `/tmp/v10-validate2.py` |
| 变异实验脚本 | `/tmp/v10-mutations.py`、`/tmp/v10-hazard.py` |
| `Mutex` 非递归崩溃确证 | `/tmp/v10-probe/mutex6.swift`（崩溃报告：`~/Library/Logs/DiagnosticReports/mutex6-*.ips`，`_os_unfair_lock_recursive_abort`） |
| 自重入 warning/segfault 最小复现 | `/tmp/v10-hz/hz.swift` |
| 诊断数日志（两种顺序、迁移前后） | `/tmp/v3-entry-first.log`、`/tmp/v3-svcad-first.log`、`/tmp/v10-tc-entry-first.log` |
| V3 冻结基线 | `/tmp/v3-mut`（`Entry.swift` = `ede0ca41…`） |
| Entry.swift 差异 | `/tmp/v10-entry.diff` |
| 本轮新构建产物 | `/tmp/automnt-v10`、`.build/xcode-v10` |

工作区在复验前后逐文件 sha256 完全一致；所有变异仅在 `/tmp` 副本，验证过程未修改任何源码、测试、`Package.swift`、`build.sh` 或工程文件。
