# Software Cursor Overlay

这个文档聚焦一个很具体的问题：Codex Computer Use 在真实操作时显化出来的黄色小鼠标，是否是独立的软件光标 overlay，而不是直接抢占用户当前硬件鼠标。

结论先写在前面：从当前已经拿到的 bundle、字符串、资源名和运行时窗口证据看，这个黄色小鼠标基本可以确认是 `SkyComputerUseService` 自己持有的独立 `Software Cursor` 窗口。

## 已观察事实

### 1. 主宿主是一个无 Dock 图标的常驻 agent app

`Codex Computer Use.app/Contents/Info.plist` 可见：

```json
{
  "CFBundleExecutable": "SkyComputerUseService",
  "CFBundleIdentifier": "com.openai.sky.CUAService",
  "CFBundleName": "Codex Computer Use",
  "LSUIElement": 1
}
```

这里的 `LSUIElement = 1` 说明它是典型的 agent-style macOS app，更适合承载状态栏、浮层窗口和后台交互，而不是普通前台应用。

### 2. 主 app 资源里直接存在 cursor 相关资产

对主 app 的 `Assets.car` 做 `assetutil --info`，可以看到这些名字：

```text
Name: "CUAAppIcon_Assets/cursor"
Name: "CUAAppIcon_Assets/cursor dark"
Name: "menubar-cursor"
RenditionName: "menubar-cursor.svg"
```

这说明官方包里不仅有菜单栏图标资源，也有单独命名为 `cursor` / `cursor dark` 的图形资产。

进一步地，这些 asset 现在已经能直接导出为 PNG：

- [appicon-cursor.png](assets/extracted-2026-04-17/appicon-cursor.png)
- [appicon-cursor-dark.png](assets/extracted-2026-04-17/appicon-cursor-dark.png)
- [menubar-cursor.png](assets/extracted-2026-04-17/menubar-cursor.png)

另外，`Package_SlimCore.bundle` 和 `Package_ComputerUse.bundle` 中都能直接导出运行时用的小尺寸 `SoftwareCursor` 资源：

- [software-cursor-slimcore.png](assets/extracted-2026-04-17/software-cursor-slimcore.png)
- [software-cursor-computeruse.png](assets/extracted-2026-04-17/software-cursor-computeruse.png)

两份 `SoftwareCursor` 导出后的 PNG 二进制哈希一致，说明至少当前版本里它们引用的是同一张图。

### 3. `SkyComputerUseService` 字符串里出现了完整的光标窗口和动画线索

对 `SkyComputerUseService` 做 `strings`，能直接看到这些符号和日志文案：

```text
cursorWindow
imageView
imageLayer
cursorRadius
cursorScaleAnchorPoint
cursorMotionProgressAnimation
Moving mouse to %s
Start Bezier cursor animation (%{public}s).
Move cursor to (%f, %f) %s animation (%{public}s).
Signal cursor movement completion (%{public}s).
Enable the virtual cursor in Computer Use.
Detach the computer use cursor from the command palette.
```

这组证据比“有个 cursor 资源”更强，因为它已经落到了窗口对象、图层对象和运动动画对象这一层。

### 4. 运行时窗口清单里真的出现了 `Software Cursor`

在触发一次真实 `computer-use` 点击后，用 `CGWindowListCopyWindowInfo` 枚举窗口，能看到 `Codex Computer Use` 进程名下至少三个相关窗口：

```text
OwnerName: Codex Computer Use
WindowName: Software Cursor
Layer: 0
Bounds: X=1949 Y=696 Width=126 Height=126
IsOnscreen: 1
```

```text
OwnerName: Codex Computer Use
WindowName: Item-0
Layer: 25
Bounds: X=1804 Y=0 Width=21 Height=24
```

```text
OwnerName: Codex Computer Use
WindowName: ""
Layer: 25
Bounds: X=-754 Y=458 Width=41 Height=37
```

其中：

- `Item-0` 明显像菜单栏状态项窗口。
- 无标题 `41x37` 小窗长期藏在屏幕外，更像一个备用的内部 UI 容器。
- `Software Cursor` 是最关键的直接证据，名字已经把职责写出来了。

### 5. `Software Cursor` 会随着一次次工具动作改变位置

对 Finder 连续做两次安全点击后，再次枚举窗口，`Software Cursor` 的坐标发生了变化：

第一次：

```text
WindowName: Software Cursor
Bounds: X=1949 Y=696 Width=126 Height=126
```

第二次：

```text
WindowName: Software Cursor
Bounds: X=1949 Y=796 Width=126 Height=126
```

这说明它不是静态装饰，而是一个会被操作事件驱动移动的独立窗口。

## 当前推断

### 1. 黄色小鼠标是软件光标，不是系统硬件光标

当前最合理的解释是：

- 真正的系统事件仍然由 automation / event tap 路径发给目标 app。
- 用户看到的黄色小鼠标，是 `SkyComputerUseService` 自己渲染的一层“软件光标”。
- 这层软件光标单独运动、单独做动画，因此视觉上能模拟“鼠标在动”，但不需要真的抢走用户平时看到的系统箭头。

### 2. 它大概率是一个透明背景的小窗口，而不是注入目标 app 的子视图

原因有三点：

- 字符串里直接出现 `cursorWindow`。
- 运行时 `CGWindowList` 能枚举到命名明确的 `Software Cursor` 窗口。
- 这个窗口 owner 是 `Codex Computer Use`，而不是被控 app。

所以它更像一个由 service 维护的独立 overlay window，而不是 Finder / System Settings 之类 app 内部被插入了一块绘制层。

### 3. 黄色外观大概率来自 app 自带 cursor asset，而不是系统默认箭头重着色

这一点目前还是推断，但证据方向比较一致：

- `Assets.car` 里有专门的 `cursor` / `cursor dark` 资源。
- 二进制里同时出现 `imageView` / `imageLayer` / `imageForResource:` / `imageNamed:`。

这更像“加载自带图片资源并在窗口里渲染”，而不是直接拿系统箭头做系统级替换。

## 为什么这套体验不会抢用户鼠标

如果这个判断成立，那么体验上“看起来像有一个额外的小黄鼠标在代操作，但用户自己的真实鼠标仍然自由”就很好解释了：

- automation 层负责发真实点击和移动事件；
- overlay 层只负责给人看；
- 两者在视觉上对齐，但逻辑上分离。

这比直接操纵系统可见光标更稳，也更容易做出平滑路径、点击高亮和 delay 控制。

## 还没完全确认的点

- 还没有抓到一次动画进行中的连续窗口轨迹，目前只有离散位置点。
- 当前 `get_app_state` 返回的截图里通常看不到这个光标，推测截图采样路径和 overlay 合成路径并不完全相同，但这还需要单独验证。

## 对开源实现的启发

如果后续要做 `open-computer-use` 的可用体验，这条发现很有价值：

- 可以把“真实输入注入”和“软件光标可视化”明确拆开。
- 软件光标可以做成独立 overlay window，而不是强依赖真实鼠标位置。
- 事件执行即使失败，overlay 也可以保持可观测，有利于调试和用户信任。
- 菜单栏状态项和软件光标都放在同一个 `LSUIElement` agent app 里，是一条已经被官方实现验证过的产品形态。
