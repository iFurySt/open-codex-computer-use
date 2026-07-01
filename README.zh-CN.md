# open-computer-use

[![English](https://img.shields.io/badge/English-Click-yellow)](./README.md)
[![简体中文](https://img.shields.io/badge/简体中文-点击查看-orange)](./README.zh-CN.md)
[![Release](https://img.shields.io/github/v/release/iFurySt/open-codex-computer-use)](https://github.com/iFurySt/open-codex-computer-use/releases)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/iFurySt/open-codex-computer-use)
<a href="https://llmapis.com?source=https%3A%2F%2Fgithub.com%2FiFurySt%2Fopen-codex-computer-use" target="_blank"><img src="https://llmapis.com/api/badge/iFurySt/open-codex-computer-use" alt="LLMAPIS" width="20" /></a>

> [!TIP]
> 对 Browser Use 感兴趣的话，可以看看 [open-browser-use](https://github.com/iFurySt/open-codex-browser-use)。

---

`open-computer-use` 是一个开源的 `Computer Use` 服务，已经包装成 `MCP` 协议，支持所有的 AI Agent 或 MCP Client 快速调用，实现 macOS、Linux 和 Windows 上的 `Computer Use` 能力。

项目的背后是 OpenAI 刚发布的 [Codex Computer Use](https://openai.com/index/codex-for-almost-everything/)，让我看到了基于 Accessibility 可以实现非抢占式 CUA 能力，因此决定复刻一个开源版本

在这期间我利用了之前写的 [harness 模版](https://github.com/iFurySt/harness-template) 开启了这个新项目。这是一个可以快速拉起面向 AI 仓库的 template，非常适合 100% AI-Generated 的项目，也是这一个月来我们最大的实践和收获。现在我们可以基于这套方法论快速实现很多东西；如果你有兴趣，我也写了一篇[文章](https://www.ifuryst.com/blog/2026/speedrunning-the-ai-era/)专门介绍这套方法论

## 演示

### Codex App 和 Codex CLI

[![open-computer-use 自定义演示封面](./docs/generated/readme-assets/open-computer-use-demo-cover.png)](https://youtu.be/2s6aVpGiwaQ)

<sub><em>`open-computer-use` 作为 Computer Use，在 Codex App 和 Codex CLI 里使用，和官方体验一致。</em></sub>

### Gemini CLI

https://github.com/user-attachments/assets/eacb3b15-f939-46c7-b3b3-6f876977a58d

<sub><em>Gemini CLI 通过MCP接入使用 `open-computer-use`，实现完整的 Computer Use 操作。</em></sub>

### Linux

https://github.com/user-attachments/assets/e036b1c8-2200-4896-abd4-19225915cf66

<sub><em>`open-computer-use` 在 Linux 里使用</em></sub>

## Quick Start

```bash
npm i -g open-computer-use
```

通过 npm 安装后也会同时提供短命令 `ocu`。

**macOS 第一次使用前，需要授权 `Accessibility` 和 `Screen Recording` 的权限，windows和linux无需执行**
```bash
open-computer-use
# 或
ocu
```

开始用前可以通过一键安装到主流的Agent里：
```bash
# 一键安装到 Codex，写到 ~/.codex/config.toml 中
open-computer-use install-codex-mcp
ocu install-codex-mcp
```

也可以手动配置到你自己的客户端里：

```json
{
  "mcpServers": {
    "open-computer-use": {
      "command": "open-computer-use",
      "args": ["mcp"]
    }
  }
}
```

### Skill

一键安装skill：

```bash
# 安装到 Codex
npx skills add iFurySt/open-codex-computer-use -g -a codex --skill open-computer-use -y
npx skills ls -g -a codex | rg 'open-computer-use'
```

如果只需要 macOS 录制工作流并生成可复用 skill，可以安装独立的
Record & Replay workflow skill：

```bash
npx skills add iFurySt/open-codex-computer-use -g -a codex --skill open-computer-use-record-and-replay -y
```

安装到 Claude Code
```
npx skills add iFurySt/open-codex-computer-use -g -a claude-code --skill open-computer-use -y
npx skills add iFurySt/open-codex-computer-use -g -a claude-code --skill open-computer-use-record-and-replay -y
```

更新已有的全局安装，包括上面安装到 Codex 的那份：

```bash
npx skills update open-computer-use -g -y
npx skills update open-computer-use-record-and-replay -g -y
```

也可以手动下载 [`open-computer-use` skill](./skills/open-computer-use) 或
[`open-computer-use-record-and-replay` skill](./skills/open-computer-use-record-and-replay) 安装

### Record & Replay 快速开始

当你想让用户演示一个 macOS 工作流，并把录制结果转成可复用 skill 时，使用独立的
Record & Replay MCP surface：

```bash
# 安装官方兼容的 Record & Replay 三件套 MCP surface 到 Codex
open-computer-use install-codex-record-and-replay-mcp
```

这个 MCP surface 只暴露官方兼容的三个工具：

```text
event_stream_start
event_stream_status
event_stream_stop
```

OCU 自己的控制条、等待和回调能力放在 CLI 扩展层：

```bash
# 通过 OCU app agent 开始录制，并显示本地控制条
open-computer-use event-stream start --json

# 独立 wrapper 可以等待用户点击 Done / Discard 后继续
open-computer-use event-stream wait --json --session-id <id> --notify-command '["/path/to/hook"]'

# 校验完成态 session，并生成第一版 skill 草稿
open-computer-use event-stream validate --json --strict-ocu --require-skill-draft <metadataPath-or-sessionPath>
open-computer-use event-stream summarize --json <metadataPath-or-sessionPath>
open-computer-use event-stream scaffold-skill --json <metadataPath-or-sessionPath-or-eventsPath> \
  --skill-name <new-skill-name> \
  --description "<what it does>" \
  --output-dir <new-skill-dir>
```

如果要把 Record & Replay 拆成独立 thin skill repo：

```bash
open-computer-use scaffold-record-and-replay-skill-repo --output-dir ./open-computer-use-rnr-skill-repo
(cd ./open-computer-use-rnr-skill-repo && ./scripts/check.sh)
```

## 更多

除了直接用上面的 MCP JSON 配置，你也可以用一些内置子命令：

```bash
# 一键安装到 Codex，写到 ~/.codex/config.toml 中
open-computer-use install-codex-mcp

# 单独安装 Record & Replay MCP surface，写到 ~/.codex/config.toml 中
open-computer-use install-codex-record-and-replay-mcp

# 一键安装到 Codex 插件，主要方便在 Codex App 中使用
open-computer-use install-codex-plugin

# 一键安装到 Claude Code，写到 ~/.claude.json 中
open-computer-use install-claude-mcp

# 一键安装到 Gemini CLI 当前项目，写到 ./.gemini/settings.json
open-computer-use install-gemini-mcp

# 一键安装到 Gemini CLI 用户级配置
open-computer-use install-gemini-mcp --scope user

# 一键安装到 opencode，写到 ~/.config/opencode/opencode.json（或当前生效的配置文件）
open-computer-use install-opencode-mcp

# 直接调用单个 Computer Use tool，输出 MCP 风格的 JSON result
open-computer-use call list_apps
ocu call list_apps
open-computer-use call get_app_state --args '{"app":"TextEdit"}'

# 在同一个进程里编排连续动作，复用 get_app_state 拿到的 element_index
# 连续动作默认会在成功的相邻操作之间 sleep 1 秒
open-computer-use call --calls '[{"tool":"get_app_state","args":{"app":"TextEdit"}},{"tool":"press_key","args":{"app":"TextEdit","key":"Return"}}]'
open-computer-use call --calls-file examples/textedit-overlay-seq.json --sleep 0.5

# 检查权限；只有缺失时才会拉起引导，已全部授权则只打印状态并退出
open-computer-use doctor

# Record & Replay 兼容 event stream
open-computer-use event-stream mcp
open-computer-use event-stream start --json
open-computer-use event-stream status --json
open-computer-use event-stream stop --json
open-computer-use event-stream cancel --json
open-computer-use event-stream wait --json --session-id <id> --timeout 30
open-computer-use event-stream validate --json --strict-ocu <metadataPath>
open-computer-use event-stream scaffold-skill --json <metadataPath-or-eventsPath> --skill-name <new-skill-name> --description "<what it does>" --output-dir <new-skill-dir>

# 导入官方 hosted Record & Replay 返回的录制样本，生成脱敏 fixture 并跑 readiness
# 建议先 inspect，不创建 fixture，只确认 hosted JSON 能解析出 handoff path 和 transcript 证据
scripts/ingest-official-record-and-replay-fixture.py --status-json <event_stream_stop-response.json> --name <fixture-name> --scenario simple-action-stop --mcp-transcript <mcp-transcript.json> --require-mcp-transcript-evidence --inspect-only
scripts/ingest-official-record-and-replay-fixture.py --status-json <event_stream_stop-response.json> --name <fixture-name> --scenario simple-action-stop --mcp-transcript <mcp-transcript.json> --require-mcp-transcript-evidence --check-fixture-set --check-coverage
# 也可以先生成 capture packet；替换其中的 hosted JSON 占位文件后，按 wrapper 顺序校验、inspect、导入和刷新 strict artifact
make record-and-replay-official-golden-capture-packet RNR_SCENARIO=simple-action-stop RNR_PACKET_DIR=<packet-dir>
scripts/finalize-record-and-replay-official-capture-packet.py --packet-dir <packet-dir> --start-json <event_stream_start-response.json> --status-json <event_stream_status-active-response.json> --stop-json <event_stream_stop-response.json> --final-status-json <event_stream_status-final-response.json>
(cd <packet-dir> && ./verify-inputs.sh && ./inspect-only.sh && ./import-fixture.sh)
(cd <packet-dir> && ./strict-golden-gate.sh)
# 只有 required official golden 缺失或 readiness 未过时，才审计 strict 预期失败 artifact
(cd <packet-dir> && ./strict-expected-failure-audit.sh)
# 生成 required + recommended capture packet set 和批量 wrapper
make record-and-replay-official-golden-capture-packet-set RNR_PACKET_DIR=<packet-dir>
(cd <packet-dir> && ./verify-all.sh && ./inspect-all.sh && ./import-all.sh)
# 可选校准：导入同场景 OCU candidate，并打印后续 pairing / fixture-set 命令
(cd <packet-dir> && ./ingest-ocu-candidates.sh)
(cd <packet-dir> && ./strict-expected-failure-audit.sh)
# 也可以从 stdin 传入单独的 transcript JSON，此时 status JSON 需要来自文件
cat <mcp-transcript.json> | scripts/ingest-official-record-and-replay-fixture.py --status-json <event_stream_stop-response.json> --mcp-transcript - --name <fixture-name> --scenario simple-action-stop --require-mcp-transcript-evidence --check-fixture-set --check-coverage
# 也可以直接通过 stdin 管道传入 hosted event_stream_stop/status JSON；如果里面是相对路径，用 --status-json-base-dir 指定解析基准目录
cat <event_stream_stop-response.json> | scripts/ingest-official-record-and-replay-fixture.py --status-json - --status-json-base-dir <recording-parent-dir> --name <fixture-name> --scenario simple-action-stop --use-status-json-as-transcript --require-mcp-transcript-evidence --check-fixture-set --check-coverage
# --check-coverage 会报告 required 场景覆盖，并在样本存在时同步跑 required fixture readiness
# 采集 required 场景后可以用 --require-coverage，让导入后覆盖率或 readiness 不满足时直接失败
scripts/ingest-official-record-and-replay-fixture.py --status-json <event_stream_stop-response.json> --name <fixture-name> --scenario simple-action-stop --require-coverage
# 单独检查仓库里的 required official successful recording fixture 覆盖；排查缺失时可用 --allow-missing 只输出报告
scripts/check-event-stream-official-fixture-coverage.py --allow-missing --check-readiness
# 导入 OCU action smoke 或本地 recording，生成同 scenario 的 candidate fixture
# --smoke-json 会自动消费 action smoke 输出里的 mcpTranscriptPath。
# 如果要保存 stdout 后再导入，需要保留 smoke 临时目录：
#   OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_KEEP_TMP=1 make event-stream-action-smoke > /tmp/action-smoke.jsonl
# action smoke 默认跑 mixed-action-stop；设置 OPEN_COMPUTER_USE_EVENT_STREAM_SMOKE_ACTION_SCENARIO=simple-action-stop
# 或 drag-stop 可以采样指定真实输入 candidate 场景。
# 也可以让导入脚本自己跑 action smoke，并在导入完成前保留证据：
#   scripts/ingest-ocu-record-and-replay-candidate.py --run-action-smoke --scenario drag-stop ...
scripts/ingest-ocu-record-and-replay-candidate.py --smoke-json <action-smoke-output.jsonl> --name <candidate-name> --scenario simple-action-stop --official-root <official-fixtures> --check-fixture-set
# opt-in baseline：证明当前 OCU baseline 可用，并报告官方 golden 场景覆盖
make record-and-replay-baseline-smoke
# release / standalone 留证入口：写出 dist/record-and-replay-baseline-summary.json
make record-and-replay-baseline-audit
# 快速 fixture-only gate：要求入库的官方 successful recording 通过 readiness
make record-and-replay-official-golden-fixture-gate
# 只读下一步规划：官方 fixture 入库后，生成同 scenario OCU candidate 采样/导入/配对命令
make record-and-replay-ocu-candidate-pairing-preflight
# 严格 release gate：同样跑 baseline 检查，并要求 required 官方 successful recording readiness 通过
make record-and-replay-official-golden-gate
# 严格 release 留证入口：写出 dist/record-and-replay-official-golden-gate-summary.json；
# required 官方 golden 缺失或未 ready 时，用 allow-missing 模式确认这是预期失败而不是 baseline 回归
make record-and-replay-official-golden-gate-audit
scripts/check-record-and-replay-baseline-summary.py dist/record-and-replay-official-golden-gate-summary.json --allow-strict-official-golden-missing

# 查看帮助
open-computer-use -h
ocu -h
```

## Cursor Motion

Cursor Motion 是一个面向 macOS 的开源光标运动系统，基于 Software.Inc 几位大佬的公开信息实现的开源版本，也可以到 [Releases 页面](https://github.com/iFurySt/open-codex-computer-use/releases) 下载 app 运行。

[![Cursor Motion 自定义演示封面](./docs/generated/readme-assets/cursor-motion-demo-cover.png)](https://youtu.be/KRUq5GUHv1Q)

## Star History

<a href="https://www.star-history.com/?repos=iFurySt%2Fopen-codex-computer-use&type=date&legend=top-left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=ifuryst/open-codex-computer-use&type=date&theme=dark&legend=top-left" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=ifuryst/open-codex-computer-use&type=date&legend=top-left" />
    <img alt="open-computer-use Star History 趋势图" src="https://api.star-history.com/chart?repos=ifuryst/open-codex-computer-use&type=date&legend=top-left" />
  </picture>
</a>

## License

[MIT](./LICENSE)
