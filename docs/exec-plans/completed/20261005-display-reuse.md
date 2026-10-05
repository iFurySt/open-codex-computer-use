# 显示器预热与复用

## 目标与边界

用户授权优先复用虚拟屏，提供调用方预热、复用、保留及释放参数。结束会话仍恢复借用窗口、处理专属实例和清理捕获；只把无会话的 helper/display 留在进程内。首次热插拔、配置不匹配及最终释放仍可能重置 Dock，不宣称独立桌面或完全消除桌面重配置。

## 调研与决策

- DockKeeper 的 separate-spaces-pinning 实测：底部 Dock 不稳定跟随主屏，AX/重启不能可靠恢复。全局鼠标召唤/拦截不符合本项目输入边界。
- Apple CGDisplayReconfigurationCallBack 只提供重配置通知，不是 Dock 位置设置 API。
- PrimeLab VirtualDisplay 技术记录提出持有显示器并复用；其对象残留报告仅作为版本相关线索。本项目继续用独立 helper、EOF 与确认移除。
- 默认复用匹配 width/height/scale 的空屏；默认结束保留，显式 retain_display=false 真正移除；Quit 释放全部。预热按配置幂等，不占会话且不允许输入。

## 进度与验证

- [x] 搜索开源与官方资料，确认目前没有验证过且满足输入边界的更好 Dock 恢复路径。
- [x] registry 空屏池、预热/释放、调用参数、GUI 共用。
- [x] Swift/Node contract、真实连续复用与最终移除测试。
- [x] 同步架构、使用/安全/质量/history，本地提交。

参考：https://github.com/blamechris/DockKeeper/blob/main/docs/spikes/separate-spaces-pinning.md 、https://developer.apple.com/documentation/coregraphics/cgdisplayreconfigurationcallback 、https://github.com/PrimeLab-Foundation/VirtualDisplay/blob/main/docs/platform/macos-virtual-display-apis.md

## 验证结果

macOS 26.5.1 / arm64：Swift 184 tests，1 opt-in skip；Node 25 contracts；现有工具及 cursor idle smoke 通过。真实签名 bundle 1×、2× 各 20 次预热后复用循环通过，display/helper 不变、session 身份隔离、每次收到真实 SCK 帧、Dock 所在屏/物理布局/主屏不变。补配置隔离、强制新建、活动屏释放拒绝、旧 session 失效、空闲 helper 异常退出、新建替代及 release/Quit；生产 release 主 bundle/helper 通过 codesign --verify。

一次额外 1× 测试被物理桌面上的 Chrome → ChatGPT 前台变化中断；这是未受控桌面的观察干扰，不能据此声称并行 AppKit first-responder 验收。runner 现在记录前台变化，并明确断言测试 OCU runtime 未被激活；重跑完整循环通过。首次接入/最终释放 Dock 重置、TextEdit 偶发闪现与全面并行输入验收仍在 desktop-containment 计划中。

构建曾在原 dist helper 签名时遇到 Operation not permitted；重试成功，改用独立输出目录完成签名/真实测试后恢复 dist。测试只用独立 socket namespace，不终止用户当前 GUI 或接管其应用；运行中的旧 GUI 需正常重启才加载新构建。
