# 功能发布记录

## 2026-04

| 日期 | 功能域 | 用户价值 | 变更摘要 |
| --- | --- | --- | --- |
| 2026-04-20 | macOS 分发签名与公证 | `Open Computer Use` 的 release `.app` 和 `Cursor Motion` 的下载 `.dmg` 现在可以走更标准的 Apple 分发链路，首次下载运行时的系统信任体验更接近正式 macOS 软件。 | 发布 `0.1.17`，接通 `Developer ID Application` 证书导入、统一签名和 `Cursor Motion` 的 notarization / staple 流程；CI 已支持读取 GitHub secrets 自动完成签名与公证，README 也补了 `Cursor Motion` 的演示视频入口。 |
| 2026-04-20 | Open Computer Use 开发态身份 | 本地 debug/dev 调试构建不再和正式发布版在系统权限列表里混成同名对象，开发授权与正式分发边界更清楚。 | 发布 `0.1.16`，CI release 回退到原来的 ad-hoc 打包路径，不再要求 GitHub Actions 导入开发证书；本地非 release 构建统一改成 `Open Computer Use (Dev).app` 和 `com.ifuryst.opencomputeruse.dev`，权限发现也会在 dev 运行态优先绑定当前 dev app。 |
| 2026-04-20 | Open Computer Use 权限身份 | 从 npm、brew、DMG 或本地构建安装后，`Open Computer Use.app` 的权限身份现在更容易收口到同一条签名链，不会再默认把 npm 路径当成唯一稳定授权目标。 | 发布 `0.1.15`，给 `Open Computer Use.app` 的打包链路补上统一 codesign 入口，CI release 支持通过 GitHub Actions secrets 导入证书后统一签名；权限发现也改成按 bundle identity 搜索当前运行副本、`/Applications`、npm 和 Homebrew 安装位置。 |
| 2026-04-20 | Cursor Motion 打包一致性 | Releases 里的 `CursorMotion.dmg` 现在会和 `swift run CursorMotion` 更一致，不再因为缺少官方 cursor 资源而退回更锯齿、朝向也更差的 fallback glyph。 | 发布 `0.1.14`，修复打包 `.app` 时没有把官方 `official-software-cursor-window-252.png` 带进 bundle 的问题；`Cursor Motion` 现在会优先从 `Bundle.main` 读取这张图，DMG 打包脚本也会把它复制进 `Contents/Resources`，并显式打开高分屏渲染。 |
| 2026-04-20 | Cursor Motion 与发版链路 | Cursor Motion 作为独立 demo 的命名和入口更统一，同时 release tag 现在可以直接产出可下载的 macOS `.dmg`。 | 发布 `0.1.13`，把 `StandaloneCursorLab` 统一更名为 `Cursor Motion` / `CursorMotion`，同步中英文 README 与架构文档，并新增 tag 驱动的 `CursorMotion-<version>.dmg` GitHub Releases 发布链路。 |
| 2026-04-19 | 权限浮窗细节收口 | `Allow` 后的引导浮窗动效更连贯，且在系统设置窗口稳定后能自动落到正确位置，不需要用户手动点一下再归位。 | 发布 `0.1.12`，补齐权限 panel 的 source-to-target 入场动画、返回按钮，以及动画结束后的持续 re-anchor，修复 release workflow 因 npm 版本仍停在 `0.1.11` 而发布失败的问题。 |
| 2026-04-18 | 权限浮窗与文档入口 | 第一次冷启动系统设置时权限浮窗能直接出现，仓库根目录也重新补回中文文档入口。 | 发布 `0.1.11`，修复首次 `Allow` 冷启动 `System Settings` 时辅助浮窗需要切窗后才显示的时序问题，并新增根目录 `README.zh-CN.md` 承载中文说明。 |
| 2026-04-18 | 权限身份与 onboarding | npm 安装后的权限身份更稳定，已授权用户不会被重复弹窗打扰。 | 发布 `0.1.10`，统一 bundle identifier 为 `com.ifuryst.opencomputeruse`，让权限检测兼容路径型 TCC 记录并优先认 npm 全局安装后的 app；同时让 `doctor` / 默认启动在权限齐全时不再弹出 onboarding，完成授权后自动关窗。 |
| 2026-04-17 | 发布稳定性 | release workflow 不再因为 Xcode 26 的 CoreFoundation 类型检查而在构建阶段提前失败。 | 发布 `0.1.9`，修复权限引导窗口里 `AXUIElement` 属性读取在 `macos-26` / Xcode 26.2 下的编译错误，恢复 npm release artifact 构建链路。 |
| 2026-04-17 | 权限引导与安装 | 权限授权浮窗在 `Allow` 后不再掉到屏幕底部，且仓库继续提供稳定的一键安装/发布版本。 | 发布 `0.1.8`，收口 `System Settings` 跟随 panel 的定位修复，并同步更新插件、CLI、smoke/test 与发布文档中的版本号。 |
| 2026-04-08 | 模板仓库 | 提供了一套可直接用于新项目启动的 Agent-first 基础模板。 | 补齐了 AGENTS 入口、execution plan、history、release note、CI/CD 和供应链安全骨架。 |
| 2026-04-17 | 开源 computer-use | 提供了一版可本地运行、可回归验证的 Swift `computer-use` MCP server。 | 新增 Swift package、9 个 tools、fixture app、smoke suite、`doctor`/`snapshot` 诊断入口和对应架构文档。 |
