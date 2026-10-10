# Locked Use 独立 PR 提取

## 目标和范围
从 awesome-extension 的最终 Locked Use 实现提取独立 PR，基于最新 main，不携带虚拟工作区、独立电源模块、AX diff 或 ColorSync 调查。保留 main 已合并的后台窗口、sky_key 与 agent display 生命周期。

## 约束和风险
- 不修改 awesome-extension 或既有运行实例；所有操作在独立 worktree。
- 保留管理员显式验证 profile、原生认证 fallback 和生产证据门槛，不为提取自动锁屏或安装系统组件。
- main 的新增 SkyLight 输入路径也必须检查租约；租约内捕获明确走 ScreenCaptureKit，普通后台窗口保持原捕获行为。
- main 没有 AX diff API，固定验证器继续读取其完整快照；保留 post-merge 失败先结束租约的修正和实际计数 / 图像变化日志。
- 保留 MCP endSession 的 agent display / occlusion 恢复，不用 turn-ended 替代最终清理。

## 步骤
1. [x] 同步 main，提取原独立 feature diff 和合并后的必要修正。
2. [x] 处理共享构建及退出路径冲突，补齐新输入路径门和捕获选择。
3. [x] 运行 Swift / Node / Python 回归、文档检查和构建检查。
4. [ ] 核对 diff 范围，记录历史 / 发布说明，提交并推送独立分支，创建 main PR。

## 验证边界
既有双物理屏完整 legacy 闭环及用户确认属于 awesome-extension 的实机证据；本次独立分支另跑离线 / 构建集成检查，不将旧实测当作新分支的真实锁屏验收。完整 Data Protection、Secure Input、组件死亡和显示器矩阵仍未完成，生产保持关闭。

## 检查结果
Swift 301 项（7 跳过、0 失败），Node 25 项，Python 28 项，文档检查、组件 / App 签名构建与 ABI 检查通过。make check-repo 的模板缺失属于 main 的既有问题，不在本次修复范围。
