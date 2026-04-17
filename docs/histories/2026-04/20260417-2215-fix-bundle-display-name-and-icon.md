## [2026-04-17 22:15] | Task: 修复 app bundle 显示名和图标

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> 系统设置的 `Accessibility` 和 `Screen *` 列表里当前显示的是 `OpenComputerUse`，并且没有 logo；需要改成 `Open Computer Use`，而且要有 logo。

### 🛠 Changes Overview
**Scope:** `scripts/`, `plugins/open-computer-use`, `docs/`

**Key Actions:**
- **[Bundle Identity]**: 把打包产物从 `OpenComputerUse.app` 切到 `Open Computer Use.app`，让 macOS System Settings 读取到带空格的 bundle 显示名。
- **[Bundle Icon]**: 新增构建期 icon 渲染脚本，生成 `icns` 并写入 app bundle，再通过 `CFBundleIconFile` 暴露给系统权限面板。
- **[Packaging and Docs]**: 同步更新插件 launcher、Codex 安装脚本、npm staging 和文档里的 bundle 路径，避免打包链路继续引用旧名字。

### 🧠 Design Intent (Why)
System Settings 对这两类 TCC 权限列表显示的名字更接近 app bundle 文件名，而不是单独看 `CFBundleDisplayName`。因此只改 `Info.plist` 不够，必须把实际 `.app` 名字改成带空格版本，并且补上真正的 bundle icon 资源，才能同时解决无空格名和空白图标。

### 📁 Files Modified
- `scripts/build-open-computer-use-app.sh`
- `scripts/render-open-computer-use-icon.swift`
- `scripts/install-codex-plugin.sh`
- `scripts/npm/build-packages.mjs`
- `plugins/open-computer-use/scripts/launch-open-computer-use.sh`
- `README.md`
- `docs/CICD.md`
- `docs/exec-plans/active/20260417-permission-onboarding-app.md`
- `docs/histories/2026-04/20260417-2215-fix-bundle-display-name-and-icon.md`
