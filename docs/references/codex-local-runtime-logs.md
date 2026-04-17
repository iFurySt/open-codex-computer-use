# Codex 本地运行日志补充观测

这份文档描述当上游 LLM 抓包不够用时，如何利用 Codex 自己的本地日志补充观察本地 tool / MCP 行为，尤其是 `computer-use` 这类走本机 `stdio` 的 MCP server。

默认排查顺序应该是：

1. 先看 `docs/references/codex-network-capture.md` 对应的上游 HTTP / WebSocket dump。
2. 只有当上游样本不足以解释本地 tool 行为时，再查 Codex 本地日志。
3. 只有当本地日志仍然不够，且确实需要原始 `stdio` JSON-RPC 字节流时，才考虑 wrapper / shadow plugin / 更底层 hook。

大多数情况下，第 1 步已经足够；这份文档是补充路径，不是默认入口。

## 适用场景

- 需要确认某个本地 MCP tool 实际被调用了什么参数。
- 需要确认某次本地 tool 调用返回了什么结果或错误。
- 需要分析官方 `computer-use` 这类不经过网络、因此不会出现在 MITM 抓包里的本地 `stdio` tool。
- 需要把“模型决定调用了哪个 tool”和“本地 tool 实际返回了什么”串起来看。

## 为什么需要这条补充路径

`mitmdump` 抓到的是 Codex 到上游模型服务的 HTTP / WebSocket 流量。它很适合回答：

- 模型看到了什么上下文。
- 模型何时决定调用某个 tool。
- tool call 在模型协议层长什么样。

但对于官方 `computer-use` 这种本地 `stdio` MCP，网络抓包看不到：

- Codex 宿主与本地 MCP server 的 `stdio` 交换细节。
- 本地 tool 的宿主侧落盘结果。
- 某些本地 tool 调用后的完整输出摘要。

这时补看 Codex 自己的本地日志，通常就足够了。

## 主要日志位置

当前本机 Codex 运行时，最有用的本地日志库是：

```text
$HOME/.codex/logs_2.sqlite
```

建议始终以只读方式查询：

```bash
sqlite3 -readonly "$HOME/.codex/logs_2.sqlite" ".tables"
```

## 这份日志里通常能看到什么

对本地 MCP tool，日志里通常会出现两类信息：

1. `ToolCall: mcp__...`
   这类记录能看到 Codex 实际分发给 tool 的参数。
2. `event.name="codex.tool_result"`
   这类记录能看到 tool 返回的摘要结果、耗时、成功/失败状态，以及部分输出。

对官方 `computer-use`，常见形态类似：

```text
ToolCall: mcp__computer_use__click {"app":"com.electron.lark","x":194,"y":321}
```

```text
event.name="codex.tool_result" tool_name=mcp__computer_use__click ... arguments={"app":"com.electron.lark","x":194,"y":321} ... output=...
```

当日志粒度足够时，还能看到：

- `mcp_server=computer-use`
- `mcp_server_origin=stdio`
- 错误返回，例如 `Apple event error -10005: noWindowsAvailable`
- 成功返回后的 AX 树、窗口标题、元素片段或 tool 输出摘要

## 常用查询

### 1. 看最近的 `computer-use` tool 调用参数

```bash
sqlite3 -readonly "$HOME/.codex/logs_2.sqlite" "
SELECT datetime(ts,'unixepoch','localtime') AS t,
       substr(feedback_log_body,1,2400)
FROM logs
WHERE feedback_log_body LIKE '%ToolCall: mcp__computer_use__%'
ORDER BY ts DESC, ts_nanos DESC
LIMIT 50;
"
```

### 2. 看最近的 `computer-use` tool 返回结果

```bash
sqlite3 -readonly "$HOME/.codex/logs_2.sqlite" "
SELECT datetime(ts,'unixepoch','localtime') AS t,
       substr(feedback_log_body,1,3200)
FROM logs
WHERE feedback_log_body LIKE '%event.name=\"codex.tool_result\"%'
  AND feedback_log_body LIKE '%mcp_server=computer-use%'
ORDER BY ts DESC, ts_nanos DESC
LIMIT 50;
"
```

### 3. 同时看参数和结果

```bash
sqlite3 -readonly "$HOME/.codex/logs_2.sqlite" "
SELECT datetime(ts,'unixepoch','localtime') AS t,
       substr(feedback_log_body,1,3200)
FROM logs
WHERE feedback_log_body LIKE '%ToolCall: mcp__computer_use__%'
   OR (
        feedback_log_body LIKE '%mcp__computer_use__%'
    AND feedback_log_body LIKE '%output=%'
      )
ORDER BY ts DESC, ts_nanos DESC
LIMIT 100;
"
```

### 4. 按具体 tool 过滤

例如只看 `get_app_state`：

```bash
sqlite3 -readonly "$HOME/.codex/logs_2.sqlite" "
SELECT datetime(ts,'unixepoch','localtime') AS t,
       substr(feedback_log_body,1,3200)
FROM logs
WHERE feedback_log_body LIKE '%mcp__computer_use__get_app_state%'
ORDER BY ts DESC, ts_nanos DESC
LIMIT 50;
"
```

### 5. 结合 thread id 缩小范围

如果已经知道某条记录里的 `thread_id=...`，可以进一步过滤：

```bash
sqlite3 -readonly "$HOME/.codex/logs_2.sqlite" "
SELECT datetime(ts,'unixepoch','localtime') AS t,
       substr(feedback_log_body,1,3200)
FROM logs
WHERE thread_id = '<thread-id>'
ORDER BY ts DESC, ts_nanos DESC
LIMIT 100;
"
```

这在同一时间跑了多个 Codex 会话时特别有用。

## 与上游抓包的分工

推荐这样分工：

- 上游抓包：
  看模型输入、模型输出、工具决策、协议层事件时序。
- 本地运行日志：
  看本地 tool 最终拿到的参数、返回的结果、耗时和本地 MCP 来源。

一个简单判断标准是：

- 如果你想回答“模型为什么决定调用这个 tool”，先看上游抓包。
- 如果你想回答“这个本地 tool 到底拿到了什么参数、回了什么错误”，先看本地日志。

## 关于官方 `computer-use` 的一个关键结论

对官方 bundled `computer-use`，当前更现实的观测方式通常不是去拦截 `stdio`，而是先利用 Codex 宿主已经落盘的日志。

原因是：

- 官方 `computer-use` 本身是本地 `stdio` MCP。
- 网络 MITM 默认只能抓上游 LLM call，看不到这条本地 `stdio` 链路。
- Codex 宿主已经把不少 `mcp__computer_use__*` 的参数和结果写进了本地日志。

这意味着很多场景下，根本不需要先做侵入式拦截。

## 什么时候才值得做 wrapper / shadow plugin

只有在下面这些问题上，本地日志才可能不够：

- 需要看原始 newline-delimited JSON-RPC message，而不是宿主整理后的日志摘要。
- 需要确认宿主和本地 MCP server 之间某个边缘字段是否在 wire 上真实存在。
- 需要对宿主侧日志粒度之外的 framing / 顺序问题做精确复盘。

这时更推荐：

1. 复制 bundled plugin 做一个 repo-local shadow plugin。
2. 把 `.mcp.json` 里的 `command` 改成自己的 wrapper。
3. 在 wrapper 里做最小分流，把 stdin/stdout 旁路写盘后再转发给真实二进制。

不推荐默认就做：

- 网络 MITM
- `DYLD_INSERT_LIBRARIES`
- 常驻二进制代理替代真正父进程
- 需要额外系统权限和长期维护成本的动态 hook

## 风险与脱敏

本地日志可能包含：

- prompt 片段
- tool 参数
- tool 输出
- 窗口标题、元素文本、URL
- 会话元数据

因此建议：

- 只读查询，不直接改动 Codex 本地状态。
- 优先提炼结论，不把原始日志整段提交进仓库。
- 如果需要把结果沉淀到 `docs/`，只保留最必要、脱敏后的片段和结论。

## 推荐工作流

1. 先按 `docs/references/codex-network-capture.md` 抓上游样本。
2. 如果上游样本已经能回答问题，就直接在仓库文档里沉淀结论。
3. 如果问题落在本地 `stdio` MCP / `computer-use` 行为上，再查 `logs_2.sqlite`。
4. 只有当本地日志仍然不够，才考虑 wrapper / shadow plugin 方案。

这个顺序能避免一上来就走高侵入、难维护的拦截路径。
