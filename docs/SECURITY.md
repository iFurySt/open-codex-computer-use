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

## macOS Locked Use 实验边界

- 生产 backend 在完整实测证据缺失时关闭；只有管理员显式安装的验证 profile 能运行实验事务。用户环境和请求 metadata 不能开启生产自动解锁。
- 签名 Root Broker 从内核 audit token 认证原生 CLI / app agent / Guardian / Apple helper，批准绑定 UID、角色、signer 和 Team ID。SCM_RIGHTS 原客户端端点也要验证；许可绑定会话、连接与一次性 attempt，不能从请求指定任意 requirement。
- 安装器只添加自己的 OR branch，保留原密码 fallback；备份完整语义规则并在回滚前检查当前策略没有第三方变更。独立 deny-only probe 与实际验证 profile 分离。
- 解锁入口仅在双保护准备后做一次公开电源活动声明，并在 3 秒内等待完整 AX 发布。只按 Apple 签名 loginwindow 的 AXIdentifier 匹配（深度 ≤8），唯一候选写空字符串，不读取密码。验证版本随后尝试一次窗口限定点击：要求有限 AX 几何、唯一同 PID 的 on-screen 窗口包含目标点，使用 NSEvent.windowNumber、目标 PID / 窗口字段、与现有 sky_click 复用的 CGEventSetWindowLocation 私有编码及 subtype 3，在 session stage 投递鼠标 down/up，不合成全局 Return。验证 profile 可在真实 UserPasswordTextField 空写成功、字段声明支持 AXConfirm 时尝试一次 AXConfirm；是否生效独立记录，不视作解锁证据。两个会话过滤器只接受继承私有管道传递的随机一次性标记、正确 Guardian 来源、无 Shift / Control / Option / Command 点击修饰键、同目标 / 窗口 / 坐标且相隔小于 250ms 的一对点击；能力最多 5 秒，重复、接管、停止或重锁后不可恢复，不增加 PID-only 豁免。随机标记不进入 argv/env、日志或报告。硬件活动检测始终独立工作并撤销能力。此路由实际投递 / 认证效果尚待实测，queued 不是成功证据。取消禁止迟到写入，在途事件必须排空。SetResult 与真实同会话 unlocked 观察缺一不可。
- 认证策略观察在独立队列完成。双保护就绪后保持有界 authorizing 待命，不预先签发许可；仅在已验证插件首次 claim、原会话仍锁定、策略和双保护新鲜时签发。许可最多 5 秒且不得超过本轮启动截止（默认 8 秒，显式验证 profile 总待命 20 秒；准备双保护仍最多 8 秒）；取消 / 过期等待不能重启。恢复协议不能被同步 authd 查询堵塞。策略最大 2 秒新鲜度不是每条消息都做同步读取，也不覆盖第三方新规则。
- 两个保护进程各持有遮罩、输入过滤和硬件活动检测；只有撤销许可、排空动作 / 解锁事务并观测同会话锁定后才释放。停止 deadline 只结束自身 automation agent，不能提前杀保护或按时间撤罩。
- 人工 recovery-only 入口只对验证 profile 开放，在准备双保护后、签发许可前结束事务。准备失败的快速收束不能冒充双保护完整通过。
- 当前自动解锁、完整 Keychain、Secure Input、进程 / 服务故障和显示器变化仍未全部通过。两个物理屏幕 preview 和已解锁遮罩下 AX / SCK 的结果不能替代这些门槛。详见 [实验与恢复说明](locked-use.md)。

- macOS 14.4+ 的授权插件用 public LightweightCodeRequirements 对 socket audit token 建立 SecTask 验证：固定 signing ID / 团队、Developer ID validation category、动态签名有效、已签名、hardened runtime 和 Library Validation。逐项拒绝危险 entitlement，并重校验运行中的任务；现代验证失败不回退到字符串或磁盘检查。旧系统保留原 SecCode 路径。独立签名测试验证合法身份通过、错误 ID / 团队 / ad hoc / get-task-allow 被拒绝；实机锁屏表现仍须单独记录。

认证诊断采集是只读、限时、限量的辅助观察；原始 OS 字段不持久化，只保存白名单枚举，缺失日志不能作为认证 / 撤罩依据。上游报告记录插件介入后的会话级 Keychain 不可访问，未证明空输入导致重设；隔离环境是开发建议，不是 API 要求。新认证路径仍需验证系统的 Keychain 可用状态，不能从固定 AX 探针结果推出安全性。

验证 profile 的 HID 对比实验只改变鼠标投递层，继续经过同样的双会话过滤器和一次性能力校验；HID 注入不等于真实硬件活动或认证授权。生产与旧协议保持 session 层。
