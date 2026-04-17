# 稳定性与可运维性

## 当前最低验证线

- 构建：`swift build`
- 单元测试：`swift test`
- 端到端 smoke：`./scripts/run-tool-smoke-tests.sh`
- 本地诊断：
  - `.build/debug/OpenComputerUse doctor`
  - `.build/debug/OpenComputerUse snapshot <app>`

## 已知关键依赖

- 宿主必须有 `Accessibility` 与 `Screen Recording` 权限。
- smoke suite 依赖本地 GUI session，不能把它当成无头环境命令。
- 普通 app 的 `get_app_state` 结果依赖 AX tree 和窗口截图，复杂 app 上输出会有差异。

## 当前故障排查顺序

1. 先跑 `.build/debug/OpenComputerUse doctor`，确认权限状态。
2. 用 `.build/debug/OpenComputerUse list-apps` 确认目标 app 是否被发现。
3. 用 `.build/debug/OpenComputerUse snapshot <app>` 看是 transport 问题还是 snapshot / action 问题。
4. 如果只想验证仓库基线，直接跑 fixture + smoke，不要先在复杂第三方 app 上排查。

## 后续补强方向

- 增加结构化日志和失败原因分类。
- 对 screenshot capture / AX traversal 增加更明确的 timeout 和 fallback。
- 增加普通 app 回归样本，而不是只覆盖 fixture。

CI/CD 流程结构和 release 自动化的默认方案，统一写在 `docs/CICD.md`。
