# Bug Verification: 兄弟主机承载的共享不再误报「位置被占用」

- **Slug**: gui-peer-mount-status
- **Tested**: 2026-11-16
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

在局域网外安装并启动修复后的构建后，原始症状不再出现：由 `100.113.52.52`（Tailscale）承载的共享在 `DX4600` 条目下显示绿色「可用」，侧栏不再出现「有 2 个共享文件夹需要处理」；挂载事实未变，回归套件全部通过。真正第三方卷占用与右键菜单未在真实窗口重建/打开，见残留风险。

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | 局域网外，`ditto` 安装 `.build/xcode/Build/Products/Release/Automnt.app` 到 `/Applications`，`open -a Automnt`，查看真实主窗口（窗口 `w-364`） | pass | DX4600 的 finalhome、personal_folder 均为「可用」，无橙色图标；侧栏无待处理提示 |
| Reproduction (pre-fix 对照) | 同环境修复前窗口截图 `.build/evidence/outside-lan-gui-2026-11-16.png` | pass（对照） | 两共享「位置被占用」，侧栏「有 2 个共享文件夹需要处理」 |
| Mount facts | `mount \| grep smbfs`；`automnt --status` | pass | 仍为 `//jiezhengj@100.113.52.52/finalhome`、`//jiezhengj@100.113.52.52/personal_folder`；CLI 四条配置均「已挂载」 |
| New / updated tests | `swift test` | pass | 215 tests / 53 suites（含新增 3 个用例）、109 tests / 30 suites、33 tests / 3 suites 全部通过 |
| Regression suite | `swift test`（同上，连续两次完整运行） | pass | 无失败用例；一次早期运行出现 1 个未复现的瞬时失败，见残留风险 |
| CLI self-test | `bash scripts/build.sh` → `./.build/automnt --self-test` | pass | 构建含本地化与 Swift 6 门禁；`Self-tests: 305 passed, 0 skipped, 0 failed` |
| Localization gate | `python3 scripts/verify-localization.py` | pass | 未新增文案键，复用现有 “Available” |
| Build / signature | `bash scripts/build-app.sh` | pass | `** BUILD SUCCEEDED **`；签名、指定要求校验通过，`Authority=Apple Development: jie.zhengj@qq.com (8SDSF987N2)` 未变 |
| Detail action | 展开 finalhome 详情，读取可访问性树并点击「在 Finder 中打开」 | pass | 详情只列「挂载位置 /Volumes/finalhome」与「在 Finder 中打开」；点击后 Finder 选中 `finalhome`，无占用错误 |
| Row context menu | `agent-desktop right-click`（辅助功能 `AXShowMenu`） | not-run | 返回 `kAXErrorCannotComplete (-25204)`，未能打开菜单；应用保持响应，无副作用 |
| Menu bar extra | — | not-run | 未在真实窗口展开菜单栏附加项逐一核对 |

## Output Excerpts

安装与运行：

```text
Identifier=org.automnt.automnt
Authority=Apple Development: jie.zhengj@qq.com (8SDSF987N2)
```

挂载事实（修复前后一致）：

```text
//jiezhengj@100.113.52.52/finalhome on /Volumes/finalhome (smbfs, ...)
//jiezhengj@100.113.52.52/personal_folder on /Volumes/personal_folder (smbfs, ...)
```

可访问性树（修复后窗口）：

```text
switch '此服务器参与自动挂载' value= '1' states= ['checked']
switch '自动挂载此共享文件夹, finalhome' value= '1' states= ['checked']
switch '自动挂载此共享文件夹, personal_folder' value= '1' states= ['checked']
button 'finalhome, 可用'
button 'personal_folder, 可用'
TEXT: '挂载位置'
TEXT: '/Volumes/finalhome'
BUTTON: '在 Finder 中打开'
```

测试汇总：

```text
Test run with 109 tests in 30 suites passed after 0.876 seconds.
Test run with 215 tests in 53 suites passed after 4.857 seconds.
Test run with 33 tests in 3 suites passed after 0.038 seconds.
Self-tests: 305 passed, 0 skipped, 0 failed
```

截图：

- 修复前：`.build/evidence/outside-lan-gui-2026-11-16.png`（橙色「位置被占用」、「有 2 个共享文件夹需要处理」）。
- 修复后：`.build/evidence/outside-lan-gui-after-fix-2026-11-16.png`（两行绿色「可用」，无待处理提示）。
- 修复后详情：`.build/evidence/outside-lan-gui-after-fix-detail-2026-11-16.png`（展开 finalhome：「挂载位置 /Volumes/finalhome」，操作只有「在 Finder 中打开」）。

## Residual Risks

- 真实「第三方卷占用配置路径」未在本次环境重建（需要另一卷占据同一挂载点）；该分支由既有 `locationOccupied` 用例覆盖，未见回归。
- 行右键菜单与菜单栏附加项未能在真实窗口打开（辅助功能限制），其打开/挂载/弹出条件由单元测试与代码审阅覆盖。
- 一次早期完整测试运行出现 1 个未记录用例名的瞬时失败，随后两次完整运行均通过且未修改相关代码；判断为环境/时序性偶发，仍需在后续持续测试中留意。
- 本次只实际查看了中文界面；其他语言的「可用」沿用既有翻译，未重打真实窗口。
- 若用户之后从配置里删除承载挂载的那条兄弟主机，同一挂载会重新按「位置被占用」显示（此时它已不再是配置内条目），这是当前规则的预期边界。

## Recommendation

关闭该缺陷。修复在局域网外真实窗口端到端复验通过，挂载与后台服务未受影响；剩余未验证项（第三方占用、右键菜单/菜单栏）已在残留风险中如实标注，不阻断结案。
