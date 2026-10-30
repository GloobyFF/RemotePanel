from __future__ import annotations

import json
import re
import urllib.parse
import urllib.request
import html as html_lib
from pathlib import Path
from typing import Any
from datetime import datetime, timezone

from .utils import download_image

TMDB_NOW_PLAYING_URL = "https://www.themoviedb.org/movie/now-playing"
TMDB_POPULAR_URL = "https://www.themoviedb.org/movie"
TMDB_UPCOMING_URL = "https://www.themoviedb.org/movie/upcoming"
TMDB_IMAGE_BASE = "https://image.tmdb.org/t/p/w342"
USER_AGENT = "RemotePanelEInkStudio/0.1"


def _fetch_html(url: str, timeout: int = 20, proxy: str = "") -> str:
    if proxy:
        from core.http_fetch import fetch_text
        return fetch_text(url, timeout=timeout, proxy=proxy, headers={"User-Agent": USER_AGENT})
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", errors="ignore")


def _clean_text(text: str) -> str:
    text = re.sub(r"<[^>]+>", " ", text)
    text = html_lib.unescape(text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def _extract_json_ld(html: str) -> list[dict[str, Any]]:
    blocks = re.findall(r'<script type="application/ld\+json">(.*?)</script>', html, flags=re.S | re.I)
    items: list[dict[str, Any]] = []
    for raw in blocks:
        raw = raw.strip()
        if not raw:
            continue
        try:
            payload = json.loads(raw)
        except Exception:
            continue
        if isinstance(payload, list):
            for entry in payload:
                if isinstance(entry, dict):
                    items.append(entry)
        elif isinstance(payload, dict):
            items.append(payload)
    return items


def _extract_meta_content(html: str, name: str) -> str:
    patterns = [
        rf'<meta\s+name="{re.escape(name)}"\s+content="([^"]*)"',
        rf'<meta\s+property="{re.escape(name)}"\s+content="([^"]*)"',
    ]
    for pattern in patterns:
        match = re.search(pattern, html, flags=re.I)
        if match:
            return _clean_text(match.group(1))
    return ""


def _fetch_movie_detail(url: str) -> dict[str, Any]:
    if not url:
        return {}
    try:
        html = _fetch_html(url, timeout=15)
    except Exception:
        return {}
    overview = _extract_meta_content(html, "description") or _extract_meta_content(html, "og:description")
    poster_url = _extract_meta_content(html, "og:image")
    backdrop_urls: list[str] = []
    detail_backdrop_match = re.search(
        r'<img[^>]+class="[^"]*backdrop[^"]*"[^>]+src="(?P<url>https://media\.themoviedb\.org/t/p/[^"\s]+)"',
        html,
        flags=re.I,
    )
    if detail_backdrop_match:
        backdrop_urls.append(html_lib.unescape(detail_backdrop_match.group("url")))
    try:
        backdrop_html = _fetch_html(url.rstrip("/") + "/images/backdrops", timeout=15)
        for match in re.finditer(
            r'https://media\.themoviedb\.org/t/p/(?:w500_and_h282_face|w533_and_h300_face|original)/[^"\'\s]+',
            backdrop_html,
            flags=re.I,
        ):
            backdrop_url = html_lib.unescape(match.group(0))
            if backdrop_url not in backdrop_urls:
                backdrop_urls.append(backdrop_url)
            if len(backdrop_urls) >= 2:
                break
    except Exception:
        pass
    for entry in _extract_json_ld(html):
        if str(entry.get("@type") or "").lower() != "movie":
            continue
        if not overview:
            overview = _clean_text(str(entry.get("description") or ""))
        if not poster_url:
            image_value = entry.get("image")
            if isinstance(image_value, str):
                poster_url = image_value
            elif isinstance(image_value, list) and image_value:
                poster_url = str(image_value[0])
        break
    return {
        "overview": overview,
        "poster_url": poster_url,
        "backdrop_url": backdrop_urls[0] if backdrop_urls else "",
        "backdrop_urls": backdrop_urls,
    }


def fetch_now_playing_movies(
    limit: int = 6,
    poster_dir: Path | None = None,
    backdrop_dir: Path | None = None,
    listing_url: str = "",
    proxy: str = "",
) -> dict[str, Any]:
    def parse_listing(url: str, source_label: str) -> list[dict[str, Any]]:
        html = _fetch_html(url, proxy=proxy)
        parsed: list[dict[str, Any]] = []

        json_ld_items = _extract_json_ld(html)
        for entry in json_ld_items:
            if str(entry.get("@type") or "").lower() != "movie":
                continue
            title = str(entry.get("name") or "").strip()
            if not title:
                continue
            release_date = str(entry.get("dateCreated") or entry.get("datePublished") or "").strip()
            overview = _clean_text(str(entry.get("description") or ""))
            poster_url = ""
            image_value = entry.get("image")
            if isinstance(image_value, str):
                poster_url = image_value
            elif isinstance(image_value, list) and image_value:
                poster_url = str(image_value[0])
            movie_url = str(entry.get("url") or "").strip()
            movie_id = ""
            match = re.search(r"/movie/(\d+)", movie_url)
            if match:
                movie_id = match.group(1)
            parsed.append(
                {
                    "id": movie_id,
                    "title": title,
                    "release_date": release_date,
                    "overview": overview,
                    "poster_url": poster_url,
                    "url": movie_url,
                    "poster_local_path": "",
                    "source": source_label + "_jsonld",
                }
            )

        if len(parsed) < limit * 2:
            card_pattern = re.compile(
                r'href="(?P<url>/movie/(?P<id>\d+)[^\"]*)"[\s\S]{0,900}?'
                r'<img[^>]+alt="(?P<title>[^\"]+)"[^>]+(?:src|srcset)="(?P<img>https://[^\"\s]+)[^\"]*"[\s\S]{0,1200}?'
                r'<span[^>]+class="[^\"]*(?:release_date|subheader)[^\"]*"[^>]*>(?P<date>[^<]+)</span>',
                flags=re.S | re.I,
            )
            seen_titles = {item["title"] for item in parsed}
            for match in card_pattern.finditer(html):
                title = _clean_text(match.group("title"))
                if not title or title in seen_titles:
                    continue
                poster_url = _clean_text(match.group("img"))
                release_date = _clean_text(match.group("date"))
                movie_id = _clean_text(match.group("id"))
                movie_url = urllib.parse.urljoin("https://www.themoviedb.org", match.group("url"))
                parsed.append(
                    {
                        "id": movie_id,
                        "title": title,
                        "release_date": release_date,
                        "overview": "",
                        "poster_url": poster_url,
                        "url": movie_url,
                        "poster_local_path": "",
                        "source": source_label + "_cards",
                    }
                )
                seen_titles.add(title)
        return parsed

    pool: list[dict[str, Any]] = []
    custom = str(listing_url or "").strip()
    sources = [(custom, "custom")] if custom and custom.rstrip("/") != TMDB_NOW_PLAYING_URL.rstrip("/") else [
        (TMDB_NOW_PLAYING_URL, "tmdb_now_playing"),
        (TMDB_UPCOMING_URL, "tmdb_upcoming"),
        (TMDB_POPULAR_URL, "tmdb_popular"),
    ]
    for url, source_label in sources:
        try:
            pool.extend(parse_listing(url, source_label))
        except Exception:
            continue

    deduped: list[dict[str, Any]] = []
    seen_keys: set[str] = set()
    for item in pool:
        key = str(item.get("id") or "").strip() or str(item.get("title") or "").strip().lower()
        if not key or key in seen_keys:
            continue
        seen_keys.add(key)
        deduped.append(item)
        if len(deduped) >= max(limit * 3, 12):
            break

    items = deduped[: max(limit * 2, 12)]
    if items:
        window_size = min(limit, len(items))
        cycle = max(1, len(items) - window_size + 1)
        now = datetime.now(timezone.utc)
        offset = (now.timetuple().tm_yday * 24 + now.hour) % cycle
        items = items[offset:] + items[:offset]
    for item in items:
        detail = _fetch_movie_detail(str(item.get("url") or ""))
        if detail.get("overview"):
            item["overview"] = detail["overview"]
        if detail.get("poster_url"):
            item["poster_url"] = detail["poster_url"]
        if detail.get("backdrop_url"):
            item["backdrop_url"] = detail["backdrop_url"]
        if detail.get("backdrop_urls"):
            item["backdrop_urls"] = detail["backdrop_urls"]

    if poster_dir:
        poster_dir.mkdir(parents=True, exist_ok=True)
        for index, item in enumerate(items, 1):
            poster_url = str(item.get("poster_url") or "").strip()
            if not poster_url:
                continue
            movie_id = str(item.get("id") or "").strip() or f"movie_{index}"
            suffix = Path(urllib.parse.urlparse(poster_url).path).suffix or ".jpg"
            dest = poster_dir / f"{movie_id}{suffix}"
            try:
                download_image(poster_url, dest)
                item["poster_local_path"] = str(dest)
            except Exception:
                continue

    if backdrop_dir:
        backdrop_dir.mkdir(parents=True, exist_ok=True)
        for index, item in enumerate(items, 1):
            backdrop_urls = item.get("backdrop_urls") if isinstance(item.get("backdrop_urls"), list) else []
            if not backdrop_urls and item.get("backdrop_url"):
                backdrop_urls = [item.get("backdrop_url")]
            movie_id = str(item.get("id") or "").strip() or f"movie_{index}"
            local_paths = []
            for backdrop_index, raw_url in enumerate(backdrop_urls[:2], 1):
                backdrop_url = str(raw_url or "").strip()
                if not backdrop_url:
                    continue
                suffix = Path(urllib.parse.urlparse(backdrop_url).path).suffix or ".jpg"
                dest = backdrop_dir / f"{movie_id}_{backdrop_index}{suffix}"
                try:
                    download_image(backdrop_url, dest)
                    local_paths.append(str(dest))
                except Exception:
                    continue
            if local_paths:
                item["backdrop_local_path"] = local_paths[0]
                item["backdrop_local_paths"] = local_paths

    return {
        "source": "tmdb_multi_pool",
        "sources": [TMDB_NOW_PLAYING_URL, TMDB_UPCOMING_URL, TMDB_POPULAR_URL],
        "items": items[:limit],
        "pool_size": len(items),
    }
