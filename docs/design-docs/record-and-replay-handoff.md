# Record & Replay Handoff

## 状态

本文是 Record & Replay 后续推进的短入口。完整设计看 `record-and-replay-replication.md`，官方逆向证据看 `../references/codex-computer-use-reverse-engineering/record-and-replay-event-stream.md`，执行拆解看 `../exec-plans/active/20260626-record-and-replay-event-stream.md`。

当前共识是：先直接复刻官方 Record & Replay 的可观察行为，再补 OCU 为独立运行必须拥有的控制条、等待和通知能力。官方兼容层和 OCU 扩展层必须保持边界清楚。

## 落库地图

后续推进不应再依赖聊天上下文。当前方案和上下文已经按用途拆到这些位置：

- `record-and-replay-handoff.md`：短入口，记录当前结论、边界、推进协议、待解决问题和下一轮顺序。
- `record-and-replay-replication.md`：完整设计入口，记录官方兼容层、OCU 扩展层、校准合同、独立 repo 合同、事件/AX/screenshot/control bar 方案和验收门槛。
- `record-and-replay-official-golden-capture.md`：官方 successful recording golden fixture 的短操作入口，记录采集前检查、hosted JSON inspect-only、正式导入、OCU candidate 对比和严格验收 gate。
- `../exec-plans/active/20260626-record-and-replay-event-stream.md`：执行计划，记录里程碑、已完成 baseline、P0/P1/P1.5/P2 推进拆解和具体命令。
- `../references/codex-computer-use-reverse-engineering/record-and-replay-event-stream.md`：官方上下文和证据入口，记录 plugin 包装、Codex.app asar 观察、Computer Use 二进制字符串、MCP surface、official fixture 和 raw probe 边界。
- `../../skills/open-computer-use-record-and-replay/SKILL.md`：OCU thin skill baseline，约束独立 repo 中 agent 如何调用三件套、停止录制、读取产物和生成 skill。
- `../../skills/open-computer-use/references/record-and-replay.md`：通用 OCU skill 的 R&R 参考说明。
- `../../scripts/prepare-record-and-replay-official-golden-capture.py`：官方 successful recording golden 采集前的只读 preflight，报告当前 official scenario 覆盖、官方 plugin cache、scenario recipe、下一条 inspect/import/OCU candidate 命令。
- `../../scripts/prepare-record-and-replay-ocu-candidate-pairing.py`：官方 fixture 入库后的只读 pairing preflight，报告 same-scenario OCU candidate 是否存在/ready，输出 scenario recipe、candidate ingest 与 fixture-set compare 命令。
- `../../scripts/scaffold-record-and-replay-skill-repo.py`：源码 checkout 的 standalone repo scaffold 入口。
- `open-computer-use scaffold-record-and-replay-skill-repo --output-dir <dir>`：npm 安装态的 standalone repo scaffold 入口；用于后续真正创建独立 repo。

后续如果方案、证据或接口合同变化，优先更新本 handoff、完整设计、execution plan 和逆向参考，再按需同步 skill 与 README。

## 落库完成判定

后续处理 Record & Replay 时，不应再把聊天记录当作唯一上下文。至少要能从仓库内回答这些问题，才算方案已经落库完整：

- 为什么选择直接复刻官方可观察行为，而不是重新设计一套 OCU 协议。
- 哪些行为属于官方兼容层，必须保持 `event_stream_start/status/stop` 三件套无参数。
- 哪些能力属于 OCU 独立扩展层，例如开始确认 UI、录制控制条、`wait`、notify callback、validation、summary、skill scaffold 和 standalone repo self-check。
- 哪些字段、算法或触发策略仍只是 OCU baseline，必须等待 official golden recording 校准后才能宣称官方等价。
- 后续如果要继续复刻官方，应该先采集什么样本、用哪些脚本脱敏导入、如何比较 OCU candidate。
- 后续如果要拆真实 standalone repo，应该以哪个 scaffold 为蓝本、默认 CI 跑哪些不启动录制的检查、哪些 lifecycle smoke 只能 opt-in。

当前这些问题分别落在本 handoff、`record-and-replay-replication.md`、active execution plan、逆向参考文档、thin skill 和 standalone repo scaffold contract 中。推进新改动时，如果发现某个回答只能从聊天上下文里推断，就先补文档再继续实现。

## 本轮结论

这次推进的核心结论是：OCU 后续不要另设计一套 Record & Replay 协议，而是以官方当前可观察行为为默认目标。官方兼容路径继续围绕 `event_stream_start/status/stop` 三个 no-arg MCP tools、官方 session 文件、事件流、AX payload、截图上下文和录制到 skill 的 handoff 收敛；任何暂时没有 official golden recording 证明的实现都只能标成 OCU baseline 或待校准。

独立运行能力另放在 OCU 扩展层。因为 OCU 不能依赖 Codex.app 替它绘制录制 bar、接收 Done / Discard 或转发结束回调，所以开始确认 UI、录制中控制条、`cancel`、`wait --session-id`、`wait --notify-command`、validate / summarize / scaffold 和 standalone thin skill repo 都归 OCU 扩展层。上层使用方可以监听 `wait` / notify 结果继续生成 skill，但官方兼容 MCP surface 不因此增加工具、参数或 callback 字段。

后续拆独立 repo 时，repo 只包装 thin skill 和 runtime contract：要求安装 `open-computer-use`，启动 `open-computer-use event-stream mcp`，用 OCU 自有控制条完成录制，再读取 `metadataPath` / `eventsPath` 走 validation、summary 和 skill scaffold。独立 repo 不复制 OCU runtime 源码，也不假设 Codex.app 私有 UI、feature gate 或回调一定存在。

## Baseline 实施基准

后续第一波 baseline 的目标是“能用且不误报官方等价”，不是一次性完成所有官方算法级校准。实现和验收时按下面口径推进：

- 官方兼容 baseline：`open-computer-use event-stream mcp` 只暴露 `event_stream_start`、`event_stream_status`、`event_stream_stop` 三件套 no-arg tools；server name、initialize / tools-list、no-active status/stop response、session 文件布局、`session.started` / `session.ended` 生命周期、已确认动作事件、AX payload 和截图上下文都向官方样本收敛。
- OCU 独立 baseline：OCU 自己提供开始确认 UI、录制中控制条、Done / Discard、`cancel`、`wait --session-id`、`wait --notify-command`、validate / summarize / scaffold 和 standalone repo self-check；这些能力可以交给独立 plugin / skill repo 使用，但不能进入官方兼容 MCP surface。
- 可交付判定：默认 baseline summary 应能给出 `usableBaseline=true` 和 `standaloneRepoBaselineReady=true`。当 required official successful recording golden 缺失时，必须保持 `officialSuccessfulRecordingGoldenComplete=false`、`officialSuccessfulRecordingEquivalenceReady=false` 和 `requiresOfficialGoldenCapture=true`；当 required `simple-action-stop` 已入库且 readiness 通过时，可以把最小 required golden 标为完成，但 recommended 场景和算法级 schema 未齐前仍不能宣称全部 official successful recording schema、AX compact diff 或 screenshot 策略已经等价。
- official fixture set gate 是 official golden 入库后的强对比入口。同 scenario OCU candidate 进入 compare 前必须先通过自身 readiness；compare 默认要求 AX diff evidence、AX diff marker 一致、suppressed event sequence 一致和 suppressed schema 一致。当前 baseline summary 会消费 `checkedAxDiffComparisonPolicy`、`checkedSuppressedStreamComparisonPolicy` 和 `checkedAxDiffComparisonFailure`，避免后续拿到官方 compact diff 或 suppressed fallback 后，candidate 缺字段仍被误判通过。
- 暂不升级为官方等价的内容：AX compact diff 的 element identity / line budget / fallback 条件、截图触发阈值、timeout endReason、raw scroll event schema、terminal / selection / secure input / debug 字段，以及 MCP elicitation 的真实业务 message / `_meta`。这些都必须等 official golden recording 或新的官方 fixture 进入后再校准。
- 后续真实 standalone repo 只消费 OCU runtime 和 thin skill。默认 CI 跑不启动录制的 package、runtime contract、skill workflow、wait/notify 和 synthetic recording-to-skill checks；真实桌面 lifecycle smoke 只能作为 opt-in。
- standalone repo 默认自检还必须跑生成态 `scripts/verify-manifest.py`，也就是 `checks.manifestContract=scripts/verify-manifest.py`。这条检查只验证 `record-and-replay-skill-repo.json` 的机器合同：官方 evidence、required / recommended scenario、`sourceRepoBaselineAudit`、`strictOfficialGoldenExpectedFailureAudit`、`officialEvidence.sourceRepoBaselineChecks.officialFixtureSetGate.sameScenarioComparePolicy`、OCU `extensionLayer`、官方三件套 no-arg surface 和 recording-to-skill handoff 是否漂移，不启动录制，也不把任何 OCU 扩展加进官方 MCP surface。source / npm staged smoke 与 baseline summary 都要输出 / 消费 `checkedManifestContract=true` 和 `checkedOfficialFixtureSetComparePolicyManifest=true`。
- standalone repo 默认自检还必须跑生成态 `scripts/verify-source-baseline-summary.py`，也就是 `checks.sourceBaselineSummaryEvidence=scripts/verify-source-baseline-summary.py`。scaffold 会把源仓 `dist/record-and-replay-baseline-summary.json` 的脱敏投影复制到 `evidence/source-baseline-summary.json`，该 verifier 校验 `usableBaseline=true`、`standaloneRepoBaselineReady=true`，并要求 official golden 状态自洽：当前可以是 required `simple-action-stop` gap 明确，也可以是未来 official golden gate / successful recording equivalence 已完成；如果仍缺 required scenario 却声明 equivalence ready 会失败。它还会确认 source / npm staged standalone evidence 都保留 `checkedOfficialFixtureSetComparePolicyManifest=true`，并确认 `fixtureIngestPipelines.checkedOfficialSessionDirectoryPathHandoff=true`、`preflightPipelines.checkedOfficialCapturePacketSetContractManifest=true`、`preflightPipelines.checkedOfficialCapturePacketPostCaptureWorkflow=true`、`preflightPipelines.checkedOfficialCapturePacketWorkflowVerifier=true`、`preflightPipelines.checkedOfficialCapturePacketSetPostCaptureWorkflow=true`、`preflightPipelines.checkedOfficialCapturePacketSetWorkflowVerifier=true`、`preflightPipelines.checkedOfficialCapturePacketStrictAuditHandoff=true` 和 `preflightPipelines.checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff=true` 没有在投影里丢失。source / npm staged smoke 与 baseline summary 都要输出 / 消费 `checkedSourceBaselineSummaryEvidence=true`、`checkedSourceBaselineSummaryOfficialGoldenState=true`、`checkedSourceBaselineSummaryOfficialSessionDirectoryPathHandoff=true`、`checkedSourceBaselineSummaryCapturePacketSetContractManifest=true`、`checkedSourceBaselineSummaryCapturePacketPostCaptureWorkflow=true`、`checkedSourceBaselineSummaryCapturePacketWorkflowVerifier=true`、`checkedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow=true`、`checkedSourceBaselineSummaryCapturePacketSetWorkflowVerifier=true`、`checkedSourceBaselineSummaryCapturePacketStrictAuditHandoff=true` 和 `checkedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff=true`。源仓 baseline 还会单独消费 `fixtureIngestPipelines.checkedOfficialSessionDirectoryPathHandoff=true`、`preflightPipelines.checkedOfficialCapturePacketPostCaptureWorkflow=true`、`preflightPipelines.checkedOfficialCapturePacketWorkflowVerifier=true`、`preflightPipelines.checkedOfficialCapturePacketSetPostCaptureWorkflow=true` 与 `preflightPipelines.checkedOfficialCapturePacketSetWorkflowVerifier=true`，证明 official completed directory handoff 与 capture packet / packet set 的机器合同不只声明文件和 wrapper，还声明录制后的有序 handoff 以及 `verify-workflow.sh` 执行计划校验。
- standalone repo 默认自检还必须跑生成态 `scripts/verify-readme-handoff.py`，也就是 `checks.readmeHandoffContract=scripts/verify-readme-handoff.py`。这条检查只验证 README 是否继续暴露官方 evidence 文件、baseline / strict audit handoff、strict 缺 official golden 的 expected-failure 审计命令、required / recommended successful recording 场景、recording-to-skill 命令和 wait/notify 边界；不启动录制，也不改变官方兼容 MCP surface。source / npm staged smoke 与 baseline summary 都要输出 / 消费 `checkedReadmeHandoffContract=true`、`checkedReadmeOfficialEvidenceHandoff=true`、`checkedReadmeOfficialGoldenGap=true` 和 `checkedReadmeWaitNotifyBoundary=true`。

## 快速上下文结论

这些结论是后续推进时最容易在聊天上下文里丢失的部分，默认以这里为准：

- 官方 `record-and-replay` plugin 只是包装入口；它通过 `.mcp.json` 启动同一个 Computer Use runtime 的 `event-stream mcp` 模式。普通 Computer Use 和 Record & Replay 共用 runtime，但暴露的 MCP surface 不同。
- 当前对 Codex.app asar 的观察只支持把 Codex.app 视为宿主侧 feature gate、插件可见性和通用 MCP elicitation / approval UI 的提供方；没有证据表明 Codex.app 自己实现 `event_stream_*` tools、写 recording files、绘制录制控制条或保存事件流。
- OCU 因此不能耦合 Codex.app。开始确认 UI、录制中 bar、Done / Discard、结束状态、`wait` listener 和 notify callback 都必须由 OCU runtime 自己承载；使用方只通过 OCU 暴露的 CLI / MCP / generated standalone repo contract 集成。
- 官方兼容 MCP surface 只允许 `event_stream_start`、`event_stream_status`、`event_stream_stop` 三个无参数 tools。`cancel`、`wait`、notify callback、validation、summary、skill scaffold 和 standalone repo self-check 是 OCU 扩展层，不进入官方三件套 schema。
- 截图不是“每个事件默认截图”。官方证据只确认 `screenshotNeededForContext` / `accessibilityInspectorPayload` 这类上下文线索；OCU 默认应最小化截图，只在 payload 判断需要视觉上下文且当前 snapshot 可用时写 `screenshots/` 并给出 `screenshotPath`，触发阈值仍等 official golden recording 校准。
- Compact AX diff 指的是同一 app/window 的后续 AX payload 不再重复输出整棵 accessibility tree，而是用官方风格的 `~` / `+` / `-` 表示 changed / added / removed，并保留 previous diff 与 cumulative diff 语义。OCU 当前 LCS 风格实现只是 baseline；element identity、line budget、removed summary 和 fallback 条件必须用 official golden recording 校准。
- 当前已有官方 non-recording surface fixture、Codex-hosted no-active status/stop fixture、宿主外 raw start/status/stop timeout fixture，以及 required `simple-action-stop` official successful recording fixture。前几类只能证明 surface、idle response 和宿主外边界；`simple-action-stop` 只满足最小 required successful recording 门槛，不能覆盖 keyboard、drag、cancel、timeout、截图阈值或 AX compact diff 算法级等价。
- `keyboard-input-stop`、`drag-stop`、`cancel`、`timeout` 仍是 recommended 采样清单。没有这些样本前，不能宣称 OCU 已完成所有 official successful recording 场景复刻。
- 下一步不应再从聊天里拼命令。required 样本已入库时，先用 `make record-and-replay-official-golden-fixture-gate` / `make record-and-replay-official-golden-gate-audit` 留存 readiness 和 strict summary artifact，再用 OCU candidate ingest / pairing preflight 生成同场景 candidate，跑 fixture set gate 的 AX diff + suppressed stream 强对比；后续 recommended 场景继续走 capture packet verify / inspect / import wrapper。

## 决策摘要

- 第一阶段只做 macOS。
- “直接复刻官方”在本仓库里的含义是复刻可观察协议、文件、事件、状态流转和生成 skill 的 handoff 行为；不得复制官方私有实现代码，也不得把 OCU 私有便利参数加入官方兼容 MCP surface。
- 官方兼容 MCP surface 只保留 `event_stream_start`、`event_stream_status`、`event_stream_stop` 三个无参数 tools。
- 同一时间只允许一个 active recording；重复 start 返回 active session 是 runtime one-active 语义，agent 侧需要询问用户是使用该 active recording 还是等待它结束，不能静默当作新 demonstration。
- `cancel`、`wait`、`validate`、`summarize`、`scaffold-skill`、控制条交互和 notify callback 都属于 OCU 扩展层，不能进入官方三件套 tool schema。
- OCU 自己绘制开始确认 UI 和录制控制条，不能依赖 Codex.app 绘制 bar 或把用户点击转发回来。
- `events.jsonl` 是后续生成 skill 的主证据，`metadata.json` / `session.json` 只提供状态、路径、timing 和计数。
- 被用户取消的 recording 不能用于创建或更新 skill；上层应该提示重新录制。
- 截图是上下文补充，不是每个事件默认主数据。
- AX compact diff 是官方事件流的重要组成部分，最终必须用 official golden recording 校准，而不是长期停留在 full tree 或概念相似的 diff。
- 独立 thin skill / plugin repo 只包装 OCU runtime，不复制本仓库录制逻辑。

## 后续推进协议

后续基于本文推进时，先把每个改动归到三类之一：

- **官方兼容层**：只改 `event-stream mcp` 三件套、session 文件、官方已确认事件和 official golden 校准逻辑。这里不能增加新的 MCP tool、tool 参数、callback 参数或 OCU 私有状态依赖。
- **OCU 扩展层**：只服务独立运行，包括开始确认 UI、录制控制条、`cancel`、`wait`、notify callback、validate / summarize / scaffold、standalone thin skill repo 和安装便利命令。这里可以比官方多，但必须在 docs 和测试里明确是 OCU 扩展。
- **待官方校准 baseline**：已经有实现价值但没有 official golden 证明的字段、算法或触发策略。这里可以落代码和 smoke，但不能在文档或注释里宣称“已官方等价”。

每次推进都按这个顺序收口：

1. 先补或引用证据：官方 fixture、asar 观察、二进制字符串、官方 skill 文案、或 OCU smoke 结果。
2. 再做实现：官方兼容层保持三件套不变，扩展能力走 CLI / runtime / standalone repo。
3. 再补验证：surface drift、recording validation、golden readiness、recording compare、skill scaffold 或 standalone repo smoke 中至少选中对应路径。
4. 最后同步文档：如果字段、流程、边界或验收口径变化，同步更新 `record-and-replay-replication.md`、本 handoff、exec plan、reverse-engineering reference 和 history 中受影响的部分。

判断一个行为能否从 baseline 升级为“官方复刻完成”时，必须同时满足：

- 有 official golden recording 或官方 non-recording fixture 证据。
- OCU candidate 可以通过可复跑脚本与该证据比较，而不是只靠人工目测。
- 文档里已经删除或更新对应的“待校准”标记。

没有 official golden 时，默认措辞保持为“OCU baseline”“官方风格”“待 official golden 校准”。

## 易混边界

- Codex.app 边界：当前可观察证据只支持把 Codex.app 视为宿主、feature gate 和通用 MCP elicitation UI 的提供方；录制控制条、事件文件、AX payload、截图上下文和 `event_stream_*` tool 字符串都落在 Computer Use runtime 侧。OCU 因此必须自己承担开始确认、录制中 bar、Done / Discard 和结束唤醒。
- 官方兼容层边界：`open-computer-use event-stream mcp` 要尽量像官方 `SkyComputerUseClient event-stream mcp`，但只暴露三件套 no-arg tools。任何独立集成所需的 `wait`、callback、session index、validate 或 skill scaffold 都走 CLI / runtime 扩展。
- Screenshot 口径：官方字符串确认 `screenshotNeededForContext`，但没有证据表明每个事件都截图。OCU 默认应最小化截图，只在上下文不足或测试显式要求时写入 `screenshots/`，并把截图失败降级为可诊断事件或 suppressed 记录。
- Compact AX diff 口径：官方 diff marker 是 `~`、`+`、`-`，并有 previous / cumulative diff 和 fallback 线索。OCU 当前 LCS 风格 diff 是 baseline，不是最终官方等价算法；后续必须用 official golden recordings 校准字段、line budget、element identity、removed summary 和 fallback 条件。
- Skill handoff 口径：录制结束后不能只交付 runbook。可用 recording-to-skill scaffold 生成草稿，但最终仍要由 agent 读取 `events.jsonl`、补齐业务输入、按 summary 的 `safetySignals` 和上下文确认高风险动作、按 `skill-creator` 完成可发现 skill。
- Golden fixture 口径：已有 required `simple-action-stop` official recording fixture 时，只能把该场景覆盖到的生命周期、click、stop endReason 和 handoff shape 作为最小 official evidence；未被该 fixture 或后续 recommended fixture 覆盖的字段名、字段顺序、timeout endReason、raw event 结构和截图触发策略仍只能标成 OCU baseline 或待官方校准。

## 已沉淀的官方上下文

- 官方 `record-and-replay` 插件启动同一个 Computer Use runtime，只是参数为 `event-stream mcp`。
- 官方 Record & Replay MCP server name 是 `Record & Replay`，protocol version 是 `2025-11-25`。
- 官方 1.0.857 的非录制 surface fixture 已入库：`../references/codex-computer-use-reverse-engineering/fixtures/record-and-replay-event-stream-surface-1.0.857.json`。
- 官方 raw start/status/stop 在宿主外当前会超时，边界 fixture 已入库：`../references/codex-computer-use-reverse-engineering/fixtures/record-and-replay-official-raw-start-timeout-1.0.857.json`。`scripts/test-event-stream-probe-fixtures.py` 会确认三次 raw `tools/call` 都是 timeout、fixture 不含本机路径且没有 recording handoff paths；`make record-and-replay-baseline-smoke` 会把这些检查写入 `evidence.officialRawStartTimeout`，作为当前 usable baseline 的必需 non-recording evidence。
- 通过 Codex-hosted Record & Replay tool 观察到 no-active `event_stream_status` / `event_stream_stop` response shape：text JSON 只有 `isRecording=false` 和 `maxDurationSeconds=1800`，fixture 已入库：`../references/codex-computer-use-reverse-engineering/fixtures/record-and-replay-official-no-active-status-stop-1.0.857.json`。
- Codex.app 侧目前只观察到 feature flag、插件可见性和通用 MCP elicitation/approval 处理；录制控制条、事件文件、AX diff、截图上下文和 `event_stream_*` 字符串在 Computer Use runtime 相关二进制里。
- 官方字符串确认的事件名、文件名、control endReason 和 AX diff marker 已写入逆向参考文档。

## 当前 OCU Baseline

当前分支已经围绕这个方向沉淀了 baseline 能力，后续推进时应先复用它们，而不是重新设计 surface：

- `open-computer-use event-stream mcp` 暴露官方三件套。
- 官方三件套运行时参数面已守住基本 `tools/call` contract：`params` 必须是 object，`params.name` 必须是非空 string，`arguments` 必须是 object，且 `event_stream_start/status/stop` 不接受任何字段；缺失 / 非 object params、缺失 / 非 string tool name、非 object arguments 或非空 object arguments 都通过 tool error 返回，且不创建 session 文件。
- MCP no-active `event_stream_status` / `event_stream_stop` 已按官方观察返回 `isRecording=false` / `maxDurationSeconds=1800` 的最小 text JSON；CLI `event-stream status/stop --json` 仍保留 OCU 扩展字段。
- CLI 扩展包含 `start/status/stop/cancel/wait/validate/summarize/scaffold-skill`。
- session 产物包含 `events.jsonl`、`metadata.json`、`session.json`、`suppressed.jsonl`、`latest-session.json` 和 `active-session.json`。
- 已有 OCU 自有开始确认和录制控制条 baseline。
- 输入事件覆盖 click、context menu、drag、text input、submit、shortcut、window context、AX context、selection、terminal value、debug error 和 raw event 摘要。
- AX payload 已有 full、previous diff 和 cumulative diff baseline。
- `wait --session-id`、`waitTimedOut`、`waitSessionMatched` 和 `wait --notify-command` 已作为独立集成扩展。
- summary / scaffold handoff 已有结构化 `runtimeInputs`、`safetySignals`、`summaryLimits`、完成态 `recordingIncomplete`、`sessionStartedNotFirst`、`sessionStartedCountInvalid`、`sessionEndedNotFinal`、`sessionEndedCountInvalid` 和 `blockingDiagnostics`，用于把文本输入 / selection 依赖转成运行时输入候选，把 submit、send/delete/save/upload 等可能改变外部状态的动作转成显式确认线索，在长录制摘要被截断时要求回读 `events.jsonl`，在 recording 仍 active、缺少 `session.started`、重复写入 `session.started`、`session.started` 不是首事件、缺少 `session.ended`、重复写入 `session.ended` 或 `session.ended` 后又出现事件时拒绝生成 skill 草稿，并在 Input Monitoring 不可用等阻断性诊断出现时拒绝生成 skill 草稿；默认只保留长度、目标摘要、原因、计数和敏感标记，不复制原始文本。
- thin skill baseline 位于 `../../skills/open-computer-use-record-and-replay/SKILL.md`，通用 skill 的参考说明位于 `../../skills/open-computer-use/references/record-and-replay.md`。
- standalone thin skill repo scaffold 入口是 `../../scripts/scaffold-record-and-replay-skill-repo.py`；生成 repo 自带 `scripts/verify-runtime.py`，用于在不启动录制的前提下验证 `open-computer-use event-stream mcp` 的官方兼容三件套 surface，包括 initialize capabilities、tool description、empty input schema、MCP annotations、no-active status/stop response shape、malformed `tools/call` contract 和被拒请求不创建 session 文件的副作用边界，也自带 `scripts/check.sh` 作为 package + runtime verifier + wait/notify contract smoke + synthetic recording-to-skill 的组合自检入口；其中生成态 package script 会校验 skill frontmatter 的 `name` 和非空 `description`，`scripts/verify-package-artifact.py` 会在打包后打开 `.skill` archive，确认 `.skill` alias 与 zip 字节一致、archive 路径只在预期 skill 目录下、packaged `SKILL.md` 的 frontmatter 和 Record & Replay handoff 片段仍存在，并输出 `checkedPackageArtifact=true` 供 source / npm staged scaffold smoke、baseline summary 和 artifact audit 消费；生成 repo 还带 SHA-pinned `.github/workflows/ci.yml` 在独立 repo 中复跑同一自检。生成 README 还固定了 recording-to-skill handoff：完整 OCU 产物用 `validate --strict-ocu --require-skill-draft <metadataPath-or-sessionPath>`，只有 `eventsPath` 时用非 strict `validate --require-skill-draft <eventsPath>`，并说明 events-only 可以从 `session.ended.endReason=recording_controls_cancelled` 推断取消态但不能证明 metadata/session alias 或 declared handoff paths。生成 repo 默认自检会运行 `scripts/verify-skill-workflow.py`、`scripts/wait-notify-contract-smoke.py` 和 `scripts/recording-to-skill-smoke.py`：workflow verifier 静态守住官方 handoff 与 OCU Independent Wait / Notify Integration 边界，wait/notify smoke 用不存在的 session 验证 callback skipped、不创建 session 文件和 `waitSessionMatched=false`，也用合成 completed session 验证成功 callback 能收到 `OPEN_COMPUTER_USE_EVENT_STREAM_SUPPRESSED_EVENTS_PATH`，失败 callback 非零退出会让 CLI 非零并返回 `reason=nonZeroExit`，callback 超时也会让 CLI 非零并返回 `reason=timeout`，recording-to-skill smoke 用临时合成 completed recording 验证安装态 strict validator、events-only validator、strict `declaredPaths` evidence 和 `scaffold-skill` 草稿生成路径，并用 cancelled recording 验证 strict / events-only validation 和 `scaffold-skill` 都会拒绝生成 skill；生成态 manifest 的 `extensionLayer` 也会机器可读地声明 `wait --notify-command`、`waitTimedOut` / `waitSessionMatched`、notify stdin/env、`callbackFailureMakesCliFail` 和 `callbackTimeoutMakesCliFail` 不属于官方 MCP surface，`mcpServer.rejectedRequestsDoNotCreateSessionFiles` 固定 malformed request 副作用边界，源码与 npm staged baseline 都会消费 `checkedPackageArtifact`、`checkedRequiresObjectParams`、`checkedRequiresStringToolName`、`checkedRequiresObjectArguments`、`checkedRejectsUnexpectedArguments`、`checkedRejectsNonObjectArguments`、`checkedRejectedRequestsDoNotCreateSessionFiles`、`checkedNotifySuppressedEventsPathEnv`、`checkedNotifyCallbackFailureExit`、`checkedNotifyCallbackFailureReason`、`checkedNotifyCallbackTimeoutFailureExit` 和 `checkedNotifyCallbackTimeoutReason`，源码 standalone baseline 还会消费 lifecycle smoke 的 one-active、idempotent stop 和 final status evidence，`recordingToSkill` 区块则机器可读地声明 strict validation、events-only validation、scaffold-skill handoff 和 cancelled recording 拒绝 contract。生成 repo 还带可选 `scripts/recording-lifecycle-smoke.py`，用于在本地显式 start/repeat start/status/stop/repeat stop/final status 一个最小 recording，验证 one-active、idempotent stop 和 completed status，再用安装态 validator 校验 session 文件；它不进入默认 `check.sh`，避免独立 repo CI 默认启动真实录制。
- 生成态 runtime verifier 的 surface evidence 现在拆成三项机器字段：`checkedInitializeSurfaceContract` 固定 protocol / server name / capabilities / 无 `instructions`，`checkedToolMetadataContract` 固定三件套 tool name、description、input schema 和 annotations，`checkedToolInputSchemaNoArguments` 单独固定空 object schema 与 `additionalProperties=false`。source / npm staged scaffold smoke、baseline summary 和 artifact audit 都消费这三项字段。
- 生成态 `scripts/verify-runtime.py` 和可选 `scripts/recording-lifecycle-smoke.py` 的 MCP response timeout 诊断必须带 runtime 路径、执行命令、`open-computer-use --version` 结果和设置 `OPEN_COMPUTER_USE_CLI` 指向当前 runtime 的修复提示；`OPEN_COMPUTER_USE_RUNTIME_VERIFY_TIMEOUT_SECONDS` 可用于本地快速复现旧全局安装或错误 launcher 导致的超时。源码 scaffold smoke 用假旧 runtime 覆盖该失败路径，npm staged smoke 也静态验证生成物包含这些诊断文本。
- baseline summary 和 artifact audit 会把 source / npm staged 的 `checkedRuntimeTimeoutDiagnostics` 当作 `usableBaseline` 必需 evidence；缺失时 `missingUsableBaselineEvidence` 会分别报告 `standaloneSkillRepo.checkedRuntimeTimeoutDiagnostics` 和 `npmStagedSkillRepo.checkedRuntimeTimeoutDiagnostics`，避免 release / standalone audit 只验证 runtime surface，却漏掉旧 runtime 排障路径。
- npm staged scaffold 还必须证明安装态 launcher 的 Python 依赖失败路径可诊断：`PYTHON` 指向不存在的文件或 Python 2 时应返回 command-specific `Python 3 is required to run` 和 `PYTHON=/path/to/python3` 修复提示。`checkedNpmPythonLauncherDiagnostics` 已进入 baseline summary、runner 早期断言和 artifact audit；缺失时 `missingUsableBaselineEvidence` 会报告 `npmStagedSkillRepo.checkedNpmPythonLauncherDiagnostics`。
- 生成 repo README 必须把 Python 3 前置条件写清楚：自检脚本要求 `python3` 可用，通过 npm launcher 创建 repo 时如果 shell 找不到 Python 3，应设置 `PYTHON=/path/to/python3`。源码 standalone smoke 和 npm staged smoke 都输出 `checkedGeneratedReadmePrerequisites=true`，baseline summary 与 artifact audit 会在 source / npm staged 两侧消费该 evidence，缺失时报告 `standaloneSkillRepo.checkedGeneratedReadmePrerequisites` 或 `npmStagedSkillRepo.checkedGeneratedReadmePrerequisites`。
- npm package build 必须携带 source baseline summary artifact：`scripts/npm/build-packages.mjs` 打包 `open-computer-use` 时会复制 `dist/record-and-replay-baseline-summary.json`，供安装态 scaffold 生成 `evidence/source-baseline-summary.json`。缺失该 artifact 时 build 直接以 `Missing Record & Replay baseline summary artifact` 失败，并要求先运行 `make record-and-replay-baseline-audit`；npm staged smoke 会临时移走该 artifact 覆盖负例，避免发布出缺 baseline evidence 的 npm 包。

## Standalone Repo Contract

后续真正拆出独立 repo 时，以 scaffold 生成物的 `record-and-replay-skill-repo.json` 作为机器可读 contract：

- `mcpServer` 只声明 `open-computer-use event-stream mcp`、initialize capabilities、`event_stream_start/status/stop` 三件套、tool metadata、object params contract、非空 string tool name contract、empty object argument contract 和 no-active response shape。
- `officialEvidence` 声明该 standalone repo contract 目前基于官方 `record-and-replay/1.0.857` 的 non-recording surface fixture、Codex-hosted no-active status/stop fixture 和 hostless raw start/status/stop timeout 边界 fixture；它同时显式标记还没有 successful recording golden，并把 required `simple-action-stop` 与 recommended `simple-action-stop` / `keyboard-input-stop` / `drag-stop` / `cancel` / `timeout` 成功录制场景写成机器可读清单。`officialEvidence.scenarioRecipes` 还会随 scaffold 固化每个场景的 capture goal、预期 action event、预期 endReason、evidence 要求和 OCU candidate 来源，避免独立 repo 把 no-active 或 timeout 边界证据误读成事件 schema 已官方等价，也避免后续只拿到场景名却丢失采样动作细节。`officialEvidence.sourceRepoBaselineChecks` 声明源仓 baseline 负责验证 baseline contract smoke、hostless raw timeout、official fixture set gate same-scenario compare policy、official capture packet preflight 和 OCU candidate pairing preflight；其中 `officialFixtureSetGate.sameScenarioComparePolicy` 机器声明 AX diff evidence / marker 与 suppressed event sequence / schema 都必须进入校准 gate，`officialGoldenCapturePreflight.requiredEvidence` 机器声明 `checkedOfficialCapturePacketInputSemanticGuard`、`checkedOfficialCapturePacketSetContractManifest`、`checkedOfficialCapturePacketPostCaptureWorkflow`、`checkedOfficialCapturePacketSetPostCaptureWorkflow`、`checkedOfficialCapturePacketStrictAuditHandoff` 和 `checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff` 必须由源仓 baseline 证明。`officialEvidence.sourceRepoBaselineAudit` 声明 release / standalone handoff 应在源仓运行 `make record-and-replay-baseline-audit`，官方 successful recording fixtures 入库后再运行 `make record-and-replay-official-golden-gate-audit`，并用 `make record-and-replay-baseline-audit-targets-smoke` 守住两个 audit target 的 dry-run 合同；默认 baseline 摘要产物是 `dist/record-and-replay-baseline-summary.json`，默认 strict 摘要产物是 `dist/record-and-replay-official-golden-gate-summary.json`，覆盖变量分别是 `RNR_BASELINE_SUMMARY_JSON` 和 `RNR_OFFICIAL_GOLDEN_SUMMARY_JSON`，manifest 同时声明 strict 缺 official golden 时可运行的 `strictOfficialGoldenExpectedFailureAudit` 命令、`verifiesSummaryArtifactSeparation=true` 与 `verifiesSummaryEnvVarIsolation=true`；`officialEvidence.standaloneRepoBoundary` 明确独立 repo 默认自检不启动官方录制、不复制 preflight 脚本，也不复制 OCU runtime 源码。
- `extensionLayer` 只声明 OCU 独立集成命令，例如 `wait --notify-command`、`waitTimedOut` / `waitSessionMatched`、notify stdin 和 `OPEN_COMPUTER_USE_EVENT_STREAM_*` 环境变量（包含 `OPEN_COMPUTER_USE_EVENT_STREAM_SUPPRESSED_EVENTS_PATH`）；它必须显式标记 `officialCompatibleMcpSurface=false`，避免独立 repo 把 listener/callback 误加到 MCP 三件套里。
- `checks` 是默认发布/安装前必须跑的自检：`scripts/package-skill.sh`、`scripts/verify-manifest.py`、`scripts/verify-source-baseline-summary.py`、`scripts/verify-runtime.py`、`scripts/verify-skill-workflow.py`、`scripts/wait-notify-contract-smoke.py`、`scripts/recording-to-skill-smoke.py` 和组合入口 `scripts/check.sh`。这些检查都不应启动真实桌面录制；`verify-manifest.py` 只校验生成态 `record-and-replay-skill-repo.json` 的机器合同，`verify-source-baseline-summary.py` 只审计随 scaffold 复制的 `evidence/source-baseline-summary.json` 投影证据，`verify-runtime.py` 可以调用 no-active status/stop，因为这不会创建 session，`wait-notify-contract-smoke.py` 可以等待不存在的 session，因为这只验证 unmatched session / callback skipped 语义。
- `optionalChecks` 只放需要本地桌面权限或会真实创建 recording session 的检查；当前只有 `scripts/recording-lifecycle-smoke.py`。
- 默认 CI 只调用 `scripts/check.sh`，用于验证 skill frontmatter、runtime contract 和 recording-to-skill handoff。真实录制 lifecycle smoke 由开发者在本机或专门授权环境显式运行。
- 生成 repo 不复制 OCU runtime 源码，也不假设 Codex.app 私有 UI；它只依赖已安装的 `open-computer-use` binary 和 OCU 自有控制条 / wait / validation / scaffold 能力。

补充：source standalone 和 npm staged baseline 不只消费 `recording-to-skill` handoff 总开关。`scripts/run-record-and-replay-baseline-smoke.sh` 和最终 summary 现在还要求 `checkedStrictValidation`、`checkedEventsOnlyValidation`、`checkedScaffoldSkill` 和 `checkedSkillCreatorHandoff` 这类具体 evidence，分别证明完整 OCU session strict gate、events-only gate、`scaffold-skill` 正路径和后续 `skill-creator` 交接文案都没有从独立 repo scaffold 中丢失；npm staged 路径同样证明这些证据能从安装态 launcher 生成的 repo 默认自检中传播出来。

## 后续最短路径

如果下一轮目标是继续实现官方复刻，先走这条路径：

1. 用正常 Codex 宿主流程采集官方 successful recording，优先 stop / cancel / repeat start / no-active status-stop / 简单动作样本。
2. 先用 `scripts/prepare-record-and-replay-official-golden-capture.py --scenario <scenario>` 做只读 preflight，确认当前缺口、`scenarioRecipe` 和下一条命令；需要交接采集输入时，可加 `--capture-packet-dir <dir>` 生成包含 recipe、placeholder hosted JSON 和 verify/inspect/import/check wrappers 的 capture packet；需要一次准备全部推荐场景时，再加 `--capture-packet-recommended-scenarios` 生成 per-scenario 子目录、根级 manifest 和 `verify-all.sh` / `inspect-all.sh` / `import-all.sh` / `check-all.sh` / `ingest-ocu-candidates.sh` 批量 wrapper。单场景 `capturePacket` 与根级 `capturePacketSet` 都会用 `includeTranscript` / `requiresMcpTranscriptInput` 声明当前采集包是否要求 `inputs/mcp-transcript.json`，消费方不应靠猜文件是否存在或解析 README 判断。替换 packet 输入后先运行 `verify-inputs.sh` 或 `verify-all.sh`，再用 `scripts/ingest-official-record-and-replay-fixture.py --status-json <event_stream_stop-response.json> --name <fixture-name> --scenario <scenario> --inspect-only` 无写入检查 hosted JSON 是否能解析出 handoff path、recording input 和 MCP transcript 证据；检查通过后去掉 `--inspect-only` 正式脱敏导入并跑 readiness。recommended packet set 导入后还应运行根级 `ingest-ocu-candidates.sh`，批量生成 simple / drag 等可自动采样场景的 OCU candidate，并跳过 keyboard / cancel / timeout 这类 recording-required 或 no-action 场景。导入后的 `fixture-manifest.json` 必须保留 `scenario` 与 `scenarioRecipe`，fixture set gate 会拒绝 recipe drift；official / OCU direct ingest、coverage report 和 fixture set gate 的 scenario-specific readiness 参数也都从同一个 scenario catalog 生成。也可用 `--status-json -` 从 stdin 直接读取刚复制出来的 hosted JSON；如果 stdin 或转存 JSON 里的 handoff path 是相对路径，加 `--status-json-base-dir <recording-parent-dir>` 固定解析基准；如果已有 raw MCP transcript，再加 `--mcp-transcript <probe-output.json> --require-mcp-transcript-evidence --check-fixture-set --check-coverage`，或在 status JSON 已落文件时用 `--mcp-transcript -` 从 stdin 读取 transcript；如果同一 status JSON 已含 response-shape evidence，可用 `--use-status-json-as-transcript` 复用。采集 required 场景后可加 `--require-coverage`，让导入后 official scenario 覆盖或 required readiness 不足时直接返回非零。
3. 用 `scripts/ingest-ocu-record-and-replay-candidate.py --recording <ocu-recording-or-metadata> --name <candidate-name> --scenario <scenario> --official-root <official-fixtures> --check-fixture-set`、`--smoke-json <action-smoke-output.jsonl>` 或 `--run-action-smoke --scenario simple-action-stop|drag-stop` 导入 OCU candidate，再用 fixture set gate 对比 lifecycle、metadata 稳定字段、event sequence、replay-critical semantic fields、AX diff evidence / marker 和 suppressed stream sequence / schema。`keyboard-input-stop` 目前走已有 recording / smoke JSON 导入，不走 synthetic keyboard `--run-action-smoke`。
4. 根据差异校准官方兼容层，保持 `event_stream_start/status/stop` 三件套无参数。
5. 只有当独立运行体验受阻时才改 OCU 扩展层，例如控制条、`wait`、notify、validation 或 standalone repo scaffold。

如果下一轮目标是拆独立 repo，先走这条路径：

1. 运行 `open-computer-use scaffold-record-and-replay-skill-repo --output-dir <new-repo>` 生成 repo。
2. 在生成 repo 中运行 `./scripts/check.sh`，确认 package、runtime contract、skill workflow 和 synthetic recording-to-skill smoke 通过。
3. 在有桌面权限的本机显式运行 `./scripts/recording-lifecycle-smoke.py`，确认安装态 runtime 可以真实 start / stop 最小 recording。
4. 根据真实发布目标补 repo README、版本、安装说明和 release 流程，但不要把 OCU runtime 源码复制进独立 repo。

## 待解决问题

- 已有 required `simple-action-stop` official successful recording fixture，且当前 readiness / fixture set gate 可验证该最小门槛。当前也已有 official non-recording surface fixture、Codex-hosted no-active status/stop response fixture 和 raw start/status/stop timeout 边界 fixture；baseline summary 会分别消费 `evidence.officialSurfaceCompare`、`evidence.officialNoActiveResponse` 和 `evidence.officialRawStartTimeout`。`scripts/check-event-stream-official-fixture-coverage.py` 会单独报告 required official scenario 覆盖和 readiness；该 report 也会单独输出 recommended scenario 覆盖，默认清单是 `simple-action-stop`、`keyboard-input-stop`、`drag-stop`、`cancel`、`timeout`。recommended 只指引后续 official golden 采样，不影响 required 覆盖的退出码。
- 官方算法级 AX compact diff 仍未校准。
- 鼠标、键盘、drag、terminal、selection、window、debug、secure input 和 raw event 字段仍需官方 recording 校准。
- 截图触发阈值、字段名和 suppressed 行为仍需官方 recording 校准。
- MCP elicitation 的 host schema baseline 已有，但官方 Record & Replay 真实业务 message / `_meta` 仍未确认。
- timeout endReason 当前是 OCU baseline，未确认官方实际输出。
- 独立 thin plugin / skill repo 尚未真正创建和发布验证；当前只有 scaffold 生成态 repo 的本地打包/frontmatter gate、完整 initialize / tool metadata / no-active response runtime contract verifier、可选最小 recording lifecycle smoke、组合 `check.sh` 和生成态 CI workflow smoke。

## 下一轮推进顺序

1. 补齐 recommended 官方 golden recordings。
   Required `simple-action-stop` 已入库；后续继续使用正常 Codex 宿主流程录制 keyboard、drag、cancel、timeout 等推荐样本。样本必须脱敏后再入库。

2. 导入和检查官方样本。
   优先使用 `scripts/ingest-official-record-and-replay-fixture.py --status-json <event_stream_stop-response.json> --name <fixture-name> --scenario <scenario> --inspect-only` 检查 hosted official recording；确认 `stage=inspect`、`recordingInputInspection.*.exists=true` 和需要的 MCP transcript evidence 后，再去掉 `--inspect-only` 正式导入。也可以把 hosted JSON pipe 给 `--status-json -`。如果 hosted JSON 中的 `metadataPath` / `sessionPath` / `eventsPath` 是相对路径，传 `--status-json-base-dir <recording-parent-dir>`，避免按当前工作目录误解析。正式导入会调用 `scripts/import-event-stream-fixture.py` 脱敏入库，把 `scenario` / `scenarioRecipe` 写进 manifest，并按 scenario 跑 `scripts/check-event-stream-golden-readiness.py`。如果只有 session 目录、`metadata.json` 或 `session.json`，可用 `--recording <path>`；如果另有 raw MCP transcript，则加 `--mcp-transcript <probe-output.json> --require-mcp-transcript-evidence --check-fixture-set --check-coverage`，或者在 status JSON 已经来自文件时用 `--mcp-transcript -` 从 stdin 读取单独 transcript。`--status-json -` 和 `--mcp-transcript -` 不能同时使用；同一 status JSON 含 transcript / response-shape evidence 时，改用 `--use-status-json-as-transcript` 直接复用。导入后可用同一导入命令加 `--require-coverage`，或单独用 `scripts/check-event-stream-official-fixture-coverage.py --require-readiness` 验证 required scenario 覆盖和 readiness，再用 `scripts/check-event-stream-official-fixture-set.py --official-root <fixtures>` 做集合级 readiness；后续有 OCU candidate fixture 时再加 `--candidate-root <fixtures>` 做同 scenario 强对比。

3. 对比 OCU candidate。
   优先用 `scripts/ingest-ocu-record-and-replay-candidate.py --recording <ocu-recording-or-metadata> --name <candidate-name> --scenario <scenario>` 导入已有 OCU recording；如果 candidate 来自 `make event-stream-action-smoke`，可把 action smoke stdout 保存成 JSONL 后用 `--smoke-json <action-smoke-output.jsonl>`，脚本会从 `recordingsRoot` / `sessionId` 找到 session 目录，并自动消费同一 JSON 里的 `mcpTranscriptPath`。因为 action smoke 默认会清理临时目录，手动保存 stdout 给后续导入时需要同时设置 `OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_KEEP_TMP=1` 或 `OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_TMPDIR=<dir>`；否则优先用 `--run-action-smoke` 让导入脚本自己跑一次 opt-in 真实输入 smoke，并保留同 session MCP transcript 到导入完成。`--run-action-smoke` 会按 `--scenario simple-action-stop|drag-stop` 触发同名真实输入采样，分别生成 click 或 drag candidate；其它非 keyboard scenario 回退到默认 mixed action smoke，只适合作为通用监听链路证据。`keyboard-input-stop` 因当前 macOS 对 synthetic keyboard event 的 session tap 过滤不稳定，先通过 `--recording` 或保留的 `--smoke-json` 导入并跑 readiness。导入时若已有其它 local MCP transcript，也可显式加 `--mcp-transcript <probe-output.json> --require-mcp-transcript-evidence`；official fixture 已入库后再加 `--official-root <official-fixtures> --check-fixture-set` 直接跑 same-scenario gate。底层仍使用 `scripts/compare-event-stream-recordings.py` 比较 event sequence、schema、metadata keys、stable metadata values、final session evidence、replay-critical semantic fields 和 AX diff evidence；官方 fixture 入库后优先打开 `--require-same-metadata-keys`、`--require-same-metadata-values`、`--require-final-session-evidence` 和 `--require-semantic-fields`，确保 metadata/session 布局键、state / active / endReason / count 这类稳定状态值、最终 `session.ended` 闭环、target AX、drag 起止点、keyboard 目标、AX treeLines 等关键证据没有从 OCU candidate 中丢失或漂移。

4. 校准官方兼容层。
   优先校准 MCP response、session 文件字段、endReason、事件字段、AX payload 和 screenshot context。保持官方三件套无参数。

5. 强化 OCU 扩展层。
   在不污染官方 surface 的前提下，继续打磨控制条、wait/notify、取消路径、权限错误和 standalone thin skill repo。

6. 拆真实 standalone repo。
   以 `scripts/scaffold-record-and-replay-skill-repo.py` 的生成物为蓝本创建独立 repo，只声明 runtime contract 和 thin skill；发布前至少跑 `scripts/check.sh`，本地具备桌面权限时再跑可选 `scripts/recording-lifecycle-smoke.py`。

## 常用验证入口

- `make event-stream-surface-smoke`
- `make event-stream-no-active-smoke`
- `make event-stream-smoke`
- `make event-stream-smoke-matrix`
- `make event-stream-action-smoke`
- `make event-stream-skill-scaffold-smoke`
- `make record-and-replay-skill-repo-smoke`
- `make codex-record-and-replay-installer-smoke`
- `make event-stream-fixture-smoke`
- `make event-stream-official-fixture-ingest-smoke`
- `make event-stream-official-fixture-coverage-smoke`
- `make event-stream-ocu-candidate-ingest-smoke`
- `make event-stream-golden-readiness-smoke`
- `make event-stream-official-fixture-set-smoke`
- `make event-stream-compare-smoke`
- `make event-stream-probe-fixture-smoke`
- `make record-and-replay-baseline-smoke` / `scripts/run-record-and-replay-baseline-smoke.sh`：本机 opt-in baseline 候选验证，串起 baseline contract smoke、默认 matrix、截图上下文 smoke、真实输入 action smoke、官方 1.0.857 non-recording surface 对比、official fixture set gate smoke、official fixture coverage report、hosted official fixture ingest smoke、OCU candidate ingest smoke、official golden capture preflight smoke、OCU candidate pairing preflight smoke、standalone repo scaffold smoke 和 npm staging scaffold smoke；脚本会先把 `scripts/test-record-and-replay-baseline-contract.py` 输出写入 `evidence.baselineContract`，证明 shared `REQUIRED_BASELINE_CHECKS`、standalone / npm staged smoke required keys、summary evidence keys 和 standalone lifecycle summary rename mapping 已在同一轮 baseline 中自检；脚本会解析 matrix / screenshot / action smoke 的 JSON 输出，在最终摘要中写入脱敏的 `evidence.eventStreamMatrix`、`evidence.screenshotContextSmoke` 和 `evidence.realInputActionSmoke`，证明 lifecycle / no-active / timeout / wait / approval / elicitation / app-agent wait-notify 路径、`OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS=always` 下的 `screenshotNeededForContext` 标记、当前环境可截图时的 `screenshotPath` 校验，以及真实 CGEvent 输入录制到 skill 草稿链路都跑过；同一 baseline 还会显式跑 `OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTION_SCENARIO=simple-action-stop|drag-stop` 的 OCU action candidate smoke，并要求 `evidence.realInputActionSmoke.checkedSimpleActionStopCandidate=true` 与 `checkedDragStopCandidate=true`，证明当前 OCU 至少能生成 click / drag 两类同场景 candidate 证据；脚本会解析官方 surface compare 的 JSON，要求 local / official 两个 label 都匹配官方 fixture，并在最终摘要中写入脱敏的 `evidence.officialSurfaceCompare`；脚本也会解析 official fixture set gate smoke 和 official fixture coverage report 的 JSON，最终摘要中的 `evidence.officialFixtureSetGate` 会证明集合级 gate、`simple-action-stop` / `keyboard-input-stop` / `drag-stop` / `cancel` / `timeout` scenario policy、candidate readiness 负例和 candidate pairing 自检都跑过，同时暴露仓库真实 official recording fixture required / recommended scenario 覆盖；required `simple-action-stop` 已入库且 ready 时会输出 required coverage/readiness 通过，推荐清单未齐时仍会输出 `repoHasRecommendedOfficialScenarioCoverage=false` / `missingRepoRecommendedOfficialScenarios=[...]`；脚本会解析 hosted official fixture ingest 与 OCU candidate ingest 的 JSON 摘要，并在 `evidence.fixtureIngestPipelines` 中要求 official ingest、`sessionDirectoryPath` handoff、candidate ingest、smoke JSON import、official/candidate pairing、candidate redaction、keyboard readiness 和 drag readiness 都为 true；脚本会解析 official capture / OCU pairing preflight smoke 的 JSON 摘要，并在 `evidence.preflightPipelines` 中要求 capture packet Make targets、capture packet、capture packet 后续 handoff scripts、recommended packet set、缺样本/缺插件/coverage error、keyboard recording-required、缺 candidate、paired candidate 和 compare 成功路径都被覆盖；也会解析 standalone / npm 两个 scaffold smoke 的 JSON 摘要，要求 runtime contract、wait/notify、recording-to-skill handoff、declared handoff paths、scaffold failure exit、cancelled recording guard、lifecycle smoke、安装态 manifest contract、官方 evidence 场景清单、官方 evidence source repo audit 命令、安装态生成 repo 默认 `check.sh` evidence、`skill-creator` handoff evidence 和官方 handoff guard evidence 都为 true，再输出带 `checkedOfficialEvidenceScenarioManifest` / `checkedOfficialEvidenceAuditManifest` 的 `evidence.standaloneSkillRepo` / `evidence.npmStagedSkillRepo` 机器可读 JSON 摘要；依赖桌面输入权限、官方 bundled cache 和当前 `dist/` artifacts，不进入默认 CI。
- `make record-and-replay-baseline-audit`：等价于 baseline smoke 加 `--summary-json`，默认把最终 summary 落到 `dist/record-and-replay-baseline-summary.json`；可用 `RNR_BASELINE_SUMMARY_JSON=<path>` 覆盖。它不改变 baseline 退出语义，只是把 release / standalone audit 证据落盘。
- `make record-and-replay-official-golden-capture-preflight`：实际运行 `scripts/prepare-record-and-replay-official-golden-capture.py`，查看当前缺口和下一条 inspect/import 命令。
- `make record-and-replay-official-golden-capture-packet`：生成单个 official capture packet；默认 `RNR_SCENARIO=simple-action-stop`，默认写到系统临时目录，可用 `RNR_PACKET_DIR=<dir>` 覆盖。该入口不启动官方录制，只写 scenario recipe、`capture-contract.json`、hosted status/transcript JSON placeholder 和 verify/inspect/import/check wrapper；`verify-inputs.sh` 会先检查输入存在、JSON 可解析且不再是 `_placeholder=true`，再按 `capture-contract.json` 检查 status JSON 至少包含 `eventsPath`，并且包含 `metadataPath` 或 `sessionPath` 这类 handoff 文件 evidence；`suppressedEventsPath` / `sessionDirectoryPath` 只作为 optional evidence 记录，避免官方最小包被误拒。transcript enabled 时还要检查 MCP transcript evidence。`capture-contract.json` 和返回 JSON 还会写 `postCaptureWorkflow`，把录制后的替换输入、verify、inspect、import、coverage / fixture-set gate、可选 OCU candidate ingest、strict audit 和 strict expected-failure audit 排成机器可读步骤。消费 hosted JSON 的 `inspect-only.sh` / `import-fixture.sh` wrapper 也会先跑同一语义校验，并拒绝仍带 `_placeholder=true` 的输入文件。单场景 packet 还会生成并在 README / JSON 中暴露 `check-fixture-set.sh`、`strict-golden-gate.sh`、`strict-expected-failure-audit.sh` 和可用时的 `ingest-ocu-candidate.sh`，用于 official fixture 导入后的 fixture-set gate、strict audit artifact 刷新、required official golden 缺口的 expected-failure audit 和 same-scenario OCU candidate 导入；`strict-golden-gate.sh` 实际运行 `make record-and-replay-official-golden-gate-audit`，`strict-expected-failure-audit.sh` 实际运行 `scripts/check-record-and-replay-baseline-summary.py dist/record-and-replay-official-golden-gate-summary.json --allow-strict-official-golden-missing`，并由 baseline summary / artifact audit 消费 `checkedOfficialCapturePacketStrictAuditHandoff`、`checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff` 和 `checkedOfficialCapturePacketPostCaptureWorkflow`。离线生成时可用 `RNR_ALLOW_MISSING_OFFICIAL_PLUGIN=1`，测试路径可用 `RNR_FIXTURE_ROOT` / `RNR_OFFICIAL_PLUGIN_ROOT` 覆盖。
- `make record-and-replay-official-golden-capture-packet-set`：生成 required + recommended capture packet set，包含 `simple-action-stop`、`keyboard-input-stop`、`drag-stop`、`cancel` 和 `timeout` 子目录以及根级 `verify-all.sh` / `inspect-all.sh` / `import-all.sh` / `check-all.sh` / `ingest-ocu-candidates.sh`；同样不启动官方录制，并支持同一组 `RNR_*` 覆盖变量。
- capture packet set 的根级 `verify-all.sh` 会逐个运行子 packet 输入校验和 `capture-contract.json` 语义校验；根级 `capture-packets.json` 会内联 `captureContracts` / `captureContractPaths` / `postCaptureWorkflow`，把每个 scenario 的 expected action event、expected `endReason`、handoff path evidence、transcript requirement 和录制后步骤顺序留在集合级 manifest，方便后续独立 repo 或 skill 直接消费；根级 `inspect-all.sh` / `import-all.sh` 会在执行任何子 packet wrapper 前，先全量检查所有场景的 hosted status response 与 MCP transcript 输入是否仍带 `_placeholder=true`，再由子 wrapper 执行 handoff / transcript semantic guard；根级 `ingest-ocu-candidates.sh` 会批量运行存在 `ingest-ocu-candidate.sh` 的子场景，并明确跳过 keyboard / cancel / timeout 这类不生成 synthetic candidate wrapper 的场景。如果 packet set 用 `--no-include-transcript` 生成，根级 wrapper 只检查 status response，不会要求不存在的 transcript 输入。official capture preflight smoke 和 baseline summary 都要求单场景 verify wrapper、单场景 inspect/import wrapper、批量 verify wrapper、批量 OCU candidate handoff wrapper、批量 contract manifest、批量 post-capture workflow、批量 wrapper 的占位拒绝行为、单场景 no-transcript packet、no-transcript packet set 行为，以及这层根级 preflight-all 行为，避免批量导入时前几个场景已写入、后续场景才因为占位 JSON 失败的半批次状态；baseline summary 还消费 `checkedOfficialCapturePacketInputSemanticGuard`、`checkedOfficialCapturePacketSetContractManifest`、`checkedOfficialCapturePacketPostCaptureWorkflow` 和 `checkedOfficialCapturePacketSetPostCaptureWorkflow`，防止 capture packet 退回只检查 JSON 形状、只保留子目录合同，或丢掉录制后的机器可读 handoff 顺序。
- `make record-and-replay-official-golden-capture-preflight-smoke`：快测 official golden capture preflight 的 JSON 输出合同。
- `make record-and-replay-official-golden-fixture-gate`：只跑仓库 official successful recording fixture 覆盖与 required readiness；比完整 baseline strict gate 更快，适合导入官方样本后立即验证 fixture 是否合格。
- `make record-and-replay-official-golden-gate-audit`：等价于 strict official golden gate 加 `--summary-json`，默认写 `dist/record-and-replay-official-golden-gate-summary.json`，可用 `RNR_OFFICIAL_GOLDEN_SUMMARY_JSON=<path>` 覆盖；用于 required official successful recording 入库后的 release gate 留证。缺 required 样本时仍应非零退出，同时写出失败摘要，但默认不会覆盖 `dist/record-and-replay-baseline-summary.json`。
- `make record-and-replay-ocu-candidate-pairing-preflight`：实际运行 `scripts/prepare-record-and-replay-ocu-candidate-pairing.py`，在 official fixture ready 后查看 same-scenario OCU candidate ingest/compare 下一步。
- `make record-and-replay-ocu-candidate-pairing-preflight-smoke`：快测 OCU candidate pairing preflight 的 JSON 输出合同。

补充：`scripts/run-record-and-replay-baseline-smoke.sh` 现在也会显式消费 `scripts/compare-event-stream-no-active.py` 的 JSON 输出，并在最终摘要写入 `evidence.officialNoActiveResponse`。该 evidence 固定 Codex-hosted no-active `event_stream_status` / `event_stream_stop` 的 `isRecording=false` / `maxDurationSeconds=1800` 最小 text JSON，并确认本地对比不会创建 session 文件；它只证明 no-active response shape，不代表 official successful recording fixture 已入库。

补充：baseline 最终摘要的顶层 `status` 会直接区分 `usableBaseline`、`standaloneRepoBaselineReady`、`officialSuccessfulRecordingGoldenComplete`、`officialSuccessfulRecordingEquivalenceReady`、`officialGoldenGatePassed` 和默认模式下的 `officialGoldenRequirementSatisfied`，并输出 `requiresOfficialGoldenCapture`、`missingRequiredOfficialSuccessfulRecordingScenarios`、`notReadyRequiredOfficialSuccessfulRecordingScenarios` 与 `missingRecommendedOfficialSuccessfulRecordingScenarios`。`standaloneRepoBaselineReady` 表示源码与 npm staged standalone scaffold 的默认 contract 已可用；`officialSuccessfulRecordingEquivalenceReady` 只有在 usable baseline 和 required official successful recording golden 同时成立时才会为 true。`officialSuccessfulRecordingGoldenComplete` / `officialGoldenGatePassed` 只有在 required official scenario 覆盖和 required fixture readiness 都通过时才会为 true；默认模式允许缺 official golden，所以 `officialGoldenRequirementSatisfied=true` 只表示当前没有强制 golden gate。只有 scenario manifest 存在但 readiness 不合格时仍会失败，并通过 `notReadyRequiredOfficialSuccessfulRecordingScenarios` 指出需要修复或重新采集的官方场景。`usableBaseline` 由各 smoke / scaffold evidence 推导；若必需 evidence 缺失，摘要会输出 `missingUsableBaselineEvidence` 并返回非零。摘要还会输出机器可读 `nextActions`，把修 baseline evidence、采 required official golden、准备 recommended capture packet set 和 scaffold standalone repo 的下一步命令直接列出。这让后续发版或拆 repo 时不用从 `evidence.officialFixtureSetGate` 里间接推断当前缺口，也不会在非 golden 的其它 baseline 证据不完整时误报可用。

补充：`realInputActionSmoke` 不再只用 `skillPath` / `mcpTranscriptPath` 间接证明真实输入录制到 skill 草稿链路。action smoke 的最终 JSON 还会输出 `checkedMcpResponseShapesCaptured`、`checkedSkillReadinessCanCreateDraft`、`checkedSkillCreatorFinalizationHandoff` 和 `checkedGeneratedSkillPathRedaction`，baseline summary 会把它们都纳入 `usableBaseline` 必需 evidence，确认同一份真实录制同时覆盖三件套 response shape、skill readiness、`skill-creator` 收尾文案和路径脱敏。完整 baseline audit 还会额外运行 `simple-action-stop` 与 `drag-stop` action candidate smoke，并把 `checkedSimpleActionStopCandidate` / `checkedDragStopCandidate` 纳入 `usableBaseline` 必需 evidence；这证明 OCU candidate 采样链路已经能覆盖 click 与 drag，但 official successful recording equivalence 仍必须等待官方 `simple-action-stop` golden fixture 入库后再判定。

补充：`usableBaseline` 对 source standalone 与 npm staged recording-to-skill 证据的最低要求包括 strict validation、events-only validation、scaffold-skill 正路径和 skill-creator handoff。缺任一项时，最终摘要会在 `missingUsableBaselineEvidence` 中报告对应的 `standaloneSkillRepo.*` 或 `npmStagedSkillRepo.*` concrete evidence 字段。

补充：baseline 摘要里的 official capture `nextActions` 不再要求调用方手拼 preflight 参数。缺 required official golden 时会先给出 `make record-and-replay-official-golden-capture-packet RNR_SCENARIO=<scenario> RNR_PACKET_DIR=<packet-dir>`，再给出 packet 内 `verify-inputs.sh`、`inspect-only.sh` / `import-fixture.sh` 和 `make record-and-replay-official-golden-gate-audit`；recommended 场景未齐时会给出 `make record-and-replay-official-golden-capture-packet-set RNR_PACKET_DIR=<packet-dir>` 以及 `verify-all.sh`、`inspect-all.sh` / `import-all.sh` / `ingest-ocu-candidates.sh`。

补充：需要把 baseline 最终摘要作为 release / standalone audit evidence 留存时，运行 `scripts/run-record-and-replay-baseline-smoke.sh --summary-json <path>`。脚本仍会把同一份机器可读 JSON 打到 stdout，并保持原有退出码；生成 summary 后会立即用 `scripts/check-record-and-replay-baseline-summary.py` 审计同一份摘要，audit 输出走 stderr，不改变 stdout / 文件中的最终 summary 合同；严格 official golden 模式失败时，也会在生成最终摘要后返回非零，方便调用方同时拿到失败证据和下一步 `nextActions`。落盘后仍可用 `scripts/check-record-and-replay-baseline-summary.py <path>` 重新做默认审计：要求顶层 `baseline=record-and-replay`、顶层 `ok` 与 `usableBaseline && officialGoldenRequirementSatisfied` 一致，顶层 `checks` 声明包含所有必需 baseline smoke / compare / preflight / standalone 检查，且不能带未知或重复 check；缺失、未知和重复项会分别在 audit JSON 的 `declaredChecks.missingRequired`、`declaredChecks.unknown` 和 `declaredChecks.duplicates` 中列出。`scripts/record_and_replay_baseline_contract.py` 是顶层 `checks` 的唯一源码，builder 负责按该 tuple 顺序输出，audit 负责按同一合同复审。审计也要求 usable baseline、standalone repo baseline、官方 non-recording / raw timeout boundary 成立，并直接检查 baseline contract、event-stream matrix、截图上下文、真实输入 action smoke、official fixture set gate、fixture ingest pipeline、official surface、no-active response、raw-timeout boundary、official capture / OCU pairing preflight、baseline audit Make target、source standalone repo 和 npm staged repo evidence，也会检查派生状态不变量：`requiresOfficialGoldenCapture` 必须和 official golden 是否完成一致，`officialSuccessfulRecordingEquivalenceReady` 必须等于 usable baseline + official golden complete，`standaloneRepoBaselineReady` 不能在 `usableBaseline=false` 时为 true，golden complete 不能同时带 required gaps / coverage errors；同时会检查 required / recommended official capture 与 standalone repo `nextActions` 是否仍包含 packet Make、verify、inspect、import、`make record-and-replay-official-golden-gate-audit`、recommended 根级 `ingest-ocu-candidates.sh`、source `record-and-replay-baseline-audit`、generated `check.sh` 和 lifecycle smoke 命令。默认模式允许缺 official successful recording golden，同时要求 `officialSuccessfulRecordingEquivalenceReady=false`。如果要做 official golden release gate，改用 `scripts/check-record-and-replay-baseline-summary.py <path> --require-official-golden`，它会要求 golden gate、required scenario readiness 和 equivalence ready 全部成立。如果要审计 `make record-and-replay-official-golden-gate-audit` 在缺 required official fixture 时写出的预期失败摘要，使用 `scripts/check-record-and-replay-baseline-summary.py <path> --allow-strict-official-golden-missing`；该模式要求 strict summary 失败只由 required official scenario missing / not-ready 解释，且 baseline/standalone/官方 non-recording/raw timeout evidence 仍完整、无 coverage errors。默认 CI 里的 runner 级 stub smoke 会验证落盘 JSON 与 stdout 最终摘要一致、runner 确实调用 summary audit，并验证严格模式缺 official golden 时仍保留非零退出码；summary audit smoke 会验证 builder 产出的顶层 `checks` 与 shared contract 顺序完全一致，并覆盖默认 / 严格审计口径、预期 strict missing 审计口径、顶层 summary / checks 不变量、unknown / duplicate checks 负例、baseline contract evidence 负例、派生状态不变量、官方边界 evidence 负例、preflight evidence 负例、usable baseline direct evidence 负例、nextActions command 负例和 audit target evidence 负例。

补充：为了让 release / standalone audit 不需要手写 runner 参数，Makefile 还提供 `make record-and-replay-baseline-audit` 和 `make record-and-replay-official-golden-gate-audit`。默认 baseline audit 使用 `RNR_BASELINE_SUMMARY_JSON` 指定落盘路径，默认是 `dist/record-and-replay-baseline-summary.json`；strict official golden audit 使用 `RNR_OFFICIAL_GOLDEN_SUMMARY_JSON` 指定落盘路径，默认是 `dist/record-and-replay-official-golden-gate-summary.json`。前者保持默认 baseline 缺 official golden 仍可通过的语义，后者保持 strict official golden 缺 required 样本时非零退出的语义，并且默认不会覆盖可用 baseline artifact。

补充：`make record-and-replay-baseline-audit-targets-smoke` / `scripts/test-record-and-replay-baseline-audit-make-targets.py` 用 `make -n` 检查上述两个 audit target 的命令展开，确认 baseline 默认/自定义 summary 路径、strict 默认/自定义 summary 路径、strict 与 baseline 默认 artifact 分离、baseline/strict summary 覆盖变量互不污染，以及 strict audit target 的 `--require-official-golden` 都未漂移。该 smoke 不启动完整 baseline 或官方录制，已接入默认 CI；完整 `scripts/run-record-and-replay-baseline-smoke.sh` 也会运行它，并在最终摘要的 `evidence.preflightPipelines` 写入 `checkedBaselineAuditMakeTargets`、`checkedBaselineAuditDefaultSummaryPath`、`checkedBaselineAuditCustomSummaryPath`、`checkedBaselineAuditIgnoresStrictSummaryVar`、`checkedBaselineAuditStrictOfficialGoldenTarget`、`checkedBaselineAuditStrictOfficialGoldenDefaultSummaryPath`、`checkedBaselineAuditStrictOfficialGoldenCustomSummaryPath`、`checkedBaselineAuditStrictOfficialGoldenIgnoresBaselineSummaryVar` 和 `checkedBaselineAuditStrictOfficialGoldenSeparateSummaryPath`。这些字段属于 `usableBaseline` 必需 evidence，避免 release / standalone audit 的短命令漂移但完整 baseline 仍误报可用。

补充：`scripts/run-record-and-replay-baseline-smoke.sh --require-official-golden` 和 `make record-and-replay-official-golden-gate` 复用同一条 baseline 聚合验证，但会在 required official successful recording fixture 缺失或 required readiness 未通过时返回非零，并输出 `officialGoldenRequirementSatisfied=false`。当前没有 `simple-action-stop` 官方 successful recording 入库时，该严格 gate 预期失败；它用于后续 official golden 入库后的 release / 拆 repo 验收，不改变默认 `make record-and-replay-baseline-smoke` 的“baseline 可用但 golden 未完成”语义。

## 下轮读文档顺序

1. `record-and-replay-handoff.md`
2. `record-and-replay-replication.md`
3. `record-and-replay-official-golden-capture.md`
4. `../references/codex-computer-use-reverse-engineering/record-and-replay-event-stream.md`
5. `../exec-plans/active/20260626-record-and-replay-event-stream.md`
6. `../../skills/open-computer-use-record-and-replay/SKILL.md`
7. `../../skills/open-computer-use/references/record-and-replay.md`
