# 验证结果

- Slug: recovery-lock-reporting（沿用上下文）
- Tested: 2026-10-07
- Assessment: ./assessment.md
- Fix: ./fix.md
- Result: verified

# 已执行检查

优化构建退出 0；中英文自测各 250 passed / 0 skipped / 0 failed，含隔离持锁及锁路径不可打开原始分支复现。

最新产物使用固定 Apple Development 身份和 automnt 标识签名，经普通 --config 自搬迁替换；候选与当前指定要求一致，正式路径严格验证通过，业务配置 SHA 不变；两个共享盘健康探测均退出 0。签名部署目录 `/var/folders/fl/wy27csqx4s1dhlfvd9gts88c0000gn/T/automnt-004-lock-deploy-4xkpodhm`。

使用外部排他 flock 持有正式恢复锁，执行正式二进制中英文普通评估均退出 0，显示准确的恢复评估暂未执行提示，不出现 Session-suppressed / 会话抑制中；逐卷跳过并发挂载。再通过真实 PTY 菜单选择手动入口，出现 Remount deferred 而非 Remount finished，返回菜单 Esc 退出 0。锁自动释放；未改写业务恢复状态和配置，前后字节完全一致。

第一次菜单测试捕获正确 deferred 提示，但 PTY 结束时尚未等待进程退出，断言退出状态失败；第二次明确 wait 后全部通过，没有修改产品源码。

# 证据

- `/tmp/automnt-004-held-lock-zh.log`
- `/tmp/automnt-004-held-lock-en.log`
- `/tmp/automnt-004-held-lock-menu-verified.log`
- `/tmp/automnt-004-lock-{zh,en}.log`

# 残余边界与建议

关闭此提示缺陷。持锁期间只是有界暂缓恢复，未进行 NAS 故障或断网；此结果不完成 Feature 的三轮真实故障恢复、跨版本授权连续性或桌面通知显示验收。git diff --check 通过。
