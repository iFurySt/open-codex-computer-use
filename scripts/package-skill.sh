#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skills_root="${repo_root}/skills"
dist_dir="${repo_root}/dist/skills"
manifest_path="${dist_dir}/package-manifest.json"

if ! command -v node >/dev/null 2>&1; then
  echo "node is required to validate the skill package" >&2
  exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
  echo "zip is required to package the skill" >&2
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "unzip is required to validate the skill package" >&2
  exit 1
fi

skill_dirs=()
while IFS= read -r skill_entrypoint; do
  skill_dirs+=("$(dirname "${skill_entrypoint}")")
done < <(find "${skills_root}" -mindepth 2 -maxdepth 2 -name SKILL.md -print | sort)

if [[ "${#skill_dirs[@]}" -eq 0 ]]; then
  echo "missing skill entrypoints under ${skills_root}" >&2
  exit 1
fi

rm -rf "${dist_dir}"
mkdir -p "${dist_dir}"

manifest_entries=()

for skill_dir in "${skill_dirs[@]}"; do
  skill_name="$(basename "${skill_dir}")"
  zip_path="${dist_dir}/${skill_name}-skill.zip"
  skill_path="${dist_dir}/${skill_name}.skill"

  node - "${skill_dir}/SKILL.md" "${skill_name}" <<'NODE'
const fs = require("fs");

const skillPath = process.argv[2];
const expectedName = process.argv[3];
const content = fs.readFileSync(skillPath, "utf8");
const errors = [];

if (!content.startsWith("---\n")) {
  errors.push("SKILL.md must start with YAML frontmatter");
}
if (!new RegExp(`^name:\\s*${expectedName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*$`, "m").test(content)) {
  errors.push(`SKILL.md frontmatter must include name: ${expectedName}`);
}
if (!/^description:\s*\S/m.test(content)) {
  errors.push("SKILL.md frontmatter must include a non-empty description");
}

if (errors.length > 0) {
  for (const error of errors) {
    console.error(error);
  }
  process.exit(1);
}
NODE

  (
    cd "${skills_root}"
    zip -q -r "${zip_path}" "${skill_name}"
  )
  cp "${zip_path}" "${skill_path}"

  if ! cmp -s "${zip_path}" "${skill_path}"; then
    echo "${skill_name}-skill.zip and ${skill_name}.skill differ" >&2
    exit 1
  fi

  has_skill_entrypoint=0
  entry_count=0
  while IFS= read -r entry; do
    entry_count=$((entry_count + 1))
    if [[ "${entry}" != "${skill_name}/"* ]]; then
      echo "skill zip entry must be under ${skill_name}/: ${entry}" >&2
      exit 1
    fi
    if [[ "${entry}" == "${skill_name}/SKILL.md" ]]; then
      has_skill_entrypoint=1
    fi
  done < <(unzip -Z1 "${zip_path}")

  if [[ "${entry_count}" -eq 0 ]]; then
    echo "${skill_name} skill zip is empty" >&2
    exit 1
  fi

  if [[ "${has_skill_entrypoint}" -ne 1 ]]; then
    echo "skill zip is missing ${skill_name}/SKILL.md" >&2
    exit 1
  fi

  manifest_entries+=("${skill_name}|${zip_path}|${skill_path}")
done

node - "${repo_root}" "${manifest_path}" "${manifest_entries[@]}" <<'NODE'
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const repoRoot = process.argv[2];
const manifestPath = process.argv[3];
const entries = process.argv.slice(4);

const skills = entries.map((entry) => {
  const [name, zipPath, skillPath] = entry.split("|");
  const zip = fs.readFileSync(zipPath);
  const skill = fs.readFileSync(skillPath);
  const zipSha = crypto.createHash("sha256").update(zip).digest("hex");
  const skillSha = crypto.createHash("sha256").update(skill).digest("hex");

  if (zipSha !== skillSha) {
    throw new Error(`${name}-skill.zip and ${name}.skill must contain identical bytes`);
  }

  return {
    name,
    rootDirectory: name,
    artifacts: {
      zip: path.relative(repoRoot, zipPath),
      skill: path.relative(repoRoot, skillPath)
    },
    sha256: {
      zip: zipSha,
      skill: skillSha
    }
  };
});

const primarySkill = skills.find((skill) => skill.name === "open-computer-use") ?? skills[0];
const payload = {
  name: primarySkill.name,
  rootDirectory: primarySkill.rootDirectory,
  artifacts: primarySkill.artifacts,
  sha256: primarySkill.sha256,
  generatedAtUtc: new Date().toISOString(),
  skills
};

fs.writeFileSync(manifestPath, `${JSON.stringify(payload, null, 2)}\n`);
NODE

for entry in "${manifest_entries[@]}"; do
  IFS="|" read -r _ zip_path skill_path <<<"${entry}"
  echo "${zip_path}"
  echo "${skill_path}"
done
