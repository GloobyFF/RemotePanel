from __future__ import annotations

import json
import threading
from queue import Queue, Empty
import subprocess
import urllib.request
from datetime import datetime
from pathlib import Path
import sys
import tkinter as tk
from tkinter import messagebox, ttk

from PIL import ImageTk

# Allow running as script or bundled exe.
ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from core.config import load_config, save_config, app_dir, resource_dir
from core.hermes_bridge import HermesBridge
from core.news import fetch_rss_titles
from core.bilibili import fetch_bilibili_status
from core.project_store import load_project, save_project
from core.protocol import adb_forward, send_png, test_connection
from core.config import config_path
from core.render import PanelData, png_to_preview_image, render_panel
from core.scheduler import select_active_template
from core.layout_render import render_page
from core.movies import fetch_now_playing_movies
from core.utils import download_image, system_lines
from core.weather import fetch_weather, fetch_weekly_weather, fetch_weather_payload, fetch_weekly_weather_payload
from core.traffic import fetch_traffic, traffic_lines
from studio.designer import TemplateDesigner
from studio.file_dialogs import choose_existing_file, choose_save_file

HERMES_SESSIONS_ROOT = Path.home() / ".hermes" / "sessions"


def _compact_text(value: str, limit: int = 120) -> str:
    text = " ".join(str(value or "").split())
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "…"


def _looks_like_system_note(text: str) -> bool:
    return text.startswith("[System note:") or text.startswith("[IMPORTANT:")


def _looks_like_internal_assistant_note(text: str) -> bool:
    stripped = text.strip()
    if not stripped:
        return True
    prefixes = (
        "Need ",
        "We need ",
        "Compile and",
        "Patch ",
        "Start ",
        "Render ",
        "Add ",
        "Redesign ",
        "Inspect ",
        "Trace ",
        "[CONTEXT COMPACTION",
    )
    return stripped.startswith(prefixes)


def _looks_like_low_signal_user_text(text: str) -> bool:
    compact = " ".join(str(text or "").split()).strip()
    stripped = compact.strip("。！？!?,，~～… ").lower()
    if not stripped:
        return True
    exact_matches = {
        "继续",
        "好的",
        "好",
        "行",
        "可以",
        "ok",
        "okay",
        "收到",
        "明白",
        "非常好",
        "很好",
        "不错",
        "就这样",
        "很好就这样",
        "非常好就这样",
    }
    if stripped in exact_matches:
        return True
    low_signal_fragments = (
        "就这样",
        "继续吧",
        "继续改",
        "继续做",
        "可以了",
        "没问题",
        "挺好",
        "tool calls",
        "empty response",
        "process the tool",
    )
    if any(fragment in stripped for fragment in low_signal_fragments):
        return True
    if compact.endswith(("?", "？")) and len(compact) <= 18:
        return True
    return False


def _extract_candidate_tasks(messages: list[dict[str, str]]) -> list[str]:
    candidates: list[str] = []
    for item in messages:
        if item.get("role") != "user":
            continue
        text = " ".join(str(item.get("content") or "").split()).strip()
        if not text or _looks_like_system_note(text) or _looks_like_low_signal_user_text(text):
            continue
        if len(text) < 4:
            continue
        candidates.append(_compact_text(text, 60))
    deduped: list[str] = []
    seen: set[str] = set()
    for task in reversed(candidates):
        normalized = task.casefold()
        if normalized in seen:
            continue
        seen.add(normalized)
        deduped.append(task)
    deduped.reverse()
    return deduped


def load_latest_hermes_session_bridge_payload() -> dict[str, object]:
    sessions_index = HERMES_SESSIONS_ROOT / "sessions.json"
    if not sessions_index.exists():
        return {}
    try:
        sessions = json.loads(sessions_index.read_text())
    except Exception:
        return {}
    if not isinstance(sessions, dict) or not sessions:
        return {}
    candidates = []
    for entry in sessions.values():
        if not isinstance(entry, dict):
            continue
        updated_at = str(entry.get("updated_at") or "")
        session_id = str(entry.get("session_id") or "").strip()
        origin = entry.get("origin") or {}
        if not session_id or not updated_at:
            continue
        platform = str((origin.get("platform") if isinstance(origin, dict) else entry.get("platform")) or "")
        if platform and platform != "weixin":
            continue
        candidates.append((updated_at, session_id, entry))
    if not candidates:
        return {}
    _, session_id, entry = sorted(candidates, key=lambda item: item[0], reverse=True)[0]
    transcript_path = HERMES_SESSIONS_ROOT / f"{session_id}.jsonl"
    if not transcript_path.exists():
        transcript_path = HERMES_SESSIONS_ROOT / f"session_{session_id}.json"
    if not transcript_path.exists():
        return {}

    messages: list[dict[str, str]] = []
    if transcript_path.suffix == ".jsonl":
        try:
            for raw_line in transcript_path.read_text(errors="ignore").splitlines():
                raw_line = raw_line.strip()
                if not raw_line:
                    continue
                item = json.loads(raw_line)
                if isinstance(item, dict):
                    messages.append({"role": str(item.get("role") or ""), "content": str(item.get("content") or "")})
        except Exception:
            return {}
    else:
        try:
            payload = json.loads(transcript_path.read_text(errors="ignore"))
        except Exception:
            return {}
        for item in payload.get("messages", []) if isinstance(payload, dict) else []:
            if isinstance(item, dict):
                messages.append({"role": str(item.get("role") or ""), "content": str(item.get("content") or "")})

    meaningful_users = []
    meaningful_assistant = []
    meaningful_chat: list[dict[str, str]] = []
    for item in messages:
        role = item.get("role", "")
        text = str(item.get("content") or "").strip()
        if not text:
            continue
        if role == "user":
            if _looks_like_system_note(text):
                continue
            meaningful_users.append(text)
            meaningful_chat.append({"role": "user", "content": text})
        elif role == "assistant":
            if _looks_like_internal_assistant_note(text):
                continue
            meaningful_assistant.append(text)
            meaningful_chat.append({"role": "assistant", "content": text})

    candidate_tasks = _extract_candidate_tasks(meaningful_chat)
    user_last = _compact_text(meaningful_users[-1], 90) if meaningful_users else ""
    assistant_last = _compact_text(meaningful_assistant[-1], 110) if meaningful_assistant else ""
    if not user_last and not assistant_last:
        return {}

    recent_topics = candidate_tasks[-3:]
    recent_messages: list[dict[str, str]] = []
    pending_user: str | None = None
    rounds: list[dict[str, str]] = []
    for item in meaningful_chat:
        role = item["role"]
        content = item["content"]
        if role == "user":
            pending_user = content
        elif role == "assistant" and pending_user:
            rounds.append({"role": "user", "content": _compact_text(pending_user, 120)})
            rounds.append({"role": "assistant", "content": _compact_text(content, 120)})
            pending_user = None
    recent_messages = rounds[-4:]
    if not recent_messages:
        recent_messages = [{"role": item["role"], "content": _compact_text(item["content"], 120)} for item in meaningful_chat[-4:]]
    summary = " / ".join(recent_topics[-2:]) if recent_topics else (user_last or "最近对话")
    origin = entry.get("origin") or {}
    user_name = str((origin.get("user_name") if isinstance(origin, dict) else "") or "主人们")
    if not user_name or user_name == "o9cq803DAk-m-bnz9RJtoOAlTZrg@im.wechat":
        user_name = "主人们"
    return {
        "title": f"{user_name} × Hermes",
        "summary": summary,
        "user_last": user_last,
        "assistant_last": assistant_last,
        "tasks": recent_topics[-3:],
        "recent_messages": recent_messages,
        "updated_at": datetime.now().isoformat(),
        "session_id": session_id,
    }


def load_latest_hermes_work_status_payload() -> dict[str, object]:
    session = load_latest_hermes_session_bridge_payload()
    if not session:
        return {}
    tasks = session.get("tasks") or []
    task_list = [str(item).strip() for item in tasks if isinstance(item, str) and str(item).strip()]
    summary = str(session.get("summary") or "最近对话").strip()
    assistant_last = str(session.get("assistant_last") or "").strip()

    current_task = task_list[-1] if task_list else ""
    next_task = task_list[-2] if len(task_list) >= 2 else ""
    if not current_task:
        fallback_user_last = str(session.get("user_last") or "").strip()
        if fallback_user_last and not _looks_like_low_signal_user_text(fallback_user_last):
            current_task = _compact_text(fallback_user_last, 60)
    if next_task == current_task:
        next_task = ""

    summary_parts = [part for part in (summary, assistant_last) if part]
    compact_summary = " / ".join(summary_parts[:2]) if summary_parts else "最近对话"
    return {
        "updated_at": datetime.now().isoformat(),
        "summary": _compact_text(compact_summary, 120),
        "current_task": _compact_text(current_task, 60),
        "next_task": _compact_text(next_task, 60),
        "blocked": False,
        "blocker": "",
    }


def normalize_cookie_string(raw: str) -> str:
    text = str(raw or "").strip()
    if not text:
        return ""
    if "\t" in text and "SESSDATA" in text:
        pairs = []
        for line in text.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) >= 7:
                name = parts[5].strip()
                value = parts[6].strip()
                if name and value:
                    pairs.append(f"{name}={value}")
        if pairs:
            return "; ".join(pairs)
    return text.replace("\n", "; ").replace("\r", "; ").strip(" ;")


def build_hourly_greeting(now: datetime, news_titles: list[str]) -> tuple[str, str, list[str]]:
    hour = now.hour
    if hour < 6:
        greeting = "夜深了，慢一点也没关系"
    elif hour < 9:
        greeting = "先把第一件关键事推进掉"
    elif hour < 12:
        greeting = "上午适合把主线往前顶"
    elif hour < 14:
        greeting = "中段稳住节奏，别被打断"
    elif hour < 18:
        greeting = "下午继续清掉最重的块"
    else:
        greeting = "今天也稳稳收束一段进度"
    topics: list[str] = []
    if news_titles:
        top = str(news_titles[0]).strip()
        compact = top.replace("—", " ").replace("-", " ").replace("/", " ")[:22]
        greeting = f"{greeting}\n{compact}"
        topics = [t[:28] for t in news_titles[:3]]
    quote = f"{now.strftime('%H:%M')} 刷新 / 每小时联动新闻"
    return greeting, quote, topics


REFRESH_OPTIONS = [
    ("不刷新", 0),
    ("1分钟", 1),
    ("1小时", 60),
    ("1天", 1440),
]
REFRESH_LABEL_TO_MINUTES = {label: minutes for label, minutes in REFRESH_OPTIONS}
REFRESH_MINUTES_TO_LABEL = {minutes: label for label, minutes in REFRESH_OPTIONS}
DWELL_OPTIONS = [
    ("10秒", 10),
    ("20秒", 20),
    ("30秒", 30),
    ("1分钟", 60),
    ("2分钟", 120),
    ("5分钟", 300),
]
DWELL_LABEL_TO_SECONDS = {label: seconds for label, seconds in DWELL_OPTIONS}
DWELL_SECONDS_TO_LABEL = {seconds: label for label, seconds in DWELL_OPTIONS}


class StudioApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Remote Panel E-Ink Studio")
        self.geometry("980x760")
        self.minsize(900, 680)
        self.cfg = load_config()
        self.preview_png: bytes | None = None
        self.preview_photo = None
        self.downloaded_image: Path | None = None
        self.status_queue: Queue[str] = Queue()
        self.ui_queue: Queue[callable] = Queue()
        self.printmana_timeout_job: str | None = None
        self.auto_send_job: str | None = None
        self.template_auto_job: str | None = None
        self.content_refresh_job: str | None = None
        self.template_designer: TemplateDesigner | None = None
        self.project_path = resource_dir() / "projects" / "default.project.json"
        self.bridge = HermesBridge(config_path().parent / "hermes_bridge")
        self.project = load_project(self.project_path)
        self.template_map: dict[str, object] = {}
        self.template_preview_active = False
        self.template_enable_vars: dict[str, tk.BooleanVar] = {}
        self.template_summary_var = tk.StringVar(value="模板摘要加载中")
        self.template_refresh_vars: dict[str, tk.StringVar] = {}
        self.template_dwell_vars: dict[str, tk.StringVar] = {}
        self.template_refresh_job: str | None = None
        self.template_manager_window: tk.Toplevel | None = None
        self.template_manager_container: ttk.Frame | None = None
        self.style = ttk.Style(self)
        self._configure_styles()
        self.preview_render_job: str | None = None
        self._build_ui()
        self._load_cfg_to_fields()
        self.refresh_template_choices()
        self.render_preview()
        self.after(150, self._flush_status_queue)
        self.after(300, self.auto_connect)
        self.after(400, self.apply_default_pane_ratio)
        self.after(1200, self.startup_send_template_if_enabled)
        self.after(1600, self.start_template_automation_if_enabled)
        self.after(1800, self.start_template_refresh_loop)
        self.after(2000, self.start_auto_send_if_enabled)
        self.after(2500, self.start_hourly_refresh)

    def _configure_styles(self):
        try:
            self.style.theme_use("clam")
        except Exception:
            pass
        self.style.configure("TFrame", background="#eef2f7")
        self.style.configure("Card.TFrame", background="#ffffff")
        self.style.configure("TLabel", background="#eef2f7", foreground="#18212f")
        self.style.configure("Card.TLabel", background="#ffffff", foreground="#18212f")
        self.style.configure("Hero.TLabel", background="#eef2f7", foreground="#102033", font=("Arial", 18, "bold"))
        self.style.configure("SubHero.TLabel", background="#eef2f7", foreground="#607089", font=("Arial", 10))
        self.style.configure("TLabelframe", background="#eef2f7", borderwidth=0)
        self.style.configure("TLabelframe.Label", background="#eef2f7", foreground="#22324a", font=("Arial", 11, "bold"))
        self.style.configure("AccentPrimary.TButton", font=("Arial", 11, "bold"), padding=(14, 10), foreground="#ffffff", background="#3056f5", borderwidth=0)
        self.style.map("AccentPrimary.TButton", background=[("active", "#2347d8")])
        self.style.configure("AccentSecondary.TButton", font=("Arial", 11, "bold"), padding=(14, 10), foreground="#1d2d44", background="#dbe7ff", borderwidth=0)
        self.style.map("AccentSecondary.TButton", background=[("active", "#c9dbff")])
        self.style.configure("Ghost.TButton", font=("Arial", 10, "bold"), padding=(12, 8), foreground="#2f4f8f", background="#f2f6ff", borderwidth=0)
        self.style.map("Ghost.TButton", background=[("active", "#e7efff")])

    def _build_ui(self):
        self.configure(bg="#eef2f7")
        self.columnconfigure(0, weight=1)
        self.rowconfigure(0, weight=1)
        paned = ttk.PanedWindow(self, orient=tk.HORIZONTAL)
        paned.grid(row=0, column=0, sticky="nsew")
        self.main_paned = paned

        left_shell = ttk.Frame(paned, style="TFrame")
        right = ttk.Frame(paned, padding=10, style="TFrame")
        paned.add(left_shell, weight=2)
        paned.add(right, weight=1)

        left_canvas = tk.Canvas(left_shell, highlightthickness=0)
        left_scrollbar = ttk.Scrollbar(left_shell, orient=tk.VERTICAL, command=left_canvas.yview)
        left_canvas.configure(yscrollcommand=left_scrollbar.set)
        left_scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        left_canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        left = ttk.Frame(left_canvas, padding=10, style="TFrame")
        left_window = left_canvas.create_window((0, 0), window=left, anchor="nw")

        def _sync_left_scroll(_event=None):
            left_canvas.configure(scrollregion=left_canvas.bbox("all"))
            left_canvas.itemconfigure(left_window, width=left_canvas.winfo_width())

        left.bind("<Configure>", _sync_left_scroll)
        left_canvas.bind("<Configure>", _sync_left_scroll)

        def _on_left_mousewheel(event):
            delta = event.delta
            if delta:
                left_canvas.yview_scroll(int(-delta / 120), "units")

        left_canvas.bind("<Enter>", lambda _e: left_canvas.bind_all("<MouseWheel>", _on_left_mousewheel))
        left_canvas.bind("<Leave>", lambda _e: left_canvas.unbind_all("<MouseWheel>"))

        # Device frame
        dev = ttk.LabelFrame(left, text="设备基础设置", padding=8)
        dev.pack(fill=tk.X, pady=4)
        self.host = tk.StringVar()
        self.port = tk.StringVar()
        self.width_var = tk.StringVar()
        self.height_var = tk.StringVar()
        self.image_id = tk.StringVar()
        self.font_path = tk.StringVar()
        self.threshold = tk.StringVar()
        self.rotate_send = tk.BooleanVar(value=False)
        self.auto_send_enabled = tk.BooleanVar(value=False)
        self.auto_send_interval = tk.StringVar(value="20")
        self.startup_send_selected_template = tk.BooleanVar(value=True)
        self._row(dev, 0, "IP", ttk.Entry(dev, textvariable=self.host, width=18), "端口", ttk.Entry(dev, textvariable=self.port, width=8), "Image ID", ttk.Entry(dev, textvariable=self.image_id, width=4))
        self._row(dev, 1, "宽", ttk.Entry(dev, textvariable=self.width_var, width=8), "高", ttk.Entry(dev, textvariable=self.height_var, width=8), "阈值", ttk.Entry(dev, textvariable=self.threshold, width=6))
        dev.columnconfigure(4, weight=1)
        btns = ttk.Frame(dev)
        btns.grid(row=2, column=0, columnspan=6, sticky="ew", pady=4)
        ttk.Button(btns, text="测试连接", command=self.test_conn).pack(side=tk.LEFT, padx=4)
        ttk.Button(btns, text="USB转发", command=self.enable_usb_forward).pack(side=tk.LEFT, padx=4)
        ttk.Button(btns, text="自动连接", command=self.auto_connect).pack(side=tk.LEFT, padx=4)
        ttk.Button(btns, text="保存当前配置", command=self.save_fields).pack(side=tk.LEFT, padx=4)
        ttk.Button(btns, text="发送连接测试页", command=self.send_connection_test_page, style="Ghost.TButton").pack(side=tk.LEFT, padx=4)

        auto = ttk.Frame(dev)
        auto.grid(row=3, column=0, columnspan=6, sticky="ew", pady=4)
        ttk.Checkbutton(auto, text="发送旋转180°", variable=self.rotate_send, command=self.save_fields).pack(side=tk.LEFT, padx=4)
        ttk.Checkbutton(auto, text="自动重发/保活", variable=self.auto_send_enabled, command=self.on_auto_send_toggle).pack(side=tk.LEFT, padx=4)
        ttk.Checkbutton(auto, text="启动后自动发送", variable=self.startup_send_selected_template, command=self.save_fields).pack(side=tk.LEFT, padx=4)
        ttk.Label(auto, text="间隔秒").pack(side=tk.LEFT, padx=4)
        ttk.Entry(auto, textvariable=self.auto_send_interval, width=6).pack(side=tk.LEFT, padx=4)

        content_box = ttk.LabelFrame(left, text="板块信息设置", padding=10)
        content_box.pack(fill=tk.X, pady=4)
        info_hint = ttk.Label(content_box, text="配置模板中各信息板块的数据来源与账号状态", style="SubHero.TLabel")
        info_hint.grid(row=0, column=0, columnspan=3, sticky="w", padx=4, pady=(0, 8))

        custom_box = ttk.Frame(content_box)
        custom_box.grid(row=1, column=0, columnspan=3, sticky="ew", pady=4)
        self.weather_city = tk.StringVar()
        self.rss_url = tk.StringVar()
        self.printmana_api = tk.StringVar()
        self.bili_uid = tk.StringVar()
        self.bili_cookie = tk.StringVar()
        ttk.Label(custom_box, text="天气城市").grid(row=0, column=0, sticky="w")
        ttk.Entry(custom_box, textvariable=self.weather_city, width=18).grid(row=0, column=1, sticky="ew", padx=4)
        ttk.Button(custom_box, text="取天气", command=self.fetch_weather_async).grid(row=0, column=2, padx=4)
        ttk.Label(custom_box, text="RSS").grid(row=1, column=0, sticky="w")
        ttk.Entry(custom_box, textvariable=self.rss_url).grid(row=1, column=1, sticky="ew", padx=4)
        ttk.Button(custom_box, text="取新闻", command=self.fetch_news_async).grid(row=1, column=2, padx=4)
        ttk.Label(custom_box, text="PrintMana API").grid(row=2, column=0, sticky="w")
        ttk.Entry(custom_box, textvariable=self.printmana_api).grid(row=2, column=1, sticky="ew", padx=4)
        ttk.Button(custom_box, text="测试打印机", command=self.fetch_printmana_async).grid(row=2, column=2, padx=4)
        ttk.Button(custom_box, text="立即刷新全部板块", command=self.refresh_all_sections_now, style="Ghost.TButton").grid(row=3, column=0, columnspan=3, sticky="w", pady=(8, 0))
        custom_box.columnconfigure(1, weight=1)

        bili = ttk.LabelFrame(content_box, text="B站板块", padding=10)
        bili.grid(row=2, column=0, columnspan=3, sticky="ew", pady=8)
        self.bili_status = tk.StringVar(value="未连接")
        self.bili_account = tk.StringVar(value="")
        ttk.Label(bili, text="连接状态").grid(row=0, column=0, sticky="w")
        ttk.Label(bili, textvariable=self.bili_status).grid(row=0, column=1, sticky="w", padx=4)
        ttk.Label(bili, text="当前账号").grid(row=1, column=0, sticky="w")
        ttk.Label(bili, textvariable=self.bili_account).grid(row=1, column=1, sticky="w", padx=4)
        ttk.Label(bili, text="UID").grid(row=2, column=0, sticky="w")
        ttk.Entry(bili, textvariable=self.bili_uid).grid(row=2, column=1, sticky="ew", padx=4)
        ttk.Label(bili, text="Cookie").grid(row=3, column=0, sticky="w")
        ttk.Entry(bili, textvariable=self.bili_cookie, show="*").grid(row=3, column=1, sticky="ew", padx=4)
        bili_btns = ttk.Frame(bili)
        bili_btns.grid(row=4, column=0, columnspan=3, sticky="w", pady=4)
        ttk.Button(bili_btns, text="保存B站配置", command=self.save_fields).pack(side=tk.LEFT, padx=4)
        ttk.Button(bili_btns, text="剪贴板导入Cookie", command=self.bili_import_cookie_clipboard).pack(side=tk.LEFT, padx=4)
        ttk.Button(bili_btns, text="文件导入Cookie", command=self.bili_import_cookie_file).pack(side=tk.LEFT, padx=4)
        ttk.Button(bili_btns, text="读取B站", command=self.fetch_bili_async).pack(side=tk.LEFT, padx=4)
        ttk.Button(bili_btns, text="刷新状态", command=self.bili_refresh_status).pack(side=tk.LEFT, padx=4)
        ttk.Button(bili_btns, text="清空B站数据", command=self.bili_logout_placeholder).pack(side=tk.LEFT, padx=4)
        bili.columnconfigure(1, weight=1)

        self.content_status_var = tk.StringVar(value="天气/新闻/打印机/B站状态待刷新")
        ttk.Label(content_box, textvariable=self.content_status_var, style="Card.TLabel", justify=tk.LEFT, anchor="w").grid(row=3, column=0, columnspan=3, sticky="ew", padx=4, pady=(2, 0))
        content_box.columnconfigure(1, weight=1)

        template_box = ttk.LabelFrame(left, text="模板设计和轮播管理", padding=10)
        template_box.pack(fill=tk.X, expand=False, pady=4)
        self.selected_template_id = tk.StringVar()
        self.template_auto_enabled = tk.BooleanVar(value=False)
        self.template_auto_interval = tk.StringVar(value="30")
        self.template_auto_rotate = tk.BooleanVar(value=False)
        hero_row = ttk.Frame(template_box)
        hero_row.grid(row=0, column=0, columnspan=4, sticky="ew", pady=(2, 6))
        ttk.Button(hero_row, text="模板设计", command=self.open_template_designer, style="AccentSecondary.TButton").pack(side=tk.LEFT, padx=4)
        ttk.Button(hero_row, text="管理模板", command=self.open_template_manager, style="AccentPrimary.TButton").pack(side=tk.LEFT, padx=4)

        pick_row = ttk.Frame(template_box)
        pick_row.grid(row=1, column=0, columnspan=4, sticky="ew", pady=2)
        ttk.Label(pick_row, text="当前模板").pack(side=tk.LEFT, padx=4)
        self.template_combo = ttk.Combobox(pick_row, state="readonly", width=28, textvariable=self.selected_template_id)
        self.template_combo.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=4)
        self.template_combo.bind("<<ComboboxSelected>>", lambda e: self.on_home_template_change())
        ttk.Button(pick_row, text="刷新模板", command=self.reload_project_templates, style="Ghost.TButton").pack(side=tk.LEFT, padx=4)

        action_row = ttk.Frame(template_box)
        action_row.grid(row=2, column=0, columnspan=4, sticky="ew", pady=2)
        ttk.Button(action_row, text="发送当前模板", command=self.send_selected_template, style="Ghost.TButton").pack(side=tk.LEFT, padx=4)
        ttk.Button(action_row, text="发送当前时段模板", command=self.send_active_scheduled_template, style="Ghost.TButton").pack(side=tk.LEFT, padx=4)
        ttk.Button(action_row, text="保存模板调度设置", command=self.save_template_plan, style="Ghost.TButton").pack(side=tk.LEFT, padx=4)

        auto_row = ttk.Frame(template_box)
        auto_row.grid(row=3, column=0, columnspan=4, sticky="ew", pady=2)
        ttk.Checkbutton(auto_row, text="自动按时切换模板", variable=self.template_auto_enabled, command=self.toggle_template_automation).pack(side=tk.LEFT, padx=4)
        ttk.Checkbutton(auto_row, text="轮播启用模板", variable=self.template_auto_rotate, command=self.save_fields).pack(side=tk.LEFT, padx=4)
        ttk.Label(auto_row, text="检查秒").pack(side=tk.LEFT, padx=4)
        ttk.Entry(auto_row, textvariable=self.template_auto_interval, width=6).pack(side=tk.LEFT, padx=4)

        self.template_status = tk.StringVar(value="未启用模板自动化")
        ttk.Label(template_box, textvariable=self.template_status).grid(row=4, column=0, columnspan=4, sticky="w", padx=4, pady=3)
        template_box.columnconfigure(0, weight=1)

        actions = ttk.Frame(left)
        actions.pack(fill=tk.X, pady=8)
        ttk.Button(actions, text="预览当前内容", command=self.render_preview, style="Ghost.TButton").pack(side=tk.LEFT, padx=4)
        ttk.Button(actions, text="发送当前预览", command=self.send_current, style="AccentPrimary.TButton").pack(side=tk.LEFT, padx=4)
        ttk.Button(actions, text="导出 PNG", command=self.save_png, style="Ghost.TButton").pack(side=tk.LEFT, padx=4)

        # Preview
        ttk.Label(right, text="黑白预览", font=("Arial", 14, "bold")).pack(anchor="w")
        self.preview_label = ttk.Label(right, relief=tk.SUNKEN, anchor="center")
        self.preview_label.pack(fill=tk.BOTH, expand=True, pady=8)
        self.log = tk.Text(right, height=10, wrap=tk.WORD)
        self.log.pack(fill=tk.X)
        self.status("Ready")

        self.weather_lines: list[str] = []
        self.news_lines: list[str] = []

    def _row(self, parent, row, *items):
        col = 0
        for item in items:
            if isinstance(item, str):
                ttk.Label(parent, text=item).grid(row=row, column=col, sticky="w", padx=4, pady=3)
            else:
                item.grid(row=row, column=col, sticky="ew", padx=4, pady=3)
            col += 1

    def _load_cfg_to_fields(self):
        c = self.cfg

        def safe_int_string(value, fallback: int, minimum: int | None = None) -> str:
            try:
                parsed = int(str(value).strip())
            except (TypeError, ValueError):
                parsed = fallback
            if minimum is not None:
                parsed = max(minimum, parsed)
            return str(parsed)

        self.host.set(str(c.get("host") or "127.0.0.1"))
        self.port.set(safe_int_string(c.get("port"), 38000, 1))
        self.width_var.set(safe_int_string(c.get("width"), 600, 1))
        self.height_var.set(safe_int_string(c.get("height"), 800, 1))
        self.image_id.set(safe_int_string(c.get("image_id"), 0, 0))
        self.font_path.set(str(c.get("font_path", "")))
        self.threshold.set(safe_int_string(c.get("threshold"), 128, 0))
        self.weather_city.set(str(c.get("weather_city", "Beijing")))
        self.rss_url.set(str(c.get("rss_url", "https://hnrss.org/frontpage")))
        self.printmana_api.set(str(c.get("printmana_api", "http://192.168.28.126:8088/api/printers")))
        self.rotate_send.set(bool(c.get("rotate_send", False)))
        self.auto_send_enabled.set(bool(c.get("auto_send_enabled", False)))
        self.auto_send_interval.set(safe_int_string(c.get("auto_send_interval"), 20, 5))
        self.selected_template_id.set(str(c.get("selected_template_id", "")))
        self.startup_send_selected_template.set(bool(c.get("startup_send_selected_template", True)))
        self.template_auto_enabled.set(bool(c.get("template_auto_enabled", False)))
        self.template_auto_interval.set(str(c.get("template_auto_interval", 30)))
        self.template_auto_rotate.set(bool(c.get("template_auto_rotate", False)))
        self.bili_uid.set(str(c.get("bili_uid", "")))
        self.bili_cookie.set(str(c.get("bili_cookie", "")))
        self.bili_refresh_status()
        self.refresh_content_status_summary()

    def apply_default_pane_ratio(self):
        try:
            self.update_idletasks()
            total_width = self.main_paned.winfo_width()
            if total_width <= 1:
                total_width = self.winfo_width()
            sash_x = max(300, int(total_width * 2 / 3))
            self.main_paned.sashpos(0, sash_x)
        except Exception as e:
            self.status(f"默认分栏比例设置失败：{e}")

    def current_cfg(self) -> dict:
        cfg = dict(self.cfg)

        def parse_int(value: str, fallback: int, minimum: int | None = None) -> int:
            try:
                parsed = int(str(value).strip())
            except (TypeError, ValueError):
                parsed = fallback
            if minimum is not None:
                parsed = max(minimum, parsed)
            return parsed

        cfg.update({
            "host": self.host.get().strip() or str(cfg.get("host", "127.0.0.1")),
            "port": parse_int(self.port.get(), int(cfg.get("port", 38000)), 1),
            "width": parse_int(self.width_var.get(), int(cfg.get("width", 600)), 1),
            "height": parse_int(self.height_var.get(), int(cfg.get("height", 800)), 1),
            "image_id": parse_int(self.image_id.get(), int(cfg.get("image_id", 0)), 0),
            "font_path": self.font_path.get().strip(),
            "threshold": parse_int(self.threshold.get(), int(cfg.get("threshold", 128)), 0),
            "weather_city": self.weather_city.get().strip(),
            "rss_url": self.rss_url.get().strip(),
            "printmana_api": self.printmana_api.get().strip(),
            "rotate_send": bool(self.rotate_send.get()),
            "auto_send_enabled": bool(self.auto_send_enabled.get()),
            "auto_send_interval": parse_int(self.auto_send_interval.get(), int(cfg.get("auto_send_interval", 20)), 5),
            "selected_template_id": self.selected_template_id.get().strip(),
            "startup_send_selected_template": bool(self.startup_send_selected_template.get()),
            "template_auto_enabled": bool(self.template_auto_enabled.get()),
            "template_auto_interval": parse_int(self.template_auto_interval.get(), int(cfg.get("template_auto_interval", 30)), 10),
            "template_auto_rotate": bool(self.template_auto_rotate.get()),
            "bili_uid": self.bili_uid.get().strip(),
            "bili_cookie": self.bili_cookie.get().strip(),
        })
        return cfg

    def panel_data(self) -> PanelData:
        city = self.weather_city.get().strip() or "天气"
        rss_host = self.rss_url.get().strip() or "未配置 RSS"
        body_lines = [
            f"天气城市：{city}",
            f"RSS：{rss_host}",
            f"PrintMana：{self.printmana_api.get().strip() or '未配置'}",
            f"B站：{self.bili_account.get().strip() or self.bili_status.get().strip() or '未连接'}",
        ]
        status_lines = [f"设备 {self.host.get().strip() or '127.0.0.1'}:{self.port.get().strip() or '38000'}"]
        return PanelData(
            title="Remote Panel E-Ink Studio",
            body="\n".join(body_lines),
            footer=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            status_lines=status_lines,
            weather_lines=self.weather_lines,
            news_lines=self.news_lines,
            image_path=None,
        )

    def get_selected_template(self):
        template_id = self.selected_template_id.get().strip()
        if template_id and template_id in self.template_map:
            return self.template_map[template_id]
        combo_value = self.template_combo.get().strip()
        if combo_value:
            guessed_id = combo_value.split(" - ", 1)[0].strip()
            if guessed_id in self.template_map:
                self.selected_template_id.set(guessed_id)
                return self.template_map[guessed_id]
        templates = getattr(self.project, "templates", [])
        if templates:
            fallback = templates[0]
            self.selected_template_id.set(fallback.id)
            return fallback
        return None

    def render_selected_template_preview(self):
        template = self.get_selected_template()
        if not template or not template.pages:
            return False
        cfg = self.current_cfg()
        self.project.device.host = cfg["host"]
        self.project.device.port = cfg["port"]
        self.project.device.width = cfg["width"]
        self.project.device.height = cfg["height"]
        self.project.device.threshold = cfg["threshold"]
        self.project.global_style.font_path = cfg["font_path"]
        page = template.pages[0]
        self.preview_png = render_page(page, self.project.device, self.project.global_style, bridge=self.bridge, live_data=False)
        preview = png_to_preview_image(self.preview_png, (360, 520))
        self.preview_photo = ImageTk.PhotoImage(preview)
        self.preview_label.configure(image=self.preview_photo)
        self.template_status.set(f"预览模板：{template.id} - {template.name}")
        self.status(f"模板预览已生成：{template.id}/{page.name}，{len(self.preview_png)} bytes")
        return True

    def render_preview(self):
        try:
            if self.render_selected_template_preview():
                return
            cfg = self.current_cfg()
            self.preview_png = render_panel(self.panel_data(), cfg)
            preview = png_to_preview_image(self.preview_png, (360, 520))
            self.preview_photo = ImageTk.PhotoImage(preview)
            self.preview_label.configure(image=self.preview_photo)
            self.status(f"预览已生成：{cfg['width']}x{cfg['height']}，{len(self.preview_png)} bytes")
        except Exception as e:
            messagebox.showerror("预览失败", str(e))

    def request_preview_render(self, delay_ms: int = 120):
        if self.preview_render_job:
            try:
                self.after_cancel(self.preview_render_job)
            except Exception:
                pass
        self.preview_render_job = self.after(delay_ms, self._run_requested_preview)

    def _run_requested_preview(self):
        self.preview_render_job = None
        self.render_preview()

    def send_current(self, show_errors: bool = True):
        self.render_preview()
        if not self.preview_png:
            return False
        cfg = self.current_cfg()
        try:
            png_bytes = self.preview_png
            if self.rotate_send.get():
                import io
                from PIL import Image
                image = Image.open(io.BytesIO(self.preview_png))
                rotated = image.rotate(180, expand=True)
                output = io.BytesIO()
                rotated.save(output, format="PNG")
                png_bytes = output.getvalue()
            sent = self.send_png_with_auto_recover(cfg["host"], cfg["port"], png_bytes, cfg["image_id"], context="当前页发送")
            self.bridge.write_state(
                last_sent_at=datetime.now().isoformat(),
                active_template_id="",
                active_pages=[cfg["image_id"]],
                device_online=True,
                last_error="",
            )
            self.status(f"已发送 {sent} bytes 到 {cfg['host']}:{cfg['port']}")
            return True
        except Exception as e:
            if show_errors:
                messagebox.showerror("发送失败", str(e))
            self.status(f"发送失败：{e}")
            return False

    def build_connection_test_panel(self, text: str) -> PanelData:
        now = datetime.now()
        return PanelData(
            title="Remote Panel E-Ink Studio",
            body=text,
            footer=now.strftime("%Y-%m-%d %H:%M:%S"),
            status_lines=["连接测试", f"目标 {self.host.get().strip() or '127.0.0.1'}:{self.port.get().strip() or '38000'}"],
            weather_lines=[],
            news_lines=[],
            image_path=None,
        )

    def send_connection_test_page(self):
        cfg = self.current_cfg()
        try:
            panel = self.build_connection_test_panel("你好，Remote Panel E-Ink Studio 已连接")
            png_bytes = render_panel(panel, cfg)
            if self.rotate_send.get():
                import io
                from PIL import Image
                image = Image.open(io.BytesIO(png_bytes))
                rotated = image.rotate(180, expand=True)
                output = io.BytesIO()
                rotated.save(output, format="PNG")
                png_bytes = output.getvalue()
            sent = self.send_png_with_auto_recover(cfg["host"], cfg["port"], png_bytes, cfg["image_id"], context="连接测试页发送")
            self.preview_png = png_bytes
            preview = png_to_preview_image(self.preview_png, (360, 520))
            self.preview_photo = ImageTk.PhotoImage(preview)
            self.preview_label.configure(image=self.preview_photo)
            self.bridge.write_state(
                last_sent_at=datetime.now().isoformat(),
                active_template_id="",
                active_pages=[cfg["image_id"]],
                device_online=True,
                last_error="",
            )
            self.status(f"测试页已发送 {sent} bytes 到 {cfg['host']}:{cfg['port']}")
            return True
        except Exception as e:
            messagebox.showerror("测试页发送失败", str(e))
            self.status(f"测试页发送失败：{e}")
            return False

    def open_template_designer(self):
        if self.template_designer and self.template_designer.winfo_exists():
            self.template_designer.deiconify()
            self.template_designer.lift()
            self.template_designer.focus_force()
            return
        self.template_designer = TemplateDesigner(self, self.current_cfg())
        self.template_designer.protocol("WM_DELETE_WINDOW", self.close_template_designer)
        self.template_designer.lift()
        self.template_designer.focus_force()

    def close_template_designer(self):
        if self.template_designer and self.template_designer.winfo_exists():
            self.template_designer.destroy()
        self.template_designer = None

    def test_conn(self):
        cfg = self.current_cfg()
        try:
            ok = self.test_connection_with_auto_recover(cfg["host"], cfg["port"])
            self.status("连接成功" if ok else "连接失败")
        except Exception as e:
            messagebox.showerror("连接失败", str(e))
            self.status(f"连接失败：{e}")

    def ensure_usb_debug_bridge(self) -> tuple[bool, str]:
        adb_ok, adb_info = self.detect_adb_device()
        if not adb_ok:
            return False, adb_info or "未检测到 ADB 设备"
        cfg = self.current_cfg()
        target_port = int(cfg["port"])
        try:
            adb_forward(target_port, target_port)
        except Exception as first_error:
            try:
                subprocess.run(["adb", "forward", "--remove", f"tcp:{target_port}"], check=False, capture_output=True, text=True)
                adb_forward(target_port, target_port)
            except Exception as second_error:
                return False, f"{adb_info} / forward失败: {second_error or first_error}"
        self.host.set("127.0.0.1")
        self.cfg["host"] = "127.0.0.1"
        try:
            self.save_fields()
        except Exception:
            pass
        return True, adb_info

    def test_connection_with_auto_recover(self, host: str, port: int) -> bool:
        try:
            return test_connection(host, port)
        except Exception as first_error:
            should_retry = host in {"127.0.0.1", "localhost"}
            if not should_retry:
                raise
            self.status(f"连接检查失败，尝试自动恢复 USB 调试/转发：{first_error}")
            ok, info = self.ensure_usb_debug_bridge()
            if not ok:
                raise RuntimeError(f"连接失败，且自动恢复 USB 调试未成功：{info}") from first_error
            self.status("已自动重建 USB 转发，重试连接中")
            return test_connection("127.0.0.1", port)

    def send_png_with_auto_recover(self, host: str, port: int, png_bytes: bytes, image_id: int, context: str = "发送") -> int:
        try:
            return send_png(host, port, png_bytes, image_id)
        except Exception as first_error:
            should_retry = host in {"127.0.0.1", "localhost"}
            if not should_retry:
                raise
            self.status(f"{context}失败，尝试自动恢复 USB 调试/转发：{first_error}")
            ok, info = self.ensure_usb_debug_bridge()
            if not ok:
                raise RuntimeError(f"{context}失败，且自动恢复 USB 调试未成功：{info}") from first_error
            self.status(f"{context}：已自动重建 USB 转发，重试一次")
            return send_png("127.0.0.1", port, png_bytes, image_id)

    def reload_project_templates(self):
        self.project = load_project(self.project_path)
        self.refresh_template_choices()
        self.status("模板项目已刷新")

    def refresh_template_choices(self):
        templates = getattr(self.project, "templates", [])
        self.template_map = {t.id: t for t in templates}
        values = [f"{t.id} - {t.name}" for t in templates]
        self.template_combo["values"] = values
        self.refresh_template_enable_list()
        preferred = self.selected_template_id.get().strip() or str(self.cfg.get("selected_template_id", ""))
        target_index = -1
        if preferred:
            for index, template in enumerate(templates):
                if template.id == preferred:
                    target_index = index
                    break
        if target_index < 0 and templates:
            try:
                active = select_active_template(self.project)
                for index, template in enumerate(templates):
                    if template.id == active.id:
                        target_index = index
                        break
            except Exception:
                target_index = 0 if templates else -1
        if target_index >= 0:
            self.template_combo.current(target_index)
            self.selected_template_id.set(templates[target_index].id)
            self.template_preview_active = False
            self.template_status.set(f"当前模板：{templates[target_index].id} - {templates[target_index].name}")
        else:
            self.selected_template_id.set("")
            self.template_status.set("未找到模板")

    def on_home_template_change(self):
        combo_value = self.template_combo.get().strip()
        guessed_id = combo_value.split(" - ", 1)[0].strip() if combo_value else ""
        template = self.template_map.get(guessed_id)
        if template:
            self.template_preview_active = True
            self.selected_template_id.set(template.id)
            self.template_status.set(f"当前模板：{template.id} - {template.name}")
            self.save_fields()
            self.request_preview_render()

    def refresh_template_enable_list(self):
        self.template_summary_var.set(self.build_template_summary())
        if not self.template_manager_container:
            return
        for child in self.template_manager_container.winfo_children():
            child.destroy()
        self.template_enable_vars = {}
        self.template_refresh_vars = {}
        self.template_dwell_vars = {}
        templates = getattr(self.project, "templates", [])
        if not templates:
            ttk.Label(self.template_manager_container, text="暂无模板").pack(anchor="w", padx=4, pady=4)
            return
        header = ttk.Frame(self.template_manager_container)
        header.pack(fill=tk.X, padx=2, pady=2)
        for text, width in (("ON",4),("模板",18),("操作",8),("刷新",8),("停留",8),("ID",16),("计划",22)):
            ttk.Label(header, text=text, width=width, anchor="w").pack(side=tk.LEFT, padx=3)
        for template in templates:
            row = ttk.Frame(self.template_manager_container)
            row.pack(fill=tk.X, padx=2, pady=2)
            enabled_var = tk.BooleanVar(value=bool(template.enabled))
            self.template_enable_vars[template.id] = enabled_var
            ttk.Checkbutton(row, text="", variable=enabled_var, command=lambda tid=template.id: self.on_template_enabled_toggle(tid)).pack(side=tk.LEFT, padx=2)
            ttk.Label(row, text=f"{template.name}", width=18, anchor="w").pack(side=tk.LEFT, padx=4)
            ttk.Button(row, text="预览", command=lambda tid=template.id: self.select_template_from_list(tid)).pack(side=tk.LEFT, padx=4)
            refresh_var = tk.StringVar(value=self.refresh_label_for_template(template))
            self.template_refresh_vars[template.id] = refresh_var
            refresh_box = ttk.Combobox(row, textvariable=refresh_var, width=8, state="readonly", values=[label for label, _ in REFRESH_OPTIONS])
            refresh_box.pack(side=tk.LEFT, padx=4)
            refresh_box.bind("<<ComboboxSelected>>", lambda _event, tid=template.id: self.on_template_refresh_change(tid))
            dwell_var = tk.StringVar(value=self.dwell_label_for_template(template))
            self.template_dwell_vars[template.id] = dwell_var
            dwell_box = ttk.Combobox(row, textvariable=dwell_var, width=8, state="readonly", values=[label for label, _ in DWELL_OPTIONS])
            dwell_box.pack(side=tk.LEFT, padx=4)
            dwell_box.bind("<<ComboboxSelected>>", lambda _event, tid=template.id: self.on_template_dwell_change(tid))
            ttk.Label(row, text=f"[{template.id}]", width=16, anchor="w").pack(side=tk.LEFT, padx=2)
            ttk.Label(row, text=self.describe_schedule(template), width=22, anchor="w").pack(side=tk.LEFT, padx=4)

    def build_template_summary(self) -> str:
        templates = getattr(self.project, "templates", [])
        enabled = [t for t in templates if getattr(t, "enabled", False)]
        if not templates:
            return "暂无模板"
        return f"共 {len(templates)} 个模板 / 启用 {len(enabled)} 个\n点击“管理模板”设置启用、预览、刷新和停留时间。"

    def refresh_content_status_summary(self):
        weather_state = "已加载" if self.weather_lines else "未加载"
        news_state = "已加载" if self.news_lines else "未加载"
        printmana_state = "已读取" if self.bridge.read_printmana() else "未读取"
        bili_state = self.bili_status.get().strip() or "未连接"
        self.content_status_var.set(
            f"天气：{weather_state} / 新闻：{news_state} / 打印机：{printmana_state} / B站：{bili_state}"
        )

    def open_template_manager(self):
        if self.template_manager_window and self.template_manager_window.winfo_exists():
            self.template_manager_window.deiconify()
            self.template_manager_window.lift()
            self.refresh_template_enable_list()
            return
        win = tk.Toplevel(self)
        win.title("模板管理器")
        win.geometry("1180x520")
        win.transient(self)
        self.template_manager_window = win
        shell = ttk.Frame(win, padding=10)
        shell.pack(fill=tk.BOTH, expand=True)
        ttk.Label(shell, text="模板管理器", font=("Arial", 14, "bold")).pack(anchor="w")
        ttk.Label(shell, text="单独设置启用、预览、刷新周期、停留时间。", anchor="w").pack(fill=tk.X, pady=4)
        scroll = ttk.Frame(shell)
        scroll.pack(fill=tk.BOTH, expand=True)
        canvas = tk.Canvas(scroll, highlightthickness=0)
        scrollbar = ttk.Scrollbar(scroll, orient=tk.VERTICAL, command=canvas.yview)
        canvas.configure(yscrollcommand=scrollbar.set)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        container = ttk.Frame(canvas)
        window_id = canvas.create_window((0, 0), window=container, anchor="nw")
        container.bind("<Configure>", lambda e: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.bind("<Configure>", lambda e: canvas.itemconfigure(window_id, width=e.width))
        self.template_manager_container = container
        win.protocol("WM_DELETE_WINDOW", self.close_template_manager)
        self.refresh_template_enable_list()

    def close_template_manager(self):
        if self.template_manager_window and self.template_manager_window.winfo_exists():
            self.template_manager_window.destroy()
        self.template_manager_window = None
        self.template_manager_container = None

    def refresh_label_for_template(self, template) -> str:
        minutes = max(0, int(getattr(template, "refresh_minutes", 0) or 0))
        return REFRESH_MINUTES_TO_LABEL.get(minutes, "不刷新")

    def on_template_refresh_change(self, template_id: str):
        template = self.template_map.get(template_id)
        var = self.template_refresh_vars.get(template_id)
        if not template or var is None:
            return
        template.refresh_minutes = REFRESH_LABEL_TO_MINUTES.get(var.get(), 0)
        save_project(self.project, self.project_path)
        self.status(f"模板刷新周期已更新：{template.id} / {var.get()}")

    def dwell_label_for_template(self, template) -> str:
        seconds = max(10, int(getattr(template, "dwell_seconds", 20) or 20))
        return DWELL_SECONDS_TO_LABEL.get(seconds, "20秒")

    def on_template_dwell_change(self, template_id: str):
        template = self.template_map.get(template_id)
        var = self.template_dwell_vars.get(template_id)
        if not template or var is None:
            return
        template.dwell_seconds = DWELL_LABEL_TO_SECONDS.get(var.get(), 20)
        save_project(self.project, self.project_path)
        self.status(f"模板停留时间已更新：{template.id} / {var.get()}")
        self.refresh_template_enable_list()

    def describe_schedule(self, template) -> str:
        schedule = getattr(template, "schedule", None)
        if not schedule:
            return "无调度"
        if schedule.type == "always":
            return "兜底 / 全天"
        if schedule.type == "daily_range":
            return f"时段 {schedule.start}-{schedule.end}"
        if schedule.type == "exact_times":
            return "定点 " + ", ".join(schedule.times[:3])
        if schedule.type == "manual":
            return "仅手动"
        return str(schedule.type)

    def select_template_from_list(self, template_id: str):
        template = self.template_map.get(template_id)
        if not template:
            return
        self.selected_template_id.set(template.id)
        combo_values = list(self.template_combo.cget("values"))
        for index, value in enumerate(combo_values):
            if value.startswith(f"{template.id} - "):
                self.template_combo.current(index)
                break
        self.on_home_template_change()

    def on_template_enabled_toggle(self, template_id: str):
        template = self.template_map.get(template_id)
        var = self.template_enable_vars.get(template_id)
        if not template or var is None:
            return
        template.enabled = bool(var.get())
        save_project(self.project, self.project_path)
        self.status(f"模板 {'启用' if template.enabled else '禁用'}：{template.id}")
        self.refresh_template_choices()

    def _send_template(self, template, source: str, update_switch_time: bool = True, refresh_data: bool = False):
        pages = []
        cfg = self.current_cfg()
        self.project.device.host = cfg["host"]
        self.project.device.port = cfg["port"]
        self.project.device.width = cfg["width"]
        self.project.device.height = cfg["height"]
        self.project.device.threshold = cfg["threshold"]
        self.project.global_style.font_path = cfg["font_path"]
        self.sync_live_session_status()
        if refresh_data:
            self.refresh_template_widget_sources(template, source)
        for page in template.pages:
            png = render_page(page, self.project.device, self.project.global_style, bridge=self.bridge)
            if self.rotate_send.get():
                import io
                from PIL import Image
                image = Image.open(io.BytesIO(png))
                rotated = image.rotate(180, expand=True)
                output = io.BytesIO()
                rotated.save(output, format="PNG")
                png = output.getvalue()
            sent = self.send_png_with_auto_recover(self.project.device.host, self.project.device.port, png, page.image_id, context=f"模板发送 {template.id}/{page.name}")
            pages.append(page.image_id)
            self.status(f"{source}：已发送 {template.id}/{page.name} image_id={page.image_id}, {sent} bytes")
        state_kwargs = dict(last_sent_at=datetime.now().isoformat(), active_template_id=template.id, active_pages=pages, device_online=True, last_error="")
        if update_switch_time:
            state_kwargs["last_switch_at"] = datetime.now().isoformat()
        self.bridge.write_state(**state_kwargs)
        self.selected_template_id.set(template.id)
        self.cfg["selected_template_id"] = template.id
        self.template_status.set(f"已发送模板：{template.id} - {template.name}")
        return template.id

    def send_selected_template(self, show_errors: bool = True):
        self.template_preview_active = True
        template = self.get_selected_template()
        if not template:
            if show_errors:
                messagebox.showerror("模板不存在", "请先选择一个模板")
            else:
                self.status("启动发送跳过：未找到可发送模板")
            return
        try:
            self._send_template(template, "手动模板发送" if show_errors else "启动自动模板发送", refresh_data=True)
            self.save_fields()
        except Exception as e:
            if show_errors:
                messagebox.showerror("模板发送失败", str(e))
            self.status(f"模板发送失败：{e}")

    def startup_send_template_if_enabled(self):
        if not self.startup_send_selected_template.get():
            return
        try:
            if self.template_auto_enabled.get():
                sent = self.send_active_scheduled_template(show_errors=False)
                if sent:
                    return
            self.send_current(show_errors=False)
        except Exception as e:
            self.status(f"启动自动发送失败：{e}")

    def send_active_scheduled_template(self, show_errors: bool = True):
        try:
            template = select_active_template(self.project, datetime.now())
            self._send_template(template, "定时模板发送" if show_errors else "启动定时模板发送", refresh_data=True)
            return True
        except Exception as e:
            if show_errors:
                messagebox.showerror("定时模板发送失败", str(e))
            self.status(f"定时模板发送失败：{e}")
            return False

    def save_template_plan(self):
        self.cfg = self.current_cfg()
        path = save_config(self.cfg)
        self.status(f"模板自动化配置已保存：{path}")
        self.reload_project_templates()
        if self.template_auto_enabled.get():
            self.start_template_automation()

    def toggle_template_automation(self):
        if self.template_auto_enabled.get():
            self.start_template_automation()
        else:
            self.stop_template_automation()

    def start_template_automation_if_enabled(self):
        if self.template_auto_enabled.get():
            self.start_template_automation()

    def start_template_automation(self):
        self.stop_template_automation(log_message=False)
        try:
            interval = max(10, int(self.template_auto_interval.get()))
        except ValueError:
            self.template_auto_interval.set("30")
            interval = 30
        self.template_status.set(f"模板自动化已开启，每 {interval} 秒检查一次")
        self.template_auto_job = self.after(1000, self._template_auto_tick)

    def stop_template_automation(self, log_message: bool = True):
        if self.template_auto_job:
            try:
                self.after_cancel(self.template_auto_job)
            except Exception:
                pass
            self.template_auto_job = None
        if log_message:
            self.template_status.set("模板自动化已停止")

    def start_template_refresh_loop(self):
        self.stop_template_refresh_loop()
        self.template_refresh_job = self.after(30 * 1000, self._template_refresh_tick)

    def stop_template_refresh_loop(self):
        if self.template_refresh_job:
            try:
                self.after_cancel(self.template_refresh_job)
            except Exception:
                pass
            self.template_refresh_job = None

    def _template_refresh_tick(self):
        self.template_refresh_job = None
        try:
            state = self.bridge.read_state()
            active_template_id = state.get("active_template_id", "") if isinstance(state, dict) else ""
            last_sent_at = str(state.get("last_sent_at", "") or "") if isinstance(state, dict) else ""
            last_switch_at = str(state.get("last_switch_at", last_sent_at) or last_sent_at) if isinstance(state, dict) else ""
            last_content_refresh_at = str(state.get("last_content_refresh_at", "") or "") if isinstance(state, dict) else ""
            template = self.template_map.get(active_template_id)
            if template:
                now = datetime.now()
                if last_sent_at:
                    last_sent_dt = datetime.fromisoformat(last_sent_at)
                    if (now - last_sent_dt).total_seconds() >= 20:
                        self.refresh_hourly_greeting_data(log_error=False)
                        self._send_template(template, "模板保活重发 20秒", update_switch_time=False)
                        self.template_refresh_job = self.after(30 * 1000, self._template_refresh_tick)
                        return
                interval_minutes = max(0, int(getattr(template, "refresh_minutes", 0) or 0))
                refresh_anchor_raw = last_content_refresh_at or last_sent_at
                if interval_minutes > 0 and refresh_anchor_raw:
                    elapsed = (now - datetime.fromisoformat(refresh_anchor_raw)).total_seconds()
                    if elapsed >= interval_minutes * 60:
                        source = f"模板周期刷新 {self.refresh_label_for_template(template)}"
                        self.refresh_scheduled_content_sources(source, template=template)
                        self.bridge.write_state(last_content_refresh_at=datetime.now().isoformat())
                        self._send_template(template, source, update_switch_time=False)
                        self.template_refresh_job = self.after(30 * 1000, self._template_refresh_tick)
                        return
                if self.template_auto_enabled.get() and self.template_auto_rotate.get() and last_switch_at:
                    dwell_seconds = max(10, int(getattr(template, "dwell_seconds", 20) or 20))
                    switched_elapsed = (now - datetime.fromisoformat(last_switch_at)).total_seconds()
                    if switched_elapsed >= dwell_seconds:
                        enabled_templates = [t for t in getattr(self.project, "templates", []) if getattr(t, "enabled", False)]
                        if enabled_templates:
                            current_index = next((idx for idx, item in enumerate(enabled_templates) if item.id == template.id), -1)
                            next_template = enabled_templates[(current_index + 1) % len(enabled_templates)]
                            self._send_template(next_template, f"按停留时间轮播 {self.dwell_label_for_template(template)}")
        except Exception as e:
            self.status(f"模板周期刷新失败：{e}")
        self.template_refresh_job = self.after(30 * 1000, self._template_refresh_tick)

    def start_hourly_refresh(self):
        self.stop_hourly_refresh()
        try:
            self.refresh_scheduled_content_sources("启动内容刷新", template=self.get_selected_template())
        except Exception as e:
            self.status(f"启动内容刷新失败：{e}")
        self.content_refresh_job = self.after(3600 * 1000, self._hourly_refresh_tick)

    def stop_hourly_refresh(self):
        if self.content_refresh_job:
            try:
                self.after_cancel(self.content_refresh_job)
            except Exception:
                pass
            self.content_refresh_job = None

    def refresh_hourly_greeting_data(self, log_error: bool = True):
        try:
            titles = fetch_rss_titles(self.rss_url.get(), 3)
            greeting, quote, topics = build_hourly_greeting(datetime.now(), titles)
            self.bridge.set_daily_greeting(greeting=greeting, quote=quote, weather_city=self.weather_city.get().strip() or "Shanghai", news_topics=topics)
        except Exception as e:
            if log_error:
                self.status(f"问候语刷新失败：{e}")

    def sync_live_session_status(self) -> dict[str, object]:
        payload = load_latest_hermes_session_bridge_payload()
        if payload:
            self.bridge_write_with_trace("会话同步", "session_status", "session_status.json", lambda: self.bridge.write_session_status(payload), str(payload.get("summary") or payload.get("title") or "session"))
            work_payload = load_latest_hermes_work_status_payload()
            if work_payload:
                self.bridge_write_with_trace(
                    "会话同步",
                    "work_status",
                    "work_status.json",
                    lambda: self.bridge.set_work_status(
                        summary=str(work_payload.get("summary") or ""),
                        current_task=str(work_payload.get("current_task") or ""),
                        next_task=str(work_payload.get("next_task") or ""),
                        blocked=bool(work_payload.get("blocked") or False),
                        blocker=str(work_payload.get("blocker") or ""),
                    ),
                    str(work_payload.get("current_task") or work_payload.get("summary") or "work"),
                )
        return payload

    def fetch_printmana_data(self):
        url = self.printmana_api.get().strip()
        if not url:
            raise ValueError("请输入 PrintMana API 地址")
        self.append_refresh_trace(f"PrintMana: 请求列表 {url}")
        data = self._curl_json(url, timeout=8)
        if not isinstance(data, list):
            raise ValueError("打印机接口返回不是数组")
        self.append_refresh_trace(f"PrintMana: 列表返回 {len(data)} 台")
        detail = None
        if data:
            printer_id = data[0].get("id")
            if printer_id:
                detail_url = url.rstrip("/") + "/" + str(printer_id)
                self.append_refresh_trace(f"PrintMana: 请求详情 {detail_url}")
                detail = self._curl_json(detail_url, timeout=8)
                self.append_refresh_trace(f"PrintMana: 详情返回 {str(detail.get('name') or printer_id)} / {str(detail.get('statusText') or '')}")
        return {"endpoint": url, "printers": data, "primary": detail, "updated_at": datetime.now().isoformat()}

    def _curl_json(self, url: str, timeout: int = 8):
        command = [
            "curl", "-sS", "--max-time", str(timeout),
            "--connect-timeout", str(timeout),
            url,
        ]
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            stderr = (result.stderr or "").strip()
            stdout = (result.stdout or "").strip()
            message = stderr or stdout or f"curl exit {result.returncode}"
            raise RuntimeError(message)
        try:
            return json.loads(result.stdout)
        except Exception as e:
            raise ValueError(f"接口返回不是有效 JSON: {e}") from e

    def trace_bridge_mtime(self, name: str) -> str:
        try:
            return datetime.fromtimestamp(self.bridge.path(name).stat().st_mtime).isoformat()
        except Exception:
            return "unknown"

    def bridge_write_with_trace(self, source: str, label: str, file_name: str, writer, summary: str = ""):
        self.append_refresh_trace(f"{source}：{label}开始落盘")
        result = writer()
        mtime = self.trace_bridge_mtime(file_name)
        suffix = f" / {summary}" if summary else ""
        self.append_refresh_trace(f"{source}：{label}已落盘 {mtime}{suffix}")
        return result

    def refresh_printmana_for_scheduled_send(self, source: str):
        try:
            self.append_refresh_trace(f"{source}：PrintMana 开始落盘")
            data = self.fetch_printmana_data()
            self._set_printmana(data)
            count = len(data.get("printers") or [])
            primary = data.get("primary") or {}
            status_text = str(primary.get("statusText") or primary.get("status") or "")
            bridge_path = self.bridge.path("printmana.json")
            try:
                bridge_mtime = datetime.fromtimestamp(bridge_path.stat().st_mtime).isoformat()
            except Exception:
                bridge_mtime = "unknown"
            self.append_refresh_trace(f"{source}：PrintMana 已落盘 {count} 台 / {status_text or 'UNKNOWN'} / {bridge_mtime}")
            self.after(0, self.refresh_content_status_summary)
            self.after(0, lambda count=count, status_text=status_text: self.status(f"{source}：打印机数据已刷新 {count} 台 {('/ ' + status_text) if status_text else ''}"))
        except Exception as e:
            error_text = str(e)
            self.append_refresh_trace(f"{source}：PrintMana 落盘失败：{error_text}")
            self.after(0, lambda error_text=error_text: self.status(f"{source}：打印机数据刷新失败：{error_text}"))

    def refresh_weather_for_scheduled_send(self, source: str):
        try:
            city = self.weather_city.get().strip() or "Shanghai"
            payload = fetch_weather_payload(city)
            lines = [
                f"{payload.get('name', city)}: {payload.get('temperature', '?')}°C {payload.get('description', '')}",
                f"风速: {payload.get('wind_speed', '?')} km/h",
                f"今日: {payload.get('temp_min', '?')}~{payload.get('temp_max', '?')}°C",
            ]
            self.weather_lines = lines
            self.bridge_write_with_trace(source, f"天气 {city}", "content_cache.json", lambda: self.bridge.write_content_cache(f"weather::{city}", {"city": city, "lines": lines, "payload": payload}), f"weather::{city}")
            weekly_payload = fetch_weekly_weather_payload(city, 7)
            weekly_lines = [f"{item['weekday']} {item['temp_min']}~{item['temp_max']}° {item['description']}" for item in weekly_payload.get("days", [])]
            self.bridge_write_with_trace(source, f"周天气 {city}", "content_cache.json", lambda: self.bridge.write_content_cache(f"weather_weekly::{city}::6", {"city": city, "days": 6, "lines": weekly_lines, "payload": weekly_payload}), f"weather_weekly::{city}::6")
            self.after(0, self.refresh_content_status_summary)
            self.after(0, lambda: self.status(f"{source}：天气数据已刷新"))
        except Exception as e:
            error_text = str(e)
            self.after(0, lambda error_text=error_text: self.status(f"{source}：天气数据刷新失败：{error_text}"))

    def refresh_news_for_scheduled_send(self, source: str):
        try:
            rss_url = self.rss_url.get().strip()
            lines = fetch_rss_titles(rss_url, 5)
            self.news_lines = lines
            self.bridge_write_with_trace(source, "新闻主 RSS", "content_cache.json", lambda: self.bridge.write_content_cache(f"rss::{rss_url}::5", {"rss_url": rss_url, "max_items": 5, "lines": lines}), f"rss::{rss_url}::5")
            self.bridge_write_with_trace(source, "新闻主 RSS(4)", "content_cache.json", lambda: self.bridge.write_content_cache(f"rss::{rss_url}::4", {"rss_url": rss_url, "max_items": 4, "lines": list(lines)[:4]}), f"rss::{rss_url}::4")
            github_url = "https://hellogithub.com/rss"
            github_lines = fetch_rss_titles(github_url, 4)
            self.bridge_write_with_trace(source, "HelloGitHub RSS", "content_cache.json", lambda: self.bridge.write_content_cache(f"rss::{github_url}::4", {"rss_url": github_url, "max_items": 4, "lines": github_lines}), f"rss::{github_url}::4")
            self.after(0, self.refresh_content_status_summary)
            self.after(0, lambda: self.status(f"{source}：新闻数据已刷新 {len(lines)} 条"))
        except Exception as e:
            error_text = str(e)
            self.after(0, lambda error_text=error_text: self.status(f"{source}：新闻数据刷新失败：{error_text}"))

    def refresh_bili_for_scheduled_send(self, source: str):
        uid = self.bili_uid.get().strip()
        if not uid:
            return
        try:
            cookie = normalize_cookie_string(self.bili_cookie.get().strip())
            data = fetch_bilibili_status(uid, cookie)
            self.bridge_write_with_trace(source, "B站", "bilibili.json", lambda: self.bridge.write_bilibili(data), str(data.get('account_name') or data.get('uid') or uid))
            self.after(0, self.bili_refresh_status)
            self.after(0, lambda: self.status(f"{source}：B站数据已刷新 {data.get('account_name') or data.get('uid')}"))
        except Exception as e:
            error_text = str(e)
            self.after(0, lambda error_text=error_text: self.status(f"{source}：B站数据刷新失败：{error_text}"))

    def refresh_movies_for_scheduled_send(self, source: str):
        try:
            poster_dir = app_dir() / "data" / "movie_posters"
            data = fetch_now_playing_movies(limit=6, poster_dir=poster_dir)
            items = data.get("items") or []
            self.bridge_write_with_trace(source, "电影页", "content_cache.json", lambda: self.bridge.write_content_cache("movies::now_playing::6", data), f"movies::now_playing::6 / {len(items)} 部")
            self.after(0, lambda: self.status(f"{source}：电影数据已刷新 {len(items)} 部"))
        except Exception as e:
            error_text = str(e)
            self.after(0, lambda error_text=error_text: self.status(f"{source}：电影数据刷新失败：{error_text}"))

    def refresh_template_widget_sources(self, template, source: str):
        weather_targets = set()
        weekly_targets = set()
        rss_targets = set()
        traffic_targets = set()
        for page in getattr(template, "pages", []):
            for widget in getattr(page, "widgets", []):
                if widget.type == "weather":
                    weather_targets.add(widget.city.strip() or "Shanghai")
                elif widget.type == "weather_weekly":
                    requested_days = max(1, int(widget.max_items or 6))
                    fetch_days = requested_days + 1 if requested_days >= 6 else requested_days
                    weekly_targets.add((widget.city.strip() or "Shanghai", fetch_days))
                elif widget.type == "rss_news":
                    rss_targets.add((widget.rss_url.strip(), max(1, int(widget.max_items or 5))))
                elif widget.type in {"traffic_usage", "traffic_dashboard_card"}:
                    extra = widget.extra if isinstance(widget.extra, dict) else {}
                    traffic_targets.add((str(extra.get("endpoint") or ""), str(extra.get("token") or "")))

        for city in weather_targets:
            payload = fetch_weather_payload(city)
            lines = [
                f"{payload.get('name', city)}: {payload.get('temperature', '?')}°C {payload.get('description', '')}",
                f"风速: {payload.get('wind_speed', '?')} km/h",
                f"今日: {payload.get('temp_min', '?')}~{payload.get('temp_max', '?')}°C",
            ]
            self.bridge_write_with_trace(source, f"模板天气 {city}", "content_cache.json", lambda city=city, lines=lines, payload=payload: self.bridge.write_content_cache(f"weather::{city}", {"city": city, "lines": lines, "payload": payload}), f"weather::{city}")
        for city, days in weekly_targets:
            payload = fetch_weekly_weather_payload(city, days)
            lines = [f"{item['weekday']} {item['temp_min']}~{item['temp_max']}° {item['description']}" for item in payload.get("days", [])]
            self.bridge_write_with_trace(source, f"模板周天气 {city}", "content_cache.json", lambda city=city, days=days, lines=lines, payload=payload: self.bridge.write_content_cache(f"weather_weekly::{city}::{days}", {"city": city, "days": days, "lines": lines, "payload": payload}), f"weather_weekly::{city}::{days}")
        for rss_url, max_items in rss_targets:
            lines = fetch_rss_titles(rss_url, max_items)
            self.bridge_write_with_trace(source, f"模板RSS {max_items}", "content_cache.json", lambda rss_url=rss_url, max_items=max_items, lines=lines: self.bridge.write_content_cache(f"rss::{rss_url}::{max_items}", {"rss_url": rss_url, "max_items": max_items, "lines": lines}), f"rss::{rss_url}::{max_items}")
        for endpoint, token in traffic_targets:
            data = fetch_traffic(endpoint=endpoint or None, token=token or None) if (endpoint or token) else fetch_traffic()
            lines = traffic_lines(data)
            self.bridge_write_with_trace(source, "模板VPS/流量", "content_cache.json", lambda endpoint=endpoint, token=token, lines=lines: self.bridge.write_content_cache(f"traffic::{endpoint or 'default'}::{token or 'default'}", {"endpoint": endpoint or "default", "lines": lines}), f"traffic::{endpoint or 'default'}::{token or 'default'}")

        if weather_targets or weekly_targets or rss_targets or traffic_targets:
            self.after(0, lambda: self.status(f"{source}：模板缓存数据已刷新"))

    def refresh_all_enabled_template_sources(self, source: str):
        templates = [t for t in getattr(self.project, "templates", []) if getattr(t, "enabled", False)]
        for template in templates:
            self.refresh_template_widget_sources(template, source)

    def ensure_default_alerts(self):
        inbox = self.bridge.read_inbox(include_acknowledged=True)
        if inbox:
            return
        self.bridge.notify("info", "GitHub", "关注 changelog 与有趣项目动态。", ttl_seconds=7 * 24 * 3600)
        self.bridge.notify("warn", "VPS", "留意流量与节点状态。", ttl_seconds=7 * 24 * 3600)

    def refresh_scheduled_content_sources(self, source: str, template=None):
        self.sync_live_session_status()
        self.ensure_default_alerts()
        self.append_refresh_trace(f"{source}：开始刷新每日问候")
        self.after(0, lambda: self.status(f"{source}：开始刷新每日问候"))
        self.refresh_hourly_greeting_data(log_error=False)
        self.append_refresh_trace(f"{source}：开始刷新天气")
        self.after(0, lambda: self.status(f"{source}：开始刷新天气"))
        self.refresh_weather_for_scheduled_send(source)
        self.append_refresh_trace(f"{source}：开始刷新新闻")
        self.after(0, lambda: self.status(f"{source}：开始刷新新闻"))
        self.refresh_news_for_scheduled_send(source)
        self.append_refresh_trace(f"{source}：开始刷新全部模板缓存")
        self.refresh_all_enabled_template_sources(source)
        self.append_refresh_trace(f"{source}：开始刷新 PrintMana")
        self.after(0, lambda: self.status(f"{source}：开始刷新 PrintMana"))
        self.refresh_printmana_for_scheduled_send(source)
        self.append_refresh_trace(f"{source}：开始刷新电影页")
        self.after(0, lambda: self.status(f"{source}：开始刷新电影页"))
        self.refresh_movies_for_scheduled_send(source)
        self.append_refresh_trace(f"{source}：开始刷新 B站")
        self.after(0, lambda: self.status(f"{source}：开始刷新 B站"))
        self.refresh_bili_for_scheduled_send(source)
        self.bridge.write_state(last_content_refresh_at=datetime.now().isoformat())

    def _refresh_all_sections_job(self):
        source = "手动刷新全部板块"
        self.append_refresh_trace(f"{source}：任务启动")
        self.refresh_scheduled_content_sources(source, template=self.get_selected_template())
        self.append_refresh_trace(f"{source}：任务完成")
        return source

    def _after_refresh_all_sections(self, source: str):
        self.request_preview_render()
        self.status(f"{source}完成")

    def refresh_all_sections_now(self):
        self._run_async("手动刷新全部板块", self._refresh_all_sections_job, self._after_refresh_all_sections)

    def _hourly_refresh_tick(self):
        self.content_refresh_job = None
        try:
            state = self.bridge.read_state()
            active_template_id = state.get("active_template_id", "") if isinstance(state, dict) else ""
            active_template = self.template_map[active_template_id] if active_template_id and active_template_id in self.template_map else None
            self.refresh_scheduled_content_sources("每小时内容刷新", template=active_template)
            self.reload_project_templates()
            if active_template_id and active_template_id in self.template_map:
                self._send_template(self.template_map[active_template_id], "每小时内容刷新")
            elif self.template_auto_enabled.get():
                self.send_active_scheduled_template(show_errors=False)
            else:
                self.send_current(show_errors=False)
        except Exception as e:
            self.status(f"每小时刷新失败：{e}")
        self.content_refresh_job = self.after(3600 * 1000, self._hourly_refresh_tick)

    def _template_auto_tick(self):
        self.template_auto_job = None
        if not self.template_auto_enabled.get():
            return
        now = datetime.now()
        hhmm = now.strftime("%H:%M")
        already_sent = str(self.cfg.get("last_template_auto_hhmm", "")) == hhmm
        try:
            templates = [t for t in getattr(self.project, "templates", []) if getattr(t, "enabled", False)]
            if self.template_auto_rotate.get() and templates:
                state = self.bridge.read_state()
                active_template_id = state.get("active_template_id", "") if isinstance(state, dict) else ""
                current_index = -1
                for index, template in enumerate(templates):
                    if template.id == active_template_id:
                        current_index = index
                        break
                next_template = templates[(current_index + 1) % len(templates)]
                self._send_template(next_template, "自动轮播发送")
                self.template_status.set(f"轮播模板：{next_template.id} / 停留 {self.dwell_label_for_template(next_template)}")
            else:
                template = select_active_template(self.project, now)
                self.template_status.set(f"当前计划命中：{template.id} @ {hhmm}")
                if template.schedule.type == "exact_times" and hhmm in template.schedule.times and not already_sent:
                    self._send_template(template, "自动精确定时发送")
                    self.cfg["last_template_auto_hhmm"] = hhmm
                    save_config(self.current_cfg() | {"last_template_auto_hhmm": hhmm})
                elif template.schedule.type == "daily_range":
                    active_template_id = self.bridge.read_state().get("active_template_id", "") if isinstance(self.bridge.read_state(), dict) else ""
                    if active_template_id != template.id:
                        self._send_template(template, "自动时段切换发送")
                elif template.schedule.type == "always":
                    self.template_status.set(f"当前保底模板：{template.id}")
        except Exception as e:
            self.template_status.set(f"模板自动化检查失败：{e}")
        try:
            interval = max(10, int(self.template_auto_interval.get()))
        except ValueError:
            interval = 30
            self.template_auto_interval.set("30")
        self.template_auto_job = self.after(interval * 1000, self._template_auto_tick)

    def save_fields(self):
        self.cfg = self.current_cfg()
        path = save_config(self.cfg)
        self.status(f"配置已保存：{path}")
        if self.auto_send_enabled.get():
            self.start_auto_send()
        else:
            self.stop_auto_send()
        if self.template_auto_enabled.get():
            self.start_template_automation()
        else:
            self.stop_template_automation(log_message=False)

    def enable_usb_forward(self):
        cfg = self.current_cfg()
        try:
            adb_forward(cfg["port"], cfg["port"])
            self.host.set("127.0.0.1")
            self.cfg["host"] = "127.0.0.1"
            self.status("USB 转发已启用：127.0.0.1:38000")
        except Exception as e:
            messagebox.showerror("USB转发失败", str(e))
            self.status(f"USB 转发失败：{e}")

    def detect_adb_device(self) -> tuple[bool, str]:
        try:
            import subprocess
            result = subprocess.run(["adb", "devices", "-l"], check=True, capture_output=True, text=True)
            lines = [line.strip() for line in result.stdout.splitlines() if line.strip() and not line.startswith("List of devices")]
            devices = [line for line in lines if "\tdevice" in line or " device " in line or line.endswith(" device")]
            if devices:
                return True, devices[0]
            return False, result.stdout.strip()
        except Exception as e:
            return False, str(e)

    def auto_connect(self):
        cfg = self.current_cfg()
        host = str(cfg.get("host") or "127.0.0.1")
        port = int(cfg.get("port") or 38000)
        adb_ok, adb_info = self.detect_adb_device()
        if host in {"127.0.0.1", "localhost"} and adb_ok:
            try:
                ok, info = self.ensure_usb_debug_bridge()
                if ok:
                    self.test_conn()
                    return
                self.status(f"USB 自动恢复失败：{info}")
                return
            except Exception as e:
                self.status(f"USB 自动恢复失败：{e}")
                return
        if adb_ok:
            try:
                self.enable_usb_forward()
                self.test_conn()
                return
            except Exception:
                pass
        self.status(f"ADB 未就绪，保留 Wi-Fi 配置：{host}:{port} ({adb_info or '未检测到设备'})")

    def toggle_auto_send(self):
        if self.auto_send_enabled.get():
            self.start_auto_send()
        else:
            self.stop_auto_send()
        self.cfg = self.current_cfg()
        save_config(self.cfg)

    def on_auto_send_toggle(self):
        self.toggle_auto_send()

    def start_auto_send_if_enabled(self):
        if self.auto_send_enabled.get():
            self.start_auto_send()

    def start_auto_send(self):
        self.stop_auto_send(log_message=False)
        try:
            interval = max(5, int(self.auto_send_interval.get()))
        except ValueError:
            self.auto_send_interval.set("20")
            interval = 20
        self.status(f"自动重发已开启，间隔 {interval} 秒")
        self.auto_send_job = self.after(interval * 1000, self._auto_send_tick)

    def stop_auto_send(self, log_message: bool = True):
        if self.auto_send_job:
            try:
                self.after_cancel(self.auto_send_job)
            except Exception:
                pass
            self.auto_send_job = None
        if log_message:
            self.status("自动重发已停止")

    def _auto_send_tick(self):
        self.auto_send_job = None
        if not self.auto_send_enabled.get():
            return
        if self.template_auto_enabled.get():
            self.send_active_scheduled_template(show_errors=False)
        else:
            self.send_current(show_errors=False)
        try:
            interval = max(5, int(self.auto_send_interval.get()))
        except ValueError:
            interval = 20
            self.auto_send_interval.set("20")
        self.auto_send_job = self.after(interval * 1000, self._auto_send_tick)

    def choose_font(self):
        fonts_dir = resource_dir() / "fonts"
        if not fonts_dir.exists():
            fonts_dir = app_dir() / "fonts"
        path = choose_existing_file(
            self,
            title="选择字体",
            initialdir=str(fonts_dir),
            filetypes=[("Font", "*.ttf *.ttc *.otf"), ("All", "*.*")],
        )
        if path:
            self.font_path.set(path)
            self.render_preview()

    def choose_image(self):
        path = choose_existing_file(
            self,
            title="选择图片",
            initialdir=app_dir(),
            filetypes=[("Images", "*.png *.jpg *.jpeg *.bmp *.gif *.webp"), ("All", "*.*")],
        )
        if path:
            self.local_image.set(path)
            self.use_image.set(True)
            self.render_preview()

    def bili_refresh_status(self):
        data = self.bridge.read_bilibili()
        if not data:
            self.bili_status.set("未连接 / 无数据")
            self.bili_account.set("")
            self.refresh_content_status_summary()
            return
        uid = str(data.get("uid") or self.bili_uid.get().strip() or "")
        status_text = "已连接"
        if data.get("cookie_enabled"):
            status_text += " / 含消息读取"
        self.bili_status.set(status_text)
        account = str(data.get("account_name") or "未命名账号")
        self.bili_account.set(f"{account} ({uid})" if uid else account)
        self.refresh_content_status_summary()

    def fetch_bili_async(self):
        def job():
            uid = self.bili_uid.get().strip()
            cookie = normalize_cookie_string(self.bili_cookie.get().strip())
            if not uid:
                raise ValueError("请输入 B站 UID")
            return fetch_bilibili_status(uid, cookie)
        self._run_async("读取B站", job, self._set_bili_status)

    def bili_import_cookie_clipboard(self):
        try:
            raw = self.clipboard_get()
        except Exception as exc:
            messagebox.showerror("导入失败", f"读取剪贴板失败：{exc}")
            return
        cookie = normalize_cookie_string(raw)
        if not cookie:
            messagebox.showerror("导入失败", "剪贴板里没有可用 Cookie")
            return
        self.bili_cookie.set(cookie)
        self.save_fields()
        self.status("已从剪贴板导入 B站 Cookie")

    def bili_import_cookie_file(self):
        path = choose_existing_file(
            self,
            title="选择 Cookie 文件",
            initialdir=str(Path.home()),
            filetypes=[("Text", "*.txt *.cookie *.cookies"), ("All", "*.*")],
        )
        if not path:
            return
        try:
            raw = Path(path).read_text(encoding="utf-8", errors="ignore")
        except Exception as exc:
            messagebox.showerror("导入失败", f"读取文件失败：{exc}")
            return
        cookie = normalize_cookie_string(raw)
        if not cookie:
            messagebox.showerror("导入失败", "文件里没有可用 Cookie")
            return
        self.bili_cookie.set(cookie)
        self.save_fields()
        self.status(f"已导入 Cookie：{path}")

    def _set_bili_status(self, data):
        self.bridge.write_bilibili(data)
        self.bili_refresh_status()
        self.request_preview_render()
        self.status(f"B站数据已更新：{data.get('account_name') or data.get('uid')}")

    def bili_login_placeholder(self):
        self.fetch_bili_async()

    def bili_logout_placeholder(self):
        self.bridge.write_bilibili({})
        self.bili_refresh_status()
        self.status("已清空 B站登录/状态数据")

    def save_png(self):
        self.render_preview()
        if not self.preview_png:
            return
        path = choose_save_file(
            self,
            title="保存 PNG",
            initialdir=app_dir() / "data",
            default_name="panel.png",
            defaultextension=".png",
            filetypes=[("PNG", "*.png")],
        )
        if path:
            Path(path).write_bytes(self.preview_png)
            self.status(f"PNG 已保存：{path}")

    def fetch_weather_async(self):
        self._run_async("取天气", lambda: fetch_weather(self.weather_city.get()), self._set_weather)

    def _set_weather(self, lines):
        self.weather_lines = lines
        self.use_weather.set(True)
        self.refresh_content_status_summary()
        self.render_preview()
        self.status("天气已更新")

    def fetch_news_async(self):
        self._run_async("取新闻", lambda: fetch_rss_titles(self.rss_url.get(), 5), self._set_news)

    def _set_news(self, lines):
        self.news_lines = lines
        self.use_news.set(True)
        rss_url = self.rss_url.get().strip()
        if rss_url:
            self.bridge.write_content_cache(f"rss::{rss_url}::5", {"rss_url": rss_url, "max_items": 5, "lines": list(lines)})
            self.bridge.write_content_cache(f"rss::{rss_url}::4", {"rss_url": rss_url, "max_items": 4, "lines": list(lines)[:4]})
        self.refresh_content_status_summary()
        self.render_preview()
        self.status("新闻已更新")

    def fetch_printmana_async(self):
        self.status("读取打印机中...")
        self.append_refresh_trace("手动测试打印机：开始请求 PrintMana API")
        self._printmana_fetch_in_progress = True
        if self.printmana_timeout_job:
            try:
                self.after_cancel(self.printmana_timeout_job)
            except Exception:
                pass
        self.printmana_timeout_job = self.after(12000, self._check_printmana_fetch_timeout)

        def runner():
            try:
                data = self.fetch_printmana_data()
                self.ui_queue.put(lambda data=data: self._set_printmana(data))
            except Exception as e:
                self.append_refresh_trace(f"手动测试打印机失败：{e}")
                self.ui_queue.put(lambda e=e: self._handle_printmana_error(e))

        threading.Thread(target=runner, daemon=True).start()

    def _set_printmana(self, data):
        self._printmana_fetch_in_progress = False
        if self.printmana_timeout_job:
            try:
                self.after_cancel(self.printmana_timeout_job)
            except Exception:
                pass
            self.printmana_timeout_job = None
        self.bridge.write_printmana(data)
        count = len(data.get("printers") or [])
        updated_at = str(data.get("updated_at") or "")
        self.append_refresh_trace(f"手动测试打印机：成功刷新 {count} 台")
        self.refresh_content_status_summary()
        self.status(f"打印机数据已更新：{count} 台 / {updated_at}")
        self.request_preview_render()

    def _handle_printmana_error(self, error: Exception):
        self._printmana_fetch_in_progress = False
        if self.printmana_timeout_job:
            try:
                self.after_cancel(self.printmana_timeout_job)
            except Exception:
                pass
            self.printmana_timeout_job = None
        messagebox.showerror("读取打印机失败", str(error))
        self.status(f"读取打印机失败：{error}")

    def _check_printmana_fetch_timeout(self):
        self.printmana_timeout_job = None
        if getattr(self, "_printmana_fetch_in_progress", False):
            self._printmana_fetch_in_progress = False
            self.append_refresh_trace("手动测试打印机：12秒超时未完成")
            self.status("读取打印机超时：请检查 PrintMana 详情接口是否卡住")

    def download_image_async(self):
        def job():
            url = self.image_url.get().strip()
            if not url:
                raise ValueError("请输入图片 URL")
            return download_image(url, app_dir() / "data" / "downloaded_image")
        self._run_async("下载图片", job, self._set_downloaded_image)

    def _set_downloaded_image(self, path: Path):
        self.downloaded_image = path
        self.local_image.set(str(path))
        self.use_image.set(True)
        self.render_preview()
        self.status(f"图片已下载：{path}")

    def _run_async(self, name: str, fn, callback):
        self.status(f"{name}中...")
        def runner():
            try:
                result = fn()
                self.ui_queue.put(lambda result=result: callback(result))
            except Exception as e:
                self.append_refresh_trace(f"{name}失败：{e}")
                self.ui_queue.put(lambda e=e: (messagebox.showerror(f"{name}失败", str(e)), self.status(f"{name}失败：{e}")))
        threading.Thread(target=runner, daemon=True).start()

    def append_refresh_trace(self, text: str):
        trace_path = ROOT / "hermes_bridge" / "refresh_trace.log"
        trace_path.parent.mkdir(parents=True, exist_ok=True)
        with trace_path.open("a", encoding="utf-8") as f:
            f.write(f"[{datetime.now().strftime('%H:%M:%S')}] {text}\n")

    def _flush_status_queue(self):
        try:
            while True:
                callback = self.ui_queue.get_nowait()
                callback()
        except Empty:
            pass
        try:
            while True:
                text = self.status_queue.get_nowait()
                self.log.insert(tk.END, f"[{datetime.now().strftime('%H:%M:%S')}] {text}\n")
                self.log.see(tk.END)
        except Empty:
            pass
        self.after(150, self._flush_status_queue)

    def status(self, text: str):
        self.status_queue.put(text)


def main():
    app = StudioApp()
    app.mainloop()


if __name__ == "__main__":
    main()
