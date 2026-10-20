# 本轮认证与配置目标

当前设计复用 macOS 的 SMB 登录凭据，不再提供独立密码管理；不存在本轮应用 Keychain CRUD 修复或共享密码库验收要求。沙盒/helper 实际复用系统认证、后台挂载与恢复仍未验证。已有 CLI 配置应在首次系统面板授权固定配置文件夹后自动出现在 GUI；本地路径/书签/权限状态与 helper 预检已经接入，真实共享访问及后台验收未闭环。不要求用户检查或导入 CLI 配置，不提供任意存储位置选择。2026-10-13 最新签名构建、289 项测试和原生未授权窗口记录见 [方案 A 实施证据](option-a-authorization.md)。

以下所有 2026-10-11 探针、测试、构建、旧界面和权限矩阵均为历史实现版本记录，保留当时结果。Keychain insert/delete 的 `-34018` 调查属于已移除的独立凭据管理范围，未修复、未通过，不能解释成系统 SMB 认证复用已验证。历史目录/书签路线亦不作为当前产品步骤。App Group 与 launchd 的局部成功不等于系统认证、共享所有权、真实 SMB 挂载或退出/登录/网络恢复验收。

# 实施范围与当前结论

2026-10-11 round90真实运行复验：最新签名GUI `--check-background-job-presence` exit0，legacy registered、baseline/recovery absent，耗时0.048337667s（`.build/round90-service-presence.log`）。故本机旧安装仍不满足import release gate，未触发配置写入/停止服务。独立随机Keychain探针exit1，insert/delete仍-34018，issue authorizationRequired，cleanup unverified（`.build/round90-keychain.log`）；这确证本签名权限仍不足，不能建议只解锁或重输密码即可解决，亦不证明免费账号绝对不支持。未启动真实SMB mount/GUI window。

2026-10-11 guarded import commit：原生预览新增Import CLI configuration动作，snapshot已存在/缺内部授权/后台切换/eject时disabled，调用时再次guard；旧CLI配置及legacy/baseline/recovery job均须明确absent，unknown拒绝。仅使用已选文件preview.source进入既有repository absent-only import，保留unknown字段/强制automation=false，成功reload readiness/关闭sheet，失败保留预览显示说明。不自动删除CLI配置或停止已安装service；旧安装迁移/原子释放协议仍未闭合，检查后外部重新注册的竞态未消除。2项既有import tests通过（`.build/import-commit-tests.log`），免费签名Release/seal/diff通过（`.build/import-commit-build.log`），真实GUI导入尚未运行，T015不勾。

2026-10-11 凭据状态失效处理：sheet共享identity变化清draft/旧presence/username/确认状态并重新attributes查询；invalid identity明确提示并清状态；关闭清username/presence；delete失败把状态置unknown而非沿用已存在，需Check重试。免费签名Release/三目标seal/diff通过（`.build/credential-state-reset-build.log`）；无新增本地化字符串。真实GUI交互与Keychain权限仍待，不把此build当CRUD验收。

2026-10-11 round87同步：最高优化CLI构建/资源及本地化gate通过（`.build/cli-round87-build.log`），候选免费Apple Development签名strict通过、version3.4.0、295 passed/0 skipped/0 failed（`.build/cli-round87-self-tests.log:4850`）。核对根目录绝对路径且target/candidate非symlink后备份`.build/automnt-before-round87`并替换root automnt；root/candidate字节相同，SHA256 e5946fc6ab622d971e47a1a5e5b28cf5770a239ce25420fba38dab0658e30a97，strict/version/diff复核通过。未替换已安装CLI服务。全量Swift78 Core+116 Platform共194项通过（`.build/full-tests-round87.log:217,525`）。本轮不构成真实Keychain/SMB自动恢复验收；T014/T015/T016/T033等父任务保留未完成。

2026-10-11 active-app手动操作增量：StoppedManualOperation在owner app时不再直接放行，实际launchctl检查baseline/recovery必须恰一registered/另一absent，unknown/双注册/双absent拒绝；parent与worker在evaluation lock内的既有调用同时生效。2项tests通过（含9种presence组合，`.build/manual-active-service-tests.log`），免费签名Release/三目标seal/diff通过（`.build/manual-active-service-build.log`）。继承沙盒worker实际launchctl visibility与真实mount/eject尚待，注册事实不当作SM approval/helper health证据。

2026-10-11 导入预览增量：原页仅显示host，现以原生List/Section显示host alias、address/port、每share name/SMB URL/mountPoint，动态值verbatim及可选文本复制，无新本地化文案。签名Release/三目标seal/diff通过（`.build/import-preview-details-build.log`）；未做真实窗口/VoiceOver验收。没有接通import commit：目前仍未证明旧CLI服务已释放，不能以保存旧数据绕过唯一配置/后台接管契约。

2026-10-11 profile核查：本机新profile目录无文件、旧目录不存在；基础权限自动签名build exit0（`.build/auto-signing-check.log`），GUI临时共享keychain group自动签名build exit65，缺org.automnt.automnt Mac App Development profile，提示-allowProvisioningUpdates（`.build/auto-keychain-signing-check.log:67`）。已撤回实验声明；未执行门户provisioning更新。新增release/mas/account-runbook.md区分开发profile核对/门户资源操作与正式付费团队/商店提交，不把无本机profile推断成免费账号必然不支持。T053仍未执行。

2026-10-11 Keychain签名权限实验：GUI/helper临时声明各自com.apple.application-identifier与同team keychain-access-groups后，手动Apple Development build exit65，Xcode明确要求Automnt provisioning profile（`.build/keychain-entitlement-build.log:69`），尚未进入运行；这仅证明当前无profile配置不足，不证明免费账号绝对无法生成profile。已撤回该两项声明恢复可构建配置，免费签名Release/三目标seal/diff通过（`.build/keychain-entitlement-restored-build.log`）。verify-signature.py加强为所有显式声明（含generated keys）都必须在签名中精确存在，再比较sandbox键集合；避免未来显式application-id被忽略。下一步检查本机可用profile/自动签名能力；不得用传统Keychain降级掩盖共享后台凭据契约。

2026-10-11 真实Keychain失败证据：GUI --probe-keychain-storage以隔离service org.automnt.keychain-probe/随机account和内存随机值执行CRUD，不触碰SMB项，不输出identity/username/password。免费签名Release/三目标seal通过；实际runtime exit1，initial-absence通过后insert SecItemAdd=-34018（errSecMissingEntitlement），delete同码、cleanup未验证（`.build/keychain-storage-runtime.log`）。这不是Keychain锁定证据，也不是CRUD成功；当前data protection Keychain签名权限不足，需继续核对可用entitlement/profile及GUI/helper共享契约。没有成功返回的新增项；不据此保证不存在残留。此前用户名实现仅build/边界测试通过，真实保存仍不成立。

2026-10-11 凭据用户名状态增量：保存时把用户名同步写入Keychain label属性（用户名属于可查询属性，密码仍仅保存在data payload）；attributes-only metadata返回present+可选username，旧item无label时不读取密码补齐。凭据页独立显示已保存用户名，不填编辑draft，删除/查询失败清除显示。4项credential memory/pipe边界测试通过（`.build/credential-metadata-tests.log`），免费签名Release/三目标seal/diff通过（`.build/credential-metadata-build.log`）。测试未涉及实际Keychain add/update/read或GUI交互；共享helper Keychain与真实连接验证仍未完成。

2026-10-11 沙盒job查询运行证据：签名GUI新增只读--check-background-job-presence，最终构建三目标seal通过后实际exit0，legacy=registered/baseline=absent/recovery=absent，耗时0.052635042s（`.build/sandbox-job-presence-runtime.log`）。证实GUI沙盒可查询本机jobs，未证明继承worker相同查询/实际挂载。初次CLI localization门将label调用误判为界面文案，转为Platform命名入口后门通过。当前Core/CLI最高优化重建/免费签名strict/295自测0skip0fail通过（`.build/cli-round80-build.log`/`.build/cli-round80-self-tests.log`）；根替换3.4.0，旧根备份.build/automnt-before-round80，根/候选SHA256=524647d2643b45aa94f6eca2dd84af592401b58f1caedcb8dcb103658d6548ce。未动安装业务CLI/服务；未验证SMB恢复/完整界面，目标未完成。

2026-10-11 停止态弹出接入：parent unmount请求显式manual标记，平台与worker采用停止态许可、旧CLI config/job absent检查及helper lease/固定GUI job排除；菜单/详情弹出与调用前刷新共用手动就绪条件，后台切换中禁用。成功弹出仍仅在pending intent+内核path absent时写suppression，失败不伪造结果。6项UserEject/ownership/readiness测试通过（`.build/stopped-eject-tests.log`），免费签名Release/三目标seal/diff通过（`.build/stopped-eject-build.log`）。真实弹出/停止服务/沙盒查询未验，不勾T033；root仍待同步round77 Core判定。

2026-10-11 停止态worker排他：StoppedManualOperation在evaluation.lock内对none owner取得helper lifetime lease，再严格launchctl确认两个固定GUI job absent；parent预检、worker执行均接入，worker保持lease到实际挂载返回，后启动helper不能并行评估。注册存在/查询unknown拒绝；active app路径仍用原owner许可。免费签名Release/三目标seal/diff通过（`.build/stopped-worker-lease-build.log`），2项helper lease排他/停止态判定测试通过（`.build/stopped-worker-lease-tests.log`）。未证明沙盒launchctl可用或真实挂载；停止态eject、旧CLI跨store接管/fresh setup仍待；root需同步上轮Core变化。

2026-10-11 停止态GUI入口：新增canMount独立判定，manualMountReady基于revision/终态owner、baseline/recovery实际SM状态；none/stopped仅automation=false且两注册stopped，active app仅一enabled/另stopped可用。菜单/详情手动按钮及调用前刷新采用独立判定，eject原规则不变；legacy未知仍由platform/worker拒绝。4项策略测试通过（`.build/stopped-mount-ui-tests.log`），免费签名Release/三目标seal/diff通过（`.build/stopped-mount-ui-build.log`）。未真实点击/停用/SMB，仍缺worker侧SM注册变化竞态复核、停止态eject完整契约及fresh setup；Core新增判定使根CLI再次需同步，未完成目标。

2026-10-11 根CLI同步：当前源码经scripts/build.sh最高优化arm64/macOS27构建（版本/九语/concurrency门），Apple Development身份org.automnt.cli签名、strict验证、295自测0skip/0fail通过（`.build/cli-round76-build.log`/`.build/cli-round76-self-tests.log`）。确认根绝对路径及非symlink后备份`.build/automnt-before-round76`并替换根automnt；--version=3.4.0，根与候选SHA256同为8ae1b36f413ee12075e386396488dbe2c5bf4e04c73172923bd62bf7abdbb3ee，strict验证exit0。未替换已安装业务CLI、未注册/停止任务，未发布；本地未发布兼容minor批次仍用SSOT3.4.0。此记录闭合截至本轮共享Core源码与根二进制差异，不代表GUI/核心恢复验收完成。

2026-10-11 旧CLI job排除接入：新增LegacyServicePresence只读launchctl print（2s期限+各200ms终止/kill等待；stderr私有UUID文件≤64KiB），严格复用LaunchAgentPresence分类。ManualEject.mount与worker调用，worker锁内复查；registered（含idle）/unknown拒绝。免费签名Release/三目标seal/diff通过（`.build/manual-legacy-job-build.log`），4项absence分类/手动ownership测试通过（`.build/manual-legacy-job-tests.log`）。沙盒launchctl实际允许性未验，失败保守拒绝；未停止现有business job。GUI停止态按钮与服务实际停止检查仍待接入，根CLI仍待同步重建。

2026-10-11 终态journal兼容纠正：完成切换仍留transitionID用于审计；ManualOperationOwnership现允许active app+desired app+verified enabled及stopped none+desired none+verified stopped的保留ID，仍拒未匹配ID/非终态。24项策略/所有权/handoff测试通过（`.build/manual-terminal-journal-tests.log`），免费签名Release/三目标精确entitlements/嵌套seal通过（`.build/manual-terminal-journal-build.log`）。此记录纠正前两轮“无transition才可操作”的过严表述。旧CLI job排除仍待接入，GUI停止态入口仍未开放；根CLI未同步共享Core增量。

2026-10-11 停止态worker接入：ManualEject.mount与mount+manual worker使用explicitManualAppOperation许可；两侧legacy config必须absent，worker锁内再次检查，unknown拒绝；启动intent pending校验保留。GUI尚未开放停止态按钮，须补实际服务停止判定及跨store旧job排除。首次构建进行时追加worker锁内复检，随后重新完整签名构建exit0（`.build/manual-stopped-worker-final-build.log`），三目标精确entitlements/嵌套seal通过；未验证真实SMB/停止态界面。根CLI尚未重建共享Core增量。

2026-10-11 手动停止态锁内许可：EvaluationPermit增加默认false explicitManualAppOperation，仅owner参数app可用，持evaluation.lock重读revision/generation后按停止态策略校验；默认自动评估仍要求active owner。10项ManualOperationOwnership/OwnershipConflict测试通过（`.build/manual-locked-permit-tests.log`），覆盖已停止许可、自动评估拒绝、过期generation、CLI拒绝及原有所有权回归。新增入口尚未由GUI/worker调用，不能标完整手动契约；须继续检查worker journal许可及旧CLI排除。当前签名GUI/根CLI尚未重建本轮共享Core增量。

2026-10-11 停止态手动操作策略基础：新增ManualOperationOwnership纯判定，app active且无冲突transition可操作；none/stopped仅automation=false且lastVerifiedServiceStatus=stopped、无transition/外部desired owner可操作，cli/stopping拒绝。2项策略测试exit0（`.build/manual-owner-policy-tests.log`），保留现有弃用/测试unused warnings。尚未接入EvaluationPermit/worker/UI/legacy实查，运行行为不变，不作为全局停用手动操作完成，也未更新GUI签名产物或根CLI。后续接入前必须补锁内revision/generation与旧CLI排除。

2026-10-11 手动目标控制增量：菜单/详情/ManualEject不再因Host/Share enabled=false禁手动挂载；worker仅对operation=mount且manuallyRequested=true放行目标自动化enabled，不影响health/cleanup自动保护。全局automation与app active owner/锁/版本校验仍保留，因此全局停用后的显式手动操作仍未满足完整契约，需独立停止态permit而非直接绕过所有权。免费签名Release/三目标精确entitlements/嵌套seal/diff通过（`.build/manual-disabled-target-build.log`），实际目标挂载未验。不标T033/T036完成。

2026-10-11 恢复开关应用：saveRecovery即时CAS后，automation=true自动调既有bounded repair-to-app切换固定服务，执行前核revision/仍enabled；automation=false只保存恢复偏好。legacy未知/owner保护保留，不假报应用成功。免费签名Release/三目标精确entitlements/嵌套seal/diff通过（`.build/recovery-setting-apply-build.log`）。未执行真实业务服务切换/失败回退，不标T033完成；UI-only无需CLI重建。

2026-10-11 当前产物运行复验：签名App --check-shared-container exit0，directory/writable-metadata=false；随即以新随机UUID跑内置probe write/read/remove，各exit0并清除标记，证明当前签名进程实际访问可用，metadata false不当写失败。--check-helper-authorization exit0，仅signature/group预检，明确runtime-unverified；--check-legacy-configuration exit0输出unknown，不当CLI不存在。完整swift test exit0，Core77项/Platform112项=189项（`.build/full-tests-round68.log`），未替代UI/真实SMB恢复验收。未改源码，无CLI重建需求。

2026-10-11 凭据检查恢复：新增九语Check saved credentials，原页重试attributes存在查询，成功清旧错误、不改凭据草稿、未知保持删除禁用。免费签名Release/三目标精确entitlements/嵌套seal/localization/diff通过（`.build/credential-recheck-build.log`）；未触发真实权限失败/恢复，不标T014完成。UI-only无需CLI重建。

2026-10-11 凭据失败草稿：save失败仅password清空、username保留，九语提示重输password，成功/离开/放弃照常清全部。免费签名Release/三目标精确entitlements/嵌套seal/localization/diff通过（`.build/credential-failure-draft-build.log`）。ioreg console复检CGSSessionScreenIsLocked=true，未触发真实Keychain失败/原生退出交互；不作为UI验收。初次plistlib.load管道不可seek退出1，改loads缓冲解析退出0后取得锁定状态。UI-only无需CLI重建。

2026-10-11 GUI停用闭环接线：saveAutomation(false)先CAS写freeze，再在任务开始核revision/仍false，调已有bounded repair-to-none，drain/unregister错误仍呈现；未获CLI控制不绕owner保护。Handoff筛选测试16项、免费签名Release/三目标精确entitlements/嵌套seal/diff通过（`.build/automation-disable-handoff-tests.log`、`.build/automation-disable-build.log`）。非真实业务服务停用证据；开关/退出竞态、实际worker drain与旧CLI独立store仍待；UI-only无需CLI重建。

2026-10-11 凭据删除影响：Credential sheet传入当前配置share，同SMB identity列清单于页与确认框，补删除后已有挂载仍可用九语草译，保留其它配置可能复用提醒。免费签名Release/三目标精确entitlements/嵌套seal/localization/diff通过（`.build/credential-deletion-impact-build.log`）。未触发真实业务凭据删除；取消/删除/失败及长清单布局待解锁，不标T014完成；UI-only无需CLI重建。

2026-10-11 Keychain presence：provider contains使用returnAttributes不取data，notFound=false、授权/其它错误throw；sheet打开查询，删除仅confirmed presence启用，成功保存/删除更新presence，未知显示下一步。三条九语草译，4项Credential测试（边界层，非真实Keychain跨进程）、localization/免费签名Release/三目标精确entitlements/嵌套seal/diff通过（`.build/credential-presence-tests.log`、`.build/credential-presence-build.log`）。已存用户名、服务器验证、复用影响清单与真实共享Keychain权限仍待，未标T014完成；Platform/UI-only无需CLI重建。

2026-10-11 已有server草稿保留：HostEditor Add to this server原identity重复会丢弃不同共享name/mountPoint/enabled；改为整组preflight，同identity不同share不改host/saveIndex、不部分合并并显示既有验证提示；完全相同才去重。免费签名Release/三目标精确entitlements/嵌套seal/diff通过（`.build/existing-server-draft-build.log`）。没有执行真实GUI重复共享路径，未把编译当交互验收；UI-only无需CLI重建。

2026-10-11 mounted多选草稿防部分丢失：HostEditorView在加入草稿前allSatisfy整组host/port检查，选后改地址不静默跳过、不清选择、不部分改草稿；匹配成功才合并去重并清反馈。2项MountedShareDiscovery测试（解析层，不是UI交互）、localization/免费签名Release/三目标精确entitlements/嵌套seal/diff通过（`.build/discovery-selection-tests.log`、`.build/discovery-selection-build.log`）。真实窗口选后修改/保存路径待解锁，未把解析测试当UI验收；UI-only无需CLI重建。

2026-10-11 诊断权限纠偏：GUI DiagnosticAuthorizationSummary原先三个值均hasAuthorization，会将内部group目录描述成bookmark/scoped grant；改为真实PermissionStore.hasSavedBookmark与配置AuthorizedDirectory.scoped，旧CLI临时inspection scope不作为配置后台grant。10项Diagnostic测试、免费签名Release/三目标精确entitlements/嵌套seal/diff通过（`.build/diagnostic-authorization-tests.log`、`.build/diagnostic-authorization-build.log`）。真实签名GUI导出交互待解锁验证；Platform/UI-only无需CLI重建，整个Feature未完成。

2026-10-11 后台启用前原CLI检查：GUI保存过group配置也不能仅凭group owner排除旧CLI；activateAppBackground automation=true前置LegacyConfigurationPresence重读，present/unknown在helper检查、注册、repair之前返回；host后台section补临时授权入口。localization/免费签名Release/三目标精确entitlements/嵌套seal/diff通过（`.build/legacy-background-guard-build.log`）。尚无旧launchd job释放证明；配置absence不证明job absent，本项仅缩小绕过面，不宣称迁移、首次流程、核心自动恢复通过；UI-only无需CLI重建。

2026-10-11 原CLI检查反馈补齐：absent/present/unknown分别显示下一步，错选提示正确Library/Application Support位置，不再将takeoverRequired展示成通用保存错误。九语言两键、免费签名Release/三目标精确entitlements/嵌套seal/diff通过（`.build/legacy-inspection-feedback-build.log`）。本轮实际ioreg解析确认uid501/onConsole true/CGSSessionScreenIsLocked true；先前根plist解析KeyError已修正，不将锁屏环境作为原生窗口验收。选择器授权/实际保存/完整首次体验仍待；仅UI变化，CLI无需重建。

2026-10-11 原CLI位置检查：首次页SwiftUI folder fileImporter可授权真实用户Library/Application Support的临时读取，PermissionStore严格验证canonical路径，保留scope至model结束，无bookmark写入/目录创建；save仍重读LegacyConfigurationPresence，不缓存absence。九语言两键校验、presence测试、免费签名Release及三目标seal/diff通过（`.build/legacy-directory-inspection-tests.log`、`.build/legacy-directory-inspection-build.log`）。尚未真实操作选择器或验证sandbox授权后absent路径；已有CLI用户仍必须迁移。该入口仅是CLI检查授权补充，全新用户常规无需选择目录的已批准体验仍未满足，不作为首次设置完成证据。Platform/UI变化，不影响刚重建CLI。

2026-10-11 兼容CLI新增显式--disable-automation（在Feature3.4.0未发布批次内）：前置严格参数/非daemon，搬迁自愈前CAS保存false并协调器释放，保留安装/配置/已挂载卷。优化编译/免费签名/295自测0失败、help真实包含入口、非法extra参数真实返回2、根automnt替换/strict/diff通过（`.build/disable-command-build.log`、`.build/disable-command-self-test.log`、`.build/disable-command-help.log`、`.build/disable-command-invalid-args.log`）。有效业务停用命令未执行，故不宣称旧后台释放或实际迁移完成；GUI释放证明接线仍待。

2026-10-11 CLI释放判定：只读launchctl查询不存在probe label真实exit113/明确Could not find service；不触碰业务job。共享LaunchAgentPresence只接受匹配label且113的missing，权限/timeout/未知拒绝stopped，5类断言通过（`.build/launchagent-presence-tests.log`）。CLI stopAndVerify使用bounded bootout及print、plist删除失败抛错、worker排空后再次查询；status不再由plist存在性或任意非零错误推导stopped。免费签名原生GUI及嵌套seal通过（`.build/launchagent-presence-gui-build.log`）。最终优化CLI/免费签名/295自测/根automnt替换/strict/diff通过（`.build/launchagent-presence-final-build.log`、`launchagent-presence-final-self-test.log`）。实际旧服务释放未执行，GUI迁移依旧未完成。

2026-10-11 原生授权预览接线：首次页新增SwiftUI fileImporter plist选择与sheet服务器列表；ConfigurationImportPreview只读取用户所选文件并释放security scope，不修改源或目标。读取限制1MiB/nofollow/私有普通文件，隐私/schema验证，拒绝symlink；程序create输入的预览/revision不变/symlink回归通过（`.build/import-preview-final-tests.log`）。九语言3资源校验、全Package（`.build/import-preview-package-tests.log`）、最终免费签名Release/三目标/嵌套seal/diff通过（`.build/import-preview-final-build.log`）。选择器/预览尚未在解锁桌面真实操作验收；sheet无提交动作，旧后台释放与正式导入尚未完成，不宣称完成迁移。仅Platform/UI变化，CLI binary不受影响。

2026-10-11 签名沙盒旧配置探测：真实app --check-legacy-configuration exit0输出presence=unknown（`.build/legacy-sandbox-probe.log`），证明无法直接访问旧路径；这不证明不存在，当前首次保存守卫会拒绝，GUI-only可用性尚未闭合。共享repository新增显式importConfiguration，限制1MiB、privacy/schema验证、保留未知字段、禁止覆盖、自动挂载强制关闭；ConfigurationImportTests经程序create生成输入，扩展字段/停自动化/拒绝覆盖通过（`.build/configuration-import-tests.log`）。优化CLI重建/免费签名/295自测/根automnt替换/strict/diff，GUI原生Release与三代码目标/nested seal均通过（`.build/configuration-import-cli-build.log`、`configuration-import-cli-self-test.log`、`configuration-import-gui-build.log`）。导入API尚未接GUI；不修改真实旧配置，不停真实旧服务。正式接管需释放证明与授权读取，仍未完成。

2026-10-11 唯一配置保守边界：GUI saveFirstHost前对真实home下旧CLI automnt.plist只读O_NOFOLLOW探测；existing及permission/unsafe path unknown拒绝create，草稿保留，新增九语言冲突说明（母语审校未完成）。LegacyConfigurationPresenceTests区分缺失、非法内容现有文件、目录、正常/悬空symlink；`.build/legacy-presence-tests.log`通过，localization校验、免费签名Release及app/helper/worker/nested seal、diff通过（`.build/legacy-presence-gui-build.log`）。此改动仅阻止静默双配置；没有宣称迁移完成。沙盒对旧路径的deny可能同时影响全新用户，正常首次保存可用性待解锁后运行核查，正式确认/导入/旧服务释放入口仍需实施。CLI源码未变，根二进制保持上一轮同步。

2026-10-11 CLI只读状态查询同步：--status严格仅两个参数，在自安装/自愈之前读取canonical安装。实机候选签名org.automnt.cli与安装automnt不同仍exit0；安装binary/活动plist/LaunchAgent plist hash+mtime未变化。真实现有配置为两个主机、各两个共享，内核已挂载；只读发现不是GUI迁移或恢复通过。优化重建、免费Apple Development签名、295 passed/0 skipped/0 failed、strict签名验证、根automnt替换与--status/--version3.4.0/diff通过（`.build/status-readonly-final-build.log`、`status-readonly-final-self-test.log`、`status-readonly-final-runtime.log`）。没有改动旧安装或服务。T022部分进展，App Group配置接管仍未完成。

2026-10-11 实际旧CLI边界：launchctl print gui/501/com.user.automnt成功，state=not running但job仍loaded，WatchPaths/StartOnMount事件eligible，runs154/last exit0；不能把当前无进程当释放成功。codesign requirement比较：根二进制identifier org.automnt.cli，已安装identifier automnt，均同免费Apple Development身份；解释了--status安装前置身份拒绝，但未授权静默重签旧安装或bootout，因此保持旧后台。已撤回无证据窗口改动的当前源码Release/三目标/嵌套seal/diff通过（`.build/locked-desktop-revert-build.log`）。GUI迁移须通过兼容管理入口显式释放eligible旧job并验证，再提交App Group配置；当前缺口保持未完成。

2026-10-11 窗口复验环境更正：桌面截图`.build/windowless-desktop.png`全黑；ioreg Root的IOConsoleUsers明确CGSSessionScreenIsLocked=true/onConsole=true/uid501（`.build/desktop-session-state.plist`）。前两轮空AX窗口观测发生在已锁屏环境，不能支持普通启动缺陷结论。独立Commands窗口环境改动也已撤回；恢复原先在解锁桌面实际成功过的窗口代码，保留表单dismiss-before-terminate修正。未改动表单/保存后退出仍需解锁桌面实际复验，不绕过锁屏。此前sample正常事件等待与签名构建结果保留，但不宣称窗口修复或复验通过。

2026-10-11 单实例窗口复验：先核对并TERM清理五个工作区签名测试副本（均无持久配置），普通open启动PID79200，AX窗口列表为空，File/Open仍为空。sample主线程正常AppKit事件等待（`.build/single-instance-window-sample.txt`），无证据表明配置/授权阻塞。将Open动作的openWindow环境放入独立SwiftUI Commands后签名构建通过（`.build/window-command-environment-build.log`），PID79438菜单项enabled=true但仍无窗口。试验禁用Scene恢复签名构建通过（`.build/window-restoration-build.log`），PID79690仍无窗口，已撤回该无效恢复策略。Commands环境改动保留但不宣称修复；原始单实例窗口及未改动Quit尚未通过。最终源码相较最近产物只撤回恢复策略，下一轮需重建并继续定位。后台未启用，配置未保存。

2026-10-11 接管核查及未改动表单退出：确认GUI internalDirectory在App Group、CLI getActiveConfigURL仍在原Application Support、AppServiceHandoffAdapter明确拒绝CLI owner，现有配置迁移/旧服务释放尚未实现，不得宣称共同管理。根CLI --status退出1并报安装签名身份不兼容，不能据此推断旧服务已停止。未改动HostEditor/Credential的Quit分支也改成dismiss→onDisappear终止，免费签名Release/三目标/嵌套seal/diff通过（`.build/unchanged-draft-quit-build.log`）。运行PID79016多副本环境下File/Open两次无AX窗口，editor动作均-1728；未完成未改动Quit复验，不外推普通单实例启动缺陷。需要清理自身测试副本再测。无配置持久写入/后台启用。

2026-10-11 真实发现入口验收：系统mount -t smbfs实际返回两项同服务器已挂载卷；签名沙盒PID78718首次editor→真实发现按钮，AX列表显示两项SMB URL与mountPoint，URL无用户名。多选→添加按钮→AX host=真实发现主机、port=445，未手填/硬编码目标、未保存配置/启用后台。证明沙盒内getmntinfo及发现→草稿链路可用；资源不是缺失，持久保存/唯一活动配置接管/恢复仍待闭合。凭据保存对话框仅修正缩进，行为无变化。

2026-10-11 模态退出时序真实复验：HostEditor/Credential保存成功/放弃后改为先dismiss，再onDisappear调用finish；避免在确认sheet内直接终止。免费签名Release/三目标/嵌套seal/diff通过（`.build/draft-dismiss-quit-build.log`）。新PID78529：真实主窗口→首次编辑→仅Spotlight开关改动→“退出 Automnt”→嵌套确认button2放弃→AX进程count=0，放弃后退出路径通过。无业务配置保存/后台启用。服务器保存后退出与凭据表单仍待真实复验；T013整体不闭合。

2026-10-11 显式Quit菜单复验：原委托路径PID77965同样未读到确认；新增SwiftUI appTermination命令直接调用现有草稿request（系统委托保留），免费签名Release/三目标/嵌套seal/diff通过（`.build/draft-quit-command-build.log`）。新PID78140真实“退出 Automnt”菜单点击→嵌套确认实际存储/放弃更改/继续编辑；继续编辑后AX确认嵌套sheet=0、草稿开关0保留；再次Quit→点击放弃后嵌套确认消失，但进程count=1、编辑sheet仍1，终止未成功。故仅确认呈现/继续编辑已通过，不宣称完整Quit闭合；需调查模态sheet内terminate时序。未保存业务配置或启用后台。

2026-10-11 Quit草稿状态增量：PID77658确认frontmost=true、Quit菜单enabled=true、草稿开关0后发送⌘Q，仍未读到嵌套确认（-1719），故原路径未验收通过。代码核查发现HostEditor/Credential退出回调仅task首次注册，改为onChange(hasChanges/hasInput, initial:true)按最新布尔状态更新回调，避免捕获初始View值；不把此推断作为已复现根因。免费签名Release/三目标/嵌套seal/diff通过（`.build/draft-quit-refresh-build.log`）；修改后真实Quit复验尚待执行，未闭合任务。

2026-10-11 单实例启动/放弃复验：PID76946可见Cancel按钮点击→真实嵌套确认→放弃更改，AX确认sheets=0并仍显示空配置“设置 Automnt”。此前两个副本已退出，ps仅剩该验证进程；通过原生Quit结束后，等待进程退出再普通open（不带-n），新PID77658自动window=Automnt。故此前多实例open -n无窗口不代表普通启动失败，撤回对正常启动缺陷的推断；场景排序没有单独因果证据。无目标/配置保存。PID77658编辑草稿后原生Quit菜单点击仍进程存活、编辑sheet保留，但没有读到确认，需核查sheet期间Quit菜单是否启用/动作投递，不宣称Quit保护通过。

2026-10-11 首次编辑真实交互样本（PID76946，中文/macOS27.2/免费签名）：AX读取空配置页面“设置 Automnt”，点击真实主按钮打开服务器设置sheet，无配置文件夹选择。未改动⌘W后window=Automnt/sheets=0；重新打开仅点击Spotlight草稿开关，独立⌘W后出现嵌套“保存更改？”确认，按钮实际描述为存储/放弃更改/继续编辑；点击继续编辑后sheet保留、确认sheet=0、开关值0保留。后续重复⌘W因前台焦点/键盘投递未稳定形成确认，discard自动化索引报-1719，未宣称通过。无业务目标输入/保存，无后台启用；当前测试副本仍保留未保存设置草稿。首次取消局部已验证，完整保存/放弃/⌘Q仍待验证，T013不闭合。

2026-10-11 窗口呈现定位：PID76641主线程sample为正常AppKit事件循环，非诊断RunLoop阻塞（`.build/windowless-app-sample.log`）。新增原生File/Open Automnt命令，复用SwiftUI openWindow(main)，免费签名Release/三目标/嵌套seal通过（`.build/window-open-command-build.log`）。PID76946的真实辅助功能菜单“文件→打开 Automnt”点击后读取window name=Automnt，证明主场景可呈现；正常启动自动呈现仍未修复，不能闭合首次启动验收。未保存业务配置。

2026-10-11 原生窗口自动化初查：System Events UI elements enabled=true，已可读取目标进程菜单；正常open启动PID76487实际无窗口。将Window移到MenuBarExtra前，免费签名Release/三目标/嵌套seal/diff通过（`.build/window-launch-order-build.log`）；新PID76641仍经按PID辅助功能读取返回无窗口，故场景排序调整没有解决此样本，不宣称修复。需继续核查启动事件/场景呈现与窗口状态；未输入/保存业务配置、未启用后台、未操作其他应用。⌘W及完整首次流程验收仍待窗口可访问后继续。

2026-10-11 编辑器及平台复验：首次保存路径直接程序create、automationEnabled=false；编辑器保存失败保持draft和sheet，取消无create调用（代码核查，非真实窗口验收）。保存失败九语文案移除要求检查内部文件夹权限/共享文件夹设置的误导，改为输入保留、重试及持续失败联系支持。九语键完整性通过，免费签名Release/三目标/嵌套seal通过；平台回归75测试/20 suites全部通过（`.build/service-controller-platform-tests.log`）；构建 `.build/editor-save-copy-build.log`。翻译为待人工母语复核，真实窗口取消/失败/快捷键仍未验收，不勾T013。

2026-10-11 正常服务控制接入：ServiceController对notFound仅在App/helper严格签名、固定随包plist Label/BundleProgram正确且无替代Program/ProgramArguments时映射stopped，未知/无效定义保留unavailable；enabled/requiresApproval互斥门槛不变。async unregister对已停止幂等返回，进程租约及worker收敛检查仍由handoff保留。受限探针改用实际ServiceController.register/unregister，最新免费签名Release及精确三目标/嵌套seal通过；真实open启动registered status1→独立helper响应验证→unregistered status0，stderr空。证据 `.build/service-controller-build.log`、`.build/service-controller-probe.{stdout,stderr}`；背景契约已同步。无业务配置，尚不证明完整启用handoff、SMB/恢复及篡改定义拒绝的运行验收。

2026-10-11 launchd独立helper启动实证：受限注册探针在组根写随机UUID票据；仅无配置/后台状态时helper启动读取票据、写精确响应并退出，不获取业务执行租约、不评估或挂载。GUI等待最多8秒验证响应再async unregister。首次响应成功后发现exit跳过Swift defer清理，已修为作用域退出后exit；shell无法读取组目录（系统EPERM），由同组签名应用在核对确切UUID及响应后清理旧票据，未改绕系统访问。修正后免费签名Release/三目标/嵌套seal通过，三个独立open启动连续均精确返回registered status=1、independent-helper-response-verified、unregistered status=0且stderr空；后续探针能以withoutOverwriting创建证明上一轮票据清理完成。证据 `.build/launchd-helper-cleanup-build.log`、`.build/launchd-helper-pass-{1,2,3}.{stdout,stderr}`。这是launchd独立sandbox helper启动与同组读写/登记撤销证明，不能替代真实SMB、GUI退出/登录/网络恢复三轮验收；T016/T061仍不勾。

2026-10-11 SMAppService注册/清理实证：系统正常open启动仍notFound，统一日志显示BTMErrorDomain -95 record not found，且已解析正确App URL、固定label及helper路径。新增受限 `--probe-background-registration`：仅在内部automnt.plist/backend-state/transition-journal均不存在、两固定服务未注册或notFound且签名预检通过时执行；不生成业务配置。最新免费Apple Development Release/三目标精确签名/嵌套seal通过，经正常open启动真实register成功，SDK status=1(enabled)，随后async unregister成功status=0(notRegistered)，stderr为空。证据 `.build/registration-probe-build.log`、`.build/registration-probe.stdout`、`.build/registration-probe.stderr`、`.build/service-discovery-system.log`。notFound此样本由登记记录不存在导致，不可推为随包定义缺失或免费团队不能注册；普通启用对另一服务notFound的保守门槛须进一步修订/验证。此探针没有活动配置，不证明helper执行、SMB挂载、退出后/登录后恢复或T016整体通过；无残留启用登记。

2026-10-11 服务发现复验：诊断保留SDK具体状态，当前目标SDK SMAppService.h第27–28行定义notFound为错误且找不到服务，不能等同notRegistered。最新真实免费签名Release及精确三目标/嵌套seal通过；注册LaunchServices后，构建位置及新安装的用户Applications/Automnt Development.app均返回两服务notFound，exit0。单纯移入用户Applications未解决服务发现；未注册后台、未生成业务配置。证据 `.build/service-sdk-status-build.log`、`.build/service-sdk-status-runtime.json`。T013已按维护者纠正改为直接添加及内部存储，不保留目录选择前置；后台注册和真实独立运行仍待验证，任务不勾选。

2026-10-11 系统服务只读诊断：新增精确 `--check-background-service-status` 路由，在MainActor查询两个固定SMAppService.agent，不注册/注销/评估或写业务配置。正式免费签名Release及精确三目标/嵌套seal通过，运行exit0，baseline/recovery均映射为unavailable（SDK notFound或未知状态），runtime-unverified；随包Contents/Library/LaunchAgents中两个定义存在，须继续核查安装位置/系统发现与注册，不能把状态查询成功视为后台可用。日志 `.build/service-status-build.log`、`.build/service-status-runtime.json`。同时移除旧GUI绑定诊断路线，并同步实际离线支持中英正文与存储模型的内部配置说明；未创建/迁移活动配置。

2026-10-11 helper预检修订：删除GUI→独立sandbox helper的Process预检，仅校验Apple锚/固定身份/同团队签名，新增helper sandbox=true、共享组精确为签名团队.org.automnt.shared且无inherit的检查；GUI独立解析内部容器，ensure还核对传入目录为程序内部目录。真实免费签名Release、精确三目标/嵌套seal及Platform回归exit0。原GUI诊断命令重跑exit0，明确输出 `helper-preflight: signature-and-group-verified; runtime-unverified`，不再启动helper或产生该路径SIGTRAP。证据 `.build/helper-local-preflight-build.log`、`.build/helper-local-preflight-tests.log`、`.build/helper-local-preflight-runtime.json`。这只证明本地预检通过，SMAppService/launchd启动、GUI退出后的实际恢复仍未验收；未注册服务或改变活动业务配置。

2026-10-11 首次添加服务器接入：首次页及工具栏可直接开启既有HostEditor；保存时由saveFirstHost→repository.create验证完整用户输入并以不覆盖竞争创建方式写唯一内部配置，默认自动挂载关闭，取消仅丢弃内存draft。删除普通Folder access、旧authorize入口及创建空配置动作；外部CLI接管尚未实现，不能宣称共存完成。最终Apple Development Release/三目标精确签名/嵌套封印通过，日志 `.build/first-server-final-build.log`；九语首次说明已编译入产物，diff检查通过。未以Agent伪造业务配置测试，真实窗口添加/取消/保存失败留draft及键盘退出仍待验收。后台直接启动预检问题仍未解决。

2026-10-11 GUI直接启动helper诊断：增加仅显式诊断模式输出阶段与子进程退出状态；重建后GUI诊断为child-exit/reason2/status5，签名预检已通过。实际崩溃报告显示helper在main前libsecinit `_libsecinit_appsandbox` / `SYSCALL_SET_USERLAND_PROFILE`触发SIGTRAP，而非PermissionStore目录访问失败；不能以此判定共享存储不可访问。证据 `.build/helper-stage-build.log`、`.build/helper-stage-runtime.json`及本机DiagnosticReports的2026-10-11 17:03:29 helper报告。当前直接启动独立沙盒helper预检路线不成立；需按SMAppService/launchd的真实独立启动路径核查并修订预检，不绕过签名检查、不把缺少真实后台验收视作成功。未注册服务、未修改活动配置。

2026-10-11 内部目录接入：PermissionStore.internalDirectory()在App Group内由程序准备0700目录，不生成业务配置；GUI restore及helper普通/check入口使用该目录，helper ensure取消普通启动书签传输。首次页面已移除选择内部目录动作（仍待将创建配置合并至首次添加服务器及CLI明确接管）。Release/精确签名检查和Platform回归exit0；真实独立helper目录检查exit0，但GUI→helper检查exit1/authorizationRequired，不能宣称后台路径验收通过。证据 `.build/internal-store-build.log`、`.build/internal-store-tests.log`、`.build/internal-store-runtime.json`。后续增加的九语首次说明源码尚未重建入该产物；未创建业务配置、注册服务或改变现有CLI owner。

2026-10-11 双向真实读写验证：正式Apple Development Xcode Release，GUI写→独立helper读/清理、helper写→新GUI进程读/清理，六步均exit0。精确声明权限/共同团队/Apple锚/嵌套封印全通过。探针仅使用运行期UUID命名与载荷，禁止覆盖既有文件，清理前校验父容器及完整载荷；未生成业务配置。初次探针因Foundation不支持atomic+withoutOverwriting组合而断言，在接触文件前失败；改用withoutOverwriting后通过。日志 `.build/shared-container-write-final-build.log`、`.build/shared-container-write-runtime.json`。此证据确认本机免费身份的正式GUI/helper可跨独立进程读写共享容器；不等于launchd登录/GUI退出后后台恢复、任意签名CLI访问或商店分发验收。旧书签首次流程暂停；正常内部存储接入及唯一配置接管仍待实现。

2026-10-11 正式bundle的App Group检查：GUI/helper声明 `$(DEVELOPMENT_TEAM).org.automnt.shared`，Xcode展开签名团队；验签脚本仅以已验证team替换声明占位。新增只读 `--check-shared-container`，从自身签名team定位容器，不写配置/不注册服务。Apple Development Release与精确权限/嵌套封印通过；GUI/helper均exit0，容器目录存在，但isWritable元数据为false。先前exit1定位为错误地把元数据当成实际写权限验证；修订后只报告located。尚未进行实际文件创建/独立进程交叉读取，因此不能宣称共享读写成功。Platform75测试/20suites通过（2.458s）；日志 `.build/shared-container-metadata-build.log`、`.build/shared-container-xcode-runtime.json`、`.build/shared-container-platform-tests.log`。CLI/root二进制本轮未变更，业务存储仍待接入。

2026-10-11 存储路线修订：维护者否定首次选择内部配置目录；正常GUI启动应自行管理内部配置。旧目录书签技术记录不是产品验收。独立App Group探针使用免费Apple Development及 `TEAMID1234.org.automnt.shared`、两个不同签名identifier和嵌入Info.plist；未写业务配置。codesign静态strict通过，首次进程SIGTRAP（OSStatus100001，libsecinit），加入团队/应用身份元数据后SIGKILL；系统日志为 taskgated-helper `no eligible provisioning profiles found`、amfid -413 `No matching profile found`。当前探针未进入main，未证明容器可访问；也不能把手工codesign探针profile缺失外推为免费账号不支持。下一步核查Xcode profile和实际bundle路径。证据 `.build/app-group-probe-results.json`、`.build/app-group-probe-system.log`。完整GUI实现继续，不能回退要求普通用户选内部目录。

已使用本机免费 Apple Development 身份（团队 `TEAMID1234`）完成真实 Release 构建，App、Helper、Worker 的 Apple 信任链、共同团队、签名 identifier、精确沙盒权限及嵌套封印检查全部通过。**T006 尚未完成**：独立 helper 的持久目录授权与真实跨进程权限仍未验证。以下早期记录中的“尚未签名”“未替换”等结论只描述当轮历史，不代表最新状态；最新证据见末尾增量记录。

早期权限探测轮次未选择证书；后续已实际使用本机免费 Apple Development 证书，如下方增量记录。尚未完成服务注册、真实产品挂载或活动业务配置修改，未发布。校验脚本只检查代码，不启动待校验程序。

# GUI 沙盒内 helper 授权检查（2026-10-11）

新增签名 GUI 的无窗口只读 `--check-helper-authorization` 路由，调用与实际开启后台相同的签名核验及 5 秒 helper 子进程检查。不索取授权、不注册服务、不进入评估、不修改业务配置。Release 构建、签名/元数据校验及九语言覆盖检查通过；实际运行 exit 1，错误域 `AutomntCore.AutomntIssue`、code 8，最终诊断明确为 timeout。此证据只证明失败有界返回，不证明 GUI 能成功启动/读取独立 helper 权限；直接 shell 下 helper exit 1 的结果不能替代此路径。GUI 仅对 authorizationRequired 展示目录权限说明，其余错误按真实类别报告。日志 `.build/gui-helper-probe-classification-build.log`、`.build/gui-helper-authorization-runtime.log`。

授权路径研究：已读取 Apple 官方 [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) 的完整文档 JSON。官方支持以 options=[] 创建临时书签并传给 launch agent/XPC 接收进程，显式 security-scoped bookmark 用于进程退出后的持久访问。拟由 helper 在接收临时访问后自行建立私有持久书签；该流程尚未实现/验证，不把 GUI 持久书签视为跨身份授权令牌。当前缺口与免费/付费账号无确定因果。

# helper 子进程启动阶段定位（2026-10-11）

对签名 GUI 的只读诊断做单变量主循环实验：由 dispatchMain 改为 RunLoop.main.run，仍 exit 1 / timeout，不能将超时归因于主循环。随后捕获 GUI 的真实 helper 子进程（pid 71408，父进程为 Automnt 71406）的 1 秒 sample，全部 776 个样本停在 dyld 初始化 → libSystem_initializer → _libsecinit_appsandbox → _xpc_pipe_routine → mach_msg2_trap；尚未到 HelperEntry。此证据将本次失败定位在系统沙盒启动等待，未确定具体请求/权限原因；不得声称 PermissionStore.resolve 卡住。日志 `.build/gui-helper-child.sample.txt`、`.build/gui-helper-runloop-runtime.log`。直接 shell 与 GUI 子进程启动方式结果不同，后续应验证 SMAppService/系统独立启动及临时授权通信，不改 helper 为继承 GUI 沙盒来掩盖问题。

# 临时书签接收实现与验证边界（2026-10-11）

新增 PermissionBinding：GUI 侧只从现有 AuthorizedDirectory 创建 options=[] 临时书签；4 字节大端长度帧，最多 65536 字节；接收侧 poll/read 共用 5 秒截止时间，拒绝空/截断/超长/非法书签、stale 和错误目录，再由 helper 身份生成自身持久书签。新增 `--bind-directory-authorization` 精确入口，仅写私有授权，不注册/评估/修改业务配置。GUI 发送与系统独立启动尚未接入，不能宣称授权闭环。

Apple Development Release、app/helper/worker 签名及嵌套封印通过；Platform 72 项/19 suites 回归通过。真实签名 helper 的空输入测试外部 8 秒截止时间超时（`.build/permission-binding-build.log`、`.build/permission-binding-tests.log`）；程序的接收器尚未被实机证实执行，因此非法输入/5 秒截止时间的真实验收未通过，不以回归替代。继续比较只读检查与绑定入口启动，系统初始化等待尚未收敛。未传入真实目录书签，未创建业务配置或修改现有授权。

# 授权帧边界回归及系统日志（2026-10-11）

未发现残留 AutomntHelper 进程。secinitd 最近8分钟日志能看到 GUI AppSandbox request successful，以及 helper pid 对应的初始化 peer connection，但尚无可支持具体根因的结果；不能由 persona 警告直接推断失败。日志 `.build/helper-secinit-system.log` 仅本地，不进入支持导出。

抽出可注入文件描述符的同一 receiveFrame 读取路径，使用真实匿名管道进行3项回归：空/短头/零长度/超长/截断帧均 authorizationRequired；保持写端打开且无数据，在100ms截止时 timeout（实际110ms，测试上限1秒）；完整载荷及EOF正确读取。`.build/permission-binding-frame-tests.log` 3/3通过。此测试不传目录书签、不修改私有授权或业务配置；仅证明帧接收边界，签名helper启动/实际授权仍未通过。

# 系统同意提示根因与允许后复验（2026-10-11）

15:47:28 对 secinitd pid658 做只读1秒采样（`.build/secinitd-wait.sample.txt`）：名为 org.automnt.automnthelper 的队列773样本停在 AppSandboxRequest.executeRequestWithError → appsandboxContainerSync → displaySharingConsentPrompt → CFUserNotificationReceiveResponse。这将本次等待定位到系统 sharing consent 用户响应，而非目录解析。未代点/绕过提示；维护者随后明确回复“已允许”。提示完整文字/用途范围未采集，不将其视为配置目录或网络卷授权。

允许后实际签名GUI `--check-helper-authorization` 立即 exit1 / authorizationRequired（code1），此前timeout消失。直接helper只读59ms返回授权不可用；绑定空/超长/截断11–13ms拒绝，非法bookmark11ms拒绝；保持stdin打开不发数据，5.031s返回timeout并exit1。`.build/gui-helper-after-consent.log`、`.build/permission-binding-after-consent.json`。这些结果证明真实入口和输入边界执行，尚无真实目录书签或成功持久授权，不证明launchd/挂载/恢复。后续需接入GUI发送临时书签并独立复读，保持系统提示由用户处理。

# GUI 授权发送接入及首次实机验证（2026-10-11）

启用/修复后台前改用 HelperAuthorizationCheck.ensure：优先独立只读检查；仅 authorizationRequired 时发送当前 AuthorizedDirectory 生成的临时书签帧，绑定成功后启动新helper无输入复读自身持久书签，成功才进入原后台接管。签名验证、空环境、无日志载荷不变；输入写端非阻塞/F_SETNOSIGPIPE，总写入及退出等待5秒，取消传递至detached任务，异常/取消强杀子进程并关闭pipe。没有服务注册副作用。

新增精确 `--bind-helper-authorization` 无窗口诊断入口，仅从GUI已有私有PermissionStore读取，不选择/创建目录或伪造配置；失败只报告阶段/枚举/domain/code。Platform 75项/20 suites通过；最终真实签名Release与全封印通过。真实执行 exit1、stage=app-directory、authorizationRequired（`.build/helper-binding-gui-runtime.json`），说明当前GUI身份尚无可复读目录授权，未执行真实书签传递。需在最新GUI原生文件选择器中由维护者授予配置目录后继续；不能用路径字符串/手写偏好代替授权。GUI→helper成功持久授权、launchd、挂载恢复仍未通过。

# 修正上一轮沙盒探测结论

上一轮只对不存在主机调用 NetFS，并在 25 秒后超时。该结果**不能证明沙盒允许真实 SMB 挂载**，也不能证明函数已进入网络连接阶段；未获得有效挂载、服务器返回值或可靠 sandboxd 证据。撤回 task-25 描述中的“核心自动挂载能力在沙盒内可达”结论。

此前 SIGTRAP 堆栈定位到 `_libsecinit_appsandbox`，但未通过控制变量实验排除 bundle 身份、签名、授权、启动方式等原因。撤回“由重新签名顺序导致”的确定性归因；原因待确认。

此前目录枚举错误的数值 257 属 Foundation 文件读取错误报告，不能直接当作 POSIX EPERM；准确错误域和底层原因未完整留档。普通 BSD socket 创建成功也不能证明被允许向服务器建立网络连接。容器 HOME 观察只适用于当时的探针，不能外推 app/helper/worker 的全部运行方式。

此前未沙盒化的对照探针在活动配置目录创建了一个零字节探针文件，随后已删除。该实验不应重做。后续验证只使用隔离目录与明确授权的真实资源，不写活动配置目录。

# 权限矩阵

这些声明已通过真实开发签名的嵌入值核查；运行授权与权限连续性仍待复验，声明本身不代表能力可用。

| 目标 | 权限 | 代码依据与边界 |
| --- | --- | --- |
| App | `com.apple.security.app-sandbox` | 拟采用 Mac App Store 沙盒；权限收紧不能当作产品核心能力已通过。 |
| App | `com.apple.security.network.client` | 前台触发 `BackgroundEvaluationTrigger`/`TCPReachabilityProbe` 与服务器通信；不申请监听端口权限。 |
| App | `com.apple.security.files.user-selected.read-write` | 原生文件选择器选取真实配置目录；`PermissionStore.authorize` 验证与保存书签，配置修改需要写权限。不是任意文件系统访问许可。 |
| App | `com.apple.security.files.bookmarks.app-scope` | `PermissionStore.authorize/resolve` 使用应用范围安全作用域书签，以无 UI、无自动挂载选项在后台解析。 |
| 独立 helper | `com.apple.security.app-sandbox` | SMAppService LaunchAgent 独立启动，不继承 GUI 的沙盒上下文。 |
| 独立 helper | `com.apple.security.network.client` | `HelperEntry` 调用后台评估、TCP 探活与凭据准备。 |
| 独立 helper | `com.apple.security.files.bookmarks.app-scope` | 当前 `HelperEntry` 通过其自身 `PermissionStore.resolve()` 读取自身持久书签。**此权限不会提供或转移书签；当前未实现 helper 的独立授权流程。** |
| 子 worker | `com.apple.security.app-sandbox`、`com.apple.security.inherit` | `MountWorkerRunner` 使用受控 `Process` 启动包内 worker，由其继承父进程沙盒。继承式子程序只声明这两项，不混入独立 network/files 权限。独立直接启动不能作为该路径验收。 |

未加入 App Group、Keychain access groups、临时沙盒例外、管理员权限或 Apple Events 权限。`KeychainCredentialProvider` 使用默认 Data Protection Keychain 查询，没有显式共享访问组；未假设 GUI/helper 凭据天然共享。worker 通过匿名管道获得必要内存凭据。网络卷 TCC、书签跨进程/跨身份有效性、真实 NetFS 与 DiskArbitration 能力均待验证，没有声明可绕过 TCC 的 entitlement。

特别注意：worker 当前同样调用自身 `PermissionStore.resolve()`。沙盒继承不能自动证明它可读取 App 或独立 helper 私有偏好的书签；这是 T013/T016/T015 尚待解决的运行授权缺口。

# 配置与签名关系

`Signing.xcconfig` 包含版本派生配置，并选择 Manual / Apple Development 签名策略。`DEVELOPMENT_TEAM` 与精确 `CODE_SIGN_IDENTITY` 由实际构建参数提供；仓库未硬编码个人团队或证书。三目标 Debug/Release 共六处配置分别绑定自己的 entitlement 文件。

示例构建参数：

```sh
xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt \
  -configuration Release -derivedDataPath .build/xcode-sign \
  DEVELOPMENT_TEAM=<team> CODE_SIGN_IDENTITY=<certificate-hash> build
```

App/helper/worker 的稳定签名标识各不相同，因此不要求三者具有字面相同的 designated requirement。检查脚本要求各自满足 `anchor apple generic`、自身固定 identifier 和共同开发团队的代码要求。这与 `BundledCodeVerifier` 对 App/worker 的运行检查一致。真实三目标签名与升级权限连续性未验证。

# 实际验证

| 检查 | 实际结果 |
| --- | --- |
| 工程及三份 entitlement plist | `plutil -lint` 全部 OK。 |
| 无签名 Release 构建 | `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` 退出 0。此检查不验证 entitlements 实际嵌入。 |
| 真实开发签名构建（未指定团队） | `xcodebuild ... build` 退出 65；App/Helper/Worker 分别报告需要指定开发团队或 provisioning profile。不是签名通过。 |
| 签名检查八项判定测试 | `python3 -m unittest discover -s scripts/tests -v`：8 tests，OK。使用模拟 codesign 结果，只验证判定逻辑。 |
| 真实 ad-hoc 负向验证 | 在忽略目录内，用系统 `true` 可执行文件副本建立有效封印的临时包；`codesign --verify --deep --strict` 通过，但 `verify-signature.sh` 退出 1，明确拒绝 ad-hoc。未启动该包内代码。 |
| 旧无签名构建负向验证 | 检查脚本退出 1，codesign 报资源封印无效；没有将旧产物报告为可信。 |

八项测试分别验证：正常三身份及共同团队规则、ad-hoc 拒绝、嵌入代码异团队拒绝、额外 network.server 权限拒绝、inherit 被更改拒绝、错误 identifier 拒绝、Apple-anchored 要求校验失败拒绝、缺嵌入代码拒绝。模拟成功不等于实际开发签名成功。

# 最终本地回归

2026-10-11 实际重跑：`swift test` 为 Core 108 tests/30 suites、Platform 70 tests/18 suites，全部 passed；`scripts/build.sh .build/automnt-signing-regression` 退出 0；该新产物 `--self-test` 为 295 passed、0 skipped、0 failed。`verify-localization.py --quiet` 与 `verify-swift6-concurrency.py --quiet` 均退出 0。工作区根目录旧发行二进制未替换。

签名脚本八项测试最初因测试临时目录的 `/var` 与 `/private/var` 路径别名不一致而失败；测试夹具改为解析后的绝对路径后，八项全部通过。该修正仅针对测试夹具，没有绕过校验器的身份或权限检查。

# 官方依据与尚未验证部分

已读取 Apple 官方归档 [Entitlement Key Reference：Enabling App Sandbox](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)。该页更新于 2017-03-27，解释 entitlement 配置、network.client、用户选择文件、应用范围书签与继承机制。它是归档依据，**不能作为 macOS 27 运行兼容性已通过的证据**。

当前 [App Sandbox 文档](https://developer.apple.com/documentation/security/app-sandbox) 页面为动态内容，本轮获取到的正文不足以核对全文；未声称已阅读当前全文。

未验证：Apple Development 真实三目标签名及嵌入权限、真实启动与容器行为、helper 独立书签授权、Keychain 跨身份授权、真实 SMB/NetFS/DiskArbitration/TCC、launchd 注册与退出、常规更新权限连续性、App Store 分发。上述为历史待验证状态。维护者已授权使用本机免费开发身份；证书 OU 核实团队为 `TEAMID1234`，以 `DEVELOPMENT_TEAM=TEAMID1234 CODE_SIGN_IDENTITY='Apple Development' CODE_SIGN_STYLE=Manual` 实际 Release 构建退出 0。Xcode 实际选择该团队的 qq.com Apple Development 证书；尚不能报告“只差付费账号”。

# helper 实际启动与元数据核查（2026-10-11）

新增只读 `--check-directory-authorization` 入口，真实签名 helper 首次执行退出 133；系统报告 `AutomntHelper-2026-10-11-152646.ips` 指出代码签名 Info.plist 缺少 CFBundleIdentifier，在 `_libsecinit_appsandbox` 终止，尚未到达业务代码。helper Debug/Release 配置启用 `CREATE_INFOPLIST_SECTION_IN_BINARY` 与 `GENERATE_INFOPLIST_FILE`，重新构建/签名验证通过。同一只读入口复验退出 1，明确输出 `directory-authorization: unavailable`（`.build/helper-directory-authorization-fixed.log`），本次直接启动的初始化崩溃不再出现；不能据此证明 launchd 启动、持久目录授权或 SMB 可用。

签名验证脚本现额外读取 Apple silicon Mach-O 的 `__TEXT,__info_plist`，解析并核对 helper 的 CFBundleIdentifier 与 CFBundleExecutable。当前真实签名包通过新检查、三目标权限/信任链及嵌套封印检查，本地化与 diff 检查退出 0。此检查仅核查元数据，不运行程序。GUI 与 helper 使用各自私有偏好存储，当前没有完成独立授权交接；不复制 GUI 书签或放宽沙盒来冒充已解决。T006 保持未完成，尚不能报告只差付费账号。

# 真实开发签名增量核查（2026-10-11）

真实校验发现两项此前模拟测试未暴露的问题：codesign 的文本 requirement 必须以 `=` 前缀传递，否则被解释成文件路径；tool target 的 bundle identifier 不自动成为代码签名 identifier，辅助程序实际被签为 `AutomntHelper` / `AutomntWorker`。已修正校验器参数，并为两个 tool target 明确指定签名 identifier。首次增量重建仍保留旧嵌入副本；clean build 退出 0 后，真实校验器对 App、Helper、Worker 分别通过 Apple 信任链、共同团队、签名 identifier 和精确沙盒权限校验，完整包的嵌套代码封印也通过。`open` 启动命令退出 0；窗口、容器及后台行为仍需实际观察，不能由启动命令返回值推定成功。

同轮 `scripts/build.sh .build/automnt-current` 退出 0，优化产物自测为 295 passed、0 skipped、0 failed。工作区根目录 `automnt` 已使用该产物替换；替换前副本保留于忽略目录 `.build/automnt-before-current`，没有更改已安装用户程序或现有业务配置。随后根目录 CLI 使用同一真实 Apple Development 证书签名，`codesign --verify --strict automnt` 退出 0，`--version` 为 3.4.0；对已替换且已签名的根目录可执行文件重跑 `--self-test` 为 295 passed、0 skipped、0 failed，日志为 `.build/root-cli-self-test.log`。

2026-10-11 单共享手动挂载与菜单精确详情导航增量：最终开发签名 Release 构建日志 `.build/detail-navigation-build.log`，退出 0；三个目标与嵌套封印检查全 PASS，本地化与 diff 检查退出 0。`open -n` 最终签名包退出 0，进程核查观察到新 PID 68287（旧实例 64749 同时存在），仅对新验证副本发送 TERM，避免留多个运行副本。未观察窗口、菜单点击、滚动、VoiceOver 或真实 SMB，故这些验收不由进程存在推定。手动挂载提交边界新增 1 项测试通过；CLI 再次优化构建、295/0/0 自测、开发签名及根目录替换完成，版本仍为 3.4.0。

# 当前运行验收边界

继续用已获授权的免费 Apple Development 身份开展真实签名 GUI/helper 运行验证，付费账号不是完整界面实施前置。验证采用的系统认证与沙盒/helper 能力、唯一共享配置所有权、真实自动挂载和三类恢复；新 HTML/原生 demo、unsigned build、typecheck 和历史逻辑测试均不能替代。本轮未执行新的签名、Keychain 或 SMB 探针。

# 2026-10-20 GUI 安装位置与旧测试副本清理

- 历史遗留 `~/Applications/Automnt Development.app` 是 2026-10-11 服务发现测试用的临时副本（见本文件前述记录），与正式 App 使用同一 bundle ID，但二进制、图标与资源均为旧构建；不是当前发布产物，已删除。
- 先前打包落在 `~/Applications` 是打包步骤的选择，不是产品要求；本轮统一安装到 `/Applications/Automnt.app`，并删除 `~/Applications/Automnt.app` 与 `Automnt Development.app`。
- 已刷新 LaunchServices，仅保留 `/Applications/Automnt.app`；实际运行路径与唯一副本均已核对。配置目录保持全新欢迎状态，未生成业务配置。
