# RemotePanel 交接说明（给后续 AI / 工程师）

更新日期：**2026-11-01**（Asia/Shanghai），对应提交 `07d41aa` 之后的代码。

先读这几条：

- iOS 端已经**不再依赖** TeamC 上的 `:9121` 服务。所有数据由设备上的 `RPLocalFeed` 直接去各个公网/局域网源拉取（见第 4 节）。
- 页面清单的唯一来源是 `ios/RemotePanel/RPLocalFeed.m` 里的 `RPLocalPageCatalog()`。文档里的表只是快照，有出入时以代码为准。
- iOS 只能在 Build Mac `.179`（High Sierra + Xcode 10.1）上编译。Android 在任何装了 JDK 17+ 和 Android SDK 34 的机器上都能编。
- 不要把任何密码、token、API key 写进仓库、README 或脚本默认值。

---

## 1. 仓库里有什么

| 路径 | 内容 |
|------|------|
| `ios/RemotePanel/` + `ios/RemotePanel.xcodeproj` | 主程序 RemotePanel，iPad 全屏轮播资讯屏（ObjC） |
| `ios/ZhangJieStocks/` | 独立小应用「张洁股票」，A 股持仓轮播（ObjC，见第 8 节） |
| `ios/build_install.sh` | 在 `.179` 上编译并装机 RemotePanel |
| `android/` | Android 版资讯屏（Kotlin，见 `android/README.md`） |
| `server/` | 旧 H5/API 服务 `RemotePanelih5Standalone` 的瘦身副本，现在只作参考（见第 10 节） |
| `extras/` | 图标包、旧的项目对照表、改版前的截图 |

不进 git 的本地文件（`.gitignore`）：根目录的 `RemotePanel.ipa`、`ZhangJieStocks.ipa`，以及 `shots/`。`shots/` 里是调试截图和在 `.179` 上用过的签名、钥匙串解锁、Apple 登录自动化脚本，**不要提交**。

---

## 2. 设备与签名

| 项 | 值 |
|----|----|
| 设备 | Easton iPad 3，iOS **9.3.5**，armv7 |
| UDID | `1b9b4d6959e9d533837d946d94105049dfd794a8` |
| Team ID | `FLFYQXCCZM` |
| RemotePanel | `com.glooby.RemotePanel`，版本 `2.0`，build **`9`** |
| ZhangJieStocks | `com.glooby.ZhangJieStocks`，显示名「张洁股票」，版本 `1.0`，build `2`（未编译验证） |
| Android | `com.glooby.remotepanel`，versionName `2.0.0`，versionCode `2` |

签名摘要见 `ios/PROVISIONING-NOTES.txt`（不含密码）。

---

## 3. 机器与网络

| 角色 | 地址 | 说明 |
|------|------|------|
| Build Mac | `192.168.28.179`，用户 `fangzhiling` | Xcode 10.1。规范工程树：`/Users/fangzhiling/Developer/RemotePanel` |
| TeamC | `192.168.28.12`，用户 `teamc` | 旧 `:9121` 服务所在机器 |
| SOCKS 代理 | `socks5h://192.168.28.77:1080` | iOS 访问 GitHub、Steam、X 等源时默认走它 |
| 打印机接口 | `http://192.168.28.126:8088/api/printers` | 打印机页数据源 |

SSH 到 Build Mac 的凭证找 operator。

---

## 4. RemotePanel（iOS）架构

硬约束：iOS 9.3.5、armv7、Xcode 10.1 工具链、**只用 Objective-C**。不要引入 Swift、SwiftUI，也不要调用 iOS 10+ 的 API。设备只有约 1 GB 内存，图片解码和缓存都要克制。

数据流：

1. `RPKioskRootVC` 每 30 秒调用一次 `-pollNow`，它会调 `[[RPLocalFeed sharedFeed] refreshWithCompletion:]`。
2. `RPLocalFeed` 在后台队列里逐个检查各数据源的缓存。只给过期的源排任务，任务**串行**执行。走代理的请求失败后会自动直连重试一次，单次请求超时 25 秒（POST 是 45 秒）。
3. 每完成一个源就发 `RPFeedProgressNotification`，界面随之增量刷新。全部完成后由 `-assemble` 拼出状态字典，交给当前页的 `applyState:baseURL:`。
4. 缓存存在 `Caches/RemotePanelLocalFeed.plist`。冷启动时先显示旧缓存，再后台刷新。

`RPAPIClient`（`:9121/api/h5/state`）和设置键 `RemotePanel.baseURL` 还留在代码里，但轮询已经不走它们了。

`RPLocalFeed` 初始化时还会在 **8090 端口**起一个局域网 HTTP 服务，见第 6 节。

---

## 5. 页面清单

在内置页之外，还可以添加最多 8 个自定义网页（`pageId` 以 `web-` 开头，用 WKWebView 全屏显示）。

| pageId | 标题 | 默认停留(秒) | 默认数据源 | 缓存键 / 默认刷新间隔 | 默认走代理 |
|--------|------|------|------------|----------------|----|
| `hello` | 问候海报 | 60 | AI 接口 `https://apiclaude.cc`，模型 `gpt-6-astra`，key 需在设置里填 | `hello`，每个时段（早/中/晚）生成一次 | 否 |
| `schedule` | 日程与提醒 | 60 | ICS 订阅地址，默认空，留空就不拉 | `schedule` / 24h | 否 |
| `weather` | 天气+VPS | 70 | Open-Meteo，城市默认 `Shanghai`；VPS 用量来自 `https://igobeat.com/api/traffic`（token 在设置里填） | `weather` / 6h，`vps` / 24h | 否 |
| `daily-news` | 每日新闻 | 70 | 中新网滚动 RSS | `daily` / 12h | 否 |
| `github-news` | AI·热门项目 | 70 | GitHub search API | `github` / 24h | 是 |
| `x-news` | X · 动态 | 60 | getdaytrends 美国区，译成中文 | `x` / 2h | 是 |
| `xiaohongshu-hot` | 小红书热门 | 60 | tophub 小红书榜 | `xhs` / 2h | 是 |
| `bilibili-hot` | 哔哩哔哩热门 | 60 | B 站 popular API | `bili` / 2h | 否 |
| `stocks-cn` | 国内股票 | 70 | 东方财富 `push2`，默认 `600519,300750,600036,601318,002594` | `stocks` / 30min | 否 |
| `crypto` | 比特币 | 70 | OKX 现货，默认 `btc,eth,sol,bnb,xrp` | `crypto` / 30min | 是 |
| `person-photo-local-1` | 本地相册 A | 60 | 设备相册 | 无 | 无 |
| `print` | 打印机 | 75 | `http://192.168.28.126:8088/api/printers` | `print` / 10min | 否 |
| `movie-now-showing` | 最近上映 | 35 | 猫眼 `movieOnInfoList` | `movies` / 24h | 否 |
| `steam-new-releases` | Steam 新游 | 60 | Steam `featuredcategories` | `steam` / 24h | 是 |
| `steam-new-releases-2` | Steam 热销 | 60 | 和上一页共用同一份数据 | `steam` | 是 |
| `gamer520-pc-latest` | PC 游戏上新 | 60 | gamer520 `/pcplay` | `pc` / 24h | 是 |
| `person-photo-local-2` | 本地相册 B | 60 | 设备相册 | 无 | 无 |
| `gamer520-switch-latest` | Switch 上新 | 60 | gamer520 `/gameswitch` | `switch` / 24h | 是 |
| `ps5-games-latest` | PS5 上新 | 60 | 2468c.com `/ps5game` | `ps5` / 24h | 是 |
| `local-video` | 视频（**默认关闭**） | 12 | 相册视频、`Documents/Videos` 下的文件或 HTTP 地址 | 无 | 无 |

另外有一个不占页面的走马灯（ticker）：设置里填了 ticker 地址就每 10 分钟拉一次，也可以通过 `GET /tell` 直接推送（第 6 节）。

刷新间隔可以在设置里按缓存键单独改，可选 10 分钟到 24 小时。

已经退役的独立页 `system`、`weather-weekly`、`vps`：它们不在页面清单里，启动时还会被强制设为关闭。`RPPageFactory` 里仍保留了它们的实现。

**新增一个内置页**要改这些地方：`RPLocalFeed.m` 里的 `RPLocalPageCatalog()`、`RPLocalSourceDefaults()`、`RPLocalFeedKeyForPage()`，`-refreshWithCompletion:` 里的任务列表，`-assemble`，以及 `RPPages.m` 里的 `RPPageFactory +pageForId:title:`。

---

## 6. 设置

打开设置有三种方式：右上角齿轮、顶部长按、局域网内用浏览器打开 `http://<iPad IP>:8090/setup`。iPad 的 IP 会写在 8090 首页的日志里。

### NSUserDefaults 键

| 键 | 含义 |
|----|------|
| `RemotePanel.page.enabled.<pageId>` | 页面开关。没设过时用页面清单的默认值 |
| `RemotePanel.page.dwell.<pageId>` | 单页停留秒数 |
| `RemotePanel.dwellOverride` | 全局停留秒数，`0` 表示用各页自己的 |
| `RemotePanel.source.url.<pageId>` | 覆盖默认数据源（地址、城市、股票代码、币种等） |
| `RemotePanel.source.proxy.<pageId>` | 这个源是否走代理 |
| `RemotePanel.httpProxy` | 代理地址，空的时候用 `socks5h://192.168.28.77:1080` |
| `RemotePanel.refresh.<缓存键>` | 刷新间隔（秒，至少 60） |
| `RemotePanel.vpsURL` / `RemotePanel.vpsToken` / `RemotePanel.vps.useProxy` | VPS 用量接口 |
| `RemotePanel.hello.key` / `RemotePanel.hello.model` | 问候页的 AI key 和模型 |
| `RemotePanel.tickerURL` / `RemotePanel.ticker.useProxy` | 走马灯 |
| `RemotePanel.webPages` | 自定义网页数组，每项含 `id`/`title`/`url`/`enabled`/`dwell` |
| `RemotePanel.albumLocalId`、`RemotePanel.video.*` | 相册和视频来源 |
| `RemotePanel.baseURL` | 旧 `:9121` 地址，已不再使用 |

### 8090 局域网服务

这个服务在单独的线程里一次处理一个请求，**没有任何鉴权**，只能放在可信的局域网里用。

| 请求 | 作用 |
|------|------|
| `GET /` | 最近 80 条拉取日志 |
| `GET /setup` | 网页版设置页 |
| `GET /setup.json`、`POST /setup` | 读写全部设置（JSON） |
| `POST /video-chunk?name=&seq=&last=` | 分片上传视频到 `Documents/Videos` |
| `GET /tell?t=文字` | 推一条走马灯消息（最长 120 字） |
| `GET /pages[?i=N]` | 列出页面，带 `i` 时跳到第 N 页 |
| `GET /shot[?i=N]` | 截取当前页（或第 N 页）的 PNG |

设置页的 HTML 源文件是 `ios/RemotePanel/setup_page.html`。改完后运行 `gen_setup.py` 生成 `setup_html.inc`，再手动把内容贴进 `RPLocalFeed.m` 的 `RPSetupHTML()`。注意脚本里的路径写死成了 `D:\Myproject\RemotePanel-handoff\...`。

---

## 7. 源文件地图（`ios/RemotePanel/`）

| 文件 | 作用 |
|------|------|
| `RPKioskRootVC.m` | 根 VC：页面列表、轮播、停留计时、30 秒轮询、原生设置界面、弹窗时暂停轮播 |
| `RPPages.m` / `.h` | 各页面 VC 和 `RPPageFactory` |
| `RPLocalFeed.m` / `.h` | 页面清单、各数据源的拉取和解析、缓存、8090 服务 |
| `RPNet.m` | 同步 HTTP GET/POST，支持 SOCKS/HTTP 代理 |
| `RPTheme.m` | 颜色、像素字体、`contentScale`（2.0）、卡片配色 |
| `RPPhotoSource.m` | 本地相册，按 Favorites → Camera Roll → All Photos → Moments 的顺序找 |
| `RPAPIClient.m` | 旧的 `:9121` 客户端，现在没有调用方 |
| `setup_page.html`、`gen_setup.py` | 8090 设置页的源文件和生成脚本 |
| `Info.plist` | 版本、字体列表、ATS（允许局域网 HTTP）、屏幕方向、相册权限文案 |
| `fonts/` | Fusion Pixel、Ark Pixel、Zpix、WeatherIcons |

---

## 8. ZhangJieStocks（张洁股票）

独立的 Xcode 工程，位于 `ios/ZhangJieStocks/`，约束和 RemotePanel 相同（iOS 9.3、armv7、iPad、ObjC）。

- 第一页是持仓汇总，之后每只股票一页，自动轮播。两种页面的停留时间分别存在 `ZJ.dwellSummary` 和 `ZJ.dwellStock`。
- 行情来自东方财富 `push2.eastmoney.com/api/qt/ulist.np/get`。只在 A 股交易时段（工作日 9:30–11:30、13:00–15:00，北京时间）每 60 秒拉一次。
- 持仓（代码、名称、买入价、股数）存在 NSUserDefaults 的 `ZJ.holdings`，最后一次行情存在 `ZJ.quotes`。第一次启动时会预置 5 只示例股票。
- 设置：点底部「设置」按钮或长按，进入 `ZJSettingsVC`。
- 仓库里**没有**它的编译安装脚本。可以照 `ios/build_install.sh` 改一份：改工程名、scheme、bundle ID，并给 `com.glooby.ZhangJieStocks` 配一个 provisioning profile。

---

## 9. 编译与安装

### RemotePanel（只能在 `.179` 上编）

```bash
# 先把本仓库的 ios/ 用 rsync 同步到 .179 的 /Users/fangzhiling/Developer/RemotePanel/
cd /Users/fangzhiling/Developer/RemotePanel
export SSHPASS='…找 operator 要…'   # 只用于解锁钥匙串，不要写进文件
./build_install.sh
```

`build_install.sh` 的要点：

- 编译参数是 `ARCHS=armv7`、`IPHONEOS_DEPLOYMENT_TARGET=9.3`、`TARGETED_DEVICE_FAMILY=2`，手动签名。
- 碰到 `errSecInternalComponent` 会重新解锁钥匙串，再编一次。
- 装机先走 USB，失败了再走 Wi-Fi。
- `ROOT` 和 `ios-deploy` 的路径都写死了（后者在某次编译的 DerivedData 里）。换机器或换目录要改脚本。

### Android

```bash
cd android
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

细节见 `android/README.md`。

Android 版在 2026-11-01 按 1080×1920 竖屏整体重做：

- 所有尺寸按 1080 宽的设计稿写（`ui/Ui.kt`），最小字号 38px。
- 数据源并行拉取，每个源单独缓存；失败后等 3 分钟再试，期间继续显示旧数据（`data/FeedCache.kt`）。
- 图片统一走 OkHttp，按需带 Referer 并支持代理重试；失败时显示有标题首字的色块，不再是空白或默认图。
- 页面清单和 iOS 相同（manifest 锁定竖屏），各页的内容和数据源见 `android/README.md`。

---

## 10. 服务端（`server/`，仅作参考）

`server/` 是 `RemotePanelih5Standalone` 的瘦身副本，不含约 5 GB 的 `ipad/data` 媒体缓存，也不含 `.venv`。iOS 和 Android 都不依赖它了。TeamC 上的原服务可能还在跑：

```bash
cd /Users/teamc/Documents/RemotePanelih5Standalone
python3 ipad/ipad_server.py --host 0.0.0.0 --port 9121
# H5 预览 http://192.168.28.12:9121/h5-lite，控制台 /ipad/control
```

当时 `/api/h5/state` 的顶层键有：`weather`、`vps`、`news`（含 `daily_items`、`github_items`）、`print`、`movies`、`steam`、`gamer520`、`switch_games`、`ps5_games`、`ops` 等。主程序在 `server/ipad/ipad_server.py`（4425 行），共享逻辑在 `server/core/`。

---

## 11. 已知问题 / 待办

- 8090 服务没有鉴权，同一局域网里的任何设备都能改设置、上传视频、截屏。
- `RPAPIClient`、`RemotePanel.baseURL` 和 `kDefaultBaseURL` 已经没用了，可以删掉。
- `RPPageFactory` 里还有 `system`、`vps`、`weather-weekly` 的实现。如果确定不再启用，可以删掉这部分死代码。
- 设置页 HTML 要手动生成再粘贴，容易漏。`gen_setup.py` 的路径也是写死的。
- `ios/build_install.sh` 的 `ROOT` 和 `ios-deploy` 路径写死；ZhangJieStocks 还没有编译脚本。
- 仓库里跟踪了 `server/**/__pycache__/*.pyc`，还有两个备份文件 `server/ipad/ipad_server.py.bak_rp_135831` 和 `ios/RemotePanel/RPKioskRootVC.m.pre_capture_bak`。
- `extras/*.png` 是改版前的截图，只能作视觉参考。

### build 7 的 iOS 修复（2026-11-01，尚未编译和上机）

代码审查发现的问题已经在 RemotePanel build 7 和 ZhangJieStocks build 2 里改了。这些改动是在 Windows 上写的，**还没有在 `.179` 上编译过，也没有装到 iPad 上验证**。另有一位审查者逐行读过一遍，没有发现编译错误。第一次在 `.179` 上编译时请留意报错。

需要上机确认的地方：

- 自定义网页页能正常显示（以前会被平移出屏幕，变成空白）。
- 打印机页、天气页不再空白，GitHub 页不再出现 `<null>`。
- 重启 App 后，各页直接显示上次的缓存，不用全部重新拉。
- 用浏览器给 8090 上传一段视频，传完能正常播放。
- 拔掉网线或让某个源连不上，过几分钟页面仍会更新其他源，日志里能看到退避。

改动内容：

- **网络**（`RPNet.m`）：
  - 连接后设 `SO_RCVTIMEO`/`SO_SNDTIMEO`，每个请求再加一个总时长上限；
  - 响应完整后才解析，读取循环里加了 `@autoreleasepool`。
- **刷新**（`RPLocalFeed.m`）：
  - 超过 10 分钟没结束的一轮刷新会被放弃，重新开始，并用代号（generation）防止新旧两轮同时跑；
  - 失败的源按 5、10、20、40、60 分钟逐步延后重试；
  - 本版本写入的缓存在刷新间隔内直接算新鲜，不再走旧的形状检查；
  - 只有数据变了才写盘，写盘失败会记日志。
- **NSNull**：`store:` 里用 `RPPlistSafe` 递归把 NSNull 换成 `@""`，GitHub 字段也改用 `RPString()`。
- **设置**：
  - 在 iPad 上保存设置后调 `invalidateForSettingsChange`，让缓存失效；
  - 问候语记录生成它的接口、模型和 key（只记 key 的长度和后四位），这三样任何一个变了，下一轮就重新生成。
- **8090 服务**：
  - 每个请求放进单独的 `@autoreleasepool`；
  - 发送统一用 `sendAll`；
  - 读请求体有 30 秒总时限，收不全或超过 200 KB 的直接拒绝。
- **页面**（`RPPages.m`）：
  - 自定义网页页覆盖了 `parkMotionOffscreen`；
  - `purgeDisplayedImages` 改用 C 函数，不再有 block 自引用；
  - B 站图片预取改读 `news.bili_items`；
  - 日程页等待权限回调时不再隐藏内容；
  - 格式化器只创建一次。
- **日历**：先排序再截取 18 条；UTC 时间换成本地时间。
- **相册**（`RPPhotoSource.m`）：相册枚举改在后台队列，完成回调回到主线程。
- **顶栏**（`RPKioskRootVC.m`）：
  - 进度条只改约束的 `constant`；
  - 状态标签 FAIL 在下一轮全部成功后恢复成 LIVE。
- **ZhangJieStocks**：
  - 共用一个 `NSURLSession`；
  - 新增 `+shouldFetch`，覆盖 9:15–11:35 和 12:55–15:05，能拿到收盘价；
  - 收盘后如果拉取失败，每 5 分钟重试一次。

还没处理：

- 8090 服务没有鉴权；
- SSL 握手本身还没有总时长上限，只靠每次读取 10 秒以上的超时兜底。

---

## 12. 版本记录（RemotePanel iOS）

| build | 内容 |
|-------|------|
| 4 | 内存优化（解码上限、NSCache、离页释放、相册 FastFormat）；有图页在飞入前预加载；日历乱码修复（系统字体 + ICS QP/GBK 解码） |
| 5 | 自定义全屏网页（最多 8 个）。轮到时隐藏顶栏和进度条，点左右边缘翻页，长按顶部开设置 |
| 6 | 行情卡改成三栏，中间放大现价；页面布局更紧凑 |
| 7 | 网络读写超时和刷新看门狗；NSNull 清理（磁盘缓存终于能保存）；失败退避；修复自定义网页空白、视频上传截断、内存泄漏、日历排序和 UTC 时间；相册枚举移到后台。2026-11-01 已在 `.179` 编译并装机 |
| 8 | 翻页动画快一倍（飞入 1.15 秒、飞出 1.05 秒）；相册改用 HighQualityFormat，按屏幕像素（最大 2048）请求，不再是模糊缩略图；小红书直接读 tophub，16 条，大图 + 宫格 + 带热度条的排行榜；Steam、PC、Switch、PS5、电影封面按原始比例排版（`RPAspectGrid`），不再裁切；封面按卡片像素解码 |
| 9 | 相册随机播放：读整个相册（上限 5000），按"种子 + 照片 ID 的哈希"排序，一轮放完才重复；进度存在 `RemotePanel.photo.cycle.<slot>`，翻页和重启后接着放；A 页全部竖拍、B 页全部横拍 |

---

## 13. 自检清单

- [ ] `ios/RemotePanel/Info.plist` 的 `CFBundleVersion` 和第 2 节一致
- [ ] 第 5 节的表和 `RPLocalPageCatalog()` 一致
- [ ] 在 `.179` 上运行 `build_install.sh`，最后输出 `INSTALL_OK`
- [ ] 打开 `http://<iPad IP>:8090/`，日志里各个源都显示「成功」或「跳过」
- [ ] `cd android && ./gradlew :app:assembleDebug` 能通过
- [ ] `git diff` 里没有密码、token 或 key



