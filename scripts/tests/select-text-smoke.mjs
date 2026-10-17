#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { randomUUID } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { JsonLinePeer, WorkerJavaScriptSession } from "../node-repl/open-computer-use-repl.mjs";

assert.equal(process.platform, "darwin", "select-text smoke requires macOS");
const root = fileURLToPath(new URL("../../", import.meta.url));
const nativePath = path.resolve(process.argv[2] ?? path.join(root, ".build/debug/OpenComputerUse"));
const fixturePath = path.join(path.dirname(nativePath), "OpenComputerUseFixture");
assert.ok(existsSync(nativePath) && existsSync(fixturePath), "Run swift build first");
const namespace = randomUUID().toUpperCase();
const directory = path.join(tmpdir(), `open-computer-use-fixture-${namespace}`);
const env = { ...process.env, OPEN_COMPUTER_USE_FIXTURE_NAMESPACE: namespace, OPEN_COMPUTER_USE_FIXTURE_HEADLESS: "1",
  OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY: "1", OPEN_COMPUTER_USE_VISUAL_CURSOR: "0",
  OPEN_COMPUTER_USE_ACTION_READ_BACK: "0" };
const fixture = spawn(fixturePath, [], { env, stdio: ["ignore", "ignore", "pipe"] });
let fixtureError = "";
fixture.stderr.on("data", data => { fixtureError = (fixtureError + data).slice(-4096); });
const stateFile = path.join(directory, "state.json");
let native, session;
async function waitFor(test) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (test()) return;
    if (fixture.exitCode !== null) throw new Error(`Fixture exited: ${fixtureError}`);
    await new Promise(resolve => setTimeout(resolve, 30));
  }
  throw new Error(`Fixture timeout: ${fixtureError}`);
}
function state() { return JSON.parse(readFileSync(stateFile, "utf8")); }
async function run(code, expectedError) {
  const result = await session.run(code);
  const output = result.content.filter(item => item.type === "text").map(item => item.text).join("\n");
  if (expectedError) { assert.equal(result.isError, true, output); assert.match(output, expectedError); }
  else assert.equal(result.isError, false, output);
  return output;
}
try {
  await waitFor(() => existsSync(stateFile));
  native = new JsonLinePeer({ command: nativePath, args: ["mcp"], env });
  await native.initialize();
  const request = native.request.bind(native);
  native.request = async (method, params, timeout) => {
    const result = await request(method, params, timeout);
    if (method === "tools/call" && params.name === "select_text" && !result.isError) {
      assert.deepEqual(result.content, [{ type: "text", text: "ok" }], "Selection must honor no-read-back mode");
    }
    return result;
  };
  session = new WorkerJavaScriptSession({ native });
  await run(`var app = await cua.getApp("OpenComputerUseFixture");
    var ax = await app.getAXState({emit:false});
    var index = Number(ax.match(/^\\s*(\\d+).*ID: fixture-input(?:\\s|$)/m)[1]);
    await app.setValue(index, "a👍中文|中文");`);
  await run(`await app.selectText(index, "中文");`, /matches.*prefix or suffix/);
  await run(`await app.selectText(index, "missing");`, /could not find/);
  await run(`await app.selectText(index, "中文", {prefix:"a👍"});`);
  assert.equal(state().selectedRangeLocation, 3);
  assert.equal(state().selectedRangeLength, 2);
  assert.equal(state().selectedText, "中文");
  const observed = await run(`await app.getAXState();`);
  assert.match(observed, /Selected text: \[中文\]/);
  await run(`await app.selectText(index, "中文", {prefix:"|", selection:"cursor_before"});`);
  assert.equal(state().selectedRangeLocation, 6);
  assert.equal(state().selectedRangeLength, 0);
  await run(`await app.selectText(index, "中文", {prefix:"|", selection:"cursor_after"});`);
  assert.equal(state().selectedRangeLocation, 8);
  assert.equal(state().selectedRangeLength, 0);
  assert.equal(state().elements.find(item => item.identifier === "fixture-input").value, "a👍中文|中文");
  console.log("Worker JS → native MCP → fixture: ambiguity, missing text, Unicode selection, both caret modes and no-read-back passed.");
} finally {
  await session?.close();
  native?.close();
  fixture.kill("SIGTERM");
  if (fixture.exitCode === null && fixture.signalCode === null) {
    await new Promise(resolve => {
      const timer = setTimeout(() => { fixture.kill("SIGKILL"); resolve(); }, 3000);
      fixture.once("exit", () => { clearTimeout(timer); resolve(); });
    });
  }
  rmSync(directory, { recursive: true, force: true });
}
