from __future__ import annotations

import json
import re
import xml.etree.ElementTree as ET
from typing import Any

from core.http_fetch import fetch_bytes


def fetch_rss_titles(url: str, limit: int = 5) -> list[str]:
    return [item["title"] if not item.get("summary") else item["title"] for item in fetch_rss_items(url, limit)]


def fetch_rss_items(url: str, limit: int = 5, proxy: str = "") -> list[dict[str, str]]:
    url = url.strip()
    if not url:
        return []
    if "hellogithub.com/rss" in url.lower():
        items = fetch_hellogithub_project_titles(url, limit, proxy=proxy)
        if items:
            return [{"title": item, "summary": "", "link": "", "image_url": ""} for item in items]
    raw = fetch_bytes(url, timeout=12, proxy=proxy, headers={"User-Agent": "RemotePanelEInkStudio/0.1"})
    root = ET.fromstring(raw)
    items: list[dict[str, str]] = []
    # RSS item/title
    for item in root.findall(".//item"):
        title = item.findtext("title") or ""
        description = item.findtext("description") or ""
        entry = build_rss_item(item, title, description)
        if entry:
            items.append(entry)
        if len(items) >= limit:
            return items
    # Atom entry/title
    ns = {"a": "http://www.w3.org/2005/Atom"}
    for entry in root.findall(".//a:entry", ns):
        title = entry.findtext("a:title", namespaces=ns) or ""
        summary = entry.findtext("a:summary", namespaces=ns) or entry.findtext("a:content", namespaces=ns) or ""
        parsed = build_rss_item(entry, title, summary)
        if parsed:
            items.append(parsed)
        if len(items) >= limit:
            return items
    return items[:limit]


def build_rss_item(node: ET.Element, title: str, description: str) -> dict[str, str]:
    clean_title = clean(title)
    clean_summary = clean(description)
    if not clean_title and not clean_summary:
        return {}
    link = clean(node.findtext("link") or "")
    if not link:
        for child in list(node):
            if child.tag.endswith("link"):
                link = clean(child.attrib.get("href", ""))
                if link:
                    break
    image_url = extract_image_url(node, description)
    if len(clean_summary) > 120:
        clean_summary = clean_summary[:119].rstrip() + "…"
    return {
        "title": clean_title or clean_summary,
        "summary": clean_summary if clean_summary != clean_title else "",
        "link": link,
        "image_url": image_url,
    }


def extract_image_url(node: ET.Element, html_text: str) -> str:
    for child in node.iter():
        tag = child.tag.lower()
        if tag.endswith("enclosure") and str(child.attrib.get("type", "")).startswith("image/"):
            return clean(child.attrib.get("url", ""))
        if tag.endswith("thumbnail") or tag.endswith("content"):
            url = child.attrib.get("url")
            if url:
                return clean(url)
    match = re.search(r'<img[^>]+src=["\']([^"\']+)["\']', html_text or "", re.I)
    return clean(match.group(1)) if match else ""


def clean(s: str) -> str:
    s = re.sub(r"<[^>]+>", "", s)
    return re.sub(r"\s+", " ", s).strip()


def combine_title_and_description(title: str, description: str) -> str:
    clean_title = clean(title)
    clean_description = clean(description)
    if not clean_title:
        return clean_description
    if not clean_description:
        return clean_title
    if re.fullmatch(r"HelloGitHub 第\s*\d+\s*期", clean_title):
        return f"{clean_title} · {clean_description}"
    return clean_title


def fetch_hellogithub_project_titles(url: str, limit: int, proxy: str = "") -> list[str]:
    raw = fetch_bytes(url, timeout=12, proxy=proxy, headers={"User-Agent": "RemotePanelEInkStudio/0.1"})
    root = ET.fromstring(raw)
    latest_link = ""
    for item in root.findall(".//item"):
        latest_link = (item.findtext("link") or "").strip()
        if latest_link:
            break
    if not latest_link:
        return []
    html = fetch_bytes(latest_link, timeout=15, proxy=proxy, headers={"User-Agent": "RemotePanelEInkStudio/0.1"}).decode("utf-8", "ignore")
    match = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', html, re.S)
    if not match:
        return []
    payload = json.loads(match.group(1))
    volume = (((payload.get("props") or {}).get("pageProps") or {}).get("volume") or {})
    data = volume.get("data") or []
    lines: list[str] = []
    for category in data:
        category_name = clean(str(category.get("category_name") or ""))
        items = category.get("items") or []
        if not items:
            continue
        item = items[0]
        name = clean(str(item.get("name") or item.get("full_name") or ""))
        description = clean(str(item.get("description") or ""))
        if len(description) > 56:
            description = description[:56].rstrip() + "…"
        if not name:
            continue
        text = f"{category_name} · {name}"
        if description:
            text = f"{text} · {description}"
        lines.append(text)
        if len(lines) >= limit:
            return lines
    return lines[:limit]
