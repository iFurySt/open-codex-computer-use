# 虚拟显示器身份与 ColorSync 残留

## 目标与边界
阻止测试 namespace / bundle 变化导致新物理显示器身份无限产生；只读诊断 ICC 与 WindowServer 记录，保留物理屏配置。不将残留数量直接等同卡顿根因，不继续 hotplug 压力测试，不自动删除 root-owned 配置或重启系统服务。

## 证据
当前没有在线虚拟屏/helper；139 份 OCU ICC 文件，用户 WindowServer prefs 中 100 个不同 UUID（不能全部认定属于 OCU）。拔 LG 后 ColorSync CPU 接近 0，WindowServer 仍约 58%。开源 MirageKit 有相同症状报告，另一个项目在同版 macOS 记录 unbounded serial 导致 registry bloat，均为回归线索而非本机因果证明。

## 进度
- [x] 只读确认残留与 namespace-dependent serial。
- [x] 固定有界跨 namespace 身份池、碰撞/耗尽回归。
- [x] 可重复只读诊断入口、文档/history、本地提交。
- [ ] 接回 LG 后性能观察与有备份的定向残留修复（待用户协调；不自动修改全局缓存）。

## 交付与待办
预防性代码已完成 186 tests（1 skip）和正式签名构建/验证，本地 dist 已更新。旧 139 份 ICC 已复制校验清单备份，原系统文件未移动。接回 LG 后下一次采样 ColorSync 两服务均 0%，WindowServer 约 40%；不能证明旧 profile 无害或导致卡顿。管理员非交互检查失败（需要密码），旧残留清理及前后性能验证仍待协调，不自动清空全局缓存。
