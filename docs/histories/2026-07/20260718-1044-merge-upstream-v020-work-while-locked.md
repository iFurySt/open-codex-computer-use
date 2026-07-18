## [2026-07-18 10:44] | Task: 合并 upstream v0.2.0 并新增锁屏可选放行

### 🤖 Execution Context
* **Agent ID**: `/hvn:cortex --auto`
* **Base Model**: Claude Opus 4.8
* **Runtime**: Claude Code (background job)

### 📥 User Query
> 拉取 fork 源头 `iFurySt/open-codex-computer-use` 最新代码，对比 fork 与最新版差异，把我们开发的功能与其最新更新合并到 fork；再检查合并后 agent（Claude Code / Codex）能否在锁屏时继续操作电脑，若不能则开发该功能。

### 🛠 Changes Overview
**Scope:** 三方合并（本地 Stage Manager + origin 锁屏守卫 + upstream v0.2.0）+ `OpenComputerUseKit` 锁屏策略 + app-agent IPC 加固

**Key Actions:**
- **[三方合并]**: 合并 upstream v0.1.51→v0.2.0 全部 17 个提交（`text_limit` 破坏性改动、tree budget 参数、数字 `element_index`、Windows UTF-8、匿名 Web 点击保留）到含两套 fork 功能的分支；唯一语义冲突：upstream 新增 `WindowCaptureCandidate.isOnscreen`，修复 4 处测试构造。
- **[锁屏能力判定]**: 合并后锁屏守卫为 fail-closed，**阻止**全部工具——与目标相反。
- **[可选放行]**: 新增 `MacSessionLockPolicy`，`OPEN_COMPUTER_USE_ALLOW_LOCKED=1` 开启锁屏 best-effort 控制；默认仍 fail-closed。可行原因：所有 action 走 process-targeted 投递（AX / `postToPid`），不经全局 HID tap。锁屏时截图返回空图，优先用 `element_index` 定位。
- **[安全加固]**: 对抗式复审发现 confused-deputy——同 uid 未认证 socket 可 per-call 伪造该标志。改为仅经可信启动 env 传入并在 agent 侧剥离 per-call 该键。
- **[验证]**: +7 锁屏策略测试，共 172 测试全绿；full workspace build 通过；`make check-docs` 通过。

### 🧠 Design Intent (Why)
无人值守 agent 需要在锁屏时继续工作，但先前团队的 brainstorm 已论证「宣称 Lock Screen 支持」不可辩护，故守卫刻意 fail-closed。本次不推翻该决定：默认不变，仅提供显式 opt-in，并如实记录限制（截图不可用、coordinate-only 不可靠）与残余同 uid 信任边界。安全敏感开关只走启动 env，避免 per-call socket 伪造。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MacSessionGuard.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/RELIABILITY.md`
- `docs/SECURITY.md`
- `docs/histories/2026-07/20260718-1044-merge-upstream-v020-work-while-locked.md`
