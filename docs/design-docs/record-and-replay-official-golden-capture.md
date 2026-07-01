# Record & Replay Official Golden Capture

## 状态

本文是后续采集官方 successful recording golden fixture 的操作入口。完整方案看 `record-and-replay-replication.md`，推进总入口看 `record-and-replay-handoff.md`，官方逆向证据看 `../references/codex-computer-use-reverse-engineering/record-and-replay-event-stream.md`。

当前仓库已经有官方 1.0.857 non-recording surface、Codex-hosted no-active status/stop response、宿主外 raw start timeout 边界证据，以及最小 required `simple-action-stop` official successful recording fixture。该 required 样本来自正常 Codex-hosted Record & Replay 流程，入库后通过 readiness；recommended `keyboard-input-stop`、`drag-stop`、`cancel`、`timeout` 仍未齐。未被 official successful recording 样本覆盖的事件字段、AX compact diff、截图触发、timeout endReason 或 raw event 结构仍只能标为 OCU baseline，直到本页流程导入并通过 gate。

## 采集目标

先采 required，再采 recommended：

- Required：`simple-action-stop`，一次最小点击动作，然后通过官方录制控制结束。
- Recommended：`keyboard-input-stop`、`drag-stop`、`cancel`、`timeout`。

`prepare-record-and-replay-official-golden-capture.py` 和
`prepare-record-and-replay-ocu-candidate-pairing.py` 都会在 JSON 输出里带
`scenarioRecipe`，用于把每个 scenario 的人工采集动作、预期动作事件、
预期 `endReason`、OCU candidate 来源方式和注意事项机器可读化。正式导入
后的 `fixture-manifest.json` 也会写入同一份 `scenarioRecipe`，fixture set
gate 会拒绝 recipe 与 scenario 不匹配的样本。后续录官方样本时优先按这个
字段执行，不要只依赖聊天上下文或记忆。
同一份 scenario catalog 也生成 official / OCU direct ingest 和 fixture set
gate 的 readiness 参数，覆盖 required / recommended 清单、预期 action
event、预期 `endReason`、动作类 full AX payload、生命周期类 no-action 放行和
需要 MCP transcript 时的 completed response-shape evidence；不要在单个导入
脚本里另写一套 scenario policy。
coverage report 也会在只扫描 scenario 覆盖时校验 `scenarioRecipe` drift；
因此 manifest 里只有正确 scenario 名但 recipe 与 catalog 不一致的样本不能
作为 official golden 覆盖。
完整 baseline 摘要还会把 coverage report 的错误原样放到
`status.officialFixtureCoverageErrors` 和
`evidence.officialFixtureSetGate.coverageErrors`；严格 gate 失败时如果看到
`coverageErrors=...`，优先修复或重新导入对应 fixture，再继续 OCU candidate
对比。
采集前 `prepare-record-and-replay-official-golden-capture.py` 会把同类错误提升到
顶层 `coverageErrors` 和 `nextActions`；official fixture 入库后的
`prepare-record-and-replay-ocu-candidate-pairing.py` 也会先跑 coverage report，
并通过 `officialCoverageErrors` 阻止带坏 manifest 的 official fixture 进入
candidate pairing 判断。

每个 successful recording fixture 至少要能证明：

- `event_stream_start` / active `event_stream_status` / `event_stream_stop` / final `event_stream_status` 的 hosted MCP response shape。
- 返回的 `eventsPath` 可解析，并且至少有 `metadataPath` 或 `sessionPath` 指向官方 handoff 文件；`suppressedEventsPath` 在官方 hosted 最小包里可能不存在，导入 fixture 时会补空 `suppressed.jsonl`。
- `events.jsonl` 以唯一的 `session.started` 开头，以唯一的 `session.ended` 结束。
- 动作类场景包含对应动作事件和 AX payload。
- stop / cancel 场景的 `endReason` 与 scenario policy 一致。

官方 bundled skill 要求 `event_stream_start` 成功后结束 turn，让用户完成录制后再回来；因此 official successful recording gate 不要求额外 `repeatStartResponseShape`。重复 start / repeat stop 仍由本地 raw probe 和 OCU lifecycle smoke 覆盖 one-active / idempotent 行为，但不是 Codex-hosted official capture 的必需证据。

## 采集前检查

在采集官方样本前，先跑只读 preflight。它不会启动录制，也不会写 fixture；输出 JSON 会报告本机官方 plugin cache、当前 official scenario 覆盖、下一条 inspect-only / import / OCU candidate 命令：

```bash
./scripts/prepare-record-and-replay-official-golden-capture.py
```

如果要把后续人工采集后的导入动作落成一个可交接目录，可显式生成 capture packet：

```bash
./scripts/prepare-record-and-replay-official-golden-capture.py \
  --capture-packet-dir /tmp/ocu-rnr-official-simple-action-stop
```

也可以用 Make 入口生成同一类单场景 packet；默认场景是 required
`simple-action-stop`，默认目录是系统临时目录，可用变量覆盖：

```bash
make record-and-replay-official-golden-capture-packet
make record-and-replay-official-golden-capture-packet \
  RNR_SCENARIO=drag-stop \
  RNR_PACKET_DIR=/tmp/ocu-rnr-official-drag-stop
```

如果只想在没有官方 bundled plugin cache 的环境里预生成 packet，可加
`RNR_ALLOW_MISSING_OFFICIAL_PLUGIN=1`。测试或离线准备时也可以用
`RNR_FIXTURE_ROOT=<dir>` 和 `RNR_OFFICIAL_PLUGIN_ROOT=<dir>` 覆盖扫描路径。

该参数仍不会启动官方录制，也不会写 fixture。它只会写入 `README.md`、`preflight.json`、`scenario-recipe.json`、`capture-contract.json`、`inputs/event_stream_stop-response.json` / `inputs/mcp-transcript.json` 占位文件，以及 `verify-inputs.sh`、`verify-workflow.sh`、`inspect-only.sh`、`import-fixture.sh`、`check-coverage.sh`、`check-fixture-set.sh`、`strict-golden-gate.sh`、`strict-expected-failure-audit.sh` 和可用时的 `ingest-ocu-candidate.sh` wrapper。`verify-workflow.sh` 不读取 hosted JSON，只检查 `postCaptureWorkflow` 里的 input / command 与生成的文件、可执行 bit、transcript 开关一致。`strict-golden-gate.sh` 保留短文件名，但实际运行 `make record-and-replay-official-golden-gate-audit`，用于在 official fixture 入库后同步刷新 strict summary artifact；`strict-expected-failure-audit.sh` 审计已落盘的 `dist/record-and-replay-official-golden-gate-summary.json --allow-strict-official-golden-missing`，用于 required official golden 尚缺时证明 strict 失败是预期缺口而不是 baseline 回归。official capture preflight smoke 会输出 `checkedCapturePacketStrictAuditHandoff=true`、`checkedCapturePacketStrictExpectedFailureAuditHandoff=true`、`checkedCapturePacketPostCaptureWorkflow=true` 和 `checkedCapturePacketWorkflowVerifier=true`，并由 baseline artifact 消费为 `checkedOfficialCapturePacketStrictAuditHandoff`、`checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff`、`checkedOfficialCapturePacketPostCaptureWorkflow` 与 `checkedOfficialCapturePacketWorkflowVerifier`。返回 JSON 的 `capturePacket.includeTranscript` / `capturePacket.requiresMcpTranscriptInput` 会机器可读地声明当前 packet 是否要求 `inputs/mcp-transcript.json`，并同时给出 `captureContractPath`、`statusResponseInputPath`、`mcpTranscriptInputPath`、`verifyWorkflowShell`、`checkFixtureSetShell`、`strictGoldenGateShell`、`strictExpectedFailureAuditShell`、`postCaptureWorkflow` 和可选 `ingestOcuCandidateShell`；如果单场景 packet 使用 `--no-include-transcript` 生成，`mcpTranscriptInputPath=null`，wrapper 只校验 status response。

`capture-contract.json` 是录制后替换输入的机器合同，记录当前 scenario、fixture name、capture goal、预期 action event、预期 `endReason`、status JSON 必须出现的 handoff path key，以及是否必须提供 MCP transcript evidence。它还写入有序 `postCaptureWorkflow`，把录完官方样本后的步骤固定为替换 hosted status JSON、按需替换 MCP transcript、`verify-inputs.sh`、`inspect-only.sh`、`import-fixture.sh`、coverage / fixture-set gate、可用时的 OCU candidate ingest、strict golden audit 和 strict expected-failure audit；后续独立 repo、skill 或人工交接不应再从 README 文案里推断顺序。录完官方样本前也可以运行 `verify-workflow.sh`，先证明 `postCaptureWorkflow` 中每个 command/input 都落到了当前 packet 的真实 wrapper 和输入文件。录完官方样本后，如果保存的是 hosted `event_stream_start`、active `event_stream_status`、`event_stream_stop` 和 final `event_stream_status` 的独立 JSON，先从仓库根目录运行 `scripts/finalize-record-and-replay-official-capture-packet.py --packet-dir <packet-dir> --start-json <event_stream_start-response.json> --status-json <event_stream_status-active-response.json> --stop-json <event_stream_stop-response.json> --final-status-json <event_stream_status-final-response.json>`；它会生成 `inputs/event_stream_stop-response.json` 和 `inputs/mcp-transcript.json`，并立即跑 `verify-workflow.sh` / `verify-inputs.sh`。也可以手工用真实 hosted JSON 替换占位文件，再运行 `verify-inputs.sh`；它现在不只确认输入存在、JSON 可解析且不再是 `_placeholder=true`，还会检查 status JSON 至少包含 `eventsPath`，并且包含 `metadataPath` 或 `sessionPath` 这类 Record & Replay handoff 文件 evidence；`suppressedEventsPath` 和 `sessionDirectoryPath` 会作为 optional handoff evidence 记录，但不再阻断官方最小包。transcript enabled 时还会检查 `inputs/mcp-transcript.json` 至少包含 `startResponseShape` / `statusResponseShape` / `stopResponseShape` / `finalStatusResponseShape` / `transcript` 等 MCP transcript evidence。`inspect-only.sh` 和 `import-fixture.sh` 在执行导入命令前也会先调用同一语义校验，避免把合法但明显不是 successful recording handoff 的 JSON 送入导入链路。随后运行 `inspect-only.sh`，确认无误后再运行 `import-fixture.sh`、`check-fixture-set.sh`、`strict-golden-gate.sh`，并在存在 `ingest-ocu-candidate.sh` 时导入 same-scenario OCU candidate；`strict-golden-gate.sh` 应刷新 `dist/record-and-replay-official-golden-gate-summary.json`，不要只跑不落盘的 strict gate。required official golden 尚缺时，先让 strict gate audit 写出失败 summary，再运行 `strict-expected-failure-audit.sh` 证明失败只由缺样本解释。这个 `ingest-ocu-candidate.sh` 会显式把 candidate 写到当前 official fixture root 下的 `ocu-candidates/`，而不是落回仓库默认 candidate 目录，确保自定义 `RNR_FIXTURE_ROOT` 时 official fixture 与 OCU candidate 仍在同一组样本根目录下配对。OCU candidate 导入是后续校准动作，不是 required official golden strict gate 的硬条件；需要比较时使用 candidate 导入输出里的 `fixtureSetGateShell` 或 `pairingPreflightShell` 显式运行强对比。消费 hosted JSON 的 wrapper 仍会先检查 status response 和 MCP transcript 输入是否仍带 `_placeholder=true`，如果任一输入仍是占位文件会直接失败并提示替换对应 input。生成的 wrapper 会写入创建 packet 时的仓库路径；如果把 packet 移到别处或要针对另一个 checkout 运行，显式设置 `REPO_ROOT=/path/to/repo`。

如果要一次准备 required + recommended 的全部采集包：

```bash
./scripts/prepare-record-and-replay-official-golden-capture.py \
  --capture-packet-dir /tmp/ocu-rnr-official-golden-packets \
  --capture-packet-recommended-scenarios
```

等价 Make 入口：

```bash
make record-and-replay-official-golden-capture-packet-set
make record-and-replay-official-golden-capture-packet-set \
  RNR_PACKET_DIR=/tmp/ocu-rnr-official-golden-packets
```

这会在目标目录下为 `simple-action-stop`、`keyboard-input-stop`、`drag-stop`、`cancel` 和 `timeout` 各生成一个子目录，并写入根级 `capture-packets.json`。仍然只生成占位输入和 wrapper，不启动官方录制。`capture-packets.json` 和命令返回值都会声明 `includeTranscript` / `requiresMcpTranscriptInput`，每个子 `capturePacket` 也会带同样字段，方便后续交接脚本直接判断是否要等待或校验 transcript 输入。根级 `capture-packets.json` 还会写入 `captureContracts`、`captureContractPaths` 和按 scenario 分组的 `postCaptureWorkflow`，把每个子目录的 `capture-contract.json` 合同与录制后步骤内联到 packet set manifest；后续独立 repo、skill 或批量采集脚本可以只读根 manifest 就知道每个 scenario 的 expected action event、expected `endReason`、status handoff path evidence、transcript evidence requirement，以及替换输入、inspect-only、导入、OCU candidate ingest 和 strict audit 的执行顺序。批量目录还会生成根级 `verify-all.sh`、`verify-workflow.sh`、`inspect-all.sh`、`import-all.sh`、`check-all.sh`、`ingest-ocu-candidates.sh` 和 `strict-expected-failure-audit.sh`，用于在替换完各场景输入后按场景顺序批量执行子目录 wrapper，或在 strict summary 已落盘后审计 required official golden 缺口是否是预期失败；其中 `verify-all.sh` 会逐个运行子 packet 的 `verify-inputs.sh`，`verify-workflow.sh` 会检查根级 manifest、每个子 `capture-contract.json` 和各 wrapper 脚本一致，`inspect-all.sh` / `import-all.sh` 会先检查所有子目录的 hosted status response 与 MCP transcript 输入是否仍是 `_placeholder=true`，任一场景未替换就直接退出，不会先执行前置场景的子 wrapper；`ingest-ocu-candidates.sh` 只运行存在 `ingest-ocu-candidate.sh` 的子场景，导入 candidate 后输出校准用配对命令，并跳过 keyboard / cancel / timeout 这类需要真实录制或不生成 synthetic candidate wrapper 的场景。若生成 packet set 时使用 `--no-include-transcript`，这些 manifest 字段会是 `false`，根级 wrapper 也只检查 status response 输入，不会错误要求不存在的 `inputs/mcp-transcript.json`。baseline smoke、summary builder 和 artifact audit 通过 `checkedOfficialCapturePacketSetContractManifest`、`checkedOfficialCapturePacketSetPostCaptureWorkflow` 与 `checkedOfficialCapturePacketSetWorkflowVerifier` 守住集合级合同、有序 handoff 和 workflow verifier，避免后续只保留子目录文件而丢失可机器消费的根级上下文。该 Make 入口同样支持 `RNR_ALLOW_MISSING_OFFICIAL_PLUGIN`、`RNR_FIXTURE_ROOT` 和 `RNR_OFFICIAL_PLUGIN_ROOT`。

默认 scenario 来自 `scripts/record_and_replay_scenarios.py` 的
`DEFAULT_REQUIRED_SCENARIOS[0]`，当前是 required `simple-action-stop`。official
capture preflight、OCU candidate pairing preflight、official ingest、OCU candidate
ingest、fixture coverage report 和 fixture set gate 都应该复用这份 catalog，不要
在单个脚本里再手写另一套默认场景清单。如果只想生成命令而本机暂时没有官方
bundled plugin cache，可加：

```bash
--allow-missing-official-plugin
```

需要把 preflight 当成 release 前硬 gate 时，加：

```bash
--require-ready
```

再确认导入工具链 smoke 可用：

```bash
make event-stream-official-fixture-ingest-smoke
make event-stream-official-fixture-coverage-smoke
make event-stream-official-fixture-set-smoke
make event-stream-ocu-candidate-ingest-smoke
```

如果要确认当前 OCU baseline 仍可用，运行：

```bash
make record-and-replay-baseline-smoke
```

需要把最终机器摘要留作发版或独立 repo audit evidence 时，运行：

```bash
scripts/run-record-and-replay-baseline-smoke.sh --summary-json /tmp/ocu-rnr-baseline-summary.json
```

也可以使用 Make 包装入口。默认 baseline audit 写入
`dist/record-and-replay-baseline-summary.json`，可用 `RNR_BASELINE_SUMMARY_JSON=<path>`
覆盖：

```bash
make record-and-replay-baseline-audit
make record-and-replay-baseline-audit \
  RNR_BASELINE_SUMMARY_JSON=/tmp/ocu-rnr-baseline-summary.json
```

该命令应输出 `status.usableBaseline=true`。required `simple-action-stop` 官方样本已入库且 readiness 通过时，`status.officialSuccessfulRecordingGoldenComplete=true` / `status.requiresOfficialGoldenCapture=false` 是正确状态；如果后续在其它 checkout 或新环境里 required 样本缺失，则应回到 `status.officialSuccessfulRecordingGoldenComplete=false` / `status.requiresOfficialGoldenCapture=true`。

## 官方采集流程

官方 successful recording 必须从正常 Codex 宿主 Record & Replay 流程采集，不要把宿主外 raw MCP start timeout 当成 successful recording。

1. 在 Codex 中启动官方 Record & Replay skill / MCP tool。
2. 按目标 scenario 做最小动作。
3. 通过官方录制控制结束，或按场景取消 / 等待 timeout。
4. 保存 `event_stream_start`、active `event_stream_status`、最终 `event_stream_stop` 和完成态 final `event_stream_status` 返回 JSON。
5. 如果有同 session MCP transcript，也保存为单独 JSON；如果没有，用 `scripts/finalize-record-and-replay-official-capture-packet.py` 从第 4 步的 hosted JSON 生成 packet 所需 transcript evidence。

如果前面生成了 capture packet，把第 4 步保存的 JSON 写入 `inputs/event_stream_stop-response.json`，把第 5 步 transcript 写入 `inputs/mcp-transcript.json`，然后先运行 `verify-inputs.sh` 或根级 `verify-all.sh`。不要把原始 hosted JSON、截图、隐私文本或本机绝对路径提交进仓库；正式入库必须通过 inspect-only 与脱敏导入脚本。

不要把本机绝对路径、原始截图、原始终端内容、密码字段或隐私文本直接复制进文档。正式入库必须走导入脚本脱敏。

## Inspect-Only

先用 inspect-only 确认 hosted JSON 能解析出录制路径和 evidence，不写 fixture。优先使用 preflight JSON 里的 `commands.inspectOnlyShell`，或手动运行：

```bash
python3 scripts/ingest-official-record-and-replay-fixture.py \
  --status-json <event_stream_stop-response.json> \
  --name official-simple-action-stop-1.0.857 \
  --scenario simple-action-stop \
  --inspect-only
```

如果 status JSON 来自剪贴板或临时 stdin：

```bash
python3 scripts/ingest-official-record-and-replay-fixture.py \
  --status-json - \
  --name official-simple-action-stop-1.0.857 \
  --scenario simple-action-stop \
  --inspect-only
```

如果 hosted JSON 里的 handoff path 是相对路径，加：

```bash
--status-json-base-dir <recording-parent-dir>
```

如果同一 status JSON 已包含 response-shape evidence，可以加：

```bash
--use-status-json-as-transcript --require-mcp-transcript-evidence
```

如果 transcript 是单独文件：

```bash
--mcp-transcript <mcp-transcript.json> --require-mcp-transcript-evidence
```

Inspect-only 通过时，重点看返回 JSON 里的 `recordingInputInspection`、handoff path 是否存在，以及 MCP transcript evidence 是否满足当前 scenario。

## 正式导入

Inspect-only 通过后，去掉 `--inspect-only` 正式导入：

```bash
python3 scripts/ingest-official-record-and-replay-fixture.py \
  --status-json <event_stream_stop-response.json> \
  --name official-simple-action-stop-1.0.857 \
  --scenario simple-action-stop \
  --mcp-transcript <mcp-transcript.json> \
  --require-mcp-transcript-evidence \
  --check-fixture-set \
  --check-coverage
```

导入 required 场景时，可加 `--require-coverage`，让 required scenario 覆盖或 readiness 不足时直接失败：

```bash
--require-coverage
```

正式导入后至少运行：

```bash
python3 scripts/check-event-stream-official-fixture-coverage.py --require-readiness
python3 scripts/check-event-stream-official-fixture-set.py --official-root docs/references/codex-computer-use-reverse-engineering/fixtures/recordings
```

同一检查也有更短的 Make 入口：

```bash
make record-and-replay-official-golden-fixture-gate
```

需要机器可解析 JSON 时，直接使用上面的 `scripts/check-event-stream-official-fixture-coverage.py --require-readiness`；Make 在失败时会追加自身错误行，适合作为 human / release gate。

当 required official successful recording 入库并通过 readiness 后，严格 gate 应该通过；日常留证优先运行 audit 入口：

```bash
make record-and-replay-official-golden-gate-audit
```

如果只想跑不落盘的 human gate，也可以用：

```bash
make record-and-replay-official-golden-gate
```

需要把 strict gate 的机器摘要保存到自定义路径时，用：

```bash
make record-and-replay-official-golden-gate-audit \
  RNR_OFFICIAL_GOLDEN_SUMMARY_JSON=/tmp/ocu-rnr-official-golden-summary.json
```

不带覆盖变量时，strict gate audit 默认写入
`dist/record-and-replay-official-golden-gate-summary.json`，避免缺 required official
fixture 时的预期失败摘要覆盖 baseline 可用证据。

## OCU Candidate 对比

官方 fixture 入库后，可以先运行只读 pairing preflight。它不会启动 action smoke，也不会写 candidate fixture；只检查 official fixture readiness，并输出下一条 OCU candidate ingest / fixture set gate 命令：

```bash
./scripts/prepare-record-and-replay-ocu-candidate-pairing.py
```

或通过 Make：

```bash
make record-and-replay-ocu-candidate-pairing-preflight
```

官方 fixture 入库后，为同一 scenario 导入 OCU candidate：

```bash
python3 scripts/ingest-ocu-record-and-replay-candidate.py \
  --recording <ocu-recording-or-metadata> \
  --name ocu-simple-action-stop \
  --scenario simple-action-stop \
  --official-root docs/references/codex-computer-use-reverse-engineering/fixtures/recordings \
  --check-fixture-set
```

如果需要重新采 OCU click / drag candidate，可用真实输入 action smoke：

```bash
python3 scripts/ingest-ocu-record-and-replay-candidate.py \
  --run-action-smoke \
  --scenario simple-action-stop \
  --name ocu-simple-action-stop \
  --official-root docs/references/codex-computer-use-reverse-engineering/fixtures/recordings \
  --check-fixture-set \
  --require-mcp-transcript-evidence
```

`keyboard-input-stop` 当前不要走 synthetic keyboard `--run-action-smoke`。该场景先用已有 OCU recording 或保留的 action smoke JSONL 导入，避免 macOS 过滤合成键盘事件造成不稳定。

## 完成判定

一个 scenario 可以从 OCU baseline 升级为官方校准完成，必须同时满足：

- official fixture 已脱敏入库，并带正确 `scenario` 与 `scenarioRecipe` manifest。
- `check-event-stream-official-fixture-coverage.py --require-readiness` 通过。
- `check-event-stream-official-fixture-set.py` 对 official fixture 通过。
- 同 scenario OCU candidate 可通过 fixture set gate 或 recording compare。
- 相关文档删除或更新对应 “待 official golden 校准” 标记。

没有通过这些 gate 前，文档和代码注释都应继续使用 “OCU baseline”“官方风格” 或 “待 official golden 校准”。
