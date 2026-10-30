from __future__ import annotations

import json
import urllib.request

DEFAULT_TRAFFIC_ENDPOINT = "https://igobeat.com/api/traffic"
DEFAULT_TRAFFIC_TOKEN = ""


def fetch_traffic(endpoint: str | None = None, token: str | None = None, timeout: int = 15) -> dict:
    endpoint = endpoint or DEFAULT_TRAFFIC_ENDPOINT
    token = token or DEFAULT_TRAFFIC_TOKEN
    req = urllib.request.Request(
        endpoint,
        headers={"Authorization": f"Bearer {token}", "User-Agent": "RemotePanelEInkStudio/0.1"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = json.loads(r.read().decode("utf-8", "ignore"))
    if not data.get("ok"):
        raise RuntimeError(f"traffic api returned not ok: {data}")
    return data


def traffic_lines(data: dict) -> list[str]:
    monthly = data.get("monthly", {})
    alert = data.get("alert", {})
    cycle = data.get("cycle", {})
    return [
        f"VPS Traffic {str(alert.get('level', 'unknown')).upper()}",
        f"Used: {monthly.get('used_human', '?')} / {monthly.get('quota_human', '?')}",
        f"Remain: {monthly.get('remaining_human', '?')}",
        f"Percent: {monthly.get('percent_used', '?')}%",
        str(alert.get("message", "")),
        f"Cycle: {short_date(cycle.get('start'))} -> {short_date(cycle.get('end'))}",
    ]


def short_date(value) -> str:
    if not value:
        return "?"
    s = str(value)
    return s[:10]
