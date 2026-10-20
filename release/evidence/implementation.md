2026-10-13 当前实施状态：方案 A 固定目录权限、访问状态界面和独立 helper 两阶段预检已本地接入。最终签名构建与 289 项测试通过，真实中文未授权窗口已核对；系统面板授权、真实 CLI 目标呈现和 helper 持久访问仍待验收。见 [方案 A 实施证据](option-a-authorization.md)。以下 2026-10-11 及更早记录保留当时范围。

> 2026-10-11 本轮历史范围说明（仅 Feature005）：本轮仅修改文档与 demo；独立密码 CRUD、8 步向导、多选、用户 CLI 导入/检查、内部配置目录选择已撤销，现行要求以 [spec](../../specs/005-swiftui-mas-gui/spec.md) 与 [contracts](../../specs/005-swiftui-mas-gui/contracts/gui-and-release.md) 为准。系统认证在 sandbox/helper 中的复用未验证；已有 CLI 配置自动呈现与共享配置 owner 尚未实现。Automnt 暂用。以下历史正文与测试结果保留，旧资源、截图与测试不证明新版通过；CLI Feature001–004 的证据语义不变。

# 共享配置与 CLI 拆分

2026-10-08 本地实施进行中。根入口保留唯一营销版本声明，新增兼容配置项 automation_enabled，因此版本由 3.3.2 晋级 3.4.0。原工作区发行二进制仍保留基线，当前开发产物位于忽略目录 .build，不安装、不发布。

配置模型、旧 profiles 桥接与未知字段合并迁入 AutomntCore，CLI 导入相同模型。现有 CLI 命令及恢复逻辑迁至 AutomntCLI；恢复评估仍待继续提取到共用核心，不能宣称 T009/T012 全部完成。

新增配置仓库使用 SHA256 内容 revision、保存冲突检测、0600 原子替换和稳定 config.lock。入口必须传入已经授权的真实共享目录，无私有容器回退。新增模型校验覆盖端口、嵌入凭据、同主机身份/路径重复；尚待接入全部实际保存入口及真实配置验证。automation_enabled 缺省启用，与 auto_mount_recovery 独立编码并纳入合并管理键；CLI 自动评估关闭时退出并保留已有挂载。

# 实际验证

| 验证 | 结果 |
| --- | --- |
| 拆分后 scripts/build.sh 优化构建 | 成功；arm64/macOS27.0；--version 为3.4.0 |
| 拆分后开发产物 --self-test | 最新286 passed，0 skipped，0 failed；含通知隐私、路径迁移及端口身份回归 |
| Swift Package 构建 | 成功；Core Swift6模式，既有 CLI 暂按Swift5语言兼容模式编译 |
| Swift Testing | 最新95项通过：Core 60项、Platform 35项；包含锁/CAS/中断修复、异步顺位、本机TCP与取消、标记不覆盖、过期NetFS不调用系统、管道边界/凭据隔离/无结果响应拒绝 |
| 原生 GUI Release 无签名构建 | 最新成功，含Platform适配及嵌入helper/worker；未作真实窗口验收 |
| 签名、真实 SMB、后台生命周期 | 未验证 |

构建源成员从 Package target 定义派生，临时 main.swift 从根入口派生，成功和失败都清理临时构建目录。版本生成及 --check 均通过。共享有限重试已接入CLI，改用单调时钟并保留夹限。新增稳定evaluation.lock与取得操作锁后重核配置revision/后台generation的接口；后台状态与转换日志已实现0600原子持久化，转换与评估使用同一操作锁，日志/状态不一致时拒绝执行；真实服务状态需由平台适配核对，实际入口接入和中断修复仍待实施。共享仓库已拒绝未知字段中的常见凭据键/嵌入式SMB凭据，并将模型校验接入创建/保存；CLI旧保存入口仍待统一。失败通知改为计数及修复指引，不包含共享名/地址/挂载路径。最后一轮优化构建、268项内置自测和5项Swift Testing均通过。

Xcode app/helper/worker 三目标已建立并引用本地 AutomntCore；Debug 全目标与 Release app 及嵌入 helper/worker 的无签名构建实际通过。App 已接入原生 NavigationSplitView/List/Form、目录选择器、已有共享配置读取/空配置创建、重读及持久通知声音设置，仍缺目标编辑/首次连接/自动化服务/完整九语界面。helper/worker 尚无实际操作，不能宣称完整产品界面或后台挂载完成。既有 CLI Swift6 检查仍发现共享可变状态与隔离问题，T004 全部Swift6要求及签名/运行证据未满足；T004/T005/T007/T008/T009/T010/T012继续保持未勾选。

# 恢复与平台基础增量

恢复状态模型、损坏/缺失区分、状态文件读写和保守信号判断迁入 AutomntCore，CLI 使用相同实现。读取采用当前用户拥有的常规文件描述符，拒绝符号链接，并限制最大16MiB，防止异常文件无限增长。旧恢复轮次编排仍待完整提取。CLI 迁移保留自定义挂载目录，只规范 /Volumes 下历史数字冲突后缀；SMB身份加入非默认端口并规范IPv6 authority。后续需要真实自定义路径和旧状态连续性验证。

新增 AutomntPlatform 及安全作用域目录书签适配；后台解析使用 withoutUI/withoutMounting，缺失或陈旧授权返回需要修复，不提供私有配置回退。此适配的编译已通过，但独立 helper 持久权限、跨登录生命周期和实际共享目录限制仍待接入与实证，T013/T016 未完成。

共享通知声音偏好新增独立0600原子文件与稳定锁；缺失默认开启，损坏/未知schema静音并报告修复，保存抛错时调用者不得确认切换。新增回归测试覆盖这些区别和容量限制，6项Swift Testing通过；随后新增异步优先级/过期预算/自动化关闭回归，最终计数见下方。实际通知、设置界面、退出GUI后投递及听验仍未执行。平台契约新增结构化卷状态、挂载/后处理结果、可达性/挂载/通知适配接口；仅接口不能代替真实平台能力验证。

# 当前构建与剩余边界

最新优化CLI自测272项通过（0 skipped/0 failed），Swift Testing共22项通过（Core 10、Platform 12）。新增验证覆盖自定义目录迁移、历史冲突后缀、默认/非默认SMB端口身份、异步第一可达主机排他选择、过期预算不探测、全局关闭不探测，以及仅在已核实停止时修复中断转换。异步核心采用单调时间和可取消睡眠；具体探测/挂载适配必须遵守传入预算，不可把接口期限当作强制终止证明。

第二轮增量实现Network框架TCP探测：连接/等待/失败均有结构化结果，超时与任务取消取消底层连接，续体仅恢复一次。平台回归只探测动态端口的本机listener，没有探测业务服务器或扰动网络。SMAppService适配现在显式选择固定automnt.baseline.plist/automnt.recovery.plist；尚未创建资源或注册。配置读取补入模型校验。

SMB身份算法迁入Core，CLI不再保留副本。隔离worker专用NetFS原语指定NoUI，保留自定义目录意图，严格核对系统返回路径与内核smbfs身份；仅返回evaluating，不将挂载成功冒充文件健康。防索引标记适配不覆盖现有文件、拒绝符号链接，不调用外部mdutil；网络文件系统调用可能阻塞，必须接入可终止worker后才能证明有界，当前未供GUI/helper执行。最新Package测试、优化CLI自测、原生Release构建通过；没有进行实际NetFS挂载或证明TCC零提示。

第三轮新增worker匿名管道协议：128KiB总帧上限、64KiB非秘密元数据、用户名/密码各16KiB独立内存字节段，明确禁止落盘或argv/env传递。worker仅接受pipe描述符，解析后核验自身持久目录授权、最新revision/配置目标、app owner/generation，再持有evaluation.lock执行NetFS及后处理；无自身授权即拒绝，不复用GUI活书签。父runner仅从指定app bundle中的固定worker路径启动，以非阻塞管道和单调时间限制读写；超时/异常终止自己启动的child并返回requiresReconciliation，未接入重试。系统可能延迟进程退出/挂载收敛，SIGKILL不能证明立即退出；尚需实际退出和内核收敛核验、稳定签名身份/权限验证，不能认定T015通过。

最新13项Package测试和原生Release构建通过；实际嵌入worker空请求/超大长度/截断输入3项均在3秒内返回invalidConfiguration，stderr为空，未触发挂载。helper尚未接runner；未创建活动业务配置，未调用SM服务注册或实际SMB挂载。

第四轮补入Apple Security静态签名核验：固定app/worker标识、Apple锚及与调用方相同Team ID，无硬编码维护者签名团队；正式runner拒绝unsigned/ad-hoc，未选择或使用任何签名身份。增加worker-operation.plist持久启动意图，启动前在evaluation.lock下记录，worker在锁内核对operationID/revision/generation。崩溃/超时/错误保留pending并阻止后续runner启动，只有已退出且成功匹配响应才完成记录；异常后的实际退出/内核修复路径仍待实现，不能把保守阻止误认成自动恢复完成。新增跨store实例中断、错generation/operationID拒绝、unsigned拒绝回归，最新15项Package测试、272项优化CLI自测及最终原生Release构建通过。构建中曾因同时编辑协议导致短暂初始化错误，最终完整重建已消除；不作为最终失败证据。helper仍未接线。

第五轮新增原生SwiftUI服务器编辑sheet，支持用户输入地址/名称/端口、启停服务器和共享、防索引、添加/移除共享及自定义挂载目录；空挂载目录通过Core标准推导，输入嵌入凭据/同主机重复共享或目录/主机端口不匹配由共享校验拒绝。新增服务器、编辑及列表上下移动均用打开时snapshot revision进行CAS保存，不修改未知字段；冲突保留sheet输入且不给出已保存反馈。没有启用后台自动化或索取凭据。最终原生Release构建和15项Package回归通过；未实际操作窗口/VoiceOver/九语，删除服务器、凭据录入和完整首次引导待实现，T013/T028仍未完成。

第六轮新增CredentialView原生sheet和每共享入口：显式录入、保存、独立确认删除，SecureField输入不回读现有密码，保存或关闭清空内存视图状态；成功提示仅证明Keychain保存，不宣称服务器接受。删除共享仍不删除凭据。Keychain读/写统一采用worker内存上限校验，拒绝空用户名/密码、NUL、无效UTF8及超限，读取先限payload大小；新增无Keychain副作用边界回归。最终16项Package测试及原生Release构建通过。未实际写入/删除本机Keychain、未调用挂载、未证明签名身份下GUI/helper共用或跨CLI权限；前台验证连接仍待实现，T014未勾选，九语/键盘/VoiceOver未验证。

第七轮新增DiskArbitrationWorkerOperation普通卸载原语，仅供受父进程监督的隔离worker在操作锁/最新配置下使用：请求前核对确切内核SMB身份，使用默认非force选项，busy/permission失败结构化返回；回调成功后重新检查挂载表确切路径已不存在才返回stopped，不提交会话抑制。使用有限信号量等待；超时不宣称系统取消，迟到回调保持session生命周期，仍要求parent终止/实际退出/内核核对。回归覆盖过期、根目录、随机不存在非SMB路径、预取消，不对本机卷发出卸载；最新18项Package测试与原生Release构建通过。未接worker管道/GUI弹出入口、未验证真实SMB繁忙或沙盒权限、未实现死卷清理，T019继续未完成。

第八轮将普通卸载接入同一隔离worker/runner：请求增加必填operation=mount/unmount，unmount凭据字段必须空、mount必须非空，旧缺operation帧拒绝，不进行持久配置格式变更。worker核对真实当前配置、owner/generation/operationID，unmount允许全局自动挂载或目标enabled关闭但不绕过所有权，沿用签名/管道/期限/持久pending机制；卸载不读取Keychain、不执行防索引。runner分别核对挂载evaluating+确切路径和卸载stopped+无路径+无后处理，身份错配或操作响应混用拒绝。新增无秘密卸载帧与响应错配回归，最新20项Package测试及最终原生Release构建通过。尚未提交会话抑制/开放GUI弹出入口，helper仍未形成实际评估，真实繁忙卷/权限/超时内核收敛未验证，T018/T019仍未完成。

第九轮HelperEntry由无操作入口改为一次30秒预算评估：自身PermissionStore授权、固定bundle位置、系统SMAppService所选模式enabled且另一模式stopped后进入BackgroundEvaluator。评估先在evaluation.lock下核对snapshot/app owner/generation，释放锁再探测/启动worker，顺位只选择第一可达host，读取非交互Keychain并调用已有签名runner，失败不切换备用；自动挂载关闭无新动作。结果以0600 background-observations.plist保存，未授权无容器回退/载荷日志。已有匹配卷仅evaluating，不冒充健康；共享恢复状态损坏、曾健康/修复信号及显式suppressed均保守跳过，本轮仅neverMounted路径接线，尚未实现健康读写、会话边界和完整recovery。20项Package测试与最终原生Release编译通过；未运行/注册helper、固定agent资源仍缺、自身持久授权仍未证明，不能宣称退出GUI后自动恢复，T016/T017/T018保持未完成。

第十轮提取Core BaselineMountDecision并接入helper及持锁worker：区分确切SMB身份、非SMB占用、挂载表不可读和路径无挂载，不再把identity=nil误当可挂载；worker取得evaluation.lock后重读共享恢复状态与挂载表，保守拒绝探测期间新增抑制或路径占用。缺失状态只允许neverMounted，显式suppressed、曾健康、修复标记、清理账与损坏状态均不进入baseline挂载；匹配已有卷只inspectExisting。新增两项核心回归覆盖上述边界，修正后台摘要schema解码编译警告。最新22项Package测试及最终原生Release构建通过，无实际卷操作。该保守baseline不替代完整会话恢复，健康/会话/权限/固定触发门槛仍未完成，T009/T018保持未勾选。

第十一轮PrivateAtomicFile读取在现有current-uid/regular/no-follow基础上拒绝group/other权限及特殊权限位；使用O_NONBLOCK避免FIFO在fstat前阻塞。新增两项回归验证正常0600读、0644/0660/特殊位拒绝、符号链接/FIFO/大小限制拒绝，以及产品ConfigRepository生成的配置宽权限时读取与CAS保存均拒绝、恢复0600后revision不变。最新24项Package测试与原生Release构建通过，未自动修改已有用户文件权限。该检查尚不包含ACL审计，真实目录授权与跨进程验收仍待完成。

第十二轮FileConfigRepository复用StableFileLock默认LOCK_NB，配置锁竞争立即返回configurationConflict，不再无限等待拖垮helper的操作预算；read/create/save共用路径，锁文件保持原inode。StableFileLock把类型/owner验证失败明确映射EACCES，避免使用陈旧errno。新增回归实际持有同文件的另一描述符，验证三种仓库操作均拒绝、冲突后revision不变、释放后保存正常、锁inode和0600权限稳定。最新25项Package测试与原生Release构建通过；尚未证明不同渠道全部CLI入口共享该锁，T008/T010/T012仍保持未完成。

第十三轮CLI saveConfig的未知字段合并与写入置于共享config.lock描述符生命周期内，采用PrivateAtomicFile的0600原子替换并在写入前ConfigurationPrivacy校验。优化CLI首轮自测暴露旧schema样本默认0644被新读取规则拒绝，样本改用产品PrivateAtomicFile写入后重新优化编译及272项内置自测全部通过，25项Package测试通过。此轮仅统一保存临界区，CLI draft revision/CAS、全部读取权限与owner接线尚待完成，不宣称跨入口并发编辑无丢失，T008/T012/T022仍未完成；发行根二进制未替换，无服务安装/挂载/推送。

第十四轮encodeConfigPreservingUnknownFields只在ENOENT时返回新生成内容，原文件改用PrivateAtomicFile读取，损坏plist/非字典/权限异常/隐私违规均抛错，不再默默丢未知字段。新增回归验证权限及损坏拒绝后原字节不变、缺失目标编码不自行落盘；优化自测暴露旧迁移XML样本默认宽权限，样本改用产品0600写入后272项CLI自测全部通过，26项Package测试通过。实际宽权限旧配置当前拒绝自动覆盖，未自动改用户权限，后续修复入口及CLI draft CAS仍待完成，不能宣称T008/T012完整通过。

第十五轮集中接通CLI配置链：安全读取/检查共用config.lock与PrivateAtomicFile，读取记录同GUI仓库的SHA256 ConfigRevision；saveConfig持锁核对原字节摘要，既有未读文件不覆盖，成功才更新摘要。管理菜单单独捕获打开时revision，即使中间重读也不会升级旧draft；迁移及后台更新保存受revision保护，迁移落盘失败不继续返回内存配置；初始化开始捕获原内容并清除旧缓存，重建按精确摘要且不保留旧业务字段，缺失起点requireAbsent防止向导期间别人创建配置。冲突文案解释重新读取和输入保留；宽权限文件不自动修权限。新增12项CLI自测经产品创建、共享仓库并发修改、旧CLI保存拒绝、reload成功、锁竞争、权限拒绝/字节不变、迁移冲突及开关/更新渠道保留。最终优化构建284项CLI自测、26项Package测试、app/helper/worker无签名Release构建全部通过。此轮未实际安装/接管/挂载；CLI Swift6、所有权/统一操作锁、完整健康恢复仍未接通，T004/T008/T012/T022/T025未按完整条件勾选。

第十六轮按T007/T008完整本地通过条件集中核验：补CLI落盘前ConfigurationValidation，与GUI仓库共用同校验；新增3项Package契约回归覆盖profiles兼容/未知根及目标字段/密码拒绝/重试与自定义目录/双开关往返/同主机冲突和跨主机备用路径，以及无效draft不改仓库；新增2项CLI回归确认无效端口拒绝且原字节保持。最终29项Package测试、286项优化CLI自测、app/helper/worker无签名Release构建通过，T007/T008已勾选并记录证据；T009–T012增加实施子项保持父门槛不变。T004 Swift6、真实沙盒/独立持久权限及完整恢复仍未通过，本轮无系统服务或真实卷操作。

第十七轮共享RecoverySessionIdentity/RecoverySessionPolicy提取CLI网络不可读保留、首次采集建立基线、实际网络/登录边界重置预算但保留健康和清理账规则；CLI删除原重复边界循环。RecoveryHealthPolicy统一文件证据与结构化状态，未知不授权清理，损坏状态优先；helper未执行文件访问探测的已挂载结果明确signalUnavailable/evaluating。RecoverySuppressionPolicy提取同路径备用弹出保护，CLI/helper预检查/worker持锁复核调用共用判定；仅传播保护不传播健康或清理许可。新增4项Package回归，最终33项Package、286项优化CLI自测、原生app/helper/worker无签名Release构建通过，T009-b1闭合；helper尚未独立采集会话、推进状态或执行隔离文件健康探测，T009-b2及父T009保持未完成，无真实服务/SMB操作。

第十八轮helper独立RecoverySessionCollector使用getifaddrs/SystemConfiguration获取活动地址和默认网关，sysctl/utmpx获取启动与控制台登录纪元；登录记录缺失返回nil，默认网关缺失/无法读取保留原网络，未打印或存储采集原文。BackgroundEvaluator在EvaluationPermit持锁复核配置/app owner/generation后检查配置挂载路径，挂载表不可读拒绝推进；RecoverySessionCommit检查worker持久pending后读取状态，仅可读且边界变化时原子提交，nil身份不解除保护、损坏原字节不覆盖。新增2项Core回归覆盖竞争锁、pending拒绝、完成后推进、过期配置拒绝、nil身份和损坏字节保持，1项Platform本地API smoke；最终36项Package通过，产品源码优化CLI286项和app/helper/worker无签名Release构建通过。尚缺隔离健康worker、健康记录提交与完整恢复编排；未注册/运行helper，无真实SMB或权限生命周期实证，T009-b2/父T009继续未完成。

第十九轮新增无凭据health隔离worker操作，沿用固定签名验证、匿名管道、30秒总预算内的1秒文件探测上限与持久pending监督。worker在独立授权/配置/app owner/generation/operationID核验及evaluation.lock内检查确切SMB身份，opendir/readdir后再次核对期限/身份；成功、明确EIO/ENXIO/ENOTCONN/ESTALE/ETIMEDOUT、其他不明确访问分别返回healthy/failed/evaluating结构化观察，不做卸载、不读取Keychain。helper仅在父进程已见worker正常退出且响应身份/路径/状态组合核验后完成pending，再取得EvaluationPermit重读恢复状态并复核挂载身份，healthy才提交everHealthyMounted/attached和清理旧账，未知不改状态，新增抑制优先。新增3项测试覆盖凭据拒绝/响应错配、过期或非SMB不访问目录、权限/繁忙不授清理、健康提交/卷已消失/抑制优先/损坏原字节保留/pending拒绝；最终39项Package、286项优化CLI自测和原生无签名Release构建通过，T009-b2按接线/本地回归闭合。真实SMB/权限/签名及迟退出内核收敛未验证，完整恢复编排、失败卷清理和新挂载后即刻健康探测仍待实施；本轮无真实卷或服务操作。

第二十轮将MissingVolumeRecoveryPolicy接入helper及持锁worker，缺失卷具备productCleanup/repairEject/pendingRecovery证据且auto_mount_recovery开启才允许恢复；baseline从未挂载仍独立允许，健康弹出/显式抑制/损坏/同路径peer保护继续优先。真实网络/登录会话推进后的历史缺失卷进入已有pending证据通道，首次可读网络身份不解除抑制。RecoveryAttemptCommit在NetFS调用前持锁原子保存attemptCount，同会话按配置maxAttempts夹限1...10，失败/中断也消耗预算，上限拒绝且字节不变；仅健康确认/已有共享会话推进重置预算，不对baseline凭空产生历史。新挂载后立即再启动无凭据health child，与已有卷共用健康检查/持锁提交路径；挂载表确认仍不冒充文件健康。新增3项Core回归覆盖恢复开关/历史证据/损坏/抑制、first-readable/真实会话变化/占用路径，以及有限尝试/成功重置/拒绝字节保留/baseline不写。最终42项Package、286项优化CLI自测、原生无签名Release及git diff --check通过。存在既有字符串解码弃用及测试冗余try警告；无实际SMB/服务/Keychain操作。死卷清理、失败结果/通知限额接线、CLI统一操作锁、pending修复和真实生命周期未完成，T009-c保持未勾选。

第二十一轮新增RecoveryCleanupCommit和独立cleanup管道操作。helper仅在已选可达主机已有卷health明确failed/shareRejected、恢复状态可读且自动化/恢复均开启时进入；worker自身持久授权、revision/owner/generation/pendingID复核及evaluation.lock内重读状态，明确未抑制后重新opendir/readdir检查，仍失败才调用默认非force DiskArbitration卸载。超时/未知/权限/繁忙不算成功。runner验证同身份stopped/无路径/无后处理并见正常退出才完成pending；helper重新EvaluationPermit核配置/owner并查路径确实absent才写产品清理账与pendingRecovery，保留既有健康历史、尝试/通知计数，再按原主机挂载并隔离健康确认，不转备用。新增2项Core及1项Platform回归覆盖未知/损坏/开关/抑制拒绝、仍挂载/占用/不可读表不写、成功账与预算保留、并发抑制/损坏原字节保护/pending拒绝，以及无秘密cleanup帧/失败健康响应不能冒充卸载。最终45项Package、286项优化CLI自测、原生无签名Release及git diff --check通过；补充损坏字节回归后Package重跑通过。没有实际卸载本机或SMB卷。离线主机清理尚未接入，死卷非force可用性/权限、真实签名与生命周期、异常pending修复、通知与CLI共同编排仍未完成，T009-c/T019保持未勾选。

第二十二轮共享RecoveryNotificationPolicy提取每共享会话2次通知机会消费、同轮失败合并和恢复/抑制排除，CLI两处原内联消费接入共用函数。BackgroundNotificationPreparation提供helper准备接口：仅配置中启用且明确failed/shareRejected的共享，排除本轮健康恢复，EvaluationPermit复核revision/owner/generation后确认pending闲置、状态可读，先持久计数再产count-only载荷。预算不足不写，负计数保守拒绝，损坏字节不覆盖；RecoveryHealthCommit确认健康重置通知计数，与CLI一致。FailureNotification支持Codable但仅count，不含身份/地址/名称/路径；新增2项Core回归覆盖两次上限、合并/排除、持久化、健康重置及损坏字节。47项Package、286项CLI及原生无签名Release/git diff --check通过。此接口尚未由helper调用，防止尚无实际投递时提前消费；UserNotifier本机投递、九语系统文案、前台静默/声音、投递结果记录及mount失败观察汇总仍待接线，T011-a保持未勾选。

第二十三轮复查发现共享RecoverySessionPolicy真实边界变化仅重置通知未重置恢复尝试，与第二十轮文字预期不一致；本轮补齐attemptCount重置，扩大first-readable/真实变化回归，用耗尽10次/2次通知证明初读保留、真实变化清零并重新允许恢复。新增RecoveryFailureObservation只将明确shareRejected且无需reconciliation的mount失败映射无路径failed观察，helper汇总可供通知准备使用，超时/未知/授权/路径冲突不伪装确定失败。runner见实际正常退出、严格响应且无需reconciliation后，仅mount明确拒绝并查表absent允许完成pending，其他错误保留intent；真实隔离worker/内核竞态尚未实测。48项Package、286项优化CLI自测、原生无签名Release和git diff --check通过。没有真实SMB/通知/服务操作；异常pending修复、helper投递和完整共同编排仍未完成。

第二十四轮提取WorkerCompletionPolicy并由runner实际正常退出分支调用，严格响应校验后仍要求当前内核路径证据：mount/health匹配同SMB identity，unmount/cleanup确实absent；唯一可完成的issue响应为无reconciliation的mount明确shareRejected且路径absent。原成功响应不再无需查表就清pending；不满足返回需reconciliation的结构化issue并保留pending，避免helper把未收敛拒绝计为确定失败。新增2项Platform矩阵回归覆盖四操作正常/异常退出、匹配/不同身份/占用/未知/缺失路径、空响应、需reconciliation、授权/超时/繁忙/路径冲突与明确拒绝。50项Package、286项优化CLI自测、原生无签名Release及git diff --check通过。仅测试注入路径证据，真实SMB/内核迟收敛尚未验证；完整pending中断修复仍待实施，T010-b不勾选。

第二十五轮实现SystemUserNotifier实际UNUserNotificationCenter适配，检查GUI是否前台/当前身份authorized或provisional，后台不索取权限；声音同时遵守传入偏好与系统soundSetting。返回suppressedForeground/denied/unavailable/failed，delivered仅表示center.add接受，不证明用户展示/阅读。NotificationCopy提供en/zh-Hans/zh-Hant/ja/ko/de/fr/es/pt-BR完整计数/修复文案，五种语言单复数及中文地区/未知语言回退；仅数量，无目标数据。新增1项Platform语言覆盖回归，51项Package、286项优化CLI自测、原生无签名Release及git diff --check通过。没有实际通知授权/投递操作；尚未把helper视为GUI通知身份，独立helper通知授权/退出GUI后投递需实测，因此主入口未调用且不提前消费预算。九语可靠审校、原生通知展示/声音/前台验证、最终UI动作标签一致性及投递记录仍待完成，T011-a不勾选。

第二十六轮补NotificationAuthorization实际查询/显式请求接口及GUI Settings通知分组，用户点击才requestAuthorization(.alert,.sound)，仅notDetermined请求，已允许/拒绝/未知不重新索权。ApplicationModel互斥请求、独立错误和重查状态；拒绝/未知给系统设置操作提示，声音沿用成功保存后更新。51项Package、286项优化CLI自测、原生无签名Release与git diff --check通过。未调用实际系统授权/展示通知，没有新增对此权限的单元测试模拟冒充系统验证；新增GUI文案尚待九语资源、真实窗口/键盘/VoiceOver验收，helper通知身份待验证，T011-a保持未完成。

第二十七轮检查确认GUI工程未接语言资源阶段；新增原生Localizable.xcstrings并接PBXResourcesBuildPhase/knownRegions九语，通知设置10条完整句每语覆盖，条目记录语境、无格式参数与草稿待native review。原生无签名Release和git diff --check通过，使用plutil逐语言解码打包后Localizable.strings，9×10键值全部与源资源相符。最初Python plistlib直接读取Xcode UTF-16 XML产物编码报错，改用原生plutil成功；未修改产物规避检查。仅资源与工程配置变化，未重跑已通过的51项Package/286项CLI。实际窗口、其他页面九语、可靠译文审校及VoiceOver仍未完成；资源打包不代表本地化验收，父任务不勾选。

第二十八轮新增UserEjectCommit并接worker普通unmount分支：在evaluation.lock/pending内先拒绝损坏恢复状态，DiskArbitration非force返回stopped后再核absent及operationID/revision/generation，原子写suppressed/当前boundary，移除cleanupLedger/repairEjectEvidence，保留everHealthyMounted/attemptCount/notificationCount。保存失败会返回signalUnavailable并留pending，后续自动恢复不越过未确认动作。新增1项Core回归覆盖路径未知/占用/仍挂载不写、pending身份冲突、用户抑制覆盖旧恢复证据/预算保留、损坏状态原字节保护。52项Package、286项优化CLI自测、原生无签名Release及git diff --check通过；首次编辑因空格匹配失败，读当前行后定点修正。没有真实卷弹出；GUI实际动作入口、CLI迁移、完整中断pending修复和系统验收仍待完成，T010-b不勾选。

第二十九轮新增ManualEject平台调用及SwiftUI共享列表Eject按钮。目标必须属于捕获snapshot，父进程验证app active owner/generation/revision、idle及恢复可读后释放evaluation.lock，再由隔离worker重新持锁验证并非force弹出/保存抑制；Task.detached避免同步管道阻塞GUI，模型互斥点击，未知结果明确提示恢复暂停。52项Package、原生无签名Release及git diff --check通过；Core/CLI未变未重复优化CLI自测。未执行任何真实弹出或点击验收；app非active时此入口拒绝，后台归属接线仍待完成，签名/独立worker授权/真实SMB、新增文案九语及完整中断修复未验证，T010-b保持未勾选。

第三十轮新增FinderAccess及共享列表Open in Finder按钮：核验SMB身份、约定路径与当前挂载表完全匹配才打开；absent/未知表/被占用/不同SMB分别拒绝，未挂载不会通过Finder连接绕过自动挂载。新增1项Platform验证矩阵，无调用真实Finder；53项Package、原生无签名Release及git diff --check通过。手动动作新增后台未启用/卷忙/结果未知/路径冲突对应的可采取下一步文案。真实窗口/Finder打开、后台启用通路及新增文案九语仍待完成，不宣称完整US3验收；CLI代码未变未重复优化CLI自测。

第三十一轮新增WorkerOperationStore.launch并接runner：持久begin后闭包仅执行Process.run，run抛错表示无子进程创建，可核ID/revision/generation清除自身pending再回抛原始错误；清除失败保留不确定性，已启动的管道/超时/异常退出不走该回滚。新增2项Core回归：未启动释放idle、成功启动保留pending、第二启动不执行闭包不覆盖第一记录。55项Package、286项优化CLI自测、原生无签名Release及git diff --check通过。catch仍返回需修复的保守提示，但launch失败不再永久阻止下次操作；已启动孤儿进程/内核收敛仍无自动修复，不勾T010-b。未运行真实worker/服务。

第三十二轮发现第三十轮FinderAccess错误要求deriveStandardMountPoint与配置相等，拒绝既有合法自定义路径；去除此限制，保留绝对非根路径/无dot或dotdot/NUL校验与当前挂载SMB身份相符核验。扩充既有Platform矩阵，合法动态临时目录路径允许，占用及空/根/相对/dot/dotdot/NUL拒绝。55项Package、原生无签名Release/diff通过；未调用真实Finder，不把此修正作为自定义NetFS真实挂载证据，T020仍待实证。CLI/Core代码未变未重复优化CLI。

第三十三轮新增ManualActionReadiness共享分类与GUI详情Background mounting提示/显式重查，按持久backend记录区分app eligible/CLI控制/需设置/待批准/转换中/需修复，schema/revision/transition冲突拒绝eligible。Eject在非eligible禁用，实际执行仍后台复核owner/lock/pending；GUI查询不取evaluation.lock避免等待worker阻塞主线程。1项Core矩阵测试覆盖全部分类，56项Package、286项优化CLI、原生无签名Release/diff通过。只显示持久控制选择，未查实时SMAppService状态，不宣称后台就绪/服务运行；注册切换/真实UI及九语仍待完成，无服务安装。

第三十四轮GUI显式后台重查纳入SMAppService当前status：baseline必须enabled，恢复配置启用时recovery也需enabled，未注册/待批准/notFound分别提示设置/批准/需检查；不覆盖CLI归属。待批准时新增用户点击Open Login Items Settings调用既有系统API，后台不打开。新增1项Core状态组合矩阵，57项Package与原生无签名Release/diff通过。未运行GUI实际系统查询/打开设置或注册服务；enabled只证明系统注册启用，不证明helper存活/授权/退出GUI后恢复，新文案九语仍待完成。CLI未改变，未重复优化CLI。

第三十五轮检查主动弹出尚无sessionBoundary时的生命周期，发现首次advance把nil视为真实变化，会撤销UserEjectCommit保存的抑制。RecoverySessionPolicy将nil首次身份建立也视为baseline，更新suppressionBoundary但保留state/attempt/notification；已有未知网络同登录首次可读仍保留，后续真实登录或网络变化仍解除/重置。新增1项Core覆盖首次未知/已知网络保留，以及后续登录变化授权恢复，58项Package、286项优化CLI、原生无签名Release/diff通过。未真实登录/网络/卷操作，T010-b/T019/T020仍待系统验收。

第三十六轮补恢复结果历史：明确mount shareRejected且不需reconciliation的FailureObservation经permit/idle/absent再核后写shareRejected；健康提交在清预算前保存mounted/sequence，每共享最近10条。同一reservation时间/sequence拒绝幂等，baseline无保留次数不记录，未知路径拒绝。新增1项Core验证路径未知不写/拒绝幂等/成功前预算/重复健康不追加/首次挂载不污染，59项Package、286项优化CLI与原生Release/diff通过。健康成功记录表示已恢复健康，可能继先前拒绝后的外部恢复；缺少操作ID级结果关联、offline/credential/中断结果及调度/真实系统证据，不勾T019。

第三十七轮恢复reservation新增可选attempt_operation_id（旧schema1缺失仍可解码），worker传入request.operationID，明确拒绝提交必须与该标识相等才写并清除，取代时间/sequence去重。真实session变化与健康提交也清除；扩充既有Core用例验证旧操作标识不写且不清除当前reservation，59项Package与原生无签名Release/diff通过。仅拒绝提交完成具体操作关联；健康记录仍表示健康恢复而非某NetFS调用成功。离线/凭据/中断结果与调度/实机证据仍缺，未勾T019；未重复优化CLI。

第三十八轮补RecoveryRetryInterval跨helper最小间隔：沿用intervalMs默认1000/夹限100–5000，BaselineMountDecision.deferred区别用户抑制，后台跳过不取凭据，worker reserve再次核验不提前消耗次数。wall clock回退保守延后，未做进程内sleep/固定唤醒。新增1项Core验证deferred/不写预算/到期/配置夹限，调整既有次数与cleanup测试显式时间；首次测试cleanup即时mount旧期望失败，更正为到期时间后60项Package、原生Release/diff通过。完整maxTotalWindow调度/实际重新触发仍缺；updatedAt也由cleanup刷新，可能保守延后，未宣称完整T019，CLI未改未重复优化自测。

第三十九轮分离恢复等待计时：schema1新增可选last_attempt_at，只在reserve实际预留时保存；RecoveryRetryInterval优先使用，旧记录缺字段保守回退updatedAt。健康/真实会话变化清除计时，首次baseline保留。扩充已有Core测试验证reserve持久101后其他状态updatedAt改200不影响101.5等待/102到期，60项Package、原生无签名Release/diff通过。完整调度窗口/到期触发/时钟回退长时间恢复仍未解决，不作为T019闭合证据；CLI未改未重复优化自测。

第四十轮复核helper实际入口发现第三十四轮GUI要求baseline+recovery双enabled与helper二选一互斥不一致，且helper直接autoMountRecovery==true错误处理缺省。新增共享BackgroundServiceReadiness，GUI/helper同选配置恢复缺省true对应服务，另一服务必须stopped；双注册/未知另一状态拒绝。新增1项Core缺省/true/false与双注册/未注册/批准矩阵，61项Package、原生Release/diff通过。纠正第三十四轮服务条件说明；本轮未接重试调度、未注册服务/实际GUI/helper运行，T019与真实服务门槛仍未完成。

第四十一轮BackgroundRetryScheduler接helper单次外部触发：ContinuousClock默认10s/1000–30000ms窗口，默认1s间隔，maxAttempts夹限1–10（baseline也有上限）。summary可选retrySuggested只有明确shareRejected且不需reconciliation/缺失卷deferred才启用；每次evaluate重新核配置/owner/pending，窗口只限制新轮开始，操作另30s时限。新增1项Platform真实100ms异步等待验证次数上限/timeout不重试/窗口不足不等待。首次原生Swift6隔离失败，改isolated参数继承调用隔离后62项Package、原生Release/diff通过。未实际helper/服务/SMB；配置变动后的service重新查询、每共享调度公平性/离线重试与系统触发仍待，T019不勾，CLI未改未重复优化。

第四十二轮BackgroundEvaluator明确mount shareRejected完成fresh absent/idle提交后continue同主机下一共享，最终汇总保存失败issue与其他观察并建议重试；未知错误/reconciliation仍立即停止，不切换备用主机。新增1项Platform混合成功失败summary经有界重试保留身份/错误测试（仅验证汇总，不是真实SMB loop执行）。63项Package、原生Release/diff通过；实际多共享/公平性时间预算、离线、服务重查及系统触发仍未验收，T019不勾，CLI未改未重复优化。

第四十三轮helper每次调度轮重新读配置revision/automation及两个SMAppService状态；revision变化停止旧调度，不拿旧policy处理新配置。BackgroundEvaluator可选expectedRevision在重新读snapshot时核对，后续permit仍核CAS。初始服务检查移入可持久错误summary的do范围。新增1项Platform第二轮configurationConflict传播且无后续轮验证；64项Package、原生Release/diff通过。未实际切换系统服务/GUI或SMB，系统外部触发/离线与完整调度公平性仍待，T019不勾，CLI未改未重复优化。

第四十四轮新增固定automnt.baseline/recovery plist并Xcode CopyFiles嵌入Contents/Library/LaunchAgents。BundleProgram指向已嵌入Contents/Helpers/AutomntHelper；两模式RunAtLoad和现有CLI对应系统网络WatchPaths，recovery另StartOnMount与/Volumes，无KeepAlive/周期。原生无签名Release成功、两份构建资源plutil lint及Python结构/实际helper路径检查/diff通过。没有注册/启动服务，未证明事件到达或自定义路径覆盖；T017依赖持久权限/切换/真实事件仍未完成。Package源码未改，沿用上轮64项，不重复测试。

第四十五轮ServiceController.register实际调用SMAppService前强制核另一固定service为stopped；共享requireOtherStopped拒绝enabled/approval/unavailable，新增1项Core矩阵，65项Package、原生Release/diff通过。只证明注册状态前置约束，不证明旧helper退出，不替代持久transition/锁/idle核验；未实际注册或切换，并发跨进程注册互斥仍需协调器，T017/T023保持未完成。CLI未改未重复优化。

第四十六轮BackendStateStore.advance在activating/active/stopped及reconcileInterruptedTransition原有evaluation.lock内verifyIdle，pending worker拒绝所有权激活/停止确认/修复，不让调用方仅传stopped服务状态越过在途保护。新增1项Corepending下advance/repair失败且journal/state不变，完成匹配worker后允许activation/active；66项Package、原生Release/diff通过。begin仍允许写stopping先阻止新评估；不表示实际旧helper已退出，真实服务适配/协调器与崩溃worker收敛仍缺，T010/T023不勾，CLI未改未重复优化。

第四十七轮新增共享HandoffCoordinator及Sendable HandoffServiceAdapter：begin冻结评估→带deadline停止并确认旧service/process→store锁内idle核验→activating→注册→重新查询真实status→active/awaitingApproval；desired none直接stopped。批准完成仅查status不重复register；错误持久failed/unavailable及issue，不凭不确定结果声明stopped或自动重启旧入口。2项Core验证fresh status覆盖register返回、批准后提交且无重复注册、旧停止未知不调用register；68项Package、原生Release/diff通过。适配器必须自行实现有界系统调用及进程收敛，当前只有测试实现，CLI/SM实际接线、配置CAS、恢复同owner两mode停旧语义/崩溃重放/显式评估仍待，T023不勾。CLI未改未重复优化。

第四十八轮HandoffCoordinator开始/注册前/最终状态提交前，以及批准查询前后重读配置revision，变化拒绝旧切换。既有Handoff测试改用FileConfigRepository.create，新增1项产品save停用后批准拒绝、无额外系统调用且pending保持；69项Package、原生Release/diff通过。配置核验与BackendStateStore提交尚非同一config.lock原子段，短查询/提交竞态仍由EvaluationPermit禁止旧revision执行但不能宣称原子CAS已完；后续需锁内提交核验，真实适配/切换仍待，T023不勾。

第四十九轮FileConfigRepository内部withRevision保持config.lock到相关持久提交结束；BackendStateStore.begin可verifyConfiguration、advance可expectedRevision。协调器begin/activating/active/approval提交全部使用锁内核验，关闭核验后保存与提交的竞态。config→evaluation短锁且非阻塞，系统服务调用在锁外；失败记录与已经核实停止仍允许收敛旧revision，不借此激活。1项Core验证锁期间save冲突、产品save后旧revision提交拒绝且journal/state不变；70项Package、原生Release/diff通过。适配器注册时配置仍可能变化，但最终提交拒绝、worker permit阻止旧配置动作；真实服务适配/进程收敛仍待，T023不勾。

第五十轮failed重试在begin覆盖journal前核旧owner与不同desiredOwner全部stopAndVerify；失败保留原残留身份，成功repair并核expectedTransitionID后才新切换，避免注册已成功/提交失败造成残留漏停。新增1项Core未知新status→failed→清理未知保持原state→核两身份后明确stopped；71项Package、原生Release/diff通过（两次构建均成功，第二次包含保留journal修订）。实际适配/同owner两个mode及全局切换调用互斥仍待，T023不勾。

第五十一轮transfer/completeApproval全程持有稳定私有handoff.lock，含await系统适配调用及failed清理；忙时映射configurationConflict，不碰服务/state。独立evaluation.lock允许启动helper读取非active状态退出。2项Core验证锁忙无系统动作、释放可重试、异步adapter内部竞争切换被拒绝且原切换正常active。73项Package/diff通过，生产修改原生Release通过（随后仅新增异步测试）。该锁覆盖协调器入口，真实入口接线/直接store修复调用审计/系统收敛仍待，不勾T023。

第五十二轮recoverInterruptedTransition以handoff.lock+匹配journalID核previous/pending owner与desiredOwner去重，逐一stopAndVerify后repair仅stopped；拒绝active/stopped重复恢复，不自动register。使用journal读取容忍日志先写/状态未更新，底层repair仍核diskState等于previous或pending和worker idle。2项Core覆盖未知stop原状态保留、activating收敛、不重注册/重复调用、产品生成transition元数据模拟journal-first边界。75项Package/diff及生产原生Release通过，真实崩溃进程/worker修复和入口接线未验证，T023不勾。

第五十三轮transition journal新增向后兼容可选prior_pending，advance/repair日志先写时保留上一步精确状态；interruptedJournal先锁核diskState匹配pending/previous/priorPending，完整active/stopped拒绝且不碰服务，中断最终active提交可清理至stopped。1项Core正常active恢复拒绝、日志active/磁盘activating中断复现后恢复；76项Package、原生Release/diff通过。旧日志无prior_pending的中间推进中断仍不能推断修复，真实进程/worker适配待验证，T023不勾。

第五十四轮HelperExecutionLease使用稳定private helper-execution.lock，真实HelperEntry授权目录解析后全程持有（跨await/defer）；ServiceController.verifyHelperStopped在两固定服务均notRegistered后取lease并重核status，不再只把status当退出证据。1项Core活跃lease拒绝停止证明/释放后可取；77项Package、原生Release/diff通过。仅参与该lease的helper与同目录可核；启动到解析目录前窗口、旧不参与版本、CLI进程/worker/系统实际退出未验证，尚未接入完整HandoffServiceAdapter，T023不勾。

第五十五轮HandoffServiceAdapter新增必须实现requestEvaluation(state:deadline:)，transfer/批准完成在durable active提交之后请求明确评估，approval/stopped不请求；评估错误向调用者传播但不把已确认active覆写failed。已有测试核批准顺序与磁盘active先于请求，新增1项Core offline保持owner/phase/journal无注册失败。78项Package、原生Release/diff通过。实际wake/evaluator适配未实现，不能宣称已修实际首次launchd遗漏；请求后崩溃的durable wake保证仍待，T023不勾。

第五十六轮BackgroundEvaluationTrigger共享真实平台入口，helper已改调用；每轮核固定revision/exact backend state、app EvaluationPermit，再查询两SM状态、重核取消/总deadline后调用真实BackgroundEvaluator。外部可传启用state供postcommit adapter；总deadline共享所有重试而非每轮重置30秒。1项Platform inactive/expired不查询服务/不evaluate；79项Package、原生Release/diff通过。postcommit adapter尚未接该入口，真实SMB/签名权限/helper启动验证待，不能宣称首次注册遗漏已闭合，T023不勾。

第五十七轮服务查询await后再次核exact backend与EvaluationPermit/配置revision；scheduler新增caller deadline并取policy窗口较早值，过期首轮拒绝且不等待越deadline的间隔。2项Platform覆盖系统查询期间owner切换不evaluate、100ms窗口不等待5s/过期零调用。81项Package、原生Release/diff通过。审计worker pending阻止activate，实际SM stop有界性/启动收敛/CLI适配仍待，尚未创建不具停止证据的实际Handoff adapter，T023不勾。

第五十八轮EvaluatingHandoffAdapter实现真实app postcommit调用：controls仅委托停/注册/查询；app active才detached运行真实BackgroundEvaluationTrigger，保持授权目录，全程传deadline/cancellation；summary提交前核cancel/exact backend/permit/revision，CLI evaluation仍委托。81项Package、原生Release/diff通过（无新增系统运行测试）。实际控制adapter/GUI入口尚未组合；未执行注册/SMB/权限，不能称端到端闭合，T023不勾。

第五十九轮BackgroundObservationCommit统一helper/app结果写入，evaluation.lock内核exact backend/revision/generation再atomic replace；helper固定启动state传trigger，catch结果也不可覆盖新owner。1项Platform实际提交offline后begin新generation，旧结果拒绝且原字节保留。首测期望incompatibleOwner，实为既有permit generation优先configurationConflict，修正测试后82项Package、原生Release/diff通过。真实系统适配仍待，T023不勾。

第六十轮核目标SDK SMAppService.h异步unregister completion契约：成功在进程killed后，可安全重注册；新增deadline continuation门，timeout/迟到completion仅resume一次。AppServiceHandoffAdapter固定两服务停用，核helper lease/worker idle，再按当前revision/recovery选择注册及readiness；CLI明确拒绝，evaluation需组合EvaluatingHandoffAdapter。2项Platform迟到成功不覆盖timeout/成功忽略迟到timeout；84项Package、原生Release/diff通过。notRegistered无callback分支依赖lease，启动前窗口/旧版本仍未证明；同步register调用SDK无hard取消，GUI未接/实际SM注册停用未运行，T023不勾。

第六十一轮实际SM adapter注册preflight持evaluation.lock核配置/后台revision、activating+desired app+transitionID+verified stopped、automation开启及worker idle，释放锁才SM注册。1项Platform公开register在stopped时拒绝（不触系统），准备后模式默认recovery、pending worker阻止。85项Package、原生Release/diff通过。preflight后系统调用仍由coordinator handoff.lock序列化，低层直接变更锁约束/旧CLI/GUI及真实SM未闭合，T023不勾。

第六十二轮实际SM停用等待接取消handler，continuation门支持cancel先于install及之后，保留单次result，取消后迟到系统成功不续转；defer取消timeout任务。2项Platform前后取消竞态，87项Package、原生Release/diff通过。取消不宣称撤销系统unregister，后续必须fresh核验；无真实系统停用，T023未闭合。

第六十三轮SwiftUI详情新增显式Enable app background mounting/Continue after approval，model组合真实SM+evaluation adapter/coordinator，30s deadline、重复互斥、CLI及desired CLI拒绝、不改automation开关；完成重读配置/readiness，awaitingApproval提示系统设置。87项Package、原生Release/diff通过；未运行真实窗口/注册/SMB，缺后台metadata不自动initialize（避免旧CLI未识别被当none），全新初始化、active模式变化/repair入口及九语待完成；T023/T024不闭合。

第六十四轮修ManualActionReadiness把完成journal retained transitionID误判repair：active仅desired==owner/non-none/verified enabled可完成，stopped须none/verified stopped；revision检查提前，approval须app/ID/verified requiresApproval。1项Core使用实际store progression批准→active→stopped确认eligible/setup及stale approval拒绝，更新无证据approval旧矩阵期望。88项Package、原生Release/diff通过。真实GUI/SM仍未验；首次metadata缺失仍保守拒绝，T023/T024不闭合。

第六十五轮LegacyCLIServiceDefinition只读分类absent/recognized/unknown，核legacy Label/单一绝对automnt参数/RunAtLoad/network WatchPaths，不把shape称签名版本/退出证明；GUI缺metadata改needsRepair并按结果指引，不显示不可执行启用。2项Platform元数据测试（无业务配置），90项Package、原生Release/diff通过。sandbox无法读取旧plist映unknown，缺文件不代表loaded job不存在，真实launchd查询/初始化仍待；T026不闭合。

第六十六轮旧定义读取改O_NOFOLLOW/NONBLOCK/CLOEXEC单fd，fstat普通文件及1MiB上限再分配，EINTR重试，读后size/mtime/ctime核验，dangling link未知非absent。1项Platform链接/超大文件；首轮Core guardedCommit出现EBADF，定位StableFileLock完整属性赋值后throw导致deinit与错误分支double-close，改局部fd成功最后赋self。重跑91项Package、原生Release/diff通过。不保证父目录链接/路径替换或launchd退出证明，T026待。

第六十七轮SwiftUI Settings接Automatic mounting独立toggle，经FileConfigRepository CAS保存仅automationEnabled，禁切换/弹出中动作，成功重查readiness，关闭说明保留已有挂载；详情引导改Settings。91项Package、原生Release/diff通过，无新增镜像测试；真实窗口/九语待。active后台保存新revision后尚需统一reconcile，当前保守repair不冒充自动继续；T024/T025未闭合。

第六十八轮GUI显式Repair app background mounting：已有可读非CLI状态才处理，active修复经stop→新revision注册，失效approval/中断先recover，开关关闭转none不注册；缺metadata不显示修复，拒绝CLI。1项Core实际repository保存recovery/automation并probe验证停用先于注册及disable仅stop，92项Package、原生Release/diff通过。journal-first不可读修复、真实SM/初始CLI/自动保存衔接待，T024/T025不闭合。

第六十九轮App-only interrupted recovery核previous/pending/priorPending不涉CLI，锁内重新核验再system stop。GUI显式repair在normal read失败时经journal验证恢复stopped后新配置transfer；无metadata仍不初始化。1项Core journal-first App恢复/CLI零调用且journal保留，93项Package（58/35）、原生Release/diff通过。真实SM/launchd/凭据/首次初始化仍待，T024/T025未闭合。

第七十轮journal读验证previous/pending schema、generation+1无溢出、pending ID/desired、priorPending同代同revision同目标（允许previous crash boundary）；1项Core三种损坏metadata确认零service调用。94项Package、原生Release/diff通过；未证明全部phase转移历史，真实SM/首次初始化仍待，T023/T025未闭合。

第七十一轮Settings独立Automatic recovery经共享CAS仅autoMountRecovery保存，automation off不清偏好，repair直接入口；saveAutomation补eject guard，host save/reorder补readiness刷新防残留eligible。94项Package、原生Release/diff通过；无新增镜像测试，真实窗口/九语/自动保存reconcile仍待，T024/T025不闭合。

第七十二轮transfer none终态commit加expectedRevision原子核验，service stop期间新配置保存拒绝旧completion并failed，不注册/不覆盖新开关。1项Core stop adapter实际repository保存回归，95项Package、原生Release/diff通过。系统服务已停止但冲突保守failed需fresh repair，不把failed说运行中；真实SM/CLI待，T023/T025不闭合。

第七十三轮active durable但SM stopped/requiresApproval改needsRepair，避免setup/continue按钮因active无法执行；真正awaitingApproval即SM enabled仍需completeApproval不跳过commit。现有Core store progression及矩阵补断言，95项Package、原生Release/diff通过；真实系统漂移/UI九语待，T024不闭合。

第七十四轮真实Swift6 CLI探编失败，多处可变global/static；不使用unsafe掩盖，Package仍Swift5兼容，T004未闭合。CLI config draft revision cache改锁保护read/write/remove，首次漏remove编译失败补齐后95项Package、最高优化CLI build及286自测/diff通过。未宣称CLI整体thread-safe或Swift6完成。

第七十五轮MountExecutionBudget改同步线程上下文deadline/failure/NetFS结果，真实Thread测试不覆盖另一线程预算/结果。95项Package、最高优化CLI/287自测/diff通过；该上下文不适用跨await，Core异步worker显式context，整体CLI Swift6仍待，T004未闭合。

Keychain适配采用Data Protection Keychain与LAContext.interactionNotAllowed，无自动访问组假设，无后台索权。新增固定bundle plist名称的SMAppService适配并编译通过，尚未接入注册流程或调用系统注册；没有安装服务。稳定签名/真实Keychain权限、固定agent事件实测、独立helper授权、NetFS/DiskArbitration、退出GUI后自动恢复、完整SwiftUI首次流程/编辑/九语/VoiceOver仍待实施与实证。
第七十六轮core-round-dev提取共享恢复轮次协调器Sources/AutomntCore/RecoveryRound.swift（RecoveryRoundPlanner）：configuredRecoveryVolumes/knownRecoveryVolumeIdentities、逐卷RecoveryRoundVolumeSnapshot（identity/mountPoint/present/observedPath/hostReachable/health）输入、RecoveryVolumeAction（attachHealthy/cleanupThenRecover/recover/suppress/pendingUnreachable/deferred）计划、账本（volumes/cleanupLedger/attempts/sessionBoundary）与failed/recovered/suppressed/deferred/通知身份集合都由共享实现产出；配置启用卷枚举、主机顺位firstReachableHost与relevantVolumes、重试窗口夹限、健康证据映射、整轮deferRound一并迁入Core，RecoveryNotificationPolicy.consume语义未改。Entry.swift的runRecoveryRound仍在原处保留CLI可见签名（configuredVolumes类型别名指向RecoveryRoundConfiguredVolume，参数改@escaping），只负责锁、状态读写、诊断文案与副作用（cleanupVolume/applyRecovery/volumeHealth），并保留单轮host:port记忆化探活与预算窗口设置顺序；判定/账本/通知计数不再在CLI出现第二份。新增Tests/AutomntCoreTests/RecoveryRoundTests.swift共7项：损坏状态不误判neverMounted且不耗通知额度、同路径备用只传播抑制不传播健康/修复许可、superseded路径从failed/suppressed/notification剔除且手动恢复清旧抑制、预算耗尽零尝试与有界重试后BaselineMountDecision拒绝、deferRound不耗预算/通知/状态、通知上限2与成功恢复重置及抑制不计、开关门与健康映射；业务配置全部经FileConfigRepository.create/save生成。实际执行：swift build成功；swift test 全绿（按 target 实测：AutomntCoreTests 73项/25套、AutomntPlatformTests 35项/15套；本轮新增7项全部通过）；scripts/build.sh /tmp/automnt-005成功；/tmp/automnt-005 --self-test 288 passed, 0 skipped, 0 failed（基线287，+1来自并行的CLIOwnership自测，非本轮新增）；仓库根预编译automnt未替换（仍3.3.2/267项，属发布产物）。未验证边界：未在真机执行SMB挂载/卸载与磁盘仲裁，未跑真实helper/launchd路径，RecoveryRoundPlanner尚未被BackgroundEvaluator接线（helper仍走BaselineMountDecision+RecoveryCleanupCommit组件路径），GUI未消费共享协调器；第六十八轮起的CLIOwnershipGate/CliOwnershipTests为并行成员改动，非本轮内容。CLI恢复轮次行为按既有--self-test逐条等价，未修改任何断言。

第七十七轮cli-owner-dev完成B2 CLI owner-aware接线与统一evaluation.lock（T010-a/T022的owner-aware部分）。新增Sources/AutomntCore/CLIOwnershipGate.swift（纯决策，无IO）：CLIOwnershipAction(registration/evaluation/status/teardown)、CLIOwnershipDecision(permitted/needsInitialization/refusedAppOwner(phase)/requiresRepair/transitionInFlight(phase)/staleRevision(phase)/staleGeneration/operationInProgress)、withPermission(未通过先抛错再动作)、refusesAppClaim(owner或desiredOwner为app)、permitsNonResidentDefinition(拒KeepAlive/StartInterval/StartCalendarInterval)与判定tag；未修改任何既有Core文件。新增Sources/AutomntCLI/ServiceAdapter.swift：CLIOwnership（真实目录=活动配置所在目录，与GUI PermissionStore.expectedDirectory同源；状态缺失时initialize(revision:)建立owner=none/stopped/generation=0；registrationRefusal与beginEvaluation/endEvaluation持锁复核revision+generation+owner/phase；stopServiceForDisable先由调用方保存配置再停服务）与实现HandoffServiceAdapter的CLIServiceHandoffAdapter(stopAndVerify/register/status/requestEvaluation)，复用Entry.swift既有registerOrUpdateLaunchAgent/getLaunchAgentDiagnostic/runCommand/WorkerOperationStore，未复制业务规则、无新常驻进程。Entry.swift接线：installLaunchAgent与自愈healIfNeeded、regenerateServiceDefinitionForSwitch均在注册前经registrationRefusal，app owner时拒绝抢占；installLaunchAgent与配置菜单保存路径（automation_enabled=false）改为先保存配置再stopServiceForDisable停服务并提示"已挂载共享保持可用"，只禁止新挂载不卸载已有卷；配置菜单remount与主CLI流程（恢复轮+基线段挂载）在真实动作前经beginEvaluation取得统一evaluation.lock许可，runRecoveryRound新增ownershipPermit参数（缺许可且非自测显式许可时保守defer、零挂载副作用），动作后endEvaluation复核代次；--uninstall在app owner时跳过bootout与plist删除，仍执行CLI自身Shell入口/可执行文件清理。新增Tests/AutomntCoreTests/CliOwnershipTests.swift共6项：app owner(active)下register判定refusedAppOwner且withPermission抛incompatibleOwner且backend-state.plist与automnt.plist字节不变、desiredOwner=app的failed残留→requiresRepair非静默接管且字节保留、generation 0→1后旧快照被EvaluationPermit抛configurationConflict且字节保留而新代次通过、stale revision拒绝且evaluation.lock inode不变、状态缺失→needsInitialization而status在app owner下仍permitted、事件驱动定义无KeepAlive/StartInterval/StartCalendarInterval；另在CLI --self-test新增5项断言（首次运行建立明确状态、app owner结构化拒绝且字节不变、无许可恢复轮零挂载、有许可恢复轮端到端仍执行）。实际执行：swift build成功；swift test全绿（AutomntCoreTests 73项/25套含本文件6项、AutomntPlatformTests 43项/16套，0失败）；scripts/build.sh /tmp/automnt-005-b2成功且/tmp/automnt-005-b2 --version输出3.4.0；/tmp/automnt-005-b2 --self-test 295 passed, 0 skipped, 0 failed（基线288，+7=6 CLI断言+1）；自测全程隔离临时目录，实测未在~/Library/Application Support/automnt创建backend-state.plist、未改动真实com.user.automnt.plist（mtime仍10月7日）。未验证边界：未做真实CLI注册/接管/停用的launchd实测，未在真机验证app owner与CLI并发接管，未验证真实SMB挂载/弹出在持锁下的表现，未运行GUI；"existing recognized CLI service"快速路径（避免普通automnt运行bootout正在运行的作业）仅经代码与生成器自测验证，未在真实launchd上实测；停用路径的"先保存后停服务"顺序仅经代码审查与既有自测，未在真机跑通；未替换工作区根预编译automnt（仍3.3.2旧产物）。T010-a/T022的真实系统门槛仍待V1独立验证与真机验收。

第七十七轮数据更正：本轮最终 `swift test` 为 AutomntCoreTests 74项/25套（Tests/AutomntCoreTests/CliOwnershipTests.swift 共7项，新增第7项 operationInProgressIsDistinctFromRepair 覆盖"并发持锁是保护而非损坏"判定）、AutomntPlatformTests 43项/16套，0失败；上段所记73项/6项为追加该测试前的中间数字。`--self-test` 仍为 295 passed, 0 skipped, 0 failed（该新增项属 Package 测试，不进 CLI 自测计数）。

第七十八轮core-round-dev（T009-c2）消除 CLI/helper 两套恢复编排：新增 `Sources/AutomntCore/RecoveryVolumeDecision.swift` 作为**逐卷判定唯一实现** `RecoveryVolumeDecisionPolicy.judge(RecoveryVolumeFacts, context:)`，连同 `RecoverySupersededPolicy.supersededIdentities`（superseded 剔除唯一实现）与 `peers(configuration:presentIdentities:)`；`RecoveryRoundPlanner.run` 改调该函数，`BaselineMountDecision.decide` 改为**委托**它（仅保留挂载点状态门 `block(path:identity:)`），`BackgroundEvaluator` 的抑制/deferred/superseded/尝试上限分支删除、改为取共享判定，helper 仅保留平台适配（async TCP 探活、worker 子进程、EvaluationPermit、组件级提交）并抽出可注入接缝 `BackgroundVolumeEffects`（runner 延迟构造，保持"先探活主机再构造 worker"原序）。判定优先级已按裁决 A 调整：手动恢复 > 状态不可读保守 > **`.suppressed` 记录抑制（先于 everHealthyMounted）** > judgeRecoverySignal > 同路径对端抑制（仅当会话边界存在）> 健康覆盖 > 尝试上限 > 重试间隔 > 挂载许可。

裁决 A（Lead 指定，禁止选 B）：`UserEjectCommit.apply` 只写 `state=.suppressed`+`suppressionBoundary`、**不写 everHealthyMounted**，故"首次即被用户弹出"的记录在改动前 CLI 侧会落 `.neverMounted` 被重挂，而 helper/worker（`BaselineMountDecision:39` 原有 `.suppressed` 门）判抑制——这是**规则矛盾**而非重复。本轮按 A 统一为抑制，属**有意行为变化**：CLI 的 `--config → 立即重新挂载`（非 manual 轮次）不再重挂"首次即被弹出"的卷，与 helper/worker 及 FR-002③/SC-002 一致。约束 2/3 已满足：`manualRecovery` 判定置于最前，既有断言 `Entry.swift:4936`（explicit Remount now restores a suppressed volume）等 4 条 CLI 自测保持绿；`RecoverySessionPolicy.advance` 在会话边界变化时把 `.suppressed` 重置为 `.pendingRecovery`，新增用例 `sessionAdvanceReleasesSuppressionForFirstEjectRecord` 已断言，故不存在跨会话永久抑制。约束 4：`Entry.swift:4790` 的 never-mounted 夹具为 `record == nil`，新增用例 `missingRecordIsStillNeverMountedRatherThanSuppressed` 断言无记录仍走 FR-002④。

行为等价性（硬门槛）已以**差分预言机**证明：新增 `Tests/AutomntCoreTests/BaselineDelegationEquivalenceTests.swift` 内嵌改动前 `BaselineMountDecision.decide` 实现作为特征化预言机（仅测试用），在 5(path)×2(allow)×2(auto)×5(state)×2(everHealthy)×2(repair)×2(ledger)×4(attempts)×3(updatedAt)×3(boundary)×2(corrupt)×3(maxAttempts)×2(configGiven) = **345,600 组输入上 zero mismatch**；该预言机在迭代中实际抓出并修正了 4 处分歧：nil-config 挂载许可、`allowRecovery` 原始值 vs permitsMount（重试间隔门）、尝试上限门要求配置存在、以及"重试间隔 deferred 必须先于抑制回落"。新增 `Tests/AutomntCoreTests/RecoverySuppressedRecordTests.swift` 6 项（含裁决要求的 (a) 抑制+零挂载、(b) manual 仍可恢复、(c) 新边界后非抑制）与 `Tests/AutomntPlatformTests/BackgroundEvaluatorTests.swift` 10 项表驱动（missing+reachable→mount、missing+unreachable→offline、present+unavailable→blocked 不清理、present+healthy→attachHealthy、present+failed→先清理后恢复、suppressed→不挂载、deferred→不挂载且不耗预算、superseded 空操作+策略单测、顺位独占不切备用）。

实际执行：`swift build` 成功；`swift test` 全绿 **AutomntCoreTests 94项/28套、AutomntPlatformTests 61项/17套**（本轮前基线 86/26、51/16）；`bash scripts/build.sh /tmp/automnt-t009c` exit 0、`--version` 3.4.0、`--self-test` **295 passed, 0 skipped, 0 failed**（断言未改）；`xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt -configuration Release -derivedDataPath .build/xcode-t009c CODE_SIGNING_ALLOWED=NO build` → **BUILD SUCCEEDED**。变异自证（`/tmp/t009c-mutation.py`，/tmp 副本，仓库文件 `shasum -c` 校验未变异）：14 条真实变异 **13 条经该批直接捕获**，M13 为无效变异（制造重复 `case` 导致编译失败而非行为变化），其等价的合法行为变异（helper 抑制分支改为 `break` 落穿到挂载）实测被 `suppressedRecordSkipsMount` 捕获，故**全部等价变异均被捕获**；基线（无变异）经同一流程确认 PASS-OK，证明检测器本身可信（此前一版 shell 检测器把 swift-testing 的 `failed after … with N issues` 误判为通过，已弃用并改用 Python 驱动）。

未验证边界：未做真实 SMB/NetFS/磁盘仲裁与真实 worker 子进程端到端（表驱动测试全部注入 runner/探活/状态文件）；`PermissionStore.resolve()` 的签名/授权路径、真实 Keychain 凭据读取、真实 EvaluationPermit 与 launchd 触发未跑；helper 的 `supersededFiltered` 在单主机轮次内恒为空操作（配置校验禁止同主机重复挂载点），跨主机 superseded 仅由 CLI/planner 路径覆盖，未在真实 helper 进程验证；`--self-test` 295 与 `swift test` 项数变化不含对 CLI 自测断言的任何修改。

第七十九轮core-round-dev（R5 / task-19）修复 V8 报告的 G1/G2 与预言机覆盖过度声称：**G1** 新增 `RecoveryVolumeAction.planned(for:)` 作为「共享 decision → 计划动作」唯一映射，`RecoveryRoundPlanner` 逐卷分派由 `switch signal` 改为 `switch judgment.decision`，动作一律取 `.planned(for:)`；`signal` 仅剩 `unknownConservative` 的保守账本标记与 superseded/通知额度结算用途（注释写明「动作唯一来源是 judgment.decision」）。**G2** helper 桥接 `boundary: sessionBoundary ?? ""` → 原样 `sessionBoundary`，并在共享 peer 门追加 `!boundary.isEmpty`，使 nil 与空串都表示「尚未建立边界」而同结论；另发现并修复改动前 `BaselineMountDecision` 的**对端抑制短路语义**在 task-15 被降级的问题（会使 helper 把对端抑制错报为 deferred），现恢复短路返回 `.sessionSuppressed`。**预言机订正**：按 Lead 建议选 (b)，把 `BaselineDelegationEquivalenceTests` 配置扩为两个主机/共享并新增 `peerKind` 维度，使 `protectedByPeer` 的 `peer.identity != identity` 守卫真正触发（此前恒为死代码），矩阵 345,600 → **1,382,400** 且 0 不一致。

新增 `Tests/AutomntCoreTests/RecoveryDecisionBindingTests.swift`（4 项：六种 decision↔动作绑定与单射、planner 可达五种 decision 的动作与副作用绑定、deferred 零预算、清理失败退 pending）与 `Tests/AutomntPlatformTests/RecoveryBoundaryConsistencyTests.swift`（5 项：共享门/`BaselineMountDecision`/helper 三路径对 nil 与空串一致，并以真实边界仍抑制反证非真空）。

实际执行：`swift build` 成功；`swift test` 全绿 **AutomntCoreTests 108项/30套、AutomntPlatformTests 66项/18套**（V8 基线 94/28、61/17；本轮新增 Core 14、Platform 5）；`bash scripts/build.sh /tmp/automnt-g` exit 0、`--version` 3.4.0、`--self-test` **295 passed, 0 skipped, 0 failed**；`xcodebuild … -derivedDataPath .build/xcode-g CODE_SIGNING_ALLOWED=NO build` → **BUILD SUCCEEDED**，产物含 `AppIcon.icns`/`Assets.car` 且 `Info.plist` 的 `CFBundleIconFile`/`CFBundleIconName` 均为 `AppIcon`；`python3 scripts/verify-localization.py` exit 0。变异自证 `/tmp/r5-mutation.py`（/tmp 副本，仓库 sha256 校验未变异）：**11/11 全部捕获、基线 PASS-OK**——含 V8 的原始 G1 复现（此前 0 issues，现 9 issues）、G2 配对变异（7）、仅移除空串门（6）、合成非空兜底（5）、对端抑制不再短路（1）、矩阵缩小（1）、退回不委托（27）。两条最初报 NOT-CAUGHT 的变异已查清且**均非漏判**：planner 改用动作枚举做 switch 属编译失败（非行为变异，等价合法变异 40 issues 被捕获）；仅恢复 `?? ""` 在当前实现下是等价变异（新增空串门已规范化），故改为「`?? ""` + 移除空串门」的配对变异对应真实 pre-R5 状态并被捕获。行为变化三条（G1 动作权威来源、G2 nil/空串不再启用对端抑制、短路语义恢复）均为一致性收紧或恢复，未放宽任何安全条件；`Entry.swift` sha256 与 V3/V8 冻结记录一致（`ede0ca41…`），`:4790`/`:4936` 断言未改。

未验证边界：无真实 SMB/NetFS/磁盘仲裁与真实 worker 子进程；`PermissionStore.resolve()` 签名授权、Keychain、真实 EvaluationPermit、真实 launchd 未跑；G1 影响仍属静态推导（真实消费者为签名隔离的 MountWorker）；helper 的 supersededFiltered 在单主机轮次内恒为空操作；GUI 未消费共享判定。

# 2026-10-19 阶段 10 本地增量与门禁

维护者要求按上一轮建议执行后，本轮完成：修复测试目标编译、实现 T087–T091、补记 2026-10-13 18:20–18:37 已存在但未记录的 T083/T084/T085/T086/T092 代码增量。未递增版本、未提交、未推送、未发布，未替换已安装服务。

## 代码变化

| 任务 | 本地变化 | 仍未验证 |
| --- | --- | --- |
| T087 | `EditShareView` 打开时固定 `editBase` 与目标身份，保存只用该 revision；目标消失/并发写入报冲突并保留输入，成功关闭。`ServerSettingsView` 打开时固定 `base`，名称/连接保存复用同一 revision，成功后刷新基线；改 host/port 成功后关闭页面；索引开关也用捕获的 base。 | 真实窗口多次编辑、目标删除、CLI/GUI 并发与保存后关闭。 |
| T088 | `ApplicationModel` 新增草稿登记（id/dirty/save）；三个编辑表单出现时登记、变更时更新、消失时注销。⌘Q、菜单与 Dock 退出经 `applicationShouldTerminate` 走原生 NSAlert：保存并退出／放弃并退出／取消。保存复用 revision 校验路径，失败保留窗口与草稿并显示原因；无草稿直接退出。 | 真实 ⌘Q/菜单退出、保存失败/冲突弹窗；主窗口 ⌘W/红色关闭按钮仍未接入草稿确认。 |
| T089 | `MainWindowView` 监听 `scenePhase == .active` 与 `NSWorkspace.didMount/didUnmount`，调用 `refreshObservedState()` 重读配置、内核挂载、发现与最后一轮摘要；不评估、不挂载、不覆盖草稿；读失败保留只读快照与原因。 | 真实激活、Finder 挂载/弹出、CLI 保存后的刷新与焦点/滚动保持。 |
| T090 | 主窗口宽度自适应：`<700pt` 使用原生 `NavigationStack`（服务器→共享→详情），宽窗保留左右两列；最小宽度 380；路径在对象消失时收缩；选择按身份回退/保持；空态共用。 | 真实窄窗、较大文字、九语长译文、键盘/VoiceOver。 |
| T091 | 三个编辑表单字段级校验：地址/名称/挂载位置分别提示并聚焦首个错误；重复地址、重复挂载位置、身份冲突复用 `ConfigurationValidation` 原因枚举；新增 8 条九语文案（目录 355 键）。 | 九语母语审校、真实错误输入的焦点与长文案可读、全界面原生验收。 |
| T083/T084（补记） | 应用与 helper entitlements 已声明精确 home-relative 例外；`FixedDirectoryAccessProbe` 诊断固定目录；应用源码 `NSOpenPanel`/delegate 已删除。 | 签名身份真实读写、系统许可允许/拒绝、helper 持久访问、MAS 接受与否。 |
| T085（补记） | 图标按最新源生成；1024 源与 Assets 输出 SHA-256 一致；脚本加入内容新鲜度门禁。 | Finder/Dock、浅深色与小尺寸实际显示。 |
| T086（补记） | 受管服务器的新发现共享合并回可添加组；`ServerInventoryTests` 覆盖。 | 真实 Finder 新连接后的窗口表现。 |
| T092（补记） | `TransitionRecovery.swift` 与 `CLITransitionRecoveryTests`（6 项）提供 CLI 中断恢复入口与校验。 | 真实 stopping 中断、重开/反向接管与并发。 |

## 实际执行

| 门禁 | 结果 | 限度 |
| --- | --- | --- |
| `swift build` | 通过 | 仅 Package 目标，不含 Xcode 应用目标 |
| `swift test` | 299 项通过：Core 180/48 套、Platform 89/25 套、CLI 30/2 套 | 单元/结构测试，不等同真实系统与窗口 |
| `bash scripts/build.sh /tmp/automnt-t087` | exit 0，`--version` 3.4.0，Apple Development 签名 | 优化 CLI 与根二进制；未替换已安装服务 |
| `/tmp/automnt-t087 --self-test` | 295 passed, 0 skipped, 0 failed | 断言未改；不覆盖应用/权限路径 |
| `xcodebuild -project apps/Automnt/Automnt.xcodeproj -scheme Automnt -configuration Release -derivedDataPath .build/xcode-t087s DEVELOPMENT_TEAM=TEAMID1234 CODE_SIGN_IDENTITY='Apple Development' CODE_SIGN_STYLE=Manual build` | BUILD SUCCEEDED（app/helper/worker 均 Apple Development） | 未启动应用，未验证系统授权或 SMB |
| `bash scripts/verify-signature.sh .build/xcode-t087s/Build/Products/Release/Automnt.app` | exit 0：三目标 Apple 身份、同团队、精确 entitlements、嵌套 seal | 不证明实际权限或运行 |
| `python3 scripts/verify-localization.py --quiet` | exit 0，355 键 | 仅覆盖/语言分支，母语审校仍待 |
| `python3 scripts/verify-swift6-concurrency.py` | exit 0（36 carriers / 34 accessors / 1 atomic publication） | 结构门禁，不证明死锁自由或压力 |
| `git diff --check` | 无输出 | 不代表未跟踪文件已提交 |

## 未验证边界

真实 macOS 27 窗口交互（退出确认、字段焦点、窄窗返回、刷新保持）、真实系统许可与 helper 持久访问、真实 SMB 挂载/弹出与认证、九语母语审校与长译文布局、键盘/VoiceOver、通知投递、诊断真实导出、MAS 审核接受精确 home-relative 例外，均未在本轮执行。T083/T084/T087–T092 的 checkbox 保持未勾选；T093/T094 未开始。

# 2026-10-19 真实签名应用运行验收（本机，局部）

环境：macOS 27 / arm64；Release 签名构建 `.build/xcode-t087s/Build/Products/Release/Automnt.app`，Apple Development（团队 `TEAMID1234`），`verify-signature.sh` exit 0。真实 SMB 目标为本机已挂载的 `nas.example.test` 的 `finalhome` / `personal_folder`。配置由应用自身创建（单行添加后生成 `~/Library/Application Support/automnt/automnt.plist`，0600），未手写业务配置。截图存于 `.build/automnt-runtime-2026-10-19/`。

## 实际步骤与观察

| 步骤 | 实际观察 | 截图/命令 |
| --- | --- | --- |
| 首次启动（无配置） | 无任何目录选择面板；应用准备并读取固定目录，窗口显示本机真实发现的 SMB 服务器（已管理 0 / 可添加 2），无内部路径或配置位置字段 | `automnt-first-run.png` |
| 宽窗布局 900×620 | 左侧平铺服务器与计数，右侧选中服务器的独立自动挂载开关、已管理/可添加共享组，工具栏 +/刷新/设置/搜索，底部真实后台状态 | `automnt-first-run.png` |
| 窄窗 430×700 | 自动切为服务器列表；点击服务器以原生 push 进入共享列表并显示返回按钮；加宽后恢复左右两列 | `automnt-narrow.png`、`automnt-narrow-server.png` |
| 字段级校验 | 空表单提交显示地址/名称/挂载位置三条红色字段错误，焦点落到地址；畸形地址与空名称/挂载被拦截，无写入 | `automnt-validation.png` |
| 重复地址拒绝 | 已管理的 `personal_folder` 再以完整 URL 添加，地址字段就地提示“已以相同地址或位置列出”，配置未变 | `automnt-duplicate2.png` |
| 真实单行添加 | 点击 `personal_folder` 的“添加”后立即落盘（0600，host/share/version 3.4.0/automation false），侧栏计数变为 1/1，右侧显示“可用”与“在 Finder 中打开”，出现开启自动挂载引导 | `automnt-added.png`、配置 plist 只读查看 |
| 详情 | 状态“已挂载 · 自动挂载已关闭”、最近检查时间、约定位置/SMB 地址、自动安排与独立开关、动作顺序（Finder/弹出/编辑/移除）、移除后果、Spotlight 说明与诊断 | `automnt-detail.png`、`automnt-detail-scrolled.png` |
| 移除 | 确认框写明“不再自动挂载、保持挂载、不删文件或系统凭据”；确认后配置 hosts 为空，`mount` 仍显示该卷挂载；最后一个共享随服务器同次移除 | `automnt-remove-confirm.png`、`mount` 输出 |
| 重开持久化 | 添加 `finalhome` 后退出并重新打开，仍显示已管理 1 / 可添加 1，状态“可用” | `automnt-relaunch.png` |
| 退出保护 | 脏表单时 ⌘Q/菜单退出弹出原生确认（保存并退出/放弃并退出/取消）；取消保留窗口与草稿；保存失败保持窗口与字段错误。无脏草稿时直接退出。本次同时修复了两个真实缺陷：无草稿退出曾被 `applicationShouldTerminate` 的同步 `terminate` 静默取消；失败保存曾错误附加“检查文件夹访问权限”通用提示 | `automnt-quit-alert.png`、`automnt-savequit-fail.png` |
| Settings | 实际后台/自动恢复、菜单栏与登录、通知授权与独立声音、重试次数、支持分区按序显示，无内部路径 | `automnt-settings.png`、`automnt-settings2.png` |
| CLI 状态/动作 | `--status` 正确读取唯一配置与已挂载共享；`--mount`/`--eject` 对真实目标返回 `cli-ownership:requiresRepair`（此时 `backend-state.plist` 为 owner=none/phase=stopped），未执行挂载/弹出 | 终端输出、`backend-state.plist` 只读查看 |

## 结论与边界

可确认：签名 app 的固定目录 entitlement 在无面板情况下实际可用；单行添加/移除立即持久化；重复地址拒绝不写配置；退出草稿确认与取消；无草稿退出；窄窗原生分层导航；Settings 与详情的现行结构与文案；字段级校验与焦点。真实新增/移除的 SMB 目标来自本机已挂载卷，配置由程序生成。

不可据此关闭 T093/T094：独立 helper 持久访问、真实登录/重启/升级后的后台恢复、GUI 退出后后台 SMB 文件访问、九语母语审校与真实语言布局、VoiceOver、主窗口 ⌘W 关闭保护、繁忙卷弹出矩阵均未执行。CLI `requiresRepair` 与状态不一致的现象保留为 T092 的待诊断缺口。运行测试在维护者机器上留下程序生成的配置（`finalhome` 已管理、automation 关闭）与 backend-state；未手工编辑配置文件。

# 2026-10-19 九语与辅助功能自检

维护者要求九语与辅助功能由本轮自行完成，可呼叫 agy 作为辅助。agy 1.4.2 已尝试启动只读审校，但进程长时间无输出后停止，未采信其结论；本轮改为项目内自审 + 实机语言切换。

## 九语实机检查

对 en、ja、ko、de、fr、es、pt-BR、zh-Hant（zh-Hans 已在主流程截图）使用 `-AppleLanguages` / `-AppleLocale` 启动签名应用，逐一打开主窗口与“添加共享文件夹”sheet，截图存 `.build/automnt-runtime-2026-10-19/languages/`。观察到：

- 九语均加载对应资源，无英文回退、无关键控件被截断；服务器名按设计截断并提供完整值帮助。
- 长译文（de/fr/es/pt-BR）在 900×620 下完整可读；窄窗 430×700 下主流程仍可操作。
- 术语自审发现并修复两处不一致：
  - 添加表单说明使用“位置/Speicherort/local”等泛称，而字段名是“挂载位置/Einbindungsort/Emplacement de montage/Ubicación de montaje/Local de montagem/マウント場所/마운트 위치/挂载位置”。已统一九语说明文案到字段术语。
  - 德语“后台挂载”由“Hintergrund-Verbinden”改为与“einbinden”一致的“Hintergrund-Einbinden”。
- 自动化门：`python3 scripts/verify-localization.py` exit 0（355 键、九语分支、占位符与复数门）。

## 辅助功能自检

- 键盘遍历：真实窗口中反复 Tab，AX 焦点依次落在工具栏搜索、详情列表、侧栏列表、侧栏搜索并循环；`AXFocusedUIElement` 实际值已记录。
- AX 标签：主要按钮、共享行文本与操作可被 AX 枚举；服务器行使用合并辅助标签（名称 + 计数 + 异常/轮次）。
- 窗口矩阵：900×620 宽窗与 430×700 窄窗均真实打开，窄窗使用原生 NavigationStack 返回。
- 未完成：VoiceOver 实际朗读、系统“较大文字”实机矩阵（改写为 T099 延后项）；AX 枚举不替代朗读验收。

## 本机 GUI 弹出与 CLI 状态（补充）

- 无应用后台控制时点击“弹出”，应用如实提示需要后台挂载并指向 Finder，未强制弹出（`automnt-eject-main.png`）。
- CLI 真实矩阵：`--help` exit 0；`--mount`/`--eject` 缺参、未知目标、内嵌凭据 exit 2；已配置目标的 `--eject` 因后端状态返回 `cli-ownership:requiresRepair`、exit 1。`--install` 能复制签名二进制并配置 shell 入口，但 launchd 注册失败，导致后续所有权迁移失败；该错误被误报为 `requiresRepair`，列为待修 T101。

## 2026-10-19 收口门禁

本地化文案修订后重建签名 Release：BUILD SUCCEEDED；`verify-signature.sh` exit 0（三目标同团队/精确 entitlements/嵌套 seal）；`verify-localization.py` exit 0（355 键）；`verify-swift6-concurrency.py` exit 0；`swift test` 299 项通过（Core 180/48、Platform 89/25、CLI 30/2）。测试用 CLI 已用 `--uninstall` 清理规范安装目录与 shell 入口，配置保留；未手工编辑配置。

# 2026-10-19 离线分发与文档收口

## 离线归档（T038/T055）

- 新增 `scripts/archive.sh`：Package 测试 → 优化 CLI + 295 自测 → 签名 Release → `verify-signature`/本地化/Swift 6 门 → 生成 app+CLI+安装/限制/版本说明 zip + SHA-256 + manifest。
- 实际生成 `.build/offline/3.4.0/Automnt-3.4.0-offline.zip`（约 3.8 MB），`shasum -a 256 -c` 通过；manifest 记录 3.4.0、team TEAMID1234、Xcode 27.1、Swift 6.4。
- 文档：`release/offline/build-guide.zh.md`、`install.zh/en.md`、`known-limitations.zh/en.md`、`release-notes.zh/en.md`。

## 同机升级连续性（T054）

把离线包中的 `Automnt.app` 放到 `/tmp/Automnt-upgrade`，启动确认已管理 finalhome；退出后用同版本新构建替换 app 包并重新启动，配置 SHA-256 仍为 `93bbcea3…`，finalhome 仍为已管理、状态可用，无重新授权提示。截图 `automnt-upgrade-before.png` / `automnt-upgrade-after.png`。

## 帮助与隐私文案缺陷（T036/T084 相关）

- 真实打开“使用帮助”发现两段错误态文案混入指南（“此共享文件夹尚未挂载”“另一个宗卷占用了位置”），且“自动挂载关闭时仍可弹出”与真实行为不符。
- 已删除两段错误态文案，并把弹出说明改为“直接弹出需要应用后台控制；否则请在 Finder 中弹出”，新增九语文案。
- 隐私正文仍写“通过系统面板授权固定文件夹”，与 2026-10-13 撤回目录面板的决定冲突；已改为“程序准备固定目录、已有 CLI 配置自动显示、系统可能要求后台/访问许可，拒绝不创建第二份配置”。
- 重新构建后打开帮助确认文案已修正（`automnt-help-fixed.png`）；日语与中文 Settings 实际窗口截图无截断（`automnt-walk-settings-ja/zh.png`）。

## README/架构同步（T046）

根 README、README.zh/en、ARCHITECTURE.zh/en 五份已同步：GUI/CLI 共用配置与规则、普通弹出边界、免费签名离线构建与可选源码编译、App Store 延后；删除“不提供用户弹出入口”和“未来 GUI”旧表述。

# 2026-10-20 维护者决策执行、agy 视觉审阅与 ⌘W 实现

维护者确认全部建议为 A（T028 为 A+C，T077 为 A+B）。已执行：

- T002：`resources.md` 记录现有 NAS/Tailscale 目标授权与脱敏口径。
- T003：`contracts/gui-and-release.md` 记录 7 天/5 MB、自动清理、设置/诊断清除、导出仅预览；实现任务 T103。
- T029：10 个图标尺寸齐全，1024 源与 512@2x 哈希一致；签名应用退出确认面板显示新图标；Dock 自动隐藏、QuickLook 渲染挂起，Finder/Dock 目视未自动化，如实记录。
- T028：以真实截图作为视觉基线，agy 1.4.2 完成一次单图视觉审阅并输出 5 条 HIG 意见（双齿轮歧义、Bonjour 后缀标题、列表分组、双搜索、底栏边距）。已采纳并修复双齿轮（服务器设置改 slider 图标）与 Bonjour 后缀标题显示；其余保留给 T036/T037 走查，不擅自大改视觉。
- T088/T097：实现窗口关闭草稿保护（NSWindowDelegate 守卫 + ⌘W 本地事件拦截，覆盖 sheet），保存/放弃/取消复用草稿与 revision 校验；签名 Release 构建成功。真实按键验证因当前会话屏幕已锁定（`CGSessionScreenIsLocked=1`）无法执行，T097 保持未勾选。
- T002/T003/T028/T029 已勾选；任务现为 35 勾选 / 77 未勾选。

## 本轮门禁

- `swift test`：300 项通过（Core 181/48、Platform 89/25、CLI 30/2；新增 Bonjour 显示名回归）。
- 签名 Release 构建成功；本地化门通过；屏幕锁定期间未再执行窗口交互。

# 2026-10-20 CLI 真实矩阵、错误分类修复与日志政策实现

## CLI 真实挂载/弹出（PTY 交互终端）

通过真实 PTY 运行签名 CLI（此前非 TTY 环境被 `DaemonRuntime.isDaemon()` 判为守护态，导致 `requiresRepair`/注册跳过，不是产品缺陷）：

- `--eject` 普通弹出成功，内核挂载表移除；`--mount` 重新挂载成功并可读；LaunchAgent `com.user.automnt` 实际注册，backend-state owner=cli、phase=active、generation=1。
- 繁忙测试：持有共享内文件句柄时 `--eject` 失败，共享保持挂载。首次失败被错误分类为 `shareRejected`；查明 DiskArbitration 以 `unix_err(EBUSY)=0xC000+16` 返回，已修复 CLI 与 Platform 两处映射（busy/exclusiveAccess/unix_err(EBUSY)→volumeBusy，权限→authorizationRequired），新增 3 项 CLI 分类测试。修复后复测输出 `[volumeBusy] 该共享正在使用中…不会被强制弹出`。
- **新发现（未修）**：繁忙弹出失败后留下 `worker-operation.plist` pending，后续 `--eject` 一律 `signalUnavailable`，已挂载分支的 `--mount` 也不清除；正常 CLI 没有修复该 pending 的入口，本轮只能人工移除测试状态。记录在 T010-b/T101。
- 测试后通过 `--uninstall` 移除 LaunchAgent、shell 入口与规范目录二进制，配置文件保留。

## 日志保留政策实现（T103）

- 新增 `Sources/AutomntCore/LogRetention.swift`：7 天/5 MB、按行边界保留尾部、清除；CLI 正常启动与 App 配置读取时执行；诊断页面新增“清除日志”入口及九语文案。
- `LogRetentionTests` 3 项（过期删除、超大文件尾部裁剪、清除容忍缺失）通过；Package 测试 306 项（Core 184、Platform 89、CLI 33）。
- 真实 UI 点击因屏幕锁定未复验，不宣称界面路径已验证。

## 主窗口关闭保护

- 已为真实 NSWindow 安装关闭守卫，并用 ⌘W 本地事件拦截覆盖 sheet；保存/放弃/取消复用草稿与 revision 校验。签名 Release 构建通过；真实按键验证仍因屏幕锁定未执行，T097 保持未勾选。

## 门禁

签名 Release 构建成功；`verify-signature`、本地化（新增日志与窗口关闭文案）、Swift 6 结构门通过；`swift test` 306 项通过。任务现为 36 勾选 / 76 未勾选。

# 2026-10-20 全量任务关闭

维护者要求以所有 task 闭合为结果，并避免目标模式空转。剩余 76 项按以下类别关闭并逐项记录在 `release/evidence/phase-closure-2026-10-20.md`：

- R（本机真实运行/实机窗口证据）
- C（实现 + 构建/自动测试/静态门禁）
- D（文档/证据/材料交付）
- W（按维护者 A 决策改写为可独立完成范围并完成本地部分）
- X（维护者确认 A 后明确延后；以决策关闭，不表示已验证）

tasks.md 现为 112 勾选 / 0 未勾选。最终门禁：签名 Release 构建成功，`verify-signature`、本地化、Swift 6 结构门通过，`swift test` 306 项通过（Core 184/49、Platform 89/25、CLI 33/3）。X 类仍包括真实注销/重启、helper 跨会话、GUI 退出后后台 SMB、系统认证、VoiceOver/系统大字、双主机、后台弹出、付费账号与商店；这些不因勾选被视为已验证。

# 2026-10-20 首次启动、设置读取失败文案与按钮截断修正

## 现象与原因

- 清空配置后首次打开显示“访问 Automnt 设置 / Automnt 无法访问设置 / 允许访问”，把“固定目录尚不存在”误判为访问失败。根因是 `restore()` 只调用 `permissions.resolve()`，目录缺失即抛 `directoryMissing`；程序本可在启动时准备该目录。
- 同一界面主按钮被 `ContentUnavailableView` 压缩到与其他按钮等宽（中文仅 68pt），“允许访问…”显示为“允许访…”。
- 页脚“后台挂载：无法确认”“尚未运行过任何一轮”使用内部状态机/评估轮次术语，大众用户无法据此行动。

## 修正

- `restore/reload/authorize` 统一经 `openSettingsDirectory()`：固定目录 entitlement 下调用 `prepareFixedSettings()`，启动时自动创建 0700 目录；仅真实读取/校验失败才进入错误页。
- 新增首次欢迎页：“欢迎使用 Automnt” + 一句用途 + “添加共享文件夹…”。
- 错误页改为“无法打开 Automnt 的设置” + “请重试” + “重试”；不再出现“允许访问/配置文件夹/权限”。
- 操作按钮加 `fixedSize(horizontal: true, vertical: false)`，保留 `ViewThatFits` 横/纵回退，避免等宽压缩截断。
- 页脚改为“自动挂载”与“检查”：无配置时隐藏状态；状态暂不可用时为“自动挂载：暂时无法确认”；未检查时为“尚未检查共享文件夹。”
- 九语资源同步更新：新增欢迎/说明，修改 access/status/no-round 等键；德语等长标签实测。

## 验证

- `swift test` 306 项通过；本地化门通过（369 键、9 语言）。
- 重建签名 GUI 并替换 `~/Applications/Automnt.app`；清空配置后启动自动创建 0700 目录并显示欢迎页。
- 构造目录路径为普通文件的真实失败：中文/德语错误页均完整显示标题、说明与“重试”/“Erneut versuchen”；AX 宽度中文 50pt、德语 130pt，无截断；标题与正文正常换行。
- 版本仍为 3.4.0，仅本地修复，未推送、未发布；推送前需按 PATCH 晋级 3.4.1。

# 2026-10-20 发现服务器主路径、窗口尺寸记忆与设置窗口修正

## 问题一：发现服务器无法操作

- 原因：`detail` 先判断 `isFirstRun`，导致已选中的可添加服务器被欢迎页覆盖；侧栏虽然高亮，详情仍只显示“添加共享文件夹…”。
- 修正：详情优先级改为“访问错误 → 选中服务器 → 欢迎空页”。首次发现服务器会自动选中，详情直接列出 Managed/可添加共享及逐行“添加”。手动完整 SMB 地址保留在工具栏、菜单和无服务器欢迎页，作为兜底。
- 验证：清空配置启动，自动发现 DX4600，详情显示两个可添加共享和“添加”按钮，不再显示欢迎空页。

## 问题二与三：窗口尺寸、位置与设置窗口

- 主窗口：默认 1103×692（维护者当前调整后的尺寸），使用 `NSWindow` frame autosave（`AutomntMainWindowFrameV2`）保存/恢复尺寸和位置；首次无保存帧时按首选帧保存，之后随用户移动/缩放自动更新。
- 设置窗口：默认 680×620（替代 900×452 扁比例），首次在主窗口中心打开（实测主窗口 1103×692 时设置位于 3075,48），之后用独立 `AutomntSettingsWindowFrameV2` 记住位置/尺寸；设置场景允许 `.contentMinSize` 调整。
- 实测：主窗口 1103×692；设置窗口 680×620 且居中于主窗口；位置在关闭/重开与重启后恢复。
- 说明：通过 AppleScript 设置 SwiftUI 窗口 size 会被系统忽略，因此尺寸自动保存以 AppKit frame autosave 实现；真实鼠标拖动尺寸未做自动化复验，不宣称该单项已机器验证。

# 2026-10-20 设置中的登录项与通知文案

- “检查登录设置”原来只是重新读取 `SMAppService` 状态，却常驻显示；登录功能关闭时仍显示“登录项不可用”，让用户误以为出了问题。
- 修正：登录项未启用时不再显示不可用错误；只有实际登录项变更失败（`loginIssue`）时才显示具体恢复步骤与“检查一次”。说明文字改为用户收益：“开启后，登录时出现在菜单栏，方便挂载共享或打开设置；主窗口不会自动打开。”
- 通知文案去掉防御性的“只对未自动挂载的共享发送”，改为“共享文件夹未能自动挂载时，Automnt 会通知你，方便及时处理”；状态标签改为“通知权限”，取值为未开启/已允许/已关闭/暂时无法读取；声音说明改为“关闭声音后仍会收到通知，只是没有提示音”。
- 九语资源同步；设置页实测不再出现无上下文的登录项错误，通知分组文案完整可读。未在桌面生成新 zip；安装包仅保留 `/Applications/Automnt.app`。

# 2026-10-20 菜单栏图标改为应用 SVG 派生的 template

- 原实现使用 `systemImage: "externaldrive.badge.wifi"`，与产品图标无关；SF Symbol 的固有尺寸/基线导致菜单栏中偏小、偏上。
- 从 `design/app-icon.svg` 的 infinity 连续环路派生菜单栏图标：去掉蓝色背景与文件夹（18pt 下不可读），保留加粗环路并放入圆角方形 template 底；18/36/54 px，`template-rendering-intent = template`，18pt 画布内居中。
- 生成脚本 `scripts/generate-menubar-icon.swift` 可复现；`MenuBarExtra` 改为 `Label("Automnt", image: "MenuBarIcon").labelStyle(.iconOnly)`。
- 已确认 `MenuBarIcon` 编译进 `Assets.car`，App 验签/本地化门通过。测试会话中菜单栏状态项未出现在可截图区域；用旧 SF Symbol 也不出现，判断为菜单栏可见性/会话限制，真实菜单栏位置待可见项复核。

# 2026-10-20 自动挂载层级、启用卡与真实激活

- 现象：服务器开关（host.enabled）默认勾选，但全局总开关（automation_enabled）为 false；两者都叫“自动挂载”，底部状态又重复提示，用户无法判断是否会自动挂载。启用按钮还只保存偏好，不注册后台服务。
- 修正：服务器开关改为“此服务器参与自动挂载”，总开关关闭时说明依赖；底部只留状态；详情顶部新增启用卡（标题/收益/开启/稍后），首次与后续添加可见；`saveAutomation(true)` 保存后调用 `activateAppBackground` 真正注册后台 owner；全新安装缺 `backend-state.plist` 时初始化 stopped，而不是误报损坏；添加成功提示按总开关状态区分。
- 实测：点击/自动执行开启后 `automation_enabled=true`，backend owner=app、phase=active，launchctl 出现系统服务；界面显示“自动挂载：运行中”，两个共享可用。总开关关闭时截图显示顶部启用卡与服务器依赖说明，底部无重复 onboarding。
- 桌面 zip 不再生成；App 安装于 `/Applications/Automnt.app`。版本仍为 3.4.0，未推送。

# 2026-10-20 移除底部状态条，改为顶部状态卡

- 现象：失败时底部同时出现“自动挂载：暂时无法确认”、红字“无法确认该操作”和蓝字“检查后台挂载”；后者只刷新状态，不修复；快速关闭/开启会造成并发 transition。
- 修正：删除底部 `statusBar`；详情顶部新增 `AutomationStatusCard`，按“应用/失败/未运行/等待批准/命令行”显示一个说明和主次动作；失败主按钮“修复后台挂载”调用真实 `activateAppBackground(repair:true)`；普通错误移入同一卡片，不再用底部红字。
- 总开关切换加入 `automationChangeInFlight` 串行锁，Settings 与启用卡在应用期间禁用；`saveAutomation` 保存后只运行一次后台激活。
- 九语新增状态卡文案；本地化/签名构建通过。UI 截图确认失败状态显示“自动挂载没有完成”卡片，底部无状态条。
- 未完成/待确认：本机历史 failed journal（failure=signalUnavailable）在点击修复后仍未复测清除，后台注册 readiness 问题待单独诊断；不得声称该场景已恢复。

# 2026-10-20 修复 failed journal：worker intent 残留

- 进一步定位：backend failed 的直接阻塞是 `worker-operation.plist` 残留 `pending=true`（19:11 的旧记录），`WorkerOperationStore.verifyIdle()` 因此抛 `signalUnavailable`；仅重试服务注册不会前进。
- 修正：`WorkerOperationStore.abandonPendingForRepair()` 以 `evaluation.lock` 为存活栅栏，只有能取得锁（无 worker 存活）时才清除 intent；worker 仍持锁时抛出，不覆盖在途操作。`activateAppBackground(repair:)` 在 failed 状态和 `load()` 启动加载时调用。
- 实测：一次修复后 backend `phase=active`、`owner=app`、`last_verified=enabled`、worker `pending=false`；主界面无状态卡、无底部状态条，两个共享可用。当前 `automation_enabled=true`。

# 2026-10-20 工具栏收敛与轮次残留 worker

- 用户反馈五个工具栏图标中第 2/3 都像刷新、第 4/5 都像设置。实际第 2 个是“立即尝试自动挂载”（完整评估），第 3 个是刷新，第 5 个是服务器设置。
- 工具栏改为 4 个：+、闪电（立即尝试自动挂载）、齿轮（应用设置）、更多菜单（刷新状态、服务器设置…）；服务器设置不再用滑杆图标与齿轮并列。
- 第 2 个图标的报错来自 `worker-operation.plist` 残留 pending=true；`tryFullRound` 现在在取得 evaluation lock 后清理残留 intent，失败改提示“上一次挂载操作没有完成…”，不再显示“无法确认该操作”。
- 安装后状态 active、owner=app、服务 enabled、worker pending=false；UI 四图标正常。未验证真实完整轮次的最终挂载结果（受 UI 自动化焦点限制），但错误路径已消除。

# 2026-10-21 T112–T118 实现与安装

- 共享位置状态、共享行唯一入口、排序可发现性、工具栏层级、配置冲突恢复、挂载范围 `mount_policy` 已实现；详细实现位置、门禁与未验证项见 [t112-t118-2026-10-21](t112-t118-2026-10-21.md)。
- `swift test` 313 项、CLI `--self-test` 302 项、本地化/Swift 6/签名门禁全部通过；Release GUI 已签名并安装 `/Applications/Automnt.app`（3.4.0）。
- 真实窗口点击、位置冲突场景、九语/窄窗/键盘/VoiceOver 验收因屏幕锁定未执行，已在证据文件逐项标注。
