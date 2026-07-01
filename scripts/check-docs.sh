#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required_files=(
  "AGENTS.md"
  "README.md"
  "CONTRIBUTING.md"
  "docs/REPO_COLLAB_GUIDE.md"
  "docs/HISTORY_GUIDE.md"
  "docs/PLANS_GUIDE.md"
  "docs/ARCHITECTURE.md"
  "docs/CICD.md"
  "docs/DESIGN.md"
  "docs/PRODUCT_SENSE.md"
  "docs/QUALITY_SCORE.md"
  "docs/RELIABILITY.md"
  "docs/SECURITY.md"
  "docs/SUPPLY_CHAIN_SECURITY.md"
  "docs/design-docs/core-beliefs.md"
  "docs/design-docs/index.md"
  "docs/design-docs/record-and-replay-handoff.md"
  "docs/design-docs/record-and-replay-official-golden-capture.md"
  "docs/design-docs/record-and-replay-replication.md"
  "docs/product-specs/index.md"
  "docs/references/README.md"
  "docs/references/codex-computer-use-reverse-engineering/record-and-replay-event-stream.md"
  "docs/references/codex-computer-use-reverse-engineering/fixtures/record-and-replay-event-stream-surface-1.0.857.json"
  "docs/references/codex-computer-use-reverse-engineering/fixtures/record-and-replay-official-no-active-status-stop-1.0.857.json"
  "docs/references/codex-computer-use-reverse-engineering/fixtures/record-and-replay-official-raw-start-timeout-1.0.857.json"
  "docs/generated/README.md"
  "docs/exec-plans/templates/execution-plan.md"
  "docs/exec-plans/tech-debt-tracker.md"
  "docs/histories/template.md"
  "docs/releases/feature-release-notes.md"
  "skills/open-computer-use-record-and-replay/SKILL.md"
  "skills/open-computer-use/references/record-and-replay.md"
)

missing=0

for path in "${required_files[@]}"; do
  if [[ ! -f "${repo_root}/${path}" ]]; then
    echo "缺少必要文件: ${path}"
    missing=1
  fi
done

for dir in docs/exec-plans/active docs/exec-plans/completed docs/histories; do
  if [[ ! -d "${repo_root}/${dir}" ]]; then
    echo "缺少必要目录: ${dir}"
    missing=1
  fi
done

if ! grep -q "docs/" "${repo_root}/AGENTS.md"; then
  echo "AGENTS.md 应明确指向 docs/，说明它是仓库知识的正式来源"
  missing=1
fi

doc_contracts=(
  $'README.md\trecord-and-replay-baseline-audit\t英文 README 应声明 Record & Replay baseline audit artifact 入口'
  $'README.md\trecord-and-replay-official-golden-capture-packet\t英文 README 应声明 official golden capture packet 入口'
  $'README.md\tfinalize-record-and-replay-official-capture-packet.py\t英文 README 应声明 hosted official capture finalizer 入口'
  $'README.md\t--allow-strict-official-golden-missing\t英文 README 应声明 strict expected-failure summary audit 入口'
  $'README.md\tstrict-expected-failure-audit.sh\t英文 README 应声明 capture packet strict expected-failure wrapper'
  $'README.zh-CN.md\trecord-and-replay-baseline-audit\t中文 README 应声明 Record & Replay baseline audit artifact 入口'
  $'README.zh-CN.md\trecord-and-replay-official-golden-capture-packet\t中文 README 应声明 official golden capture packet 入口'
  $'README.zh-CN.md\tfinalize-record-and-replay-official-capture-packet.py\t中文 README 应声明 hosted official capture finalizer 入口'
  $'README.zh-CN.md\t--allow-strict-official-golden-missing\t中文 README 应声明 strict expected-failure summary audit 入口'
  $'README.zh-CN.md\tstrict-expected-failure-audit.sh\t中文 README 应声明 capture packet strict expected-failure wrapper'
  $'docs/design-docs/record-and-replay-handoff.md\tingest-ocu-candidates.sh\tRecord & Replay handoff 短入口应声明 recommended packet set 的 OCU candidate 批量 handoff'
  $'docs/design-docs/record-and-replay-official-golden-capture.md\tingest-ocu-candidates.sh\t官方 golden 采集入口应声明 recommended packet set 的 OCU candidate 批量 handoff'
  $'docs/design-docs/record-and-replay-official-golden-capture.md\trecord-and-replay-official-golden-gate-audit\t官方 golden 采集入口应声明采样后刷新 strict audit artifact'
  $'docs/design-docs/record-and-replay-replication.md\tingest-ocu-candidates.sh\tRecord & Replay 设计文档应声明 recommended packet set 的 OCU candidate handoff'
  $'docs/CICD.md\tingest-ocu-candidates.sh\tCI 文档应声明 baseline artifact audit 会守住 recommended packet set 的 OCU candidate handoff'
  $'docs/design-docs/record-and-replay-handoff.md\tsourceRepoBaselineAudit\tRecord & Replay handoff 短入口应声明 standalone source repo audit manifest handoff'
  $'docs/design-docs/record-and-replay-handoff.md\tverifiesSummaryEnvVarIsolation\tRecord & Replay handoff 应声明 standalone source repo audit manifest 的变量隔离合同'
  $'docs/design-docs/record-and-replay-handoff.md\trecord-and-replay-official-golden-gate-summary.json\tRecord & Replay handoff 应声明 strict audit 使用独立 summary artifact'
  $'docs/design-docs/record-and-replay-handoff.md\tstrictOfficialGoldenExpectedFailureAudit\tRecord & Replay handoff 应声明 standalone manifest 的 strict expected-failure audit 字段'
  $'docs/design-docs/record-and-replay-handoff.md\tverify-manifest.py\tRecord & Replay handoff 应声明 standalone manifest self-check 脚本'
  $'docs/design-docs/record-and-replay-handoff.md\tcheckedManifestContract\tRecord & Replay handoff 应声明 standalone manifest contract evidence'
  $'docs/design-docs/record-and-replay-handoff.md\tcheckedOfficialFixtureSetComparePolicyManifest\tRecord & Replay handoff 应声明 standalone official fixture set compare policy evidence'
  $'docs/design-docs/record-and-replay-handoff.md\tcheckedSourceBaselineSummaryEvidence\tRecord & Replay handoff 应声明 standalone source baseline summary evidence'
  $'docs/design-docs/record-and-replay-handoff.md\tcheckedSourceBaselineSummaryOfficialGoldenState\tRecord & Replay handoff 应声明 standalone source summary 会守住 official golden 状态自洽 evidence'
  $'docs/design-docs/record-and-replay-handoff.md\tcheckedSourceBaselineSummaryCapturePacketSetContractManifest\tRecord & Replay handoff 应声明 standalone source summary 会守住 capture packet set contract evidence'
  $'docs/design-docs/record-and-replay-handoff.md\tcheckedSourceBaselineSummaryCapturePacketPostCaptureWorkflow\tRecord & Replay handoff 应声明 standalone source summary 会守住 capture packet post-capture workflow evidence'
  $'docs/design-docs/record-and-replay-handoff.md\tcheckedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow\tRecord & Replay handoff 应声明 standalone source summary 会守住 packet set post-capture workflow evidence'
  $'docs/design-docs/record-and-replay-handoff.md\tcheckedSourceBaselineSummaryCapturePacketStrictAuditHandoff\tRecord & Replay handoff 应声明 standalone source summary 会守住 capture packet strict audit handoff evidence'
  $'docs/design-docs/record-and-replay-handoff.md\tcheckedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff\tRecord & Replay handoff 应声明 standalone source summary 会守住 capture packet strict expected-failure audit handoff evidence'
  $'docs/design-docs/record-and-replay-handoff.md\tevidence/source-baseline-summary.json\tRecord & Replay handoff 应声明 standalone copied baseline summary evidence'
  $'docs/design-docs/record-and-replay-handoff.md\tofficialFixtureSetGate.sameScenarioComparePolicy\tRecord & Replay handoff 应声明 standalone official fixture set compare policy manifest'
  $'docs/design-docs/record-and-replay-replication.md\tsourceRepoBaselineAudit\tRecord & Replay 设计文档应声明 standalone source repo audit manifest handoff'
  $'docs/design-docs/record-and-replay-replication.md\tverifiesSummaryEnvVarIsolation\tRecord & Replay 设计文档应声明 standalone source repo audit manifest 的变量隔离合同'
  $'docs/design-docs/record-and-replay-replication.md\tRNR_OFFICIAL_GOLDEN_SUMMARY_JSON\tRecord & Replay 设计文档应声明 strict audit summary 覆盖变量'
  $'docs/design-docs/record-and-replay-replication.md\tstrictOfficialGoldenExpectedFailureAudit\tRecord & Replay 设计文档应声明 standalone manifest 的 strict expected-failure audit 字段'
  $'docs/design-docs/record-and-replay-replication.md\tmanifestContract\tRecord & Replay 设计文档应声明 standalone manifest contract check'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedManifestContract\tRecord & Replay 设计文档应声明 standalone manifest contract evidence'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedOfficialFixtureSetComparePolicyManifest\tRecord & Replay 设计文档应声明 standalone official fixture set compare policy evidence'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedSourceBaselineSummaryEvidence\tRecord & Replay 设计文档应声明 standalone source baseline summary evidence'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedSourceBaselineSummaryOfficialGoldenState\tRecord & Replay 设计文档应声明 standalone source summary 会守住 official golden 状态自洽 evidence'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedSourceBaselineSummaryCapturePacketSetContractManifest\tRecord & Replay 设计文档应声明 standalone source summary 会守住 capture packet set contract evidence'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedSourceBaselineSummaryCapturePacketPostCaptureWorkflow\tRecord & Replay 设计文档应声明 standalone source summary 会守住 capture packet post-capture workflow evidence'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow\tRecord & Replay 设计文档应声明 standalone source summary 会守住 packet set post-capture workflow evidence'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedSourceBaselineSummaryCapturePacketStrictAuditHandoff\tRecord & Replay 设计文档应声明 standalone source summary 会守住 capture packet strict audit handoff evidence'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff\tRecord & Replay 设计文档应声明 standalone source summary 会守住 capture packet strict expected-failure audit handoff evidence'
  $'docs/design-docs/record-and-replay-replication.md\tcopiedBaselineSummaryEvidence\tRecord & Replay 设计文档应声明 standalone copied baseline summary evidence manifest'
  $'docs/design-docs/record-and-replay-replication.md\tofficialFixtureSetGate.sameScenarioComparePolicy\tRecord & Replay 设计文档应声明 standalone official fixture set compare policy manifest'
  $'docs/design-docs/record-and-replay-handoff.md\t--allow-strict-official-golden-missing\tRecord & Replay handoff 应声明 strict expected-failure summary audit 入口'
  $'docs/design-docs/record-and-replay-replication.md\t--allow-strict-official-golden-missing\tRecord & Replay 设计文档应声明 strict expected-failure summary audit 入口'
  $'docs/ARCHITECTURE.md\trecord-and-replay-baseline-audit\t架构文档应声明 standalone repo source baseline audit handoff'
  $'docs/ARCHITECTURE.md\tverifiesSummaryEnvVarIsolation\t架构文档应声明 standalone source repo audit manifest 的变量隔离合同'
  $'docs/ARCHITECTURE.md\tstrictOfficialGoldenExpectedFailureAudit\t架构文档应声明 standalone manifest 的 strict expected-failure audit 字段'
  $'docs/ARCHITECTURE.md\tverify-manifest.py\t架构文档应声明 standalone manifest self-check 脚本'
  $'docs/ARCHITECTURE.md\tmanifestContract\t架构文档应声明 standalone manifest contract check'
  $'docs/ARCHITECTURE.md\tcheckedOfficialFixtureSetComparePolicyManifest\t架构文档应声明 standalone official fixture set compare policy evidence'
  $'docs/ARCHITECTURE.md\tcheckedSourceBaselineSummaryEvidence\t架构文档应声明 standalone source baseline summary evidence'
  $'docs/ARCHITECTURE.md\tcheckedSourceBaselineSummaryOfficialGoldenState\t架构文档应声明 standalone source summary 会守住 official golden 状态自洽 evidence'
  $'docs/ARCHITECTURE.md\tcheckedSourceBaselineSummaryCapturePacketSetContractManifest\t架构文档应声明 standalone source summary 会守住 capture packet set contract evidence'
  $'docs/ARCHITECTURE.md\tcheckedSourceBaselineSummaryCapturePacketPostCaptureWorkflow\t架构文档应声明 standalone source summary 会守住 capture packet post-capture workflow evidence'
  $'docs/ARCHITECTURE.md\tcheckedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow\t架构文档应声明 standalone source summary 会守住 packet set post-capture workflow evidence'
  $'docs/ARCHITECTURE.md\tcheckedSourceBaselineSummaryCapturePacketStrictAuditHandoff\t架构文档应声明 standalone source summary 会守住 capture packet strict audit handoff evidence'
  $'docs/ARCHITECTURE.md\tcheckedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff\t架构文档应声明 standalone source summary 会守住 capture packet strict expected-failure audit handoff evidence'
  $'docs/ARCHITECTURE.md\tverify-package-artifact.py\t架构文档应声明 standalone generated repo 会运行 package artifact self-check'
  $'docs/ARCHITECTURE.md\tcheckedPackageArtifact\t架构文档应声明 baseline artifact audit 会守住 standalone package artifact evidence'
  $'docs/ARCHITECTURE.md\tcopiedBaselineSummaryEvidence\t架构文档应声明 standalone copied baseline summary evidence manifest'
  $'docs/ARCHITECTURE.md\tofficialFixtureSetGate.sameScenarioComparePolicy\t架构文档应声明 standalone official fixture set compare policy manifest'
  $'docs/ARCHITECTURE.md\t--allow-strict-official-golden-missing\t架构文档应声明 strict expected-failure summary audit 入口'
  $'docs/CICD.md\tcheckedOfficialEvidenceAuditManifest\tCI 文档应声明 baseline artifact audit 会守住 standalone source audit manifest evidence'
  $'docs/CICD.md\tcheckedManifestContract\tCI 文档应声明 baseline artifact audit 会守住 standalone manifest contract evidence'
  $'docs/CICD.md\tcheckedOfficialFixtureSetComparePolicyManifest\tCI 文档应声明 baseline artifact audit 会守住 standalone official fixture set compare policy evidence'
  $'docs/CICD.md\tcheckedSourceBaselineSummaryEvidence\tCI 文档应声明 baseline artifact audit 会守住 standalone source baseline summary evidence'
  $'docs/CICD.md\tcheckedSourceBaselineSummaryOfficialGoldenState\tCI 文档应声明 baseline artifact audit 会守住 standalone source summary official golden 状态自洽 evidence'
  $'docs/CICD.md\tcheckedSourceBaselineSummaryCapturePacketSetContractManifest\tCI 文档应声明 baseline artifact audit 会守住 standalone source summary capture packet set contract evidence'
  $'docs/CICD.md\tcheckedSourceBaselineSummaryCapturePacketPostCaptureWorkflow\tCI 文档应声明 baseline artifact audit 会守住 standalone source summary capture packet post-capture workflow evidence'
  $'docs/CICD.md\tcheckedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow\tCI 文档应声明 baseline artifact audit 会守住 standalone source summary packet set post-capture workflow evidence'
  $'docs/CICD.md\tcheckedSourceBaselineSummaryCapturePacketStrictAuditHandoff\tCI 文档应声明 baseline artifact audit 会守住 standalone source summary capture packet strict audit handoff evidence'
  $'docs/CICD.md\tcheckedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff\tCI 文档应声明 baseline artifact audit 会守住 standalone source summary capture packet strict expected-failure audit handoff evidence'
  $'docs/CICD.md\tverify-package-artifact.py\tCI 文档应声明 standalone generated repo 会运行 package artifact self-check'
  $'docs/CICD.md\tcheckedPackageArtifact\tCI 文档应声明 baseline artifact audit 会守住 standalone package artifact evidence'
  $'docs/QUALITY_SCORE.md\tcheckedSourceBaselineSummaryOfficialGoldenState\t质量文档应声明 baseline artifact audit 会守住 standalone source summary official golden 状态自洽 evidence'
  $'docs/QUALITY_SCORE.md\tcheckedSourceBaselineSummaryCapturePacketSetContractManifest\t质量文档应声明 baseline artifact audit 会守住 standalone source summary capture packet set contract evidence'
  $'docs/QUALITY_SCORE.md\tcheckedSourceBaselineSummaryCapturePacketPostCaptureWorkflow\t质量文档应声明 baseline artifact audit 会守住 standalone source summary capture packet post-capture workflow evidence'
  $'docs/QUALITY_SCORE.md\tcheckedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow\t质量文档应声明 baseline artifact audit 会守住 standalone source summary packet set post-capture workflow evidence'
  $'docs/QUALITY_SCORE.md\tcheckedSourceBaselineSummaryCapturePacketStrictAuditHandoff\t质量文档应声明 baseline artifact audit 会守住 standalone source summary capture packet strict audit handoff evidence'
  $'docs/QUALITY_SCORE.md\tcheckedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff\t质量文档应声明 baseline artifact audit 会守住 standalone source summary capture packet strict expected-failure audit handoff evidence'
  $'docs/QUALITY_SCORE.md\tverify-package-artifact.py\t质量文档应声明 standalone generated repo 会运行 package artifact self-check'
  $'docs/QUALITY_SCORE.md\tcheckedPackageArtifact\t质量文档应声明 baseline artifact audit 会守住 standalone package artifact evidence'
  $'docs/CICD.md\tcopiedBaselineSummaryEvidence\tCI 文档应声明 standalone copied baseline summary evidence manifest'
  $'docs/CICD.md\tofficialFixtureSetGate.sameScenarioComparePolicy\tCI 文档应声明 standalone official fixture set compare policy manifest'
  $'docs/CICD.md\tverify-source-baseline-summary.py\tCI 文档应声明 standalone generated repo 会运行 source baseline summary self-check'
  $'docs/design-docs/record-and-replay-handoff.md\tverify-package-artifact.py\tRecord & Replay handoff 应声明 standalone generated repo 会运行 package artifact self-check'
  $'docs/design-docs/record-and-replay-handoff.md\tcheckedPackageArtifact\tRecord & Replay handoff 应声明 standalone package artifact evidence'
  $'docs/design-docs/record-and-replay-replication.md\tverify-package-artifact.py\tRecord & Replay 设计文档应声明 standalone generated repo 会运行 package artifact self-check'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedPackageArtifact\tRecord & Replay 设计文档应声明 standalone package artifact evidence'
  $'docs/CICD.md\tMissing Record & Replay baseline summary artifact\tCI 文档应声明 npm package build 缺 baseline summary artifact 时失败'
  $'docs/design-docs/record-and-replay-handoff.md\tMissing Record & Replay baseline summary artifact\tRecord & Replay handoff 应声明 npm package build 缺 baseline summary artifact 时失败'
  $'docs/design-docs/record-and-replay-replication.md\tMissing Record & Replay baseline summary artifact\tRecord & Replay 设计文档应声明 npm package build 缺 baseline summary artifact 时失败'
  $'docs/CICD.md\tverify-manifest.py\tCI 文档应声明 standalone generated repo 会运行 manifest self-check'
  $'docs/CICD.md\tverifiesSummaryEnvVarIsolation\tCI 文档应声明 standalone source audit manifest 的变量隔离合同'
  $'docs/CICD.md\tcheckedStandaloneNextActionBaselineAuditCommand\tCI 文档应声明 baseline artifact audit 会守住 standalone nextActions 的 source baseline audit 命令'
  $'docs/QUALITY_SCORE.md\tcheckedMissingGoldenNextActionStrictAuditStep\t质量文档应声明 baseline artifact audit 会守住 missing golden nextActions 的 strict audit 命令'
  $'docs/exec-plans/active/20260626-record-and-replay-event-stream.md\tcheckedMissingGoldenNextActionStrictAuditStep\t执行计划应声明 baseline artifact audit 会守住 missing golden nextActions 的 strict audit 命令'
  $'docs/design-docs/record-and-replay-official-golden-capture.md\tcapture-contract.json\t官方 golden 采集入口应声明 capture packet semantic contract'
  $'docs/design-docs/record-and-replay-official-golden-capture.md\tcheckedOfficialCapturePacketStrictAuditHandoff\t官方 golden 采集入口应声明 capture packet strict audit handoff evidence'
  $'docs/design-docs/record-and-replay-official-golden-capture.md\tcheckedOfficialCapturePacketStrictExpectedFailureAuditHandoff\t官方 golden 采集入口应声明 capture packet strict expected-failure audit handoff evidence'
  $'docs/design-docs/record-and-replay-official-golden-capture.md\tpostCaptureWorkflow\t官方 golden 采集入口应声明 capture packet post-capture workflow contract'
  $'docs/design-docs/record-and-replay-official-golden-capture.md\tverify-workflow.sh\t官方 golden 采集入口应声明 capture packet workflow verifier'
  $'docs/design-docs/record-and-replay-official-golden-capture.md\tfinalize-record-and-replay-official-capture-packet.py\t官方 golden 采集入口应声明 hosted official capture finalizer'
  $'docs/design-docs/record-and-replay-official-golden-capture.md\tfinalStatusResponseShape\t官方 golden 采集入口应声明 hosted final status response shape'
  $'docs/design-docs/record-and-replay-official-golden-capture.md\tcheckedOfficialCapturePacketPostCaptureWorkflow\t官方 golden 采集入口应声明 capture packet post-capture workflow evidence'
  $'docs/design-docs/record-and-replay-official-golden-capture.md\tcheckedOfficialCapturePacketWorkflowVerifier\t官方 golden 采集入口应声明 capture packet workflow verifier evidence'
  $'docs/design-docs/record-and-replay-official-golden-capture.md\tcheckedOfficialCapturePacketSetPostCaptureWorkflow\t官方 golden 采集入口应声明 packet set post-capture workflow evidence'
  $'docs/design-docs/record-and-replay-official-golden-capture.md\tcheckedOfficialCapturePacketSetWorkflowVerifier\t官方 golden 采集入口应声明 packet set workflow verifier evidence'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedOfficialCapturePacketInputSemanticGuard\tRecord & Replay 设计文档应声明 capture packet semantic guard evidence'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedOfficialCapturePacketStrictAuditHandoff\tRecord & Replay 设计文档应声明 capture packet strict audit handoff evidence'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedOfficialCapturePacketStrictExpectedFailureAuditHandoff\tRecord & Replay 设计文档应声明 capture packet strict expected-failure audit handoff evidence'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedOfficialCapturePacketPostCaptureWorkflow\tRecord & Replay 设计文档应声明 capture packet post-capture workflow evidence'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedOfficialCapturePacketWorkflowVerifier\tRecord & Replay 设计文档应声明 capture packet workflow verifier evidence'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedOfficialCapturePacketSetPostCaptureWorkflow\tRecord & Replay 设计文档应声明 packet set post-capture workflow evidence'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedOfficialCapturePacketSetWorkflowVerifier\tRecord & Replay 设计文档应声明 packet set workflow verifier evidence'
  $'docs/design-docs/record-and-replay-handoff.md\tcheckedOfficialCapturePacketInputSemanticGuard\tRecord & Replay handoff 应声明 capture packet semantic guard evidence'
  $'docs/design-docs/record-and-replay-handoff.md\tcheckedOfficialCapturePacketStrictAuditHandoff\tRecord & Replay handoff 应声明 capture packet strict audit handoff evidence'
  $'docs/design-docs/record-and-replay-handoff.md\tcheckedOfficialCapturePacketStrictExpectedFailureAuditHandoff\tRecord & Replay handoff 应声明 capture packet strict expected-failure audit handoff evidence'
  $'docs/design-docs/record-and-replay-handoff.md\tcheckedOfficialCapturePacketPostCaptureWorkflow\tRecord & Replay handoff 应声明 capture packet post-capture workflow evidence'
  $'docs/design-docs/record-and-replay-handoff.md\tcheckedOfficialCapturePacketWorkflowVerifier\tRecord & Replay handoff 应声明 capture packet workflow verifier evidence'
  $'docs/design-docs/record-and-replay-handoff.md\tcheckedOfficialCapturePacketSetPostCaptureWorkflow\tRecord & Replay handoff 应声明 packet set post-capture workflow evidence'
  $'docs/design-docs/record-and-replay-handoff.md\tcheckedOfficialCapturePacketSetWorkflowVerifier\tRecord & Replay handoff 应声明 packet set workflow verifier evidence'
  $'docs/ARCHITECTURE.md\tcheckedOfficialCapturePacketInputSemanticGuard\t架构文档应声明 capture packet semantic guard evidence'
  $'docs/ARCHITECTURE.md\tcheckedOfficialCapturePacketStrictAuditHandoff\t架构文档应声明 capture packet strict audit handoff evidence'
  $'docs/ARCHITECTURE.md\tcheckedOfficialCapturePacketPostCaptureWorkflow\t架构文档应声明 capture packet post-capture workflow evidence'
  $'docs/ARCHITECTURE.md\tcheckedOfficialCapturePacketWorkflowVerifier\t架构文档应声明 capture packet workflow verifier evidence'
  $'docs/ARCHITECTURE.md\tfinalize-record-and-replay-official-capture-packet.py\t架构文档应声明 hosted official capture finalizer'
  $'docs/ARCHITECTURE.md\tcheckedOfficialCapturePacketSetPostCaptureWorkflow\t架构文档应声明 packet set post-capture workflow evidence'
  $'docs/ARCHITECTURE.md\tcheckedOfficialCapturePacketSetWorkflowVerifier\t架构文档应声明 packet set workflow verifier evidence'
  $'docs/CICD.md\tcheckedOfficialCapturePacketInputSemanticGuard\tCI 文档应声明 baseline artifact audit 会守住 capture packet semantic guard evidence'
  $'docs/CICD.md\tcheckedOfficialCapturePacketStrictAuditHandoff\tCI 文档应声明 baseline artifact audit 会守住 capture packet strict audit handoff evidence'
  $'docs/CICD.md\tcheckedOfficialCapturePacketStrictExpectedFailureAuditHandoff\tCI 文档应声明 baseline artifact audit 会守住 capture packet strict expected-failure audit handoff evidence'
  $'docs/CICD.md\tcheckedOfficialCapturePacketPostCaptureWorkflow\tCI 文档应声明 baseline artifact audit 会守住 capture packet post-capture workflow evidence'
  $'docs/CICD.md\tcheckedOfficialCapturePacketWorkflowVerifier\tCI 文档应声明 baseline artifact audit 会守住 capture packet workflow verifier evidence'
  $'docs/CICD.md\trecord-and-replay-official-capture-finalizer-smoke\tCI 文档应声明 hosted official capture finalizer smoke'
  $'docs/CICD.md\tcheckedOfficialCapturePacketSetPostCaptureWorkflow\tCI 文档应声明 baseline artifact audit 会守住 packet set post-capture workflow evidence'
  $'docs/CICD.md\tcheckedOfficialCapturePacketSetWorkflowVerifier\tCI 文档应声明 baseline artifact audit 会守住 packet set workflow verifier evidence'
  $'docs/QUALITY_SCORE.md\tcheckedOfficialCapturePacketInputSemanticGuard\t质量文档应声明 baseline artifact audit 会守住 capture packet semantic guard evidence'
  $'docs/QUALITY_SCORE.md\tcheckedOfficialCapturePacketStrictAuditHandoff\t质量文档应声明 baseline artifact audit 会守住 capture packet strict audit handoff evidence'
  $'docs/QUALITY_SCORE.md\tcheckedOfficialCapturePacketStrictExpectedFailureAuditHandoff\t质量文档应声明 baseline artifact audit 会守住 capture packet strict expected-failure audit handoff evidence'
  $'docs/QUALITY_SCORE.md\tcheckedOfficialCapturePacketPostCaptureWorkflow\t质量文档应声明 baseline artifact audit 会守住 capture packet post-capture workflow evidence'
  $'docs/QUALITY_SCORE.md\tcheckedOfficialCapturePacketWorkflowVerifier\t质量文档应声明 baseline artifact audit 会守住 capture packet workflow verifier evidence'
  $'docs/QUALITY_SCORE.md\tfinalize-record-and-replay-official-capture-packet.py\t质量文档应声明 hosted official capture finalizer'
  $'docs/QUALITY_SCORE.md\tcheckedOfficialCapturePacketSetPostCaptureWorkflow\t质量文档应声明 baseline artifact audit 会守住 packet set post-capture workflow evidence'
  $'docs/QUALITY_SCORE.md\tcheckedOfficialCapturePacketSetWorkflowVerifier\t质量文档应声明 baseline artifact audit 会守住 packet set workflow verifier evidence'
  $'docs/exec-plans/active/20260626-record-and-replay-event-stream.md\tcheckedOfficialCapturePacketInputSemanticGuard\t执行计划应声明 capture packet semantic guard evidence'
  $'docs/exec-plans/active/20260626-record-and-replay-event-stream.md\tcheckedOfficialCapturePacketStrictAuditHandoff\t执行计划应声明 capture packet strict audit handoff evidence'
  $'docs/exec-plans/active/20260626-record-and-replay-event-stream.md\tcheckedOfficialCapturePacketStrictExpectedFailureAuditHandoff\t执行计划应声明 capture packet strict expected-failure audit handoff evidence'
  $'docs/exec-plans/active/20260626-record-and-replay-event-stream.md\tcheckedOfficialCapturePacketPostCaptureWorkflow\t执行计划应声明 capture packet post-capture workflow evidence'
  $'docs/exec-plans/active/20260626-record-and-replay-event-stream.md\tcheckedOfficialCapturePacketWorkflowVerifier\t执行计划应声明 capture packet workflow verifier evidence'
  $'docs/exec-plans/active/20260626-record-and-replay-event-stream.md\tcheckedOfficialCapturePacketSetPostCaptureWorkflow\t执行计划应声明 packet set post-capture workflow evidence'
  $'docs/exec-plans/active/20260626-record-and-replay-event-stream.md\tcheckedOfficialCapturePacketSetWorkflowVerifier\t执行计划应声明 packet set workflow verifier evidence'
  $'docs/exec-plans/active/20260626-record-and-replay-event-stream.md\tcheckedSourceBaselineSummaryCapturePacketPostCaptureWorkflow\t执行计划应声明 standalone source summary capture packet post-capture workflow evidence'
  $'docs/exec-plans/active/20260626-record-and-replay-event-stream.md\tcheckedSourceBaselineSummaryCapturePacketWorkflowVerifier\t执行计划应声明 standalone source summary capture packet workflow verifier evidence'
  $'docs/exec-plans/active/20260626-record-and-replay-event-stream.md\tcheckedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow\t执行计划应声明 standalone source summary packet set post-capture workflow evidence'
  $'docs/exec-plans/active/20260626-record-and-replay-event-stream.md\tcheckedSourceBaselineSummaryCapturePacketSetWorkflowVerifier\t执行计划应声明 standalone source summary packet set workflow verifier evidence'
  $'docs/exec-plans/active/20260626-record-and-replay-event-stream.md\tcheckedSourceBaselineSummaryCapturePacketStrictAuditHandoff\t执行计划应声明 standalone source summary capture packet strict audit handoff evidence'
  $'docs/exec-plans/active/20260626-record-and-replay-event-stream.md\tcheckedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff\t执行计划应声明 standalone source summary capture packet strict expected-failure audit handoff evidence'
  $'docs/design-docs/record-and-replay-official-golden-capture.md\tcheckedOfficialCapturePacketSetContractManifest\t官方 golden 采集入口应声明 capture packet set contract manifest evidence'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedOfficialCapturePacketSetContractManifest\tRecord & Replay 设计文档应声明 capture packet set contract manifest evidence'
  $'docs/design-docs/record-and-replay-handoff.md\tcheckedOfficialCapturePacketSetContractManifest\tRecord & Replay handoff 应声明 capture packet set contract manifest evidence'
  $'docs/ARCHITECTURE.md\tcheckedOfficialCapturePacketSetContractManifest\t架构文档应声明 capture packet set contract manifest evidence'
  $'docs/CICD.md\tcheckedOfficialCapturePacketSetContractManifest\tCI 文档应声明 baseline artifact audit 会守住 capture packet set contract manifest evidence'
  $'docs/QUALITY_SCORE.md\tcheckedOfficialCapturePacketSetContractManifest\t质量文档应声明 baseline artifact audit 会守住 capture packet set contract manifest evidence'
  $'docs/exec-plans/active/20260626-record-and-replay-event-stream.md\tcheckedOfficialCapturePacketSetContractManifest\t执行计划应声明 capture packet set contract manifest evidence'
  $'docs/CICD.md\tstrictOfficialGoldenExpectedFailureAudit\tCI 文档应声明 standalone manifest 的 strict expected-failure audit 字段'
  $'docs/CICD.md\t--allow-strict-official-golden-missing\tCI 文档应声明 strict expected-failure summary audit 入口'
  $'docs/design-docs/record-and-replay-handoff.md\tOPEN_COMPUTER_USE_EVENT_STREAM_SUPPRESSED_EVENTS_PATH\tRecord & Replay handoff 应声明 notify callback 传递 suppressed events path'
  $'docs/design-docs/record-and-replay-replication.md\tcheckedNotifySuppressedEventsPathEnv\tRecord & Replay 设计文档应声明 baseline 会守住 notify suppressed events path evidence'
  $'docs/CICD.md\tcheckedNotifySuppressedEventsPathEnv\tCI 文档应声明 baseline artifact audit 会守住 notify suppressed events path evidence'
)

for contract in "${doc_contracts[@]}"; do
  IFS=$'\t' read -r path needle message <<<"${contract}"
  if [[ ! -f "${repo_root}/${path}" ]]; then
    continue
  fi
  if ! grep -Fq -- "${needle}" "${repo_root}/${path}"; then
    echo "${message}: ${path} 缺少 ${needle}"
    missing=1
  fi
done

if [[ "${missing}" -ne 0 ]]; then
  exit 1
fi

echo "文档骨架检查通过"
