# macOS 虚拟显示器工作区

OCU 的原生 GUI、CLI、MCP 和 JS 共用进程级 `VirtualDisplaySessionRegistry`。一个 runtime 支持多个独立会话；每个会话拥有一块虚拟显示器、独立视频流及多个应用/窗口。同一 PID 只能属于一个会话。最低构建目标仍为 macOS 14；当前实测环境为 macOS 26.5.1 / Apple Silicon。其他系统版本和架构尚未确认。

## 启动 GUI

```bash
./scripts/build-open-computer-use-app.sh debug
open "dist/Open Computer Use (Dev).app"
```

Release 使用原有 `Open Computer Use.app`、bundle ID、`OPEN_COMPUTER_USE_CODESIGN_*` 和公证入口。Debug 使用原有 `.dev` 身份，需要单独授权 Accessibility 和 Screen Recording；终端的授权不能代替签名 App 的授权。helper 先签名，外层 bundle 后签名。

左侧展示会话。点击 New session，填写名称和显示倍率，再 Create 创建空虚拟桌面；选中会话后用 Add application 搜索应用，选择专用启动或接管已有 PID/window。同一显示器可重复加入多个应用，窗口采用错位布局。新建/移除显示器可能触发系统桌面或 Space 通知，其他会话会按安全策略暂停，需要显式 Resume。接管前将目标应用留在后台。专用实例模式请求后台启动，Chrome 使用临时独立 profile；若 LaunchServices 返回已有 PID，拒绝隐式接管。主区域观看选中会话的整个虚拟屏幕，支持适应窗口和原始像素尺寸；Target 选择具体应用窗口。Toolbar 提供添加应用、暂停/继续和结束选中会话，Quit 清理所有会话。预览不接收人工键鼠输入。

桌面下方的 Actions 是可编辑命令单元，可拖动分隔线调整高度。每个会话保留自己的内存 notebook，默认提供 Calculator → TextEdit 的可运行示例。单元支持编辑标题/JSON、单条播放、删除，Add cell 可添加模板并滚动到新单元，Run all 按当前顺序执行并在首个错误处停止。左侧编辑命令，右侧展示格式化 JSON；UI Tree 与截图左右排列。输出保留成功/错误状态和耗时；编辑后旧结果标为 Edited since last run。Stop and pause 阻止后续单元并关闭该会话输入门，当前操作在已有的安全边界退出；恢复后需要新的 snapshot。

采用直接调用生产 dispatcher 的原生 kernel，保留跨单元 snapshot 缓存，无需 Jupyter/Node/shell 进程。示例单元：

```json
{"tool":"get_app_state","args":{"app":"$app"}}
```

```json
{"tool":"click","args":{"app":"$app","element_index":"21","click_method":"accessibility"}}
```

`$app`（或省略 app）使用开始运行时选中的应用；多应用编排可明确填写各自 bundle ID。索引必须从最新 snapshot 取得，模板的 REPLACE_FROM_SNAPSHOT 是待填写占位符，不能直接运行。`session_id` 自动绑定当前 notebook，显式跨会话 ID 被拒绝。Run all 冻结本次运行的单元顺序、命令和默认目标；修改留待下次执行。仅运行 session 内的 OCU tools 和内置示例编排，创建/结束通过工作区进行，不执行任意 shell 或 JS。输出仅在内存，不生成 .ipynb 文件，也不持久化截图或输入内容。

新会话直接点击 Run all：`prepare_example` 启动专属 Calculator 与 TextEdit，`calculate` 使用 AX identifier 选择实际按钮计算 `42 × 17`，从 Calculator AX display 读取结果，`write_result` 把 `${expression} = ${result}` 写入 TextEdit 并读回核对。前后 inspection 单元返回真实 AX tree / ScreenCaptureKit 截图。可编辑 calculate 的 `left` / `operation` / `right`，或修改 write_result 的模板；运算支持 +、-、*、/，数字采用有限长度的十进制字符串。示例命令是 notebook 内置编排，不新增 MCP tools；其他单元仍可逐条调用常规工具。

TextEdit 通过 `attach_app_to_virtual_display` 的可选 `new_document: true` 启动会话专属临时 `Result.txt`（仅限专用 TextEdit 启动），避免空启动只有文件选择面板。不会隐式接管用户应用/文档。示例只验证 UI 中的内容，不承诺落盘：当前 AX set_value 的文本能读回，但 TextEdit Save 仍禁用，后台 ⌘S 也未保存。临时文件目录 0700、初始文件 0600；正常退出后移除，崩溃恢复只清理已确认退出的专属进程留下的可验证目录。未经保存的其他真实编辑仍可能阻止安全退出。

会话 ID 可复制到工具调用。关闭主窗口保留后台会话，再次打开 App 显示同一窗口。Quit 恢复借用窗口，专用实例留在虚拟屏上礼貌退出，再停止捕获并移除显示器；专用实例拒绝退出时把窗口移回物理屏供用户处理，保留会话并显示原因。恢复失败也保留会话。借用应用不会被退出。切换 OCU 构建时，有活动会话的旧 runtime 不会被替换；需要先结束会话，或明确使用独立 socket namespace。

## 实现分层

- `packages/VirtualDisplayBridge`：自行维护的小型 Objective-C bridge，运行时探测 `CGVirtualDisplay*` 类与 selector，检查创建和 `applySettings`。私有 ABI 缺失时明确失败。
- `apps/VirtualDisplayHost`：每会话一个 helper，只持有显示器。stdin/stdout 交换配置与 ready/error；stdin EOF / stop 退出，诊断写 stderr。父进程等待系统在线列表确认移除，超时只终止自己创建的 helper。
- `VirtualDisplaySession.swift`：串行会话操作、精确 PID/CGWindowID/AX 关联、窗口位置读回、暂停门、恢复记录与应用生命周期。GUI 使用 worker 执行阻塞操作，暂停先关闭输入门。
- `VirtualDisplayCapture.swift`：显示器级 ScreenCaptureKit 流，最高 30 fps、BGRA、无音频、隐藏系统光标、排除当前宿主 PID。只保存最新 `CVPixelBuffer`，共享 Metal 预览直接渲染；视频不经过 MCP 或逐帧 PNG。
- 既有 `ComputerUseService`：窗口级 AX tree 和截图，增加明确 session context。窗口选择与恢复策略受会话约束，旧调用保持原行为。

默认 1920×1080 points、1×、60 Hz；2× 对应 3840×2160 pixels。helper 请求扩展显示器并放在原桌面右侧，保留物理屏位置请求、不设置主屏或物理屏模式。runtime 等待 CoreGraphics、NSScreen 和 ScreenCaptureKit 可用，读取实际布局。运行中不改分辨率。接入/移除仍可能引发 macOS 桌面重配置，不能承诺零系统副作用。

坐标工具仍接受返回窗口截图的像素坐标，按实际像素尺寸映射到 AX/Quartz points；显示器预览使用独立坐标映射。布局版本绑定操作缓存，支持 Retina 与负坐标。物理或虚拟布局变化、目标窗口移动/消失、用户激活目标、Space 变化、睡眠/锁屏、权限撤销或捕获错误都会暂停。恢复重新验证身份/几何与捕获；静止画面不按无新帧自动判失败。状态提供 capture running/error/frame age、创建前后前台 PID 和物理布局保持情况供诊断。

## API 与工具

Swift：`VirtualDisplaySessionRegistry.shared` 提供 `create`、`states` / `currentState` / `state`、`attach`、`availableApplications` / `availableWindows`、`selectWindow`、`pause` / `resume` / `destroy` / `destroyAll`。阻塞生命周期 API 在 worker 调用。`capture(sessionID:).subscribeFrames` / `unsubscribeFrames` 在捕获队列提供原始帧；消费者必须及时返回，最多保留最新一帧。

macOS 增加六个 MCP tools：

| 工具 | 关键参数 |
| --- | --- |
| `create_virtual_display` | 可选 `width`, `height`, `scale` |
| `attach_app_to_virtual_display` | `session_id`, `app`, `mode=adopt/launch`；adopt 必须提供 `pid`, `window_id` |
| `get_virtual_display_state` | 可选 `session_id`；省略时返回所有 sessions |
| `pause_virtual_display` / `resume_virtual_display` | `session_id` |
| `destroy_virtual_display` | `session_id` |

原有 app tools 增加可选 `session_id`；`get_app_state` 可用 `window_id` 选择受管理窗口。必须匹配会话中受管理应用；多个同 bundle 的实例用 window_id 消除歧义；未指定 session 的旧行为不变。Windows/Linux 仍只暴露原有 9 tools；JS 在绑定 session 前检查 native 工具能力，避免旧 runtime 静默忽略 session 参数。

CLI 示例：

```bash
open-computer-use call create_virtual_display --args '{"scale":1}'
open-computer-use call attach_app_to_virtual_display --args '{"session_id":"SESSION_ID","app":"APP_BUNDLE_ID","mode":"adopt","pid":123,"window_id":456}'
open-computer-use call get_virtual_display_state # 列出所有会话
open-computer-use call get_virtual_display_state --args '{"session_id":"SESSION_ID"}'
open-computer-use call destroy_virtual_display --args '{"session_id":"SESSION_ID"}'
```

会话跨 CLI 调用存活，但 snapshot 属于调用客户端。动作和前置 snapshot 应放在同一次 `call --calls`，或使用持续 MCP / JS 连接。暂停/继续、窗口选择、布局变化和 turn-ended 都要求重新 snapshot。断连不自动销毁显示器。

JS 示例：

```js
var displays = await cua.listVirtualDisplays();
var session = await cua.createVirtualDisplay({ scale: 1 });
await session.attachApp("APP_BUNDLE_ID", { mode: "adopt", pid: 123, windowId: 456 });
var target = await session.getApp("APP_BUNDLE_ID");
await target.getAXState();
// 依据最新 AX 索引调用 target.click / setValue / scroll 等。
await session.pause();
await session.resume();
await target.getAXState();
await session.destroy();
// 加入 GUI 已创建的会话：
var joined = await cua.getVirtualDisplay("SESSION_ID");
await joined.getState();
var existing = await cua.getApp("APP_BUNDLE_ID", { sessionId: "SESSION_ID" });
```

## 后台边界与恢复

虚拟会话强制禁止 global HID、系统光标移动、真实应用激活、AXRaise / activation recovery；即使旧全局输入环境开关开启，也不会解除限制。显式 click 方法不静默切换。不使用共享剪贴板。会话的定向鼠标/文本事件清除继承的物理修饰键 flags；快捷键只设置请求指定的修饰键。快照仅渲染所选窗口，不带系统菜单栏；AX 对象、命中测试和键盘焦点必须属于所选窗口，坐标不能越界。输入前检查 snapshot、窗口身份与位置，输入后读回 AX 和截图，结果区分投递与观察到变化；变化是否满足任务仍需调用方验证。

拖拽明确拒绝：当前 process-targeted 事件未在真实测试中驱动内部拖拽，不能以投递成功声明支持。菜单、IME、特殊快捷键和系统拖放没有通用兼容承诺。未知系统对话框暂停，借用应用其他窗口不会自动被挪走；专用实例的新窗口验证身份后才纳入管理。

恢复文件仅保存 PID、进程启动时间、bundle ID、window ID、原 frame 与显示器身份，启动时间优先通过内核查询，必要时回退 LaunchServices，不能验证时拒绝移动。恢复路径按 bundle/socket namespace 隔离，日志合并本 runtime 的所有会话；目录 0700、文件 0600，不保存截图或输入内容。下次创建前核对进程身份再恢复；原显示器消失时回到可用物理屏。无法安全恢复或专用应用拒绝退出时保留会话，不强杀有未保存内容的应用。专用实例另存逐会话恢复标记；进程仍存活时保留其 profile，不因崩溃强制退出，下次创建时只在确认原进程已退出后清理可验证的 OCU 临时 profile。helper 通过管道 EOF 跟随父进程退出，不把“释放对象必然移除”作为通用规律。

## 可重复验证

```bash
swift test
node --test scripts/node-repl/*.test.mjs
./scripts/run-tool-smoke-tests.sh
./scripts/run-virtual-display-tests.sh --example
./scripts/run-virtual-display-tests.sh --multi-session
./scripts/run-virtual-display-tests.sh --cycles 20 --scale 1
./scripts/run-virtual-display-tests.sh --cycles 20 --scale 2
./scripts/run-virtual-display-tests.sh --cycles 1 --foreground-guard --strict-desktop
./scripts/run-virtual-display-tests.sh --cycles 1 --input-matrix
./scripts/run-virtual-display-tests.sh --holder-only --cycles 20
./scripts/run-virtual-display-tests.sh --third-party com.apple.TextEdit
./scripts/run-virtual-display-tests.sh --third-party com.google.Chrome
./scripts/run-virtual-display-tests.sh --lab
codesign --verify --deep --strict "dist/Open Computer Use (Dev).app"
```

Runner 默认保持用户当前前台，真实 AppKit target 不自行激活；所有操作经过 AX 与 ScreenCaptureKit。`--foreground-guard` 明确启动并激活一个受控测试窗口，结束后恢复原前台应用，用于检查 active/key/first responder 与瞬时 resign 计数；其状态文件仅做观测，不用于模拟目标动作。`--strict-desktop` 要求整个交互期间硬件鼠标不动、前台 PID 不变。默认事件观察允许用户移动鼠标，统计 agent 是否投递到全局 session event stream，不读取键盘内容。

当前证据与限制：

| 路径 | macOS 26.5.1 / arm64 结果 |
| --- | --- |
| AppKit AX 点击、Unicode set_value、滚动、sheet | 真实 UI 和截图验证通过；受控 sheet 使用 nonactivating NSPanel，NSAlert 自行激活会触发暂停 |
| 1× / 2× 捕获 | 可辨识红色图案验证来源 |
| 重复启停 | 20 次捕获重建、销毁、在线列表移除、旧帧清除通过；自有 helper 异常退出暂停/清理通过 |
| 多会话 / 多应用 / notebook | 两个独立 1×/2× 显示器、同屏两个真实 AppKit 进程、跨会话归属拒绝、三个目标逐条 AX 变化、暂停/捕获/销毁隔离通过；签名 GUI 的创建/切换、单元编辑/播放/输出和全部 Quit 清理通过 |
| 暂停与缓存 | 暂停拒绝输入，继续后旧 snapshot 拒绝 |
| 拖拽 | 未验证成功，接口拒绝 |
| AppKit app_post / sky_click | 未改变真实按钮计数；返回新状态说明未验证变化，不切换输入方法 |
| press_key | 受窗口焦点校验约束，当前只有投递/读回证据，不声明具体快捷键效果 |
| 前台 AppKit probe | 测试期间发生前台切换，未形成有效 active/key/first responder 保持证据 |
| TextEdit 空启动 / 专属文档 | 空启动仍没有可关联的普通窗口；new_document 已验证后台打开专属文档、AX 写入/读回。默认示例不保存文件 |
| Chrome 临时 profile 专用启动 | 应用自行进入前台，失败并安全清理 |
| Calculator + 正式 GUI | Release 复用已有权限；专用启动、放置窗口、实时预览、CLI 共用会话、AX 修改并还原数值、暂停/继续、关窗保活、重开、结束和带活动会话 Quit 清理通过 |
| Dev GUI 权限缺失 | 展示权限入口并禁用创建，通过实机检查 |

多物理屏/负坐标在当前桌面观察；负坐标和 Retina 映射有单元测试。Spaces、Stage Manager、持续并行人工输入的 AppKit 焦点验收、锁屏/睡眠恢复、权限撤销、主进程崩溃恢复、跨架构与其他 macOS 版本尚未完整实机验收。当前能力不是独立登录桌面，应用兼容性由逐项测试确认。

参考来源与采用边界见 [虚拟显示器参考](../references/macos-virtual-display.md)。

## 桌面重配置与启动窗口的回归记录（2026-10-05）

创建/移除显示器本身仍会触发 WindowServer 重配置，不能承诺桌面零刷新。helper 使用稳定、未占用的 serial，读取实际布局，只修正有差异的 origin/mirror，不重写相同的物理屏配置。`creation_observation` 新增 `display_serial`、`additional_configuration_applied`、`desktop_before`/`desktop_after`、`main_display_preserved`/`dock_display_preserved`。主屏和物理 frame 没变，不代表 Dock 没移动；Dock 来自只读 AX/窗口几何观察，不用缓存的 NSScreen.visibleFrame 推断。

当前上下屏排列已复现原实现创建后 Dock 从上屏移到下屏且销毁后不自动恢复。优化后 20 次生命周期保持主屏、物理 frame 和测试前的 Dock 所在屏，稳定 identity 后跳过额外配置；但该次基线的 Dock 已在下屏，不能据此声称保住上屏 Dock。创建时发现 Dock 迁移会暂停并显示原因，不修改 Dock/Spaces 偏好、不重启 Dock、不移动用户鼠标。上屏 Dock 保持验收仍开放。

专属应用请求隐藏启动，并在等待首个 AX 窗口期间维持 AXHidden；移动及读回全部窗口后才 unhide。TextEdit 文档作为隐藏应用启动的初始 OpenDocuments event 交给 LaunchServices，不使用 AppleScript、脚本输入或额外 Automation 授权。此操作仅针对返回的全新实例与 OCU 专属文件，既有实例仍拒绝隐式接管。这个策略减少可见启动窗口，但不保证任意第三方应用零闪现；隐藏/揭示失败会明确报错、暂停并保留清理记录。

真实六单元例子完成 Calculator 714、TextEdit AX 内容及 SCK 捕获；16ms 元数据采样中 Calculator 未落在物理屏、两个应用未激活，成功样本为零物理窗口样本/零全局事件。重复测试仍捕获 TextEdit 启动的一次物理窗口样本，严格 `--example` 因此失败，不能声称零闪现验收通过。观察只记录新目标进程的窗口几何/归属，不读取用户键盘内容或保存物理屏像素。该 runner 会因前台 PID 改变或窗口样本非零而失败，不能通过只检查最后 frame 放宽验收。

```bash
./scripts/run-virtual-display-tests.sh --desktop-lifecycle --cycles 20
node scripts/run-app-agent-lifecycle-smoke.mjs --with-session
```

退出协议回归使用独立 socket namespace，启动实际签名 bundle，创建会话后请求 terminate，确认 runtime/helper 正常退出；失败保留进程供诊断，不强杀用户应用。创建 sheet 显示等待 macOS 的进度提示。已定位并修复曾使创建看似卡死的退出嵌套事件循环死锁；Quit 调度与回复使用 RunLoop，清理在 worker 执行。
