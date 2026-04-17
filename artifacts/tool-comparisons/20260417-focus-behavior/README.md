# 2026-04-17 Focus Behavior Comparison

这组样本用于对比官方 `computer-use` 与仓库内 `open-computer-use` 在“只读取状态”和“坐标点击”场景下对用户前台焦点/鼠标的影响。

## 目录

- `computer-use/`
  - 来自已连接官方 `computer-use` MCP tool 的样本。
- `open-codex-computer-use/`
  - 来自仓库当前实现的样本。
  - 目录名保留旧命名，只是为了不改动这批已留档样本的路径。
  - `get_app_state` 通过本地打包后的 `dist/OpenCodexComputerUse.app` 走 JSON-RPC `tools/call` 采集。
  - `click` 同样通过本地 JSON-RPC 采集。

## 方法

- 目标 app：`Activity Monitor`
- 对照前台 app：`iTerm2`
- 观测项：
  - tool request
  - tool result 摘要
  - 调用前后的 frontmost app
  - 调用前后的鼠标坐标

## 已知限制

- 官方 `computer-use` 当前不能直接识别仓库里的裸可执行 fixture，因此对比目标改为双方都能解析的系统 app。
- 鼠标坐标会受到用户实时移动影响，因此这里只把它当作辅助观测；“是否切走前台 app”是更稳定的对比信号。
- `open-computer-use` 的坐标点击现在会先做 AX hit-test；如果命中失败，则仍会降级到全局 HID。
