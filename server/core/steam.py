from __future__ import annotations

import json
import os
import re
import subprocess
import urllib.parse
import html
from datetime import datetime
from pathlib import Path
from typing import Any

from .utils import download_image

STEAM_FEATURED_URL = "https://store.steampowered.com/api/featuredcategories?cc=cn&l=schinese"
STEAM_APPDETAILS_URL = "https://store.steampowered.com/api/appdetails?cc=cn&l=schinese&appids={app_id}"
DEFAULT_PROXY = "socks5://192.168.28.77:1080"
LOW_SIGNAL_WORDS = {
    "dlc",
    "soundtrack",
    "ost",
    "artbook",
    "demo",
    "playtest",
    "test server",
    "server",
    "pack",
    "bundle",
    "合集",
    "捆绑包",
    "支持者包",
    "资料片",
    "终极版",
    "壁纸",
    "wallpaper",
    "skin",
    "avatar",
}
EXCLUDED_TEXT_WORDS = {
    "adult",
    "adults only",
    "nsfw",
    "hentai",
    "eroge",
    "erotic",
    "porn",
    "sex",
    "sexual",
    "nudity",
    "nude",
    "only upskirt",
    "18+",
    "成人",
    "色情",
    "性爱",
    "性内容",
    "裸露",
    "裸体",
    "黄油",
    "绅士",
    "乳摇",
    "你妈真漂亮",
}
EXCLUDED_TAG_IDS = {
    12095,  # Sexual Content
    6650,   # Nudity
    9130,   # Hentai
    5611,   # Mature
    24904,  # NSFW
}


def _resolve_proxy(proxy_url: str | None = None, fallback: bool = True) -> str:
    direct = str(proxy_url or "").strip()
    if direct:
        return direct
    if not fallback:
        return ""
    for key in ("REMOTEPANEL_STEAM_PROXY", "STEAM_PROXY"):
        value = str(os.environ.get(key) or "").strip()
        if value:
            return value
    return DEFAULT_PROXY


def _curl_text(url: str, timeout: int = 20, proxy_url: str | None = None, proxy_fallback: bool = True) -> str:
    env = os.environ.copy()
    proxy = _resolve_proxy(proxy_url, fallback=proxy_fallback)
    if proxy:
        env["ALL_PROXY"] = proxy
        env["all_proxy"] = proxy
    else:
        for key in ("ALL_PROXY", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"):
            env.pop(key, None)
    command = [
        "curl",
        "-sS",
        "-L",
        "--max-time",
        str(timeout),
        "--connect-timeout",
        str(timeout),
        url,
    ]
    result = subprocess.run(command, capture_output=True, text=True, env=env, check=False)
    if result.returncode != 0:
        stderr = (result.stderr or "").strip()
        stdout = (result.stdout or "").strip()
        raise RuntimeError(stderr or stdout or f"curl exit {result.returncode}")
    return result.stdout


def _curl_json(url: str, timeout: int = 20, proxy_url: str | None = None, proxy_fallback: bool = True) -> dict[str, Any]:
    data = json.loads(_curl_text(url, timeout=timeout, proxy_url=proxy_url, proxy_fallback=proxy_fallback))
    if not isinstance(data, dict):
        raise ValueError("Steam API payload is not an object")
    return data


def _clean_text(value: Any) -> str:
    text = str(value or "").strip()
    text = re.sub(r"<br\s*/?>", " ", text, flags=re.I)
    text = re.sub(r"<[^>]+>", " ", text)
    text = html.unescape(text)
    text = re.sub(r"\s+", " ", text)
    return text


def _price_text(item: dict[str, Any]) -> str:
    final = item.get("final_price")
    original = item.get("original_price")
    discount = int(item.get("discount_percent") or 0)
    if item.get("is_free"):
        return "免费"
    if isinstance(final, int):
        final_text = f"¥{final / 100:.0f}" if final % 100 == 0 else f"¥{final / 100:.2f}"
        if discount > 0 and isinstance(original, int):
            return f"{final_text} ({discount}% off)"
        return final_text
    return "价格待定"


def _review_text(item: dict[str, Any]) -> str:
    label = _clean_text(item.get("review_desc"))
    if label:
        return label
    pct = item.get("review_score")
    total = item.get("review_count")
    if isinstance(pct, int) and isinstance(total, int) and total > 0:
        return f"{pct}% / {total}评"
    return "新作观察中"


def _genres_text(item: dict[str, Any]) -> str:
    genres = item.get("genres") or []
    names: list[str] = []
    for genre in genres:
        if isinstance(genre, dict):
            name = _clean_text(genre.get("description") or genre.get("name"))
            if name:
                names.append(name)
    return " / ".join(names[:2]) or "类型待补充"


def _tag_names(item: dict[str, Any]) -> list[str]:
    tags = item.get("tags") or item.get("categories") or []
    names: list[str] = []
    for tag in tags:
        if isinstance(tag, dict):
            name = _clean_text(tag.get("name"))
            if name:
                names.append(name)
        elif isinstance(tag, str):
            name = _clean_text(tag)
            if name:
                names.append(name)
    return names


def _tag_ids(item: dict[str, Any]) -> set[int]:
    ids: set[int] = set()
    for bucket_name in ("tags", "content_descriptors"):
        bucket = item.get(bucket_name) or []
        if isinstance(bucket, dict):
            for value in bucket.values():
                try:
                    ids.add(int(value))
                except Exception:
                    pass
        else:
            for entry in bucket:
                if isinstance(entry, dict):
                    for candidate in (entry.get("tagid"), entry.get("id")):
                        try:
                            ids.add(int(candidate))
                        except Exception:
                            pass
                else:
                    try:
                        ids.add(int(entry))
                    except Exception:
                        pass
    return ids


def _is_low_signal(item: dict[str, Any]) -> bool:
    fields = [
        _clean_text(item.get("name")),
        _clean_text(item.get("short_description")),
        " ".join(_tag_names(item)),
    ]
    hay = " ".join(fields).lower()
    return any(word in hay for word in LOW_SIGNAL_WORDS)


def _should_exclude(item: dict[str, Any]) -> bool:
    tag_ids = _tag_ids(item)
    if tag_ids & EXCLUDED_TAG_IDS:
        return True
    fields = [
        _clean_text(item.get("name")),
        _clean_text(item.get("title")),
        _clean_text(item.get("short_description")),
        _clean_text(item.get("detailed_description")),
        _clean_text(item.get("about_the_game")),
        " ".join(_tag_names(item)),
        _genres_text(item),
    ]
    hay = " ".join(fields).lower()
    if any(word in hay for word in EXCLUDED_TEXT_WORDS):
        return True
    if _is_low_signal(item):
        return True
    return False


def _one_liner(item: dict[str, Any], section_key: str = "new_releases") -> str:
    desc = _clean_text(item.get("short_description") or item.get("about_the_game") or item.get("detailed_description"))
    if not desc:
        tags = _tag_names(item)
        if tags:
            desc = "、".join(tags[:4])
    if not desc:
        genre_text = _genres_text(item)
        desc = f"{genre_text}作品，等待商店补充简介。"
    max_len = 70 if section_key == "top_sellers" else 74
    if len(desc) > max_len:
        desc = desc[: max_len - 1].rstrip() + "…"
    return desc


def _fetch_appdetails(app_id: str, proxy_url: str, proxy_fallback: bool = True) -> dict[str, Any]:
    payload = _curl_json(STEAM_APPDETAILS_URL.format(app_id=app_id), timeout=30, proxy_url=proxy_url, proxy_fallback=proxy_fallback)
    block = payload.get(str(app_id)) or {}
    data = block.get("data") if isinstance(block, dict) else {}
    return data if isinstance(data, dict) else {}


def _parse_release_date(details: dict[str, Any]) -> tuple[str, datetime | None]:
    release = details.get("release_date") if isinstance(details.get("release_date"), dict) else {}
    date_text = _clean_text(release.get("date"))
    if not date_text:
        return "", None
    for fmt in ("%d %b, %Y", "%b %d, %Y", "%Y年%m月%d日", "%Y-%m-%d", "%Y/%m/%d"):
        try:
            return date_text, datetime.strptime(date_text, fmt)
        except Exception:
            continue
    return date_text, None


def _is_recent_release(release_dt: datetime | None, max_age_days: int) -> bool:
    if release_dt is None:
        return False
    delta = datetime.now() - release_dt
    return 0 <= delta.days <= max_age_days


def _download_to(url: str, dest: Path) -> str:
    if not url:
        return ""
    try:
        download_image(url, dest)
        return str(dest)
    except Exception:
        return ""


def _build_featured_section(
    section_key: str,
    limit: int,
    proxy_url: str | None,
    capsule_dir: Path | None,
    hero_dir: Path | None,
    screenshot_dir: Path | None,
    title: str,
    subtitle: str,
    proxy_fallback: bool = True,
    featured_url: str = "",
) -> dict[str, Any]:
    proxy = _resolve_proxy(proxy_url, fallback=proxy_fallback)
    payload = _curl_json(featured_url or STEAM_FEATURED_URL, proxy_url=proxy, proxy_fallback=False)
    section = payload.get(section_key) or {}
    raw_items = section.get("items") or []
    if not isinstance(raw_items, list):
        raw_items = []

    kept: list[dict[str, Any]] = []
    skipped: list[str] = []
    for raw in raw_items:
        if not isinstance(raw, dict):
            continue
        name = _clean_text(raw.get("name") or f"Steam #{raw.get('id')}")
        app_id = str(raw.get("id") or "").strip()
        if not app_id:
            skipped.append(name)
            continue
        if _should_exclude(raw):
            skipped.append(name)
            continue
        try:
            details = _fetch_appdetails(app_id, proxy, proxy_fallback=False)
        except Exception:
            details = {}
        combined = dict(raw)
        combined.update({k: v for k, v in details.items() if v not in (None, "", [], {})})
        if _should_exclude(combined):
            skipped.append(name)
            continue
        detail_name = _clean_text(combined.get("name") or name)
        capsule = _clean_text(raw.get("large_capsule_image") or raw.get("small_capsule_image") or raw.get("header_image"))
        tags = _tag_names(combined)
        date_text, _release_dt = _parse_release_date(combined)
        release_info = combined.get("release_date") if isinstance(combined.get("release_date"), dict) else {}
        kept.append(
            {
                "id": app_id,
                "title": detail_name,
                "genres": _genres_text(combined),
                "price": _price_text(raw),
                "review": _review_text(raw),
                "summary": _one_liner(combined, section_key=section_key),
                "capsule_image": capsule,
                "capsule_local_path": "",
                "header_image": "",
                "header_local_path": "",
                "screenshots": [],
                "tags": tags[:6],
                "release_date": {
                    "date": date_text or _clean_text(raw.get("release_date")),
                    "coming_soon": bool(release_info.get("coming_soon")) if isinstance(release_info, dict) else False,
                },
                "steam_url": f"https://store.steampowered.com/app/{app_id}",
                "_details": details,
            }
        )
        if len(kept) >= limit:
            break

    if capsule_dir:
        capsule_dir.mkdir(parents=True, exist_ok=True)
    if hero_dir:
        hero_dir.mkdir(parents=True, exist_ok=True)
    if screenshot_dir:
        screenshot_dir.mkdir(parents=True, exist_ok=True)

    for index, item in enumerate(kept, 1):
        app_id = str(item.get("id") or "").strip() or f"steam_{index}"
        capsule_url = str(item.get("capsule_image") or "").strip()
        if capsule_dir and capsule_url:
            suffix = Path(urllib.parse.urlparse(capsule_url).path).suffix or ".jpg"
            item["capsule_local_path"] = _download_to(capsule_url, capsule_dir / f"{app_id}{suffix}")

        details = item.pop("_details", {}) if isinstance(item.get("_details"), dict) else {}
        if not details:
            details = _fetch_appdetails(app_id, proxy, proxy_fallback=False)
        header_url = _clean_text(details.get("header_image"))
        screenshots = details.get("screenshots") if isinstance(details.get("screenshots"), list) else []
        item["header_image"] = header_url
        if hero_dir and header_url:
            suffix = Path(urllib.parse.urlparse(header_url).path).suffix or ".jpg"
            item["header_local_path"] = _download_to(header_url, hero_dir / f"{app_id}{suffix}")

        local_shots: list[dict[str, Any]] = []
        for shot_index, shot in enumerate(screenshots[:2], 1):
            if not isinstance(shot, dict):
                continue
            shot_url = _clean_text(shot.get("path_full") or shot.get("path_thumbnail"))
            local_path = ""
            if screenshot_dir and shot_url:
                suffix = Path(urllib.parse.urlparse(shot_url).path).suffix or ".jpg"
                local_path = _download_to(shot_url, screenshot_dir / f"{app_id}_{shot_index}{suffix}")
            local_shots.append(
                {
                    "url": shot_url,
                    "local_path": local_path,
                }
            )
        item["screenshots"] = local_shots

    return {
        "source": STEAM_FEATURED_URL,
        "section": section_key,
        "proxy": proxy,
        "fetched_at": datetime.now().isoformat(),
        "title": title,
        "subtitle": subtitle,
        "items": kept,
        "raw_count": len(raw_items),
        "shown_count": len(kept),
        "filtered_count": len(skipped),
        "skipped_titles": skipped[:20],
    }


def fetch_steam_new_releases(
    limit: int = 6,
    proxy_url: str | None = None,
    capsule_dir: Path | None = None,
    hero_dir: Path | None = None,
    screenshot_dir: Path | None = None,
    proxy_fallback: bool = True,
    featured_url: str = "",
) -> dict[str, Any]:
    return _build_featured_section(
        section_key="new_releases",
        limit=limit,
        proxy_url=proxy_url,
        capsule_dir=capsule_dir,
        hero_dir=hero_dir,
        screenshot_dir=screenshot_dir,
        title="Steam 新游",
        subtitle="近期上架精选",
        proxy_fallback=proxy_fallback,
        featured_url=featured_url,
    )


def fetch_steam_top_sellers(
    limit: int = 6,
    proxy_url: str | None = None,
    capsule_dir: Path | None = None,
    hero_dir: Path | None = None,
    screenshot_dir: Path | None = None,
    proxy_fallback: bool = True,
    featured_url: str = "",
) -> dict[str, Any]:
    return _build_featured_section(
        section_key="top_sellers",
        limit=limit,
        proxy_url=proxy_url,
        capsule_dir=capsule_dir,
        hero_dir=hero_dir,
        screenshot_dir=screenshot_dir,
        title="Steam 热门",
        subtitle="当前热销与高关注作品",
        proxy_fallback=proxy_fallback,
        featured_url=featured_url,
    )


def fetch_steam_new_and_trending(
    limit: int = 2,
    proxy_url: str | None = None,
    capsule_dir: Path | None = None,
    hero_dir: Path | None = None,
    screenshot_dir: Path | None = None,
    recent_days: int = 365,
    fallback_days: int = 730,
    proxy_fallback: bool = True,
    featured_url: str = "",
) -> dict[str, Any]:
    top_sellers = fetch_steam_top_sellers(
        limit=12,
        proxy_url=proxy_url,
        capsule_dir=capsule_dir,
        hero_dir=hero_dir,
        screenshot_dir=screenshot_dir,
        proxy_fallback=proxy_fallback,
        featured_url=featured_url,
    )
    proxy = _resolve_proxy(proxy_url, fallback=proxy_fallback)
    items = top_sellers.get("items") if isinstance(top_sellers, dict) else []
    items = items if isinstance(items, list) else []

    recent: list[dict[str, Any]] = []
    fallback: list[dict[str, Any]] = []
    for item in items:
        app_id = str(item.get("id") or "").strip()
        if not app_id:
            continue
        details = _fetch_appdetails(app_id, proxy, proxy_fallback=False)
        release_info = details.get("release_date") if isinstance(details.get("release_date"), dict) else {}
        date_text, release_dt = _parse_release_date(details)
        item["release_date"] = {
            "date": date_text,
            "coming_soon": bool(release_info.get("coming_soon")) if isinstance(release_info, dict) else False,
        }
        if _is_recent_release(release_dt, recent_days):
            recent.append(item)
        elif _is_recent_release(release_dt, fallback_days):
            fallback.append(item)

    selected = (recent + fallback)[:limit]
    if not selected:
        selected = items[:limit]
    top_sellers["items"] = selected
    top_sellers["shown_count"] = len(selected)
    top_sellers["title"] = "Steam 新品热卖"
    top_sellers["subtitle"] = f"近{recent_days}天发售且当前热销"
    top_sellers["section"] = "new_and_trending"
    top_sellers["recent_days"] = recent_days
    top_sellers["fallback_days"] = fallback_days
    return top_sellers
