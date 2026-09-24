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

test("app-bound API forwards background-operation options", async () => {
  const native = mockNative();
  const session = new PersistentJavaScriptSession({ native });
  const result = await session.run(`
    var backgroundApp = await cua.getApp("Text");
    await backgroundApp.getAXState({ emit: false, textLimit: "max", maxTreeNodes: 42, maxTreeDepth: 7, windowPlacement: "agent_display" });
    await backgroundApp.getScreenshot({ emit: false, windowPlacement: "keep" });
    await backgroundApp.getAXStateAndScreenshot({ emit: false, windowPlacement: "restore" });
    await backgroundApp.typeText("hello", { keyMethod: "sky_key" });
    await backgroundApp.pressKey("cmd+a", { keyMethod: "sky_key" });
  `);

  assert.equal(result.isError, false);
  assert.deepEqual(native.calls[1], {
    name: "get_app_state",
    arguments: {
      app: "Text",
      text_limit: "max",
      max_tree_nodes: 42,
      max_tree_depth: 7,
      window_placement: "agent_display",
    },
  });
  assert.deepEqual(native.calls[2], {
    name: "get_app_state",
    arguments: { app: "Text", window_placement: "keep", text_limit: 1 },
  });
  assert.deepEqual(native.calls[3], {
    name: "get_app_state",
    arguments: { app: "Text", window_placement: "restore" },
  });
  assert.deepEqual(native.calls[4], {
    name: "type_text",
    arguments: { app: "Text", text: "hello", key_method: "sky_key" },
  });
  assert.deepEqual(native.calls[5], {
    name: "press_key",
    arguments: { app: "Text", key: "cmd+a", key_method: "sky_key" },
  });
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
