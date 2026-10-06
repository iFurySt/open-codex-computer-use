# 单文件独立 ColorSync 触发复现

日期：2026-10-06，macOS 26.5.1 / arm64，内置屏 + LG，原有外屏连接路径保持。接续[生命周期隔离](20261006-colorsync-root-isolation.md)，用户要求用最少独立代码缩小触发范围。

## 复现与定位结果

**71 行独立 Objective-C demo 复现了配置虚拟屏、退出后的请求频率增量；不需要链接任何 OCU 模块。** 同一签名二进制的两个单轮条件：

1. 构造 descriptor → `initWithDescriptor:` → 等待 → EOF/退出：没有虚拟屏上线，未观察到此前每轮约 0.4 请求/秒的增幅。
2. 同样初始化，再 `applySettings:`（1920×1080、60 Hz、hiDPI=false）使显示器上线 → 退出并确认移除：请求频率从约 2.19 升至 2.57 次/秒。

最小触发路径已缩为 **私有显示器初始化、应用模式上线、退出移除**。descriptor 本身和未配置模式的实例未表现出同样的阶梯。不能据此断言 `applySettings:` 内部某一函数就是缺陷：该调用同时使屏幕上线，注册/上线/移除的系统内部路径仍未进一步分离。

## 测量

每窗约 20 秒，CPU 为两项 ColorSync 服务累计 CPU 时间差之和，100% 表示一核。不是新的健康基线实验：此前约 2.2 请求/秒的异常仍在，采用顺序增量对照。

| 条件/阶段 | ColorSync CPU | 显示信息请求/秒 | 在线屏数量 |
| --- | ---: | ---: | ---: |
| 不应用模式：基线 | 14.31% | 2.140 | 2 |
| descriptor 后 | 14.56% | 2.195 | 2 |
| init 后 | 14.27% | 2.191 | 2 |
| 退出后 | 14.96% | 2.198 | 2 |
| 应用模式：基线 | 14.68% | 2.194 | 2 |
| descriptor 后 | 14.57% | 2.141 | 2 |
| init 后 | 14.58% | 2.194 | 2 |
| apply 后，虚拟屏在线 | 49.25% | 2.378 | 3 |
| 退出/移除后的被动窗口 | 17.71% | 2.572 | 2 |
| 再次静置观察 | 16.93% | 2.582 | 2 |

在线窗口包含初始色彩配置工作，约 49% 不能当作移除后的持续 CPU。apply 阶段超过 25% 合计 CPU 守卫，控制器停止后续阶段并正常清理；之后用纯被动探针取得退出后的数值。两个进程均 exit 0，CG 确认移除，无清理错误。不是重新做 30 次压力。

匹配 ICC 总数始终 146；apply 对照更新一份现有 ICC 的内容（前轮显式色度实验后返回缺省描述符），没有新增/删除文件。不能把这一组称为 ICC 内容完全不变的实验。前轮同身份、内容恒定的 30 次对照仍是已有独立证据。物理屏身份/坐标在检查边界保持不变。

## demo 的最小依赖与核心代码

[MinimalDisplay.m](../../experiments/DisplayPerformance/MinimalDisplay.m) 仅依赖 Foundation/CoreGraphics，运行时调用私有类，没有 OCU bridge/runtime、SwiftPM、NSApplication、AX、SCK、Metal、布局事务或析构 hook。也去掉了生产的额外 `serialNumber` setter，只保留 `serialNum`。固定已预热槽位避免新身份扩张；参数约束和 stdin 协议提供阶段停顿，不属于显示器实现的业务依赖。

核心是 descriptor 固定身份/尺寸/队列，`initWithDescriptor:`，`CGVirtualDisplayMode` 的 1920×1080/60Hz 模式，settings 的 modes/hiDPI，`applySettings:`，最后 ARC/autoreleasepool 与进程退出。没有公开的“目标应用”“窗口”“屏幕捕获”等代码。这足以作为后续私有 API/系统连接链路诊断的最小触发案例。

控制器 [minimal.py](../../experiments/DisplayPerformance/minimal.py) 每次仅一个进程，复用已有被动 CPU/日志探针；源码核心可单独用 clang 构建，不依赖控制器才能运行。运行命令与副作用见[实验 README](../../experiments/DisplayPerformance/README.md)。创建锁在未上线阶段可能使其他创建请求暂时等待，需协调测试窗口。不要未经预热更换槽位。

## 边界与下一层方向

- demo 独立不等于系统环境已隔离：其他工作树 runtime 仍保留，外屏/CalDigit 链路、历史状态和 root 请求发起者尚未分离。
- 单轮增量与前次 .4 请求/秒阶梯一致，但没有健康基线上的多轮最小 demo 对照，不能由单轮确定具体系统缺陷或硬件责任。
- 下一步可在健康基线复跑同一 demo，并对照外屏直连/扩展坞，或测试同一进程持有、不同 dispatch queue、不同模式应用时序。优先围绕已缩小的私有显示器路径，不继续扩展到 GUI/输入代码。
- 本轮没有生产代码修复，固定身份与显示器保留/复用仍是缓解；不把最小复现误称为根因修复。

[脱敏数据及同一源码/二进制指纹](../../experiments/DisplayPerformance/results-minimal-20261006.json)。13 项 Python 测试通过，clang 构建及严格 Developer ID 签名验证通过；参数拒绝、无创建 EOF、非法阶段退出均实测。首个新签名进程启动超过五秒，本地无创建冒烟改用二十秒超时后通过，未放宽创建/清理安全守卫。正式 App 制品未改变，不重启其他工作树 runtime。
