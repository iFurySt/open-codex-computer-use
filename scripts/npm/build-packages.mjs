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

print_launcher_help() {
  cat <<'EOF'
Open Computer Use

Usage:
  open-computer-use [command] [options]
  open-computer-use

Commands:
  mcp                  Start the stdio MCP server.
  doctor               Print permission status and launch onboarding if needed.
  list-apps            Print running or recently used apps.
  snapshot <app>       Print the current accessibility snapshot for an app.
  call <tool>           Call one tool, or run a JSON array of tool calls.
  turn-ended           Notify the running MCP process that the host turn ended.
  install-claude-mcp   Install the MCP server into ~/.claude.json for this project.
  install-gemini-mcp   Install the MCP server into Gemini CLI config.
  install-codex-mcp    Install the MCP server into ~/.codex/config.toml.
  install-opencode-mcp Install the MCP server into ~/.config/opencode.
  install-codex-plugin Install this npm package into the local Codex plugin cache.
  help [command]       Show general or command-specific help.
  version              Print the CLI version.

Global options:
  -h, --help           Show help.
  -v, --version        Show version.

Notes:
  Running without a command launches the permission onboarding app.
  Use \`open-computer-use help <command>\` for command-specific help.
EOF
}

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
install_claude_mcp_script="\${package_root}/scripts/install-claude-mcp.sh"
install_gemini_mcp_script="\${package_root}/scripts/install-gemini-mcp.sh"
install_mcp_script="\${package_root}/scripts/install-codex-mcp.sh"
install_opencode_mcp_script="\${package_root}/scripts/install-opencode-mcp.sh"
install_script="\${package_root}/scripts/install-codex-plugin.sh"

if [[ "\${1:-}" == "install-claude-mcp" || "\${1:-}" == "install-clauce-mcp" ]]; then
  shift
  exec "\${install_claude_mcp_script}" "$@"
fi

if [[ "\${1:-}" == "install-gemini-mcp" ]]; then
  shift
  exec "\${install_gemini_mcp_script}" "$@"
fi

if [[ "\${1:-}" == "install-codex-mcp" ]]; then
  shift
  exec "\${install_mcp_script}" "$@"
fi

if [[ "\${1:-}" == "install-opencode-mcp" ]]; then
  shift
  exec "\${install_opencode_mcp_script}" "$@"
fi

if [[ "\${1:-}" == "install-codex-plugin" ]]; then
  shift
  exec "\${install_script}" "$@"
fi

if [[ "\${1:-}" == "-h" || "\${1:-}" == "--help" ]]; then
  print_launcher_help
  exit 0
fi

if [[ "\${1:-}" == "help" && $# -le 1 ]]; then
  print_launcher_help
  exit 0
fi

if [[ "\${1:-}" == "help" && "\${2:-}" == "install-codex-plugin" ]]; then
  cat <<'EOF'
Usage:
  open-computer-use install-codex-plugin

Install this npm package into the local Codex plugin cache.
EOF
  exit 0
fi

if [[ "\${1:-}" == "help" && "\${2:-}" == "install-codex-mcp" ]]; then
  cat <<'EOF'
Usage:
  open-computer-use install-codex-mcp

Install the open-computer-use MCP server into ~/.codex/config.toml.
EOF
  exit 0
fi

if [[ "\${1:-}" == "help" && "\${2:-}" == "install-gemini-mcp" ]]; then
  cat <<'EOF'
Usage:
  open-computer-use install-gemini-mcp [--scope project|user]

Install the open-computer-use MCP server into Gemini CLI config.
EOF
  exit 0
fi

if [[ "\${1:-}" == "help" && "\${2:-}" == "install-opencode-mcp" ]]; then
  cat <<'EOF'
Usage:
  open-computer-use install-opencode-mcp

Install the open-computer-use MCP server into ~/.config/opencode.
EOF
  exit 0
fi

if [[ "\${1:-}" == "help" && ( "\${2:-}" == "install-claude-mcp" || "\${2:-}" == "install-clauce-mcp" ) ]]; then
  cat <<'EOF'
Usage:
  open-computer-use install-claude-mcp
  open-computer-use install-clauce-mcp

Install the open-computer-use MCP server into ~/.claude.json for the current project.
EOF
  exit 0
fi

if [[ ! -x "\${app_binary}" ]]; then
  echo "open-computer-use could not find a runnable app bundle at \${app_binary}." >&2
  exit 1
fi

exec "\${app_binary}" "$@"
`;
}

function renderPostinstall(packageName, version) {
  return `#!/usr/bin/env node
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const packageRoot = path.resolve(scriptDir, "..");
const bundledAppBinary = path.join(
  packageRoot,
  "dist",
  ${JSON.stringify(appBundleName)},
  "Contents",
  "MacOS",
  ${JSON.stringify(appExecutableName)}
);

function shouldLaunchOnboarding() {
  if (process.platform !== "darwin") {
    return false;
  }

  if (process.env.CI === "1" || process.env.CI === "true") {
    return false;
  }

  if (process.env.OPEN_COMPUTER_USE_SKIP_POSTINSTALL_ONBOARDING === "1") {
    return false;
  }

  if (process.stdout.isTTY !== true) {
    return false;
  }

  return process.env.npm_config_global === "true" || process.env.npm_config_location === "global";
}

function launchOnboardingIfPossible() {
  if (!shouldLaunchOnboarding() || !existsSync(bundledAppBinary)) {
    return false;
  }

  try {
    const child = spawn(bundledAppBinary, [], {
      detached: true,
      stdio: "ignore",
      env: {
        ...process.env,
        OPEN_COMPUTER_USE_LAUNCHED_FROM_POSTINSTALL: "1",
      },
    });
    child.on("error", () => {});
    child.unref();
    return true;
  } catch {
    return false;
  }
}

const launchedOnboarding = launchOnboardingIfPossible();
const mcpConfig = ${JSON.stringify({
  mcpServers: {
    "open-computer-use": {
      command: "open-computer-use",
      args: ["mcp"],
    },
  },
}, null, 2)};
const lines = [
  "",
  "Installed ${packageName}@${version}.",
  "Package: https://www.npmjs.com/package/${packageName}",
  "Commands: open-computer-use, open-computer-use-mcp, open-codex-computer-use-mcp",
  "",
  launchedOnboarding
    ? "Permission onboarding launched automatically using the bundled app."
    : "Run open-computer-use or open-computer-use doctor if you want to open the bundled permission onboarding.",
  "",
  "Next:",
  "1. If the helper did not appear, run open-computer-use or open-computer-use doctor",
  "2. In macOS System Settings, grant Accessibility and Screen Recording to the app or host CLI you actually plan to run",
  "3. Run open-computer-use install-claude-mcp, install-gemini-mcp, install-codex-mcp, or install-opencode-mcp for your host CLI, or install-codex-plugin for the local Codex plugin cache",
  "",
  "You can add this to any MCP-capable client:",
  JSON.stringify(mcpConfig, null, 2),
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

On interactive local global installs, the package also tries to open the bundled permiso-style permission onboarding automatically. If nothing appears, run \`open-computer-use\` or \`open-computer-use doctor\`. If macOS \`Accessibility\` or \`Screen Recording\` permission is missing, the helper opens the onboarding window and tells you what still needs to be granted. If everything is already granted, it just exits.

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

In practice, using this package as MCP is: global install, let the bundled onboarding helper run (or launch it yourself), add the JSON config, then grant macOS \`Accessibility\` and \`Screen Recording\` permission to the bundled npm-installed \`Open Computer Use.app\` or the host CLI you actually use.

Package page: https://www.npmjs.com/package/${packageName}

## Use

\`\`\`bash
# Show global help, command help, and version
open-computer-use --help
open-computer-use help snapshot
open-computer-use --version

# Install into Claude Code for the current project
open-computer-use install-claude-mcp

# Install into Gemini CLI for the current project or user config
open-computer-use install-gemini-mcp
open-computer-use install-gemini-mcp --scope user

# Install into Codex as a plain MCP entry in ~/.codex/config.toml
open-computer-use install-codex-mcp

# Install into opencode in ~/.config/opencode
open-computer-use install-opencode-mcp

# Check permissions first; if the postinstall helper did not appear, run this manually
# If Accessibility / Screen Recording is missing, it opens the permission onboarding window
# If both are already granted, this just prints the status and exits
open-computer-use doctor

# Start the stdio MCP server for Claude Desktop, Cursor, Cline, or another MCP client
open-computer-use mcp

# Call tools directly; the JSON-array form keeps state in one process for follow-up actions
open-computer-use call list_apps
open-computer-use call get_app_state --args '{"app":"TextEdit"}'
open-computer-use call --calls '[{"tool":"get_app_state","args":{"app":"TextEdit"}},{"tool":"press_key","args":{"app":"TextEdit","key":"Return"}}]'

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
    description: "Prebuilt macOS Computer Use MCP server. After install, run open-computer-use doctor.",
    license: "MIT",
    homepage: "https://github.com/iFurySt/open-codex-computer-use",
    repository: {
      type: "git",
      url: "https://github.com/iFurySt/open-codex-computer-use",
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
      "scripts/install-claude-mcp.sh",
      "scripts/install-gemini-mcp.sh",
      "scripts/install-config-helper.mjs",
      "scripts/install-codex-mcp.sh",
      "scripts/install-opencode-mcp.sh",
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
  cpSync(path.join(repoRoot, "scripts", "install-claude-mcp.sh"), path.join(packageRoot, "scripts", "install-claude-mcp.sh"));
  cpSync(path.join(repoRoot, "scripts", "install-gemini-mcp.sh"), path.join(packageRoot, "scripts", "install-gemini-mcp.sh"));
  cpSync(path.join(repoRoot, "scripts", "install-config-helper.mjs"), path.join(packageRoot, "scripts", "install-config-helper.mjs"));
  cpSync(path.join(repoRoot, "scripts", "install-codex-mcp.sh"), path.join(packageRoot, "scripts", "install-codex-mcp.sh"));
  cpSync(path.join(repoRoot, "scripts", "install-opencode-mcp.sh"), path.join(packageRoot, "scripts", "install-opencode-mcp.sh"));
  cpSync(path.join(repoRoot, "scripts", "install-codex-plugin.sh"), path.join(packageRoot, "scripts", "install-codex-plugin.sh"));
  cpSync(path.join(repoRoot, "LICENSE"), path.join(packageRoot, "LICENSE"));

  writeExecutable(path.join(packageRoot, "bin", "open-computer-use"), renderLauncher());
  writeExecutable(path.join(packageRoot, "bin", "open-computer-use-mcp"), renderLauncher());
  writeExecutable(path.join(packageRoot, "bin", "open-codex-computer-use-mcp"), renderLauncher());
  writeFileSync(path.join(packageRoot, "scripts", "postinstall.mjs"), renderPostinstall(packageName, version), "utf-8");
  writeFileSync(path.join(packageRoot, "README.md"), renderReadme(packageName, version), "utf-8");
  writeFileSync(path.join(packageRoot, "package.json"), `${JSON.stringify(renderPackageJson(packageName, version), null, 2)}\n`, "utf-8");

  chmodSync(path.join(packageRoot, "scripts", "install-claude-mcp.sh"), 0o755);
  chmodSync(path.join(packageRoot, "scripts", "install-gemini-mcp.sh"), 0o755);
  chmodSync(path.join(packageRoot, "scripts", "install-codex-mcp.sh"), 0o755);
  chmodSync(path.join(packageRoot, "scripts", "install-opencode-mcp.sh"), 0o755);
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
