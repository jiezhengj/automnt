# Bug Fix: 可达性探测可被证伪，并补上同轮回退与网络变化触发

- **Slug**: mount-failure-host-fallback
- **Fixed**: 2026-11-14
- **Assessment**: ./assessment.md
- **Status**: applied

# 修复概要

后台与 CLI 的可达性探测不再把「TCP 连上」当作可挂载的充分证据：先对 Bonjour 实例名做 DNS-SD SRV 解析，再完成一次 TCP 连接加一次 SMB2 `NEGOTIATE` 应答校验，只有收到 `\xfeSMB` 响应头才判定可达；本机 fake-ip TUN 后面的假地址会在数毫秒内被判为不可达。在此基础上补齐同轮回退：被选中的主机在挂载阶段以连接类失败（`offline` / `timeout`）结束时，按保存顺序改挂同一共享（共享名与挂载点都相同）在下一顺位启用主机上的条目，成功即停；`shareRejected` / `credentialFailure` / `pathConflict` 不触发回退。同时给应用侧启动代理补上 `SystemConfiguration` 目录监听，使 Tailscale 上下线能启动一轮评估。

# 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| `Sources/AutomntCore/SMB2NegotiateFrame.swift` | 新增 | 最小 SMB2 `NEGOTIATE` 请求帧、NetBIOS 长度前缀编解码与响应头判定（`\xfeSMB`），不认证、不建会话。 |
| `Sources/AutomntCore/BonjourServiceResolver.swift` | 新增 | `<实例>._smb._tcp.local[.]` 的 DNS-SD 解析（`DNSServiceResolve` + SRV 目标 + 超时/取消，阻塞封装不占用协作线程池）；解析失败即判定不可达，不回退到 `getaddrinfo(实例名)`。 |
| `Sources/AutomntCore/HostFallbackPolicy.swift` | 新增 | 回退规则的唯一实现：失败分类（`offline`/`timeout`/`.hostUnreachable`/NetFS 连接类状态码）、候选选择（同名共享 + 同挂载点、保存顺序、排除失败主机）、`isSameShareMount` 识别同一共享已由另一身份挂载。 |
| `Sources/AutomntPlatform/TCPReachabilityProbe.swift` | 修改 | 探测改为「DNS-SD 解析 → TCP → SMB2 `NEGOTIATE`」，共用同一探测预算。 |
| `Sources/AutomntPlatform/BackgroundEvaluator.swift` | 修改 | `first_reachable` 下挂载阶段连接类失败改试下一顺位候选主机；同一共享已由另一身份挂载时记健康而非报路径冲突。 |
| `Sources/AutomntCore/RecoveryRound.swift` | 修改 | 恢复轮在连接类失败后按同一规则回退，成功写入 `attached`、失败写入 `pendingRecovery`，抑制中的候选不得被回退改写。 |
| `Sources/AutomntCLI/Entry.swift` | 修改 | CLI 探针改用同一套 DNS-SD + SMB2 握手机制（不依赖平台层）；`--internal-netfs-mount` 用独立退出码区分凭据失败与连接类失败；`runRecoveryRound` 支持回退身份挂载；`ensureMountPointReady` 不再卸载已由另一身份挂载的同一共享；自测新增回退场景。 |
| `apps/Automnt/Resources/LaunchAgents/automnt.recovery.plist` | 修改 | `WatchPaths` 增加 `/Library/Preferences/SystemConfiguration`。 |
| `apps/Automnt/Resources/LaunchAgents/automnt.baseline.plist` | 修改 | 同上，保持两份定义一致。 |
| `Tests/AutomntCoreTests/HostFallbackPolicyTests.swift` | 新增 | 7 项：失败分类、NetFS 状态码分类、同名同挂载点约束、保存顺序、候选只带配对共享、跨身份同共享识别、回退卷与配置同源。 |
| `Tests/AutomntCoreTests/RecoveryRoundTests.swift` | 修改 | 4 项：连接类失败同轮回退、共享被拒不回退、成功即停与预算耗尽不再尝试、抑制中的候选不被改写。 |
| `Tests/AutomntPlatformTests/BackgroundEvaluatorTests.swift` | 修改 | 2 项：挂载阶段 `offline` 回退到下一主机并只产生一份健康记录、共享被拒不回退。 |
| `Tests/AutomntPlatformTests/TCPReachabilityTests.swift` | 修改 | 只回应 TCP 的监听端判为不可达（原「本地 TCP 连接即可达」断言反转）、回应 SMB2 响应头的监听端判为可达、取消仍抛 `CancellationError`。 |

# 关键改动

探测（`Sources/AutomntPlatform/TCPReachabilityProbe.swift`、`Sources/AutomntCLI/Entry.swift`）在连接就绪后发送 `SMB2NegotiateFrame.request()` 并只要求 4 字节 `\xfeSMB` 响应头：

```swift
guard let target = await resolver.resolveIfNeeded(host: host,
                                                  timeoutMilliseconds: remainingMilliseconds(until: deadline)) else {
    return false
}
```

CLI 侧子进程用独立退出码还原失败类别，父进程据此决定能否回退：

```swift
if mounted { exit(0) }
if credentialFailure { exit(internalNetFSMountCredentialFailureExitCode) }
exit(HostFallbackPolicy.isConnectionFailure(netFSStatus: status)
     ? internalNetFSMountConnectionFailureExitCode : 1)
```

回退只在连接类失败时进入，候选由同一份规则选出：

```swift
if policy == .firstReachable, let failed = issue,
   HostFallbackPolicy.isConnectionFailure(failed) {
    if let fallback = try await evaluateFallback(...) { ... }
}
```

# 新增与更新测试

- `Tests/AutomntCoreTests/HostFallbackPolicyTests.swift::onlyConnectionIssuesTriggerFallback` — 只有 `offline`/`timeout`/`hostUnreachable` 触发回退。
- `Tests/AutomntCoreTests/HostFallbackPolicyTests.swift::netFSStatusCodesClassifyConnectionFailures` — NetFS 连接类状态码（50/51/60/61/64/65）与共享/凭据类状态码的区分。
- `Tests/AutomntCoreTests/HostFallbackPolicyTests.swift::candidatesRequireSameShareAndSameMountPoint` — 共享名不同或挂载点不同都不得回退。
- `Tests/AutomntCoreTests/HostFallbackPolicyTests.swift::savedOrderIsRespectedAndFailedHostExcluded` — 候选按保存顺序且不含失败主机。
- `Tests/AutomntCoreTests/HostFallbackPolicyTests.swift::candidateHostsCarryOnlyPairedShares` — 候选主机只带可与失败共享配对的共享。
- `Tests/AutomntCoreTests/HostFallbackPolicyTests.swift::sameShareMountRecognisedAcrossHostIdentities` — 同一共享已由另一身份挂载可被识别（CLI 不卸载、helper 不报冲突）。
- `Tests/AutomntCoreTests/HostFallbackPolicyTests.swift::fallbackVolumesMirrorConfiguredVolumes` — 回退卷身份与 `configuredRecoveryVolumes` 同源，无配对时为空。
- `Tests/AutomntCoreTests/RecoveryRoundTests.swift::connectionFailureFallsBackToNextHostInSameRound` — 同一轮改挂下一顺位，失败身份仍留证据但不再上报失败或通知。
- `Tests/AutomntCoreTests/RecoveryRoundTests.swift::shareRejectionDoesNotFallBack` — 共享被拒不回退。
- `Tests/AutomntCoreTests/RecoveryRoundTests.swift::fallbackStopsAtFirstSuccessAndRespectsBudget` — 成功即停；预算耗尽后不再尝试候选。
- `Tests/AutomntCoreTests/RecoveryRoundTests.swift::fallbackNeverOverridesSuppressedCandidate` — 抑制结论不被回退清除或改写。
- `Tests/AutomntPlatformTests/BackgroundEvaluatorTests.swift::connectionFailureAtMountFallsBackToSameShareOnNextHost` — 第二条主机被挂载、只产生一份健康记录。
- `Tests/AutomntPlatformTests/BackgroundEvaluatorTests.swift::shareRejectionAtMountDoesNotFallBack` — 不产生回退挂载。
- `Tests/AutomntPlatformTests/TCPReachabilityTests.swift::tcpOnlyEndpointIsNotReachable` / `smb2NegotiateResponderIsReachable` / `cancelledProbeThrowsCancellation` — 假服务端判不可达、SMB stub 判可达、取消语义不变。
- CLI 内置自测（`Sources/AutomntCLI/Entry.swift` 内 `runSelfTests`）— 注入 `hostReachability` 与 `applyRecovery` 复现「第一条连接类失败、第二条成功」，断言 `RecoveryRoundOutcome.recovered` 为第二条、`failed` 与 `notificationKeys` 为空；另有共享被拒只尝试第一条并如实上报失败。

# 本地验证

- `swift test` → `109 tests in 30 suites passed`、`212 tests in 52 suites passed`、`33 tests in 3 suites passed`（全部通过）。
- `bash scripts/build.sh` → 退出 0，产出并签署 `.build/automnt`（`Apple Development: jie.zhengj@qq.com (8SDSF987N2)`），版本 3.5.1。
- `./.build/automnt --self-test` → `305 passed, 0 skipped, 0 failed`（改动前 302）。
- `git diff --check` → 通过。
- 局域网内实测探测（`--internal-host-probe <host> 445 1000`）：`DX4600._smb._tcp.local` 判可达 0.03–0.21s（DNS-SD SRV + SMB 握手）；`DX4600.local` 与 `100.113.52.52`（Tailscale）判可达 0.03s；`198.18.0.5`（fake-ip）判不可达 0.01s；编造的不存在实例名判不可达 1.0s（DNS-SD 等待超时）；`100.113.52.52` 连续 30 次无失败。
- 自建监听端对照：本机起一个只接受 TCP 后立刻关闭的监听端与一个回 `\xfeSMB` 响应头的 stub，同一探测命令对前者退出 1、对后者退出 0——证明判定依据是 SMB 应答而非「连上了」。
- 用 Python 直接复现旧逻辑：`getaddrinfo` 对 `DX4600._smb._tcp.local` 与编造名字给出的四个地址（`198.18.0.5`、`2001:2::5`、`198.18.0.195`、`2001:2::c5`）**全部 TCP 连接成功、SMB 应答为空**，与评估记录的「TCP-only 探测恒假成功」一致。
- 局域网内实测失败分类（`--internal-netfs-mount <url> <path>`）：`smb://192.0.2.1/share` → 78（连接类）7.25s；`smb://198.18.0.5/share` → 78 2.22s；`smb://100.113.52.52/no-such-share-automnt` → 1（共享被拒）0.68s；`smb://DX4600._smb._tcp.local/no-such-share-automnt` → 1 0.38s。
- 触发源实验（kqueue 监听四个路径，`tailscale down` / `tailscale up` 各一次）：`/var/run/resolv.conf` 在两条边沿都变化；`/Library/Preferences/SystemConfiguration` 目录在 `tailscale up` 时收到写事件；`preferences.plist`、`NetworkInterfaces.plist` 与 `ifconfig` 的 utun 列表在上下线前后不变。据此给应用侧启动代理补目录监听。
- 用临时 launchd 任务（`WatchPaths` 只含 `/Library/Preferences/SystemConfiguration`）复验同一机制：`tailscale down` 不触发，`tailscale up` 触发一次并写入时间戳。任务验后已 `bootout` 并删除 plist。
- 安装后的真实 App 上（包内四条 `WatchPaths`、经界面重新登记）：`tailscale down` 与 `tailscale up` **都**启动了一轮（`runs` 两次递增），与上面临时任务只 `up` 触发的结论不同——触发源同为 `SystemConfiguration` 目录，只是该目录在上下线时都可能写入。文档与后续判断以真实 App 的结论为准。
- `plutil -lint apps/Automnt/Resources/LaunchAgents/*.plist` → 两份均 OK；`launchctl print gui/501/org.automnt.automnt.recovery` 可正常读取该任务。
- `./automnt --status` 读取真实配置：两条主机（`DX4600._smb._tcp.local:445`、`100.113.52.52:445`），各两个共享，均处于已挂载状态；未改动维护者配置。

# 与评估的偏差

- **范围扩展（已记录）**：评估未列出的三处改动——`ensureMountPointReady`（`Sources/AutomntCLI/Entry.swift`）在挂载点已被另一身份挂载同一共享时不再强制卸载；`BackgroundEvaluator` 把这种情况记为健康而非 `pathConflict`；CLI 新增连接类失败的独立退出码 78（用于父进程分类，不传递任意文本）。原因：回退成功后，「配置里的第一顺位身份」与「实际挂载身份」不再相等，原实现会卸载可用挂载或在下一轮误报冲突，属于回退落地的必要条件。
- **探测实现位置**：评估提出「或新增一个共享的 SMB 探测组件」。实际把 SMB2 帧与 DNS-SD 解析放进 `AutomntCore` 供平台层复用，CLI 仍保留自己的一套连接循环（扁平单二进制不依赖 `AutomntPlatform`），与项目既有「双实现须同步核对」的约定一致；两侧共用同一帧构造与同一解析器，未新增重复常量。
- **未验证项**：
  - 应用侧启动代理的 `WatchPaths` 改动：**已闭环**。Release 构建产物含四条路径（`scripts/verify-signature.py` 五项 PASS）；新包已安装到 `/Applications` 并经应用界面重新登记，`launchctl print gui/501/org.automnt.automnt.recovery` 与包内 plist 一致；`tailscale down` → `up` 实测启动一轮（`runs` 递增、每次 `exit(0)`、154–405ms），`background-observations.plist` 重写为两个共享 `healthy`。附带发现：**替换 App 包不会刷新 launchd 登记**，重装后必须经应用自身路径重新登记（已写入 AGENTS.md）。
  - Tailscale 中继（非直连）下的 SMB 握手耗时仍未测量，只有局域网与直连 Tailscale 数据（29–32ms）。
  - 真实「弹出后自动重挂」与回退路径的端到端效果未能执行：CLI 单共享弹出在当前环境被 `[cli-ownership:refusedAppOwner] 后台服务当前由 Automnt 应用管理` 拒绝，后台所有权属于应用。
  - 连接类 NetFS 失败实测可耗 5–7 秒，在 30 秒整轮窗口内属于评估允许的「尽力而为」范围，未做优化。

# 后续事项

- 应用侧已闭环（构建 → 安装 → 重新登记 → 真实触发实测）。剩余：真实执行一次 `tailscale up` 时同步抓后台日志，确认启动原因确实来自 `SystemConfiguration` 目录变化，而非登录/卷挂载等其它触发源。
- 由 bug-test 阶段重做原始复现：制造「首条主机探测可达但挂载连接类失败」的场景，确认本轮改挂下一顺位、状态记录为 `attached`、且只发一次成功通知；同时确认共享被拒与凭据失败仍如实上报。
- 推送 `main` 前按 SemVer 晋级补丁版本、重建 `.build/automnt` 并跑一遍自测，再随 Release 发布；当前未提交、未推送、未改版本号。
- 建议后续评估把「探测预算内 SMB 握手」的失败分类暴露到 `--status` 或诊断日志，便于用户区分「名字解析错」「不是 SMB 服务」「凭据错」。
