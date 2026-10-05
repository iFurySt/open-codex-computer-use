#!/usr/bin/env node
// Real signed runtime and ScreenCaptureKit; uses no FixtureBridge or global input.
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { randomUUID, createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";
import { createConnection } from "node:net";
import { promisify } from "node:util";
import { setTimeout as delay } from "node:timers/promises";

assert.equal(process.platform, "darwin");
const app = resolve(process.argv.find(arg => arg.endsWith(".app")) ?? "dist/Open Computer Use.app");
const executable = join(app, "Contents/MacOS/OpenComputerUse");
const namespace = `ocu-reuse-smoke-${randomUUID()}`;
const socketPath = join(tmpdir(), `open-computer-use-agent-${createHash("sha256").update(namespace).digest("hex").slice(0, 16)}.sock`);
const execute = promisify(execFile);
const env = { ...process.env, OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE: namespace };
const scale = Number(process.argv.find(arg => arg.startsWith("--scale="))?.split("=")[1] ?? 1);
assert.ok([1, 2].includes(scale));
const configuration = {scale};
const cycles = Number(process.argv.find(arg => arg.startsWith("--cycles="))?.split("=")[1] ?? 20);
assert.ok(Number.isInteger(cycles) && cycles > 0 && cycles <= 100);
function request(value) {
  return new Promise((resolve, reject) => {
    const socket = createConnection(socketPath);
    let buffer = "";
    socket.setTimeout(15000, () => socket.destroy(new Error("Agent response timed out")));
    socket.on("error", reject);
    socket.on("connect", () => socket.write(JSON.stringify(value) + "\n"));
    socket.on("data", data => {
      buffer += data;
      if (buffer.includes("\n")) {
        socket.end();
        try { resolve(JSON.parse(buffer.split("\n")[0])); } catch (error) { reject(error); }
      }
    });
    socket.on("end", () => { if (!buffer.includes("\n")) reject(new Error("Agent closed without response")); });
  });
}
function alive(pid) {
  try { process.kill(pid, 0); return true; } catch (error) { if (error.code === "ESRCH") return false; throw error; }
}
async function call(tool, args = {}, expectError = false) {
  let result;
  try { result = await execute(executable, ["call", tool, "--args", JSON.stringify(args)], {env, timeout: 60000}); }
  catch (error) { if (expectError && error.stdout) result = error; else throw error; }
  const output = JSON.parse(result.stdout);
  assert.equal(output.isError, expectError, result.stdout);
  if (expectError) return output;
  const text = output.content.find(item => item.type === "text").text;
  try { return JSON.parse(text); } catch { return text; }
}
try {
  assert.deepEqual((await call("get_virtual_display_state")).sessions, []);
  const info = await request({kind: "agentInfo"});
  assert.equal(resolve(info.bundleURL), app);
  const warm = await call("prewarm_virtual_display", configuration);
  const holder = warm.idle_displays.find(display => display.display_id === warm.display_id);
  assert.ok(holder?.online);
  assert.equal((await request({kind: "agentInfo"})).ownedDisplayCount, 1);
  assert.equal((await call("prewarm_virtual_display", configuration)).display_id, warm.display_id, "Prewarm allocated a duplicate");
  const sessionIDs = new Set();
  let desktopBaseline;
  for (let cycle = 1; cycle <= cycles; cycle++) {
    const started = Date.now();
    const state = await call("create_virtual_display", configuration);
    assert.equal(state.display_reused, true);
    assert.equal(state.display_id, holder.display_id);
    assert.equal(state.helper_pid, holder.helper_pid);
    assert.equal(sessionIDs.has(state.session_id), false, "Reused a session identity");
    sessionIDs.add(state.session_id);
    assert.deepEqual(state.applications, []);
    assert.deepEqual(state.windows, []);
    const before = state.creation_observation.desktop_before;
    const after = state.creation_observation.desktop_after;
    assert.ok(before.physical_displays.length > 0);
    desktopBaseline ??= before;
    for (const desktop of [before, after]) {
      assert.equal(desktop.main_display_id, desktopBaseline.main_display_id);
      assert.equal(desktop.dock_display_id, desktopBaseline.dock_display_id);
      assert.deepEqual(desktop.physical_displays, desktopBaseline.physical_displays);
    }
    assert.equal(state.creation_observation.physical_layout_preserved, true);
    assert.notEqual(after.foreground_pid, info.pid, "Reuse activated the OCU test runtime");
    if (before.foreground_pid !== after.foreground_pid) {
      console.log(JSON.stringify({check: "foreground_changed_during_observation", cycle, before_pid: before.foreground_pid, after_pid: after.foreground_pid}));
    }
    await call("release_virtual_displays", {display_id: state.display_id}, true);
    let captured = state;
    for (let attempt = 0; attempt < 50 && captured.capture.frame_age_seconds === undefined; attempt++) {
      await delay(100);
      captured = await call("get_virtual_display_state", {session_id: state.session_id});
    }
    assert.ok(captured.capture.running);
    assert.equal(captured.capture.error, undefined);
    assert.ok(Number.isFinite(captured.capture.frame_age_seconds), "No real ScreenCaptureKit frame");
    await call("destroy_virtual_display", {session_id: state.session_id});
    const ended = await call("get_virtual_display_state");
    assert.deepEqual(ended.sessions, []);
    assert.equal(ended.idle_displays.length, 1);
    assert.equal(ended.idle_displays[0].display_id, holder.display_id);
    assert.ok(alive(holder.helper_pid));
    await call("get_virtual_display_state", {session_id: state.session_id}, true);
    console.log(JSON.stringify({check: "display_reused", cycle, elapsed_ms: Date.now() - started, passed: true}));
  }
  // Bypass a matching idle lease explicitly; strict removal leaves the old pool untouched.
  const strict = await call("create_virtual_display", {...configuration, reuse_display: false});
  assert.equal(strict.display_reused, false);
  assert.notEqual(strict.display_id, holder.display_id);
  await call("destroy_virtual_display", {session_id: strict.session_id, retain_display: false});
  assert.equal(alive(strict.helper_pid), false);
  assert.equal((await call("get_virtual_display_state")).idle_displays[0].display_id, holder.display_id);
  // A second configuration has its own lease; releasing it cannot retire the first.
  const other = await call("create_virtual_display", {scale: scale === 1 ? 2 : 1});
  assert.equal(other.display_reused, false);
  assert.notEqual(other.display_id, holder.display_id);
  await call("destroy_virtual_display", {session_id: other.session_id});
  const originalAgain = await call("create_virtual_display", configuration);
  assert.equal(originalAgain.display_reused, true);
  assert.equal(originalAgain.display_id, holder.display_id);
  await call("destroy_virtual_display", {session_id: originalAgain.session_id});
  await call("release_virtual_displays", {display_id: other.display_id});
  assert.equal(alive(other.helper_pid), false);
  assert.ok(alive(holder.helper_pid));
  // Simulate loss of our idle helper. A dead lease must be pruned rather than reused.
  process.kill(holder.helper_pid, "SIGTERM");
  for (let attempt = 0; attempt < 100 && alive(holder.helper_pid); attempt++) await delay(50);
  assert.equal(alive(holder.helper_pid), false);
  const replaced = await call("create_virtual_display", configuration);
  assert.equal(replaced.display_reused, false);
  assert.notEqual(replaced.helper_pid, holder.helper_pid);
  await call("destroy_virtual_display", {session_id: replaced.session_id});
  await call("release_virtual_displays");
  assert.equal(alive(replaced.helper_pid), false);
  assert.deepEqual((await call("get_virtual_display_state")).idle_displays, []);
  const quitWarm = await call("prewarm_virtual_display", configuration);
  const quitHolder = quitWarm.idle_displays[0];
  assert.equal((await request({kind: "terminate"})).ok, true);
  const deadline = Date.now() + 20000;
  while (alive(info.pid) && Date.now() < deadline) await delay(50);
  assert.equal(alive(info.pid), false);
  assert.equal(alive(quitHolder.helper_pid), false);
  console.log(JSON.stringify({check: "reuse_lifecycle_complete", cycles, scale, passed: true}));
} catch (error) {
  // Never force-terminate a runtime after cleanup failure; retain it for diagnosis.
  console.error(error.message);
  console.error(JSON.stringify({namespace, socketPath}));
  try { await request({kind: "terminate"}); } catch {}
  process.exitCode = 1;
}
