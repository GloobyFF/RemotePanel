from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


PRIVATE_CHANNEL_DOC = Path(
    "/Users/teamc/Library/Mobile Documents/com~apple~CloudDocs/PRIVATE_CHANNEL_ACCESS.md"
)
PENGUIN_QUERY = Path("/Users/teamc/Documents/penguin-balance-monitor/query.mjs")
DISABLED_CHANNEL_IDS = {"penguin"}


def _node_executable() -> str:
    candidates = [
        os.environ.get("PENGUIN_NODE", ""),
        shutil.which("node") or "",
        "/Users/teamc/local/node/bin/node",
        "/opt/homebrew/bin/node",
        "/usr/local/bin/node",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return candidate
    raise FileNotFoundError("Node.js executable not found for Penguin query")


def _money(value: Any) -> float | None:
    try:
        return round(float(value), 4)
    except (TypeError, ValueError):
        return None


def _number(data: dict[str, Any], *paths: str) -> float | None:
    for path in paths:
        value: Any = data
        for part in path.split("."):
            if not isinstance(value, dict):
                value = None
                break
            value = value.get(part)
        parsed = _money(value)
        if parsed is not None:
            return parsed
    return None


def _safe_error(exc: Exception) -> str:
    if isinstance(exc, urllib.error.HTTPError):
        return f"HTTP {exc.code}"
    if isinstance(exc, urllib.error.URLError):
        return "网络不可用"
    if isinstance(exc, subprocess.TimeoutExpired):
        return "查询超时"
    return type(exc).__name__


def _extract_private_config() -> dict[str, dict[str, str]]:
    raw = PRIVATE_CHANNEL_DOC.read_text(encoding="utf-8")
    config: dict[str, dict[str, str]] = {}
    blocks = {
        "penguin": re.search(r"## Penguin API(?P<body>.*?)(?=\n## )", raw, flags=re.S),
        "apiclaude": re.search(r"## API Claude(?P<body>.*?)(?=\n## )", raw, flags=re.S),
        "iapibox": re.search(r"## iApiBox(?P<body>.*?)(?=\n## )", raw, flags=re.S),
    }
    for channel_id, match in blocks.items():
        body = match.group("body") if match else ""
        address = re.search(r"API 地址：`([^`]+)`", body)
        api_key = re.search(r"API Key：`([^`]+)`", body)
        config[channel_id] = {
            "base_url": address.group(1).rstrip("/") if address else "",
            "api_key": api_key.group(1) if api_key else "",
        }
    return config


def _query_penguin() -> dict[str, Any]:
    result = subprocess.run(
        [_node_executable(), str(PENGUIN_QUERY)],
        cwd=str(PENGUIN_QUERY.parent),
        capture_output=True,
        text=True,
        timeout=45,
        check=True,
    )
    payload = json.loads(result.stdout)
    account = payload.get("account") if isinstance(payload.get("account"), dict) else {}
    usage = payload.get("usage") if isinstance(payload.get("usage"), dict) else {}
    return {
        "id": "penguin",
        "name": "Penguin API",
        "domain": urlparse(str(payload.get("source") or "")).netloc,
        "status": "online",
        "balance_usd": _money(account.get("balanceUsd")),
        "today_usd": _money(usage.get("todayUsd")),
        "today_status": "reported",
        "month_usd": _money(usage.get("monthUsd")),
        "total_used_usd": _money(account.get("totalUsedUsd")),
        "requests": int(account.get("requestCount") or 0),
        "tokens": None,
        "rpm": int(usage.get("rpm") or 0),
        "tpm": int(usage.get("tpm") or 0),
        "runway_days": _money(usage.get("estimatedDaysRemaining")),
        "queried_at": str(payload.get("queriedAt") or ""),
    }


def _query_v1_usage(channel_id: str, name: str, base_url: str, api_key: str) -> dict[str, Any]:
    request = urllib.request.Request(
        f"{base_url}/v1/usage",
        headers={"Authorization": f"Bearer {api_key}", "User-Agent": "RemotePanel/1.0"},
    )
    with urllib.request.urlopen(request, timeout=25) as response:
        payload = json.loads(response.read().decode("utf-8", errors="replace"))
    usage = payload.get("usage") if isinstance(payload.get("usage"), dict) else {}
    total = usage.get("total") if isinstance(usage.get("total"), dict) else {}
    today = usage.get("today") if isinstance(usage.get("today"), dict) else {}
    today_usd = _number(today, "actual_cost", "cost")
    if today_usd == 0:
        today_usd = None
    return {
        "id": channel_id,
        "name": name,
        "domain": urlparse(base_url).netloc,
        "status": "online",
        "balance_usd": _number(payload, "remaining", "balance"),
        "today_usd": today_usd,
        "today_status": "delayed" if today_usd is None else "reported",
        "month_usd": _number(usage, "month.actual_cost", "month.cost"),
        "total_used_usd": _number(total, "actual_cost", "cost"),
        "requests": int(_number(total, "requests") or 0),
        "tokens": int(_number(total, "total_tokens") or 0),
        "rpm": int(_number(usage, "rpm") or 0),
        "tpm": int(_number(usage, "tpm") or 0),
        "runway_days": None,
        "queried_at": datetime.now(timezone.utc).isoformat(),
    }


def fetch_private_channel_summary() -> dict[str, Any]:
    config = _extract_private_config()
    channels: list[dict[str, Any]] = []
    if "penguin" not in DISABLED_CHANNEL_IDS:
        try:
            channels.append(_query_penguin())
        except Exception as exc:
            channels.append({"id": "penguin", "name": "Penguin API", "domain": "penguinapi.vip", "status": "error", "error": _safe_error(exc)})

    for channel_id, name in (("apiclaude", "API Claude"), ("iapibox", "iApiBox")):
        item = config.get(channel_id, {})
        try:
            channels.append(_query_v1_usage(channel_id, name, item["base_url"], item["api_key"]))
        except Exception as exc:
            channels.append({
                "id": channel_id,
                "name": name,
                "domain": urlparse(item.get("base_url", "")).netloc,
                "status": "error",
                "error": _safe_error(exc),
            })

    def total(field: str, display_precision: int | None = None) -> float:
        values = [float(item.get(field) or 0) for item in channels]
        if display_precision is not None:
            values = [round(value, display_precision) for value in values]
        return round(sum(values), 4)

    return {
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "channels": channels,
        "totals": {
            "online": sum(item.get("status") == "online" for item in channels),
            "balance_usd": total("balance_usd", 2),
            "today_usd": total("today_usd", 2),
            "month_usd": total("month_usd", 2),
            "requests": int(total("requests")),
            "tokens": int(total("tokens")),
        },
    }
