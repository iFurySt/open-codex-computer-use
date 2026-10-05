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

lid smoke 要求已批准的签名 helper、初始 SleepDisabled=0 和没有活动协调器，验证真实开关、定时恢复与用户态协调器崩溃后的恢复；它不关闭物理盖子。helper 自身崩溃后的真实 launchd 恢复、插拔电源与功耗仍需独立实测。

GUI probe 启动独立真实 AppKit 进程，通过 AXPress 更新计数器，读回 AX 值，并验证前后 ScreenCaptureKit 窗口截图不同。可选择已有显示器，不创建虚拟屏幕，也不依赖 FixtureBridge。开盖测试会检查前台应用未改变；`--closed-lid` 在请求合盖保活后等待最多 60 秒供用户合盖，要求整个采样区间保持合盖，结束或失败均释放自身请求。窗口截图仅在内存。Power App 必须单独获得 Accessibility / Screen Recording；探针不会自动请求权限或解锁。

当前已通过 30 项自动测试（含 10 项 metrics 测试）、真实普通保活跨进程 smoke，以及签名 host 接受 / 可注入副本拒绝 / 错误角色拒绝。开盖下真实 GUI AXPress / AX 值读回 / ScreenCaptureKit 前后截图验证已通过，且前台应用未改变。特权服务已获系统批准并通过签名 XPC 状态查询；真实 pmset 开关、8 秒定时恢复及强制结束协调器后的恢复均已通过。2026-10-05 在 macOS 26.5.1 / Apple Silicon 上的物理合盖验收通过：内核 AppleClamshellState=true、SleepDisabled=true，30 秒合盖采样完成 11 次 AXPress、计数读回及前后 SCK 截图变化验证。探针结束后 hold=ended/released、SleepDisabled=0、helper_confirmed=false，fixture 退出；随后关闭空闲协调器。此次只证明本机当前配置下的 30 秒真实合盖 GUI 工作流，不代表所有设备、电源模式、锁屏状态或一分钟持续运行。helper 自身 SIGKILL/launchd 恢复、电源切换与功耗仍待验收。功能作为实验模块交付。

## 后续与其他模块合并

Virtual Display / Locked Use 只持有和释放请求 ID，不直接修改电源开关。电源心跳不能续期解锁许可；显示器变化后的重新验证仍由虚拟会话负责。联合模式退出先关闭输入与处理重锁，再释放电源请求，同时保留各组件独立的异常恢复路径。

来源：[Amphetamine Power Protect](https://github.com/x74353/Amphetamine)、[Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)、[Apple 睡眠通知与断言](https://developer.apple.com/library/archive/qa/qa1340/_index.html)。实现不复制第三方源码，无新增外部依赖。

## Metrics：短期电源数据

协调器启动时默认启用统一 metrics，每 5 秒读取一次，只保留最近 1 小时；不需要 root，不启动 powermetrics，也不创建或续期任何防休眠许可。机器睡眠、协调器停止时没有样本，不补造这些区间。调用方需要持续保活时自行 acquire。

```sh
OCUPowerHost metrics
OCUPowerHost metrics --query '{"since":1791180000,"until":1791180300,"limit":20}'
OCUPowerHost metrics-configure '{"enabled":true,"interval_seconds":5,"retention_seconds":3600}'
OCUPowerHost metrics-configure '{"enabled":false,"interval_seconds":5,"retention_seconds":3600}'
OCUPowerHost metrics-clear
python3 scripts/run-power-metrics-smoke.py
```

`metrics` 返回 configuration、samples、truncated、collection_error 和 sensor_freshness；样本按时间升序，截断时选取范围内最新 N 条，可用更早的 until 查询前一段。since/until 为 Unix 秒，默认 limit=100，上限 100；不支持 hold ID 过滤或把全机耗电归因于某个调用方。SDK 提供 `PowerClient.metrics(MetricsQuery)`、`configureMetrics(MetricsConfiguration)` 和 `clearMetrics()`；返回 `MetricsReport`。`MetricsCollector` / `MetricsSample.readings` 可扩展其他采集器，当前生产 collector 只记录下面的白名单。

| 字段 | 单位 / 含义 | 来源与边界 |
| --- | --- | --- |
| system_power_watts | W，整机供电轨读数 | Apple Silicon AppleSMC.PSTR，只读 metadata/read；无该 key、格式未知、访问拒绝或非有限数值时 unavailable。未用外接功率计校准，不承诺所有设备都支持。 |
| battery_net_power_watts | W，正值充入电池、负值从电池放出 | AppleSmartBattery 平均电流 × 电压，derived_sensor；电池净功率不是整机功率，AC 满电时可为 0。 |
| battery_voltage_volts | V | 电池电压；不是适配器额定功率。 |
| battery_percent | % | IOPowerSources 当前电量。 |
| battery_temperature_celsius | °C | AppleSmartBattery 温度，不代表 CPU 温度；越界时 unavailable。 |
| collection_duration_seconds | s | monotonic clock 测得本次 native 采集耗时，不含 SQLite 写入、队列等待或查询传输。 |
| thermal_state / on_battery / charging / lid_closed | 状态 | 热压力、供电、充电与硬件合盖状态，未知保持缺失。 |
| active_holds / requested / confirmed / lid_state_known | 状态 | 本协调器许可数量与实际确认能力，不含用户其他 App 的 assertions。 |

每个 reading 带 source、unit、quality（reported_sensor / derived_sensor / reported_state / measured_interval / unavailable）；缺失 value 与 unavailable_reason 显式区分于数值 0。timestamp 是读取时的墙钟 Unix 秒，uptime_seconds 为 continuous monotonic clock；硬件自身刷新周期未知，同值连续读取不意味着传感器每 5 秒刷新。没有 CPU/GPU/ANE 模型估算或 per-process Energy Impact，避免把子系统和整机功率混合为一个数字。

本地数据库位于用户 Application Support 的 `OpenComputerUsePower[.dev]/Metrics/metrics.sqlite3`。目录 0700、文件 0600，拒绝非本用户、symlink、硬链接与 extended ACL；debug/release 分开。使用系统 sqlite3，无外部依赖。schema version=1，事务写入；主数据库最多 32 MiB、最多 10,000 条、单条最多 8 KiB。使用 DELETE journal 和 secure_delete，避免长期积累 WAL；事务中的临时 journal 可能额外占用不超过数据库规模的空间。达到容量限制时 collection_error 可见，普通保活不受影响。

采样间隔允许 1...300 秒，保留时间允许 60...86400 秒，配置必须完整提供三个字段并跨重启保留。缩短保留立即删除过期记录；运行期间即使禁用采集也每分钟清理，查询/重启时再次清理。协调器停止期间没有后台清理进程，过期数据在下一次启动/查询删除；墙钟回退时删除未来记录。空间可复用，clear 会 VACUUM；要保持数据为空，先禁用采集再 clear，否则下一次采样会重新写入。

采集、写入在独立串行队列运行，错误不影响保活生命周期；写入后续采样重试，启动初始化失败通过 metrics IPC 返回错误。metrics 仅读取/存储设备数值与固定状态，不记录输入、窗口、应用列表、截图、硬件序列号或证书，不联网发送。

2026-10-05 本机 rootless smoke 获得有效 PSTR 读数（一个样本约 38.1 W），同时电池净功率为 0 W；验证无保活请求、SQLite 持久化、限量查询、禁用/重启/clear。真实电池放电与跨硬件功率校准尚未验证；单位、符号和无效输入有自动测试。

接口调研来源：[Apple 电池驱动实现](https://github.com/apple-oss-distributions/PowerManagement/blob/main/AppleSmartBatteryManager/AppleSmartBattery.cpp)、[power-monitor 的 SMC/IOReport 接口研究](https://github.com/electricapp/power-monitor)。仅参考 ABI 和传感器含义，未引入或复制其实现；没有新增第三方库。
