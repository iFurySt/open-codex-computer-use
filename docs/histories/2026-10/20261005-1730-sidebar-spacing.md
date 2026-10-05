## 2026-10-05 | Task: 统一侧栏间距和资源层级

### Execution Context
- Agent: Codex /root，macOS 本地工作区。

### 用户诉求
以 session 选中框的左右间距统一 sidebar，Logo 同边界；Sessions/Displays 内项目内缩体现层级。

### 改动与设计
统一 WorkspaceSidebarLayout：List scroll content 和品牌共用 10 points 外边距，分组不再额外叠加 12 points；两类资源统一 row insets，并加 12 points 内容缩进。右侧按钮内边距一致，原生选中背景保持外边界。toolbar、折叠动画和会话生命周期保持现有实现。

### 验证
release 签名 App 构建与签名验证；纯间距改动不新增镜像实现的测试。不创建/销毁虚拟屏进行 UI 验证，避免影响当前会话及桌面稳定性；实机最终视觉待重开更新版确认。

### 主要文件
- apps/OpenComputerUse/Sources/OpenComputerUse/VirtualDisplayWorkspace.swift
- docs/FRONTEND.md
