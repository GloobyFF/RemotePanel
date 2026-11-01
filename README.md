# RemotePanel

家庭资讯屏：iPad 3（iOS 9.3.5）和 Android 上的全屏轮播看板，外加一个 A 股持仓小应用。

完整交接说明见 **[README-FOR-AI.md](./README-FOR-AI.md)**。

## Layout

| Path | Contents |
|------|----------|
| `ios/RemotePanel/` | iPad 资讯屏主程序（ObjC，iOS 9.3 / armv7）。数据由设备直接拉取，不依赖服务端 |
| `ios/ZhangJieStocks/` | 「张洁股票」A 股持仓轮播（ObjC，iOS 9.3） |
| `ios/build_install.sh` | 在 Build Mac `.179` 上编译并安装 RemotePanel |
| `android/` | Android 资讯屏（Kotlin），见 [android/README.md](./android/README.md) |
| `server/` | 旧 `:9121` H5/API 服务的瘦身副本，仅作参考 |
| `extras/` | 图标包、项目对照表、改版前截图 |

**Do not** put passwords, tokens, or API keys in this repo. Build-Mac SSH / keychain unlock: ask the operator.
