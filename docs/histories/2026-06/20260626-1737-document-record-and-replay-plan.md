## [2026-06-26 17:37] | Task: Record & Replay baseline

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> 把 Record & Replay 复刻方案和相关逆向上下文落到 docs，后续基于这个推进。

### 🛠 Changes Overview
**Scope:** docs, macOS runtime, OpenComputerUseKit tests

**Key Actions:**
- **[Plan]**: 新增 active execution plan，明确 macOS event-stream 复刻目标、范围、里程碑、验证方式和关键决策。
- **[Reference]**: 新增官方 Record & Replay 逆向参考，沉淀插件包装、MCP surface、Codex.app asar 分工、Computer Use 二进制字符串、AX diff 和截图上下文线索。
- **[Navigation]**: 在 reverse-engineering README 中挂载新参考文档，方便后续 Agent 发现。
- **[Baseline]**: 新增 Record & Replay 兼容 `event-stream mcp`，暴露 `event_stream_start`、`event_stream_status`、`event_stream_stop` 三个无参数 tools，并对齐官方 descriptions、annotations 和 Record & Replay MCP protocol version。
- **[Session Files]**: 新增 event-stream session 文件模型，写入 `events.jsonl`、`metadata.json`、兼容 alias `session.json`、`suppressed.jsonl`、`latest-session.json` 和 active session 状态。
- **[CLI]**: 新增 `open-computer-use event-stream start/status/stop/wait --json`，并通过 app-agent proxy 复用长驻进程里的 recorder 状态。
- **[Wait Semantics]**: 修复并发 `wait` / `stop` race，确保最终 metadata 写入后再清理 active session；app-agent 对 `status/stop/cancel/wait` 不再持有环境覆盖全局锁，避免 listener 阻塞结束命令。
- **[Events]**: baseline 记录 `session.started`、`window.changed`、`AX.focusedWindowChanged`、`mouse.click`、`mouse.context_menu`、`mouse.drag`、`keyboard.text_input`、`keyboard.submit`、`keyboard.shortcut`、`terminal.value_changed`、`selection.changed`、`debug.error`、`session.ended`，并附带基础 app/window attribution。
- **[Input Context]**: `mouse.click` / `mouse.context_menu` 现在会尽量附带 `targetAccessibilityElement`，键盘事件现在会尽量附带 `focusedAccessibilityElement`；click 坐标明确区分 screen-state `location` 和 `appKitLocation`；`mouse.drag` 当前记录起止 screen-state / AppKit 坐标、距离、时长和目标 AX 摘要，payload 字段结构仍待 official golden recording 校准；`experimentalRawEvents` 当前记录低层 NSEvent 摘要，scroll wheel 在官方独立事件名未知时只写 raw-only 事件。
- **[Controls]**: 新增 OCU 自有 Record & Replay 控制条，显示录制中、计时、Done / Discard，并支持拖动；Discard 走 `recording_controls_cancelled`。
- **[Cancel]**: 新增 `open-computer-use event-stream cancel --json` 作为 OCU CLI 扩展，MCP surface 仍保持官方三件套。
- **[AX Payload]**: `AX.focusedWindowChanged` 事件现在会尽量带 `accessibilityInspectorPayload`；首帧为 full tree，同 app/window 的后续事件使用轻量 `~` / `+` / `-` compact diff，diff payload 同时带 previous diff 和 cumulative diff baseline，失败写入 `suppressed.jsonl`。
- **[AX Diff Coverage]**: AX compact diff baseline 从相邻行启发式改为 LCS 风格行 diff，比较时归一化 AX tree leading element index，降低插入元素导致后续稳定行被误判为变更的噪音；单测覆盖 changed / added / removed / over-budget fallback。
- **[AX Payload Service Coverage]**: `EventStreamService` 的 snapshot-to-payload diff 状态机已抽成生产和测试共用 helper；新增服务级测试确认 full payload、previous diff 和 cumulative diff 会写入真实 session `events.jsonl` 的 `AX.focusedWindowChanged` 事件。
- **[Window Context]**: 新增 input 前 focused window context 检测；如果 app bundle + frontmost window title 变化，会在输入事件前先写顶层 `window.changed`，再补 `AX.focusedWindowChanged`，覆盖同一 app 内窗口切换后的上下文缺口；字段、初始帧语义和事件顺序待 golden recording 校准。
- **[Screenshot Context]**: 新增 `OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS=auto|always|never`，在 AX payload 需要额外视觉上下文时写入 session `screenshots/` 并返回 `screenshotNeededForContext`、`screenshotAvailable`、`screenshotPath`。
- **[Screenshot Context Coverage]**: 新增服务级测试，用可控 PNG snapshot 验证 `always` 策略会把截图写入当前 session `screenshots/`，且 `accessibilityInspectorPayload.screenshotPath` 指向可解析图片。
- **[Time Limit]**: 按官方 “up to 30 minutes” 描述新增最长录制时长，默认 30 分钟自动 stop 并写入 `recording_time_limit_reached`；该 endReason 暂为 OCU baseline，后续用 official golden recording 校准。
- **[Tests]**: 补 parser、proxy decision、MCP surface、session 文件生命周期、wait/stop 并发、最长录制时长、AX diff、控制条开关和截图策略单测；新增 `scripts/run-event-stream-smoke-tests.sh` 和 `make event-stream-smoke`，用可复跑 MCP smoke 验证 event-stream 文件产物；默认 smoke 跳过截图采集以避免锁屏/登录窗口环境的 ScreenCaptureKit 噪音；截图 smoke 在 snapshot 有截图数据时验证 `screenshotPath` 落盘，无截图数据时验证 payload 标记；timeout smoke 通过 MCP start/status 验证自动结束和 `recording_time_limit_reached`。
- **[Docs Handoff]**: 补充后续推进入口、P0/P1/P2/P3 分层、验收门槛和官方兼容层 / OCU 扩展层边界，明确第一版通知模型是 `wait` listener，主动 callback/webhook 后续只放在 OCU 扩展层。
- **[Design Note]**: 新增 Record & Replay 复刻设计入口，把“直接复刻官方 observable behavior + OCU 自有控制条/wait/通知扩展”的分层方案、推进顺序、验收门槛和当前缺口集中沉淀到 `docs/design-docs/`。
- **[Drag Events]**: 鼠标录制从 mouse-down 立即写 click 改为 down / dragged / up 后判定，补齐官方已确认的 `mouse.drag` baseline，避免拖拽误记成点击。
- **[Raw Events]**: 按官方字符串补齐 `experimentalRawEvents` baseline，点击、拖拽、键盘事件会附带 raw 摘要，并用 raw-only 事件保留 scroll wheel；新增 `OPEN_COMPUTER_USE_EVENT_STREAM_RAW_EVENTS=0` 关闭开关。
- **[Selection]**: 按官方字符串补齐轻量 `selection.changed` baseline；输入事件后如果 focused AX element 暴露非空 `selectedText` 且 selection signature 变化，会写入 selected text、focused element summary 和 app/window attribution；如果此前有选择而当前选择为空，会写 `selectionCleared=true` 清空事件，字段与触发时机仍待 official golden recording 校准。
- **[Secure Input]**: 按官方 `secureInput` 字符串线索补键盘文本脱敏 baseline；secure/protected focused element 下不写明文 `text` 或 raw `characters`，只保留长度和 redaction 标记。
- **[Terminal Events]**: 按官方 `terminal.value_changed` 字符串补齐轻量 baseline；明显终端上下文下 focused AX value 变化时记录 value hash / length 和脱敏 focused element，同时避免键盘 raw characters 与 focused value 写入终端缓冲区明文；字段与触发时机仍待 official golden recording 校准。
- **[Debug Events]**: 按官方 `debug.error` 字符串补齐轻量 baseline；AX snapshot、cumulative AX diff fallback 和 screenshot 写入失败时会在主事件流写入低敏 debug metadata，完整错误细节继续进入 `suppressed.jsonl`。
- **[Input Monitoring Diagnostics]**: 如果本地 input monitor 全部安装失败，录制仍会启动但会写入 `debug.error` 主事件，标记 `subsystem=inputMonitoring` / `reason=inputMonitorsUnavailable`，避免上层误把无输入事件的录制当成正常空录制。
- **[Start Approval Handoff]**: 补充 start approval / MCP elicitation 推进方案：官方兼容 MCP surface 仍保持三件套无参数，OCU 独立模式通过自有开始确认 UI 或 policy 承载用户确认；后续先在 service 层沉淀 approved / denied / cancelled 语义，再接 UI 和可选 MCP elicitation。
- **[Start Approval Baseline]**: 在 `EventStreamService.start()` 前接入 approval gate；已有 active session 时不重复确认，新 session 只有 approved 后才创建；denied / cancelled 返回官方已观察错误文案且不写 session；新增 `OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL=auto|interactive|approve|deny|cancel|mcp|elicitation`，交互式 runtime 使用 OCU 自有开始确认弹窗，smoke 显式 auto-approve，MCP elicitation smoke 显式走 `mcp`。
- **[MCP Elicitation Baseline]**: 新增 `OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL=mcp|elicitation`；event-stream MCP server 会在 host `initialize` 声明 `capabilities.elicitation` 时发送内部 `elicitation/create` approval request，accept 后才创建 session，decline / cancel / unsupported 不创建 session；该路径不改变官方三件套 tools/list 或 input schema。后续已按 Codex.app host schema 校准 form request shape，官方业务 message / `_meta` 仍待 golden 样本。
- **[Official Initialize Alignment]**: 复核官方 `SkyComputerUseClient event-stream mcp` 的 initialize/tools-list 输出；确认三件套 tools 与当前 schema 一致，并将 OCU event-stream initialize 调整为不返回 `instructions`，对齐官方当前 behavior。
- **[Wait Listener Coverage]**: 补 `runOpenComputerUseEventStream(.wait...)` 的 CLI dispatcher 测试，验证 wait listener 能被同一 runtime 内的 stop 唤醒并返回最终 stopped session。
- **[Wait Timeout Signal]**: `event-stream wait --json` 返回体新增 OCU 扩展字段 `waitTimedOut`，上层 plugin/skill 可区分 stop/cancel 唤醒和 timeout 返回；官方兼容 MCP surface 不暴露该字段。
- **[Wait Session Match Signal]**: `event-stream wait --json --session-id ...` 返回体新增 OCU 扩展字段 `waitSessionMatched`；wait 会优先读取目标 session 目录里的完成态 metadata，因此 latest session 被后续录制覆盖后仍能返回指定历史 session。未知或不匹配 session id 会快速返回 `waitTimedOut=true` / `waitSessionMatched=false` 并跳过 notify callback，避免独立集成方无限等待错误 id。
- **[Wait Timeout Smoke]**: `run-event-stream-smoke-tests.sh` 新增 `OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_WAIT_TIMEOUT=1`，通过真实 app-agent CLI start/wait/cancel 路径验证 `waitTimedOut=true`。
- **[No Active Smoke]**: `run-event-stream-smoke-tests.sh` 新增 `OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_NO_ACTIVE=1`，通过真实 MCP initialize/tools-list/status/stop 路径验证无 active recording 时返回 idle 且不写 session 文件。
- **[Official Surface Smoke]**: `run-event-stream-smoke-tests.sh` 增加 `OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_OFFICIAL=1`，可选启动官方 Record & Replay client 只做 initialize/tools-list 对比，避免触发真实录制。
- **[Lifecycle Smoke]**: 扩展 event-stream MCP smoke，覆盖 active session 重复 start、stop 后重复 stop/status，以及 timeout 后 stop 的幂等行为，固定官方 one-active / idempotent 语义。
- **[Approval Smoke]**: `run-event-stream-smoke-tests.sh` 增加 `OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_APPROVAL=deny|cancel`，通过真实 MCP stdio 路径验证 approval 被拒绝时返回官方错误文案且不创建 session 文件。
- **[App-Agent Wait Smoke]**: 修正 app-agent event-stream MCP server 初始化时机，并为 proxied `event-stream mcp` 请求转发外层 `OPEN_COMPUTER_USE_*` 环境，避免 `event_stream_start` 的环境覆盖生效前提前初始化共享 recorder；新增 `OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_APP_AGENT_WAIT=1`，通过 app-agent socket 验证 MCP start 写入指定 recordings root、共享 recorder 状态和 CLI `wait` 被并发 `stop` 唤醒。
- **[Stale Session Recovery]**: 当新 recorder 进程只看到旧 active `latest-session.json` 时，会持久化写回 `state=stopped` / `endReason=recording_process_unavailable`，同步 `metadata.json` / `session.json` 并清理 stale `active-session.json`，避免独立集成方持续看到幽灵录制。
- **[No Active Unit Coverage]**: 在单元层补 `event_stream_status` / `event_stream_stop` 未 start 时的 idle 语义断言，固定无 session id、无路径、且不创建 `latest-session.json` / `active-session.json` 的行为；同时复跑官方 surface smoke，只做 initialize/tools-list 对比，不触发官方录制。
- **[Official Surface Fixture]**: 新增官方 `record-and-replay` 1.0.857 的 normalized `initialize` / `tools/list` fixture，作为非录制 surface 漂移对比证据；该 fixture 不包含 `event_stream_start` 输出或用户录制内容。
- **[Official Fixture Regression]**: 将官方 non-recording surface fixture 接入单元测试；本地 `event-stream mcp` 的 protocol/name/capabilities/no-instructions 和三件套 tools 完整 JSON 必须持续匹配 fixture，server version 单独忽略以适配 OCU 自身版本。
- **[Skill Integration Reference]**: 在 `skills/open-computer-use` 中新增 Record & Replay reference，说明 `event-stream mcp` 官方三件套、session 文件、OCU `wait/cancel` 扩展和安全边界，为后续独立薄 skill/repo 提供可复用蓝本。
- **[Official Smoke Timeout]**: 为 official surface smoke 的官方 MCP 响应读取增加默认 10 秒超时和 `OPEN_COMPUTER_USE_EVENT_STREAM_OFFICIAL_TIMEOUT` 覆盖；补充逆向观察，裸官方 `event_stream_status` 可能依赖宿主/runtime 状态并挂起，因此自动化官方对比继续只覆盖 initialize/tools-list。
- **[Recording Validator]**: 新增 `scripts/validate-event-stream-recording.py`，校验 session 目录或 metadata/session 文件的 JSONL 可解析性、metadata/session alias、event/suppressed counts、final `session.ended`、`endReason` 和 `screenshotPath`；OCU smoke 已接入 strict 模式，官方 golden recording 后续可先用非 strict 模式做结构检查。
- **[Recording Summary]**: 新增 runtime CLI `open-computer-use event-stream summarize --json` 和源码脚本 `scripts/summarize-event-stream-recording.py`，把录制事件流提取为 event types、window、action sequence、target/focused element、selection、debug 和 redaction evidence；默认只输出 AX `value` / `selectedText` 长度、不输出原文，event-stream smoke 已接入读取验证，为后续根据 recording 创建 skill 提供前置审计入口。
- **[Runtime Validator]**: 新增 runtime CLI `open-computer-use event-stream validate --json`，让安装态 OCU 可以直接校验 metadata/session alias、event/suppressed counts、final `session.ended`、`endReason`、required event type 和 `screenshotPath`，独立 skill/plugin 不再依赖源码 checkout；默认、timeout、wait-timeout 和 app-agent wait smoke 同时调用 runtime validator 与源码 Python validator 做交叉检查。
- **[Runtime Declared Path Gate]**: runtime Swift validator 与源码 Python validator 在 `--strict-ocu` 下新增 declared handoff path gate，输出 `declaredPaths`，并要求 `metadataPath` / `sessionPath` / `eventsPath` / `suppressedEventsPath` 四个字段都存在且解析后文件存在；Swift 单测和 skill scaffold smoke 覆盖完整路径、缺失四字段和坏 `sessionPath`，skill scaffold 测试夹具同步补齐 `sessionPath` / `session.json`。
- **[Events-Only Validation]**: runtime Swift validator 与源码 Python validator 现在支持非 strict `events.jsonl` 输入；只有主事件流时也能检查 JSONL、required event type、完成态、skill draft gate、从 `session.ended.endReason` 推断取消态和阻断性诊断。strict OCU 仍要求 metadata/session alias，runtime/source summary 和 scaffold 也同步支持 `<eventsPath>` 输入并拒绝 cancelled events-only stream。
- **[Skill Draft Validation Gate]**: runtime CLI 与源码 Python validator 新增 `--require-skill-draft`，在结构校验之外要求至少一个高层动作且 recording 未取消；action smoke 和 scaffold smoke 覆盖可生成草稿与 cancelled 拒绝路径，方便独立 skill/plugin 在 scaffold 前先做硬 gate。
- **[Fixture Import]**: 新增 `scripts/import-event-stream-fixture.py` 和 `make event-stream-fixture-smoke`，为后续官方 golden recording 入库提供脱敏导入路径；默认改写本机路径、session id、timestamp、app attribution、窗口标题、AX value / selectedText，并移除 screenshot path；runtime validator / summary 和 Python helper 同步支持 fixture metadata 中的相对路径。`--mcp-transcript` 会把 probe output 脱敏成 `mcp-transcript.json`，用于保存官方 `event_stream_*` response shape。
- **[Golden Readiness Gate]**: 新增 `scripts/check-event-stream-golden-readiness.py` 和 `make event-stream-golden-readiness-smoke`，把“这个 fixture 是否足够作为 official/OCU golden baseline”从人工判断变成可复跑 JSON gate；默认要求 fixture manifest/source/version、final state、`session.started` 恰好一次且为首事件、`session.ended`、动作事件和 AX payload，full/diff/cumulative AX 证据可按校准阶段显式要求，也可要求 `mcp-transcript.json` 和指定 `event_stream_start/status/stop` response 证据。
- **[MCP Timeout Evidence]**: golden readiness gate 对 required MCP tool timeout 给出明确 `MCP tool timed out` 错误；`make event-stream-golden-readiness-smoke` 覆盖只有 timeout shape 的 transcript 不会被误判为成功 response golden。
- **[Fixture Compare]**: 新增 `scripts/compare-event-stream-recordings.py` 和 `make event-stream-compare-smoke`，把官方 fixture 与 OCU candidate 的 event type sequence、event counts、metadata keys 和 per-event JSON schema path/type 差异变成可复跑 JSON 报告，并覆盖相同样本通过、缺字段失败和事件顺序漂移失败。
- **[AX Diff Compare Gate]**: fixture import 在脱敏 `treeLines` / `cumulativeTreeLines` 时保留 `+` / `-` / `~` marker；recording compare 新增 `--require-ax-diff-evidence` 和 `--require-same-ax-diff-markers`，可要求 OCU candidate 保留官方 fixture 中出现的 AX diff/cumulative payload 和 marker 类型；`make event-stream-compare-smoke` 覆盖缺 evidence 与缺 marker 失败路径。
- **[Semantic Field Compare Gate]**: recording compare 新增 `--require-semantic-fields`，按事件类型比较官方 baseline 中出现的 replay-critical 字段是否也出现在 OCU candidate 中；覆盖 target AX、keyboard focused AX、drag 起止点、selection / terminal 摘要字段、window attribution 和 AX treeLines / cumulativeTreeLines，避免只看事件序列或完整 schema 时漏掉可复用 skill 所需的关键证据。
- **[Metadata Key Compare Gate]**: recording compare 新增 metadata key diff 和 `--require-same-metadata-keys`，把 metadata/session 文件布局键漂移变成可失败的官方校准 gate；`make event-stream-compare-smoke` 覆盖 candidate 缺 metadata key 的失败路径。
- **[Metadata Value Compare Gate]**: recording compare 新增 stable metadata value diff 和 `--require-same-metadata-values`，比较 `state`、`active`、`endReason`、`eventCount`、`suppressedEventCount`，避免 metadata key 一致但 stop/cancel/final count 状态漂移时仍通过；`make event-stream-compare-smoke` 覆盖 candidate endReason 漂移失败路径。
- **[Lifecycle Compare Gate]**: recording compare 的 `--require-final-session-evidence` 保留兼容 flag 名，但 evidence 已扩展为 start/end lifecycle：比较 `session.started` 个数、是否为首事件、`session.ended` 个数、是否为最后事件以及 endReason 集合；`make event-stream-compare-smoke` 覆盖 candidate 缺失 start boundary 和最后事件不是 `session.ended` 的失败路径。
- **[Wait Notify Callback]**: 新增 `open-computer-use event-stream wait --notify-command '<json-argv>'` 作为 OCU 独立集成 callback 扩展；结束唤醒时通过 stdin/env 传最终 status JSON，wait timeout 时跳过 callback，callback 非零退出或超时会让 CLI 返回 error；单元测试覆盖成功通知和 timeout 跳过。
- **[Wait Notify Smoke]**: 扩展 `OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_APP_AGENT_WAIT=1`，在真实 app-agent socket 路径下验证 `wait --notify-command` 能收到 stop 后最终 status JSON、session/state env 和成功 `notification` 结果。
- **[Wait Lifecycle Coverage]**: 补 `event-stream wait` 生命周期覆盖，固定已结束 session 再 wait 会立即返回最终状态，cancel/Discard 会唤醒 listener，并把 `recording_controls_cancelled` 传给 notify callback；app-agent wait smoke 也覆盖 completed wait。
- **[Session Alias Handoff]**: status / metadata JSON 增加 OCU 便利字段 `sessionPath`，指向 `session.json` alias；`wait --notify-command` 同步暴露 `OPEN_COMPUTER_USE_EVENT_STREAM_SESSION_PATH`，validator 和 fixture import 会校验 / 相对化该字段，方便独立 skill 在取消路径直接读取 session alias。
- **[Skill Handoff Smoke]**: 默认 event-stream smoke 现在按官方 skill 消费路径从 `event_stream_stop` 的 text JSON 读取 `eventsPath` / `metadataPath` / `sessionPath`，并使用 `sessionPath` alias 再跑 runtime validate/summarize，固定独立 skill/plugin 的路径消费语义。
- **[Smoke Matrix]**: 新增 `scripts/run-event-stream-smoke-matrix.sh` 和 `make event-stream-smoke-matrix`，默认跑稳定本地 baseline 矩阵：lifecycle、no-active、timeout、wait timeout、approval denied/cancelled、MCP elicitation approval、app-agent wait/notify、fixture import 和 recording compare；截图与官方 surface 对比保持 opt-in。
- **[CI Gate]**: 将 shell / Node / Python 脚本语法检查、`npm run package:skill`、Record & Replay surface drift smoke、`swift test` 和稳定 Record & Replay smoke matrix 接入 `scripts/ci.sh`，并补齐最小 `.github` workflow / issue / PR / dependency-review 骨架，使仓库默认 CI 入口能守住 event-stream baseline 与 thin skill 制品；截图和官方 bundle 对比仍保持 opt-in。
- **[Thin Skill]**: 新增 `open-computer-use-record-and-replay` 独立 skill，聚焦 macOS 录制、停止、读取 `eventsPath` / `metadataPath` / `sessionPath`、validate / summarize 和生成可复用 skill 的流程；它不依赖 Codex.app 私有 UI，后续可迁到独立 repo。
- **[Skill Packaging]**: `scripts/package-skill.sh` 从 hardcoded 单 skill 改为扫描 `skills/*/SKILL.md`，逐个校验 frontmatter、打包 `.zip` / `.skill` 并写入多 skill manifest；该打包路径已接入默认 CI。
- **[Surface Drift Smoke]**: 新增 `scripts/compare-event-stream-surface.py` 和 `make event-stream-surface-smoke`，只调用 initialize / `tools/list`，用官方 1.0.857 non-recording fixture 校验 OCU `event-stream mcp`；脚本支持 `--use-default-official` opt-in 复核本机官方 bundle，当前本机官方对比通过且不启动录制。
- **[MCP Elicitation Smoke]**: 新增 event-stream MCP elicitation approval 单测与 `OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_MCP_ELICITATION=1` smoke；默认 smoke matrix 已覆盖该路径，验证真实 stdio MCP server 发出 `elicitation/create`、接收 accept 后开始录制，并继续通过 stop / validate / summarize 收敛。
- **[Official Recording Probe]**: 新增 `scripts/probe-event-stream-recording.py`，支持 local OCU 和官方 bundled Record & Replay client 的 raw MCP transcript 探测；local `--start-stop` 可完成 start/status/stop，官方只读 initialize/tools-list 可返回，官方 raw start/status/stop 当前在宿主外超时且未产出 recording paths。新增 `make event-stream-probe`、`make event-stream-official-probe` 和 `make event-stream-official-start-probe`。
- **[Official Probe Fixture]**: 将官方 1.0.857 raw start/status/stop 宿主外 timeout 观测脱敏保存为 `record-and-replay-official-raw-start-timeout-1.0.857.json`；新增 `scripts/test-event-stream-probe-fixtures.py` 和 `make event-stream-probe-fixture-smoke`，默认 CI 校验该 fixture 不含本机绝对路径且仍表达三件套 surface 与 start/status/stop timeout 边界。
- **[MCP Elicitation Host Schema]**: 复核 Codex.app asar 的通用 MCP elicitation schema 和 pending request panel，确认 host form path 使用 `mode: "form"`、object `requestedSchema` 和 `accept|decline|cancel` response；OCU start approval request 改为显式 `mode: "form"` + 空对象 schema，去掉 request schema 内的 `additionalProperties`，并让 probe fixture 摘要记录 server-initiated elicitation request shape。
- **[Probe Elicitation Coverage]**: `scripts/probe-event-stream-recording.py` 的 server-initiated elicitation response 已按 host schema 校准：accept 发送 `content: {}`，decline / cancel 发送 `content: null`；新增 `--elicitation-action accept|decline|cancel`，保留旧 `--decline-elicitation` 兼容别名；新增 `scripts/test-event-stream-recording-probe.py` fake MCP server smoke，覆盖 request schema 摘要提取、三种 action 应答形状和兼容别名，并接入 `make event-stream-probe-fixture-smoke` 与默认 CI。
- **[Recording-To-Skill Scaffold]**: 新增 `scripts/scaffold-event-stream-skill.py`，从 validated / summarized recording 生成第一版 `SKILL.md` 草稿和脱敏 `references/recording-summary.json`；新增 `scripts/test-event-stream-skill-scaffold.py`、`make event-stream-skill-scaffold-smoke` 并接入默认 CI，固定录制后 handoff 不只停留在文档流程。
- **[Runtime Skill Scaffold]**: 新增 `open-computer-use event-stream scaffold-skill --json`，复用 Swift summary helper 在安装态生成第一版 `SKILL.md` 草稿和脱敏 `references/recording-summary.json`；独立 thin skill / repo 不再需要 checkout 本仓库源码才能完成 recording-to-skill handoff。
- **[Runtime Scaffold Smoke]**: 扩展 `scripts/test-event-stream-skill-scaffold.py`，同一临时 recording 同时经过源码 Python helper 和 runtime CLI `event-stream scaffold-skill --json`，并检查两条生成路径都不泄漏本机绝对路径。
- **[Replay-Oriented Scaffold]**: 扩展 Swift runtime scaffold 和源码 Python scaffold 的生成模板，`SKILL.md` 草稿现在会写出 runtime inputs、`get_app_state` / semantic `element_index` 优先的 agent replay procedure、observed replay steps 和 verification checklist；单测与 smoke 同步断言这些章节，避免录制到 skill 的 handoff 只剩事件摘要。
- **[Skill Finalization Scaffold]**: 继续对齐官方 Record & Replay skill 的“创建实际可发现 skill”要求，生成的 `SKILL.md` 草稿新增 finalization checklist，明确不能停在 runbook / replay plan，最终化前应读取并完成 `skill-creator` workflow、包含 validation，最终产物应是实际可发现 skill 目录；thin skill 和通用 reference 同步说明这一边界。
- **[Skill Creation Strategy]**: 对齐官方 Record & Replay skill 的生成策略，Swift runtime scaffold、源码 Python scaffold、thin skill 和 reference 都明确生成 skill 前应先检查 connector / API / 专用工具，Computer Use 只用于 UI 依赖、视觉验证或缺少语义工具覆盖的部分。
- **[Skill Readiness]**: 为 Swift runtime summary 和源码 Python summary 增加 `skillReadiness`，输出 `ready` / `needsReview` / `insufficient`、原因和建议下一步；scaffold 生成的 `SKILL.md` 同步展示 workflow readiness，避免录制信息不足时生成看似完整但需要猜测的 skill。
- **[Structured Runtime Inputs]**: Swift runtime summary 和源码 Python summary 现在输出结构化 `runtimeInputs`，从文本输入和 selection 事件提取运行时值候选、目标摘要、长度和敏感标记；runtime Swift scaffold 与源码 Python scaffold 优先用该字段渲染 Runtime Inputs，并保留 action sequence fallback。
- **[Structured Safety Signals]**: Swift runtime summary 和源码 Python summary 现在输出结构化 `safetySignals`，从 `keyboard.submit` 和 target/focused element 的 send/delete/save/upload/publish 等低敏标题关键词提取显式确认线索；runtime Swift scaffold 与源码 Python scaffold 会在 Safety 区块渲染 Confirmation Signals，并把 `hasSafetySignals` 纳入 workflow readiness 的 human review reason。
- **[Thin Skill Safety Handoff]**: `open-computer-use-record-and-replay` thin skill 和通用 `open-computer-use` Record & Replay reference 现在要求 agent 显式消费 `runtimeInputs` / `safetySignals`；standalone thin skill repo scaffold smoke 也断言导出 repo 保留 `safetySignals`、`skillEvidence.hasSafetySignals=true` 和 replay 前显式确认指引。
- **[Summary Truncation Guard]**: Swift runtime summary 和源码 Python summary 现在输出结构化 `summaryLimits`，记录 action sequence、runtime inputs、safety signals、target/focused elements、diagnostics 和截图路径等高容量字段的上限、源计数、保留计数和省略计数；scaffold 会渲染 Summary Limits 并在截断时要求回读原始 `events.jsonl`，避免长录制草稿静默漏步骤。
- **[Blocking Diagnostics Gate]**: Swift runtime summary / validator、源码 Python summary / validator 和 scaffold smoke 现在识别阻断性 `blockingDiagnostics`；当前把 `debug.error` 的 `reason=inputMonitorsUnavailable` 判定为不可用于 skill creation，`skillReadiness.canCreateSkillDraft=false`，`--require-skill-draft` 与 Swift/Python scaffold 都会拒绝生成草稿并要求修权限后重录。
- **[Recording Completion Gate]**: Swift runtime summary / validator、源码 Python summary / validator 和 scaffold smoke 现在识别未完成录制；`state=recording`、`active=true` 或缺少 `session.ended` 都会输出 `recordingIncomplete=true`，`skillReadiness.canCreateSkillDraft=false`，`--require-skill-draft` 与 Swift/Python scaffold 都会拒绝生成草稿并要求先 stop 录制。
- **[Start Event Gate]**: Swift runtime summary / validator、源码 Python summary / validator 和 scaffold smoke 现在识别 start boundary 异常；缺失 `session.started`、重复 `session.started` 或 `session.started` 不是第一条事件都会输出 `sessionStartedCountInvalid` / `sessionStartedNotFirst`，`skillReadiness.status=insufficient` / `canCreateSkillDraft=false`，`--require-skill-draft` 与 Swift/Python scaffold 都会拒绝生成草稿并要求重录。
- **[Final Event Gate]**: Swift runtime summary / validator、源码 Python summary / validator 和 scaffold smoke 现在识别 `session.ended` 后仍继续写事件的 malformed recording；summary 输出 `sessionEndedNotFinal=true` / `sessionEndedIsFinal=false`，`skillReadiness.status=insufficient` / `canCreateSkillDraft=false`，`--require-skill-draft` 与 Swift/Python scaffold 都会拒绝生成草稿并要求重录。
- **[Duplicate Final Event Gate]**: Swift runtime summary / validator、源码 Python summary / validator 和 scaffold smoke 现在识别多个 `session.ended` 的 malformed recording；summary 输出 `sessionEndedCountInvalid=true` / `sessionEndedCount>1`，`skillReadiness.status=insufficient` / `canCreateSkillDraft=false`，`--require-skill-draft` 与 Swift/Python scaffold 都会拒绝生成草稿并要求重录。
- **[Scaffold Validation Gate]**: Swift runtime scaffold 与源码 Python scaffold 现在会在 summary / 写文件前先跑 recording validator 的 skill draft gate；event count、metadata/session alias、路径或截图引用等结构不一致时返回 `recordingValidationFailed` 并拒绝生成草稿，避免坏 recording 只因可摘要而进入 skill draft。
- **[Cancelled Recording Guard]**: 取消录制的 session 会被 summary 标为 `skillReadiness.status=insufficient` / `canCreateSkillDraft=false`；runtime Swift scaffold 与源码 Python scaffold 都拒绝从 cancelled recording 生成 skill 草稿，并由单测和 scaffold smoke 覆盖。
- **[Recording Time Limit Handoff]**: thin skill 与通用 Record & Replay reference 同步官方 handoff：start 成功后结束当前 turn、请用户完成后回来，并告知录制最长 30 分钟；不改变官方兼容 MCP schema。
- **[Start Approval Time Limit]**: OCU 自有开始确认弹窗会显示当前录制时限，默认 `up to 30 minutes`；新增 helper 单测覆盖文案格式，避免独立 UI 漏掉官方 time-limit handoff。
- **[Concurrent Recording Handoff]**: thin skill、通用 reference、设计 handoff 与执行计划同步官方 one-active 语义：重复 start 返回 active session 时，agent 应询问用户要使用当前录制还是等待它结束，不能静默当作本次新录制。
- **[Codex R&R Installer]**: 新增 `open-computer-use install-codex-record-and-replay-mcp`，写入独立 `record_and_replay` MCP server，启动 `open-computer-use event-stream mcp`；普通 9-tool Computer Use 仍由 `install-codex-mcp` 安装，避免两个 surface 混在一起。
- **[Installer Smoke]**: 新增 `scripts/test-codex-record-and-replay-installer.mjs` 和 `make codex-record-and-replay-installer-smoke`，用临时 `CODEX_HOME` 验证 TOML 写入 `args = ["event-stream","mcp"]` 和重复执行幂等；该 smoke 已接入默认 CI。
- **[Input Handler Recording]**: 新增 `testEventStreamServiceRecordsInputMonitorMouseAndKeyboardEvents`，通过自定义 input monitor installer 捕获 recorder 注册的 mouse/key handlers，再喂入构造的 `NSEvent`，验证 `mouse.click` 和 `keyboard.text_input` 经真实 handler 路径写入 `events.jsonl`。
- **[Raw Event Safety]**: 修正 raw event summary 对 AppKit event 属性的读取边界：`phase` / `momentumPhase` 只读 scroll event，`clickCount` 只读 pointer event，keyDown 不再附带无意义 AppKit 坐标，避免不支持属性的 `NSEvent` 抛 exception。
- **[Standalone Thin Repo Scaffold]**: 新增 `scripts/scaffold-record-and-replay-skill-repo.py`，把仓库内 `open-computer-use-record-and-replay` thin skill 导出成只依赖 `open-computer-use` runtime 的独立 repo 骨架；新增 `scripts/test-record-and-replay-skill-repo-scaffold.py` 和 `make record-and-replay-skill-repo-smoke`，校验生成物可打包 `.skill`、不泄漏本机源码路径，并固定 `event-stream mcp` 三件套 runtime contract。
- **[Standalone Runtime Verification]**: standalone thin skill repo scaffold 现在会生成 `scripts/verify-runtime.py`；smoke 会构建当前 `OpenComputerUse` binary，并在生成态 repo 内运行 verifier，按 initialize / `notifications/initialized` / `tools/list` 顺序实际检查 `Record & Replay` server name、`2025-11-25` protocol、无 `instructions` initialize response，以及 `event_stream_start/status/stop` 三个无参数 tools。
- **[Standalone Repo Self Check]**: standalone thin skill repo scaffold 现在会生成 `scripts/check.sh`，串起 `scripts/package-skill.sh` 和 `scripts/verify-runtime.py`；smoke 会在生成态 repo 内运行该组合门禁，固定发布或安装前的最小自检入口。
- **[Standalone Repo CI]**: standalone thin skill repo scaffold 现在会生成 `.github/workflows/ci.yml`，使用 SHA-pinned `actions/checkout` 和 `actions/setup-node`，在 macOS runner 中安装发布版 `open-computer-use` 后运行 `scripts/check.sh`；smoke 会检查 workflow 调用同一自检入口且所有 `uses:` 都 pin 到 40 位 SHA。
- **[Standalone Package Frontmatter Gate]**: standalone thin skill repo 生成态 `scripts/package-skill.sh` 现在会校验 `skills/*/SKILL.md` 的 frontmatter，要求 `name` 匹配目录名且 `description` 非空；smoke 会临时清空 description 并确认 package script 失败，再恢复后继续打包。
- **[Standalone Surface Contract]**: standalone thin skill repo 生成态 `scripts/verify-runtime.py` 现在不只检查三件套 tool 名称，还校验官方兼容的 initialize capabilities、tool description、empty input schema 和 MCP annotations；`record-and-replay-skill-repo.json` 同步写入 `capabilities` / `toolMetadata`，smoke 覆盖 manifest 和 verifier 内容。
- **[Standalone Lifecycle Smoke]**: standalone thin skill repo scaffold 现在会生成可选 `scripts/recording-lifecycle-smoke.py`；它通过同一 `event-stream mcp` 进程执行 start/repeat start/status/stop/repeat stop/final status，检查 one-active、idempotent stop、completed status、`metadata.json` / `session.json` / `events.jsonl`，并用安装态 runtime `event-stream validate --strict-ocu` 校验 session 文件。`make record-and-replay-skill-repo-smoke` 会用当前构建出的 `OpenComputerUse` binary 实际运行该脚本，但生成 repo 默认 `scripts/check.sh` 和 CI workflow 仍保持 non-recording contract check。
- **[Standalone Recording Handoff README]**: standalone thin skill repo 生成态 README 现在固定 recording-to-skill handoff 指引：完整 OCU session 先跑 `validate --strict-ocu --require-skill-draft <metadataPath-or-sessionPath>`，只有 `eventsPath` 时跑非 strict events-only gate；取消或未完成 recording 不能用于创建或更新 skill，且 generated scaffold 也会先跑 skill-draft validation gate。smoke 已断言这些指引随独立 repo 导出。
- **[Standalone Recording-To-Skill Smoke]**: standalone thin skill repo scaffold 现在会生成 `scripts/recording-to-skill-smoke.py` 并接入默认 `scripts/check.sh`；该 smoke 使用临时合成 completed recording 验证安装态 runtime 的 strict skill-draft validation、events-only validation 和 `event-stream scaffold-skill --json` 草稿生成路径，不需要启动真实桌面录制。`make record-and-replay-skill-repo-smoke` 会单独运行该脚本，也会通过生成态 `check.sh` 再跑一次。
- **[Standalone Declared Path Self-Check]**: 生成态 `scripts/recording-to-skill-smoke.py` 现在会检查 strict validator 输出的 `declaredPaths`，要求 `metadataPath` / `sessionPath` / `eventsPath` / `suppressedEventsPath` 四个 handoff path 都解析存在；README、thin skill 和通用 reference 同步说明 strict OCU validation 能证明 declared handoff paths，而 events-only gate 不能证明。
- **[Standalone Recording-To-Skill Contract]**: standalone thin skill repo manifest 新增 `recordingToSkill` 区块，机器可读声明 strict validation、events-only validation 和 scaffold-skill 的 handoff 边界，包括 strict 必须证明 declared handoff paths、events-only 不能证明 alias/path，以及 scaffold 会先跑 skill draft validation gate。
- **[Standalone Skill Workflow Verification]**: standalone thin skill repo scaffold 新增生成态 `scripts/verify-skill-workflow.py`，并接入默认 `scripts/check.sh` 和 manifest `checks.skillWorkflow`；该 verifier 不启动录制，只检查 thin skill 保留官方 handoff 语义：只用 `event_stream_start/status/stop` 三件套、start 后结束 turn、不轮询、用户完成后 stop、取消后不再 stop，以及 validate/summarize/scaffold 前置门禁。smoke 会验证正常通过和移除关键文案后的失败路径。
- **[Standalone Wait Notify Contract]**: standalone thin skill repo scaffold 的生成态 manifest 新增 `extensionLayer`，显式声明 `wait --notify-command`、`waitTimedOut` / `waitSessionMatched`、notify stdin/env 和 listener 不属于官方兼容 MCP surface；生成态 README 与 `scripts/verify-skill-workflow.py` 同步守住 Independent Wait / Notify Integration，smoke 覆盖 manifest、正向校验和删除关键 env 文案后的失败路径。
- **[Standalone Wait Notify Smoke]**: standalone thin skill repo scaffold 新增生成态 `scripts/wait-notify-contract-smoke.py`，并接入默认 `scripts/check.sh` 与 manifest `checks.waitNotifyContractSmoke`；该 smoke 不启动真实录制，只等待不存在的 session，断言安装态 CLI 返回 `waitTimedOut=true` / `waitSessionMatched=false`、notify callback 被跳过，且不会创建 `latest-session.json` / `active-session.json`。
- **[NPM Standalone Repo Scaffold]**: npm staging 包现在携带 `scripts/scaffold-record-and-replay-skill-repo.py` 和 `skills/open-computer-use-record-and-replay/`，launcher 新增 `open-computer-use scaffold-record-and-replay-skill-repo --output-dir <dir>`；安装态无需源码 checkout 即可生成 standalone Record & Replay thin skill repo 骨架，并继续通过生成态 `scripts/verify-skill-workflow.py` 自检官方 handoff 语义。
- **[NPM Standalone Repo Smoke]**: 新增 `scripts/test-npm-record-and-replay-skill-repo-scaffold.mjs` 和 `make npm-record-and-replay-skill-repo-smoke`；该 opt-in smoke 用本地 `dist/` artifacts stage `open-computer-use` npm 包，再通过 staged launcher 执行安装态 scaffold 命令，验证生成 repo 包含 workflow verifier 且 package script 可产出 `.skill`。
- **[NPM Scaffold UX]**: 安装态 launcher 为 `scaffold-record-and-replay-skill-repo` 补专用 help，明确它生成 standalone repo 而不是更新 MCP/plugin config；同时增加 Python 3 解析和缺失诊断，优先使用 `PYTHON`，再按平台尝试系统 Python，并在 npm staging smoke 中覆盖 help 文案和 missing Python failure。
- **[NPM Python Gate]**: 安装态 launcher 现在会解析 `python --version` 并只接受 Python 3，避免旧环境中 `python` 指向 Python 2 时进入 scaffold 脚本后才失败；npm staging smoke 增加 fake Python 2 executable，覆盖非 Python 3 候选会被拒绝。
- **[Action Smoke Skill Handoff]**: 真实输入 action smoke 现在会检查 runtime scaffold 生成的 skill 草稿保留 `skill-creator` finalization 指引，并明确不能停在 standalone runbook / replay plan，防止“能录制、能生成文件”但不满足官方 recording-to-skill handoff。
- **[Standalone Skill Creator Handoff]**: standalone thin skill repo scaffold 生成的 `scripts/recording-to-skill-smoke.py` 也会检查 runtime scaffold 草稿保留 `skill-creator` finalization 指引和非 runbook/replay-plan 文案，并在 smoke JSON 中输出 `checkedSkillCreatorHandoff=true`，让独立 repo 默认 `scripts/check.sh` 守住同一 handoff 语义。
- **[NPM Standalone Repo Self-Check]**: npm staging smoke 现在会让 staged launcher 生成 standalone repo 后运行生成态 `scripts/check.sh`，并把 `OPEN_COMPUTER_USE_CLI` 指向同一个 staged launcher；这会在安装态路径下同时验证 package、runtime contract、skill workflow、合成 recording-to-skill scaffold 和 `skill-creator` handoff。
- **[NPM Recording-To-Skill Contract]**: npm staging smoke 现在会先用 staged launcher 校验合成 recording，确认 strict validator 已输出 `declaredPaths`，再读取安装态生成 repo 的 `record-and-replay-skill-repo.json`，断言 `recordingToSkill` contract 保留 strict validation、events-only validation 和 scaffold-skill 的机器可读边界，避免 npm scaffold 路径丢失 standalone recording-to-skill 合同。
- **[NPM Smoke Verification]**: 本地刷新 `dist/Open Computer Use.app` 后，`make npm-record-and-replay-skill-repo-smoke` 已通过；该结果证明当前 staged npm launcher 可以携带 strict `declaredPaths` validator evidence 走完整 standalone repo 默认自检。
- **[Baseline Verification]**: 当前 worktree 复跑 `make event-stream-smoke-matrix`、`make event-stream-action-smoke` 和 `scripts/compare-event-stream-surface.py --use-default-official` 均通过，覆盖无真实输入的 lifecycle 矩阵、真实 CGEvent 输入录制到 skill 草稿链路，以及 OCU / 官方 1.0.857 non-recording surface drift。
- **[Baseline Smoke Target]**: 新增 opt-in `make record-and-replay-baseline-smoke`，把默认 matrix、真实输入 action smoke、官方 1.0.857 non-recording surface 对比、standalone thin skill repo smoke 和 npm standalone repo smoke 串成一个本机候选验证入口；该入口不进默认 CI，因为它依赖桌面输入权限、官方 bundled cache 和当前 `dist/` artifacts。本机已复跑通过。
- **[Default CI Verification]**: 复跑 `make ci` 通过，覆盖文档/仓库卫生、脚本语法、skill 打包、Record & Replay 默认 smoke、Swift 单测、默认 matrix 和 Windows / Linux Go test；真实输入 action 与 npm staging baseline 继续由 opt-in baseline smoke 覆盖。
- **[Official No-Active Response]**: 通过 Codex-hosted 官方 Record & Replay `event_stream_status` / `event_stream_stop` 观察到 no-active text JSON 只有 `isRecording=false` 和 `maxDurationSeconds=1800`；OCU MCP no-active status/stop 已按该 shape 校准，CLI 扩展仍保留本地诊断字段。
- **[Standalone No-Active Runtime Contract]**: standalone thin skill repo 生成态 `scripts/verify-runtime.py` 现在也会在临时 recording root 下调用 no-active `event_stream_status` / `event_stream_stop`，确认返回官方 `isRecording=false` / `maxDurationSeconds=1800` shape 且不会创建 session 文件；生成态 manifest 同步写入 `mcpServer.noActiveResponse`。
- **[Official Surface Recheck]**: 复跑 `scripts/compare-event-stream-surface.py --use-default-official`，确认 OCU 本地 `event-stream mcp` 与官方 `record-and-replay/1.0.857` 默认 cache 的 initialize / `tools/list` 仍匹配已入库 fixture；该检查不启动录制，只验证 non-recording surface。
- **[CGEvent Tap Input]**: EventStream 生产录制路径从单纯 `NSEvent.addGlobalMonitorForEvents` 升级为优先安装 listen-only `CGEvent` tap，失败时再回退到 NSEvent monitor；这更接近 Record & Replay 对 session 输入流的需求，也能捕获外部进程发出的 HID click 和 keyboard event。
- **[Action Smoke]**: 新增 `make event-stream-action-smoke` / `OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTIONS=1`，启动 app-agent recorder 后由外部 Swift 进程发出低影响 CGEvent click 和 Shift-F20 keyboard event，停止后用 validator / summary 要求 `mouse.click`、`keyboard.shortcut`、`AX.focusedWindowChanged`、`session.ended` 入流；该 smoke 现在还会用同一份真实录制产物调用 runtime `event-stream scaffold-skill --json` 生成 `SKILL.md` 草稿，并断言草稿 / `recording-summary.json` 不含本机绝对路径、summary 路径字段使用 `<recording-*>` 占位且 `skillReadiness.canCreateSkillDraft=true`，覆盖真实输入录制到路径脱敏 skill 草稿的端到端链路。该 smoke 为 opt-in，不进入默认 CI。

### 🔁 Follow-up (2026-06-27, fixture-backed no-active drift check)

- **[No-Active Fixture Check]**: 新增 `scripts/compare-event-stream-no-active.py` 和 `make event-stream-no-active-smoke`，用 Codex-hosted 官方 1.0.857 no-active fixture 校验本地 OCU MCP `event_stream_status` / `event_stream_stop` text JSON，固定 `isRecording=false` / `maxDurationSeconds=1800` shape。
- **[No Session Side Effect]**: 新检查使用临时 recording root，断言 no-active status/stop 不会创建 `latest-session.json`、`active-session.json` 或 session 目录，避免官方 idle response 校准引入隐式状态写入。
- **[CI Sync]**: 将 no-active drift check 接入 `scripts/ci.sh`，并同步 Makefile、architecture、CI/CD、execution plan、reverse-engineering reference、handoff 和 quality score。

### 🔁 Follow-up (2026-06-27, strict OCU current segment gate)

- **[Current Segment Validation]**: runtime Swift validator 与源码 Python validator 新增 strict OCU current segment path gate；`state=recording` 必须带存在的 `currentSegmentEventsPath` / `currentSegmentMetadataPath`，`state=stopped|cancelled` 不能残留这两个字段。
- **[Runtime/Source Parity]**: `scripts/test-event-stream-skill-scaffold.py` 同时覆盖源码脚本和安装态 runtime CLI 的缺失 / 残留拒绝路径，避免独立 skill scaffold 只在源码 checkout 下有 gate。
- **[Scope Note]**: 该 gate 固定 OCU 自身 active/final session 文件一致性，不把 current segment 字段视为已完成的官方 successful recording schema；最终字段语义仍待 official golden fixtures 校准。

### 🔁 Follow-up (2026-06-27, local probe sanitization gate)

- **[Probe Fixture Redaction]**: `scripts/probe-event-stream-recording.py --fixture-output` 现在会把 MCP text content 中可解析的 JSON 转成脱敏 `textJSON`，避免 start/status/stop response text 里保留本机绝对路径。
- **[Local Probe Smoke]**: 新增 `scripts/test-event-stream-local-probe.py` 和 `make event-stream-local-probe-smoke`，用真实本地 OCU `event-stream mcp` 采集 start/status/stop transcript，固定 active response 带 current segment 字段、final response 不残留 current segment 字段、fixture 不含本机路径，并用源码 validator 与 runtime validator 校验最终 session 文件。
- **[CI Sync]**: 将 local probe smoke 接入默认 `scripts/ci.sh`，并同步 Makefile、CI/CD、architecture、execution plan、reverse-engineering reference 和 quality score。

### 🔁 Follow-up (2026-06-27, repeat-start probe evidence)

- **[Probe One-Active Evidence]**: `scripts/probe-event-stream-recording.py --start-stop` 的采样顺序扩展为 start / repeat start / status / stop；首次 start 成功后立即再次调用 `event_stream_start`，用于保存 one-active 语义证据。
- **[Local Probe Assertion]**: `scripts/test-event-stream-local-probe.py` 现在断言两次 start 返回同一个 active session，并继续校验 current segment 脱敏和 final cleanup。
- **[Fixture Shape]**: probe fixture 新增 `repeatStartResponseShape`，由 fake MCP server test 覆盖脱敏后的 repeat start response；首个 start 超时时仍保持官方 raw start-timeout fixture 的旧边界，不强行采集 repeat start。

### 🔁 Follow-up (2026-06-27, completed lifecycle probe evidence)

- **[Probe Completed Evidence]**: `scripts/probe-event-stream-recording.py --start-stop` 现在在首次 stop 成功后继续调用 repeat stop 和 final status，采样顺序变为 start / repeat start / status / stop / repeat stop / final status。
- **[Local Probe Assertion]**: `scripts/test-event-stream-local-probe.py` 断言 repeat stop 和 final status 仍返回同一个 completed session，覆盖 idempotent stop 与 completed status 证据。
- **[Fixture Shape]**: probe fixture 新增 `repeatStopResponseShape` 和 `finalStatusResponseShape`；首个 start 超时时仍保持官方 raw start-timeout fixture 的旧边界，不强行采集 completed lifecycle。

### 🔁 Follow-up (2026-06-27, golden readiness lifecycle shapes)

- **[Readiness Shape Gate]**: `scripts/check-event-stream-golden-readiness.py` 新增 `--require-mcp-response-shape`，可显式要求 `repeatStartResponseShape`、`repeatStopResponseShape` 和 `finalStatusResponseShape` 这类 raw probe completed lifecycle 证据。
- **[Timeout Semantics]**: required response shape 缺失、timeout 或没有 result/error 会独立失败；timeout 错误使用 `MCP response shape timed out: <shape>`，避免宿主外边界样本被误判成 successful response golden。
- **[Tool/Shape Split]**: tool 级 `--require-mcp-tool-response event_stream_*` 现在按“该 tool 至少有一次 result/error”聚合；同一 tool 的 repeat shape timeout 不会污染已成功的 tool response，具体 repeat lifecycle 仍由 `--require-mcp-response-shape` 单独要求。
- **[Fixture Import Coverage]**: fixture import smoke 增加 repeat start / repeat stop / final status shape 脱敏断言，确认 MCP text JSON 仍会被解码成相对路径和脱敏 session id。

### 🔁 Follow-up (2026-06-27, compare MCP response shapes)

- **[Compare Shape Gate]**: `scripts/compare-event-stream-recordings.py` 新增可选 `--require-mcp-response-shapes`，当 baseline 与 candidate 都带 `mcp-transcript.json` 时，比较 start/repeat/status/stop/final response shape 是否存在并保持 result/error/timeout 状态。
- **[Schema Gate]**: 新增 `--require-same-mcp-response-schema`，在 shape 存在和状态一致之外要求 candidate response shape 保留 baseline 的 schema path/type，避免 response text JSON 字段在 OCU candidate 中静默丢失。
- **[Smoke Coverage]**: `scripts/test-event-stream-recording-compare.py` 覆盖 matching transcript 通过、缺 repeat start shape、repeat start timeout 状态漂移和 repeat start response schema 缺失失败路径。

### 🔁 Follow-up (2026-06-27, fixture import calibration chain)

- **[Import-To-Gate Smoke]**: `scripts/test-event-stream-fixture-import.py` 现在会把脱敏导入后的 fixture 继续交给 golden readiness response-shape gate 和 recording compare MCP response shape/schema gate，证明 `mcp-transcript.json` 的 sanitized response shape 可以被后续官方/OCU 校准链路直接消费。
- **[Readiness Chain]**: 同一 smoke 要求导入产物通过 `repeatStartResponseShape`、`repeatStopResponseShape` 和 `finalStatusResponseShape` 的 readiness shape gate，避免 fixture import 只验证文件脱敏、不验证 lifecycle response evidence 可用性。
- **[Compare Chain]**: 同一 smoke 用导入 fixture 自比并打开 `--require-mcp-response-shapes --require-same-mcp-response-schema`，固定 response shape evidence 与 schema gate 的输入合同。

### 🔁 Follow-up (2026-06-27, suppressed stream compare)

- **[Suppressed Compare Gate]**: `scripts/compare-event-stream-recordings.py` 现在读取 `suppressed.jsonl`，输出 suppressed event sequence、count diff 和 schema diff，并新增 `--require-same-suppressed-event-sequence` / `--require-same-suppressed-schema` 两个 gate。
- **[Fallback Evidence Coverage]**: `scripts/test-event-stream-recording-compare.py` 增加 candidate 缺 suppressed event 和 suppressed schema 缺字段失败路径，避免后续官方样本中的 AX / screenshot / 压缩降级证据只通过 `suppressedEventCount` 间接覆盖。

### 🔁 Follow-up (2026-06-27, readiness suppressed evidence)

- **[Readiness Suppressed Gate]**: `scripts/check-event-stream-golden-readiness.py` 新增 `--require-suppressed-events` 和 `--require-suppressed-event-type`，动作类或 fallback 校准样本可以显式要求 `suppressed.jsonl` 中存在指定降级证据。
- **[Fixture Path Redaction]**: `scripts/import-event-stream-fixture.py` 现在会脱敏事件和 suppressed event 中的通用 `path` / 未知 `*Path` 字段，只保留 redacted marker 和长度，避免非标准字段泄漏本机路径。
- **[Smoke Coverage]**: `scripts/test-event-stream-fixture-import.py` 和 `scripts/test-event-stream-golden-readiness.py` 覆盖 suppressed event 脱敏、suppressed evidence readiness gate，以及导入 fixture 后继续通过 readiness / compare 校准链路。

### 🔁 Follow-up (2026-06-27, readiness endReason gate)

- **[EndReason Readiness Gate]**: `scripts/check-event-stream-golden-readiness.py` 新增 `--require-end-reason <reason>`，从 metadata/session alias 和 `session.ended.endReason` 汇总 `endReasons`，用于官方 stop / cancel / timeout golden fixture 入库时显式固定 expected completion reason。
- **[Smoke Coverage]**: `scripts/test-event-stream-golden-readiness.py` 覆盖 required `recording_controls_stopped` 通过和 required `recording_controls_cancelled` mismatch 失败路径，避免 control completion reason 只靠人工审查。

### 🔁 Follow-up (2026-06-27, readiness final session evidence)

- **[Session End Readiness Gate]**: `scripts/check-event-stream-golden-readiness.py` 现在默认拒绝多个 `session.ended` 或 `session.ended` 后仍继续写入事件的 malformed fixture，并输出 `lastEventType`、`sessionEndedCount` 和 `sessionEndedIsFinal` 供 JSON 报告审查。
- **[Smoke Coverage]**: `scripts/test-event-stream-golden-readiness.py` 覆盖 duplicate `session.ended` 和 non-final `session.ended` 失败路径，避免坏 lifecycle recording 被误判为 official/OCU golden baseline。

### 🔁 Follow-up (2026-06-27, readiness session alias evidence)

- **[Session Alias Readiness Gate]**: `scripts/check-event-stream-golden-readiness.py` 现在读取并报告 `metadata.json` / `session.json` alias 状态，输出 `metadataSessionAliasComplete` 和 `metadataSessionAliasMatches`，默认拒绝两者同时存在但内容不同的 fixture。
- **[Required Alias Coverage]**: readiness 新增 `--require-session-alias`，用于官方 handoff golden fixture 入库时强制要求 `metadata.json` 和 `session.json` 两份 alias 都存在且一致。
- **[Smoke Coverage]**: `scripts/test-event-stream-golden-readiness.py` 覆盖 ready fixture alias 通过、缺失 `session.json` alias 失败和 alias 内容漂移失败路径。

### 🔁 Follow-up (2026-06-27, readiness metadata counts)

- **[Metadata Count Readiness Gate]**: `scripts/check-event-stream-golden-readiness.py` 现在报告 `metadataEventCount` / `metadataSuppressedEventCount` 和对应 match 状态，并默认拒绝已声明但与 `events.jsonl` / `suppressed.jsonl` 行数不一致的 metadata count。
- **[Required Count Coverage]**: readiness 新增 `--require-metadata-counts`，用于官方 handoff golden fixture 入库时强制要求 `eventCount` 和 `suppressedEventCount` 都存在且与文件行数一致。
- **[Manifest Suppressed Count]**: readiness 现在也校验 fixture manifest 的 `suppressedEventCount`，避免 fallback evidence 计数只在 metadata 中被检查。
- **[Smoke Coverage]**: `scripts/test-event-stream-golden-readiness.py` 覆盖 metadata event count 漂移、缺失 metadata counts 和 manifest suppressed count 漂移失败路径。

### 🔁 Follow-up (2026-06-27, readiness handoff paths)

- **[Declared Path Evidence]**: `scripts/check-event-stream-golden-readiness.py` 现在输出 `declaredPaths`，记录 metadata 中 `metadataPath`、`eventsPath`、`sessionPath` 和 `suppressedEventsPath` 的原始值、解析路径和存在性。
- **[Default Drift Gate]**: readiness 默认拒绝已经声明但不存在的 handoff path，避免官方 fixture 只证明文件内容、不证明 skill handoff 返回路径可消费。
- **[Required Path Coverage]**: readiness 新增 `--require-handoff-paths`，用于官方 handoff golden fixture 入库时强制要求四个路径字段都存在且指向可读产物。
- **[Smoke Coverage]**: `scripts/test-event-stream-golden-readiness.py` 覆盖 ready fixture path 通过、缺失 handoff path 字段、`sessionPath` 指向不存在文件和 `eventsPath` 指向不存在 JSONL 的失败路径。

### 🔁 Follow-up (2026-06-27, compare handoff paths)

- **[Compare Path Evidence]**: `scripts/compare-event-stream-recordings.py` 现在输出 `handoffPathEvidence`，分别记录 baseline 和 candidate 的 `metadataPath`、`eventsPath`、`sessionPath`、`suppressedEventsPath` 解析状态。
- **[Candidate Path Gate]**: recording compare 新增 `--require-handoff-paths`，要求 baseline 和 candidate 都声明四个 handoff path 且解析后文件存在；该 gate 不比较路径字符串本身，避免不同 fixture/candidate 目录导致误报。
- **[Smoke Coverage]**: `scripts/test-event-stream-recording-compare.py` 覆盖相同样本 path 通过、candidate 缺 `sessionPath` 失败和 candidate `suppressedEventsPath` 指向不存在文件失败路径。

### 🔁 Follow-up (2026-06-27, scroll raw action smoke)

- **[Scroll Raw Coverage]**: `make event-stream-action-smoke` 现在除了外部 HID click 和 Shift-F20 keyboard event，也会发出真实 CG scroll wheel event。
- **[No Synthetic Scroll Type]**: 由于当前官方字符串样本还没有确认独立 scroll event 名称，smoke 只要求 `type=experimentalRawEvents` / `reason=scrollWheel` / raw `eventType=scrollWheel` 入流，不臆造 `mouse.scroll`。
- **[Recording-To-Skill Continuity]**: Swift/Python summary 与 scaffold 现在会把 `reason=scrollWheel` 的 raw-only event 纳入 `actionSequence` 并渲染为 Scroll replay step；同一 smoke 继续要求 validator、summary 和 runtime scaffold 通过，确保补 scroll raw evidence 不破坏录制到 skill 草稿的路径脱敏 handoff。

### 🔁 Follow-up (2026-06-27, baseline smoke script)

- **[Reusable Gate]**: 新增 `scripts/run-record-and-replay-baseline-smoke.sh`，把 baseline 候选验证顺序从 Makefile 命令串收敛成可复用脚本。
- **[Make Entrypoint]**: `make record-and-replay-baseline-smoke` 现在只转调该脚本，后续独立 repo、release gate 或人工验收可以直接复用同一入口。
- **[Machine Summary]**: 脚本成功时输出 `{"ok":true,"baseline":"record-and-replay",...}` JSON 摘要，便于上层脚本判断组合 baseline 已完成。
- **[Fixture Set Coverage]**: baseline 脚本现在也运行 `scripts/test-event-stream-official-fixture-set.py`，确保 official successful recording 入库后的集合级 gate 在 opt-in baseline 候选验证中被覆盖。
- **[Verification]**: 已复跑 `make record-and-replay-baseline-smoke`，覆盖默认 matrix、真实输入 action smoke、官方 1.0.857 surface compare、official fixture set gate smoke、standalone repo smoke 和 npm staged repo smoke。

### 🔁 Follow-up (2026-06-27, official fixture set gate)

- **[Scenario Manifest]**: `scripts/import-event-stream-fixture.py` 新增 `--scenario <scenario>`，把官方/OCU fixture 的机器可读场景写入 manifest，避免后续靠目录名或人工上下文配对。
- **[Set-Level Gate]**: 新增 `scripts/check-event-stream-official-fixture-set.py`，默认要求 official fixture set 至少包含 `simple-action-stop` successful recording，并对 official 样本运行 strict readiness。
- **[Candidate Pairing]**: fixture set gate 支持 `--candidate-root`，按同 scenario 找 OCU candidate，并用 recording compare 固定 event sequence、schema、metadata keys/values、handoff paths、final session evidence、semantic fields 和 MCP response shape。
- **[Scenario Policies]**: `simple-action-stop` 现在要求 `mouse.click` 与 `recording_controls_stopped` endReason，`keyboard-input-stop` 要求 `keyboard.text_input` 与 `recording_controls_stopped` endReason，`drag-stop` 要求 `mouse.drag` 与 `recording_controls_stopped` endReason，`cancel` 要求 `recording_controls_cancelled` endReason；`timeout` 因官方 endReason 未观测，暂不固定具体值。
- **[Smoke Coverage]**: 新增 `scripts/test-event-stream-official-fixture-set.py` / `make event-stream-official-fixture-set-smoke`，覆盖 gate 成功、缺 candidate、缺 scenario 和导入 `--scenario` 写 manifest。
- **[Verification]**: 已复跑 `make event-stream-official-fixture-set-smoke`、`make event-stream-fixture-smoke`、`make event-stream-golden-readiness-smoke` 和 `make event-stream-compare-smoke`。

### Follow-up (2026-06-27, timeout official scenario policy smoke)

- **[Timeout Policy Evidence]**: `scripts/test-event-stream-official-fixture-set.py` 新增 `timeout` 场景 lifecycle-only fixture，验证该 scenario 只要求 `session.started` / `session.ended` 与 MCP transcript，不要求 action event 或 AX payload，也不提前固定尚未观测的官方 timeout endReason。
- **[Baseline Evidence]**: `scripts/run-record-and-replay-baseline-smoke.sh` 现在强制读取并输出 `checkedTimeoutScenarioPolicy`，避免 opt-in baseline 摘要只证明 stop / keyboard / drag / cancel policy。
- **[Docs]**: 同步更新 handoff、replication design、reverse-engineering reference、architecture 和 quality score，明确 timeout gate 仍是待官方 golden 校准的生命周期策略。
- **[Verification]**: 已复跑 `make record-and-replay-baseline-smoke` 通过，最终摘要包含 default matrix、真实输入 action smoke、官方 1.0.857 non-recording surface compare、official fixture set gate、standalone repo smoke 和 npm staged repo smoke；同一摘要中 `checkedTimeoutScenarioPolicy=true`，但 `repoHasRequiredOfficialSuccessfulFixture=false`，继续明确真实 official successful recording 尚未入库。

### 🔁 Follow-up (2026-06-27, official start probe refresh)

- **[Official Probe]**: 复跑 `make event-stream-official-start-probe`，官方 bundled 1.0.857 raw MCP client 仍只正常返回 initialize / tools-list。
- **[Start Timeout]**: 裸 `event_stream_start`、后续 `event_stream_status` 和 `event_stream_stop` 均 10 秒超时，没有返回 metadata/events/session paths，也没有可导入 official successful recording。
- **[Fixture Refresh]**: 刷新 `record-and-replay-official-raw-start-timeout-1.0.857.json`，sanitized fixture 现在显式包含 `startResponseShape`、`statusResponseShape` 和 `stopResponseShape` 三个 10 秒 timeout；`scripts/test-event-stream-probe-fixtures.py` 同步要求 transcript 中恰好三次 `tools/call` timeout，避免官方宿主外边界证据退回旧的 start/stop-only 形态。
- **[Current Baseline Verification]**: 刷新 fixture 后复跑默认 `make ci` 和 opt-in `make record-and-replay-baseline-smoke` 均通过；后者覆盖默认 event-stream matrix、真实输入 action smoke、官方 1.0.857 surface compare、official fixture set gate、standalone repo smoke 和 npm staged repo smoke。
- **[User-Facing Quickstart]**: README 和 README.zh-CN 新增 Record & Replay 快速开始，覆盖 dedicated R&R MCP 安装、官方三件套 surface、OCU CLI wait/notify、validate/summarize/scaffold-skill 以及 standalone thin skill repo scaffold 自检入口。
- **[Calibration Boundary]**: official successful recording fixture 仍需要通过正常 Codex 宿主流程，或先补齐官方 runtime 所需宿主状态后再采集。

### 🔁 Follow-up (2026-06-27, recording controls callback coverage)

- **[Controls Callback Coverage]**: `EventStreamRecordingControls` 新增测试探针，保持 panel 私有，但允许单测按按钮标题触发内部 NSButton action。
- **[Done / Discard Evidence]**: 新增 `testEventStreamRecordingControlsButtonsTriggerRuntimeCallbacks`，验证 Done 只触发 stop callback，Discard 只触发 cancel callback，补齐 OCU 自有控制条点击直接进入 runtime 的按钮级证据。
- **[Verification]**: 已复跑 `swift test --filter testEventStreamRecordingControlsButtonsTriggerRuntimeCallbacks` 通过。

### 🔁 Follow-up (2026-06-27, wait notify failure coverage)

- **[Notify Failure Coverage]**: 新增 wait notify 回调失败回归，验证 callback 非零退出时 `notification.ok=false`、`reason=nonZeroExit`、保留 exit code，并让 `runOpenComputerUseEventStream` 返回 `hasToolError=true`。
- **[Notify Timeout Coverage]**: 新增 wait notify 回调超时回归，验证 `OPEN_COMPUTER_USE_EVENT_STREAM_NOTIFY_TIMEOUT_SECONDS` 生效，超时 callback 会被终止并返回 `reason=timeout`、`timedOut=true`、`hasToolError=true`。
- **[Verification]**: 已复跑 `swift test --filter testRunEventStreamCLIWaitReportsNotifyCommand` 通过。

### 🔁 Follow-up (2026-06-27, event-stream CLI error exit)

- **[CLI Exit Semantics]**: 修正 `open-computer-use event-stream ...` 入口，打印 JSON 后如果 `OpenComputerUseCallOutput.hasToolError=true` 会和普通 `call` 命令一样以非零退出码结束。
- **[Standalone Contract]**: 生成态 `scripts/wait-notify-contract-smoke.py` 新增合成 completed session，用 `--notify-command` 的非零退出验证 JSON `notification.reason=nonZeroExit`、`exitCode=7`，并断言 CLI 退出码非零。该检查不启动真实桌面录制。
- **[Verification]**: 已复跑 `swift build --product OpenComputerUse`、`swift test --filter testRunEventStreamCLIWaitReportsNotifyCommand` 和 `make record-and-replay-skill-repo-smoke` 通过。

### 🔁 Follow-up (2026-06-27, recording-to-skill failure exit)

- **[Standalone Recording-To-Skill Failure Contract]**: 生成态 `scripts/recording-to-skill-smoke.py` 新增无动作 recording 负例，验证安装态 `event-stream scaffold-skill --json` 会输出 `ok=false` 且 CLI 退出码非零，避免独立 repo 的 shell/CI 只看 JSON 文本而误判失败 scaffold 为成功。
- **[Scaffold Smoke Assertion]**: `scripts/test-record-and-replay-skill-repo-scaffold.py` 现在断言生成态 smoke JSON 暴露 `checkedScaffoldSkillFailureExit=true`，确保该契约随 standalone repo scaffold 一起导出。

### 🔁 Follow-up (2026-06-27, recording controls frame clamp)

- **[Controls Placement]**: OCU 自有 Record & Replay 控制条的初始定位改为使用可测试的 visible-frame clamp，常规屏幕居中贴近顶部，多显示器负坐标、窄屏或高度不足时会尽量保持在可见区域内。
- **[Controls Coverage]**: 新增控制条 frame helper 单测，覆盖常规可见区域、负坐标窄屏和高度不足屏幕，避免独立交互录制入口在非主流屏幕布局下把 Done / Discard 控制放到不可见位置。

### 🔁 Follow-up (2026-06-27, event-stream no-arg contract)

- **[MCP Runtime Contract]**: `event_stream_start/status/stop` 的运行时 dispatcher 现在会拒绝非 object `arguments` 和非空 object `arguments`，与 tools/list 中 `additionalProperties=false` 的空 object schema 保持一致；错误通过既有 tool error 通道返回，不改变官方三件套 surface。
- **[No Side Effect Coverage]**: 新增 MCP 单测，验证 `event_stream_status` 携带意外字段、`event_stream_start` 携带非 object 参数时都返回 `isError=true`，并且不会创建 `latest-session.json` 或 `active-session.json`。
- **[Standalone Contract]**: standalone thin skill repo 的生成态 manifest 新增 `mcpServer.requiresObjectArguments=true` 和 `mcpServer.rejectsUnexpectedArguments=true`，`scripts/verify-runtime.py` 也会实际调用带意外参数的 `event_stream_status` 和带数组参数的 `event_stream_start` 并断言 tool error，确保独立 repo 默认自检守住 no-arg runtime contract。
- **[Tool Name Contract]**: `tools/call.params.name` 现在必须是非空 string；缺失或非 string tool name 会在进入 dispatcher / start approval 前返回 tool error，且不会创建 session 索引文件。standalone thin skill repo 的 manifest 新增 `mcpServer.requiresStringToolName=true`，生成态 `verify-runtime.py` 和 scaffold smoke 同步验证该 malformed request 无副作用。
- **[Tool Params Contract]**: `tools/call.params` 现在必须是 object；缺失或非 object params 会在解析 tool name 前返回 tool error，且不会触发 start approval 或创建 session 索引文件。standalone thin skill repo 的 manifest 新增 `mcpServer.requiresObjectParams=true`，生成态 `verify-runtime.py` 和 scaffold smoke 同步验证该 malformed request 无副作用。

### 🔁 Follow-up (2026-06-27, standalone cancelled recording gate)

- **[Recording-to-Skill Guard]**: standalone thin skill repo 的生成态 `scripts/recording-to-skill-smoke.py` 新增 cancelled recording 负例，验证 `recording_controls_cancelled` 录制在 strict validation、events-only validation 和 `event-stream scaffold-skill --json` 三条路径都会被拒绝。
- **[Manifest Contract]**: `record-and-replay-skill-repo.json` 的 `recordingToSkill` 区块新增 `rejectsCancelledRecordings=true`，让独立 repo 默认 contract 机器可读地声明被用户 Discard / cancel 的录制不能用于创建或更新 skill。
- **[NPM Scaffold Contract]**: npm staging smoke 现在读取安装态 scaffold 生成的 `record-and-replay-skill-repo.json` 时也断言 `recordingToSkill.rejectsCancelledRecordings=true`，避免源码 scaffold 与 npm launcher scaffold 的 recording-to-skill 边界漂移。
- **[NPM Verification]**: 刷新 release app artifact 后复跑 `make npm-record-and-replay-skill-repo-smoke` 通过，输出新增 `checkedCancelledRecordingContract=true`，确认安装态 scaffold 路径也保留 cancelled recording guard。

### 🔁 Follow-up (2026-06-27, baseline smoke evidence summary)

- **[Standalone Smoke Summary]**: `scripts/test-record-and-replay-skill-repo-scaffold.py` 的最终 JSON 现在输出实际检查过的 runtime contract、no-active response、no-arg malformed request gate、wait/notify contract、recording-to-skill handoff、declared handoff paths、scaffold failure exit、cancelled recording guard、`skill-creator` handoff 和真实 lifecycle smoke 标志。
- **[Baseline JSON Gate]**: `scripts/run-record-and-replay-baseline-smoke.sh` 现在捕获 standalone repo smoke 与 npm staged repo smoke 的 JSON 输出，并显式要求关键 evidence 为 true；最终 baseline 摘要新增 `evidence.standaloneSkillRepo` 和 `evidence.npmStagedSkillRepo`，避免组合 smoke 只看子命令退出码。
- **[Verification]**: 复跑 `make npm-record-and-replay-skill-repo-smoke` 和 `make record-and-replay-baseline-smoke` 通过；新的 baseline 输出同时证明 standalone / npm 路径保留 recording-to-skill、cancelled recording、wait/notify、runtime contract 和 `skill-creator` handoff 边界。

### 🔁 Follow-up (2026-06-27, npm staged generated-check evidence)

- **[NPM Check Evidence]**: `scripts/test-npm-record-and-replay-skill-repo-scaffold.mjs` 现在解析安装态 scaffold 生成 repo 的 `scripts/check.sh` 输出，并显式要求 `checkedWaitNotifyContract`、`checkedDeclaredHandoffPaths`、`checkedScaffoldSkillFailureExit` 和 `checkedCancelledRecordingRejected` 为 true。
- **[Baseline Evidence]**: `scripts/run-record-and-replay-baseline-smoke.sh` 同步要求 npm staged smoke 输出这些新增 evidence，并把它们写入最终 `evidence.npmStagedSkillRepo` 摘要。
- **[Verification]**: 复跑 `make npm-record-and-replay-skill-repo-smoke` 与 `make record-and-replay-baseline-smoke` 通过；最终 baseline JSON 显示 npm staged 路径已证明 wait/notify、declared paths、scaffold failure exit、cancelled recording rejection、manifest contract 和 `skill-creator` handoff。

### 🔁 Follow-up (2026-06-27, official skill handoff semantics)

- **[Status Semantics]**: `skills/open-computer-use-record-and-replay/SKILL.md` 现在明确 `event_stream_status` 只能在用户询问状态或录制后返回时使用，不能用作等待录制完成的轮询机制。
- **[Event Stream Access]**: 同一 thin skill 现在明确 MCP server 不直接暴露 event-stream 内容，agent 必须从 `event_stream_stop` / status 返回的 `eventsPath`、`metadataPath` 和 `sessionPath` 读取本地文件。
- **[Generated Repo Guard]**: standalone repo 生成态 `scripts/verify-skill-workflow.py` 的 required snippets 同步固定上述两条官方 skill handoff 语义，`scripts/test-record-and-replay-skill-repo-scaffold.py` 也会断言生成物包含这些文案。
- **[Verification]**: 复跑 `make record-and-replay-skill-repo-smoke` 和 `make npm-record-and-replay-skill-repo-smoke` 通过，确认源码 scaffold 与 npm staged scaffold 都保留这两条官方语义。

### 🔁 Follow-up (2026-06-27, official handoff negative guards)

- **[Workflow Negative Guards]**: `scripts/test-record-and-replay-skill-repo-scaffold.py` 现在会临时删除 status 非轮询说明和 MCP 不直接暴露 event-stream 内容说明，分别断言生成态 `scripts/verify-skill-workflow.py` 失败并报告 `missingRequiredSnippets`。
- **[Baseline Evidence]**: `scripts/run-record-and-replay-baseline-smoke.sh` 现在要求 standalone smoke 输出 `checkedStatusNotUsedAsWaitLoopGuard=true` 和 `checkedMcpNoDirectEventContentsGuard=true`，并把这两项写入最终 `evidence.standaloneSkillRepo`。
- **[Verification]**: 复跑 `python3 -m py_compile scripts/test-record-and-replay-skill-repo-scaffold.py` 和 `make record-and-replay-skill-repo-smoke` 通过，确认官方 handoff 语义不只停留在正向文案存在检查。

### 🔁 Follow-up (2026-06-27, npm official handoff evidence)

- **[Generated Verifier Evidence]**: standalone repo scaffold 生成态 `scripts/verify-skill-workflow.py` 成功 JSON 现在显式输出 `checkedStatusNotUsedAsWaitLoopGuard=true` 和 `checkedMcpNoDirectEventContentsGuard=true`。
- **[NPM Check Evidence]**: `scripts/test-npm-record-and-replay-skill-repo-scaffold.mjs` 现在要求 npm staged launcher 生成 repo 后，其默认 `scripts/check.sh` 输出同样两个 guard 字段，并在 npm smoke 最终 JSON 中公开它们。
- **[Baseline Evidence]**: `scripts/run-record-and-replay-baseline-smoke.sh` 现在同时要求 `evidence.npmStagedSkillRepo` 证明这两个官方 handoff guard，避免安装态 scaffold 路径只继承文案但不暴露机器可读证据。

### 🔁 Follow-up (2026-06-27, official surface baseline evidence)

- **[Official Surface Evidence]**: `scripts/run-record-and-replay-baseline-smoke.sh` 现在捕获 `scripts/compare-event-stream-surface.py --use-default-official` 的 JSON 输出，显式要求 `local-open-computer-use` 和 `official-record-and-replay` 两个 label 都通过。
- **[Sanitized Summary]**: baseline 最终 JSON 新增 `evidence.officialSurfaceCompare`，只保留 fixture 名、protocol version、server name、tool names 和 ok 状态，不把本机官方 plugin 路径写入摘要。
- **[Verification Scope]**: 这仍然只证明官方 1.0.857 non-recording surface 对齐，不替代 successful recording golden fixture。

### 🔁 Follow-up (2026-06-27, matrix and action baseline evidence)

- **[Matrix Evidence]**: `scripts/run-record-and-replay-baseline-smoke.sh` 现在捕获默认 matrix stdout，要求 default lifecycle handoff、no-active、timeout、wait-timeout、approval、MCP elicitation 和 app-agent wait/notify 路径都出现，并在最终 JSON 写入脱敏 `evidence.eventStreamMatrix`。
- **[Action Evidence]**: 同一 baseline 脚本现在捕获真实输入 action smoke stdout，要求录制事件包含 `session.started`、`window.changed`、`AX.focusedWindowChanged`、`mouse.click`、scroll raw-only `experimentalRawEvents` 和 `session.ended`，且 runtime scaffold 已生成 skill 草稿；最终 JSON 写入 `evidence.realInputActionSmoke`，不保留临时文件路径。
- **[Why]**: 这样 baseline 摘要不再只证明 standalone/npm scaffold 证据，也能机器可读地证明“可用版本”的核心录制链路和真实输入链路已经跑过。

### 🔁 Follow-up (2026-06-27, official fixture set baseline evidence)

- **[Fixture Set Evidence]**: `scripts/test-event-stream-official-fixture-set.py` 现在输出具体 JSON evidence，覆盖集合级 gate、`simple-action-stop` / `keyboard-input-stop` / `drag-stop` requirement、candidate pairing、缺 candidate / 缺 scenario 负例、stop / cancel endReason policy 和导入 scenario manifest。
- **[Baseline Summary]**: `scripts/run-record-and-replay-baseline-smoke.sh` 现在捕获该 JSON，要求关键 evidence 为 true，并在最终摘要写入 `evidence.officialFixtureSetGate`。
- **[Golden Boundary]**: baseline 摘要会扫描仓库真实 official recording fixture scenario 覆盖，输出 `repoHasRequiredOfficialSuccessfulFixture` 与 `missingRepoOfficialScenarios`；当前缺 `simple-action-stop` 时仍明确表示 official successful recording 尚未入库，避免把 gate smoke 通过误读成官方 golden 完成。

### 🔁 Follow-up (2026-06-27, hosted official fixture ingest)

- **[Ingest Script]**: 新增 `scripts/ingest-official-record-and-replay-fixture.py`，用于把正常 Codex hosted Record & Replay 的 `event_stream_stop/status` 返回 JSON 转成脱敏 official fixture。脚本会递归解析 direct JSON、`content[].text` 或 JSON-RPC `result.content[].text` 中的 `metadataPath` / `sessionPath` / `eventsPath`，再调用 `scripts/import-event-stream-fixture.py`。
- **[Readiness]**: ingest 后会按 scenario 运行 `scripts/check-event-stream-golden-readiness.py`；提供 `--mcp-transcript --require-mcp-transcript-evidence --check-fixture-set` 时，会进一步要求 response-shape evidence 并跑集合级 official fixture set gate。
- **[Smoke / CI]**: 新增 `scripts/test-official-record-and-replay-fixture-ingest.py` 和 `make event-stream-official-fixture-ingest-smoke`，用合成 hosted response 覆盖导入、脱敏、readiness 和 fixture set gate；该 smoke 已接入默认 `scripts/ci.sh`。
- **[Boundary]**: 这只是让后续官方 successful recording 一键入库和校准，不代表当前仓库已经拥有 official successful recording fixture。

### 🔁 Follow-up (2026-06-27, hosted official fixture stdin ingest)

- **[CLI Usability]**: `scripts/ingest-official-record-and-replay-fixture.py --status-json -` 现在可以从 stdin 直接读取 hosted `event_stream_stop/status` JSON，适合把 Codex tool 返回内容复制或 pipe 进导入脚本。
- **[Transcript Reuse]**: `--use-status-json-as-transcript` 在 stdin 模式下会把同一 JSON 临时写成 transcript 输入，完成导入后结果中以 `usedMcpTranscript="<stdin>"` 表示来源，避免输出已清理的临时路径。
- **[Smoke Coverage]**: `scripts/test-official-record-and-replay-fixture-ingest.py` 覆盖 stdin JSON、transcript 复用、readiness 和 fixture set gate，确保后续采集 official successful recording 时不必先手工创建中间 JSON 文件。

### 🔁 Follow-up (2026-06-27, OCU candidate fixture ingest)

- **[Candidate Script]**: 新增 `scripts/ingest-ocu-record-and-replay-candidate.py`，用于把已有 OCU recording、action smoke JSONL 或 opt-in `--run-action-smoke` 采集结果导入成脱敏 `source=ocu` candidate fixture。
- **[Readiness / Pairing]**: candidate 导入前先跑 strict OCU validation，导入后按 scenario 跑 readiness；提供 `--official-root --check-fixture-set` 时会直接复用 official fixture set gate 做 same-scenario 对比。若 official 样本要求 MCP response shape evidence，candidate 也可传 `--mcp-transcript --require-mcp-transcript-evidence`。
- **[Smoke / CI]**: 新增 `scripts/test-ocu-record-and-replay-candidate-ingest.py` 和 `make event-stream-ocu-candidate-ingest-smoke`，覆盖 direct recording、smoke JSONL、脱敏和 official/candidate pairing；该 smoke 已接入默认 `scripts/ci.sh`。

### 🔁 Follow-up (2026-06-27, action smoke MCP transcript)

- **[MCP Recording Path]**: `make event-stream-action-smoke` 现在通过 proxied `event-stream mcp` start/repeat start/status/stop/repeat stop/final status 录制真实输入，不再只通过 CLI start/stop 生成 action recording。
- **[Transcript Evidence]**: action smoke 输出 JSON 新增 `mcpTranscriptPath`，指向同一 session 的 MCP transcript；baseline 聚合脚本现在要求该字段存在，并在 `realInputActionSmoke.checkedMcpTranscriptCaptured` 中输出证据。
- **[Candidate Ingest]**: `scripts/ingest-ocu-record-and-replay-candidate.py --smoke-json` 会自动消费 action smoke JSONL 中的 `mcpTranscriptPath`；`--run-action-smoke` 会用短 `/tmp/ocu-rnr-*` 目录保留录制和 transcript 到导入结束，避免 app-agent Unix socket path 过长。
- **[Manual Import Note]**: README、handoff、architecture 和 reverse-engineering reference 明确补充：`make event-stream-action-smoke` 默认会清理临时目录，手动保存 stdout 给 `--smoke-json` 时需要设置 `OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_KEEP_TMP=1` 或 `OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_TMPDIR=<dir>`；否则优先使用 importer 的 `--run-action-smoke`。

### 🔁 Follow-up (2026-06-27, official fixture coverage report)

- **[Coverage Script]**: 新增 `scripts/check-event-stream-official-fixture-coverage.py`，单独扫描仓库 recording fixtures 中的 official scenario 覆盖；默认要求 `simple-action-stop`，缺失时返回非零，`--allow-missing` 只报告 `coverageOk=false`。
- **[Smoke / CI]**: 新增 `scripts/test-event-stream-official-fixture-coverage.py` 和 `make event-stream-official-fixture-coverage-smoke`，覆盖 missing、allow-missing、candidate ignored、success、duplicate scenario 和 missing scenario 负例；默认 `scripts/ci.sh` 运行 smoke，并用 `--allow-missing` 输出当前仓库缺 official successful recording 的机器可读报告。
- **[Baseline Evidence]**: `scripts/run-record-and-replay-baseline-smoke.sh` 改为复用 coverage report，而不是内嵌扫描逻辑；最终 `evidence.officialFixtureSetGate` 继续暴露 `coverageOk`、`repoHasRequiredOfficialSuccessfulFixture` 和 `missingRepoOfficialScenarios`，避免把 synthetic fixture set gate 通过误读成 official golden 已完成。

### 🔁 Follow-up (2026-06-27, candidate readiness in fixture set gate)

- **[Candidate Readiness]**: `scripts/check-event-stream-official-fixture-set.py` 在 `--candidate-root` 模式下，找到同 scenario OCU candidate 后会先跑 `source=ocu` golden readiness，再做 official-vs-candidate compare。
- **[Negative Coverage]**: `scripts/test-event-stream-official-fixture-set.py` 新增 candidate `metadata.json` / `session.json` alias 漂移负例，并让 baseline 聚合脚本要求 `checkedCandidateReadinessFailure=true`。
- **[Why]**: 这避免手动传入结构不完整的 candidate fixture 时只靠 compare 通过；后续 official successful recording 入库后，candidate 必须先证明自身 metadata/session/count/path/MCP evidence 完整。

### 🔁 Follow-up (2026-06-27, screenshot path containment)

- **[Validator Contract]**: runtime Swift validator 与源码 Python validator 现在要求事件 payload 里的 `screenshotPath` 必须解析到当前 session 目录内，并且文件存在。
- **[Negative Coverage]**: 新增 Swift validator 单测和 `scripts/test-event-stream-skill-scaffold.py` 负例，使用“session 外部但存在”的截图文件，确认失败原因是外部引用而不是 missing file。
- **[Why]**: 录制到 skill 和后续 official fixture 校准都应该消费自包含 recording 包；外部截图引用会让独立 repo、脱敏 fixture 或用户分享 recording 时出现不可复现上下文。

### 🔁 Follow-up (2026-06-27, standalone screenshot containment evidence)

- **[Standalone Contract]**: `scripts/scaffold-record-and-replay-skill-repo.py` 生成的 standalone repo 现在会在 `recordingToSkill.strictValidation.requiresScreenshotPathsInsideSession=true` 中机器可读声明截图路径必须留在 session 目录内。
- **[Generated Self-Check]**: 生成态 `scripts/recording-to-skill-smoke.py` 会构造一个 `screenshotPath` 指向 session 外部但文件存在的 recording，要求安装态 `event-stream validate --strict-ocu` 拒绝，并在成功自检中输出 `checkedScreenshotPathContainment=true`。
- **[Smoke Evidence]**: 源码 standalone smoke、npm staged standalone smoke 和 `record-and-replay-baseline-smoke` 都开始要求该 evidence，避免主仓 validator 修好后，未来拆出去的 thin skill repo 自检遗漏同一边界。

### 🔁 Follow-up (2026-06-27, npm staged screenshot containment preflight)

- **[NPM Artifact Gate]**: `scripts/test-npm-record-and-replay-skill-repo-scaffold.mjs` 现在会在调用安装态 scaffold 前，用 staged launcher 直接校验 session 外部 `screenshotPath` 负例。
- **[Failure Mode]**: 如果本地 `dist/Open Computer Use.app` 里的 native binary 还没有该 validator gate，smoke 会明确提示重建 `dist` artifacts，而不是等生成 repo 的 `scripts/check.sh` 才以 `external screenshotPath validation should fail` 晚失败。
- **[Why]**: npm standalone smoke 依赖当前 `dist/` native artifacts；把 artifact freshness 检查前置，可以让 release/staging baseline 的失败原因更接近真实问题。

### 🔁 Follow-up (2026-06-27, official fixture stdin base dir)

- **[Hosted Fixture Ingest]**: `scripts/ingest-official-record-and-replay-fixture.py` 新增 `--status-json-base-dir`，用于解析 `--status-json -` 或转存 status JSON 里出现的相对 `metadataPath` / `sessionPath` / `eventsPath`。
- **[Smoke Coverage]**: `scripts/test-official-record-and-replay-fixture-ingest.py` 现在覆盖 stdin hosted JSON 中相对 handoff path 的导入，并断言最终 `recordingInput` 解析到指定 base dir 下的 recording。
- **[Why]**: 官方 hosted 返回通常应是绝对路径，但手工复制、脱敏或中转时可能变成相对路径；显式 base dir 可以避免导入脚本按当前工作目录误解析，提升后续 official golden recording 入库稳定性。

### 🔁 Follow-up (2026-06-27, official fixture transcript stdin)

- **[Hosted Fixture Ingest]**: `scripts/ingest-official-record-and-replay-fixture.py` 新增 `--mcp-transcript -`，允许在 `--status-json` 来自文件时从 stdin 读取单独 MCP transcript / response-shape JSON。
- **[Input Guard]**: `--status-json -` 与 `--mcp-transcript -` 同时使用会明确失败；同一份 JSON 既是 status 又是 transcript 的场景继续用 `--use-status-json-as-transcript`。
- **[Smoke Coverage]**: `scripts/test-official-record-and-replay-fixture-ingest.py` 覆盖 transcript stdin 正路径和双 stdin 错误，确认 readiness / fixture set gate 可以消费 stdin transcript evidence。
- **[Why]**: 正常 Codex hosted 采样后经常会分别拿到 stop/status JSON 与 raw MCP transcript；允许 transcript 直接从 stdin 输入，可以减少临时文件并降低 official golden fixture 入库摩擦。

### 🔁 Follow-up (2026-06-27, keyboard and drag official scenario policies)

- **[Scenario Policies]**: `scripts/check-event-stream-official-fixture-set.py` 新增 `keyboard-input-stop` 和 `drag-stop` 可选 scenario policy，分别要求 `keyboard.text_input` / `mouse.drag`、`recording_controls_stopped` endReason、full AX payload 和 completed lifecycle MCP response-shape evidence。
- **[Smoke Coverage]**: `scripts/test-event-stream-official-fixture-set.py` 新增 keyboard / drag 成功场景和 keyboard 缺失必需事件负例，最终 JSON evidence 输出 `checkedKeyboardInputScenarioPolicy=true` 和 `checkedDragScenarioPolicy=true`。
- **[Why]**: 默认 required scenario 仍是 `simple-action-stop`，但后续官方 golden 入库不能只校准点击；提前固化 keyboard / drag 场景策略，可以在采到官方样本后直接进入 same-scenario readiness / compare。

### 🔁 Follow-up (2026-06-27, recommended official fixture coverage)

- **[Coverage Report]**: `scripts/check-event-stream-official-fixture-coverage.py` 现在把 required 和 recommended official scenario coverage 分开输出。required 默认仍是 `simple-action-stop`，会影响非 `--allow-missing` 退出码；recommended 默认报告 `simple-action-stop`、`keyboard-input-stop`、`drag-stop`、`cancel`、`timeout`，只作为后续 official golden 采样路线图。
- **[Smoke Coverage]**: `scripts/test-event-stream-official-fixture-coverage.py` 覆盖默认 recommended 缺失报告、只覆盖 required 时 recommended 仍未齐、以及自定义 `--recommended-scenario simple-action-stop` 时 recommended coverage 为 true。
- **[Baseline Evidence]**: `scripts/run-record-and-replay-baseline-smoke.sh` 的最终 `evidence.officialFixtureSetGate` 同步输出 `recommendedOfficialScenarios`、`repoHasRecommendedOfficialScenarioCoverage` 和 `missingRepoRecommendedOfficialScenarios`，避免 opt-in baseline 只暴露 required 最小缺口。
- **[Verification]**: 已复跑 `make event-stream-official-fixture-coverage-smoke`、`make check-docs`、`./scripts/ci.sh` 和 `make record-and-replay-baseline-smoke` 通过；baseline 最终摘要显示 recommended 清单为 `simple-action-stop` / `keyboard-input-stop` / `drag-stop` / `cancel` / `timeout`，当前全部缺失，且 required `simple-action-stop` 仍未入库。
- **[Why]**: 当前最小 official golden 门槛仍是 `simple-action-stop`，但要复刻官方 Record & Replay 不能只校准点击；把 keyboard、drag、cancel、timeout 放进 recommended report，可以让后续采样和比对顺序可见，同时不阻塞当前 baseline。

### 🔁 Follow-up (2026-06-27, OCU candidate keyboard and drag readiness)

- **[Candidate Ingest]**: `scripts/ingest-ocu-record-and-replay-candidate.py` 的场景级 validation/readiness 现在覆盖 `keyboard-input-stop` 和 `drag-stop`，分别要求 `keyboard.text_input` / `mouse.drag`、AX context、`recording_controls_stopped`、full AX payload，以及启用 MCP transcript evidence 时的 repeat start / repeat stop / final status response-shape evidence。
- **[Smoke Coverage]**: `scripts/test-ocu-record-and-replay-candidate-ingest.py` 新增合成 keyboard / drag OCU recording，确认 candidate ingest 在没有 official fixture 的情况下也会先跑同 scenario readiness，并输出 `checkedKeyboardInputScenarioReadiness=true` / `checkedDragScenarioReadiness=true`。
- **[Why]**: official fixture set gate 已经定义 keyboard / drag scenario policy；candidate ingest 也必须提前守住同样的最低证据，避免后续采到官方 keyboard / drag 样本时才发现 OCU candidate 导入阶段只做了通用结构检查。

### 🔁 Follow-up (2026-06-27, baseline ingest pipeline evidence)

- **[Baseline Evidence]**: `scripts/run-record-and-replay-baseline-smoke.sh` 现在把 hosted official fixture ingest smoke 和 OCU candidate ingest smoke 纳入同一条 opt-in baseline，并在最终摘要新增 `evidence.fixtureIngestPipelines`。
- **[Gate Coverage]**: 该 evidence 要求 `checkedOfficialFixtureIngest`、`checkedOcuCandidateIngest`、`checkedOcuSmokeJsonImport`、`checkedOcuOfficialCandidatePairing`、`checkedOcuCandidateRedaction`、`checkedOcuKeyboardInputScenarioReadiness` 和 `checkedOcuDragScenarioReadiness` 都为 true。
- **[Why]**: baseline 不能只证明当前 runtime 能录、standalone repo 能 scaffold；它也要证明后续采到官方 successful recording 后，官方样本入库、OCU candidate 入库、同 scenario pairing 和 keyboard/drag readiness 都有同一条可复跑链路。

### 🔁 Follow-up (2026-06-27, baseline screenshot context evidence)

- **[Smoke Output]**: `scripts/run-event-stream-smoke-tests.sh` 的截图模式现在会输出 `screenshotContextChecked`、`screenshotNeededForContextCount`、`screenshotAvailableCount` 和 `screenshotPathCount`，让调用方能区分“已触发截图上下文标记”和“当前环境实际产出了截图文件”。
- **[Baseline Evidence]**: `scripts/run-record-and-replay-baseline-smoke.sh` 现在显式运行截图上下文 smoke，并在最终摘要新增 `evidence.screenshotContextSmoke`；该 evidence 要求 `OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS=always` 下出现 `screenshotNeededForContext`，如果当前环境实际返回截图数据，则要求 `screenshotPath` 存在。
- **[Why]**: 截图上下文是官方 Record & Replay 已观察到的关键字段；opt-in baseline 应覆盖它的可用性，同时不能把当前无截图环境误判为失败，也不能把 OCU 的触发策略误称为官方 golden。

### 🧠 Design Intent (Why)
这次讨论形成了后续实现会依赖的关键约束：先复刻官方 `record-and-replay` 1.0.857 的 observable behavior，再补充 OCU 自有控制条和 wait/通知扩展。第一版实现先打通官方兼容 MCP surface、可消费的文件产物、基础事件流、AX payload 和按需截图上下文，给后续官方 golden fixtures、算法级 AX compact diff 校准和独立 skill/plugin repo 提供稳定落点。

### 📁 Files Modified
- `docs/exec-plans/active/20260626-record-and-replay-event-stream.md`
- `docs/design-docs/record-and-replay-replication.md`
- `docs/ARCHITECTURE.md`
- `docs/QUALITY_SCORE.md`
- `docs/references/codex-computer-use-reverse-engineering/record-and-replay-event-stream.md`
- `docs/references/codex-computer-use-reverse-engineering/fixtures/record-and-replay-event-stream-surface-1.0.857.json`
- `docs/references/codex-computer-use-reverse-engineering/README.md`
- `docs/histories/2026-06/20260626-1737-document-record-and-replay-plan.md`
- `README.md`
- `Makefile`
- `scripts/run-event-stream-smoke-tests.sh`
- `scripts/run-event-stream-smoke-matrix.sh`
- `scripts/run-record-and-replay-baseline-smoke.sh`
- `scripts/ingest-official-record-and-replay-fixture.py`
- `scripts/test-official-record-and-replay-fixture-ingest.py`
- `scripts/ingest-ocu-record-and-replay-candidate.py`
- `scripts/test-ocu-record-and-replay-candidate-ingest.py`
- `scripts/ci.sh`
- `scripts/package-skill.sh`
- `scripts/compare-event-stream-surface.py`
- `scripts/probe-event-stream-recording.py`
- `scripts/test-event-stream-probe-fixtures.py`
- `scripts/scaffold-event-stream-skill.py`
- `scripts/test-event-stream-skill-scaffold.py`
- `scripts/install-codex-record-and-replay-mcp.sh`
- `scripts/test-codex-record-and-replay-installer.mjs`
- `scripts/scaffold-record-and-replay-skill-repo.py`
- `scripts/test-record-and-replay-skill-repo-scaffold.py`
- `scripts/install-config-helper.mjs`
- `scripts/npm/build-packages.mjs`
- `docs/references/codex-computer-use-reverse-engineering/fixtures/record-and-replay-official-raw-start-timeout-1.0.857.json`
- `.github/workflows/ci.yml`
- `.github/workflows/docs-check.yml`
- `.github/workflows/repo-hygiene.yml`
- `.github/workflows/supply-chain-security.yml`
- `.github/PULL_REQUEST_TEMPLATE.md`
- `.github/ISSUE_TEMPLATE/bug_report.yml`
- `.github/ISSUE_TEMPLATE/feature_request.yml`
- `.github/ISSUE_TEMPLATE/config.yml`
- `.github/dependency-review-config.yml`
- `.editorconfig`
- `.markdownlint.json`
- `scripts/import-event-stream-fixture.py`
- `scripts/check-event-stream-official-fixture-coverage.py`
- `scripts/test-event-stream-official-fixture-coverage.py`
- `scripts/check-event-stream-official-fixture-set.py`
- `scripts/test-event-stream-official-fixture-set.py`
- `scripts/compare-event-stream-recordings.py`
- `scripts/test-event-stream-fixture-import.py`
- `scripts/test-event-stream-recording-compare.py`
- `scripts/validate-event-stream-recording.py`
- `scripts/summarize-event-stream-recording.py`
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/record-and-replay.md`
- `skills/open-computer-use-record-and-replay/SKILL.md`
- `apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/OpenComputerUseMain.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/EventStreamMCPServer.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/EventStreamRecordingControls.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/EventStreamRecordingSummary.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/EventStreamRecordingValidation.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/EventStreamSkillScaffold.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/EventStreamService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/EventStreamToolDefinitions.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseCLI.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`

## 2026-06-27 Record & Replay baseline no-active evidence

- `scripts/run-record-and-replay-baseline-smoke.sh` 现在显式运行 `scripts/compare-event-stream-no-active.py`，要求本地 OCU MCP no-active `event_stream_status` / `event_stream_stop` 与 Codex-hosted 官方 1.0.857 fixture 的最小 text JSON 对齐。
- baseline 成功摘要新增 `evidence.officialNoActiveResponse`，记录 fixture 名、checked tools、status/stop shape 和 no-session-files evidence，避免后续只看 surface compare 时漏掉 hosted no-active response 语义。

## 2026-06-27 Standalone official evidence manifest

- `scripts/scaffold-record-and-replay-skill-repo.py` 生成的 standalone repo manifest 新增 `officialEvidence`，机器可读声明当前 contract 基于官方 `record-and-replay/1.0.857` 的 surface fixture、Codex-hosted no-active fixture 和 hostless raw timeout fixture。
- standalone / npm staged / baseline smoke 现在都会检查 `checkedOfficialEvidenceManifest=true`，同时 manifest 明确 `hasSuccessfulRecordingGolden=false`，避免独立 repo 把 non-recording 证据误读成 official successful recording golden 已完成。
- `officialEvidence` 现在还写入 required `simple-action-stop` 与 recommended `simple-action-stop` / `keyboard-input-stop` / `drag-stop` / `cancel` / `timeout` 成功录制场景清单，并通过 `officialEvidence.scenarioRecipes` 固化每个场景的 capture goal、预期 action event、预期 endReason、evidence 要求和 OCU candidate 来源；源码 standalone 与 npm staged scaffold smoke 都按 exact manifest 断言，避免后续拆独立 repo 时丢失官方 golden 采样路线或采样动作细节。
- standalone / npm staged / baseline smoke 现在额外输出 `checkedOfficialEvidenceScenarioManifest=true`，把场景清单检查从泛化的 official evidence manifest 检查中拆出来，便于 baseline 摘要直接证明采样路线仍被守住。

## 2026-06-27 Baseline readiness status

- `scripts/run-record-and-replay-baseline-smoke.sh` 的最终 JSON 新增顶层 `status`，直接输出 `usableBaseline`、`officialNonRecordingBaselineVerified`、`standaloneRepoScaffoldBaselineVerified`、`officialSuccessfulRecordingGoldenComplete`、`recommendedOfficialRecordingCoverageComplete`、`requiresOfficialGoldenCapture` 和缺失的 required / recommended official successful recording scenarios；`officialSuccessfulRecordingGoldenComplete` 现在要求 required scenario 覆盖和 required readiness 同时通过。
- 该字段只汇总已有 smoke / coverage 结果，不改变 gate 通过条件；目的是把“当前 baseline 可用”和“官方 successful recording golden 仍未完成”放到同一层机器可读结论里，避免后续人工从 `evidence.officialFixtureSetGate` 里间接推断。

## 2026-06-27 Strict official golden gate

- `scripts/run-record-and-replay-baseline-smoke.sh` 新增 `--require-official-golden`，在完整跑完 baseline 聚合检查并输出最终 JSON 后，如果 required official successful recording fixture 仍缺失就返回非零。
- `Makefile` 新增 `make record-and-replay-official-golden-gate`，作为后续 official golden 入库后的 release / 拆 standalone repo 验收入口。
- 严格模式会在最终摘要写入 `ok=false`、`status.strictOfficialGoldenRequired=true`、`status.officialGoldenGatePassed=false` 和缺失的 required official scenario；当前缺 `simple-action-stop` 时该命令预期失败，默认 `make record-and-replay-baseline-smoke` 仍保持“baseline 可用但 official golden 未完成”的通过语义。

## 2026-06-27 Baseline summary helper

- `scripts/run-record-and-replay-baseline-smoke.sh` 不再内嵌最终摘要的大段 Python heredoc，改为调用 `scripts/build-record-and-replay-baseline-summary.py` 生成机器可读 JSON 并处理 `--require-official-golden` 退出码。
- 新增 `scripts/test-record-and-replay-baseline-summary.py` 和 `make record-and-replay-baseline-summary-smoke`，用合成 JSON/JSONL 证据覆盖默认模式允许缺 official golden、严格模式缺 required official fixture 失败、严格模式覆盖 required official fixture 通过三种分支。
- 默认 `scripts/ci.sh` 接入该快测，让 `status.strictOfficialGoldenRequired`、`status.officialGoldenGatePassed` 和 required official scenario 缺口字段的回归不再只依赖 opt-in 完整 baseline smoke。

## 2026-06-27 Baseline usable evidence derivation

- `scripts/build-record-and-replay-baseline-summary.py` 不再把 `status.usableBaseline` 写死为 `true`；现在会从 event-stream matrix required modes、截图上下文、真实输入 action required event types、官方 non-recording surface、官方 no-active response、official fixture set gate、fixture ingest pipeline、standalone repo self-check 和 npm staged repo self-check 的 evidence 推导。
- 默认 baseline 仍允许缺少 official successful recording golden；但如果上述必需 evidence 任一缺失，最终摘要会写入 `ok=false`、`status.usableBaseline=false` 和 `status.missingUsableBaselineEvidence=[...]`，并返回非零。
- `scripts/test-record-and-replay-baseline-summary.py` 新增缺失 npm staged `checkedSkillCreatorHandoff` 的负例，固定默认模式下 usable baseline evidence 不完整也会失败。

## 2026-06-27 Official fixture ingest coverage gate

- `scripts/ingest-official-record-and-replay-fixture.py` 新增 `--check-coverage`，导入 hosted official recording 后会调用 `scripts/check-event-stream-official-fixture-coverage.py --allow-missing --check-readiness`，并在返回 JSON 中写入 `coverage` report。
- 新增 `--require-coverage`，导入后要求 output root 满足 required official successful recording scenario 覆盖，且 required fixture readiness 通过；当前 required 仍是 `simple-action-stop`，缺失或 readiness 未过时命令返回非零。
- `scripts/test-official-record-and-replay-fixture-ingest.py` 新增 post-ingest coverage/readiness 成功路径和 cancel-only fixture 下 require-coverage 失败路径；baseline summary 也把 `checkedPostIngestCoverageReport` / `checkedPostIngestCoverageReadiness` / `checkedPostIngestRequireCoverageFailure` 纳入 `fixtureIngestPipelines` evidence。

## 2026-06-27 Official fixture not-ready diagnostics

- `scripts/check-event-stream-official-fixture-coverage.py` 新增顶层 `notReadyOfficialScenarios`，只在 required scenario 已有 official fixture 但集合级 readiness 未通过时填充；缺样本仍只通过 `missingOfficialScenarios` 表示。
- `scripts/build-record-and-replay-baseline-summary.py` 将该字段汇总到 `status.notReadyRequiredOfficialSuccessfulRecordingScenarios` 和 `evidence.officialFixtureSetGate.notReadyRepoOfficialScenarios`，严格 official golden gate 失败时 stderr 会分开输出 `missing=...` 与 `notReady=...`。
- `make event-stream-official-fixture-coverage-smoke` 与 `make record-and-replay-baseline-summary-smoke` 已覆盖 missing、covered-but-not-ready 和 ready 三类分支。

## 2026-06-27 Official fixture inspect-only ingest

- `scripts/ingest-official-record-and-replay-fixture.py` 新增 `--inspect-only`，只解析 hosted status JSON / recording input / handoff paths / MCP transcript evidence，不创建 fixture，用于官方 successful recording 采样后先检查返回体是否可导入。
- `scripts/test-official-record-and-replay-fixture-ingest.py` 覆盖 inspect-only 成功、不创建 output dir、stdin status JSON 复用 transcript 成功，以及要求 MCP transcript evidence 但未提供时失败。
- `scripts/build-record-and-replay-baseline-summary.py` 与合成 summary smoke 新增 `checkedOfficialFixtureInspectOnly` evidence；README、架构、handoff、逆向参考和执行计划同步说明先 inspect 再正式导入。

## 2026-06-27 Scenario-aware OCU action candidate smoke

- `scripts/run-event-stream-smoke-tests.sh` 的真实输入 action smoke 新增 `OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTION_SCENARIO`，默认仍跑 `mixed-action-stop` 覆盖 click 和 scroll raw-only，显式设置 `simple-action-stop`、`drag-stop` 时分别采样 click 和 drag。
- `scripts/ingest-ocu-record-and-replay-candidate.py --run-action-smoke --scenario <scenario>` 现在会把 simple / drag 映射到同名 action smoke 场景，并在 capture evidence 里记录 `actionScenario`；其它非 keyboard scenario 回退到 mixed，只作为通用真实监听链路证据。
- `keyboard-input-stop` candidate 仍通过已有 recording / smoke JSON 导入和 readiness gate 覆盖；因当前 macOS 对 synthetic keyboard event 的 session tap 过滤不稳定，暂不把 keyboard 纳入 `--run-action-smoke` 承诺。README、架构、handoff、逆向参考、执行计划和质量记录同步说明该能力属于 OCU candidate baseline，后续仍需要 official successful recording golden 做同场景校准。
- 复跑 `make record-and-replay-baseline-smoke` 通过，最终摘要证明当前 usable baseline 仍完整：matrix、截图上下文、默认真实输入 action smoke、官方 1.0.857 non-recording surface、官方 no-active response、official fixture set gate、official/OCU ingest pipeline、standalone repo 和 npm staged repo evidence 均通过；同时继续输出 `officialSuccessfulRecordingGoldenComplete=false` 和缺失的 official successful recording 场景，避免把 baseline 可用误读为官方 golden 已完成。
