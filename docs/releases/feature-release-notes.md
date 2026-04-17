# 功能发布记录

## 2026-04

| 日期 | 功能域 | 用户价值 | 变更摘要 |
| --- | --- | --- | --- |
| 2026-04-18 | 权限浮窗与文档入口 | 第一次冷启动系统设置时权限浮窗能直接出现，仓库根目录也重新补回中文文档入口。 | 发布 `0.1.11`，修复首次 `Allow` 冷启动 `System Settings` 时辅助浮窗需要切窗后才显示的时序问题，并新增根目录 `README.zh-CN.md` 承载中文说明。 |
| 2026-04-18 | 权限身份与 onboarding | npm 安装后的权限身份更稳定，已授权用户不会被重复弹窗打扰。 | 发布 `0.1.10`，统一 bundle identifier 为 `com.ifuryst.opencomputeruse`，让权限检测兼容路径型 TCC 记录并优先认 npm 全局安装后的 app；同时让 `doctor` / 默认启动在权限齐全时不再弹出 onboarding，完成授权后自动关窗。 |
| 2026-04-17 | 发布稳定性 | release workflow 不再因为 Xcode 26 的 CoreFoundation 类型检查而在构建阶段提前失败。 | 发布 `0.1.9`，修复权限引导窗口里 `AXUIElement` 属性读取在 `macos-26` / Xcode 26.2 下的编译错误，恢复 npm release artifact 构建链路。 |
| 2026-04-17 | 权限引导与安装 | 权限授权浮窗在 `Allow` 后不再掉到屏幕底部，且仓库继续提供稳定的一键安装/发布版本。 | 发布 `0.1.8`，收口 `System Settings` 跟随 panel 的定位修复，并同步更新插件、CLI、smoke/test 与发布文档中的版本号。 |
| 2026-04-08 | 模板仓库 | 提供了一套可直接用于新项目启动的 Agent-first 基础模板。 | 补齐了 AGENTS 入口、execution plan、history、release note、CI/CD 和供应链安全骨架。 |
| 2026-04-17 | 开源 computer-use | 提供了一版可本地运行、可回归验证的 Swift `computer-use` MCP server。 | 新增 Swift package、9 个 tools、fixture app、smoke suite、`doctor`/`snapshot` 诊断入口和对应架构文档。 |
