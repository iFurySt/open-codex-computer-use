#!/usr/bin/env node

import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..");

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    ...options,
  });
  if (result.status !== 0) {
    throw new Error(
      [
        `${command} ${args.join(" ")} failed with exit code ${result.status ?? "unknown"}`,
        result.stdout,
        result.stderr,
      ].filter(Boolean).join("\n"),
    );
  }
  return result;
}

function runAllowFailure(command, args, options = {}) {
  return spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    ...options,
  });
}

function readJSON(filePath) {
  return JSON.parse(readFileSync(filePath, "utf8"));
}

function writeJSON(filePath, value) {
  writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function parseJSONObjectLines(stdout) {
  return stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.startsWith("{"))
    .map((line) => JSON.parse(line));
}

const tmp = mkdtempSync(path.join(tmpdir(), "ocu-npm-rnr-skill-repo-"));
const baselineSummaryArtifact = path.join(repoRoot, "dist", "record-and-replay-baseline-summary.json");
const baselineSummaryOriginal = readFileSync(baselineSummaryArtifact, "utf8");

function writeCurrentBaselineSummaryArtifact() {
  const baselineSummary = JSON.parse(baselineSummaryOriginal);
  baselineSummary.evidence ??= {};
  baselineSummary.evidence.fixtureIngestPipelines ??= {};
  baselineSummary.evidence.fixtureIngestPipelines.checkedOfficialSessionDirectoryPathHandoff = true;
  writeJSON(baselineSummaryArtifact, baselineSummary);
  return baselineSummary;
}

try {
  const baselineSummaryBackup = `${baselineSummaryArtifact}.bak-test-${process.pid}`;
  renameSync(baselineSummaryArtifact, baselineSummaryBackup);
  try {
    const missingBaselineSummary = runAllowFailure("node", [
      path.join(repoRoot, "scripts", "npm", "build-packages.mjs"),
      "--skip-build",
      "--out-dir",
      path.join(tmp, "missing-baseline-summary-npm"),
      "--package",
      "open-computer-use",
    ]);
    if (missingBaselineSummary.status === 0) {
      throw new Error("npm package build unexpectedly succeeded without the Record & Replay baseline summary artifact");
    }
    if (!missingBaselineSummary.stderr.includes("Missing Record & Replay baseline summary artifact")) {
      throw new Error(missingBaselineSummary.stderr || missingBaselineSummary.stdout);
    }
    if (!missingBaselineSummary.stderr.includes("make record-and-replay-baseline-audit")) {
      throw new Error(missingBaselineSummary.stderr || missingBaselineSummary.stdout);
    }
  } finally {
    renameSync(baselineSummaryBackup, baselineSummaryArtifact);
  }
  const currentBaselineSummary = writeCurrentBaselineSummaryArtifact();
  const sourceHasSuccessfulRecordingGolden =
    currentBaselineSummary.status?.officialSuccessfulRecordingGoldenComplete === true;

  const npmOutDir = path.join(tmp, "npm");
  const generatedRepo = path.join(tmp, "generated-rnr-skill-repo");
  const build = run("node", [
    path.join(repoRoot, "scripts", "npm", "build-packages.mjs"),
    "--skip-build",
    "--out-dir",
    npmOutDir,
    "--package",
    "open-computer-use",
  ]);
  if (build.stderr) {
    process.stderr.write(build.stderr);
  }

  const packageRoot = path.join(npmOutDir, "open-computer-use");
  const launcher = path.join(packageRoot, "bin", "open-computer-use");
  if (!existsSync(path.join(packageRoot, "scripts", "record_and_replay_scenarios.py"))) {
    throw new Error("npm package is missing scripts/record_and_replay_scenarios.py");
  }
  if (!existsSync(path.join(packageRoot, "dist", "record-and-replay-baseline-summary.json"))) {
    throw new Error("npm package is missing dist/record-and-replay-baseline-summary.json");
  }

  const help = run("node", [launcher, "help", "scaffold-record-and-replay-skill-repo"]);
  if (!help.stdout.includes("open-computer-use scaffold-record-and-replay-skill-repo --output-dir <dir>")) {
    throw new Error(help.stdout);
  }
  if (!help.stdout.includes("Generates a standalone Record & Replay thin skill repo")) {
    throw new Error(help.stdout);
  }
  if (!help.stdout.includes("Python 3 must be available")) {
    throw new Error(help.stdout);
  }
  if (help.stdout.includes("updates a local MCP or plugin config")) {
    throw new Error(help.stdout);
  }

  const missingPython = runAllowFailure("node", [
    launcher,
    "scaffold-record-and-replay-skill-repo",
    "--output-dir",
    path.join(tmp, "missing-python-output"),
  ], {
    env: {
      ...process.env,
      PYTHON: path.join(tmp, "missing-python3"),
    },
  });
  if (missingPython.status === 0) {
    throw new Error("scaffold unexpectedly succeeded with missing PYTHON");
  }
  if (!missingPython.stderr.includes("Python 3 is required to run")) {
    throw new Error(missingPython.stderr);
  }
  if (!missingPython.stderr.includes("PYTHON=/path/to/python3")) {
    throw new Error(missingPython.stderr);
  }

  const fakePython2 = path.join(tmp, "python2-fake");
  writeFileSync(fakePython2, "#!/bin/sh\necho 'Python 2.7.18'\nexit 0\n", "utf8");
  chmodSync(fakePython2, 0o755);
  const python2 = runAllowFailure("node", [
    launcher,
    "scaffold-record-and-replay-skill-repo",
    "--output-dir",
    path.join(tmp, "python2-output"),
  ], {
    env: {
      ...process.env,
      PYTHON: fakePython2,
    },
  });
  if (python2.status === 0) {
    throw new Error("scaffold unexpectedly accepted Python 2");
  }
  if (!python2.stderr.includes("Python 3 is required to run")) {
    throw new Error(python2.stderr);
  }

  const validateHelp = run("node", [launcher, "event-stream", "validate", "--help"]);
  if (!validateHelp.stdout.includes("--require-skill-draft")) {
    throw new Error(
      [
        "staged open-computer-use binary does not support event-stream validate --require-skill-draft",
        "Rebuild dist native artifacts before running make npm-record-and-replay-skill-repo-smoke.",
        validateHelp.stdout,
      ].join("\n"),
    );
  }

  const preflightSession = path.join(tmp, "declared-path-preflight", "session");
  mkdirSync(preflightSession, { recursive: true });
  const preflightMetadataPath = path.join(preflightSession, "metadata.json");
  const preflightSessionPath = path.join(preflightSession, "session.json");
  const preflightEventsPath = path.join(preflightSession, "events.jsonl");
  const preflightSuppressedEventsPath = path.join(preflightSession, "suppressed.jsonl");
  const preflightEvents = [
    { type: "session.started", timestamp: "2026-06-27T00:00:00.000Z" },
    {
      type: "mouse.click",
      timestamp: "2026-06-27T00:00:01.000Z",
      location: { x: 20, y: 30 },
      targetAccessibilityElement: { role: "AXButton", title: "Continue" },
    },
    {
      type: "session.ended",
      timestamp: "2026-06-27T00:00:02.000Z",
      endReason: "recording_controls_stopped",
    },
  ];
  writeFileSync(preflightEventsPath, `${preflightEvents.map((event) => JSON.stringify(event)).join("\n")}\n`, "utf8");
  writeFileSync(preflightSuppressedEventsPath, "", "utf8");
  const preflightMetadata = {
    sessionId: "npm-declared-path-preflight",
    state: "stopped",
    active: false,
    endReason: "recording_controls_stopped",
    eventCount: preflightEvents.length,
    suppressedEventCount: 0,
    metadataPath: preflightMetadataPath,
    sessionPath: preflightSessionPath,
    eventsPath: preflightEventsPath,
    suppressedEventsPath: preflightSuppressedEventsPath,
  };
  writeJSON(preflightMetadataPath, preflightMetadata);
  writeJSON(preflightSessionPath, preflightMetadata);
  const declaredPathPreflight = run("node", [
    launcher,
    "event-stream",
    "validate",
    "--json",
    "--strict-ocu",
    "--require-skill-draft",
    preflightMetadataPath,
  ]);
  const declaredPathPayload = JSON.parse(declaredPathPreflight.stdout);
  const declaredPaths = declaredPathPayload.declaredPaths ?? {};
  const missingDeclaredPath = ["metadataPath", "sessionPath", "eventsPath", "suppressedEventsPath"].find((key) => {
    return declaredPaths[key]?.exists !== true;
  });
  if (missingDeclaredPath) {
    throw new Error(
      [
        "staged open-computer-use binary does not emit strict declaredPaths evidence.",
        "Rebuild dist native artifacts before running make npm-record-and-replay-skill-repo-smoke.",
        JSON.stringify(declaredPathPayload, null, 2),
      ].join("\n"),
    );
  }

  const externalScreenshotSession = path.join(tmp, "screenshot-containment-preflight", "session");
  mkdirSync(externalScreenshotSession, { recursive: true });
  const externalScreenshot = path.join(tmp, "outside-session-screenshot.png");
  writeFileSync(externalScreenshot, "not a real png, only path containment evidence\n", "utf8");
  const externalScreenshotMetadataPath = path.join(externalScreenshotSession, "metadata.json");
  const externalScreenshotSessionPath = path.join(externalScreenshotSession, "session.json");
  const externalScreenshotEventsPath = path.join(externalScreenshotSession, "events.jsonl");
  const externalScreenshotSuppressedEventsPath = path.join(externalScreenshotSession, "suppressed.jsonl");
  const externalScreenshotEvents = [
    { type: "session.started", timestamp: "2026-06-27T00:00:00.000Z" },
    {
      type: "AX.focusedWindowChanged",
      timestamp: "2026-06-27T00:00:01.000Z",
      accessibilityInspectorPayload: {
        screenshotNeededForContext: true,
        screenshotAvailable: true,
        screenshotPath: externalScreenshot,
      },
    },
    {
      type: "mouse.click",
      timestamp: "2026-06-27T00:00:02.000Z",
      location: { x: 20, y: 30 },
      targetAccessibilityElement: { role: "AXButton", title: "Continue" },
    },
    {
      type: "session.ended",
      timestamp: "2026-06-27T00:00:03.000Z",
      endReason: "recording_controls_stopped",
    },
  ];
  writeFileSync(
    externalScreenshotEventsPath,
    `${externalScreenshotEvents.map((event) => JSON.stringify(event)).join("\n")}\n`,
    "utf8",
  );
  writeFileSync(externalScreenshotSuppressedEventsPath, "", "utf8");
  const externalScreenshotMetadata = {
    sessionId: "npm-screenshot-containment-preflight",
    state: "stopped",
    active: false,
    endReason: "recording_controls_stopped",
    eventCount: externalScreenshotEvents.length,
    suppressedEventCount: 0,
    metadataPath: externalScreenshotMetadataPath,
    sessionPath: externalScreenshotSessionPath,
    eventsPath: externalScreenshotEventsPath,
    suppressedEventsPath: externalScreenshotSuppressedEventsPath,
  };
  writeJSON(externalScreenshotMetadataPath, externalScreenshotMetadata);
  writeJSON(externalScreenshotSessionPath, externalScreenshotMetadata);
  const screenshotContainmentPreflight = runAllowFailure("node", [
    launcher,
    "event-stream",
    "validate",
    "--json",
    "--strict-ocu",
    externalScreenshotMetadataPath,
  ]);
  if (screenshotContainmentPreflight.status === 0) {
    throw new Error(
      [
        "staged open-computer-use binary does not reject screenshotPath outside the session directory.",
        "Rebuild dist native artifacts before running make npm-record-and-replay-skill-repo-smoke.",
        screenshotContainmentPreflight.stdout,
      ].join("\n"),
    );
  }
  const screenshotContainmentPayload = JSON.parse(
    screenshotContainmentPreflight.stdout || screenshotContainmentPreflight.stderr,
  );
  const expectedScreenshotContainmentError =
    `screenshotPath from event line 2 must stay inside session directory: ${externalScreenshot}`;
  if (!screenshotContainmentPayload.errors?.includes(expectedScreenshotContainmentError)) {
    throw new Error(
      [
        "staged open-computer-use binary does not emit screenshotPath containment evidence.",
        "Rebuild dist native artifacts before running make npm-record-and-replay-skill-repo-smoke.",
        JSON.stringify(screenshotContainmentPayload, null, 2),
      ].join("\n"),
    );
  }

  const scaffold = run("node", [
    launcher,
    "scaffold-record-and-replay-skill-repo",
    "--output-dir",
    generatedRepo,
  ]);
  const scaffoldPayload = JSON.parse(scaffold.stdout);
  if (scaffoldPayload.ok !== true) {
    throw new Error(scaffold.stdout);
  }

  const readme = readFileSync(path.join(generatedRepo, "README.md"), "utf8");
  const verifyManifestPath = path.join(generatedRepo, "scripts", "verify-manifest.py");
  const verifySourceSummaryPath = path.join(generatedRepo, "scripts", "verify-source-baseline-summary.py");
  const verifyReadmePath = path.join(generatedRepo, "scripts", "verify-readme-handoff.py");
  const verifyManifest = readFileSync(verifyManifestPath, "utf8");
  const verifyRuntime = readFileSync(path.join(generatedRepo, "scripts", "verify-runtime.py"), "utf8");
  const manifestPath = path.join(generatedRepo, "record-and-replay-skill-repo.json");
  const sourceSummaryPath = path.join(generatedRepo, "evidence", "source-baseline-summary.json");
  const manifest = readJSON(manifestPath);
  const sourceSummary = readJSON(sourceSummaryPath);
  if (!readme.includes("Python 3 must be available as `python3`")) {
    throw new Error("generated README.md is missing the Python 3 prerequisite");
  }
  if (!readme.includes("PYTHON=/path/to/python3")) {
    throw new Error("generated README.md is missing the npm launcher Python override guidance");
  }
  if (!readme.includes("make record-and-replay-baseline-audit")) {
    throw new Error("generated README.md is missing the source repo baseline audit handoff");
  }
  if (!readme.includes("make record-and-replay-official-golden-gate-audit")) {
    throw new Error("generated README.md is missing the strict official golden audit handoff");
  }
  if (!readme.includes("dist/record-and-replay-baseline-summary.json")) {
    throw new Error("generated README.md is missing the baseline summary artifact handoff");
  }
  if (!readme.includes("evidence/source-baseline-summary.json")) {
    throw new Error("generated README.md is missing copied baseline summary evidence handoff");
  }
  if (!readme.includes("dist/record-and-replay-official-golden-gate-summary.json")) {
    throw new Error("generated README.md is missing the strict official golden summary artifact handoff");
  }
  if (!readme.includes("--allow-strict-official-golden-missing")) {
    throw new Error("generated README.md is missing the strict expected-failure audit handoff");
  }
  if (!verifyManifest.includes("checkedManifestContract")) {
    throw new Error("generated verify-manifest.py is missing manifest contract evidence");
  }
  if (!verifyManifest.includes("strictOfficialGoldenExpectedFailureAudit")) {
    throw new Error("generated verify-manifest.py is missing strict expected-failure audit validation");
  }
  if (!readFileSync(verifySourceSummaryPath, "utf8").includes("checkedSourceBaselineSummaryEvidence")) {
    throw new Error("generated verify-source-baseline-summary.py is missing source summary evidence validation");
  }
  if (!verifyRuntime.includes("OPEN_COMPUTER_USE_RUNTIME_VERIFY_TIMEOUT_SECONDS")) {
    throw new Error("generated verify-runtime.py is missing runtime timeout override support");
  }
  if (!verifyRuntime.includes("runtimeVersion=")) {
    throw new Error("generated verify-runtime.py is missing runtime version timeout diagnostics");
  }
  if (!verifyRuntime.includes("Set OPEN_COMPUTER_USE_CLI to the current open-computer-use runtime")) {
    throw new Error("generated verify-runtime.py is missing stale runtime guidance");
  }
  const expectedOfficialEvidence = {
    baselineVersion: "record-and-replay/1.0.857",
    nonRecordingSurfaceFixture: "record-and-replay-event-stream-surface-1.0.857.json",
    noActiveStatusStopFixture: "record-and-replay-official-no-active-status-stop-1.0.857.json",
    hostlessRawStartTimeoutFixture: "record-and-replay-official-raw-start-timeout-1.0.857.json",
    sourceRepoBaselineChecks: {
      baselineContract: "baseline-contract-smoke",
      officialRawStartTimeout: "official-raw-start-timeout-fixture-smoke",
      officialFixtureSetGate: {
        check: "official-fixture-set-smoke",
        sameScenarioComparePolicy: {
          requiresAxDiffEvidence: true,
          requiresSameAxDiffMarkers: true,
          requiresSameSuppressedEventSequence: true,
          requiresSameSuppressedSchema: true,
        },
      },
      officialFixtureIngest: {
        check: "official-fixture-ingest-smoke",
        requiredEvidence: [
          "checkedOfficialSessionDirectoryPathHandoff",
        ],
      },
      officialGoldenCapturePreflight: {
        check: "official-golden-capture-preflight-smoke",
        requiredEvidence: [
          "checkedOfficialCapturePacketInputSemanticGuard",
          "checkedOfficialCapturePacketSetContractManifest",
          "checkedOfficialCapturePacketPostCaptureWorkflow",
          "checkedOfficialCapturePacketWorkflowVerifier",
          "checkedOfficialCapturePacketSetPostCaptureWorkflow",
          "checkedOfficialCapturePacketSetWorkflowVerifier",
          "checkedOfficialCapturePacketStrictAuditHandoff",
          "checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff",
        ],
      },
      ocuCandidatePairingPreflight: "ocu-candidate-pairing-preflight-smoke",
    },
    sourceRepoBaselineAudit: {
      usableBaseline: "make record-and-replay-baseline-audit",
      strictOfficialGoldenGate: "make record-and-replay-official-golden-gate-audit",
      auditTargetDryRunSmoke: "make record-and-replay-baseline-audit-targets-smoke",
      baselineSummaryArtifact: "dist/record-and-replay-baseline-summary.json",
      copiedBaselineSummaryEvidence: "evidence/source-baseline-summary.json",
      strictOfficialGoldenSummaryArtifact: "dist/record-and-replay-official-golden-gate-summary.json",
      baselineSummaryEnvVar: "RNR_BASELINE_SUMMARY_JSON",
      strictOfficialGoldenSummaryEnvVar: "RNR_OFFICIAL_GOLDEN_SUMMARY_JSON",
      strictOfficialGoldenExpectedFailureAudit: "scripts/check-record-and-replay-baseline-summary.py dist/record-and-replay-official-golden-gate-summary.json --allow-strict-official-golden-missing",
      verifiesSummaryArtifactSeparation: true,
      verifiesSummaryEnvVarIsolation: true,
    },
    standaloneRepoBoundary: {
      defaultChecksDoNotStartOfficialRecording: true,
      preflightScriptsRemainInOpenComputerUseRepo: true,
      doesNotCopyOpenComputerUseRuntimeSource: true,
    },
    hasSuccessfulRecordingGolden: sourceHasSuccessfulRecordingGolden,
    requiredSuccessfulRecordingScenarios: [
      "simple-action-stop",
    ],
    recommendedSuccessfulRecordingScenarios: [
      "simple-action-stop",
      "keyboard-input-stop",
      "drag-stop",
      "cancel",
      "timeout",
    ],
    scenarioRecipes: {
      "simple-action-stop": {
        scenario: "simple-action-stop",
        priority: "required",
        captureGoal: "Record one low-risk left click and finish with the Record & Replay Done control.",
        userAction: "Click a stable, harmless UI target once, then click Done in the official recording controls.",
        expectedActionEvents: ["mouse.click"],
        expectedEndReason: "recording_controls_stopped",
        expectedEvidence: [
          "event_stream_start/status/stop hosted MCP response shape",
          "metadata/session/events/suppressed handoff paths",
          "one session.started as the first event",
          "one session.ended as the final event",
          "mouse.click action event",
          "AX payload for the clicked target/window",
        ],
        ocuCandidateSourceKind: "run-action-smoke",
        notes: [
          "Use this as the minimum official successful recording golden fixture.",
          "Keep the clicked target harmless and easy to describe after redaction.",
        ],
      },
      "keyboard-input-stop": {
        scenario: "keyboard-input-stop",
        priority: "recommended",
        captureGoal: "Record a small text input and finish with the Record & Replay Done control.",
        userAction: "Type a short non-sensitive string into a harmless text field, then click Done.",
        expectedActionEvents: ["keyboard.text_input"],
        expectedEndReason: "recording_controls_stopped",
        expectedEvidence: [
          "keyboard.text_input action event",
          "focusedAccessibilityElement or equivalent keyboard target evidence",
          "AX payload for the edited field/window",
          "completed hosted MCP response shape",
        ],
        ocuCandidateSourceKind: "recording-required",
        notes: [
          "Do not use synthetic --run-action-smoke for this scenario; macOS may filter synthetic keyboard events.",
          "Use non-sensitive placeholder text only.",
        ],
      },
      "drag-stop": {
        scenario: "drag-stop",
        priority: "recommended",
        captureGoal: "Record one low-risk drag gesture and finish with the Record & Replay Done control.",
        userAction: "Drag a harmless target a short distance, release it, then click Done.",
        expectedActionEvents: ["mouse.drag"],
        expectedEndReason: "recording_controls_stopped",
        expectedEvidence: [
          "mouse.drag action event",
          "start/end location evidence",
          "targetAccessibilityElement or equivalent drag target evidence",
          "AX payload for the affected window",
          "completed hosted MCP response shape",
        ],
        ocuCandidateSourceKind: "run-action-smoke",
        notes: [
          "Use a fixture or harmless UI target where drag has no external side effects.",
        ],
      },
      cancel: {
        scenario: "cancel",
        priority: "recommended",
        captureGoal: "Record the official cancellation path.",
        userAction: "Start recording, optionally perform no action, then click Discard/Cancel in the recording controls.",
        expectedActionEvents: [],
        expectedEndReason: "recording_controls_cancelled",
        expectedEvidence: [
          "session.ended endReason=recording_controls_cancelled",
          "cancelled hosted MCP/status response shape when available",
          "no skill creation from the cancelled recording",
        ],
        ocuCandidateSourceKind: "recording-required",
        notes: [
          "Cancelled recordings are evidence for lifecycle semantics only and must not be used to scaffold a skill.",
        ],
      },
      timeout: {
        scenario: "timeout",
        priority: "recommended",
        captureGoal: "Record the official maximum-duration timeout path.",
        userAction: "Start recording and let the official time limit expire without using Done or Discard.",
        expectedActionEvents: [],
        expectedEndReason: null,
        expectedEvidence: [
          "one session.started as the first event",
          "one session.ended as the final event",
          "official timeout endReason once observed",
          "completed or timeout hosted MCP/status response shape",
        ],
        ocuCandidateSourceKind: "recording-required",
        notes: [
          "OCU currently uses recording_time_limit_reached as a baseline; official timeout endReason still needs calibration.",
          "This sample may be slow because the official limit is expected to be long.",
        ],
      },
    },
    successfulRecordingGoldenRequiredFor: [
      "session file schema equivalence",
      "event field schema equivalence",
      "AX compact diff algorithm equivalence",
      "screenshot trigger equivalence",
      "timeout endReason equivalence",
    ],
  };
  if (JSON.stringify(manifest.officialEvidence) !== JSON.stringify(expectedOfficialEvidence)) {
    throw new Error(JSON.stringify(manifest, null, 2));
  }
  const expectedReadmeScenarioList = [
    "The minimum required official successful recording scenario is",
    "`simple-action-stop`. The recommended calibration set is",
    "`simple-action-stop`, `keyboard-input-stop`, `drag-stop`, `cancel`, and `timeout`.",
  ].join("\n");
  if (!readme.includes(expectedReadmeScenarioList)) {
    throw new Error(
      [
        "Generated standalone README scenario list drifted.",
        expectedReadmeScenarioList,
        readme,
      ].join("\n"),
    );
  }
  if (manifest.extensionLayer?.waitNotify?.callbackFailureMakesCliFail !== true) {
    throw new Error(JSON.stringify(manifest, null, 2));
  }
  if (manifest.extensionLayer?.waitNotify?.callbackTimeoutMakesCliFail !== true) {
    throw new Error(JSON.stringify(manifest, null, 2));
  }
  if (
    !manifest.extensionLayer?.waitNotify?.environmentVariables?.includes(
      "OPEN_COMPUTER_USE_EVENT_STREAM_SUPPRESSED_EVENTS_PATH",
    )
  ) {
    throw new Error(JSON.stringify(manifest, null, 2));
  }
  if (manifest.checks?.skillWorkflow !== "scripts/verify-skill-workflow.py") {
    throw new Error(JSON.stringify(manifest, null, 2));
  }
  if (manifest.checks?.manifestContract !== "scripts/verify-manifest.py") {
    throw new Error(JSON.stringify(manifest, null, 2));
  }
  if (manifest.checks?.packageArtifact !== "scripts/verify-package-artifact.py") {
    throw new Error(JSON.stringify(manifest, null, 2));
  }
  if (manifest.checks?.sourceBaselineSummaryEvidence !== "scripts/verify-source-baseline-summary.py") {
    throw new Error(JSON.stringify(manifest, null, 2));
  }
  if (manifest.checks?.readmeHandoffContract !== "scripts/verify-readme-handoff.py") {
    throw new Error(JSON.stringify(manifest, null, 2));
  }
  if (manifest.mcpServer?.rejectedRequestsDoNotCreateSessionFiles !== true) {
    throw new Error(JSON.stringify(manifest, null, 2));
  }
  const recordingToSkill = manifest.recordingToSkill;
  const strictValidation = recordingToSkill?.strictValidation;
  if (
    strictValidation?.command !==
      "event-stream validate --json --strict-ocu --require-skill-draft <metadataPath-or-sessionPath>" ||
    strictValidation?.requiresMetadataSessionAlias !== true ||
    strictValidation?.requiresScreenshotPathsInsideSession !== true ||
    strictValidation?.requiresSkillDraftReady !== true ||
    JSON.stringify(strictValidation?.requiresDeclaredHandoffPaths) !==
      JSON.stringify(["metadataPath", "sessionPath", "eventsPath", "suppressedEventsPath"])
  ) {
    throw new Error(JSON.stringify(manifest, null, 2));
  }
  const eventsOnlyValidation = recordingToSkill?.eventsOnlyValidation;
  if (
    eventsOnlyValidation?.command !==
      "event-stream validate --json --require-skill-draft <eventsPath>" ||
    eventsOnlyValidation?.provesMetadataSessionAlias !== false ||
    eventsOnlyValidation?.provesDeclaredHandoffPaths !== false
  ) {
    throw new Error(JSON.stringify(manifest, null, 2));
  }
  const scaffoldSkill = recordingToSkill?.scaffoldSkill;
  if (
    scaffoldSkill?.command !==
      "event-stream scaffold-skill --json <metadataPath-or-sessionPath-or-eventsPath>" ||
    scaffoldSkill?.runsSkillDraftValidationGate !== true
  ) {
    throw new Error(JSON.stringify(manifest, null, 2));
  }
  if (recordingToSkill?.rejectsCancelledRecordings !== true) {
    throw new Error(JSON.stringify(manifest, null, 2));
  }

  const manifestCheck = run("python3", [verifyManifestPath], {
    cwd: generatedRepo,
  });
  const manifestPayload = JSON.parse(manifestCheck.stdout);
  if (
    manifestPayload.ok !== true ||
    manifestPayload.checkedManifestContract !== true ||
    manifestPayload.checkedStrictExpectedFailureAudit !== true ||
    manifestPayload.checkedOfficialFixtureSetComparePolicy !== true ||
    manifestPayload.checkedSourceBaselineSummaryEvidenceCheck !== true
  ) {
    throw new Error(manifestCheck.stdout);
  }
  try {
    const mutatedManifest = JSON.parse(JSON.stringify(manifest));
    mutatedManifest.officialEvidence.sourceRepoBaselineAudit.strictOfficialGoldenExpectedFailureAudit = "missing";
    writeJSON(manifestPath, mutatedManifest);
    const invalidManifest = runAllowFailure("python3", [verifyManifestPath], {
      cwd: generatedRepo,
    });
    if (invalidManifest.status === 0) {
      throw new Error(invalidManifest.stdout);
    }
    if (!invalidManifest.stderr.includes("strict expected-failure audit command drifted")) {
      throw new Error(invalidManifest.stderr || invalidManifest.stdout);
    }
  } finally {
    writeJSON(manifestPath, manifest);
  }

  const sourceSummaryCheck = run("python3", [verifySourceSummaryPath], {
    cwd: generatedRepo,
  });
  const sourceSummaryPayload = JSON.parse(sourceSummaryCheck.stdout);
  if (
    sourceSummaryPayload.ok !== true ||
    sourceSummaryPayload.checkedSourceBaselineSummaryEvidence !== true ||
    sourceSummaryPayload.checkedSourceBaselineSummaryOfficialGoldenState !== true ||
    sourceSummaryPayload.checkedSourceBaselineSummaryOfficialGoldenGap !== !sourceHasSuccessfulRecordingGolden ||
    sourceSummaryPayload.checkedSourceBaselineSummaryOfficialGoldenComplete !== sourceHasSuccessfulRecordingGolden ||
    sourceSummaryPayload.checkedSourceBaselineSummaryOfficialSessionDirectoryPathHandoff !== true ||
    sourceSummaryPayload.checkedSourceBaselineSummaryCapturePacketPostCaptureWorkflow !== true ||
    sourceSummaryPayload.checkedSourceBaselineSummaryCapturePacketWorkflowVerifier !== true ||
    sourceSummaryPayload.checkedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow !== true ||
    sourceSummaryPayload.checkedSourceBaselineSummaryCapturePacketSetWorkflowVerifier !== true ||
    sourceSummaryPayload.checkedSourceBaselineSummaryCapturePacketStrictAuditHandoff !== true ||
    sourceSummaryPayload.checkedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff !== true
  ) {
    throw new Error(sourceSummaryCheck.stdout);
  }
  if (
    sourceSummary.status?.usableBaseline !== true ||
    sourceSummary.status?.standaloneRepoBaselineReady !== true ||
    sourceSummary.status?.officialSuccessfulRecordingGoldenComplete !== sourceHasSuccessfulRecordingGolden ||
    sourceSummary.evidence?.fixtureIngestPipelines?.checkedOfficialSessionDirectoryPathHandoff !== true ||
    sourceSummary.evidence?.preflightPipelines?.checkedOfficialCapturePacketSetContractManifest !== true ||
    sourceSummary.evidence?.preflightPipelines?.checkedOfficialCapturePacketPostCaptureWorkflow !== true ||
    sourceSummary.evidence?.preflightPipelines?.checkedOfficialCapturePacketWorkflowVerifier !== true ||
    sourceSummary.evidence?.preflightPipelines?.checkedOfficialCapturePacketSetPostCaptureWorkflow !== true ||
    sourceSummary.evidence?.preflightPipelines?.checkedOfficialCapturePacketSetWorkflowVerifier !== true ||
    sourceSummary.evidence?.preflightPipelines?.checkedOfficialCapturePacketStrictAuditHandoff !== true ||
    sourceSummary.evidence?.preflightPipelines?.checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff !== true ||
    sourceSummary.evidence?.standaloneSkillRepo?.checkedOfficialFixtureSetComparePolicyManifest !== true ||
    sourceSummary.evidence?.npmStagedSkillRepo?.checkedOfficialFixtureSetComparePolicyManifest !== true
  ) {
    throw new Error(JSON.stringify(sourceSummary, null, 2));
  }
  if (!sourceHasSuccessfulRecordingGolden) {
    try {
      const mutatedSourceSummary = JSON.parse(JSON.stringify(sourceSummary));
      mutatedSourceSummary.status.officialGoldenGatePassed = true;
      mutatedSourceSummary.status.officialSuccessfulRecordingGoldenComplete = true;
      mutatedSourceSummary.status.officialSuccessfulRecordingEquivalenceReady = true;
      mutatedSourceSummary.status.requiresOfficialGoldenCapture = false;
      mutatedSourceSummary.status.missingRequiredOfficialSuccessfulRecordingScenarios = [];
      mutatedSourceSummary.status.notReadyRequiredOfficialSuccessfulRecordingScenarios = [];
      mutatedSourceSummary.status.officialFixtureCoverageErrors = [];
      writeJSON(sourceSummaryPath, mutatedSourceSummary);
      const completedSourceSummary = run("python3", [verifySourceSummaryPath], {
        cwd: generatedRepo,
      });
      const completedPayload = JSON.parse(completedSourceSummary.stdout);
      if (
        completedPayload.checkedSourceBaselineSummaryOfficialGoldenState !== true ||
        completedPayload.checkedSourceBaselineSummaryOfficialGoldenGap !== false ||
        completedPayload.checkedSourceBaselineSummaryOfficialGoldenComplete !== true
      ) {
        throw new Error(completedSourceSummary.stdout);
      }
    } finally {
      writeJSON(sourceSummaryPath, sourceSummary);
    }
  }
  try {
    const mutatedSourceSummary = JSON.parse(JSON.stringify(sourceSummary));
    mutatedSourceSummary.status.officialGoldenGatePassed = true;
    mutatedSourceSummary.status.officialSuccessfulRecordingGoldenComplete = true;
    mutatedSourceSummary.status.officialSuccessfulRecordingEquivalenceReady = true;
    mutatedSourceSummary.status.requiresOfficialGoldenCapture = false;
    mutatedSourceSummary.status.missingRequiredOfficialSuccessfulRecordingScenarios = ["simple-action-stop"];
    mutatedSourceSummary.status.notReadyRequiredOfficialSuccessfulRecordingScenarios = [];
    mutatedSourceSummary.status.officialFixtureCoverageErrors = [];
    writeJSON(sourceSummaryPath, mutatedSourceSummary);
    const invalidSourceSummary = runAllowFailure("python3", [verifySourceSummaryPath], {
      cwd: generatedRepo,
    });
    if (invalidSourceSummary.status === 0) {
      throw new Error(invalidSourceSummary.stdout);
    }
    if (
      !invalidSourceSummary.stderr.includes(
        "official golden state must be either current required gap or completed equivalence",
      )
    ) {
      throw new Error(invalidSourceSummary.stderr || invalidSourceSummary.stdout);
    }
  } finally {
    writeJSON(sourceSummaryPath, sourceSummary);
  }
  try {
    const mutatedSourceSummary = JSON.parse(JSON.stringify(sourceSummary));
    mutatedSourceSummary.evidence.fixtureIngestPipelines.checkedOfficialSessionDirectoryPathHandoff = false;
    writeJSON(sourceSummaryPath, mutatedSourceSummary);
    const invalidSourceSummary = runAllowFailure("python3", [verifySourceSummaryPath], {
      cwd: generatedRepo,
    });
    if (invalidSourceSummary.status === 0) {
      throw new Error(invalidSourceSummary.stdout);
    }
    if (!invalidSourceSummary.stderr.includes("official sessionDirectoryPath handoff evidence missing")) {
      throw new Error(invalidSourceSummary.stderr || invalidSourceSummary.stdout);
    }
  } finally {
    writeJSON(sourceSummaryPath, sourceSummary);
  }
  try {
    const mutatedSourceSummary = JSON.parse(JSON.stringify(sourceSummary));
    mutatedSourceSummary.evidence.preflightPipelines.checkedOfficialCapturePacketSetContractManifest = false;
    writeJSON(sourceSummaryPath, mutatedSourceSummary);
    const invalidSourceSummary = runAllowFailure("python3", [verifySourceSummaryPath], {
      cwd: generatedRepo,
    });
    if (invalidSourceSummary.status === 0) {
      throw new Error(invalidSourceSummary.stdout);
    }
    if (!invalidSourceSummary.stderr.includes("capture packet set contract manifest evidence missing")) {
      throw new Error(invalidSourceSummary.stderr || invalidSourceSummary.stdout);
    }
  } finally {
    writeJSON(sourceSummaryPath, sourceSummary);
  }
  try {
    const mutatedSourceSummary = JSON.parse(JSON.stringify(sourceSummary));
    mutatedSourceSummary.evidence.preflightPipelines.checkedOfficialCapturePacketPostCaptureWorkflow = false;
    writeJSON(sourceSummaryPath, mutatedSourceSummary);
    const invalidSourceSummary = runAllowFailure("python3", [verifySourceSummaryPath], {
      cwd: generatedRepo,
    });
    if (invalidSourceSummary.status === 0) {
      throw new Error(invalidSourceSummary.stdout);
    }
    if (!invalidSourceSummary.stderr.includes("capture packet post-capture workflow evidence missing")) {
      throw new Error(invalidSourceSummary.stderr || invalidSourceSummary.stdout);
    }
  } finally {
    writeJSON(sourceSummaryPath, sourceSummary);
  }
  try {
    const mutatedSourceSummary = JSON.parse(JSON.stringify(sourceSummary));
    mutatedSourceSummary.evidence.preflightPipelines.checkedOfficialCapturePacketSetPostCaptureWorkflow = false;
    writeJSON(sourceSummaryPath, mutatedSourceSummary);
    const invalidSourceSummary = runAllowFailure("python3", [verifySourceSummaryPath], {
      cwd: generatedRepo,
    });
    if (invalidSourceSummary.status === 0) {
      throw new Error(invalidSourceSummary.stdout);
    }
    if (!invalidSourceSummary.stderr.includes("capture packet set post-capture workflow evidence missing")) {
      throw new Error(invalidSourceSummary.stderr || invalidSourceSummary.stdout);
    }
  } finally {
    writeJSON(sourceSummaryPath, sourceSummary);
  }
  try {
    const mutatedSourceSummary = JSON.parse(JSON.stringify(sourceSummary));
    mutatedSourceSummary.evidence.preflightPipelines.checkedOfficialCapturePacketWorkflowVerifier = false;
    writeJSON(sourceSummaryPath, mutatedSourceSummary);
    const invalidSourceSummary = runAllowFailure("python3", [verifySourceSummaryPath], {
      cwd: generatedRepo,
    });
    if (invalidSourceSummary.status === 0) {
      throw new Error(invalidSourceSummary.stdout);
    }
    if (!invalidSourceSummary.stderr.includes("capture packet workflow verifier evidence missing")) {
      throw new Error(invalidSourceSummary.stderr || invalidSourceSummary.stdout);
    }
  } finally {
    writeJSON(sourceSummaryPath, sourceSummary);
  }
  try {
    const mutatedSourceSummary = JSON.parse(JSON.stringify(sourceSummary));
    mutatedSourceSummary.evidence.preflightPipelines.checkedOfficialCapturePacketSetWorkflowVerifier = false;
    writeJSON(sourceSummaryPath, mutatedSourceSummary);
    const invalidSourceSummary = runAllowFailure("python3", [verifySourceSummaryPath], {
      cwd: generatedRepo,
    });
    if (invalidSourceSummary.status === 0) {
      throw new Error(invalidSourceSummary.stdout);
    }
    if (!invalidSourceSummary.stderr.includes("capture packet set workflow verifier evidence missing")) {
      throw new Error(invalidSourceSummary.stderr || invalidSourceSummary.stdout);
    }
  } finally {
    writeJSON(sourceSummaryPath, sourceSummary);
  }
  try {
    const mutatedSourceSummary = JSON.parse(JSON.stringify(sourceSummary));
    mutatedSourceSummary.evidence.preflightPipelines.checkedOfficialCapturePacketStrictAuditHandoff = false;
    writeJSON(sourceSummaryPath, mutatedSourceSummary);
    const invalidSourceSummary = runAllowFailure("python3", [verifySourceSummaryPath], {
      cwd: generatedRepo,
    });
    if (invalidSourceSummary.status === 0) {
      throw new Error(invalidSourceSummary.stdout);
    }
    if (!invalidSourceSummary.stderr.includes("capture packet strict audit handoff evidence missing")) {
      throw new Error(invalidSourceSummary.stderr || invalidSourceSummary.stdout);
    }
  } finally {
    writeJSON(sourceSummaryPath, sourceSummary);
  }
  try {
    const mutatedSourceSummary = JSON.parse(JSON.stringify(sourceSummary));
    mutatedSourceSummary.evidence.preflightPipelines.checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff = false;
    writeJSON(sourceSummaryPath, mutatedSourceSummary);
    const invalidSourceSummary = runAllowFailure("python3", [verifySourceSummaryPath], {
      cwd: generatedRepo,
    });
    if (invalidSourceSummary.status === 0) {
      throw new Error(invalidSourceSummary.stdout);
    }
    if (!invalidSourceSummary.stderr.includes("capture packet strict expected-failure audit handoff evidence missing")) {
      throw new Error(invalidSourceSummary.stderr || invalidSourceSummary.stdout);
    }
  } finally {
    writeJSON(sourceSummaryPath, sourceSummary);
  }
  try {
    const mutatedManifest = JSON.parse(JSON.stringify(manifest));
    mutatedManifest.officialEvidence.sourceRepoBaselineChecks.officialFixtureSetGate
      .sameScenarioComparePolicy.requiresSameSuppressedSchema = false;
    writeJSON(manifestPath, mutatedManifest);
    const invalidManifest = runAllowFailure("python3", [verifyManifestPath], {
      cwd: generatedRepo,
    });
    if (invalidManifest.status === 0) {
      throw new Error(invalidManifest.stdout);
    }
    if (!invalidManifest.stderr.includes("official fixture set suppressed schema policy missing")) {
      throw new Error(invalidManifest.stderr || invalidManifest.stdout);
    }
  } finally {
    writeJSON(manifestPath, manifest);
  }
  try {
    const mutatedManifest = JSON.parse(JSON.stringify(manifest));
    mutatedManifest.officialEvidence.sourceRepoBaselineChecks.officialGoldenCapturePreflight.requiredEvidence =
      mutatedManifest.officialEvidence.sourceRepoBaselineChecks.officialGoldenCapturePreflight.requiredEvidence.filter(
        (value) => value !== "checkedOfficialCapturePacketSetContractManifest",
      );
    writeJSON(manifestPath, mutatedManifest);
    const invalidManifest = runAllowFailure("python3", [verifyManifestPath], {
      cwd: generatedRepo,
    });
    if (invalidManifest.status === 0) {
      throw new Error(invalidManifest.stdout);
    }
    if (!invalidManifest.stderr.includes("official capture packet set contract manifest evidence missing")) {
      throw new Error(invalidManifest.stderr || invalidManifest.stdout);
    }
  } finally {
    writeJSON(manifestPath, manifest);
  }
  try {
    const mutatedManifest = JSON.parse(JSON.stringify(manifest));
    mutatedManifest.officialEvidence.sourceRepoBaselineChecks.officialGoldenCapturePreflight.requiredEvidence =
      mutatedManifest.officialEvidence.sourceRepoBaselineChecks.officialGoldenCapturePreflight.requiredEvidence.filter(
        (value) => value !== "checkedOfficialCapturePacketPostCaptureWorkflow",
      );
    writeJSON(manifestPath, mutatedManifest);
    const invalidManifest = runAllowFailure("python3", [verifyManifestPath], {
      cwd: generatedRepo,
    });
    if (invalidManifest.status === 0) {
      throw new Error(invalidManifest.stdout);
    }
    if (!invalidManifest.stderr.includes("official capture packet post-capture workflow evidence missing")) {
      throw new Error(invalidManifest.stderr || invalidManifest.stdout);
    }
  } finally {
    writeJSON(manifestPath, manifest);
  }
  try {
    const mutatedManifest = JSON.parse(JSON.stringify(manifest));
    mutatedManifest.officialEvidence.sourceRepoBaselineChecks.officialGoldenCapturePreflight.requiredEvidence =
      mutatedManifest.officialEvidence.sourceRepoBaselineChecks.officialGoldenCapturePreflight.requiredEvidence.filter(
        (value) => value !== "checkedOfficialCapturePacketWorkflowVerifier",
      );
    writeJSON(manifestPath, mutatedManifest);
    const invalidManifest = runAllowFailure("python3", [verifyManifestPath], {
      cwd: generatedRepo,
    });
    if (invalidManifest.status === 0) {
      throw new Error(invalidManifest.stdout);
    }
    if (!invalidManifest.stderr.includes("official capture packet workflow verifier evidence missing")) {
      throw new Error(invalidManifest.stderr || invalidManifest.stdout);
    }
  } finally {
    writeJSON(manifestPath, manifest);
  }
  try {
    const mutatedManifest = JSON.parse(JSON.stringify(manifest));
    mutatedManifest.officialEvidence.sourceRepoBaselineChecks.officialGoldenCapturePreflight.requiredEvidence =
      mutatedManifest.officialEvidence.sourceRepoBaselineChecks.officialGoldenCapturePreflight.requiredEvidence.filter(
        (value) => value !== "checkedOfficialCapturePacketSetPostCaptureWorkflow",
      );
    writeJSON(manifestPath, mutatedManifest);
    const invalidManifest = runAllowFailure("python3", [verifyManifestPath], {
      cwd: generatedRepo,
    });
    if (invalidManifest.status === 0) {
      throw new Error(invalidManifest.stdout);
    }
    if (!invalidManifest.stderr.includes("official capture packet set post-capture workflow evidence missing")) {
      throw new Error(invalidManifest.stderr || invalidManifest.stdout);
    }
  } finally {
    writeJSON(manifestPath, manifest);
  }
  try {
    const mutatedManifest = JSON.parse(JSON.stringify(manifest));
    mutatedManifest.officialEvidence.sourceRepoBaselineChecks.officialGoldenCapturePreflight.requiredEvidence =
      mutatedManifest.officialEvidence.sourceRepoBaselineChecks.officialGoldenCapturePreflight.requiredEvidence.filter(
        (value) => value !== "checkedOfficialCapturePacketSetWorkflowVerifier",
      );
    writeJSON(manifestPath, mutatedManifest);
    const invalidManifest = runAllowFailure("python3", [verifyManifestPath], {
      cwd: generatedRepo,
    });
    if (invalidManifest.status === 0) {
      throw new Error(invalidManifest.stdout);
    }
    if (!invalidManifest.stderr.includes("official capture packet set workflow verifier evidence missing")) {
      throw new Error(invalidManifest.stderr || invalidManifest.stdout);
    }
  } finally {
    writeJSON(manifestPath, manifest);
  }
  try {
    const mutatedManifest = JSON.parse(JSON.stringify(manifest));
    mutatedManifest.officialEvidence.sourceRepoBaselineChecks.officialGoldenCapturePreflight.requiredEvidence =
      mutatedManifest.officialEvidence.sourceRepoBaselineChecks.officialGoldenCapturePreflight.requiredEvidence.filter(
        (value) => value !== "checkedOfficialCapturePacketStrictAuditHandoff",
      );
    writeJSON(manifestPath, mutatedManifest);
    const invalidManifest = runAllowFailure("python3", [verifyManifestPath], {
      cwd: generatedRepo,
    });
    if (invalidManifest.status === 0) {
      throw new Error(invalidManifest.stdout);
    }
    if (!invalidManifest.stderr.includes("official capture packet strict audit handoff evidence missing")) {
      throw new Error(invalidManifest.stderr || invalidManifest.stdout);
    }
  } finally {
    writeJSON(manifestPath, manifest);
  }
  try {
    const mutatedManifest = JSON.parse(JSON.stringify(manifest));
    mutatedManifest.officialEvidence.sourceRepoBaselineChecks.officialGoldenCapturePreflight.requiredEvidence =
      mutatedManifest.officialEvidence.sourceRepoBaselineChecks.officialGoldenCapturePreflight.requiredEvidence.filter(
        (value) => value !== "checkedOfficialCapturePacketStrictExpectedFailureAuditHandoff",
      );
    writeJSON(manifestPath, mutatedManifest);
    const invalidManifest = runAllowFailure("python3", [verifyManifestPath], {
      cwd: generatedRepo,
    });
    if (invalidManifest.status === 0) {
      throw new Error(invalidManifest.stdout);
    }
    if (!invalidManifest.stderr.includes("official capture packet strict expected-failure audit handoff evidence missing")) {
      throw new Error(invalidManifest.stderr || invalidManifest.stdout);
    }
  } finally {
    writeJSON(manifestPath, manifest);
  }

  const readmeCheck = run("python3", [verifyReadmePath], {
    cwd: generatedRepo,
  });
  const readmePayload = JSON.parse(readmeCheck.stdout);
  if (
    readmePayload.ok !== true ||
    readmePayload.checkedReadmeHandoffContract !== true ||
    readmePayload.checkedReadmeOfficialEvidenceHandoff !== true ||
    readmePayload.checkedReadmeOfficialGoldenGap !== true ||
    readmePayload.checkedReadmeWaitNotifyBoundary !== true
  ) {
    throw new Error(readmeCheck.stdout);
  }
  try {
    writeFileSync(
      path.join(generatedRepo, "README.md"),
      readme.replace(
        "make record-and-replay-official-golden-gate-audit",
        "missing-strict-gate",
      ),
    );
    const invalidReadme = runAllowFailure("python3", [verifyReadmePath], {
      cwd: generatedRepo,
    });
    if (invalidReadme.status === 0) {
      throw new Error(invalidReadme.stdout);
    }
    if (!invalidReadme.stderr.includes("missingRequiredSnippets")) {
      throw new Error(invalidReadme.stderr || invalidReadme.stdout);
    }
  } finally {
    writeFileSync(path.join(generatedRepo, "README.md"), readme);
  }

  const workflow = run(path.join(generatedRepo, "scripts", "verify-skill-workflow.py"), [], {
    cwd: generatedRepo,
  });
  const workflowPayload = JSON.parse(workflow.stdout);
  if (workflowPayload.ok !== true || workflowPayload.checkedSkillWorkflow !== true) {
    throw new Error(workflow.stdout);
  }

  const check = run(path.join(generatedRepo, "scripts", "check.sh"), [], {
    cwd: generatedRepo,
    env: {
      ...process.env,
      OPEN_COMPUTER_USE_CLI: launcher,
      OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY: "1",
    },
  });
  const checkPayloads = parseJSONObjectLines(check.stdout);
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedStrictValidation === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedEventsOnlyValidation === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedScaffoldSkill === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedNoActiveStatusStop === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedInitializeSurfaceContract === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedToolMetadataContract === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedToolInputSchemaNoArguments === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedRequiresObjectParams === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedRequiresStringToolName === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedRequiresObjectArguments === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedRejectsUnexpectedArguments === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedRejectsNonObjectArguments === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedRejectedRequestsDoNotCreateSessionFiles === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedManifestContract === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedSourceBaselineSummaryEvidence === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedSourceBaselineSummaryOfficialGoldenState === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedSourceBaselineSummaryOfficialSessionDirectoryPathHandoff === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedReadmeHandoffContract === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedSkillWorkflow === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedStatusNotUsedAsWaitLoopGuard === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedMcpNoDirectEventContentsGuard === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedWaitNotifyContract === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedNotifyCallbackFailureExit === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedNotifyCallbackFailureReason === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedNotifyCallbackTimeoutFailureExit === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedNotifyCallbackTimeoutReason === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedSkillCreatorHandoff === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedDeclaredHandoffPaths === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedScreenshotPathContainment === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedScaffoldSkillFailureExit === true)) {
    throw new Error(check.stdout);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedCancelledRecordingRejected === true)) {
    throw new Error(check.stdout);
  }
  const packagedSkill = path.join(
    generatedRepo,
    "dist",
    "skills",
    "open-computer-use-record-and-replay.skill",
  );
  if (!existsSync(packagedSkill)) {
    throw new Error(`generated repo self-check did not package skill: ${packagedSkill}`);
  }
  if (!checkPayloads.some((payload) => payload.ok === true && payload.checkedPackageArtifact === true)) {
    throw new Error(check.stdout);
  }

  console.log(JSON.stringify({
    ok: true,
    checkedNpmLauncher: true,
    checkedNpmPythonLauncherDiagnostics: true,
    checkedStandaloneRepoScaffold: true,
    checkedManifestContract: true,
    checkedReadmeHandoffContract: true,
    checkedReadmeOfficialEvidenceHandoff: true,
    checkedReadmeOfficialGoldenGap: true,
    checkedReadmeWaitNotifyBoundary: true,
    checkedGeneratedReadmePrerequisites: true,
    checkedGeneratedReadmeScenarioList: true,
    checkedOfficialEvidenceManifest: true,
    checkedOfficialEvidenceScenarioManifest: true,
    checkedOfficialEvidencePreflightManifest: true,
    checkedOfficialEvidenceAuditManifest: true,
    checkedOfficialFixtureSetComparePolicyManifest: true,
    checkedSourceBaselineSummaryEvidence: true,
    checkedSourceBaselineSummaryOfficialGoldenState: true,
    checkedSourceBaselineSummaryOfficialSessionDirectoryPathHandoff: true,
    checkedSourceBaselineSummaryCapturePacketSetContractManifest: true,
    checkedSourceBaselineSummaryCapturePacketPostCaptureWorkflow: true,
    checkedSourceBaselineSummaryCapturePacketWorkflowVerifier: true,
    checkedSourceBaselineSummaryCapturePacketSetPostCaptureWorkflow: true,
    checkedSourceBaselineSummaryCapturePacketSetWorkflowVerifier: true,
    checkedSourceBaselineSummaryCapturePacketStrictAuditHandoff: true,
    checkedSourceBaselineSummaryCapturePacketStrictExpectedFailureAuditHandoff: true,
    checkedPackageArtifact: true,
    checkedGeneratedRepoSelfCheck: true,
    checkedRuntimeTimeoutDiagnostics: true,
    checkedInitializeSurfaceContract: true,
    checkedToolMetadataContract: true,
    checkedToolInputSchemaNoArguments: true,
    checkedNoActiveStatusStop: true,
    checkedRequiresObjectParams: true,
    checkedRequiresStringToolName: true,
    checkedRequiresObjectArguments: true,
    checkedRejectsUnexpectedArguments: true,
    checkedRejectsNonObjectArguments: true,
    checkedRejectedRequestsDoNotCreateSessionFiles: true,
    checkedSkillWorkflow: true,
    checkedStatusNotUsedAsWaitLoopGuard: true,
    checkedMcpNoDirectEventContentsGuard: true,
    checkedWaitNotifyContract: true,
    checkedNotifySuppressedEventsPathEnv: true,
    checkedNotifyCallbackFailureExit: true,
    checkedNotifyCallbackFailureReason: true,
    checkedNotifyCallbackTimeoutFailureExit: true,
    checkedNotifyCallbackTimeoutReason: true,
    checkedSkillPackaging: true,
    checkedRecordingToSkillManifestContract: true,
    checkedCancelledRecordingContract: true,
    checkedStrictValidation: true,
    checkedDeclaredHandoffPaths: true,
    checkedScreenshotPathContainment: true,
    checkedEventsOnlyValidation: true,
    checkedScaffoldSkill: true,
    checkedScaffoldSkillFailureExit: true,
    checkedCancelledRecordingRejected: true,
    checkedRecordingToSkillHandoff: true,
    checkedSkillCreatorHandoff: true,
  }, null, 2));
} finally {
  writeFileSync(baselineSummaryArtifact, baselineSummaryOriginal, "utf8");
  rmSync(tmp, { recursive: true, force: true });
}
