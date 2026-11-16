# Bug Verification: 可达性探测可被证伪，同轮回退与网络变化触发已补齐

- **Slug**: mount-failure-host-fallback
- **Tested**: 2026-11-16（局域网外复验；初验 2026-11-14，局域网内）
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified
- **Previous result**: partial（2026-11-14：成因与触发源已验证，原始复现未执行）

# 验证概要（2026-11-14 初验，已被文末局域网外复验取代）

原始症状的两个直接成因都已在本机实测中消失：探测不再被 fake-ip TUN 骗过（假地址一律判不可达，真实 SMB 服务判可达），且「连接类失败后同一轮改挂下一顺位主机」这条链路在单元测试与 CLI 内置自测中全部通过，未见回归。应用侧触发源也已闭环：新包已安装到 `/Applications`、经应用自身路径重新登记后 `WatchPaths` 与包内 plist 一致，`tailscale up` 实测启动一轮并写入 `healthy` 观测。（附带结论：重装 App 本身不会刷新 launchd 登记，必须重新登记。）

但**原始复现仍未端到端重做**：原始场景要求本机离开 NAS 所在局域网、首条主机真实挂载失败，而验证时本机在局域网内且两个共享已以局域网地址挂载（回退没有发生的理由）；后台所有权又属于应用，CLI 的 `--mount` / 弹出被 `[cli-ownership:refusedAppOwner]` 拒绝。因此按「症状成因逐环验证 + 未做端到端复现」仍判为 partial。（本节为初验结论；原始复现已于 2026-11-16 完成，最终结果见文末「局域网外复验」。）

# 执行的检查

| 检查 | 命令 / 动作 | 结果 | 说明 |
|------|-------------|------|------|
| 探测是否仍被骗（fake-ip） | `./.build/automnt --internal-host-probe <host> 445 1000` 对 `198.18.0.5`、`DX4600._smb._tcp.local`、`fake-nas-zzz._smb._tcp.local` | pass | 三者全部退出 1（不可达）。原始评估记录的相同命令全部退出 0，误判已消失。 |
| DNS-SD 解析是否生效 | 同上，对 `DX4600._smb._tcp.local`、`DX4600.local`、`100.113.52.52` | pass | 三者退出 0，耗时 0.03s。实例名经 SRV 目标解析后握手成功，未走 `getaddrinfo(实例名)`。 |
| 探测是否只认同 TCP 的假服务端 | 本机起两个监听端（一个连上即关，一个回 `\xfeSMB` 响应头），对各自端口探测 | pass | SMB stub → 退出 0；只接受 TCP 的监听端 → 退出 1。对应单元测试同一断言。 |
| 修复前误判的可解释性 | Python 直接对 `getaddrinfo` 结果建连并读 4 字节 | pass | 四个 fake-ip 地址（`198.18.0.195`、`198.18.0.5`、`2001:2::c5`、`2001:2::5`）TCP 均成功、SMB 应答均为空 —— 与「旧逻辑只看 TCP 就连过」一致。 |
| 挂载失败分类 | `./.build/automnt --internal-netfs-mount <url> <path>` | pass | `smb://192.0.2.1/share` → 78（连接类，7.25s）；`smb://198.18.0.5/share` → 78（2.22s）；`smb://DX4600._smb._tcp.local/no-such-share-automnt` → 1（共享被拒，0.38s）。连接类与共享类可区分，回退条件可判定。 |
| App 能否本地构建 | `xcodebuild ... DEVELOPMENT_TEAM=74FR87HYTH CODE_SIGN_IDENTITY="Apple Development" CODE_SIGN_STYLE=Manual build` | pass | BUILD SUCCEEDED；`scripts/verify-signature.py` 五项全 PASS；App/Helper/Worker 均为 `Apple Development: jie.zhengj@qq.com (8SDSF987N2)`，团队 `74FR87HYTH`。第一次失败是因为把证书 ID `8SDSF987N2` 当成了团队 ID。 |
| 网络变化触发源 | 临时 launchd 任务，`WatchPaths` 仅 `/Library/Preferences/SystemConfiguration`；执行 `tailscale down` → `tailscale up` | pass | `down` 未触发；`up` 触发一次（`2026-11-14 23:26:05` 写入日志）。证明应用侧补的这条监听能在 Tailscale 上线时启动后台任务。任务验后已卸载并删除。 |
| 新增 / 更新的单元测试 | `swift test` | pass | `109 tests in 30 suites passed`、`212 tests in 52 suites passed`、`33 tests in 3 suites passed`。含 `HostFallbackPolicyTests` 7 项、`RecoveryRoundTests` 4 项回退用例、`BackgroundEvaluatorTests` 2 项回退用例、`TCPReachabilityTests` 3 项探测用例。 |
| CLI 内置自测 | `./.build/automnt --self-test` | pass | `305 passed, 0 skipped, 0 failed`（修复前 302），其中含注入式回退场景：首条连接类失败、第二条成功 → `recovered` 为第二条且无失败与通知；共享被拒只尝试首条并如实上报。 |
| 项目校验脚本 | `python3 scripts/verify-swift6-concurrency.py --quiet`、`verify-localization.py --quiet`、`generate-version.py --check` | pass | 三者退出 0，版本仍为 3.5.1。 |
| `git diff --check` | `git diff --check` | pass | 无空白错误。 |
| 真实配置未被改动 | `./.build/automnt --status` | pass | 维护者的两条主机、四个共享与其挂载状态原样；验证期间未写入配置。 |
| 原始复现（离开局域网后真实挂载失败并回退） | — | not-run | 本机在 NAS 局域网内；且后台所有权属应用，CLI `--mount` 被 `[cli-ownership:refusedAppOwner]` 拒绝，无法制造真实挂载失败。 |
| 应用侧新监听是否随包生效 | `DEVELOPMENT_TEAM=74FR87HYTH CODE_SIGN_IDENTITY="Apple Development"` Release 构建后 `plutil -p <产物>/Automnt.app/Contents/Library/LaunchAgents/automnt.recovery.plist` | pass | 构建产物内已含四条路径；`scripts/verify-signature.py` 五项全 PASS。之前报「App 无法重建」是团队 ID 传错（把证书 ID `8SDSF987N2` 当成了 Team ID），非缺证书。 |
| 安装已构建的新包 | `ditto` 替换 `/Applications/Automnt.app`（旧包备份至 `/tmp/Automnt-backup-3.5.1-20261114-234930.app`），`codesign --verify --deep --strict` + `scripts/verify-signature.py` | pass | 3.5.1（3005001）安装完成，签名五项全 PASS。 |
| 新监听是否随包生效（已安装包） | `plutil -p /Applications/Automnt.app/Contents/Library/LaunchAgents/automnt.recovery.plist` | pass | 已安装包内 `WatchPaths` 含 `/Library/Preferences/SystemConfiguration`。 |
| 重装是否自动刷新 launchd 登记 | 重装后立即 `launchctl print gui/501/org.automnt.automnt.recovery` | fail（已修复） | 登记仍为旧三条，包内已是四条。跟踪结论：**重装不刷新 SMAppService 登记**，必须经应用自身路径重新登记。现已在 AGENTS.md 写入该事实。 |
| 经应用界面重新登记后的真实登记 | 设置里关闭再打开「自动挂载」（`activateAppBackground` → `HandoffCoordinator` → `AppServiceHandoffAdapter.register`），再看 `launchctl print` | pass | `WatchPaths` 与包内 plist 一致（四条）；`--check-background-service-status` → recovery `system-status=enabled`；`backend-state.plist` phase=active、generation 4→6。 |
| 真实 App 上的 Tailscale 上线触发 | 应用保持运行，`tailscale down` → 10s → `tailscale up` → 20s，监控 `launchctl print` 的 `runs` 与 `background-observations.plist` | pass | `runs` 递增（如 9→10→11），每次 `exited due to exit(0), ran for 154–405ms`；`background-observations.plist` 在 23:55:54 与 23:58:01 重写，两个共享均为 `healthy`。**之前「未在已安装 App 上验证」的缺口已补齐。** |
| 两向触发范围 | 同上，观察 `down` 与 `up` 各自的 runs 增量 | pass（修正旧结论） | 本配置下 `down` 也会启动一轮（此前临时 launchd 任务下只 `up` 触发）。可确认的是 `up` 稳定触发且观测健康；**不得再声称「down 不触发」**。 |
| 局域网内的真实弹出与重挂（GUI） | 应用内弹出 `finalhome` → 行变成「已手动弹出」→ 点「连接并打开」 | pass | 弹出后 `mount` 只剩 `personal_folder`；重挂后两个共享都在，`background-observations.plist` 两项均 `healthy`，`mount-recovery-state.plist` 两项均 `attached`。弹出抑制与手动解除在本轮真实可用。 |
| 应用持有后台时 CLI 是否仍拒绝单共享操作 | `automnt --mount smb://DX4600._smb._tcp.local/personal_folder` | pass（预期拒绝） | 仍返回 `[cli-ownership:refusedAppOwner]`，不做注册、自愈或抢占。 |
| 探测在 Tailscale 路径上的预算余量 | `--internal-host-probe 100.113.52.52 445 {1000,2000,5000}` | pass（略偏紧） | 一次 1016ms 退出 1（预算到期），其余 32–35ms 退出 0；Python 直接建连 8–96ms 后 SMB 应答超时。Tailscale 路径建连有抖动，1 秒预算属于「够用但不宽裕」。 |
| 配置迁移能否落盘（新发现，非本 bug 范围） | 观察 `automnt.log` 与 `automnt.plist` 的 `version` | **fail** | 22:13–23:25 每次启动都记 `Configuration auto-migrated`，但文件始终停在 `3.4.0`；同一秒内先 `Resource temporarily unavailable`（`config.lock` 的 EAGAIN），再 `automnt.AutomntIssue error 13`（`invalidConfiguration`）。单进程手工重放编码+隐私+原子替换全部成功，指向 CLI 自搬迁后两个进程抢同一把锁。已单列为独立缺陷，详见下文。 |

# 关键输出摘录

探测（修复后）：

```text
DX4600._smb._tcp.local             exit=0 real 0.03
fake-nas-zzz._smb._tcp.local       exit=1 real 1.00
198.18.0.5                         exit=1 real 0.01
DX4600.local                       exit=0 real 0.03
100.113.52.52                      exit=0 real 0.03
```

自建监听端（同一探测命令）：

```text
smb-stub exit=0
tcp-only exit=1
```

旧逻辑为何会误判（fake-ip 地址全部「TCP 通但无 SMB」）：

```text
DX4600._smb._tcp.local -> 198.18.0.5: tcp=OK  smb_reply=b''
DX4600._smb._tcp.local -> 2001:2::5: tcp=OK  smb_reply=b''
fake-nas-zzz._smb._tcp.local -> 198.18.0.195: tcp=OK  smb_reply=b''
```

挂载失败分类：

```text
smb://192.0.2.1/share                          exit=78  7.25s
smb://198.18.0.5/share                         exit=78  2.22s
smb://DX4600._smb._tcp.local/no-such-share     exit=1   0.38s
```

触发源（`tailscale down` 后无输出，`tailscale up` 后）：

```text
--after up:
2026-11-14 23:26:05
```

自测与单元测试：

```text
Self-tests: 305 passed, 0 skipped, 0 failed
Test run with 109 tests in 30 suites passed
Test run with 212 tests in 52 suites passed
Test run with 33 tests in 3 suites passed
```

# 残留风险

- **应用侧监听已在真实 App 上验证**（本条原先为残留风险，已关闭）：新包已安装、经应用界面重新登记、`WatchPaths` 与包内 plist 一致，`tailscale up` 实测触发一轮并写入 `healthy` 观测。
- **原始场景只在成因层面验证，没有端到端重做**（已于 2026-11-16 关闭，见下文「局域网外复验」）：离开局域网 + 首条主机真实挂载失败 + 自动落到 Tailscale 主机这一整条链，本次未执行。当前的证据是「每一环单独为真」而非「整链为真」。
- **连接类 NetFS 失败仍可能耗掉大半预算**：实测 2.2–7.3 秒后才发现是连接类失败，回退只能在本轮剩余预算内尽力而为。若首条主机同时有多个共享，极端情况下第二个共享可能没有预算回退。
- **`tailscale down` 也会触发一轮**：本配置下上下线都启动任务（与旧临时 launchd 任务的结论不同）。不构成风险，但文档与旧结论需以此为准；下线后「本该卸载或标记不可用」的场景仍由现有决策策略处理。
- **Tailscale 中继下的握手耗时仍未测量**：只有局域网与直连 Tailscale 的数据（30ms 级），中继场景是否仍落在 1 秒探测预算内未验证。

# 结论与建议（2026-11-14，已被 2026-11-16 局域网外复验取代）

不建议直接关闭该 bug，建议保持 open 并记为「成因已修复、触发源已实测、待端到端验收」。理由：探测误判、同轮回退与 Tailscale 上线触发三层均已有实测证据与自动回归测试，但原始复现（离开局域网后的真实挂载回退）仍未在真实环境跑过。

下一步建议按以下顺序补齐，补齐后可把结果改为 `verified` 并关闭：

1. 已在本机验证构建、签名、安装、重新登记与 `tailscale up` 触发（见上表）。剩下的是：真实执行一次 `tailscale down` → `tailscale up` 时同步抓后台日志，确认启动的原因确实来自 `SystemConfiguration` 目录变化（而非登录/卷挂载等其它触发源）。
2. 在离开局域网、Tailscale 在线的环境下真实触发一轮（登录或手动），确认首条主机在探测阶段就以毫秒级失败、并在同一轮改挂 Tailscale 主机的同一共享，`--status` 显示 `attached` 而非 `pending-recovery`，且只发一次成功通知。
3. 同一环境下确认共享被拒与凭据失败仍如实上报，不发生回退。
4. 上述完成后，推送 `main` 前按 SemVer 晋级补丁版本、重建 `.build/automnt` 并再跑一遍自测与 `swift test`。

# 2026-11-16 局域网外复验（原始复现已补做）

- **结果**：verified（运行时链路）。另发现 1 个 GUI 显示缺陷，见「新发现」，需单独立项。

## 环境

- 本机 `en0` = `192.168.40.46/23`，网关 `192.168.40.1`，不在 NAS 所在局域网（家中网段为 `192.168.31.0/24`）。
- Tailscale 在线：`dx4600` active，`direct 125.121.46.115:36922`（公网直连）。
- Clash Verge fake-ip TUN 在线（`utun5` = `198.18.0.1`），原始复现条件之一仍然成立。
- 配置未改动：两条主机（`DX4600._smb._tcp.local` 在前、`100.113.52.52` 在后）、`first_reachable`、两个共享同名同挂载点。

## 检查

| 检查 | 命令 / 动作 | 结果 | 说明 |
|------|-------------|------|------|
| 开机自动挂载（无人干预） | 等登录后的后台轮次，读 `mount`、`mount-recovery-state.plist`、`background-observations.plist` | pass | 09:07:20 开机 → 09:07:45 helper 启动 → 09:08:02 两个共享挂在 `//100.113.52.52/...` → 09:10:01 两项 `healthy`。局域网身份没有产生挂载尝试。 |
| 网络变化触发 | `tailscale down`（09:15:55）→ `tailscale up`（09:16:26） | pass | `down`：runs 5→6，观测 `issue=offline`、四个卷 `pending-recovery`（如实上报，无崩溃）。`up`：09:16:32 launchd 以 `xpc event` 启动 helper，09:16:40 两个共享挂到 Tailscale 主机，观测 `healthy`、状态 `attached`。 |
| 原始复现（离开局域网 + 首条主机不可用 + 自动落到 Tailscale） | 同上，全程不点界面 | pass | 首条（局域网 Bonjour 名）在探测阶段失败，同一轮改用第二条（`100.113.52.52`）挂载同一共享；两个共享都在，`--status` 四项均「已挂载」。 |
| 探测（局域网外） | `--internal-host-probe <host> 445 1000` | pass | `DX4600._smb._tcp.local` → 1（1.05s）；`100.113.52.52` → 0（0.06–0.10s）；`198.18.0.5` → 1（1.04s）；编造实例名 → 1（1.05s）。 |
| 失败分类（局域网外） | `--internal-netfs-mount <url> <path>` | pass | 不存在共享（Tailscale 主机）→ 1，0.99s；`smb://192.0.2.1/share` → 78，5.22s；局域网名 + 不存在共享 → 78，30.07s（DNS-SD 等满整轮上限）。 |
| 成功是否发通知 | 读 `mount-recovery-state.plist` 与通知队列 | pass | `notification_count=0`；现行实现只为 `shareRejected` 准备失败通知，成功不通知。初验里「只发一次成功通知」的表述已过时。 |
| 自动回归（本轮） | `swift test` | pass | 109 tests / 30 suites、212 tests / 52 suites、33 tests / 3 suites，全部通过。 |
| 内置自测（本轮） | `--self-test` | pass | `305 passed, 0 skipped, 0 failed`。 |
| 真实轮次中的共享被拒 / 凭据失败不回退 | — | not-run | 需临时改配置制造失败共享；按项目规则不手工改配置。决策由单元测试与内置自测覆盖。 |
| Tailscale 中继（非直连）握手耗时 | — | not-run | 本轮只有直连数据。 |

## 关键输出摘录

探测（局域网外）：

```text
DX4600._smb._tcp.local             exit=1 1.05s
100.113.52.52                      exit=0 0.06s
198.18.0.5                         exit=1 1.04s
fake-nas-zzz._smb._tcp.local       exit=1 1.05s
```

`tailscale up` 后的触发与挂载（unified log 与状态文件）：

```text
09:16:32.134 launchd: [gui/501/org.automnt.automnt.recovery:] launching: xpc event
09:16:32.160 Successfully spawned AutomntHelper[6091] because xpc event
09:16:40.655 exited due to exit(0), ran for 8518ms
mount-recovery-state: //100.113.52.52/finalhome mounted @ 09:16:40
background-observations: two volumes healthy, retrySuggested=false
```

失败分类：

```text
smb://100.113.52.52/no-such-share-automnt   exit=1   0.99s
smb://192.0.2.1/share                       exit=78  5.22s
smb://DX4600._smb._tcp.local/no-such-share  exit=78  30.07s
```

复验时的 `--status`（节选）：

```text
[1] DX4600._smb._tcp.local:445
    - finalhome (/Volumes/finalhome) [已挂载, 启用]
    - personal_folder (/Volumes/personal_folder) [已挂载, 启用]
[2] 100.113.52.52:445
    - finalhome (/Volumes/finalhome) [已挂载, 启用]
    - personal_folder (/Volumes/personal_folder) [已挂载, 启用]
```

## 新发现：GUI 把「兄弟主机已挂载」误报为「位置被占用」

- **现象**：两个共享实际挂在 `/Volumes/finalhome`、`/Volumes/personal_folder`（身份 `//100.113.52.52/...`）；主窗口里第一台服务器 `DX4600` 的两个共享显示橙色「位置被占用」，侧栏摘要为「有 2 个共享文件夹需要处理」，第二台服务器显示「本轮已检查」。
- **证据**：真实窗口截图，本机 `.build/evidence/outside-lan-gui-2026-11-16.png`（未入库）。
- **原因**：`apps/Automnt/AutomntApp.swift` 的 `availability(of:)` 用 SMB 身份与内核挂载表比对。挂载点上是 `//100.113.52.52/finalhome`，与配置身份 `//dx4600._smb._tcp.local/finalhome` 不相等，`isLocationOccupied` 便返回 true。后端已用 `HostFallbackPolicy.isSameShareMount` 把「同名共享由另一顺位身份挂载」判为健康，GUI 没有同步这条规则。
- **影响**：局域网外每次自动挂载成功后，用户都会看到「需要处理 / 位置被占用」的误报；点进详情只能「查看占用位置」，而占用者就是同一共享。CLI `--status` 同时显示「已挂载」，两处口径不一致。
- **建议**：单独立项修复 GUI 判定（在 `availability` / `isLocationOccupied` 识别「同一共享、同一挂载点、配置内另一主机身份」，按可用展示并注明实际经哪台主机），并移除侧栏误报计数。本次未修改任何源码。

后续（2026-11-16）：已按独立缺陷立项修复并复验，见 `.specify/bugs/gui-peer-mount-status/`（`Result: verified`）。修复后同一环境真实窗口显示两共享「可用」，侧栏不再计为待处理。

## 结论

原始症状已不再出现：离开局域网、Tailscale 在线、首条主机不可用，应用在开机或网络变化时自动把两个共享挂到 Tailscale 主机，全程无需人工操作，状态为 `healthy` / `attached`，CLI 显示已挂载。结合 2026-11-14 的成因级验证与本轮真实复现，本 bug 的验收链路已闭环，可将结果改为 `verified` 并关闭。

新增的 GUI 误报不改变挂载结果，但会让用户在局域网外误以为需要处理；建议作为独立缺陷处理，不并入本 bug。
