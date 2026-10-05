# 独立虚拟显示器性能对照

与 GUI/runtime 解耦的原生探针；使用已有 `VirtualDisplayHost` 二进制，创建和退出均绕过主 App 的会话管理。没有 AX、应用启动、输入、截图落盘或系统配置清理。

```sh
swiftc -swift-version 5 experiments/DisplayPerformance/Probe.swift -o /tmp/ocu-display-performance-probe
python3 -B experiments/DisplayPerformance/run.py --probe /tmp/ocu-display-performance-probe --output /tmp/ocu-display-observe --mode observe --seconds 20
python3 -B experiments/DisplayPerformance/run.py --probe /tmp/ocu-display-performance-probe --output /tmp/ocu-display-hotplug --mode hotplug --seconds 20
python3 -B -m unittest discover -s experiments/DisplayPerformance -p 'test_*.py'
```

`hotplug` 要求已有签名 bundle 包含 helper，且测试开始时没有其他 OCU 虚拟屏。`--helper` 可指定另一份已构建 helper。接入/移除会触发系统桌面重配置，可能暂停其他会话、改变 Dock 位置；需要先协调测试窗口。这个模式四次创建、最多三个身份，使用生产固定池末端的空闲槽位并遵守跨进程身份锁，不使用随机 serial。发现其他 OCU 虚拟屏上线时中止并清理自身 helper。

测试会产生系统持久 ICC/显示布局记录，最多使用三个身份；不会删除这些记录。需要捕获的探针必须已有 Screen Recording 权限，否则明确跳过，不主动弹出权限请求。原始报告包含显示器 UUID/ICC 名称，保存在调用方指定的目录，不应原样提交到仓库。`Ctrl-C` 会停止自身负载并通过 stdin 关闭自身 helper；清理结果写报告，无法确认清理时会保留错误，不强杀其他进程。

## 对照内容

- `observe`：基线、CG 查询（目标 2/20 Hz）、SCK 枚举（目标 2 Hz），各自配恢复窗口；发现在线虚拟屏时追加捕获与捕获+渲染。每次捕获前重新查询目标，消失或权限缺失时跳过。实际查询频率见计数，调用耗时会降低实际频率。
- `hotplug`：物理屏基线、固定身份首次接入、同身份重建、两个不同身份接入；每次退出后观察恢复。首次持有期间加入 SCK 捕获、Metal 离屏渲染及恢复窗口。
- 捕获使用 BGRA、30 fps 上限、队列深度 3、最新 buffer；静态屏幕不要求持续收到完整帧。渲染以约 30 Hz 重绘最新帧，最多两份 GPU command 在途。它覆盖 CI/Metal 图像路径，不等同于完整 SwiftUI/MTKView 主界面测试。
- 每秒从进程累计 CPU 时间差计算单核百分比；报告 WindowServer 和两项 ColorSync 服务。没有测量整机帧延迟、GPU 或探针自身 CPU，不能以这份数据宣称整个 GUI 没有性能问题。
- 日志中的 `ColorSyncProfileCreateDeviceProfile` 是处理请求，不是每次新建 ICC 文件。文件数量、SHA-256、显示器身份和物理布局单独取快照。

已有异常循环时只能测增量；拓扑在测量窗口内变化时标记 `topology_changed`，不能把这种窗口当严格单变量对照。无法读取 root daemon 的堆栈时，不推断调用者。

本次脱敏指标见 [results-20261005.json](results-20261005.json)，结论及剩余因果缺口见 [调查报告](../../docs/references/20261005-display-performance-causality.md)。
