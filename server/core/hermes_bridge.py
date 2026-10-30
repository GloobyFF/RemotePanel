from __future__ import annotations

import json
import os
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class HermesBridge:
    def __init__(self, root: Path | str):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)

    def path(self, name: str) -> Path:
        return self.root / name

    def _read_json(self, name: str, default: Any) -> Any:
        path = self.path(name)
        if not path.exists():
            return default
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return default

    def _write_json(self, name: str, data: Any) -> None:
        path = self.path(name)
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(tmp, path)

    def notify(self, severity: str, title: str, body: str, ttl_seconds: int = 3600) -> dict[str, Any]:
        if severity not in {"critical", "warn", "info"}:
            raise ValueError("severity must be critical, warn, or info")
        inbox = self.read_inbox(include_acknowledged=True)
        msg = {
            "id": datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex[:8],
            "severity": severity,
            "title": title,
            "body": body,
            "created_at": now_iso(),
            "ttl_seconds": ttl_seconds,
            "acknowledged": False,
        }
        inbox.append(msg)
        self._write_json("inbox.json", inbox)
        return msg

    def read_inbox(self, include_acknowledged: bool = False) -> list[dict[str, Any]]:
        data = self._read_json("inbox.json", [])
        if not isinstance(data, list):
            return []
        now = datetime.now(timezone.utc)
        messages = []
        for message in data:
            if not isinstance(message, dict):
                continue
            try:
                created_at = datetime.fromisoformat(str(message.get("created_at") or "").replace("Z", "+00:00"))
                if created_at.tzinfo is None:
                    created_at = created_at.replace(tzinfo=timezone.utc)
                ttl_seconds = int(message.get("ttl_seconds") or 0)
                if ttl_seconds > 0 and (now - created_at.astimezone(timezone.utc)).total_seconds() >= ttl_seconds:
                    continue
            except (TypeError, ValueError):
                pass
            messages.append(message)
        if not include_acknowledged:
            messages = [m for m in messages if not m.get("acknowledged")]
        rank = {"critical": 0, "warn": 1, "info": 2}
        return sorted(messages, key=lambda m: (rank.get(m.get("severity", "info"), 9), m.get("created_at", "")))

    def clear_inbox(self) -> None:
        self._write_json("inbox.json", [])

    def set_daily_greeting(self, greeting: str, quote: str = "", weather_city: str = "Beijing", news_topics: list[str] | None = None) -> dict[str, Any]:
        data = {
            "date": datetime.now().strftime("%Y-%m-%d"),
            "greeting": greeting,
            "quote": quote,
            "weather_city": weather_city,
            "news_topics": news_topics or [],
            "updated_at": now_iso(),
        }
        self._write_json("daily.json", data)
        return data

    def read_daily(self) -> dict[str, Any]:
        data = self._read_json("daily.json", {})
        return data if isinstance(data, dict) else {}

    def set_work_status(self, summary: str, current_task: str = "", next_task: str = "", blocked: bool = False, blocker: str = "") -> dict[str, Any]:
        data = {
            "updated_at": now_iso(),
            "summary": summary,
            "current_task": current_task,
            "next_task": next_task,
            "blocked": blocked,
            "blocker": blocker,
        }
        self._write_json("work_status.json", data)
        return data

    def read_work_status(self) -> dict[str, Any]:
        data = self._read_json("work_status.json", {})
        return data if isinstance(data, dict) else {}

    def write_session_status(self, data: dict[str, Any]) -> dict[str, Any]:
        payload = dict(data)
        payload.setdefault("updated_at", now_iso())
        self._write_json("session_status.json", payload)
        return payload

    def read_session_status(self) -> dict[str, Any]:
        data = self._read_json("session_status.json", {})
        return data if isinstance(data, dict) else {}

    def write_content_cache(self, key: str, data: dict[str, Any]) -> dict[str, Any]:
        cache = self._read_json("content_cache.json", {})
        if not isinstance(cache, dict):
            cache = {}
        payload = dict(data)
        payload.setdefault("updated_at", now_iso())
        cache[str(key)] = payload
        self._write_json("content_cache.json", cache)
        return payload

    def read_content_cache(self, key: str) -> dict[str, Any]:
        cache = self._read_json("content_cache.json", {})
        if not isinstance(cache, dict):
            return {}
        data = cache.get(str(key), {})
        return data if isinstance(data, dict) else {}

    def read_bilibili(self) -> dict[str, Any]:
        data = self._read_json("bilibili.json", {})
        return data if isinstance(data, dict) else {}

    def write_bilibili(self, data: dict[str, Any]) -> dict[str, Any]:
        self._write_json("bilibili.json", data)
        return data

    def write_printmana(self, data: dict[str, Any]) -> dict[str, Any]:
        self._write_json("printmana.json", data)
        return data

    def read_printmana(self) -> dict[str, Any]:
        data = self._read_json("printmana.json", {})
        return data if isinstance(data, dict) else {}

    def command_switch_template(self, template_id: str, send_now: bool = True) -> dict[str, Any]:
        return self.write_command({"command": "switch_template", "template_id": template_id, "send_now": send_now})

    def write_command(self, command: dict[str, Any]) -> dict[str, Any]:
        command = dict(command)
        command.setdefault("created_at", now_iso())
        self._write_json("command.json", command)
        return command

    def read_command(self) -> dict[str, Any]:
        data = self._read_json("command.json", {})
        return data if isinstance(data, dict) else {}

    def write_state(self, **kwargs: Any) -> dict[str, Any]:
        state = self._read_json("state.json", {})
        if not isinstance(state, dict):
            state = {}
        state.update(kwargs)
        state["updated_at"] = now_iso()
        self._write_json("state.json", state)
        return state

    def read_state(self) -> dict[str, Any]:
        data = self._read_json("state.json", {})
        return data if isinstance(data, dict) else {}
