# Bug Assessment: 可达性探测被本机虚拟网卡骗过，挂载失败也不回退到下一条主机

- **Slug**: mount-failure-host-fallback
- **Created**: 2026-11-13
- **Updated**: 2026-11-14（回到局域网后补齐现场证据，关闭全部 NEEDS CLARIFICATION）
- **Source**: 本会话的现场调查（用户口述症状 + 本机系统日志/状态文件 + 局域网内外两轮实测）
- **Verdict**: valid
- **Severity**: high

## Report (verbatim or summarized)

用户报告：Tailscale 开着，但远程主机的卷宗没有自动挂载。

现场调查结论（2026-11-13）：

- 配置里同一台 NAS 有两条主机条目——第一条是局域网 Bonjour 名（`<nas>._smb._tcp.local`），第二条是 Tailscale IP；`mount_policy = first_reachable`；两条都启用、共享名与挂载点相同。
- 10:33:31 launchd 因「文件系统挂载」事件启动后台 helper，跑了一轮自动挂载。
- 10:33:32 对第一条主机的 TCP 探测 4ms 就“成功”，实际经 `utun5` 连到 `198.18.x`——本机 Clash Verge（verge-mihomo）的 fake-ip TUN 地址。
- 10:33:32 读取钥匙串凭据后开始真正挂载；10:34:02 失败：`mount runner failed issue=offline`。
- `background-observations.plist` 记 `issue = offline`；两个共享停在 `pending-recovery`；第二条 Tailscale IP 从未被探测或尝试。
- 之后到 17:37 没有任何一轮自动挂载（后台任务只在登录、网络配置变化、卷挂载或手动请求时启动）。

## Symptom

在局域网之外、Tailscale 在线时，自动挂载轮次被本机虚拟网卡对“任意可解析名字都可 TCP 连接”的假象骗过，选中了局域网那条主机；真实 SMB 挂载失败后，本轮既不换下一条主机，也不会紧接着重试，用户看到的最终现象是“Tailscale 全绿，但共享一直是 pending / offline”。

期望行为（维护者明确）：在家优先走局域网挂载 NAS，不在家时局域网那条探测失败后自动落到 Tailscale 那条；这是现有 `first_reachable` 的语义，不是新功能。

## Reproduction

1. 配置两条指向同一台 NAS 的主机：第一条为局域网名字，第二条为 Tailscale IP；策略保持默认 `first_reachable`；两条共享同名、同挂载点。
2. 让本机运行一个会把任意域名解析成虚拟 IP、并接受任意 TCP 连接的本机 TUN（本次现场是 Clash Verge 的 fake-ip 模式）；确认名字被解析到该虚拟段（本次为 `198.18.0.0/16`）。
3. 离开该 NAS 所在的局域网，保持 Tailscale 在线。
4. 触发一轮自动挂载（登录、插入/挂载卷、网络变化，或在界面点一次挂载）。
5. 观察：第一条主机探测“成功”→ 挂载 30 秒后 `offline` → 第二条 Tailscale IP 从未被尝试 → 共享停在 pending-recovery。

## 局域网内复测（2026-11-14，补充证据）

维护者回到局域网后（本机 192.168.31.154，en0，网关 192.168.31.1），重新实测，结论比原判断更严重：

**该名字在家里也解析不到 NAS。** `getaddrinfo("DX4600._smb._tcp.local")` 在局域网内返回 `198.18.0.5` 与 `2001:2::5`——仍是 Clash Verge 的 fake-ip。任意编造的名字（如 `fake-nas-zzz._smb._tcp.local`）同样被解析到 `198.18.0.195`，说明 fake-ip 对任意 `*.local` 名字都给答案，与是否在家无关。

| 目标 | TCP 连接 | SMB2 NEGOTIATE 应答 |
| --- | --- | --- |
| `DX4600._smb._tcp.local`（配置里写的名字） | 成功 <1ms | 立刻 EOF/reset（fake-ip 后无服务） |
| `fake-nas-zzz._smb._tcp.local` | 成功 <1ms | 立刻 EOF/reset |
| `198.18.0.5` | 成功 <1ms | 立刻 reset |
| `DX4600.local`（Bonjour SRV 目标） | 成功 25ms | 正常，73 字节，`status=0xc000000d` |
| `192.168.31.218`（NAS 真实 IPv4） | 成功 22ms | 正常 |
| `100.113.52.52`（Tailscale IP） | 成功 29ms | 正常 |
| `240e:390:57d:84f0::1cc`（SRV 给出的第二个 IPv6） | 成功连接 | **无任何应答，1007ms 超时**（黑洞地址） |

补充观察：

- 共享今天仍能挂上，是因为真正的 NetFS 挂载走系统 Bonjour 解析（`smbutil statshares` 显示对端为 `192.168.31.218:445`，SMB_3.1.1），绕开了 `getaddrinfo` 的 fake-ip。
- 直接 `mount_smbfs //user@DX4600._smb._tcp.local/hold` 成功（0.24s，系统内部解析实例名）；`mount_smbfs //user@198.18.0.5/hold` 报 `Operation timed out`（2.17s）；`mount_smbfs //user@fake-nas-zzz._smb._tcp.local/hold` 报 `No route to host`（30.02s）。
- DNS-SD 解析可用：`DNSServiceResolve("DX4600", "_smb._tcp", "local")` 2s 内返回 `DX4600.local.:445`，随后 `getaddrinfo` 给出 `240e:…:ecb0`、`240e:…::1cc`、`192.168.31.218`；`NWConnection(to: .service(...), using: .tcp)` 39ms 内完成真实 SMB 握手。编造的实例名 1s 无应答。
- `./automnt --internal-host-probe <host> 445 1000` 对 `DX4600._smb._tcp.local`、`fake-nas-zzz._smb._tcp.local`、`198.18.0.5`、`240e:…::1cc` 全部返回 0（判为可达），与上表一一对应，直接复现了误判。
- 触发器缺口复测：LaunchAgent 只监听 `NetworkInterfaces.plist`、`com.apple.airport.preferences.plist`、`/Volumes`。该 plist 的修改时间为 11 月 13 日 19:26，而 `preferences.plist` 为 11 月 14 日 21:20；utun/Tailscale 接口变化不落在监听的 plist 上。
- 代码常量：`apps/Automnt/Service/HelperEntry.swift:93` 整轮 `deadline = now + 30s`；`Sources/AutomntPlatform/MountWorkerRunner.swift:55-62` 要求剩余预算 `>0 && <=30s`。因此第一条主机的失败挂载可以耗掉整轮 30 秒。

## Suspected Code Paths

- `Sources/AutomntCore/Evaluator.swift:67-81` — `HostPriorityEvaluator.reachableHosts(stopAfterFirst:)`：`first_reachable` 在第一条探测成功后立即停止，后续主机不再探测。
- `Sources/AutomntPlatform/TCPReachabilityProbe.swift:6-18` — 后台探针只做 `NWConnection` 的 TCP 连接；本机虚拟网卡接受连接即返回 true，无法证明对端是 SMB 服务器。
- `Sources/AutomntPlatform/BackgroundEvaluator.swift:196-210` — 探测结果决定本轮参与的主机（`first_reachable` 取前 1 个），此后不再引入其他主机。
- `Sources/AutomntPlatform/BackgroundEvaluator.swift:327-347` — 挂载失败即整台主机提前返回，本轮结束；没有“换下一条同名共享”的分支。
- `Sources/AutomntCore/RecoveryRound.swift:207-210`、`218-228` — `firstReachableHost` / `relevantVolumes` 同样只让首个可达主机的卷参与本轮。
- `Sources/AutomntCLI/Entry.swift:674-720` — CLI 侧另有一套 `HostReachabilityProbe.canConnect`（`getaddrinfo` + TCP connect），同样的“TCP 通即可达”假设。
- `Sources/AutomntCLI/Entry.swift:3479-3560` — CLI 的 `runRecoveryRound` 使用同一套 `relevantVolumes` 与单次挂载副作用，同样没有跨主机回退。
- `Sources/AutomntPlatform/MountWorkerRunner.swift:63-68` — 挂载操作剩余预算被限制在 30 秒内；一次失败的 NetFS 挂载会吃掉整轮预算。
- `apps/Automnt/Service/HelperEntry.swift:92-95` — 后台整轮评估窗口固定 30 秒，和上面的 30 秒挂载上限叠加，导致“同轮再试一条主机”没有时间。
- `apps/Automnt/Resources/LaunchAgents/automnt.recovery.plist` — 触发源只有登录、`NetworkInterfaces.plist`、机场偏好、`/Volumes`；Tailscale 连接变化不在此列（次要问题）。

## Root Cause Hypothesis

高置信度。根因是**把“TCP 连接成功”当作“这台主机可用于 SMB 挂载”的充分证据**。本机存在一个会接受任意地址连接的本机 TUN（Clash Verge 的 fake-ip 模式）时，局域网那条主机的名字**无论在家还是在外**都只能解析到 fake-ip，TCP 探测必然假成功，`first_reachable` 因此选它、并让本轮只处理它的共享。真实 NetFS 挂载随后失败（30 秒后 `offline`），而实现里没有“挂载失败就换下一条同名共享”的回退分支，整轮就此结束；下一次触发仍会先探同一条主机、再次假成功，所以 Tailscale 那条永远轮不到。30 秒的整轮窗口与 30 秒的挂载上限叠加，使“同轮回退”在当前预算下也放不下。

局域网复测把“假成功”从环境特异提升为常态：该名字在任何网络下都只会拿到 fake-ip，所以只要本机开着 fake-ip TUN，局域网主机的探测判定就是恒假的真。TCP-only 探测在这台机器上不具备任何分辨力。

## Proposed Remediation

**Preferred**（维护者 2026-11-14 确认按此执行）：分两部分，先修“选错”，再补“兜底”，都不改变 `first_reachable` 的优先级语义。

1. **让可达性探测能被证伪**：TCP 连上后，在既有探测预算内发送一次 SMB2 `NEGOTIATE`，只要求收到合法的 SMB 响应头（`\xfeSMB` 前四字节）即判定可达，随后关闭连接（不做认证、不写任何状态）。本机 TUN 后面没有 SMB 服务，这一跳会在数毫秒内被重置或超时，探测如实失败。
   - 名字解析不得依赖 `getaddrinfo(实例名字符串)`：对形如 `<实例>._smb._tcp.local[.]` 的输入，先用 DNS-SD `DNSServiceResolve` 拿到 SRV 目标（如 `DX4600.local.`）再解析地址；普通主机名/IP 走原有路径。
   - 待实测项：Tailscale 中继下的握手耗时未验证（本次仅测得局域网内连 Tailscale IP 为 29–32ms），必要时放宽探测预算。
2. **补上同轮回退**：若被选中的主机在挂载阶段以连接类失败（`offline` / `timeout`）结束，且配置里还有启用主机带有同名共享（共享名与挂载点都相同），在仍有预算时改试该主机的同一共享；成功即停，不重复挂两份。`shareRejected` / `credentialFailure` / `pathConflict` **不触发回退**（维护者已确认：换一条主机无法解决共享或凭据问题，只会推迟并模糊真实错误）。
3. **预算**（维护者已确认）：保持 30 秒整轮窗口不变，不改“每主机子预算”。探测如实后，失败主机在探测阶段即以毫秒级失败，回退通常仍有充足预算；极端情况下回退只能在本轮预算内尽力而为，未完成时由下一次触发重新评估。
4. **触发源**（维护者已确认同批修复）：除现有三个触发源外，补一个能感知网络接口/路径变化的信号（例如 `State:/Network/Global/IPv4` 或接口列表变化），使 Tailscale 上下线能启动一轮评估；不新增常驻进程，不轮询。

**Alternatives**:
- 只做第 1 部分：足以修复本次报告场景（选路错误），改动面最小；但“探测通过、挂载失败”的兜底仍缺。
- 只用“记住最近成功的主机优先”替代回退：能减少重复等待，但不能修复首次选路错误，且需要持久化新状态，风险更大，不作为首选。
- 修改用户配置（只留一条主机 / 调顺序 / 改挂载范围）：会破坏“家里 LAN、外面 Tailscale”的产品意图，不作为修复手段。
- 把 30 秒整轮改为每主机子预算：维护者决定不做，优先保证登录/唤醒后的轮次时长可预期。

**Files likely to change**:
- `Sources/AutomntPlatform/TCPReachabilityProbe.swift`（或新增一个共享的 SMB 探测组件）
- `Sources/AutomntCore/Evaluator.swift`（若探测接口需要区分“TCP 可达/不可达/SMB 不可达”）
- `Sources/AutomntPlatform/BackgroundEvaluator.swift`（同轮回退）
- `Sources/AutomntCLI/Entry.swift`（CLI 探针与 `runRecoveryRound` 的同轮语义）
- 可能涉及 `Sources/AutomntCore/RecoveryRound.swift`（把“回退候选主机”作为共享规则）
- `apps/Automnt/Service/HelperEntry.swift`（若调整整轮窗口）

**Tests to add or update**:
- `Tests/AutomntPlatformTests/BackgroundEvaluatorTests.swift`：两条主机、第一条探测可达但挂载返回 `offline`、第二条挂载健康 → 断言第二条被挂载、观测为健康、只产生一次成功记录。
- `Tests/AutomntPlatformTests/TCPReachabilityTests.swift`：只接受 TCP 但不回应 SMB 的监听端 → 探测为 false；正常 SMB stub（或受控的最小响应）→ true。
- `Tests/AutomntCoreTests/MountPolicyTests.swift` / `RecoveryRoundTests.swift`：`first_reachable` 的回退候选选择保持保存顺序，`all_reachable` 行为不变。
- CLI 内置自测：用注入的 `hostReachability` 与 `applyRecovery` 复现“第一条失败、第二条成功”，断言 `RecoveryRoundOutcome.recovered`。

## Risks & Considerations

- **探测误判反向**：SMB 服务较慢或只支持旧协议时，新增握手可能把本来可用的局域网主机判为不可达。需要探测预算与失败分类可解释，并保留快速失败。
- **延迟**：每次探测多一个往返；Tailscale 中继下约数百毫秒，可接受但要计入 1 秒预算。
- **预算与等待**：整轮 30 秒窗口是当前代码常量而非规格契约；调整会影响界面等待与后台任务时长，需要单独确认。
- **重复挂载与通知**：回退必须在同一共享上成功即停，且不能让两条主机的失败记录同时触发通知；跨主机的 superseded 清理需要沿用现有规则。
- **凭据**：两条路径可能对应不同的钥匙串条目；回退使用目标主机自己的凭据，不共享第一条的失败原因。
- **CLI 与 GUI 双实现**：探测和轮次在 CLI 与后台 helper 各有一套，修复必须同步核对，否则 CLI 安装的用户仍会踩同一个坑。

## Open Questions

四项均已关闭（2026-11-14，维护者确认 + 局域网实测）：

- ~~在家庭局域网内 `getaddrinfo` 能否把实例名解析成真实地址~~ → **不能**。家里同样只会得到 Clash fake-ip；必须走 DNS-SD 的 SRV 目标。实测见上文表格与 DNS-SD 段落。
- ~~回退是否也应覆盖 `credentialFailure`~~ → **不覆盖**。维护者采纳建议：仅 `offline` / `timeout` 触发同轮回退。
- ~~整轮 30 秒窗口是否属于对外契约~~ → **保持不变**。不引入每主机子预算。
- ~~Tailscale 上下线是否触发评估~~ → **同批修复**。现有 LaunchAgent 触发源对 utun 变化不敏感，需要补一个网络路径变化的触发信号。
