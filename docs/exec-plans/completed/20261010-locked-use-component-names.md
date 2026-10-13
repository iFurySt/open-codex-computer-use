# Locked Use 组件命名

## 目标
更新 PR #92：正式 App 使用 Open Computer Use.app / OCU Guardian.app；开发构建保留 Dev 显示后缀。后台程序统一为 OCULockService / OCULockInstaller，插件为 OCULockAuth.bundle，测试目标为 OCU Lock Demo，诊断插件为 OCULockProbe.bundle。

## 约束
保持内部签名标识、launchd Label、权限与许可规则稳定。组件目录按 debug / release 隔离，正式 App 不嵌入测试 App 或诊断插件。系统 Guardian 使用固定安装路径，显示名称仍区分构建配置。已有旧安装只经旧签名 installer 正常停用卸载后再安装；不在线重命名插件，不自动修改当前机器认证策略。

## 步骤
- [x] 同步构建产品、运行路径、安装器、诊断、授权机制和测试脚本。
- [x] 构建并校验两种配置的签名制品，运行回归及文档检查。
- [x] 更新历史、发布说明、PR 正文并推送。

## 验证结果
Swift 301 项（7 跳过）、Node 25 项、Python 29 项通过；debug / release 组件与 App 构建、严格签名、运行组件集合、plist 名称及诊断插件 ABI 校验通过。变更补充到 PR #92；未触碰当前机器的已安装认证组件。
