# Bug Fix: 兄弟主机承载的共享不再误报「位置被占用」

- **Slug**: gui-peer-mount-status
- **Fixed**: 2026-11-16
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

GUI 的可用性判定原来只认「配置身份 == 内核挂载身份」，把回退成功后由配置内另一条主机承载的同一共享当成第三方卷占用。现在 Core 新增「配置内兄弟主机承载」识别，界面将其呈现为「可用」，并只在真正承载挂载的条目上提供弹出/挂载；真正的第三方占用仍报「位置被占用」。

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Sources/AutomntCore/HostFallbackPolicy.swift` | modified | 新增 `peerIdentityProvidingSameShare`：要求挂载身份属于配置内另一条主机、共享名与挂载点都与当前共享相同；不访问网络 |
| `Sources/AutomntCore/OperationPresentation.swift` | modified | `TargetAvailability` 增加 `.availableViaPeer`，并增加 `isAvailableAtConfiguredPath`、`isMountedByIdentity` 两个语义属性，把「可打开」与「可弹出」分开 |
| `Sources/AutomntCore/ShareDetail.swift` | modified | `ShareDetail.Status.availableViaPeer`；`ShareDetailBuilder.build` 增加 `mountedByPeer`（默认 false）；`nextStep`、`isUsableAtExpectedPath`、`DetailActionPolicy` 按新状态处理（仅打开，不弹出/挂载） |
| `apps/Automnt/AutomntApp.swift` | modified | `availability(of:)` 在占用判定前返回 `.availableViaPeer`；`isLocationOccupied` 排除兄弟身份；`detail(of:)` 用兄弟身份生成详情，实际位置即配置路径 |
| `apps/Automnt/Views/MainWindowView.swift` | modified | 行状态符号/颜色/文案、行菜单与详情主操作接入新状态；详情打开动作对兄弟承载直接打开路径（否则 `FinderAccess` 会按身份拒绝并报占用） |
| `apps/Automnt/Views/DetailViews.swift` | modified | 菜单栏「在 Finder 中打开」对兄弟承载可用且打开路径；「挂载」不重复执行；「弹出」只在本身份挂载时可用 |
| `Tests/AutomntCoreTests/ShareDetailTests.swift` | modified | 新增兄弟承载详情与动作用例 |
| `Tests/AutomntCoreTests/HostFallbackPolicyTests.swift` | modified | 新增兄弟身份识别边界用例 |
| `Tests/AutomntCoreTests/TargetAvailabilityTests.swift` | added | 锁定「可用但不可按本身份弹出」的动作边界 |

## Diff Highlights (optional)

Core 识别规则只接受「配置里的另一条主机」：

```swift
public static func peerIdentityProvidingSameShare(_ share: SMBShareConfig,
                                                  mountedIdentity: String,
                                                  in configuration: AutomntConfig) -> String? {
    guard let ownIdentity = smbResourceIdentity(share.smbURL),
          mountedIdentity != ownIdentity else { return nil }
    for host in configuration.hosts {
        for other in host.shares {
            guard let identity = smbResourceIdentity(other.smbURL),
                  identity == mountedIdentity,
                  sharesMatch(share, other) else { continue }
            return identity
        }
    }
    return nil
}
```

GUI 判定与详情：

```swift
if path == .smb(identity: identity) { return .usable }
// The same share on another configured host already carries this mount point;
// the path is usable, and this entry must not be reported as a location conflict.
if peerIdentityProvidingSameShare(share) != nil { return .availableViaPeer }
```

```swift
if case .smb(let mounted) = path {
    return mounted != identity && peerIdentityProvidingSameShare(share) == nil
}
```

详情动作只保留打开：

```swift
case .availableViaPeer:
    // The path is usable, but the mounted identity belongs to another configured
    // entry. Opening is safe; eject/mount stay with the entry that owns it.
    if detail.actualMountPoint != nil { actions.insert(.openInFinder) }
```

## Tests Added or Updated

- `Tests/AutomntCoreTests/HostFallbackPolicyTests.swift::peerIdentityRequiresConfiguredSiblingShareAtSameMountPoint` — 要求配置内兄弟条目、排除本身份、排除未配置身份、排除不同挂载点。
- `Tests/AutomntCoreTests/ShareDetailTests.swift::peerCarriedMountIsAvailableWithoutEject` — 兄弟承载时状态可用、可在配置路径使用、只提供打开，不提供弹出/挂载/使用实际位置；未挂载时该标志不改变状态。
- `Tests/AutomntCoreTests/TargetAvailabilityTests.swift::peerCarriedMountIsAvailableButNotMountedByIdentity` — 锁定「可用但不可按本身份弹出」的动作边界。

## Local Verification

- Commands run: `swift test` → 109 tests / 30 suites、215 tests / 53 suites、33 tests / 3 suites 全部通过（最终连续两次运行一致）。
- Commands run: `bash scripts/build.sh` → CLI 重建通过（含本地化与 Swift 6 门禁）；`./.build/automnt --self-test` → `Self-tests: 305 passed, 0 skipped, 0 failed`。
- Commands run: `python3 scripts/verify-localization.py` → PASS（未新增用户文案，复用现有 “Available”；九语文案仍齐全）。
- Commands run: `bash scripts/build-app.sh` → `** BUILD SUCCEEDED **`；签名与指定要求校验 PASS，指定要求仍固定在 `Apple Development: jie.zhengj@qq.com (8SDSF987N2)`。
- Install: 备份旧包到 `/tmp/Automnt.app.bak`，用 `ditto` 替换 `/Applications/Automnt.app`；`codesign --verify --deep --strict` 通过，`Authority` 与上一版一致，未触发证书变化。
- Manual checks（局域网外、Tailscale 在线、共享挂在 `100.113.52.52` 上）：
  - 修复前真实窗口：DX4600 两个共享橙色「位置被占用」，侧栏「有 2 个共享文件夹需要处理」（`.build/evidence/outside-lan-gui-2026-11-16.png`）。
  - 修复后真实窗口：两个共享绿色「可用」，侧栏无待处理提示（`.build/evidence/outside-lan-gui-after-fix-2026-11-16.png`）；可访问性树读出两个开关均为开启、两行为「可用」。
  - 展开 finalhome 详情：显示「挂载位置 /Volumes/finalhome」，操作只有「在 Finder 中打开」；点击后 Finder 选中 `finalhome` 卷，没有出现占用错误。
  - 挂载事实未变：`mount` 仍显示 `//jiezhengj@100.113.52.52/...` 两条 smbfs。

## Deviations from Assessment

- 评估提出的文件清单未包含 `TargetAvailabilityTests.swift`；实现时补了这个用例，用于锁定菜单栏/行菜单依赖的两个语义属性。
- 评估写「兄弟主机承载按可用显示」；实现进一步让兄弟承载优先于「自动挂载关闭」状态（自动化关闭但兄弟承载仍可用时显示可用，自动安排仍显示已关闭），避免把可用共享显示成「关闭且可弹出」的错误组合。

## Follow-ups

- 行右键菜单与菜单栏附加项未能在本次真实窗口里用辅助功能打开（`AXShowMenu` 返回 `kAXErrorCannotComplete`），其条件由单元测试与代码审阅覆盖；如需要，可再用物理右键补验一次。
- 若后续要在行内注明「经哪台主机承载」，需要新增用户文案并补齐九语本地化；本次按评估约定复用「可用」。
- 本次只验证中文界面；其他语言的「可用」沿用既有翻译，未重打真实窗口。
