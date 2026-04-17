## [2026-04-17 23:50] | Task: 修复权限拖拽面板被系统设置窗口遮挡

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> 权限引导里的拖拽提示条还被 `System Settings` 窗口盖住；需要确保它显示在系统设置窗口上面。

### 🛠 Changes Overview
**Scope:** `apps/OpenComputerUse`, `docs/`

**Key Actions:**
- **[Window Ordering]**: 给权限辅助 panel 改成 `.floating` 层级，并在显示时显式 `order(.above, relativeTo:)` 到当前 `System Settings` 主窗口之上。
- **[Window Targeting]**: 从 `CGWindowList` 里同时读取 `System Settings` 的 bounds 和 `windowNumber`，让定位逻辑和排序逻辑都基于同一个真实窗口上下文。
- **[AX Polling Tuning]**: 把 controls row 的 AX 扫描改成低频缓存，只在滚动/拖动时强制刷新，避免高频遍历 `System Settings` AX 树引发左侧滚动条反复抽动。
- **[Anchor Clamp & Reorder Debounce]**: 只有在目标 `System Settings` 窗口编号变化时才重新 `order(.above)`，并给 controls row 跟随加了向上抬升上限；滚到中段后不再把提示条带到列表中间，而是回退到窗口底边附近。
- **[Remove AX Anchor Scanning]**: 最终移除了对 `System Settings` 内部 `+ / -` 控件行的定时/事件驱动 AX 探测，辅助条改为仅根据窗口 bounds 固定贴底，彻底切断对系统设置 UI 树的持续跨进程访问。
- **[Coordinate System Fix]**: 把 `CGWindowList` 返回的 Quartz window bounds 先转换成 AppKit 屏幕坐标，再参与 panel 定位，修正窗口上下拖动时辅助条反向漂移的问题。
- **[Drag Bundle Fallback]**: 当权限引导是通过 `swift run OpenComputerUse` 启动时，拖拽 tile 现在会自动回退到仓库内 `dist/Open Computer Use.app`，避免因为当前进程不是 `.app` bundle 而导致无法拖出权限条目。
- **[Permission Identity Alignment]**: 权限状态查询不再只看 `Bundle.main.bundleIdentifier`；当 onboarding 实际引导用户拖入仓库内打包好的 `.app` 时，TCC 查询会改用那个真实 app bundle 的 identifier，避免列表里已经出现 `Open Computer Use` 但 UI 仍然不显示 `Done`。
- **[Valid Bundle Guard]**: 回退到 `dist/Open Computer Use.app` 时会先验证它是否包含 `Info.plist`、可执行文件且 bundle id 正确，避免把空壳目录拖进系统设置后出现无图标、拖拽角标异常和权限状态不收敛的问题。
- **[Path-Based TCC Detection]**: 适配 macOS TCC 把 `Open Computer Use.app` 授权记录存成 `client_type=1` 路径项的情况；权限查询现在会同时检查 app 路径和 bundle identifier，不再因为系统设置里已授权但数据库 key 不是 bundle id 而卡在 `Allow`。
- **[Cold Launch Bootstrap Retry]**: 当 `Allow` 会首次冷启动 `System Settings` 时，辅助 panel 现在会在短时间内重试挂载，直到系统设置窗口真正 ready；避免“第一次拉起系统设置看不到浮窗，切走再切回才出现”的时序问题。
- **[Docs Sync]**: 更新架构文档，补充这块权限引导面板现在会保持在 `System Settings` 窗口之上的行为说明。

### 🧠 Design Intent (Why)
这个问题一半是窗口层级，一半是刷新策略。原先 panel 处在 `.normal` 且只做 `orderFront`，遇到前台的 `System Settings` 普通窗口时很容易被同层窗口压住；同时我们为了贴近 `+ / -` 控件行，持续通过 Accessibility IPC 读取 `System Settings` 的内部 UI 树。对这类 SwiftUI 系统页面，这种“读”并不是完全静态、无副作用的，足以把滚动区域和 overlay scrollbar 的重绘节奏带起来。最终收敛方案是把 panel 提升到辅助浮层、显式相对目标窗口排序，并完全放弃内部 AX 锚点扫描，只按窗口 bounds 固定贴底，这样才能稳定满足“始终盖在窗口上面且不扰动系统设置自身滚动表现”的要求。

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260417-2350-fix-permission-accessory-panel-ordering.md`
