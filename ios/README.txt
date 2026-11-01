RemotePanel Kiosk 2.0 (build 9)
Path on build Mac: /Users/fangzhiling/Developer/RemotePanel
Bundle: com.glooby.RemotePanel
Deploy: iOS 9.3 armv7 iPad, all orientations
Pages: 20 built-in pages from RPLocalPageCatalog() in RPLocalFeed.m (local-video off by default), plus up to 8 custom web pages
Data: fetched on the device by RPLocalFeed (30 s poll, per-feed TTL, plist cache). The old :9121 API is no longer used.
Settings: top-right gear + long-press, or http://<iPad IP>:8090/setup
Photos: Favorites -> Camera Roll -> All Photos -> Moments; permission/empty on-screen hints
Media: image URL cache + payload fingerprint to avoid poll flicker
Build: ./build_install.sh (needs SSHPASS from the operator)
Sibling app: ZhangJieStocks/ (com.glooby.ZhangJieStocks), no build script yet
See ../README-FOR-AI.md for details.
