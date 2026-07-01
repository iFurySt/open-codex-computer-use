# CI/CD 说明

这个模板自带一套不依赖具体语言栈的 CI/CD 骨架。

## 当前 release 入口

- `scripts/release-package.sh`：构建 universal `Open Computer Use.app`，cross-compile Linux / Windows runtime，stage 三个既有 root/alias npm 包；每个包都会内置 macOS app、Linux binaries 和 Windows exes，并暴露 `open-computer-use` / `ocu` 等 npm bin 入口，产出 `dist/release/npm/*.tgz` 与 `dist/release/release-manifest.json`。当前 CI 继续显式使用 ad-hoc signing，保持和此前发布链路一致；本地 debug/dev 构建则允许使用开发机自己的签名身份。
- `scripts/build-cursor-motion-dmg.sh`：本地构建 `Cursor Motion.app` 并封装 `dist/release/cursor-motion/CursorMotion-<version>.dmg`，支持 `native` / `arm64` / `x86_64` / `universal`。
- `scripts/build-open-computer-use-linux.sh`：本地构建实验性 Linux `open-computer-use` binary，支持 `arm64` / `amd64`；release package 会把这两个产物内置进既有 npm 包的 `dist/linux/`。
- `scripts/build-open-computer-use-windows.sh`：本地构建实验性 Windows `open-computer-use.exe`，支持 `arm64` / `amd64`；release package 会把这两个产物内置进既有 npm 包的 `dist/windows/`。
- `.github/workflows/release.yml`：支持 push semver tag 自动发布，也支持手动触发；tag push 时会同时跑 npm release 打包逻辑与 `Cursor Motion` 的 DMG 打包，并把 `.dmg` 上传到对应的 GitHub Releases 页面。`Open Computer Use` 的 npm 产物默认走 ad-hoc signing；如果配置了 `OPEN_COMPUTER_USE_CODESIGN_*` secrets，则会先导入 `Developer ID Application` 证书，再按同一 identity 对 release `.app` 统一签名。`Cursor Motion` 的 DMG 也会复用同一张 `Developer ID Application` 证书签 app；若同时配置 `APPLE_NOTARY_*` secrets，则会在上传前对 `.dmg` 做 notarization 和 staple。

## 设计原则

这套默认流水线的目标，是在项目真正成形前先把交付链路搭起来，而不是假装已经知道未来项目该怎么 build 和 deploy。

当新项目的技术栈确定后，你应该继续在 `scripts/release-package.sh` 这条真实构建链路上扩展，而不是另起一套平行流程。

所有 GitHub Actions 都已经 pin 到 commit SHA。后续升级 action 时，也要继续保持这个约束。

## 推荐接入顺序

1. 保留 `ci.yml`，作为仓库的基础门禁。
2. 在 `scripts/ci.sh` 里继续叠加项目自己的验证命令。
3. 在 `scripts/release-package.sh` 已有的真实构建基础上继续扩展 release 产物。
4. 技术栈和环境稳定后，再补具体的部署 job。
5. 即使交付方式变化，SBOM 和 provenance 这类供应链能力也建议保留。

## 当前 CI 门禁

`scripts/ci.sh` 是本地和 GitHub Actions 共用的默认入口，当前会顺序执行：

- `scripts/check-docs.sh`
- `scripts/check-repo-hygiene.sh`
- `scripts/check-action-pinning.sh`
- 所有 `scripts/**/*.sh` 的 `bash -n`
- 所有 `scripts/**/*.mjs` 的 `node --check`
- 所有 `scripts/**/*.py` 的 `python3 -m py_compile`
- `npm run package:skill`
- `scripts/compare-event-stream-surface.py`
- `scripts/compare-event-stream-no-active.py`
- `scripts/test-event-stream-probe-fixtures.py`
- `scripts/test-event-stream-recording-probe.py`
- `scripts/test-event-stream-local-probe.py`
- `scripts/test-event-stream-golden-readiness.py`
- `scripts/test-event-stream-official-fixture-coverage.py`
- `scripts/check-event-stream-official-fixture-coverage.py --allow-missing`
- `scripts/test-record-and-replay-baseline-summary.py`
- `scripts/test-record-and-replay-baseline-summary-audit.py`
- `scripts/test-record-and-replay-baseline-audit-make-targets.py`
- `scripts/test-record-and-replay-baseline-runner-summary-json.py`
- `scripts/test-record-and-replay-official-golden-capture-preflight.py`
- `scripts/test-record-and-replay-ocu-candidate-pairing-preflight.py`
- `scripts/test-event-stream-official-fixture-set.py`
- `scripts/test-official-record-and-replay-fixture-ingest.py`
- `scripts/test-ocu-record-and-replay-candidate-ingest.py`
- `scripts/test-event-stream-skill-scaffold.py`
- `scripts/test-record-and-replay-skill-repo-scaffold.py`
- `swift test`
- `scripts/run-event-stream-smoke-matrix.sh`
- Windows / Linux Go runtime tests，前提是当前环境安装了 `go`

`scripts/check-docs.sh` 不只检查通用文档骨架，也守住 Record & Replay baseline 的关键入口文档、官方 non-recording fixture 文件和 recommended packet set 的 `ingest-ocu-candidates.sh` handoff 文案，避免 R&R summary / artifact audit 合同只在脚本里更新、短入口和 CI 文档继续漂移。

Record & Replay surface drift check 默认只比对 OCU 自己的 `event-stream mcp` 与仓库内官方 1.0.857 non-recording fixture。探测本机官方 Codex bundle 的路径需要显式执行 `scripts/compare-event-stream-surface.py --use-default-official`，不进入默认 CI，避免 CI 依赖当前机器的 Codex plugin cache。

Record & Replay no-active drift check 默认只启动本地 OCU `event-stream mcp`，调用 `event_stream_status` / `event_stream_stop`，并和 Codex-hosted 官方 1.0.857 no-active fixture 比对 text JSON shape，同时断言不会创建 `latest-session.json`、`active-session.json` 或 session 目录。该检查不调用 `event_stream_start`，不启动真实录制。

Record & Replay raw probe fixture check 默认只校验仓库内已经脱敏入库的官方 raw start-timeout transcript shape，不会启动官方 bundled client，也不会调用官方 `event_stream_start`。真实官方 raw start/status/stop 探测需要显式执行 `make event-stream-official-start-probe`。

Record & Replay local probe smoke 会启动本地 OCU `event-stream mcp`，通过 `scripts/probe-event-stream-recording.py --target local --start-stop` 采集 initialize/tools-list/start/repeat start/status/stop/repeat stop/final status transcript，断言重复 start 返回同一个 active session、repeat stop 和 final status 返回同一个 completed session，生成的 fixture 里 MCP text JSON 已转换为脱敏 `textJSON`、不含本机绝对路径，并用源码 validator 与 runtime validator 校验最终 session 文件。该检查只使用本地 OCU，不依赖官方 bundle。

Record & Replay 默认 CI 只跑稳定本地矩阵：lifecycle、no-active、timeout、wait timeout、approval denied/cancelled、MCP elicitation approval、app-agent wait/notify、fixture import、golden readiness 和 recording compare；另外单独跑 skill scaffold smoke，覆盖录制摘要生成带 `skillReadiness` 的 `SKILL.md` 草稿和脱敏 summary 的 handoff，并跑 standalone thin skill repo scaffold smoke，确认导出的独立 repo 骨架可打包、只声明 `open-computer-use event-stream mcp` runtime contract，且生成态 `scripts/package-skill.sh` 会拒绝缺失 description 的 frontmatter，生成态 `scripts/verify-manifest.py` 会校验 `record-and-replay-skill-repo.json` 的 `manifestContract`、官方 evidence、source repo audit、OCU 扩展边界和 recording-to-skill handoff，生成态 `scripts/verify-source-baseline-summary.py` 会审计 `evidence/source-baseline-summary.json` 这份来自 `dist/record-and-replay-baseline-summary.json` 的脱敏投影，确认 `usableBaseline=true`、`standaloneRepoBaselineReady=true`、official golden 状态自洽（当前 required gap 明确，或未来 official golden/equivalence ready 完成态成立）且 source / npm staged standalone evidence 完整，生成态 `scripts/verify-runtime.py` 可以用当前构建出的 `OpenComputerUse` binary 实际握手验证官方三件套 surface，包括 initialize capabilities、tool description、empty input schema 和 MCP annotations；同一 smoke 也会运行生成态 `scripts/check.sh`，固定独立 repo 发布/安装前的组合自检入口。生成态 manifest 会把 `scripts/package-skill.sh`、`scripts/verify-manifest.py`、`scripts/verify-source-baseline-summary.py`、`scripts/verify-runtime.py`、`scripts/wait-notify-contract-smoke.py`、`scripts/recording-to-skill-smoke.py` 和 `scripts/check.sh` 放在默认 `checks`，把会启动真实录制的 `scripts/recording-lifecycle-smoke.py` 放在 `optionalChecks`。默认自检会运行生成态 `scripts/wait-notify-contract-smoke.py`，用 missing session 验证 callback skipped / 不创建 session 文件，并用合成 completed session 验证 notify callback 能收到 `OPEN_COMPUTER_USE_EVENT_STREAM_SUPPRESSED_EVENTS_PATH`、非零退出会让 CLI 非零且返回 `reason=nonZeroExit`、callback 超时会让 CLI 非零且返回 `reason=timeout`；也会运行生成态 `scripts/recording-to-skill-smoke.py`，用临时合成 completed recording 验证安装态 validator 的 strict skill-draft gate、events-only gate 和 runtime `scaffold-skill` 草稿生成路径，不启动真实桌面录制；smoke 还会显式运行生成态 `scripts/recording-lifecycle-smoke.py`，通过当前构建出的 runtime 创建最小 recording，覆盖重复 start 返回同一 active session、stop 幂等和停止后的 status，再用安装态 validator 校验 session 文件；生成态 `.github/workflows/ci.yml` 仍只调用不启动真实录制的 `check.sh`，并会被校验使用 SHA-pinned actions 且会在安装发布版 runtime 后调用同一自检。截图上下文和官方 Codex bundle surface 对比仍然保持 opt-in，分别通过 `OPEN_COMPUTER_USE_EVENT_STREAM_MATRIX_SCREENSHOTS=1` 和 `OPEN_COMPUTER_USE_EVENT_STREAM_MATRIX_OFFICIAL=1` 打开，避免默认 CI 依赖当前桌面截图状态或本机官方 bundle。

Record & Replay baseline artifact check 默认用 stub evidence 跑 `scripts/run-record-and-replay-baseline-smoke.sh --summary-json <path>` 的 runner 级测试，确认落盘 JSON 与 stdout 的最终摘要一致；同一测试也会确认 runner 在生成摘要后调用 summary audit，且 audit 输出只走 stderr，不改变 stdout / 文件中的最终 summary 合同。测试还会打开 `--require-official-golden`，确认缺 required official successful recording fixture 时仍写出失败摘要并保留非零退出码。默认 CI 还会运行 `scripts/test-record-and-replay-baseline-summary-audit.py`，用合成摘要覆盖 `scripts/check-record-and-replay-baseline-summary.py` 的默认 / 严格 / 预期 strict missing 审计口径：默认要求顶层 `baseline=record-and-replay`、顶层 `ok` 与 `usableBaseline && officialGoldenRequirementSatisfied` 一致，顶层 `checks` 声明包含所有必需 baseline smoke / compare / preflight / standalone 检查且不带未知或重复 check，并在失败时通过 `declaredChecks.missingRequired`、`declaredChecks.unknown` 和 `declaredChecks.duplicates` 报告具体名称；允许 usable standalone baseline 缺 official golden，但必须保持 `officialSuccessfulRecordingEquivalenceReady=false`；`--require-official-golden` 必须要求 official golden gate 和 equivalence ready；`--allow-strict-official-golden-missing` 只允许 strict summary 因 required official scenario missing / not-ready 失败，同时继续要求 baseline evidence 完整、无 coverage errors，并输出 `checkedStrictOfficialGoldenMissingFailure` 与 `checkedStrictMissingGoldenHasRequiredGap` evidence。审计会直接检查 event-stream matrix、截图上下文、真实输入 action smoke、official fixture set gate、fixture ingest pipeline、official surface、no-active response、raw-timeout boundary、official capture / OCU pairing preflight、baseline audit Make target、source standalone repo 和 npm staged repo evidence；source / npm staged standalone evidence 也必须包含 `checkedManifestContract=true`、`checkedSourceBaselineSummaryEvidence=true`、`checkedSourceBaselineSummaryOfficialGoldenState=true`、`checkedOfficialEvidenceAuditManifest=true`、`checkedOfficialFixtureSetComparePolicyManifest=true` 和 `checkedNotifySuppressedEventsPathEnv=true`，分别证明生成 repo 的 `scripts/verify-manifest.py` / `manifestContract` 会自校验 manifest、生成 repo README/manifest 保留 `make record-and-replay-baseline-audit`、`make record-and-replay-official-golden-gate-audit`、`make record-and-replay-baseline-audit-targets-smoke`、默认 baseline artifact、默认 strict artifact、`RNR_BASELINE_SUMMARY_JSON` / `RNR_OFFICIAL_GOLDEN_SUMMARY_JSON` 变量名、`strictOfficialGoldenExpectedFailureAudit` 命令、`copiedBaselineSummaryEvidence=evidence/source-baseline-summary.json` 的 official golden 状态自洽检查、`officialEvidence.sourceRepoBaselineChecks.officialFixtureSetGate.sameScenarioComparePolicy` 的 AX diff / suppressed stream 强对比策略，以及 `verifiesSummaryArtifactSeparation=true` / `verifiesSummaryEnvVarIsolation=true` 隔离声明，并证明 notify callback 能拿到 suppressed stream handoff path。同一 audit smoke 也会断言 builder 产出的顶层 `checks` 与 `scripts/record_and_replay_baseline_contract.py` 的 shared contract 顺序完全一致，并篡改顶层 `checks`、派生状态，确认缺失、未知、重复 check，或 `requiresOfficialGoldenCapture`、`standaloneRepoBaselineReady`、`officialSuccessfulRecordingEquivalenceReady`、golden complete 与 required gaps / coverage errors 组合不一致时会失败；还会篡改 `nextActions` commands，确认 required capture packet 的 Make/verify/inspect/import/`record-and-replay-official-golden-gate-audit` strict audit step、recommended capture packet set 的 Make/verify/inspect/import/`ingest-ocu-candidates.sh`、standalone source baseline audit、scaffold/check/lifecycle 命令缺失时会失败；其中 standalone source baseline audit 对应 `checkedStandaloneNextActionBaselineAuditCommand`。`scripts/test-record-and-replay-baseline-audit-make-targets.py` 还会用 `make -n` 守住 `record-and-replay-baseline-audit` / `record-and-replay-official-golden-gate-audit` 两个 Make 包装入口确实传递 `--summary-json`，且 strict 入口传递 `--require-official-golden`；默认 CI 运行该 smoke 时会额外设置外层 `RNR_BASELINE_SUMMARY_JSON=/tmp/ocu-rnr-ci-outer-summary.json` 和 `RNR_OFFICIAL_GOLDEN_SUMMARY_JSON=/tmp/ocu-rnr-ci-outer-golden-summary.json`，确认脚本内部默认路径检查不会被调用方环境污染，同时 dry-run smoke 也会通过命令行覆盖反向变量，确认 `RNR_OFFICIAL_GOLDEN_SUMMARY_JSON` 不影响 baseline audit、`RNR_BASELINE_SUMMARY_JSON` 不影响 strict audit；`scripts/test-record-and-replay-official-golden-capture-preflight.py` 会守住 capture packet 的 `capture-contract.json`、`verify-inputs.sh` semantic guard、packet set 的 `verify-all.sh`、根级 `ingest-ocu-candidates.sh`、inspect/import placeholder guard、`strict-golden-gate.sh` 指向 audit target 和批量 preflight-all 行为，其中 `checkedCapturePacketInputSemanticGuard` / `checkedOfficialCapturePacketInputSemanticGuard` 证明 status JSON 必须带 handoff path evidence、transcript enabled 时必须带 MCP transcript evidence，`checkedOfficialCapturePacketStrictAuditHandoff` 证明采样包不会退回只跑不落盘的 strict gate；完整 baseline runner 也会消费这些 smoke 输出，在最终摘要的 `evidence.preflightPipelines` 写入 baseline audit target、baseline 默认/自定义 summary path、baseline 忽略 strict summary 变量、strict 默认/自定义 summary path、strict 忽略 baseline summary 变量、strict 独立 summary path、official capture packet、capture packet strict audit handoff、capture packet input semantic guard、recommended packet set OCU candidate handoff 和 OCU pairing evidence，缺失时 `usableBaseline=false`，且落盘 summary 的 artifact audit 会再次直接检查这些 preflight evidence、其它 usable baseline 子证据、派生状态、顶层 `checks` 和 `nextActions` command handoff。这样 release / standalone audit 依赖的 `--summary-json`、standalone/npm evidence、official capture packet wrapper、状态语义、检查声明、strict 预期失败摘要和下一步命令不是只靠完整 opt-in baseline 手工覆盖。

Recommended official capture packet set 还必须在根级 `capture-packets.json` 写入 `captureContracts` / `captureContractPaths`，并通过 `checkedOfficialCapturePacketSetContractManifest` 进入 `evidence.preflightPipelines`。这条 CI 证据证明批量采样包保留每个 scenario 的 expected action event、expected `endReason`、handoff path evidence 和 transcript requirement，后续独立 repo 或 skill 可以直接消费集合级合同，不需要靠 README 或遍历子目录推断。

Official capture packet / packet set 还必须暴露机器可读 `postCaptureWorkflow`。默认 CI 的 preflight smoke 会输出 `checkedCapturePacketPostCaptureWorkflow=true`、`checkedCapturePacketWorkflowVerifier=true`、`checkedCapturePacketSetPostCaptureWorkflow=true` 和 `checkedCapturePacketSetWorkflowVerifier=true`，baseline summary 投影为 `checkedOfficialCapturePacketPostCaptureWorkflow`、`checkedOfficialCapturePacketWorkflowVerifier`、`checkedOfficialCapturePacketSetPostCaptureWorkflow` 与 `checkedOfficialCapturePacketSetWorkflowVerifier`，artifact audit 通过对应 evidence 守住录制后替换 hosted JSON、verify、inspect、import、coverage / fixture-set gate、可选 OCU candidate ingest、strict audit 和 strict expected-failure audit 的有序 handoff，也守住 `verify-workflow.sh` 对 input / command / wrapper 文件一致性的校验。

Codex-hosted official capture 的 transcript gate 按官方 skill 流程要求 `event_stream_start`、active `event_stream_status`、`event_stream_stop` 和 final `event_stream_status` response shape；不要求额外 `repeatStartResponseShape`。`make record-and-replay-official-capture-finalizer-smoke` 运行 `scripts/test-record-and-replay-official-capture-finalizer.py`，用合成 hosted JSON 验证 `scripts/finalize-record-and-replay-official-capture-packet.py` 可以把 start/status/stop/final-status JSON 写入 packet inputs、生成 `mcp-transcript.json`，并通过 `verify-workflow.sh` / `verify-inputs.sh`；这条 smoke 不启动官方录制。

Official capture packet 还必须暴露 `strict-expected-failure-audit.sh`。默认 CI 的 preflight smoke 会输出 `checkedCapturePacketStrictExpectedFailureAuditHandoff=true`，baseline summary 投影为 `checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff`，artifact audit 通过 `checkedOfficialCapturePacketStrictExpectedFailureAuditHandoffEvidence` 守住 `--allow-strict-official-golden-missing` 审计入口，避免 required official golden 尚缺时只能人工判断 strict 失败摘要是否符合预期。

Standalone source summary verifier 也会继承这条证据。生成 repo 的 `evidence/source-baseline-summary.json` 会保留 `preflightPipelines.checkedOfficialCapturePacketSetContractManifest`、`preflightPipelines.checkedOfficialCapturePacketPostCaptureWorkflow`、`preflightPipelines.checkedOfficialCapturePacketWorkflowVerifier`、`preflightPipelines.checkedOfficialCapturePacketSetPostCaptureWorkflow`、`preflightPipelines.checkedOfficialCapturePacketSetWorkflowVerifier`、`preflightPipelines.checkedOfficialCapturePacketStrictAuditHandoff` 和 `preflightPipelines.checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff`，`scripts/verify-source-baseline-summary.py` 会输出 `checkedSourceBaselineSummaryOfficialGoldenState=true`、`checkedSourceBaselineSummaryCapturePacketSetContractManifest=true`、`checkedSourceBaselineSummaryCapturePacketPostCaptureWorkflow=true`、`checkedSourceBaselineSummaryCapturePacketWorkflowVerifier=true`、`checkedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow=true`、`checkedSourceBaselineSummaryCapturePacketSetWorkflowVerifier=true`、`checkedSourceBaselineSummaryCapturePacketStrictAuditHandoff=true` 与 `checkedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff=true`；source scaffold smoke、npm staged scaffold smoke、baseline summary 和 artifact audit 都消费这些字段，避免独立 repo 自检只证明 source summary 存在，却漏掉 official golden 状态自洽检查、recommended packet set 的集合级 contract manifest、录制后的 post-capture workflow、workflow verifier、strict audit summary artifact 刷新 handoff，或 strict 缺样本 expected-failure 审计 handoff。

Record & Replay npm package build 也守住同一个 source baseline summary artifact。`node ./scripts/npm/build-packages.mjs` 打包 `open-computer-use` 时必须复制 `dist/record-and-replay-baseline-summary.json`，因为安装态 `scaffold-record-and-replay-skill-repo` 会把它投影成生成 repo 内的 `evidence/source-baseline-summary.json`；如果该 artifact 缺失，build 会失败并提示 `Missing Record & Replay baseline summary artifact`，同时要求先运行 `make record-and-replay-baseline-audit` 再构建 npm 包。`scripts/test-npm-record-and-replay-skill-repo-scaffold.mjs` 会临时移走该 artifact 验证负例，避免 npm 制品静默漏带 baseline evidence，等到独立 repo 自检才失败。

Skill 打包也在默认 CI 中运行，确保 `skills/*/SKILL.md` 的 frontmatter、zip 根目录、`.skill` alias 和 `dist/skills/package-manifest.json` 的多 skill manifest 结构持续可用。Record & Replay standalone generated repo 还会在默认 `scripts/check.sh` 里运行 `scripts/verify-package-artifact.py`，打开生成的 `.skill` archive，确认 `.skill` alias 与 zip 字节一致、archive 路径只在预期 skill 目录下、packaged `SKILL.md` frontmatter 和 Record & Replay handoff 片段仍存在，并把 `checkedPackageArtifact=true` 写入 source / npm staged scaffold smoke、baseline summary 和 artifact audit，避免独立 repo 只证明文件存在却没有证明可安装制品内容。

`.github/workflows/ci.yml` 只调用 `scripts/ci.sh`，避免 GitHub Actions 和本地验证入口分叉。`docs-check`、`repo-hygiene` 和 `supply-chain-security` workflow 是轻量补充门禁；所有 `uses:` 都必须继续 pin 到 40 位 commit SHA。

## 默认 release 产物

当前 release 流水线会产出：

- `dist/release/release-manifest.json`
- `dist/release/npm/open-computer-use-<version>.tgz`
- `dist/release/npm/open-computer-use-mcp-<version>.tgz`
- `dist/release/npm/open-codex-computer-use-mcp-<version>.tgz`
- `dist/release/cursor-motion/CursorMotion-<version>.dmg`
- GitHub Actions 中上传的 npm release artifact
- GitHub Releases 中和 tag 对齐的 `CursorMotion-<version>.dmg`

也就是说，即使项目还没进入更复杂的部署阶段，仓库现在也已经同时具备了一条真实可复用的 npm 制品封装链路，以及一条由 git tag 驱动的 macOS app DMG 交付链路。
