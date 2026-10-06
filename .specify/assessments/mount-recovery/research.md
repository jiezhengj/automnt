# Idea Research: 挂载丢失后的自动恢复机制

- **Slug**: mount-recovery
- **Created**: 2026-10-04
- **Evidence confidence (overall)**: medium-high（官方文档级证据与业界案例已补齐；仅实机行为校准与用户规模未取证）

## Users & Demand

- 维护者转述：部分用户在远程主机不稳定、挂载丢失后不知道如何重新挂载，只有重启电脑才能恢复，产品不够傻瓜化 — [source: 维护者口述 2026-10-04] (confidence: medium, cited)
- 受影响用户数量、丢挂载发生频率、支持请求占比均未量化 — [NEEDS CLARIFICATION: 问题规模] (confidence: low)

## Prior Art

- **内部（v2.x 旧方案）**：LaunchAgent 同时含 `RunAtLoad`、`StartInterval=60` 与 `WatchPaths=[/Library/Preferences/SystemConfiguration, 配置路径]`；旧 README 原文：“reevaluates policy on a 60-second `StartInterval` … the interval covers delayed network readiness and missed file events” — [source: git dd568e7 README.md；git edf17d5 diff 引 auto_mount.swift:3524-3536] (confidence: high, cited)
- **内部（3.0.0 移除决策）**：提交说明明确“纯事件驱动守护：LaunchAgent 仅通过 WatchPaths 监听系统网络变化触发，刚性排除 StartInterval 周期轮询；引入 EvaluationRetryRunner 实行有界有限重试 (<=3 次, <=10s)”；移除动因即维护者所述“用户手动卸载后没一会儿又被重新挂载” — [source: git edf17d5 commit message；维护者口述] (confidence: high, cited)
- **内部（现行兜底）**：单轮评估内的有限重试 EvaluationRetryRunner（默认 3 次、间隔 1s、总窗口 ≤10s）；挂载失败链路含有时限的 `diskutil unmount force` + `umount -f` 失效挂载清理 — [source: automnt.swift:10-14, 235-248, 1231-1242] (confidence: high, cited)
- **内部（手动恢复路径已存在）**：向导完成文案明确“后续可通过运行 'automnt' 手动执行挂载”——裸命令即触发一轮评估挂载 — [source: automnt.swift:2364] (confidence: high, cited)
- **外部先例（未联网核验）**：macOS 生态存在 AutoMounter、Mountain 等第三方网络卷自动挂载管理工具；系统自带 autofs 支持按需/自动重挂映射；macOS SMB 客户端对短暂掉线有会话级重连、长时掉线后卷转为 stale 或被系统清理 — [ASSUMPTION: web_search 不可用（环境缺 DEEPSEEK_API_KEY），凭产品通识未取证] (confidence: low)

## Market & Context

- 用户今天的替代做法是重启电脑——恰好等价于 LaunchAgent `RunAtLoad` 触发的重新评估；换言之“重启能好”本身就是“重新评估一次就能恢复”的强旁证 — [source: automnt.swift:2898 `RunAtLoad: true`；维护者口述症状] (confidence: high, cited)
- 不做的代价：远程（Tailscale 等）用户群的“傻瓜化”承诺受损，每个丢挂载事件都可能转化为支持请求或用户流失 — [source: 维护者口述] (confidence: medium, cited)

## Data & Constraints

- **触发面缺口（机械事实）**：现行守护仅由 `RunAtLoad`（登录）与 `WatchPaths`（网络配置变化）触发；SMB 会话因服务端/路径层问题丢失而网络配置未变时，没有任何触发器会重新评估——挂载丢失后无人再管，直到下次网络变化或重启。这与“只有重启电脑才行”的症状精确吻合 — [source: automnt.swift:2897-2906；维护者口述] (confidence: high, cited)
- 3.0.0 自测硬性断言“LaunchAgent dictionary strictly excludes StartInterval”——现设计原则源码头部亦写明“杜绝轮询 (无 StartInterval)” — [source: automnt.swift:10, 3468-3472] (confidence: high, cited)
- 宪法 II：后台评估必须由系统提供的服务机制**按需启动**，不得引入常驻等待进程，不得让配置入口与后台服务各自维护独立运行循环；周期性 StartInterval 是否属“按需启动”存在解释空间，任何周期化方案须先过宪法兼容性论证 — [source: .specify/memory/constitution.md] (confidence: high, cited)
- RetryPolicy（maxAttempts / intervalMs / maxTotalWindowMs）已是可配置项，但只作用于单轮评估内部，不覆盖“丢挂载之后” — [source: automnt.swift:235-248, 469-524] (confidence: high, cited)
- 凭据由系统钥匙串管理，挂载尝试失败时存在触发钥匙串/网络访问的重复成本 — [source: .specify/memory/constitution.md 项目约束] (confidence: high, cited)

## Evidence Against the Idea

1. **原方案正是被维护者亲自移除的**：存在式“缺了就挂”的自动重挂无法区分“用户主动卸载”与“网络丢失”，会覆盖用户意图；这是本想法绕不开的核心矛盾，不是历史误判 — [source: 维护者口述；git edf17d5] (confidence: high)
2. **症状可能部分是可发现性问题**：产品已有裸 `automnt` 一键重挂；若用户只是不知道，菜单引导/通知/文档的代价远小于自动重挂机制 — [source: automnt.swift:2364] (confidence: high)
3. **抖动风险**：远程不稳定主机上自动重挂可能形成“挂载→掉线→再挂载”循环，体验可能比“一次明确通知+一键恢复”更差；凭据失效时还会放大重试成本 — [ASSUMPTION] (confidence: medium)
4. **与现行设计原则有张力**：“杜绝轮询、纯事件驱动”是 3.0.0 的明确卖点（README 对外承诺），周期化回摆需要充分论证或改走事件化（挂载消失事件、健康探测）路线 — [source: automnt.swift:10；git edf17d5 README 段落] (confidence: high)
5. **规模未证**：若受影响用户面很小，完整自动恢复机制的投入产出比存疑，轻量引导可能足够 — [NEEDS CLARIFICATION]

## Gaps & Open Questions

- [NEEDS CLARIFICATION: “用户手动卸载”与“网络/服务端原因丢失”在系统层面如何可靠区分（卸载事件来源、DiskArbitration 信号、网络丢失表现为 stale 挂载还是干净卸载）？]
- [NEEDS CLARIFICATION: “只能重启电脑才行”的个案根因取证——是 stale 死卷残留、挂载点污染、凭据失效，还是纯粹不知道有手动命令？不同根因对应完全不同的解法。]
- [NEEDS CLARIFICATION: 用户手动卸载后期望语义——永久不再自动挂载该卷，还是仅本次/本会话不挂？]
- [NEEDS CLARIFICATION: 问题规模数据（频率、用户数、支持请求占比）。]
- [NEEDS CLARIFICATION: 外部工具（AutoMounter 等）如何处理手动卸载意图——本轮 web_search 不可用，需后续核验。]

## Sources

- git 仓库历史：`dd568e7`（旧 StartInterval=60 机制与旧 README 原文）、`edf17d5`（3.0.0 移除轮询的提交说明与 diff）、`e8dba58`（现行基线）
- 代码库（只读）：`automnt.swift` 行 8-20（设计原则）、235-248（RetryPolicy）、1027-1048（EvaluationRetryRunner）、1231-1242（失效挂载强制清理）、2364（手动挂载引导）、2897-2906 与 3468-3472（LaunchAgent 生成与无 StartInterval 断言）
- `.specify/memory/constitution.md`（Constitution II 与凭据约束）
- 外部网络检索：不可用（环境缺 DEEPSEEK_API_KEY），外部先例均标注 ASSUMPTION

## 补充调研（2026-10-04，应维护者要求移至裁决前完成）

### A1 系统层语义证据（手动卸载 vs 网络丢失）

- DiskArbitration 官方 SDK 头文件：`DADiskUnmountOptions` 仅含 `Force`/`Whole` 两选项，`DADiskUnmountCallback` 签名为 `(DADiskRef, DADissenterRef, context)`——**卸载事件不携带任何成因/用户意图字段**；事件层不存在现成判别信号 — [source: MacOSX.sdk System/Library/Frameworks/DiskArbitration.framework/Headers/DiskArbitration.h:68-81, 336-343] (confidence: high, cited)
- `unmount(2)` 官方文档：`MNT_FORCE` 强制卸载后“any further accesses … result in errors even if the filesystem is later remounted”——被断网的 SMB 卷以**失效（stale）挂载**长期滞留是内核语义支持的形态 — [source: man 2 mount/unmount] (confidence: high, cited)
- 产品自身历史佐证“断网=失效挂载”：AGENTS.md 公开文档标准术语“断网失效挂载的超时强制清理”，且代码含 `forceUnmountWithTimeout`（diskutil unmount force + umount -f）清 stale 死卷 — [source: AGENTS.md §3；automnt.swift:12-14, 1231-1242] (confidence: high, cited)
- **推论（重要）**：既然事件层无成因信号，意图判定只能靠推断；而业界给出的规避法是**自有动作台账**（只恢复自己清理/自己挂载的卷），完全绕开判别问题——见下方案例。残余边界：系统自行强制卸载产生的“干净缺失”会被台账漏记（安全方向失败：不恢复、但绝不覆盖意图） — [source: 下方案例 + 本条推论] (confidence: medium)

### 触发机制证据（C 类方案的更优形态）

- `launchd.plist(5)` 官方文档：**`WatchPaths` 被明确标注 "Use of this key is highly discouraged, as filesystem event monitoring is highly race-prone, and it is entirely possible for modifications to be missed"**——现行产品正依赖此键，这本身是“丢挂载后无人再管”的第二根因候选（漏事件） — [source: man 5 launchd.plist] (confidence: high, cited)
- `StartOnMount <boolean>` 官方键：“causes the job to be started every time a filesystem is mounted”——官方提供的**挂载事件触发器**，纯事件驱动、无轮询 — [source: man 5 launchd.plist] (confidence: high, cited)
- `StartInterval` 官方语义：睡眠期间的触发会丢失、作业运行中触发也会丢失——旧 60 秒轮询自身可靠性也有文档化缺陷 — [source: man 5 launchd.plist] (confidence: high, cited)
- autofs 官方机制（`automount(8)`/`auto_master(5)`）：按需触发挂载（路径访问触发）、空闲超时自动卸载（默认 1 小时）——“用时挂载、闲置回收”的官方范式；但示例映射为 NFS/-hosts/-fstab，**SMB 映射支持未证实** — [source: man 8 automount、man 5 auto_master] (confidence: high, cited；SMB 适用性 unknown)

### 案例与分享（GitHub 检索，gh CLI）

- **Ejectify for Mac**（nielsmouthaan/ejectify-macos，MIT）：睡眠/熄屏前安全卸载选定卷、唤醒后尝试重挂；**只恢复自己卸载的卷**；“eject 整盘”选项明确**禁用自动重挂**——业界把“用户弹出=意图”直接产品化为开关语义。其 issue 区存在 "Time Machine drive won't remount"（恢复失败案例） — [source: gh api repos/nielsmouthaan/ejectify-macos/readme；gh search issues remount] (confidence: high, cited)
- **Mounty**（x0054/mounty，MIT）：按 WiFi SSID 门控才尝试挂载、Keychain 存凭据、幂等（已挂载则返回现位置）、文档建议配 cron 周期调用——C 形态（轮询+上下文门控+幂等）在社区的真实写照，亦佐证“网络上下文门控”是自然意图护栏 — [source: gh api repos/x0054/mounty/readme] (confidence: high, cited)
- udiskie（coldfix/udiskie，Linux 可移动介质自动挂载器，1k+ stars）：存在按设备的忽略机制——同类意图抑制思路的又一例 — [source: gh search repos automounter] (confidence: medium, cited)

### 外部检索限制（如实记录）

- 本机 web_search 不可用（环境缺 DEEPSEEK_API_KEY）；web_fetch 对 developer.apple.com/stackoverflow.com 均因本机 DNS 解析到非公网地址被连接安全策略拒绝——**Web 页面正文未取证**；上述官方文档证据全部来自本机随系统的 man 页与 Xcode SDK 头文件（Apple 随系统分发的原始文档），案例证据来自 GitHub（gh CLI） — [source: 本机实测] (confidence: high)

### 补充调研后的开放问题收敛

- 原 A1（“能否区分手动卸载与网络丢失”）**已有文档级答案**：事件层不能；但“自有动作台账”范式（Ejectify 实证）可在不判别成因的前提下满足“误覆盖=0”。残余为实机校准项（两种缺失形态的实际出现比例），转为规格化阶段的验收取证，不再阻塞裁决。

## 修正（2026-10-05，维护者质询后）

维护者质询：“automnt 没有提供卸载 SMB 的功能；从 Finder 卸载时，台账怎么能知道是用户主动卸载？”——该质询成立，v2 的“自有动作台账”表述夸大了覆盖面，如实修正如下：

- **确认**：automnt 无法感知 Finder 卸载的意图属性（DA 事件无成因字段，前文已实锤）。台账记录的是 automnt **自己的**动作（stale 清理），不记录也无法解释用户的卸载动作。
- **台账真实覆盖面**：①automnt 自己清理的失效卷 → 记账恢复 ✓；②任何非 automnt 动手的消失（含 Finder 卸载）→ 无账 → 不恢复 → 误覆盖=0 ✓（意图保护成立）。
- **台账覆盖不到的死角（维护者点破）**：用户弹掉**已失效的死卷**（修复动作而非“不想挂”意图）→ 无账 → 永不自动恢复，除非其后发生网络上下文迁移或重启。这可能正是主症状的一半场景。
- **完整判别的真实难度**：区分“健康时弹出（意图）”与“死卷修复弹出（非意图）”需要**卸载时刻**的卷健康+主机可达性上下文；可行途径只有挂载命名空间事件观察（Apple 官方标注 WatchPaths 竞态、可能漏事件）或常驻观察会话（宪法 II 张力）。**事件层判别是硬问题，台账单独扛不住**——此结论修正 v2 对 B 可行性的过度乐观。
- **可行的产品分层语义（折衷，覆盖面逐层递减）**：
  1. 可达性迁移恢复：主机/网络上下文从不可达→可达时，恢复全部配置启用且缺失的卷（无论谁弄没的——覆盖“弹掉死卷等网络回来”场景）；
  2. 会话内抑制：健康弹出后，本可达窗口内不自动重挂（覆盖 3.0.0 抱怨场景，但弹出判定仍是启发式——卸载时刻主机可达即视为健康弹出，死卷弹出在主机已回归时会被误判）；
  3. stale 主动清理+记账恢复（产品已有清理能力，结构最稳）；
  4. 通知/一键重挂兜底（残余死角：弹掉死卷、主机一直可达、再无网络迁移）。
- **新开放问题**：抑制粘性语义（健康弹出=会话级抑制 vs 永久抑制直到显式恢复）是产品取舍，需维护者裁决——直接决定“弹出死卷”死角的大小。

## 根本前提实测取证（2026-10-05，维护者质询“究竟能不能识别”后补做）

**问题**：automnt 无弹出功能，从 Finder 弹出 SMB 时，究竟能否区分“用户弹出”与“网络丢失”？

### 实测证据（本机真实数据，只读取证）

- **丢失侧（决定性）**：过去 72 小时统一日志出现 12+ 次 `kernel (smbfs) smb_iod_start_reconnect: id N start reconnect.`（id 1→59 递增），而 `mount` 显示两卷（personal_folder/finalhome）全程在挂载表中——**网络/会话丢失不产生卸载，smbfs 原地重连，挂载不消失** — [source: `log show --last 72h`，`mount`；本机 2026-10-04 22:06 ~ 10-05 01:44] (confidence: high, cited)
- **卸载侧**：卸载事件走 `diskarbitrationd: unmount call of <private> returned (status code …)` / `unmounted disk … ongoing/failure`——与丢失侧日志**形状分明**；7 天窗口内出现一次**失败**的卸载尝试（22:09:54，紧贴 22:09:55 smbfs 重连），说明系统会尝试动死卷但不一定成功；窗口内无成功干净卸载样本 — [source: `log show --last 7d`，同上时段] (confidence: high, cited)
- **挂载表形态**：两卷 `smbfs, nodev, nosuid, mounted by jiezhengj`——“mounted by”标注挂载者，可作归属辅助 — [source: `mount`] (confidence: high, cited)

### 结论：判别可行性判定

- **事件成因字段**：不存在（DA 头文件实锤）→“读取意图”路线死亡。
- **结构性不对称**：丢失≠卸载（实测）→“缺失=曾被卸载”是可靠信号；配合 automnt 自身动作台账，**归属判定（用户弹出 vs 自身清理）是可完成的**。
- **修复弹出（弹掉死卷）判别**：卸载前的 `smb_iod_start_reconnect` 会话丢失证据可区分修复弹出与健康弹出——判别信号存在且已抓到丢失侧样本。
- **残余不确定度（如实）**：①健康弹出的干净卸载样本未捕获（7 天内无成功卸载事件，定义上应走 diskarbitrationd 通道）；②系统强制卸载的边界行为（已见失败尝试，成功时会与用户弹出同形）；③内核日志文案非公开 API，macOS 版本漂移风险。全部失败方向安全：无证据 → 保守抑制 + 通知/一键兜底。
- **待补对照实验（校准项，非可行性门槛）**：一次真实 Finder 弹出 + 一次真实断网，各抓一组日志/挂载表快照，锁定两侧形状与系统强制卸载边界。实验触碰真实挂载，需维护者批准时机。

### 对裁决的影响

可行性前提**成立且已实测**：B' 的判别层从“押注假设”升级为“三重信号（结构不对称+自账+丢失证据日志）”，go 的证据基础成立；对照实验转为规格化阶段的**验收校准项**（影响启发式阈值，不影响方案成立性）。

