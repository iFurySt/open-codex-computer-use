#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
用法:
  ./scripts/start-codex-mitm-dump.sh [session-name]

说明:
  后台启动 mitmdump，并把抓包样本写到 artifacts/codex-dumps/<session-name>/。
  如果不传 session-name，则默认使用时间戳自动生成目录。

可选环境变量:
  MITM_LISTEN_HOST      监听地址，默认 127.0.0.1
  MITM_LISTEN_PORT      监听端口，默认 8082
  MITM_CA_CERT          mitm CA 证书路径，默认 $HOME/.mitmproxy/mitmproxy-ca-cert.pem
  CODEX_DUMP_BASE_DIR   抓包输出根目录，默认 <repo>/artifacts/codex-dumps
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
listen_host="${MITM_LISTEN_HOST:-127.0.0.1}"
listen_port="${MITM_LISTEN_PORT:-8082}"
ca_cert="${MITM_CA_CERT:-${HOME}/.mitmproxy/mitmproxy-ca-cert.pem}"
dump_base_dir="${CODEX_DUMP_BASE_DIR:-${repo_root}/artifacts/codex-dumps}"
addon_script="${repo_root}/scripts/codex_dump.py"
timestamp="$(date +%Y%m%d-%H%M%S)"
session_name="${1:-${timestamp}-codex-capture}"
session_dir="${dump_base_dir}/${session_name}"
log_path="${session_dir}/mitmdump.log"
pid_path="${session_dir}/mitmdump.pid"
env_path="${session_dir}/codex-proxy.env"

if ! command -v mitmdump >/dev/null 2>&1; then
  echo "未找到 mitmdump，请先安装 mitmproxy。" >&2
  exit 1
fi

if [[ ! -f "${addon_script}" ]]; then
  echo "缺少抓包 addon: ${addon_script}" >&2
  exit 1
fi

if [[ ! -f "${ca_cert}" ]]; then
  echo "未找到 mitm CA 证书: ${ca_cert}" >&2
  exit 1
fi

if lsof -nP -iTCP:"${listen_port}" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "端口 ${listen_port} 已被占用，请调整 MITM_LISTEN_PORT。" >&2
  exit 1
fi

if [[ -e "${session_dir}" ]]; then
  if find "${session_dir}" -mindepth 1 -maxdepth 1 | read -r _; then
    echo "session 目录已存在且非空: ${session_dir}" >&2
    exit 1
  fi
else
  mkdir -p "${session_dir}"
fi

cat >"${env_path}" <<EOF
export HTTPS_PROXY="http://${listen_host}:${listen_port}"
export NO_PROXY="127.0.0.1,localhost"
export SSL_CERT_FILE="${ca_cert}"
EOF

nohup mitmdump \
  --listen-host "${listen_host}" \
  --listen-port "${listen_port}" \
  -s "${addon_script}" \
  --set codex_dump_dir="${session_dir}" \
  >"${log_path}" 2>&1 &

pid=$!
echo "${pid}" >"${pid_path}"

sleep 1

if ! kill -0 "${pid}" >/dev/null 2>&1; then
  echo "mitmdump 启动失败，最近日志：" >&2
  if [[ -f "${log_path}" ]]; then
    tail -n 40 "${log_path}" >&2
  fi
  exit 1
fi

cat <<EOF
mitmdump 已后台启动。

session_dir: ${session_dir}
pid: ${pid}
log: ${log_path}
env: ${env_path}

后续让 Codex 走代理时，可直接执行：

  source "${env_path}"
  codex exec --skip-git-repo-check -C /tmp 'reply with one word: ok'

停止抓包：

  kill "${pid}"
EOF
