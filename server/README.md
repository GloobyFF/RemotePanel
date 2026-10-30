# RemotePanel iPad Standalone

This folder is a standalone iPad preview package extracted from `RemotePanelEInkStudio`.

## Folder

- `ipad/` — iPad-specific server, project file, bridge cache, assets, preview data
- `core/` — shared rendering/model/runtime code required by the iPad server
- `fonts/` — font resources required by the renderer
- `WeatherIcons/` — weather icon font used by weather pages

## Run

From Terminal:

```bash
cd /Users/teamc/Documents/RemotePanelih5Standalone
python3 ipad/ipad_server.py --host 0.0.0.0 --port 9121
```

Or double-click:

- `run_ipad_server.command`

Then open:

- `http://127.0.0.1:9121/ipad`
- or your LAN address, for example `http://192.168.28.12:9121/ipad`

## Main file being edited

- `ipad/ipad_server.py`

## Notes

- This standalone copy does not depend on the original repo path.
- If you want fresh content caches, keep using `ipad/refresh_ipad_cache.py` inside this standalone folder.
- If another AI takes over, point it at this folder root.
