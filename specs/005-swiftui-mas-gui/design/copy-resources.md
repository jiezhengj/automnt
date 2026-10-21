**当前规范（2026-10-13；保留方案 A 架构，撤回目录选择例外）**：程序决定并准备固定目录，GUI/CLI 使用真实用户的唯一活动配置及单后台 owner。首次、设置、CLI 共用和恢复均不让用户选择、寻找或手工创建内部目录；之前 NSOpenPanel/父目录选择例外撤回。仅在真实系统授权需要时允许/拒绝，普通应用 alert 不产生沙盒文件权限；免目录选择机制尚未证实，不承诺通用 Allow/Deny API。失败不创建平行配置、不显示零目标、不新挂载或接管，已有快照只读。历史 290 项测试、签名与中文首次窗口不证明当前权限、独立 helper 生命周期、MAS 或九语验收。本轮仅文档，最新规格覆盖旧实现与历史评审。

# 资源语境与审校边界

本清单记录拟发布界面的完整语义资源与动作，不以网页DOM每个重复节点建立资源。相同含义复用ID，含义不同即使字面相同也分别命名。中文为设计候选；品牌、SMB、用户输入不翻译。应用 String Catalog 已集成九语资源，历史目录面板实现的 14 个授权键均有九语值，历史资源完整性检查通过（258 source strings / 347 catalog keys）；机器草稿尚未获可靠语言审校，真实布局验收未完成，T060保持未完成。HTML模拟提示、工具选择器、假地址/路径/用户名、示例目标及演示时间均为设计标注，不加入产品资源。

所有动态值使用类型化参数：server/share/user/path/address/result/reason为String，count/index为Int，checkedAt为Date；用户值不作为格式串。数量资源以完整句建立系统plural分支，规则见localization.md。不得把时间、原因、名词拼接为句子。真实观测缺失有独立空值，不写“刚刚”。下面的ID为稳定语义名，英文与其他语言按语境独立编写。

# 导航与目标动作

| ID | 中文候选 | 语境/动作与参数 |
| --- | --- | --- |
| nav.app | Automnt | 窗口与菜单品牌 |
| nav.servers | 服务器 | 列表分组，名称来自用户配置 |
| nav.shares | 共享文件夹 | 列表/窄窗返回入口，保留选中目标 |
| nav.add | 添加共享文件夹 | 打开添加sheet，⌘N |
| nav.settings | 设置… | 打开同一Settings窗口，⌘, |
| target.server | 服务器 | 服务器名称/地址值单独完整呈现 |
| target.mountLocation | 挂载位置 | 配置位置，不代表已挂载 |
| target.currentLocation | 当前位置 | 已核对的真实挂载路径 |
| target.notMounted | 尚未挂载 | 无实际路径 |
| target.checked | 最近检查 | checkedAt按系统格式显示 |
| target.unobserved | 尚未检查 | 缺有效观测，不猜时间 |
| target.finder | 在 Finder 中打开 | 打开核对的目标挂载目录；英文Open in Finder |
| target.mount | 挂载 | 显式目标挂载，独立于自动化enabled |
| target.eject | 弹出 | 非强制目标弹出；忙碌失败保留挂载 |
| target.edit | 编辑… | 当前目标草稿sheet |
| target.retry | 重试 | 按当前结构化失败重新核对 |
| target.checkProblem | 检查挂载问题… | 未判定原因的失败打开分类修复建议，不假定凭据错误 |
| service.viewResult | 查看结果 | 核对正在进行的后台启用、停止或切换 |
| target.details | 查看详情 | 打开当前目标完整状态 |
| target.remove | 移除共享文件夹… | 删除管理配置确认，不删除远端文件 |
| target.editAddress | 编辑服务器地址… | 服务器草稿，与受影响共享关联 |
| target.stopWaiting | 停止等待 | 不撤销已完成挂载，随后核对结果 |
| target.stopWaitingHelp | 停止等待后，Automnt 会检查结果。已经完成的挂载不会撤销。 | 检查进行中辅助说明 |
| target.shareEnabled | 启用此共享文件夹 | 仅此ShareConfig.enabled |
| target.shareDisabledHelp | 关闭后，此共享文件夹不再自动挂载。已经挂载的共享仍可使用。 | 开关附近完整后果 |
| server.enabled | 自动挂载此服务器的共享 | 仅HostConfig.enabled |
| server.disabledHelp | 关闭后，此服务器的共享不再自动挂载。已有挂载仍可使用。 | 服务器开关附近 |
| server.orderHelp | 按此顺序检查服务器，选择首个可达的服务器。该服务器的某个共享挂载失败时，不会因此改用后面的服务器。 | 核心firstReachableHost语义须T007/T036验证 |
| server.moveUp | 上移 | 边界禁用；保留目标焦点 |
| server.moveDown | 下移 | 边界禁用；保留目标焦点 |
| server.undoOrder | 撤销顺序调整 | 已管理组即时排序的CAS保护撤销 |
| server.conflictTitle | 服务器顺序已被修改 | revision冲突alert |
| server.keepCurrentOrder | 保留当前顺序 | 冲突时保留最新持久配置，不覆盖 |
| server.reload | 重新读取 | 排序或撤销冲突后核对最新持久顺序 |

# 自动化状态与设置

| ID | 中文候选 | 语境/行为 |
| --- | --- | --- |
| service.running | 自动挂载已开启 | 实际服务已核对，意图开启/owner及generation一致 |
| service.runningHelp | 退出 Automnt 后，自动挂载仍会继续运行。 | 仅已确认运行时使用 |
| service.stopped | 自动挂载已关闭 | 意图关闭且实际服务已停 |
| service.stoppedHelp | 不再自动挂载新的共享；已经挂载的共享仍可使用。 | 不用退出解释停用原因 |
| service.stopping | 正在关闭自动挂载 | 服务停止尚未核对 |
| service.stoppingHelp | 正在确认后台服务停止。已经挂载的共享仍可使用。 | 过渡状态 |
| service.stopFailed | 未能关闭自动挂载 | 意图已关闭、实际停止失败 |
| service.stopFailedHelp | 关闭请求已保存，但尚未确认后台服务停止。 | 不声称已经停止 |
| service.retryStop | 重试关闭 | 用户显式重试，刷新结果 |
| service.approval | 等待后台运行许可 | requiresApproval |
| service.approvalHelp | 请在系统登录项设置中允许 Automnt 在后台运行。 | 系统设置入口附近 |
| service.openBackground | 打开后台设置… | 用户显式打开相关系统设置 |
| service.revoked | 自动挂载未运行 | 意图开启但未注册/被撤销 |
| service.revokedHelp | 已保存开启设置，但后台服务未运行。检查系统设置后可恢复。 | 不静默重注册 |
| service.restore | 恢复自动挂载 | 经过明确恢复操作重新核对 |
| service.activating | 正在启用自动挂载 | 注册/核对过渡 |
| service.activatingHelp | 正在核对后台服务；完成后会显示结果。 | 不宣称成功 |
| service.switching | 正在切换后台服务 | owner切换过渡 |
| service.switchingHelp | 切换完成前不会启动第二个自动挂载服务。 | 无第二evaluator承诺 |
| service.unknown | 无法确认自动挂载状态 | 查询失败、owner/generation不匹配 |
| service.unknownHelp | 尚未取得有效的后台状态。已挂载共享的状态分别显示。 | 不推断挂载或服务停止 |
| service.recheck | 重新检查 | 重读实际状态与诊断 |
| service.savedIntent | 已保存设置 | 开启/关闭偏好单独值，无运行含义 |
| service.intentOn | 自动挂载开启 | 已保存偏好值 |
| service.intentOff | 自动挂载关闭 | 已保存偏好值 |
| service.observation | 状态核对 | checkedAt，缺值显示尚未核对 |
| setting.automatic | 自动挂载 | 根级automation_enabled，即时保存 |
| setting.automaticHelp | 关闭后，已经挂载的共享文件夹仍可使用。 | 写入失败回保存值并显示错误 |
| setting.recovery | 自动恢复 | 独立auto_mount_recovery |
| setting.recoveryHelp | 共享意外断开后，额外响应卷宗变化尝试恢复。关闭后，仍在登录或网络变化时自动挂载。 | 不保证所有断开有触发事件 |
| setting.menu | 在菜单栏中显示 Automnt | 菜单显示偏好，默认关闭 |
| setting.loginMenu | 登录时显示菜单栏 | 默认关闭；仅menu启用可选 |
| setting.loginState | 登录菜单状态 | 与偏好独立；未注册/正在注册/已注册/待批准/已撤销/注册失败/无法确认分别完整资源，不拼接 |
| setting.loginApproval | 待批准 | 打开登录项设置允许，返回重读 |
| setting.loginRevoked | 已撤销 | 不自动重新注册；用户可显式重试 |
| setting.loginFailed | 注册失败 | 偏好不冒充系统成功；持续失败说明 |
| setting.loginSystem | 打开登录项设置… | 系统入口失败持续显示，可重试 |
| setting.loginRetry | 检查一次 | Check Again | 仅登录项未加载时显示；重新读取真实状态 |
| state.offlineAddress | 查看服务器地址… | 显示完整地址，检查网络，不更改地址/凭据或挂载 |
| state.offlineWait | 服务器当前不可达。检查网络连接；网络变化后会自动检查。 | 仅自动挂载开启；关闭时改为开启后才自动重试 |
| setting.loginNotFound | 登录项暂时没有加载。请退出 Automnt，从“应用程序”文件夹重新打开，然后再检查。 | The login item didn’t load. Quit Automnt, reopen it from the Applications folder, then check again. | 仅登录项实际变更失败时显示；未启用登录功能时不显示，避免噪音 |
| setting.loginSystem | 打开系统登录项设置… | Open Login Items Settings… | requiresApproval 的系统入口 |
| setting.notificationPermission | 通知权限：未开启/已允许/已关闭/暂时无法读取 | Notification Permission: Not set up/Allowed/Not allowed/Couldn’t read | 状态标签，不把系统授权说成“系统授权” |
| setting.loginHelp | 开启后，登录时 Automnt 会出现在菜单栏，方便快速挂载共享或打开设置；主窗口不会自动打开。 | GUI 登录项只负责菜单栏，后台自动挂载独立 |
| setting.notifications | 通知 | 分组 |
| setting.notificationsHelp | 共享文件夹未能自动挂载时，Automnt 会通知你，方便及时处理。 | 主动说明用户收益，不用“只/从不”防御措辞 |
| setting.sound | 通知声音 | 默认开启，独立偏好 |
| setting.soundHelp | 关闭声音后仍会收到通知，只是没有提示音。 | 说明实际差别，不用“仍会收到”免责式表达 |
| setting.language | 语言 | 分组 |
| setting.languageHelp | 在系统设置的“语言与地区”中更改 Automnt 的语言。 | 系统应用语言，无应用内语言开关 |
| setting.help | 帮助 | 分组 |
| setting.saveFailed | 未能保存设置：{reason} | String，回滚已保存值、保留焦点 |

# 主界面与共享状态

| ID | 中文候选 | 语境/参数 |
| --- | --- | --- |
| empty.title | 自动挂载共享文件夹 | 已具备所需真实访问并成功确认无目标的真实空状态 |
| empty.help | 请先在 Finder 中选择“前往 → 连接服务器…”并连接 SMB 共享。已挂载的共享会出现在这里。 | 已授权并成功读取配置，且无本机已挂载 SMB 共享时的次级指导；工具栏完整 URL 入口仍可达 |
| empty.background | 关闭窗口或退出 Automnt 后，已启用的自动挂载仍会继续运行。 | 条件性说明 |
| state.mounted | 已挂载 | 实际位置核对 |
| state.mountedHelp | 可以在 Finder 中访问此共享文件夹。 | 可用实际路径 |
| state.offline | 服务器离线 | 可达失败 |
| state.offlineHelp | 服务器暂时无法连接。网络变化后，Automnt 会再次尝试挂载。 | 不暗示密码失败 |
| state.permission | 需要访问权限 | 授权缺失/失效 |
| state.permissionHelp | 当前系统访问受限。请查看原因或导出诊断信息以获取帮助。 | 按实际错误展示下一步；配置访问错误使用 configAccess 独立资源，不能冒充 SMB 认证失败 |
| state.failure | 无法挂载 | 结构化失败摘要 |
| state.loginFailureHelp | 请先在 Finder 中连接此共享并完成登录，再重试。 | 系统认证失败，不打开应用凭据页 |
| state.ejected | 已弹出 | 用户主动弹出成功 |
| state.ejectedHelp | 重新登录或网络环境变化前，Automnt 不会自动挂载此共享。你也可以现在重新挂载。 | 会话抑制边界 |
| state.checking | 正在检查 | 有在途操作 |
| state.checkingHelp | 正在检查共享文件夹是否可用。 | ProgressView非无限成功预期 |
| state.error | 无法完成操作：{reason} | String；可访问持久结果，非仅toast |
| state.noFailures | 当前没有挂载失败的共享文件夹 | N=0前台摘要，不投递通知 |
| notice.failure | {count} 个共享文件夹未能自动挂载。打开 Automnt 查看详情或重试。 | Int>0，九语完整plural，不含私有目标信息 |

# 确认与帮助

| ID | 中文候选 | 语境/行为 |
| --- | --- | --- |
| confirm.removeTitle | 移除此共享文件夹？ | 完整目标作为独立可访问上下文 |
| confirm.removeHelp | Automnt 将不再自动挂载此共享。已经挂载的共享仍可使用，服务器上的文件不会删除。 | 三方后果 |
| target.ejecting | 正在弹出“{share}”… | String完整共享名/服务器上下文；直接执行，无例行确认 |
| confirm.busy | 共享文件夹正在使用，无法弹出。请关闭相关文件后重试。 | 无强制回退 |
| confirm.unsavedTitle | 要保存修改吗？ | Draft关闭/⌘Q |
| confirm.cancelQuit | 取消退出 | 安全默认 |
| confirm.discardQuit | 放弃并退出 | 丢草稿，不删除已保存配置 |
| confirm.saveQuit | 保存并退出 | 接通实际退出保护，持久化成功才退出；失败/冲突保草稿及焦点 |
| confirm.conflict | 设置已在其他地方更改。重新载入后，请检查你的修改再保存。 | CAS失败，不覆盖，保留编辑草稿 |
| menu.open | 打开 Automnt | 主窗口，保持目标选择 |
| menu.hide | 隐藏菜单栏图标 | menu关闭，注销login opt-in |
| menu.stop | 关闭自动挂载 | 保已有挂载；核对实际停止后才显示已关闭 |
| menu.quit | 退出 Automnt | 有草稿则确认；helper原状态不变 |
| menu.stale | 此共享的设置已更改。打开详情查看最新状态。 | revision/目标移除失效 |
| help.diagnostics | 查看诊断信息… | 脱敏快照后用户显式导出 |
| help.export | 导出诊断信息… | 系统保存面板取消不写 |
| help.diagnosticsHelp | 导出前可以查看内容。诊断信息不会自动上传。 | 不含密码/用户名/地址/路径 |
| help.usage | 使用帮助 | 离线正文 |
| help.usageBody | 自动挂载需要服务器可达、配置有效且系统 SMB 认证可用。共享无法访问时，在详情中查看原因并完成对应修复。退出 Automnt 后，已启用的自动挂载仍会继续运行。 | 不承诺无条件恢复 |
| help.license | 开源许可 | 完整MIT正文及第三方适用声明，逐字法律正文单独交付 |
| action.cancel | 取消 | 放弃当前操作，不隐含退出 |
| action.back | 返回 | 返回发起页面，保留编辑草稿 |
| action.continue | 继续 | 继续当前操作，不隐含保存 |
| action.save | 保存 | 据编辑开始 baseRevision/身份 CAS；成功关闭或重置 draft/baseRevision/dirty，失败/冲突/目标消失保输入 |
| action.remove | 移除 | 共享管理配置确认动作 |
| action.done | 完成 | 关闭当前sheet回发起控件 |

# 输入验证与失败修复

| ID | 中文候选 | 语境/下一步 |
| --- | --- | --- |
| draft.navigationBlocked | 请先完成或取消当前修改，再添加共享或打开设置。 | sheet或未保存草稿期间⌘N/⌘,；持续状态播报、不移焦点 |
| validation.address | 输入有效的 SMB 服务器地址。 | 地址无法解析；聚焦字段，不提交 |
| validation.share | 输入一个共享的完整 SMB 地址。 | 未选择；聚焦列表或首行 |
| validation.duplicate | 此共享已在 Automnt 中配置。请编辑现有共享。 | 稳定目标身份重复，不新建 |
| repair.title | 修复挂载失败 | 结构化原因明确，不把所有错误映射密码 |
| repair.help | 请检查服务器连接、登录信息或挂载位置，然后重试。 | 未知原因总说明；已知原因用具体句 |
| repair.suggestions | 查看建议 | 打开分类建议 |
| repair.login | 请先在 Finder 中连接此共享并完成登录，再重试。 | 复用系统 SMB 认证；能力未验证 |
| repair.access | 检查共享名称，并确认你的账号有权访问。 | 服务器拒绝访问，与目录TCC权限分开 |
| repair.location | 挂载位置发生冲突。请检查当前已挂载的共享后重试。 | 保留真实原因；不打开内部目录选择器 |
| repair.timeout | 连接时间过长。请检查服务器和网络连接后重试。 | 超时，可重试，无强制挂载 |
| repair.unknown | 如果问题持续出现，可导出诊断信息以获取帮助。 | 未知错误，给脱敏诊断入口 |
| confirm.abandon | 放弃修改？ | 尚未保存添加/编辑草稿 |
| confirm.abandonHelp | 你的修改尚未保存。放弃后，这些输入将丢失。 | 安全默认继续编辑 |
| confirm.keepEditing | 继续编辑 | 返回原编辑内容与草稿 |
| confirm.discard | 放弃修改 | 清编辑草稿，不影响已保存配置 |
| status.configSaved | 设置已保存 | 仅实际CAS成功；不能先成功后写入 |
| status.targetRemoved | 此共享已移除 | 实际配置删除成功，保已有挂载 |
| status.exportFailed | 未能导出诊断信息：{reason} | String；保脱敏预览，重新选择位置 |
| status.operationFailed | 操作未完成：{reason} | 无更具体用户原因时使用，String不含秘密 |

添加一次只保存当前行的一个共享，成功后立即移入已管理组；不收集多选添加草稿。编辑保存成功关闭编辑器并重置 dirty；失败保留完整编辑草稿与错误，非活动窗口字段仍可编辑。冲突不覆盖其他入口的修改。字段错误持续显示，未知系统错误提供完整用户原因与脱敏诊断。

# 补充页面资源

| ID | 中文候选 | 语境 |
| --- | --- | --- |
| settings.quitMenuHelp | 退出 Automnt 后，菜单栏图标也会关闭。自动挂载按当前设置继续运行。 | 菜单偏好附近 |
| settings.summary | 管理自动挂载、菜单栏和通知。 | Settings说明 |
| about.purpose | Automnt 在后台挂载 SMB 共享文件夹。 | 帮助用途 |
| repair.checkTitle | 检查挂载问题 | 建议详情 |
| repair.chooseHint | 选择一项查看建议。 | 未选择分类 |
| help.supportPrivacy | 支持与隐私 | 正式离线说明标题 |
| state.enabled | 已启用 | 局部配置意图，不代表挂载成功 |
| state.disabled | 已停用 | 局部配置意图，不代表卷已卸载 |
| server.order | 服务器顺序 | 导航顺序标题 |
| target.statusLocation | 状态与位置 | 详情分组标题 |

帮助与诊断经Settings四入口呈现；无法确认服务状态时另有诊断入口，原生设计预览以设置及附近说明引导至该入口，不保留另一套不可达关于/诊断页面；完整MIT和第三方声明按发布内容验收。上述资源为唯一中文语义候选，原型中的模拟提示、审阅说明和示例值不作为翻译来源。真实观测日期用系统日期格式，不能把演示“刚刚”设为默认资源。

# 系统入口补充

| ID | 中文候选 | 语境 |
| --- | --- | --- |
| setting.openNotifications | 通知设置… | 系统设置入口；打开失败显示原因 |
| setting.openLanguage | 语言设置… | 系统设置入口；打开失败显示原因 |
| action.returnSettings | 返回设置 | 帮助sheet回发起控件 |
| action.closeSettings | 关闭设置 | 浏览器流程参考；正式原生Settings使用系统窗口关闭 |

# 现有目标编辑

| ID | 中文候选 | 语境与参数 |
| --- | --- | --- |
| edit.title | 编辑共享文件夹 | 绑定稳定目标身份的sheet |
| edit.serverImpact | 服务器地址的修改会影响同一服务器的共享：{shares}。已有挂载保持原状；下一次连接使用新设置。 | shares String，系统列表格式，完整句资源 |
| edit.systemAuthHelp | 连接此共享使用 macOS 的 SMB 登录信息。如需登录，请先在 Finder 中连接。 | 不提供独立密码管理；沙盒/helper 复用尚未验证 |
| edit.addressError | 输入不含共享路径或登录信息的 SMB 服务器地址。 | 无效地址；焦点回地址字段 |
| edit.nameError | 输入共享名称。 | 空名称；焦点回名称字段 |
| edit.removed | 此共享已移除。请取消编辑并重新选择。 | 保存前身份核对失败 |
| edit.conflict | 设置已在其他地方更改。你的修改尚未保存。返回编辑可保留输入；重新载入后需再次检查。 | 非敏感草稿保留，不覆盖配置 |
| edit.return | 返回编辑 | 冲突取消回草稿 |

保存成功关闭编辑器、重置 dirty；失败保留草稿与 sheet。原型模拟结果不作为系统成功资源的证据，实际挂载位置仍按真实核对显示。

# 退出草稿反馈

| ID | 中文候选 | 语境 |
| --- | --- | --- |
| quit.completeDraft | 请完成当前草稿的验证与确认，保存成功后再退出。 | 不完整添加草稿不能直接保存退出；回原编辑内容 |
| quit.confirmEdit | 请确认并保存修改，保存成功后再退出。 | 目标编辑返回输入；不丢非敏感草稿 |
| quit.unsavedTitle | 修改尚未保存 | 无法完成保存时的持续反馈 |
| quit.returnEdit | 请返回当前编辑，完成验证与保存后再退出。 | 不以暂时提示宣称成功 |

原型“保存并退出”对未完成的添加/目标编辑返回原草稿，不伪造保存；实现按完整原子校验保存成功后执行退出。放弃清编辑草稿，保已保存配置与挂载。

# 摘要、修复分类与支持正文

| ID | 中文候选 | 语境与参数 |
| --- | --- | --- |
| settings.notificationsOffHelp | 关闭通知后，仍可在 Automnt 中查看挂载失败的共享。 | 通知设置附近，不承诺系统一定显示通知 |
| notice.currentStatus | 此页面显示最新核对的状态。 | 旧通知打开后的摘要；状态复用state.* |
| repair.categoryLogin | 登录信息 | 修复分类 |
| repair.categoryAccess | 访问权限 | 此处为服务器账号权限，不是本机目录授权 |
| repair.categoryLocation | 挂载位置 | 修复分类 |
| repair.categoryTimeout | 超时 | 修复分类 |
| repair.categoryOther | 其他问题 | 修复分类 |
| service.diagnosticsHelp | 在设置的帮助中查看诊断信息。 | 原生设计预览unknown状态旁说明；正式实现可直达同一诊断sheet |
| support.openSupport | 获取支持 | 打开实际支持URL；失败不退出正文 |
| support.openPolicy | 阅读完整隐私政策 | 打开实际政策URL |
| support.linkFailure | 无法打开链接。请重试，或复制地址在浏览器中打开。 | 持续alert反馈；保正文/语言/滚动位置 |
| support.copyAddress | 复制链接 | 仅有实际URL时可用，复制完整地址 |
| support.purpose | Automnt 在后台自动挂载已配置的 SMB 共享文件夹，需要服务器可达、配置有效且系统认证可用。已启用的后台恢复是核心能力，手动挂载用于异常兜底。 | 产品目标；实际后台能力仍需验收 |
| support.help | 遇到连接问题，请先在共享详情中查看原因与修复建议。如需寻求支持，可以导出并检查诊断信息，再决定是否发送。发送前请确认内容中没有你不愿共享的信息。不要发送密码。 | 完整支持段落；英文候选见support-privacy.md第23行 |
| support.product | 命令行版本免费开源；Mac App Store 图形版本一次购买。图形版本独立可用，不需要安装命令行版本。许可与第三方声明可从设置的“开源许可”阅读。 | 完整产品段落；英文候选见support-privacy.md第25行 |
| help.licenseIntro | Automnt 采用 MIT 许可。正式应用同时提供适用的第三方许可与声明。 | MIT法律全文逐字保留，不以简介替代 |
| help.bodyLanguage | 正文语言 | 支持与隐私正文选择器；选项中文/English使用自称 |
| support.dataHandling | Automnt 需要读取和保存自身设置，已经配置的共享文件夹会自动显示。程序准备所需位置，无需你选择内部文件夹。需要系统许可时，你可以允许或拒绝；有效权限在以后复用。取消后可以稍后继续，权限失效时可重新允许访问。连接共享使用 macOS 的 SMB 登录；诊断信息由你预览并选择是否导出，不会自动上传。所连接的服务器会处理连接请求。 | 候选数据处理说明；实际沙盒系统认证和独立后台权限另行验收，不把内部 helper 协议当产品文案 |

通知摘要复用state.mounted及相应说明，不再保留另一套“已恢复”状态句。支持正文语言切换改变正文，不改变全应用语言；标题、控件标签随应用语言。正式政策、支持URL及可靠语言审校仍为明确验收依赖。

# 辅助名称、商店与支持资源

menu.target.accessibility使用完整句“{server}，{share}，{result}”；三个String，result是目标实际状态而非全局摘要。列表同名目标同样读服务器与共享；排序位置使用“{server}，第 {index} 位，共 {count} 个服务器”，Int按系统数字格式。不设置应用密码控件；系统认证由 macOS/Finder 完成。逐页焦点、朗读和错误结果按accessibility.md。

商店标题Automnt、副标题“SMB 共享自动挂载”；候选功能正文：“在服务器可达、设置和登录信息有效且已允许访问时，Automnt 在后台自动挂载配置的 SMB 共享文件夹。你可以查看当前状态、管理设置并修复连接问题。命令行版本免费开源；Mac App Store 图形版本一次购买。”售价US$1.99由商店产品信息呈现，不在界面硬编码。不得声称恢复Finder侧栏入口或访问任意路径即时连接。支持/隐私中文与英文提供实际可联系入口及数据收集说明；其余七语商店本地化、正式隐私与支持正文、适用第三方许可尚未交付，T045/T048验收。候选不是已发布承诺。

# 通知授权、索引防护与菜单分支资源

| ID | 中文候选 | 语境 |
| --- | --- | --- |
| menu.empty | 尚未添加共享文件夹。 | 无保存目标；不显示演示目标 |
| menu.add | 添加共享文件夹… | 无目标时前台打开主列表或单共享输入 |
| state.standby | 尚未选择此服务器 | 本轮选择了顺序靠前的可达服务器；不推断历史挂载消失 |
| state.standbyHelp | 当前使用顺序靠前的可达服务器。仅当之前的服务器均不可达时，才自动挂载此服务器的共享。 | 排他评估说明 |
| menu.busy | 正在处理此共享，请等待结果。 | 禁用挂载/弹出等冲突动作，仍可查看详情 |
| notification.request | 允许通知… | 仅前台显式请求 |
| notification.purpose | 共享文件夹未能自动挂载时，Automnt 会通知你，方便及时处理。 | 未决定状态；主动说明触发场景与价值 |
| notification.allowed | 通知已允许 | 实际授权状态；不代表横幅必达 |
| notification.denied | 通知已关闭。挂载失败时，你仍可在 Automnt 中查看原因。 | 持续结果，下一步打开系统通知设置 |
| notification.requestFailed | 未能请求通知权限：{reason} | String；保留原因、可显式重试 |
| index.setting | 尝试阻止 Spotlight 索引 | 共同配置意图，不保证系统停止索引 |
| index.help | 减少此服务器共享的磁盘与网络索引活动，同时限制 Spotlight 搜索共享内容。系统限制可能使设置无法生效；不会自动删除已有索引。 | 服务器详情；HostConfig.prevent_spotlight_index，不覆盖其他服务器 |
| index.title | 索引防护 | 逐目标独立于挂载健康 |
| index.off | 未启用 | 偏好关闭，不推断索引实际状态 |
| index.waiting | 等待挂载后检查 | 当前没有可核对的真实挂载 |
| index.completed | 已完成可验证的防护步骤 | 旁列实际范围，不等于索引已停止 |
| index.unconfirmed | 已尝试，但无法确认系统索引状态。 | 正常挂载仍可访问 |
| index.limited | 无法完成索引防护：{reason} | String；诊断入口、不索取管理员权限 |

# 备用目标动作

| 资源ID | 简体中文候选 | 语境与参数 |
| --- | --- | --- |
| state.standbyAction | 挂载 | 手动挂载此目标，保持自动首可达服务器选择与四层偏好 |

# 系统认证资源范围

| 资源ID | 简体中文候选 | 语境 |
| --- | --- | --- |

# 长度与布局策略

所有动作允许原生自适应重排，详情采用纵向动作组。表单说明自然多行；长路径/地址可选择复制并获得完整辅助值；输入横向编辑不截掉已保存值。菜单视觉截断允许，完整名称与状态仍可访问，长菜单滚动。帮助、许可、诊断、确认及较大文字下的sheet均可滚动，关键取消与确认保可达。先以两倍文本膨胀和长变量检查正常/窄窗；两倍是压力样本，不是各语言准确比例或上限。真实九语全部复验，不能用伪本地化代替。每资源的阅读/焦点语境由上表与accessibility.md对应场景共同定义。

本清单仍须对照当前Swift/HTML所有可达错误分支逐条核查，补字段验证、独立系统错误映射及正式商店/支持正文；没有把候选覆盖率宣称为100%。

# 主列表、单行添加与系统认证

| ID | 中文候选 | 语境/动作与参数 |
| --- | --- | --- |
| main.title | SMB 共享 | 左侧平铺服务器摘要；右侧选中服务器的紧凑已管理/可添加组；未挂载配置保留真实状态 |
| main.managedCount | 已管理 {count} | Int；服务器行摘要，系统完整复数资源；不等于已挂载数量 |
| main.addableCount | 可添加 {count} | Int；服务器行摘要，本机已挂载但未管理数量；系统完整复数资源 |
| main.serverIssue | 异常 | 服务器摘要有需处理状态；右侧给具体原因与修复下一步 |
| nav.backServers | 服务器 | 窄窗系统返回服务器层级，恢复选择和滚动 |
| nav.backShares | 共享文件夹 | 窄窗系统返回选中服务器共享层级，恢复共享焦点和滚动 |
| main.managed | 已管理 | 已保存配置；不等于已挂载 |
| main.addable | 可添加 | 本机已挂载、尚未管理的 SMB 共享 |
| main.refresh | 刷新 | 重新读取本机挂载和配置，不扫描任意远端共享 |
| add.row | 添加 | 仅当前共享；立即保存，成功移入已管理组 |
| add.saving | 正在添加… | 当前行保存中，防重复提交 |
| add.failed | 未能添加共享：{reason} | String；保留当前行与输入，可重试 |
| empty.finder | 在 Finder 中连接共享 | 指导使用“前往 → 连接服务器…”；不承诺代替系统认证 |
| manual.open | 输入 SMB 地址… | 次要入口，单共享 sheet |
| manual.title | 添加 SMB 共享 | 不进入向导 |
| manual.url | SMB 地址 | 完整 URL；不含用户名或密码 |
| manual.urlHelp | 输入完整地址，例如 smb://server.local/share。 | 通用语法示例，不是默认值 |
| manual.invalid | 输入包含服务器和共享名称的完整 SMB 地址。 | 就近错误，焦点回字段 |
| manual.add | 添加 | 保存一个共享；成功关闭并重置 dirty |
| auth.system | 使用 macOS 的 SMB 登录信息 | 无独立凭据录入、查看、删除页 |
| auth.finderHelp | 如需登录，请先在 Finder 中连接此共享并完成认证，再重试。 | 已识别认证问题的下一步 |
| main.configUnavailable | 暂时无法读取共享设置：{reason} | String；保留当前观察，不把读取失败当无配置 |

已有 CLI 配置应自动出现在同一管理界面，不提供“检查 CLI 配置”或“导入”资源；共享配置及所有权协调已有本地实现，真实两入口闭环仍未验证。系统凭据复用、沙盒/helper 后台认证及自动恢复尚需真实运行验证。Automnt 是临时名称且来源受质疑，正式名称待确认。当前资源移除八步向导、独立密码管理、多选添加与任意存储目录选择语义；方案 A 的固定目录由程序准备，configAccess.* 表达用途、拒绝及真实访问恢复，不要求选择目录；保留其余服务、菜单、设置、通知、诊断、确认与九语/复数验证缺口。

# 全产品补充语义资源

| ID | 中文候选 | 语境/动作 |
| --- | --- | --- |
| nav.managedServers | 已管理服务器 | 持久顺序，拖放/键盘移动即存 |
| nav.discoveredServers | 可添加的服务器 | 未管理发现候选，不参与优先级 |
| server.orderSaved | 服务器顺序已保存 | 持久化成功独立于挂载结果 |
| server.orderFailed | 无法保存服务器顺序：{reason} | 完整原因，恢复持久顺序 |
| server.undoConflict | 顺序已在其他地方更改，无法撤销。 | 不覆盖最新配置 |
| operation.evaluate | 检查并挂载 | 完整策略评估；九语需语境审校 |
| operation.refresh | 刷新状态 | 只重读配置、挂载和后台状态 |
| operation.singleShare | 挂载 | 单共享显式请求 |
| edit.confirmName | 确认名称 | 行内提交名称 |
| setting.retryPolicy | 重试设置 | 共享核心 retry_policy 参数 |
| help.about | 关于 Automnt | 原生 About，版本派生 |
| remove.lastShareHelp | 此服务器没有其他已管理共享，也会从列表中移除。已经挂载的共享仍可使用。 | 配置移除确认 |

候选资源覆盖 FR-027–032；不新增语言/主题选择或普通弹出确认。名称、原因等为类型化参数，旧排序 Draft 文案不进入当前产品。

# 开始使用与设置访问文案

下表保留完整语义候选及资源语境；历史目录面板实现的 14 个授权键已集成九语应用资源，历史完整性门禁通过，机器草稿不视为获批译文。T080 的可靠语言审校及九语原生布局复核仍待完成。初始 ContentUnavailableView 按标题→用途→主动作阅读，不混入后台许可、通知、SMB 认证或业务配置创建。{reason} 为脱敏、自然语言原因；普通授权资源不使用 {folderPath}/{folderName}，原始书签不进入界面或导出。

| ID | 简体中文候选 | English candidate | 语境/行为 |
| --- | --- | --- | --- |
| configAccess.title | 开始使用 Automnt | Get Started with Automnt | 首次/取消 ContentUnavailableView 标题 |
| configAccess.help | Automnt 会把设置保存在这台 Mac 上。已经添加过的共享文件夹会自动显示。 | Automnt keeps its settings on this Mac. Shared folders you have already added will appear automatically. | 说明设置位置与自动显示，不要求理解内部目录或权限 |
| configAccess.continue | 继续… | Continue… | 首次/拒绝后继续访问；按已验证机制需要时调用真实系统许可，不打开内部目录选择器 |
| configAccess.grant | 重试 | Try Again | 实际读取失败后的重试；不暗示系统授权面板，不承诺通用 API |
| configAccess.panelPrompt | 重试 | Try Again | 历史资源 ID，仅留追溯；当前固定目录由程序准备，不出现系统授权按钮 |
| configAccess.cancelled | 尚未允许 Automnt 访问设置。准备好后，可以继续。 | Automnt doesn’t have access to its settings yet. Continue when you’re ready. | 仍未授权，恢复 Continue… 焦点，无零目标统计 |
| configAccess.wrongDirectory | 无法打开 Automnt 的设置。请重试。 | Automnt couldn’t open its settings. Try again. | 实际校验失败；不要求重选目录或理解权限 |
| configAccess.prepareFailed | 无法打开 Automnt 的设置。请重试。 | Automnt couldn’t open its settings. Try again. | 不展示内部原因给大众用户；诊断可另记脱敏原因 |
| configAccess.stale | 无法打开 Automnt 的设置。请重试。 | Automnt couldn’t open its settings. Try again. | 固定目录不需要书签续期；不暴露内部术语 |
| configAccess.revoked | 无法打开 Automnt 的设置。请重试。 | Automnt couldn’t open its settings. Try again. | 实际读取失败，不当作目标消失 |
| configAccess.readFailed | Automnt 无法读取你的设置。请重试。 | Automnt couldn’t read your settings. Try again. | 读/解析失败；原因不进入大众界面，诊断另记脱敏信息 |
| configAccess.retry | 重新读取 | Reload | 不创建新配置 |
| configAccess.backgroundHelp | 自动挂载暂时无法读取设置。请保持 Automnt 打开以管理设置；后台服务未作更改。 | Automatic mounting can’t read your settings right now. Keep Automnt open to manage them; the background service has not been changed. | 表达影响与下一步，不显示内部协议或权限术语 |

| firstRun.title | 欢迎使用 Automnt | Welcome to Automnt | 全新无配置时详情区标题 |
| firstRun.help | 添加一个共享文件夹即可开始。服务器可用时，Automnt 会自动挂载它。 | Add a shared folder to get started. Automnt will mount it automatically when the server is available. | 一句用途，不要求理解后台/权限 |
| firstRun.action | 添加共享文件夹… | Add Shared Folder… | 首个主动作 |
| status.noRound | 尚未检查共享文件夹。 | Shared folders haven’t been checked yet. | 替代“尚未运行过任何一轮” |
| status.autoMount.unavailable | 自动挂载：暂时无法确认 | Automatic mounting: status unavailable | 状态不可确认，不暗示权限被拒 |
| status.autoMount.off | 自动挂载：已关闭 | Automatic mounting: off | 用户可理解的关闭状态 |
| status.autoMount.running | 自动挂载：运行中 | Automatic mounting: running | 实际运行状态 |
| status.autoMount.waiting | 自动挂载：等待在“登录项”中允许 | Automatic mounting: waiting for approval in Login Items | 系统待批准 |
| status.autoMount.applying | 自动挂载：正在应用设置 | Automatic mounting: applying your setting | 切换中 |
| status.autoMount.cli | 自动挂载：由命令行版本管理 | Automatic mounting: managed by the command-line version | 实际 owner 为 CLI |

2026-10-20 修正：固定目录缺失属于首次启动，不是访问错误；程序启动时自行准备，不再显示“访问 Automnt 设置/允许访问”。只有真实读取失败才显示“无法打开 Automnt 的设置”+“重试”。按钮设置 intrinsic width（`fixedSize`）并保留横/纵回退，逐语验证德语等长标签不截断。状态文案统一“自动挂载/检查”，不使用“后台挂载/一轮”。

废弃 configAccess.create 和带 folderPath 的指导，不新增内部位置字段、选择/更改/导入资源。首次、设置、菜单和恢复支持均无内部目录选择、查找或手工创建；程序准备固定位置，真实许可按需要允许/拒绝，机制仍待验证。拒绝/取消回发起按钮并持续给出原因，成功访问自动读取已有共享，不额外通知/声音，沿系统动效。读失败不显示零目标，已有快照只读；显式诊断可显示路径并按导出规则脱敏。历史 290 项测试/签名/中文首次窗口见[方案 A 实施证据](../../../release/evidence/option-a-authorization.md)，不证明最新权限、helper 生命周期、MAS 或九语。未来 T084/T091/T094 验统一访问、准确字段原因及全界面九语长译文/窄窗/大字/键盘/VoiceOver/拒绝保存退出焦点。

# 当前资源修复边界

现有应用已有单行添加、完整无凭据 SMB URL、用途说明、访问状态与 CAS，不应描述为完全未实现。确认缺口包括已管理服务器新增发现共享未合并、编辑开始 revision/身份及保存基线不足、实际退出草稿保护未接通、生命周期观察不足、无选择引导及窄导航不足。保存后反复提示为尚未复现的用户反馈，不将全部 save 判为故障；共享编辑与原生 demo 的成功关闭证据不证明服务器编辑或实际退出通过。

未来 T086/T089/T090/T091 资源须覆盖已管理服务器新发现共享、事件只刷新、无选择引导/窄返回、空 URL 与非法 URL 的独立原因；T087/T088 须覆盖编辑开始身份/revision、成功基线、冲突/目标消失和实际退出保护。T083–T094 已追加至[主任务清单](../tasks.md)，全部未完成；本文件引用其编号，不表示实现或验收通过。依次覆盖授权架构、统一访问、图标、发现合并、编辑 CAS/dirty/身份、实际退出草稿、生命周期刷新、无选择/窄导航、字段校验文案、owner 中断恢复、真实后台矩阵和全界面原生九语验收。


# 设置文案去防御化（2026-10-20）

登录与通知文案按“用户会得到什么/何时会收到”表达：通知直接说明“共享未能自动挂载时会通知你”，不用“只对……发送、除此之外不发”的免责结构；声音开关说明“仍会收到通知，只是没有提示音”。登录项不可用时说明先退出并从“应用程序”重新打开，再给“检查一次”，不再保留含义不明的常驻“检查登录设置”。通知权限状态用“未开启/已允许/已关闭/暂时无法读取”，不再用“系统授权”这种抽象标签。


# 自动挂载层级文案（2026-10-20）

| ID | 简体中文 | English | 语境 |
| --- | --- | --- | --- |
| automation.includeServer | 此服务器参与自动挂载 | Include This Server in Automatic Mounting | 服务器级参与，不是总开关 |
| automation.serverPending | 自动挂载总开关已关闭。开启总开关后，这个服务器才会自动挂载。 | The main automatic mounting switch is off. Turn it on to include this server. | 总开关关闭时的服务器说明 |
| automation.offTitle | 自动挂载已关闭 | Automatic Mounting Is Off | 详情区启用卡标题 |
| automation.offBody | 共享文件夹已添加。开启自动挂载后，登录或网络变化时 Automnt 会自动挂载它们。 | Shared folders are added. Turn on automatic mounting so Automnt mounts them after sign-in or network changes. | 说明收益与触发时机 |
| automation.enable | 开启自动挂载 | Turn On Automatic Mounting | 主按钮；开启时注册后台服务 |
| automation.turningOn | 正在开启自动挂载… | Turning on automatic mounting… | 保存后、服务激活中 |
| automation.activationFailed | 无法更改自动挂载。请检查后台服务状态后重试。 | Background mounting could not be changed. Check the service state and try again. | 激活失败，不谎报已开启 |


# 后台状态卡文案（2026-10-20）

| ID | 简体中文 | English | 语境 |
| --- | --- | --- | --- |
| background.applyingTitle | 正在应用自动挂载设置… | Applying Automatic Mounting Settings… | 过渡中，开关禁用 |
| background.failedTitle | 自动挂载没有完成 | Automatic Mounting Didn’t Finish | 已开启但服务未确认 |
| background.failedBody | 后台服务没有确认。修复会重新尝试设置，不会重复挂载已挂载的共享。 | The background service didn’t confirm. Repairing retries the setup without mounting anything twice. | 信任说明 |
| background.stopFailedTitle | 后台挂载没有完全关闭 | Background Mounting Didn’t Fully Stop | 关闭时失败 |
| background.notRunningTitle | 自动挂载已开启，但后台服务没有运行 | Automatic Mounting Is On, but the Background Service Isn’t Running | 意图与事实不一致 |
| background.approvalTitle | 自动挂载正在等待系统允许 | Automatic Mounting Is Waiting for System Approval | 登录项待批准 |
| background.repair | 修复后台挂载 | Repair Background Mounting | 主按钮，真实恢复 |
| background.cliTitle | 自动挂载由命令行版本管理 | Automatic Mounting Is Managed by the Command-Line Service | 命令行接管 |


# 工具栏与轮次文案（2026-10-20）

- “Try Automatic Mounting Now”使用闪电图标，tooltip 同名；不是刷新。
- “Refresh Status”和“Server Settings…”收进“更多”菜单。
- 轮次启动被残留 worker intent 阻塞时，提示“上一次挂载操作没有完成。请先修复后台挂载，再重试本轮检查。”，不再使用“无法确认该操作”。


# 2026-10-21 位置、共享行、排序与配置冲突

| ID | 中文候选 | 语境/行为 |
| --- | --- | --- |
| location.mountedElsewhere | 挂载在其他位置 | 同一共享身份已在另一路径；不表示挂载失败 |
| location.actualHelp | 这个共享文件夹已经挂载在另一个位置。使用配置位置的任务可能找不到它。 | 详情解释，列出配置/实际位置 |
| location.useActual | 使用此位置 | 把配置挂载位置改为当前实际路径；不迁移、不弹出 |
| location.openActual | 在 Finder 中打开实际位置 | 只打开实际路径，不打开配置路径 |
| location.occupied | 位置已被占用 | 配置位置被另一个卷占用，不是恢复失败 |
| location.occupiedHelp | 配置的挂载位置被另一个卷占用。Automnt 不会替换它。 | 说明不提供弹出占用卷主按钮 |
| location.showOccupying | 在 Finder 中显示占用位置 | 只查看，不弹出 |
| location.updated | 已使用当前挂载位置。以后会按新位置挂载。 | 改位置成功后的确认 |
| share.review | 查看详情 | 行尾 chevron/整行进入详情；不再按状态换主按钮 |
| share.attentionHelp | 查看每个共享文件夹的原因和下一步。 | 服务器详情顶部的问题摘要卡 |
| server.orderHelpFirst | 按此顺序检查服务器，找到第一个可达的服务器后停止。 | 默认 first_reachable |
| server.orderHelpAll | 按此顺序检查所有可达的服务器。 | all_reachable |
| server.orderDrag | 拖动调整顺序 | 拖拽把手 tooltip |
| server.orderFiltered | 清除搜索后可调整顺序。 | 过滤时禁用排序 |
| server.mountScope | 挂载范围 | 设置项名称 |
| server.mountScopeFirst | 只挂载第一个可达的服务器 | 默认选项 |
| server.mountScopeAll | 挂载所有可达的服务器 | 可选策略 |
| server.mountScopeHelp | 服务器按左侧顺序检查。选择第一项时，找到第一个可达服务器后停止；选择第二项时，继续检查并处理所有可达服务器的共享文件夹。 | 设置说明，随选项变化 |
| config.conflict | 配置已在另一个窗口或命令行中更新。重新读取最新设置后再继续。 | 不再只写“配置已更改” |
| config.reload | 重新读取设置 | 冲突卡的明确入口 |
| config.reloadedDraft | 已重新读取最新设置。你的输入还在，请核对后再保存。 | 表单内重新读取后 |
| config.conflictHelp | 重新读取不会挂载、弹出或覆盖你正在输入的内容。 | 冲突说明辅助 |

# 2026-10-21 实现定稿文案

上一节的候选表用于评审；实际落盘以九语资源 `apps/Automnt/Resources/Localizable.xcstrings` 的键为准。本节记录实现采用的英文源键与简体中文，二者与资源条目一致；其余八语由同一批条目提供（草稿，待母语审校）。

| 英文源键 | 简体中文 | 语境 |
| --- | --- | --- |
| Mount Scope | 挂载范围 | 设置「自动挂载」组选择器名称 |
| First Reachable Server | 首个可达服务器 | 默认选项（first_reachable） |
| All Reachable Servers | 所有可达服务器 | 可选策略（all_reachable） |
| Servers are checked in the order shown in the sidebar. The first option stops at the first reachable server; the second also mounts the shared folders of every other reachable server. | 服务器按侧栏显示的顺序检查。选择第一项时，找到第一个可达服务器后停止；选择第二项时，还会挂载其余所有可达服务器的共享文件夹。 | 选择器说明，随选项解释差别 |
| Mount scope saved. The next round checks servers in this scope. | 挂载范围已保存。下一轮检查会按这个范围执行。 | 保存后的确认 |
| Drag a row by its handle to change the order. A round stops at the first reachable server; later servers wait. | 拖动行的把手可以调整顺序。一次检查按此顺序进行，找到第一个可达服务器后停止，后面的服务器会等待。 | 默认策略的排序脚注 |
| Drag a row by its handle to change the order. Every reachable server is checked in this order and its shared folders are mounted. | 拖动行的把手可以调整顺序。按此顺序检查所有可达服务器，并挂载它们的共享文件夹。 | all_reachable 的排序脚注 |
| Drag to change the order | 拖动调整顺序 | 拖拽把手 tooltip |
| Clear the search to change the order. | 清除搜索后再调整顺序。 | 过滤时脚注，说明排序禁用原因 |
| Mounted at a different location | 挂载在其他位置 | 行/详情状态：同一身份挂在别处，可用 |
| This shared folder is already mounted at another location, so tasks that use the configured location may not find it. Open it there or use that location. | 这个共享文件夹已经挂载在另一个位置，使用配置位置的任务可能找不到它。请在那里打开它，或改用那个位置。 | 位置不同的下一步与影响说明 |
| Open the Actual Location in Finder | 在 Finder 中打开实际位置 | 打开实际挂载路径，不是配置路径 |
| Use This Location | 使用此位置 | 把配置位置改为当前实际路径 |
| Using the current mount location. Future mounts use the new location. | 已改用当前挂载位置。以后会按新位置挂载。 | 改位置成功后的确认 |
| Location occupied | 位置被占用 | 行状态：配置路径被其他卷占用 |
| Location occupied by another volume | 位置被另一个卷占用 | 详情状态标题 |
| Another volume occupies the configured location. Automnt will not replace it. Show it in Finder, or choose a different location for this shared folder. | 配置的挂载位置被另一个卷占用。Automnt 不会替换它。可在 Finder 中查看它，或为这个共享文件夹选择其他位置。 | 占用状态的下一步；不提供弹出占用卷 |
| Show the Occupying Folder in Finder | 在 Finder 中显示占用位置 | 只查看占用路径 |
| Opens this shared folder’s details. | 打开此共享文件夹的详情。 | 行/问题列表的辅助功能提示 |
| %lld shared folders need attention | %lld 个共享文件夹需要处理 | 服务器详情问题列表标题（复用既有键） |
| The configuration changed in another window or from the command line. Reload the latest settings; your input is kept. | 配置已在另一个窗口或命令行中更改。请重新读取最新设置；你的输入会保留。 | 保存冲突说明 |
| Reload Settings | 重新读取设置 | 冲突卡的明确入口 |
| Reloaded the latest settings. Your input is kept; check it before saving. | 已重新读取最新设置。你的输入仍然保留；保存前请核对。 | 重新读取成功后的确认 |
| Reloading does not mount, eject or overwrite what you typed. | 重新读取不会挂载、弹出或覆盖你输入的内容。 | 冲突卡辅助说明，说明安全边界 |
| Every enabled server is checked in the saved order, so this server was not reached in the last round. It is not an error. | 所有启用的服务器都会按保存的顺序检查，所以上一轮没有访问到这台服务器。这不是错误。 | 「上轮未检查」在 all_reachable 下的解释 |
| That folder is no longer available. Refresh the list and check the current location. | 该文件夹已不可用。请刷新列表并检查当前位置。 | 打开已消失的实际/占用路径 |

# 2026-10-21 交互与文案复核后的资源修订

## 冲突与恢复资源

冲突不再描述“另一个窗口或命令行”，也不再要求用户做界面上不存在的动作。可恢复冲突的文案固定为三句：状态（设置已在别处更新）、唯一动作（使用最新设置）、后果（刷新不挂载、不弹出、不覆盖输入）。表单内已过期时不再让用户“重新载入”，而是关闭后重新打开。

新增资源：`Your settings were updated elsewhere. Use the latest settings to refresh this window; what you typed is kept.`、`Use Latest Settings`、`Refreshing mounts or ejects nothing and does not overwrite what you typed.`、`These settings were updated elsewhere. Close this window and open it again.`、`Automnt can’t read your settings right now. Quit and reopen Automnt, then try again.`。

## 全局动作与对象动作的命名

底栏两个全局动作使用带文字标签：`Add Shared Folder…` 与 `Check Now`；悬停说明补足“检查所有共享文件夹并挂载缺少的”。应用设置只保留应用菜单的“设置…”（⌘,）。详情工具栏的服务器级入口改名为 `Server Connection…`，避免与全局设置共用“设置”语义。

## 术语收敛

- 可达 → 可用：`All Available Servers`、`Only the First Available Server` 及两段排序说明。
- 轮次 → 检查：`Attempts per Check`、`Not checked last time`、`The check finished. Each shared folder shows its own result and the time it was checked.`。
- 会话 → 用户动作：`Ejected` 替代 `Ejected for this session`。
- 后台挂载 → 自动挂载状态（设置行），保留“后台服务”只在解释为何未生效时出现一次。
- `Show the Menu Bar at Login` 改为 `Show Automnt in the Menu Bar at Login`，与“在菜单栏中显示 Automnt”区分“现在显示/登录时显示”。
- 命令行接管时明确说明“目前由命令行版本管理自动挂载……请先在命令行中停止服务”，不再提供必然报错的修复按钮。

## 仍待修订

共享详情内的开关失败提示、服务器设置“完成”的保存模型、菜单栏动作结果、移除最后一个共享的后果说明仍沿用旧资源，待下一轮交互修订一并处理；九语翻译仍为草案，需母语审校。
