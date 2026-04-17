# 安全默认约束

## 当前实现边界

- 当前 server 只提供本地 `stdio` MCP，不对外监听 TCP/HTTP 端口。
- 所有动作都必须显式带 `app` 参数；当前不会在后台自动扫描并控制任意 app。
- 真实 app 路径依赖宿主进程已经获得 macOS `Accessibility` 与 `Screen Recording` 权限。

## 数据处理

- screenshot 只写到临时目录 `TMPDIR/open-computer-use/`，默认不长期持久化。
- fixture app 的合成状态只写到本地临时 JSON 文件，目的是支撑 deterministic smoke test。
- 当前仓库不引入第三方服务，也不上传截图、AX tree 或输入内容。

## 授权与最小权限

- 当前还没有官方闭源实现里的 session approval / app allowlist。
- 这意味着开源版当前的安全边界主要由：
  - 明确的 tool 调用参数
  - 宿主进程权限
  - 本地使用场景
  共同提供。
- 下一阶段应优先补：
  - app allowlist
  - session 级审批
  - 更清楚的高风险 app / 系统设置防护策略

## Fixture Bridge 约束

- `FixtureBridge` 只用于仓库内测试夹具，不是给第三方 app 的控制平面。
- 任何面向真实 app 的能力新增，都不应该复用这条测试专用通道。

仓库级的依赖、SBOM 和 provenance 默认能力，统一写在 `docs/SUPPLY_CHAIN_SECURITY.md`。
