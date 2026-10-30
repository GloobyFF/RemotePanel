# RemotePanel handoff package (2026-10-30)

详细交接说明请读：**[README-FOR-AI.md](./README-FOR-AI.md)**（给后续 AI / 工程师的完整上下文）。

## Layout

| Path | Contents |
|------|----------|
| `ios/` | Native ObjC Xcode project (canonical build tree from `.179`) |
| `android/` | Kotlin kiosk app (P0：问候/天气/新闻/相册/Web×N)，见 `android/README.md` |
| `server/` | Slim copy of `RemotePanelih5Standalone` (port 9121 API) |
| `extras/` | Optional appicon tarball, project map, small screenshots |
| `RemotePanel-handoff-20261030.zip` | Archive of this whole folder (created after packaging) |

**Do not** put passwords in edits to the README. Build-Mac SSH / keychain unlock: ask the operator.
