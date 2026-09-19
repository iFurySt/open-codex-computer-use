## [2026-09-19 10:45] | Task: CLI 参数别名容错、大图解耦瘦身与语义化点击支持

### 🤖 Execution Context
* **Agent ID**: `Antigravity`
* **Base Model**: `Gemini 3.8 Flash (High)`
* **Runtime**: `macOS 27.0 arm64`

### 📥 User Query
> 针对调用 Apple Music 过程中的实际痛点进行优化：解决参数命名漂移报错、巨幅 Base64 截图污染终端输出与 Token 爆炸问题，并增强语义化点击能力。

### 🛠 Changes Overview
**Scope:** `scripts/npm/build-packages.mjs` (CLI launcher template), `skills/open-computer-use/SKILL.md`, `skills/open-computer-use/references/usage.md`, `docs/releases/feature-release-notes.md`

**Key Actions:**
- **参数别名标准化**: 在 launcher 中增加 `normalizeToolArgs`，自动将常见别名如 `index -> element_index`、`button -> mouse_button`、`amount -> pages`、`start/end -> from/to` 标准化，避免 Agent 因 API drift 报错。
- **截图瘦身解耦**: 默认将 `get_app_state`、`click` 及 `--calls` 输出中的多兆 Base64 图片保存至 `/tmp/ocu_last_screenshot.png`，在标准输出返回轻量引用；提供 `--raw-image` / `OCU_RAW_IMAGE=1` 显式保留原始格式。
- **语义化快速点击**: 支持在 `click` 参数中传入 `text` / `title` 及可选 `role`，通过启发式角色评分算法自动定位目标元素索引并执行点击。
- **文档与用例对齐**: 同步更新 `SKILL.md` 和 `usage.md`，补全常见 CLI 调用示例与参数规范说明。

### 🧠 Design Intent (Why)
*AI Agent 在进行 ReAct 循环交互时极易因文档与底层参数偏差（如 index vs element_index）导致单步中断，且数兆的 Base64 终端输出会造成管道阻塞与严重的 Token 浪费。通过在跨平台 CLI 启动包装层注入透明的中间件处理，既保障了 100% 向下兼容，又极大提升了所有 LLM Agent 在消费 Open Computer Use 时的易用性与稳定性。*

### 📁 Files Modified
- `scripts/npm/build-packages.mjs`
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/usage.md`
- `docs/releases/feature-release-notes.md`
