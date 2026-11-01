# RemotePanel Android

家庭信息屏的 Android 客户端，与 iOS kiosk 同仓库。按 **1080×1920 竖屏**设计（manifest 锁定竖屏），**minSdk 28**（Android 9）。不依赖 `:9121` 服务，所有数据由设备直接从各数据源拉取。

## 页面

| pageId | 标题 | 内容 | 数据源 |
|--------|------|------|--------|
| `hello` | 问候海报 | 大时钟、当前天气、问候语、5 条头条、3 个指数 | 其他页的数据；问候语用 AI 接口（填了 key 才调用），否则按天气生成提醒 |
| `schedule` | 日程与提醒 | 今天起 8 天的日程，包括重复事件 | 本机系统日历（`CalendarContract.Instances`） |
| `weather` | 天气+VPS | 实况、6 项指标、逐 2 小时、7 天温度条；填了 token 时显示 VPS 用量 | Open-Meteo |
| `daily-news` | 每日新闻 | 头条大卡片 + 7 条，带发布时间 | 中新网 RSS |
| `github-news` | AI·热门项目 | 近 30 天新建的 AI 项目，显示 Star、语言、topics | GitHub search API |
| `x-news` | X · 动态 | 美国热门前 20 名 + 讨论最多 6 个 | getdaytrends.com |
| `xiaohongshu-hot` | 小红书热门 | 头条大图、6 宫格、6 条文字榜 | tophub.today；配图从 image.so.com 按标题搜 |
| `bilibili-hot` | 哔哩哔哩热门 | 缩略图、时长、UP 主、分区、播放/点赞/弹幕 | B 站 popular API |
| `stocks-cn` | 国内股票 | 上证、深证、创业板三大指数 + 自选股 | 东方财富 push2，连不上时换腾讯 qt.gtimg.cn |
| `crypto` | 比特币 | 现价、涨跌（自北京时间 0 点）、24h 高低和成交额 | OKX 单币 ticker |
| `print` | 打印机 | 进度、剩余时间、层数、温度、AMS 料仓 | 局域网打印机 JSON（默认 `192.168.28.126:8088`） |
| `movie-now-showing` | 最近上映 | 海报、评分或想看人数、主演、今日排片 | 猫眼 |
| `steam-new-releases` / `-2` | Steam 新游 / 热销 | 2×4 封面，价格和折扣 | Steam featuredcategories |
| `gamer520-pc-latest` / `gamer520-switch-latest` | PC / Switch 上新 | 2×4 封面，发布时间、版本 | gamer520 列表页 |
| `ps5-games-latest` | PS5 上新 | 3×3 竖版封面 | 2468c 列表页 |
| `person-photo-local-1` / `-2` | 照片（默认关闭） | 全屏随机照片，8 秒换一张 | SMB 或 HTTP 目录 |
| `local-video` | 视频（默认关闭） | 随机播放一段视频，播完翻页 | SMB 目录 |
| `web-*` | 自定义网页（最多 8 个） | 全屏 WebView，不显示顶栏 | 设置里填的网址 |

## 界面

- 所有尺寸按 1080 宽的设计稿写，由 `ui/Ui.kt` 的 `Ui.px()` 换算到实际屏幕。最小字号 38px（约 13sp），正文 46px，标题 54–68px，大数字 104–200px，目标是 2–3 米外能看清。
- 深色背景，每天换一个强调色。A 股和加密货币都是红涨绿跌。
- 顶栏 132px：页面标题、星期 / 页码 / 倒计时、状态点、时钟、设置按钮。顶栏下面是 8px 的停留进度条。
- 状态点：绿色表示这页数据是新的；黄色表示正在读取，或刷新失败、显示的是旧数据；红色表示读取失败且没有数据可显示。
- 每页底部写数据来源和更新时间。刷新失败时这行变黄，并注明显示的是旧数据。
- 点屏幕左右两边 18% 的区域翻页。长按顶栏或点齿轮进入设置。
- 每 4 分钟把整个画面随机挪动几个像素，减少长期显示造成的烧屏。

## 数据与图片

- `data/FeedCache.kt`：每个数据源单独缓存，按各自的刷新间隔更新。失败后等 3 分钟再重试，期间继续显示上一次成功的数据。
- `data/FeedRepository.kt`：所有数据源并行请求，每到一个就刷新当前页，不用等最慢的那个。上一轮没结束时不会开始新一轮。
- `net/ImageFetch.kt`：Glide 改走 OkHttp。请求带浏览器 UA，B 站和 360 图片带 Referer；直连失败时走设置里的代理重试一次。
- `ui/Img.kt`：
  - 按显示尺寸向 CDN 要缩略图（B 站 `@WxH`，猫眼 `imageMogr2`），并解码成 RGB_565。
  - 过滤站点 logo 和懒加载占位图。
  - 加载中显示灰色色块；真正加载失败时，显示带标题首字和来源名的渐变色块。
  - 页面离开屏幕时释放图片，下一页的图片提前 8 秒预载。
- `net/HttpClient.kt`：解析域名后优先用 IPv4。在 IPv6 不通的网络里，直接走 IPv6 的连接要等 10 秒超时，才会换 IPv4。

## 构建

需要 JDK 17+ 和 Android SDK（platform 34、build-tools 34）。

```bash
cd android
# SDK 不在默认位置时：
echo "sdk.dir=$HOME/android-sdk" > local.properties

./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

在模拟器上按目标尺寸预览：`adb shell wm size 1080x1920 && adb shell wm density 480`。

## 设置

右上角齿轮，或长按顶栏、左右边缘。可以改：页面开关和停留秒数、全局停留时间、天气城市、新闻 RSS、各页数据源、代理、AI key、VPS token、照片和视频目录、自定义网页。从设置返回后，所有数据源会立即重新拉取。

## 代码结构

| 目录 / 文件 | 作用 |
|------|------|
| `ui/KioskActivity.kt` | 外壳：顶栏、轮播、停留计时、30 秒轮询、预载、防烧屏 |
| `ui/Ui.kt`、`ui/Fmt.kt`、`ui/Img.kt` | 设计尺寸与字号、数字和时间格式化、图片加载 |
| `pages/BoardPage.kt` | 所有原生数据页的容器：数据没变就不重建，并显示底部来源行 |
| `pages/HomePages.kt` | 问候、天气、日程、打印机 |
| `pages/NewsPages.kt` | 新闻、GitHub、X、小红书、B 站 |
| `pages/MarketPages.kt` | 股票、加密货币 |
| `pages/MediaPages.kt` | 电影、Steam、PC / Switch / PS5 |
| `pages/PhotoPage.kt`、`VideoPage.kt`、`WebPage.kt` | 照片、视频、自定义网页 |
| `data/Feeds.kt`、`data/MoreFeeds.kt` | 各数据源的请求与解析 |
| `data/Models.kt` | 页面用的数据结构 |
