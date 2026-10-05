## 2026-10-05 | Task: 分组完整 hover 热区与空会话自动 ready

### Execution Context
- Agent: Codex /root，macOS 本地工作区。

### 用户诉求与改动
标题增加上下内间距，移动到右侧 + 不失去 hover；新建 session 不需再点开始。标题按钮内 padding 8 points，右侧 + 固定 28×38 points，HStack 全宽 contentShape 统一 hover，保留少量分组间距。新建无受管应用的空会话不因创建前台/Dock 观察变化暂停；Space 通知只暂停有受管 PID 的会话。锁屏/睡眠等事件继续暂停全部，布局/权限/捕获及应用身份冲突检查不放宽。

### 设计与验证
避免 GUI 创建后盲目 resume，直接纠正空会话生命周期判断；Dock 仍保留 diagnostics，不声称问题已消除。Swift 回归覆盖空会话正常启动、布局异常，以及 Space 与睡眠/锁屏事件的分层暂停。签名构建与验证；不创建/销毁虚拟屏或重启用户会话，真实 hover 连续移动待更新版确认。

### 主要文件
- apps/OpenComputerUse/Sources/OpenComputerUse/VirtualDisplayWorkspace.swift
- packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplaySession.swift
- packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/VirtualDisplayTests.swift

最终验证：Swift 193 tests（1 opt-in skip）通过，release/helper 签名构建及 strict/deep 校验通过，本地 dist 已更新；未重启已有会话。
