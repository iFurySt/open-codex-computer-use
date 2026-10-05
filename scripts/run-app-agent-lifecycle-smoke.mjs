#!/usr/bin/env node
// Exercise the actual signed app-agent shutdown protocol, including terminateLater.
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { randomUUID, createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";
import { createConnection } from "node:net";
import { promisify } from "node:util";
import { setTimeout as delay } from "node:timers/promises";

assert.equal(process.platform, "darwin", "This smoke requires macOS");
const app = resolve(process.argv.find(arg => arg.endsWith(".app")) ?? "dist/Open Computer Use.app");
const executable = join(app, "Contents/MacOS/OpenComputerUse");
const namespace = `ocu-shutdown-smoke-${randomUUID()}`;
const socketPath = join(tmpdir(), `open-computer-use-agent-${createHash("sha256").update(namespace).digest("hex").slice(0, 16)}.sock`);
const execute = promisify(execFile);
const env = { ...process.env, OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE: namespace };
function request(value) {
  return new Promise((resolve, reject) => {
    const socket = createConnection(socketPath);
    let buffer = "";
    socket.setTimeout(8000, () => socket.destroy(new Error("Agent response timed out")));
    socket.on("error", reject);
    socket.on("connect", () => socket.write(JSON.stringify(value) + "\n"));
    socket.on("data", data => {
      buffer += data;
      if (buffer.includes("\n")) {
        socket.end();
        try { resolve(JSON.parse(buffer.split("\n")[0])); } catch (error) { reject(error); }
      }
    });
    socket.on("end", () => { if (!buffer.includes("\n")) reject(new Error("Agent closed without a response")); });
  });
}
function alive(pid) {
  try { process.kill(pid, 0); return true; } catch (error) { if (error.code === "ESRCH") return false; throw error; }
}
async function call(tool) {
  const result = await execute(executable, ["call", tool], { env, timeout: 60000 });
  const output = JSON.parse(result.stdout);
  assert.equal(output.isError, false, result.stdout);
  return JSON.parse(output.content.find(item => item.type === "text").text);
}
try {
  assert.deepEqual((await call("get_virtual_display_state")).sessions, []);
  const info = await request({ kind: "agentInfo" });
  assert.equal(resolve(info.bundleURL), app);
  assert.ok(Number.isInteger(info.pid) && info.pid > 1);
  let helperPID;
  if (process.argv.includes("--with-session")) helperPID = (await call("create_virtual_display")).helper_pid;
  const started = Date.now();
  assert.equal((await request({ kind: "terminate" })).ok, true);
  while (alive(info.pid) && Date.now() - started < 20000) await delay(50);
  assert.equal(alive(info.pid), false, "Quit remained blocked in the nested AppKit loop");
  if (helperPID) assert.equal(alive(helperPID), false, "Owned display helper remained");
  console.log(JSON.stringify({ check: "app_agent_shutdown", with_session: Boolean(helperPID), elapsed_ms: Date.now() - started, passed: true }));
} catch (error) {
  // Keep a failed runtime available for diagnosis; never force-discard user apps.
  console.error(error.message);
  process.exitCode = 1;
}
