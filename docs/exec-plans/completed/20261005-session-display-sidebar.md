# Sessions / Displays 侧栏与显示器删除

## 目标与边界
- 原生 NavigationSplitView toolbar、侧栏全高与品牌保持；内容改为 Sessions / Displays 两个独立可折叠分组。箭头/加号、行删除在 hover 时显示，控件保持可访问。
- 分组加号创建会话；显示器同时展示活动与空闲资源。选中活动屏显示其会话，选中空屏可在该屏创建会话。
- 默认删除 session 保留屏；context menu 可选择同时删除屏。删除 display 串行安全结束全部关联 session 后释放；失败保留未完成状态，不强杀应用，不承诺可回滚的 all-or-nothing。

## 进度
- [x] typed 显示器查询、精确租用与显示器级删除 API/tools。
- [x] 两分组 hover 控件、选择与删除策略。
- [x] Swift / Node / 真实 signed runtime 删除回归、GUI 检查和签名构建。
- [x] 文档/history 同步、本地提交。

## 验证记录
Swift 184 tests（1 opt-in skip）、Node 26 tests、签名 runtime 两轮复用及精确租用/级联删除通过；原生 GUI 分组折叠检查通过。最终签名制品构建通过。性能排查启动后停止新增 hotplug 验证；hover 视觉效果仍需人工复核。
