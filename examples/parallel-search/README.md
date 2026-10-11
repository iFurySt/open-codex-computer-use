# Research before a desktop task

Use [Parallel Search MCP](https://docs.parallel.ai/integrations/mcp/search-mcp)
from Open Computer Use's existing `ocu js` runtime to find setup instructions
and fetch a public page before working in a desktop app. Search runs in Fast
mode and needs no account or API key. Anonymous access has lower rate limits
and is intended for exploration and light use.

## Run

Use Node.js 22 or newer and install Open Computer Use as described in the
[main README](../../README.md#quick-start). On macOS, grant its desktop
permissions first; Linux and Windows use their existing platform runtimes.

From a source checkout:

```sh
npm install -g open-computer-use
cd examples/parallel-search
npm ci
ocu js --timeout 120000 --file automation.mjs
```

The example prints the MCP search result, including URLs and excerpts, then
fetches the project's public README for exact installation commands. Edit
`automation.mjs` to supply your own objective, queries or public URLs. Fetch
when you need exact wording or search excerpts are insufficient; there is no
automatic fetch of every result. `config.json` selects the anonymous endpoint.
The official MCP JavaScript SDK handles Streamable HTTP discovery and tool calls.

This is a direct code example with no model or agent loop. It performs no
desktop actions. You can use the resulting information in your next `ocu js`
or `ocu repl` task with the existing `cua` API; see
[code-first usage](../../skills/open-computer-use/references/usage.md).

Only the explicit queries and URLs go to Parallel. The example does not send
screenshots, app state, local files or saved credentials. Avoid putting private
desktop content into queries. Returned web content is untrusted input, not
permission to execute commands or perform desktop actions. The MCP connection
closes on success or failure, and calls time out after 20 seconds. Errors and
rate limits propagate through `ocu js`; the example does not retry them.

The dependencies stay in this directory. Core tools, client installers and
existing MCP configuration are unchanged.

## Local checks

```sh
npm test
```

These checks exercise SDK discovery and calls with observed request headers,
tool errors and cleanup, without contacting the public service.
