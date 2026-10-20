本包是 Automnt 3.4.0 的免费离线构建，随 GitHub Releases 分发。使用免费 Apple Development 签名，未公证，也不包含 App Store 分发；其他 Mac 上的 Gatekeeper 可能阻止打开。

# 包内容

- `Automnt.app`：SwiftUI 图形界面（含独立 helper/worker）。
- `automnt`：签名预编译命令行程序，不需要在用户机器上编译。
- `安装说明.md`、`Install.md`、`已知限制.md`、`Known-Limitations.md`、版本说明。
- 包外的 `.zip.sha256`：校验完整性的 SHA-256。

# 校验

```sh
shasum -a 256 -c Automnt-3.4.0-offline.zip.sha256
```

校验通过后再解压。

# 安装图形界面

1. 将 `Automnt.app` 拖入“应用程序”文件夹（或保留在本地目录运行）。
2. 首次打开若被 Gatekeeper 阻止，说明本机安全策略不接受免费开发签名；不要通过关闭系统安全来绕过，改用本机/同一团队环境验证。
3. 首次启动由程序自行准备固定配置目录，不出现内部目录选择面板。
4. 需要后台自动挂载时，在设置中开启自动挂载，并按系统提示允许后台项目；未获系统允许前，界面会显示真实状态而不是伪装成功。

# 安装命令行（可选）

从 zip 解压时 `payload/automnt` 保留可执行权限。若单独下载 Release 中的 `automnt` 资产，浏览器通常不会保留执行位，请先运行：

```sh
chmod +x automnt
./automnt --install
```

安装会把签名程序复制到规范目录并配置 shell 入口。注册后台 LaunchAgent 需要系统允许；注册失败时不要手工创建服务，先查看命令输出。

# 升级

用新版本 `Automnt.app` 替换旧应用即可。配置保存在用户配置目录，升级不应要求重新授权；如果系统提示权限，按界面说明允许或拒绝，不会创建第二份配置。

# 卸载

图形界面从“应用程序”移除；命令行运行 `automnt --uninstall`。默认保留配置，只有显式 `--purge` 才删除配置与日志。
