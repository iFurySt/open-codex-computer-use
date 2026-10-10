# 结构化权限查询

用户要求为 OCU 增加 `--json` 权限状态并提交 PR。

- macOS `doctor --json` 输出权限 JSON，不打开引导，支持宿主轮询。
- CLI 和 app-agent proxy 共用 PermissionDiagnostics 序列化，普通 doctor 行为保持一致。
- 字段：platform、accessibilityTrusted、screenCaptureGranted、allGranted、missingPermissions。缺权限仍退出 0；状态沿用现有系统 API/TCC 诊断语义。
- Linux/Windows 明确拒绝不支持的权限 JSON 查询。
- 更新双语 README、架构说明、功能发布记录，补充参数、四种权限组合和代理路由测试。

验证：Swift 测试、Node contract 测试、Linux/Windows Go 测试、文档检查与 CLI JSON 手工查询（结果见 PR）。
