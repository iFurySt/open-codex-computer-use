import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";

// This example deliberately has no auth provider, credential lookup or API key.
export async function withParallel(run, { fetchImpl = globalThis.fetch } = {}) {
  const config = JSON.parse(await readFile(new URL("./config.json", import.meta.url), "utf8"));
  const client = new Client({ name: "open-computer-use-parallel-example", version: "1.0.0" });
  const transport = new StreamableHTTPClientTransport(new URL(config.url), {
    requestInit: { headers: { "User-Agent": config.userAgent } },
    fetch: fetchImpl,
  });
  const sessionId = randomUUID();
  const options = { timeout: 20_000 };
  try {
    await client.connect(transport, options);
    const catalog = await client.listTools({}, options);
    for (const name of ["web_search", "web_fetch"]) {
      if (!catalog.tools.some(tool => tool.name === name)) throw new Error(`Parallel MCP is missing ${name}`);
    }
    async function call(name, args) {
      const result = await client.callTool({ name, arguments: { ...args, session_id: sessionId } }, undefined, options);
      if (result.isError) {
        throw new Error(`${name}: ${result.content.filter(item => item.type === "text").map(item => item.text).join("\n")}`);
      }
      return result;
    }
    return await run({
      search: (objective, searchQueries) => call("web_search", { objective, search_queries: searchQueries }),
      fetch: (urls, objective) => call("web_fetch", { urls, objective, full_content: false }),
    });
  } finally {
    await client.close();
  }
}
