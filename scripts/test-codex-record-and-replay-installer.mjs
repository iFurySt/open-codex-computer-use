#!/usr/bin/env node

import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const scriptPath = path.join(repoRoot, "scripts", "install-codex-record-and-replay-mcp.sh");

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function runInstaller(codexHome) {
  const result = spawnSync(scriptPath, {
    cwd: repoRoot,
    env: {
      ...process.env,
      CODEX_HOME: codexHome,
    },
    encoding: "utf8",
  });

  if (result.status !== 0) {
    throw new Error(`installer failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
  }

  return result.stdout;
}

const tempRoot = mkdtempSync(path.join(tmpdir(), "ocu-rnr-installer-"));

try {
  const codexHome = path.join(tempRoot, "codex-home");
  const configPath = path.join(codexHome, "config.toml");
  const firstOutput = runInstaller(codexHome);
  const firstConfig = readFileSync(configPath, "utf8");

  assert(firstOutput.includes('Installed Codex MCP server "record_and_replay"'), "first install should report installation");
  assert(firstConfig.includes('[mcp_servers."record_and_replay"]'), "config should include record_and_replay MCP server");
  assert(firstConfig.includes('command = "open-computer-use"'), "config should launch open-computer-use");
  assert(firstConfig.includes('args = ["event-stream","mcp"]'), "config should launch event-stream mcp");

  const secondOutput = runInstaller(codexHome);
  const secondConfig = readFileSync(configPath, "utf8");

  assert(secondOutput.includes('Codex MCP server "record_and_replay" is already installed'), "second install should be idempotent");
  assert(secondConfig === firstConfig, "second install should leave config unchanged");

  process.stdout.write(JSON.stringify({ ok: true, installer: "codex-record-and-replay-mcp" }) + "\n");
} finally {
  rmSync(tempRoot, { recursive: true, force: true });
}
