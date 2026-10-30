from __future__ import annotations

import json
import os
import sys
import argparse
from datetime import datetime, timezone
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parent.parent
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

from core.bilibili import fetch_bilibili_status
from core.config import DEFAULT_CONFIG, config_path
from core.gamer520 import fetch_gamer520_pcplay, fetch_gamer520_switch
from core.github_ai import fetch_github_ai_trending
from core.hermes_bridge import HermesBridge
from core.movies import fetch_now_playing_movies
from core.news import fetch_rss_items, fetch_rss_titles
from core.private_channels import fetch_private_channel_summary
from core.ps5games import fetch_ps5_games
from core.steam import fetch_steam_new_and_trending, fetch_steam_new_releases, fetch_steam_top_sellers
from core.traffic import fetch_traffic, traffic_lines
from core.utils import download_image
from core.http_fetch import fetch_bytes
from core.ics_calendar import sync_ics_file
from core.source_settings import (
    effective_proxy,
    load_source_settings,
    looks_like_feed,
    source_url,
    weather_city,
)
from core.weather import fetch_weather_payload, fetch_weekly_weather_payload
from studio.app import (
    load_latest_hermes_session_bridge_payload,
    load_latest_hermes_work_status_payload,
    normalize_cookie_string,
)

IPAD_ROOT = Path(__file__).resolve().parent
PROJECT_PATH = IPAD_ROOT / "ipad.project.json"
BRIDGE_PATH = IPAD_ROOT / "hermes_bridge"
STATE_PATH = IPAD_ROOT / "ipad_state.json"
POSTER_DIR = IPAD_ROOT / "data" / "movie_posters"
MOVIE_BACKDROP_DIR = IPAD_ROOT / "data" / "movie_backdrops"
STEAM_CAPSULE_DIR = IPAD_ROOT / "data" / "steam_capsules"
STEAM_HERO_DIR = IPAD_ROOT / "data" / "steam_headers"
STEAM_SCREENSHOT_DIR = IPAD_ROOT / "data" / "steam_screenshots"
NEWS_IMAGE_DIR = IPAD_ROOT / "data" / "news_images"


def load_project() -> dict:
    return json.loads(PROJECT_PATH.read_text(encoding="utf-8"))


def load_runtime_config() -> dict:
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


def enabled_templates(project: dict) -> list[dict]:
    templates = project.get("templates") or []
    return [t for t in templates if t.get("enabled")]


def iter_widgets(project: dict):
    for template in enabled_templates(project):
        for page in template.get("pages") or []:
            for widget in page.get("widgets") or []:
                if isinstance(widget, dict):
                    yield template, page, widget


def ensure_default_alerts(bridge: HermesBridge) -> None:
    inbox = bridge.read_inbox(include_acknowledged=True)
    if inbox:
        return
    bridge.notify("info", "GitHub", "关注 changelog 与有趣项目动态。", ttl_seconds=7 * 24 * 3600)
    bridge.notify("warn", "VPS", "留意流量与节点状态。", ttl_seconds=7 * 24 * 3600)


def refresh_weather(bridge: HermesBridge, city: str, proxy: str = "") -> None:
    payload = fetch_weather_payload(city, proxy=proxy)
    lines = [
        f"{payload.get('name', city)}: {payload.get('temperature', '?')}°C {payload.get('description', '')}",
        f"风速: {payload.get('wind_speed', '?')} km/h",
        f"今日: {payload.get('temp_min', '?')}~{payload.get('temp_max', '?')}°C",
    ]
    bridge.write_content_cache(f"weather::{city}", {"city": city, "lines": lines, "payload": payload})


def refresh_weekly_weather(bridge: HermesBridge, city: str, days: int, proxy: str = "") -> None:
    payload = fetch_weekly_weather_payload(city, days, proxy=proxy)
    lines = [f"{item['weekday']} {item['temp_min']}~{item['temp_max']}° {item['description']}" for item in payload.get("days", [])]
    bridge.write_content_cache(f"weather_weekly::{city}::{days}", {"city": city, "days": days, "lines": lines, "payload": payload})


def refresh_rss(bridge: HermesBridge, rss_url: str, max_items: int, proxy: str = "") -> None:
    if not rss_url:
        return
    items = fetch_rss_items(rss_url, max_items, proxy=proxy)
    NEWS_IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    for index, item in enumerate(items, 1):
        if not isinstance(item, dict):
            continue
        image_url = str(item.get("image_url") or "").strip()
        if not image_url:
            continue
        try:
            suffix = Path(image_url.split("?", 1)[0]).suffix or ".jpg"
            dest = NEWS_IMAGE_DIR / f"rss_{abs(hash(rss_url))}_{index}{suffix}"
            if proxy:
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(fetch_bytes(image_url, timeout=20, proxy=proxy))
                local = dest
            else:
                local = download_image(image_url, dest)
            item["image_local_path"] = str(local)
        except Exception:
            item["image_local_path"] = ""
    lines = [str(item.get("title") or "") for item in items if isinstance(item, dict) and str(item.get("title") or "").strip()]
    bridge.write_content_cache(f"rss::{rss_url}::{max_items}", {"rss_url": rss_url, "max_items": max_items, "lines": lines, "items": items})


def refresh_traffic_cache(bridge: HermesBridge, endpoint: str, token: str) -> None:
    data = fetch_traffic(endpoint=endpoint or None, token=token or None) if (endpoint or token) else fetch_traffic()
    lines = traffic_lines(data)
    bridge.write_content_cache(
        f"traffic::{endpoint or 'default'}::{token or 'default'}",
        {"endpoint": endpoint or "default", "token": token or "default", "lines": lines, "payload": data},
    )


def refresh_movies(bridge: HermesBridge, listing_url: str = "", proxy: str = "") -> None:
    data = fetch_now_playing_movies(
        limit=6,
        poster_dir=POSTER_DIR,
        backdrop_dir=MOVIE_BACKDROP_DIR,
        listing_url=listing_url,
        proxy=proxy,
    )
    items = data.get("items") if isinstance(data, dict) else []
    if not isinstance(items, list) or not items:
        previous = bridge.read_content_cache("movies::now_playing::6") or {}
        previous_items = previous.get("items") if isinstance(previous, dict) else []
        if isinstance(previous_items, list) and previous_items:
            previous["refresh_warning"] = "latest upstream fetch returned no movies; retained last successful cache"
            bridge.write_content_cache("movies::now_playing::6", previous)
            return
        raise RuntimeError("movie sources returned no items; empty cache not written")
    bridge.write_content_cache("movies::now_playing::6", data)


def refresh_private_channels(bridge: HermesBridge) -> None:
    bridge.write_content_cache("private_channels::summary", fetch_private_channel_summary())


def refresh_game_listing(bridge: HermesBridge, cache_key: str, fetcher, label: str, url: str = "", proxy: str = "") -> None:
    previous = bridge.read_content_cache(cache_key) or {}
    data = fetcher(limit=10, image_dir=NEWS_IMAGE_DIR, url=url, proxy=proxy)
    if not data.get("items"):
        if previous.get("items"):
            previous["refresh_warning"] = f"latest {label} fetch returned no items; retained last successful cache"
            bridge.write_content_cache(cache_key, previous)
            return
        raise RuntimeError(f"{label} returned no items and no prior cache exists")
    bridge.write_content_cache(cache_key, data)


def refresh_gamer520(bridge: HermesBridge, url: str = "", proxy: str = "") -> None:
    refresh_game_listing(bridge, "gamer520::pcplay::10", fetch_gamer520_pcplay, "Gamer520 PC", url=url, proxy=proxy)


def refresh_gamer520_switch(bridge: HermesBridge, url: str = "", proxy: str = "") -> None:
    refresh_game_listing(bridge, "gamer520::gameswitch::10", fetch_gamer520_switch, "Gamer520 Switch", url=url, proxy=proxy)


def refresh_ps5_games(bridge: HermesBridge, url: str = "", proxy: str = "") -> None:
    refresh_game_listing(bridge, "2468c::ps5game::10", fetch_ps5_games, "2468c PS5", url=url, proxy=proxy)


def refresh_github_ai(bridge: HermesBridge, force: bool = False, api_url: str = "", proxy: str = "") -> None:
    cache_key = "github::ai-trending::4"
    previous = bridge.read_content_cache(cache_key) or {}
    updated_at = str(previous.get("updated_at") or "")
    if not force and updated_at:
        try:
            age = datetime.now(timezone.utc) - datetime.fromisoformat(updated_at.replace("Z", "+00:00"))
            if age.total_seconds() < 3600 and previous.get("items"):
                return
        except (TypeError, ValueError):
            pass
    data = fetch_github_ai_trending(limit=12, days=30, api_url=api_url, proxy=proxy)
    if not data.get("items"):
        if previous.get("items"):
            return
        raise RuntimeError("GitHub AI search returned no repositories")
    bridge.write_content_cache(cache_key, data)


def refresh_steam_new_releases(bridge: HermesBridge, proxy_url: str, featured_url: str = "", proxy_fallback: bool = False) -> None:
    data = fetch_steam_new_releases(
        limit=6,
        proxy_url=proxy_url,
        capsule_dir=STEAM_CAPSULE_DIR,
        hero_dir=STEAM_HERO_DIR,
        screenshot_dir=STEAM_SCREENSHOT_DIR,
        proxy_fallback=proxy_fallback,
        featured_url=featured_url,
    )
    bridge.write_content_cache("steam::new_releases::6", data)


def refresh_steam_top_sellers(bridge: HermesBridge, proxy_url: str, featured_url: str = "", proxy_fallback: bool = False) -> None:
    data = fetch_steam_top_sellers(
        limit=2,
        proxy_url=proxy_url,
        capsule_dir=STEAM_CAPSULE_DIR,
        hero_dir=STEAM_HERO_DIR,
        screenshot_dir=STEAM_SCREENSHOT_DIR,
        proxy_fallback=proxy_fallback,
        featured_url=featured_url,
    )
    bridge.write_content_cache("steam::top_sellers::2", data)


def refresh_steam_new_and_trending(bridge: HermesBridge, proxy_url: str, featured_url: str = "", proxy_fallback: bool = False) -> None:
    data = fetch_steam_new_and_trending(
        limit=2,
        proxy_url=proxy_url,
        proxy_fallback=proxy_fallback,
        featured_url=featured_url,
        capsule_dir=STEAM_CAPSULE_DIR,
        hero_dir=STEAM_HERO_DIR,
        screenshot_dir=STEAM_SCREENSHOT_DIR,
    )
    bridge.write_content_cache("steam::new_and_trending::2", data)


def refresh_session_sync(bridge: HermesBridge) -> None:
    payload = load_latest_hermes_session_bridge_payload()
    if payload:
        bridge.write_session_status(payload)
    work_payload = load_latest_hermes_work_status_payload()
    if work_payload:
        bridge.set_work_status(
            summary=str(work_payload.get("summary") or ""),
            current_task=str(work_payload.get("current_task") or ""),
            next_task=str(work_payload.get("next_task") or ""),
            blocked=bool(work_payload.get("blocked") or False),
            blocker=str(work_payload.get("blocker") or ""),
        )


def refresh_printmana(bridge: HermesBridge, printmana_api: str, proxy: str = "") -> None:
    url = str(printmana_api or "").strip()
    if not url:
        return
    import subprocess

    def _curl_json(target: str, timeout: int = 8):
        command = [
            "curl", "-sS", "--max-time", str(timeout),
            "--connect-timeout", str(timeout),
        ]
        if proxy:
            command.extend(["--proxy", proxy])
        command.append(target)
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            stderr = (result.stderr or "").strip()
            stdout = (result.stdout or "").strip()
            message = stderr or stdout or f"curl exit {result.returncode}"
            raise RuntimeError(message)
        try:
            return json.loads(result.stdout)
        except Exception as e:
            raise ValueError(f"接口返回不是有效 JSON: {e}") from e

    data = _curl_json(url)
    if not isinstance(data, list):
        raise ValueError("打印机接口返回不是数组")
    detail = None
    if data:
        printer_id = data[0].get("id")
        if printer_id:
            detail = _curl_json(url.rstrip("/") + "/" + str(printer_id))
    bridge.write_printmana({"endpoint": url, "printers": data, "primary": detail, "updated_at": datetime.now().isoformat()})


def refresh_bilibili(bridge: HermesBridge, uid: str, cookie: str) -> None:
    uid = str(uid or "").strip()
    if not uid:
        return
    data = fetch_bilibili_status(uid, normalize_cookie_string(cookie))
    bridge.write_bilibili(data)


def safe_step(label: str, fn) -> tuple[str, str]:
    try:
        fn()
        return (label, "ok")
    except Exception as exc:
        return (label, f"error: {exc}")


def refresh_daily_defaults(bridge: HermesBridge) -> None:
    current = bridge.read_daily()
    greeting = str(current.get("greeting") or "主人们，今天继续稳稳推进")
    quote = str(current.get("quote") or "准备开始")
    weather_city = str(current.get("weather_city") or "Shanghai")
    topics = current.get("news_topics") if isinstance(current.get("news_topics"), list) else []
    bridge.set_daily_greeting(greeting=greeting, quote=quote, weather_city=weather_city, news_topics=topics)


def should_do_full_steam_refresh(bridge: HermesBridge, force: bool = False) -> bool:
    if force:
        return True
    interval_minutes = max(30, int(os.environ.get("REMOTE_PANEL_STEAM_REFRESH_MINUTES", "180") or "180"))
    cache = bridge.read_content_cache("steam::new_releases::6") or {}
    updated_at = str(cache.get("updated_at") or "").strip()
    if not updated_at:
        return True
    try:
        normalized = updated_at.replace("Z", "+00:00")
        updated_dt = datetime.fromisoformat(normalized)
        if updated_dt.tzinfo is None:
            updated_dt = updated_dt.replace(tzinfo=timezone.utc)
    except Exception:
        return True
    age_seconds = (datetime.now(timezone.utc) - updated_dt.astimezone(timezone.utc)).total_seconds()
    return age_seconds >= interval_minutes * 60


def main() -> int:
    parser = argparse.ArgumentParser(description="Refresh iPad content cache")
    parser.add_argument("--fast", action="store_true", help="skip slow Steam refreshes for frequent automatic updates")
    args = parser.parse_args()
    project = load_project()
    runtime_cfg = load_runtime_config()
    bridge = HermesBridge(BRIDGE_PATH)
    POSTER_DIR.mkdir(parents=True, exist_ok=True)
    STEAM_CAPSULE_DIR.mkdir(parents=True, exist_ok=True)
    STEAM_HERO_DIR.mkdir(parents=True, exist_ok=True)
    STEAM_SCREENSHOT_DIR.mkdir(parents=True, exist_ok=True)
    NEWS_IMAGE_DIR.mkdir(parents=True, exist_ok=True)

    results: list[tuple[str, str]] = []

    results.append(safe_step("session_sync", lambda: refresh_session_sync(bridge)))
    results.append(("default_alerts", "skipped: synthetic alerts disabled"))
    results.append(safe_step("daily_defaults", lambda: refresh_daily_defaults(bridge)))

    source_settings = load_source_settings()
    city = weather_city(source_settings)
    weather_proxy = effective_proxy("weather", source_settings)
    weather_targets: set[str] = {city}
    weekly_targets: set[tuple[str, int]] = {(city, 6)}
    rss_targets: dict[str, tuple[int, str]] = {}
    for source_id, limit in (("daily-news", 8), ("hello", 4), ("x-news", 8)):
        rss = source_url(source_id, source_settings)
        if rss:
            rss_targets[rss] = (limit, effective_proxy(source_id, source_settings))
    github_endpoint = source_url("github-news", source_settings)
    if looks_like_feed(github_endpoint):
        rss_targets[github_endpoint] = (8, effective_proxy("github-news", source_settings))
    else:
        rss_targets.setdefault("https://github.blog/changelog/feed/", (4, effective_proxy("github-news", source_settings)))
    traffic_targets: set[tuple[str, str]] = {("", "")}

    for _template, _page, widget in iter_widgets(project):
        wtype = str(widget.get("type") or "")
        if wtype == "weather":
            weather_targets.add(str(widget.get("city") or "Shanghai").strip() or "Shanghai")
        elif wtype == "weather_weekly":
            city = str(widget.get("city") or "Shanghai").strip() or "Shanghai"
            requested_days = max(1, int(widget.get("max_items") or 6))
            fetch_days = requested_days + 1 if requested_days >= 6 else requested_days
            weekly_targets.add((city, fetch_days))
        elif wtype == "rss_news":
            rss_url = str(widget.get("rss_url") or "").strip()
            max_items = max(1, int(widget.get("max_items") or 5))
            if rss_url:
                rss_targets.setdefault(rss_url, (max_items, ""))
        elif wtype in {"traffic_usage", "traffic_dashboard_card"}:
            extra = widget.get("extra") if isinstance(widget.get("extra"), dict) else {}
            endpoint = str(extra.get("endpoint") or "")
            token = str(extra.get("token") or "")
            traffic_targets.add((endpoint, token))

    for city_name in sorted(weather_targets):
        results.append(safe_step(f"weather:{city_name}", lambda city_name=city_name: refresh_weather(bridge, city_name, proxy=weather_proxy)))
    for city_name, days in sorted(weekly_targets):
        results.append(safe_step(f"weekly_weather:{city_name}:{days}", lambda city_name=city_name, days=days: refresh_weekly_weather(bridge, city_name, days, proxy=weather_proxy)))
    for rss_url, (max_items, rss_proxy) in sorted(rss_targets.items()):
        results.append(safe_step(f"rss:{max_items}:{rss_url}", lambda rss_url=rss_url, max_items=max_items, rss_proxy=rss_proxy: refresh_rss(bridge, rss_url, max_items, proxy=rss_proxy)))
    for endpoint, token in sorted(traffic_targets):
        results.append(safe_step(f"traffic:{endpoint or 'default'}", lambda endpoint=endpoint, token=token: refresh_traffic_cache(bridge, endpoint, token)))

    print_url = source_url("print", source_settings) or str(runtime_cfg.get("printmana_api") or "")
    results.append(safe_step("printmana", lambda: refresh_printmana(bridge, print_url, proxy=effective_proxy("print", source_settings))))
    results.append(safe_step("private_channels", lambda: refresh_private_channels(bridge)))
    results.append(safe_step("movies", lambda: refresh_movies(
        bridge,
        listing_url=source_url("movie-now-showing", source_settings),
        proxy=effective_proxy("movie-now-showing", source_settings),
    )))
    results.append(safe_step("gamer520", lambda: refresh_gamer520(
        bridge,
        url=source_url("gamer520-pc-latest", source_settings),
        proxy=effective_proxy("gamer520-pc-latest", source_settings),
    )))
    results.append(safe_step("gamer520_switch", lambda: refresh_gamer520_switch(
        bridge,
        url=source_url("gamer520-switch-latest", source_settings),
        proxy=effective_proxy("gamer520-switch-latest", source_settings),
    )))
    results.append(safe_step("ps5_games", lambda: refresh_ps5_games(
        bridge,
        url=source_url("ps5-games-latest", source_settings),
        proxy=effective_proxy("ps5-games-latest", source_settings),
    )))
    if looks_like_feed(github_endpoint):
        results.append(("github_ai", "skipped: github source is an RSS feed"))
    else:
        results.append(safe_step("github_ai", lambda: refresh_github_ai(
            bridge,
            force=not args.fast,
            api_url=github_endpoint,
            proxy=effective_proxy("github-news", source_settings),
        )))
    steam_new_proxy = effective_proxy("steam-new-releases", source_settings)
    steam_hot_proxy = effective_proxy("steam-new-releases-2", source_settings)
    do_full_steam_refresh = should_do_full_steam_refresh(bridge, force=not args.fast)
    if do_full_steam_refresh:
        results.append(safe_step("steam", lambda: refresh_steam_new_releases(
            bridge,
            steam_new_proxy,
            featured_url=source_url("steam-new-releases", source_settings),
            proxy_fallback=False,
        )))
        results.append(safe_step("steam_top_sellers", lambda: refresh_steam_top_sellers(
            bridge,
            steam_hot_proxy,
            featured_url=source_url("steam-new-releases-2", source_settings),
            proxy_fallback=False,
        )))
        results.append(safe_step("steam_new_and_trending", lambda: refresh_steam_new_and_trending(
            bridge,
            steam_hot_proxy,
            featured_url=source_url("steam-new-releases-2", source_settings),
            proxy_fallback=False,
        )))
    else:
        reason = "fresh cache"
        if args.fast:
            reason = "fast mode + fresh cache"
        results.append(("steam", f"skipped: {reason}"))
        results.append(("steam_top_sellers", f"skipped: {reason}"))
        results.append(("steam_new_and_trending", f"skipped: {reason}"))
    results.append(safe_step("schedule", lambda: sync_ics_file(
        BRIDGE_PATH / "schedule.json",
        source_url("schedule", source_settings),
        proxy=effective_proxy("schedule", source_settings),
    )))
    results.append(safe_step("bilibili", lambda: refresh_bilibili(
        bridge,
        str(runtime_cfg.get("bili_uid") or ""),
        str(runtime_cfg.get("bili_cookie") or ""),
    )))
    now = datetime.now().isoformat()
    bridge.write_state(last_content_refresh_at=now)

    state = {}
    if STATE_PATH.exists():
        try:
            state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
        except Exception:
            state = {}
    if not isinstance(state, dict):
        state = {}
    state["last_content_refresh_at"] = now
    state["updated_at"] = now
    STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
    summary = ", ".join(f"{label}={status}" for label, status in results)
    print(f"iPad cache refreshed into {BRIDGE_PATH}")
    print(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
