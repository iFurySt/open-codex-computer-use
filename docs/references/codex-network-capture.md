# Codex 上游抓包与评估样本沉淀

这份文档描述如何用 `mitmdump` + 仓库内的 `scripts/codex_dump.py` 抓取 Codex 到上游的 HTTP / WebSocket 流量，并把样本沉淀到仓库内的 `artifacts/codex-dumps/` 目录做后续分析和 eval。

默认排查顺序里，这份文档应该优先于 `docs/references/codex-local-runtime-logs.md`：

- 先看上游 LLM call dump。
- 只有当上游样本不足以解释本地 tool / MCP 行为时，才补查 Codex 自己的本地日志。

尤其是官方 `computer-use` 这类本地 `stdio` MCP，网络抓包通常只能回答“模型侧发生了什么”，不能完整回答“本地 tool 最终收到了什么参数、回了什么结果”；这类问题再切到本地日志路径更合适。

## 适用场景

- 观察 Codex 实际发往上游的请求形态。
- 记录不同 prompt / 配置 /模型下的真实响应轨迹。
- 为后续 eval、回归对比或逆向分析沉淀样本。
- 让 Agent 可以直接在后台启动抓包，再执行一批 Codex 用例。

## 目录约定

抓包结果推荐统一写到：

```text
artifacts/codex-dumps/<session-name>/
```

这个目录已经被 `.gitignore` 忽略，适合长期把真实样本保存在仓库工作区里而不误提交。

建议每次实验单独建一个 session 目录，例如：

```text
artifacts/codex-dumps/20260417-basic-ok/
artifacts/codex-dumps/20260417-tool-call-case-a/
artifacts/codex-dumps/20260417-reasoning-compare-gpt54/
```

## 前置条件

1. 本机已安装 `mitmproxy` / `mitmdump`。
2. mitm CA 文件存在：

```text
$HOME/.mitmproxy/mitmproxy-ca-cert.pem
```

3. 如需让 GUI app 也走代理，还需要把 mitm CA 导入并信任到系统钥匙串；但对 CLI 抓包，显式设置 `SSL_CERT_FILE` 通常就够用。

## 前台启动 mitmdump

最直接的前台跑法：

```bash
mitmdump \
  --listen-host 127.0.0.1 \
  --listen-port 8082 \
  -s scripts/codex_dump.py \
  --set codex_dump_dir=artifacts/codex-dumps/session-001
```

然后在另一个终端里让 Codex 走这个代理：

```bash
HTTPS_PROXY=http://127.0.0.1:8082 \
NO_PROXY=127.0.0.1,localhost \
SSL_CERT_FILE=$HOME/.mitmproxy/mitmproxy-ca-cert.pem \
codex exec --skip-git-repo-check -C /tmp 'reply with one word: ok'
```

## 后台启动 mitmdump

如果希望 Agent 或脚本自己在后台拉起抓包，优先直接用仓库内脚本：

```bash
./scripts/start-codex-mitm-dump.sh basic-ok
```

这个脚本会自动：

- 创建 `artifacts/codex-dumps/<session-name>/`
- 后台启动 `mitmdump`
- 写入 `mitmdump.log`
- 写入 `mitmdump.pid`
- 生成 `codex-proxy.env`，方便后续 `source`

最常见的后续用法是：

```bash
source artifacts/codex-dumps/basic-ok/codex-proxy.env
codex exec --skip-git-repo-check -C /tmp 'reply with one word: ok'
```

如果你需要完全手工控制，也可以用下面这套等价底层写法：

```bash
session_dir="artifacts/codex-dumps/$(date +%Y%m%d-%H%M%S)-basic-ok"
mkdir -p "$session_dir"

nohup mitmdump \
  --listen-host 127.0.0.1 \
  --listen-port 8082 \
  -s scripts/codex_dump.py \
  --set codex_dump_dir="$session_dir" \
  >"$session_dir/mitmdump.log" 2>&1 &

echo $! >"$session_dir/mitmdump.pid"
```

这套方式有几个优点：

- 不依赖交互终端，适合 Agent 直接执行。
- 日志、PID 和抓包内容都落在同一个 session 目录里。
- 后续批量跑多个 Codex case 时，不需要重复手工盯着 mitm UI。

停止抓包：

```bash
kill "$(cat "$session_dir/mitmdump.pid")"
```

## 通过代理执行 Codex case

固定写法建议如下：

```bash
HTTPS_PROXY=http://127.0.0.1:8082 \
NO_PROXY=127.0.0.1,localhost \
SSL_CERT_FILE=$HOME/.mitmproxy/mitmproxy-ca-cert.pem \
codex exec --skip-git-repo-check -C /tmp 'reply with one word: ok'
```

如果要跑多组 case，推荐只启动一次 `mitmdump`，然后串行执行多条 Codex 命令，并为每个 case 建独立 session 目录。

## 主要会抓到什么

当前 Codex 主模型调用通常会命中：

```text
https://chatgpt.com/backend-api/codex/responses
```

它不是普通 REST body，而是：

1. 先发起 `GET /backend-api/codex/responses`
2. 返回 `101 Switching Protocols`
3. 后续通过 WebSocket 帧承载：
   - `response.create`
   - `response.created`
   - `response.in_progress`
   - `response.output_text.delta`
   - `response.completed`

辅助流量里还可能看到：

- `https://chatgpt.com/backend-api/wham/apps`
- `https://chatgpt.com/backend-api/plugins/featured`
- analytics 相关请求

## 输出结构

`scripts/codex_dump.py` 默认会生成：

```text
artifacts/codex-dumps/<session-name>/
  http/
  websocket/
```

其中：

- `http/*.json`
  保存匹配到的 HTTP 请求和响应。
- `websocket/*.jsonl`
  按事件逐行保存 WebSocket 开始、消息和结束。
- `mitmdump.log`
  如果用后台方式启动，会包含 mitmdump 自身日志。
- `mitmdump.pid`
  如果用后台方式启动，会保存后台进程 PID。

## 脱敏默认值

仓库内的 `scripts/codex_dump.py` 默认会对以下内容做脱敏：

- `Authorization`
- Cookie / Set-Cookie
- 常见 token / api key 字段

这能降低误把认证信息直接写盘的风险，但并不意味着抓包结果可以随意外传。样本里仍然可能包含：

- prompt
- tool call 参数
- 模型回复
- 会话元数据

因此建议：

- 优先把抓包结果留在本机。
- 做 eval 留档时，只共享必要片段或二次脱敏后的摘要。
- 不要把 `artifacts/codex-dumps/` 从 `.gitignore` 里移除。

## 推荐工作流

1. 创建一个明确命名的 session 目录。
2. 后台启动 `mitmdump`。
3. 通过 `HTTPS_PROXY` 跑一组 Codex case。
4. 结束后停止 `mitmdump`。
5. 重点分析：
   - `websocket/` 里的 `response.create`
   - `response.output_text.delta`
   - `response.completed`
6. 把结论、差异和评估结果沉淀到仓库文档，而不是直接提交原始抓包。

## 常见问题

### 1. 只能看到部分请求，看不到主 LLM call

优先检查：

- 是否真的让 Codex 继承了 `HTTPS_PROXY`
- 是否设置了 `SSL_CERT_FILE=$HOME/.mitmproxy/mitmproxy-ca-cert.pem`
- 是否在抓 `chatgpt.com/backend-api/codex/responses`
- 是否只盯着 HTTP，而没有看 `websocket/*.jsonl`

### 2. 为什么不直接抓 `api.openai.com`

当前这台机器上的 Codex 主链路实际走的是 `chatgpt.com/backend-api/codex/responses`，不是传统的 `api.openai.com/v1/...`。

### 3. 为什么默认不建议用 `ALL_PROXY`

`ALL_PROXY` 可能把本地 `127.0.0.1` 的 MCP 流量也一起代理走，容易干扰本地调试链路。默认只设 `HTTPS_PROXY` 更稳。
