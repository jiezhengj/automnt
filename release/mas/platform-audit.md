2026-10-20 只读审计当前本机产物，不声称其他 macOS/Intel 支持。

# 平台事实

| 项目 | 实际值 |
| --- | --- |
| 构建环境 | macOS 27 / arm64，Xcode 27.1，Swift 6.4 |
| 根 `automnt` | Mach-O arm64，`--version` 3.4.0，LC_BUILD_VERSION minos 27.0 / sdk 27.0 |
| 离线包 CLI | Mach-O arm64，`--version` 3.4.0，Apple Development 签名 |
| GUI | `CFBundleShortVersionString` 3.4.0，`CFBundleVersion` 3004000，`LSMinimumSystemVersion` 27.0 |
| 目标架构 | 仅 arm64；不维护 Intel/旧 macOS |

# 门禁

`swift test` 306 项、优化 CLI `--self-test` 295 项、`verify-signature`、`verify-localization`、`verify-swift6-concurrency` 均通过。GUI 与 CLI 共用配置和挂载规则；source 与预编译产物版本一致（3.4.0）。

# 未覆盖

其他 macOS 版本、Intel、真实 App Store 分发、公证、Developer ID 签名和其他设备 Gatekeeper 行为未验证；这些不属于当前免费离线范围。
