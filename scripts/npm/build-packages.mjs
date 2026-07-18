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
const metaPackageNames = [
  "open-computer-use",
  "open-computer-use-mcp",
  "open-codex-computer-use-mcp",
];
const runtimeTargets = [
  {
    os: "darwin",
    cpu: "arm64",
    kind: "macos-app",
    executablePath: ["dist", appBundleName, "Contents", "MacOS", appExecutableName],
  },
  {
    os: "darwin",
    cpu: "x64",
    kind: "macos-app",
    executablePath: ["dist", appBundleName, "Contents", "MacOS", appExecutableName],
  },
  {
    os: "linux",
    cpu: "arm64",
    kind: "binary",
    buildArch: "arm64",
    executablePath: ["dist", "linux", "arm64", "open-computer-use"],
  },
  {
    os: "linux",
    cpu: "x64",
    kind: "binary",
    buildArch: "amd64",
    executablePath: ["dist", "linux", "amd64", "open-computer-use"],
  },
  {
    os: "win32",
    cpu: "arm64",
    kind: "binary",
    buildArch: "arm64",
    executablePath: ["dist", "windows", "arm64", "open-computer-use.exe"],
  },
  {
    os: "win32",
    cpu: "x64",
    kind: "binary",
    buildArch: "amd64",
    executablePath: ["dist", "windows", "amd64", "open-computer-use.exe"],
  },
];
const packageNames = [
  ...metaPackageNames,
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
  --arch native|arm64|x86_64|universal  macOS app build arch. Defaults to universal.
  --out-dir <dir>
  --package <package-name>
  --skip-build

Packages:
${packageNames.map((name) => `  - ${name}`).join("\n")}
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

  for (const buildArch of ["arm64", "amd64"]) {
    run(path.join(repoRoot, "scripts", "build-open-computer-use-linux.sh"), [
      "--configuration",
      configuration,
      "--arch",
      buildArch,
    ]);
    run(path.join(repoRoot, "scripts", "build-open-computer-use-windows.sh"), [
      "--configuration",
      configuration,
      "--arch",
      buildArch,
    ]);
  }
}

function writeExecutable(filePath, content) {
  writeFileSync(filePath, content, "utf-8");
  chmodSync(filePath, 0o755);
}

function platformLaunchTable() {
  return Object.fromEntries(
    runtimeTargets.map((runtimeTarget) => [
      `${runtimeTarget.os}-${runtimeTarget.cpu}`,
      {
        executablePath: runtimeTarget.executablePath,
      },
    ]),
  );
}

function renderLauncher() {
  return `#!/usr/bin/env node
const { spawn } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const platformPackages = ${JSON.stringify(platformLaunchTable(), null, 2)};
const packageRoot = path.resolve(__dirname, "..");
const args = process.argv.slice(2);
const command = args[0] || "";
const installCommands = new Map([
  ["install-claude-mcp", "install-claude-mcp.sh"],
  ["install-clauce-mcp", "install-claude-mcp.sh"],
  ["install-gemini-mcp", "install-gemini-mcp.sh"],
  ["install-codex-mcp", "install-codex-mcp.sh"],
  ["install-opencode-mcp", "install-opencode-mcp.sh"],
  ["install-codex-plugin", "install-codex-plugin.sh"],
]);

function printLauncherHelp() {
  console.log(\`Open Computer Use

Usage:
  open-computer-use [command] [options]
  ocu [command] [options]
  open-computer-use

Commands:
  mcp                  Start the stdio MCP server.
  doctor               Print permission status and launch onboarding if needed on macOS.
  list-apps            Print running or recently used apps.
  snapshot <app>       Print the current accessibility snapshot for an app.
  call <tool>          Call one tool, or run a JSON array of tool calls.
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
  This npm package bundles native runtimes for supported platforms and selects the current os-arch at launch.
  Use 'open-computer-use help <command>' for command-specific help.\`);
}

function printInstallHelp(scriptName, usage) {
  console.log(\`Usage:
  \${usage}

This helper updates a local MCP or plugin config to run:
  open-computer-use mcp

Script:
  \${scriptName}\`);
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

function spawnAndExit(executable, executableArgs) {
  const child = spawn(executable, executableArgs, {
    stdio: "inherit",
    windowsHide: false,
  });

  child.on("error", (error) => {
    fail(\`Failed to start \${executable}: \${error.message}\`);
  });

  for (const signal of ["SIGINT", "SIGTERM"]) {
    process.on(signal, () => {
      child.kill(signal);
    });
  }

  child.on("exit", (code, signal) => {
    if (signal) {
      process.exit(1);
    }
    process.exit(code ?? 0);
  });
}

function runInstallCommand(scriptName, scriptArgs) {
  if (process.platform === "win32") {
    fail(\`\${command} currently requires a POSIX shell. Configure your MCP client with command "open-computer-use" and args ["mcp"] on Windows.\`);
  }

  const scriptPath = path.join(packageRoot, "scripts", scriptName);
  if (!fs.existsSync(scriptPath)) {
    fail(\`Missing installer helper at \${scriptPath}.\`);
  }

  spawnAndExit(scriptPath, scriptArgs);
}

function resolveNativeExecutable() {
  const platformKey = \`\${process.platform}-\${process.arch}\`;
  const target = platformPackages[platformKey];
  if (!target) {
    const supported = Object.keys(platformPackages).sort().join(", ");
    fail(\`Unsupported platform \${platformKey}. Supported platforms: \${supported}.\`);
  }

  const executablePath = path.join(packageRoot, ...target.executablePath);
  if (!fs.existsSync(executablePath)) {
    fail(\`Missing bundled native runtime for \${platformKey} at \${executablePath}.

Reinstall with:
  npm install -g open-computer-use\`);
  }

  return executablePath;
}

if (command === "-h" || command === "--help" || (command === "help" && args.length <= 1)) {
  printLauncherHelp();
  process.exit(0);
}

if (command === "help" && args[1] === "install-codex-plugin") {
  printInstallHelp("install-codex-plugin.sh", "open-computer-use install-codex-plugin");
  process.exit(0);
}

if (command === "help" && args[1] === "install-codex-mcp") {
  printInstallHelp("install-codex-mcp.sh", "open-computer-use install-codex-mcp");
  process.exit(0);
}

if (command === "help" && args[1] === "install-gemini-mcp") {
  printInstallHelp("install-gemini-mcp.sh", "open-computer-use install-gemini-mcp [--scope project|user]");
  process.exit(0);
}

if (command === "help" && args[1] === "install-opencode-mcp") {
  printInstallHelp("install-opencode-mcp.sh", "open-computer-use install-opencode-mcp");
  process.exit(0);
}

if (command === "help" && (args[1] === "install-claude-mcp" || args[1] === "install-clauce-mcp")) {
  printInstallHelp("install-claude-mcp.sh", "open-computer-use install-claude-mcp");
  process.exit(0);
}

if (installCommands.has(command)) {
  const scriptName = installCommands.get(command);
  runInstallCommand(scriptName, args.slice(1));
} else {
  spawnAndExit(resolveNativeExecutable(), args);
}
`;
}

function renderPostinstall(packageName, version) {
  return `#!/usr/bin/env node
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
  "Commands: open-computer-use, ocu, open-computer-use-mcp, open-codex-computer-use-mcp",
  "Native runtime will be selected from bundled artifacts for " + process.platform + "-" + process.arch + ".",
  "",
  "Next:",
  "1. Run open-computer-use --version or ocu --version",
  "2. Add the MCP config below to your host client",
  "3. On macOS, run open-computer-use doctor and grant Accessibility / Screen Recording if prompted",
  "",
  "MCP config:",
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

Cross-platform npm distribution for the open-source **Open Computer Use** MCP server.

This package bundles native runtimes for these supported platforms and lets the Node launcher choose the current \`process.platform\` / \`process.arch\` pair:

${runtimeTargets.map((runtimeTarget) => `- \`${runtimeTarget.os}-${runtimeTarget.cpu}\``).join("\n")}

Global command aliases:

- \`open-computer-use\`
- \`ocu\`
- \`open-computer-use-mcp\`
- \`open-codex-computer-use-mcp\`

## Install

\`\`\`bash
npm install -g ${packageName}
\`\`\`

The root launcher resolves the current \`process.platform\` / \`process.arch\` pair and runs the matching bundled native runtime.

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

Package page: https://www.npmjs.com/package/${packageName}

## Use

\`\`\`bash
open-computer-use --version
ocu --version
open-computer-use --help
open-computer-use mcp
ocu mcp
open-computer-use call list_apps

# macOS permission check and onboarding
open-computer-use doctor

# Installer helpers for MCP-capable CLIs
open-computer-use install-claude-mcp
open-computer-use install-gemini-mcp
open-computer-use install-gemini-mcp --scope user
open-computer-use install-codex-mcp
open-computer-use install-opencode-mcp
open-computer-use install-codex-plugin
\`\`\`

## Notes

- Version: \`${version}\`
- Supported npm platforms: \`darwin-arm64\`, \`darwin-x64\`, \`linux-arm64\`, \`linux-x64\`, \`win32-arm64\`, \`win32-x64\`
- macOS still requires \`Accessibility\` and \`Screen Recording\` permissions.
- Linux requires a signed-in desktop session with AT-SPI2 / D-Bus accessibility available for real app control.
- Windows requires a signed-in desktop session for UI Automation access.

Source repository: https://github.com/iFurySt/open-codex-computer-use
`;
}

function packageKeywords(extraKeywords = []) {
  return [
    "computer-use",
    "codex",
    "mcp",
    "macos",
    "linux",
    "windows",
    "automation",
    ...extraKeywords,
  ];
}

function renderMetaPackageJson(packageName, version) {
  return {
    name: packageName,
    version,
    description: "Cross-platform Computer Use MCP server launcher. After install, configure open-computer-use mcp.",
    license: "MIT",
    homepage: "https://github.com/iFurySt/open-codex-computer-use",
    repository: {
      type: "git",
      url: "git+https://github.com/iFurySt/open-codex-computer-use.git",
    },
    bugs: {
      url: "https://github.com/iFurySt/open-codex-computer-use/issues",
    },
    keywords: packageKeywords(),
    preferGlobal: true,
    publishConfig: {
      access: "public",
    },
    bin: {
      "open-computer-use": "bin/open-computer-use",
      "ocu": "bin/ocu",
      "open-computer-use-mcp": "bin/open-computer-use-mcp",
      "open-codex-computer-use-mcp": "bin/open-codex-computer-use-mcp",
    },
    scripts: {
      postinstall: "node ./scripts/postinstall.mjs",
    },
    files: [
      ".agents/plugins/marketplace.json",
      "bin/",
      "dist/Open Computer Use.app/",
      "dist/linux/",
      "dist/windows/",
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

function copyInstallerScripts(packageRoot) {
  cpSync(path.join(repoRoot, "scripts", "install-claude-mcp.sh"), path.join(packageRoot, "scripts", "install-claude-mcp.sh"));
  cpSync(path.join(repoRoot, "scripts", "install-gemini-mcp.sh"), path.join(packageRoot, "scripts", "install-gemini-mcp.sh"));
  cpSync(path.join(repoRoot, "scripts", "install-config-helper.mjs"), path.join(packageRoot, "scripts", "install-config-helper.mjs"));
  cpSync(path.join(repoRoot, "scripts", "install-codex-mcp.sh"), path.join(packageRoot, "scripts", "install-codex-mcp.sh"));
  cpSync(path.join(repoRoot, "scripts", "install-opencode-mcp.sh"), path.join(packageRoot, "scripts", "install-opencode-mcp.sh"));
  cpSync(path.join(repoRoot, "scripts", "install-codex-plugin.sh"), path.join(packageRoot, "scripts", "install-codex-plugin.sh"));

  for (const scriptName of [
    "install-claude-mcp.sh",
    "install-gemini-mcp.sh",
    "install-codex-mcp.sh",
    "install-opencode-mcp.sh",
    "install-codex-plugin.sh",
  ]) {
    chmodSync(path.join(packageRoot, "scripts", scriptName), 0o755);
  }
}

function assertFileExists(filePath, packageName) {
  if (!existsSync(filePath)) {
    throw new Error(`Missing artifact for ${packageName}: ${filePath}. Run without --skip-build first.`);
  }
}

function copyBundledRuntimes(packageRoot, packageName) {
  const distRoot = path.join(packageRoot, "dist");
  mkdirSync(distRoot, { recursive: true });

  const macosSourcePath = path.join(repoRoot, "dist", appBundleName);
  const macosDestinationPath = path.join(distRoot, appBundleName);
  assertFileExists(macosSourcePath, packageName);
  cpSync(macosSourcePath, macosDestinationPath, { recursive: true });

  for (const platformDir of ["linux", "windows"]) {
    const sourcePath = path.join(repoRoot, "dist", platformDir);
    const destinationPath = path.join(distRoot, platformDir);
    assertFileExists(sourcePath, packageName);
    cpSync(sourcePath, destinationPath, { recursive: true });
  }

  for (const runtimeTarget of runtimeTargets) {
    const executablePath = path.join(packageRoot, ...runtimeTarget.executablePath);
    assertFileExists(executablePath, packageName);
    if (runtimeTarget.kind !== "macos-app") {
      chmodSync(executablePath, 0o755);
    }
  }
}

function stageMetaPackage(packageName, version, outDir) {
  const packageRoot = path.join(outDir, packageName);
  rmSync(packageRoot, { recursive: true, force: true });

  mkdirSync(path.join(packageRoot, ".agents", "plugins"), { recursive: true });
  mkdirSync(path.join(packageRoot, "bin"), { recursive: true });
  mkdirSync(path.join(packageRoot, "dist"), { recursive: true });
  mkdirSync(path.join(packageRoot, "plugins"), { recursive: true });
  mkdirSync(path.join(packageRoot, "scripts"), { recursive: true });

  cpSync(path.join(repoRoot, ".agents", "plugins", "marketplace.json"), path.join(packageRoot, ".agents", "plugins", "marketplace.json"));
  cpSync(path.join(repoRoot, "plugins", "open-computer-use"), path.join(packageRoot, "plugins", "open-computer-use"), {
    recursive: true,
  });
  cpSync(path.join(repoRoot, "LICENSE"), path.join(packageRoot, "LICENSE"));
  copyBundledRuntimes(packageRoot, packageName);
  copyInstallerScripts(packageRoot);

  const launcher = renderLauncher();
  writeExecutable(path.join(packageRoot, "bin", "open-computer-use"), launcher);
  writeExecutable(path.join(packageRoot, "bin", "ocu"), launcher);
  writeExecutable(path.join(packageRoot, "bin", "open-computer-use-mcp"), launcher);
  writeExecutable(path.join(packageRoot, "bin", "open-codex-computer-use-mcp"), launcher);
  writeFileSync(path.join(packageRoot, "scripts", "postinstall.mjs"), renderPostinstall(packageName, version), "utf-8");
  writeFileSync(path.join(packageRoot, "README.md"), renderReadme(packageName, version), "utf-8");
  writeFileSync(path.join(packageRoot, "package.json"), `${JSON.stringify(renderMetaPackageJson(packageName, version), null, 2)}\n`, "utf-8");

  removeJunkFiles(packageRoot);
}

function stagePackage(packageName, version, outDir) {
  if (!metaPackageNames.includes(packageName)) {
    throw new Error(`Unsupported package name: ${packageName}`);
  }

  stageMetaPackage(packageName, version, outDir);
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
