本指南说明如何从当前源码可复现地生成签名 GUI 与预编译 CLI 的离线包。仓库不硬编码个人签名团队。

# 前置条件

- macOS 27 + Xcode 27（当前开发基线），arm64。
- 有效 Apple Development 身份；`DEVELOPMENT_TEAM` 由调用者提供，不从仓库读取。
- 已安装 `swift`、`xcodebuild`、`python3`。

# 命令

```sh
cd <repo>
export DEVELOPMENT_TEAM=<your-team>
swift test
bash scripts/build.sh /tmp/automnt
bash scripts/verify-localization.py
bash scripts/verify-swift6-concurrency.py
xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt \
  -configuration Release -derivedDataPath .build/xcode-offline \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CODE_SIGN_IDENTITY='Apple Development' \
  CODE_SIGN_STYLE=Manual build
bash scripts/verify-signature.sh .build/xcode-offline/Build/Products/Release/Automnt.app
bash scripts/archive.sh .build/offline/3.4.0
```

`scripts/archive.sh` 会依次运行 Package 测试、优化 CLI 与自测、签名 Release 构建、验签/本地化/Swift 6 门，并把 app、CLI、说明文档打成 zip + SHA-256。

# 产物与限制

- 归档输出在 `.build/offline/<version>/`，含 `manifest.txt`、`.zip` 与 `.sha256`。
- 免费 Apple Development 签名不能替代 Developer ID 与公证；其他设备分发不在本流程承诺范围。
- 构建可复现性受 Xcode/SDK 版本影响；manifest 记录实际 xcodebuild 与 swift 版本。
- 归档产物与派生目录不进入 Git；发布前需人工核对版本、签名与校验和。
