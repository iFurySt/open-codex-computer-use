## 2026-10-05 18:31 | Task: 统一创建会话的原生选择控件

### Execution Context
- Agent: `/root`，Codex desktop，macOS arm64。

### 用户诉求
- Display 与 Display scale 对齐；展开菜单参考 HeyYo Audio / Microphone，保持锚点并完整覆盖原点击框。
- 删除 Reuse 辅助说明；完成后提交并重启 App。

### 改动
- 将 SwiftUI Display Picker 与独立 scale bridge 收敛为同一个 NSPopUpButton bridge，两个 HStack 均为左标签、Spacer、右侧 230×34 points 控件。
- 沿用 HeyYo Microphone 的原生 large/rounded、selected-row popup、横向低 hugging/compression 设置。
- 菜单最小宽度额外包含勾选列空间，覆盖触发框右侧箭头；菜单按选中文字锚定，不撑开 sheet。
- 选项不变时不重建 NSMenu，避免工作区轮询打断已展开菜单；Coordinator 使用 MainActor。
- 移除创建会话的 Reuse/Applications 段落，同步 FRONTEND 文档。

### 验证
- release 主 App/helper 构建与 Developer ID 签名成功，deep/strict 签名验证通过。
- 安全退出旧 runtime、替换签名制品并重启最终版本；未强杀目标应用。
- Computer Use AX 与截图确认两行左右对齐、无 Reuse 段落；分别展开 Display 与 scale，确认菜单覆盖右侧箭头，scale 选到 2× 后 AX 值更新。
- 本轮属于控件布局调整，未新增实现镜像测试或执行显示器创建/销毁压力循环。

### 文件
- apps/OpenComputerUse/Sources/OpenComputerUse/VirtualDisplayWorkspace.swift
- docs/FRONTEND.md
