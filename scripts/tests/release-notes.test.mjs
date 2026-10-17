import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const validator = fileURLToPath(new URL("../validate-github-release-notes.mjs", import.meta.url));

function validateChangelog(url) {
  const directory = mkdtempSync(path.join(os.tmpdir(), "ocu-release-notes-"));
  const notesPath = path.join(directory, "notes.md");
  try {
    writeFileSync(notesPath, `## What's Changed\n\n* Keep existing installations compatible after the repository rename.\n\n**Full Changelog**: ${url}\n`);
    return spawnSync(process.execPath, [validator, "--tag", "v1.1.2", "--notes-only", "--notes-path", notesPath], {
      encoding: "utf8",
    });
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

for (const repository of ["open-computer-use", "open-codex-computer-use"]) {
  test(`accepts release notes from ${repository}`, () => {
    const result = validateChangelog(`https://github.com/iFurySt/${repository}/compare/v1.1.1...v1.1.2`);
    assert.equal(result.status, 0, result.stderr);
  });
}

test("rejects changelogs from unrelated repositories and lookalike URLs", () => {
  for (const repository of ["other/open-computer-use", "iFurySt/open-computer-use-other"]) {
    const result = validateChangelog(`https://github.com/${repository}/compare/v1.1.1...v1.1.2`);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Full Changelog must use/);
  }
});

test("keeps previous-tag and target-tag checks after the rename", () => {
  for (const comparison of ["v1.1.1...v1.1.3", "v1.1.2...v1.1.2", "main...v1.1.2"]) {
    const result = validateChangelog(`https://github.com/iFurySt/open-computer-use/compare/${comparison}`);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Full Changelog must/);
  }
});
