# macOS 清洗后 AX 增量输出

状态：已实现。全量采集保持原样，减少的是模型读取的重复 AX 文本。Windows/Linux 不变。

## 数据流

`SnapshotBuilder → TreeRenderer 清洗后的 AXCleanNode → 身份协调 → 操作缓存 → AXSnapshotOutput → MCP text/image`

renderer 在创建显示行的同一位置生成结构化节点，不解析输出文本来恢复树。节点包含显示内容、父节点、顺序、缩进和附加行；继续沿用文本截断、空容器省略、行摘要、synthetic text 和链接规则。节点数预算与稳定引用计数独立。

每个客户端 dispatcher 有独立的引用分配器、身份状态和输出历史。引用在客户端内递增、不回收；同一 AX 对象优先通过 CFEqual 匹配。唯一 AXIdentifier 加相同 role 和已匹配父节点可以辅助匹配；两侧都必须唯一。不会按名称/坐标猜测重绑定。AXRow 的清洗身份内容变化、synthetic text 内容变化会分配新引用；普通字段的值变化保留引用并输出更新。这是保守策略，不承诺所有 toolkit 的虚拟列表都能正确提供内容身份。

操作始终使用最近完整采集的元素映射；省略输出不会跳过虚拟会话的读回、输入门和动作证据。已不在当前映射里的引用明确拒绝。引用连续性表示当前观察目标连续，不表示控件可无限期保持可操作。

## 接口

macOS app tools 接受 `snapshot_mode`：

| 模式 | 行为 |
| --- | --- |
| `auto` | 默认。首次完整，后续返回变化和必要上下文 |
| `full` | 显式完整观察，恢复模型基线 |
| `none` | 不发布 AX 文本；采集、操作缓存、截图与安全校验保持各自现有行为 |

`OPEN_COMPUTER_USE_AX_SNAPSHOT_MODE=full` 可恢复完整输出；单次参数优先。一次性 CLI `snapshot` 和 GUI notebook 强制完整输出。`get_app_state` 额外接受 `base_snapshot_id`；调用方可以指定实际接收的快照，而不是使用 runtime 最近发布的快照。

```text
AX snapshot client:s18 mode=diff base_snapshot_id=client:s17
Context: 12 group Search
~ 42 text field Search Value: hello [parent=12]
+ 108 button Clear [parent=12]
- Observed refs: 57 (no longer in this observation)
Order 12: 42,108
The focused UI element is 42 text field Search Value: hello.
```

`+`/`~` 携带节点当前完整清洗行；`Order` 替换受影响父节点的直接子引用列表。上下文只包含相关当前父容器，不展开无关兄弟。离开观察树不等于应用删除；滚动和控件暴露范围也会影响观察。无变化输出 `AX unchanged`，仍保留当前焦点/选区摘要。焦点或选区消失也会明确输出。

scope 包含 session、PID/进程启动时间、window ID、虚拟布局/输入 epoch、text limit 和 tree budgets；别名最终归入实际目标。身份协调不受 text/tree budget 配置变化影响，输出基线则必须同配置。每客户端保留最多 16 个发布版本和 16 个目标的上次身份状态；发布历史和身份状态均不保留 PNG。连接关闭释放 dispatcher；turn-ended/缓存清理会清空历史但不回收引用编号。

找不到基线、scope 不兼容、当前或基线观察被截断、无结构化节点时返回完整输出并注明原因。增量 UTF-8 字节数达到完整输出的 80% 时也返回完整输出。截断不输出误导性的删除 patch。

## JS 与截图

adapter 从 native schema 检测能力，旧 macOS 及 Windows/Linux 不接收新的参数。`getAXState({snapshotMode:"full"})` 可主动恢复；正常 emit 成功后才保存模型基线 ID。`emit:false` 默认完整返回，供代码独立读取，但不推进模型基线；如果代码自行输出隐藏读取的字符串，adapter 不会尝试推断它是否已被模型读取。

截图请求使用 `none`；动作也省略 AX 输出，虚拟会话继续强制读回。选定的 window ID 保留在后续观察中，不发给动作工具。JS reset 后没有模型基线，首次观察通过显式缺失基线恢复完整状态。

AX 与截图是独立的信息源。原生截图返回策略未改变，不会因为 AX unchanged 自动跳过截图；canvas、视频和自绘区域需要像素验证。上下文压缩不能由 native runtime 自动检测，需要显式 full。

## 验证与复现

```sh
swift test
node --test scripts/node-repl/*.test.mjs
./scripts/run-tool-smoke-tests.sh
OPEN_COMPUTER_USE_AX_REPLAY_OUTPUT=/tmp/ocu-ax-replay.json swift test --filter AXSnapshotDiffTests/testLocalChangeTokenReplay
# 在独立 Python 环境安装 tiktoken==0.12.0，再运行：
python scripts/benchmark-ax-diff.py /tmp/ocu-ax-replay.json
# 真实 AX/SCK 与 AXPress 验证，要求可交互桌面和权限：
OPEN_COMPUTER_USE_AX_REAL_REPLAY_OUTPUT=/tmp/ocu-ax-real-replay.json ./scripts/run-virtual-display-tests.sh --ax-diff-only
```

2026-10-06 离线重放结果（tiktoken 0.12.0，o200k_base；80 个控件、21 次观察，包含首次完整输出）：

| 场景 | 完整 token | 文本行 diff token | 上下文增量 token | 增量减少 |
| --- | ---: | ---: | ---: | ---: |
| 字段局部更新 | 21,063 | 2,432 | 2,034 | 90.34% |
| 列表增删/顺序 | 20,013 | 2,517 | 5,514 | 72.45% |
| 无变化 | 20,853 | 1,073 | 1,594 | 92.36% |

这些是确定性清洗节点的文本评测，不含截图、模型推理或实际账单。文本 diff 对顺序的表达更短；结构化增量额外携带明确的引用关系、焦点与父容器。不能据此断言模型任务成功率提升。

真实 AppKit 测试本轮已经取得 AX 状态和 SCK 截图，但点击被既有系统对话框/登录屏安全门暂停；未宣称真实动作或商业应用验收通过。Calculator、TextEdit、Finder、Electron/WebView 的真实连续轨迹和相同模型的动作成功率对照仍需补充。

## 外部参考

- [Playwright v1.59.0](https://github.com/microsoft/playwright/tree/01b2b1533e0bfa1c582117e3ec109fcb57657747)：参考 compareSnapshots、filterSnapshotDiff 及多 track/重排/属性变化测试。当前公开 API 不等同于这个历史实现。
- [anchortree](https://github.com/truffle-dev/anchortree/tree/2f085c506e9fa92e24940ba7c280545a35bee529)：参考稳定身份与 added/removed/changed 的表达；未采用其模糊重绑定策略。

参考代码已克隆到仓库外，不是构建依赖；实现代码没有复制外部源码。
