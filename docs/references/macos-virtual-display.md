# macOS 虚拟显示器参考与边界

核对日期：2026-10-05。生产 bridge、holder、session 与预览由本仓库自行维护，第一版不依赖第三方显示器包，也没有复制第三方实现源码。原生 GUI 参考自有 HeyYo 的 SwiftUI/AppKit 单例窗口、NavigationSplitView 和 toolbar 模式，不引入其登录、录音或网络业务。

| 来源 | 采用经验 | 不据此推断 |
| --- | --- | --- |
| [Chromium virtual_display_util_mac.mm](https://chromium.googlesource.com/chromium/src/+/HEAD/ui/display/mac/test/virtual_display_util_mac.mm)（核对 blob `be79514b3803c3b6078fa8d96022aa185ab4f940`） | 四个私有类接口、非零 vendor、独立 serial、HiDPI mode 和异步显示器检测；Chromium 同样保留 removal workaround | 对象释放在所有系统上都可靠，或私有 ABI 有 Apple 兼容承诺 |
| [DeskPad](https://github.com/Stengo/DeskPad) | 虚拟屏投影到独立 App 窗口的形态 | 任意应用都能后台输入 |
| [VirtualDisplayKit](https://github.com/xocialize/VirtualDisplayKit) | 显示器和预览模块拆分方式 | 第一版必须增加该依赖 |
| [standardassistant](https://github.com/UsefulSoftwareCo/standardassistant) | 分离显示、捕获、窗口管理 | 移动真实鼠标/改变系统焦点符合 OCU 后台边界 |
| [VirtualDisplay 技术记录](https://github.com/PrimeLab-Foundation/VirtualDisplay/blob/main/docs/platform/macos-virtual-display-apis.md) | 对象释放后可能残留的项目实验，促使采用专用持有进程和移除断言 | 个别异常必然是 macOS 通用规律 |
| [Apple SCStream](https://developer.apple.com/documentation/screencapturekit/scstream) | 使用正式 ScreenCaptureKit 流与帧输出接口 | 静止桌面没有新帧就是捕获失败 |

第三方材料用于方向和接口核对。若后续复制源码，必须单独保留其许可证、版权和来源。私有 API 实际支持范围以本仓库 runner 的系统/架构测试证据为准。

实现、使用和兼容性矩阵见 [设计文档](../design-docs/virtual-display.md)。
