# Avoid Synthetic Row Side Action Clicks

### Request

排查并修复 OCU 点击飞书会话列表时，容易点到会话右侧 hover 出来的“完成”勾，导致消息会话被收掉的问题。

### Changes

- 为 accessibility renderer 合成出来的 summary `text` record 增加 `isSyntheticText` 标记。
- element-targeted `click` 对 synthetic text 改用左侧安全锚点，不再使用父容器中心作为默认点击点。
- synthetic text 点击时会过滤右侧紧凑 hover action（如“完成”/ done / archive），再允许剩余行内候选参与点击，避免 side action 被排序成首选候选，同时保留打开会话的主行点击能力。
- 将右侧紧凑 hover action 过滤推广到普通 row/container/text 的后代候选；用户直接点到 side action 本身时仍可执行该按钮，但点 row 或 row text 时不再把 side action 当主候选。
- 对静态文本点击优先使用更大的行级父容器 frame 计算点击锚点，降低 Electron text frame 偏移导致点到相邻行的风险。
- 命中点反查到覆盖整页的 Electron/WebArea 级 AX 元素时，不再扫描整个大容器的子孙候选，避免远处可点击元素劫持当前行点击。
- activation-only fallback 收窄到窗口级元素；普通静态文本或容器不能再靠 `AXFocused` / `AXMain` 成功就声明点击已处理，必须继续落到定向鼠标事件。
- Electron/WebArea 里的合成会话行文本现在优先寻找紧邻的行级 `AXPress` 祖先并静默执行，避免依赖物理鼠标 fallback，也避免点到行内右侧 side action。
- 复测发现这条 WebArea 行级祖先点击优化会误伤 Chrome/GitHub pinned repository card：正式版 OCU 可直接点击 profile pinned `container` 进入 repo，而 dev 版会把点击提前判定为已处理但没有导航。现在该优化收窄到 Electron/Lark 这类目标，浏览器 WebArea 回到通用 link/container 点击路径。
- app-agent proxy 会透传 `OPEN_COMPUTER_USE_*` 环境变量，方便调试开关在 Dev `.app` agent 内生效；正常验证仍不启用全局物理 pointer fallback。
- 新增单元测试覆盖 synthetic text 与普通元素的点击锚点策略、右侧 side action 过滤边界、宽泛 hit record 防护、行级 AX 祖先点击边界、Electron-scoped WebArea 优化边界，以及 activation-only fallback 的角色边界。
- 同步更新架构文档，记录 synthetic text 的点击边界。

### Motivation

飞书会话列表中的可读文本经常是 renderer 为父 row/container 合成的 summary，而不是一个真实独立的可点击 text 元素。旧逻辑会用这个父容器的中心点，并继续扫描其可点击子孙；当 Lark 在 row 右侧 hover 出“完成”按钮时，这个按钮可能被选为首个 `AXPress` 候选，从而把“打开会话”误操作成“完成/收起会话”。新的策略把 synthetic text 视为只代表 row 的可读摘要：点击落在左侧安全区域，子孙候选只保留不像右侧 side action 的目标。

真实验证还暴露另一个 false positive：不可点的静态文本会在 activation-only fallback 里因为 `AXFocused` / `AXMain` 返回成功而提前结束，导致实际会话没有切换。这个兜底现在只保留给窗口级元素；Electron/WebArea 行文本会优先使用行级 `AXPress` 祖先，保持静默 AX 操作，不把全局物理 pointer fallback 当作正常通过标准。

Chrome/GitHub pinned card 复测暴露了优化作用域问题：GitHub profile 的 pinned repository card 在 AX 里也是带 URL 的 `container`，但它属于浏览器 WebArea，而不是 Electron 会话列表。对这类通用浏览器页面，应该保留原来的 target / hit-test / 定向鼠标 fallback 链路；Electron row 祖先点击优化只服务于 Lark/Feishu 这类目标，避免为了修会话列表而破坏原有 Chrome 行为。

### Files

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`

### Validation

- `swift test`
- `./scripts/run-tool-smoke-tests.sh`
- `./scripts/build-open-computer-use-app.sh debug`
- 使用 dev app 对飞书做真实验证：
  - 旧补丁下点击 `AgentSphere 双周会群` / `AgentSphere 研发群` 这类会话行 text 不再触发“完成”，但也未切换会话。
  - 旧补丁下点击 row container 仍可能把会话收掉，确认 side-action 过滤不能只作用于 synthetic text。
  - 新补丁下点击 `AgentSphere 研发群` row text 后，会话行仍保留，未再被“完成”收掉；但当时仍未切换会话，后续定位为普通静态文本 activation-only fallback 抢先返回成功。
  - 只用 OCU dev app 的 AX 路径复测：动态定位并打开 `司开星` 会话，右侧标题确认后发送 `OCU AX静默测试笑话：为什么程序员喜欢喝咖啡？因为没有咖啡因，线程就起不来。`，列表预览与消息区均出现该消息，输入框清空。
  - 随后动态定位并打开 `徐昱嵩` 会话，右侧标题确认后先 AX click 聚焦 text entry area，再发送 `OCU AX静默测试笑话：为什么测试工程师进咖啡店先点空杯？因为要测边界条件。`，列表预览与消息区同样确认发送成功。
  - 验证过程没有设置 `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS`，不依赖全局物理鼠标 fallback。
  - 额外对 Chrome、Finder、Sublime Text 做非破坏性真实 app smoke：`get_app_state` 正常，点击当前已选 tab / 当前已选 Finder sidebar row / 当前已选 Sublime tab 均成功。
  - 使用已安装正式版 OCU `0.1.49` 对 Chrome/GitHub profile 做对照：直接点击 6 个 pinned repository `container` 均可进入 repo 并读到 star。
  - 修复后重建 dev app，终止旧 dev app agent，再用 dev OCU 对同一 Chrome/GitHub profile 做相同验证：动态解析 6 个 pinned repository `container`，逐个点击进入 repo、读取 star、Back 回 profile，6 个 URL 均匹配预期。
