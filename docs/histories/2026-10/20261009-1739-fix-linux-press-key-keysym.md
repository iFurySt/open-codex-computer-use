## [2026-10-09 17:39] | Task: Fix Linux press_key keysym synthesis

### 🤖 Execution Context
* **Agent ID**: `Claude Code`
* **Base Model**: `Claude Opus 5.5`
* **Runtime**: `T3 Code / Claude Code harness`

### 📥 User Query
> 在 Linux 上 `press_key` 发送的键不对（Enter 变成 `4`），确认原因并准备修复 Pull Request。

### 🛠 Changes Overview
**Scope:** Linux Computer Use runtime

**Key Actions:**
- **具名键改用 keysym 合成**: `send_key` 对 Enter、Tab、Escape、方向键等具名键使用 `KeySynthType.SYM`，不再把 keysym 当作 keycode 传给 `PRESSRELEASE`。
- **修饰键改用 modifier mask**: `ctrl` / `shift` / `alt` / `super` 通过 `LOCKMODIFIERS` / `UNLOCKMODIFIERS` 保持，组合键中的字符通过 `Gdk.unicode_to_keyval` 转为 keysym（`/`、`-`、`=` 等标点在 GDK 中没有同名 keysym 名称）；未知修饰键和返回 `VoidSymbol` 的未知键名直接报错，不再静默发送。
- **回归覆盖**: 新增不依赖真实桌面的 `send_key` Python 测试，并同步 Linux 架构说明与功能发布记录。

### 🧠 Design Intent (Why)
`Atspi.generate_keyboard_event` 在 `PRESS` / `RELEASE` / `PRESSRELEASE` 模式下只接受硬件 keycode。原实现传入 `Gdk.keyval_from_name` 返回的 keysym，AT-SPI 取其低字节当作 keycode：Return（0xFF0D）变成 keycode 13，即美式键盘的 `4`；Control_L（0xFFE3）变成未映射的 keycode 227，因此快捷键缺少修饰键。`SYM` 模式接受 keysym 并完成按下与抬起，modifier mask 则由 AT-SPI 负责锁定与释放。在 Ubuntu 26.04、X11、Google Chrome 中用 keydown 记录验证：Return、Tab、Escape、Down、Page_Down、Left、BackSpace、`ctrl+a`、`shift+Left`、`shift+Home`、`alt+Left`、`ctrl+/`、`ctrl+-`、`ctrl+=`、`ctrl+,` 均送达正确按键。

### 📁 Files Modified
- `apps/OpenComputerUseLinux/runtime.py`
- `apps/OpenComputerUseLinux/runtime_test.py`
- `docs/ARCHITECTURE.md`
- `docs/releases/feature-release-notes.md`
