# 修复 CLI 数字型 element_index 参数

## 用户诉求

修复 Issue #18：`open-computer-use call click --args '{"app":"TextEdit","element_index":0}'` 会因为 CLI JSON 把 `0` 解析成数字，而 dispatcher 只接受字符串，最终误报 `click requires either element_index or x/y`。

## 主要改动

- Swift `ComputerUseToolDispatcher` 新增 `element_index` 专用规范化逻辑，允许 JSON 数字索引转成字符串索引，同时保持 tool schema 的 `string` 类型不变。
- `click`、`perform_secondary_action`、`scroll`、`set_value` 统一使用该专用读取逻辑。
- Windows 和 Linux Go runtime 同步接受数字型 `element_index`，保持三端 CLI 参数行为一致。
- skill 文档示例改成规范的字符串写法，避免继续引导用户传数字。
- 补充 Swift / Go 单元测试覆盖字符串索引、数字索引和小数索引拒绝路径。

## 设计动机

官方 tool surface 把 `element_index` 暴露为字符串，仓库也应继续保持这个 schema；但手写 CLI JSON 时用户自然会把索引写成数字。解析层把整数数字容错转换为字符串，可以兼容现有文档误导产生的命令，同时不扩大其它字符串参数的接受类型。

## 受影响文件

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `apps/OpenComputerUseWindows/main.go`
- `apps/OpenComputerUseWindows/main_test.go`
- `apps/OpenComputerUseLinux/main.go`
- `apps/OpenComputerUseLinux/main_test.go`
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/usage.md`
