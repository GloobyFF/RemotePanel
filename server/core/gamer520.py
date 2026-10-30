from __future__ import annotations

import os
import re
import subprocess
import urllib.parse
import urllib.request
from html import unescape
from pathlib import Path

from core.utils import download_image

USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
GAMER520_URL = "https://www.gamer520.com/pcplay"
GAMER520_SWITCH_URL = "https://www.gamer520.com/gameswitch"


def _fetch_html(url: str, timeout: int = 30, proxy: str | None = None) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Referer": "https://www.gamer520.com/",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        },
    )
    def valid_page(text: str) -> bool:
        return bool(re.search(r'<article[^>]+class=["\'][^"\']*post-grid', text or "", re.I))

    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            raw = response.read()
        direct_text = raw.decode("utf-8", "ignore")
        if valid_page(direct_text):
            return direct_text
    except Exception:
        direct_text = ""
    if proxy is None:
        proxy = str(os.environ.get("REMOTE_PANEL_FETCH_PROXY") or "").strip()
    else:
        proxy = str(proxy).strip()
    if not proxy:
        raise RuntimeError("gamer520 listing was not reachable directly, and this page is not set to use the proxy")
    command = [
        "curl", "--proxy", proxy, "--http1.1", "-L", "--max-time", str(timeout),
        "-A", USER_AGENT, "-e", "https://www.gamer520.com/", url,
    ]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0 or not result.stdout.strip() or not valid_page(result.stdout):
        message = (result.stderr or result.stdout or "failed to fetch gamer520 listing").strip()
        raise RuntimeError(message[:1000])
    return result.stdout


def _clean(text: str) -> str:
    text = re.sub(r"<[^>]+>", "", text or "")
    text = unescape(text)
    return re.sub(r"\s+", " ", text).strip()


def _pick_image(block: str, base_url: str = GAMER520_URL) -> str:
    for pattern in [
        r'<img[^>]+data-src="([^"]+)"',
        r"<img[^>]+data-src='([^']+)'",
        r'<img[^>]+src="([^"]+)"',
        r"<img[^>]+src='([^']+)'",
    ]:
        match = re.search(pattern, block, re.I)
        if match:
            value = match.group(1).strip()
            if value and not value.startswith("data:image/"):
                return urllib.parse.urljoin(base_url, value)
    return ""


def _download_image_with_proxy_fallback(url: str, dest: Path, timeout: int = 30, proxy: str | None = None) -> Path:
    """Download artwork directly first, then through the page's SOCKS route."""
    try:
        return download_image(url, dest)
    except Exception:
        if proxy is None:
            proxy = str(os.environ.get("REMOTE_PANEL_FETCH_PROXY") or "").strip()
        else:
            proxy = str(proxy).strip()
        if not proxy:
            raise
        dest.parent.mkdir(parents=True, exist_ok=True)
        result = subprocess.run(
            [
                "curl", "--proxy", proxy, "--http1.1", "-L", "--fail",
                "--max-time", str(timeout), "-A", USER_AGENT, "-o", str(dest), url,
            ],
            capture_output=True, text=True, check=False,
        )
        if result.returncode != 0 or not dest.exists() or dest.stat().st_size == 0:
            dest.unlink(missing_ok=True)
            raise RuntimeError((result.stderr or "failed to download gamer520 image").strip())
        return dest


def fetch_gamer520_listing(url: str, limit: int = 10, image_dir: Path | None = None, image_prefix: str = "gamer520", proxy: str | None = None) -> dict:
    html = _fetch_html(url, proxy=proxy)
    articles = re.findall(
        r'<article[^>]+class="[^"]*post-grid[^"]*"[\s\S]*?</article>',
        html,
        re.I,
    )
    items = []
    if image_dir is not None:
        image_dir.mkdir(parents=True, exist_ok=True)
    for index, block in enumerate(articles, 1):
        title_match = re.search(r'<h2[^>]+class="entry-title"[^>]*>\s*<a[^>]+href="([^"]+)"[^>]*title="([^"]+)"', block, re.I)
        if not title_match:
            title_match = re.search(r'<h2[^>]+class="entry-title"[^>]*>\s*<a[^>]+href="([^"]+)"[^>]*>([\s\S]*?)</a>', block, re.I)
        if not title_match:
            continue
        link = urllib.parse.urljoin(url, title_match.group(1).strip())
        title = _clean(title_match.group(2))
        if not title:
            continue
        image_url = _pick_image(block, url)
        local_path = ""
        if image_url and image_dir is not None:
            try:
                parsed = urllib.parse.urlparse(image_url)
                suffix = Path(parsed.path).suffix or ".jpg"
                local = _download_image_with_proxy_fallback(image_url, image_dir / f"{image_prefix}_{index}{suffix}", proxy=proxy)
                local_path = str(local)
            except Exception:
                local_path = ""
        items.append(
            {
                "title": title,
                "link": link,
                "image_url": image_url,
                "image_local_path": local_path,
            }
        )
        if len(items) >= limit:
            break
    if not items:
        raise RuntimeError("gamer520 listing parsed zero items; refusing to publish empty cache")
    return {
        "source": url,
        "items": items,
        "lines": [item["title"] for item in items],
    }


def fetch_gamer520_pcplay(limit: int = 10, image_dir: Path | None = None, url: str = "", proxy: str | None = None) -> dict:
    return fetch_gamer520_listing(url or GAMER520_URL, limit, image_dir, "gamer520_pc", proxy=proxy)


def fetch_gamer520_switch(limit: int = 10, image_dir: Path | None = None, url: str = "", proxy: str | None = None) -> dict:
    return fetch_gamer520_listing(url or GAMER520_SWITCH_URL, limit, image_dir, "gamer520_switch", proxy=proxy)
