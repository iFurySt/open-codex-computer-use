#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import {
  chmodSync,
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..", "..");
const defaultOutDir = path.join(repoRoot, "dist", "npm");
const appBundleName = "Open Computer Use.app";
const appExecutableName = "OpenComputerUse";
const packageNames = [
  "open-computer-use",
  "open-computer-use-mcp",
  "open-codex-computer-use-mcp",
];

function parseArgs(argv) {
  const options = {
    arch: "universal",
    configuration: "release",
    outDir: defaultOutDir,
    packageNames: [...packageNames],
    skipBuild: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];

    switch (arg) {
      case "--arch":
        options.arch = argv[index + 1];
        index += 1;
        break;
      case "--configuration":
        options.configuration = argv[index + 1];
        index += 1;
        break;
      case "--out-dir":
        options.outDir = path.resolve(repoRoot, argv[index + 1]);
        index += 1;
        break;
      case "--package":
        options.packageNames = [argv[index + 1]];
        index += 1;
        break;
      case "--skip-build":
        options.skipBuild = true;
        break;
      case "-h":
      case "--help":
        printHelp();
        process.exit(0);
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  for (const packageName of options.packageNames) {
    if (!packageNames.includes(packageName)) {
      throw new Error(`Unsupported package name: ${packageName}`);
    }
  }

  return options;
}

function printHelp() {
  process.stdout.write(`Usage: node ./scripts/npm/build-packages.mjs [options]

Options:
  --configuration debug|release
  --arch native|arm64|x86_64|universal
  --out-dir <dir>
  --package <package-name>
  --skip-build
`);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: repoRoot,
    stdio: "inherit",
    ...options,
  });

  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed with exit code ${result.status ?? "unknown"}`);
  }
}

function readJSON(filePath) {
  return JSON.parse(readFileSync(filePath, "utf-8"));
}

function removeJunkFiles(targetPath) {
  if (!existsSync(targetPath)) {
    return;
  }

  const entryStat = statSync(targetPath);
  if (entryStat.isDirectory()) {
    for (const entry of readdirSync(targetPath)) {
      removeJunkFiles(path.join(targetPath, entry));
    }
    return;
  }

  if (path.basename(targetPath) === ".DS_Store") {
    unlinkSync(targetPath);
  }
}

function ensureBuilt(configuration, arch) {
  run(path.join(repoRoot, "scripts", "build-open-computer-use-app.sh"), [
    "--configuration",
    configuration,
    "--arch",
    arch,
  ]);
}

function writeExecutable(filePath, content) {
  writeFileSync(filePath, content, "utf-8");
  chmodSync(filePath, 0o755);
}

function renderLauncher() {
  return `#!/usr/bin/env bash
set -euo pipefail

script_path="\${BASH_SOURCE[0]}"
while [[ -L "\${script_path}" ]]; do
  script_dir="$(cd "$(dirname "\${script_path}")" && pwd)"
  script_path="$(readlink "\${script_path}")"
  if [[ "\${script_path}" != /* ]]; then
    script_path="\${script_dir}/\${script_path}"
  fi
done
package_root="$(cd "$(dirname "\${script_path}")/.." && pwd)"
app_binary="\${package_root}/dist/${appBundleName}/Contents/MacOS/${appExecutableName}"
install_script="\${package_root}/scripts/install-codex-plugin.sh"

if [[ "\${1:-}" == "install-codex-plugin" ]]; then
  shift
  exec "\${install_script}" "$@"
fi

if [[ ! -x "\${app_binary}" ]]; then
  echo "open-computer-use could not find a runnable app bundle at \${app_binary}." >&2
  exit 1
fi

exec "\${app_binary}" "$@"
`;
}

function renderPostinstall(packageName) {
  return `#!/usr/bin/env node
const lines = [
  "",
  "Installed ${packageName}.",
  "Commands: open-computer-use, open-computer-use-mcp, open-codex-computer-use-mcp",
  "Start MCP: open-computer-use mcp",
  "Grant permissions / diagnose: open-computer-use doctor",
  "Install into Codex plugin cache: open-computer-use install-codex-plugin",
  "",
];
for (const line of lines) {
  console.log(line);
}
`;
}

function renderReadme(packageName, version) {
  return `# ${packageName}

Prebuilt macOS npm distribution for the open-source **Open Computer Use** MCP server.

This package bundles a ready-to-run \`${appBundleName}\`, the Codex plugin metadata, and three global command aliases:

- \`open-computer-use\`
- \`open-computer-use-mcp\`
- \`open-codex-computer-use-mcp\`

## Install

\`\`\`bash
npm install -g ${packageName}
\`\`\`

## MCP config

If your MCP client accepts a stdio-style \`mcpServers\` JSON config, this is the default setup:

\`\`\`json
{
  "mcpServers": {
    "open-computer-use": {
      "command": "open-computer-use",
      "args": ["mcp"]
    }
  }
}
\`\`\`

In practice, using this package as MCP is: global install, add the JSON config, then grant macOS \`Accessibility\` and \`Screen Recording\` permission to the host terminal or app on first use.

## Use

\`\`\`bash
# Check permissions; if Accessibility / Screen Recording is missing, open the permission onboarding window
open-computer-use doctor

# Start the stdio MCP server for Claude Desktop, Cursor, Cline, or another MCP client
open-computer-use mcp

# Install this package into the local Codex plugin marketplace/cache
open-computer-use install-codex-plugin
\`\`\`

## Notes

- Version: \`${version}\`
- Platform: macOS 14+
- Architectures: \`arm64\` and \`x64\` via a universal app bundle
- The host terminal or app still needs macOS \`Accessibility\` and \`Screen Recording\` permissions

Source repository: https://github.com/iFurySt/open-codex-computer-use
`;
}

function renderPackageJson(packageName, version) {
  return {
    name: packageName,
    version,
    description: "Prebuilt macOS Computer Use MCP server with Codex plugin installer.",
    license: "MIT",
    homepage: "https://github.com/iFurySt/open-codex-computer-use",
    repository: {
      type: "git",
      url: "git+https://github.com/iFurySt/open-codex-computer-use.git",
    },
    bugs: {
      url: "https://github.com/iFurySt/open-codex-computer-use/issues",
    },
    keywords: [
      "computer-use",
      "codex",
      "mcp",
      "macos",
      "automation",
    ],
    os: ["darwin"],
    cpu: ["arm64", "x64"],
    preferGlobal: true,
    publishConfig: {
      access: "public",
    },
    bin: {
      "open-computer-use": "bin/open-computer-use",
      "open-computer-use-mcp": "bin/open-computer-use-mcp",
      "open-codex-computer-use-mcp": "bin/open-codex-computer-use-mcp",
    },
    scripts: {
      postinstall: "node ./scripts/postinstall.mjs",
    },
    files: [
      ".agents/plugins/marketplace.json",
      "bin/",
      `dist/${appBundleName}/`,
      "plugins/open-computer-use/.codex-plugin/",
      "plugins/open-computer-use/.mcp.json",
      "plugins/open-computer-use/assets/",
      "plugins/open-computer-use/scripts/",
      "scripts/install-codex-plugin.sh",
      "scripts/postinstall.mjs",
      "README.md",
      "LICENSE",
    ],
  };
}

function stagePackage(packageName, version, outDir) {
  const packageRoot = path.join(outDir, packageName);
  rmSync(packageRoot, { recursive: true, force: true });

  mkdirSync(path.join(packageRoot, ".agents", "plugins"), { recursive: true });
  mkdirSync(path.join(packageRoot, "bin"), { recursive: true });
  mkdirSync(path.join(packageRoot, "dist"), { recursive: true });
  mkdirSync(path.join(packageRoot, "plugins"), { recursive: true });
  mkdirSync(path.join(packageRoot, "scripts"), { recursive: true });

  cpSync(path.join(repoRoot, ".agents", "plugins", "marketplace.json"), path.join(packageRoot, ".agents", "plugins", "marketplace.json"));
  cpSync(path.join(repoRoot, "dist", appBundleName), path.join(packageRoot, "dist", appBundleName), {
    recursive: true,
  });
  cpSync(path.join(repoRoot, "plugins", "open-computer-use"), path.join(packageRoot, "plugins", "open-computer-use"), {
    recursive: true,
  });
  cpSync(path.join(repoRoot, "scripts", "install-codex-plugin.sh"), path.join(packageRoot, "scripts", "install-codex-plugin.sh"));
  cpSync(path.join(repoRoot, "LICENSE"), path.join(packageRoot, "LICENSE"));

  writeExecutable(path.join(packageRoot, "bin", "open-computer-use"), renderLauncher());
  writeExecutable(path.join(packageRoot, "bin", "open-computer-use-mcp"), renderLauncher());
  writeExecutable(path.join(packageRoot, "bin", "open-codex-computer-use-mcp"), renderLauncher());
  writeFileSync(path.join(packageRoot, "scripts", "postinstall.mjs"), renderPostinstall(packageName), "utf-8");
  writeFileSync(path.join(packageRoot, "README.md"), renderReadme(packageName, version), "utf-8");
  writeFileSync(path.join(packageRoot, "package.json"), `${JSON.stringify(renderPackageJson(packageName, version), null, 2)}\n`, "utf-8");

  chmodSync(path.join(packageRoot, "scripts", "install-codex-plugin.sh"), 0o755);
  removeJunkFiles(packageRoot);
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const pluginManifestPath = path.join(repoRoot, "plugins", "open-computer-use", ".codex-plugin", "plugin.json");
  const { version } = readJSON(pluginManifestPath);

  if (!options.skipBuild) {
    ensureBuilt(options.configuration, options.arch);
  }

  rmSync(options.outDir, { recursive: true, force: true });
  mkdirSync(options.outDir, { recursive: true });

  for (const packageName of options.packageNames) {
    stagePackage(packageName, version, options.outDir);
  }

  process.stdout.write(`${options.outDir}\n`);
}

main();
