"""Per-page upstream URLs and the shared fetch proxy, edited from the iPad settings."""

from __future__ import annotations

import json
import os
from pathlib import Path

SETTINGS_FILE = "source_settings.json"

# Matches the proxy already used by the game scrapers, so a fresh settings
# file keeps GitHub / Steam / Gamer520 reachable until the operator changes it.
DEFAULT_HTTP_PROXY = "socks5h://192.168.28.77:1080"

DEFAULT_SOURCES: dict[str, dict] = {
    "hello": {
        "label": "HelloGitHub",
        "url": "https://hellogithub.com/rss",
        "use_proxy": True,
        "kind": "rss",
    },
    "weather": {
        "label": "天气城市（城市名，不是 URL）",
        "url": "Shanghai",
        "use_proxy": False,
        "kind": "weather",
    },
    "daily-news": {
        "label": "每日新闻 RSS",
        "url": "https://www.chinanews.com.cn/rss/scroll-news.xml",
        "use_proxy": False,
        "kind": "rss",
    },
    "github-news": {
        "label": "GitHub 热门 / RSS",
        "url": "https://api.github.com/search/repositories",
        "use_proxy": True,
        "kind": "github",
    },
    "print": {
        "label": "打印机接口",
        "url": "",
        "use_proxy": False,
        "kind": "json",
    },
    "movie-now-showing": {
        "label": "电影列表",
        "url": "https://www.themoviedb.org/movie/now-playing",
        "use_proxy": True,
        "kind": "html",
    },
    "steam-new-releases": {
        "label": "Steam 新游",
        "url": "https://store.steampowered.com/api/featuredcategories?cc=cn&l=schinese",
        "use_proxy": True,
        "kind": "steam",
    },
    "steam-new-releases-2": {
        "label": "Steam 热销",
        "url": "https://store.steampowered.com/api/featuredcategories?cc=cn&l=schinese",
        "use_proxy": True,
        "kind": "steam",
    },
    "gamer520-pc-latest": {
        "label": "PC 游戏",
        "url": "https://www.gamer520.com/pcplay",
        "use_proxy": True,
        "kind": "html",
    },
    "gamer520-switch-latest": {
        "label": "Switch 游戏",
        "url": "https://www.gamer520.com/gameswitch",
        "use_proxy": True,
        "kind": "html",
    },
    "ps5-games-latest": {
        "label": "PS5 游戏",
        "url": "https://2468c.com/ps5game",
        "use_proxy": True,
        "kind": "html",
    },
    "x-news": {
        "label": "X / 社交 RSS",
        "url": "",
        "use_proxy": True,
        "kind": "rss",
    },
    "schedule": {
        "label": "日程 ICS 订阅",
        "url": "",
        "use_proxy": False,
        "kind": "ics",
    },
}


def settings_path() -> Path:
    return Path(__file__).resolve().parents[1] / "ipad" / "hermes_bridge" / SETTINGS_FILE


def _clean_proxy(value: str) -> str:
    value = str(value or "").strip()
    lower = value.lower()
    if lower.startswith(("http://", "https://", "socks5://", "socks5h://", "socks4://")):
        return value
    return ""


def _clean_source_url(source_id: str, value: str) -> str:
    value = str(value or "").strip()
    if not value:
        return ""
    if source_id == "weather":
        if value.lower().startswith(("http://", "https://", "javascript:", "file:")):
            return ""
        return value[:80]
    if value.lower().startswith("webcal://"):
        value = "https://" + value[len("webcal://"):]
    lower = value.lower()
    if lower.startswith(("http://", "https://")):
        return value
    return ""


def load_source_settings() -> dict:
    merged_sources = {key: dict(value) for key, value in DEFAULT_SOURCES.items()}
    proxy = DEFAULT_HTTP_PROXY
    path = settings_path()
    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            data = {}
        if isinstance(data, dict):
            cleaned = _clean_proxy(str(data.get("http_proxy") or ""))
            if "http_proxy" in data:
                proxy = cleaned
            sources = data.get("sources") if isinstance(data.get("sources"), dict) else {}
            for key, default in merged_sources.items():
                raw = sources.get(key)
                if not isinstance(raw, dict):
                    continue
                if "url" in raw:
                    default["url"] = _clean_source_url(key, raw.get("url"))
                if "use_proxy" in raw:
                    default["use_proxy"] = bool(raw.get("use_proxy"))
    return {"http_proxy": proxy, "sources": merged_sources}


def save_source_settings(payload: dict) -> dict:
    current = load_source_settings()
    if not isinstance(payload, dict):
        payload = {}
    if "http_proxy" in payload:
        current["http_proxy"] = _clean_proxy(payload.get("http_proxy"))
    incoming = payload.get("sources") if isinstance(payload.get("sources"), dict) else {}
    for key, default in current["sources"].items():
        raw = incoming.get(key)
        if not isinstance(raw, dict):
            continue
        if "url" in raw:
            default["url"] = _clean_source_url(key, raw.get("url"))
        if "use_proxy" in raw:
            default["use_proxy"] = bool(raw.get("use_proxy"))
    path = settings_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(current, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(tmp, path)
    return current


def source_entry(source_id: str, settings: dict | None = None) -> dict:
    settings = settings or load_source_settings()
    sources = settings.get("sources") if isinstance(settings.get("sources"), dict) else {}
    entry = sources.get(source_id)
    if isinstance(entry, dict):
        return entry
    return dict(DEFAULT_SOURCES.get(source_id) or {})


def source_url(source_id: str, settings: dict | None = None) -> str:
    return str(source_entry(source_id, settings).get("url") or "").strip()


def effective_proxy(source_id: str, settings: dict | None = None) -> str:
    settings = settings or load_source_settings()
    entry = source_entry(source_id, settings)
    if not entry.get("use_proxy"):
        return ""
    return str(settings.get("http_proxy") or "").strip()


def weather_city(settings: dict | None = None) -> str:
    city = source_url("weather", settings).strip()
    return city or "Shanghai"


def looks_like_feed(url: str) -> bool:
    lowered = str(url or "").lower()
    return any(token in lowered for token in ("/rss", ".rss", "/feed", "atom", ".xml"))


def find_rss_payload(content_cache: dict, url: str) -> dict:
    url = str(url or "").strip()
    if not url or not isinstance(content_cache, dict):
        return {}
    best: dict = {}
    prefix = f"rss::{url}::"
    for key, payload in content_cache.items():
        if not isinstance(payload, dict):
            continue
        same = str(payload.get("rss_url") or "").strip() == url or str(key).startswith(prefix)
        if not same:
            continue
        if not (payload.get("items") or payload.get("lines")):
            continue
        if len(payload.get("items") or []) >= len(best.get("items") or []):
            best = payload
    return best
