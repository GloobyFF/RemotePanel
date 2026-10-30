from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFont, ImageOps

from .config import app_dir


@dataclass
class PanelData:
    title: str = "Remote Panel E-Ink Studio"
    body: str = ""
    footer: str = ""
    status_lines: list[str] | None = None
    weather_lines: list[str] | None = None
    news_lines: list[str] | None = None
    image_path: str | None = None
from .config import app_dir


def default_font_path() -> str:
    candidates = [
        r"C:\Windows\Fonts\msyh.ttc",
        r"C:\Windows\Fonts\simhei.ttf",
        r"C:\Windows\Fonts\simsun.ttc",
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Light.ttc",
        "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for p in candidates:
        if Path(p).exists():
            return p
    return ""


def get_font(path: str, size: int):
    try:
        candidate = Path(path) if path else None
        if candidate and not candidate.is_absolute():
            candidate = app_dir() / candidate
        if candidate and candidate.exists():
            return ImageFont.truetype(str(candidate), size)
        d = default_font_path()
        if d:
            return ImageFont.truetype(d, size)
    except Exception:
        pass
    return ImageFont.load_default()


def wrap_text(draw: ImageDraw.ImageDraw, text: str, font, max_width: int) -> list[str]:
    if not text:
        return []
    lines: list[str] = []
    for para in text.splitlines() or [text]:
        current = ""
        # CJK-friendly char wrapping, but preserve spaces for English.
        units = list(para) if any(ord(ch) > 127 for ch in para) else para.split(" ")
        sep = "" if any(ord(ch) > 127 for ch in para) else " "
        for unit in units:
            candidate = unit if not current else current + sep + unit
            bbox = draw.textbbox((0, 0), candidate, font=font)
            if bbox[2] - bbox[0] <= max_width or not current:
                current = candidate
            else:
                lines.append(current)
                current = unit
        if current:
            lines.append(current)
    return lines


def bw_threshold(img: Image.Image, threshold: int = 128) -> Image.Image:
    gray = ImageOps.grayscale(img)
    return gray.point(lambda p: 0 if p < threshold else 255, mode="L")


def load_fit_image(path: str, box: tuple[int, int], threshold: int) -> Image.Image | None:
    try:
        img = Image.open(path).convert("RGB")
        img.thumbnail(box, Image.Resampling.LANCZOS)
        canvas = Image.new("RGB", box, "white")
        x = (box[0] - img.width) // 2
        y = (box[1] - img.height) // 2
        canvas.paste(img, (x, y))
        return bw_threshold(canvas, threshold)
    except Exception:
        return None


def render_panel(data: PanelData, cfg: dict) -> bytes:
    width = int(cfg.get("width", 600))
    height = int(cfg.get("height", 800))
    threshold = int(cfg.get("threshold", 128))
    font_path = str(cfg.get("font_path", ""))
    title_font = get_font(font_path, int(cfg.get("title_font_size", 36)))
    body_font = get_font(font_path, int(cfg.get("body_font_size", 24)))
    small_font = get_font(font_path, int(cfg.get("footer_font_size", 18)))

    img = Image.new("L", (width, height), 255)
    draw = ImageDraw.Draw(img)

    # Header
    draw.rectangle([0, 0, width, 72], fill=0)
    draw.text((18, 16), data.title[:32], fill=255, font=title_font)

    y = 92
    margin = 22
    max_width = width - margin * 2

    if data.body:
        draw.rectangle([margin, y, width - margin, min(y + 230, height - 80)], outline=0, width=3)
        ty = y + 18
        for line in wrap_text(draw, data.body, body_font, max_width - 28)[:6]:
            draw.text((margin + 14, ty), line, fill=0, font=body_font)
            ty += int(cfg.get("body_font_size", 24)) + 8
        y += 250

    if data.image_path:
        box_h = min(260, max(120, height - y - 220))
        fitted = load_fit_image(data.image_path, (max_width, box_h), threshold)
        if fitted:
            img.paste(fitted, (margin, y))
            draw.rectangle([margin, y, margin + max_width, y + box_h], outline=0, width=2)
            y += box_h + 18

    sections = []
    if data.weather_lines:
        sections.append(("天气", data.weather_lines))
    if data.news_lines:
        sections.append(("新闻", data.news_lines))
    if data.status_lines:
        sections.append(("状态", data.status_lines))

    for heading, lines in sections:
        if y > height - 90:
            break
        draw.line([margin, y, width - margin, y], fill=0, width=2)
        y += 10
        draw.text((margin, y), heading, fill=0, font=small_font)
        y += int(cfg.get("footer_font_size", 18)) + 8
        for item in lines[:5]:
            if y > height - 74:
                break
            for line in wrap_text(draw, "• " + item, small_font, max_width)[:2]:
                draw.text((margin, y), line, fill=0, font=small_font)
                y += int(cfg.get("footer_font_size", 18)) + 6

    draw.rectangle([0, height - 48, width, height], fill=0)
    footer = data.footer or "Ready"
    draw.text((16, height - 34), footer[:60], fill=255, font=small_font)

    img = bw_threshold(img, threshold)
    import io
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def png_to_preview_image(png: bytes, max_size=(300, 400)) -> Image.Image:
    import io
    img = Image.open(io.BytesIO(png)).convert("L")
    img.thumbnail(max_size, Image.Resampling.NEAREST)
    return img
