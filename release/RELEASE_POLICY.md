
# 适用范围

本文件规定 Automnt 在 GitHub 上发布 Release 时的产物范围、版本规则与 GUI 源码处理方式。仓库根 `AGENTS.md` 的“推送即发布与阶段性安全交付准则”仍是项目级规则；本文件补充 Release 具体产物边界。

# 版本与推送

- 唯一版本源是根 `automnt.swift` 的 `automntVersion`；`Sources/AutomntCore/BuildVersion.swift` 与 `apps/Automnt/Resources/Version.xcconfig` 由 `scripts/generate-version.py` 派生。
- `main` 上凡包含核心代码变更的推送，必须按 SemVer 递增版本并同步重新构建预编译 CLI。
- 纯文档、截图或规则修订的推送不构成对外交付，不强制递增版本。

# GitHub Release 产物

每次 Release 只提供：

- `automnt`：用当前源码与最高优化参数重新构建、签名的 CLI 二进制（macOS 27 / Apple silicon）。
- `automnt-<version>.sha256`：该二进制的 SHA-256 校验值。
- Release Notes：说明版本、变化、下载、升级与已知限制。

不得上传：

- 构建好的 GUI `.app`；
- 包含 GUI 的离线 zip、dmg 或其他安装包；
- GUI 的签名、公证或商店上传产物。

# GUI 源码与自行编译

- GUI 源代码与 CLI 一样在 GitHub 仓库公开，按仓库 `LICENSE`（MIT）开源；任何人都可以查看、修改并自行编译。
- Release 不提供预构建 GUI，不代表 GUI 源码保密或不可用。
- 自行编译需要 macOS 27、Xcode 27 和可用的签名身份；在仓库根目录运行：

```sh
xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt \
  -configuration Release -derivedDataPath .build/xcode \
  DEVELOPMENT_TEAM=<你的 Team ID> CODE_SIGN_IDENTITY="Apple Development" build
```

- 生成的 App 在 `.build/xcode/Build/Products/Release/Automnt.app`。自行编译的产物由编译者自行签名、分发和承担支持责任；项目不为其提供公证或安装支持。
- GUI 面向未来的 Mac App Store 收费版本，商店可行性、审核与定价仍未最终确认；未获维护者另行授权前，不得把 GUI 预构建产物上传到任何 Release。

# Release 检查清单

1. 确认 `automntVersion` 与生成文件一致：`python3 scripts/generate-version.py --check`。
2. 构建并签名 CLI：`bash scripts/build.sh <output>`；运行 `<output> --version` 与 `<output> --self-test`。
3. 运行 `swift test`、`python3 scripts/verify-localization.py`、`python3 scripts/verify-swift6-concurrency.py`。
4. 本地构建 GUI 验证源码可编译（不归档、不上传）。
5. 提交版本、二进制、Release Notes 与相关文档；打 `vx.y.z` 标签并推送 `main` 与标签。
6. 用 `gh release create` 创建 Release，只附加 CLI 与校验值；用 `gh release view` 核对资源列表。

# 历史产物

`v3.4.0` 及更早的 Release 曾包含 GUI 离线包，属于本政策生效前的历史产物，不追溯删除；自 `v3.5.0` 起按本文件执行。
