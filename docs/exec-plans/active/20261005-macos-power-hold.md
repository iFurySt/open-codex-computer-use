# macOS 独立电源保活

## 目标与范围

提供独立 Swift SDK / CLI 和签名后台服务，支持手动无限持续、定时和连接绑定的系统 / 显示器 / 合盖保活。调用方负责任务结束信号。开发在独立 worktree，不改 Part 1 / Part 2 实现。普通保活不需要管理员权限，合盖使用签名 helper 管理 pmset disablesleep。

## 决策与实现

- 独立 package、构建脚本与 bundle；不改根 Package.swift。
- 用户态协调器持有普通 assertions 和调用方 holds；手动请求跨 CLI 退出存活。协调器退出不自动重建旧 holds。
- root helper 通过 XPC 验证同 signer 的固定 host identifier，管理 30 秒内部租约及恢复记录；host 每 5 秒续期。helper 重启先恢复，不继承旧租约。
- 多请求按能力聚合；电量 / 温度截止由每个请求配置，默认无总时限、无额外截止。
- 外部已禁止睡眠时拒绝合盖接管；检测到外部变更终止对应请求，不争抢设置。
- 真正合盖与图形会话可用性需实机验证，不以普通保活或测试 mock 代替。

## 验证与交付

- [x] Core 生命周期 / 多请求 / 连接 / 时间 / 电源条件测试
- [x] 普通 IOKit 后端与跨 CLI 真进程 smoke
- [x] 签名 XPC helper、安装、journal mock 和协调器异常恢复测试（helper 自身 SIGKILL / launchd 恢复仍待实机）
- [ ] 合盖 / 电源切换 / AX / SCK 实机验证
- [x] 文档、history、回归与本地合并

实机不可完成的边界明确记录，不改变用户锁屏 / 睡眠状态来伪装验证。开发日志不记录输入、画面、签名证书或机器绝对路径。

## 当前验证记录

20 项独立 package 测试、普通保活跨进程 smoke、Developer ID 角色 / entitlement 校验及外部 SDK 编译通过。开盖下真实 AppKit fixture 的 AXPress、计数读回、ScreenCaptureKit 前后截图及前台应用保持验证通过。修复 GUI 探针 AppKit 初始化与父进程死亡后的 fixture 清理。特权服务已批准。macOS 26 的 BundleProgram 在路径解析阶段失败，改用标准 Applications 位置的 ProgramArguments 与 AssociatedBundleIdentifiers；真实签名 XPC、pmset 开关、8 秒定时恢复及协调器 SIGKILL 后恢复通过。首轮物理合盖等待超时，清理后确认 SleepDisabled=0，等待用户重试。

独立实现分支已无冲突合并回 awesome-extension；仓库架构、安全、可靠性和质量说明已同步。保留本 plan 为 active，直至补完实机验收或将未完成项明确转为后续任务。
