# 脱敏诊断快照与用户导出（T034 核心部分）

本轮实现 `DiagnosticSnapshot` / `DiagnosticExporter`（此前全仓无实现）。所有命令均在 `/Users/jiezhengj/Documents/Project/automnt` 实际执行。

## 本轮范围与明确不做的事

**已实现**：快照生成 + 脱敏 + 纯内存预览 + 用户明确指定目的地后的导出。

**明确未实现（按任务边界）**：

- **未实现日志保留期限/容量/清理政策**。这是 T003 的范围，其通过条件写明「未决定不落地日志保留政策」，维护者尚未决定。本实现不设置任何 TTL、上限、轮转或定时清理。
- **未实现任何自动上传、遥测、第三方分析或长期留存**。导出只发生在调用方显式给出目的 URL 时；预览是纯内存操作，不写盘。全程无网络代码。
- 未引入第三方依赖；未改动配置格式。

**未做 GUI 接线（有意）**：`apps/Automnt/Views/DiagnosticsView.swift` 是新增文件，加入 app target 需要编辑 `apps/Automnt/Automnt.xcodeproj/project.pbxproj`（不在本任务写范围内），且会引入新的用户可见文案。任务描述允许「若动 UI 会影响现有构建，就只做 Core」，因此本轮只交付 Core 引擎，未改 `AutomntApp.swift`、未新增文案。app target 仍能编译（下节实测）。

## 模型字段清单

`DiagnosticSnapshot`（`schemaVersion = 1`，Codable，顶层字段恰为 9 个）：

| 字段 | 类型 | 内容 |
| --- | --- | --- |
| `schemaVersion` | Int | 固定 1 |
| `generatedAt` | Date | 快照生成时刻 |
| `product` | DiagnosticProductInfo | `version`（取自 SSOT `AutomntBuildVersion.value`）、`channel`（cli/app/unknown） |
| `signature` | DiagnosticSignatureSummary | `state`（verified/unverified/unavailable）、`requirementSatisfied` |
| `system` | DiagnosticSystemSummary | `macOSVersion`、`architecture` |
| `authorization` | DiagnosticAuthorizationSummary | `directoryAuthorized`、`bookmarkPresent`、`scopedAccessGranted`（只有布尔，无路径） |
| `automation` | DiagnosticAutomationSummary | 自动化/恢复开关、主机数、共享数、启用共享数、通知声音偏好 |
| `volumes` | [DiagnosticVolumeStatus] | 每卷 `target`（替身）、`status`、`issue`、`observedAt` |
| `events` | [DiagnosticEvent] | `at`、`category`、`detail`（已过脱敏器） |

不含的字段（负向断言覆盖）：密码、用户名、主机/IP、共享名、文件路径、原始书签字节、Keychain reference、计算机名、序列号、team identifier。`authorization` 只暴露布尔状态，不暴露授权目录路径；`signature` 不暴露 team ID 与 requirement 文本。

## 脱敏规则

`DiagnosticRedactor` 逐次导出新建，**不持久化、不跨导出复用**：

1. **已声明值替换**：主机、别名、共享名、`smb_url`、挂载点、卷 identity/actualPath、`additionalSensitiveValues`（如错误文本里的用户名）在**任何文本渲染之前**先注册进映射表。注册顺序固定（主机 → 共享 → 观测 → 附加），因此替身编号确定。
2. **正文替换**：事件 `detail` 先按已知值替换（**按长度降序**，避免短值切断长值），再用残差模式兜底：
   - `smb://…` → `<endpoint#n>`
   - `//host/share` UNC → `<endpoint#n>`
   - `/Volumes|/Users|/private|/var|/tmp` 路径 → `<path#n>`
   - IPv4 字面量 → `<host#n>`
   - `*.local` 主机名 → `<host#n>`
3. **替身语义**：按**值**为键。同一真实值在一次导出内始终映射到同一替身（便于关联定位）；不同真实值映射到不同替身。同值不同类别不会产生两个替身，避免同一目标看起来像两个。
4. **不长期跟踪**：映射表随本次导出结束即消失，无任何落盘或跨次复用。

**泄漏门（fail closed）**：`preview` 渲染完成后，用 `containsSensitiveValue` 复查输出是否仍含任一已声明敏感值（忽略长度 < 3 的值以避免端口/单字母误报）。命中即抛 `DiagnosticExportError(.leakDetected)`，**不返回预览**，错误里也不含该值本身。

## 负向测试证据

`Tests/AutomntCoreTests/DiagnosticSnapshotTests.swift`（10 项，`@Suite(.serialized)`）。

Fixture 通过产品 API 构造（`AutomntConfig`/`HostConfig`/`SMBShareConfig`，无手写 plist），含 15 个真实值：`fileserver.example.internal`、`Studio NAS`、`Design Assets`、`Design%20Assets`、`/Volumes/Design Assets`、`Archive`、`10.20.30.40`、`/Volumes/Archive`、`backup.local`、`Vault`、`/Volumes/Vault`、`svc-mount-user`、`Team`、`/srv/mounts/vol-7f3a`、`printer-2f.local`、`private-nas.example`、`old-server.example`、`standalone-nas`。

关键断言：

- `exportContainsNoRawSensitiveValueInAnyFormat`：JSON 与 text 两种格式下，逐一断言 18 个真实值（含用户名的 `additionalSensitiveValues`）**都不出现**（大小写不敏感）；并断言无 `smb://` 残留、无 IPv4 正则命中、无 `*.local` 命中、无 `/Volumes/` 残留。
- `placeholdersAreStableWithinOneExportAndDistinctAcrossValues`：同一主机/路径在正文里重复出现时替身计数 ≥2 且完全相同；不同真实值替身不同；同值不同 kind 仍是同一替身；`substitutedValueCount` 精确。
- `credentialBearingFieldsNeverAppear`：把 `password hunter2xyz` 与用户名塞进事件正文后，两个秘密值均不出现；顶层键名不含 password/username/credential/bookmark/keychain/secret/token；输出无 `bookmarkData`/`SecKeychain`。
- `previewWritesNothingToDisk`：预览前后工作目录必须为空；并清空后复查进程临时目录中 `automnt-diagnostic*` 正则文件为空（预览未偷写）。
- `exportWritesOnlyToTheExplicitDestination`：未给目的地前文件不存在；`export` 后内容等于预览文本且仍无敏感值。
- `leakGateRejectsAnOutputThatStillContainsADeclaredValue`：构造一个**确实未脱敏**的快照，`preview` 必须抛 `.leakDetected`；检测器大小写不敏感；长度 <3 的值不误报。
- `emptyAndUnconfiguredStatesStillExportWithoutCrashing`：空输入 / 空配置 / 空事件三种状态，两种格式都能导出且不崩。
- `redactorHandlesValuesItWasNotToldAbout`：未声明的 IP 与 `/Volumes/Client Work` 由残差模式替换；同值两次出现同替身。
- `modelCarriesOnlyTheContractedSummaryFields`：顶层键集合精确等于 9 个契约字段；Codable 往返相等；`version` 等于 SSOT。
- `repeatedBuildsUseTheirOwnMappingAndDoNotPersistState`：两次独立构建互不继承映射表。

## 变异自证（/tmp 副本，工作区源码零改动）

在 `/tmp/diag-mut`（rsync 副本，排除 `.build`/`.git`）上逐条变异，每条后运行 `swift test --filter DiagnosticSnapshotTests`。**14 条变异全部被捕获（每条都变红）**：

| # | 变异 | 结果 |
| --- | --- | --- |
| M01 | 去掉 `/Volumes` 等残差路径替换 | 红灯 3 issues |
| M02 | 去掉共享名注册 | 红灯 6 issues |
| M03 | 去掉主机名注册 | 红灯 5 issues |
| M04 | 去掉 `smb_url` 注册 | 红灯 2 issues |
| M05 | 去掉挂载点注册 | 红灯 3 issues |
| M06 | 去掉 `additionalSensitiveValues` 注册 | 红灯 6 issues |
| M07 | 事件 `detail` 不做脱敏 | 红灯 7 issues |
| M08 | 去掉泄漏门（不再抛 leakDetected） | 红灯 1 issue |
| M09 | 让 `preview` 偷写临时文件 | 红灯 1 issue |
| M10 | 让 `export` 写到别的路径 | 红灯 1 issue |
| M11 | 去掉 IPv4 模式 | 红灯 7 issues |
| M12 | 去掉 `.local` 模式 | 红灯 5 issues |
| M13 | 去掉 `smb://` 模式 | 红灯 5 issues |
| M14 | 去掉 UNC 模式 | 红灯 3 issues |

**变异过程中发现并修复的三个真实覆盖缺口**（这是本轮最有价值的部分，说明「写了负向断言」不等于「断言有判别力」）：

1. **M02/M05 起初没红**：共享名与挂载点只出现在 URL 与 `/Volumes` 路径内部，被残差模式顺手替换，其显式注册毫无判别力。修正：fixture 增加**裸出现**的共享名/别名事件，以及一个 `/srv/mounts/vol-7f3a` 自定义挂载点（残差路径模式不覆盖 `/srv`），并让挂载点里不含共享名子串。
2. **M12/M13 起初没红**：`.local` 主机与 `smb://` 都被其他模式或已声明值掩盖。修正：新增**只属于该模式**的输入——未在配置中的 `printer-2f.local`、无路径段的 `smb://standalone-nas`（UNC 模式要求 authority 后必须有 `/`，故只有 smb 模式能捕获）。
3. **M09 起初没红**：临时目录基线与兄弟测试并发写同名文件竞争。修正：改为「先清空、再断言为空」的绝对判定，并将整个 suite 标记 `.serialized`。修正后连续 3 次运行稳定通过。
4. **构建期真实缺陷**：实现第一版时「先渲染事件正文、后注册 `additionalSensitiveValues`」，导致 `svc-mount-user` 泄漏。**是泄漏门自己先触发**（抛出 leakDetected）才被发现；修复为「先注册全部值、再渲染正文」，并让审计清单直接派生自脱敏器的实际替换表，使二者不可能漂移。

副本每条变异后已还原；结束前与工作区逐文件 sha256 一致（`DiagnosticSnapshot.swift`、`DiagnosticSnapshotTests.swift` 均 OK）。`/tmp/diag-mut` 与所有临时备份已删除，`automnt-diagnostic-stray.txt` 等残留已清理。

## 实际验证

| 验证 | 命令 | 结果 |
| --- | --- | --- |
| 整包构建 | `swift build` | Build complete |
| 整包测试 | `swift test` | 66 tests / 18 suites 与 108 tests / 30 suites 全部 passed，0 failed（合计 174 项） |
| 诊断专项 | `swift test --filter DiagnosticSnapshotTests` | 10 tests / 1 suite passed（串行 suite，连跑 3 次稳定） |
| CLI 优化构建 | `bash scripts/build.sh /tmp/automnt-diag` | 成功 |
| CLI 版本 | `/tmp/automnt-diag --version` | `3.4.0` |
| CLI 自测 | `/tmp/automnt-diag --self-test` | **295 passed, 0 skipped, 0 failed** |
| 本地化门 | `python3 scripts/verify-localization.py` | exit 0（102 源字符串 / 102 目录键，9 语言全非空，无回填，NotificationCopy 九语齐备） |
| 原生 Release 无签名构建 | `xcodebuild ... -derivedDataPath .build/xcode-diag CODE_SIGNING_ALLOWED=NO build` | `** BUILD SUCCEEDED **`（验证 Core 改动未破坏 app 集成） |

## 未验证边界

- **GUI 界面未实现**：无 `DiagnosticsView`、无预览/导出入口按钮、无文件选择器接线，因此「用户在界面上看到脱敏预览并主动选择目的地」这条完整交互**未经真实界面验证**；本轮只验证了 Core 引擎与契约层行为。原因是新增 app target 文件需要改 `project.pbxproj`（不在写范围）并新增九语文案。
- **未做真实端到端导出**：未从真实活动配置（真实主机/共享）生成快照并导出到用户选定位置；测试 fixture 均为合成值。
- 脱敏只覆盖已知模式与已声明值。若某真实值既未被声明、又不匹配任何残差模式（例如一个不含 `.local`/IP/`/Volumes` 特征的裸自定义主机短名），它可能不被替换——本实现按「调用方声明 + 常见形态」设计，**不是**通用 PII 分类器。
- 快照目前的输入来自调用方组装（`DiagnosticBuildInputs`）；尚未从签名校验、后台授权、服务状态的**真实运行时**采集这些输入，因此 `signature`/`authorization` 字段的取值正确性依赖未来的接线。
- 事件 `detail` 是自由文本，本实现只保证「已声明值 + 残留模式」被替换，不保证任意自然语言描述里的私有信息都被识别。
- 保留/清理政策未实现，因此导出文件的**存放归属与清理责任**仍待维护者决定（与 T003 一致）；本实现不自动删除、不自动上传任何导出文件。
- 九语文案本轮无新增，故本地化门维持既有 102 项；未来加 GUI 文案时需补九语并重跑该门。
