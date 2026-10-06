# 独立虚拟显示器性能对照

与 GUI/runtime 解耦的原生探针；使用已有 `VirtualDisplayHost` 二进制，创建和退出均绕过主 App 的会话管理。没有 AX、应用启动、输入、截图落盘或系统配置清理。

```sh
swiftc -swift-version 5 experiments/DisplayPerformance/Probe.swift -o /tmp/ocu-display-performance-probe
python3 -B experiments/DisplayPerformance/run.py --probe /tmp/ocu-display-performance-probe --output /tmp/ocu-display-observe --mode observe --seconds 20
python3 -B experiments/DisplayPerformance/run.py --probe /tmp/ocu-display-performance-probe --output /tmp/ocu-display-hotplug --mode hotplug --seconds 20
python3 -B -m unittest discover -s experiments/DisplayPerformance -p 'test_*.py'
```

已有身份的累积启停可用 `cycles.py` 分批验证，每批最多 3 次；例如上面的 hotplug 测试已预先使用槽位 31、且当前没有虚拟屏在线时：

```sh
python3 -B experiments/DisplayPerformance/cycles.py --probe /tmp/ocu-display-performance-probe --output /tmp/ocu-display-cycles-1 --helper 'dist/Open Computer Use.app/Contents/Helpers/VirtualDisplayHost' --slot 31 --cycles 3
```

每次在线持有 4 秒、移除后等待 2 秒，全程采样服务 CPU，包含创建/移除阶段。每次退出后检查 ICC 数量；若新增文件或另一个 OCU 显示器出现，停止这一批。首次使用尚无 ICC 的槽位会产生一份配置并中止，因此需要选已预热的身份。批次报告区分创建次数与批次是否完整结束；批间应另跑物理屏恢复窗口、收集用户体感。中断通过自身 helper 管道清理，不移除 ICC。2026-10-05 的累积对照总量上限为 9 次，不作为无界压力工具。

`hotplug` 要求已有签名 bundle 包含 helper，且测试开始时没有其他 OCU 虚拟屏。`--helper` 可指定另一份已构建 helper。接入/移除会触发系统桌面重配置，可能暂停其他会话、改变 Dock 位置；需要先协调测试窗口。这个模式四次创建、最多三个身份，使用生产固定池末端的空闲槽位并遵守跨进程身份锁，不使用随机 serial。发现其他 OCU 虚拟屏上线时中止并清理自身 helper。

测试会产生系统持久 ICC/显示布局记录，最多使用三个身份；不会删除这些记录。需要捕获的探针必须已有 Screen Recording 权限，否则明确跳过，不主动弹出权限请求。原始报告包含显示器 UUID/ICC 名称，保存在调用方指定的目录，不应原样提交到仓库。`Ctrl-C` 会停止自身负载并通过 stdin 关闭自身 helper；清理结果写报告，无法确认清理时会保留错误，不强杀其他进程。

## 对照内容

- `observe`：基线、CG 查询（目标 2/20 Hz）、SCK 枚举（目标 2 Hz），各自配恢复窗口；发现在线虚拟屏时追加捕获与捕获+渲染。每次捕获前重新查询目标，消失或权限缺失时跳过。实际查询频率见计数，调用耗时会降低实际频率。
- `hotplug`：物理屏基线、固定身份首次接入、同身份重建、两个不同身份接入；每次退出后观察恢复。首次持有期间加入 SCK 捕获、Metal 离屏渲染及恢复窗口。
- 捕获使用 BGRA、30 fps 上限、队列深度 3、最新 buffer；静态屏幕不要求持续收到完整帧。渲染以约 30 Hz 重绘最新帧，最多两份 GPU command 在途。它覆盖 CI/Metal 图像路径，不等同于完整 SwiftUI/MTKView 主界面测试。
- 每秒从进程累计 CPU 时间差计算单核百分比；报告 WindowServer 和两项 ColorSync 服务。没有测量整机帧延迟、GPU 或探针自身 CPU，不能以这份数据宣称整个 GUI 没有性能问题。
- 日志中的 `ColorSyncProfileCreateDeviceProfile` 是处理请求，不是每次新建 ICC 文件。文件数量、SHA-256、显示器身份和物理布局单独取快照。

已有异常循环时只能测增量；拓扑在测量窗口内变化时标记 `topology_changed`，不能把这种窗口当严格单变量对照。无法读取 root daemon 的堆栈时，不推断调用者。

## 只读色彩查询

```sh
clang -fobjc-arc experiments/DisplayPerformance/ColorProfiles.m -framework Foundation -framework CoreGraphics -framework ColorSync -o /tmp/ocu-display-profile-query
/tmp/ocu-display-profile-query
/tmp/ocu-display-profile-query --verify-ocu-files
/tmp/ocu-display-profile-query --repeat 16
```

查询在线屏幕的 factory/custom/current profile、有效性和 API 耗时；显式文件验证仅遍历 OCU 的 ICC。没有 profile setters、设备注册或缓存清理。重复查询限制为 1–16 轮，可用于采样自己拥有的客户端；这些查询也会产生系统调用，因此不能同时把该窗口称为完全无负载基线。API 耗时包含 WindowServer 状态查询与 ColorSync registry/XPC，不能全部归为 daemon 等待，也不等于打字延迟。输出的物理屏 profile 文件名可能包含 UUID，只在本地保留，提交前脱敏。

日志单独统计整组 `XPC_DISPLAY_INFO_REQUEST` 与逐屏 profile 调用；两项频率不能互换。拓扑首尾一致也不保证窗口中间没有热插拔，需结合逐屏日志和其他生产者记录判断。

本次脱敏指标见 [初始对照](results-20261005.json) 和 [累积启停/体感对照](results-subjective-20261005.json)，结论及剩余因果缺口见 [调查报告](../../docs/references/20261005-display-performance-causality.md)。

健康基线下的六次有界热插拔及 LG 断开/接回续测见[脱敏恢复指标](results-recovery-20261006.json)与[续测报告](../../docs/references/20261006-display-disconnect-recovery.md)。物理插拔由用户手动完成；只对已有固定身份测试，不删除 profile，不重启系统服务。

同日扩展为十组各三次、每组后被动观察 30 秒的[30 次累积记录](results-thirty-20261006.json)，另有停止后约 90 秒恢复窗口；[完整解释](../../docs/references/20261006-thirty-display-cycles.md)。原始窗口由 `cycles.run_batch` 与 `run.Experiment.phase` 编排采集，不提高单批次上限、不使用随机 serial。

当前分支重新编译并签名的同一 helper/bridge 二进制，分别在内置屏与 LG 条件各运行 30 次，见[内置屏数据](results-builtin-current-source-20261006.json)、[LG 数据](results-lg-current-source-20261006.json)及[同构建控制变量报告](../../docs/references/20261006-current-source-display-controls.md)。两个数据集包含相同构建/源码 SHA-256；不是对整个 GUI/registry 的端到端验证。

## 最小生命周期隔离

`build_isolation.py` 在仓库外复制当前 helper/bridge，构建 `current`、`drain`、`primaries` 三种实验变体；不会修改生产源码。三者都在自己的 helper 内给私有类 `dealloc` 加诊断：`current` 保持原逻辑，`drain` 提前释放对象并运行一秒 RunLoop，`primaries` 显式填写 Chromium 测试实现的色度坐标。这是用于排除假设的实验，不是已验证修复；编译锚点改变时拒绝自动补丁。可传 `--sign` 使用已有证书，产物和指纹留在输出目录。

```sh
python3 -B experiments/DisplayPerformance/build_isolation.py --variant drain --output /tmp/ocu-isolation-build
python3 -B experiments/DisplayPerformance/lifecycle.py --probe /tmp/ocu-display-performance-probe --helper /tmp/ocu-isolation-build/drain/.build/debug/IsolationHost --output /tmp/ocu-isolation-drain --slot 28 --cycles 3
```

`lifecycle.py` 每批最多三次，前后各 10–60 秒测量，默认任一 ColorSync 服务基线超过 5% 就不接入显示器；仅在明确记录增量对照时调整阈值，上限 20%。应选择已有 ICC 的空闲固定槽位，禁止随意生成身份。每次检查实际移除、退出、ICC 数量/内容、物理拓扑，异常即停止并清理自己的 helper。第一次使用未预热槽位仍可能新增一份 ICC 然后中止，不能把这个保护误读成不会生成记录。原始 stderr/报告含机器信息，不原样提交。

现有 `experiments/VirtualDisplay/Runner --holder-only` 是早期随机 serial 生命周期演示，会生成不同显示身份；**不要用于性能压力或 ICC 增长回归**。使用这里的固定身份、有界对照。正常会话默认 retain/reuse；真正释放、App 退出或崩溃仍会热插拔，不保证外屏 ColorSync 兼容问题消失。
