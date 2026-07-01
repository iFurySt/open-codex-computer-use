# Record & Replay Event Stream

本文记录 2026-06-26 对官方 `record-and-replay` 1.0.857 与 `Codex Computer Use.app` 的本地逆向观察。目标是为 `open-computer-use` 复刻 Record & Replay event stream 提供可追溯上下文。

## 摘要

官方 Record & Replay 不是一个独立自动化 runtime。它仍然启动 `Codex Computer Use.app` 内的 `SkyComputerUseClient`，通过 `event-stream mcp` 子命令暴露一组单独的 MCP tools。普通 Computer Use 插件和 Record & Replay 插件共用同一个 client，差别主要在启动参数、插件元数据和 skill。

`Codex.app` 侧目前只观察到插件可见性、`recordAndReplay` feature flag 和通用 MCP elicitation/approval 处理。录制控制条、事件文件、AX diff、截图上下文和 `event_stream_*` tools 的字符串均在 Computer Use 相关 app / service 二进制中观察到。

这份证据支撑当前实现判断：OCU 应直接复刻官方 `event-stream mcp` 的可观察协议和 recording 文件行为，同时自己补齐脱离 Codex.app 后必须拥有的开始确认、录制控制条、Done / Discard、wait 唤醒和 notify callback。Codex.app 可以作为官方宿主参与 feature gate 或通用 MCP elicitation，但不能成为 OCU 独立使用时的必需依赖。

仍未被本页证据完整证明的内容包括：官方 successful recording 的跨场景完整 `metadata.json` / `events.jsonl` schema、AX compact diff 的算法级输出、截图触发阈值、timeout endReason、以及 Record & Replay start elicitation 的业务化 `message` / `_meta`。Required `simple-action-stop` 已有 official golden fixture，但 keyboard、drag、cancel、timeout 和算法级策略仍必须通过更多 official golden recordings 或正常 Codex 宿主流程继续采集，不能只靠字符串推断。

## 官方插件包装

官方插件在 Codex plugin cache 内的相对位置：

```text
openai-bundled/record-and-replay/1.0.857/
```

`record-and-replay` 插件的 `.mcp.json` 启动方式：

```json
{
  "mcpServers": {
    "event-stream": {
      "command": "./Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient",
      "args": ["event-stream", "mcp"],
      "cwd": "."
    }
  }
}
```

对比普通 `computer-use` 插件，它也启动同一个 `SkyComputerUseClient`，但参数是：

```json
["mcp"]
```

这说明官方把 Record & Replay 实现为同一 runtime 下的另一个 MCP mode，而不是另一个宿主能力。

## MCP Surface

直接探测官方 `SkyComputerUseClient event-stream mcp` 的 `tools/list`，serverInfo 为：

```text
name: Record & Replay
protocolVersion: 2025-11-25
```

2026-06-26 复核时，官方 initialize result 只包含 `capabilities`、`protocolVersion` 和 `serverInfo`，没有 `instructions` 字段。OCU event-stream MCP initialize 应保持这一点；普通 Computer Use MCP 的 instructions 不适用于 Record & Replay surface。

对应的 normalized 非录制 fixture 已保存到 `fixtures/record-and-replay-event-stream-surface-1.0.857.json`。该 fixture 只包含 `initialize` 和 `tools/list`，没有调用 `event_stream_start`，因此不包含用户录制内容或 session 文件。

同日尝试用裸 `SkyComputerUseClient event-stream mcp` 调用官方 `event_stream_status` 时，stdio client 未在数秒内返回响应，手动中断。该现象说明 lifecycle tools 可能依赖官方 runtime / 宿主状态，不适合作为无宿主 smoke 的稳定非录制样本；当前自动化官方对比因此只覆盖 `initialize` 和 `tools/list`，且带读取超时。

2026-06-27 通过 Codex-hosted Record & Replay MCP tool 观察到 no-active 状态：在未启动录制且 `event_stream_status` 显示无 active recording 后，`event_stream_status` 与 `event_stream_stop` 都返回 text JSON `{"isRecording": false, "maxDurationSeconds": 1800}`，没有 `state`、`active`、`eventCount`、`eventsPath` 或 `metadataPath`。该观察已保存为 `fixtures/record-and-replay-official-no-active-status-stop-1.0.857.json`。这只校准 no-active lifecycle response shape；active / completed session 的官方字段仍需要 successful recording golden 校准。仓库内 `scripts/compare-event-stream-no-active.py` 会启动本地 OCU `event-stream mcp`，只调用 `event_stream_status` / `event_stream_stop`，和该 fixture 比对 text JSON，并断言不会创建 session 文件；该脚本不调用 `event_stream_start`。

2026-06-29 通过 Codex-hosted Record & Replay 正常 `event_stream_start` / `event_stream_status` / `event_stream_stop` 观察到一个 completed session，最终 `endReason=recording_controls_stopped`，`isRecording=false`，`maxDurationSeconds=1800`。这次录制约 5 分钟，期间用户没有执行预期的低风险单击场景，实际捕获了多应用真实工作流和私有可见内容，因此不入库、不脱敏导入为 fixture，也不能替代 required `simple-action-stop` official successful recording golden。只保留脱敏结构观察：

- active start response 包含 `eventsPath`、`isRecording=true`、`maxDurationSeconds=1800`、`metadataPath`、`sessionDirectoryPath`、`sessionID` 和 `startedAt`。
- completed status / stop response 包含 `endReason`、`endedAt`、`eventsPath`、`isRecording=false`、`maxDurationSeconds=1800`、`metadataPath`、`sessionDirectoryPath`、`sessionID` 和 `startedAt`。
- `metadataPath` 实际指向 `session.json`；该 session 文件只包含 `id`、`startedAt`、`endedAt`、`endReason` 和 `eventsPath`。
- session 目录中只观察到 `events.jsonl` 和 `session.json`，没有 `metadata.json`、`suppressed.jsonl` 或截图目录。
- `events.jsonl` 共 434 行，事件使用顶层 `kind` 字段；脱敏 kind 计数为 `session.started=1`、`session.ended=1`、`window.changed=16`、`selection.changed=124`、`mouse.click=34`、`mouse.context_menu=2`、`mouse.drag=4`、`keyboard.text_input=88`、`keyboard.submit=21`、`keyboard.shortcut=143`。
- AX payload 中能观察到 `fullTree` 与 `diffFromPrevious` 形态；该样本只证明官方 completed session 会写 AX full / diff 结构，不足以校准 compact diff 算法、截图触发策略或 OCU same-scenario 对比。

这个观察把 official hosted successful recording 的最小输入合同收敛为 `events.jsonl + session.json`：后续正式导入官方 golden 时，不能假设原始目录一定有 OCU 风格 `metadata.json`、`suppressed.jsonl` 或截图目录。仓库 fixture 层会在脱敏导入时补齐自己的可验证 metadata 和空 suppressed 文件；这只是入库 normalization，不代表官方原始包一定写这些文件。

2026-07-01 通过正常 Codex-hosted Record & Replay 流程采集并脱敏导入了 required `simple-action-stop` official fixture：`fixtures/recordings/official-simple-action-stop-1.0.857/`。该 fixture 来自 official `record-and-replay 1.0.857`，manifest 标记 `source=official`、`scenario=simple-action-stop`，脱敏后事件统计为 13 条：`session.started=1`、`window.changed=3`、`mouse.click=6`、`keyboard.shortcut=1`、`selection.changed=1`、`session.ended=1`，最终 `endReason=recording_controls_stopped`，并带 hosted `event_stream_start/status/stop/final status` response-shape evidence。`scripts/check-event-stream-golden-readiness.py` 用 `--require-source official`、`--require-official-plugin-version 'record-and-replay 1.0.857'`、`--require-event-type mouse.click`、`--require-end-reason recording_controls_stopped`、`--require-session-alias`、`--require-metadata-counts`、`--require-handoff-paths` 和 MCP transcript/response-shape requirements 可通过；`scripts/check-event-stream-official-fixture-coverage.py --check-readiness --require-readiness` 与 `make record-and-replay-official-golden-fixture-gate` 也可通过。这满足最小 required official successful recording golden 门槛，但该样本不是 keyboard / drag / cancel / timeout 校准样本，也不能单独证明 AX compact diff 算法、截图触发阈值或所有事件字段 schema 已等价。

仓库内 `scripts/compare-event-stream-surface.py` 是 non-recording surface fixture 的可复跑 drift check：默认比较 OCU `event-stream mcp` 与 `fixtures/record-and-replay-event-stream-surface-1.0.857.json`，`--use-default-official` 会额外探测本机默认官方 plugin cache 下的 `SkyComputerUseClient event-stream mcp` 并和同一 fixture 比较。2026-06-26 本机复核时，官方默认 cache 的 non-recording surface 仍匹配该 fixture；该脚本不调用 `event_stream_start`，不会启动真实录制。

`scripts/run-record-and-replay-baseline-smoke.sh` 也会消费 `scripts/compare-event-stream-no-active.py` 的结果，并在最终摘要写入 `evidence.officialNoActiveResponse`。该 evidence 让 opt-in baseline 同时证明官方 no-active response shape 和无 session 文件副作用，但仍只属于 non-recording 证据。

2026-06-27 再次运行 `scripts/compare-event-stream-surface.py --use-default-official`，本机 OCU `event-stream mcp` 与官方默认 cache 中的 `record-and-replay/1.0.857` non-recording surface 仍同时匹配该 fixture。复核范围仍只包括 initialize / `tools/list`，确认 server name 为 `Record & Replay`、protocol version 为 `2025-11-25`，tools 仍为 `event_stream_start`、`event_stream_status`、`event_stream_stop`。该复核没有调用 `event_stream_start`，没有产生官方 recording。

仓库内 `scripts/probe-event-stream-recording.py` 是后续采集 official golden recording 前的 raw MCP 探测脚手架：它支持 `--target local|official`，记录 initialize / tools-list / start / repeat start / status / stop / repeat stop / final status transcript，处理 server-initiated `elicitation/create`，并在显式 `--start-stop` 时尝试短录制、重复 start、status、stop、重复 stop 和最终 status。probe 的 elicitation response shape 按 Codex host 观察结果处理：accept 发送 `content: {}`，decline / cancel 发送 `content: null`；`--elicitation-action accept|decline|cancel` 可显式选择 action，旧的 `--decline-elicitation` 仍作为 decline 兼容别名。`--fixture-output` 会把 MCP text content 中可解析的 JSON 转成脱敏 `textJSON`，避免 start/status/stop response text 内部保留本机绝对路径。`scripts/test-event-stream-recording-probe.py` 用 fake MCP server 固定 elicitation 行为、repeat start、repeat stop、final status 和 text JSON 脱敏，`scripts/test-event-stream-local-probe.py` 用真实本地 OCU start/repeat start/status/stop/repeat stop/final status 固定 local response shape、one-active、idempotent stop、completed status 语义和最终 session validator 路径，并验证 generated fixture 不含本机路径。2026-06-26 本机复核结果：

- `scripts/probe-event-stream-recording.py --target official` 可正常返回官方 `Record & Replay` initialize / tools-list。
- `scripts/probe-event-stream-recording.py --target official --start-stop --timeout 5` 中，官方 raw `event_stream_start` 在宿主外 5 秒超时，随后 raw `event_stream_stop` 也超时；没有返回 `metadataPath` / `eventsPath`，也没有可导入的官方 recording fixture。
- `scripts/probe-event-stream-recording.py --target local --start-stop` 可对 OCU baseline 完成 start / status / stop，并返回 `recording_controls_stopped`，用于验证 probe 脚手架自身。

2026-06-27 再次运行 `make event-stream-official-start-probe`，官方 bundled `record-and-replay/1.0.857` 仍只在 initialize / tools-list 阶段正常返回；`event_stream_start`、随后 `event_stream_status` 和 `event_stream_stop` 都在 10 秒超时，没有返回 `metadataPath`、`eventsPath`、`sessionPath` 或任何可导入 recording。该复核确认当前裸官方 MCP client 仍缺少 Codex 宿主侧录制状态 / UI choreography，不能单独产出 official successful recording fixture。

因此 official golden recordings 仍需要通过正常 Codex 宿主 Record & Replay 流程、或后续找到官方 runtime 所需的宿主状态后采集；raw 官方 client 只适合 surface 和边界观测，不能产出 required/recommended successful recording fixture。

上述官方 raw start/status/stop timeout 已保存为 sanitized fixture：

- `fixtures/record-and-replay-official-raw-start-timeout-1.0.857.json`

该 fixture 只保留 transcript shape、server info、tool names、start/status/stop 三次 `tools/call` timeout 事实和进程返回形态，不包含本机绝对路径或用户录制内容。`scripts/test-event-stream-probe-fixtures.py` 会在默认 CI 中校验它的基本结构，并要求 `startResponseShape`、`statusResponseShape` 和 `stopResponseShape` 都是 timeout；`scripts/test-event-stream-recording-probe.py` 则校验 probe 自身的 elicitation 应答和 request 摘要提取逻辑。若把这类 timeout transcript 作为 `mcp-transcript.json` 交给 golden readiness gate 并要求对应 tool response，gate 会明确报 `MCP tool timed out`；它只能证明当前宿主外采样边界，不能替代成功的 official response golden。

官方 successful recording 后续入库时，优先用 `scripts/ingest-official-record-and-replay-fixture.py --status-json <event_stream_stop-response.json> --name <fixture-name> --scenario <scenario> --inspect-only` 从 hosted `event_stream_stop` / `event_stream_status` 返回 JSON 里递归提取 `metadataPath` / `sessionPath` / `eventsPath` / `sessionDirectoryPath`，先确认 recording input、handoff path 和可选 MCP transcript 证据都能解析且不会创建 fixture；检查通过后去掉 `--inspect-only` 正式导入。也可以用 `--status-json -` 从 stdin 直接读取刚复制出的 hosted JSON；如果 hosted JSON 中的 handoff path 是相对路径，传 `--status-json-base-dir <recording-parent-dir>` 固定解析基准。若 hosted JSON 只给 `sessionDirectoryPath`，导入器会直接把该目录作为 recording input，再读取其中的 `metadata.json` 或官方最小 `session.json`。随后脚本会调用 `scripts/import-event-stream-fixture.py` 生成脱敏 fixture 并立即跑 golden readiness。导入器现在接受 official hosted 最小目录，也就是只有 `events.jsonl` 和 `session.json` 的 recording；它会把 session `id` 当作 session id 脱敏，生成 fixture 侧 `metadata.json`，补齐 `eventCount` / `suppressedEventCount` / `eventsPath` / `metadataPath` / `sessionPath` / `suppressedEventsPath`，并在原始包没有 suppressed stream 时写空 `suppressed.jsonl`，以满足后续 readiness / compare gate 的 handoff path 合同。若同时有 raw MCP transcript，可加 `--mcp-transcript <probe-output.json> --require-mcp-transcript-evidence --check-fixture-set`，或者在 status JSON 已经来自文件时用 `--mcp-transcript -` 从 stdin 读取单独 transcript，让导入后继续跑 response-shape readiness 和集合级 official fixture set gate；`--status-json -` 和 `--mcp-transcript -` 不能同时使用，若同一 status JSON 已含 transcript / response-shape evidence，可加 `--use-status-json-as-transcript` 复用。`make event-stream-official-fixture-ingest-smoke` 用合成 hosted response 覆盖这条路径。

底层仍可直接用 `scripts/import-event-stream-fixture.py --mcp-transcript <probe-output.json>` 生成脱敏 fixture，再跑 `make event-stream-fixture-smoke` 复核导入链路。该 smoke 不只检查脱敏：它还会把导入后的 fixture 继续喂给 `check-event-stream-golden-readiness.py --require-mcp-response-shape repeatStartResponseShape --require-mcp-response-shape repeatStopResponseShape --require-mcp-response-shape finalStatusResponseShape`，并在样本包含 fallback 证据时要求 `--require-suppressed-events` / `--require-suppressed-event-type`；同时用 `compare-event-stream-recordings.py --require-mcp-response-shapes --require-same-mcp-response-schema` 自比。这样能固定 sanitized `mcp-transcript.json` 和 `suppressed.jsonl` 被 readiness/compare 校准 gate 正确消费；真实 successful recording 覆盖仍以 `fixtures/recordings/*/fixture-manifest.json` 的 official scenario 和 coverage/readiness report 为准。

已观察到 3 个 tools：

| Tool | 参数 | 读写语义 | 说明 |
| --- | --- | --- | --- |
| `event_stream_start` | 无 | non-readonly, non-idempotent | 开始录制用户操作，最长 30 分钟；已有 active recording 时返回当前 session。 |
| `event_stream_status` | 无 | readonly, idempotent | 返回当前或最近一次录制状态，包括 metadata 和 events 路径。 |
| `event_stream_stop` | 无 | non-readonly, idempotent | 停止 active recording；返回 metadata 和 events 路径。 |

这个 surface 应作为 OCU 官方兼容模式的第一约束。扩展能力应放在 OCU CLI 或独立 runtime API 中，不应修改这 3 个 tool 的参数。

## Skill 行为

官方 `record-and-replay` skill 的关键流程：

- 用户确认准备好后才调用 `event_stream_start`。
- start 后结束当前 turn，请用户完成操作后回复。
- 用户完成后调用 `event_stream_stop`。
- 读取返回的 `metadataPath` 和 `eventsPath`。
- `events.jsonl` 是主要输入，`session.json` / metadata 只提供 timing 和路径。
- cancellation 的 `endReason` 为 `recording_controls_cancelled`。
- AX payload 可能是 full tree，也可能是 diff。
- AX compact diff 使用 `~`、`+`、`-` 表示 changed / added / removed。

这意味着复刻工作不仅要产出事件，还要保留能被 skill 消费的文件布局和 endReason。

## Codex.app Asar 观察

本地解包命令示例：

```bash
npx --yes @electron/asar extract <Codex.app>/Contents/Resources/app.asar <scratch>/codex-app-asar-record-replay
```

在解包后的 asar 中观察到：

- `recordAndReplay` feature flag。
- bundled plugin eligibility 中对 `record-and-replay` 的特殊处理。
- 插件 UI 中对 `record-and-replay` 的 icon / name 特殊展示。
- 通用 MCP elicitation/approval 事件：`reply-with-mcp-server-elicitation-response`。
- pending request panel 处理 MCP server elicitation response。
- `elicitation/create` params schema 中观察到 `mode: "form"`、`message`、`requestedSchema`；`requestedSchema` 只接受 object schema，`properties` 可为空，`required` 可选。Codex host 的 UI 分流逻辑会检查 `mode === "form"` 后才进入普通表单 elicitation path。
- elicitation response schema 中观察到 `action: "accept" | "decline" | "cancel"`；`accept` 可带 `content` 对象，`decline` / `cancel` 会带 `content: null`。Codex host 还会把用户操作通过 `reply-with-mcp-server-elicitation-response` 发回 runtime。

未在 Codex.app asar 中观察到：

- `event_stream_start`
- `event_stream_status`
- `event_stream_stop`
- 录制控制条文案
- `events.jsonl`
- `metadata.json`
- `recording_controls_cancelled`

推断：Codex.app 作为宿主只负责 feature gate、插件可见性和通用 MCP elicitation；Record & Replay 的核心录制逻辑和控制条在 Computer Use runtime 内部。

## Computer Use 二进制字符串

在官方 `Codex Computer Use.app` / `SkyComputerUseClient` / `SkyComputerUseService` 相关二进制中观察到下列字符串。

录制控制条和结束原因：

```text
Record & Replay Recording Controls
Record & Replay is recording your actions
Open Record & Replay recording controls
Move Record & Replay recording controls
Discard Recording
I'm done recording.
I've cancelled recording.
recording_controls_stopped
recording_controls_cancelled
```

MCP 与文件产物：

```text
Runs the Record & Replay client as an MCP server
event_stream_start
event_stream_status
event_stream_stop
events.jsonl - append-only activity events captured during the segment
metadata.json - segment timestamps and event counts
eventsPath
metadataPath
suppressedEventsPath
currentSegmentEventsPath
currentSegmentMetadataPath
suppressed.jsonl
session.json
```

权限和 gating：

```text
Record & Replay is not enabled for this user.
Record & Replay approval cancelled via MCP elicitation.
Record & Replay approval denied via MCP elicitation.
```

这些字符串支持两个判断：

- 官方控制条不是 Codex.app 直接绘制的 Electron UI。
- 官方 event stream 至少包含主事件流、metadata 和 suppressed events 三类文件。
- 官方 start tool description 和控制条确认录制最长 30 分钟；当前字符串样本未确认超时结束时对外写入的 endReason。
- 官方 start 前 approval 至少有 cancelled / denied 两种对外错误语义；`Codex.app` 可提供通用 MCP elicitation panel，但 Record & Replay 录制逻辑仍在 Computer Use runtime。

## Start Approval 观察

当前证据分两类：

- `Codex.app` asar：能看到通用 MCP elicitation/approval request 和 pending request panel 处理逻辑。
- Computer Use 相关二进制：能看到 `Record & Replay approval cancelled via MCP elicitation.`、`Record & Replay approval denied via MCP elicitation.`、录制控制条文案和 `recording_controls_*` endReason。

因此更稳妥的推断是：官方宿主可以承载 MCP elicitation UI，但 Record & Replay start approval 的业务语义属于 event-stream runtime。OCU 复刻时不能要求独立 plugin / skill 一定运行在 Codex.app 里，也不能把 approval 做成新的 MCP tool 参数。

后续实现和校准应遵守：

- `event_stream_start` 保持无参数。
- approval approved 后才创建 session 和写 `session.started`。
- approval denied / cancelled 不创建 session，并返回官方风格错误。
- OCU 独立模式需要自有开始确认 UI 或明确的 policy fallback。
- MCP elicitation 只能作为 host 支持时的内部通道，不能成为 OCU 独立使用的硬依赖，也不能改变 `tools/list` 或 `event_stream_start` 的 input schema。
- OCU 当前 baseline 已接入 `OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL=mcp|elicitation`：event-stream MCP server 只在 host initialize 声明 `capabilities.elicitation` 后发送 `elicitation/create`，accept 后创建 session，decline / cancel / unsupported 不创建 session。OCU 发送显式 `mode: "form"` 和空对象 `requestedSchema`，以匹配 Codex.app host 的可渲染 form elicitation schema；真实官方 Record & Replay start request 的最终 message / `_meta` / business-specific schema 仍待 official golden 校准。

## Event Stream 与 AX Diff

已观察到的事件和 AX diff 相关字符串：

```text
session.started
mouse.click
mouse.context_menu
mouse.drag
keyboard.text_input
keyboard.submit
keyboard.shortcut
terminal.value_changed
selection.changed
AX.focusedWindowChanged
window.changed
debug.error
diffFromPrevious
suppressedEventCount
isAXTreeDiffingEnabled
lastAXTree
AX tree unexpectedly missing.
screenshotNeededForContext
accessibilityInspectorPayload
experimentalRawEvents
secureInput
The following is a diff from the previous accessibility tree
The following is a cumulative diff from the initial accessibility tree
Child page depth differs
values differ from index
timediff
feature/axTreeDiffing
feature/axTreeDiffingRemovedElementIDRanges
DifferenceBaseline
UIElementRenderDifference
UIElementRenderDifferenceBuffer
enableAXDiffing
difference
disableDiff
Skip AX tree diff render because removed element summary exceeded full-tree line budget (%ld).
Skip AX tree diff render because difference exceeded full-tree line budget (%ld).
```

官方 skill 还明确提到 compact render 语法：

- `~`：changed
- `+`：added
- `-`：removed

因此 OCU 如果要“直接复刻官方”，不能只记录 raw AX tree 或每次 full tree。需要实现官方风格的 compact AX diff，并在 diff 超预算或缺少 baseline 时回退 full tree。OCU 当前已在 full AX payload 中双写官方观察到的 `fullTree` 和既有 `treeLines`，并保留 previous diff 作为主 `renderedText/treeLines`，额外写入 `cumulativeRenderedText/cumulativeTreeLines` 表示从 initial tree 到 current tree 的累计 diff；`fullTree` 当前采用与 `treeLines` 同源的行数组，字段精确结构和 diff 算法仍待 official golden recording 校准。

输入事件方面，当前字符串样本能确认 `mouse.context_menu`、`mouse.drag`、`keyboard.submit`、`keyboard.shortcut`、`terminal.value_changed`、`selection.changed`、`window.changed` 和 `debug.error` 这些官方事件名，也能看到 `secureInput` 线索。OCU baseline 已实现 `mouse.context_menu`、`mouse.drag`、`keyboard.submit`、`keyboard.shortcut`、轻量 `terminal.value_changed`、轻量 `selection.changed` / selection clear、顶层 `window.changed` 和低敏 `debug.error`；生产路径现在优先安装 listen-only `CGEvent` tap 捕获 session 级输入，失败时回退到 `NSEvent.addGlobalMonitorForEvents`，并新增 `make event-stream-action-smoke` 验证外部 HID click 和 scroll wheel 能分别写出 `mouse.click` 与 scroll raw-only `experimentalRawEvents`，且同一份真实录制产物能继续生成含 Scroll replay step 的 `SKILL.md` 草稿。`keyboard-input-stop` 和 `drag-stop` 场景通过同一 action smoke 的显式 scenario 分别验证 `keyboard.text_input` 和 `mouse.drag`；`keyboard.shortcut` 仍是实现支持的官方字符串事件名，但默认真实输入 smoke 不再依赖低影响功能键 shortcut 合成，后续等 official golden recording 入库后再校准 shortcut 字段和采样策略。其中 `mouse.drag` 按 mouse down / dragged / up 的起止位置、距离和时长记录，字段结构仍需 official golden recording 校准。`terminal.value_changed` 当前只在明显终端上下文且 focused AX value 变化时记录，payload 只写 value hash / length 和脱敏 focused element，不写终端缓冲区全文；字段结构、触发时机和官方是否记录明文仍需官方样本校准。`selection.changed` 当前在 focused AX element 暴露非空 `selectedText` 且 selection signature 变化时记录；如果此前已记录过选择而当前选择为空，会写 `selectionCleared=true` 的清空事件，避免后续 skill 误用 stale selection，字段和触发时机仍需官方样本校准。`window.changed` 当前在录制开始和输入前 app/window context 变化时写入，并继续补 `AX.focusedWindowChanged` 作为 AX 上下文；字段、初始帧语义和事件顺序仍需官方样本校准。`debug.error` 当前在 AX snapshot、cumulative AX diff fallback、screenshot 写入失败和 Input Monitoring monitor 全部安装失败时写入主事件流，payload 只保留 subsystem / reason / errorType / 低敏 context，完整错误细节继续写入 `suppressed.jsonl`。Input Monitoring 不可用的 OCU baseline 使用 `subsystem=inputMonitoring` 和 `reason=inputMonitorsUnavailable`，这是为了避免独立集成方拿到无输入事件的空录制却没有可诊断信号；字段仍待官方样本校准。`secureInput` 当前作为安全 baseline 接入：focused AX element 暴露 protected/secure/password 信号时，键盘文本事件不写明文 `text`，raw key event 不写 `characters`，只保留 redaction 标记和字符数。终端上下文下，OCU 也会脱敏键盘 raw characters 和 focused element value，避免把终端缓冲区写入输入事件。`experimentalRawEvents` 已作为低层 NSEvent 摘要接入点击、拖拽、键盘和 scroll wheel；当前字符串样本没有确认独立 scroll event 名称，因此 OCU 对 scroll 只写 raw-only `experimentalRawEvents` 事件，避免臆造官方事件名。为了让 recording-to-skill handoff 不漏掉滚动动作，summary/scaffold 会把 `kind=experimentalRawEvents` / `type=experimentalRawEvents` 且 `reason=scrollWheel` 的事件纳入 `actionSequence` 并渲染成 Scroll replay step。

## 截图上下文

当前没有观察到“每个事件都截图”的证据。已观察到的线索是：

- `screenshotNeededForContext`
- `accessibilityInspectorPayload`
- `experimentalRawEvents`

更合理的实现方向是：事件默认以 AX 和输入事件为主，只有在上下文不足或官方 schema 要求时标记并采集截图。截图路径、字段名和采集频率仍需要官方样本校准。

OCU 当前采用的可校准策略：

- 默认策略为 `auto`，通过 `OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS=auto|always|never` 覆盖。
- `auto` 只在 AX payload 上下文明显不足时尝试写截图；`always` / `never` 用于验证和调试。
- 截图写入 session 目录下的 `screenshots/`，payload 包含 `screenshotNeededForContext`、`screenshotAvailable`，写入成功时包含 `screenshotPath`。
- 这属于对官方线索的开源实现策略，不代表已经确认官方触发阈值或字段全集；后续仍需 official golden recording 校准。

## 对 OCU 的实现影响

OCU 应分成两层：

- 官方兼容层：`event-stream mcp` 暴露无参数 3 tools，文件布局和 JSON schema 尽量对齐官方。
- OCU 扩展层：CLI `wait`、自有录制控制条、独立通知机制、后续单独 plugin/skill repo。

自有控制条是必要扩展，因为 OCU 不能依赖 Codex.app 帮忙绘制 recording bar，也不能依赖 Codex.app 把用户点击回传给 Computer Use。控制条交互应直接落到 OCU runtime，并把 stop/cancel 状态写回 session。

## 兼容边界

后续实现和评审应按下表区分“官方复刻”和“OCU 扩展”，避免把集成便利性误认为官方 surface。

| 领域 | 官方兼容要求 | OCU 扩展 |
| --- | --- | --- |
| MCP tools | 只暴露 `event_stream_start`、`event_stream_status`、`event_stream_stop`，三者均无参数。 | 不在 MCP surface 增加 `cancel`、`wait` 或 callback 参数。 |
| CLI / runtime API | 官方插件通过 `SkyComputerUseClient event-stream mcp` 间接使用。 | `open-computer-use event-stream start/status/stop/cancel/wait --json` 供独立集成方使用；`wait --notify-command '<json-argv>'` 提供本地 callback。 |
| 录制 UI | 官方控制条在 Computer Use runtime 内部，Codex.app 只做宿主 gating / elicitation。 | OCU 自己绘制浮动控制条，Done / Discard 交互直接落到 OCU runtime。 |
| 通知模型 | 官方 skill 通过下一轮调用 stop/status 读取路径。 | 已提供 blocking `wait` listener 和同步 `--notify-command` callback；后续如需长期订阅，可继续在 OCU 扩展层增加 webhook/socket。 |
| Start approval | 官方存在 MCP elicitation cancelled / denied 错误语义，tool surface 仍无参数。 | OCU 已有自有开始确认 UI / policy，并接入 MCP elicitation baseline 作为 host-capability 内部 gate；host form schema 已按 Codex.app asar 校准，真实官方业务 metadata / message 仍待 golden 校准。 |
| 事件文件 | `events.jsonl` 是主输入，metadata/session 提供 timing、路径和状态。 | 可增加 `latest-session.json` / `active-session.json` 这类索引文件，但不要让上层 skill 必须依赖它们。 |
| AX / screenshot | 以官方样本确认 payload schema、compact diff 和截图触发条件。 | 在校准前允许保留 OCU baseline 字段，但必须在 docs 标记待官方校准。 |

## 未决问题

后续需要用官方 runtime 采集短录制样本来确认：

- `event_stream_start/status/stop` 的完整 response JSON schema。
- `events.jsonl` 每类事件的字段、顺序和 timing 格式。
- `metadata.json` 或 `session.json` 的实际命名、字段和状态流转。
- cancel 与 stop 的 metadata 差异。
- start approval approved / denied / cancelled 的 MCP response、错误文本和是否写任何 session 文件。
- `suppressed.jsonl` 写入条件和字段。
- 截图路径、payload 字段和触发策略。
- AX diff 的 element identity、line budget、removed range summary 和 fallback 规则。

这些样本应按版本保存，至少记录官方插件版本、采集日期、系统版本和脱敏方式。

## OCU 当前复刻状态

截至 2026-06-26，OCU 已具备可继续校准的 macOS baseline：

- `open-computer-use event-stream mcp` 暴露官方兼容的 3 个无参数 tools。
- `event-stream start/status/stop/cancel/wait --json` 作为 OCU CLI 扩展，便于独立插件或 skill 集成；`wait --notify-command '<json-argv>'` 在结束唤醒时把最终 status JSON 写给本地 callback，超时 wait 不触发 callback。
- session 产物包含 `events.jsonl`、OCU 完整状态 `metadata.json`、官方风格最小 handoff `session.json`、`suppressed.jsonl`、`latest-session.json`、录制中的 `active-session.json`，以及按需写入的 `screenshots/`。
- OCU 的 `session.json` 不再是 `metadata.json` 的字节相等 alias；它写 `id`、`startedAt`、结束后的 `endedAt` / `endReason` 和 `eventsPath`，贴近 2026-06-29 Codex-hosted completed session 观察。Swift / Python validator 与 golden readiness 仍要求 `metadata.json` 与 `session.json` 语义兼容，并在直接传入 `session.json` 且同目录存在 `metadata.json` 时优先用完整 metadata 做 OCU strict 校验。
- `AX.focusedWindowChanged` 会尽量写入 `accessibilityInspectorPayload`，首帧为 full tree，并同时保留官方兼容 `fullTree` 与 OCU `treeLines`；同 app/window 后续帧使用轻量 `~` / `+` / `-` compact diff，diff payload 同时包含 previous diff 和 cumulative diff baseline。
- `mouse.click` / `mouse.context_menu` 和 `keyboard.text_input` / `keyboard.submit` / `keyboard.shortcut` 会补充轻量 AX 目标上下文：点击事件尽量记录 `targetAccessibilityElement`，键盘事件尽量记录 `focusedAccessibilityElement`。
- OCU 自有浮动控制条负责录制状态、计时、Done / Discard 和拖动，不依赖 Codex.app。
- OCU 已接入 MCP elicitation approval baseline；`OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL=mcp|elicitation` 时，支持 elicitation 的 MCP host 会收到内部 `elicitation/create` approval request，accept 后才创建 session，decline / cancel / unsupported 不创建 session。
- OCU 已按官方 “up to 30 minutes” 行为增加自动结束；当前 endReason 使用 `recording_time_limit_reached` 作为开源 baseline，后续需用 official golden recording 校准官方实际值。
- OCU 已按官方已确认事件名补齐 `mouse.drag` baseline，mouse down 时只记录 pending pointer，mouse up 后按距离阈值决定写 click/context menu 还是 drag，避免拖拽被误记为点击。
- OCU 已按官方字符串补轻量 `selection.changed` baseline；输入事件后如果当前 focused AX element 有非空 `selectedText` 且 signature 变化，会写入 selected text、focused element summary 和 app/window attribution；如果此前有选择而当前选择为空，会写 `selectionCleared=true` 清空事件。
- OCU 已按官方字符串补轻量 `terminal.value_changed` baseline；明显终端上下文下 focused AX value 变化时写入 value hash / length 和脱敏 focused element，不写终端缓冲区全文。
- OCU 已按官方字符串补顶层 `window.changed` baseline；录制开始和输入前 app/window context 变化时写入 window context，并随后补 `AX.focusedWindowChanged`。
- OCU 已按官方字符串补轻量 `debug.error` baseline；AX / screenshot 上下文采集降级以及 Input Monitoring monitor 全部安装失败时写主事件低敏 debug metadata，完整细节仍写 `suppressed.jsonl`。
- OCU 已按官方 `secureInput` 线索补键盘文本脱敏 baseline；secure focused element 下不记录明文 text/raw characters。
- OCU 已按官方字符串里的 `experimentalRawEvents` 补低层输入事件 baseline，默认开启，可用 `OPEN_COMPUTER_USE_EVENT_STREAM_RAW_EVENTS=0` 关闭；scroll wheel 暂时只作为 raw-only 事件记录。
- OCU 已补 input 前 window context 检测；如果 app bundle + frontmost window title 变化，会在输入事件前先写 `AX.focusedWindowChanged`，以覆盖同一 app 内窗口切换后的上下文缺口。
- OCU 已新增 runtime CLI `open-computer-use event-stream validate --json` 和源码脚本 `scripts/validate-event-stream-recording.py` 作为录制产物结构校验器；OCU smoke 使用 `--strict-ocu` 校验 `metadata.json` / `session.json` 语义兼容、count、final event、endReason、截图路径，以及 OCU active recording 的 `currentSegmentEventsPath` / `currentSegmentMetadataPath` 存在性、final recording 不残留 current segment 字段，并要求完整 OCU session 声明且可解析 `metadataPath` / `sessionPath` / `eventsPath` / `suppressedEventsPath`。runtime Swift validator 与源码 Python validator 都会输出 `declaredPaths` 作为 handoff 证据。安装后的独立 skill/plugin 应优先调用 runtime CLI，源码脚本用于仓库内交叉检查和后续官方 golden recordings 非 strict 校准；current segment 与 declared path strict gate 是 OCU 产物一致性约束，字段最终仍待官方 successful recording 校准。
- OCU 已新增 runtime CLI `open-computer-use event-stream summarize --json` 和源码脚本 `scripts/summarize-event-stream-recording.py` 作为录制后可消费性审计工具，会提取 event type、window、action sequence、target/focused element、selection、debug、redaction evidence 和 OCU 扩展 `skillReadiness`；默认只输出 AX `value` / `selectedText` 长度，不输出原文。这是生成 skill 前的 OCU 辅助入口，不代表已确认官方 summary schema。
- OCU 已新增 runtime CLI `open-computer-use event-stream scaffold-skill --json`，可在安装态把 summary 生成第一版带 workflow readiness 的 `SKILL.md` 草稿和脱敏 `references/recording-summary.json`；源码 checkout 里的 `scripts/scaffold-event-stream-skill.py` 保留为开发交叉检查。这是独立 repo / skill 集成的辅助脚手架，不属于官方 `event_stream_*` MCP surface，也不替代 agent 对 `events.jsonl` 的人工审查和业务语义整理。
- OCU 已新增 `scripts/import-event-stream-fixture.py` 作为官方 golden recording 入库前的脱敏导入入口，默认改写本机路径、session id、timestamp、app attribution、窗口标题、AX value / selectedText，并移除 screenshot path；事件和 suppressed event 中的通用 `path` / 未知 `*Path` 字符串会改成 redacted marker 和长度，避免本机路径通过非标准字段漏进 fixture；如果输入是 official hosted 最小 `events.jsonl + session.json` 目录，导入器会把 `session.json.id` 脱敏为 fixture session id，合成 fixture `metadata.json` 和空 `suppressed.jsonl`，并保留官方风格 `session.json` handoff，保证后续 `--require-session-alias` / `--require-metadata-counts` / `--require-handoff-paths` readiness 可以直接消费；`--mcp-transcript <probe-output.json>` 会额外写入脱敏 `mcp-transcript.json`，把 MCP response text JSON 解码后只保留脱敏 shape；`--scenario <scenario>` 会写入 fixture manifest，供 official baseline set gate 与 OCU candidate 按同 scenario 配对；`make event-stream-fixture-smoke` 覆盖这条净化路径。
- OCU 已新增 `scripts/ingest-official-record-and-replay-fixture.py` 作为 hosted official recording 入库包装入口；它可从 `event_stream_stop` / `event_stream_status` 返回 JSON、JSON-RPC `result.content[].text`、`--status-json -` stdin 或直接 `metadata.json` / `session.json` 里提取 handoff path，调用 import 脚本脱敏入库，并按 scenario 运行 golden readiness。传入 `--mcp-transcript` 和 `--require-mcp-transcript-evidence` 时，会进一步要求 response-shape 证据；传入 `--use-status-json-as-transcript` 时，可把同一 status JSON 临时复用成 transcript；传入 `--check-fixture-set` 时，会用当前 output root 运行集合级 official fixture set gate。`make event-stream-official-fixture-ingest-smoke` 覆盖 nested hosted response、stdin 输入、脱敏、readiness 和 fixture set gate。
- OCU 已新增 `scripts/ingest-ocu-record-and-replay-candidate.py` 作为 same-scenario candidate 入库入口；它可导入已有 OCU `--recording`，也可从 action smoke JSONL 的 `recordingsRoot` / `sessionId` 解析真实 session 目录并自动消费同一 JSON 中的 `mcpTranscriptPath`，或显式 `--run-action-smoke` 采集一次 opt-in 真实输入 smoke 后导入。action smoke 当前通过 proxied `event-stream mcp` start/repeat start/status/stop/repeat stop/final status 录制同一 session，因此输出的 transcript 可作为 candidate response-shape evidence；手动保存 action smoke stdout 给 `--smoke-json` 时需要保留 smoke 临时目录，或直接使用 importer 的 `--run-action-smoke` 路径。`--run-action-smoke` 会按 `--scenario simple-action-stop|drag-stop` 选择同名 action smoke 场景，分别产生 click 或 drag candidate；其它非 keyboard scenario 回退到默认 `mixed-action-stop`，只作为通用真实监听链路证据。`keyboard-input-stop` 当前通过已有 recording 或保留的 smoke JSON 导入，因为 macOS 对 synthetic keyboard event 的 session tap 过滤在不同环境下不稳定。脚本会先跑 strict OCU validation，再调用 fixture import 生成 `source=ocu` fixture，随后按 scenario 跑 readiness；提供 `--official-root --check-fixture-set` 时，会把新 candidate 直接交给 official fixture set gate。若 official 样本要求 MCP response shape evidence，candidate 应传入或自动消费 `mcp-transcript.json` 并加 `--require-mcp-transcript-evidence`。
- OCU 已新增 `scripts/check-event-stream-golden-readiness.py` 作为源码侧 golden gate，检查脱敏 fixture 的 manifest/source/version、final state、metadata/session handoff 兼容性、metadata event/suppressed counts、declared handoff path evidence、`session.started` 首事件 / 唯一性、`session.ended` 最终事件 / 唯一性、动作事件、AX payload，以及按需要求的 expected `endReason`、full/diff/cumulative AX payload、suppressed fallback evidence、`event_stream_start/status/stop` MCP response 证据和 `repeatStartResponseShape` / `repeatStopResponseShape` / `finalStatusResponseShape` 等 raw probe lifecycle response shape 证据；`--require-end-reason <reason>` 会从 metadata/session handoff 和 `session.ended.endReason` 汇总校验，用于后续 stop / cancel / timeout 官方样本入库。gate 输出 `metadataSessionAliasComplete`、`metadataSessionAliasMatches`、`metadataEventCountMatches`、`metadataSuppressedEventCountMatches`、`declaredPaths`、`lastEventType`、`sessionEndedCount`、`sessionEndedIsFinal` 和 `hasFullTreePayload`，默认拒绝同时存在但语义不兼容的 `metadata.json` / `session.json`，默认拒绝已声明但与文件行数不一致的 `eventCount` / `suppressedEventCount`，默认拒绝已声明但不存在的 `metadataPath` / `eventsPath` / `sessionPath` / `suppressedEventsPath`，也默认拒绝多个 `session.ended` 或 `session.ended` 后继续写入事件的 malformed fixture；`--require-session-alias` 会进一步要求两份 handoff 文件都存在，`--require-metadata-counts` 会进一步要求 metadata count 字段存在，`--require-handoff-paths` 会进一步要求四个 handoff path 字段都存在且可解析，`--require-suppressed-events` 要求 `suppressed.jsonl` 非空，`--require-suppressed-event-type <type>` 要求指定 suppressed event type 存在。required MCP tool 的 timeout transcript 会明确失败为 `MCP tool timed out`，required response shape 的 timeout 会失败为 `MCP response shape timed out`，no-active status/stop 这类生命周期 fixture 必须显式放宽 action / AX 要求，避免结构合法但信息不足或只有 timeout 边界的样本被当成事件语义 golden。
- OCU 已新增 `scripts/compare-event-stream-recordings.py` 作为官方 fixture 与 OCU candidate 的事件序列、metadata key diff、stable metadata value diff、declared handoff path evidence、final session evidence、JSON schema、suppressed stream、replay-critical semantic field、AX diff evidence 和可选 MCP response shape evidence 对比入口；`--require-same-metadata-keys` 可要求 candidate metadata key set 与 baseline 一致，`--require-same-metadata-values` 可要求 candidate 的 `state`、`active`、`endReason`、`eventCount`、`suppressedEventCount` 与 baseline 一致，避免 final state / endReason / count 漂移只因 key set 一致而漏掉；`--require-handoff-paths` 可要求 baseline 与 candidate 都声明 `metadataPath` / `eventsPath` / `sessionPath` / `suppressedEventsPath` 且解析后文件存在，避免 candidate 只保留 key set 却丢掉 skill 可消费路径；`--require-final-session-evidence` 可要求 candidate 保留 baseline 的 `session.ended` 个数、最后事件位置和 endReason 集合，避免录制闭环丢失；`--require-same-suppressed-event-sequence` 和 `--require-same-suppressed-schema` 可要求 candidate 保留 baseline `suppressed.jsonl` 中出现的 AX / screenshot / 压缩降级证据顺序和 schema；`--require-semantic-fields` 可要求 candidate 保留 baseline 中出现的 target AX、keyboard focused AX、drag 起止点、selection / terminal 摘要字段、window attribution、AX `fullTree`、AX `treeLines` / `cumulativeTreeLines`；当 baseline 与 candidate 都带 `mcp-transcript.json` 时，`--require-mcp-response-shapes` 可要求 candidate 保留 baseline 中出现的 start/repeat/status/stop/final response shape result/error/timeout 状态，`--require-same-mcp-response-schema` 可进一步要求 response schema path/type 不丢失。`make event-stream-compare-smoke` 覆盖相同样本通过、缺 metadata key、metadata value drift、缺 handoff path、handoff path 指向不存在文件、缺 final session evidence、缺 suppressed event/schema evidence、缺 semantic field、事件顺序漂移、缺 AX diff/cumulative evidence、缺 diff marker、缺 MCP response shape、response timeout 状态漂移和 response schema 缺失失败路径。
- OCU 已新增 `scripts/check-event-stream-official-fixture-set.py` 作为 official golden fixture 集合级 gate；它要求 official fixture manifest 带 `scenario`，默认至少要求 `simple-action-stop` official successful recording，通过 `check-event-stream-golden-readiness.py` 跑 strict readiness。`simple-action-stop` 会要求 `mouse.click` 和 `recording_controls_stopped` endReason，`keyboard-input-stop` 会要求 `keyboard.text_input` 和 `recording_controls_stopped` endReason，`drag-stop` 会要求 `mouse.drag` 和 `recording_controls_stopped` endReason，`cancel` 会要求 `recording_controls_cancelled` endReason，`timeout` 在官方 endReason 未确认前只跑生命周期 readiness、不固定 endReason，并允许 no action / no AX payload。传入 `--candidate-root` 后，它会按同 scenario 找 OCU candidate，先用 `source=ocu` 跑同 scenario readiness，再调用 `compare-event-stream-recordings.py` 要求 event sequence、schema、metadata keys/values、handoff paths、final session evidence、semantic fields 和 MCP response shape 对齐。`make event-stream-official-fixture-set-smoke` 用临时 official / OCU fixtures 覆盖成功、缺 candidate、candidate alias 漂移、缺 scenario、stop endReason mismatch、keyboard / drag 成功录制策略、keyboard 缺失必需事件失败、cancel 成功、timeout lifecycle-only 样本和导入 `--scenario` 写 manifest；当前仓库的 required `simple-action-stop` official fixture 可通过该 gate，recommended 场景继续作为后续入库后的机械验收入口。
- OCU candidate ingest 入口 `scripts/ingest-ocu-record-and-replay-candidate.py` 现在与集合级 gate 的 stopped action scenario 保持一致：`simple-action-stop` 要求 `mouse.click`，`keyboard-input-stop` 要求 `keyboard.text_input`，`drag-stop` 要求 `mouse.drag`；三者都会要求 stopped endReason、full AX payload，并在 `--require-mcp-transcript-evidence` 时要求 repeat start / repeat stop / final status response-shape evidence。这让 OCU candidate 在 official fixture 入库前也能先通过同 scenario readiness，而不是只等 official-vs-candidate gate 再发现 keyboard/drag 录制缺关键事件。
- OCU 已新增 `scripts/check-event-stream-official-fixture-coverage.py` 作为仓库真实 official fixture 覆盖率 report；它默认要求 `simple-action-stop` official successful recording，缺失时返回非零，`--allow-missing` 会改成只输出 `coverageOk=false` / `missingOfficialScenarios` 供默认 CI 和 baseline smoke 记录当前缺口。该 report 同时输出 recommended coverage，默认清单是 `simple-action-stop`、`keyboard-input-stop`、`drag-stop`、`cancel`、`timeout`，并通过 `missingRecommendedOfficialScenarios` 指引下一批 official golden 采集；recommended coverage 不影响退出码。传入 `--check-readiness` 时，required scenario 存在后还会跑 official fixture set readiness 并输出 `requiredOfficialReadinessOk`；如果 scenario manifest 已存在但 readiness 不合格，会在顶层 `notReadyOfficialScenarios` 里列出对应场景。传入 `--require-readiness` 时，只有 required scenario 覆盖和 readiness 都通过才算 `coverageOk=true` / `hasRequiredOfficialSuccessfulFixture=true`。
- OCU baseline 聚合入口 `scripts/run-record-and-replay-baseline-smoke.sh` 现在同时运行 hosted official fixture ingest smoke 与 OCU candidate ingest smoke，并把结果写入 `evidence.fixtureIngestPipelines`；该 evidence 也要求 official hosted JSON 只给 `sessionDirectoryPath` 时可导入官方最小 session 目录。这证明导入/脱敏/配对/候选 readiness 管线可复跑；真实 official recording 是否齐备以 coverage report 的 required/recommended scenario 覆盖、required readiness 以及 official fixture set gate 为准。
- OCU baseline 聚合入口现在也运行截图上下文 smoke，并把结果写入 `evidence.screenshotContextSmoke`；这证明 `always` policy 会让 AX payload 带 `screenshotNeededForContext`，且当前环境返回截图数据时 `screenshotPath` 会被校验存在。它仍不是官方截图触发阈值或 suppressed 行为的 golden 校准，后续仍需 official recording fixture。
- OCU 已新增 `scripts/probe-event-stream-recording.py` 作为 official golden recording 采集前的 raw MCP 探测入口；local OCU start/repeat start/status/stop/repeat stop/final status probe 可用，并由 `scripts/test-event-stream-local-probe.py` 固定 generated fixture 脱敏、one-active response、idempotent stop、completed status、active current segment response 和 final cleanup response；官方 bundled client 在宿主外只读 surface probe 可用，raw start/status/stop 当前超时。

仍未完成的官方级校准：

- start approval gate、OCU 自有开始确认弹窗和 MCP elicitation approval 已有 baseline；Codex.app host form schema 和 response action 已确认，官方 Record & Replay 真实业务 message / `_meta` 仍待样本确认。
- 需要继续通过正常 Codex 宿主流程或已满足官方 runtime 宿主状态的环境采集 recommended official golden recordings，确认 keyboard、drag、cancel、timeout 等场景的完整 JSON schema 和字段顺序；当前 raw 官方 client start/status/stop probe 仍超时。
- 需要采集达到或模拟最长时长的官方样本，确认 timeout completion 的 state / endReason / metadata 差异。
- AX compact diff 当前是官方风格的轻量 previous / cumulative 实现，还不是已确认等价的 `UIElementRenderDifference` 算法。
- 点击/键盘目标摘要字段名和内容仍是 OCU baseline，需要 official golden recordings 校准官方是否使用同名字段、是否有更完整的 raw event 结构。
- `mouse.drag` 字段名、距离阈值、`terminal.value_changed` 字段与触发时机、`selection.changed` 字段与清空选择语义、`window.changed` 字段与初始帧语义、`debug.error` 字段语义、Input Monitoring failure debug payload、`secureInput` 字段语义、raw payload 结构，以及可能存在的独立 scroll event schema 仍待官方样本校准。
- 截图上下文触发条件、路径字段和 suppressed 行为仍只基于已观察字符串与 OCU smoke 验证。
