## 2026-10-05 | Task: 明确启动实例所有权与窗口授权

### Execution Context
- Agent: Codex /root，macOS 本地工作区。

### 用户诉求
按讨论结论区分 launch/adopt，App/PID 不授权全部窗口，提供查询候选与精确窗口原子能力，GUI 选择进程/窗口，保持后台边界。

### 改动与设计
新增 get_app_candidates 和 Swift/JS 只读查询，返回全部匹配 PID/window。launch 默认只持有验证过的新实例，隐藏并返回候选窗口，明确 window_id 后才移动；manage_all_windows=true 才授权专属初始窗口，示例/runner 显式 opt in。adopt app 可省略，仅 PID/window 控制范围，既有 owned 身份不因逐窗口授权变成 borrowed。未知新专属窗口和 modal 暂停，borrowed 普通其他窗口不动。暂停后授权仍检查身份/物理布局并保持暂停输入。恢复基线在移动失败重试时不覆盖。

GUI 拆分 App/PID/window 选择，Launch 后保留 sheet 进入明确窗口选择，不选首个 PID/window。返回旧 PID 为结构化 error+candidates，不 hide/接管旧实例。专属 hide 前检查 PID 新增、bundle 和出生时间；早期注册 AXWindowCreated 通知（不支持则轮询）。Chrome 专属 profile 附带实际虚拟屏初始位置；不承诺零闪现。

### 验证与限制
完整 Swift 191 tests（1 opt-in skip）和 Node 27 tests 通过，包含真实运行进程的只读候选查询（AX 窗口依赖测试进程权限）；release/helper 签名构建与 strict/deep 校验。没有新建显示器或强制退出现有 GUI/应用。两阶段真实窗口移动/恢复、通知 containment 与零闪现不能由策略单测证明，已记质量/可靠性待验收。

### 主要文件
- packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplaySession.swift
- packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift
- apps/OpenComputerUse/Sources/OpenComputerUse/VirtualDisplayWorkspace.swift
- scripts/node-repl/open-computer-use-repl.mjs
