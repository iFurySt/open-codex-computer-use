# 记录官方 state renderer 逆向线索

## 用户诉求

继续结合逆向结果优化 `open-computer-use`，让 Lark / Electron app 的工具返回逐步接近官方 `computer-use`。

## 主要改动

- 新增 `docs/references/codex-computer-use-reverse-engineering/state-rendering-1.0.770.md`。
- 记录官方 `computer-use` 1.0.770 client / service binary 中和 state rendering 相关的字符串、AX 字段、tree transform、窗口错误与 action 线索。
- 更新 reverse-engineering README，把新文档纳入导航。

## 设计动机

后续 renderer 对齐不应该只依赖一次工具输出的肉眼对比。把官方 binary 中稳定可观察的字段和 transform 名称沉到仓库里，可以帮助后续 agent 选择更有证据的迭代方向。

## 受影响文件

- `docs/references/codex-computer-use-reverse-engineering/README.md`
- `docs/references/codex-computer-use-reverse-engineering/state-rendering-1.0.770.md`
