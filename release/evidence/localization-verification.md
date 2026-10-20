> 2026-10-11 本轮历史范围说明（仅 Feature005）：本轮仅修改文档与 demo；独立密码 CRUD、8 步向导、多选、用户 CLI 导入/检查、内部配置目录选择已撤销，现行要求以 [spec](../../specs/005-swiftui-mas-gui/spec.md) 与 [contracts](../../specs/005-swiftui-mas-gui/contracts/gui-and-release.md) 为准。系统认证在 sandbox/helper 中的复用未验证；已有 CLI 配置自动呈现与共享配置 owner 尚未实现。Automnt 暂用。以下历史正文与测试结果保留，旧资源、截图与测试不证明新版通过；CLI Feature001–004 的证据语义不变。

# V4 独立复验：九语本地化与防回归门

本轮由独立验证者（verifier4）复验共享任务 task-11（V4 复验九语本地化），对象为 task-10 交付的 `apps/Automnt/Resources/Localizable.xcstrings`（102 键 × 九语）与 Lead 新增的 `scripts/verify-localization.py` 门。

验证方式：**只读 + 只运行命令**，工作区未修改任何源码、资源、脚本或测试。唯一新增文件是本文件。变异实验全部在 `/tmp/verifier4/mut/repo`（`rsync` 副本）上进行。

关键事实基线：

```text
$ shasum -a 256 apps/Automnt/Resources/Localizable.xcstrings scripts/verify-localization.py
019f80c11f1156eca23779d1207f69fa8b943bf705d5a96189085221bb75a0ed  apps/Automnt/Resources/Localizable.xcstrings
177d060f163be486d9a3a6c3ccadbf7ca0d305ba4c3c6885b2e339df97141504  scripts/verify-localization.py
```

## 结论摘要

| 项目 | 结果 |
| --- | --- |
| GUI 模块内「源码文案 ↔ catalog 键」双向差集（我独立口径） | **通过**：102 ↔ 102，双向差集为 0 |
| 九语编译产物键数一致、非英语非英文原样 | **通过**：九个 `lproj` 各 102 键，取值与 catalog 零漂移 |
| 防回归门三类变异自证 | **通过**：三类变异均 exit 1；未变异 exit 0；`build.sh` 在变异下确实失败 |
| 术语与诚实性 | **通过**（无「已通过审校」表述）；但发现 2 处跨模块术语/品牌不一致（见缺陷） |
| 隐私抽查 | **通过**：catalog 与证据文件无真实私有目标 |
| **总体** | **未全通过**：GUI 内门有效，但**通知横幅文案整套不在门与 catalog 口径内**，且存在品牌大小写与 es 术语不一致 |

## 1. 独立重算覆盖（不采信实现者数字）

我重写了一份与 `scripts/verify-localization.py` 实现方式不同的抽取器 `/tmp/verifier4/extract_independent.py`：整文件单遍分词（多行 `"""` 感知、字符串感知的顶层参数切分），API 集合为超集。

```text
swift files scanned: 5
source string literals at user-visible arg positions: 102 unique
NOT in catalog (0):
catalog keys with no literal reference (0):
```

与 Lead 脚本的口径集合逐项比对：

```text
mine: 102  lead: 102
only mine: []
only lead: []
catalog keys: 102   set-equal to mine: True
```

结论：在 `apps/Automnt/**` 范围内，**102 ↔ 102 双向为 0 属实**，且两类口径当前**没有**互相漏掉的字面量。

### 1.1 我额外做的一层校验（寻找「双方同时漏掉」）

只看「差集为 0」会循环论证，因此我另做两个更强的检查：

1. **零 API 假设的全字面量清扫**（`/tmp/verifier4/sweep_all_literals.py`）：把 GUI 模块里**每一个** Swift 字符串字面量列出，不看任何 API 名。

```text
total string literals in GUI module: 138
  literal value present as catalog key : 114
  literal value NOT a catalog key      : 24
```

这 24 条逐条人工判读后**全部不是用户可见文案**：SF Symbols 名（`plus`、`eject`、`server.rack` 等 11 条）、进程/协议内部常量（`AutomntHelper`、`org.automnt.automnt`、`--probe-notification-channel`、`mount-recovery-state.plist`、`Library/LaunchAgents/com.user.automnt.plist`）、以及 6 条仅写入 stderr 的诊断行（`probe: bundleID=…` 等）。**未发现被两类口径同时漏掉的 GUI 文案。**

2. **API 形状盲区实测**：向 `/tmp` 副本源码插入 `help`、`navigationSubtitle`、`accessibilityHint` 文案，然后分别跑两个抽取器。

```text
=== gate (default, what build.sh runs) ===
（无输出）
EXIT=0
=== my independent extractor ===
NOT in catalog (3):
   - 'V4 Probe help only'  ['apps/Automnt/AutomntApp.swift:483']
   - 'V4 Probe hint only'  ['apps/Automnt/AutomntApp.swift:485']
   - 'V4 Probe subtitle only'  ['apps/Automnt/AutomntApp.swift:484']
```

`help` / `navigationSubtitle` / `accessibilityHint` / `accessibilityLabel` / `accessibilityValue` / `Menu`(首个字符串参数) / `Link` / `Picker` / `Stepper` / `badge` 均**不在门的 15 类模式中**。当前源码恰好都没用这些 API（`grep` 确认 `accessibility*`=0、`help(`=0、`navigationSubtitle`=0、`.help`=0），所以今日不漏；但门**无法阻止**后续加入后静默漏译。

3. **门的文件扫描范围偏窄**（`scripts/verify-localization.py:71-73`）：

```python
def swift_sources() -> list[pathlib.Path]:
    return sorted(list(APP_DIR.glob("*.swift")) + list(APP_DIR.glob("Views/*.swift")))
```

只覆盖 `apps/Automnt/*.swift` 与 `apps/Automnt/Views/*.swift`。实测：在 `apps/Automnt/Views/NewFolder/ExtraView.swift` 新建 `Text("V4 Probe nested view copy")` 后。

```text
=== lead gate (default, build.sh) ===
EXIT=0
=== my extractor (rglob) ===
NOT in catalog (1):
   - 'V4 Probe nested view copy'  ['apps/Automnt/Views/NewFolder/ExtraView.swift:5']
```

当前 `Service/`、`Worker/` 无 GUI 文案，故今日不漏；但 `Views/` 下新建子目录即会出现静默漏译。

### 1.2 本轮最有价值的发现：通知横幅文案整套在两类口径之外

`Sources/AutomntPlatform/SystemUserNotifier.swift:35`（`NotificationCopy`）与 `Sources/AutomntCore/FailureNotification.swift:12` 承载**全部九语通知横幅正文**，是用户可见文案，但：

- 不在 `apps/Automnt/**` 的任何扫描范围内；
- 不使用 catalog，也不是 `String(localized:)`；
- 是手写的 `if language.hasPrefix(...)` 分支。

调用链已确认是真实 GUI 路径，不是死代码：

```text
Sources/AutomntPlatform/SystemUserNotifier.swift:35  public enum NotificationCopy
Sources/AutomntPlatform/NotificationChannel.swift:340  let text = NotificationCopy.text(count: count, language: Locale.preferredLanguages.first ?? "en")
Sources/AutomntPlatform/NotificationChannel.swift:342  content.title = text.title
Sources/AutomntPlatform/NotificationChannel.swift:343  content.body = text.message
apps/Automnt/Service/HelperEntry.swift:38  await deliverFailureNotification(..., bundle: bundle)
```

我把该 enum 抽到 `/tmp/verifier4/notifprobe/` 独立编译运行，实测九语输出（节选）：

```text
=== count = 1 ===
[en] title=automnt: Automatic recovery incomplete
     msg=One shared folder could not be restored automatically. Open automnt settings and choose “Remount now”.
[zh-Hans] title=automnt：自动恢复未完成
     msg=1 个共享文件夹未能自动恢复。请打开 automnt 配置并选择“立即重新挂载”。
[ko] title=automnt: 자동 복구 미완료
     msg=공유 폴더 1개를 자동으로 복구하지 못했습니다. automnt 설정을 열고 ‘지금 다시 마운트’를 선택하세요.
=== count = 1000000 ===
[en] msg=1000000 shared folders could not be restored automatically. …
```

两点后果：

- **品牌大小写不一致**：GUI catalog 已改为 `Automnt`，通知横幅九语 title 全部仍是小写 `automnt`（见缺陷 D1）。
- **引导动作在 GUI 中不存在**：九语通知正文都要求用户「打开 automnt 配置并选择『立即重新挂载』/ choose “Remount now”」，但 `grep -rn "Remount\|立即重新挂载" apps/Automnt` 结果为 **NONE in GUI**；该动作只在 CLI（`Sources/AutomntCLI/Entry.swift:2566`）存在。用户照做找不到入口。

## 2. 验证实际编译产物（不是源文件）

```text
$ xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt -configuration Release \
    -derivedDataPath .build/v4-l10n-verify CODE_SIGNING_ALLOWED=NO build
** BUILD SUCCEEDED **    (exit 0)
```

九个 `lproj` 解出后的键数与取值核对（`plutil -convert json`）：

```text
de.lproj keys=102
en.lproj keys=102
es.lproj keys=102
fr.lproj keys=102
ja.lproj keys=102
ko.lproj keys=102
pt-BR.lproj keys=102
zh-Hans.lproj keys=102
zh-Hant.lproj keys=102

en       keys=102 same-as-en=True
zh-Hans  keys=102 same-as-en=True
zh-Hant  keys=102 same-as-en=True
ja       keys=102 same-as-en=True
ko       keys=102 same-as-en=True
de       keys=102 same-as-en=True
fr       keys=102 same-as-en=True
es       keys=102 same-as-en=True
pt-BR    keys=102 same-as-en=True

zh-Hans  identical-to-English=1 -> ['Automnt']
zh-Hant  identical-to-English=1 -> ['Automnt']
ja       identical-to-English=1 -> ['Automnt']
ko       identical-to-English=1 -> ['Automnt']
de       identical-to-English=4 -> ['Automnt', 'Name', 'Port', 'Server']
fr       identical-to-English=3 -> ['Automnt', 'Notifications', 'Port']
es       identical-to-English=1 -> ['Automnt']
pt-BR    identical-to-English=1 -> ['Automnt']
```

**非英语取值与 catalog 零漂移**：

```text
catalog-vs-product value drift: 0
```

抽样复核（4 语 × 5 条，取自编译产物）：`Servers` → `Servers | 伺服器 | サーバ | Server | Servidores`；`Eject` → `Eject | 退出 | 取り出す | Auswerfen | Ejetar`；`Open in Finder` → `在 Finder 中打開 | Finderで開く | Im Finder öffnen | Abrir no Finder`；`Delete saved credentials?` → `要刪除已儲存的登入資訊嗎？ | 保存済みのログイン情報を削除しますか？ | Gesicherte Anmeldedaten löschen? | Excluir as credenciais salvas?`；`Open Login Items Settings` → `打開「登入項目」設定 | 「ログイン項目」設定を開く | Anmeldeobjekte öffnen | Abrir “Itens de Início”`。非英语均非英文原样。

## 3. 防回归门自证（/tmp 副本，工作区未改动）

基线：

```text
$ python3 scripts/verify-localization.py --quiet
EXIT=0
$ python3 scripts/verify-localization.py
PASS  all 102 source string(s) have non-empty entries in all 9 languages
EXIT=0
```

| 变异 | 操作 | 结果 |
| --- | --- | --- |
| (a) 未进 catalog 的新 `Text("…")` | 在 `AutomntApp.swift` 增加 `Text("V4 Probe: unlocalized, with comma.")` | **exit 1**，报 `FAIL 1 source string(s) have no catalog entry` |
| (b) 删除某键语言分支 | 删除 `Eject` 的 `ja` | **exit 1**，报 `FAIL 1 key(s) are missing language branches: 'Eject' missing: ja` |
| (c) 清空某键 `ja` 值 | `Eject.ja` 置空字符串 | **exit 1**，报 `'Eject' missing: ja` |
| 额外：仅空白值 | 把 `Saved credentials deleted.` 的 `ko` 置 `"   "` | **exit 1**，报 `missing: ko`（`.strip()` 生效） |

`build.sh` 确实把门接在构建里（变异 a 下）：

```text
$ bash scripts/build.sh /tmp/verifier4/mut/out-automnt
3.4.0
3.4.0
catalog: apps/Automnt/Resources/Localizable.xcstrings
source strings found: 103   catalog keys: 102
FAIL  1 source string(s) have no catalog entry:
  - 'V4 Probe: unlocalized, with comma.'  (apps/Automnt/AutomntApp.swift:433)
build.sh EXIT=1
--- did it reach swiftc? ---
ls: /tmp/verifier4/mut/out-automnt: No such file or directory
```

即门失败发生在 `swiftc` 之前，**没有产出二进制**，归因清楚；未变异时同一 `build.sh` 成功产出（`EXIT=0`，输出版本 `3.4.0`）。

### 3.1 门默认强度不足（实测）

`build.sh` 只跑默认模式（`scripts/build.sh:10`：`verify-localization.py --quiet`）。我构造变异 (f)：把某条**整句**在 7 个语言里回填英文原文。

```text
=== DEFAULT gate (what build.sh runs) ===
EXIT=0
=== --require-translated (NOT run by build.sh) ===
FAIL  6 key(s) reuse the English text for other languages:
  - 'Shared folder ejected. It will stay disconnected until the network or login session changes.'
    identical in: zh-Hant, ja, ko, de, fr, es, pt-BR
EXIT=1
```

即：**「整句漏译成英文」这一类最典型的漏译，默认门放行**。`--require-translated` 因品牌与同形词（`Automnt`、de `Name/Port/Server`、fr `Notifications/Port`）不能直接启用，需要白名单才能进 `build.sh`。

## 4. 术语与诚实性复核

### 4.1 诚实性：通过

- catalog **102 条 `comment` 全部**以 `Draft translations require native review.` 结尾（`comments not ending with exact draft phrase: 0`）。
- `localizations.<lang>.stringUnit.state` 918 项全为 `translated`，`extractionState` 全为 `manual`——state 是 catalog 机制字段，不能误读为人工审校通过；证据文档已正确说明。
- 全仓检索未发现任何「已通过审校 / 已通过母语 / 审校通过 / translations approved」式表述；命中的 `"approved translations; native review remains a separate gate."`（`scripts/verify-localization.py:168`）是否定句。

### 4.2 术语基线一致性

对照 `specs/005-swiftui-mas-gui/design/localization.md`「九语术语候选基线」逐项核对 catalog：

- **品牌 Automnt 未翻译**：九语全部 `Automnt`，`Automnt` 键九语一致。
- **共享文件夹**：zh-Hant `共享檔案夾`、ja `共有フォルダ`、ko `공유 폴더`、de `Freigegebener Ordner`、fr `Dossier partagé`、es `Carpeta compartida`、pt-BR `Pasta compartilhada` —— 与基线表逐字一致。
- **挂载/弹出**：ja `マウント`/`取り出す`、ko `마운트`/`추출`、de `Verbinden`/`Auswerfen`、fr `Monter`/`Éjecter`、es `Montar`/`Expulsar`、pt-BR `Montar`/`Ejetar` —— 一致。基线表已自行标注 zh-Hant「退出」与 de `Verbinden` 待验证，catalog 确实取「退出」，属**已知待验证项**而非偏离。
- **自动挂载/自动恢复**：九语与基线表一致。
- **启用此服务器/此共享文件夹**：catalog 取「启用/有効にする/활성화/aktivieren/activer/activar/ativar」，与「核心文案候选」表的 zh 候选「启用此服务器/启用此共享文件夹」一致（英文为 `Include this…`，语义贴合，属可接受偏差）。
- **访问权限**：zh-Hans `文件夹访问权限`、zh-Hant `檔案夾存取權`、ja `フォルダのアクセス権`、ko `폴더 접근 권한`、de `Ordnerzugriff`、fr `Accès aux dossiers`、es `Acceso a carpetas`、pt-BR `Acesso às pastas` —— 一致。

破坏性/权限类逐条抽读未发现语义反转：`Delete saved credentials?`、`Delete credentials`、`Eject`、`Remove shared folder`、`Open Login Items Settings`、`Grant access to the Automnt folder…` 九语均在语义上正确表达「删除凭据 / 弹出 / 移除 / 打开登录项 / 授予访问」，未发现把「删除」误作「停用」或反向。

**未发现 catalog 内译文与术语表冲突。** 冲突出现在 catalog 之外的模块（见 5.1）。

### 4.3 数量/复数

catalog 内 `pluralVariations` 计数为 0，无 `%` / `{` / `\(` 格式串——与证据文档自述一致。但同时也说明：**`specs/…/localization.md`「数量、变量与复数资源」一节所要求的按语言 plural 分支（en one/other、de one/other、fr/es/pt-BR one/many/other）在本轮 catalog 中并未落地**；现网复数逻辑仍由 `NotificationCopy` 的 `number == 1` 手写分支承担（de/fr/es/pt-BR 有单复数两分支，zh/ja/ko 无），en 只有泛化复数（`\(number) shared folders`，count=1 时输出 `1 shared folders`）。该缺口属实现范围外，但不应被「102 键九语齐全」掩盖。

## 5. 缺陷

### D1（中）通知横幅品牌大小写与 GUI 不一致

本轮唯一源码改动是 GUI 内品牌大小写修正，但同一产品另两处用户可见通知文案未同步。

- 位置：`Sources/AutomntPlatform/SystemUserNotifier.swift:40,43,46,49,52,57,62,67`（九语 title）及正文 `:40,43,46,49,53,54,58,59,63,64,68,69,72,73`；`Sources/AutomntCore/FailureNotification.swift:14,15,17`。
- 最小复现：

```text
$ grep -n '"automnt[ :：]' Sources/AutomntPlatform/SystemUserNotifier.swift Sources/AutomntCore/FailureNotification.swift
Sources/AutomntPlatform/SystemUserNotifier.swift:43:  return ("automnt：自动恢复未完成", "\(number) 个共享文件夹未能自动恢复。…")
Sources/AutomntCore/FailureNotification.swift:14:  return ("automnt: Mounts Not Automatically Restored", …)
（九语 title 全部命中）
```

- 用户可见现象：系统通知横幅显示 `automnt`，而应用内显示 `Automnt`。

### D2（中）es 恢复术语在通知路径未统一，与证据文档自述冲突

- `release/evidence/localization.md:101` 声称 es「恢复」已统一为 `recuperación`；catalog 中 `Automatic recovery` es = `Recuperación automática`。
- 但 `Sources/AutomntPlatform/SystemUserNotifier.swift:62` 仍为 `Restauración automática incompleta`，正文 `:63,64` 用 `restaurar automáticamente`。
- 最小复现：`grep -n 'Restauración\|restaurar' Sources/AutomntPlatform/SystemUserNotifier.swift` → 命中 3 处。
- 影响：同一产品两个界面用两套西班牙语术语；证据文档的「已统一」表述在通知路径上不成立。

### D3（低）通知引导动作在 GUI 中不存在

`NotificationCopy` 九语正文均要求用户到配置中选择「立即重新挂载 / Remount now」，但 GUI 中不存在该命令。

- 最小复现：`grep -rn "Remount now\|立即重新挂载" apps/Automnt` → NONE；`Sources/AutomntCLI/Entry.swift:2566` 才有。
- 影响：用户按通知指引操作会找不到入口，属「给出不可执行的下一步」。

### D4（低）证据文档引用了不存在的文件

- `release/evidence/localization.md:127` 引用 `Sources/AutomntPlatform/NotificationCopy.swift`；该文件不存在。
- 最小复现：`ls Sources/AutomntPlatform/NotificationCopy.swift` → No such file。实际位置为 `Sources/AutomntPlatform/SystemUserNotifier.swift:35`。

### D5（低）门默认强度与覆盖面的已知缺口（非本轮回归，但会被误当「已守住」）

- 默认模式不检测「整句回填英文」（3.1 实测 exit 0）。
- `help`/`navigationSubtitle`/`accessibility*`/`Menu` 首参等 API 不在扫描集合（1.1 实测）。
- 仅扫描 `apps/Automnt/*.swift` 与 `Views/*.swift`，不递归（1.1 实测 exit 0）。
- 不覆盖 `Sources/AutomntPlatform`、`Sources/AutomntCore` 的通知横幅文案（1.2）。

## 6. 隐私抽查：通过

对 catalog 与证据文件扫描 IPv4、`smb://`、`/Users/`、`*.local|*.lan`、MAC、email：

```text
IPv4                             []
smb URL                          []
abs user path                    []
real hostname-ish (.local/.lan)  []
USERS dir                        []
mac addr                         []
email                            []
```

catalog 中出现的路径仅为通用占位 `/Volumes`（键 `Enter an SMB address without a username or password. Leave the mount folder empty to use its standard folder in /Volumes.`）与 `Library/Application Support`，均为通用系统路径，非私有目标。证据文件 `localization.md` 中的 `/Users/jiezhengj/...` 是仓库本身的工作路径，非用户目标数据，不构成泄漏。

## 7. 仍未验证的边界（不得当作已完成）

以下均为**未验证**，本轮不具备验证条件：

- **真实系统语言下 GUI 目视**：未在 macOS 27 以九种系统语言运行 GUI，未确认长译文换行、窄窗口重排、较大系统文字（辅助功能字号）、浅色/深色下的实际渲染。`AGENTS.md`「原生界面与产品文案原则」要求的逐页布局与原生验收未完成。窗口 `minWidth` 硬约束（`CredentialView.swift:43` 420、`HostEditorView.swift:50` 420、主窗 `defaultSize(width: 900, height: 620)`）对长译文的自适应表现未验证。
- **VoiceOver / 辅助功能**：未做；源码中 `accessibilityLabel/Hint/Value` 计数为 0，本轮未新增辅助功能标签资源，门也不覆盖它们。
- **复数分支**：未在真实系统 locale 下验证 CLDR 类别选择；catalog 无 plural 变体，见 4.3。`/tmp` 探针实测 de/fr/es/pt-BR 有单复数两分支、en 有 `One shared folder…` 单数分支，zh/ja/ko 使用自然量词（如 `1 个`、`1개`、`1 個`），未出现 `1 shared folders` 类错误；但这是**硬编码 `number == 1`** 而非系统 plural 规则，fr/es/pt-BR 的 `many` 类别（百万倍数）与 `0` 分支未按 CLDR 区分，未在真实系统下验证。
- **母语审校**：zh-Hans、zh-Hant、ja、ko、de、fr、es、pt-BR 八种全部未获母语审校，全部 102 条为草稿。本报告不对译文质量作母语级背书，仅做结构与术语表一致性核对。
- **通知横幅真机弹出**：仅验证了文案取值与调用路径，未在真实通知中心观察到横幅（需授权环境）。
- **App Store 商店页与支持材料文案、品牌名称可用性/商标**：范围外，未验证。

## 8. 复验方法可复现性

本报告使用的独立工具（均在 `/tmp`，不在仓库内）：

- `/tmp/verifier4/extract_independent.py`：独立抽取器（整文件分词 + 字符串感知参数切分），支持 `L10N_ROOT` 环境变量指向副本。
- `/tmp/verifier4/sweep_all_literals.py`：零 API 假设的全字面量清扫。
- `/tmp/verifier4/term_check.py`：术语基线表与 catalog 的交叉核对。
- `/tmp/verifier4/notifprobe/`：`NotificationCopy` 独立编译探针，实测九语三档计数输出。

变异实验的 `/tmp/verifier4/mut/repo` 在实验后已恢复为与工作区逐字节一致：

```text
$ diff -rq --exclude=.build --exclude=.git <workspace> /tmp/verifier4/mut/repo
（无输出）
```

# 第二轮复验（R4 修复后）：GUI 通知文案与门口径加固

本节由独立验证者 `verifier3`（共享任务 task-13 / V5）追加，记录对 R4（task-12）修复的独立复跑结果。上文（V4 / verifier4）的原文、结论与原始输出一律未改动；本节为纯追加，追加前后已用字节级前缀比对确认（见第 9 节）。

本轮未采信实现者数字，全部命令在本机（macOS 27.2，arm64，Xcode 27.0）重跑；变异实验只在 `/tmp/v5-mut`（`rsync -a --exclude .build --exclude .git` 副本）上进行，工作区 1602 个非 `.build`/`.git` 文件在复验前后逐文件 sha256 完全一致。

## 1. 结论摘要

| 编号 | 项目 | 结果 |
| --- | --- | --- |
| R4-1 | `NotificationCopy` 九语实测（独立编译探针，非读源码） | **通过**：品牌 `Automnt`、es `recuperación`、无「不存在动作」措辞、无私有目标 |
| R4-2 | CLI 渠道 `FailureNotification.swift` 未改 | **通过**：sha256 与期望值逐字节一致，探针实测仍为小写 `automnt` |
| R4-3 | F5 门口径加固（实现者列 7 条 + 我自加 5 条） | **通过**：全部 exit 1，未变异 exit 0；`build.sh` 在变异下于编译前失败且不产出二进制 |
| R4-4 | 白名单精确性（防「整语豁免」） | **通过**：精确 `(语言, 英文原文)` 对，8 语各逐语回填均被拒 |
| R4-5 | `swift test` / `build.sh` / `--self-test` / `xcodebuild` | **通过**：0 失败（Platform 50/16、Core 86/26）；`--self-test` **295 passed / 0 skipped / 0 failed**；`** BUILD SUCCEEDED **` |
| R4-6 | F4 文档表述与事实一致性 | **基本通过**，但有 1 处**行号引用失准**（见 F8） |
| R4-7 | 修复本身的**残余缺口** | **发现 3 项**：F7（中，`NotificationCopy` 的 message 分支没有任何译文回填检查，门与单测双双漏判）、F7-b（提示，禁用动作词表大小写敏感）、F6（低，仅"全角同形字"为双漏）；详见第 8 节 |
| **总体** | | **通过**（F1/F2/F3/F5 修复成立且经独立变异证实）；F7/F7-b/F6 为**残余覆盖缺口**，非本轮回归 |

F1/F2/F3 三项用户可见缺陷**均已真实修复**，且我已用独立编译探针逐语实测确认，不是只读源码得出的结论。

## 2. `NotificationCopy` 九语实测（独立编译探针）

方法：从**当前工作区**的 `Sources/AutomntPlatform/SystemUserNotifier.swift` 中逐字抽出 `public enum NotificationCopy { … }` 整体（41 行），拼成独立 `swiftc -O` 程序编译运行。**不是**读源码文本，也不是只跑测试目标内的断言。四档计数 × 九语 = 36 条记录。

```text
$ swiftc -O -o /tmp/v5-probe/probe /tmp/v5-probe/main.swift ; ./probe
COMPILE_EXIT=0   RUN_EXIT=0
LANG	en	COUNT	1	TITLE	Automnt: Automatic recovery incomplete	MSG	One shared folder could not be mounted automatically. Open Automnt to review.
LANG	zh-Hans	COUNT	1	TITLE	Automnt：自动恢复未完成	MSG	1 个共享文件夹未能自动挂载。请打开 Automnt 查看详情。
LANG	zh-Hant	COUNT	1	TITLE	Automnt：自動復原未完成	MSG	1 個共享檔案夾未能自動掛載。請打開 Automnt 查看詳細資訊。
LANG	ja	COUNT	1	TITLE	Automnt：自動復旧が完了していません	MSG	1 個の共有フォルダを自動でマウントできませんでした。Automnt を開いて詳細を確認してください。
LANG	ko	COUNT	1	TITLE	Automnt: 자동 복구 미완료	MSG	공유 폴더 1개를 자동으로 마운트하지 못했습니다. Automnt를 열어 자세히 확인하세요.
LANG	de	COUNT	1	TITLE	Automnt: Automatische Wiederherstellung unvollständig	MSG	Ein freigegebener Ordner konnte nicht automatisch verbunden werden. Öffne Automnt, um die Details zu prüfen.
LANG	fr	COUNT	1	TITLE	Automnt : Rétablissement automatique incomplet	MSG	Un dossier partagé n’a pas pu être monté automatiquement. Ouvrez Automnt pour consulter les détails.
LANG	es	COUNT	1	TITLE	Automnt: Recuperación automática incompleta	MSG	No se ha podido montar automáticamente una carpeta compartida. Abre Automnt para consultar los detalles.
LANG	pt-BR	COUNT	1	TITLE	Automnt: Recuperação automática incompleta	MSG	Não foi possível montar automaticamente uma pasta compartilhada. Abra o Automnt para ver os detalhes.
（count = 2 / 3 / 1000000 各九语，共 36 条，全文见 /tmp/v5-probe/out.txt）
```

对 36 条记录做机器断言（脚本 `/tmp/v5-probe` 内联，见第 9 节）：

```text
records: 36
FAILS: 0
ASSERT_EXIT=0
```

断言覆盖：① 每语 title 与 message 均含 `Automnt`；② 无独立小写 `automnt`（正则 `(?<![A-Za-z])automnt(?![A-Za-z])`）；③ 18 条「不存在动作」措辞全部不出现；④ es title 含 `recuperación` 且不含 `restauraci`/`restaurar`；⑤ 无 IPv4 / `smb://` / `/Users/` / email / `/Volumes`；⑥ 四档计数下九语 title 互不相同且非空；⑦ 计数正确渲染（en/de/fr/es/pt-BR 的 count=1 用「One/Ein/Un/una/uma」，其余含数字）。

**F1（品牌）**：九语 title 与 message 共 18 处全部为 `Automnt`，无小写。
**F2（es 术语）**：es title = `Recuperación automática incompleta`，message 用 `montar automáticamente`，全文无 `Restauración`/`restaurar`。
**F3（不实引导）**：18 条措辞全部不出现；正文统一为「打开 Automnt 查看详情」。

同时复核 GUI 侧确实没有该动作（V4 的 D3 前提仍成立）：

```text
$ grep -rn 'Remount|重新挂载|再マウント|다시 마운트' --include='*.swift' apps/Automnt/
（无输出：GUI Swift 源码中不存在该动作）
$ grep -rn 'Remount' --include='*.swift' Sources/AutomntCLI/
Sources/AutomntCLI/Entry.swift:2566:  SelectionItem(id: "remount", title: tr("立即重新挂载", "Remount now"),
```

即：改动后的正文只承诺 GUI 真实存在的动作（打开 Automnt），F3 修复方向正确。

## 3. CLI 渠道未改（契约要求的小写 `automnt`）

```text
$ shasum -a 256 Sources/AutomntCore/FailureNotification.swift
2897bdc6e491fe7a6202158deb336f4cf0957ae30e54598032fd7fbf96e936e1  Sources/AutomntCore/FailureNotification.swift
```

与 task-13 给出的期望值**逐字节一致**。独立编译探针实测该渠道输出：

```text
$ swiftc -O -o /tmp/v5-cli/probe /tmp/v5-cli/main.swift ; /tmp/v5-cli/probe
CLI	english=true	TITLE	automnt: Mounts Not Automatically Restored	SUBTITLE	Automatic recovery incomplete	MSG	3 shared folder(s) could not be restored automatically. Open automnt configuration and choose "Remount now".
CLI	english=false	TITLE	automnt：挂载未自动恢复	SUBTITLE	自动恢复未完成	MSG	3 个共享文件夹未能自动恢复。请打开 automnt 配置并选择“立即重新挂载”。
```

契约依据（不列为缺陷）：

```text
specs/005-swiftui-mas-gui/contracts/core-and-channels.md:21
  共同 CLI 基础文案使用 automnt，GUI 显示 Automnt，详细地址仍只在本机必要界面展示。
```

**判定**：CLI 渠道保留小写 `automnt` 与其中文正文「立即重新挂载」符合契约原文，是**渠道区分**，不是缺陷。`FailureNotification.swift` 的 sha256 与 R4 前完全一致，证实「只改 GUI 渠道」的声明成立。

## 4. F5 门口径——独立变异实验

沙箱 `/tmp/v5-mut`，每条变异前先还原、施加单点修改、再跑 `python3 scripts/verify-localization.py --quiet`。未变异基线 `exit=0`。

### 4.1 实现者列出的 7 类

| 编号 | 变异 | 期望 | 实测 |
| --- | --- | --- | --- |
| M1 | `Views/NewFolder/ExtraView.swift` 新增未本地化 `Text("V5 probe nested unlocalized copy")` | exit 1 | **exit 1**，`FAIL 1 source string(s) have no catalog entry`，扫描文件数 5 → **6**（证实 rglob 递归生效） |
| M2 | `.help("V5 probe help copy")` | exit 1 | **exit 1**，`FAIL 2 source string(s)…` |
| M3 | `.accessibilityHint("V5 probe accessibility hint copy")` | exit 1 | **exit 1**，`FAIL 2 source string(s)…` |
| M4 | 整句回填英文（默认模式，非 `--require-translated`） | exit 1 | **exit 1**，`FAIL 1 key(s) reuse the English text for other languages (outside the allowlist)` |
| M5 | 删除 `Eject.ja` 语言分支 | exit 1 | **exit 1**，`FAIL 1 key(s) are missing language branches` |
| M6 | `NotificationCopy` 品牌改回小写 `automnt` | exit 1 | **exit 1**，`FAIL 2 problem(s) in the hand-written NotificationCopy banner copy` |
| M7 | 回填 `Remount now` | exit 1 | **exit 1**，同上 |

### 4.2 我自加的 5 类（独立设计）

| 编号 | 变异 | 期望 | 实测 |
| --- | --- | --- | --- |
| X1 | `NotificationCopy` 两个语言分支返回**完全相同**的文案（fr 克隆 en） | exit 1 | **exit 1**（`titles are not distinct`） |
| X2 | 把 `language.hasPrefix("de")` 的选择器改成 `"xx"`（de 分支不可达、仍保留 9 个 `return`） | exit 1 | **exit 1**（`no language branch for: de`） |
| X3 | es 回退到 R4 之前的 `Restauración automática incompleta` | exit 1 | **exit 1**（`uses 'Restauración/restaurar' for es`） |
| X4 | 向正文注入私有目标 `smb://192.168.1.100/Private` | exit 1 | **exit 1**，`FAIL 2 problem(s)`（`contains a private target`） |
| X5 | 把某键 `ko` 值改成纯空白 `"   "` | exit 1 | **exit 1**（`.strip()` 生效，`missing: ko`） |

**X1 的设计意图**：利用「两道防线」——若门只看 title 是否互不相同，则「把两种语言整段设成同一文案」会漏判。实测 X1 被拒（两个 `return` 的 title 相同），确认该防线有效。

### 4.3 `build.sh` 在变异下于编译前失败且不产出二进制

```text
=== baseline build.sh ===
bash scripts/build.sh /tmp/v5-out-automnt
BASELINE_EXIT=0
binary: 1618192 bytes

=== mutated（NotificationCopy 品牌改小写）===
bash scripts/build.sh /tmp/v5-out-mut
MUTATED_EXIT=1
FAIL  2 problem(s) in the hand-written NotificationCopy banner copy:
  - NotificationCopy branch 2 omits the GUI brand 'Automnt': 'automnt：自动恢复未完成'
  - NotificationCopy branch 2 uses the CLI brand spelling 'automnt' in the GUI channel: 'automnt：自动恢复未完成'
--- did a binary get produced? ---
NO BINARY (correct: failed before swiftc)
```

归因清楚：门失败发生在 `swiftc` 之前，**没有产出二进制**；未变异时同一 `build.sh` 成功产出（exit 0）。

## 5. 白名单精确性复核（防「整语豁免」）

从**运行中的门模块**直接读出白名单（而非读源码常量）：

```text
{"zh-Hans": ["Automnt"], "zh-Hant": ["Automnt"], "ja": ["Automnt"], "ko": ["Automnt"],
 "de": ["Automnt", "Name", "Port", "Server"], "fr": ["Automnt", "Notifications", "Port"],
 "es": ["Automnt"], "pt-BR": ["Automnt"]}
entries=13, languages=8, any '*'=no
every allowlisted string is a real English source key: yes
```

即白名单是**精确到 `(语言, 英文原文)` 的对**，共 13 对、8 种语言，**无通配符、无「整语豁免」**，且每个被豁免的字符串都确实是 catalog 中的真实英文源键。

逐语攻击（对**未被豁免**的键回填该键自己的英文原文）：

| 语言 | 被回填的键 | 实测 |
| --- | --- | --- |
| zh-Hans / zh-Hant / ja / ko / fr / es / pt-BR | `Eject` | 全部 **exit 1** |
| de | `Shared folder ejected. It will stay disconnected until the network or login session changes.` | **exit 1** |

补充构造 `W2c`：把 `Eject` 的 de 值设为该键自己的英文源 `Eject` → **exit 1**（`'Eject' identical in: de`）。这证明「de 虽已豁免 `Name/Port/Server`/`Automnt` 四个同形词，但**不能**顺带豁免 `Eject`」——白名单没有开成整语豁免。

同时确认 `--require-translated` 严格模式如设计所述**忽略白名单**：

```text
$ python3 scripts/verify-localization.py --require-translated --quiet
FAIL  5 key(s) reuse the English text for other languages (ignoring the allowlist):
  - 'Automnt'  identical in: zh-Hans, zh-Hant, ja, ko, de, fr, es, pt-BR
  - 'Name'  identical in: de
  - 'Notifications'  identical in: fr
  - 'Port'  identical in: de, fr
  - 'Server'  identical in: de
EXIT=1
```

**判定**：白名单精确且精确到对，攻击全部被拒。

## 6. 常规回归（工作区重跑）

```text
$ swift test
Test run with 50 tests in 16 suites passed after 2.063 seconds.   # AutomntPlatformTests（含 NotificationCopyTests 5 项）
Test run with 86 tests in 26 suites passed after 0.217 seconds.   # AutomntCoreTests
TEST_EXIT=0     issues=0

$ swift test --filter NotificationCopyTests
Test recoveryTerminologyMatchesTheCatalogBaseline() passed
Test nineLanguagesHaveCompleteCountOnlyGuidance() passed
Test guiChannelUsesCapitalizedBrandOnly() passed
Test payloadStaysCountOnlyAndRedacted() passed
Test guiBannerDoesNotPromiseAnActionTheAppLacks() passed
Test run with 5 tests in 1 suite passed

$ rm -f /tmp/automnt-v5 && bash scripts/build.sh /tmp/automnt-v5
BUILD_SH_EXIT=0     (1618184 bytes)
$ /tmp/automnt-v5 --version
3.4.0        (exit 0)
$ /tmp/automnt-v5 --self-test | tail -1
Self-tests: 295 passed, 0 skipped, 0 failed     (exit 0)

$ xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt \
    -configuration Release -derivedDataPath .build/xcode-v5 CODE_SIGNING_ALLOWED=NO build
** BUILD SUCCEEDED **    (XCODE_EXIT=0)
```

编译产物复核：九个 `lproj` 齐全，各 **102** 键（`plutil -convert json` 逐个数）。

数字与实现者声明一致（Platform 50/16、Core 86/26、自测 295/0/0）。

## 7. F4 复核：`release/evidence/localization.md` 与事实的一致性

| 检查项 | 结果 |
| --- | --- |
| 是否仍引用不存在的 `Sources/AutomntPlatform/NotificationCopy.swift` | **否**（仅在 F4 修复说明中作为「原错误」被引用，属正常溯源） |
| 是否订正了第一轮「es 已统一」的不实表述 | **是**（第 103 行如实说明第一轮只覆盖 catalog，通知横幅路径漏改，并指向第二轮修复） |
| 是否声称已通过母语审校 | **否**（全文无「已通过审校 / 审校通过 / 已获母语 / translations approved」式表述；明确写明八语全部为未审校草稿） |
| 复数分支缺口是否如实披露 | **是**（第 129、251 行如实说明未落地，且把复数归于 `NotificationCopy` 与 CLI 渠道） |
| `NotificationCopy` 位置表述 | **文件名正确、行号失准**——见 F8 |

**F8（提示）：`localization.md` 三处把 `NotificationCopy` 标为 `SystemUserNotifier.swift:35`，实际在第 44 行。**

- 位置：`release/evidence/localization.md:103,129,146`（另 `localization-verification.md:98,107,296` 是 V4 原文，属同一失准，本轮不改写）。
- 实测：`grep -n 'public enum NotificationCopy' Sources/AutomntPlatform/SystemUserNotifier.swift` → **44**；第 35 行实际是文档注释 `/// Wording for the GUI notification channel.`。
- 影响：仅引用精度问题。这是 F4 修复时把「不存在的文件名」换成真实文件名时带来的**新**行号引用（V4 原文的 `:35` 在 R4 改文件后已偏移），不产生错误行为，但会误导按行号跳转的读者。
- 建议：改为 `SystemUserNotifier.swift:44`（或在文中省略行号，只写文件名，行号易随改动漂移）。

## 8. 本轮新发现的残余覆盖缺口（F6 / F7 / F7-b）

以下三项**不是 R4 引入的回归**，而是「门 + 单测」两条防线残留的缺口。方法：先变异，再**同时**跑门与 `swift test`，逐条记录两侧结果；判据为**两侧都 exit 0**（记为「双双漏判」）。

### F6（低）：门的品牌检查弱于单测；唯一「双双漏判」的是全角同形字

> **自查更正**：本节最初的判断（「CJK 紧邻小写品牌时门与单测双双漏判」）在我做**变体矩阵复核**后被推翻。实际只有「全角同形字」一种形态是双漏，其余形态至少有一侧能捕获。以下为复核后的准确结论，原始误判已作废。

- 位置：门 `scripts/verify-localization.py:214` 的 `re.search(r"\bautomnt\b", value)`；单测 `Tests/AutomntPlatformTests/NotificationCopyTests.swift:41,43`。
- 变体矩阵（把 `zh-Hans` 正文 `请打开 Automnt 查看详情。` 替换为下列内容，逐条实测门与单测）：

| 变体 | 门 | 单测 | 双双漏判 |
| --- | --- | --- | --- |
| A `请打开 automnt查看详情。`（大写品牌被去掉，小写紧邻中文） | **CAUGHT** | **CAUGHT**（7 issues） | 否 |
| B `请打开 Automnt。automnt查看详情。`（保留大写 + CJK 紧邻小写） | MISS | **CAUGHT**（3 issues） | 否 |
| C `请打开 Automnt。automnt 查看详情。`（两侧 ASCII 空格） | **CAUGHT** | **CAUGHT**（3 issues） | 否 |
| D `请打开 Automnt。ａｕｔｏｍｎｔ查看详情。`（**全角同形字**） | MISS | MISS（0 issues） | **是** |
| E `请打开 Automnt。automntX 查看详情。`（小写与 ASCII 字母粘连） | MISS | **CAUGHT**（3 issues） | 否 |

- 逐条归因（用门的实际 FAIL 行确认是哪条规则命中，不凭猜测）：
  - 变体 A（大写品牌被**替换**掉）：门由**另一条规则**命中——`omits the GUI brand 'Automnt'`。因为该变体删除了唯一的 `Automnt`，触发了「必须含品牌」检查，与 `\b` 无关。单测同时命中 `contains("Automnt")`。
  - 变体 C（小写两侧有 ASCII 空格）：门由 `uses the CLI brand spelling 'automnt'` 命中，`\b` 在该形态成立。
  - 变体 B/E：小写紧邻 CJK 或紧邻 ASCII 字母，`\b` 两侧至少一侧不成立 → **门 MISS**；但单测的大小写敏感 `contains("automnt")` 不依赖 `\b`，仍 **CAUGHT**。故**门的这一条弱于单测**。
  - 变体 D：**唯一的双双漏判**——**全角同形字**（U+FF41…，视觉上与 `automnt` 几近一致）。门用 ASCII 正则、单测用 ASCII `contains`，两者都不识别全角字母。
- 严重度：**低**。变体 D 需要有人主动键入全角字符才会发生，不是普通漏译路径；且今日九语分支均无全角品牌。相对 F7 属次要项。
- 最小复现（不修改工作区）：
  ```
  rm -rf /tmp/m && mkdir /tmp/m && rsync -a --exclude .build --exclude .git <工作区>/ /tmp/m/ && cd /tmp/m
  python3 - <<'PY'
  import pathlib
  p = pathlib.Path('Sources/AutomntPlatform/SystemUserNotifier.swift'); s = p.read_text()
  s2 = s.replace("请打开 Automnt 查看详情。", "请打开 Automnt。ａｕｔｏｍｎｔ查看详情。", 1)
  assert s2 != s
  p.write_text(s2)
  PY
  python3 scripts/verify-localization.py --quiet   # 期望红灯，实际 exit 0
  swift test --filter NotificationCopyTests        # 期望红灯，实际 5 tests passed
  ```
- 建议（低优先级）：若要让门与单测口径一致，可把门的品牌检查改为大小写不敏感 + Unicode 归一化（`unicodedata.normalize("NFKC", value)` 后再匹配），单测同理；这样变体 B/E/D 都会在门侧也能捕获。

### F7（中）：`NotificationCopy` 的 message 分支没有任何「译文回填」检查

- 位置：`scripts/verify-localization.py:193-237`（只收集 `titles` 并检查 `len(set(titles)) != len(titles)`）；`NotificationCopyTests.swift` 的三个循环断言也只校验 message 含 `3`、含 `Automnt`、不含 forbidden，**不校验 message 与他语不同**。
- 问题：catalog 侧有严格的「非英语值不得等于英文源」检查（默认模式即生效），但 `NotificationCopy` 是手写分支、**不经过 catalog**，其 message 完全没有任何回填检查。门的唯一结构性约束是「title 互不相同」，message 只要非空、含品牌、不含禁用词即可通过。
- 实测（`/tmp/v5-mut`）：把 de/fr/es/pt-BR 四语的 message 全部替换为英文 `One shared folder could not be mounted automatically. Open Automnt to review.`（**title 保持不变**）：
  - 门 `exit=0`（**漏判**）
  - `swift test --filter NotificationCopyTests` `exit=0`，0 issues（**漏判**）
  - **两侧同时漏判**。
- 严重度高于 F6：该形态正是 V4 发现的同一类问题（「整套文案在两类口径之外」）的**残余**，只是现在只剩 message 一半未被覆盖；若将来只回填 message，四语用户会看到英文正文而无人报警。
- 最小复现（不修改工作区）：
  ```
  rm -rf /tmp/m && mkdir /tmp/m && rsync -a --exclude .build --exclude .git <工作区>/ /tmp/m/ && cd /tmp/m
  python3 - <<'PY'
  import pathlib
  p = pathlib.Path('Sources/AutomntPlatform/SystemUserNotifier.swift'); s = p.read_text()
  for m in ["Ein freigegebener Ordner konnte nicht automatisch verbunden werden. Öffne Automnt, um die Details zu prüfen.",
            "Un dossier partagé n’a pas pu être monté automatiquement. Ouvrez Automnt pour consulter les détails.",
            "No se ha podido montar automáticamente una carpeta compartida. Abre Automnt para consultar los detalles.",
            "Não foi possível montar automaticamente uma pasta compartilhada. Abra o Automnt para ver os detalhes."]:
      assert m in s
      s = s.replace(m, "One shared folder could not be mounted automatically. Open Automnt to review.", 1)
  p.write_text(s)
  PY
  python3 scripts/verify-localization.py --quiet   # 期望红灯，实际 exit 0
  swift test --filter NotificationCopyTests        # 期望红灯，实际 5 tests passed
  ```
- 建议：在 `check_notification_copy()` 中像检查 title 一样收集并比较全部 message（例如断言「不存在两种语言的 title 与 message 同时相同」或「每条 message 不得等于 en 分支的 message」），并在 `NotificationCopyTests` 增加镜像断言。

### F7-b（提示）：禁用动作词表大小写敏感，存在漏判面

- 位置：`scripts/verify-localization.py:124-127` 的 `"erneut verbinden"`、`"Reconnecter"`、`"Reconectar"`、`"Volver a conectar"`；`NotificationCopyTests.swift` 的 `absentActions` 同样是区分大小写的精确匹配。
- 实测（逐条注入到 de 分支，同时跑门与单测）：

  | 注入短语 | 门 | 单测 | 双双漏判 |
  | --- | --- | --- | --- |
  | `erneut verbinden`（与词表逐字相同） | CAUGHT | CAUGHT | 否 |
  | `Erneut verbinden`（首字母大写，词表为小写） | MISS | MISS | **是** |
  | `Reconnecter`（与词表逐字相同） | CAUGHT | CAUGHT | 否 |
  | `reconnecter`（词表为 `Reconnecter`） | MISS | MISS | **是** |
  | `Reconectar`（与词表逐字相同） | CAUGHT | CAUGHT | 否 |
  | `reconectar`（词表为 `Reconectar`） | MISS | MISS | **是** |
  | `Volver a conectar`（与词表逐字相同） | CAUGHT | CAUGHT | 否 |
  | `volver a conectar`（词表为 `Volver a conectar`） | MISS | MISS | **是** |
  | `Remount`（与词表逐字相同） | CAUGHT | CAUGHT | 否 |
  | `REMOUNT`（全大写） | MISS | MISS | **是** |

  即：词表中逐字给定的那几种**拼写**都能捕获；**只差大小写**的同一短语则两侧同时放行。
  对照：`今すぐ再マウント`、裸 `再マウント`（CJK 无大小写之分）→ **两侧均 CAUGHT**。
- 影响：德语/法语/西语/葡语正文若出现**句首大写**的动作短语，两条防线都会放行。今日实际文案不含这些短语（`grep` 确认 fr/de 正文未出现所列词），故**不是当前缺陷**，但这是 F3 所修「不实引导」这一最严重问题的防线上可被绕过的面。
- 建议：改用大小写不敏感匹配（`re.IGNORECASE` / `lowercased()`），并让测试与门共用同一词表以免二者漂移。

## 9. 追加方式与工作区完整性

追加前的字节基线（V4 原文，未被本轮改动）：

```text
bytes : 21139
sha256: f1dfd50d945b62a9b1243b6d1630e1b2b88679cca59eca751cad0ff816cdf989
```

追加后校验：当前文件的前 21139 字节与 `/tmp/v5-prefix-before.bin`（追加前快照）逐字节相同，即**只追加、未改写 Verifier4 原文**：

```text
$ python3 -c "
import pathlib
before=open('/tmp/v5-prefix-before.bin','rb').read()
now=pathlib.Path('release/evidence/localization-verification.md').read_bytes()
print('prefix identical:', now[:len(before)]==before)
print('baseline bytes  :', len(before))
"
prefix identical: True
baseline bytes  : 21139
```

> **关于本文件的总长度与自身 sha256**：此处**刻意不写**这两个数——把哈希写进文件会使该哈希立即
> 失效（自指），而总长度会随后续追加漂移。唯一稳定、可独立复核的量是上面这一条**前缀事实**：
> 当前文件的前 21139 字节与追加前快照逐字节相同，即本节确实只做了追加、没有改写 Verifier4 原文。
> 读者可自行执行 `wc -c release/evidence/localization-verification.md` 重算长度。

工作区完整性（复验前后逐文件 sha256 全量对照，1602 个文件）：

```text
before: 1602   after: 1602
CHANGED: ['./release/evidence/localization-verification.md']   # 仅本文件（追加本节所致）
ADDED:   []
REMOVED: []
```

即：**除本证据文件自身外，工作区没有任何文件被改动**。变异实验全部发生在 `/tmp/v5-mut`，副本在每条变异后已还原并与工作区逐字节一致（`Sources/AutomntPlatform/SystemUserNotifier.swift` 三处 sha256 均为 `368c710e…fc80`）。验证过程未修改任何源码、脚本、catalog、测试或工程文件。

关键文件 sha256（本轮复验记录）：

| 文件 | sha256 |
| --- | --- |
| `Sources/AutomntPlatform/SystemUserNotifier.swift` | `368c710e12343ca81896fa7d7ccce46b44c53ec600fa735d5029f589a7a6fc80` |
| `Sources/AutomntCore/FailureNotification.swift`（CLI，契约要求未改） | `2897bdc6e491fe7a6202158deb336f4cf0957ae30e54598032fd7fbf96e936e1` |
| `scripts/verify-localization.py` | `c6cc152afe183cb3387d2b654620da433ae4ac61f0e6a4797baaaf48ef7f672a` |
| `apps/Automnt/Resources/Localizable.xcstrings` | `019f80c11f1156eca23779d1207f69fa8b943bf705d5a96189085221bb75a0ed` |
| `Tests/AutomntPlatformTests/NotificationCopyTests.swift` | `21e57c9bd887a3fab25276686af6f900f6950964526de4602daf05ab15196f7f` |
| `release/evidence/localization.md` | `46e48feaeb12f84c221e81dd6a741ae43b85c9a0eebfb9a54ff8f4d0cd0775ff` |

`/tmp/v5-mut` 副本在每条变异后均还原，与工作区逐字节一致。派生的 GUI/helper/测试进程已清理。

## 10. 隐私抽查

对 R4 触碰的文件扫描 IPv4 / `smb://` / `/Users/` / email / `*.local|*.lan`：

```text
-- Sources/AutomntPlatform/SystemUserNotifier.swift
   (clean)
-- Sources/AutomntCore/FailureNotification.swift
   (clean)
-- scripts/verify-localization.py
133:    re.compile(r"smb://", re.IGNORECASE),     # 检测规则本身，非私有目标
134:    re.compile(r"/Users/"),                    # 检测规则本身，非私有目标
```

九语横幅文案仅含计数与「打开 Automnt」，不含卷名、地址或路径（探针断言第 ⑤ 项已确认）。

## 11. 仍未验证的边界（不得当作已完成）

- **真实通知中心横幅**：只验证了 `NotificationCopy` 的取值与独立编译输出，以及调用路径（helper → `SystemUserNotifier` → 应用内子进程 `NotificationChannel.swift` → `content.title/body`），**未在真实通知中心观察到横幅**（需授权环境），未验证点击打开、前台去重、系统声音。
- **真实系统 locale 解析**：探针注入语言字符串（含 `zh-TW`/`zh-HK`/`unknown` 回退），未在真实系统语言设置下验证 `Locale.preferredLanguages.first` 对 `zh-TW`/`pt-PT` 等区域码的实际解析。
- **GUI 内重试入口**：F3 只保证文案不谎称该动作存在；界面内重试属 **T032/T033**，本轮未实现，用户按通知打开 App 后能做什么仍未定。
- **复数分支未落地**：`NotificationCopy` 仍是手写 `number == 1` 分支，未按 CLDR 规则；catalog 无 plural 变体。fr/es/pt-BR 的 `many` 类别与 `0` 分支未按 CLDR 区分。
- **母语审校未完成**：zh-Hans、zh-Hant、ja、ko、de、fr、es、pt-BR 八语全部为未审校草稿；本报告只做结构与术语基线核对，**不对译文质量作母语级背书**。
- **真实系统语言下 GUI 目视与 VoiceOver**：未在 macOS 27 以九种系统语言运行 GUI，未确认长译文换行、窄窗口重排、较大系统文字、浅深色渲染；未做 VoiceOver/辅助功能标签验证；门虽已覆盖 `accessibility*` API 的**文案抽取**，不等于 VoiceOver 实际朗读正确。
- **App Store 商店页与支持材料文案、品牌可用性/商标**：范围外，未验证。
- **F6/F7/F7-b 修复未做**：本验证者只读，三处缺口均已给出最小复现与建议，未修改任何源码、脚本或测试。

# 第三轮复验（V6）：F6 / F7 / F7-b / F8 修复

本节由独立验证者 `verifier3`（共享任务 task-14 / V6）追加，记录对 Lead 修复 V5 所报残余缺口的独立复跑。上两节（V4 原文、V5 第二轮）的原文、结论与原始输出一律未改动；本节为纯追加，追加前后已用字节级前缀比对确认（见第 8 节）。

本轮未采信实现者描述，全部命令在本机（macOS 27.2，arm64，Xcode 27.0）重跑；变异实验只在 `/tmp/v6-mut`（`rsync -a --exclude .build --exclude .git` 副本）上进行。工作区 1602 个非 `.build`/`.git` 文件在复验期间除本证据文件外无改动（另有一次并发写入见第 8 节说明）。

## 1. 结论摘要

| 编号 | 项目 | 结果 |
| --- | --- | --- |
| V6-1 | F7 message 回填（**单数 + 复数**两形态） | **通过**：门 exit 1 **且** `swift test` exit 1（单数 5 issues、复数 10 issues） |
| V6-2 | F6 全角同形字 / F7-b 大小写变体 | **通过**：门 exit 1（6 种变体全部捕获） |
| V6-3 | 反向：未变异 exit 0、`Automnt` 不误判、白名单未放宽 | **通过**：三项均符合预期 |
| V6-4 | 我自加 6 类新变异 | **通过**：N2/N5/N6 双红，N3/N4 单测红、N1 单测红；无「双绿」异常 |
| V6-5 | `swift test` / `build.sh` / `--self-test` / `--version` / `xcodebuild` | **通过**：0 失败（Platform 51/16、Core 86/26）；295/0/0；3.4.0；`** BUILD SUCCEEDED **` |
| V6-6 | F8 行号漂移 | **已修复**：`localization.md` 不再写行号；无新的文档不实 |
| V6-7 | 产品文案是否被本轮触动 | **未触动**：运行期文案与 V5 探针输出**逐字节相同**；CLI 渠道 sha256 仍为契约值 |
| V6-8 | 新发现 | **F9（低-中）**：message 回填只与「英文 message」比对，若把某语 message 换成**英文 title** 则门与单测**双双漏判**（仅单数形态） |
| **总体** | | **通过**（F6/F7/F7-b/F8 四项修复全部成立；F9 为新的残余缺口，非本轮回归） |

## 2. F7 复跑：message 回填（单数与复数两种形态）

方法：在 `/tmp/v6-mut` 把 de/fr/es/pt-BR 四语的 message 替换为对应英文形态，**同时**跑门与 `swift test --filter NotificationCopyTests`。判据为**两侧都非零退出**。

### 2.1 单数形态（count = 1 分支）

```text
改造对象（4 条单数 message）：
  de "Ein freigegebener Ordner konnte nicht automatisch verbunden werden. Öffne Automnt, um die Details zu prüfen."
  fr "Un dossier partagé n’a pas pu être monté automatiquement. Ouvrez Automnt pour consulter les détails."
  es "No se ha podido montar automáticamente una carpeta compartida. Abre Automnt para consultar los detalles."
  pt "Não foi possível montar automaticamente uma pasta compartilhada. Abra o Automnt para ver os detalhes."
  → 统一替换为英文单数 "One shared folder could not be mounted automatically. Open Automnt to review."

$ python3 scripts/verify-localization.py --quiet
FAIL  4 problem(s) in the hand-written NotificationCopy banner copy:
  - NotificationCopy branch for 'de' reuses the English message verbatim: 'One shared folder could not be mounted automatically. Open Automnt to review.'
  - NotificationCopy branch for 'fr' reuses the English message verbatim: ...
  - NotificationCopy branch for 'es' reuses the English message verbatim: ...
  - NotificationCopy branch for 'pt' reuses the English message verbatim: ...
gate exit = 1

$ swift test --filter NotificationCopyTests
swift test exit = 1   (5 issues)
```

### 2.2 复数形态

```text
改造对象（4 条复数 message，含 \(number)）→ 统一替换为英文复数
  "\(number) shared folders could not be mounted automatically. Open Automnt to review."

$ python3 scripts/verify-localization.py --quiet
FAIL  4 problem(s) ... branch for 'de'/'fr'/'es'/'pt' reuses the English message verbatim
gate exit = 1

$ swift test --filter NotificationCopyTests
swift test exit = 1   (10 issues)
```

**判定**：两种形态均**门红 + 单测红**，F7 修复成立。特别复核了 Lead 自述的「第一版测试只测 count=2/7、漏掉 count=1 单数分支」——我逐字复跑了「**只**把 de 的单数 message 回填英文」这一形态：

```text
=== N5: only de SINGULAR message -> English ===
gate = 1   swift test = 1 (2 issues)
```

即该退化现在**不再**能双绿通过，Lead 把 count 改为 `[1, 2, 7]` 的修正确实生效。

## 3. F6（全角同形字）与 F7-b（大小写变体）

| 变异 | 门 | 单测 | 判定 |
| --- | --- | --- | --- |
| F6：`ａｕｔｏｍｎｔ`（全角同形字） | **exit 1** | exit 0 | 门已捕获（NFKC 归一化生效） |
| F7-b：`Erneut verbinden` | **exit 1** | exit 0 | 门已捕获 |
| F7-b：`REMOUNT` | **exit 1**（2 条） | exit 0 | 门已捕获 |
| F7-b：`reconectar` | **exit 1** | exit 0 | 门已捕获 |
| F7-b：`volver a conectar` | **exit 1** | exit 0 | 门已捕获 |
| F7-b：`reconnecter` | **exit 1** | exit 0 | 门已捕获 |
| F7-b：`RECONNECTER` | **exit 1** | exit 0 | 门已捕获 |

门的实际 FAIL 行（节选）：

```text
- NotificationCopy branch 2 uses the CLI brand spelling 'automnt' in the GUI channel:
  '\(number) 个共享文件夹未能自动挂载。请打开 Automnt。ａｕｔｏｍｎｔ查看详情。'
- NotificationCopy branch 5 advertises an action the GUI does not provide: 'erneut verbinden' in ...
- NotificationCopy branch 5 advertises an action the GUI does not provide: 'Remount' in ...
- NotificationCopy branch 5 advertises an action the GUI does not provide: 'remount' in ...
```

任务书对 F6/F7-b 的要求是**门 exit 1**，两者均满足。附带记录一个**非本轮要求**的不对称：`NotificationCopyTests.swift` 的 `absentActions` 仍是**区分大小写**的 ASCII `contains`，`guiChannelUsesCapitalizedBrandOnly` 也仍是 ASCII `contains("automnt")`，因此上述 6 种变体在下单测 exit 0。这不影响交付（门已守住，且门接在 `build.sh` 里），但意味着**单测这一层弱于门**；若将来有人单独跑 `swift test` 而不跑门，这些形态不会被发现。属提示，见第 7 节 F9-b。

## 4. 反向验证：未过度收紧、`Automnt` 不误判、白名单未放宽

### 4.1 未变异 exit 0

```text
$ python3 scripts/verify-localization.py
PASS  all 102 source string(s) have non-empty entries in all 9 languages
PASS  no non-English value copies the English source outside the documented brand/borrowed-word allowlist
PASS  NotificationCopy has distinct, branded, redacted copy in every language and names no action the GUI lacks
GATE_EXIT=0
```

### 4.2 正确的 `Automnt` 不被误判（大小写敏感是有意为之）

| 变异 | 门 | 判定 |
| --- | --- | --- |
| 在 de message 里再加一处正确品牌 `Öffne Automnt (Automnt).` | **exit 0** | 正确的 `Automnt` **不会**被误判 |
| 在 de message 里写入全大写 `Öffne Automnt. AUTOMNT.` | **exit 0** | 门**只**把小写 `automnt` 视为违反；`IGNORECASE` 确实已回退 |

外加两条「不该红」的良性文案（应保持 exit 0）：

```text
de 良性 "Öffne Automnt. Der Ordner bleibt verbunden."      -> gate exit 0
fr 良性 "Ouvrez Automnt. Le dossier est connecté."          -> gate exit 0
```

即 NFKC + 大小写不敏感的动作词表**没有**把正常的 `verbunden` / `connecté` 误伤为动作短语。Lead 自述「第一版顺手加 `re.IGNORECASE` 把正确的 `Automnt` 判成失败、已回退」经上表确认成立。

### 4.3 白名单未放宽

从**运行中的门模块**读出白名单，与 V5 记录的基线逐项比对：

```text
live  : {"zh-Hans":["Automnt"],"zh-Hant":["Automnt"],"ja":["Automnt"],"ko":["Automnt"],
         "de":["Automnt","Name","Port","Server"],"fr":["Automnt","Notifications","Port"],
         "es":["Automnt"],"pt-BR":["Automnt"]}
V5基线: 完全相同
identical: True      （13 对 / 8 语，无通配符，无整语豁免）
```

判定：**未被放宽**。

## 5. 我自加的 6 类新变异（独立设计）

| 编号 | 变异 | 门 | 单测 | 判定 |
| --- | --- | --- | --- | --- |
| N1 | de 的 message 与自己的 title 互换 | 0 | 1 | 单侧捕获，符合预期（de title 有专用术语断言兜底） |
| N2 | **整体删掉英文 fallback 分支**（剩 8 个 return） | **1** | **1** | 双红；门报 `has 8 language branch(es); 9 are required` + `has no fallback branch providing the English copy` |
| N3 | fr 的 message ← es 的 message（两门非英语互抄） | 0 | 1 | 单侧捕获：门只与英文比对，单测的「九语互不相同」兜住 |
| N4 | de 复数 message 去掉计数占位符 | 0 | 1 | 单侧捕获：门无计数检查，单测 `payloadStaysCountOnlyAndRedacted` 兜住 |
| N5 | **只**回填 de 的**单数** message | **1** | **1** | 双红（即 Lead 自述第一版漏掉的形态） |
| N6 | fr 的 title ← 英文 title 逐字 | **1** | **1** | 双红；门报 `titles are not distinct across languages` |

另做了两条**结构边界**探测，确认新的 fallback 识别逻辑不会因为选择器缺失而自相矛盾：

```text
E1 把 zh-Hans 的 if language.hasPrefix("zh") 改成 if true（该分支变成"无选择器"）
   -> gate exit 1（报 "no language branch for: zh"），单测 exit 1
E2 在 E1 基础上再把该分支 message 回填英文
   -> gate exit 1，单测 exit 1
```

即「分支丢了选择器」这条退化会先被「九语分支齐全」这条规则拦住，不会退化成静默放行。**N2/E1/E2 三条都无「双绿」。**

## 6. 常规回归与 `build.sh` 接线

```text
$ swift test
Test run with 51 tests in 16 suites passed after 2.132 seconds.   # AutomntPlatformTests（NotificationCopyTests 6 项）
Test run with 86 tests in 26 suites passed after 0.283 seconds.   # AutomntCoreTests
TEST_EXIT=0     issues=0
静态 @Test 计数：Core 86 / Platform 51，与运行计数一致

$ swift test --filter NotificationCopyTests
Test recoveryTerminologyMatchesTheCatalogBaseline() passed
Test messageBodiesAreTranslatedAndDistinctPerLanguage() passed   # 本轮新增
Test nineLanguagesHaveCompleteCountOnlyGuidance() passed
Test guiChannelUsesCapitalizedBrandOnly() passed
Test payloadStaysCountOnlyAndRedacted() passed
Test guiBannerDoesNotPromiseAnActionTheAppLacks() passed
Test run with 6 tests in 1 suite passed

$ rm -f /tmp/automnt-v6 && bash scripts/build.sh /tmp/automnt-v6
BUILD_SH_EXIT=0    (1618184 bytes)
$ /tmp/automnt-v6 --version
3.4.0        (exit 0)
$ /tmp/automnt-v6 --self-test | tail -1
Self-tests: 295 passed, 0 skipped, 0 failed     (exit 0)

$ xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt \
    -configuration Release -derivedDataPath .build/xcode-v6 CODE_SIGNING_ALLOWED=NO build
** BUILD SUCCEEDED **    (XCODE_EXIT=0)
```

九个 `lproj` 齐全，各 **102** 键。`build.sh` 确实把门接在编译之前（F7 变异下）：

```text
=== baseline build.sh ===   BASELINE_EXIT=0   binary bytes: 1618184
=== mutated (de 复数 message -> 英文) build.sh ===
MUTATED_EXIT=1
FAIL  1 problem(s) in the hand-written NotificationCopy banner copy:
  - NotificationCopy branch for 'de' reuses the English message verbatim: '\(number) shared folders could not be mounted automatically. Open Automnt to review.'
--- binary produced? ---   NO BINARY (correct: 失败发生在 swiftc 之前)
```

## 7. 产品文案未被触动（渠道区分复核）

Lead 声明「只改自己的门与测试，未动产品文案」，实测成立：

| 文件 | sha256 | 与 V5 的关系 |
| --- | --- | --- |
| `Sources/AutomntPlatform/SystemUserNotifier.swift` | `368c710e12343ca81896fa7d7ccce46b44c53ec600fa735d5029f589a7a6fc80` | 与 V5 记录的**逐字节相同** |
| `Sources/AutomntCore/FailureNotification.swift`（CLI 渠道） | `2897bdc6e491fe7a6202158deb336f4cf0957ae30e54598032fd7fbf96e936e1` | 仍为 `contracts/core-and-channels.md:21` 要求的契约值 |
| `apps/Automnt/Resources/Localizable.xcstrings` | `019f80c11f1156eca23779d1207f69fa8b943bf705d5a96189085221bb75a0ed` | 与 V5 记录的**逐字节相同** |
| `scripts/verify-localization.py` | `d9c7c6b3b637ef6809ef091dfec3cc726f37d8d0f087758441d341fe72895dfe` | 本轮改动 |
| `Tests/AutomntPlatformTests/NotificationCopyTests.swift` | `87938d08b37e878625a6b662bf9fc19def8dc61885455f798292f4dc0d5bd54a` | 本轮改动 |

**运行期文案逐字节复核**：我用与本轮相同的抽取方式把当前 `NotificationCopy` 编成独立 `swiftc -O` 探针运行，输出与 V5 的探针输出做 `diff`：

```text
$ swiftc -O -o /tmp/v6-probe /tmp/v6-probe-main.swift && /tmp/v6-probe > /tmp/v6-probe-out.txt
$ diff /tmp/v5-probe/out.txt /tmp/v6-probe-out.txt
（无输出）
RUNTIME COPY IDENTICAL TO V5
```

即九语 36 条运行时文案**没有任何变化**，F1/F2/F3 的修复结果保持原样，本轮确实只收紧了门与测试。

## 8. F8 复核：行号漂移与文档不实

| 检查项 | 结果 |
| --- | --- |
| `release/evidence/localization.md` 是否仍写 `:35` 行号 | **否**；三处均已改为「`Sources/AutomntPlatform/SystemUserNotifier.swift` 中 `enum NotificationCopy`」，不写行号 |
| 当前 `enum NotificationCopy` 实际行号 | **44**（`grep -n 'public enum NotificationCopy'`） |
| 是否仍引用不存在的 `NotificationCopy.swift` | 仅在 F4 修复说明中作为「原错误」被引用（正常溯源），无实际路径引用 |
| 替换后是否产生重复措辞 | 未发现（`SystemUserNotifier.swift` 3 处引用，措辞各不相同、语义完整） |
| 是否声称已通过母语审校 | **否**（全文无「已通过审校 / 审校通过 / 已获母语 / translations approved」式表述） |
| 本轮是否引入新的文档不实 | 未发现 |

判定：**F8 已修复**，且不写行号的做法比「改成 `:44`」更耐改动。

## 9. 本轮新发现的残余缺口

### F9（低-中）：message 回填只与「英文 message」比对，换成**英文 title** 即双双漏判（仅单数形态）

- 位置：`scripts/verify-localization.py:250` 的 `english_forms = {message for selector, messages in branch_messages if not selector for message in messages}`——比对集合**仅**包含 fallback 分支的 **message**；`Tests/AutomntPlatformTests/NotificationCopyTests.swift:93` 的 `let english = NotificationCopy.text(count: count, language: "en").message` 同样只取英文 **message**。
- 问题：只要某语 message 变成**英文 title**（`Automnt: Automatic recovery incomplete`），它既不等于英文 message，也就绕过了两处「回填」检查；同时它仍是英文、不是译文，用户依然看到英文正文。
- 实测（`/tmp/v6-mut`，把 de/fr/es/pt-BR 四语的 **singular** message 统一替换为英文 title）：

```text
de singular    gate=MISS  swift_test=MISS (0 issues)  DOUBLE-MISS=True
fr singular    gate=MISS  swift_test=MISS (0 issues)  DOUBLE-MISS=True
es singular    gate=MISS  swift_test=MISS (0 issues)  DOUBLE-MISS=True
pt singular    gate=MISS  swift_test=MISS (0 issues)  DOUBLE-MISS=True
```

- 为什么**只有单数**中招：复数形态替换成英文 title 会因丢掉 `\(number)` 而被单测的计数断言捕获（14 issues），单数形态英文 title 不含数字、原本也不要求含数字，于是两侧都无话可说。
- 严重度：**低-中**。与 F7 同源（都是「回填比对集合不完整」），但触发条件比 F7 窄——需要有人把文案替换成**另一条**英文串而非英文 message；F7 那条更常见的路径已闭合。仍有实际风险：任何「用英文 title 顶替译文」的编辑都不会被发现。
- 最小复现（不修改工作区）：
  ```
  rm -rf /tmp/m && mkdir /tmp/m && rsync -a --exclude .build --exclude .git <工作区>/ /tmp/m/ && cd /tmp/m
  python3 - <<'PY'
  import pathlib
  p = pathlib.Path('Sources/AutomntPlatform/SystemUserNotifier.swift'); s = p.read_text()
  m = "Ein freigegebener Ordner konnte nicht automatisch verbunden werden. Öffne Automnt, um die Details zu prüfen."
  assert m in s
  p.write_text(s.replace(m, "Automnt: Automatic recovery incomplete", 1))
  PY
  python3 scripts/verify-localization.py --quiet   # 期望红灯，实际 exit 0
  swift test --filter NotificationCopyTests        # 期望红灯，实际 6 tests passed
  ```
- 建议（由实现者决定）：把比对集合放宽为「fallback 分支的全部英文串（title 与 message 都算）」，并在单测里对 `englishTitle` 与 `englishMessage` 两者都断言不等；或更直接地，断言「非英语 message 必须与该语言的 title 不同、且不得等于英文 title 或英文 message」。

### F9-b（提示，非本轮要求）：单测层的品牌/动作词表仍弱于门

- `NotificationCopyTests.swift:8-16` 的 `absentActions` 是**区分大小写**的精确匹配，`:41/:43` 的品牌断言也是 ASCII `contains`。
- 于是第 3 节表格中 6 种大小写/全角变体**门红而单测绿**。这不违反本轮验收（要求是门红），门也接在 `build.sh` 里，故不构成缺口；但意味着「只跑 `swift test`」的人看不到这些形态。
- 建议：把单测的比对与门统一到「NFKC + 小写」口径，避免两层漂移。

## 10. 追加方式与工作区完整性

追加前的字节基线（前两轮原文，本节未改动其中任何字节）：

```text
bytes : 49859
sha256: 70b42e2f5b46fe4fdc45cb6207e12d8512067979d99a68b39c64e28dd5faf748
```

追加后校验：当前文件的前 49859 字节与 `/tmp/v6-prefix-before.bin`（追加前快照）逐字节相同，即**只追加、未改写前两轮原文**：

```text
$ python3 -c "
import pathlib
before=open('/tmp/v6-prefix-before.bin','rb').read()
now=pathlib.Path('release/evidence/localization-verification.md').read_bytes()
print('prefix identical:', now[:len(before)]==before)
print('baseline bytes  :', len(before))
"
prefix identical: True
baseline bytes  : 49859
```

> **关于本文件的总长度与自身 sha256**：此处同样**刻意不写**这两个数（自指会使哈希立即失效、长度会随后续追加漂移）。可独立复核的稳定量只有上面的前缀事实；读者可自行 `wc -c` 重算。

工作区完整性（复验前后逐文件 sha256 全量对照，1602 个文件）：

```text
before: 1602   after: 1602
CHANGED: ['./specs/005-swiftui-mas-gui/tasks.md', './release/evidence/localization-verification.md']
ADDED:   []
REMOVED: []
```

- `release/evidence/localization-verification.md`：本文件（追加本节所致），验证者写范围内。
- `specs/005-swiftui-mas-gui/tasks.md`：**不是本验证者所写**——该文件 mtime 为 `Oct 9 22:41:10`，即 Lead 在我复验期间登记 task-14 时的并发写入，非本轮变异实验产物。变异实验全部发生在 `/tmp/v6-mut`，副本在每条变异后已还原并与工作区逐字节一致（`SystemUserNotifier.swift` 三处 sha256 均为 `368c710e…fc80`）。
- 除上述两者外，工作区**没有任何其它文件被改动**；验证过程未修改任何产品文案、catalog、工程文件或 CLI 渠道。

## 11. 隐私抽查

对门、新测试与本轮改动文件扫描 IPv4 / `smb://` / `/Users/` / email：

```text
-- scripts/verify-localization.py
134:    re.compile(r"smb://", re.IGNORECASE),     # 检测规则本身，非私有目标
135:    re.compile(r"/Users/"),                    # 检测规则本身，非私有目标
-- Tests/AutomntPlatformTests/NotificationCopyTests.swift
25:  #expect(!text.message.contains("smb://") && !text.message.contains("/Volumes/"))   # 反向断言
103: let forbidden = ["/Volumes", "smb://", "@", "://", "/Users"]                      # 反向断言
```

均为**检测规则/反向断言**，不含真实私有目标。产品文案（`NotificationCopy`）仍只含计数与「打开 Automnt」。

## 12. 仍未验证的边界（不得当作已完成）

以下与 V5 第 11 节相同，本轮不因门/测试收紧而改变：

- **真实通知中心横幅**：只验证 `NotificationCopy` 的取值与独立编译输出，未在真实通知中心观察横幅、点击打开、前台去重、系统声音（需授权环境）。
- **真实系统 locale 解析**：门与测试都是静态检查/注入语言串，未在真实系统语言设置下验证 `Locale.preferredLanguages.first` 对 `zh-TW`/`pt-PT` 等区域码的解析。
- **GUI 内重试入口**：属 T032/T033，未实现；F3 只保证文案不谎称该动作存在。
- **复数分支未按 CLDR 落地**：`NotificationCopy` 仍是手写 `number == 1` 分支；本轮新增的 message 检查只是**结构/回填**检查，不解决复数规则缺口。
- **母语审校未完成**：八语全部为未审校草稿，本报告只做结构与术语基线核对，不对译文质量作母语级背书。**特别是**：F7/F9 检查的是「是否回填英文」，完全不判断译文是否地道或语义正确——门通过**不等于**文案已审校。
- **真实系统语言下 GUI 目视与 VoiceOver**：未以九种系统语言运行 GUI，未验证长译文换行、窄窗口重排、较大系统文字、浅深色；未做 VoiceOver 验证。门覆盖 `accessibility*` 的**文案抽取**，不等于朗读正确。
- **App Store 商店页、支持材料、品牌可用性/商标**：范围外，未验证。
- **F9 / F9-b 修复未做**：本验证者只读，两处已给出最小复现与建议，未修改任何源码、脚本或测试。

# V7 独立复验：NotificationCopy 回填比对集合扩宽（F9 / F9-b）

本轮由 verifier4 复验共享任务 task-16（V7），对象为 Lead 针对 V6 所报 F9 / F9-b 的修复：`scripts/verify-localization.py` 的 `NotificationCopy` 回填比对集合由「英文 fallback 的 message」扩宽为「英文 fallback 的 **title + message 全部串**」，以及 `Tests/AutomntPlatformTests/NotificationCopyTests.swift` 的 `message != english.title` 断言与品牌/动作词的 NFKC 处理。

方式同前：**只读 + 只运行命令**，工作区未修改任何源码、资源、脚本或测试。变异全部在 `/tmp/verifier4/v7/repo`（`rsync` 副本）上进行。本文件为**追加**，上一轮（V4）正文未改动——追加前 71393 字节 / sha256 `bc9a7a5be6132eca1a7ee76335382f558c4b6e9fe2713841ce091d65ad3c0d82`。

复验基线（开工时与结束时一致）：

```text
$ shasum -a 256 scripts/verify-localization.py Tests/AutomntPlatformTests/NotificationCopyTests.swift \
    Sources/AutomntPlatform/SystemUserNotifier.swift Sources/AutomntCore/FailureNotification.swift
1dc4f8c60a9775b270b25492b723c3b56da360e71cc8aa71cbe8aa84db99e789  scripts/verify-localization.py
9ded44fbced4197d53077e7159e9b847d3e22d58abc7ff838e0da942582e22ef  Tests/AutomntPlatformTests/NotificationCopyTests.swift
368c710e12343ca81896fa7d7ccce46b44c53ec600fa735d5029f589a7a6fc80  Sources/AutomntPlatform/SystemUserNotifier.swift
2897bdc6e491fe7a6202158deb336f4cf0957ae30e54598032fd7fbf96e936e1  Sources/AutomntCore/FailureNotification.swift
```

`FailureNotification.swift` 的 sha256 与 V5 记录的契约期望值一致，即**CLI 渠道文案未被本轮改动**。

## V7 结论摘要

| 项目 | 结果 |
| --- | --- |
| F9 修复（四语 singular message → 英文 title） | **通过**：门 exit 1 **且** 单测 exit 1（双红） |
| F6 修复（全角 `ａｕｔｏｍｎｔ`） | **通过**：门 exit 1 **且** 单测 exit 1（F9-b 已修） |
| F7-b 修复（大小写变体动作词） | **通过**：门 exit 1 **且** 单测 exit 1（F9-b 已修） |
| 未过度收紧（反向确认） | **通过**：未变异门 exit 0、单测 6/6；正确 `Automnt` 与无关 `AUTOMNT` 不误判；白名单逐项精确无 slack |
| 回归（swift test / build.sh / self-test / xcodebuild） | **通过**：61/17 + 94/28 全绿；295 passed 0 failed；BUILD SUCCEEDED |
| **是否存在新的双双漏判** | **是（F10）**：比对集合只含英文 fallback 分支的 3 个**精确字面量**，「英文原句 + 装饰」类内容门与单测**同时放行** |

**总体判定：未通过。** F9/F9-b 修复有效，但比对集合口径引入了新的盲区类别（F10）。

## 1. F9 / F6 / F7-b 复跑（要求 1、2）

### F9：四语 singular message → 英文 title

变异：把 de / fr / es / pt-BR 的 **singular** message 字面量替换为英文 fallback 的 title `"Automnt: Automatic recovery incomplete"`。

```text
-------- gate exit=1
FAIL  4 problem(s) in the hand-written NotificationCopy banner copy:
  - NotificationCopy branch for 'de' reuses English copy verbatim: 'Automnt: Automatic recovery incomplete'
  - NotificationCopy branch for 'fr' reuses English copy verbatim: 'Automnt: Automatic recovery incomplete'
  - NotificationCopy branch for 'es' reuses English copy verbatim: 'Automnt: Automatic recovery incomplete'
  - NotificationCopy branch for 'pt' reuses English copy verbatim: 'Automnt: Automatic recovery incomplete'
-------- swift test exit=1
Test messageBodiesAreTranslatedAndDistinctPerLanguage() recorded an issue at NotificationCopyTests.swift:114:17:
  Expectation failed: text.message != english.title        (4 次)
Test messageBodiesAreTranslatedAndDistinctPerLanguage() failed after 0.001 seconds with 5 issues.
Test run with 6 tests in 1 suite failed after 0.002 seconds with 5 issues.
```

**门红 + 单测红，F9 已修。**

### F6：全角品牌

变异：把 zh-Hans title 的 `Automnt` 换成全角 `ａｕｔｏｍｎｔ`。

```text
-------- gate exit=1
FAIL  2 problem(s) in the hand-written NotificationCopy banner copy:
  - NotificationCopy branch 2 omits the GUI brand 'Automnt': 'ａｕｔｏｍｎｔ：自动恢复未完成'
  - NotificationCopy branch 2 uses the CLI brand spelling 'automnt' in the GUI channel: 'ａｕｔｏｍｎｔ：自动恢复未完成'
-------- swift test exit=1
Test guiChannelUsesCapitalizedBrandOnly() recorded an issue at NotificationCopyTests.swift:44:17:
  Expectation failed: text.title.contains("Automnt")          (3 次)
Test guiChannelUsesCapitalizedBrandOnly() recorded an issue at NotificationCopyTests.swift:47:17:
  Expectation failed: !normalized.contains("automnt")         (3 次)
Test guiChannelUsesCapitalizedBrandOnly() failed after 0.001 seconds with 6 issues.
```

**门红 + 单测红，F6 的 NFKC 处理在两侧都已生效（F9-b 已修）。**

### F7-b：动作词大小写变体

变异：es 复数 message 末尾追加 ` VOLVER A CONECTAR`。

```text
-------- gate exit=1
FAIL  1 problem(s) in the hand-written NotificationCopy banner copy:
  - NotificationCopy branch 7 advertises an action the GUI does not provide: 'Volver a conectar' in '… VOLVER A CONECTAR'
-------- swift test exit=1
Test guiBannerDoesNotPromiseAnActionTheAppLacks() recorded an issue at NotificationCopyTests.swift:63:21:
  Expectation failed: !folded.contains(Self.normalize(phrase).lowercased())   (2 次)
Test guiBannerDoesNotPromiseAnActionTheAppLacks() failed after 0.003 seconds with 2 issues.
```

**门红 + 单测红，F7-b 已修。**

## 2. 反向确认：没有过度收紧（要求 3）

```text
$ python3 scripts/verify-localization.py        # 未变异
PASS  all 102 source string(s) have non-empty entries in all 9 languages
PASS  no non-English value copies the English source outside the documented brand/borrowed-word allowlist
PASS  NotificationCopy has distinct, branded, redacted copy in every language and names no action the GUI lacks
EXIT=0

$ swift test --filter NotificationCopyTests
Test run with 6 tests in 1 suite passed after 0.003 seconds.
```

**正确 `Automnt` 与无关全大写不误判**：把一个 title 改成 `"AUTOMNT Automnt：自动恢复未完成"`（含正确品牌 + 无关全大写词）：

```text
GATE EXIT=0     swift test EXIT=0
```

即品牌检查**保持大小写敏感**是对的：全大写 `AUTOMNT` 不是小写 CLI 拼写，不触发；若改成小写折叠则会误判。Lead 对该点的自我纠正已由本轮实测确认。

### 白名单逐项独立重算

我独立计算了「catalog 中实际存在 identical 的 (语言, 英文源) 对」，与门里 `TRANSLATION_ALLOWLIST` 比对：

```text
allowlist as coded:                actually-identical:
   zh-Hans ['Automnt']                zh-Hans ['Automnt']
   zh-Hant ['Automnt']                zh-Hant ['Automnt']
   ja      ['Automnt']                ja      ['Automnt']
   ko      ['Automnt']                ko      ['Automnt']
   de      ['Automnt','Name','Port','Server']   de ['Automnt','Name','Port','Server']
   fr      ['Automnt','Notifications','Port']   fr ['Automnt','Notifications','Port']
   es      ['Automnt']                es      ['Automnt']
   pt-BR   ['Automnt']                pt-BR   ['Automnt']

allowlist entries NOT needed (slack): {}          <- 没有多余豁免
identical pairs NOT allowlisted (would fail): {}  <- 没有漏豁免
```

**白名单与 V4/V5 基线逐项一致，未放宽**：零 slack（不存在"开了没用到"的豁免项），也零 missing。

### 白名单不是"整语豁免"

变异：把 catalog 的 de `Eject` 改成英文源 `Eject`（`Eject` 不在 de 允许集内）：

```text
FAIL  1 key(s) reuse the English text for other languages (outside the allowlist):
  - 'Eject'  identical in: de
GATE EXIT=1
```

即豁免精确到 `(语言, 源串)` 对，某语言既有豁免不会为新回填开路。

## 3. 新变异攻击（要求 4）——发现 F10

对当前 `SystemUserNotifier.swift` 施加共 13 类变异，逐条记录「门红/绿 + 单测红/绿」。全部在 `/tmp` 副本，实验后 `/tmp/verifier4/v7/repo` 已恢复 pristine（门 exit 0）。

| 编号 | 变异 | 门 | 单测 | 双漏？ |
| --- | --- | --- | --- | --- |
| m1 | 四语 singular message → 英文 title（F9 原样） | 红 | 红 | 否 |
| m2 | zh-Hans title 品牌 → 全角 `ａｕｔｏｍｎｔ`（F6） | 红 | 红 | 否 |
| m3 | es message 追加大写 `VOLVER A CONECTAR`（F7-b） | 红 | 红 | 否 |
| m11 | ko message → 英文 fallback message | 红 | 红 | 否 |
| m8b | 英文 fallback 分支整体换成 de 文案 | 红 | 红 | 否 |
| m7b | 英文分支内新增一条字面量 == ko 正确译文 | **红（误报）** | 编译错 | 否（假阳性） |
| m4 | ja message := ko message（跨语互换） | **绿** | 红 (:102) | 否（单测兜住） |
| m13 | 把无选择器 fallback 移到所有语种之前 | **绿** | 红 (51 issues) | 否（单测兜住） |
| m14 | ko message := 无 `\(number)` 的英文句 | 绿 | 红（count 断言） | 否 |
| m6 | ja message := 自己的 title | 绿 | 红 | 否 |
| m15 | 英文分支内定义一条 ko 字面量（合法 Swift） | 绿 | 绿 | —（语义上是死代码，非漏判） |
| **m17** | **ko message := `"Notice: " + 英文 fallback 原句`** | **绿** | **绿** | **是（F10）** |
| **m5** | **de message := 旧版英文措辞（与现 en 字面量不同）** | **绿** | **绿** | **是（F10 同类）** |

### F10 最小复现（本轮最关键发现）

在 `/tmp` 副本把 `Sources/AutomntPlatform/SystemUserNotifier.swift:58` 的 ko message：

```swift
// 改为（= 英文 fallback 原句加前缀，保留 \(number)，保留 Automnt）
"Notice: \(number) shared folders could not be mounted automatically. Open Automnt to review."
```

实测：

```text
--- gate ---
GATE EXIT=0
--- swift test --filter NotificationCopyTests ---
Suite NotificationCopyTests passed after 0.003 seconds.
Test run with 6 tests in 1 suite passed after 0.003 seconds.
TEST EXIT=0
```

**门绿 + 单测绿 = 双双漏判。** 标题变体同样成立：把 `:55` 的 ja title 改为 `"Automnt: Automatic recovery incomplete (details)"` → 门 exit 0、单测 exit 0。

**为什么现有全部规则都放行**：该串

- ≠ 英文 title、≠ 英文 message、≠ 英文 fallback 的精确字面量 → 集合成员判定失效；
- message 在语言间仍唯一 → `Set(bodies).count == languages.count` 通过；
- 含 `\(number)` → count 断言通过；
- 含 `Automnt` → 品牌断言通过；
- 不在禁用动作词表内。

同类：`m5` 把 de message 换成**旧版英文措辞**（`"\(number) shared folders were not mounted. Open Automnt to review."`，与当前 en 字面量只差措辞）同样双绿。**说明 F10 不是"加个前缀"的特例，而是"比对集合是精确字面量集合"这一口径的通病**：任何非逐字复制的英文内容都逃逸。

### 一处门误报（假阳性）

`m7b` 在英文 fallback 分支里放入一条与 ko 正确译文相同的字符串后，门报：

```text
FAIL  NotificationCopy branch for 'ko' reuses English copy verbatim: '공유 폴더 \(number)개를 …'
```

门把"出现在英文分支里的串"一律当英文，于是与该串同形的 ko 正确译文被反判为回填。属方向相反的缺陷（假阳性），优先级低，但说明该集合口径与"语言归属"脱钩、只是位置约定。注：该变异同时改变了 Swift 元组基数（编译失败），所以只作为口径局限性证据，不作为可编译反例。

## 4. 建议的比对集合口径（可堵住 F10，且实测零误报）

把"精确集合成员"判定改为**骨架归一化后的双向子串包含**：

1. 归一化 `sk(s)`：NFKC → 把 `\(...)` 插值与数字替换为空格 → 小写 → 去标点 → 折叠空白；
2. 对每个非英文分支的 title/message 与英文 fallback 的全部串比较，满足下列任一即失败：
   - `sk(nonEn) == sk(en)`，或
   - `sk(en) ⊂ sk(nonEn)`（英文原句被嵌入，如 F10），或
   - `sk(nonEn) ⊂ sk(en)`。

实测（`/tmp/verifier4/v7/rule_probe.py`，逐分支打印 `substring-of-EN`）：

```text
--- PRISTINE（12 个非英文 message + 各 title，全部 False = 零误报）
  zh-hant  substring-of-EN=False  \(number) 個共享檔案夾未能自動掛載。請打開 Automnt 查看詳細資訊。
  zh       substring-of-EN=False  \(number) 个共享文件夹未能自动挂载。请打开 Automnt 查看详情。
  ja       substring-of-EN=False  \(number) 個の共有フォルダを自動でマウントできませんでした。…
  ko       substring-of-EN=False  공유 폴더 \(number)개를 자동으로 마운트하지 못했습니다. …
  de       substring-of-EN=False  Ein freigegebener Ordner konnte nicht automatisch verbunden …
  fr       substring-of-EN=False  Un dossier partagé n’a pas pu être monté automatiquement. …
  es       substring-of-EN=False  No se ha podido montar automáticamente una carpeta compartida. …
  pt       substring-of-EN=False  Não foi possível montar automaticamente uma pasta compartilhada. …

--- m17（F10）: ko substring-of-EN=True   -> 直接抓到
--- m5 : de substring-of-EN=False          -> 需第二条规则补
```

**补充规则（针对 m5 这类"旧英文措辞"）**：`de` 分支的 message 在 pristine 下本来就含非 ASCII（`Öffne` / `konnte` / `prüfen`），而 `m5` 注入的是纯 ASCII 英文，可用「NotificationCopy 的 de 分支 message 必须含非 ASCII」判定。我核对了推广风险：catalog 里 de 有 **39 条**合法纯 ASCII 译文（如 `Mitteilungen`、`Das Verbinden wird vom Befehlszeilendienst gesteuert.`），所以该规则**只能用于 NotificationCopy 的 de 分支**，不能推广到 catalog。

## 5. 回归（要求 5，全绿）

```text
$ swift test
Test run with 61 tests in 17 suites passed after 0.760 seconds.     # AutomntCoreTests
Test run with 94 tests in 28 suites passed after 1.130 seconds.    # AutomntPlatformTests
swift test EXIT=0

$ bash scripts/build.sh /tmp/verifier4/v7/automnt-v7
3.4.0
build.sh EXIT=0

$ /tmp/verifier4/v7/automnt-v7 --version
3.4.0

$ /tmp/verifier4/v7/automnt-v7 --self-test
Self-tests: 295 passed, 0 skipped, 0 failed
EXIT=0

$ xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt -configuration Release \
    -derivedDataPath .build/xcode-v7-verify CODE_SIGNING_ALLOWED=NO build
** BUILD SUCCEEDED **
xcodebuild EXIT=0
```

`NotificationCopyTests` 单测项数：6（1 suite）。`scripts/build.sh:10` 仍以 `--quiet` 调用门，即默认模式包含新增的回填与 NotificationCopy 检查。

## 6. 工作区完整性

- 本轮未修改工作区任何源码、资源、脚本、测试；唯一写入是本文件的追加。
- 变异实验全部在 `/tmp/verifier4/v7/repo`；实验结束后该副本已恢复 pristine（`python3 scripts/verify-localization.py --quiet` exit 0，catalog 与 `SystemUserNotifier.swift` 均从工作区重新拷贝）。
- 工作区 `apps/Automnt/Resources/Localizable.xcstrings` sha256 = `019f80c1…a0ed`（mtime 仍为 Oct 9 15:47），与 V4 基线一致，未被本轮误写（我曾用 m9 变异 catalog，其目标路径硬编码为 `/tmp/verifier4/v7/repo/...`，已核对）。
- 追加前本文件 71393 字节 / sha256 `bc9a7a5b…c0d82`；下方比对确认前文未变。

```text
$ wc -c /tmp/verifier4/v7/evidence-prefix.md   # 追加前保存的前缀
   71393 /tmp/verifier4/v7/evidence-prefix.md
$ head -c 71393 release/evidence/localization-verification.md | shasum -a 256
bc9a7a5be6132eca1a7ee76335382f558c4b6e9fe2713841ce091d65ad3c0d82
```

## 7. 仍未验证的边界（要求 6）

- **真实通知中心**：未在授权环境投递真实横幅，未验证横幅展示、点击行为与前台去重（`suppressedForeground`）。本轮只验证文案取值与静态/单测规则。
- **真实系统 locale**：`Locale.preferredLanguages.first` 的实际取值与 `hasPrefix` 匹配（含 `zh-TW`/`zh-HK`/`pt-PT` 等区域变体）未在真实系统语言下验证。
- **GUI 内重试入口**：不存在，属 T032/T033 范围；本轮只保证文案不谎称该动作存在。
- **复数未按 CLDR**：`NotificationCopy` 仍为硬编码 `number == 1`，fr/es/pt-BR 的 `many`（百万倍数）与 `0` 分支未按 CLDR 区分；catalog 无 plural 变体。
- **母语审校未完成**：catalog 102 条 + `NotificationCopy` 九语全部为草稿，无母语审校，也无可信的机器翻译质量判定。
- **真实系统语言 GUI 目视与 VoiceOver**：未验证长译文换行、窄窗口、较大文字、浅深色，以及 VoiceOver 朗读。

## 8. V7 缺陷清单

**F10（中，本轮新发现，双双漏判）**：`NotificationCopy` 回填比对集合为英文 fallback 分支的**精确字面量集合**，因此"英文原句 + 前缀/后缀"或"英文旧措辞"这类内容，门与单测同时放行。

- 位置：`scripts/verify-localization.py:254-267`（`english_forms` 集合与 `intersection`），对应单测 `Tests/AutomntPlatformTests/NotificationCopyTests.swift:108-116`。
- 最小复现：`SystemUserNotifier.swift:58` ko message 改为 `"Notice: \(number) shared folders could not be mounted automatically. Open Automnt to review."` → 门 exit 0、单测 exit 0。
- 建议：按第 4 节改为骨架归一化双向子串包含，并对 de 分支补"message 必须含非 ASCII"。

**F11（低，门假阳性）**：门以"串是否出现在英文分支"判定语言归属，会把恰好与某语正确译文同形的英文分支串反判为回填（`verify-localization.py:260-267`）。方向与漏判相反，优先级低。

**观察（非缺陷，供 Lead 判断）**：跨语言 message 互换（m4）与 fallback 位移（m13）门仍为绿，目前只靠单测兜住；若希望门也覆盖，可对每个 `hasPrefix` 分支断言其 message 必须含与该语言对应的非 ASCII 字符（de/fr/es/pt-BR 亦满足，因为其 message 本就含非 ASCII）。
