#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const repositoryURL = "https://github.com/iFurySt/open-computer-use";
// Published notes retain their original URLs across the repository rename.
const legacyRepositoryURL = "https://github.com/iFurySt/open-codex-computer-use";
const tagPattern = /^v?(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)$/;
const cjkPattern = /[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]/u;

function fail(message) {
  throw new Error(message);
}

function parseArgs(argv) {
  const options = {
    notesOnly: false,
    notesPath: undefined,
    tag: undefined,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];

    switch (arg) {
      case "--notes-only":
        options.notesOnly = true;
        break;
      case "--notes-path":
        options.notesPath = argv[index + 1];
        index += 1;
        break;
      case "--tag":
        options.tag = argv[index + 1];
        index += 1;
        break;
      default:
        fail(`Unknown argument: ${arg}`);
    }
  }

  if (!options.tag) {
    fail("Usage: validate-github-release-notes.mjs --tag <vX.Y.Z> [--notes-only] [--notes-path <path>]");
  }

  return options;
}

function validateNotes({ notesPath, tag }) {
  if (!existsSync(notesPath)) {
    fail(`Missing reviewed GitHub Release notes: ${path.relative(repoRoot, notesPath)}`);
  }

  const body = readFileSync(notesPath, "utf8").replaceAll("\r\n", "\n");
  if (!body.endsWith("\n")) {
    fail("Release notes must end with a newline");
  }
  if (cjkPattern.test(body)) {
    fail("Release notes must use reviewed English and cannot contain CJK characters");
  }

  const lines = body.trimEnd().split("\n");
  if (lines[0] !== "## What's Changed") {
    fail("Release notes must start with exactly: ## What's Changed");
  }

  const nextHeadingIndex = lines.findIndex((line, index) => index > 0 && line.startsWith("## "));
  const whatsChangedLines = nextHeadingIndex === -1 ? lines.slice(1) : lines.slice(1, nextHeadingIndex);
  const changeItems = whatsChangedLines.filter((line) => line.startsWith("* "));
  if (changeItems.length < 1 || changeItems.length > 3) {
    fail("What's Changed must contain 1 to 3 user-visible bullet items");
  }

  const changelogLines = lines.filter((line) => line.startsWith("**Full Changelog**:"));
  if (changelogLines.length !== 1) {
    fail("Release notes must contain exactly one Full Changelog line");
  }

  const changelogLine = changelogLines[0];
  const changelogPrefix = [repositoryURL, legacyRepositoryURL]
    .map((url) => `**Full Changelog**: ${url}/compare/`)
    .find((prefix) => changelogLine.startsWith(prefix));
  if (!changelogPrefix || !changelogLine.endsWith(`...${tag}`)) {
    fail(`Full Changelog must use ${repositoryURL}/compare/<previous-tag>...${tag}`);
  }

  const previousTag = changelogLine.slice(changelogPrefix.length, -(`...${tag}`.length));
  if (!tagPattern.test(previousTag) || previousTag === tag) {
    fail("Full Changelog must reference a different semantic previous tag");
  }

  return changeItems.length;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const tagMatch = options.tag.match(tagPattern);
  if (!tagMatch) {
    fail(`Release tag must match vX.Y.Z or X.Y.Z: ${options.tag}`);
  }

  const version = tagMatch[1];
  const notesPath = path.resolve(
    repoRoot,
    options.notesPath ?? path.join("docs", "releases", "github", `${options.tag}.md`)
  );

  if (!options.notesOnly) {
    const manifestPath = path.join(repoRoot, "plugins", "open-computer-use", ".codex-plugin", "plugin.json");
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    if (manifest.version !== version) {
      fail(`Tag ${options.tag} does not match plugin manifest version ${manifest.version}`);
    }
  }

  const changeCount = validateNotes({ notesPath, tag: options.tag });
  console.log(
    `Validated ${path.relative(repoRoot, notesPath)} for ${options.tag}: ${changeCount} user-visible change item(s)`
  );
}

try {
  main();
} catch (error) {
  console.error(`Release notes validation failed: ${error.message}`);
  process.exit(1);
}
