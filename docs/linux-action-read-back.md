# Linux 动作回读

Linux 默认在动作后等待 120 ms，再返回完整快照。`OPEN_COMPUTER_USE_ACTION_READ_BACK=0` 会省去这一步，成功动作只返回 `ok`。`false`、`no`、`off` 也可以，忽略大小写和首尾空白。JS REPL 已自动设置这个变量。

关闭回读后，动作保留上次观察的索引缓存；界面变化后应通过 `get_app_state` / `getAXState()` 更新状态再选目标。显式观察照常返回快照，动作错误照常返回。`ok` 表示调用完成，不能代替界面结果验证。

## 测试

Linux 回归测试：

```sh
(cd apps/OpenComputerUseLinux && go test ./...)
python3 apps/OpenComputerUseLinux/runtime_test.py
node --test scripts/node-repl/*.test.mjs
```

真实控件测试使用私有 D-Bus 会话和 Xvfb 显示器，不操作已有桌面。Debian / Ubuntu 需要 `python3-gi`、`gir1.2-gtk-3.0`、`gir1.2-atspi-2.0`、`at-spi2-core`、`dbus-x11`、`xvfb` 和 `xauth`。

在 Linux 上构建 native binary，然后运行：

```sh
(cd apps/OpenComputerUseLinux && go build -o /tmp/ocu-read-back-test .)
bash scripts/run-linux-read-back-smoke.sh /tmp/ocu-read-back-test
```

脚本创建自己的 GTK 窗口，通过 native MCP 执行点击、secondary action、设值、中文 / emoji 输入和 Return，并检查控件的实际状态；同时验证关闭回读时的短响应、连续动作索引、错误传播、显式观察和默认快照。结束后清理测试进程、会话、显示器和临时文件。

这项测试覆盖 X11 / GTK / AT-SPI，不代表 GNOME Wayland、其他应用或完整任务的性能测试。
