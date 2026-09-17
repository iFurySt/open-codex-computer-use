#!/usr/bin/env node

import readline from "node:readline";

const serverName = process.env.OCU_TEST_SERVER_NAME ?? "open-computer-use";

const defaultToolNames = [
  "click",
  "drag",
  "get_app_state",
  "list_apps",
  "perform_secondary_action",
  "press_key",
  "scroll",
  "set_value",
  "type_text",
];
const toolNames = process.env.OCU_TEST_TOOL_NAMES?.split(",") ?? defaultToolNames;
const tools = toolNames.map((name) => ({ name, inputSchema: { type: "object" } }));

const lines = readline.createInterface({ input: process.stdin });
lines.on("line", (line) => {
  const request = JSON.parse(line);
  if (request.id === undefined) return;

  let result;
  if (request.method === "initialize") {
    result = {
      protocolVersion: "2025-03-26",
      capabilities: { tools: { listChanged: false } },
      serverInfo: { name: serverName, version: "test" },
    };
  } else if (request.method === "tools/list") {
    result = { tools };
  } else {
    process.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", id: request.id, error: { code: -32601, message: "Method not found" } })}\n`);
    return;
  }

  process.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", id: request.id, result })}\n`);
});
