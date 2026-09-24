# 收敛 PR #65 后台操作能力

## 目标

把 PR #65 的后台键盘、跨 Space snapshot 与 agent display 能力同步到最新 `main`，修复评审发现的生命周期、恢复目标、MCP annotation、默认 JS REPL 接入和私有 API 兼容性问题，并形成可验证、可继续评审的提交。

## 范围

- 包含：合并最新 `main`、后台状态清理、按 app 恢复 parked windows、JS REPL 参数透传、私有 virtual display shim fail-closed、测试与文档。
- 不包含：改变 `sky_click` / `sky_key` 的底层事件 recipe、运行会干扰当前桌面的 opt-in live tests、直接合并 PR。

## 背景

- 相关文档：`docs/RELIABILITY.md`、`docs/SECURITY.md`、`docs/references/background-input-benchmarks.md`。
- 相关代码路径：`packages/OpenComputerUseKit/`、`apps/OpenComputerUse/`、`scripts/node-repl/`。
- 已知约束：macOS app agent 会跨前台 CLI/MCP 连接驻留；默认 Codex plugin 只暴露 JS REPL；SkyLight 和 CGVirtualDisplay 均为私有 API。

## 风险

- 风险：连接结束后窗口仍停在虚拟显示器，或 occlusion notifications 未恢复。
- 缓解方式：在 app-agent connection 和 turn boundary 显式清理，并补生命周期测试。
- 风险：静态 `readOnlyHint` 与可变窗口状态不一致。
- 缓解方式：将 macOS `get_app_state` 标为非只读并同步测试。
- 风险：私有 Objective-C API 变化抛出异常导致进程退出。
- 缓解方式：在 shim 内捕获 Objective-C exception 并返回不可用结果。

## 里程碑

1. 合并最新 `main` 并解决文档与许可冲突。
2. 修复 lifecycle、restore、annotation 和 JS REPL 集成。
3. 补齐测试与文档，运行仓库验证后推送 PR head。

## 验证方式

- `swift test`
- `node --test scripts/node-repl/*.test.mjs`
- `(cd apps/OpenComputerUseWindows && go test ./...)`
- `(cd apps/OpenComputerUseLinux && go test ./...)`
- `./scripts/run-tool-smoke-tests.sh`
- `./scripts/check-docs.sh`

## 进度记录

- [x] 完成代码审查并确认阻塞项。
- [x] 合并最新 `main`，保留新增 derived implementation 对应的许可声明。
- [x] 完成实现与测试。
- [x] 完成验证、history 与待推送提交。

## 决策记录

- 2026-09-24：采用 merge commit 同步 `main`，避免改写贡献者已有提交历史。
- 2026-09-24：保留 `THIRD_PARTY_NOTICES.md`，因为 PR 明确包含 derived implementation，不能在冲突解决时静默丢弃许可文本。
- 2026-09-24：不运行 opt-in GUI live tests；它们会切换窗口/Space 或注入真实输入，需要单独安排无人使用桌面的验证窗口。
- 2026-09-24：一过性的 CLI connection 会在关闭时清理 background state；需要连续 park/action/restore 时使用同一个 JS、REPL、MCP 或 `call --calls` session。
- 2026-09-24：无侵入验证完成；Node 全套唯一失败是最新 `main` 已复现的 Worker late-error timing case，不归因于本次改动。
- 2026-09-24：实现与文档收敛为 maintainer commit `f97e890`；plan 随完成记录归档，推送后由 PR 继续承载 review 状态。
