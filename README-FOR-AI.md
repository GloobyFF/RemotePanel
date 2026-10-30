# RemotePanel 交接说明（给后续 AI） / Handoff for successor AIs

更新日期 / Updated: **2026-10-30**（Asia/Shanghai）

本包路径（TeamC Mac mini）：
- 目录：`/Users/teamc/Documents/RemotePanel-handoff-20261030/`
- 压缩包：`/Users/teamc/Documents/RemotePanel-handoff-20261030/RemotePanel-handoff-20261030.zip`

---

## 1. 产品是什么 / What this is

**RemotePanel** 是跑在 **Easton iPad 3（iOS 9.3.5）** 上的 **原生 Objective-C 资讯亭 / kiosk**。

- 全屏轮播多页内容（天气、新闻、GitHub AI/热门、相册、打印机、电影、Steam、Switch、PS5 等）。
- **每 30 秒**轮询 TeamC 上的 H5/API 服务：`http://192.168.28.12:9121/api/h5/state?rotate=1`
- UI：深色像素风字体、彩色卡片；内容区字号约 **2×** 旧版（`RPTheme.contentScale == 2.0`）。
- 支持横屏 + 竖屏（`Info.plist` 四个方向）。
- **禁止**：Swift / SwiftUI / 依赖 iOS 10+ API。必须保持 **ObjC + iOS 9.3 / armv7**。

---

## 2. 设备与签名 / Device & signing

| Item | Value |
|------|-------|
| Device | Easton iPad 3 / iOS **9.3.5** |
| UDID | `1b9b4d6959e9d533837d946d94105049dfd794a8` |
| Bundle ID | `com.glooby.RemotePanel` |
| Display name | RemotePanel |
| Team ID | `FLFYQXCCZM` |
| CFBundleShortVersionString | `2.0` |
| CFBundleVersion (build) | **`3`**（本包对应刚装上的版本） |
| App Icon | `Images.xcassets/AppIcon.appiconset`（已嵌入） |

Provisioning 细节见 `ios/PROVISIONING-NOTES.txt`。  
**密码 / keychain / SSH 凭证不要写进仓库或 README** —— SSH 到编译机请用用户 `fangzhiling`，凭证找 operator。

---

## 3. 机器与路径 / Hosts & paths

| Role | Host | Notes |
|------|------|-------|
| TeamC（API + 本 handoff） | `192.168.28.12`，user `teamc` | H5/API：`/Users/teamc/Documents/RemotePanelih5Standalone`，port **9121** |
| Build Mac（Xcode 10.1 / High Sierra） | `192.168.28.179`，user `fangzhiling` | 规范 Xcode 树：`/Users/fangzhiling/Developer/RemotePanel` |
| 编辑中转（可选） | TeamC `Documents/RemotePanel-ios-edit/` | 本轮 redesign 曾在此改，再同步到 `.179` |

**本包 iOS 源选取理由：**  
对比 TeamC `RemotePanel-ios-edit` 与 `.179` `Developer/RemotePanel` 后，选用 **`.179` 规范树**（rsync 进 `ios/`）：
- `CFBundleVersion = 3`
- 含 `AppIcon.appiconset`
- `RPPages.m` 1542 行 / `RPKioskRootVC.m` 621 行，与刚安装的二进制一致
- Roster 已去掉 `system` / `weather-weekly` / `vps` 独立页；`weather` 标题为「天气+VPS」
- `RPTheme.contentScale = 2.0`，彩色 `cardTint:`
- 含完整 `RemotePanel.xcodeproj` + `build_install.sh`

TeamC `RemotePanel-ios-edit/RemotePanel/` 内容基本同源，但根目录散落旧副本且缺规范 `.xcodeproj` 包装；`RemotePanel-work/src-sync` 是更早的中间态（仍含 system/weekly，CFBundleVersion 2），**不要当最新**。

---

## 4. 当前轮播页 Roster（已启用）

定义在 `ios/RemotePanel/RPKioskRootVC.m` → `-buildMasterRoster`：

| pageId | 标题 | 默认 dwell(s) |
|--------|------|---------------|
| `hello` | 问候海报 | 60 |
| `weather` | 天气+VPS | 70 |
| `daily-news` | 每日新闻 | 70 |
| `github-news` | AI·热门项目 | 70 |
| `person-photo-local-1` | 本地相册 A | 60 |
| `print` | 打印机 | 75 |
| `movie-now-showing` | 最近上映 | 35 |
| `steam-new-releases` | Steam 新游 | 60 |
| `steam-new-releases-2` | Steam 热销 | 60 |
| `gamer520-pc-latest` | PC 游戏上新 | 60 |
| `person-photo-local-2` | 本地相册 B | 60 |
| `gamer520-switch-latest` | Switch 上新 | 60 |
| `ps5-games-latest` | PS5 上新 | 60 |

### 已从 roster 移除（代码仍保留 factory，便于回滚）

启动时强制 `RemotePanel.page.enabled.* = NO`：
- `system` — 系统状态（原独立页）
- `weather-weekly` — 本周天气（已并入 weather 页）
- `vps` — VPS 配额（已并入 weather 页）

Factory 仍在 `RPPageFactory` 里识别这些 id，但默认不会轮播。

---

## 5. 本轮已交付的关键 Feature

- 内容字号约 **2×**（`+[RPTheme contentScale]` / `snap:`）
- **彩色卡片**背景（`cardTint:`）
- **天气页合并** weekly 预报 + VPS 用量条
- **GitHub / AI 热门**：`news.github_items` + 点击 **detail modal**
- **每日新闻** tap detail modal
- **App Icon** 资源进 Asset Catalog
- Switch / PS5 使用接口里的 **真实 `title`**（不再占位假名）
- 打印机合并为单页 dense 布局
- Settings：右上角齿轮 + 长按；每页 enable / dwell；相册来源；base URL（`NSUserDefaults`）

---

## 6. 重要源文件地图 / Source map

全部在 `ios/RemotePanel/`：

| File | Role |
|------|------|
| `RPKioskRootVC.m` | 根 VC：roster、轮播、dwell timer、30s poll、Settings UI、modal 时暂停轮播 |
| `RPPages.m` / `RPPages.h` | 各页 VC + `RPPageFactory`（weather/news/github/print/movies/steam/games/photo…） |
| `RPAPIClient.m` | `GET /api/h5/state?rotate=1` → `NSDictionary` |
| `RPTheme.m` | 颜色、像素字体、`contentScale`、卡片 tint |
| `RPPhotoSource.m` | 本地相册：Favorites → Camera Roll → All Photos → Moments |
| `AppDelegate.m` / `main.m` | 启动 |
| `Info.plist` | 版本、字体列表、ATS（允许局域网 HTTP）、方向、相册权限文案 |
| `Images.xcassets/AppIcon.appiconset` | 应用图标 |
| `fonts/` | Fusion Pixel / Ark Pixel / Zpix / WeatherIcons |
| `../build_install.sh` | 在 `.179` 上 xcodebuild + ios-deploy |
| `../RemotePanel.xcodeproj` | Xcode 10.1 工程 |
| `../PROVISIONING-NOTES.txt` | 签名摘要（无密码） |

### Settings keys（`NSUserDefaults`）

- `RemotePanel.baseURL` — 默认 `http://192.168.28.12:9121`
- `RemotePanel.dwellOverride` — 全局 dwell；`0` = 用每页默认
- `RemotePanel.page.enabled.<pageId>` — BOOL
- `RemotePanel.page.dwell.<pageId>` — 每页秒数覆盖
- 相册相关 key 见 `RPPhotoSource` / Settings UI 代码

---

## 7. 编译与安装 / Build & install

**只能在 Build Mac `.179`（High Sierra + Xcode 10.1）上编 armv7 / iOS 9.3。**

```bash
# 在 .179 上（路径为规范树）
cd /Users/fangzhiling/Developer/RemotePanel
# 若用本包覆盖规范树：先把 ios/ 同步过去，再：
export SSHPASS='…ask operator…'   # 仅用于 unlock keychain；不要写入文件
./build_install.sh
```

`build_install.sh` 要点：
- `ARCHS=armv7`，`IPHONEOS_DEPLOYMENT_TARGET=9.3`，`TARGETED_DEVICE_FAMILY=2`
- Manual signing：Team `FLFYQXCCZM`，profile UUID 见脚本 / PROVISIONING-NOTES
- 安装工具：`ios-deploy`（路径写在脚本里，缺失需在本机重编）
- 本 handoff 里的脚本 **已去掉默认 keychain 密码**；必须由 operator 提供 `SSHPASS` 或手动 unlock

TeamC **不能**替代 `.179` 做这份旧 SDK 编译。

同步建议（operator 执行）：

```text
TeamC ios/  --rsync-->  fangzhiling@192.168.28.179:/Users/fangzhiling/Developer/RemotePanel/
```

---

## 8. 服务端 / Server（API shapes）

本包 `server/` = `RemotePanelih5Standalone` 的瘦身副本（**不含**约 5GB 的 `ipad/data` 媒体缓存、不含 `.venv`）。

### 运行（TeamC 现网）

```bash
cd /Users/teamc/Documents/RemotePanelih5Standalone
# 或双击 run_ipad_server.command
python3 ipad/ipad_server.py --host 0.0.0.0 --port 9121
```

- H5 预览：`http://192.168.28.12:9121/h5-lite`
- 控制台：`http://192.168.28.12:9121/ipad/control`
- **原生 App 只依赖 JSON API**，不加载 H5 WebView 做主 UI（个别 fallback 除外）

### curl 探测

```bash
curl -sS 'http://192.168.28.12:9121/api/h5/state?rotate=1' | python3 -m json.tool | head
```

### 顶层 JSON keys（实测）

`active_screen`, `alerts`, `bilibili`, `daily`, `device`, `gamer520`, `media`, `mode`, `movies`, `news`, `ops`, `penguin`, `photo_gallery`, `print`, `ps5_games`, `schedule`, `screens`, `session`, `stage`, `steam`, `switch_games`, `template`, `updated_at`, `vps`, `weather`, `work`

### App 常用字段

| Key path | Used by |
|----------|---------|
| `weather`（含 `weekly` list，`temperature`, `description`, `icon`…） | weather 页 |
| `vps`（`used`, `remain`, `percent`, `cycle`, `status`） | weather 页合并展示 |
| `news.hello` / `news.hello_items` | hello |
| `news.daily` / `news.daily_items`（`title`, `summary`, `image_url`, `link`） | daily-news + modal |
| `news.github` / `news.github_items` / `news.github_meta` | github-news + modal；item 含 `full_name`, `description`, `stars`, `language`, `url`, `topics`… |
| `print` | 打印机页 |
| `movies[]`（含 `poster_url` 等） | movie-now-showing |
| `steam` | Steam 两页（offset 0/1） |
| `gamer520` / 列表字段 | PC 游戏 |
| `switch_games[]`（`title`, `image_url`, `link`） | Switch |
| `ps5_games[]`（`title`, `image_url`, `link`） | PS5 |
| `ops` | 旧 system 页（已默认关闭） |

主实现文件：`server/ipad/ipad_server.py`（很大）；共享逻辑在 `server/core/`（`weather.py`, `news.py`, `github_ai.py`, `steam.py`, `ps5games.py`, `gamer520.py`, …）。

依赖：见 `server/requirements.txt`（目前主要是 `pillow`）；完整环境可用 `uv.lock` / 现网 `.venv`（未打进包）。缺媒体缓存时图片 URL 可能 404，但 JSON 结构仍可对。

---

## 9. 约束 / Hard constraints

1. **iOS 9.3.5 only**，armv7，Xcode 10.1 工具链。
2. **Objective-C only** — 不要引入 Swift、SwiftUI、Combine、async/await。
3. 避免 iOS 10+ API（`UICollectionViewDiffableDataSource`、新 Photos API 等）。
4. 局域网 HTTP：已开 `NSAllowsArbitraryLoads` / local networking。
5. 轮播 + Settings 必须在低内存 iPad 3 上可长时间运行；注意图片缓存与 fingerprint 防闪烁（现有 `RPHashObject` / URL cache 模式）。
6. 横竖屏都要能用。

---

## 10. 已知限制 / 下一步值得做的修复

- Build 只能在 `.179`；TeamC 上改完必须同步再编。
- `ios-deploy` 路径绑死在某次 DerivedData；换机需改脚本。
- `server/ipad/data` 媒体巨大，handoff 未收录；若要离线完整预览需另拷。
- GitHub / 新闻 modal、天气合并页在极窄竖屏下仍可再调间距。
- Factory 仍保留 `system` / `vps` / `weather-weekly`——若永久删除需清理死代码。
- `RPKioskRootVC.m.pre_capture_bak` 是备份，可忽略或删。
- `build_install.sh` 的 `ROOT` 写死为 `.179` 路径；若在别的目录构建需改。
- 截图 `extras/*.png` 多为改版前 roster（仍含 system/vps/weekly），仅作视觉参考。

---

## 11. 本包目录结构

```text
RemotePanel-handoff-20261030/
  README.md                 # 短索引 → README-FOR-AI.md
  README-FOR-AI.md           # 本文件
  ios/                      # 完整 Xcode 工程（来自 .179）
    RemotePanel.xcodeproj/
    RemotePanel/            # sources, fonts, AppIcon, Info.plist
    build_install.sh        # 密码已剥离
    PROVISIONING-NOTES.txt
    README.txt
  server/                   # RemotePanelih5Standalone 瘦身版
    ipad/ipad_server.py
    core/
    fonts/ WeatherIcons/
    run_ipad_server.command
    ipad/data/README-DATA.txt  # 说明巨量缓存未收录
  extras/
    remotepanel-appicon.tgz
    RemotePanel-project-map.md
    若干小截图
  RemotePanel-handoff-20261030.zip
```

---

## 12. 安全提醒

- **不要**把 fangzhiling / teamc / vault 密码写入 README、脚本默认值或 git。
- SSH 到 Build Mac：`fangzhiling@192.168.28.179`，凭证通过 operator。
- 本包 `build_install.sh` 要求环境变量 `SSHPASS`（或手动 unlock keychain）。

---

## 13. 快速自检清单

- [ ] `ios/RemotePanel/Info.plist` → `CFBundleVersion` == 3  
- [ ] 存在 `AppIcon.appiconset` 且含 png  
- [ ] `RPKioskRootVC` roster 含「天气+VPS」，不含启用的 system/weekly/vps  
- [ ] `curl` TeamC `:9121/api/h5/state` 返回 `weather` / `news.github_items` / `vps`  
- [ ] 在 `.179` 用 `build_install.sh` 能装到 UDID 设备  

