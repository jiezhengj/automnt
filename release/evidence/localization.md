> 2026-10-11 本轮历史范围说明（仅 Feature005）：本轮仅修改文档与 demo；独立密码 CRUD、8 步向导、多选、用户 CLI 导入/检查、内部配置目录选择已撤销，现行要求以 [spec](../../specs/005-swiftui-mas-gui/spec.md) 与 [contracts](../../specs/005-swiftui-mas-gui/contracts/gui-and-release.md) 为准。系统认证在 sandbox/helper 中的复用未验证；已有 CLI 配置自动呈现与共享配置 owner 尚未实现。Automnt 暂用。以下历史正文与测试结果保留，旧资源、截图与测试不证明新版通过；CLI Feature001–004 的证据语义不变。

# L1 GUI 九语本地化资源实测记录

本轮实现共享任务 task-10（L1 补齐 GUI 九语本地化资源）。所有命令均在 `/Users/jiezhengj/Documents/Project/automnt` 实际执行，下列数字来自真实脚本输出与真实编译产物，不是推断。

## 现状复核（不采信任务描述数字）

用独立脚本抽取 `apps/Automnt/*.swift` 与 `apps/Automnt/Views/*.swift` 中 `Text`、`Button`、`Label`、`Toggle`、`Section`、`ContentUnavailableView`、`navigationTitle`、`LabeledContent`、`TextField`、`SecureField` 的字面量，以及 `String(localized: "…")` 与 `confirmationDialog("…")`，去重后与 catalog 键集合求差。

| 抽取口径 | 源码文案 | catalog 原有 | 缺失 |
| --- | --- | --- | --- |
| Lead 口径（不含 `TextField`/`SecureField`/`confirmationDialog`） | 95 | 10 | 85 |
| 本轮口径（含上述三类） | 102 | 10 | 92 |

两类口径结论一致：缺口是"设置 → 通知"以外的全部界面文案。本轮按更大口径补齐（102 条），并顺带覆盖了 Lead 口径遗漏的输入框标签与删除确认对话框标题。

## 改动文件

| 文件 | 改动 |
| --- | --- |
| `apps/Automnt/Resources/Localizable.xcstrings` | 10 → 102 条键（新增 93 条，1 条因品牌大小写改名）；`sourceLanguage: en`、`version: 1.0`、`comment` + `extractionState: manual` + `localizations.<lang>.stringUnit.{state,value}` 结构不变 |
| `apps/Automnt/AutomntApp.swift` | 仅 1 行：`"…Allow automnt notifications…"` → `"…Allow Automnt notifications…"`（共享品牌大小写）。无其它逻辑改动 |

未改：`Sources/`、`Tests/`、`scripts/`、`project.pbxproj`、`Package.swift`。

## 覆盖与结构验证（原始输出）

```text
$ python3 /tmp/verify_coverage.py
extracted source strings : 102
catalog keys             : 102
missing (must be 0)      : 0
keys missing a language  : 0
empty values             : 0
non-en values identical to English key (expected only brand/technical): 13
comments missing review note: 0
extractionState values   : ['manual']
sourceLanguage/version   : en / 1.0
EXIT=0

$ python3 -c "import json;json.load(open('apps/Automnt/Resources/Localizable.xcstrings'));print('OK')"
OK
```

13 条"非英语取值与英文键相同"中，9 条是品牌 **Automnt**（按规则不翻译），另 4 条为该语言真实写法：de `Name`/`Port`/`Server`，fr `Port`/`Notifications`。均非漏译。

品牌一致性：`grep -c "Allow automnt notifications"` 在 catalog 与源码中均为 0（旧小写键已改名，英文值同步更新）。

隐私抽查：catalog 中无 IP、无 `smb://` 具体目标、无 `/Users/` 路径，仅有通用示例 `/Volumes`。

## 编译产物验证

```text
$ xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt -configuration Release \
    -derivedDataPath .build/xcode-l10n CODE_SIGNING_ALLOWED=NO build
** BUILD SUCCEEDED **

$ ls .build/xcode-l10n/Build/Products/Release/Automnt.app/Contents/Resources
de.lproj  en.lproj  es.lproj  fr.lproj  ja.lproj  ko.lproj  pt-BR.lproj  zh-Hans.lproj  zh-Hant.lproj
```

九个 lproj 目录均含 `Localizable.strings`（UTF-16 XML plist），各自 **102** 条键。

### 九语抽样对照（从编译产物 `Localizable.strings` 解出，非 catalog 源文件）

| 键 | en | zh-Hans | zh-Hant | ja | ko | de | fr | es | pt-BR |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `Servers` | Servers | 服务器 | 伺服器 | サーバ | 서버 | Server | Serveurs | Servidores | Servidores |
| `Eject` | Eject | 弹出 | 退出 | 取り出す | 추출 | Auswerfen | Éjecter | Expulsar | Ejetar |
| `Open in Finder` | Open in Finder | 在 Finder 中打开 | 在 Finder 中打開 | Finderで開く | Finder에서 열기 | Im Finder öffnen | Ouvrir dans le Finder | Abrir en el Finder | Abrir no Finder |
| `SMB credentials…` | SMB credentials… | SMB 登录信息… | SMB 登入資訊… | SMBログイン情報… | SMB 로그인 정보… | SMB-Anmeldedaten… | Identifiants SMB… | Credenciales SMB… | Credenciais SMB… |
| `Include this shared folder` | Include this shared folder | 启用此共享文件夹 | 啟用此共享檔案夾 | この共有フォルダを有効にする | 이 공유 폴더 활성화 | Diesen freigegebenen Ordner aktivieren | Activer ce dossier partagé | Activar esta carpeta compartida | Ativar esta pasta compartilhada |
| `Delete saved credentials?` | Delete saved credentials? | 要删除已存储的登录信息吗？ | 要刪除已儲存的登入資訊嗎？ | 保存済みのログイン情報を削除しますか？ | 저장된 로그인 정보를 삭제할까요? | Gesicherte Anmeldedaten löschen? | Supprimer les identifiants enregistrés ? | ¿Eliminar las credenciales guardadas? | Excluir as credenciais salvas? |

任务要求的"至少 3 语种 × 3 条、非英文原样"以上表全部满足（9 语种 × 6 条）。除品牌 `Automnt` 与该语言本身的同形词外，编译产物中没有任何非英语条目等于英文原样：

```text
[zh-Hans] keys=102  identical-to-English=1   # 仅 'Automnt'
[zh-Hant] keys=102  identical-to-English=1   # 仅 'Automnt'
[ja]      keys=102  identical-to-English=1   # 仅 'Automnt'
[ko]      keys=102  identical-to-English=1   # 仅 'Automnt'
[de]      keys=102  identical-to-English=4   # Automnt, Name, Port, Server
[fr]      keys=102  identical-to-English=3   # Automnt, Notifications, Port
[es]      keys=102  identical-to-English=1   # 仅 'Automnt'
[pt-BR]   keys=102  identical-to-English=1   # 仅 'Automnt'
```

## 未受影响的回归

```text
$ swift build
Build complete! (0.61秒)

$ swift test
Test run with 46 tests in 16 suites passed after 0.851 seconds.   # AutomntPlatformTests
Test run with 86 tests in 26 suites passed after 0.253 seconds.   # AutomntCoreTests
swift test exit=0
```

## 术语与语气依据

遵循 `specs/005-swiftui-mas-gui/design/localization.md` 的「核心文案候选」与「九语术语候选基线」表定词：自动挂载、自动恢复、弹出、停用、共享文件夹、访问权限等逐语按该表取值，不机械替换句中所有词。品牌 **Automnt**、**SMB**、**Spotlight**、**Finder**、`/Volumes`、`Library/Application Support` 保留原文。破坏性/权限/修复类文案（删除凭据、弹出、修复后台挂载、目录授权、通知被拒）按语义完整表达并给出可执行下一步。

**术语统一的真实范围（第一轮时并不完整，此处如实修正）**：第一轮只统一了 **catalog 内部** es 的「恢复」术语（`Allow notifications to receive alerts when automatic recovery is incomplete.` 与 `Notifications are off. Allow Automnt notifications…` 两条，`restauración` → `recuperación`）。**当时并未覆盖 GUI 通知横幅路径**——该路径的文案是 `Sources/AutomntPlatform/SystemUserNotifier.swift` 中 `enum NotificationCopy` 的手写九语分支，不在 catalog 内，第一轮漏改，es 仍为 `Restauración automática incompleta`。因此第一轮本文档「es 已统一」的表述在通知路径上不成立。该缺口已在第二轮修复（见下文），现在条文所述才与事实一致。

## 复核状态：全部新译文均为未获母语审校的草稿

- 本轮新增的 93 条、以及改动过的既有条目，其九语取值**全部是未获母语审校的草稿（draft translations require native review）**。没有一条声称已通过母语审校或已与 macOS 27 系统界面逐项对照。
- 为满足诚实标注要求，catalog 中 **102 条键的 `comment` 全部**以 `Draft translations require native review.` 结尾（覆盖检查中 `comments missing review note: 0`）。
- 语言覆盖完整（九语齐全），未因"未经审校"而删减语言或退回双语。
- 仍需母语审校的语言：**zh-Hans、zh-Hant、ja、ko、de、fr、es、pt-BR 全部八种**。
- 仍需重点复核的条目（语义/术语风险最高）：

| 条目 | 风险 |
| --- | --- |
| `Notification access could not be checked. Check Notifications in System Settings.` | 系统设置中的"通知"面板名各语措辞需与 macOS 实际界面比对 |
| `Open Login Items Settings` | 「登录项/登入項目/ログイン項目/로그인 항목/Anmeldeobjekte/Ouverture/Ítems de inicio/Itens de Início」需与系统设置实际面板名一致 |
| `The command-line service controls mounting. Switch to app control before ejecting here.` | "command-line service / app control"为内部概念映射到用户语言，九语均需复核是否自然 |
| `An older command-line service is installed. Update or release it…` | "release it"（释放/解除占用）在九语中易失真，需复核 |
| `Eject`（zh-Hant 取「退出」） | 繁体「退出」与「退出應用程式」可能混淆，需与目标系统实际用语复核 |
| `Automatic recovery` / 各含 recovery 的长句（de/fr/es/pt-BR） | 基线表候选本身标注"待验证"，德语 `Verbinden` 在共享挂载语境是否歧义未验证 |
| `Mount folder`（取「Einhängepunkt / Point de montage / Punto de montaje」） | 逐语是否与「挂载文件夹」原意一致需复核 |
| `Include this server` / `Include this shared folder`（译作"启用"） | 与「启用此服务器」的开关语义是否贴合需母语确认 |
| 通知相关既有条目 | 第一轮仅统一 catalog 内 es 术语与品牌大小写，九语整体仍未审校；GUI 通知横幅（`NotificationCopy`）当时完全未纳入，已在第二轮处理 |

## 未验证边界（不得当作已完成）

- **未在 macOS 27 真实系统语言下启动 GUI 逐页目视**：只验证编译产物中九个 lproj 的取值正确，未在窗口内确认实际渲染、长译文换行、窄窗口重排与较大系统文字的布局表现。按 `AGENTS.md`「原生界面与产品文案原则」，长译文布局与 VoiceOver 尚需真实系统验证。
- **未做 VoiceOver / 辅助功能标签验证**；本轮未新增辅助功能标签资源。
- **未验证复数分支**：本轮文案不含 `%lld`/plural 变体；失败通知的复数资源属 `Sources/AutomntPlatform/SystemUserNotifier.swift` 中 `enum NotificationCopy`（手写九语分支，非独立文件）与 CLI 的 `Sources/AutomntCore/FailureNotification.swift`，均不在本轮范围；catalog 未引入 plural 规则。
- **未验证 App Store 商店页与支持材料文案**（本轮范围外）。
- **未验证品牌名称可用性/商标**。
- 测试用的探针字符串 `Zzz Unlocalized Probe` 属于另一成员的验证手段，本轮未为其建条，也不属产品文案；该字符串已在检查期间由对方从源码移除，现不在源码中。
- `--self-test`、业务逻辑、定价不属于本轮范围，未改动。

## 第二轮：V4 缺陷修复

独立复验（V4 / [localization-verification.md](localization-verification.md)）确认了第一轮的覆盖数字，但发现 GUI 通知横幅整套文案既不在 catalog 也不在防回归门口径内，并由此产生用户可见错误。本轮修复 F1–F5。

### 修复内容

| 缺陷 | 修复 |
| --- | --- |
| F1 品牌（GUI 渠道） | `NotificationCopy` 九语 title 与正文 `automnt` → `Automnt`。**CLI 渠道未动**：`Sources/AutomntCore/FailureNotification.swift` 保留小写 `automnt`，符合 `contracts/core-and-channels.md`「共同 CLI 基础文案使用 automnt，GUI 显示 Automnt」的渠道区分 |
| F2 es 术语 | `NotificationCopy` es 分支 `Restauración automática incompleta`/`restaurar` → `Recuperación automática incompleta`/`montar`，与 catalog 基线一致；同时核对 pt-BR `Recuperação automática`、fr `Rétablissement automatique`、de `Automatische Wiederherstellung` 与 catalog 同术语一致 |
| F3 不实引导（用户可见错误） | 九语正文原先都要求「打开 automnt 配置并选择『立即重新挂载 / Remount now』」，但该动作**只在 CLI 存在**（`grep -rn "Remount" apps/Automnt` 为空）。现改为契约要求的「N 个共享文件夹未能自动挂载。打开 Automnt 查看详情。」，只承诺 GUI 真有的动作。英文参考：`{N} shared folder(s) could not be mounted automatically. Open Automnt to review.` |
| F4 证据文档错误 | 订正本文档前述 es「已统一」的不实表述；`NotificationCopy` 的实际位置由不存在的 `Sources/AutomntPlatform/NotificationCopy.swift` 改为 `Sources/AutomntPlatform/SystemUserNotifier.swift`（`enum NotificationCopy`） |
| F5 防回归门口径 | `scripts/verify-localization.py` 四项缺口全部补齐（见下） |

**未实现 GUI 内重试按钮**：F3 只保证文案不谎称该动作存在；界面内重试入口属 T032/T033，本轮不做。

### F5：门的能力（每项都有变异实证）

1. **递归扫描**：`APP_DIR.glob("*.swift") + glob("Views/*.swift")` → `APP_DIR.rglob("*.swift")`。变异：在 `Views/NewFolder/ExtraView.swift` 加 `Text("R4 Probe nested unlocalized copy")` → **exit 1**（旧门 exit 0）。
2. **API 集合扩宽**：新增 `help`、`.help`、`navigationSubtitle`、`accessibilityLabel`、`accessibilityHint`、`accessibilityValue`、`Picker`、`Menu`、`Link`、`Stepper`、`GroupBox`，以及 `label:`/`title:`/`message:` 具名参数（覆盖 `Toggle(isOn:) { }` 等非首参标签形态）。变异：分别注入 `help`/`accessibilityHint`/`navigationSubtitle` → **exit 1**；注入 `Picker`/`Link`/`Stepper`/`GroupBox`/`Menu` → **exit 1**；`Toggle(isOn:) { Text("…") }` 写法经 `Text(` 命中 → **exit 1**；`Toggle(isOn:label:)` 具名参数写法 → **exit 1**。
3. **整句回填英文纳入默认检查**：新增 `TRANSLATION_ALLOWLIST`（精确到 `(语言, 英文原文)` 对，只放品牌与真实同形词），默认模式即在**白名单之外**拒绝非英语值等于英文源。白名单按实际重算，非照抄：zh-Hans/zh-Hant/ja/ko/es/pt-BR 各 1 条（`Automnt`），de 4 条（`Automnt`/`Name`/`Port`/`Server`），fr 3 条（`Automnt`/`Notifications`/`Port`）。由于是精确对，新增的英文回填即便措辞撞上已有术语类型也会失败。变异：把 `Shared folder ejected.…` 的 7 个语言回填英文 → **默认门 exit 1**（旧门默认放行，只在未接入 build 的 `--require-translated` 下失败）。
4. **`NotificationCopy` 手写九语分支纳入检查**：静态检查其九语 title/message 非空、title 互不相同、九语选择分支齐全、品牌为 `Automnt` 且不含小写 `automnt`、不含私有目标、不含 GUI 不提供的动作、es 不得出现 `Restauración/restaurar`。变异：小写品牌回填 → **exit 1**；`Remount now` 回填 → **exit 1**；`Restauración` 回填 → **exit 1**；删除 ko 分支 → **exit 1**。

### 第二轮实测输出

```text
$ python3 scripts/verify-localization.py
catalog: apps/Automnt/Resources/Localizable.xcstrings
source strings found: 102   catalog keys: 102
languages required:   en, zh-Hans, zh-Hant, ja, ko, de, fr, es, pt-BR
swift files scanned:  5 (recursive)

PASS  all 102 source string(s) have non-empty entries in all 9 languages
PASS  no non-English value copies the English source outside the documented brand/borrowed-word allowlist
PASS  NotificationCopy has distinct, branded, redacted copy in every language and names no action the GUI lacks
EXIT=0
```

九类变异（M1–M9，其中 M4 分两次注入不同 API；均在 `/tmp/l10n2/repo` 副本上进行，每次恢复后基线 exit 0）全部 exit 1，逐条原始输出见上文"每项都有变异实证"。

独立探针实测 `NotificationCopy` 九语（把源码中的 enum 直接抽为独立 `swiftc` 探针编译运行，非测试内断言）：

```text
[en]      title=Automnt: Automatic recovery incomplete
          msg  =3 shared folders could not be mounted automatically. Open Automnt to review.
[zh-Hans] title=Automnt：自动恢复未完成
          msg  =3 个共享文件夹未能自动挂载。请打开 Automnt 查看详情。
[zh-Hant] title=Automnt：自動復原未完成
          msg  =3 個共享檔案夾未能自動掛載。請打開 Automnt 查看詳細資訊。
[ja]      title=Automnt：自動復旧が完了していません
          msg  =3 個の共有フォルダを自動でマウントできませんでした。Automnt を開いて詳細を確認してください。
[ko]      title=Automnt: 자동 복구 미완료
          msg  =공유 폴더 3개를 자동으로 마운트하지 못했습니다. Automnt를 열어 자세히 확인하세요.
[de]      title=Automnt: Automatische Wiederherstellung unvollständig
          msg  =3 freigegebene Ordner konnten nicht automatisch verbunden werden. Öffne Automnt, um die Details zu prüfen.
[fr]      title=Automnt : Rétablissement automatique incomplet
          msg  =3 dossiers partagés n’ont pas pu être montés automatiquement. Ouvrez Automnt pour consulter les détails.
[es]      title=Automnt: Recuperación automática incompleta
          msg  =No se han podido montar automáticamente 3 carpetas compartidas. Abre Automnt para consultar los detalles.
[pt-BR]   title=Automnt: Recuperação automática incompleta
          msg  =Não foi possível montar automaticamente 3 pastas compartilhadas. Abra o Automnt para ver os detalhes.
```

对探针输出做机器扫描：

```text
$ grep -inE "remount|重新挂载|重新掛載|再マウント|다시 마운트|erneut verbinden|reconnecter|reconectar|volver a conectar" out.txt
NONE FOUND (good)
$ grep -nE '(^|[^A-Za-z])automnt' out.txt
NONE FOUND (good)
$ grep -inE "restauraci|restaurar" out.txt
NONE FOUND (good)
$ grep -c "Automnt" out.txt
18          # 9 语 × (title + message) 全部含大写品牌
```

回归：

```text
$ swift test
Test run with 50 tests in 16 suites passed after 2.280 seconds.   # AutomntPlatformTests（NotificationCopyTests 1 → 5 项）
Test run with 86 tests in 26 suites passed after 0.288 seconds.   # AutomntCoreTests
SUITE_EXIT=0

$ bash scripts/build.sh /tmp/automnt-l10n2
3.4.0   (退出码 0)
$ /tmp/automnt-l10n2 --version
3.4.0
$ /tmp/automnt-l10n2 --self-test
Self-tests: 295 passed, 0 skipped, 0 failed

$ xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt -configuration Release \
    -derivedDataPath .build/xcode-r4 CODE_SIGNING_ALLOWED=NO build
** BUILD SUCCEEDED **    (exit 0)
```

### 第二轮未验证边界

- **未在 macOS 27 真实系统语言下观察通知横幅**：只验证了 `NotificationCopy` 的输出取值与调用路径（helper → `SystemUserNotifier` → 应用内子进程 `NotificationChannel.swift:340-343` → `content.title/body`），未在真实通知中心看到横幅（需授权环境）。
- **未验证真实系统 locale 下的语言选择**：`Locale.preferredLanguages.first` 对 `zh-TW`/`zh-HK`/`pt-PT` 等区域码的解析依赖系统，只在测试里注入了语言字符串。
- **F3 只解决"文案不谎称"**：GUI 内仍**没有**重试入口（T032/T033 范围）。用户按通知打开 Automnt 后，能看到什么、能否重试，取决于 T032/T033 是否落地；本轮未实现。
- **复数分支依旧未落地**：`NotificationCopy` 仍是手写 `number == 1` 分支，未按 CLDR 系统规则；catalog 无 plural 变体。该缺口属实现范围外，不应被"门已通过"掩盖。
- **九语译文仍全部未获母语审校**：本轮修订的通知文案同样是未审校草稿，es/de/fr/pt-BR 的选词按基线表取值但未获母语确认。
- **`--require-translated` 仍未接入 `build.sh`**：默认模式现已覆盖白名单外的英文回填，故无需接入；该开关作为更严格的人工模式保留。
- 新增的 `Tests/AutomntPlatformTests/NotificationCopyTests.swift` 只覆盖通知横幅；其它 GUI 文案仍依赖 catalog 与门的结构检查，无逐条测试。`grep -c "automnt"` 在 GUI 编译产物中为 0 的结论只针对 `NotificationCopy` 的输出，二进制里仍可能含 CLI 渠道的小写 `automnt` 字符串（CLI 文案被链接进同一 app 可执行文件），这不违反渠道契约。

## 第三轮：V6（task-14）所报 F9 / F9-b 的修复

独立复验（V6）确认第二轮的 F6/F7/F7-b/F8 修复全部成立，但指出**回填检查的比对集合不完整**，并附带一项单测口径偏弱：

- **F9（中）**：message 回填的比对集合**只含英文 message**。把某语 message 换成**英文 title**（`Automnt: Automatic recovery incomplete`）时，它既不等于英文 message，门与单测**双双放行**。仅 singular 形态中招——plural 换成英文 title 会因丢掉 `\(number)` 被单测的计数断言抓住。
- **F9-b（提示）**：单测的品牌与动作词检查仍是 ASCII 且区分大小写，弱于门；因此 F6（全角同形字）与 F7-b（大小写变体）在门侧能红、单测侧不能。

本轮修复（**只改门与测试，未动任何产品文案**）：

1. `scripts/verify-localization.py`：`NotificationCopy` 回填检查的比对集合由「英文 fallback 分支的 message」扩宽为「英文 fallback 分支的 **title 与全部 message**」，并把报错措辞由 `reuses the English message verbatim` 改为 `reuses English copy verbatim` 以覆盖 title/message 两种情形。
2. `Tests/AutomntPlatformTests/NotificationCopyTests.swift`：
   - `messageBodiesAreTranslatedAndDistinctPerLanguage` 增加 `text.message != english.title` 与 `text.title != english.title`；
   - 品牌检查改为 NFKC 归一化（`precomposedStringWithCompatibilityMapping`）但**保持大小写敏感**——用小写折叠会把正确的 `Automnt` 误判为违规（Lead 第一版即如此，实测 27 issues 后修正）；
   - 动作词表检查改为 NFKC + 小写，与门口径一致。

### 本轮实际验证

| 验证 | 结果 |
| --- | --- |
| 未变异 | 门 exit 0；`NotificationCopyTests` 6 项全过 |
| F9 复现（四语 singular message → 英文 title） | 门 exit 1（4 条 `reuses English copy verbatim`）**且** 单测 exit 1（5 issues） |
| F6 全角 `ａｕｔｏｍｎｔ` | 门 exit 1（修前单测绿，修后**单测也红**） |
| F7-b `REMOUNT` / `reconectar` / `Erneut verbinden` | 门 exit 1，**单测也红** |
| 反向：正确的 `Automnt`、全大写 `AUTOMNT` | 门 exit 0（未过度收紧） |
| `swift test` | AutomntPlatformTests 51 tests/16 suites ＋ AutomntCoreTests 86 tests/26 suites，0 失败 |

### 仍属未验证（不因本轮修复改变）

- 门与单测检查的是**是否回填英文、品牌与动作词**，**不判断译文质量**；九语译文仍全部是未获母语审校的草稿。
- 真实通知中心横幅弹出/点击/前台去重/系统声音、真实系统 locale 区域码解析、GUI 内重试入口（T032/T033）、CLDR 复数分支均未验证。
- 本轮修复的是**防护层**，产品文案自第二轮起未再改动（`SystemUserNotifier.swift` 哈希与 V5 复验时一致）。

## 第四轮：V7（task-16）所报 F10 的修复

独立复验（V7）确认第三轮的 F9/F9-b 修复有效（F9、F6、F7-b 三类均为**门红＋单测红**），但指出**比对集合仍是「英文 fallback 分支的精确字面量」**，因此凡「英文原句 + 装饰」都不匹配：

- **F10（中，新双双漏判）**：把 `SystemUserNotifier.swift` 的 ko message 改为 `"Notice: \(number) shared folders could not be mounted automatically. Open Automnt to review."`（英文原句加前缀，保留 `\(number)` 与 `Automnt`）→ 门 exit 0 **且** 单测 exit 0。title 加后缀同理。V7 同时指出「译文回退到旧版英文措辞」属同类。
- **F11（低，假阳性）**：门以「串是否出现在英文分支」判定语言归属，会把**恰好与某语正确译文同形**的英文分支串反判为回填。

本轮修复（**只改门与测试，未动产品文案**）：

1. 新增 `skeleton()` 归一化：NFKC → 擦除 `\(…)` 插值与数字 → 小写 → 去标点符号 → 折叠空白。使 `1 shared folder` 与 `\(number) shared folders` 骨架相同，让单复数变体可比。
2. 门的回填判定由「精确集合成员」改为「骨架相等 **或** 双向子串包含」：`sk(nonEn) == sk(en)` 或 `sk(en) ⊂ sk(nonEn)` 或 `sk(nonEn) ⊂ sk(en)` 即失败（加装饰与删减两种形态一并覆盖）。
3. `NotificationCopyTests` 同步增加骨架比较与双向包含断言，使单测与门口径一致。

### 本轮实际验证

| 验证 | 结果 |
| --- | --- |
| 未变异（pristine） | 门 exit 0；`NotificationCopyTests` 6 项全过（**零误报**） |
| F10 复现（ko message = 英文原句加 `Notice: ` 前缀） | 门 exit 1（`is untranslated English (same skeleton as …)`）**且** 单测 exit 1（2 issues） |
| title 变体（ja title = 英文 title 加 ` (details)`） | 门 exit 1 |
| m5（de message 回退旧版英文措辞） | 门 exit 1 |
| `swift test` | AutomntPlatformTests 61/17 ＋ AutomntCoreTests 94/28，0 失败（含并发落地的 T009-c2） |

### 仍未堵住的一类（已写入门的文档字符串，如实标注）

**全新改写的英文句子**放进非英语分支仍无法被本门发现：把它与真实译文区分需要语言识别，而 V7 建议的「de 分支必须含非 ASCII」会**误伤合法德语**（实测 `Server nicht erreichbar` 就是纯 ASCII）。因此本门是**下限防护**，不能替代母语审校。已实测：`Automnt could not connect the shared folder to the server.` 放进 de 分支时门与单测均放行。

### 未验证边界（不因本轮修复改变）

门不判断译文质量；九语译文仍全部为未获母语审校的草稿；真实通知中心横幅/点击/前台去重、真实系统 locale 解析、GUI 内重试入口（T032/T033）、CLDR 复数分支均未验证。
