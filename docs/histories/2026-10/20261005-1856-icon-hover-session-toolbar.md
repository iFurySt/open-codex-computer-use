## 2026-10-05 18:56 | Task: 图标 hover 与会话专属操作组

### Execution Context
- Agent: `/root`，Codex desktop，macOS arm64。

### 用户诉求
- +、删除、copy 等图标 hover 时加深，反馈明确；右上角操作只在选中会话时出现。

### 改动
- 新增共享 WorkspaceIconButtonStyle，应用侧栏 +/折叠/trash、Session/代码块 copy、cell play/trash：默认灰，hover primary 深色与浅灰圆角底，pressed 更深，disabled 无 hover 高亮。
- 保持图标尺寸、预留槽和父行完整 hover 热区，复制成功绿色勾继续显示。
- 右上角整组以 session 选择、selectedDisplay=nil、非创建状态为条件，空页/Display/骨架页完全隐藏，系统 toolbar 按钮保持原生反馈。
- 同步 FRONTEND 和前一轮 active plan 的解锁/验证状态。

### 验证
- release 主 App/helper 构建、Developer ID 签名与 deep/strict 校验成功。
- 正常退出旧 runtime 并完成显示器清理，替换签名制品后重启 App，没有强杀目标应用。
- Computer Use AX 实机确认空工作区 toolbar 只有 New Session / Hide Sidebar，右上角操作组已移除。
- 本轮为低影响视觉调整，使用编译和实际 AX 验证，未新增实现镜像测试或热插拔压力循环。hover 色彩和占用 Display 分支已代码检查，未通过自动鼠标移动模拟 hover。

### 文件
- apps/OpenComputerUse/Sources/OpenComputerUse/WorkspaceIconButtonStyle.swift
- apps/OpenComputerUse/Sources/OpenComputerUse/WorkspaceCodeBlock.swift
- apps/OpenComputerUse/Sources/OpenComputerUse/VirtualDisplayWorkspace.swift
- docs/FRONTEND.md

### 后续修正：只改变符号颜色
- 用户指出分组标题 hover 的大面积圆角背景不符合要求；移除共享图标样式的全部背景，仅保留符号从 secondary 到 primary 的色彩变化。
- 分组标题恢复 plain 样式，保持标题、箭头与 + 的完整热区和展开逻辑；资源行原有选择样式不改。
- 更新 FRONTEND；release App/helper 构建与签名校验通过，正常退出后重启并通过 agentInfo 确认新 runtime。没有新增热插拔测试或实现镜像测试。
