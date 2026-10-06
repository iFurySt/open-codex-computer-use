# 技术债追踪

这里记录那些暂时不阻塞当前任务、但已经值得留档的技术债。

| 日期 | 区域 | 债务描述 | 为什么会存在 | 计划中的后续动作 |
| --- | --- | --- | --- | --- |
| 2026-04-17 | 普通 app AX snapshot | Finder 路径已经能拿到前台窗口子树并输出 window-relative frame，但当前还缺更多真实 app 回归样本，无法证明这套 rooting / traversal 对复杂 app 都稳定。 | 这一轮先把 Finder 这类真实 app 的坐标换算和窗口子树收敛好，再把 deterministic 回归继续留给 fixture。 | 增加 Safari / System Settings / Activity Monitor 等真实 app 样本验证，并继续收敛 `kAXMainWindowAttribute`、focused element parent chain 和多窗口回退策略。 |
| 2026-10-05 | macOS 电源保活 | helper 自身 SIGKILL 后 launchd/journal 恢复、电源插拔、功耗及企业设备兼容性仍缺真实证据。 | 当前已验证协调器崩溃恢复及本机 30 秒物理合盖 AX/SCK，不能替代 root helper 崩溃或跨电源/设备测试。 | 补受控 root helper 崩溃测试、电池/AC 切换及功耗采样，并独立验收 Locked Use 联合模式；见 [电源计划](completed/20261005-macos-power-hold.md)。 |
| 2026-10-06 | macOS AX diff | 真实商业应用连续轨迹与相同模型成功率对照尚未验收。 | real AppKit AX/SCK、点击/中文输入增量、隐藏基线、稳定引用及完整恢复已通过，三次计数器观察文本 token 减少 56.97%；不代表商业应用兼容性或模型成功率。 | 录制 Calculator/TextEdit/Finder/Electron 脱敏轨迹并比较 full/auto 的成功率与错误目标次数；见 [AX diff 计划](completed/20261006-macos-ax-diff.md)。 |
