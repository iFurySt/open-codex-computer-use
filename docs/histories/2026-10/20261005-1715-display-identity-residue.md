## 2026-10-05 | Task: 阻止虚拟显示器物理身份随 namespace 堆积

### Execution Context
- Codex /root，macOS 本地工作区。

### 用户诉求
全桌面卡顿，拔外接仍卡，怀疑反复创建/销毁残留；即使症状缓解也不能无限堆积色彩配置。

### 改动与设计
namespace 哈希 serial 改为跨 bundle/runtime 固定 32 槽位；仍避开在线及本地持有身份。跨进程文件锁覆盖选槽、helper ready 和 CG 上线，异常/崩溃释放锁；耗尽明确报错。新增只读系统诊断脚本。旧 ICC 已作本地副本备份，原系统文件未移动，未重启任何系统服务。

### 验证与限制
Swift 测试覆盖身份碰撞/耗尽/释放、1000 次身份分配不增长、锁异常释放；完整 186 tests（1 opt-in skip）通过；release bundle/helper 签名构建及 strict/deep 验证通过，已更新本地 dist，未启动应用或创建屏。真实诊断确认 139 份 OCU ICC，无在线虚拟屏/helper，混合布局含 100 个 UUID。卡顿因果未确定，性能恢复与旧残留隔离仍需协调验证，active plan 保留。没有继续创建显示器进行压力测试。固定身份不承诺 ICC 文件绝对数量上限。

### 主要文件
- packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplayIdentity.swift
- packages/OpenComputerUseKit/Sources/OpenComputerUseKit/VirtualDisplaySession.swift
- scripts/diagnose-virtual-display-residue.py
