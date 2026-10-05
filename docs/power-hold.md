# 独立 macOS 电源保活

`packages/OpenComputerUsePower` 是独立 Swift package。它不依赖 OCU 的虚拟显示器、Locked Use 或根 SwiftPM 构建；独立 SDK、CLI、用户态协调器和 root helper 提供系统闲置 / 显示器闲置 / 合盖保活。

## 构建与使用

```sh
swift test --package-path packages/OpenComputerUsePower
scripts/build-power-hold-app.sh debug
```

构建输出到 `dist/power-hold/debug/`。设置 `OPEN_COMPUTER_USE_CODESIGN_IDENTITY` 使用已有 Developer ID；不设置时为 ad-hoc，只能使用普通 assertions。`release` 与 `debug` 有独立 bundle、Mach service 和 socket 标识。分发前仍需沿既有流程公证；构建脚本本身不执行公证。

正式使用先将签名 App 安装到标准 `/Applications/Open Computer Use Power.app`（debug 为 `Open Computer Use Power (Dev).app`），再调用 bundle 内的 `Contents/MacOS/OCUPowerHost`。下列命令也可在开发阶段用 `swift run --package-path packages/OpenComputerUsePower OCUPowerHost` 替代；裸 executable 需要先在另一终端启动 `serve`，不会自动注册后台服务。

```sh
OCUPowerHost acquire
OCUPowerHost acquire --options '{"lifetime":"timed","seconds":600}'
OCUPowerHost acquire --options '{"prevent_lid_sleep":true}'
OCUPowerHost status
OCUPowerHost status HOLD_ID
OCUPowerHost release HOLD_ID
OCUPowerHost run -- /usr/bin/sleep 60
OCUPowerHost shutdown
OCUPowerHost doctor
```

命令输出 JSON。`acquire` 返回 `id`；默认 `manual`，没有总时限，CLI 退出、断连或工具 turn 结束不会释放。`timed` 需要有限正数 `seconds`，使用包含睡眠时间的 continuous monotonic clock，系统校时和调用方断开不影响计时；`connection` 随 SDK 连接关闭释放，CLI 使用 `run` 持有连接直到子命令结束。`run` 强制 connection 生命周期；CLI 被强制结束时保活释放，但不承诺结束其已启动的子进程。

`release` 在同用户范围内幂等，不能释放其他 UID 的请求。协调器保留最多 256 条终态记录，故长期之前的 ID 可能返回 unknown。最多 1024 个活动请求与 128 个控制连接。协调器退出 / 崩溃后旧请求不恢复；调用方必须重新 acquire。关闭状态窗口保留请求，Quit / shutdown 释放全部请求。

参数默认值：

| 参数 | 默认值 |
| --- | --- |
| prevent_idle_sleep | true |
| prevent_display_sleep | false |
| prevent_lid_sleep | false |
| lifetime | manual |
| battery_floor_percent | 不设置 |
| stop_on_serious_thermal_state | false |

至少请求一项能力，拼错的 options key 会报错。电量阈值仅在使用内部电池供电且读到有效容量时触发；未知电量不被伪装成低电量。温度策略在 serious / critical 时结束该请求；其他调用方的请求不会一起结束。即使关闭这些可选截止条件，也不保证抵抗硬件保护或企业管理动作。

SDK 产品为 `PowerCore`：`PowerClient.acquire(options)` / `status(id?)` / `release(id)`。`HoldOptions` 是可修改的 Swift struct。持续连接用 `PowerClient` 对象的生命周期表示；`PowerHoldRegistry` 为进程内控制 API，可注入后端与时钟。SDK 与独立 App 使用一致的 debug/release 配置；跨配置使用显式 socket path。

## 合盖后端安装与恢复

```sh
OCUPowerHost install
OCUPowerHost doctor
OCUPowerHost uninstall
```

`install` 通过 SMAppService 登记 bundle 内的 LaunchDaemon。daemon 使用标准 Applications 位置的 `ProgramArguments` 和 `AssociatedBundleIdentifiers`；本机 macOS 26 的 `BundleProgram` 登记虽获批准却在路径解析阶段失败，因此不依赖该解析路径。安装管理拒绝其他 App 位置。macOS 要求在系统设置中批准后台项；pending approval 不等于 helper 可用。安装、卸载要求 Developer ID 签名与固定角色。运行中的保活不弹管理员认证，不安装 sudoers，不接受任意 root shell。App 所在位置必须稳定，更新或移除 bundle 前先卸载；不要直接替换正在使用的已登记 bundle。

协调器使用进程持有的 IOKit assertions；它意外退出后这些断言由系统释放。合盖后端使用 `/usr/bin/pmset -a disablesleep 1/0`。root helper 持有 30 秒内部租约，协调器每 5 秒续期；租约与用户的无限持续模式不同，没有对 manual 请求设置总时限。

helper 接受同 Team、固定 host identifier、Developer ID 和无 get-task-allow 的签名角色。XPC 在消息交付前强制验证签名，连接身份与租约绑定。协调器的 Unix socket 使用内核 peer UID 与 0700/0600 权限；同 UID 的本地进程属于同一个控制信任域，hold ID 不是凭据。

首次合盖请求发现 SleepDisabled 已开启时拒绝接管。helper 在修改前持久化恢复记录，并对 pmset 偏好与 IOPMrootDomain 运行态读回验证。debug/release helper 共用全机互斥锁，恢复记录分别命名；不同 helper 不得同时管理睡眠开关。

协调器断连 / 租约过期时恢复。helper 由 launchd 重启，启动时先恢复未完成记录，不继承旧许可。恢复失败保留记录、拒绝新 acquire 并重试；root 目录 / journal 拒绝 symlink、非 root owner、宽权限和 extended ACL。系统开关没有原子所有权 API，不能识别外部工具写入相同值；与 Amphetamine 等工具并用不作为支持场景。外部把开关关闭时撤销本模块许可，不重新争抢。

`status.requested` 是本用户请求的合并，`confirmed` 是协调器持有的普通断言与最近获 helper 确认的租约。`lid_state_known=false` 表示 helper 状态未知，不能把 `confirmed.lid=false` 理解成已经恢复全机睡眠；使用 doctor 与 helper 诊断核对。错误不会以普通保活静默替代合盖保活。

首次 acquire 只禁用睡眠，不触发睡眠、不移动光标、不解锁会话、不修改自动锁屏、待机或 hibernatemode。锁屏可能使 AX/SCK 无法继续，保持机器清醒不解决这一点。

## 验证入口与当前证据

```sh
python3 scripts/run-power-hold-smoke.py
python3 scripts/test-power-hold-signing.py
python3 scripts/run-power-hold-lid-smoke.py --app 'PATH_TO_SIGNED_POWER_APP'
OCUPowerHost gui-smoke --seconds 5
OCUPowerHost gui-smoke --closed-lid --seconds 30 --display-id DISPLAY_ID
```

普通 smoke 在独立 coordinator 上验证真实 IOKit assertions、跨 CLI 手动请求、定时、连接死亡、强制结束和重启。不会改 disablesleep；若已有 coordinator 则拒绝接管。签名测试不登记服务、不改电源设置。

lid smoke 要求已批准的签名 helper、初始 SleepDisabled=0 和没有活动协调器，验证真实开关、定时恢复与用户态协调器崩溃后的恢复；它不关闭物理盖子。helper 自身崩溃后的真实 launchd 恢复、物理合盖 / 插拔电源与功耗仍需独立实测。

GUI probe 启动独立真实 AppKit 进程，通过 AXPress 更新计数器，读回 AX 值，并验证前后 ScreenCaptureKit 窗口截图不同。可选择已有显示器，不创建虚拟屏幕，也不依赖 FixtureBridge。开盖测试会检查前台应用未改变；`--closed-lid` 在请求合盖保活后等待最多 60 秒供用户合盖，要求整个采样区间保持合盖，结束或失败均释放自身请求。窗口截图仅在内存。Power App 必须单独获得 Accessibility / Screen Recording；探针不会自动请求权限或解锁。

当前已通过 20 项自动测试、真实普通保活跨进程 smoke，以及签名 host 接受 / 可注入副本拒绝 / 错误角色拒绝。开盖下真实 GUI AXPress / AX 值读回 / ScreenCaptureKit 前后截图验证已通过，且前台应用未改变。特权服务已获系统批准并通过签名 XPC 状态查询；真实 pmset 开关、8 秒定时恢复及强制结束协调器后的恢复均已通过。首次物理合盖探针因 60 秒内未检测到合盖而超时，确认清理后 SleepDisabled=0；物理合盖与功耗尚未验收。功能作为实验模块交付，不能把单元测试算作合盖支持证据。

## 后续与其他模块合并

Virtual Display / Locked Use 只持有和释放请求 ID，不直接修改电源开关。电源心跳不能续期解锁许可；显示器变化后的重新验证仍由虚拟会话负责。联合模式退出先关闭输入与处理重锁，再释放电源请求，同时保留各组件独立的异常恢复路径。

来源：[Amphetamine Power Protect](https://github.com/x74353/Amphetamine)、[Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)、[Apple 睡眠通知与断言](https://developer.apple.com/library/archive/qa/qa1340/_index.html)。实现不复制第三方源码，无新增外部依赖。
