# 背景

维护者 2026-10-24 深夜把两项遗留裁定交给 Lead 与 agy 共同决定：“未应用的九语人称/术语统一是否照改”，以及“是否单独开一项‘采用动态字体（系统较大文字）’的改进”。本记录保存讨论依据、结论与执行边界。

# 依据：agy 建议与本机实测修正

agy 对 460 条 × 9 语给出可执行建议（完整意见见 `evidence/2026-10-24/copy-decisions-round8b.txt`）。其中两处与 Apple 实际本地化不符，以本机系统自带资源为准修正：

- agy 建议德语统一为 Sie。实测 macOS 27 德语系统设置辅助功能页原文为“Personalisiere den Mac so, wie es für dich am besten funktioniert …”，登录项扩展用“Erlaube die Verwendung von Befehlszeilen-Werkzeugen …”。Apple 德语使用 du。因此**目标语气是 du**，agy 的 Sie 目标被否决。
- agy 的法语 „Ouverture“、西语 „Ítems de inicio“ 与系统一致。`LoginItems.appex` 本地化表：fr “Login Items & Extensions”=>“Ouverture et extensions”；es=>“Ítems de inicio y extensiones”；de=>“Anmeldeobjekte & Erweiterungen”。采纳为登录项面板与条目名称。

# 决定一：应用机械且语义安全的统一，语气重写留作润色项

已应用 63 处值修正到 `apps/Automnt/Resources/Localizable.xcstrings`，不新增 key、不改代码与布局：

- 德语术语：共享文件夹统一为 freigegeben（保留动词 “Wird mit dem Befehlszeilenwerkzeug geteilt.”），挂载统一为 einbinden（“Mounten”=>“Einbinden”、“gemountet”=>“eingebunden”），命令行为 Befehlszeile；删除共享文件夹确认标题同步为 “Freigegebenen Ordner entfernen?”。
- 巴西葡语：Definições=>Ajustes；登录动作 entrar na sessão=>iniciar a sessão（其中一句改为 “precisa iniciar junto com a sessão” 避免重复）。
- 日语：独立名词 アプリ=>App（保留「アプリケーション」文件夹）；网络重连 復元=>復旧（保留安装包资源“同梱リソースを復元”）。
- 韩语：하십시오=>하세요（10 处）；详情动作统一 세부사항。
- 繁体中文：資料夾=>檔案夾；恢复存取 恢復=>回復（Apple 繁中系统用语）。
- 法语/西语：登录项名称统一为 Apple 面板词 « Ouverture »、«Ítems de inicio»；条目名称同步。
- 大小写重复 key 的译文漂移（Open Login Items settings 等 4 组）镜像为标题大小写 key 的现值；“检查登录设置”两个 key 的 fr/es/pt-BR 统一。

未应用：

- 德语 du/Sie 语气全量统一。目标已确定为 du，但约 60 条字符串含敬语动词与所有格（Wählen Sie、Geben Sie、Erlauben Sie、Ihre …），属于需要逐句重写的语言编辑工作，不能字符串机械替换。记录为遗留润色项，不新增 Feature 任务，避免在验收轮引入未复核的大面积语法改动。
- 简体中文 App/应用。23 处“应用”里多为动词“应用更改”与既有术语“应用控制/应用后台挂载”，逐条核对后不改。

# 决定二：动态字体不单开任务，记为平台限制

实测：系统设置 > 无障碍 > 显示 > 文字大小滑块（0–14，默认 4）从 4 调到 6 并重启 App，Automnt 文字无变化；该面板“支持的 App”不包含 Automnt。未找到第三方原生 App 注册进该面板的公开入口（未验证 Apple 是否有限开放）。

结论：**不单开 Feature 任务**，理由：

- 无法让系统面板对本 App 生效；应用内自建字号缩放只覆盖 App 内，与系统辅助功能入口脱节，用户仍看不到系统级效果。
- 对九语长译文与窄窗布局是高破坏风险改动，需要独立设计、逐语复验与回归，不适合塞进 Feature 005 收尾。
- 系统已有可用替代：显示器“较大文字”缩放（1024×666 实测布局可读，已还原 1470×956）与系统缩放。

处理：写入 `release/offline/known-limitations.zh.md`/`.en.md` 与 `spec.md` 第八轮小节，作为已知限制与未来改进候选，不标成已支持。

# 验证

- 本地化门禁 `verify-localization.py` exit 0（267 条源字符串 × 9 语言）。
- 重建并安装 `/Applications/Automnt.app`，`verify-signature.sh` 5 项 PASS。
- 真机抽查：德语 “Automatisches Einbinden”“Freigegebenen Ordner hinzufügen…”；日语 “自動マウントと自動復旧が実行中です。”；巴西葡语 “Ajustes de Automnt”“Ao iniciar a sessão…”。

# 第十轮修订（2026-10-24 深夜，维护者确认）

- 德语 du 统一已完成：agy 对 67 条含敬称文案逐条改写，本机校验 key 与占位符后应用 65 条；剩余 3 处 Sie 为第三人称指代（die Adresse、die Reihenfolge、die Einstellungen），不是敬称。依据 Apple 德语系统设置原文“Personalisiere den Mac so, wie es für dich am besten funktioniert …”。真机德语设置页不再出现 Sie 形式（“Automnt bei der Anmeldung öffnen”“Versuche pro Prüfung”）。
- 动态字体不再作为需求：维护者确认“那就不再支持这个需求好了”。因此本项目明确不采用动态字体，不列为改进项，也不以修改显示器分辨率等方式代替；known-limitations 与 spec.md 按“已记录边界、非已支持”表述。
- 完成收口：T133 按维护者批准的等价标准（真实重启 + 端到端通知 + 运行期界面 + 注销等价证据 + 单 owner）改为通过并勾选；T134 文档收敛并勾选；spec.md 增加“完成结论（2026-10-24，第十轮）”，保留真实注销/登录与动态字体两项边界，以及商店/发布未授权项。
