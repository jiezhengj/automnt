# Bug Assessment: 局域网外自动挂到兄弟主机后，GUI 把可用共享误报为「位置被占用」

- **Slug**: gui-peer-mount-status
- **Created**: 2026-11-16
- **Source**: 本会话 2026-11-16 局域网外复验（真实窗口截图 + 本机状态文件 + 源码）
- **Verdict**: valid
- **Severity**: medium

## Report (verbatim or summarized)

维护者在局域网外完成 `mount-failure-host-fallback` 的复验后确认：两个共享已由后台自动挂到 Tailscale 主机（`//100.113.52.52/finalhome`、`//100.113.52.52/personal_folder`），`background-observations` 两项 `healthy`，CLI `--status` 四个配置条目全部显示「已挂载」；但主窗口里第一台服务器 `DX4600` 的两个共享显示橙色「位置被占用」，侧栏摘要为「有 2 个共享文件夹需要处理」。

维护者选择立即修复（2026-11-16），并要求不把界面改回「需要处理」的误报。

## Symptom

同一共享在配置里有两条主机条目（局域网 Bonjour 名在前、Tailscale IP 在后，同名共享、同挂载点）。离开局域网后，后台按 `first_reachable` 把共享挂到 Tailscale 身份上。此时首选主机的条目在界面上被标成「位置被占用」，侧栏计入待处理问题；实际挂载点可用、共享可打开。

期望：配置路径上的共享由同一共享的兄弟主机身份承载时，界面按「可用」呈现，不再计入问题；普通弹出、挂载等绑定身份的动作不应出现在没有承载该挂载的那条条目上。

## Reproduction

1. 配置两条指向同一台 NAS 的主机：第一条为局域网 Bonjour 名，第二条为 Tailscale IP；两条共享同名且同挂载点；策略保持 `first_reachable`。
2. 离开 NAS 所在局域网，保持 Tailscale 在线；让后台自动挂载（登录、网络变化，或等既有挂载）。
3. 共享实际挂在 Tailscale 身份上；打开主窗口，选中第一条（局域网名）服务器。
4. 观察：两个共享行显示橙色「位置被占用」，侧栏显示「有 2 个共享文件夹需要处理」；点开详情只有「查看占用位置」，而占用者就是同一共享。

已在本机真实窗口复现（2026-11-16 09:19/09:25，截图存于 `.build/evidence/outside-lan-gui-2026-11-16.png`）。

## Suspected Code Paths

- `apps/Automnt/AutomntApp.swift:747` `availability(of:)` — 仅当 `mountPathState(at:)` 的身份等于配置身份时判「可用」；兄弟主机身份不等于配置身份，继续向下判定。
- `apps/Automnt/AutomntApp.swift:774` `isLocationOccupied(_:)` — 挂载点是另一个 SMB 身份即返回 true，于是落到 `.locationOccupied`。
- `apps/Automnt/AutomntApp.swift:802` `isException(_:)` — `.locationOccupied` 被计为需要处理的问题，侧栏摘要由此产生。
- `Sources/AutomntCore/ShareDetail.swift:105` `ShareDetailBuilder.build` — 详情同样以「是否本身份挂载」判定 `.healthy`，兄弟主机挂载会落到 `.locationOccupied`。
- `Sources/AutomntCore/ShareDetail.swift:165` `DetailActionPolicy.available` — `.locationOccupied` 只给「查看占用位置」，与真实情况不符。
- `apps/Automnt/Views/MainWindowView.swift:1289`、`apps/Automnt/Views/DetailViews.swift:1156` — 行菜单与菜单栏的打开/挂载/弹出条件都以 `availability == .usable` 为准，需要区分「配置路径可用」与「本身份已挂载」。
- `Sources/AutomntCore/HostFallbackPolicy.swift:139` `isSameShareMount` — 后端已有「同一共享由另一身份挂载」的识别，但只按共享名比较，未要求该身份属于配置内的另一条主机，也未被 GUI 使用。

## Root Cause Hypothesis

（confidence: high）

回退/兄弟主机挂载成功后，挂载点上的 SMB 身份是配置里另一条主机的条目。GUI 的可用性判定以「配置身份 == 内核挂载身份」为唯一依据，没有把「配置内另一条同名同挂载点主机的身份」视为同一共享；随后 `isLocationOccupied` 把该身份当成「另一个卷」，界面因此把成功挂载报成位置冲突。后台评估（`BackgroundEvaluator`）已按 `HostFallbackPolicy.isSameShareMount` 把同一共享的兄弟身份挂载记健康，GUI 未同步该规则，形成前后端口径不一致。

## Proposed Remediation

**Preferred**: 在 Core 增加「兄弟主机身份」识别函数，要求三个条件同时成立：挂载身份 != 本共享身份、该身份确属配置内另一条主机的共享、共享名与挂载点与本共享相同。GUI 据此新增一个展示状态 `availableViaPeer`（配置路径可用、由配置内另一主机承载）：

- 行状态显示绿色「可用」（复用现有文案，不新增本地化键），不计入问题数量；
- 详情状态为可用，打开动作打开配置路径；不提供普通弹出/挂载（这两个动作绑定配置身份，兄弟主机的挂载应由承载它的那条条目操作）；
- 菜单栏同样区分「配置路径可用」（可打开、不可重复挂载）与「本身份已挂载」（可弹出）；
- 地点占用判定在先排除兄弟主机身份，保持真正的第三方卷冲突仍显示「位置被占用」。

只改显示与动作可见性，不改变挂载、回退、恢复规则；不新增用户可见文案，避免触碰九语本地化门槛。

**Alternatives**:
- 让兄弟主机身份挂载直接复用 `.usable`：改动最小，但行菜单与菜单栏会对错误的身份提供「弹出」，并把配置身份与真实挂载身份混为一谈；不采用。
- 在界面隐藏首选主机条目：会改变用户配置视图与排序语义，超出缺陷修复范围；不采用。

**Files likely to change**:
- `Sources/AutomntCore/HostFallbackPolicy.swift`
- `Sources/AutomntCore/OperationPresentation.swift`
- `Sources/AutomntCore/ShareDetail.swift`
- `apps/Automnt/AutomntApp.swift`
- `apps/Automnt/Views/MainWindowView.swift`
- `apps/Automnt/Views/DetailViews.swift`
- `Tests/AutomntCoreTests/HostFallbackPolicyTests.swift`
- `Tests/AutomntCoreTests/ShareDetailTests.swift`

**Tests to add or update**:
- 兄弟主机身份识别：同名同挂载点、排除本身份、排除未配置身份、挂载点不同不识别。
- 详情状态：`mountedByPeer` 时状态为 `availableViaPeer`、`isUsableAtExpectedPath` 为真、打开动作存在、不提供弹出/挂载；未挂载时该标志不改变状态。
- 既有 `locationOccupied`、`locationMismatch`、`healthy` 用例保持通过。

## Risks & Considerations

- **第三方卷同名冲突**：只按共享名识别会误把用户自己的同名卷当成兄弟主机；实现必须同时要求该身份来自配置内的另一条主机条目（本次采用）。
- **动作归属**：兄弟身份挂载的弹出/挂载必须留给承载它的那条条目，避免对错误身份执行动作。
- **可访问名称与文案**：复用「可用」，不新增字符串；若后续要在行内注明「经哪台主机」，需要另做文案与九语本地化。
- **真实窗口验收**：必须在本机安装新包后、局域网外真实窗口确认误报消失，且真正第三方占用仍显示「位置被占用」。

## Open Questions

无。维护者已选择立即修复，并接受「兄弟主机承载时按可用显示、动作留给承载条目」的语义。
