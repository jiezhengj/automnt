# Bug Verification: 无证据的挂载丢失不再被判成“用户弹出”

- **Slug**: mount-loss-misjudged-as-eject
- **Tested**: 2026-11-25
- **Assessment**: [`assessment.md`](assessment.md)
- **Fix**: [`fix.md`](fix.md)
- **Result**: verified

## Summary

原始症状在本机现场按 assessment 的复现步骤重跑后不再出现：卷在无弹出证据的情况下从挂载表消失，启动应用后由当轮评估自动挂回，无需任何手动操作；反方向（应用运行期间真实卸载）仍被识别为弹出且不被重挂。回归面 `swift test`、`automnt --self-test`、本地化闸门与 app 构建全部通过。

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | 退出应用 → `diskutil unmount /Volumes/personal_folder`（模拟无证据的静默丢失，记录仍为 `attached` + `ever_healthy_mounted=true` + 无证据位）→ `open -a /Applications/Automnt.app` | pass | 启动轮即自动挂回；随后一轮提交健康状态，记录回到 `attached`、`attempt_count 0`、观测 `healthy`。修复前同一形状（2026-11-24 现场）是整日 `suppressed`、零重挂 |
| Reproduction (negative direction) | 应用运行中 `diskutil unmount /Volumes/personal_folder` → 读状态文件 → 点「快捷挂载」 | pass | `automnt eject-observe recorded identity=//100.113.52.52/personal_folder`；记录写 `suppressed` + `suppression_has_evidence=true`；再点快捷挂载**没有**重挂该共享 |
| New / updated tests | `swift test` | pass | AutomntCoreTests 109、AutomntPlatformTests 221、AutomntCLITests 33；含新增的 `.lostWhileHealthy`、证据位旧文件解码、无证据抑制恢复一次、探活超时迁移、`.ejected` 归类 |
| Regression suite | `./automnt --self-test` | pass | 305 passed, 0 skipped, 0 failed |
| Lint / type-check（本地化与构建闸门） | `bash scripts/build.sh`、`bash scripts/build-app.sh` | pass | 本地化 277 条源字符串 × 9 语言 PASS；5 项签名/密封校验 PASS；版本仍 3.6.0（未递增） |

## Output Excerpts

```
Self-tests: 305 passed, 0 skipped, 0 failed
Test run with 33 tests in 3 suites passed after 4.442 seconds.
automnt eject-observe recorded identity=//100.113.52.52/personal_folder
post-startup record: pending-recovery | evidence: False | attempts: 1
record: attached | attempts: 0
obs: [('finalhome', 'healthy'), ('personal_folder', 'healthy')]
```

## Residual Risks

- 中继路径探活仍偏紧：本机 Tailscale 走 DERP(sfo)、单程约 325 毫秒，3000 毫秒预算在冷握手时偶尔仍失败（预热后 `nc` 约 1.3 秒可通）。失败后下一轮事件或手动入口仍可恢复，未纳入本次修复。
- 验证过程中观察到一次瞬时 `mount runner failed issue=signalUnavailable`：挂载实际已建立，但健康提交时卷尚未在挂载表中可见；下一轮评估自行收敛为 `attached`。此为挂载/提交时序竞态，与本修复无关，未单独处理。
- 已知并接受的残余取舍：应用未运行期间用 Finder 弹出，下次评估会按丢失处理并重挂一次（维护者 2026-11-25 裁定接受）。
- 现场遗留 `//100.113.52.52/no-such-share-006` 脏记录（Feature 006 测试残留，已从配置移除）仍在状态文件中，无对外影响。

## Recommendation

Close the bug — 原始症状在真实环境中既重现过（2026-11-24）也在修复后按同一路径验证消失，反方向的弹出保护未被削弱。文档侧已同步修订 `specs/004-mount-loss-recovery/spec.md`（FR-002/003/004、新增 FR-011）、`contracts/mount-recovery-contract.md` 与 `data-model.md`，避免代码与契约脱节。本次未提交、未推送、未递增版本号。
