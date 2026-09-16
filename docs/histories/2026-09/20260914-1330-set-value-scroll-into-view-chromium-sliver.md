# 20260914 修复 set_value 在 Chromium 长表单中的滚动跟随

## 用户诉求（原文压缩）

> “OCU 控制的时候，页面还是没有顺着光标滚动到指定填写的位置。”并明确要求：让 set_value 也走“先滚入视口”（与 click 一致），自测并给证据；确保下次不再重复犯错。

## 现象与根因

- 现象：在 127.0.0.1:8790 的长表单里连续填 交付目标/成功标准/非目标/策略引用/生命周期 时，值写进去了，但可视区一直停在表单顶部——操作对人不可见。
- 代码路径：`setValue` 确实调用了 `ensureElementVisible`，但它被 `elementNeedsScrollIntoView` 提前放行。
- 根因：Chromium 会把被滚动容器裁出视口的元素上报成**退化帧**（实测 `x=344 y=87 w=42 h=1`）。旧实现把“退化几何”一律判为“不需要滚动”，于是 scroll-into-view 对 Chromium 的长表单实际上从未生效。

## 变更

- `ComputerUseService.swift`：`elementNeedsScrollIntoView` 区分“完全不可信几何”（nil/非有限值/无窗口矩形 → 不滚）与“有位置但尺寸退化的裁剪帧”（宽或高 ≤ `degenerateSliverThreshold`=1pt → **需要滚动**）；`ensureElementVisible` 增加一行 gated 诊断 `scroll-into-view probe needsScroll=… mode=… localFrame=…`（沿用 `OPEN_COMPUTER_USE_DEBUG_INPUT_FALLBACKS`）。
- 测试：`testElementNeedsScrollIntoViewForOutOfWindowAndDegenerateFrames` 覆盖退化帧（Chromium 裁剪特征）、0×0 有位置帧、`.zero`、NaN 以及原有“完全在窗口外/横向在外”的场景。

## 验证

- `swift test`：**231 tests, 0 failures**（1 skipped）。
- 装机后实测：对屏外字段 `set_value` → 视口自动滚到目标（截图对比：调用前停在表单顶部、调用后 非目标/策略引用/生命周期/检查变更 同屏），字段值与既有变更计划均未被破坏。
- 装机流程：release 构建 → 替换 Mach-O → 用同一开发证书重签（**对整个 .app 重签**，否则 bundle 资源封印失效）→ `codesign --verify --deep --strict` OK → `doctor` 权限 granted → `pkill -f OpenComputerUse` 后 DSH 自动重连。

## 备注

- 回滚备份：旧的 Mach-O 已移出 app bundle（放在工作区 `tmp/ocu-backup/`），留在 bundle 内会破坏 `--deep --strict` 校验。
- 技能正文（canonical + DSH 副本）同步更新：环境开关说明、"AX 动作成功 ≠ 页面移动"、退化帧阈值、以及"填表必须让人看得见"的验收硬要求。