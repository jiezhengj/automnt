# 本轮资产基线与历史范围

维护者已替换 SVG 与 PNG，本轮直接使用这些文件，不重绘，不继续采用候选 03“文件夹＋连接环”。Automnt 是临时名称且名称来源受到质疑，正式品牌与名称可用性待确认。旧资产批准、T029/task18 的采用记录、hash、尺寸、生成脚本与构建通过仅说明旧版本，不证明当前替换资产获批或通过验证。

以下记录全部为旧图标历史构建与测量证据，保留以便追溯。旧场景 PNG 与 visual-board 同样退役并保留文件，不是当前视觉证据。当前替换资产的系统管线、Dock/Finder、浅深色、小尺寸与商店接受情况仍需实测；HTML/原生 demo 无法代替这些验收。

# 2026-10-13 当前内容同步缺口

本轮 Lead 只读计算并查看最新源与 Assets 输出，两者均为 1024×1024，但内容不同；未生成图标、修改资产或构建。

| 对象 | 字节数 | SHA-256 |
| --- | --- | --- |
| [最新设计源](../../specs/005-swiftui-mas-gui/design/app-icon-1024.png) | 134216 | `252be5e058528ab8fe9674f237da172cbecd462cf188e010c66976753f60bad6` |
| [Assets 512@2x](../../apps/Automnt/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png) | 149058 | `2cf5bb2b2dc674b027b878369adb21d8c72d9e70afe520e2a1f4cf521005c1bc` |

设计源为白色层叠文件夹与连续水平 infinity；Assets 为旧扁平文件夹与斜向分段链。[脚本](../../scripts/generate-app-icon.sh) 的 1024 档直接复制源字节，正常同步后应哈希一致；现有 `--check` 只查尺寸，不能识别源已更新而输出过期。此前 T029 的生成/构建、尺寸和哈希记录不证明新图标被采用。

后续 T085 必须生成所有尺寸、记录源/输出与各档内容新鲜度、确认构建实际采用，再查看应用/Finder/Dock、浅深色和小尺寸。最新产品清单与真实原生验收另见 T094。本轮确认缺口并追加任务，不宣称替换完成。

# T029 App 图标资产实测记录（历史）

本轮实现共享任务 task-18（T029）。所有命令均在 `/Users/jiezhengj/Documents/Project/automnt` 实际执行，下列像素、字节数、构建产物路径与校验输出均来自真实运行，不是推断。

**结论边界（先说清楚）**：本轮完成的是"资产存在且被构建产物真正采用"这一可验证部分。**图标视觉是否采用属维护者审美决定，本记录不宣布通过、不声明已审阅**。设计侧独立评审（[independent-experience-review.md](../../specs/005-swiftui-mas-gui/design/independent-experience-review.md):143-155）将"图标资产不符合 macOS 图标规范的可验证条件"列为阻塞项，其两项具体疑虑（源图全出血无圆角/无 alpha；未用目标系统资产管线）在本记录"外观与形态核对"一节如实复核，结论见该节。

## 现状（改动前）

- `apps/Automnt/Resources/` 只有 `Info.plist`、`LaunchAgents/`、`Localizable.xcstrings`、`Version.xcconfig`；**无 `Assets.xcassets`**。
- `Info.plist` 无 `CFBundleIconFile` / `CFBundleIconName`；`project.pbxproj` 未引用任何资产目录。
- 因此构建出的 `Automnt.app` 无图标，Finder/Dock 显示通用图标——用户可见缺口。

## 源图（不得改动）

| 项 | 值 |
| --- | --- |
| 路径 | `specs/005-swiftui-mas-gui/design/app-icon-1024.png` |
| sha256 | `2cf5bb2b2dc674b027b878369adb21d8c72d9e70afe520e2a1f4cf521005c1bc` |
| 像素 | 1024 × 1024 |
| 格式 / 色彩空间 / alpha | png / RGB / **hasAlpha: no** |
| 字节 | 149058 |

源文件**未修改**（sha256 与改动前一致，见文末复核）。同目录另有 `app-icon.svg`（836B，矢量方向稿），本轮未使用、未修改。

## 生成方式与命令

新增 `scripts/generate-app-icon.sh`（系统 `sips`，无第三方依赖）：

```text
bash scripts/generate-app-icon.sh           # 生成 appiconset
bash scripts/generate-app-icon.sh --check   # 只校验像素尺寸，不写入
```

尺寸映射（macOS 五个标称尺寸 × 1x/2x = 10 项）。除 512@2x 直接 `cp` 源图（避免重编码）外，其余用 `sips -z <px> <px>` 缩放：

| 文件名 | 声明 | 实际像素 | 字节 |
| --- | --- | --- | --- |
| `icon_16x16.png` | 16x16 | 16x16 | 578 |
| `icon_16x16@2x.png` | 32x32 | 32x32 | 1371 |
| `icon_32x32.png` | 32x32 | 32x32 | 1371 |
| `icon_32x32@2x.png` | 64x64 | 64x64 | 3692 |
| `icon_128x128.png` | 128x128 | 128x128 | 11531 |
| `icon_128x128@2x.png` | 256x256 | 256x256 | 42224 |
| `icon_256x256.png` | 256x256 | 256x256 | 42224 |
| `icon_256x256@2x.png` | 512x512 | 512x512 | 145311 |
| `icon_512x512.png` | 512x512 | 512x512 | 145311 |
| `icon_512x512@2x.png` | 1024x1024 | 1024x1024 | 149058 |
| **合计** | | | **542671** |

逐项用 `sips -g pixelWidth -g pixelHeight` 核对，**10/10 与 `Contents.json` 声明一致**：

```text
$ python3 (逐项 sips 核对 Contents.json)
file                     declared     actual      bytes  match
icon_16x16.png              16x16      16x16        578  OK
icon_16x16@2x.png           32x32      32x32       1371  OK
icon_32x32.png              32x32      32x32       1371  OK
icon_32x32@2x.png           64x64      64x64       3692  OK
icon_128x128.png          128x128    128x128      11531  OK
icon_128x128@2x.png       256x256    256x256      42224  OK
icon_256x256.png          256x256    256x256      42224  OK
icon_256x256@2x.png       512x512    512x512     145311  OK
icon_512x512.png          512x512    512x512     145311  OK
icon_512x512@2x.png     1024x1024  1024x1024     149058  OK

all match: True
total items: 10

$ bash scripts/generate-app-icon.sh --check
PASS  every appiconset PNG matches its declared pixel size   (exit 0)
```

1024 输出与源图**逐字节相同**：

```text
$ shasum -a 256 AppIcon.appiconset/icon_512x512@2x.png design/app-icon-1024.png
2cf5bb2b2dc674b027b878369adb21d8c72d9e70afe520e2a1f4cf521005c1bc  .../icon_512x512@2x.png
2cf5bb2b2dc674b027b878369adb21d8c72d9e70afe520e2a1f4cf521005c1bc  .../design/app-icon-1024.png
```

## 接入 Xcode target

新建资产目录 `apps/Automnt/Resources/Assets.xcassets/`（`Contents.json` + `AppIcon.appiconset/`）。

手工编辑 `apps/Automnt/Automnt.xcodeproj/project.pbxproj`（**未**运行 `scripts/generate-xcode-project.py`），照现有 `DDDD…` catalog 条目的风格：

- `FFFFFFFFFFFFFFFFFFFFFF01` = `PBXFileReference`，`lastKnownFileType = folder.assetcatalog`，`path = Resources/Assets.xcassets`
- `FFFFFFFFFFFFFFFFFFFFFF02` = `PBXBuildFile` 引用 01
- `DDDDDDDDDDDDDDDDDDDDDD03`（既有 Resources 构建阶段）的 `files` 加入 `FFFFFFFFFFFFFFFFFFFFFF02`
- 主组 `64292B1C…` 的 `children` 加入 `FFFFFFFFFFFFFFFFFFFFFF01`
- **`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`** 加入 Automnt target 的 Debug 与 Release 两个 `XCBuildConfiguration`

最后一项是**必须的**：第一次构建时只加了文件引用与构建阶段，`actool` 确实运行了，但因为没有 `--app-icon` 参数而**产不出任何图标**（见下方"排查记录"）。这是本轮唯一一次"改了文件但产物无图标"的情况，靠验收"看构建产物"抓到。

`apps/Automnt/Resources/Info.plist` 增加：

```xml
<key>CFBundleIconName</key><string>AppIcon</string>
```

工程文件语法有效：

```text
$ plutil -lint apps/Automnt/Automnt.xcodeproj/project.pbxproj
apps/Automnt/Automnt.xcodeproj/project.pbxproj: OK
```

## 构建产物验证（不是源文件）

```text
$ xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt -configuration Release \
    -derivedDataPath .build/xcode-icon CODE_SIGNING_ALLOWED=NO build
** BUILD SUCCEEDED **     (exit 0)
```

产物 Info.plist（`plutil -p`）含两个图标键，其中 `CFBundleIconName` 由本轮 `Info.plist` 提供，`CFBundleIconFile` 由 `actool` 的 partial info plist 自动注入：

```text
$ plutil -p .build/xcode-icon/Build/Products/Release/Automnt.app/Contents/Info.plist | grep -i icon
  "CFBundleIconFile" => "AppIcon"
  "CFBundleIconName" => "AppIcon"
```

产物 Resources 内出现真实图标资产：

```text
$ ls -la Automnt.app/Contents/Resources/
-rw-r--r--  AppIcon.icns     64694
-rw-r--r--  Assets.car      556584
drwxr-xr-x  de.lproj/ en.lproj/ es.lproj/ fr.lproj/ ja.lproj/ ko.lproj/ pt-BR.lproj/ zh-Hans.lproj/ zh-Hant.lproj/
```

```text
$ file Automnt.app/Contents/Resources/AppIcon.icns
Mac OS X icon, 64694 bytes, "ic13" type
```

`.icns` 内部块（直接解析容器）：

```text
magic=b'icns' declared_total=64694 actual_file=64694
  chunk 'ic13'   128x128@2x     49105 bytes
  chunk 'ic11'   16x16@2x        1529 bytes
  chunk 'ic04'   16x16(ARGB)      784 bytes
  chunk 'ic07'   128x128         13268 bytes
chunks: 4
```

10 个尺寸的**完整**资产在 `Assets.car` 中（`assetutil --info`），像素与 `Contents.json` 声明一致：

```text
SizeOnDisk  Scale  RenditionName          PixelSize
       330      1  icon_16x16.png         16x16
       330      2  icon_16x16@2x.png      32x32
       330      1  icon_32x32.png         32x32
       330      2  icon_32x32@2x.png      64x64
       330      1  icon_128x128.png       128x128
     33752      2  icon_128x128@2x.png    256x256
     33752      1  icon_256x256.png       256x256
    113241      2  icon_256x256@2x.png    512x512
    113241      1  icon_512x512.png       512x512
    226411      2  icon_512x512@2x.png    1024x1024
```

**关于 `.icns` 只有 4 块**：`xcodebuild` 对资产目录做 thinning（`builtin-linkAssetCatalog --thinned`，同一次构建的 `assetcatalog_output/unthinned/` 为空目录）。`.icns` 是给不支持资产目录的旧路径用的遗留表示，macOS 27 从 `Assets.car` 按需取图，故 4 块不构成尺寸缺失。已用下面"真实消费路径"验证 macOS 实际取到的是完整资产。

## 真实消费路径验证（用户会看到什么）

用 `NSWorkspace.shared.icon(forFile:)` 读**构建产物**，按 7 档尺寸渲染并采样像素（独立 `swiftc` 探针，非推断）：

```text
$ /tmp/iconprobe <build product>
NSWorkspace icon for .../Automnt.app
  16x16: corner alpha=[0, 0, 0, 0] center alpha=255  reps=32
  32x32: corner alpha=[0, 0, 0, 0] center alpha=255  reps=32
  64x64: corner alpha=[0, 0, 0, 0] center alpha=255  reps=32
  128x128: corner alpha=[0, 0, 0, 0] center alpha=255 reps=32
  256x256: corner alpha=[0, 0, 0, 0] center alpha=255 reps=32
  512x512: corner alpha=[0, 0, 0, 0] center alpha=255 reps=32
  1024x1024: corner alpha=[0, 0, 0, 0] center alpha=255 reps=32
```

渲染出的 256px 图像经目视确认：**蓝色圆角方形 + 白色文件夹 + 两个连接环**，四角透明（圆角由系统生成）。与 `design/app-icon-1024.png` 的图形一致，说明 macOS 确实通过资产目录取到了本轮的图标，而不是回退到通用图标。

## 外观与形态核对（如实记录，不编造）

### 明暗外观

**未做深色图标变体，本轮也没有做"明暗核对"。** 依据与实测如下：

1. 源图是单一不透明位图，不含任何外观分层信息；`app-icon-1024.png` 的 `hasAlpha: no`。
2. 实测资产目录对 `AppIcon` 的 `luminosity/dark` 外观变体的支持：向 `AppIcon.appiconset` 加入 `appearances: [{appearance: luminosity, value: dark}]` 后，`actool` 报 **`warning: The app icon set "AppIcon" has an unassigned child.`**，且该 rendition **未进入** `Assets.car`（`assetutil` 中该 AppIcon 只有 1 条 16x16，无 dark）。即：**当前 macOS 27 资产目录路径不会把 `luminosity/dark` 变体用于 macOS App Icon**。
3. 本轮产物的 `Assets.car` 中，10 条 AppIcon rendition 的记录**不含任何 appearance 键**（`assetutil` 键集合：`AssetType, BitsPerComponent, ColorModel, Colorspace, Compression, Encoding, Icon Index, Name, NameIdentifier, Opaque, PixelHeight, PixelWidth, RenditionName, SHA1Digest, Scale, SizeOnDisk, Sizes`）。

因此明暗外观变体**在本轮不适用**（而非"不适用但已核对"）。若维护者要按 macOS 26+/27 的分层图标（Liquid Glass / 深色 / 着色）交付，需要走 **Icon Composer** 管线：本机存在 `/Applications/Xcode.app/Contents/Applications/Icon Composer.app`（版本 27.0，build 129），其 `ictool` 以 `.icon` 文档为输入（`--rendition` 支持 `Default`/`TintedDark` 等），**不能**由扁平 PNG 直接合成 `.icon`（实测 `ictool app-icon-1024.png …` 报 `Missing required "icon.json" file.`）。该管线需要维护者提供或确认 `.icon` 分层源，属本轮范围外，未做。

### 形态：全出血方块 vs 系统圆角

设计侧评审的阻塞证据是"PNG 无 alpha、SVG 全出血无 `rx` 圆角"。复核结果分三层，并做了**对照实验**（避免只看我方图标就下结论）：

- **源图确实是不透明全出血方块**：实测 `app-icon-1024.png` 四角 RGBA 均 alpha=255；同目录 `app-icon.svg` 背景为 `<rect width="1024" height="1024">`，无 `rx`。
- **产物中的资产也是不透明方块**：从构建产物的 `AppIcon.icns` 解出各尺寸 PNG（16/32/128/256），四角 alpha 同样为 255。即 `actool` **没有**替我们在资产里烘焙圆角。
- **但系统在呈现时施加遮罩**：`NSWorkspace.shared.icon(forFile:)` 渲染后四角 alpha=0（见上一节）。

为确认"圆角来自系统而非我们的资产"，另建了一个**对照应用** `/tmp/maskcontrol/Control.app`：唯一差别是其图标是一张纯不透明红色方块（`hasAlpha: no`，四角 RGBA=(255,0,0,255)）。实测：

```text
=== CONTROL (opaque red square) ===
center      : (249,0,0,a=255)      <- 确认渲染的是对照图自己的红色美术
corner TL   : (0,0,0,a=0)          <- 但四角仍被抹成透明
just inside : (0,0,0,a=0)
edge mid-top: (0,0,0,a=0)

horizontal extent of opaque content at y=center: x=15…240  (canvas 0…255)
vertical   extent at x=center:               y=18…243
=> inset left=15 right=15 top=18 bottom=12

=== OURS ===
horizontal extent of opaque content at y=center: x=15…240  (canvas 0…255)
vertical   extent at x=center:               y=18…243
=> inset left=15 right=15 top=18 bottom=12
```

对照与我们得到**逐像素相同**的遮罩轮廓（约 6% 内缩的圆角方形），且对照图确实渲染了自己的红色。因此：

- **"源图必须自带圆角"在本轮实测中不成立**——只要美术填满整幅，macOS 27 的图标遮罩就会产生系统圆角与内缩，与资产是否自带 alpha 无关。
- 设计侧证据（"PNG 无 alpha、无 `rx` 圆角"）描述的事实正确，但**不足以单独判定**"不符合 macOS 图标规范"。

**仍然成立、本轮未解决的**：分层 / Liquid Glass / 深色 / 着色外观（见上一节）——那些**不是**系统遮罩能补的，需要 Icon Composer 的 `.icon` 分层源。

### 中小尺寸可读性

未做 16/32/128 px 的实机并排目视比对（设计侧评审的 N-07 建议项）。已生成并可从产物取得各尺寸渲染图（`/tmp/icon-render2/nsworkspace-{16,32,128,256,512,1024}.png`），但**没有**做逐尺寸人眼判读，也未在真实 Dock/Finder 中截图。属未验证边界。

## 排查记录（第一次构建为何无图标）

保留此节，因为它说明"只看文件改动会误判完成"：

1. 第一版只做了三件事：生成 appiconset、把 `Assets.xcassets` 加入 Resources 构建阶段、`Info.plist` 加 `CFBundleIconName`。
2. `xcodebuild` **成功**，产物 Info.plist 含 `CFBundleIconName => AppIcon`，但 `Contents/Resources/` 下**既无 `.icns` 也无 `Assets.car`**。
3. 查构建日志：`actool` 确实运行（`CompileAssetCatalogVariant`），但命令行**没有 `--app-icon` 参数**，`assetcatalog_generated_info.plist` 为空 `{}`。
4. 补上 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` 后重新构建，`--app-icon AppIcon` 出现，`assetcatalog_generated_info.plist` 变为 `{CFBundleIconFile => AppIcon, CFBundleIconName => AppIcon}`，`.icns` 与 `Assets.car` 均出现。

即：`Info.plist` 里的 `CFBundleIconName` **单独存在不等价于"图标已接入"**，必须验证产物里真的有图标文件。

## 回归（确认未牵连其他部分）

```text
$ swift build
Build complete! (0.65秒)

$ swift test
Test run with 61 tests in 17 suites passed after 2.077 seconds.   # AutomntPlatformTests
Test run with 94 tests in 28 suites passed after 1.036 seconds.   # AutomntCoreTests
TEST_EXIT=0
```

（项数用同一工作区重复运行核对过：61/17 与 94/28 稳定复现，耗时随负载在 1.0–2.1 秒间浮动。）

```text
$ bash scripts/build.sh /tmp/automnt-icon
3.4.0   (exit 0)
$ /tmp/automnt-icon --version
3.4.0
$ /tmp/automnt-icon --self-test
Self-tests: 295 passed, 0 skipped, 0 failed

$ python3 scripts/verify-localization.py --quiet
L10N_EXIT=0
```

`asset catalog` 编译无 actool 资产告警（仅剩仓库既有、与本轮无关的两条 Swift 警告 `RecoveryRound.swift:262`、`RecoverySessionCollector.swift:28`，已确认改动前就存在）。

补充说明：`Sources/AutomntCore/BuildVersion.swift` 的 mtime 会因跑 `scripts/build.sh` 而更新（该脚本第 5–6 行调用 `scripts/generate-version.py` 写入 `3.4.0`）。这是**既有构建行为的副作用，不是本轮编辑**；文件内容与 `automnt.swift` 的版本真理来源一致（`3.4.0`），且本轮未手工改动 `Sources/` 下任何文件。

## 历史资产合规

- 无真实业务数据：图标为纯图形（文件夹 + 连接环），不含主机名、IP、共享名、用户名、路径或任何文字。
- 非占位图：由设计侧候选源图 `app-icon-1024.png`（历史候选 03「文件夹＋连接环」）派生，非灰块/通用占位。
- 无第三方依赖：只用系统 `sips` 与 Xcode 自带 `actool`。
- 未改 `Sources/`、`Tests/`、`specs/` 设计源；未改 `scripts/generate-xcode-project.py`；未改 `Localizable.xcstrings`。

改动文件清单：

| 文件 | 类型 |
| --- | --- |
| `apps/Automnt/Resources/Assets.xcassets/Contents.json` | 新建 |
| `apps/Automnt/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` | 新建 |
| `apps/Automnt/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png`（10 个） | 新建 |
| `apps/Automnt/Resources/Info.plist` | 加 1 键 `CFBundleIconName` |
| `apps/Automnt/Automnt.xcodeproj/project.pbxproj` | 加 2 个对象 + Resources 阶段成员 + 主组 children + 2 处 build setting |
| `scripts/generate-app-icon.sh` | 新建 |
| `release/evidence/icon.md` | 新建（本文件） |

## 未验证边界（不得当作已完成）

- **未在真实 Finder/Dock 中截图**：只验证了 `NSWorkspace` 的渲染结果与产物内容，未在 GUI 会话里目视 Finder 图标、Dock 图标、⌘-Tab 切换器与实际尺寸下的呈现。
- **未做 16/32/128 px 人眼可读性比对**（设计侧 N-07 建议）；连接环在小尺寸是否会被读作回形针/链条**未判定**。
- **未做深色/着色/Liquid Glass 分层图标**，依据见"外观与形态核对"；该能力需 Icon Composer `.icon` 分层源，本机有 Icon Composer 27.0 但无法从扁平 PNG 自动生成。
- **未验证图标缓存行为**：macOS 会缓存图标；首次安装/替换后的实际刷新表现未测。
- **未验证 App Store 提交流程**对图标的要求（如 1024 营销图标、圆角裁切规则是否由 App Store 侧再次处理）。
- **未在签名环境下构建**：本轮 `CODE_SIGNING_ALLOWED=NO`；签名/公证对图标无影响属预期但未实测。
- **图标视觉是否采用属维护者审美决定**：本记录只证明"资产存在且被产物采用、尺寸与声明一致、系统遮罩生效"，**不宣布图标通过审阅或获得批准**。设计侧 [independent-experience-review.md](../../specs/005-swiftui-mas-gui/design/independent-experience-review.md) 的图标 NOT_PASS 结论中，"源图需自带圆角"一条本轮实测不成立，"需 Icon Composer 分层管线"一条本轮**确实未满足**——这两点的最终裁定权在维护者。

# 当前结论

上述历史生成/采用来源不能为维护者替换 SVG/PNG 提供来源或批准结论；当前以维护者提供的文件为基线，来源/许可与名称疑问仍待确认。历史验证不继承到当前资产，本轮未生成、修改或重签任何图标或应用。
