## 2026-10-05 18:38 | Task: 创建工作区的骨架屏与失败重试

### Execution Context
- Agent: `/root`，Codex desktop，macOS arm64。

### 用户诉求
- 创建后的 loading 图标与文案改为 skeleton；失败 toast 后回到创建弹窗。

### 改动与设计
- 会话与空屏共用 creation 状态；点击 Create 立即关闭弹窗，在主内容区展示原生灰阶预览占位，会话另含命令/结果占位。
- 创建状态下优先渲染 skeleton，避免旧会话 capture 查询竞争正在创建的 registry 锁；禁止后续 GUI 输入操作。
- 成功先同步资源与选择，再撤下 skeleton，直接衔接真实预览或空屏详情。
- 失败在 skeleton 上显示 2.5 秒 material toast，之后恢复对应弹窗，保留名称、display ID 和 scale 草稿；不留下创建错误的持久底栏。
- 移除两种创建弹窗原 loading；轻微透明度动画遵守减少动态效果设置，无逐帧计时器。
- 同步 FRONTEND。

### 验证
- swift test：193 项，1 跳过，0 失败。
- release 主 App 与 helper 构建、Developer ID 签名、deep/strict 校验通过。
- 正常退出无活动屏的旧 runtime，更新签名 bundle 并重启。
- Computer Use 真实点击 Create：AX 与截图确认弹窗消失、工作区 skeleton、创建相关操作禁用；随后真实会话 Ready、预览/Actions 出现，按钮恢复。
- 本轮仅一次真实会话创建，没有热插拔压力循环；该空测试会话保留供 GUI 查看，不借用或操作用户应用。
- 失败恢复分支已实现并检查草稿字段保留；本轮未人为撤销权限或破坏 helper 制造实机错误。

### 文件
- apps/OpenComputerUse/Sources/OpenComputerUse/VirtualDisplayWorkspace.swift
- docs/FRONTEND.md
