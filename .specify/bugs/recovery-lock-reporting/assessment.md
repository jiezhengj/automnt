# 诊断结论

- Slug: recovery-lock-reporting（无人值守自动生成）
- Created: 2026-10-07
- Source: feature 004 实机验收日志与源码
- Verdict: valid
- Severity: medium

# 症状与复现证据

健康卷被输出为“会话抑制中（尊重手动弹出）”。实机日志 `/tmp/automnt-004-suppression-completed-2.log` 显示全部四个卷抑制且跳过仍健康的 finalhome。精确受控复现应在隔离状态目录持有 `.mount-recovery.lock` 的排他锁，再运行恢复轮，确认不会调用恢复或改写状态。

# 代码路径与根因

automnt.swift 的 runRecoveryRound 在 open 或 flock 失败时将全部配置卷写入 outcome.suppressed；主评估随后将其解释为手动弹出的会话抑制。置信度高：直接由分支返回行为证明；实机当时是否确为锁竞争无法独立追溯。保守阻止基线挂载是合理的，但描述其原因为健康弹出不准确。

# 推荐修复

增加独立 deferredVolumeKeys 结果表示未执行评估的目标。两个锁失败分支只填 deferredVolumeKeys；主评估将其纳入禁止重复基线尝试及保护集，输出“恢复评估暂未执行（另一轮正在运行或状态锁不可用）”。手动菜单同样明确本次暂未执行而非显示 0/0/0 完成。保持实际会话抑制、通知预算、配置和状态格式不变。

添加受控持锁回归，证明 deferred 与 suppressed 分离、无可见兜底触发、无恢复调用、无状态写入；添加锁路径无法打开回归。生产安全方向保持禁止并发挂载；不引入等待或重试。

# 风险与待确认

主评估必须将 deferred 保留在基线保护集合，否则会绕开恢复锁执行挂载。两条新提示须中英一致。实机原记录只证明症状，不证明每轮均为锁竞争；本报告不据此宣称完整三轮验收通过。
