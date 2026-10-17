#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "用法: $0 <项目名>" >&2
  exit 1
fi

project_name="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

perl -0pi -e "s/open-(?:codex-)?computer-use/${project_name}/g; s/harness-template/${project_name}/g" \
  "${repo_root}/README.md" \
  "${repo_root}/AGENTS.md"

echo "已将模板名称初始化为: ${project_name}"
echo "下一步建议: 补齐 docs/ARCHITECTURE.md 和 docs/product-specs/ 中的真实项目信息"
