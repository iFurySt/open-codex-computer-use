## 2026-10-05 18:52 | Task: 精简会话标题与原生代码块

### Execution Context
- Agent: `/root`，Codex desktop，macOS arm64。

### 用户诉求
- 删除创建空屏说明，加强骨架呼吸；修复已有 Display 选择体验。
- 删除正文 Ready/session ID 行，顶部显示状态点和可复制 ID。
- Command/Result 使用代码块，调研可复用编辑器。

### 改动
- Display 菜单此前隐藏全部占用屏，而现场唯一 Display 属于现有会话；现改为显示全部资源，在线空闲屏可选择，占用/断开项标明原因并禁用，失效选择保留不可用项。不改变一屏一个活动会话的租用边界。
- 创建空屏移除说明，skeleton 灰阶提高并以 0.85 秒在 25%–100% 透明度呼吸，保留减少动态效果支持。
- 正文状态/ID 行删除，受管窗口 Target 菜单迁入 toolbar；标题左侧显示状态点，顶部 ID 悬停可复制，成功变勾 1.5 秒。ready/attached 绿、paused/待选择黄、未来 error/failed 红。
- 新增共享原生 NSTextView 代码块：命令可编辑与 undo、结果只读可选择、JSON token 高亮、双向滚动、语言栏和复制。禁用智能引号/替换，未变化文本不重写；大文本停止 token 高亮，避免过载。
- 调研 https://github.com/mchakravarty/CodeEditorView；该完整编辑器有更广能力，本任务采用小型原生封装，无新增依赖。
- FRONTEND 和 execution plan 同步。

### 验证与限制
- swift test：193 项、1 跳过、0 失败。
- release App/helper 构建、Developer ID 签名、deep/strict 校验通过。
- 正常退出旧 runtime 后更新签名制品并重启本仓库 App，没有强杀应用。
- 真实预热 API 返回一个在线空闲 Display，未挂会话；保留用于后续精确选择验收，没有重复热插拔循环。
- Computer Use 发现 Mac 锁屏且自动解锁失败；已请求手动解锁。标题布局、hover/复制反馈、手动选择及编辑/undo 实机验证仍待完成，相关 execution plan 保持 active，不宣称已通过。

### 文件
- apps/OpenComputerUse/Sources/OpenComputerUse/VirtualDisplayWorkspace.swift
- apps/OpenComputerUse/Sources/OpenComputerUse/WorkspaceCodeBlock.swift
- docs/FRONTEND.md

### 后续：普通文本标题与间距
- 用户反馈 Session 标题像一个胶囊按钮且名称/ID 间隔不清楚。实际是 macOS 26 的自动 toolbar glass 分组；对标题 item 使用 sharedBackgroundVisibility(.hidden)，旧版本走普通 toolbar fallback。
- 标题保留状态点与名称，名称/ID/copy 间隔 12 points，点与名称 8 points，左右各 4 points。名称组优先保留固有宽度，ID 可截断；仅 copy 是按钮，整体不增加点击行为。
- 同步 FRONTEND，release 主 App/helper 构建及 Developer ID/deep/strict 签名校验通过；正常清理旧 runtime 后重启并确认新 PID。本轮未追加显示器热插拔验证或实现镜像测试。
