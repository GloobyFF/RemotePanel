from __future__ import annotations

import json
import os
import sys
from pathlib import Path

DEFAULT_CONFIG = {
    "host": "127.0.0.1",
    "port": 38000,
    "width": 600,
    "height": 800,
    "image_id": 0,
    "font_path": "",
    "title_font_size": 36,
    "body_font_size": 24,
    "footer_font_size": 18,
    "threshold": 128,
    "weather_city": "Beijing",
    "rss_url": "https://hnrss.org/frontpage",
    "image_url": "",
    "rotate_send": False,
    "auto_send_enabled": False,
    "auto_send_interval": 20,
    "selected_template_id": "",
    "startup_send_selected_template": True,
    "template_auto_enabled": False,
    "template_auto_interval": 30,
    "template_auto_rotate": False,
    "last_template_auto_hhmm": "",
    "bili_uid": "",
    "bili_cookie": "",
    "steam_proxy": "",
}


def app_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parents[1]


def resource_dir() -> Path:
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        return Path(sys._MEIPASS)
    return app_dir()


def config_path() -> Path:
    portable = app_dir() / "config.json"
    if portable.exists():
        return portable
    if os.name == "nt":
        base = Path(os.environ.get("APPDATA", str(Path.home()))) / "RemotePanelEInkStudio"
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support" / "RemotePanelEInkStudio"
    else:
        base = Path.home() / ".config" / "RemotePanelEInkStudio"
    base.mkdir(parents=True, exist_ok=True)
    return base / "config.json"


def load_config() -> dict:
    cfg = dict(DEFAULT_CONFIG)
    path = config_path()
    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                cfg.update(data)
        except Exception:
            pass
    return cfg


def save_config(cfg: dict) -> Path:
    path = config_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")
    return path
