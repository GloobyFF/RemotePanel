RemotePanel Kiosk v2.2
Path: /Users/fangzhiling/Developer/RemotePanel
Bundle: com.glooby.RemotePanel
Deploy: iOS 9.3 armv7 iPad, all orientations
Roster: 16 native pages (printer merged to 1 dense page; WebView private-channels removed)
Settings: top-right gear + long-press; per-page enable/dwell; album; base URL (NSUserDefaults)
Photos: Favorites → Camera Roll → All Photos → Moments; permission/empty on-screen hints
Media: image URL cache + payload fingerprint to avoid 30s poll flicker
API: http://192.168.28.12:9121/api/h5/state?rotate=1
Build: ./build_install.sh
