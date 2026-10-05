# 电源 metrics 与短期存储

提供统一可扩展的 Swift metrics 数据模型、只读 native collector、SQLite 有界本地存储，以及 SDK/CLI 查询/configure/clear。默认每 5 秒采样、保留 1 小时，采集只随 coordinator 生存，不因为 metrics 禁止睡眠。无 root/subprocess/raw IORegistry dump；每个功率值附 source/quality/scope，缺失不补零，不把电池功率称作整机功耗。持久化仅允许数值/固定状态与保活聚合，不保存用户输入、应用列表或截图。

- [x] 核对实际可用的功耗来源与单位
- [x] 实现采集、SQLite 保留/容量上限、查询与配置
- [x] 测试单位/符号/缺失、保留/重启、禁用及 IPC
- [x] 实机 smoke、文档/history、合并

普通 assertions 与合盖后端不依赖 metrics 成功；写入失败可见并允许重试。采集间隔/保留有硬上限与 query limit，避免无界增长。

## 验证结果

30 项独立 package 测试通过（10 项 metrics，覆盖保留/容量、配置持久化、时钟回退、禁用/清空、IPC、错误隔离与重试）。rootless native smoke 获得有效 PSTR（一个样本约 38.1 W）和电池净功率 0 W，并验证无保活、SQLite 重启、查询上限和禁用。普通保活跨进程 smoke 与 Developer ID 正/负例回归通过。数据为全机传感器读数，没有调用方归因或功率计校准；电池放电与其他设备留作后续兼容性验证。

release 构建与已安装 Developer ID App 的 metrics 查询通过，读回约 36.8 W 整机轨、0 W 电池净功率及采集耗时/状态。已安装 App 不需要重新批准后台项。

已安装 App 的 2 次开盖 AX/SCK 与真实合盖开关/定时/协调器崩溃恢复回归通过。已同步主分支最新提交；两处共享文档冲突保留双方最新内容，模块代码无冲突。
