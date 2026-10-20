# 本机开发签名与当前验证范围

2026-10-11 历史记录：本机 Apple Development 身份完成 GUI/helper/worker 签名构建与嵌套 seal 验证；团队从构建参数传入。最高优化 CLI 已签名构建、295 自测通过并替换工作区根二进制，不等于服务部署或发布。免费身份可继续用于完整 SwiftUI 实施及真实运行验证，付费账号不是界面实施前置。

当前设计复用 macOS 的 SMB 登录凭据，无独立密码管理。沙盒/helper 是否能在后台实际复用系统认证尚未验证；已有 CLI 配置应自动显示，共享配置所有权尚未实现。不让用户检查/导入 CLI 配置或选择内部目录。

# 已移除凭据管理范围的历史调查

round90 最新签名 GUI 后台任务查询：旧 CLI registered，baseline/recovery absent，约 0.048 秒；未停止业务服务。旧独立 Keychain 临时项 insert/delete 均 exit1、`-34018`，清理未验证；未触碰真实 SMB 项。证据为 `.build/round90-service-presence.log` 与 `.build/round90-keychain.log`。这不是已修复/已通过，也不证明系统认证路线失败或成功。

当时 Xcode UserData 无可用 profile，旧 MobileDevice profile 目录不存在。基础自动签名通过；临时加入共享 `keychain-access-groups` 后 exit65，缺 Mac App Development profile，提示 `-allowProvisioningUpdates`，失败声明撤回。证据 `.build/auto-signing-check.log`、`.build/auto-keychain-signing-check.log`。共享 Keychain/profile 调查属于历史移除范围，不作为当前密码管理工作要求，也不能证明必须先买付费账号。

# 开发账号与系统能力下一步

基于当前采用的系统认证路径核对团队、签名/profile 与实际必要 capability，再验证沙盒网络访问、SMAppService 独立 helper、系统 SMB 认证、后台生命周期和共享配置所有权。无需为已移除密码管理路线继续执行应用 Keychain CRUD。若实际采用能力需要门户资源更新，应列出确切变更；门户 App ID/profile 更新尚未执行。

开发签名与局部容器/登记证据不能替代真实 SMB 挂载、退出 GUI 后恢复、重新登录与网络变化连续三轮验收；不以 GUI 常开或手动挂载代替核心后台能力。

# 付费账号与发布操作

Mac App Store 发行需要正式 Apple Developer Program 团队及有效成员资格，完成法律信息、协议、税务、收款资料，并在 App Store Connect 建立应用实体、售价和地区。账号、私钥、支付与法律资料不进仓库。

正式分发为主应用/helper 配置实际需要的团队/profile/capability，核对 App Groups、沙盒、系统认证、通知、网络卷访问与后台生命周期，并以分发身份 archive 校验签名/profile。开发签名不能替代分发检查。商店是否承载核心后台自动挂载仍需真实证明。

提交前完成九语实际界面、复数、长文本、键盘/VoiceOver 审阅与支持链接、隐私说明、当前资产、实机截图、审核说明。Automnt 为临时名且来源受质疑；直接使用维护者替换的 SVG/PNG，名称与资产来源/许可待确认。旧截图退役但保留；demo 不作为运行验收或商店实机截图。

上传、提交审核、公开发布、GitHub 推送/Release 仍需维护者另行授权。本轮仅更新文档，未执行外部操作或变更已安装业务 CLI 服务。
