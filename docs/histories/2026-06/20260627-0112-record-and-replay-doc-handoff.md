## [2026-06-27 01:12] | Task: Record & Replay 文档交接

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> 把方案和相关上下文落到 docs 里，后续会基于这个推进解决。

### 🛠 Changes Overview
**Scope:** docs

**Key Actions:**
- **[Handoff]**: 新增 `docs/design-docs/record-and-replay-handoff.md`，作为 Record & Replay 后续推进的短入口。
- **[Context]**: 汇总官方兼容层 / OCU 扩展层边界、已沉淀官方证据、当前 OCU baseline、待解决问题、下一轮推进顺序和常用验证入口。
- **[Navigation]**: 更新 `docs/design-docs/index.md`，让后续 Agent 可以从设计索引直接发现 handoff 文档。
- **[Concurrent Recording]**: 补齐官方 one-active handoff：重复 start 返回 active session 时，agent 应询问用户要使用当前录制还是等待它结束，不能静默把它当成本次新 demonstration。

### 🧠 Design Intent (Why)
Record & Replay 的实现上下文已经横跨设计、逆向、执行计划、skill 和验证脚本。新增短 handoff 文档用于把“下一轮应该从哪里读、按什么顺序推进、哪些边界不能破坏”固定到仓库里，避免后续继续依赖聊天上下文。

### 📁 Files Modified
- `docs/design-docs/record-and-replay-handoff.md`
- `docs/design-docs/index.md`
- `docs/histories/2026-06/20260627-0112-record-and-replay-doc-handoff.md`

### 🔁 Follow-up (2026-06-27, clarify replication boundaries)

- **[Official Replication Boundary]**: 补充“直接复刻官方”的仓库口径：复刻可观察协议、session 文件、事件流、AX payload、截图上下文和 skill handoff，不复制官方私有实现，也不把 OCU 私有扩展塞进三件套 MCP surface。
- **[Codex.app Boundary]**: 明确当前 asar 观察只支持把 Codex.app 视为 host / feature gate / 通用 elicitation UI；OCU 必须自己承担开始确认、录制中 bar、Done / Discard、wait 唤醒和 notify callback。
- **[Calibration Notes]**: 在 handoff 中补齐 screenshot、compact AX diff、skill handoff 和 golden fixture 的易混边界，后续推进时必须区分官方已确认、OCU baseline 和待 official golden 校准。

### 🔁 Follow-up (2026-06-27, make the plan actionable)

- **[Execution Protocol]**: 在 `record-and-replay-handoff.md` 增加后续推进协议，要求每个改动先归类为官方兼容层、OCU 扩展层或待官方校准 baseline，再按证据、实现、验证、文档同步闭环推进。
- **[Decision Scope]**: 在 `record-and-replay-replication.md` 固定当前方案口径：macOS first、接受 `event-stream` 子命令、直接复刻官方可观察行为、OCU 自己承载控制条 / wait / notify，独立 repo 只包装 runtime。
- **[Plan Entry]**: 在 active execution plan 中补充下一轮先读 handoff 的入口说明，避免后续推进继续依赖聊天上下文。

### 🔁 Follow-up (2026-06-27, standalone repo contract)

- **[Manifest Contract]**: standalone thin skill repo scaffold 的 `record-and-replay-skill-repo.json` 新增默认 `checks`，把 package、runtime contract、synthetic recording-to-skill smoke 和组合 self-check 明确为发布/安装前门禁；`optionalChecks` 只保留会真实创建 recording session 的 lifecycle smoke。
- **[Docs Sync]**: 在 handoff、replication、architecture、CI/CD、quality score 和 active execution plan 中同步“默认自检不启动真实录制，可选 lifecycle 才启动录制”的边界。
- **[Test Sync]**: 更新 standalone repo scaffold smoke 断言，确保生成态 manifest 的 `checks` / `optionalChecks` 分层不会回退。

### 🔁 Follow-up (2026-06-27, freeze replication decision)

- **[Decision Entry]**: 在 handoff 中补充本轮结论，明确后续以“直接复刻官方可观察行为 + OCU 独立扩展”为推进基线。
- **[Interface Contract]**: 在 replication 文档中增加官方兼容合同、OCU 扩展合同、校准合同和独立 repo 合同，方便后续评审判断新能力应落在哪一层。
- **[Evidence Boundary]**: 在逆向参考中补充当前证据能证明和不能证明的内容，避免把 Codex.app feature gate / elicitation 观察误解成 Codex.app 自己实现录制控制条或事件文件。

### 🔁 Follow-up (2026-06-27, doc landing map)

- **[Landing Map]**: 在 handoff 中补充方案落库地图，明确短入口、完整设计、执行计划、官方逆向证据、thin skill、通用 skill 参考和 standalone repo scaffold 的位置。
- **[Next Paths]**: 补充后续最短路径，分别覆盖继续官方复刻和拆真实 standalone repo 两条推进方式。
- **[Backlink]**: 在 replication 文档关联文档区补充 handoff 反链，方便从完整设计回到短入口。

### 🔁 Follow-up (2026-06-27, doc completeness gate)

- **[Completion Criteria]**: 在 handoff 中补充落库完成判定，明确后续必须能从仓库回答官方复刻原因、官方兼容层 / OCU 扩展层边界、待 golden 校准 baseline、官方样本采集路径和 standalone repo 自检分层。
- **[Context Hygiene]**: 固定规则：如果新改动的关键判断只能从聊天上下文推断，应先补文档再继续实现。

### 🔁 Follow-up (2026-06-27, official golden capture checklist)

- **[Capture Checklist]**: 新增 `docs/design-docs/record-and-replay-official-golden-capture.md`，把官方 successful recording golden fixture 的采集前检查、hosted JSON inspect-only、正式导入、OCU candidate 对比和完成判定收敛成短操作清单。
- **[Navigation]**: 更新 `docs/design-docs/index.md` 和 `docs/design-docs/record-and-replay-handoff.md`，让后续 R&R 推进可以从 handoff 直接跳到 official golden 采集流程。

### 🔁 Follow-up (2026-06-27, official golden capture preflight)

- **[Preflight Script]**: 新增 `scripts/prepare-record-and-replay-official-golden-capture.py`，作为采集官方 successful recording 前的只读 preflight，检查 official plugin cache、当前 scenario coverage/readiness，并输出 inspect-only、正式导入、strict gate 和 OCU candidate 命令。
- **[Smoke]**: 新增 `scripts/test-record-and-replay-official-golden-capture-preflight.py` 和 `make record-and-replay-official-golden-capture-preflight-smoke`，覆盖缺 required scenario、`--require-ready` 失败、缺 official plugin、允许缺 plugin 以及 keyboard 场景不使用 synthetic action smoke 的输出合同；`make record-and-replay-official-golden-capture-preflight` 保留为真实只读 preflight 入口。
- **[Docs Sync]**: 更新 official golden capture 文档、handoff 和架构说明，明确采样前优先跑 preflight，且该入口不会启动录制或写 fixture。

### 🔁 Follow-up (2026-06-27, fast official fixture gate)

- **[Fast Gate]**: 新增 `make record-and-replay-official-golden-fixture-gate`，直接复用 `scripts/check-event-stream-official-fixture-coverage.py --require-readiness`，用于导入官方 successful recording 后快速验证 required scenario 覆盖和 readiness。
- **[Docs Sync]**: 更新 README、中文 README、official capture checklist、handoff、architecture 和 quality score，明确 fast fixture-only gate 与完整 `make record-and-replay-official-golden-gate` release gate 的区别。

### 🔁 Follow-up (2026-06-27, OCU candidate pairing preflight)

- **[Pairing Preflight]**: 新增 `scripts/prepare-record-and-replay-ocu-candidate-pairing.py`，在 official fixture 入库后只读检查 same-scenario OCU candidate 状态，并生成 candidate ingest 与 fixture-set compare 命令。
- **[Smoke]**: 新增 `scripts/test-record-and-replay-ocu-candidate-pairing-preflight.py` 和 `make record-and-replay-ocu-candidate-pairing-preflight-smoke`，覆盖缺 official、official ready 但缺 candidate、candidate paired 通过和 keyboard 场景不走 synthetic action smoke 的输出合同。
- **[Docs Sync]**: 更新 README、中文 README、official capture checklist、handoff、architecture 和 quality score，明确 pairing preflight 不启动 action smoke、不写 candidate fixture，只负责组织官方入库后的下一步。

### 🔁 Follow-up (2026-06-27, scenario recipe preflight output)

- **[Scenario Catalog]**: 新增 `scripts/record_and_replay_scenarios.py`，把 `simple-action-stop`、`keyboard-input-stop`、`drag-stop`、`cancel` 和 `timeout` 的采集动作、预期 action event、预期 endReason、OCU candidate 来源方式和注意事项收敛成共享机器可读 recipe。
- **[Preflight Contract]**: `prepare-record-and-replay-official-golden-capture.py` 和 `prepare-record-and-replay-ocu-candidate-pairing.py` 的 JSON 输出新增 `scenarioRecipe`，让后续官方 golden 采样和 OCU candidate 配对不再依赖聊天上下文。
- **[Smoke]**: 更新两个 preflight smoke，固定 required click 场景和 keyboard 场景的 recipe 输出，尤其是 keyboard 不走 synthetic `--run-action-smoke` 的约束。

### 🔁 Follow-up (2026-06-27, scenario recipe fixture manifest)

- **[Fixture Manifest]**: `scripts/import-event-stream-fixture.py` 现在会把 `scenarioRecipe` 写入 `fixture-manifest.json`，让脱敏后的 official / OCU fixture 仍保留采集合同。
- **[Gate]**: `scripts/check-event-stream-official-fixture-set.py` 会校验 manifest recipe 与当前 scenario catalog 一致，拒绝只有 scenario 名但 recipe 漂移的 fixture。
- **[Smoke]**: 更新 fixture import smoke 和 official fixture set smoke，覆盖 recipe 写入和 recipe drift 负例。

### 🔁 Follow-up (2026-06-27, scenario catalog readiness policy)

- **[Catalog Policy]**: `scripts/record_and_replay_scenarios.py` 新增 shared readiness args 生成逻辑，让 expected action event、expected endReason、full AX / no-action 放行和 MCP response-shape evidence 都从 scenario catalog 派生。
- **[Gate Sync]**: official fixture set gate、official coverage report、hosted official ingest 和 OCU candidate ingest 都改为复用同一份 scenario catalog；direct ingest 不再维护弱于集合 gate 的场景规则。
- **[Smoke]**: official ingest smoke 新增 `keyboard-input-stop` / `drag-stop` direct readiness 覆盖，并复跑 fixture set、coverage、official ingest、OCU candidate ingest 相关 smoke。

### 🔁 Follow-up (2026-06-27, coverage recipe drift gate)

- **[Coverage Gate]**: `scripts/check-event-stream-official-fixture-coverage.py` 现在也会校验 official fixture manifest 的 `scenarioRecipe` 是否匹配共享 catalog；不跑 readiness 的快速 coverage report 也不会把 recipe 漂移的 fixture 算作有效 golden 覆盖。
- **[Smoke]**: `scripts/test-event-stream-official-fixture-coverage.py` 新增 recipe drift 负例，确认 `scenarioRecipeMatches=false` 会进入错误输出。
- **[Docs Sync]**: 同步 architecture、official capture checklist 和 quality score，明确 coverage 层也会拒绝只有 scenario 名但采集合同漂移的样本。

### 🔁 Follow-up (2026-06-27, baseline coverage error evidence)

- **[Summary Gate]**: `scripts/build-record-and-replay-baseline-summary.py` 现在会把 official fixture coverage report 的 `errors` 保留到 `status.officialFixtureCoverageErrors` 和 `evidence.officialFixtureSetGate.coverageErrors`。
- **[Strict Gate Output]**: 严格 official golden gate 失败时会把 recipe drift、重复 scenario 或 manifest 错误作为 `coverageErrors=...` 输出到 stderr，不再退化成模糊的 readiness 失败。
- **[Smoke]**: `scripts/test-record-and-replay-baseline-summary.py` 新增 coverage error 负例，确认最终 JSON 与 stderr 都能暴露具体 coverage 错误。

### 🔁 Follow-up (2026-06-27, preflight coverage errors)

- **[Official Preflight]**: `scripts/prepare-record-and-replay-official-golden-capture.py` 现在把 coverage report `errors` 提升为顶层 `coverageErrors`，并在 `nextActions` 中要求先修复 recipe drift、重复 scenario 或 manifest 错误。
- **[Pairing Preflight]**: `scripts/prepare-record-and-replay-ocu-candidate-pairing.py` 现在会先跑 official fixture coverage report，再跑 fixture set gate；输出 `officialCoverageErrors`，避免坏 manifest 的 official fixture 进入 OCU candidate pairing 判断。
- **[Smoke]**: official capture preflight 和 OCU pairing preflight smoke 都新增 recipe drift 负例，确认 coverage error 会在 JSON 和 next action 中显式出现。

### 🔁 Follow-up (2026-06-27, standalone scenario recipes)

- **[Standalone Manifest]**: `scripts/scaffold-record-and-replay-skill-repo.py` 生成的 `record-and-replay-skill-repo.json` 现在在 `officialEvidence.scenarioRecipes` 中写入 recommended scenario 的完整 recipe，而不只保留场景名清单。
- **[Contract Scope]**: 这些 recipe 固化 capture goal、预期 action event、预期 endReason、evidence 要求和 OCU candidate 来源，方便独立 repo 后续按同一合同采集官方 golden 和配对 OCU candidate。
- **[NPM Packaging]**: npm package 现在随 `scaffold-record-and-replay-skill-repo.py` 一起复制 `record_and_replay_scenarios.py`，保证安装态 scaffold 命令也能生成同一份 manifest recipe。
- **[Smoke]**: 源码 scaffold smoke 与 npm staged scaffold smoke 都按 exact manifest 断言 `scenarioRecipes`，npm staged smoke 还会显式检查 scenario catalog helper 已被打包，避免后续拆 repo 时丢失采样动作细节。

### 🔁 Follow-up (2026-06-27, official capture packet)

- **[Preflight Packet]**: `scripts/prepare-record-and-replay-official-golden-capture.py --capture-packet-dir <dir>` 现在会生成官方采集包，包含 `README.md`、`preflight.json`、`scenario-recipe.json`、hosted status/transcript placeholder 和 inspect/import/check wrapper。
- **[Packet Set]**: 加 `--capture-packet-recommended-scenarios` 时，会为 `simple-action-stop`、`keyboard-input-stop`、`drag-stop`、`cancel` 和 `timeout` 各生成一个子目录，并写入根级 `capture-packets.json`、`inspect-all.sh`、`import-all.sh`、`check-all.sh` 和 `ingest-ocu-candidates.sh`。
- **[Boundary]**: 该入口仍不会启动官方录制，也不会写 fixture；它只服务录完官方样本后的无写入 inspect-only 与脱敏导入交接。
- **[Smoke]**: official golden capture preflight smoke 覆盖单场景 / 批量 packet 文件结构、placeholder JSON、scenario recipe 和 wrapper 脚本输入路径。

### 🔁 Follow-up (2026-06-27, baseline summary gate wording)

- **[Baseline Smoke]**: 复跑 `make record-and-replay-baseline-smoke` 通过，证明当前 usable baseline 仍完整；摘要继续报告 required `simple-action-stop` 和 recommended official successful recording fixtures 缺失。
- **[Status Semantics]**: `scripts/build-record-and-replay-baseline-summary.py` 现在区分 `officialGoldenGatePassed` 和 `officialGoldenRequirementSatisfied`。默认模式允许缺 official golden 时只让 requirement satisfied，不再把 missing golden 误标为 gate passed。
- **[Smoke]**: baseline summary smoke 更新默认缺 golden、严格缺 golden、baseline evidence 缺失和严格 covered 四类断言。

### 🔁 Follow-up (2026-06-27, docs navigation tightening)

- **[Design Index]**: 在 `docs/design-docs/index.md` 增加 Record & Replay 默认阅读顺序，固定 handoff、完整设计、official golden capture checklist、逆向参考和 active execution plan 的入口关系。
- **[Reference Index]**: 在 `docs/references/README.md` 明确 Record & Replay 逆向参考入口，说明该文档承载官方插件包装、Codex.app asar 分工、runtime 字符串、event-stream surface、non-recording fixtures 和 official golden 缺口。

### 🔁 Follow-up (2026-06-27, baseline runner early evidence gate)

- **[Runner Gate]**: `scripts/run-record-and-replay-baseline-smoke.sh` 现在在 source / npm staged standalone 子 smoke 后立即检查完整必需 evidence，再进入 summary builder。
- **[Evidence Coverage]**: 早期 gate 新增 generated README scenario list、`sourceRepoBaselineAudit` manifest、malformed MCP request 副作用、notify suppressed path、callback failure 和 callback timeout evidence，避免缺字段到最终 summary / artifact audit 才暴露。
- **[Smoke]**: `scripts/test-record-and-replay-baseline-runner-summary-json.py` 新增篡改 standalone evidence 的负例，确认缺关键字段时 runner 返回非零且不会写 `--summary-json` artifact。

### 🔁 Follow-up (2026-06-27, standalone evidence shared contract)

- **[Shared Contract]**: `scripts/record_and_replay_baseline_contract.py` 新增 standalone / npm staged skill repo smoke required keys 和 summary evidence keys，作为 baseline runner early gate 与 artifact audit 的共享来源。
- **[Runner Sync]**: `scripts/run-record-and-replay-baseline-smoke.sh` 的 source / npm staged standalone early gate 改为读取 shared contract，不再手写长 key 列表。
- **[Audit Sync]**: `scripts/check-record-and-replay-baseline-summary.py` 的 standalone / npm staged direct evidence audit 改为读取 shared contract。
- **[Smoke]**: `scripts/test-record-and-replay-baseline-summary.py` 断言最终 summary 的 `standaloneSkillRepo` / `npmStagedSkillRepo` evidence key 集合与 shared contract 完全一致。

### 🔁 Follow-up (2026-06-27, baseline contract self-test)

- **[Contract Smoke]**: 新增 `scripts/test-record-and-replay-baseline-contract.py` 和 `make record-and-replay-baseline-contract-smoke`，直接校验 baseline shared contract 非空、无重复，并固定 standalone lifecycle smoke keys 到 summary evidence keys 的重命名关系。
- **[CI Sync]**: `scripts/ci.sh` 默认运行该 contract smoke，避免 runner、summary builder 和 artifact audit 都消费同一份 contract 时仍遗漏 contract 内部映射错误。

### 🔁 Follow-up (2026-06-28, baseline contract artifact evidence)

- **[Baseline Evidence]**: `scripts/run-record-and-replay-baseline-smoke.sh` 现在会运行 baseline contract smoke，并把 JSON 写入最终 summary 的 `evidence.baselineContract`。
- **[Summary Gate]**: `scripts/build-record-and-replay-baseline-summary.py` 将 shared checks、standalone/npm key 集和 standalone lifecycle rename mapping 纳入 `usableBaseline` 必需 evidence。
- **[Artifact Audit]**: `scripts/check-record-and-replay-baseline-summary.py` 会审计 `evidence.baselineContract`；summary smoke 与 audit smoke 都覆盖缺失 / 篡改 contract evidence 的负例。

### 🔁 Follow-up (2026-06-28, standalone baseline contract manifest)

- **[Standalone Manifest]**: `scripts/scaffold-record-and-replay-skill-repo.py` 生成的 `officialEvidence.sourceRepoBaselineChecks` 新增 `baselineContract=baseline-contract-smoke`，README 同步说明源仓 baseline 会先跑 baseline contract smoke。
- **[Smoke]**: source scaffold smoke 与 npm staged scaffold smoke 的 exact manifest 断言同步覆盖该字段，避免独立 repo handoff 漏掉 shared contract self-check 证据入口。

### 🔁 Follow-up (2026-06-28, refreshed baseline audit artifact)

- **[Full Baseline Audit]**: 复跑 `make record-and-replay-baseline-audit` 通过，刷新 `dist/record-and-replay-baseline-summary.json`。
- **[Artifact Evidence]**: 新 summary 的 `checks` 包含 `baseline-contract-smoke`，`evidence.baselineContract.ok=true`，并通过 `scripts/check-record-and-replay-baseline-summary.py` 审计。
- **[Current Gap]**: summary 继续保持 `usableBaseline=true` 和 `standaloneRepoBaselineReady=true`，同时保持 `officialSuccessfulRecordingGoldenComplete=false` / `officialSuccessfulRecordingEquivalenceReady=false`，缺口仍是 required `simple-action-stop` 以及 recommended `cancel`、`drag-stop`、`keyboard-input-stop`、`simple-action-stop`、`timeout` official successful recording fixtures。

### 🔁 Follow-up (2026-06-27, malformed MCP request side effects)

- **[Runtime Contract]**: standalone thin skill repo manifest 新增 `mcpServer.rejectedRequestsDoNotCreateSessionFiles=true`，把 malformed official-compatible `tools/call` 请求不创建 session 文件的边界显式落进机器可读 contract。
- **[Evidence]**: 生成态 `verify-runtime.py`、源码 standalone smoke、npm staged smoke 和 baseline summary 现在都会输出 / 消费 `checkedRejectsUnexpectedArguments`、`checkedRejectsNonObjectArguments` 和 `checkedRejectedRequestsDoNotCreateSessionFiles`。
- **[Smoke]**: baseline summary smoke 新增负例，确认缺少 rejected request side-effect evidence 时 `usableBaseline=false`。

### 🔁 Follow-up (2026-06-27, npm staged request-shape parity)

- **[Parity]**: npm staged standalone smoke 现在也要求生成 repo 的 `check.sh` 输出 `checkedRequiresObjectParams`、`checkedRequiresStringToolName` 和 `checkedRequiresObjectArguments`，与源码 standalone smoke 的 runtime contract 证据保持一致。
- **[Summary Gate]**: baseline summary 将 npm staged request-shape evidence 纳入 `usableBaseline` 必需条件，缺少安装态 params/name/arguments shape 证明时会返回非零。
- **[Smoke]**: baseline summary smoke 新增 npm staged request-shape 负例，确认 `npmStagedSkillRepo.checkedRequiresObjectParams` 等证据不会被遗漏。

### 🔁 Follow-up (2026-06-27, official raw timeout baseline evidence)

- **[Probe Evidence]**: `scripts/test-event-stream-probe-fixtures.py` 现在输出官方 raw start/status/stop 宿主外 timeout 的细分 evidence，包含三次 `tools/call` timeout、无 recording handoff paths、官方 surface 和脱敏检查。
- **[Summary Gate]**: `scripts/run-record-and-replay-baseline-smoke.sh` 会显式运行 raw timeout fixture smoke；`scripts/build-record-and-replay-baseline-summary.py` 写入 `evidence.officialRawStartTimeout`，并把这些字段纳入 `usableBaseline` 必需 evidence。
- **[Smoke]**: baseline summary smoke 新增 raw timeout 负例，确认缺少 `checkedOfficialRawStartDoesNotReturnRecordingPaths` 时默认 baseline 会失败，而不是把 hostless raw timeout 误读成 successful recording 证据。

### 🔁 Follow-up (2026-06-27, preflight baseline evidence)

- **[Preflight Evidence]**: official golden capture preflight smoke 与 OCU candidate pairing preflight smoke 现在都会输出机器可读 JSON 摘要，便于 baseline 聚合脚本消费。
- **[Summary Gate]**: `scripts/run-record-and-replay-baseline-smoke.sh` 会显式运行两条 preflight smoke；`scripts/build-record-and-replay-baseline-summary.py` 写入 `evidence.preflightPipelines`，并把 capture packet Make targets、capture packet、recommended packet set、packet set 根级 placeholder guard、缺 official 样本、缺插件、coverage error、keyboard recording-required、缺 candidate、paired candidate 和 compare 成功路径纳入 `usableBaseline` 必需 evidence。
- **[Smoke]**: baseline summary smoke 新增 official capture preflight 与 OCU pairing preflight 负例，确认缺少这些下一步操作入口证据时默认 baseline 会失败。

### 🔁 Follow-up (2026-06-27, standalone preflight manifest contract)

- **[Standalone Manifest]**: `scripts/scaffold-record-and-replay-skill-repo.py` 生成的 `officialEvidence` 新增 `sourceRepoBaselineChecks`，声明 hostless raw timeout、official golden capture preflight 和 OCU candidate pairing preflight 由 OCU 源仓 baseline 验证。
- **[Boundary Contract]**: 同一 manifest 新增 `standaloneRepoBoundary`，明确独立 repo 默认自检不启动官方录制、不复制 preflight 脚本、不复制 OCU runtime 源码；生成 README 同步说明这些 preflight 只属于源仓 release / baseline gate。
- **[Evidence]**: 源码 scaffold smoke、npm staged scaffold smoke 和 baseline summary 都新增 `checkedOfficialEvidencePreflightManifest=true`，并在 baseline summary smoke 中加入缺失负例，避免后续拆 repo 时只保留 successful recording 场景清单却丢失采样/配对前置门禁。

### 🔁 Follow-up (2026-06-27, baseline readiness split)

- **[Status Split]**: `scripts/build-record-and-replay-baseline-summary.py` 新增 `standaloneRepoBaselineReady` 和 `officialSuccessfulRecordingEquivalenceReady`。前者由 usable baseline + standalone/npm scaffold evidence 推导，后者由 usable baseline + required official successful recording golden 推导。
- **[Misclaim Guard]**: 当前缺 official successful recording golden 时，baseline 可以明确显示 `standaloneRepoBaselineReady=true` 但 `officialSuccessfulRecordingEquivalenceReady=false`，避免把“可拆 standalone repo 的 baseline”误读成“官方事件 schema / AX / screenshot 等价已经完成”。
- **[Smoke]**: baseline summary smoke 新增默认缺 golden、baseline evidence 缺失和 strict covered 三类断言，固定这两个派生状态的语义。

### 🔁 Follow-up (2026-06-27, baseline next actions)

- **[Summary Guidance]**: `scripts/build-record-and-replay-baseline-summary.py` 新增顶层 `nextActions`，根据当前 evidence 输出下一步机器可读动作。
- **[Action Branches]**: 缺 usable baseline evidence 时输出修复 baseline 的命令；缺 required official golden 时输出 official capture preflight、inspect-only ingest 和 strict golden gate 命令；recommended 场景未齐时输出 capture packet set 命令；standalone baseline ready 时输出 scaffold repo、生成 repo `check.sh` 和 optional lifecycle smoke 命令。
- **[Smoke]**: baseline summary smoke 覆盖默认缺 golden、baseline evidence 缺失和 strict covered 三类 `nextActions` 分支，确保后续发版 / 拆 repo 不需要人工从底层 evidence 拼下一步。

### 🔁 Follow-up (2026-06-27, baseline summary artifact output)

- **[Baseline Artifact]**: `scripts/run-record-and-replay-baseline-smoke.sh --summary-json <path>` 现在可以把最终机器可读 baseline 摘要写入文件，同时继续向 stdout 打印同一 JSON。
- **[Exit Semantics]**: `--summary-json` 不改变默认 baseline 或 `--require-official-golden` 严格 gate 的退出码；严格 gate 缺官方 successful recording golden 时仍会在写出摘要后返回非零。
- **[Docs Sync]**: handoff、replication、official capture guide、execution plan 和 quality score 都记录该参数，方便后续 release / standalone audit 留存 evidence。

### 🔁 Follow-up (2026-06-27, official capture packet make targets)

- **[Make Targets]**: 新增 `make record-and-replay-official-golden-capture-packet` 和 `make record-and-replay-official-golden-capture-packet-set`，分别生成单场景 official capture packet 和 required+recommended packet set。
- **[Safety Boundary]**: 两个 target 只调用 read-only preflight 与 packet writer，不启动官方录制、不写 fixture；输出目录默认在系统临时目录，可用 `RNR_PACKET_DIR=<dir>` 覆盖，单场景可用 `RNR_SCENARIO=<scenario>` 覆盖。
- **[Docs Sync]**: official capture guide、handoff、architecture 和 quality score 已同步记录这两个入口，后续采集 official successful recording golden 时不用手写长参数。

### 🔁 Follow-up (2026-06-27, packet make target smoke coverage)

- **[Make Variables]**: capture packet Make targets 新增 `RNR_ALLOW_MISSING_OFFICIAL_PLUGIN=1`、`RNR_FIXTURE_ROOT` 和 `RNR_OFFICIAL_PLUGIN_ROOT`，允许在没有官方 bundled plugin cache 的干净环境里只生成 packet 命令。
- **[Smoke]**: `scripts/test-record-and-replay-official-golden-capture-preflight.py` 现在直接调用两个 Make target，验证单场景 packet、recommended packet set、missing-plugin allowed 模式和生成文件结构。
- **[Baseline Evidence]**: baseline summary 现在消费 `checkedMakeCapturePacketTargets`，如果 Make packet 入口不再生成可用采集包，`usableBaseline` 会失败并报告 `preflightPipelines.checkedOfficialCapturePacketMakeTargets`。
- **[Docs Sync]**: official capture guide、handoff、architecture、execution plan 和 quality score 已同步说明这些变量。

### 🔁 Follow-up (2026-06-27, baseline next actions packet commands)

- **[Summary Guidance]**: baseline summary 的 `nextActions` 现在把 official capture 下一步直接指向 `make record-and-replay-official-golden-capture-packet` 和 `make record-and-replay-official-golden-capture-packet-set`。
- **[Packet Wrappers]**: required golden 缺口会列出 packet 内 `inspect-only.sh` / `import-fixture.sh` 和 strict gate；recommended 缺口会列出 packet set 内 `inspect-all.sh` / `import-all.sh` / `ingest-ocu-candidates.sh`。
- **[Smoke]**: baseline summary smoke 新增命令级断言，确保默认缺 official golden 时机器可读摘要不会退回旧的手写 preflight 参数。

### 🔁 Follow-up (2026-06-27, baseline next action packet execution)

- **[Smoke]**: baseline summary smoke 现在会取 `nextActions` 里的 packet Make 命令，替换临时 `RNR_PACKET_DIR` 后实际执行，验证 required 单场景 packet 能生成 `preflight.json`、`scenario-recipe.json`、`inspect-only.sh` 和 `import-fixture.sh`。
- **[Smoke]**: 同一 smoke 也会执行 recommended packet set 命令，验证 `capture-packets.json`、`inspect-all.sh`、`import-all.sh` 和 `ingest-ocu-candidates.sh` 存在，并固定 recommended 场景顺序。
- **[Offline Mode]**: 测试执行时追加 `RNR_ALLOW_MISSING_OFFICIAL_PLUGIN=1`、`RNR_FIXTURE_ROOT` 和 `RNR_OFFICIAL_PLUGIN_ROOT` 覆盖，保证干净环境也能验证 summary 命令链路本身。

### 🔁 Follow-up (2026-06-27, capture packet placeholder guard)

- **[Wrapper Guard]**: capture packet 的 `inspect-only.sh` / `import-fixture.sh` 现在会在执行导入命令前检查 input JSON 是否仍带 `_placeholder=true`。
- **[Failure Mode]**: 如果用户还没有把 hosted official JSON 写入 `inputs/event_stream_stop-response.json` 或 `inputs/mcp-transcript.json`，wrapper 会以明确错误退出，避免把占位 JSON 传进 ingest 链路。
- **[Smoke]**: official capture preflight smoke 覆盖 status response 与 MCP transcript 两类 placeholder guard，也执行 packet set 根级 `inspect-all.sh` / `import-all.sh`，确认它们会传播子 packet 的 placeholder 失败；`check-coverage.sh` 这类不消费 hosted JSON 的 wrapper 不会被该 guard 阻塞。baseline summary 也把 `checkedOfficialCapturePacketPlaceholderGuard`、`checkedOfficialCapturePacketTranscriptPlaceholderGuard` 和 `checkedOfficialCapturePacketSetRootPlaceholderGuard` 纳入 `preflightPipelines` evidence。

### 🔁 Follow-up (2026-06-27, handoff context consolidation)

- **[Context Handoff]**: `docs/design-docs/record-and-replay-handoff.md` 新增“快速上下文结论”，把官方 plugin / Codex.app / Computer Use runtime 的分工、OCU 自有 bar / wait / notify 边界、官方三件套 no-arg surface、截图上下文口径和 compact AX diff 定义集中写清。
- **[Calibration Boundary]**: 同一段明确当前只有 non-recording surface、no-active response 和 hostless raw timeout evidence，仍没有 official successful recording fixture；事件 schema、AX compact diff、截图触发、timeout endReason 和 raw event 结构都不能宣称官方等价。
- **[Next Step]**: 文档明确后续缺 official golden 时应优先走 capture packet、替换 hosted JSON、运行 packet wrapper inspect/import，再进入 fixture gate 和 OCU candidate pairing，避免继续依赖聊天上下文拼命令。

### 🔁 Follow-up (2026-06-28, baseline action scenario evidence)

- **[Baseline Audit]**: 完整 `make record-and-replay-baseline-audit` 现在在默认 `mixed-action-stop` action smoke 之外，额外运行 `OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTION_SCENARIO=simple-action-stop|drag-stop`，把 click / drag 两类 OCU 同场景 candidate 采样纳入同一份 baseline evidence。
- **[Summary Evidence]**: `scripts/build-record-and-replay-baseline-summary.py`、`scripts/check-record-and-replay-baseline-summary.py` 和相关 summary / audit smoke 已把 `realInputActionSmoke.checkedSimpleActionStopCandidate` 与 `checkedDragStopCandidate` 作为 `usableBaseline` 必需 evidence；缺少任一场景候选都会让 release / standalone audit 摘要失败。
- **[Runner Smoke]**: `scripts/test-record-and-replay-baseline-runner-summary-json.py` 的 fake action smoke stub 按 `mixed-action-stop` / `simple-action-stop` / `drag-stop` 分别返回单场景 JSONL，确认 runner 真实传递 `OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTION_SCENARIO`，避免聚合 fixture 掩盖参数漂移。
- **[Docs Sync]**: handoff、replication、architecture、active execution plan 和 quality score 同步说明该证据只证明 OCU candidate 链路可用，不替代 required `simple-action-stop` official successful recording golden；当前 official equivalence 仍应保持 false。
- **[Validation]**: 已跑通 `make record-and-replay-baseline-audit`，落盘摘要显示 `usableBaseline=true`、`standaloneRepoBaselineReady=true`、`checkedSimpleActionStopCandidate=true`、`checkedDragStopCandidate=true`，同时继续报告 required `simple-action-stop` official successful recording 缺口。

### 🔁 Follow-up (2026-06-28, runtime surface evidence split)

- **[Runtime Evidence]**: 生成态 `scripts/verify-runtime.py` 在 `checkedRuntimeContract` 之外新增 `checkedInitializeSurfaceContract`、`checkedToolMetadataContract` 和 `checkedToolInputSchemaNoArguments`，分别证明 initialize surface、三件套完整 tool metadata 和 no-arg input schema。
- **[Baseline Gate]**: shared baseline contract、source scaffold smoke、npm staged scaffold smoke、baseline summary builder 和 artifact audit 都消费这三项 evidence，缺失时 release / standalone audit 会把对应 `standaloneSkillRepo.*` 或 `npmStagedSkillRepo.*` 标为缺口。
- **[Validation]**: 已跑 `python3 scripts/test-record-and-replay-baseline-contract.py`、`python3 scripts/test-record-and-replay-baseline-summary.py`、`python3 scripts/test-record-and-replay-baseline-runner-summary-json.py`、`python3 scripts/test-record-and-replay-skill-repo-scaffold.py` 和 `make record-and-replay-baseline-audit`；刷新后的 baseline artifact 显示 source / npm staged 三项新 evidence 都为 true。未启动官方录制。

### 🔁 Follow-up (2026-06-27, import wrapper placeholder evidence)

- **[Wrapper Guard]**: official capture preflight smoke 现在同时执行单场景 `import-fixture.sh` 的 status response placeholder 和 MCP transcript placeholder 负例，确认正式导入 wrapper 自身会在 ingest 前拒绝未替换输入。
- **[Summary Gate]**: baseline summary 新增 `preflightPipelines.checkedOfficialCapturePacketImportPlaceholderGuard` evidence；缺少该证据时 `usableBaseline=false`，避免只验证 inspect-only wrapper 却漏掉正式导入路径。
- **[Docs Sync]**: architecture、handoff、replication、execution plan 和 quality score 同步说明单场景 inspect/import wrapper 与 packet set 根级 wrapper 都属于 official capture packet baseline 证据。

### 🔁 Follow-up (2026-06-27, capture packet set root preflight)

- **[Wrapper Guard]**: packet set 根级 `inspect-all.sh` / `import-all.sh` 现在会先检查所有场景子目录里的 hosted status response 与 MCP transcript 输入是否仍带 `_placeholder=true`，任一场景未替换就直接退出，不会先执行前置场景的子 wrapper。
- **[Smoke]**: official capture preflight smoke 会把第一个场景输入替换成非占位 JSON、保留后续场景占位，再运行根级 `import-all.sh`，确认它在执行 `simple-action-stop` 子 wrapper 前就因后续 `keyboard-input-stop` 占位输入失败。
- **[Summary Gate]**: baseline summary 新增 `checkedOfficialCapturePacketSetRootPreflightPlaceholderGuard` evidence；该字段缺失或为 false 时，`usableBaseline=false` 并在 `missingUsableBaselineEvidence` 中报告 `preflightPipelines.checkedOfficialCapturePacketSetRootPreflightPlaceholderGuard`。
- **[Docs Sync]**: architecture、handoff、replication、official capture guide、execution plan 和 quality score 同步说明根级批量 wrapper 的 preflight-all 语义，避免后续把它误解为只传播子 wrapper 的 placeholder guard。

### 🔁 Follow-up (2026-06-27, baseline runner summary artifact smoke)

- **[Runner Smoke]**: 新增 `scripts/test-record-and-replay-baseline-runner-summary-json.py`，用临时 fake repo 和 stub evidence 运行真实 `run-record-and-replay-baseline-smoke.sh --summary-json` shell 路径，避免完整桌面 baseline 才能发现 artifact 输出回归。
- **[Artifact Contract]**: 测试确认 `--summary-json` 写出的 JSON 与 stdout 中的最终机器摘要一致，也确认默认模式缺 official golden 时仍返回 0 且 `officialGoldenRequirementSatisfied=true`。
- **[Strict Exit]**: 同一测试打开 `--require-official-golden`，确认缺 required `simple-action-stop` official successful recording fixture 时会写出失败摘要、保留非零退出码，并在 stderr 中暴露 missing scenario。
- **[CI Sync]**: 默认 `scripts/ci.sh` 接入该 runner smoke；`docs/CICD.md`、handoff 和 quality score 同步记录这条 release / standalone audit evidence。

### 🔁 Follow-up (2026-06-27, baseline summary artifact audit)

- **[Audit CLI]**: 新增 `scripts/check-record-and-replay-baseline-summary.py`，直接消费已落盘的 baseline summary JSON，不重跑完整桌面 smoke。
- **[Default Policy]**: 默认审计要求 `usableBaseline`、`standaloneRepoBaselineReady`、official non-recording baseline 和 raw timeout boundary 成立；允许缺 official successful recording golden，但要求 `officialSuccessfulRecordingEquivalenceReady=false`，避免把可拆 standalone baseline 误读成官方事件 schema 等价。
- **[Strict Policy]**: `--require-official-golden` 审计要求 summary 本身处于 strict mode，并要求 golden gate、required scenario gaps、coverage errors 和 `officialSuccessfulRecordingEquivalenceReady` 全部满足。
- **[Runner Integration]**: `scripts/run-record-and-replay-baseline-smoke.sh` 现在生成 summary 后会自动审计同一份摘要；audit 输出走 stderr，stdout 和 `--summary-json` 文件仍保持最终 summary JSON。
- **[Smoke]**: 新增 `scripts/test-record-and-replay-baseline-summary-audit.py` 和 `make record-and-replay-baseline-summary-audit-smoke`，覆盖默认缺 golden 可过、严格缺 golden 必 fail、strict covered 通过、inconsistent equivalence 失败和 incomplete baseline 失败，并接入默认 CI；runner summary-json smoke 同步确认 runner 会调用 audit。

### 🔁 Follow-up (2026-06-27, baseline summary top-level audit)

- **[Audit Invariant]**: `scripts/check-record-and-replay-baseline-summary.py` 现在不仅审计 `status.*`，也要求顶层 `baseline=record-and-replay`，并要求顶层 `ok` 与 `status.usableBaseline && status.officialGoldenRequirementSatisfied` 一致。
- **[Smoke]**: `scripts/test-record-and-replay-baseline-summary-audit.py` 新增顶层 `ok` 被篡改和 baseline 名称被篡改两个负例，避免 release / standalone audit 阶段误消费非本 baseline 或状态不一致的 summary artifact。
- **[Docs Sync]**: architecture、handoff、replication、CICD、execution plan 和 quality score 同步记录顶层 summary 不变量；这不改变当前缺 official successful recording golden 时 `officialSuccessfulRecordingEquivalenceReady=false` 的边界。

### 🔁 Follow-up (2026-06-27, scenario default catalog source)

- **[Default Source]**: official capture preflight、OCU candidate pairing preflight、official hosted ingest、OCU candidate ingest、official fixture coverage report 和 official fixture set gate 的默认 required scenario / help 文案统一从 `scripts/record_and_replay_scenarios.py` 派生。
- **[Drift Guard]**: 相关 preflight / ingest 测试现在覆盖无 `--scenario` 时使用 `DEFAULT_REQUIRED_SCENARIOS[0]`，避免 required 场景清单后续变化时 CLI 默认值和采集/导入链路继续写死旧场景。
- **[Docs Sync]**: official golden capture guide 与 quality score 同步记录这条 catalog-first 约束；当前 official successful recording golden 仍未入库，官方事件 schema 等价状态不变。

### 🔁 Follow-up (2026-06-27, wait notify callback failure evidence)

- **[Standalone Contract]**: 生成态 `record-and-replay-skill-repo.json` 的 `extensionLayer.waitNotify` 新增 `callbackFailureMakesCliFail=true`，把失败 callback 会让 CLI 非零退出的语义写成机器可读 contract。
- **[Smoke Evidence]**: 生成态 `scripts/wait-notify-contract-smoke.py` 现在输出 `checkedNotifyCallbackFailureExit` 和 `checkedNotifyCallbackFailureReason`；源码 standalone smoke 与 npm staged smoke 都要求这些字段为 true。
- **[Baseline Gate]**: `scripts/build-record-and-replay-baseline-summary.py` 把 standalone / npm staged 的 callback failure evidence 纳入 `usableBaseline` 必需项；baseline summary smoke 新增缺失负例，避免独立 repo 只验证 callback skipped，却漏掉 callback 真实失败时的通知和退出码合同。
- **[Docs Sync]**: architecture、handoff、replication、CICD、execution plan 和 quality score 同步记录该 wait/notify 扩展边界；官方兼容 MCP surface 仍保持三件套无参数。

### 🔁 Follow-up (2026-06-27, wait notify callback timeout evidence)

- **[Standalone Contract]**: 生成态 `record-and-replay-skill-repo.json` 的 `extensionLayer.waitNotify` 新增 `callbackTimeoutMakesCliFail=true`，把 notify callback 超时也会让 CLI 非零退出的语义写成机器可读 contract。
- **[Smoke Evidence]**: 生成态 `scripts/wait-notify-contract-smoke.py` 现在用合成 completed session 运行 sleep callback，并要求 `notification.reason=timeout`、`notification.timedOut=true` 且 CLI 非零；源码 standalone smoke 与 npm staged smoke 都消费 `checkedNotifyCallbackTimeoutFailureExit` 和 `checkedNotifyCallbackTimeoutReason`。
- **[Baseline Gate]**: `scripts/build-record-and-replay-baseline-summary.py` 把 standalone / npm staged 的 callback timeout evidence 纳入 `usableBaseline` 必需项；baseline summary smoke 新增缺失负例，避免独立 repo 只验证非零退出而漏掉 callback 超时失败路径。
- **[Docs Sync]**: architecture、handoff、replication、CICD、execution plan 和 quality score 同步记录非零退出与超时两类 wait/notify callback 失败都属于 OCU 扩展层，不进入官方三件套 MCP surface。

### 🔁 Follow-up (2026-06-27, standalone lifecycle semantic evidence)

- **[Baseline Gate]**: `scripts/build-record-and-replay-baseline-summary.py` 现在把 standalone lifecycle smoke 的 `checkedOneActive`、`checkedIdempotentStop` 和 `checkedFinalStatus` 映射成 `checkedLifecycleOneActive`、`checkedLifecycleIdempotentStop` 和 `checkedLifecycleFinalStatus`，并纳入 `usableBaseline` 必需项。
- **[Runner Gate]**: `scripts/run-record-and-replay-baseline-smoke.sh` 解析 standalone smoke JSON 时也要求这三个字段为 true，避免完整 opt-in baseline 只确认 lifecycle smoke 退出成功。
- **[Smoke Evidence]**: baseline summary smoke 新增缺失负例，确认 one-active、stop 幂等或 completed final status 任一语义缺失时都会进入 `missingUsableBaselineEvidence`。
- **[Docs Sync]**: handoff、replication、execution plan 和 quality score 同步说明 npm staged 默认自检仍不启动真实录制，源码 standalone baseline 会额外消费可选 lifecycle smoke 的具体语义 evidence。

### 🔁 Follow-up (2026-06-27, standalone recording-to-skill concrete evidence)

- **[Baseline Gate]**: baseline summary 现在把 source standalone `recording-to-skill` smoke 的 `checkedStrictValidation`、`checkedEventsOnlyValidation`、`checkedScaffoldSkill` 和 `checkedSkillCreatorHandoff` 纳入 `usableBaseline` 必需项。
- **[Runner Gate]**: `scripts/run-record-and-replay-baseline-smoke.sh` 解析 standalone smoke JSON 时提前要求这些字段为 true，避免最终聚合前输入证据已经不完整。
- **[Smoke Evidence]**: baseline summary smoke 新增缺失负例，确认完整 OCU session strict gate、events-only gate、scaffold-skill 正路径或 skill-creator handoff 任一缺失时都会进入 `missingUsableBaselineEvidence`。
- **[Docs Sync]**: handoff、replication、execution plan 和 quality score 同步说明 source standalone baseline 不只消费 recording-to-skill 总开关，还消费具体 validation/scaffold/handoff 子路径证据。

### 🔁 Follow-up (2026-06-27, npm staged recording-to-skill concrete evidence)

- **[NPM Smoke]**: `scripts/test-npm-record-and-replay-skill-repo-scaffold.mjs` 现在从安装态 launcher 生成 repo 的 `check.sh` 输出中断言 `checkedStrictValidation`、`checkedEventsOnlyValidation` 和 `checkedScaffoldSkill`，并把这些字段写入 npm staged smoke 最终 JSON。
- **[Baseline Gate]**: baseline summary 与 runner 都把 npm staged strict validation、events-only validation 和 scaffold-skill 正路径 evidence 纳入 `usableBaseline` 必需项。
- **[Smoke Evidence]**: baseline summary smoke 新增 npm staged 缺失负例，确认安装态 concrete evidence 缺失会报告到 `npmStagedSkillRepo.*`。
- **[Docs Sync]**: handoff、replication、execution plan 和 quality score 同步说明 recording-to-skill concrete evidence 同时适用于 source standalone 与 npm staged 路径。

### 🔁 Follow-up (2026-06-27, real input action concrete evidence)

- **[Action Smoke]**: `scripts/run-event-stream-smoke-tests.sh` 的真实输入 action 模式现在把已内部断言的 MCP response shapes、skill readiness、`skill-creator` finalization handoff 和路径脱敏结果写成机器可读 JSON 字段。
- **[Baseline Gate]**: baseline summary 与 runner 都把 `checkedMcpResponseShapesCaptured`、`checkedSkillReadinessCanCreateDraft`、`checkedSkillCreatorFinalizationHandoff` 和 `checkedGeneratedSkillPathRedaction` 纳入 `realInputActionSmoke` 必需项。
- **[Smoke Evidence]**: baseline summary smoke 新增 action concrete evidence 缺失负例，确认缺失时会报告到 `realInputActionSmoke.*`。
- **[Docs Sync]**: handoff、replication、execution plan 和 quality score 同步说明真实输入录制到 skill 的 baseline 证据不再只依赖 `skillPath` / `mcpTranscriptPath` 存在。

### 🔁 Follow-up (2026-06-27, baseline audit make targets)

- **[Make Targets]**: 新增 `make record-and-replay-baseline-audit` 和 `make record-and-replay-official-golden-gate-audit`，分别包装默认 baseline 与 strict official golden gate 的 `--summary-json` 路径。
- **[Artifact Path]**: 两个 target 默认把 summary artifact 写到 `dist/record-and-replay-baseline-summary.json`，可用 `RNR_BASELINE_SUMMARY_JSON=<path>` 覆盖，方便 release / standalone audit 留存同一份机器 evidence。
- **[Exit Semantics]**: 默认 audit 仍保持缺 official successful recording golden 时可通过的 baseline 语义；strict audit 仍保持缺 required official golden 时非零退出但写出失败摘要的 gate 语义。
- **[Docs Sync]**: official capture guide、handoff、replication、execution plan 和 quality score 同步记录 Make audit 入口，避免后续使用方手写 runner 参数。

### 🔁 Follow-up (2026-06-27, baseline audit target smoke)

- **[Smoke]**: 新增 `scripts/test-record-and-replay-baseline-audit-make-targets.py` 和 `make record-and-replay-baseline-audit-targets-smoke`，用 `make -n` 验证两个 audit Make target 的命令展开。
- **[Coverage]**: smoke 覆盖默认 summary 路径、自定义 `RNR_BASELINE_SUMMARY_JSON` 路径和 strict target 的 `--require-official-golden` 参数，避免 Make 包装入口漂移。
- **[CI Sync]**: 默认 `scripts/ci.sh` 接入该 dry-run smoke；它不启动完整 baseline、不触发官方录制，只守住 release / standalone audit 的短命令入口。
- **[Docs Sync]**: CICD、handoff、replication、execution plan 和 quality score 同步说明该 smoke 的边界。

### 🔁 Follow-up (2026-06-27, baseline audit target summary evidence)

- **[Runner]**: `scripts/run-record-and-replay-baseline-smoke.sh` 现在也会运行 `scripts/test-record-and-replay-baseline-audit-make-targets.py`，并把输出 JSON 传给 baseline summary builder。
- **[Summary Gate]**: `scripts/build-record-and-replay-baseline-summary.py` 新增 `--baseline-audit-targets-json` 输入，并在 `evidence.preflightPipelines` 写入 `checkedBaselineAuditMakeTargets`、`checkedBaselineAuditDefaultSummaryPath`、`checkedBaselineAuditCustomSummaryPath` 和 `checkedBaselineAuditStrictOfficialGoldenTarget`。
- **[Usable Baseline]**: 上述四项现在属于 `usableBaseline` 必需 evidence；如果 release / standalone audit 的 Make wrapper 或 `--summary-json` / `--require-official-golden` 参数漂移，完整 baseline summary 会失败并报告对应 `missingUsableBaselineEvidence`。
- **[Tests]**: 更新 summary smoke 和 runner summary-json stub smoke，覆盖新增参数、正向 evidence 和 audit target evidence 缺失负例。

### 🔁 Follow-up (2026-06-27, baseline audit artifact evidence)

- **[Audit CLI]**: `scripts/check-record-and-replay-baseline-summary.py` 现在会直接审计落盘 summary 中的 baseline audit Make target evidence，而不是只相信 `status.usableBaseline`。
- **[Checks]**: 默认 artifact audit 新增 `checkedBaselineAuditMakeTargetsEvidence`、`checkedBaselineAuditDefaultSummaryPathEvidence`、`checkedBaselineAuditCustomSummaryPathEvidence` 和 `checkedBaselineAuditStrictOfficialGoldenTargetEvidence`。
- **[Smoke]**: `scripts/test-record-and-replay-baseline-summary-audit.py` 新增负例：即使 summary 的 status 仍声称 usable，只要 `evidence.preflightPipelines` 里的 audit target evidence 被改成 false，artifact audit 也会失败。
- **[Docs Sync]**: architecture、handoff、replication、CICD、execution plan 和 quality score 同步说明 release / standalone summary 复审会直接检查该 evidence。

### 🔁 Follow-up (2026-06-27, official boundary artifact evidence)

- **[Audit CLI]**: `scripts/check-record-and-replay-baseline-summary.py` 现在也会直接审计落盘 summary 中的 official boundary evidence，而不是只相信 `status.officialNonRecordingBaselineVerified` 或 `status.officialRawStartTimeoutBoundaryVerified`。
- **[Checks]**: 默认 artifact audit 新增 official surface local/bundled evidence、official no-active status/stop shape 与 no-session-files evidence，以及 raw start/status/stop timeout、无 recording paths、raw surface 和 fixture redaction evidence。
- **[Smoke]**: `scripts/test-record-and-replay-baseline-summary-audit.py` 新增负例：即使 summary 的 status 仍声称 usable，只要 `evidence.officialSurfaceCompare`、`evidence.officialNoActiveResponse` 或 `evidence.officialRawStartTimeout` 被改成 false，artifact audit 也会失败。
- **[Docs Sync]**: architecture、handoff、replication、CICD、execution plan 和 quality score 同步说明 release / standalone summary 复审会直接检查官方 non-recording / raw-timeout 边界 evidence。

### 🔁 Follow-up (2026-06-27, capture packet input verification)

- **[Packet Wrapper]**: official capture packet 现在生成 `verify-inputs.sh`，在 inspect/import 前单独检查 hosted status response 和 MCP transcript 输入是否存在、JSON 可解析且不再是 `_placeholder=true`。
- **[Packet Set]**: recommended packet set 现在生成根级 `verify-all.sh`，逐个运行子 packet 的输入校验；根级 `inspect-all.sh` / `import-all.sh` 仍保留先全量 placeholder preflight、再执行子 wrapper 的半批次导入防护；根级 `ingest-ocu-candidates.sh` 负责批量运行可自动生成 OCU candidate 的子场景。
- **[Baseline Evidence]**: `scripts/build-record-and-replay-baseline-summary.py` 和 runner 现在消费 `checkedCapturePacketVerifyInputs` / `checkedCapturePacketSetVerifyAll`，缺失时 `usableBaseline=false` 并进入 `missingUsableBaselineEvidence`。
- **[Smoke]**: `scripts/test-record-and-replay-official-golden-capture-preflight.py` 覆盖单场景 `verify-inputs.sh` 的 status/transcript 占位失败与替换后成功，也覆盖 packet set `verify-all.sh`；`scripts/test-record-and-replay-baseline-summary.py` 新增这两项 evidence 缺失负例。
- **[Docs Sync]**: official capture guide、handoff、replication、architecture、CICD、execution plan 和 quality score 同步记录 verify wrapper 属于采集包输入合同，不启动官方录制，也不替代 inspect-only / readiness gate。

### 🔁 Follow-up (2026-06-27, capture packet nextActions verify step)

- **[Summary Guidance]**: `scripts/build-record-and-replay-baseline-summary.py` 的 official capture `nextActions` 现在会显式列出 `verify-inputs.sh` 和 `verify-all.sh`，避免调用方只按机器命令跑 inspect/import 而跳过输入校验。
- **[Preflight Guidance]**: `scripts/prepare-record-and-replay-official-golden-capture.py --capture-packet-dir` 的 `nextActions` 文案现在也指向 `capturePacket.verifyInputsShell`，和生成的 packet manifest 保持一致。
- **[Smoke]**: baseline summary smoke 断言 required / recommended capture commands 包含 verify 与 OCU candidate ingest 步骤，并实际执行 packet Make 命令确认 `verify-inputs.sh`、`verify-all.sh` 与 `ingest-ocu-candidates.sh` 都被生成；official capture preflight smoke 断言 packet JSON 暴露 `verifyInputsShell`。
- **[Docs Sync]**: handoff、replication、execution plan 和 quality score 同步说明 baseline summary 的机器下一步是 verify → inspect → import。

### 🔁 Follow-up (2026-06-27, full baseline revalidation)

- **[Baseline Smoke]**: 复跑 `make record-and-replay-baseline-smoke` 通过，完整覆盖默认 event-stream matrix、截图上下文 smoke、真实输入 action smoke、官方 1.0.857 non-recording surface 对比、official no-active response、raw start/status/stop timeout fixture、official fixture set gate、fixture ingest、OCU candidate ingest、capture/pairing preflight、source standalone repo smoke 和 npm staged standalone repo smoke。
- **[Status Evidence]**: 最终摘要保持 `status.usableBaseline=true`、`status.standaloneRepoBaselineReady=true`、`status.officialNonRecordingBaselineVerified=true` 和 `status.officialRawStartTimeoutBoundaryVerified=true`。
- **[Golden Gap]**: 同一摘要仍保持 `status.officialSuccessfulRecordingGoldenComplete=false`、`status.officialSuccessfulRecordingEquivalenceReady=false`，并报告缺少 required `simple-action-stop` 以及 recommended `simple-action-stop` / `keyboard-input-stop` / `drag-stop` / `cancel` / `timeout` official successful recording fixtures。
- **[Boundary]**: 本次没有启动官方 successful recording；官方 raw start/status/stop 边界仍只证明宿主外 timeout 与 non-recording surface，不替代 Codex-hosted successful recording golden。

### 🔁 Follow-up (2026-06-27, strict gate audit env isolation)

- **[Bug]**: 运行 `RNR_BASELINE_SUMMARY_JSON=/tmp/ocu-rnr-official-golden-summary.json make record-and-replay-official-golden-gate-audit` 时，完整 baseline 前置检查通过，但内嵌的 audit Make target dry-run smoke 误继承外层 `RNR_BASELINE_SUMMARY_JSON`，导致“默认 summary 路径”断言失败。
- **[Fix]**: `scripts/test-record-and-replay-baseline-audit-make-targets.py` 现在在调用 `make -n` 前显式移除继承的 `RNR_BASELINE_SUMMARY_JSON`；自定义 summary 路径仍通过 make 命令参数覆盖。
- **[CI Coverage]**: `scripts/ci.sh` 现在带外层 `RNR_BASELINE_SUMMARY_JSON=/tmp/ocu-rnr-ci-outer-summary.json` 运行同一 dry-run smoke，确保环境隔离回归进入默认 CI，而不只依赖手工命令。
- **[Verification]**: `RNR_BASELINE_SUMMARY_JSON=/tmp/outer-should-not-affect-default.json make record-and-replay-baseline-audit-targets-smoke` 通过，证明默认路径检查不再受外层环境污染。
- **[CI]**: `./scripts/ci.sh` 已复跑通过，覆盖文档/仓库卫生、脚本语法、skill 打包、Record & Replay 默认 smoke、Swift 单测、默认 event-stream matrix 和 Windows / Linux Go test；新的外层环境变量 smoke 已进入这条默认路径。
- **[Strict Gate Evidence]**: 重跑 strict audit 后，所有 baseline 子证据与 standalone / npm staged smoke 都通过，最终只因缺 required `simple-action-stop` official successful recording fixture 而非零退出，并写出 strict summary artifact；artifact 中 `usableBaseline=true`、`standaloneRepoBaselineReady=true`、`officialGoldenRequirementSatisfied=false`、`officialSuccessfulRecordingEquivalenceReady=false`。

### 🔁 Follow-up (2026-06-27, capture packet repo-root handoff)

- **[Packet README]**: official capture packet 生成的 README 现在说明 wrapper 会写入创建 packet 时的仓库路径，并支持用 `REPO_ROOT=/path/to/repo` 覆盖，方便把 packet 目录交给另一个 checkout 使用。
- **[Fix]**: 删除旧文案里“通过 `git rev-parse` 推断仓库”的说法；真实 wrapper 使用的是 embedded `default_repo_root`，旧说法会误导后续 official hosted JSON 采集交接。
- **[Smoke]**: `scripts/test-record-and-replay-official-golden-capture-preflight.py` 已断言 packet README 包含 embedded repo path / `REPO_ROOT` 覆盖说明，且不包含 `git rev-parse`。

### 🔁 Follow-up (2026-06-27, no-transcript capture packet set)

- **[Bug]**: 单场景 capture packet 支持 `--no-include-transcript`，但 recommended packet set 的根级 `inspect-all.sh` / `import-all.sh` 仍无条件检查每个子目录的 `inputs/mcp-transcript.json`，会让无 transcript 采集包在批量模式下误失败。
- **[Fix]**: packet set root wrapper 现在按 `include_transcript` 配置生成 placeholder preflight；默认路径仍检查 status + transcript，`--no-include-transcript` 路径只检查 status response。
- **[Evidence]**: official capture preflight smoke 输出 `checkedCapturePacketSetNoTranscript=true`，baseline summary 将其映射为 `preflightPipelines.checkedOfficialCapturePacketSetNoTranscript` 并纳入 `usableBaseline` 必需 evidence；summary smoke 新增该 evidence 缺失负例。

### 🔁 Follow-up (2026-06-27, capture packet transcript manifest)

- **[Manifest Contract]**: 单场景 `capturePacket`、根级 `capturePacketSet` 和 `capture-packets.json` 现在都会写入 `includeTranscript` / `requiresMcpTranscriptInput`，并在单场景 packet 中写入 status response 与 MCP transcript input path，方便后续采集包消费方直接从 JSON 判断是否需要 transcript 输入。
- **[No Transcript Mode]**: 使用 `--no-include-transcript` 生成 recommended packet set 时，根级 manifest 与每个子 packet 的 transcript requirement 字段都会是 `false`，`mcpTranscriptInputPath=null`，与 wrapper 不检查 `inputs/mcp-transcript.json` 的行为一致。
- **[Baseline Evidence]**: baseline summary 现在消费 `preflightPipelines.checkedOfficialCapturePacketTranscriptManifest`，并在 summary smoke 中覆盖缺失负例；manifest transcript requirement 漂移会让 `usableBaseline=false`。
- **[Docs Sync]**: official capture guide、handoff、replication、execution plan 和 quality score 同步说明 transcript requirement 是机器可读交接合同，不需要解析 README 或猜测文件存在性。
- **[Smoke]**: official capture preflight smoke 已覆盖默认 `true`、无 transcript `false`、README 文案和无 transcript child packet manifest 字段。

### 🔁 Follow-up (2026-06-27, single no-transcript capture packet)

- **[Packet Smoke]**: official capture preflight smoke 现在也生成单场景 `--no-include-transcript` packet，确认只创建 `inputs/event_stream_stop-response.json`，不创建 `inputs/mcp-transcript.json`，wrapper 不带 `--mcp-transcript`，`verify-inputs.sh` 替换 status response 后即可通过。
- **[Baseline Evidence]**: baseline summary 新增 `preflightPipelines.checkedOfficialCapturePacketNoTranscript`，并在 summary smoke 中覆盖缺失负例；单场景 no-transcript packet 漂移会让 `usableBaseline=false`。
- **[Why]**: required `simple-action-stop` 最可能先用单场景 capture packet 采集；如果官方 hosted transcript 暂时不可得，单场景无 transcript 交接也必须是可复跑、可验证的 baseline 合同。

### 🔁 Follow-up (2026-06-27, preflight evidence artifact audit)

- **[Audit CLI]**: `scripts/check-record-and-replay-baseline-summary.py` 现在会直接审计 `evidence.preflightPipelines` 里的 official capture packet、no-transcript packet、packet set、transcript manifest、placeholder guard、verify-all、official capture failure path 和 OCU pairing preflight evidence。
- **[Smoke]**: `scripts/test-record-and-replay-baseline-summary-audit.py` 新增 preflight evidence 篡改负例；即使 summary 的 status 仍声称 usable，只要 official capture / OCU pairing preflight evidence 被改成 false，artifact audit 也会失败。
- **[Docs Sync]**: architecture、handoff、replication、CICD、execution plan 和 quality score 同步说明 release / standalone audit 会直接检查 preflight evidence，不只依赖 `status.usableBaseline` 的间接结果。

### 🔁 Follow-up (2026-06-27, usable baseline direct artifact audit)

- **[Audit CLI]**: `scripts/check-record-and-replay-baseline-summary.py` 现在会直接审计所有 `usableBaseline` 子证据，包括 event-stream matrix、截图上下文、真实输入 action smoke、official fixture set gate、fixture ingest pipeline、source standalone repo 和 npm staged repo evidence。
- **[Smoke]**: `scripts/test-record-and-replay-baseline-summary-audit.py` 新增 usable baseline direct evidence 篡改负例；即使 summary 的 status 仍声称 usable，只要 action / fixture ingest / standalone / npm 等 evidence 被改成 false，artifact audit 也会失败。
- **[Docs Sync]**: architecture、handoff、replication、CICD、execution plan 和 quality score 同步说明 release / standalone audit 复审的是完整 usable baseline evidence，而不是只审 official boundary、preflight 或 Make target evidence。

### 🔁 Follow-up (2026-06-27, nextActions command artifact audit)

- **[Audit CLI]**: `scripts/check-record-and-replay-baseline-summary.py` 现在会审计落盘 summary 的 `nextActions.commands`，不再只检查 action kind 是否存在。
- **[Checks]**: 缺 required official golden 时，artifact audit 要求保留 `make record-and-replay-official-golden-capture-packet`、`verify-inputs.sh`、`inspect-only.sh`、`import-fixture.sh` 和 strict gate；缺 recommended golden 时要求保留 packet set Make、`verify-all.sh`、`inspect-all.sh`、`import-all.sh` 和 `ingest-ocu-candidates.sh`；standalone baseline ready 时要求保留 scaffold、生成 repo `scripts/check.sh` 和 optional lifecycle smoke。
- **[Smoke]**: `scripts/test-record-and-replay-baseline-summary-audit.py` 新增 `nextActions` command 篡改负例，确认删除 packet Make、verify-all 或 generated repo check 命令都会让 artifact audit 失败。
- **[Docs Sync]**: architecture、handoff、replication、CICD、execution plan 和 quality score 同步说明 release / standalone audit 会验证下一步命令 handoff，不只验证 status / evidence。

### 🔁 Follow-up (2026-06-27, derived status artifact audit)

- **[Audit CLI]**: `scripts/check-record-and-replay-baseline-summary.py` 现在会审计 baseline summary 的派生状态不变量。
- **[Checks]**: `requiresOfficialGoldenCapture` 必须和 official golden complete 互为反向；`officialSuccessfulRecordingEquivalenceReady` 必须等于 usable baseline + official golden complete；`standaloneRepoBaselineReady=true` 不能出现在 `usableBaseline=false` 的 artifact 中；official golden complete 不能同时保留 required scenario gaps、not-ready gaps 或 coverage errors。
- **[Smoke]**: `scripts/test-record-and-replay-baseline-summary-audit.py` 新增派生状态篡改负例和 golden complete 仍带 gaps 的负例，确认这些状态组合不一致会让 artifact audit 失败。
- **[Docs Sync]**: architecture、handoff、replication、CICD、execution plan 和 quality score 同步说明 release / standalone audit 会验证派生状态语义，不只验证 evidence 和 nextActions。

### 🔁 Follow-up (2026-06-27, baseline implementation context)

- **[Baseline Scope]**: handoff 新增 baseline 实施基准，明确第一波目标是“能用且不误报官方等价”：默认 baseline 可以证明 OCU / standalone 可用，但缺 official successful recording golden 时仍必须保持 `officialSuccessfulRecordingEquivalenceReady=false`。
- **[Contract Sync]**: replication 文档新增 baseline 版本定义，把官方三件套、session 文件、基础事件、AX / screenshot baseline、OCU 自有控制条、wait/notify、validation、summary、skill scaffold 和 standalone repo scaffold 归为第一波必须具备能力。
- **[Plan Sync]**: active execution plan 补充当前 baseline 推进基准，要求拆独立 repo 前保持默认自检不启动真实录制，真实 lifecycle smoke 继续 opt-in，并要求任何官方等价声明先有 official fixture 与 OCU candidate 对比证据。

### 🔁 Follow-up (2026-06-27, declared checks artifact audit)

- **[Audit CLI]**: `scripts/check-record-and-replay-baseline-summary.py` 现在要求顶层 `checks` 声明包含所有必需 baseline smoke / compare / preflight / standalone 检查。
- **[Smoke]**: `scripts/test-record-and-replay-baseline-summary-audit.py` 新增删除 `checks` 条目的负例，确认 otherwise valid 的 summary artifact 也会因为检查声明漂移而失败。
- **[Docs Sync]**: architecture、handoff、replication、CICD、execution plan 和 quality score 同步说明 release / standalone audit 会验证顶层检查清单，不只验证 status、evidence、派生状态和 `nextActions`。

### 🔁 Follow-up (2026-06-27, declared checks audit diagnostics)

- **[Audit CLI]**: 顶层 `checks` 审计失败时，`scripts/check-record-and-replay-baseline-summary.py` 会在 `declaredChecks.missingRequired` 输出缺失的具体 check 名称。
- **[Smoke]**: declared-checks 篡改负例现在断言缺失清单包含被删除的 `official-no-active-response-compare` 与 `npm-staged-skill-repo-smoke`，让 release / standalone audit 失败信息可直接定位缺口。
- **[Docs Sync]**: handoff、CICD 和 quality score 同步说明 audit JSON 会携带 missing-required diagnostics。

### 🔁 Follow-up (2026-06-27, builder/audit checks consistency)

- **[Smoke]**: `scripts/test-record-and-replay-baseline-summary-audit.py` 现在会导入 `scripts/check-record-and-replay-baseline-summary.py`，并断言 builder 产出的顶层 `checks` 与 audit 的 `REQUIRED_BASELINE_CHECKS` 完全一致。
- **[Why]**: 这条检查用于防止 baseline 检查清单只在生成器或审计器一侧更新，导致 release / standalone audit 消费到看似完整但实际口径漂移的 summary artifact。
- **[Docs Sync]**: handoff、replication、CICD、execution plan 和 quality score 已同步记录 builder/audit required checks 一致性约束。

### 🔁 Follow-up (2026-06-27, canonical declared checks audit)

- **[Audit CLI]**: 顶层 `checks` 现在不仅要包含全部 required baseline checks，还不能带未知或重复 check 名称；失败时会分别通过 `declaredChecks.missingRequired`、`declaredChecks.unknown` 和 `declaredChecks.duplicates` 输出诊断。
- **[Smoke]**: `scripts/test-record-and-replay-baseline-summary-audit.py` 新增 unknown / duplicate check 篡改负例，确认追加 `obsolete-record-and-replay-smoke` 或重复 `event-stream-smoke-matrix` 都会让 artifact audit 失败。
- **[Docs Sync]**: handoff、replication、CICD、execution plan 和 quality score 同步说明顶层 `checks` 是 canonical set，不是可扩展备注列表。

### 🔁 Follow-up (2026-06-27, shared declared checks contract)

- **[Contract]**: 新增 `scripts/record_and_replay_baseline_contract.py`，把 baseline summary 顶层 `checks` 的 canonical list 抽成 builder 与 audit 共用的唯一来源。
- **[Builder / Audit]**: `scripts/build-record-and-replay-baseline-summary.py` 按 shared tuple 顺序输出 `checks`，`scripts/check-record-and-replay-baseline-summary.py` 按同一 tuple/set 复审 missing / unknown / duplicate 声明。
- **[Smoke]**: `scripts/test-record-and-replay-baseline-summary-audit.py` 断言 builder 输出顺序等于 shared contract，并继续覆盖 missing / unknown / duplicate 篡改负例，避免后续只更新生成器或审计器一侧。
- **[Runner Smoke]**: `scripts/test-record-and-replay-baseline-runner-summary-json.py` 的 fake repo 会同步复制 shared contract 文件，确保 runner 级 `--summary-json` stub 测试覆盖真实 builder/audit 依赖，而不是只复制入口脚本。
- **[Docs Sync]**: handoff、replication、CICD、execution plan 和 quality score 同步说明 shared contract 是顶层 `checks` 的唯一源码。

### 🔁 Follow-up (2026-06-27, generated README scenario list evidence)

- **[Scaffold]**: standalone thin skill repo README 的 required / recommended official successful recording scenario 清单现在从 `scripts/record_and_replay_scenarios.py` 生成，不再手写 `simple-action-stop` 等列表。
- **[Smoke Evidence]**: source scaffold smoke 和 npm staged scaffold smoke 都新增 `checkedGeneratedReadmeScenarioList=true`，并断言 README 文案与 scenario catalog 当前清单一致。
- **[Baseline Gate]**: `scripts/build-record-and-replay-baseline-summary.py` 把 source / npm staged 的 `checkedGeneratedReadmeScenarioList` 纳入 `usableBaseline` 必需 evidence；summary smoke 增加缺失负例，artifact audit 也会直接复审该 evidence。
- **[Docs Sync]**: replication 和 quality score 同步说明 README handoff 场景清单也受 scenario catalog 与 baseline summary 约束。

### 🔁 Follow-up (2026-06-27, standalone runtime timeout diagnostics)

- **[Runtime Diagnostics]**: 生成态 `scripts/verify-runtime.py` 和可选 `scripts/recording-lifecycle-smoke.py` 的 MCP response timeout 现在会输出 runtime path、`event-stream mcp` command、`open-computer-use --version` 结果和 `OPEN_COMPUTER_USE_CLI` 修复提示，避免旧全局 runtime 或错误 launcher 只报裸 timeout。
- **[Smoke Evidence]**: source scaffold smoke 新增 fake stale runtime 负例，用 `OPEN_COMPUTER_USE_RUNTIME_VERIFY_TIMEOUT_SECONDS=0.2` 快速触发 timeout 并断言错误里包含 fake `0.1.51` 版本和修复提示；npm staged scaffold smoke 静态验证安装态生成物包含同样诊断字段。
- **[Docs Sync]**: architecture、handoff、replication 和 quality score 同步说明该诊断属于 standalone repo runtime contract 的一部分，后续拆独立 repo 时应优先让 `OPEN_COMPUTER_USE_CLI` 指向当前 runtime 再运行自检。

### 🔁 Follow-up (2026-06-27, runtime timeout diagnostics baseline gate)

- **[Baseline Gate]**: `scripts/build-record-and-replay-baseline-summary.py` 现在把 source standalone 与 npm staged 的 `checkedRuntimeTimeoutDiagnostics` 纳入 `usableBaseline` 必需 evidence；完整 baseline runner 也会在聚合 summary 前先断言这两个 smoke 输出该字段。
- **[Artifact Audit]**: `scripts/check-record-and-replay-baseline-summary.py` 会直接复审 `evidence.standaloneSkillRepo.checkedRuntimeTimeoutDiagnostics` 和 `evidence.npmStagedSkillRepo.checkedRuntimeTimeoutDiagnostics`；summary smoke 与 audit smoke 都新增篡改负例。
- **[Docs Sync]**: architecture、handoff、replication 和 quality score 同步说明 release / standalone audit 不只验证 runtime 成功路径，也验证旧 runtime / 错误 launcher 的可诊断失败路径。

### 🔁 Follow-up (2026-06-27, baseline audit with runtime diagnostics evidence)

- **[Full Audit]**: 复跑 `make record-and-replay-baseline-audit` 通过，生成 `dist/record-and-replay-baseline-summary.json`；随后直接运行 `scripts/check-record-and-replay-baseline-summary.py dist/record-and-replay-baseline-summary.json` 复审通过。
- **[Status Evidence]**: 该 artifact 保持 `usableBaseline=true`、`standaloneRepoBaselineReady=true`、source / npm staged `checkedRuntimeTimeoutDiagnostics=true`，同时仍明确 `officialSuccessfulRecordingGoldenComplete=false`、`officialSuccessfulRecordingEquivalenceReady=false`，缺 required `simple-action-stop` official successful recording fixture。
- **[Boundary]**: 本次验证没有启动官方录制；official successful recording schema、AX compact diff 和 screenshot 触发策略仍必须等 Codex-hosted official golden fixture 校准。

### 🔁 Follow-up (2026-06-27, strict gate after runtime diagnostics evidence)

- **[Strict Audit]**: 复跑 `make record-and-replay-official-golden-gate-audit`，命令按预期非零退出并写出 strict `dist/record-and-replay-baseline-summary.json`。
- **[Failure Boundary]**: 落盘摘要显示 `strictOfficialGoldenRequired=true`、`usableBaseline=true`、`standaloneRepoBaselineReady=true`、source / npm staged `checkedRuntimeTimeoutDiagnostics=true`，同时 `officialGoldenRequirementSatisfied=false`、`officialGoldenGatePassed=false`、`officialSuccessfulRecordingEquivalenceReady=false`。
- **[Remaining Gap]**: strict gate 当前只缺 required `simple-action-stop` official successful recording fixture；`notReadyRequiredOfficialSuccessfulRecordingScenarios=[]`、`officialFixtureCoverageErrors=[]`，说明新增 runtime timeout diagnostics gate 没有引入额外失败点。

### 🔁 Follow-up (2026-06-27, npm Python launcher diagnostics gate)

- **[Smoke Evidence]**: npm staged standalone smoke 现在输出 `checkedNpmPythonLauncherDiagnostics=true`，证明安装态 scaffold launcher 在 `PYTHON` 指向不存在的文件或 Python 2 时会返回 command-specific Python 3 诊断和 `PYTHON=/path/to/python3` 修复提示。
- **[Baseline Gate]**: `scripts/build-record-and-replay-baseline-summary.py`、`scripts/run-record-and-replay-baseline-smoke.sh` 和 `scripts/check-record-and-replay-baseline-summary.py` 都消费该 evidence；缺失时 `usableBaseline=false` 并报告 `npmStagedSkillRepo.checkedNpmPythonLauncherDiagnostics`。
- **[Smoke]**: 复跑 `make record-and-replay-baseline-summary-smoke`、`make record-and-replay-baseline-summary-audit-smoke`、`make npm-record-and-replay-skill-repo-smoke` 和 `make record-and-replay-baseline-audit` 通过，确认 summary/audit 负例、安装态输出和完整 baseline artifact 都覆盖这条合同。

### 🔁 Follow-up (2026-06-27, generated README prerequisites evidence)

- **[Generated README]**: standalone thin skill repo 生成态 README 新增 `Prerequisites` 段，明确自检脚本要求 Python 3 可通过 `python3` 访问，并提示 npm launcher 用户可设置 `PYTHON=/path/to/python3`。
- **[Evidence Gate]**: source scaffold smoke 和 npm staged scaffold smoke 都输出 `checkedGeneratedReadmePrerequisites=true`；baseline runner、summary 和 artifact audit 把该字段纳入 `standaloneSkillRepo` / `npmStagedSkillRepo` 必需 evidence。
- **[Docs Sync]**: architecture、handoff、replication、quality score 和 active execution plan 已同步这条独立 repo handoff 约束；它不改变官方三件套 MCP surface，只补齐 standalone repo 用户可见前置条件。

### 🔁 Follow-up (2026-06-27, official capture packet handoff scripts)

- **[Capture Packet]**: 单场景 official capture packet 的 README 和 `capturePacket` JSON 现在显式暴露 `check-fixture-set.sh`、`strict-golden-gate.sh` 和可用时的 `ingest-ocu-candidate.sh`，并返回 `checkFixtureSetShell`、`strictGoldenGateShell`、`ingestOcuCandidateShell` 字段。
- **[Evidence Gate]**: official golden capture preflight smoke 输出 `checkedCapturePacketHandoffScripts=true`；baseline runner、summary 和 artifact audit 通过 `checkedOfficialCapturePacketHandoffScripts` 消费该 evidence。
- **[Why]**: 这条约束确保拿到 Codex-hosted official JSON 后，packet 不只指导 inspect/import，也能继续跑 fixture-set gate、strict official golden gate 和 same-scenario OCU candidate 导入。

### 🔁 Follow-up (2026-06-27, OCU candidate ingest handoff commands)

- **[Candidate Handoff]**: `scripts/ingest-ocu-record-and-replay-candidate.py` 成功导入后会输出 `commands.pairingPreflightShell` 和 `commands.fixtureSetGateShell`，指向 same-scenario pairing preflight 与集合级 official-vs-OCU candidate gate。
- **[Evidence Gate]**: `make event-stream-ocu-candidate-ingest-smoke` 输出 `checkedCandidateIngestHandoffCommands=true`；baseline runner、summary 和 artifact audit 通过 `checkedOcuCandidateIngestHandoffCommands` 消费该 evidence，summary smoke 也新增 `checkedCandidateIngestHandoffCommandsEvidence=true` 和缺失负例。
- **[Why]**: 这让 OCU candidate 采样/导入后的下一步不再依赖人工拼命令；后续 official fixture 入库或 candidate 重采后，可以直接按输出命令进入 readiness/compare 校准。

### 🔁 Follow-up (2026-06-27, capture packet candidate output root)

- **[Bug]**: official capture packet 的 `ingest-ocu-candidate.sh` 会跟随自定义 `--official-root`，但此前没有显式传 `--output-dir`，导致自定义 fixture root 时 OCU candidate 仍可能落回仓库默认 candidate 目录。
- **[Fix]**: `scripts/prepare-record-and-replay-official-golden-capture.py` 生成的 candidate command 现在传入 `--output-dir <fixture-root>/ocu-candidates`，保证 official fixture 与 same-scenario OCU candidate 在同一 fixture root 下配对。
- **[Evidence Gate]**: official capture preflight smoke 输出 `checkedCapturePacketOcuCandidateOutputDir=true`；baseline runner、summary 和 artifact audit 通过 `preflightPipelines.checkedOfficialCapturePacketOcuCandidateOutputDir` 消费该 evidence，summary smoke 与 artifact audit smoke 都覆盖篡改负例。
- **[Docs Sync]**: architecture、official capture guide、replication、execution plan 和 quality score 已同步这条 handoff 约束。

### 🔁 Follow-up (2026-06-27, capture packet set candidate handoff)

- **[Packet Set Handoff]**: recommended official capture packet set 根目录现在生成 `ingest-ocu-candidates.sh`，批量运行存在 `ingest-ocu-candidate.sh` 的子场景，并跳过 keyboard / cancel / timeout 这类不生成 synthetic candidate wrapper 的场景。
- **[Evidence Gate]**: official capture preflight smoke 输出 `checkedCapturePacketSetOcuCandidateHandoff=true`；baseline runner、summary 和 artifact audit 通过 `preflightPipelines.checkedOfficialCapturePacketSetOcuCandidateHandoff` 消费该 evidence，summary smoke 与 artifact audit smoke 都覆盖篡改负例。
- **[Why]**: recommended set 采完官方样本后，不再需要人工逐个进入 simple/drag 子目录查找可用 OCU candidate wrapper，后续官方/OCU 配对校准入口更稳定。
- **[Docs Sync]**: architecture、official capture guide、replication、execution plan 和 quality score 已同步这条批量 handoff 约束。

### 🔁 Follow-up (2026-06-27, recommended next action OCU candidate handoff)

- **[Summary Guidance]**: baseline summary 的 `capture-recommended-official-golden-set` `nextActions` 现在显式包含 `cd <packet-dir> && ./ingest-ocu-candidates.sh`，与 recommended packet set 实际生成的根级 helper 保持一致。
- **[Artifact Audit]**: `scripts/check-record-and-replay-baseline-summary.py` 新增 `checkedRecommendedGoldenNextActionIngestOcuCandidatesStep`，release / standalone audit 会拒绝缺少该 OCU candidate handoff 命令的 summary artifact。
- **[Smoke]**: summary smoke 断言推荐分支命令列表和临时生成的 packet set 都包含 `ingest-ocu-candidates.sh`；summary audit smoke 会篡改删除该命令并要求 audit 失败。

### 🔁 Follow-up (2026-06-27, handoff short entry sync)

- **[Docs Sync]**: `docs/design-docs/record-and-replay-handoff.md` 现在也把 recommended packet set 的根级 `ingest-ocu-candidates.sh` 写入采集步骤、常用命令和 artifact audit 说明。
- **[Why]**: 后续推进通常先读 handoff 短入口；如果这里仍只写 `verify-all.sh` / `inspect-all.sh` / `import-all.sh`，就会和 baseline summary / artifact audit 的真实合同漂移。

### 🔁 Follow-up (2026-06-27, CI audit doc sync)

- **[Docs Sync]**: `docs/CICD.md` 的 Record & Replay baseline artifact check 现在也声明 summary audit 会检查 recommended packet set 的 `ingest-ocu-candidates.sh`。
- **[Evidence Contract]**: 同一段落同步说明 official capture preflight smoke 会守住 packet set 根级 `ingest-ocu-candidates.sh`，完整 baseline runner 会把 recommended packet set OCU candidate handoff 写入 `evidence.preflightPipelines`。

### 🔁 Follow-up (2026-06-27, check-docs R&R contract)

- **[Docs Gate]**: `scripts/check-docs.sh` 现在把 Record & Replay handoff / replication / official capture 文档、逆向参考文档、官方 non-recording fixture 文件和 thin skill 入口纳入必要文件检查。
- **[Handoff Contract]**: 同一脚本还会检查 handoff、official capture、replication 和 CICD 文档继续声明 recommended packet set 的 `ingest-ocu-candidates.sh` handoff 或对应 artifact audit check，避免文档合同再次漂移。

### 🔁 Follow-up (2026-06-27, standalone source audit handoff)

- **[Standalone Manifest]**: `scripts/scaffold-record-and-replay-skill-repo.py` 生成的 `officialEvidence` 新增 `sourceRepoBaselineAudit`，声明默认 baseline audit、strict official golden gate audit 和默认 summary artifact。
- **[Evidence]**: 源码 scaffold smoke、npm staged scaffold smoke、baseline summary 和 artifact audit 新增 `checkedOfficialEvidenceAuditManifest`，缺失时 `usableBaseline=false`。
- **[Docs Sync]**: 同步 handoff、replication、architecture、CI/CD 和 quality score，明确 standalone repo handoff 不能丢失源仓 release / audit 证据入口。
- **[Docs Gate]**: `scripts/check-docs.sh` 现在检查 handoff / replication / architecture / CI 文档继续保留 `sourceRepoBaselineAudit`、baseline audit 命令和 `checkedOfficialEvidenceAuditManifest` 文案。

### 🔁 Follow-up (2026-06-27, standalone next action audit step)

- **[Summary Guidance]**: baseline summary 的 `scaffold-standalone-record-and-replay-repo` `nextActions` 现在先给出 `make record-and-replay-baseline-audit`，再给出 scaffold、生成 repo `scripts/check.sh` 和 optional lifecycle smoke。
- **[Artifact Audit]**: `scripts/check-record-and-replay-baseline-summary.py` 新增 `checkedStandaloneNextActionBaselineAuditCommand`，release / standalone audit 会拒绝缺少 source baseline audit handoff 的 summary artifact。
- **[Smoke]**: summary smoke 断言 standalone nextActions 包含 baseline audit 命令；summary audit smoke 会篡改删除该命令并要求 audit 失败。
- **[Docs Gate]**: `scripts/check-docs.sh` 现在要求 CI 文档保留 `checkedStandaloneNextActionBaselineAuditCommand` 文案。

### 🔁 Follow-up (2026-06-27, notify suppressed events path handoff)

- **[Runtime]**: `event-stream wait --notify-command` 成功回调现在会通过 `OPEN_COMPUTER_USE_EVENT_STREAM_SUPPRESSED_EVENTS_PATH` 暴露 `suppressed.jsonl`，让独立监听方在录制结束后能直接读取主事件流之外的降级 / 诊断证据。
- **[Standalone Contract]**: standalone thin skill repo scaffold 的 manifest、README/thin skill、生成态 `scripts/wait-notify-contract-smoke.py`、source scaffold smoke 和 npm staged scaffold smoke 都同步该环境变量；合成 completed session 的成功 callback 会验证该变量指向存在的 suppressed stream。
- **[Baseline Gate]**: baseline summary 与 artifact audit 新增 `checkedNotifySuppressedEventsPathEnv` 必需 evidence，summary smoke 和 audit smoke 均覆盖缺失负例。
- **[Boundary]**: 这仍属于 OCU 扩展层 `wait --notify-command`，不改变官方兼容 `event_stream_start/status/stop` 三件套 MCP surface，也不替代 required `simple-action-stop` official successful recording golden。

### 🔁 Follow-up (2026-06-28, strict audit artifact path split)

- **[Risk]**: `make record-and-replay-official-golden-gate-audit` 原先默认复用 `dist/record-and-replay-baseline-summary.json`；当前缺 required official successful recording fixture 时，strict gate 的预期失败摘要会覆盖刚通过的 baseline audit artifact。
- **[Fix]**: Makefile 新增 `RNR_OFFICIAL_GOLDEN_SUMMARY_JSON ?= dist/record-and-replay-official-golden-gate-summary.json`，strict audit 默认写该独立路径；默认 baseline audit 继续写 `dist/record-and-replay-baseline-summary.json`，仍可用 `RNR_BASELINE_SUMMARY_JSON=<path>` 覆盖。
- **[Smoke]**: `scripts/test-record-and-replay-baseline-audit-make-targets.py` 现在清理继承的 `RNR_BASELINE_SUMMARY_JSON` 与 `RNR_OFFICIAL_GOLDEN_SUMMARY_JSON`，并用 `make -n` 检查 baseline 默认/自定义路径、strict 默认/自定义路径、strict `--require-official-golden` 和 strict 默认路径不复用 baseline artifact。
- **[Summary Evidence]**: `scripts/run-record-and-replay-baseline-smoke.sh`、summary builder 和 artifact audit 都消费 `checkedBaselineAuditStrictOfficialGoldenDefaultSummaryPath`、`checkedBaselineAuditStrictOfficialGoldenCustomSummaryPath` 与 `checkedBaselineAuditStrictOfficialGoldenSeparateSummaryPath`，缺失时 `usableBaseline=false`。
- **[Standalone Handoff]**: standalone skill repo manifest 的 `officialEvidence.sourceRepoBaselineAudit` 现在分别声明 `baselineSummaryArtifact` 和 `strictOfficialGoldenSummaryArtifact`；生成态 README、source scaffold smoke 和 npm staged smoke 同步覆盖这两个 artifact handoff。

### 🔁 Follow-up (2026-06-28, audit summary variable isolation)

- **[Smoke]**: audit Make target dry-run smoke 新增双向变量隔离断言：`record-and-replay-baseline-audit RNR_OFFICIAL_GOLDEN_SUMMARY_JSON=<path>` 仍使用 baseline 默认 artifact，`record-and-replay-official-golden-gate-audit RNR_BASELINE_SUMMARY_JSON=<path>` 仍使用 strict 默认 artifact。
- **[Summary Evidence]**: baseline runner、summary builder 和 artifact audit 新增 `checkedBaselineAuditIgnoresStrictSummaryVar` 与 `checkedBaselineAuditStrictOfficialGoldenIgnoresBaselineSummaryVar`，缺失时 `usableBaseline=false`。
- **[Why]**: 这补住了只检查默认路径分离但没检查“传错覆盖变量”的缝隙，避免后续 Makefile 重构时又让 strict 失败摘要覆盖 baseline 可用证据。

### 🔁 Follow-up (2026-06-28, standalone audit isolation manifest)

- **[Standalone Manifest]**: `scripts/scaffold-record-and-replay-skill-repo.py` 生成的 `officialEvidence.sourceRepoBaselineAudit` 新增 `auditTargetDryRunSmoke`、`baselineSummaryEnvVar`、`strictOfficialGoldenSummaryEnvVar`、`verifiesSummaryArtifactSeparation` 和 `verifiesSummaryEnvVarIsolation`。
- **[Smoke]**: source scaffold smoke 与 npm staged scaffold smoke 的 exact manifest 断言同步覆盖这些字段，避免独立 repo handoff 只知道有两个 audit 命令，却不知道源仓还会机械验证 artifact 分离和覆盖变量隔离。
- **[Docs]**: 架构、handoff、replication、CI 和质量文档同步这份机器可读合同。

### 🔁 Follow-up (2026-06-28, baseline audit after isolation manifest)

- **[Full Audit]**: 在 standalone audit isolation manifest 合同补齐后复跑 `make record-and-replay-baseline-audit` 通过，刷新 `dist/record-and-replay-baseline-summary.json`。
- **[Artifact Audit]**: `scripts/check-record-and-replay-baseline-summary.py dist/record-and-replay-baseline-summary.json` 复审通过；摘要中 `usableBaseline=true`、`standaloneRepoBaselineReady=true`，并且 `checkedBaselineAuditIgnoresStrictSummaryVar=true` / `checkedBaselineAuditStrictOfficialGoldenIgnoresBaselineSummaryVar=true`。
- **[Remaining Gap]**: official successful recording golden 仍未完成，required `simple-action-stop` 仍缺失；因此 `officialSuccessfulRecordingGoldenComplete=false`、`officialSuccessfulRecordingEquivalenceReady=false` 是当前正确状态。

### 🔁 Follow-up (2026-06-28, strict audit expected-failure evidence)

- **[Strict Audit]**: 复跑 `make record-and-replay-official-golden-gate-audit`，命令按预期非零退出并刷新 `dist/record-and-replay-official-golden-gate-summary.json`；该 strict artifact 与 `dist/record-and-replay-baseline-summary.json` 不同，未覆盖可用 baseline 证据。
- **[Expected Failure]**: strict artifact 显示 `usableBaseline=true`、`standaloneRepoBaselineReady=true`、`strictOfficialGoldenRequired=true`、`officialGoldenRequirementSatisfied=false`、`officialGoldenGatePassed=false`，失败原因是 required `simple-action-stop` official successful recording 缺失，`officialFixtureCoverageErrors=[]`。
- **[Artifact Audit]**: `scripts/check-record-and-replay-baseline-summary.py` 新增 `--allow-strict-official-golden-missing`，用于审计 strict gate 缺 required official fixture 时写出的预期失败摘要；该模式要求 baseline / standalone / official non-recording / raw timeout evidence 完整、strict missing gap 可解释且无 coverage errors。
- **[Validation]**: 已用 `--allow-strict-official-golden-missing` 审计当前 strict artifact 通过，并补了 `scripts/test-record-and-replay-baseline-summary-audit.py` 的正负例，避免后续 release / standalone audit 只能人工区分预期 strict golden 缺口和 baseline 回归。

### 🔁 Follow-up (2026-06-28, standalone strict expected-failure audit handoff)

- **[Standalone Manifest]**: `scripts/scaffold-record-and-replay-skill-repo.py` 生成的 `officialEvidence.sourceRepoBaselineAudit` 新增 `strictOfficialGoldenExpectedFailureAudit`，直接暴露 `scripts/check-record-and-replay-baseline-summary.py dist/record-and-replay-official-golden-gate-summary.json --allow-strict-official-golden-missing`。
- **[Generated README]**: standalone README 的 Official Evidence 段落补充 strict gate 在 official successful recording fixtures 入库前预期失败，并给出 expected-failure audit 命令。

### 🔁 Follow-up (2026-06-28, standalone manifest self-check)

- **[Generated Repo]**: standalone thin skill repo 生成态新增 `scripts/verify-manifest.py`，默认 `scripts/check.sh` 会运行它来校验 `record-and-replay-skill-repo.json` 的机器合同。
- **[Manifest Contract]**: 生成态 manifest 新增 `checks.manifestContract=scripts/verify-manifest.py`，自检范围覆盖 official evidence、required / recommended scenario、`scenarioRecipes`、`sourceRepoBaselineAudit`、`strictOfficialGoldenExpectedFailureAudit`、OCU `extensionLayer`、官方三件套 no-arg MCP surface 和 recording-to-skill handoff。
- **[Evidence]**: source scaffold smoke、npm staged scaffold smoke、baseline shared contract 和 docs gate 都同步 `checkedManifestContract=true`，避免后续拆 standalone repo 时只验证 runtime / workflow smoke，却漏掉 manifest 自身漂移。
- **[Docs Sync]**: architecture、handoff、replication、CICD 和 quality score 同步说明该检查属于 standalone 默认自检层，不启动真实录制，也不向官方兼容 MCP surface 增加任何 OCU 扩展。
- **[Smoke]**: source scaffold smoke 与 npm staged scaffold smoke 的 exact manifest / README 断言同步覆盖该字段，避免未来独立 repo 只知道 strict gate artifact 路径，却不知道如何机器审计“预期缺 official golden”。
- **[Docs Gate]**: 架构、handoff、replication、CI、质量文档和 `scripts/check-docs.sh` 同步该 manifest 字段。

### 🔁 Follow-up (2026-06-28, manifest contract evidence negatives)

- **[Summary Gate]**: `scripts/test-record-and-replay-baseline-summary.py` 新增 source / npm staged `checkedManifestContract=false` 负例，确认最终 summary 会进入 `usableBaseline=false` 并在 `missingUsableBaselineEvidence` 中分别报告 `standaloneSkillRepo.checkedManifestContract` 与 `npmStagedSkillRepo.checkedManifestContract`。
- **[Artifact Audit]**: `scripts/test-record-and-replay-baseline-summary-audit.py` 的 direct evidence 篡改负例同步覆盖 `checkedStandaloneSkillRepoCheckedManifestContractEvidence` 和 `checkedNpmStagedSkillRepoCheckedManifestContractEvidence`，确保落盘 artifact 审计也会拒绝缺 manifest self-check evidence 的摘要。
- **[Docs Sync]**: handoff 的 standalone repo contract 列表补入 `scripts/verify-manifest.py`，明确它是默认 `checks` 的一部分，不启动真实录制。

### 🔁 Follow-up (2026-06-28, npm staged manifest verifier negative)

- **[NPM Staged Smoke]**: `scripts/test-npm-record-and-replay-skill-repo-scaffold.mjs` 现在会直接运行安装态 scaffold 生成 repo 内的 `scripts/verify-manifest.py`，要求输出 `checkedManifestContract=true` 和 `checkedStrictExpectedFailureAudit=true`。
- **[Negative Guard]**: 同一 smoke 会临时篡改生成态 `record-and-replay-skill-repo.json` 的 `strictOfficialGoldenExpectedFailureAudit`，确认 `verify-manifest.py` 非零退出并报告 `strict expected-failure audit command drifted`，再恢复原 manifest 后继续跑默认 `scripts/check.sh`。
- **[Why]**: 这让 npm 安装态生成物不只通过 `check.sh` 间接覆盖 manifest self-check，也能证明 standalone repo 自己的 manifest verifier 对关键 source audit handoff 漂移有正负例。

### 🔁 Follow-up (2026-06-28, full baseline audit refresh)

- **[Full Audit]**: 复跑 `make record-and-replay-baseline-audit` 通过，并刷新默认 baseline summary artifact。
- **[Evidence]**: 本轮 audit 覆盖 baseline contract、event-stream matrix、screenshot context、真实输入 action smoke、官方 1.0.857 surface compare、Codex-hosted no-active response compare、hostless raw timeout fixture、official fixture set gate、official/OCU fixture ingest、capture/pairing preflight、source standalone repo smoke 和 npm staged standalone repo smoke。
- **[Status]**: 摘要继续显示 `usableBaseline=true`、`standaloneRepoBaselineReady=true`、`officialNonRecordingBaselineVerified=true` 和 `officialRawStartTimeoutBoundaryVerified=true`；同时保持 `officialSuccessfulRecordingGoldenComplete=false`、`officialSuccessfulRecordingEquivalenceReady=false`，required `simple-action-stop` official successful recording 仍缺失。

### 🔁 Follow-up (2026-06-28, OCU scenario action candidates)

- **[Simple Candidate]**: 复跑 `OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTIONS=1 OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTION_SCENARIO=simple-action-stop ./scripts/run-event-stream-smoke-tests.sh` 通过；事件流包含 `session.started`、`window.changed`、`AX.focusedWindowChanged`、`mouse.click` 和 `session.ended`，并且 `skillReadiness.canCreateDraft`、MCP response shape capture、`skill-creator` handoff 和 generated skill path redaction 均通过。
- **[Drag Candidate]**: 复跑 `OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTIONS=1 OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTION_SCENARIO=drag-stop ./scripts/run-event-stream-smoke-tests.sh` 通过；事件流包含 `session.started`、`window.changed`、`AX.focusedWindowChanged`、`mouse.drag` 和 `session.ended`，并且同样能生成可交接的 skill 草稿。
- **[Boundary]**: 这两条只证明 OCU 侧 required / recommended action candidate 可复跑，不替代 official successful recording golden；required `simple-action-stop` official fixture 仍需要通过正常 Codex hosted Record & Replay 流程采集和脱敏入库。

### 🔁 Follow-up (2026-06-28, standalone README handoff verifier)

- **[Generated Repo]**: standalone thin skill repo 生成态新增 `scripts/verify-readme-handoff.py`，默认 `scripts/check.sh` 会运行它来校验 README 的交接合同。
- **[README Contract]**: verifier 检查官方 evidence fixture、baseline / strict audit 命令、strict 缺 official golden 的 expected-failure audit、required / recommended successful recording 场景、recording-to-skill 命令和 wait/notify 边界仍写在 README 中；该检查不启动真实录制，也不改变官方兼容 MCP surface。
- **[Evidence]**: `record-and-replay-skill-repo.json` 新增 `checks.readmeHandoffContract=scripts/verify-readme-handoff.py`；source scaffold smoke、npm staged scaffold smoke、shared baseline contract 和 baseline summary builder 都新增 / 消费 `checkedReadmeHandoffContract`、`checkedReadmeOfficialEvidenceHandoff`、`checkedReadmeOfficialGoldenGap` 与 `checkedReadmeWaitNotifyBoundary`。
- **[Negative Guard]**: source / npm staged scaffold smoke 都会临时篡改生成态 README 的 strict gate handoff，确认 README verifier 非零退出；summary smoke 也新增 README handoff evidence 缺失负例，确保 release / standalone audit 不能遗漏该层文档合同。

### 🔁 Follow-up (2026-06-28, official fixture set AX/suppressed strong compare)

- **[Policy]**: official fixture set gate 继续保持“直接复刻官方可观察行为，再补 OCU 扩展”的方向；同 scenario OCU candidate 不再只比较事件序列、metadata、semantic fields 和 MCP response shape，也默认要求 AX compact diff evidence / marker 与 suppressed event sequence / schema 对齐。
- **[Implementation]**: `scripts/check-event-stream-official-fixture-set.py` 固定向底层 compare 传入 `--require-ax-diff-evidence`、`--require-same-ax-diff-markers`、`--require-same-suppressed-event-sequence` 和 `--require-same-suppressed-schema`，并在输出中声明 `comparePolicy`。
- **[Smoke]**: `scripts/test-event-stream-official-fixture-set.py` 新增 official fixture 含 diff / cumulative diff、OCU candidate 缺 diff 的失败负例，要求错误报告包含缺 AX diff payload 与缺 cumulative AX diff payload。
- **[Summary Gate]**: baseline runner、summary builder 和 artifact audit 新增 `checkedAxDiffComparisonPolicy`、`checkedSuppressedStreamComparisonPolicy` 与 `checkedAxDiffComparisonFailure`，缺失时 `usableBaseline=false`。
- **[Docs Sync]**: replication / handoff / architecture / execution plan / quality score 同步说明后续 official golden 入库后，fixture set gate 会直接暴露 OCU compact diff 或 suppressed fallback 漂移；当前没有 official successful recording fixture，仍不能宣称官方 successful recording 等价。

### 🔁 Follow-up (2026-06-28, standalone fixture-set compare policy manifest)

- **[Manifest]**: standalone thin skill repo manifest 新增 `officialEvidence.sourceRepoBaselineChecks.officialFixtureSetGate.sameScenarioComparePolicy`，机器声明源仓 fixture set gate 会要求 AX diff evidence、AX diff marker、suppressed event sequence 和 suppressed schema。
- **[Verifier]**: 生成态 `scripts/verify-manifest.py` 会输出 `checkedOfficialFixtureSetComparePolicy=true`，并新增 suppressed schema policy 漂移负例；source scaffold smoke 和 npm staged scaffold smoke 都覆盖该负例。
- **[Summary Gate]**: shared baseline contract、summary builder 和 artifact audit 新增 / 消费 `checkedOfficialFixtureSetComparePolicyManifest`，缺失时 source 或 npm staged standalone evidence 会让 `usableBaseline=false`。
- **[Docs Gate]**: handoff、replication、architecture、CI、quality score 和 `scripts/check-docs.sh` 同步该字段，避免后续拆独立 repo 时丢失官方 golden 入库后的 AX / suppressed 强对比边界。

### 🔁 Follow-up (2026-06-28, standalone source baseline summary evidence)

- **[Generated Repo]**: standalone thin skill repo 生成态新增 `scripts/verify-source-baseline-summary.py`，默认 `scripts/check.sh` 会运行它来审计随 scaffold 复制的 `evidence/source-baseline-summary.json`。
- **[Evidence Projection]**: scaffold 会从源仓 `dist/record-and-replay-baseline-summary.json` 复制一份脱敏投影，只保留 baseline 状态、official fixture set gate policy evidence、source / npm staged standalone repo 关键 evidence，不复制源码或完整运行日志。
- **[Manifest Contract]**: `officialEvidence.sourceRepoBaselineAudit` 新增 `copiedBaselineSummaryEvidence=evidence/source-baseline-summary.json`，`checks` 新增 `sourceBaselineSummaryEvidence=scripts/verify-source-baseline-summary.py`。
- **[Summary Gate]**: source scaffold smoke、npm staged scaffold smoke、shared baseline contract、summary builder 和 artifact audit 新增 / 消费 `checkedSourceBaselineSummaryEvidence`；缺失时 source 或 npm staged standalone evidence 会让 `usableBaseline=false`。
- **[NPM Packaging]**: npm package 在存在 `dist/record-and-replay-baseline-summary.json` 时会携带该 artifact，安装态 scaffold 生成的 repo 也能产生同一份 source baseline summary projection。
- **[Docs Gate]**: handoff、replication、architecture、CI、quality score 和 `scripts/check-docs.sh` 同步该字段，避免 standalone repo 只保留 audit 命令文案，却不消费已落盘 baseline audit evidence。

### 🔁 Follow-up (2026-06-28, npm baseline summary artifact gate)

- **[Release Gate]**: `scripts/npm/build-packages.mjs` 不再静默跳过缺失的 `dist/record-and-replay-baseline-summary.json`；打包 `open-computer-use` 时必须复制该 artifact，供安装态 scaffold 投影出 `evidence/source-baseline-summary.json`。
- **[Failure Mode]**: 缺失 artifact 时 npm build 直接失败并输出 `Missing Record & Replay baseline summary artifact`，同时提示先运行 `make record-and-replay-baseline-audit`。
- **[Negative Guard]**: `scripts/test-npm-record-and-replay-skill-repo-scaffold.mjs` 会临时移走 baseline summary artifact，验证打包失败和诊断文案，再恢复 artifact 继续跑 npm staged scaffold smoke。
- **[Docs Sync]**: architecture、handoff、replication、CICD、quality score、execution plan 和 `scripts/check-docs.sh` 同步这条发布前置条件，避免后续 release 生成缺 source baseline summary evidence 的 npm 包。

### 🔁 Follow-up (2026-06-28, missing golden nextAction strict audit)

- **[Summary Guidance]**: `scripts/build-record-and-replay-baseline-summary.py` 的 `capture-official-successful-recording-golden` nextAction 现在以 `make record-and-replay-official-golden-gate-audit` 收尾，确保 official fixture 导入后下一步直接刷新 strict summary artifact。
- **[Artifact Audit]**: `scripts/check-record-and-replay-baseline-summary.py` 新增 `checkedMissingGoldenNextActionStrictAuditStep`，缺 required official golden 时会复审 nextAction 是否包含 strict audit Make target。
- **[Why]**: 这把 missing-golden handoff 和此前已建立的 release / standalone audit artifact 口径对齐，避免采到 `simple-action-stop` official fixture 后只跑普通 strict gate、没有留下 `dist/record-and-replay-official-golden-gate-summary.json` 证据。

### 🔁 Follow-up (2026-06-28, capture packet semantic guard)

- **[Capture Packet]**: official capture packet 新增 `capture-contract.json`，记录 scenario、fixture name、预期 action event、预期 `endReason`、status handoff path evidence 和 transcript evidence requirement。
- **[Wrapper Guard]**: `verify-inputs.sh` 现在除合法 JSON / 非 `_placeholder=true` 外，还要求 hosted status JSON 至少包含 `metadataPath` / `sessionPath` / `eventsPath` / `suppressedEventsPath` 这类 handoff path evidence；transcript enabled 时还要求 `inputs/mcp-transcript.json` 包含 response-shape 或 transcript evidence。`inspect-only.sh` / `import-fixture.sh` 在执行导入前也会先跑同一语义校验。
- **[Baseline Evidence]**: official capture preflight smoke 输出 `checkedCapturePacketInputSemanticGuard=true`；baseline runner、summary builder 和 artifact audit 通过 `checkedOfficialCapturePacketInputSemanticGuard` 消费该 evidence，缺失时 `usableBaseline=false`。

### 🔁 Follow-up (2026-06-28, capture packet set contract manifest)

- **[Packet Set Contract]**: recommended capture packet set 的根级 `capture-packets.json` 新增 `captureContracts` / `captureContractPaths`，把每个子 packet 的 `capture-contract.json` 合同内联到集合级 manifest。
- **[Baseline Evidence]**: official capture preflight smoke 输出 `checkedCapturePacketSetContractManifest=true`；baseline runner、summary builder 和 artifact audit 通过 `checkedOfficialCapturePacketSetContractManifest` 消费该 evidence，缺失时 `usableBaseline=false`。
- **[Why]**: 后续独立 repo 或 skill 只读根级 manifest 就能获得每个 scenario 的 expected action event、expected `endReason`、handoff path evidence 和 transcript requirement，不需要靠 README 或遍历子目录推断采样合同。

### 🔁 Follow-up (2026-06-28, standalone source summary capture packet contract)

- **[Standalone Projection]**: standalone scaffold 复制的 `evidence/source-baseline-summary.json` 现在保留 `preflightPipelines.checkedOfficialCapturePacketSetContractManifest`，生成态 `scripts/verify-source-baseline-summary.py` 会校验它并输出 `checkedSourceBaselineSummaryCapturePacketSetContractManifest=true`。
- **[Manifest Contract]**: `record-and-replay-skill-repo.json` 的 `officialEvidence.sourceRepoBaselineChecks.officialGoldenCapturePreflight.requiredEvidence` 现在显式声明 `checkedOfficialCapturePacketInputSemanticGuard` 和 `checkedOfficialCapturePacketSetContractManifest`。
- **[Baseline Evidence]**: source scaffold smoke、npm staged scaffold smoke、baseline summary builder 和 artifact audit 都消费 `checkedSourceBaselineSummaryCapturePacketSetContractManifest`，缺失时 `usableBaseline=false`。

### 🔁 Follow-up (2026-06-28, standalone source summary official state)

- **[Verifier Contract]**: 生成态 `scripts/verify-source-baseline-summary.py` 现在接受两种 official golden 状态：当前 required `simple-action-stop` gap 明确且 equivalence 未声明，或未来 official golden gate / successful recording equivalence 已完成且 required gaps、not-ready gaps 和 coverage errors 为空。
- **[Negative Guard]**: source scaffold smoke 和 npm staged scaffold smoke 都新增矛盾状态负例：仍缺 required scenario 却把 `officialSuccessfulRecordingEquivalenceReady` 置为 `true` 时，verifier 必须非零退出。
- **[Why]**: 这样当前 standalone repo 仍不会误报官方等价，同时未来 official golden 入库后，独立 repo 的 source summary self-check 不会被旧的 missing-golden 合同卡住。

### 🔁 Follow-up (2026-06-28, baseline artifact consumes source summary official state)

- **[Baseline Evidence]**: source scaffold smoke 和 npm staged scaffold smoke 现在都把 `checkedSourceBaselineSummaryOfficialGoldenState=true` 输出到最终 JSON。
- **[Summary Gate]**: shared baseline contract、summary builder 和 artifact audit 都消费 `checkedSourceBaselineSummaryOfficialGoldenState`；缺失时 `usableBaseline=false`，并通过具体 `standaloneSkillRepo.*` 或 `npmStagedSkillRepo.*` evidence 名称报告。
- **[Why]**: 这把生成态 `verify-source-baseline-summary.py` 的 official golden 状态自洽检查提升到 release / standalone audit artifact，而不是只停留在单独 scaffold smoke 里。

### 🔁 Follow-up (2026-06-28, capture packet strict audit handoff)

- **[Capture Packet]**: official capture preflight 的 `commands.strictOfficialGoldenGate` 现在指向 `make record-and-replay-official-golden-gate-audit`，生成的 `strict-golden-gate.sh` wrapper 也会运行 audit target，而不是只跑不落盘的 strict gate。
- **[Docs Gate]**: official golden capture 文档和 handoff 文档同步说明 `strict-golden-gate.sh` 会刷新 strict summary artifact；`scripts/check-docs.sh` 新增针脚要求官方采集入口保留 `record-and-replay-official-golden-gate-audit`。
- **[Why]**: 采到 `simple-action-stop` official successful recording 后，后续流程应直接留下 `dist/record-and-replay-official-golden-gate-summary.json` 证据，避免 release / standalone audit 还要人工补跑一次。

### 🔁 Follow-up (2026-06-28, capture packet strict audit baseline evidence)

- **[Evidence]**: official capture preflight smoke 新增 `checkedCapturePacketStrictAuditHandoff=true`，证明生成的 `strict-golden-gate.sh` wrapper 指向 `make record-and-replay-official-golden-gate-audit`。
- **[Summary Gate]**: baseline summary 投影为 `preflightPipelines.checkedOfficialCapturePacketStrictAuditHandoff`，artifact audit 通过 `checkedOfficialCapturePacketStrictAuditHandoffEvidence` 复审；缺失时 `usableBaseline=false`。
- **[Why]**: 这把上一条 handoff 行为从单脚本测试提升为 release / standalone audit artifact 的必需 evidence，防止采样包后续回退到只跑普通 strict gate。

### 🔁 Follow-up (2026-06-28, standalone source summary strict audit handoff)

- **[Standalone Projection]**: standalone scaffold 复制的 `evidence/source-baseline-summary.json` 现在保留 `preflightPipelines.checkedOfficialCapturePacketStrictAuditHandoff`，生成态 `scripts/verify-source-baseline-summary.py` 会校验它并输出 `checkedSourceBaselineSummaryCapturePacketStrictAuditHandoff=true`。
- **[Manifest Contract]**: `record-and-replay-skill-repo.json` 的 `officialEvidence.sourceRepoBaselineChecks.officialGoldenCapturePreflight.requiredEvidence` 现在显式声明 `checkedOfficialCapturePacketStrictAuditHandoff`。
- **[Baseline Evidence]**: source scaffold smoke、npm staged scaffold smoke、baseline summary builder 和 artifact audit 都消费 `checkedSourceBaselineSummaryCapturePacketStrictAuditHandoff`，缺失时 `usableBaseline=false`。
- **[Why]**: 独立 repo 后续只读 source baseline summary 也能证明 official fixture 入库后会刷新 strict summary artifact，而不是只继承源仓聊天或 README 里的操作提示。

### 🔁 Follow-up (2026-06-28, README artifact-first R&R commands)

- **[User Entry]**: README / README.zh-CN 的 Record & Replay 命令清单现在显式推荐 `make record-and-replay-baseline-audit` 作为 release / standalone 留证入口，而不只展示 `record-and-replay-baseline-smoke`。
- **[Capture Handoff]**: README / README.zh-CN 增加 `make record-and-replay-official-golden-capture-packet` 与 `record-and-replay-official-golden-capture-packet-set` 示例，要求替换 hosted JSON 占位后按 `verify` / `inspect` / `import` / strict artifact wrapper 顺序执行。
- **[Strict Artifact]**: README / README.zh-CN 增加 `make record-and-replay-official-golden-gate-audit` 和 `scripts/check-record-and-replay-baseline-summary.py ... --allow-strict-official-golden-missing`，让缺 required official golden 时的 strict 失败也有可解释 artifact。
- **[Docs Gate]**: `scripts/check-docs.sh` 新增 README 针脚，避免公开入口退回只跑不落盘的 smoke / strict gate。

### 🔁 Follow-up (2026-06-28, capture packet strict expected-failure audit)

- **[Capture Packet]**: official capture packet 和 recommended packet set 现在都会生成 `strict-expected-failure-audit.sh`，用于审计已落盘 strict summary 的 `--allow-strict-official-golden-missing` 口径。
- **[Baseline Evidence]**: official capture preflight smoke 输出 `checkedCapturePacketStrictExpectedFailureAuditHandoff=true`，baseline summary 投影为 `checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff`，artifact audit 通过 `checkedOfficialCapturePacketStrictExpectedFailureAuditHandoffEvidence` 复审；缺失时 `usableBaseline=false`。
- **[Docs Gate]**: README、official capture、handoff、replication、CI、quality score、execution plan 和 `scripts/check-docs.sh` 同步这条 wrapper / evidence，避免 required official golden 尚缺时只能人工判断 strict 失败摘要是否预期。

### 🔁 Follow-up (2026-06-28, standalone source summary strict expected-failure handoff)

- **[Standalone Projection]**: standalone scaffold 复制的 `evidence/source-baseline-summary.json` 现在也保留 `preflightPipelines.checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff`，生成态 `scripts/verify-source-baseline-summary.py` 会校验它并输出 `checkedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff=true`。
- **[Manifest Contract]**: `record-and-replay-skill-repo.json` 的 `officialEvidence.sourceRepoBaselineChecks.officialGoldenCapturePreflight.requiredEvidence` 同步声明 `checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff`。
- **[Baseline Evidence]**: source scaffold smoke、npm staged scaffold smoke、baseline summary builder 和 artifact audit 都消费 `checkedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff`，缺失时 `usableBaseline=false`。
- **[Why]**: 独立 repo 后续即使只读取脱敏 source baseline summary，也能证明 required official golden 尚缺时的 strict expected-failure audit handoff 没有在 scaffold / npm 发布链路里丢失。

### 🔁 Follow-up (2026-06-28, refreshed baseline artifacts after strict expected-failure handoff)

- **[Baseline Artifact]**: 复跑 `make record-and-replay-baseline-audit`，刷新 `dist/record-and-replay-baseline-summary.json`。默认 summary 现在显示 `usableBaseline=true`、`standaloneRepoBaselineReady=true`，并且 source / npm staged standalone evidence 都包含 `checkedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff=true`。
- **[Strict Artifact]**: 复跑 `make record-and-replay-official-golden-gate-audit`，命令按预期非零退出并刷新 `dist/record-and-replay-official-golden-gate-summary.json`。失败仍只来自 required `simple-action-stop` official successful recording fixture 尚未入库。
- **[Artifact Audit]**: `scripts/check-record-and-replay-baseline-summary.py dist/record-and-replay-baseline-summary.json` 通过；`scripts/check-record-and-replay-baseline-summary.py dist/record-and-replay-official-golden-gate-summary.json --allow-strict-official-golden-missing` 也通过，证明 strict expected-failure artifact 处于可解释缺口状态。

### 🔁 Follow-up (2026-06-28, official capture post workflow contract)

- **[Capture Contract]**: official capture packet 的 `capture-contract.json` 和返回 JSON 新增 `postCaptureWorkflow`，把录完官方样本后的替换 hosted JSON、verify、inspect、import、coverage / fixture-set gate、可选 OCU candidate ingest、strict audit 和 strict expected-failure audit 固化成机器可读步骤。
- **[Packet Set Contract]**: recommended packet set 的根级 `capture-packets.json` 新增按 scenario 分组的 `postCaptureWorkflow`，让独立 repo、skill 或批量采集脚本可以只读根 manifest 获取录制后的有序 handoff。
- **[Evidence]**: official capture preflight smoke、baseline runner、summary builder 和 artifact audit 现在消费 `checkedOfficialCapturePacketPostCaptureWorkflow` 与 `checkedOfficialCapturePacketSetPostCaptureWorkflow`，缺失时 `usableBaseline=false`，避免后续仍要从 README 或聊天上下文拼采样后流程。

### 🔁 Follow-up (2026-06-28, standalone source summary post workflow evidence)

- **[Standalone Projection]**: standalone scaffold 复制的 `evidence/source-baseline-summary.json` 现在保留 `preflightPipelines.checkedOfficialCapturePacketPostCaptureWorkflow` 与 `preflightPipelines.checkedOfficialCapturePacketSetPostCaptureWorkflow`，生成态 `scripts/verify-source-baseline-summary.py` 会校验它们并输出 `checkedSourceBaselineSummaryCapturePacketPostCaptureWorkflow=true` 和 `checkedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow=true`。
- **[Manifest Contract]**: `record-and-replay-skill-repo.json` 的 `officialEvidence.sourceRepoBaselineChecks.officialGoldenCapturePreflight.requiredEvidence` 同步声明 `checkedOfficialCapturePacketPostCaptureWorkflow` 与 `checkedOfficialCapturePacketSetPostCaptureWorkflow`。
- **[Baseline Evidence]**: source scaffold smoke、npm staged scaffold smoke、baseline summary builder 和 artifact audit 都消费这两个 source summary workflow evidence，缺失时 `usableBaseline=false`，避免后续拆独立 repo 时丢失采样包录制后的有序 handoff。

### 🔁 Follow-up (2026-06-28, standalone package artifact verifier)

- **[Generated Repo]**: standalone scaffold 新增 `scripts/verify-package-artifact.py`，默认 `scripts/check.sh` 会在 `scripts/package-skill.sh` 后运行它。
- **[Artifact Gate]**: verifier 会打开 `.skill` archive，确认 `.skill` alias 与 zip 字节一致、archive 路径只在预期 skill 目录下、packaged `SKILL.md` frontmatter 和 Record & Replay handoff 片段仍存在。
- **[Baseline Evidence]**: source scaffold smoke、npm staged scaffold smoke、baseline summary builder 和 artifact audit 都消费 `checkedPackageArtifact=true`，缺失时 `usableBaseline=false`，避免独立 repo 只证明 `.skill` 文件存在却没有证明制品内容。

### 🔁 Follow-up (2026-06-28, official capture workflow verifier)

- **[Capture Packet]**: official capture packet 和 recommended packet set 新增 `verify-workflow.sh`，不读取 hosted JSON，只校验 `postCaptureWorkflow`、input 文件、wrapper command、可执行 bit 和 transcript 开关一致。
- **[Baseline Evidence]**: official capture preflight smoke 输出 `checkedCapturePacketWorkflowVerifier=true` / `checkedCapturePacketSetWorkflowVerifier=true`；baseline summary 与 artifact audit 消费 `checkedOfficialCapturePacketWorkflowVerifier` / `checkedOfficialCapturePacketSetWorkflowVerifier`。
- **[Standalone Handoff]**: generated standalone repo 的 `evidence/source-baseline-summary.json` 继承 workflow verifier evidence，并由 `checkedSourceBaselineSummaryCapturePacketWorkflowVerifier` / `checkedSourceBaselineSummaryCapturePacketSetWorkflowVerifier` 守住，避免拆独立 repo 时丢失官方采样包自身的执行计划校验。

### 🔁 Follow-up (2026-06-28, hosted official capture finalizer)

- **[Official Fidelity]**: official successful recording 的 MCP transcript gate 对齐官方 skill 流程，要求 `event_stream_start`、active `event_stream_status`、`event_stream_stop` 和 final `event_stream_status` response shape，不再把额外 `repeatStartResponseShape` 当作 Codex-hosted official capture 的必需证据。
- **[Finalizer]**: 新增 `scripts/finalize-record-and-replay-official-capture-packet.py`，可把 Codex-hosted start/status/stop/final-status JSON 写入 capture packet inputs，并生成 readiness 可消费的 `mcp-transcript.json`。
- **[Smoke]**: 新增 `make record-and-replay-official-capture-finalizer-smoke` / `scripts/test-record-and-replay-official-capture-finalizer.py`，用合成 hosted JSON 验证 finalizer 会跑通 `verify-workflow.sh` / `verify-inputs.sh`，并覆盖缺 final status 与缺 handoff path 的失败路径。

### 🔁 Follow-up (2026-06-29, hosted official completed session observation)

- **[Safety]**: 经用户授权启动 Codex-hosted Record & Replay 后，用户通过官方录制控制结束；随后确认 `event_stream_status` / `event_stream_stop` 都显示 completed，`endReason=recording_controls_stopped`，没有 active recorder 留在后台。
- **[Observation]**: 该 completed session 约 5 分钟、434 行事件，事件使用顶层 `kind` 字段，观察到 lifecycle、window、selection、mouse click / context menu / drag、keyboard text / submit / shortcut 等事件，以及 AX `fullTree` / `diffFromPrevious` 结构。
- **[Boundary]**: 该样本捕获的是多应用真实工作流和私有可见内容，不是预期的低风险 `simple-action-stop` 单击场景；因此只把脱敏 schema 事实写入逆向参考，不入库、不导入 fixture、不作为 official successful recording golden。

### 🔁 Follow-up (2026-07-01, event kind compatibility baseline)

- **[Implementation]**: OCU event stream 写入主事件和 suppressed 事件前会规范化 payload：已有 `type` 时补同值 `kind`，只有 `kind` 时补回兼容 `type`。这让新产物贴近 Codex-hosted 官方 completed session 的顶层 `kind` 观察，同时不破坏既有 OCU 工具链。
- **[Consumer Compatibility]**: Swift validator / summarizer 和 Python `validate` / `summarize` / fixture import / golden readiness / recording compare 脚本都改为用 `kind` 优先、`type` fallback 识别事件名，后续 official `kind`-only 样本可以直接进入校验、摘要、导入和同场景对比链路。
- **[Validation]**: 已跑 Python 语法编译、`scripts/test-event-stream-golden-readiness.py`、fixture import、recording compare、skill scaffold smoke、`kind`-only validate / summarize 临时探针，以及 Swift `testEventStreamServiceStopsAtMaximumDuration` / `testEventStreamSuppressedEventsUpdateMetadata`。

### 🔁 Follow-up (2026-07-01, hosted-style MCP handoff response)

- **[MCP Response]**: `event_stream_start` / `event_stream_status` / `event_stream_stop` 的官方兼容 MCP text JSON 现在在 active / completed 状态下补 `sessionDirectoryPath`，并把对外 `metadataPath` 指向 `session.json`，同时保留 `sessionID`、`sessionId`、`sessionPath`、`eventsPath`、`isRecording` 和 `maxDurationSeconds`，贴近 2026-06-29 Codex-hosted completed session 观察。
- **[Boundary]**: 这次只调整官方兼容 MCP surface；OCU CLI `event-stream start/status/stop --json`、`wait --notify-command` 和 strict validator 仍继续使用完整 OCU metadata dictionary，避免破坏 wait/notify 扩展和本地 recording-to-skill 结构校验。
- **[Validation]**: 已跑 `swift test --filter OpenComputerUseKitTests/testEventStreamMCPServerListsRecordAndReplayTools` 和默认 `scripts/run-event-stream-smoke-tests.sh`，确认 start/status/stop handoff path、runtime validator 和 summarizer 仍能通过。

### 🔁 Follow-up (2026-07-01, official-style session handoff file)

- **[File Contract]**: OCU 录制目录里的 `metadata.json` 继续写完整 OCU status，用于 wait、strict validation、recording-to-skill 和本地工具链；`session.json` 改为官方风格最小 handoff，只写 `id`、`startedAt`、结束后的 `endedAt` / `endReason` 和 `eventsPath`，贴近 2026-06-29 Codex-hosted completed session 观察。
- **[Validator Compatibility]**: Swift runtime validator、源码 Python validator 和 golden readiness gate 不再要求 `metadata.json` / `session.json` 字节相等，而是要求 session id、`eventsPath`、`startedAt` 和结束字段语义兼容；直接传入 `session.json` 且同目录有 `metadata.json` 时，strict 校验会优先读取完整 metadata，同时仍检查 handoff 文件兼容性。
- **[Validation]**: 已跑 Python 编译、`scripts/test-event-stream-golden-readiness.py`、Swift `testEventStreamServiceWritesSessionFilesAndStops` / `testEventStreamRecordingValidationAcceptsOfficialStyleSessionHandoffAlias`，以及默认 `scripts/run-event-stream-smoke-tests.sh`。

### 🔁 Follow-up (2026-07-01, official-compatible AX fullTree payload)

- **[AX Payload]**: `AX.focusedWindowChanged` 的 full `accessibilityInspectorPayload` 现在双写官方观察到的 `fullTree` 和 OCU 既有 `treeLines`；diff payload 继续保留 `diffFromPrevious=true`、previous diff 和 cumulative diff baseline，避免把 compact diff 伪装成 full tree。
- **[Fixture Tooling]**: golden readiness 输出新增 `hasFullTreePayload`，recording compare 的 semantic paths / AX evidence 纳入 `accessibilityInspectorPayload.fullTree[]`，fixture importer 把 `fullTree` 作为敏感 AX 文本脱敏。
- **[Validation]**: 已跑 Python 编译、`scripts/test-event-stream-golden-readiness.py`、`scripts/test-event-stream-recording-compare.py`、`scripts/test-event-stream-fixture-import.py` 和 Swift `testEventStreamServiceWritesAXFullDiffAndCumulativePayloads`。

### 🔁 Follow-up (2026-07-01, official minimal session fixture import)

- **[Import Compatibility]**: `scripts/import-event-stream-fixture.py` 现在可直接导入 official hosted 最小 recording 目录，也就是只有 `events.jsonl` 和官方风格 `session.json` 的产物；导入时会把 `session.json.id` 当作 session id 脱敏，并生成 fixture 侧完整 `metadata.json`。
- **[Fixture Normalization]**: 导入后的 fixture 固定写 `metadata.json`、官方风格 `session.json`、`events.jsonl` 和空 `suppressed.jsonl`，并补齐 event / suppressed counts 与四个相对 handoff path，方便 readiness / compare gate 不依赖手工补文件。
- **[Validation]**: `scripts/test-event-stream-fixture-import.py` 新增 official-minimal 样本，覆盖 `kind`-only 事件、AX `fullTree` 脱敏、空 suppressed 文件、metadata count 和 handoff path readiness。

### 🔁 Follow-up (2026-07-01, official capture packet minimal handoff guard)

- **[Capture Contract]**: official capture packet 的 status JSON 语义校验不再要求 hosted response 自带 `suppressedEventsPath`。现在 required handoff evidence 是 `eventsPath` 加 `metadataPath` 或 `sessionPath`；`suppressedEventsPath` / `sessionDirectoryPath` 只作为 optional evidence 记录。
- **[Reasoning]**: 这与 Codex-hosted completed session 观察一致：官方原始目录可能只有 `events.jsonl` 和最小 `session.json`，fixture import 会在脱敏入库时生成空 `suppressed.jsonl` 和完整 fixture metadata。
- **[Validation]**: official capture preflight smoke 和 hosted capture finalizer smoke 覆盖无 `suppressedEventsPath` 的 hosted JSON 仍可通过 `verify-inputs.sh`，同时 no-handoff JSON 仍会失败。

### 🔁 Follow-up (2026-07-01, official sessionDirectoryPath ingest)

- **[Ingest Compatibility]**: `scripts/ingest-official-record-and-replay-fixture.py` 现在会从 hosted status JSON 递归提取 `sessionDirectoryPath`，并在没有 `metadataPath` / `sessionPath` / `eventsPath` 时把该目录作为 recording input。
- **[Official Minimal Package]**: 这条路径会继续复用 fixture import 的 official minimal session 支持，读取目录内 `events.jsonl + session.json`，并为脱敏 fixture 生成完整 `metadata.json`、官方风格 `session.json` 和空 `suppressed.jsonl`。
- **[Validation]**: `scripts/test-official-record-and-replay-fixture-ingest.py` 新增 hosted JSON 只含 `sessionDirectoryPath` 的样本，并输出 `checkedOfficialSessionDirectoryPathHandoff=true`；`scripts/run-record-and-replay-baseline-smoke.sh`、summary builder 和 summary artifact audit 也消费 `fixtureIngestPipelines.checkedOfficialSessionDirectoryPathHandoff`，缺失时 `usableBaseline=false`。该补丁不放宽 capture packet strict semantic guard，packet 仍要求 `eventsPath` 加 `metadataPath` 或 `sessionPath`。

### 🔁 Follow-up (2026-07-01, standalone sessionDirectoryPath source evidence)

- **[Standalone Manifest]**: `record-and-replay-skill-repo.json` 现在在 `officialEvidence.sourceRepoBaselineChecks.officialFixtureIngest` 中声明 `checkedOfficialSessionDirectoryPathHandoff` 是源仓 baseline evidence，避免独立 repo 只知道 capture packet / fixture set / pairing preflight。
- **[Source Summary Projection]**: `evidence/source-baseline-summary.json` 会保留 `fixtureIngestPipelines.checkedOfficialSessionDirectoryPathHandoff`，生成态 `scripts/verify-source-baseline-summary.py` 校验该字段并输出 `checkedSourceBaselineSummaryOfficialSessionDirectoryPathHandoff=true`。
- **[Baseline Evidence]**: source scaffold smoke、npm staged scaffold smoke、baseline summary builder、shared baseline contract 和 artifact audit 都消费这条 source summary evidence；缺失时 `usableBaseline=false`，防止拆 standalone repo 时丢掉 official completed response 只给 `sessionDirectoryPath` 的导入证据。

### 🔁 Follow-up (2026-07-01, required official fixture ready)

- **[Official Fixture]**: 通过 Codex-hosted Record & Replay 采集并脱敏入库 required `simple-action-stop` official successful recording fixture，保存在 `docs/references/codex-computer-use-reverse-engineering/fixtures/recordings/official-simple-action-stop-1.0.857/`。
- **[Gate Status]**: 复核 golden readiness、coverage `--require-readiness` 和 `make record-and-replay-official-golden-fixture-gate`，确认 required official fixture 已 ready；recommended `keyboard-input-stop`、`drag-stop`、`cancel`、`timeout` 仍是后续采样缺口。
- **[Standalone Contract]**: `scripts/scaffold-record-and-replay-skill-repo.py` 不再硬编码 `officialEvidence.hasSuccessfulRecordingGolden=false`，改为从 source baseline summary 派生，并让生成态 manifest verifier 校验该字段与 copied `evidence/source-baseline-summary.json` 一致。
- **[Compatibility]**: Record & Replay Python helper 补齐 future annotations，避免 macOS system Python 3.9 直接运行 capture packet / ingest / readiness 脚本时因 PEP 604 annotation 解析失败。
- **[Docs Sync]**: 更新 README、中文 README、handoff、replication、official capture checklist、architecture、reverse-engineering reference、references index 和 quality score，把状态从 required missing 调整为 required ready / recommended pending。

### 🔁 Follow-up (2026-07-01, action smoke scroll best-effort)

- **[Gate Policy]**: 默认 `mixed-action-stop` 真实输入 smoke 的 release hard gate 收敛为 `mouse.click`、AX context、MCP transcript 和 recording-to-skill handoff；外部 Swift action 仍发送 best-effort scroll wheel。
- **[Reasoning]**: 官方尚未确认独立 scroll event 名称，且 macOS 合成 scroll wheel 在部分环境会被 session event tap 过滤。捕获到的 `experimentalRawEvents` / `reason=scrollWheel` 仍进入 summary/scaffold 并渲染 Scroll replay step，但不再决定 official golden gate 是否通过。
- **[Validation Target]**: 后续 strict audit 应以 click/AX/MCP/skill handoff 作为默认 action evidence；scroll raw-only 只作为额外可用证据和推荐校准项。
