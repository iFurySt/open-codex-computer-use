## [2026-10-05 13:43] | Task: 默认真实跨应用示例与简约配对布局

### 🤖 Execution Context
* **Agent ID**: `/root`
* **Base Model**: GPT-6 (Codex)
* **Runtime**: Codex desktop, macOS 26.5.1 / arm64

### 📥 User Query
> 先提交已有改动，此后每轮完成也本地提交。新会话默认提供 Calculator 计算并写入 TextEdit 的可运行 case；命令/格式化 JSON 左右配对，截图放在 UI Tree 右侧；参考 HeyYo Dictionary 改善侧栏折叠与工具栏。

### 🛠 Changes Overview
**Scope:** macOS workspace GUI / OpenComputerUseKit / production example runner

- 先在当前分支提交已有会话/多应用/notebook 实现（ee87a1d），不推送。
- 新会话提供六个可编辑单元：启动专属应用、检查 Calculator、计算 42 × 17、检查 TextEdit、写入实际读回的结果、检查最终文档。按 AX identifier 选择真实按钮，每次使用生产 snapshot/click；结果来自 Calculator UI，TextEdit 写入后严格核对 AX 内容。
- TextEdit 通过 new_document 可选参数后台打开专属临时文档，避免空启动只有文件选择面板。私有目录/文件权限、进程身份和恢复记录约束清理，应用拒绝退出则保留会话。
- 命令与结果横向配对，独立 JSON formatter 排除图片 base64，UI Tree 和 Screenshot 横向排列。
- 参考 HeyYo 的 detail NavigationStack，采用显式 sidebar visibility/native navigation item 和右侧 primary actions，避免自动 sidebar toggle 迁移；隐藏重复窗口标题并去除工具栏分隔线。
- 同步架构、GUI、权限/安全、质量记录和执行计划。

### 🧠 Design Intent (Why)
使用已有 Swift kernel/dispatcher，让 GUI 的可运行示例与直接代码验证共享真正的 AX/SCK 能力。示例命令是受约束的 notebook 编排，未引入 Jupyter/Node/shell 依赖或新增 MCP 工具。默认只验证 TextEdit UI，不增加未经验证的保存承诺。

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/VirtualDisplayWorkspace.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplayExample.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplayNotebookOutput.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplaySession.swift`
- `experiments/VirtualDisplay/Runner/Example.swift`
- `docs/exec-plans/active/20261005-ready-example-layout.md`

### Verification and limits

Swift 180 tests（1 opt-in 跳过）、Node 24 contracts、既有 smoke 通过。--example 真实 runner 验证六个单元、Calculator 714、TextEdit UI 内容、SCK 截图、前台 PID 保持、零 runner 全局输入、专属应用/临时文档/显示器清理。最终 release bundle/helper 签名验证通过。

TextEdit AX set_value 的内容可读回，但 Save 禁用，后台 Cmd-S 未保存；默认 case 不保存文件。测试时出现过桌面通知暂停和前台切换，失败按预期报告，稳定重跑通过，不能据此声明完整人工并行输入验收。

签名 GUI 已验证新会话默认单元、Run all 启动两个真实应用、配对 JSON/tree/image 输出。随后 Mac 锁屏，自动解锁失败，会话按预期暂停，测试会话已正常清理。最终显式工具栏编译/签名通过，折叠/展开的最终实机检查仍待手动解锁，执行计划保持 active；没有宣称该检查已完成。
