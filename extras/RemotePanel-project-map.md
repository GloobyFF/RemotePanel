# RemotePanel 项目对照表

更新时间：2026-07-02

## 1) iPad Standalone（旧项目）
- 项目目录：`/Users/teamc/Documents/RemotePaneliPadStandalone`
- 用途：旧 iPad 轮播/预览项目
- 端口：`9120`
- 主访问地址：`http://192.168.28.12:9120/ipad`
- 本机地址：`http://127.0.0.1:9120/ipad`
- 启动脚本：`/Users/teamc/Documents/RemotePaneliPadStandalone/run_ipad_server.command`
- 维护定时：每天 `04:00`
- cron job_id：`474cf8339595`
- 说明：仍在使用，不能因为 h5-lite 项目而误停服务。

## 2) H5 Lite Standalone（当前 H5 项目）
- 项目目录：`/Users/teamc/Documents/RemotePanelih5Standalone`
- 用途：h5-lite 页面、控制台、9121 预览服务
- 端口：`9121`
- 主访问地址（H5）：`http://192.168.28.12:9121/h5-lite`
- 主访问地址（控制台）：`http://192.168.28.12:9121/ipad/control`
- 本机地址（H5）：`http://127.0.0.1:9121/h5-lite`
- 本机地址（控制台）：`http://127.0.0.1:9121/ipad/control`
- 启动脚本：`/Users/teamc/Documents/RemotePanelih5Standalone/run_ipad_server.command`
- 维护定时：每天 `02:00`
- cron job_id：`932b181c9c22`
- 说明：这是当前 h5-lite standalone，不要和 9120 的旧 iPad standalone 混淆。

## 3) RemotePanelEInkStudio（墨水屏项目）
- 项目目录：`/Users/teamc/Documents/GitHubResearch/RemotePanelEInkStudio`
- 用途：墨水屏模板发送 / 自动轮播 / studio 运行时
- 主运行进程：`studio/app.py`
- 关键运行态文件：`/Users/teamc/Library/Application Support/RemotePanelEInkStudio/hermes_bridge/state.json`
- 维护定时：每天 `05:00`
- cron job_id：`1426ce391211`
- 说明：这是独立项目，不走 h5-lite 9121，也不是旧 iPad standalone 9120。

---

## 快速判别规则
- 看到 `9120`：优先想到 **RemotePaneliPadStandalone**
- 看到 `9121`：优先想到 **RemotePanelih5Standalone / h5-lite**
- 看到 `studio/app.py` 或 `RemotePanelEInkStudio`：优先想到 **墨水屏项目**
- 看到 `/ipad/control`：默认是 **9121 的 h5-lite 控制台**，不是 9120 墨水屏，也不是 E-Ink Studio GUI

## 操作边界
- 不要因为修 `9121` 就停掉 `9120`
- 不要因为修 `9120` 就动 `9121`
- 不要把 E-Ink 的 bridge/state 判成 h5-lite 的状态文件
- 清理 Python 进程时，必须按 **项目目录 + 端口/主进程** 精确区分
