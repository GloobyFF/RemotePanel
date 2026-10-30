from __future__ import annotations

import json
import os
import urllib.parse
from datetime import datetime, timedelta, timezone

from core.http_fetch import fetch_bytes

GITHUB_SEARCH_URL = "https://api.github.com/search/repositories"
TOPICS = ("ai", "llm", "artificial-intelligence")
NOISE_TERMS = (
    "flashloan", "flash-loan", "mev-bot", "mev bot", "arbitrage bot",
    "crypto trading", "casino", "airdrop", "token presale",
)


def _iso_day(value: datetime) -> str:
    return value.astimezone(timezone.utc).date().isoformat()


def _request_json(url: str, timeout: int = 25, proxy: str = "") -> dict:
    headers = {
        "User-Agent": "RemotePanel/1.0",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = str(os.environ.get("GITHUB_TOKEN") or "").strip()
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return json.loads(fetch_bytes(url, timeout=timeout, proxy=proxy, headers=headers).decode("utf-8", "ignore"))


def _is_noise(item: dict) -> bool:
    haystack = " ".join(
        str(item.get(key) or "").lower()
        for key in ("name", "full_name", "description")
    )
    return any(term in haystack for term in NOISE_TERMS)


def fetch_github_ai_trending(limit: int = 4, days: int = 30, api_url: str = "", proxy: str = "") -> dict:
    """Return recently created AI repositories ranked by GitHub stars.

    GitHub does not expose stars gained per day. The transparent approximation
    used here is: created in the trailing window, tagged AI/LLM, sorted by total
    stars, merged and deduplicated across the topic searches.
    """
    since = _iso_day(datetime.now(timezone.utc) - timedelta(days=max(7, days)))
    merged: dict[str, dict] = {}
    for topic in TOPICS:
        query = f"topic:{topic} created:>={since} fork:false archived:false"
        base = (api_url or GITHUB_SEARCH_URL).split("?", 1)[0] or GITHUB_SEARCH_URL
        url = base + "?" + urllib.parse.urlencode(
            {"q": query, "sort": "stars", "order": "desc", "per_page": 12}
        )
        payload = _request_json(url, proxy=proxy)
        for raw in payload.get("items", []):
            if not isinstance(raw, dict) or _is_noise(raw):
                continue
            full_name = str(raw.get("full_name") or "").strip()
            if not full_name:
                continue
            item = {
                "full_name": full_name,
                "name": str(raw.get("name") or full_name.split("/")[-1]),
                "owner": str((raw.get("owner") or {}).get("login") or full_name.split("/")[0]),
                "description": str(raw.get("description") or "暂无项目简介").strip(),
                "stars": int(raw.get("stargazers_count") or 0),
                "forks": int(raw.get("forks_count") or 0),
                "language": str(raw.get("language") or "--"),
                "url": str(raw.get("html_url") or ""),
                "created_at": str(raw.get("created_at") or ""),
                "pushed_at": str(raw.get("pushed_at") or ""),
                "topics": [str(value) for value in (raw.get("topics") or [])[:8]],
            }
            previous = merged.get(full_name)
            if previous is None or item["stars"] > previous["stars"]:
                merged[full_name] = item
    items = sorted(merged.values(), key=lambda item: (-item["stars"], item["full_name"].lower()))[:limit]
    return {
        "source": "GitHub Search API",
        "method": f"created in trailing {days} days; AI/LLM topics; sorted by stars",
        "window_start": since,
        "items": items,
    }
