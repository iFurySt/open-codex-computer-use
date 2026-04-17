# Codex Computer Use Reverse Engineering

这个目录用于持续沉淀官方闭源 `Codex Computer Use.app` 和 `SkyComputerUseClient` 的逆向分析结果，目标是为 `open-computer-use` 的开源实现提供可追溯输入，而不是把关键上下文留在聊天记录里。

## 当前文档

- `baseline-architecture.md`
  - 当前已确认的 bundle 结构、入口、标识、transport 和模块分层。
- `runtime-and-host-dependencies.md`
  - 当前已观察到的运行时行为、宿主依赖、Inspector 直连失败现象和共享状态线索。
- `packaging-and-lifecycle-integration.md`
  - 当前已确认的插件打包结构、主 app 分发形态、CLI surface、`turn-ended` 生命周期接入方式。
- `internal-ipc-surface.md`
  - 当前已确认的 client-service 内部 IPC 类型、sender authorization、skyshot 模型和 service 生命周期线索。
- `tool-call-samples-2026-04-17.md`
  - 2026-04-17 对 9 个公开 `computer-use` tools 的实测 request / response 样本。
- `software-cursor-overlay.md`
  - 对黄色虚拟鼠标 overlay 的资源、字符串和运行时窗口证据分析。
- `permission-onboarding.md`
  - 对 Accessibility / Screen Recording 权限引导和 System Settings accessory window 的分析。
- `assets/README.md`
  - 直接从官方 bundle 导出的可视资源归档，包括 `SoftwareCursor`、`HintArrow` 和 cursor icon 资产。

## 使用约定

- 优先写“已观察事实”，再写“推断”。
- 尽量注明证据来源，例如 bundle 文件、analytics、crash report、`strings`/`otool`/`codesign`。
- 如果后续结论推翻了旧判断，直接改文档，不保留过期说法。
