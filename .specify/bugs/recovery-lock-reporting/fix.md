# 修复结果

- Slug: recovery-lock-reporting（沿用上下文）
- Fixed: 2026-10-07
- Assessment: ./assessment.md
- Status: applied

# 变更

修改 automnt.swift，增加 deferredVolumeKeys，锁无法打开或正被持有时返回暂未评估结果，不再伪报手动弹出抑制。主评估仍阻止这些目标进入基线挂载，逐卷输出跳过并发挂载。手动菜单明确评估暂未执行。真实抑制、状态格式、预算和通知契约未变。

# 本地验证

隔离自测新增三项：持锁结果单独分类；无恢复调用、通知或状态写入；锁路径为目录无法打开时仍保守跳过。优化重建退出 0，中英文自测各 250 passed / 0 skipped / 0 failed。git diff --check 通过。

# 偏差与后续

没有扩展修复范围。最终产物尚未稳定签名部署；需要 bug-test 重做持锁原始复现并验证实际终端及菜单提示，再记录正式部署。测试通过不等同真实 NAS 故障验收。
