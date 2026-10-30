from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any


@dataclass
class DeviceConfig:
    host: str = "127.0.0.1"
    port: int = 38000
    width: int = 600
    height: int = 800
    default_image_id: int = 0
    threshold: int = 128

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "DeviceConfig":
        return cls(**{k: data.get(k, getattr(cls(), k)) for k in cls().__dataclass_fields__})


@dataclass
class GlobalStyle:
    font_path: str = ""
    title_font_size: int = 36
    body_font_size: int = 24
    small_font_size: int = 18
    foreground: int = 0
    background: int = 255

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "GlobalStyle":
        return cls(**{k: data.get(k, getattr(cls(), k)) for k in cls().__dataclass_fields__})


@dataclass
class Schedule:
    type: str = "always"
    start: str = "00:00"
    end: str = "23:59"
    times: list[str] = field(default_factory=list)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Schedule":
        return cls(
            type=str(data.get("type", "always")),
            start=str(data.get("start", "00:00")),
            end=str(data.get("end", "23:59")),
            times=list(data.get("times", [])),
        )


@dataclass
class Widget:
    id: str
    type: str
    x: int
    y: int
    w: int
    h: int
    text: str = ""
    source: str = ""
    font_path: str = ""
    font_size: int = 24
    foreground: int = 0
    background: int = 255
    transparent: bool = False
    border: bool = False
    border_width: int = 2
    align: str = "left"
    valign: str = "top"
    padding: int = 8
    invert: bool = False
    visible: bool = True
    image_path: str = ""
    image_url: str = ""
    city: str = "Beijing"
    rss_url: str = "https://hnrss.org/frontpage"
    max_items: int = 5
    extra: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Widget":
        base = {k: data.get(k) for k in cls.__dataclass_fields__ if k in data}
        required = {"id", "type", "x", "y", "w", "h"}
        missing = [k for k in required if k not in base]
        if missing:
            raise ValueError(f"widget missing required fields: {missing}")
        return cls(**base)


@dataclass
class Page:
    image_id: int
    name: str = "Page"
    background: dict[str, Any] = field(default_factory=lambda: {"type": "solid", "color": 255})
    widgets: list[Widget] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {"image_id": self.image_id, "name": self.name, "background": self.background, "widgets": [w.to_dict() for w in self.widgets]}

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Page":
        return cls(
            image_id=int(data.get("image_id", 0)),
            name=str(data.get("name", "Page")),
            background=dict(data.get("background", {"type": "solid", "color": 255})),
            widgets=[Widget.from_dict(w) for w in data.get("widgets", [])],
        )


@dataclass
class Template:
    id: str
    name: str
    enabled: bool = True
    schedule: Schedule = field(default_factory=Schedule)
    refresh_minutes: int = 0
    dwell_seconds: int = 60
    pages: list[Page] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {"id": self.id, "name": self.name, "enabled": self.enabled, "schedule": asdict(self.schedule), "refresh_minutes": self.refresh_minutes, "dwell_seconds": self.dwell_seconds, "pages": [p.to_dict() for p in self.pages]}

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Template":
        return cls(
            id=str(data.get("id", "template")),
            name=str(data.get("name", data.get("id", "Template"))),
            enabled=bool(data.get("enabled", True)),
            schedule=Schedule.from_dict(dict(data.get("schedule", {"type": "always"}))),
            refresh_minutes=max(0, int(data.get("refresh_minutes", 0) or 0)),
            dwell_seconds=max(10, int(data.get("dwell_seconds", 60) or 60)),
            pages=[Page.from_dict(p) for p in data.get("pages", [])],
        )


@dataclass
class Project:
    version: int = 1
    device: DeviceConfig = field(default_factory=DeviceConfig)
    global_style: GlobalStyle = field(default_factory=GlobalStyle)
    templates: list[Template] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "version": self.version,
            "device": asdict(self.device),
            "global_style": asdict(self.global_style),
            "templates": [t.to_dict() for t in self.templates],
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Project":
        return cls(
            version=int(data.get("version", 1)),
            device=DeviceConfig.from_dict(dict(data.get("device", {}))),
            global_style=GlobalStyle.from_dict(dict(data.get("global_style", {}))),
            templates=[Template.from_dict(t) for t in data.get("templates", [])],
        )


def create_default_project() -> Project:
    return Project(
        templates=[
            Template(
                id="morning",
                name="早晨模板",
                schedule=Schedule(type="daily_range", start="06:00", end="08:59"),
                pages=[Page(image_id=0, name="晨间主页", widgets=[
                    Widget(id="greeting", type="hermes_greeting", x=20, y=20, w=560, h=130, font_size=30, border=True),
                    Widget(id="weather", type="weather", x=20, y=170, w=260, h=170, font_size=20, border=True),
                    Widget(id="news", type="rss_news", x=20, y=360, w=560, h=300, font_size=18, border=True),
                ])],
            ),
            Template(
                id="work",
                name="工作模板",
                schedule=Schedule(type="daily_range", start="09:00", end="18:59"),
                pages=[Page(image_id=0, name="工作状态", widgets=[
                    Widget(id="work_status", type="hermes_work_status", x=20, y=20, w=560, h=220, font_size=22, border=True),
                    Widget(id="traffic", type="traffic_usage", x=20, y=260, w=560, h=190, font_size=20, border=True),
                    Widget(id="alerts", type="hermes_alerts", x=20, y=470, w=560, h=170, font_size=20, border=True),
                    Widget(id="clock", type="clock", x=20, y=660, w=560, h=80, font_size=28, border=True),
                ])],
            ),
            Template(
                id="default",
                name="默认模板",
                schedule=Schedule(type="always"),
                pages=[Page(image_id=0, name="默认页", widgets=[
                    Widget(id="text", type="text", x=20, y=20, w=560, h=180, text="Remote Panel E-Ink Studio", font_size=32, border=True),
                    Widget(id="system", type="system_status", x=20, y=230, w=560, h=240, font_size=20, border=True),
                ])],
            ),
        ]
    )
