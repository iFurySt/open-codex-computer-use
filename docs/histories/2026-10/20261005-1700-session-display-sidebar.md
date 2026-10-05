## 2026-10-05 | Task: Sessions / Displays 侧栏与资源删除

### Execution Context
- Agent: Codex /root，macOS 本地工作区。

### 用户诉求与改动
侧栏提供两个独立折叠分组，hover 显示创建/删除控件；保留原生 toolbar。显示器资源支持 typed 查询、精确租用及串行级联删除，session 默认删除保留屏，可显式删除屏。新增 delete_virtual_display、create display_id 与 JS 接口；清理失败保留未完成状态。

### 验证与边界
Swift 184 tests（1 skip）、Node 26 tests、真实签名 runtime 两轮复用与级联删除通过，GUI 分组折叠检查与签名构建通过。当前每显示器最多一个活动 session，多 app 仍支持；删除不承诺回滚。系统卡顿排查启动后暂停更多 hotplug 回归，hover 视觉仍待人工复核。

### 主要文件
- apps/OpenComputerUse/Sources/OpenComputerUse/VirtualDisplayWorkspace.swift
- packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplaySession.swift
- scripts/node-repl/open-computer-use-repl.mjs
