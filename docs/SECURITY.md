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

## 独立电源保活

合盖 helper 仅接受同 Team、固定 host identifier、Developer ID 且无 get-task-allow 的签名 XPC 调用；固定操作不执行调用方 shell。Unix coordinator 以 peer UID 为信任域，socket/目录为 0600/0700。root 恢复目录与 journal 验证所有者、权限、symlink、硬链接及 extended ACL，并持有 dev/release 共用 flock；已有外部 SleepDisabled 时拒绝接管。App 固定安装到标准 Applications 位置，已登记 bundle 更新前先卸载。它不改变锁屏/认证策略；物理合盖与企业电源动作的兼容性需独立验收。详见 [电源保活](power-hold.md)。

显示器级删除只针对本 runtime 拥有的资源，在串行锁下先结束其关联会话，再移除 helper/display；任一安全清理失败都保留未完成状态。create 的精确 display_id 仅可选择匹配配置的空屏，不能隐式接管活动或其他 runtime 的显示器。GUI session trash 默认保留屏，另有明确同时删除入口。

电源 metrics 仅读取固定 AppleSMC PSTR 与电池数值/固定状态，不暴露任意 SMC 命令或写入；用户态 SQLite 目录/文件为 0700/0600，拒绝 symlink、硬链接、非本用户及 extended ACL。存储数据不含输入、画面、应用列表、序列号或证书，不上传。查询复用同 UID socket 信任域，保留配置有上限，clear 仅处理本模块数值历史；关闭协调器期间过期数据于下一次启动/查询清理。

launch 默认不授权所有窗口；只有显式 manage_all_windows 才允许管理验证过的专属实例初始窗口。adopt 必须包含 PID/window_id，app 为可选身份校验。候选查询是只读信息，无授权含义；新普通窗口不自动纳入，未知 modal/sheet 暂停。应用级 hide/unhide 仅验证新 PID、bundle 与出生时间后用于专属实例。

## macOS AX 输出历史

AX diff 在每个客户端 dispatcher 的本地内存中保留最多 16 个发布版本，以及 16 个目标的身份映射；历史仅包含清洗文本/结构，不含截图，不上传或自动落盘。连接关闭释放状态，turn-ended/显式缓存清理清空历史；none 只省略输出，不能绕过虚拟会话读回和输入校验。重放导出只有明确设置测试环境变量时发生，默认关闭，导出真实数据前需脱敏。

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

- 用户明确选择的无遮罩诊断是独立验证 profile 分支：只接受 Root 已批准签名探针的原锁定 session，不声明 guardsReady，不接受应用 action / 生产验证 / promotion，不恢复诊断许可。许可仍为首次同 audit session 插件 claim 后最多 5 秒且不超过 20 秒诊断截止；断开 / 策略失效 / 过期撤销不可重启。结果明确不含生产证据。正常生产保护规则不变。


受保护 Return 验证实验不开放通用 keyboard exemption。与 click 不同的随机 tag 只经继承管道交给独立 watchdog；两套 gate 对原锁定 session、来源、目标、固定 keyCode 36、无 modifiers / autorepeat、5 秒有效期及 250ms down/up 进行独立一次性检查。真实硬件输入监控继续生效，停止 / 接管同时撤销 mouse 与 Return gate。只有管理员 validation profile 创建 Return 能力，生产等待完整实测。
