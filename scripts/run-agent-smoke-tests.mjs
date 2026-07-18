#!/usr/bin/env node
import { existsSync, rmSync } from "node:fs";
import { spawn, spawnSync } from "node:child_process";

const args = new Map();
for (const arg of process.argv.slice(2)) {
  const [key, ...rest] = arg.split("=");
  if (key.startsWith("--")) args.set(key.slice(2), rest.length ? rest.join("=") : "true");
}

const selectedAgents = new Set((args.get("agents") ?? process.env.OPEN_COMPUTER_USE_AGENT_AGENTS ?? "claude,codex")
  .split(",")
  .map((agent) => agent.trim())
  .filter(Boolean));
const json = args.get("json") === "true";
const command = args.get("command") ?? process.env.OPEN_COMPUTER_USE_AGENT_COMMAND ?? "open-computer-use";
const timeoutMs = Number(args.get("timeout-ms") ?? process.env.OPEN_COMPUTER_USE_AGENT_TIMEOUT_MS ?? 120000);
const maxClaudeBudget = args.get("claude-budget-usd") ?? process.env.OPEN_COMPUTER_USE_CLAUDE_BUDGET_USD ?? "2.00";
const hermesProvider = args.get("hermes-provider") ?? process.env.OPEN_COMPUTER_USE_HERMES_PROVIDER;
const hermesModel = args.get("hermes-model") ?? process.env.OPEN_COMPUTER_USE_HERMES_MODEL;
const hermesMaxTurns = args.get("hermes-max-turns") ?? process.env.OPEN_COMPUTER_USE_HERMES_MAX_TURNS ?? "12";
const scenario = args.get("scenario") ?? "list-apps";

if (!["list-apps", "fixture", "fixture-full"].includes(scenario)) {
  console.error(`Unsupported --scenario=${scenario}. Use list-apps, fixture, or fixture-full.`);
  process.exit(2);
}

function usesFixture() {
  return scenario === "fixture" || scenario === "fixture-full";
}

function runProcess(name, spec) {
  return new Promise((resolve) => {
    const child = spawn(spec.command, spec.args, {
      cwd: process.cwd(),
      stdio: ["ignore", "pipe", "pipe"],
      env: {
        ...process.env,
        OPEN_COMPUTER_USE_VISUAL_CURSOR: "0",
      },
    });

    let stdout = "";
    let stderr = "";
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGTERM");
      setTimeout(() => child.kill("SIGKILL"), 3000).unref();
    }, timeoutMs);

    child.stdout.on("data", (chunk) => stdout += chunk);
    child.stderr.on("data", (chunk) => stderr += chunk);
    child.on("error", (error) => {
      clearTimeout(timer);
      resolve({ agent: name, ok: false, code: null, timedOut, stdout, stderr: String(error.message ?? error) });
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      resolve({ agent: name, ok: code === 0 && !timedOut, code, timedOut, stdout: stdout.trim(), stderr: stderr.trim() });
    });
  });
}

function codexSawToolCalls(stdout, expectedTools) {
  const seen = new Set();
  const expected = new Set(expectedTools);
  for (const line of stdout.split(/\n+/).filter(Boolean)) {
    try {
      const event = JSON.parse(line);
      if (event.type === "item.completed"
        && event.item?.type === "mcp_tool_call"
        && event.item?.server === "open-computer-use"
        && event.item?.status === "completed"
        && expected.has(event.item?.tool)) {
        seen.add(event.item.tool);
      }
    } catch {}
  }
  return [...expected].every((tool) => seen.has(tool));
}

function fixtureExecutablePath() {
  for (const candidate of [".build/release/OpenComputerUseFixture", ".build/debug/OpenComputerUseFixture"]) {
    if (existsSync(candidate)) return candidate;
  }

  const build = spawnSync("swift", ["build", "-c", "release", "--product", "OpenComputerUseFixture"], {
    cwd: process.cwd(),
    stdio: "inherit",
  });
  if (build.status !== 0) {
    throw new Error("Failed to build OpenComputerUseFixture.");
  }
  if (existsSync(".build/release/OpenComputerUseFixture")) return ".build/release/OpenComputerUseFixture";
  throw new Error("OpenComputerUseFixture executable was not found after build.");
}

function resetFixtureState() {
  rmSync(`${process.env.TMPDIR ?? "/tmp"}/open-computer-use-fixture`, { recursive: true, force: true });
}

function launchFixture() {
  resetFixtureState();
  const executable = fixtureExecutablePath();
  const child = spawn(executable, [], {
    cwd: process.cwd(),
    stdio: ["ignore", "ignore", "pipe"],
    env: {
      ...process.env,
      OPEN_COMPUTER_USE_FIXTURE_HEADLESS: "1",
    },
  });
  child.fixtureStderr = "";
  child.fixtureExitCode = null;
  child.stderr.on("data", (chunk) => child.fixtureStderr += chunk);
  child.on("close", (code) => child.fixtureExitCode = code);
  return child;
}

function callOpenComputerUse(tool, toolArgs = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, ["call", tool, "--args", JSON.stringify(toolArgs)], {
      cwd: process.cwd(),
      stdio: ["ignore", "pipe", "pipe"],
      env: {
        ...process.env,
        OPEN_COMPUTER_USE_VISUAL_CURSOR: "0",
      },
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => stdout += chunk);
    child.stderr.on("data", (chunk) => stderr += chunk);
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) {
        const details = [
          `${command} call ${tool} exited ${code}`,
          stderr.trim() ? `stderr:\n${stderr.trim()}` : "",
          stdout.trim() ? `stdout:\n${stdout.trim()}` : "",
        ].filter(Boolean).join("\n");
        reject(new Error(details.slice(0, 2000)));
        return;
      }
      try {
        resolve(JSON.parse(stdout));
      } catch (error) {
        reject(new Error(`Failed to parse ${command} call ${tool} output: ${error.message}`));
      }
    });
  });
}

function textFromToolResult(result) {
  return result?.content?.find((item) => item.type === "text")?.text ?? "";
}

function lineHasExactValue(text, id, value) {
  return text.split("\n").some((line) =>
    line.includes(`ID: ${id} `) && line.includes(` Value: ${value} Frame:`)
  );
}

async function waitForFixtureReady(fixture) {
  const deadline = Date.now() + 10000;
  let lastError;
  while (Date.now() < deadline) {
    if (fixture?.fixtureExitCode !== null) {
      throw new Error([
        `OpenComputerUseFixture exited before readiness with code ${fixture.fixtureExitCode}.`,
        fixture.fixtureStderr?.trim() ? `fixture stderr:\n${fixture.fixtureStderr.trim()}` : "",
      ].filter(Boolean).join("\n"));
    }
    try {
      const result = await callOpenComputerUse("get_app_state", { app: "OpenComputerUseFixture" });
      const text = textFromToolResult(result);
      if (text.includes("fixture-input") && text.includes("fixture-increment")) return text;
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error([
    "OpenComputerUseFixture did not become visible to open-computer-use.",
    lastError ? `last error:\n${lastError.message ?? lastError}` : "",
    fixture?.fixtureStderr?.trim() ? `fixture stderr:\n${fixture.fixtureStderr.trim()}` : "",
  ].filter(Boolean).join("\n"));
}

async function validateFixtureState(expectedValue) {
  const result = await callOpenComputerUse("get_app_state", { app: "OpenComputerUseFixture" });
  const text = textFromToolResult(result);
  const expectedTextValue = scenario === "fixture-full" ? `${expectedValue}-typed` : expectedValue;
  return {
    ok: lineHasExactValue(text, "fixture-input", expectedTextValue)
      && lineHasExactValue(text, "fixture-counter-label", "Counter: 1")
      && (scenario !== "fixture-full" || (
        lineHasExactValue(text, "fixture-key-label", "Last key: Return")
        && !lineHasExactValue(text, "fixture-scroll-status", "Scroll offset: 0")
        && !lineHasExactValue(text, "fixture-drag-status", "Last drag: none")
      )),
    textTail: text.slice(-1200),
  };
}

function scenarioExpectedTools() {
  if (scenario === "fixture") return ["get_app_state", "set_value", "click"];
  if (scenario === "fixture-full") {
    return [
      "get_app_state",
      "set_value",
      "click",
      "type_text",
      "press_key",
      "perform_secondary_action",
      "scroll",
      "drag",
    ];
  }
  return ["list_apps"];
}

function scenarioAllowedTools() {
  return scenarioExpectedTools().map((tool) => `mcp__open-computer-use__${tool}`).join(",");
}

function makePrompt(expectedValue) {
  if (scenario === "list-apps") {
    return [
      "Use the open-computer-use MCP list_apps tool exactly once before answering.",
      "Do not use terminal, shell, browser, file, or any other tool.",
      "After the tool call, reply exactly OPEN_CU_AGENT_OK."
    ].join(" ");
  }

  return [
    "Use only open-computer-use MCP tools.",
    "Call get_app_state for app OpenComputerUseFixture.",
    ...(scenario === "fixture-full" ? [
      `Find the text field and use set_value to set it exactly to ${JSON.stringify(expectedValue)}.`,
      "Click the text field by element index, then use type_text to append exactly -typed.",
      "Click the Key Capture area by element index, then use press_key with key Return.",
      "Call perform_secondary_action on the window element with action Raise.",
      "Scroll the scroll area down by 1 page.",
      "Drag inside the Drag Pad from near its upper-left interior to near its lower-right interior.",
      "Click the Increment Counter button exactly once by element index.",
    ] : [
      `Find the text field and use set_value to set it exactly to ${JSON.stringify(expectedValue)}.`,
      "Find the Increment Counter button and click it exactly once by element index.",
    ]),
    "Do not use terminal, shell, browser, file, or any other tool.",
    "After the tool calls, reply exactly OPEN_CU_AGENT_OK."
  ].join(" ");
}

function makeSpecs(prompt) {
  return {
    claude: {
      command: "claude",
      args: [
        "-p",
        "--strict-mcp-config",
        "--mcp-config", JSON.stringify({
          mcpServers: {
            "open-computer-use": {
              type: "stdio",
              command,
              args: ["mcp"],
              env: { OPEN_COMPUTER_USE_VISUAL_CURSOR: "0" },
            },
          },
        }),
        "--permission-mode", "bypassPermissions",
        "--allowedTools", scenarioAllowedTools(),
        "--output-format", "text",
        "--max-budget-usd", maxClaudeBudget,
        prompt,
      ],
      validate: (result) => result.stdout.includes("OPEN_CU_AGENT_OK"),
    },
    codex: {
      command: "codex",
      args: [
        "exec",
        "--ignore-user-config",
        "--skip-git-repo-check",
        "--dangerously-bypass-approvals-and-sandbox",
        "--disable", "image_generation",
        "--disable", "js_repl",
        "--json",
        "-c", `mcp_servers.open-computer-use.command=${JSON.stringify(command)}`,
        "-c", 'mcp_servers.open-computer-use.args=["mcp"]',
        prompt,
      ],
      validate: (result) => result.stdout.includes("OPEN_CU_AGENT_OK") && codexSawToolCalls(result.stdout, scenarioExpectedTools()),
    },
    hermes: {
      command: "hermes",
      args: [
        "chat",
        "--query", prompt,
        "--quiet",
        "--yolo",
        "--max-turns", hermesMaxTurns,
        "--toolsets", "open-computer-use",
        ...(hermesProvider ? ["--provider", hermesProvider] : []),
        ...(hermesModel ? ["--model", hermesModel] : []),
      ],
      validate: (result) => result.stdout.includes("OPEN_CU_AGENT_OK"),
    },
  };
}

const results = [];
const expectedTools = scenarioExpectedTools();
for (const name of Object.keys(makeSpecs(""))) {
  if (!selectedAgents.has(name)) continue;
  const expectedValue = `agent-smoke-${name}-${Date.now()}`;
  const prompt = makePrompt(expectedValue);
  const spec = makeSpecs(prompt)[name];
  let fixture = null;
  let fixtureValidation = null;
  if (usesFixture()) {
    fixture = launchFixture();
    try {
      await waitForFixtureReady(fixture);
    } catch (error) {
      results.push({
        agent: name,
        processOk: false,
        code: null,
        timedOut: false,
        validated: false,
        expectedTools,
        fixtureValidation: { ok: false, error: String(error?.message ?? error) },
        stdoutTail: "",
        stderrTail: "",
      });
      fixture.kill("SIGTERM");
      continue;
    }
  }

  const result = await runProcess(name, spec);
  if (usesFixture()) {
    fixtureValidation = await validateFixtureState(expectedValue).catch((error) => ({
      ok: false,
      error: String(error?.message ?? error),
    }));
    fixture?.kill("SIGTERM");
  }
  const validated = result.ok
    && spec.validate(result)
    && (!usesFixture() || fixtureValidation?.ok === true);
  results.push({
    agent: name,
    processOk: result.ok,
    code: result.code,
    timedOut: result.timedOut,
    validated,
    expectedTools,
    fixtureValidation,
    stdoutTail: result.stdout.slice(-1200),
    stderrTail: result.stderr.slice(-1200),
  });
}

const report = {
  ok: results.length > 0 && results.every((result) => result.validated),
  command,
  results,
};

if (json) {
  console.log(JSON.stringify(report, null, 2));
} else {
  console.log(`agent smoke: ${report.ok ? "ok" : "failed"}`);
  for (const result of results) {
    console.log(`- ${result.agent}: processOk=${result.processOk} validated=${result.validated} code=${result.code}`);
    if (!result.validated) {
      if (result.stdoutTail) console.log(`  stdout: ${result.stdoutTail.replace(/\n/g, " ").slice(0, 500)}`);
      if (result.stderrTail) console.log(`  stderr: ${result.stderrTail.replace(/\n/g, " ").slice(0, 500)}`);
    }
  }
}

process.exit(report.ok ? 0 : 1);
