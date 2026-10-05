# 安全默认约束

## 当前实现边界

- 对 MCP host 暴露的接口仍是本地 `stdio`；macOS CLI 与 `.app` app agent 之间会使用用户临时目录下的 Unix domain socket，socket 创建后会收紧为当前用户读写，且不对外监听 TCP/HTTP 端口。未设置 `OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE` 时继续使用历史 Socket；设置后仅以 namespace 摘要派生私有文件名，不把宿主目录或原始 namespace 写入 Socket 路径。
- Codex plugin 默认把一个本地 Node.js REPL 放在 native MCP 前面，npm CLI 的 `ocu js` / `ocu repl` 也直接使用同一 runtime。`js` 是任意本地 JavaScript 执行能力，不是受限表达式语言：代码可按启动进程权限读取文件、环境、模块和网络。只应在 host 已经具备并允许 model-code execution 的信任边界内启用；不接受这条边界的 host 应继续直连 `open-computer-use mcp` 的离散 native tools。
- REPL 里的 Computer Use 调用仍经过 native MCP，因此密码管理器 denylist、`OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS` 等 native safety gate 不会被 JavaScript adapter 绕过。JS kernel 在 Worker 中运行，超时会终止整个 Worker 并清空 bindings。
- 所有动作都必须显式带 `app` 参数；当前不会在后台自动扫描并控制任意 app。
- macOS 真实 app 路径依赖 `Open Computer Use.app` 已获得 `Accessibility` 与 `Screen Recording` 权限；终端里的 CLI / Node launcher 会把 `mcp`、`doctor`、`call`、`snapshot` 和 `list-apps` 转发给由 LaunchServices 启动的本地 app agent，避免把权限要求落到 iTerm / Terminal 身上。
- 实验性 Linux runtime 依赖已登录桌面用户的 AT-SPI2 / D-Bus session；coordinate mouse、drag、keyboard synthesis 只是 best-effort fallback，不应被视为跨 Wayland compositor 的通用后台输入授权。

## 数据处理

- 普通 app 的 screenshot 默认只在内存中编码成 PNG，并通过 MCP `image` content block 直接回传；默认不长期持久化。
- Linux runtime 的 screenshot 是 best-effort；如果 GNOME Wayland 返回黑图，bridge 会省略 image block，避免把无效截图误当成真实画面。
- fixture app 的合成状态只写到本地临时 JSON 文件，目的是支撑 deterministic smoke test；当前写入走原子替换，减少测试期间的读写竞争。
- 当前仓库不引入第三方服务，也不上传截图、AX tree 或输入内容。

## 授权与最小权限

- 当前只保留一层密码管理器 bundle denylist / bundle-id gate：
  - 会阻止对 1Password、Bitwarden、Dashlane、LastPass、NordPass 和 Proton Pass 做直接 `get_app_state` / action 调用。
  - 终端类 app、Chrome / Atlas 和系统组件不再属于内置阻止目标。
  - 对 bundle identifier 直传时返回 safety denial；对 app name 查询时默认不把这些密码管理器暴露成可解析目标。
- 但当前仍然没有官方闭源实现里的 session approval / 动态 app policy。
- 这意味着开源版当前的安全边界主要由：
  - 明确的 tool 调用参数
  - 内置密码管理器 denylist
  - `Open Computer Use.app` 的系统权限
  - 本地使用场景
  共同提供。
- `click_method=global` 是显式的系统级指针路径，可能移动真实鼠标、改变前台焦点或命中坐标处的其他窗口。调用参数本身不视为足够授权；macOS 和支持该模式的 Linux runtime 还要求进程环境中设置 `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1`。未设置时必须在任何可见 cursor 移动或真实输入事件之前拒绝请求。
- `click_method=app_post`、`sky_click` 与 `accessibility` 不允许静默切换到 `global`。这保证调用方选择的非侵入边界在失败时仍然成立。
- `click_method=sky_click` 是显式 macOS 私有 SPI 能力，不进入 `auto`。它不移动系统指针、不改变 WindowServer frontmost app，也不 raise 或切换目标窗口；内部只让目标应用短暂进入 synthetic-active 状态，绝不向真实前台应用发送 defocus record，renderer settle 后也只撤销目标的合成状态。点击后的 action-result snapshot 禁止 activate / `AXRaise` 恢复。它仍会向指定 PID/window 注入真实输入语义，因此只允许使用当前 snapshot 的 on-screen、同 PID 窗口，并在窗口身份不匹配、target-focus record 失败或私有符号缺失时 fail closed。第一版仅支持同一 Space 内的左键单击/双击。
- SkyLight ABI、raw event field 和 Chromium 接收行为都不受 Apple 公共兼容性承诺保护。系统升级后的失败不得触发静默 global fallback；应先重新验证符号和受控目标，再决定是否更新实现。
- 下一阶段应优先补：
  - session 级审批
  - 更清楚的敏感 app / 系统设置防护策略

## Fixture Bridge 约束

- `FixtureBridge` 只用于仓库内测试夹具，不是给第三方 app 的控制平面。
- 任何面向真实 app 的能力新增，都不应该复用这条测试专用通道。

仓库级的依赖、SBOM 和 provenance 默认能力，统一写在 `docs/SUPPLY_CHAIN_SECURITY.md`。

## macOS 虚拟会话

- 只有明确创建/绑定的 app、PID/window 可以操作。借用应用的其他窗口不自动接管，专用 Chrome 使用 0700 临时 profile，不复用用户浏览器 profile。
- 虚拟会话始终禁止全局 HID、系统光标移动、真实 app 激活、AXRaise、snapshot activation recovery 和共享剪贴板文本输入；旧全局开关不会解除限制。未验证的拖拽明确拒绝。
- pause 先关闭输入门，操作前后验证身份/几何/桌面状态，文本键盘 fallback 每个 chunk 再检查输入门。未知系统窗口、锁屏/睡眠/Space 变化和用户激活目标均暂停。
- 恢复文件只记录进程启动身份、窗口与原位置/显示器，不含画面或输入内容，目录 0700、文件 0600。恢复前校验 PID、launchDate、bundle、window。正常清理恢复借用窗口，不退出借用应用；专用应用拒绝退出或恢复失败则保留会话，不强杀未保存内容。专用实例/临时 profile 的独立恢复标记在进程仍活着时保留，后续只清理确认原进程已退出且路径属于 OCU UUID 临时目录的 profile。
- helper 只持有私有显示器，退出通过父进程私有管道 EOF 驱动。超时终止只针对本进程创建的 helper，不枚举并杀死其他显示器进程。
- 原始视频帧仅在本地内存/Metal 渲染，排除宿主窗口，不经 MCP 传视频。虚拟显示器共享当前登录桌面，不是隔离登录会话或安全沙箱。

实现和兼容性限制见 [虚拟工作区设计](design-docs/virtual-display.md)。

会话 notebook 直接调用生产 dispatcher，单元自动绑定所属 session，显式跨会话参数被拒绝；仅允许会话内 OCU tools 和受约束的 Calculator/TextEdit 示例编排，不执行任意 shell/JavaScript。示例通过 AX 读取实际计算结果与写入内容；TextEdit 专属临时文档不接管用户现有文档，清理核对 PID 启动身份和临时目录来源，不强制退出未保存应用。每会话保留独立 snapshot cache，单元输出/截图只驻留内存。多应用进程归属唯一会话，动作仍验证具体 PID/window，不能因共享显示器放宽输入边界。

虚拟 session 的 sky_click 禁止 synthetic focus records，定向事件使用 private source、屏内 primer，保留显式方法且不切换 fallback。隐藏仅用于核对过返回 PID 的全新专属实例；不隐藏用户既有或当前前台应用。首窗口在隐藏状态下移动/读回，但第三方文档启动仍可能短暂可见，不能宣称完全独立桌面。Dock 回归只观察几何和屏归属，不修改偏好、不重启 Dock或劫持光标。

空屏复用只保留本 runtime 私有管道持有的 helper/display，不保留输入会话、视频帧或光标；没有 session ID 的空屏不能操作。正常归还必须先完成借用窗口恢复、专属应用礼貌退出与恢复标记清理；失败保留暂停会话。release 仅能选择自有空屏，拒绝活动/未知 ID；Quit 及父进程 EOF 释放全部，不枚举或终止其他用户显示器。桌面仍属于当前登录用户，用户自行移入空屏的其他窗口不会被自动接管。
