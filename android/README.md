# RemotePanel Android（P0）

家庭信息屏 Android 客户端，与 iOS kiosk 同仓库。目标机约 **1080×1920**，**竖屏为主、支持横屏**，**minSdk 28**（约 Android 9）。

## 功能（P0）

| 页 | 说明 |
|----|------|
| 问候海报 | 时段问候 + 时钟 |
| 天气 | Open-Meteo，城市可在设置里改 |
| 每日新闻 | RSS（默认可改） |
| 本地相册 | MediaStore，页内约 8s 轮播 |
| 自定义网页 ×N（≤8） | 全屏 WebView、无顶栏，按 dwell 轮换 |

壳层：dwell 进度条、左右边缘翻页、顶部长按进设置、Web 页隐藏 chrome、保持亮屏、沉浸式系统栏。

## 构建

需要 JDK 17+ 与 Android SDK（platform 34 + build-tools 34）。

```bash
cd android
# 若本机 SDK 不在默认位置：
echo "sdk.dir=$HOME/android-sdk" > local.properties

./gradlew :app:assembleDebug
# APK: app/build/outputs/apk/debug/app-debug.apk
```

安装到设备：

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## 设置

右上角齿轮，或左右边缘 / 顶部长按。可改：页面开关与停留秒数、全局 dwell 覆盖、天气城市、新闻 RSS、自定义网页 CRUD。

## 与 iOS / server

本 P0 **不依赖** 本机 `:9121` H5 state；天气与新闻直连公网。后续若要对齐 `RPLocalFeed`，可在设置里加 feed 基址并扩展 `FeedRepository`。

## 技术栈

Kotlin + View / ViewBinding，OkHttp，Glide，Coroutines，WebView。
