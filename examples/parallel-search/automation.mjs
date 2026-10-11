// Run from this directory with: ocu js --timeout 120000 --file automation.mjs
// This source is evaluated by the OCU REPL, which supplies nodeRepl.
var { pathToFileURL } = await import("node:url");
var { withParallel } = await import(pathToFileURL(`${nodeRepl.cwd}/research.mjs`).href);
await withParallel(async research => {
  nodeRepl.write(await research.search(
    "Find Open Computer Use installation instructions and supported platforms.",
    ["Open Computer Use installation platforms"],
  ));
  // The exact repository README is useful here because we need its setup commands.
  nodeRepl.write(await research.fetch(
    ["https://github.com/iFurySt/open-codex-computer-use"],
    "Extract installation commands and platform requirements.",
  ));
});
