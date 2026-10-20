# 网络评估与挂载流程

automnt 依序评估配置中的网络策略管道，基于目标主机 TCP 445 可达性探测进行命中决策，并在匹配后执行 SMB 挂载状态核对与按需挂载：

```mermaid
flowchart TD
    Start["触发网络挂载评估\n(RunAtLoad / 网络 WatchPaths / StartOnMount + 挂载目录 WatchPaths / 手动执行)"] --> HealthCheck["InstallState 安装完整性自检\n(损毁自动触发自愈)"]
    HealthCheck --> RetryLoop["EvaluationRetryRunner\n(窗口内有限重试循环)"]
    
    RetryLoop --> NextProfile["按优先级顺序取下一条策略"]
    NextProfile --> HostProbe["HostReachabilityProbe\n(目标主机 TCP 445 探活)"]
    
    HostProbe -- "不可达 / 超时" --> HasMoreProfiles{"是否还有后续策略?"}
    HasMoreProfiles -- "是" --> NextProfile
    HasMoreProfiles -- "否" --> WindowCheck{"重试窗口是否用尽?"}
    WindowCheck -- "否 (等待间隔)" --> NextProfile
    WindowCheck -- "是" --> ExitSilent["无策略命中\n退出码 2 (静默退出)"]
    
    HostProbe -- "端口可连通 (命中)" --> HasTargets{"策略是否包含挂载目标?"}
    HasTargets -- "目标为空" --> ExitSuccess["排他阻断命中，结束评估\n退出码 0"]
    HasTargets -- "有挂载目标" --> KernelScan["MNT_NOWAIT 内核挂载表非阻塞查询"]
    
    KernelScan --> TargetAudit{"检查每个目标挂载点状态"}
    TargetAudit -- "已挂载且来源一致" --> KeepMount["保持现有挂载"]
    TargetAudit -- "失效挂载 / 源不匹配" --> BoundedClean["有界超时强制清理\n(diskutil / umount -f)"]
    BoundedClean --> DoMount["NetFSMountURLSync 静默挂载"]
    TargetAudit -- "未挂载" --> DoMount
    
    DoMount --> SpotlightShield["注入 .metadata_never_index\n执行 mdutil -i off"]
    SpotlightShield --> Finish["挂载任务完成\n退出码 0"]
    KeepMount --> Finish
```

# 支持平台与核心原则

automnt 专为 Apple silicon（arm64）设备与 macOS 27.0 或更高版本设计。不支持 Intel（x86_64）Mac 与 macOS 27.0 之前的系统版本。

- **确定性选型**：调用 macOS 原生 `NetFSMountURLSync` 框架，使用系统钥匙串免密挂载，绝不弹窗打扰用户。
- **服务可达性优先**：彻底弃用脆弱的链路层 ARP / 网关 MAC 嗅探，全面转向传输层主机服务探测（`HostReachabilityProbe`），天然兼容多网卡、Tailscale、WireGuard 及复杂 VLAN 环境。
- **纯事件驱动无轮询**：LaunchAgent 仅监听以下三类事件，严格杜绝 `StartInterval` 定时器空转：登录（`RunAtLoad`）、系统网络配置变化（`WatchPaths`）、挂载命名空间变化（`StartOnMount` 与挂载目录增删监听）。空闲时零 CPU 与能耗占用。

## 挂载丢失自动恢复（Feature 004）

恢复判定由事件唤醒的短命执行完成，不引入常驻等待进程与固定周期唤醒。

- **三重信号判别**：按卷粒度判定“卷在表但失效（网络丢失）/ 产品自身清理 / 使用者健康弹出 / 从未挂载 / 信号不可读”，输出=纳入恢复或会话抑制。
- **失败方向单向安全**：信号缺失一律按“会话抑制 + 兜底入口”，绝不因状态损坏而误判为可恢复。
- **会话边界**：网络上下文（接口/路由/网关要素）变化或重新登录（先到者）解除抑制，并清除陈旧抑制条目。
- **有界幂等**：沿用既有 `EvaluationRetryRunner`（≤3 次、间隔 1s、总窗口 ≤10s），已挂载不重复挂载。
- **零凭据交互**：凭据经 NetFS 由系统钥匙串隐式提供，不弹对话框。
- **开关**：`auto_mount_recovery`（缺省启用），关闭则回落至现状触发集；菜单“立即重新挂载”手动入口仍可用。

内核快照保持非阻塞；卷访问与 NetFS 挂载隔离在有时限的短命子进程中。权限拒绝与探测超时不证明会话丢失，保守保留卷；明确的会话失效错误可进入死卷清理。恢复挂载保持第一个可达主机的排他范围。

附属状态文件独立保存健康挂载历史、清理账、会话抑制、通知计数和尝试结果。文件不存在视为首次使用；损坏或不可读时保守抑制。配置菜单进入前按已保存配置收敛旧服务定义；守护评估不重载自身。`WatchPaths` 竞态仍可能漏事件，恢复推迟至下次事件、登录或手动入口，无固定最长延迟。

**边界**：automnt 不提供面向使用者的弹出/卸载入口；程序可在恢复前强制清理检测到的死卷。上述“健康弹出”指识别使用者在系统（如 Finder）中发起的动作。

- **单一活动配置契约**：全系统严格归一于 `~/Library/Application Support/automnt/automnt.plist`，使用 `0600` 权限安全管理。

# 核心系统机制

## 主机服务可达性探测 (HostReachabilityProbe)

在网络评估阶段，automnt 通过标准的 BSD Socket 向指定主机的目标端口（默认 445）发起非阻塞连接探测：

```swift
struct HostReachabilityProbe {
    static func canConnect(host: String, port: Int = 445, timeoutMs: Int = 1000) -> Bool
}
```

- 探测超时通常设为 500 ~ 1000 毫秒，避免长时间阻塞。
- 连接建立成功立即判定该网络策略命中并终止后续策略探测。
- 连接拒绝（RST）、路由不可达（ENETUNREACH / EHOSTUNREACH）或超时均视为未命中。

## 事件驱动与重试调度 (EvaluationRetryRunner)

由于网络连接、Wi-Fi 关联或 VPN 隧道建立往往存在数秒握手延迟，LaunchAgent 被系统网络变更事件唤醒后，不会因首次未就绪立即退出，而是通过有限重试执行器在安全时间窗口内运行：

```swift
struct EvaluationRetryRunner {
    let policy: RetryPolicy
    func run<T>(_ work: () -> T?) -> T?
}
```

- 默认配置：最大尝试 3 次，每次间隔 1000 毫秒，最大总窗口 10000 毫秒。
- 一旦某条策略探测成功，立即返回并执行挂载。
- 若窗口用尽仍未命中任何网络，返回退出码 `2`，通知 launchd 本次事件已处理且无需采取异常动作。

## 内核挂载表非阻塞查询

严禁使用 POSIX `stat()` 或 Foundation `FileManager` 检查可能已失联的挂载目录。automnt 采用 Darwin 原生 `getfsstat` 搭配 `MNT_NOWAIT` 标志位：

```swift
func queryActiveKernelMounts() -> [ActiveMountRecord] {
    let count = getfsstat(nil, 0, MNT_NOWAIT)
    guard count > 0 else { return [] }
    var buffer = [statfs](repeating: statfs(), count: Int(count))
    let actualCount = buffer.withUnsafeMutableBufferPointer { ptr in
        getfsstat(ptr.baseAddress, count * Int32(MemoryLayout<statfs>.size), MNT_NOWAIT)
    }
    // 从 buffer 读取挂载路径与源地址
}
```

此调用直接从内核 VFS 挂载快照返回数据，无论底层网络是否中断，均在数微秒内完成，杜绝进程假死与系统彩虹球。

## 失效挂载的有界超时清理

当检测到挂载点被陈旧的失效连接占用，或当前策略需要切换到不同来源时，automnt 按照两级有限超时子进程执行清理：
1. 优先调用 `diskutil unmount force <path>`；
2. 若超时或失败，降级调用 `umount -f <path>`；
3. 全过程受到最大超时窗口严格约束，前序子进程未安全退出前绝不启动并发卸载，确保文件系统卸载动作的确定性。

## Spotlight 检索防护

挂载成功后，automnt 立即执行两级索引防护：
1. 执行 `/usr/bin/mdutil -i off <mountPath>`，请求系统元数据服务停用索引；
2. 在共享卷宗根目录创建 `.metadata_never_index` 文件，防止后续系统服务自动重建索引。

## 免编译预编译自升级与自愈

- **预编译分发**：自升级直接拉取 GitHub Release 中的 `automnt` 二进制包，绕过终端用户的本地编译环境需求。
- **原子部署与校验**：新程序下载后在临时目录执行 `--version` 语法自检，验证成功后通过文件系统原子替换安装到 `~/Library/Application Support/automnt/bin/automnt`。
- **安装状态自愈**：主程序启动时由 `InstallState` 执行自检。若发现 LaunchAgent 缺失、Shell 环境变量丢失或文件损坏，自动原地修复。

# 图形界面与 CLI 共用边界

图形界面（`apps/Automnt`）、独立 helper/worker 与 CLI 共用 `Sources/AutomntCore` 的配置、挂载、恢复、冲突与脱敏规则。GUI 不解析 CLI 输出，也不维护第二套挂载判定；两处内核调用按各自构建方式分置，修改其一必须核对另一处。

- 唯一活动配置仍是 `~/Library/Application Support/automnt/automnt.plist`；固定目录由程序解析/准备，GUI 通过精确 home-relative entitlement 访问，不要求用户选择内部目录。
- 后台自动挂载由系统按需启动的 helper/worker 执行；GUI 退出后是否继续由真实后台状态决定，界面显示实际状态而非配置意图。
- GUI 与 CLI 都提供普通弹出：GUI 在共享详情中，CLI 为 `--eject`；繁忙卷如实失败，不例行升级为强制卸载。
- 离线构建使用免费 Apple Development 签名，面向本机/同团队验证；`scripts/archive.sh` 生成 app、预编译 CLI、校验和与 manifest，App Store 路径延后。
