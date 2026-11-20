# 实施任务

**Feature**：菜单栏「快捷挂载」

**Feature ID**：006-menubar-quick-mount

**输入**：`specs/006-menubar-quick-mount/spec.md`、`specs/006-menubar-quick-mount/plan.md`

## 阶段一：判定逻辑（纯逻辑，可单测）

- [x] T001 新建 `Sources/AutomntCore/QuickMountOutcome.swift`：`QuickMountTarget`（identity/name/enabled/availability/issue）、`QuickMountFailure.Reason`（credentials/locationBusy/refused/notFinished/other）、`QuickMountOutcome`（failures、count、isEmpty、`make(from:)` 无失败返回 nil）、`QuickMountGate`（ready/noConfiguration/automaticMountingOff/backgroundNotReady/busy 与 `evaluate(...)`）。
- [x] T002 新建 `Tests/AutomntCoreTests/QuickMountOutcomeTests.swift`：覆盖失败集合边界（`.notMounted`/`.unreachable`/`.notEvaluatedThisRound`/`.suppressedForThisSession`/`.locationMismatch`/`.usable`/`.availableViaPeer` 不计入）、禁用项跳过、原因映射（含 `.failed` 按 `issue` 细分）、全成功返回 nil、门禁优先级与四种原因。

## 阶段二：模型接线

- [x] T003 `apps/Automnt/AutomntApp.swift`：新增 `quickMountOutcome`、`quickMountGate`、`quickMountSummaryText(_:)`、`quickMountGateExplanation(_:)`、失败项到服务器身份的查找，以及配置变更/轮次变化时的清空。
- [x] T004 同一文件 `tryFullRound`：执行成功后刷新状态并计算本轮结果；有失败时在窗口表面写 `notice`（同一句话），无失败时清空自己写过的摘要；不改变既有的门禁与错误处理路径。

## 阶段三：界面

- [x] T005 `apps/Automnt/Views/DetailViews.swift` 菜单栏：`Check Now` 原位改为 `Quick Mount`，按门禁置灰并在紧邻一行说明原因与下一步；失败时显示一行摘要与「未挂载的共享文件夹」子菜单（每项名称 + 原因，点击到主窗口详情）。
- [x] T006 `apps/Automnt/AutomntApp.swift` 主窗口 `CommandMenu("Servers")`：同一名称、同一门禁，保留 ⌘R。

## 阶段四：文案

- [x] T007 `apps/Automnt/Resources/Localizable.xcstrings`：新增名称、四种门禁原因、摘要、子菜单标题与五种原因，九语齐备；移除 `Check Now` 与英文说明的旧条目。

## 阶段五：文档

- [x] T008 `specs/005-swiftui-mas-gui/spec.md`：标注该文档中的「快捷挂载」指逐共享定向挂载，与 006 的全局同义不同名。
- [x] T009 `specs/005-swiftui-mas-gui/design/localization.md`：记录本项是「挂载动作不加『快捷』」基线的显式例外及理由（用户指定的名称）。
- [x] T010 新建 `specs/006-menubar-quick-mount/CHANGELOG.md`，记录逐阶段改动与验证证据。

## 阶段六：验证

- [x] T011 `swift test`（含 T002 新测试）。
- [x] T012 本地化闸门：`python3 scripts/verify-localization.py` → PASS（277 条源字符串 × 9 语言，新增 11 个 key 无一条落在“非英文与英文逐字相同”清单）。**偏离原写法**：`--require-translated` 会忽略文档化的品牌/借用词 allowlist，`Automnt`、`Notifications`、`Port`、`Name` 等既有 key 在基线状态下即失败，故用项目实际的默认模式；spec SC-004 已同步修订。
- [x] T013 `bash scripts/build-app.sh` 构建、验签与指定要求校验。
- [x] T014 实机（已装 `/Applications/Automnt.app` 并用辅助功能树读取菜单）：全成功时点「快捷挂载」后菜单无任何新增文案、`background-observations.plist` 记录该轮 healthy；执行期间该项置灰并显示「另一个操作还在进行。等它结束后再试。」，结束后恢复；用真实失败共享（临时添加 `//100.113.52.52/no-such-share-006`）复现：摘要「有 1 个共享文件夹未能挂载。」+ 子菜单「未挂载的共享文件夹」→「no-such-share-006 — 服务器拒绝了该共享」，点击该项打开主窗口并选中该共享；随后从 UI 移除该共享，配置恢复 4 条 `smb_url`、两卷重新挂载。**未逐一实测**：无配置、自动挂载关闭、后台未就绪三种置灰原因只有 `QuickMountGate.evaluate` 单测覆盖，未在实机分别制造；⌘R 未在真实窗口键位实测（同为 `quickMountGate.isReady` 门禁的同一代码路径）。

## 边界

- 不推送远端、不创建 Release、不递增版本号、不动 CLI 与配置格式。
