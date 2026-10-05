import assert from "node:assert/strict";
import test from "node:test";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";
import { JsonLinePeer, PersistentJavaScriptSession, WorkerJavaScriptSession, parseListApps, toolDefinitions } from "./open-computer-use-repl.mjs";

function textResult(text, isError = false, image) {
  const content = [{ type: "text", text }];
  if (image) content.push({ type: "image", mimeType: image.mimeType, data: image.data });
  return { content, isError };
}

function mockNative() {
  const calls = [];
  const native = {
    calls,
    async request(method, params) {
      assert.equal(method, "tools/call");
      calls.push(params);
      switch (params.name) {
        case "list_apps": return textResult('[{"id":"com.example.Text","displayName":"Text"}]');
        case "get_app_state": return textResult(`state:${params.arguments.app}`, false, { mimeType: "image/png", data: Buffer.from([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]).toString("base64") });
        case "click": return textResult("clicked");
        case "type_text": return params.arguments.text === "fail" ? textResult("typing failed", true) : textResult("typed");
        default: return textResult(params.name);
      }
    },
  };
  return native;
}

test("advertises only js and js_reset", () => {
  assert.deepEqual(toolDefinitions().map(tool => tool.name), ["js", "js_reset"]);
  assert.deepEqual(toolDefinitions()[0].inputSchema.required, ["code"]);
  assert.equal(toolDefinitions()[0].inputSchema.properties.timeout_ms.maximum, 300_000);
});

test("normalizes native app-list text across macOS, Linux, and Windows", () => {
  assert.deepEqual(parseListApps([
    "TextEdit — com.apple.TextEdit [frontmost, running, last-used=2026-09-22, uses=42]",
    "Google Chrome — com.google.Chrome [last-used=2026-09-21, uses=7]",
  ].join("\n")), [
    { id: "com.apple.TextEdit", displayName: "TextEdit", isRunning: true, lastUsedDate: "2026-09-22", useCount: 42 },
    { id: "com.google.Chrome", displayName: "Google Chrome", lastUsedDate: "2026-09-21", useCount: 7 },
  ]);
  assert.deepEqual(parseListApps("gedit -- gedit [running, pid=42, window=Draft, notes]"), [
    { id: "gedit", displayName: "gedit", isRunning: true },
  ]);
  assert.deepEqual(parseListApps("No running top-level apps are visible to this Linux runtime."), []);
});

test("cua.listApps returns structured apps for the native text protocol", async () => {
  const native = mockNative();
  native.request = async (method, params) => {
    assert.equal(method, "tools/call");
    native.calls.push(params);
    return textResult("TextEdit — com.apple.TextEdit [running, last-used=2026-09-22, uses=4]");
  };
  const session = new PersistentJavaScriptSession({ native });
  const result = await session.run(`
    var apps = await cua.listApps({ emit: false });
    nodeRepl.write(JSON.stringify(apps));
  `);
  assert.equal(result.isError, false);
  assert.deepEqual(JSON.parse(result.content.at(-1).text), [
    { id: "com.apple.TextEdit", displayName: "TextEdit", isRunning: true, lastUsedDate: "2026-09-22", useCount: 4 },
  ]);
});

test("top-level await and lexical bindings persist until reset", async () => {
  const session = new PersistentJavaScriptSession({ native: mockNative() });
  let result = await session.run("var answer = await Promise.resolve(41); nodeRepl.write(answer);");
  assert.equal(result.isError, false);
  assert.equal(result.content.at(-1).text, "41");
  result = await session.run("answer += 1; nodeRepl.write(answer);");
  assert.equal(result.content.at(-1).text, "42");
  session.reset();
  result = await session.run("nodeRepl.write(typeof answer);");
  assert.equal(result.content.at(-1).text, "undefined");
});

test("return values are not implicitly serialized into MCP output", async () => {
  const session = new PersistentJavaScriptSession({ native: mockNative() });
  const result = await session.run("({ huge: 'intermediate-only' })");
  assert.equal(result.isError, false);
  assert.equal(result.content.at(-1).text, "(no output)");
});

test("app-bound API composes actions and state in one js call", async () => {
  const native = mockNative();
  const session = new PersistentJavaScriptSession({ native });
  const result = await session.run(`
    var app = await cua.getApp("Text");
    await app.click(7, { clickMethod: "accessibility" });
    await app.typeText("hello");
    await app.getAXState();
  `);
  assert.equal(result.isError, false);
  assert.deepEqual(native.calls.map(call => call.name), ["get_app_state", "click", "type_text", "get_app_state"]);
  assert.equal(native.calls[1].arguments.element_index, 7);
  assert.equal(native.calls[1].arguments.click_method, "accessibility");
  assert.ok(result.content.some(item => item.type === "text" && item.text === "state:Text"));
});

test("tool errors are catchable in JavaScript", async () => {
  const session = new PersistentJavaScriptSession({ native: mockNative() });
  const result = await session.run(`
    var badApp = await cua.getApp("Text");
    try { await badApp.typeText("fail"); } catch (error) { nodeRepl.write("caught: " + error.message); }
  `);
  assert.equal(result.isError, false);
  assert.equal(result.content.at(-1).text, "caught: typing failed");
});

test("thrown errors settle the call and keep bindings", async () => {
  const session = new PersistentJavaScriptSession({ native: mockNative() });
  await session.run("var kept = 1;");
  let result = await session.run("nodeRepl.write('before'); null[1];", 1000);
  assert.equal(result.isError, true);
  assert.match(result.content.at(-1).text, /^Error: Cannot read properties of null/);
  result = await session.run("await 1; throw new Error('after await');", 1000);
  assert.equal(result.isError, true);
  assert.equal(result.content.at(-1).text, "Error: after await");
  result = await session.run("nodeRepl.write(kept);");
  assert.equal(result.content.at(-1).text, "1");
});

for (const Session of [PersistentJavaScriptSession, WorkerJavaScriptSession]) {
  test(`${Session.name}: a late throw from a finished call does not reach the next call`, async () => {
    const session = new Session({ native: mockNative() });
    try {
      let result = await session.run(`var kept = 1; setTimeout(() => { throw new Error("late"); }, 20);
        setTimeout(() => nodeRepl.write("late write"), 20);`, 1000);
      assert.equal(result.isError, false);
      result = await session.run(`await new Promise(resolve => setTimeout(resolve, 100)); nodeRepl.write("next " + kept);`, 1000);
      assert.deepEqual(result, { content: [{ type: "text", text: "next 1" }], isError: false });
      result = await session.run(`nodeRepl.write("after");`, 1000);
      assert.deepEqual(result, { content: [{ type: "text", text: "after" }], isError: false });
    } finally {
      await session.close?.();
    }
  });
}

test("screenshots emit binary image content", async () => {
  const session = new PersistentJavaScriptSession({ native: mockNative() });
  const result = await session.run(`
    var imageApp = await cua.getApp("Text");
    var imageBytes = await imageApp.getScreenshot();
    nodeRepl.write(imageBytes.length);
  `);
  assert.equal(result.isError, false);
  assert.ok(result.content.some(item => item.type === "image" && item.mimeType === "image/png"));
  assert.equal(result.content.at(-1).text, "8");
});

test("JsonLinePeer initializes and correlates native MCP responses", async () => {
  const child = new EventEmitter();
  child.stdout = new PassThrough(); child.stderr = new PassThrough(); child.stdin = new PassThrough();
  child.kill = () => {};
  let input = "";
  child.stdin.setEncoding("utf8");
  child.stdin.on("data", chunk => {
    input += chunk;
    for (;;) {
      const newline = input.indexOf("\n"); if (newline < 0) break;
      const request = JSON.parse(input.slice(0, newline)); input = input.slice(newline + 1);
      if (request.id !== undefined) child.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", id: request.id, result: request.method === "initialize" ? { ok: true } : { content: [] } })}\n`);
    }
  });
  const peer = new JsonLinePeer({ child });
  assert.deepEqual(await peer.initialize(), { ok: true });
  assert.deepEqual(await peer.request("tools/call", { name: "list_apps" }), { content: [] });
  peer.closed = true;
});

test("worker session terminates CPU-bound code and recovers with a fresh kernel", async () => {
  const session = new WorkerJavaScriptSession({ native: mockNative() });
  let result = await session.run("while (true) {}", 100);
  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /timed out/);
  result = await session.run("nodeRepl.write(21 * 2);", 5_000);
  assert.equal(result.isError, false);
  assert.equal(result.content.at(-1).text, "42");
  await session.close();
});

test("worker session returns a structured error for invalid source input", async () => {
  const session = new WorkerJavaScriptSession({ native: mockNative() });
  const result = await session.run(undefined, 5_000);
  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /non-empty JavaScript source/);
  const recovered = await session.run("nodeRepl.write('ready');", 5_000);
  assert.equal(recovered.isError, false);
  assert.equal(recovered.content.at(-1).text, "ready");
  await session.close();
});

test("worker session serializes concurrent callers", async () => {
  const session = new WorkerJavaScriptSession({ native: mockNative() });
  const first = session.run("await new Promise(resolve => setTimeout(resolve, 40)); var order = ['first']; nodeRepl.write(order.join(','));", 5_000);
  const second = session.run("order.push('second'); nodeRepl.write(order.join(','));", 5_000);
  assert.equal((await first).content.at(-1).text, "first");
  assert.equal((await second).content.at(-1).text, "first,second");
  await session.close();
});

test("virtual display bindings carry session identity through every action", async () => {
  const calls = [];
  const native = { async request(method, params) {
    if (method === "tools/list") return {tools: [{name: "create_virtual_display"}]};
    assert.equal(method, "tools/call");
    calls.push(params);
    if (["create_virtual_display", "attach_app_to_virtual_display", "get_virtual_display_state", "pause_virtual_display", "resume_virtual_display"].includes(params.name)) return textResult(JSON.stringify({ session_id: "virtual-1", phase: "ready" }));
    return textResult("state");
  } };
  const session = new PersistentJavaScriptSession({ native });
  const result = await session.run(`
    var display = await cua.createVirtualDisplay({scale: 2});
    await display.attachApp("com.example.App", {pid: 42, windowId: 123});
    var app = await display.getApp("com.example.App", {windowId: 123});
    await app.click(2); await app.typeText("hello"); await app.pressKey("Tab");
    await app.drag([1,2], [3,4]); await app.scroll(4, "down");
    await app.setValue(3, "text"); await app.performSecondaryAction(2, "Press");
    await app.getAXState({emit:false}); await display.pause(); await display.resume(); var joined = await cua.getVirtualDisplay(display.id); await joined.getState(); await joined.destroy();
  `);
  assert.equal(result.isError, false);
  assert.deepEqual(calls[0].arguments, {scale: 2});
  assert.deepEqual(calls[1].arguments, {session_id: "virtual-1", app: "com.example.App", mode: "adopt", pid: 42, window_id: 123});
  assert.equal(calls[2].arguments.window_id, 123);
  for (const call of calls.slice(1)) assert.equal(call.arguments.session_id, "virtual-1");
  for (const call of calls.slice(3)) assert.equal(call.arguments.window_id, undefined);
});

test("unsupported native runtimes cannot silently ignore a virtual session binding", async () => {
  const calls = [];
  const native = { async request(method) { calls.push(method); return {tools: [{name: "get_app_state"}]}; } };
  const session = new PersistentJavaScriptSession({native});
  const result = await session.run('await cua.getApp("Example", {sessionId: "virtual-1"});');
  assert.equal(result.isError, true);
  assert.match(result.content.at(-1).text, /unavailable/);
  assert.deepEqual(calls, ["tools/list"]);
});

test("virtual session discovery and multi-app bindings retain independent identities", async () => {
  const calls = [];
  const native = { async request(method, params) {
    if (method === "tools/list") return { tools: [{ name: "create_virtual_display" }] };
    calls.push(params);
    if (params.name === "get_virtual_display_state") {
      return textResult(JSON.stringify(params.arguments.session_id ? {session_id: params.arguments.session_id} : {sessions: [{session_id: "one"}, {session_id: "two"}]}));
    }
    if (params.name === "attach_app_to_virtual_display") return textResult(JSON.stringify({session_id: params.arguments.session_id}));
    return textResult("state");
  } };
  const session = new PersistentJavaScriptSession({native});
  const result = await session.run(`
    var displays = await cua.listVirtualDisplays();
    var display = await cua.getVirtualDisplay(displays[0].session_id);
    await display.attachApp("First", {pid: 10, windowId: 11});
    await display.attachApp("Second", {pid: 20, windowId: 21});
    var firstApp = await display.getApp("First"); var secondApp = await display.getApp("Second");
    await firstApp.click(1); await secondApp.click(2);
    var other = await cua.getApp("Third", {sessionId: displays[1].session_id}); await other.click(3);
  `);
  assert.equal(result.isError, false);
  assert.deepEqual(calls[0].arguments, {});
  const clicks = calls.filter(c => c.name === "click");
  assert.deepEqual(clicks.map(c => [c.arguments.app, c.arguments.session_id]), [["First", "one"], ["Second", "one"], ["Third", "two"]]);
});


test("virtual display lifecycle exposes prewarm, reuse, retention and scoped idle release", async () => {
  const calls = [];
  const native = { async request(method, params) {
    if (method === "tools/list") return {tools: [{name: "create_virtual_display"}]};
    calls.push(params);
    if (params.name === "get_virtual_display_state") return textResult(JSON.stringify({sessions: [], idle_displays: [{display_id: 42}]}));
    return textResult(JSON.stringify({session_id: "lease", display_id: 42}));
  }};
  const session = new PersistentJavaScriptSession({native});
  const result = await session.run(`
    await cua.prewarmVirtualDisplay({scale: 2});
    var lease = await cua.createVirtualDisplay({scale: 2, reuseDisplay: false});
    await lease.destroy({retainDisplay: false});
    var idle = await cua.listIdleVirtualDisplays();
    if (idle[0].display_id !== 42) throw Error('missing idle state');
    await cua.releaseVirtualDisplays({displayId: 42});
    await cua.releaseVirtualDisplays();
  `);
  assert.equal(result.isError, false);
  assert.deepEqual(calls.map(call => [call.name, call.arguments]), [
    ["prewarm_virtual_display", {scale: 2}],
    ["create_virtual_display", {scale: 2, reuse_display: false}],
    ["destroy_virtual_display", {session_id: "lease", retain_display: false}],
    ["get_virtual_display_state", {}],
    ["release_virtual_displays", {display_id: 42}],
    ["release_virtual_displays", {}],
  ]);
});
