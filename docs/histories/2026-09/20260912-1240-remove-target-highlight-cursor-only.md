## [2026-09-12 12:40] | Task: 删除目标高亮特性，视觉对齐官方（只有软件光标 + click pulse）

### 🤖 Execution Context
* **Agent ID**: `session-fe09ecb5-988e-4679-aba5-333c4e21743e` (DSH subagent)
* **Base Model**: `deepseek-flash`
* **Runtime**: DeepSeek Harness Web GUI（委派子代理会话）

### 📥 User Query
> 让 OCU 的视觉**忠实对齐 Codex**：默认不再画“目标元素高亮环”，只保留软件光标（含雾状光晕）与点击脉冲。随后改派（用户裁定，优先级最高）：**彻底删除目标高亮特性，不要保留 `codex|plain` 开关——那属冗余代码**；删除该特性的文件、调用点、env 开关与诊断行；`debug-highlight` 改名 `debug-cursor`（只展示光标与点击脉冲）；光标行为与默认参数不得改变；文档同步到 fork 的 `skills/open-computer-use/SKILL.md` 与宿主副本；单屏 2 秒截图自证；原子提交 + push + 装机和回退命令。

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`（删除 TargetHighlight 三件套、Choreographer、Overlay、CLI）、`apps/OpenComputerUse`（CLI dispatch）、单元测试、`docs/`、`skills/open-computer-use/SKILL.md`。

**判定依据（不做冗余开关）**：官方 Codex Computer Use 的逆向文档与 binary 里没有“目标高亮”概念——全目录 `grep -in highlight` 零命中，运行时可视化只有 `Software Cursor`（126×126 画布、CursorView/SoftwareCursorStyle/FogCursorStyle、Bezier 移动、click pulse）。OCU 的 `TargetHighlightOverlay` 属本项目自建扩展，保留 `codex|plain` 两种样式对一个官方不存在的概念做开关，只会增加维护面。

**删除清单（物理删除，不保留死代码）**
- 源码：`TargetHighlightOverlay.swift`、`TargetHighlightLifetime.swift`、`TargetHighlightStyle.swift`。
- 编排：`VisualInteractionChoreographer` 去掉 `showTargetHighlight` 注入、`presentTargetHighlight` 与 `approach` 的 `record` / `snapshot` 形参；顺序收敛为“光标移动 → 到达节拍 → 调用方动作”，`scroll` / `perform_secondary_action` 的移动阶段不变。
- 调用点：`ComputerUseService.approachVisualTarget` 只接收 `VisualCursorTarget`；`SoftwareCursorOverlay.reset()` 去掉环清理调用。
- 开关与诊断：删除 `OPEN_COMPUTER_USE_TARGET_HIGHLIGHT_STYLE`、`OPEN_COMPUTER_USE_DEBUG_HIGHLIGHT` 与 `[open-computer-use] highlight ...` 诊断行。
- 入口：`debug-highlight` / `--debug-highlight` → `debug-cursor` / `--debug-cursor`（`VisualCursorDebugShowcase` 只画光标与脉冲，仍单屏、`--seconds` 上限 60s、`defer` 确定性收尾，打印 `screencapture -R` 矩形）。
- 测试：删除 `TargetHighlightStyleTests`（11）与 `DebugHighlightTests`（9，其中 2 个仅测环），`DebugHighlightTests` 改写为 `DebugCursorTests`（7）；`OpenComputerUseKitTests` 删除环 overlay / lifetime 断言（10），编排断言只保留 move / settle / reposition。

**不改的部分**：光标雾状光晕、Bezier 到位、click pulse、400ms 去抖合并、整轮常驻可见、单屏、`.floating` 层级与全部默认参数。

### 📁 Files Modified
- 删除：`TargetHighlightOverlay.swift`、`TargetHighlightLifetime.swift`、`TargetHighlightStyle.swift`、`TargetHighlightStyleTests.swift`、`DebugHighlightTests.swift`
- 修改：`VisualInteractionChoreographer.swift`、`ComputerUseService.swift`、`SoftwareCursorOverlay.swift`、`VisualCursorDebugShowcase.swift`、`OpenComputerUseCLI.swift`、`OpenComputerUseMain.swift`、`OpenComputerUseKitTests.swift`
- 新增：`DebugCursorTests.swift`
- 文档：`docs/ARCHITECTURE.md`、`docs/exec-plans/active/20260912-quiet-window-recovery-scroll-into-view.md`、`skills/open-computer-use/SKILL.md`（宿主副本 `~/.dsh/skills/open-computer-use/SKILL.md` 同步更新，不入库）

### ✅ Verification
- `swift build`：Build complete（0 error）。
- `swift test`：**222 tests / 1 skipped（live sky_click 默认 skip）/ 0 failures**；删除前 245，差值为本次删除的 23 个用例。
- `./scripts/check-docs.sh`：通过。
- 渲染自证：`./.build/debug/OpenComputerUse debug-cursor --seconds 2 --display 1` → 打印 `debug-cursor seconds=2.0 display=1 target=934,548,180,56 capture=874,488,300,176 screen=0,0,2048,1152`，2s 后确定性退出（exit=0）。截图 `tmp/ocu-cursor-only-c434426/cursor-only-crop.png`（裁切放大：深色箭头 + 雾状光晕，目标矩形内没有任何环）与 `full-screen-cursor-only.png`（整屏无环）。

### ⚠️ 未覆盖 / 风险
- 未做真实 GUI 端到端：不接受验收轮桌面操作，光标观感由调试入口 + 截图间接证明。
- 若未来有人重新引入“目标高亮”，`docs/ARCHITECTURE.md` 已写明这是官方不存在的概念且已删除，不要再加回来。
