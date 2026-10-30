"""Pull an ICS subscription into schedule.json (events + to-do reminders)."""

from __future__ import annotations

import hashlib
import json
import os
import re
from datetime import datetime
from pathlib import Path

from core.http_fetch import fetch_text


def _unfold(text: str) -> str:
    return re.sub(r"\r?\n[ \t]", "", text or "")


def _unescape(value: str) -> str:
    value = str(value or "")
    value = value.replace("\\n", "\n").replace("\\N", "\n")
    value = value.replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\")
    return value.strip()


def _split_when(value: str) -> tuple[str, str]:
    raw = str(value or "").strip()
    if not raw:
        return "", ""
    if "T" in raw:
        day, tim = raw.split("T", 1)
        tim = tim.rstrip("Z")
        clock = f"{tim[:2]}:{tim[2:4]}" if len(tim) >= 4 and tim[:4].isdigit() else ""
    else:
        day, clock = raw, ""
    digits = "".join(ch for ch in day if ch.isdigit())
    if len(digits) >= 8:
        day = f"{digits[:4]}-{digits[4:6]}-{digits[6:8]}"
    else:
        day = ""
    return day, clock


def parse_ics(text: str) -> tuple[list[dict], list[dict]]:
    events: list[dict] = []
    reminders: list[dict] = []
    kind = ""
    current: dict[str, str] = {}
    for raw_line in _unfold(text).splitlines():
        line = raw_line.strip()
        if line == "BEGIN:VEVENT":
            kind, current = "event", {}
            continue
        if line == "BEGIN:VTODO":
            kind, current = "todo", {}
            continue
        if line in {"END:VEVENT", "END:VTODO"}:
            if kind == "event":
                events.append(current)
            elif kind == "todo":
                reminders.append(current)
            kind, current = "", {}
            continue
        if not kind or ":" not in line:
            continue
        key, value = line.split(":", 1)
        current[key.split(";", 1)[0].upper()] = value.strip()
    return events, reminders


def _stable_id(prefix: str, uid: str, title: str, when: str) -> str:
    token = uid.strip() or hashlib.sha1(f"{title}|{when}".encode("utf-8")).hexdigest()[:12]
    return f"{prefix}:{token}"


def events_to_items(events: list[dict], today: datetime | None = None) -> list[dict]:
    today = (today or datetime.now()).date()
    items = []
    for event in events:
        title = _unescape(event.get("SUMMARY") or "")
        if not title:
            continue
        date_str, clock = _split_when(event.get("DTSTART") or "")
        if not date_str:
            continue
        try:
            if datetime.fromisoformat(date_str).date() < today:
                continue
        except ValueError:
            continue
        notes = _unescape(event.get("DESCRIPTION") or "")
        location = _unescape(event.get("LOCATION") or "")
        if location and location not in notes:
            notes = (notes + "\n" + location).strip()
        items.append(
            {
                "id": _stable_id("ics", event.get("UID") or "", title, date_str + clock),
                "date": date_str,
                "time": clock,
                "title": title[:180],
                "notes": notes[:500],
                "priority": "medium",
                "source": "ics",
            }
        )
        if len(items) >= 40:
            break
    items.sort(key=lambda item: (item.get("date") or "", item.get("time") or "", item.get("title") or ""))
    return items


def todos_to_reminders(todos: list[dict], today: datetime | None = None) -> list[dict]:
    today = (today or datetime.now()).date()
    reminders = []
    for todo in todos:
        status = str(todo.get("STATUS") or "").upper()
        if status in {"COMPLETED", "CANCELLED"}:
            continue
        title = _unescape(todo.get("SUMMARY") or "")
        if not title:
            continue
        due, clock = _split_when(todo.get("DUE") or todo.get("DTSTART") or "")
        if due:
            try:
                if datetime.fromisoformat(due).date() < today:
                    continue
            except ValueError:
                due = ""
        reminders.append(
            {
                "id": _stable_id("todo", todo.get("UID") or "", title, due + clock),
                "title": title[:180],
                "due": due,
                "time": clock,
                "notes": _unescape(todo.get("DESCRIPTION") or "")[:500],
                "done": False,
                "source": "ics",
            }
        )
        if len(reminders) >= 20:
            break
    reminders.sort(key=lambda item: (item.get("due") or "9999-12-31", item.get("time") or "", item.get("title") or ""))
    return reminders


def sync_ics_file(schedule_path: Path, url: str, proxy: str = "") -> dict:
    """Replace previous ICS rows and keep hand-written schedule items."""
    url = str(url or "").strip()
    existing: dict = {}
    if schedule_path.exists():
        try:
            loaded = json.loads(schedule_path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                existing = loaded
        except Exception:
            existing = {}
    manual_items = [
        item for item in (existing.get("items") or [])
        if isinstance(item, dict) and not str(item.get("id") or "").startswith("ics:") and not str(item.get("source") or "") == "ics"
    ]
    manual_reminders = [
        item for item in (existing.get("reminders") or [])
        if isinstance(item, dict) and str(item.get("source") or "") != "ics"
    ]
    payload = {
        "updated_at": datetime.now().isoformat(),
        "source_url": url,
        "sync_error": "",
        "items": manual_items,
        "reminders": manual_reminders,
    }
    if not url:
        payload["items"] = manual_items
        payload["reminders"] = manual_reminders
        _write(schedule_path, payload)
        return payload
    try:
        text = fetch_text(url, timeout=25, proxy=proxy, headers={"User-Agent": "RemotePanel/1.0"})
        if "BEGIN:VCALENDAR" not in text.upper():
            raise RuntimeError("响应里没有 VCALENDAR")
        events, todos = parse_ics(text)
        payload["items"] = manual_items + events_to_items(events)
        payload["reminders"] = manual_reminders + todos_to_reminders(todos)
    except Exception as exc:
        payload["sync_error"] = str(exc)[:300]
        payload["items"] = existing.get("items") if isinstance(existing.get("items"), list) else manual_items
        payload["reminders"] = existing.get("reminders") if isinstance(existing.get("reminders"), list) else manual_reminders
    _write(schedule_path, payload)
    return payload


def _write(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(tmp, path)
