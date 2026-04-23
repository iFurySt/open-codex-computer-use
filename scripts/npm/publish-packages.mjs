#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..", "..");
const maxPublishAttempts = 3;

function printHelp() {
  process.stdout.write(`Usage: node ./scripts/npm/publish-packages.mjs [options]

Options:
  --configuration debug|release
  --arch native|arm64|x86_64|universal
  --out-dir <dir>
  --package <package-name>
  --tag <dist-tag>
  --dry-run
  --skip-build
  --provenance
`);
}

function parseArgs(argv) {
  const options = {
    buildArgs: [],
    dryRun: false,
    outDir: path.join(repoRoot, "dist", "npm"),
    provenance: false,
    tag: "",
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case "--configuration":
      case "--arch":
      case "--package":
      case "--out-dir":
        options.buildArgs.push(arg, argv[index + 1]);
        if (arg === "--out-dir") {
          options.outDir = path.resolve(repoRoot, argv[index + 1]);
        }
        index += 1;
        break;
      case "--skip-build":
        options.buildArgs.push(arg);
        break;
      case "--tag":
        options.tag = argv[index + 1];
        index += 1;
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      case "--provenance":
        options.provenance = true;
        break;
      case "-h":
      case "--help":
        printHelp();
        process.exit(0);
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return options;
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

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function readPackageMetadata(packageDir) {
  const packageJSON = JSON.parse(readFileSync(path.join(packageDir, "package.json"), "utf-8"));
  return {
    name: packageJSON.name,
    version: packageJSON.version,
  };
}

function publishPriority(packageName) {
  if (/^open-computer-use-(darwin|linux|win32)-/.test(packageName)) {
    return 0;
  }
  return 1;
}

function npmPackageVersionExists(packageName, version, env) {
  const result = spawnSync("npm", ["view", `${packageName}@${version}`, "version", "--json"], {
    cwd: repoRoot,
    encoding: "utf-8",
    env,
  });

  if (result.status === 0) {
    return true;
  }

  const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
  if (output.includes("E404") || output.includes("404 Not Found")) {
    return false;
  }

  process.stderr.write(`Could not confirm whether ${packageName}@${version} already exists; attempting publish.\n`);
  return false;
}

function publishEnvCandidates(baseEnv) {
  const candidates = [];

  if (baseEnv.ACTIONS_ID_TOKEN_REQUEST_URL) {
    const oidcEnv = { ...baseEnv };
    delete oidcEnv.NODE_AUTH_TOKEN;
    delete oidcEnv.NPM_TOKEN;
    delete oidcEnv.NPM_CONFIG_USERCONFIG;
    delete oidcEnv.NPM_ID_TOKEN;
    candidates.push({
      env: oidcEnv,
      label: "GitHub Actions OIDC trusted publishing",
      provenance: true,
    });
  }

  if (baseEnv.NODE_AUTH_TOKEN) {
    const tokenEnv = { ...baseEnv };
    delete tokenEnv.ACTIONS_ID_TOKEN_REQUEST_URL;
    delete tokenEnv.ACTIONS_ID_TOKEN_REQUEST_TOKEN;
    delete tokenEnv.NPM_ID_TOKEN;
    candidates.push({
      env: tokenEnv,
      label: "NODE_AUTH_TOKEN fallback",
      provenance: false,
    });
  }

  if (candidates.length === 0) {
    candidates.push({
      env: baseEnv,
      label: "default npm environment",
      provenance: false,
    });
  }

  return candidates;
}

function publishWithRetry(args, npmEnvCandidates, packageName, version) {
  if (npmPackageVersionExists(packageName, version, npmEnvCandidates[0].env)) {
    process.stdout.write(`${packageName}@${version} already exists on npm; skipping publish.\n`);
    return;
  }

  let lastError;

  for (const { env, label, provenance } of npmEnvCandidates) {
    process.stdout.write(`Publishing ${packageName}@${version} using ${label}.\n`);
    const publishArgs = provenance && !args.includes("--provenance") ? [...args, "--provenance"] : args;

    for (let attempt = 1; attempt <= maxPublishAttempts; attempt += 1) {
      const result = spawnSync("npm", publishArgs, {
        cwd: repoRoot,
        stdio: "inherit",
        env,
      });

      if (result.status === 0) {
        return;
      }

      if (npmPackageVersionExists(packageName, version, env)) {
        process.stdout.write(`${packageName}@${version} is visible on npm after publish failure; continuing.\n`);
        return;
      }

      lastError = new Error(`npm ${publishArgs.join(" ")} failed with exit code ${result.status ?? "unknown"}`);

      if (attempt < maxPublishAttempts) {
        const delayMs = attempt * 5000;
        process.stderr.write(
          `npm publish ${packageName}@${version} via ${label} failed with exit code ${result.status ?? "unknown"}; retrying in ${delayMs / 1000}s.\n`
        );
        sleep(delayMs);
        continue;
      }

      if (npmEnvCandidates.length > 1 && label !== npmEnvCandidates[npmEnvCandidates.length - 1].label) {
        process.stderr.write(`npm publish ${packageName}@${version} via ${label} failed; trying next auth path.\n`);
      }
    }
  }

  throw lastError ?? new Error(`npm ${args.join(" ")} failed`);
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const usingTrustedPublishing = Boolean(process.env.ACTIONS_ID_TOKEN_REQUEST_URL);

  if (!options.dryRun && !process.env.NODE_AUTH_TOKEN && !usingTrustedPublishing) {
    throw new Error("npm publish requires either NODE_AUTH_TOKEN or GitHub Actions OIDC trusted publishing.");
  }

  run("node", [path.join(repoRoot, "scripts", "npm", "build-packages.mjs"), ...options.buildArgs]);

  const packageDirsResult = spawnSync(
    "find",
    [options.outDir, "-mindepth", "1", "-maxdepth", "1", "-type", "d"],
    {
      cwd: repoRoot,
      encoding: "utf-8",
    }
  );

  if (packageDirsResult.status !== 0) {
    throw new Error(`Failed to enumerate staged packages in ${options.outDir}`);
  }

  const packageDirs = packageDirsResult.stdout
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .sort((left, right) => {
      const leftName = JSON.parse(readFileSync(path.join(left, "package.json"), "utf-8")).name;
      const rightName = JSON.parse(readFileSync(path.join(right, "package.json"), "utf-8")).name;
      return publishPriority(leftName) - publishPriority(rightName) || leftName.localeCompare(rightName);
    });

  for (const packageDir of packageDirs) {
    const { name: packageName, version } = readPackageMetadata(packageDir);
    const args = ["publish", packageDir, "--access", "public"];
    if (options.tag) {
      args.push("--tag", options.tag);
    }
    if (options.provenance) {
      args.push("--provenance");
    }
    if (options.dryRun) {
      args.push("--dry-run");
    }
    const npmEnv = {
      ...process.env,
    };

    publishWithRetry(args, publishEnvCandidates(npmEnv), packageName, version);
  }
}

main();
