# CLI 发布与版本指南（当前免费离线范围）

本指南准备可复现的 CLI 发布动作；实际推送、Release 与版本递增仍需维护者授权，本文不构成发布许可。

# 版本真理源

唯一版本声明是根 `automnt.swift` 的 `automntVersion`。预编译 CLI、配置 `version`、离线包 manifest 与 Release 标题必须从它派生，不得各自维护。

# 构建与验证

```sh
swift test
bash scripts/build.sh /tmp/automnt
/tmp/automnt --version
/tmp/automnt --self-test
bash scripts/verify-signature.sh <built-app>
python3 scripts/verify-localization.py
python3 scripts/verify-swift6-concurrency.py
```

# 发布步骤（需授权）

1. 判定 SemVer 晋级类型（MAJOR/MINOR/PATCH）并修改唯一版本源。
2. 重新构建预编译 CLI 并签名，确认源码与二进制版本一致；GUI 只在本地构建验证，不进入 Release。
3. 生成 CLI 的 SHA-256 校验值；不生成或上传 GUI 离线包。
4. 经维护者授权后提交并推送 `main`，按项目规则创建 `gh release` 与 Release Notes。
5. 不把免费 Apple Development 签名当作其他设备分发或商店验收；商店路径见 T100。

# 当前状态

版本 3.5.0；维护者已授权推送并创建 GitHub Release。自 3.5.0 起 Release 只发布 CLI（`automnt` 与校验值）。GUI 源码按 MIT 开源、可自行编译，但不提供预构建 App；详见 `release/RELEASE_POLICY.md`。
