# Locked Use

配置保存在 `/Library/Application Support/OpenComputerUse/LockedUse/configuration.json`，安装后会生成：

```json
{
  "schemaVersion": 1,
  "enabled": true
}
```

修改文件需要管理员权限，服务重启后生效。验证记录由程序生成，不需要手动填写。只修改 `enabled` 不会安装组件，也不会完成正式模式的验证。

## 命令行配置

Locked Use 需要单独安装，不会随 OCU 的权限引导自动开启。请在桌面已解锁时运行，按提示完成管理员授权：

```bash
# 安装并开启验证模式，目前测试用这个
ocu locked-use enable --validation

# 查看安装、权限和验证状态
ocu locked-use status

# 停用并卸载，恢复原来的系统锁屏认证规则
ocu locked-use disable
```

需要使用包含 Locked Use 组件的签名 App；自行构建时设置 `OPEN_COMPUTER_USE_INCLUDE_LOCKED_USE=1`。主 App 需要辅助功能和屏幕录制权限，Guardian 还需要辅助功能和输入监控权限。安装后可用下面的命令弹出 Guardian 的权限申请：

```bash
"/Library/Application Support/OpenComputerUse/LockedUse/OCU Guardian.app/Contents/MacOS/OCUGuardian" --request-permissions
```

正式模式需要通过完整验证，目前尚未完成。`enable` 不带 `--validation` 时安装正式模式，但缺少有效验证记录时不会自动解锁。

## 配置项和命令

| 配置项 / 操作 | 含义 | 命令 |
| --- | --- | --- |
| `schemaVersion` | 配置格式版本，固定为 `1` | 安装时生成，无单独设置命令 |
| `enabled` | 安装时为 `true`；停用会移除整个配置文件 | `ocu locked-use enable` / `ocu locked-use disable` |
| `validatedOSBuild` | 已验证的 macOS build，未验证时省略 | `ocu locked-use certify`，验证通过后生成 |
| `validatedBrokerHash` | 已验证的服务 hash，未验证时省略 | 同上 |
| `validatedGuardianHash` | 已验证的 Guardian hash，未验证时省略 | 同上 |
| `validatedPluginHash` | 已验证的授权插件 hash，未验证时省略 | 同上 |
| 安装验证模式 | 用于本机开发测试 | `ocu locked-use enable --validation` |
| 查看状态 | 查看安装、权限和验证状态 | `ocu locked-use status`，加 `--json` 输出 JSON |
| 打开设置 | 弹窗选择启用正式模式或停用 | `ocu locked-use settings` |
| 恢复安装 | 恢复未完成的安装并清理其组件 | `ocu locked-use recover` |
| 验证正式模式 | 检查完整测试记录并确认，符合要求后切换正式模式 | `ocu locked-use certify` |

[English](locked-use.en.md)
