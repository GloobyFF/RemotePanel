from __future__ import annotations

import json
import re
import urllib.parse
import urllib.request
from datetime import datetime
from typing import Any


USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"


def _get_json(url: str, cookie: str = "") -> Any:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Referer": "https://www.bilibili.com/", **({"Cookie": cookie} if cookie else {})})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode("utf-8", errors="ignore"))


def _get_text(url: str, cookie: str = "") -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Referer": "https://www.bilibili.com/", **({"Cookie": cookie} if cookie else {})})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return resp.read().decode("utf-8", errors="ignore")


def fetch_bilibili_status(uid: str, cookie: str = "") -> dict[str, Any]:
    uid = str(uid).strip()
    if not uid:
        raise ValueError("请输入 B站 UID")

    card_data = _get_json(f"https://api.bilibili.com/x/web-interface/card?mid={urllib.parse.quote(uid)}&photo=true", cookie=cookie)
    card = ((card_data or {}).get("data") or {}).get("card") or {}
    account_name = str(card.get("name") or f"UID {uid}")
    followers = int(card.get("fans") or 0)

    latest_video = {"title": "暂无视频", "views": 0}
    try:
        html = _get_text(f"https://space.bilibili.com/{urllib.parse.quote(uid)}/video", cookie=cookie)
        match = re.search(r"__INITIAL_STATE__\s*=\s*(\{.*?\})\s*;\s*\(function", html, re.S)
        if match:
            state = json.loads(match.group(1))
            vlist = (((state.get("videoData") or {}).get("list") or {}).get("vlist") or [])
            if vlist:
                video = vlist[0] or {}
                latest_video = {
                    "title": str(video.get("title") or "暂无视频")[:40],
                    "views": int(video.get("play") or 0),
                }
    except Exception:
        pass

    new_replies = 0
    new_messages = 0
    if cookie.strip():
        try:
            unread = _get_json("https://api.bilibili.com/x/msgfeed/unread", cookie=cookie)
            data = (unread or {}).get("data") or {}
            new_replies = int(data.get("reply") or 0)
            new_messages = sum(int(data.get(k) or 0) for k in ("at", "like", "sys_msg", "up"))
        except Exception:
            pass

    return {
        "uid": uid,
        "account_name": account_name,
        "followers": followers,
        "new_replies": new_replies,
        "new_messages": new_messages,
        "latest_video": latest_video,
        "updated_at": datetime.now().isoformat(),
        "cookie_enabled": bool(cookie.strip()),
    }
