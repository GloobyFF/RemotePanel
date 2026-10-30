from __future__ import annotations

import re
import subprocess
import tempfile
import urllib.parse
from html import unescape
from pathlib import Path

from core.gamer520 import USER_AGENT

PS5_URL = "https://2468c.com/ps5game"


def _clean(value: str) -> str:
    value = re.sub(r"<[^>]+>", "", value or "")
    return re.sub(r"\s+", " ", unescape(value)).strip()


def _fetch_html(timeout: int = 30, url: str = "", proxy: str = "") -> str:
    target = url or PS5_URL
    with tempfile.TemporaryDirectory(prefix="remote-panel-ps5-") as temp_dir:
        cookie_jar = Path(temp_dir) / "cookies.txt"
        html_path = Path(temp_dir) / "listing.html"
        base = ["curl", "--http1.1", "-L", "--max-time", str(timeout), "-A", USER_AGENT]
        if proxy:
            base.extend(["--proxy", proxy])
        subprocess.run(base + ["-c", str(cookie_jar), "-o", str(html_path), target], capture_output=True, check=False)
        result = subprocess.run(
            base + ["-b", str(cookie_jar), "-c", str(cookie_jar), "-o", str(html_path), target],
            capture_output=True, text=True, check=False,
        )
        text = html_path.read_text(encoding="utf-8", errors="ignore") if html_path.exists() else ""
    if result.returncode == 0 and re.search(r'<article[^>]+class=["\'][^"\']*post-grid', text, re.I):
        return text
    raise RuntimeError((result.stderr or "2468c PS5 challenge did not return game articles").strip())


def _download_ps5_image(url: str, destination: Path, proxy: str = "") -> str:
    destination.parent.mkdir(parents=True, exist_ok=True)
    command = ["curl", "--http1.1", "-L", "--fail", "--max-time", "30", "-A", USER_AGENT,
               "-e", "https://2468c.com/", "-o", str(destination), url]
    if proxy:
        command[1:1] = ["--proxy", proxy]
    result = subprocess.run(
        command,
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0 or not destination.exists() or destination.stat().st_size < 4096:
        destination.unlink(missing_ok=True)
        return ""
    return str(destination)


def fetch_ps5_games(limit: int = 10, image_dir: Path | None = None, url: str = "", proxy: str = "") -> dict:
    page_url = url or PS5_URL
    html = _fetch_html(url=page_url, proxy=proxy)
    articles = re.findall(
        r'<article[^>]+class="[^"]*post-grid[^"]*"[\s\S]*?</article>', html, re.I
    )
    if image_dir is not None:
        image_dir.mkdir(parents=True, exist_ok=True)
    items = []
    for index, block in enumerate(articles, 1):
        title_match = re.search(
            r'<h2[^>]+class="entry-title"[^>]*>\s*<a[^>]+href="([^"]+)"[^>]*(?:title="([^"]*)")?[^>]*>([\s\S]*?)</a>',
            block, re.I,
        )
        if not title_match:
            continue
        link = urllib.parse.urljoin(page_url, title_match.group(1))
        title = _clean(title_match.group(2) or title_match.group(3))
        image_match = re.search(r'<img[^>]+data-src="([^"]+)"', block, re.I)
        if not image_match:
            image_match = re.search(r'<img[^>]+src="([^"]+)"', block, re.I)
        image_url = urllib.parse.urljoin(page_url, image_match.group(1)) if image_match else ""
        local_path = ""
        if image_url and image_dir is not None:
            try:
                suffix = Path(urllib.parse.urlparse(image_url).path).suffix or ".jpg"
                local_path = _download_ps5_image(image_url, image_dir / f"ps5_{index}{suffix}", proxy=proxy)
            except Exception:
                pass
        if title:
            items.append({"title": title, "link": link, "image_url": image_url, "image_local_path": local_path})
        if len(items) >= limit:
            break
    if not items:
        raise RuntimeError("2468c PS5 listing parsed zero items")
    return {"source": page_url, "items": items, "lines": [item["title"] for item in items]}
