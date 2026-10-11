import assert from "node:assert/strict";
import test from "node:test";
import { withParallel } from "./research.mjs";

function server({ toolError = false, missingTool = false, httpError = false } = {}) {
  const requests = [];
  let closed = false;
  const fetchImpl = async (url, init) => {
    const headers = new Headers(init.headers);
    const body = init.body ? JSON.parse(init.body) : undefined;
    requests.push({ url: String(url), method: init.method, headers, body });
    if (httpError) return new Response("rate limited", { status: 429 });
    if (init.method === "GET") {
      const stream = new ReadableStream({ start(controller) {
        init.signal.addEventListener("abort", () => { closed = true; controller.close(); }, { once: true });
      } });
      return new Response(stream, { headers: { "Content-Type": "text/event-stream" } });
    }
    if (body.id === undefined) return new Response(null, { status: 202 });
    let result;
    switch (body.method) {
      case "initialize":
        result = { protocolVersion: body.params.protocolVersion, capabilities: { tools: {} }, serverInfo: { name: "fixture", version: "1" } };
        break;
      case "tools/list":
        result = { tools: (missingTool ? ["web_search"] : ["web_search", "web_fetch"]).map(name => ({ name, inputSchema: { type: "object" } })) };
        break;
      case "tools/call":
        result = { content: [{ type: "text", text: toolError ? "fixture tool failure" : "https://example.com: useful page excerpt" }], isError: toolError };
        break;
      default: throw new Error(`Unexpected method ${body.method}`);
    }
    return new Response(JSON.stringify({ jsonrpc: "2.0", id: body.id, result }), {
      headers: { "Content-Type": "application/json", "Mcp-Session-Id": "fixture-session" },
    });
  };
  return { requests, fetchImpl, get closed() { return closed; } };
}

test("SDK discovery, search and fetch preserve output and use anonymous project headers", async () => {
  const fixture = server();
  const results = await withParallel(async research => [
    await research.search("Find setup instructions", ["computer use setup instructions"]),
    await research.fetch(["https://example.com"], "Find platform requirements"),
  ], fixture);
  assert.ok(results.every(result => result.content[0].text.includes("useful page excerpt")));
  for (const request of fixture.requests) {
    assert.equal(request.url, "https://search.parallel.ai/mcp");
    assert.equal(request.headers.get("User-Agent"), "open-computer-use/parallel-search-example");
    assert.equal(request.headers.has("Authorization"), false);
    assert.equal(request.headers.has("x-api-key"), false);
  }
  const calls = fixture.requests.filter(request => request.body?.method === "tools/call");
  assert.deepEqual(calls.map(call => call.body.params.name), ["web_search", "web_fetch"]);
  assert.deepEqual(calls[0].body.params.arguments.search_queries, ["computer use setup instructions"]);
  assert.deepEqual(calls[1].body.params.arguments.urls, ["https://example.com"]);
  assert.equal(calls[1].body.params.arguments.full_content, false);
  assert.match(calls[0].body.params.arguments.session_id, /^[0-9a-f-]{36}$/);
  assert.equal(calls[0].body.params.arguments.session_id, calls[1].body.params.arguments.session_id);
  assert.equal(fixture.closed, true);
});

test("tool errors are failures and close the connection", async () => {
  const fixture = server({ toolError: true });
  await assert.rejects(withParallel(research => research.search("Find setup", ["computer use setup instructions"]), fixture), /web_search: fixture tool failure/);
  assert.equal(fixture.closed, true);
});

test("incompatible discovery and caller failures close the connection", async () => {
  const fixture = server({ missingTool: true });
  let ran = false;
  await assert.rejects(withParallel(() => { ran = true; }, fixture), /missing web_fetch/);
  assert.equal(ran, false);
  assert.equal(fixture.closed, true);
  const callbackFixture = server();
  await assert.rejects(withParallel(() => { throw new Error("caller failed"); }, callbackFixture), /caller failed/);
  assert.equal(callbackFixture.closed, true);
});

test("HTTP errors propagate without retrying", async () => {
  const fixture = server({ httpError: true });
  await assert.rejects(withParallel(() => assert.fail("must not run"), fixture), error => error.code === 429 && error.message.includes("rate limited"));
  assert.equal(fixture.requests.length, 1);
});
