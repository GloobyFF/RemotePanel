from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageOps

from .hermes_bridge import HermesBridge
from .model import DeviceConfig, GlobalStyle, Page, Widget
from .mono_png import save_l_png_no_filter
from .news import fetch_rss_titles
from .render import get_font, load_fit_image, wrap_text
from .traffic import fetch_traffic, traffic_lines
from .utils import get_system_metrics, system_lines
from .weather import fetch_weather, fetch_weekly_weather

WEATHER_ICON_FONT = Path(__file__).resolve().parents[1] / "WeatherIcons" / "weathericons-regular-webfont.ttf"


def weather_icon_char(code: int | str | None) -> str:
    try:
        code = int(code)
    except Exception:
        code = -1
    icon_map = {
        0: "\uf00d",  # clear / sunny
        1: "\uf002",  # mostly sunny
        2: "\uf041",  # partly cloudy
        3: "\uf041",  # cloudy / overcast
        45: "\uf014", # fog
        48: "\uf014", # rime fog
        51: "\uf017", # light drizzle
        53: "\uf019", # drizzle
        55: "\uf01c", # dense drizzle
        61: "\uf01a", # light rain
        63: "\uf019", # rain
        65: "\uf01c", # heavy rain
        71: "\uf01b", # light snow
        73: "\uf01b", # snow
        75: "\uf064", # heavy snow
        80: "\uf01a", # rain showers
        81: "\uf019", # rain showers
        82: "\uf01d", # violent rain showers
        95: "\uf01e", # thunderstorm
        96: "\uf016", # thunderstorm with hail
        99: "\uf015", # heavy thunderstorm with hail
    }
    return icon_map.get(code, "\uf07b")


def get_weather_icon_font(size: int):
    return get_font(str(WEATHER_ICON_FONT), size)


def threshold(img: Image.Image, value: int) -> Image.Image:
    gray = ImageOps.grayscale(img)
    return gray.point(lambda p: 0 if p < value else 255, mode="L")


def render_page(page: Page, device: DeviceConfig, style: GlobalStyle, bridge: HermesBridge | None = None, live_data: bool = True) -> bytes:
    bg_color = int(page.background.get("color", style.background)) if isinstance(page.background, dict) else style.background
    img = Image.new("L", (device.width, device.height), bg_color)
    draw = ImageDraw.Draw(img)

    bg_path = ""
    if isinstance(page.background, dict):
        bg_path = str(page.background.get("image_path", "") or "")
    if bg_path and Path(bg_path).exists():
        bg = load_fit_image(bg_path, (device.width, device.height), device.threshold)
        if bg:
            img.paste(bg, (0, 0))

    for widget in page.widgets:
        if widget.visible:
            render_widget(img, draw, widget, style, device.threshold, bridge, live_data)

    img = threshold(img, device.threshold)
    return save_l_png_no_filter(img)


def render_widget(
    img: Image.Image,
    draw: ImageDraw.ImageDraw,
    widget: Widget,
    style: GlobalStyle,
    threshold_value: int,
    bridge: HermesBridge | None,
    live_data: bool = True,
) -> None:
    x, y, w, h = widget.x, widget.y, widget.w, widget.h
    fg = widget.foreground if not widget.invert else widget.background
    bg = widget.background if not widget.invert else widget.foreground
    if not widget.transparent:
        draw.rectangle([x, y, x + w, y + h], fill=bg)
    if widget.border:
        draw.rectangle([x, y, x + w, y + h], outline=fg, width=max(1, widget.border_width))

    content = resolve_widget_content(widget, bridge, live_data)
    if widget.type == "image":
        path = widget.image_path
        if path and Path(path).exists():
            fitted = load_fit_image(path, (max(1, w - widget.padding * 2), max(1, h - widget.padding * 2)), threshold_value)
            if fitted:
                img.paste(fitted, (x + widget.padding, y + widget.padding))
        return
    if widget.type == "printmana_filament_bars":
        render_printmana_filament_bars(draw, widget, style, bridge)
        return
    if widget.type == "printmana_8slot_bars":
        render_printmana_8slot_bars(draw, widget, style, bridge)
        return
    if widget.type == "printmana_overview_card":
        render_printmana_overview_card(draw, widget, style, bridge)
        return
    if widget.type == "printmana_ams0_card":
        render_printmana_ams0_card(draw, widget, style, bridge)
        return
    if widget.type == "bilibili_status":
        render_bilibili_status(draw, widget, style, bridge)
        return
    if widget.type == "weather_overview_card":
        render_weather_overview_card(draw, widget, style, bridge)
        return
    if widget.type == "weather_weekly_cards":
        render_weather_weekly_cards(draw, widget, style, bridge)
        return
    if widget.type == "traffic_dashboard_card":
        render_traffic_dashboard_card(draw, widget, style, bridge)
        return
    if widget.type == "news_dashboard_card":
        render_news_dashboard_card(draw, widget, style, bridge)
        return
    if widget.type == "hermes_chat_bubbles":
        render_hermes_chat_bubbles(draw, widget, style, bridge)
        return
    if widget.type == "hermes_work_board":
        render_hermes_work_board(draw, widget, style, bridge)
        return
    if widget.type == "hermes_work_status":
        render_hermes_work_board(draw, widget, style, bridge)
        return
    if widget.type == "system_dashboard_card":
        render_system_dashboard_card(draw, widget, style)
        return

    font_path = widget.font_path or style.font_path
    font = get_font(font_path, widget.font_size or style.body_font_size)
    tx = x + widget.padding
    ty = y + widget.padding
    max_width = max(1, w - widget.padding * 2)
    line_height = max(12, widget.font_size + 6)
    lines: list[str] = []
    for para in content.splitlines() or [content]:
        lines.extend(wrap_text(draw, para, font, max_width))
    max_lines = max(1, (h - widget.padding * 2) // line_height)
    lines = lines[:max_lines]
    total_height = len(lines) * line_height
    if widget.valign == "center":
        ty = y + max(0, (h - total_height) // 2)
    elif widget.valign == "bottom":
        ty = y + max(0, h - total_height - widget.padding)

    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=font)
        line_width = bbox[2] - bbox[0]
        if widget.align == "center":
            tx = x + max(0, (w - line_width) // 2)
        elif widget.align == "right":
            tx = x + max(0, w - line_width - widget.padding)
        else:
            tx = x + widget.padding
        draw.text((tx, ty), line, fill=fg, font=font)
        ty += line_height


def render_printmana_filament_bars(draw: ImageDraw.ImageDraw, widget: Widget, style: GlobalStyle, bridge: HermesBridge | None) -> None:
    x, y, w, h = widget.x, widget.y, widget.w, widget.h
    font_path = widget.font_path or style.font_path
    title_font = get_font(font_path, 22)
    label_font = get_font(font_path, 22)
    small_font = get_font(font_path, 18)
    data = bridge.read_printmana() if bridge else {}
    primary = data.get("primary") if isinstance(data, dict) else {}
    entries = []
    if isinstance(primary, dict):
        for unit in (primary.get("ams") or []):
            for slot in (unit.get("slots") or []):
                if slot.get("isEmpty"):
                    continue
                bound = slot.get("bound") or {}
                remain_pct = bound.get("remainingPercent", slot.get("remainPercent", 0))
                try:
                    pct = max(0.0, min(100.0, float(remain_pct)))
                except Exception:
                    pct = 0.0
                name = str(bound.get("name") or slot.get("type") or "FILAMENT")
                grams = bound.get("remainingGram")
                total = bound.get("totalGram")
                entries.append((pct, unit.get("index", "?"), slot.get("slot", "?"), name, grams, total))
    entries.sort(key=lambda item: item[0])
    entries = entries[:4]
    draw.rectangle([x, y, x + w, y + h], outline=0, width=3)
    draw.text((x + 14, y + 10), "低余量料仓", fill=0, font=title_font)
    if not entries:
        draw.text((x + 24, y + 70), "NO AMS DATA", fill=0, font=title_font)
        return
    top = y + 56
    card_bottom = y + h - 18
    bar_top = top + 54
    bar_h = max(120, int((card_bottom - bar_top - 26) * 0.66))
    gap = 14
    col_w = max(80, (w - 34 - gap * 3) // 4)
    for index, (pct, ams_idx, slot_idx, name, grams, total) in enumerate(entries):
        cx = x + 17 + index * (col_w + gap)
        draw.rectangle([cx, top, cx + col_w, card_bottom], outline=0, width=2)
        if ams_idx == 0:
            slot_label = f"A{int(slot_idx) + 1}"
        elif ams_idx == 1:
            slot_label = f"B{int(slot_idx) + 1}"
        else:
            slot_label = f"HT{int(slot_idx) + 1}"
        draw.text((cx + 8, top + 8), slot_label, fill=0, font=label_font)
        if pct <= 10:
            mark = "!!"
        elif pct <= 25:
            mark = "LOW"
        else:
            mark = "OK"
        draw.text((cx + col_w - 42, top + 8), mark, fill=0, font=small_font)
        bx = cx + 20
        bw = col_w - 40
        by = bar_top
        draw.rectangle([bx, by, bx + bw, by + bar_h], outline=0, width=2)
        fill_h = round(bar_h * pct / 100)
        fy = by + bar_h - fill_h
        if fill_h > 0:
            draw.rectangle([bx + 4, fy, bx + bw - 4, by + bar_h - 4], fill=0)
        for tick in (25, 50, 75):
            ty = by + bar_h - round(bar_h * tick / 100)
            draw.line([bx - 5, ty, bx + bw + 5, ty], fill=0, width=1)
        pct_text = f"{pct:.1f}%"
        tb = draw.textbbox((0, 0), pct_text, font=label_font)
        tw = tb[2] - tb[0]
        th = tb[3] - tb[1]
        tx = cx + (col_w - tw) // 2
        ty = by + (bar_h - th) // 2 - 2
        pct_fill = 255 if pct >= 45 else 0
        draw.text((tx, ty), pct_text, fill=pct_fill, font=label_font)
        if grams not in (None, ""):
            grams_text = f"{float(grams):.0f}g"
            gb = draw.textbbox((0, 0), grams_text, font=label_font)
            gw = gb[2] - gb[0]
            draw.text((cx + (col_w - gw) // 2, by + bar_h + 16), grams_text, fill=0, font=label_font)
        short_name = name[:8]
        nb = draw.textbbox((0, 0), short_name, font=small_font)
        nw = nb[2] - nb[0]
        draw.text((cx + (col_w - nw) // 2, card_bottom - 42), short_name, fill=0, font=small_font)


def render_printmana_overview_card(draw: ImageDraw.ImageDraw, widget: Widget, style: GlobalStyle, bridge: HermesBridge | None) -> None:
    x, y, w, h = widget.x, widget.y, widget.w, widget.h
    font_path = widget.font_path or style.font_path
    title_font = get_font(font_path, 26)
    status_font = get_font(font_path, 20)
    percent_font = get_font(font_path, 54)
    meta_font = get_font(font_path, 22)
    temp_font = get_font(font_path, 30)
    small_font = get_font(font_path, 16)
    data = bridge.read_printmana() if bridge else {}
    primary = data.get("primary") if isinstance(data, dict) else {}
    if not isinstance(primary, dict) or not primary:
        draw.rectangle([x, y, x + w, y + h], outline=0, width=2)
        draw.text((x + 20, y + 20), "打印机总览", fill=0, font=title_font)
        draw.text((x + 20, y + 80), "NO PRINT DATA", fill=0, font=status_font)
        return
    temps = primary.get('temps') or {}
    progress = int(primary.get('progress') or 0)
    name = str(primary.get('name') or primary.get('model') or 'Printer')[:20]
    status = str(primary.get('statusText') or primary.get('status') or 'UNKNOWN')[:16]
    remain = primary.get('remainingMinutes')
    file_name = str(primary.get('fileName') or 'No active job')[:28]
    nozzles = temps.get('nozzles') or []
    nozzle_text = '--'
    if nozzles:
        nozzle_text = ' / '.join(f"{int(n.get('temp', 0))}°" for n in nozzles[:2])
    else:
        nozzle_text = f"{int(temps.get('nozzle', 0))}°"
    bed_text = f"{int(temps.get('bed', 0))}°"
    chamber_text = f"{int(temps.get('chamber', 0))}°"
    draw.rectangle([x, y, x + w, y + h], outline=0, width=2)
    draw.text((x + 18, y + 14), "打印机总览", fill=0, font=small_font)
    draw.text((x + 18, y + 40), name, fill=0, font=title_font)
    status_box = [x + w - 170, y + 26, x + w - 18, y + 72]
    draw.rectangle(status_box, outline=0, width=2)
    sb = draw.textbbox((0, 0), status, font=status_font)
    sw = sb[2] - sb[0]
    sh = sb[3] - sb[1]
    draw.text((status_box[0] + (status_box[2]-status_box[0]-sw)//2, status_box[1] + (status_box[3]-status_box[1]-sh)//2 - 2), status, fill=0, font=status_font)
    percent_bbox = draw.textbbox((0, 0), f"{progress}%", font=percent_font)
    pw = percent_bbox[2] - percent_bbox[0]
    draw.text((x + (w - pw)//2, y + 118), f"{progress}%", fill=0, font=percent_font)
    bar_x1, bar_y1 = x + 58, y + 206
    bar_x2, bar_y2 = x + w - 58, y + 244
    draw.rectangle([bar_x1, bar_y1, bar_x2, bar_y2], outline=0, width=2)
    fill_w = round((bar_x2 - bar_x1 - 8) * max(0, min(100, progress)) / 100)
    if fill_w > 0:
        draw.rectangle([bar_x1 + 4, bar_y1 + 4, bar_x1 + 4 + fill_w, bar_y2 - 4], fill=0)
    eta_text = f"ETA {remain}m" if remain not in (None, '') else "ETA --"
    draw.text((x + 56, y + 266), eta_text, fill=0, font=meta_font)
    draw.text((x + 56, y + 302), "任务", fill=0, font=small_font)
    draw.rectangle([x + 52, y + 326, x + w - 52, y + 392], outline=0, width=1)
    draw.text((x + 68, y + 346), file_name, fill=0, font=meta_font)
    block_top = y + 420
    gap = 14
    block_w = (w - 40 - gap * 2) // 3
    metrics = [("◉", "喷嘴", nozzle_text), ("▤", "热床", bed_text), ("⌂", "仓温", chamber_text)]
    for i, (icon, label, value) in enumerate(metrics):
        bx = x + 20 + i * (block_w + gap)
        by = block_top
        draw.rectangle([bx, by, bx + block_w, by + 138], outline=0, width=2)
        draw.text((bx + 14, by + 12), icon, fill=0, font=meta_font)
        draw.text((bx + 48, by + 16), label, fill=0, font=small_font)
        vb = draw.textbbox((0, 0), value, font=temp_font)
        vw = vb[2] - vb[0]
        draw.text((bx + (block_w - vw)//2, by + 62), value, fill=0, font=temp_font)


def render_printmana_ams0_card(draw: ImageDraw.ImageDraw, widget: Widget, style: GlobalStyle, bridge: HermesBridge | None) -> None:
    x, y, w, h = widget.x, widget.y, widget.w, widget.h
    font_path = widget.font_path or style.font_path
    head_font = get_font(font_path, 18)
    title_font = get_font(font_path, 30)
    brand_font = get_font(font_path, 22)
    percent_font = get_font(font_path, 70)
    label_font = get_font(font_path, 18)
    value_font = get_font(font_path, 24)
    badge_font = get_font(font_path, 16)
    data = bridge.read_printmana() if bridge else {}
    primary = data.get("primary") if isinstance(data, dict) else {}
    ams2 = None
    if isinstance(primary, dict):
        for unit in (primary.get("ams") or []):
            if unit.get("index") == 2:
                ams2 = unit
                break
    slot = None
    if isinstance(ams2, dict):
        slots = ams2.get("slots") or []
        for s in slots:
            if not s.get("isEmpty"):
                slot = s
                break
        if slot is None and slots:
            slot = slots[0]
    draw.rectangle([x, y, x + w, y + h], outline=0, width=2)
    draw.text((x + 18, y + 14), "AMSHT信息", fill=0, font=head_font)
    if not slot:
        draw.text((x + 32, y + 72), "未找到槽位数据", fill=0, font=title_font)
        return
    bound = slot.get("bound") or {}
    pct_raw = bound.get("remainingPercent", slot.get("remainPercent", 0))
    try:
        pct = max(0.0, min(100.0, float(pct_raw)))
    except Exception:
        pct = 0.0
    grams = bound.get("remainingGram")
    total = bound.get("totalGram")
    name = str(bound.get("name") or slot.get("type") or "EMPTY")[:18]
    brand = str(bound.get("brand") or "未知品牌")[:12]
    material = str(bound.get("type") or slot.get("type") or "普通料")[:10]
    rainbow = bool(bound.get("isRainbow") or slot.get("isRainbow"))
    color_hex = str(bound.get("colorHex") or slot.get("colorHex") or "----")[:8]
    footer = f"AMS2 / S{slot.get('slot', 0)}"

    draw.text((x + 28, y + 52), name, fill=0, font=title_font)
    draw.text((x + 30, y + 96), brand, fill=0, font=brand_font)
    badge_text = "彩虹" if rainbow else material
    bb = draw.textbbox((0,0), badge_text, font=badge_font)
    bw = bb[2]-bb[0]
    draw.rectangle([x + w - bw - 52, y + 54, x + w - 24, y + 86], outline=0, width=2)
    draw.text((x + w - bw - 38, y + 63), badge_text, fill=0, font=badge_font)

    gauge = [x + 34, y + 144, x + 160, y + 560]
    draw.rectangle(gauge, outline=0, width=2)
    inner_h = gauge[3] - gauge[1] - 8
    fill_h = round(inner_h * pct / 100)
    if fill_h > 0:
        fy = gauge[3] - 4 - fill_h
        draw.rectangle([gauge[0] + 4, fy, gauge[2] - 4, gauge[3] - 4], fill=0)
    for tick in (25,50,75):
        ty = gauge[3] - round((gauge[3]-gauge[1]) * tick / 100)
        draw.line([gauge[0]-10, ty, gauge[2]+10, ty], fill=0, width=1)
        draw.text((gauge[2] + 16, ty - 10), f"{tick}", fill=0, font=head_font)

    pct_text = f"{pct:.0f}%"
    pb = draw.textbbox((0,0), pct_text, font=percent_font)
    pw = pb[2]-pb[0]
    draw.text((x + 238, y + 162), pct_text, fill=0, font=percent_font)
    remain_big = f"{float(grams):.0f}g" if grams not in (None, "") else "--"
    draw.text((x + 246, y + 232), remain_big, fill=0, font=percent_font)
    draw.text((x + 244, y + 318), "当前剩余", fill=0, font=label_font)
    draw.text((x + 244, y + 350), footer, fill=0, font=brand_font)
    draw.rectangle([x + 232, y + 394, x + w - 28, y + 466], outline=0, width=2)
    total_text = f"总量 {float(total):.0f}g" if total not in (None, "") else "总量 --"
    draw.text((x + 254, y + 418), total_text, fill=0, font=brand_font)

    band_top = y + 600
    draw.rectangle([x + 24, band_top, x + w - 24, band_top + 84], outline=0, width=2)
    cols = [
        ("材料", material),
        ("色值", color_hex),
        ("状态", "彩虹料" if rainbow else "普通料"),
    ]
    col_w = (w - 48) // 3
    for i, (label, val) in enumerate(cols):
        bx = x + 24 + i * col_w
        if i > 0:
            draw.line([bx, band_top, bx, band_top + 84], fill=0, width=2)
        draw.text((bx + 12, band_top + 10), label, fill=0, font=head_font)
        vb = draw.textbbox((0,0), val, font=value_font)
        vw = vb[2]-vb[0]
        draw.text((bx + (col_w-vw)//2, band_top + 38), val[:10], fill=0, font=value_font)


def render_bilibili_status(draw: ImageDraw.ImageDraw, widget: Widget, style: GlobalStyle, bridge: HermesBridge | None) -> None:
    x, y, w, h = widget.x, widget.y, widget.w, widget.h
    font_path = widget.font_path or style.font_path
    title_font = get_font(font_path, 28)
    big_font = get_font(font_path, 42)
    label_font = get_font(font_path, 18)
    value_font = get_font(font_path, 24)
    small_font = get_font(font_path, 16)
    data = bridge.read_bilibili() if bridge else {}
    draw.rectangle([x, y, x + w, y + h], outline=0, width=2)
    if not isinstance(data, dict) or not data:
        draw.text((x + 18, y + 24), "B站未接入", fill=0, font=title_font)
        draw.text((x + 18, y + 72), "请在左侧填 UID / Cookie 后点击 读取B站", fill=0, font=small_font)
        return
    name = str(data.get('account_name') or '未命名账号')[:18]
    followers = int(data.get('followers') or 0)
    replies = int(data.get('new_replies') or 0)
    messages = int(data.get('new_messages') or 0)
    latest = data.get('latest_video') or {}
    latest_title = str(latest.get('title') or '暂无视频')[:24]
    latest_views = int(latest.get('views') or 0)
    updated = str(data.get('updated_at') or '')[:16].replace('T', ' ')
    draw.text((x + 18, y + 18), name, fill=0, font=title_font)
    draw.text((x + 18, y + 58), "BILIBILI STATUS", fill=0, font=small_font)
    cards = [
        ('粉丝', f'{followers}'),
        ('回复', f'{replies}'),
        ('消息', f'{messages}'),
    ]
    gap = 12
    card_w = (w - 36 - gap * 2) // 3
    for i, (label, value) in enumerate(cards):
        bx = x + 18 + i * (card_w + gap)
        by = y + 98
        draw.rectangle([bx, by, bx + card_w, by + 110], outline=0, width=2)
        draw.text((bx + 12, by + 10), label, fill=0, font=label_font)
        vb = draw.textbbox((0, 0), value, font=big_font)
        vw = vb[2] - vb[0]
        draw.text((bx + (card_w - vw)//2, by + 42), value, fill=0, font=big_font)
    draw.rectangle([x + 18, y + 236, x + w - 18, y + 366], outline=0, width=2)
    draw.text((x + 32, y + 250), '最新视频', fill=0, font=label_font)
    draw.text((x + 32, y + 286), latest_title, fill=0, font=value_font)
    draw.text((x + 32, y + 326), f'播放 {latest_views}', fill=0, font=value_font)
    draw.text((x + 18, y + h - 32), f'更新 {updated}', fill=0, font=small_font)


def render_printmana_8slot_bars(draw: ImageDraw.ImageDraw, widget: Widget, style: GlobalStyle, bridge: HermesBridge | None) -> None:
    x, y, w, h = widget.x, widget.y, widget.w, widget.h
    font_path = widget.font_path or style.font_path
    title_font = get_font(font_path, 20)
    label_font = get_font(font_path, 18)
    percent_font = get_font(font_path, 28)
    grams_font = get_font(font_path, 20)
    name_font = get_font(font_path, 18)
    data = bridge.read_printmana() if bridge else {}
    primary = data.get("primary") if isinstance(data, dict) else {}
    ams_units = {unit.get('index', -1): unit for unit in (primary.get('ams') or [])} if isinstance(primary, dict) else {}
    draw.rectangle([x, y, x + w, y + h], outline=0, width=2)
    draw.text((x + 12, y + 8), "AMS 双仓 8槽余量", fill=0, font=title_font)

    def draw_centered_text(cx: int, top: int, text: str, font, fill: int = 0):
        bbox = draw.textbbox((0, 0), text, font=font)
        tw = bbox[2] - bbox[0]
        draw.text((cx - tw // 2, top), text, fill=fill, font=font)

    def draw_half(unit_index: int, top_y: int, title: str):
        block_h = 232
        draw.rectangle([x + 8, top_y, x + w - 8, top_y + block_h], outline=0, width=1)
        draw.text((x + 18, top_y + 8), title, fill=0, font=label_font)
        unit = ams_units.get(unit_index, {})
        slots = {slot.get('slot', -1): slot for slot in (unit.get('slots') or [])} if isinstance(unit, dict) else {}
        col_gap = 8
        col_w = (w - 34 - col_gap * 3) // 4
        card_top = top_y + 34
        card_h = 184
        bar_top = card_top + 26
        bar_h = 108
        for slot_index in range(4):
            slot = slots.get(slot_index, {})
            bound = slot.get('bound') or {}
            remain_pct = bound.get('remainingPercent', slot.get('remainPercent', 0))
            try:
                pct = max(0.0, min(100.0, float(remain_pct)))
            except Exception:
                pct = 0.0
            grams = bound.get('remainingGram')
            name = str(bound.get('name') or slot.get('type') or 'EMPTY')[:6]
            cx = x + 16 + slot_index * (col_w + col_gap)
            draw.rectangle([cx, card_top, cx + col_w, card_top + card_h], outline=0, width=1)
            center_x = cx + col_w // 2
            if unit_index == 0:
                slot_text = f"A{slot_index + 1}"
            elif unit_index == 1:
                slot_text = f"B{slot_index + 1}"
            else:
                slot_text = f"HT{slot_index + 1}"
            draw_centered_text(center_x, card_top + 4, slot_text, label_font)
            bx = cx + 16
            bw = col_w - 32
            draw.rectangle([bx, bar_top, bx + bw, bar_top + bar_h], outline=0, width=2)
            fill_h = round((bar_h - 8) * pct / 100)
            if fill_h > 0:
                fy = bar_top + bar_h - 4 - fill_h
                draw.rectangle([bx + 4, fy, bx + bw - 4, bar_top + bar_h - 4], fill=0)
            pct_y = bar_top + (bar_h - 28) // 2
            pct_fill = 255 if pct >= 45 else 0
            draw_centered_text(center_x, pct_y, f"{pct:.0f}%", percent_font, fill=pct_fill)
            if grams not in (None, ""):
                draw_centered_text(center_x, bar_top + bar_h + 12, f"{float(grams):.0f}g", grams_font)
            draw_centered_text(center_x, bar_top + bar_h + 68, name, name_font)

    draw_half(0, y + 42, "AMS A    A1-A4")
    draw_half(1, y + 314, "AMS B    B1-B4")


def render_weather_overview_card(draw: ImageDraw.ImageDraw, widget: Widget, style: GlobalStyle, bridge: HermesBridge | None) -> None:
    x, y, w, h = widget.x, widget.y, widget.w, widget.h
    city = widget.city or "Shanghai"
    cached = bridge.read_content_cache(f"weather::{city}") if bridge else {}
    payload = cached.get("payload") if isinstance(cached, dict) else {}
    title_font = get_font(widget.font_path or style.font_path, 34)
    temp_font = get_font(widget.font_path or style.font_path, 78)
    meta_font = get_font(widget.font_path or style.font_path, 30)
    small_font = get_font(widget.font_path or style.font_path, 24)
    icon_font = get_weather_icon_font(224)
    draw.rectangle([x, y, x + w, y + h], outline=0, width=2)
    if not isinstance(payload, dict) or not payload:
        draw.text((x + 20, y + 24), city, fill=0, font=title_font)
        draw.text((x + 20, y + 78), "WEATHER CACHE EMPTY", fill=0, font=meta_font)
        return
    name = str(payload.get("name") or city)
    desc = str(payload.get("description") or "天气")
    temp = str(payload.get("temperature") or "?")
    temp_min = str(payload.get("temp_min") or "?")
    temp_max = str(payload.get("temp_max") or "?")
    wind = str(payload.get("wind_speed") or "?")
    code = payload.get("weather_code")
    updated = str(payload.get("updated_at") or "")[:16].replace("T", " ")
    draw.text((x + 22, y + 18), name, fill=0, font=title_font)
    db = draw.textbbox((0, 0), desc, font=meta_font)
    dw = db[2] - db[0]
    desc_x = x + 168
    draw.text((desc_x, y + 20), desc, fill=0, font=meta_font)
    temp_text = f"{temp}°"
    tb = draw.textbbox((0, 0), temp_text, font=temp_font)
    tw = tb[2] - tb[0]
    draw.text((x + w - tw - 24, y + 18), temp_text, fill=0, font=temp_font)
    top_panel = (x + 24, y + 112, x + w - 24, y + 320)
    icon = weather_icon_char(code)
    ib = draw.textbbox((0, 0), icon, font=icon_font)
    iw = ib[2] - ib[0]
    ih = ib[3] - ib[1]
    panel_w = top_panel[2] - top_panel[0]
    panel_h = top_panel[3] - top_panel[1]
    icon_x = top_panel[0] + (panel_w - iw) // 2
    icon_y = top_panel[1] + (panel_h - ih) // 2 - 76
    draw.text((icon_x, icon_y), icon, fill=0, font=icon_font)
    draw.rectangle([x + 24, y + 336, x + w - 24, y + 420], outline=0, width=2)
    low_text = f"最低 {temp_min}°"
    high_text = f"最高 {temp_max}°"
    lb = draw.textbbox((0, 0), low_text, font=meta_font)
    hb = draw.textbbox((0, 0), high_text, font=meta_font)
    lw = lb[2] - lb[0]
    hw = hb[2] - hb[0]
    draw.text((x + 42, y + 364), low_text, fill=0, font=meta_font)
    draw.text((x + w - hw - 42, y + 364), high_text, fill=0, font=meta_font)
    draw.rectangle([x + 24, y + 440, x + w - 24, y + 520], outline=0, width=2)
    wind_title = "风速"
    wind_text = f"{wind} km/h"
    wb = draw.textbbox((0, 0), wind_title, font=small_font)
    ww = wb[2] - wb[0]
    wtb = draw.textbbox((0, 0), wind_text, font=meta_font)
    wtw = wtb[2] - wtb[0]
    gap = 20
    total_w = ww + gap + wtw
    start_x = x + (w - total_w) // 2
    baseline_y = y + 474
    draw.text((start_x, baseline_y), wind_title, fill=0, font=small_font)
    draw.text((start_x + ww + gap, baseline_y - 6), wind_text, fill=0, font=meta_font)
    cache_text = f"缓存 {updated}"
    cb = draw.textbbox((0, 0), cache_text, font=small_font)
    cw = cb[2] - cb[0]
    draw.text((300 - cw // 2, 750), cache_text, fill=0, font=small_font)


def render_weather_weekly_cards(draw: ImageDraw.ImageDraw, widget: Widget, style: GlobalStyle, bridge: HermesBridge | None) -> None:
    x, y, w, h = widget.x, widget.y, widget.w, widget.h
    city = widget.city or "Shanghai"
    days = max(1, int(widget.max_items or 6))
    cached = bridge.read_content_cache(f"weather_weekly::{city}::{days}") if bridge else {}
    payload = cached.get("payload") if isinstance(cached, dict) else {}
    title_font = get_font(widget.font_path or style.font_path, 24)
    temp_font = get_font(widget.font_path or style.font_path, 26)
    desc_font = get_font(widget.font_path or style.font_path, 20)
    icon_font = get_weather_icon_font(84)
    if not isinstance(payload, dict) or not payload or not payload.get("days"):
        draw.rectangle([x, y, x + w, y + h], outline=0, width=2)
        draw.text((x + 20, y + 24), f"{city} WEEK CACHE EMPTY", fill=0, font=title_font)
        return
    entries = payload.get("days", [])
    if isinstance(entries, list) and len(entries) > days:
        entries = entries[1:days + 1]
    else:
        entries = entries[:days]
    cols = 2
    rows = (len(entries) + 1) // 2
    gap = 12
    card_w = (w - gap) // cols
    card_h = max(96, (h - gap * max(0, rows - 1)) // max(1, rows))
    for index, item in enumerate(entries):
        col = index % cols
        row = index // cols
        bx = x + col * (card_w + gap)
        by = y + row * (card_h + gap)
        draw.rectangle([bx, by, bx + card_w, by + card_h], outline=0, width=2)
        draw.text((bx + 12, by + 12), str(item.get("weekday") or "--"), fill=0, font=title_font)
        temp_text = f"{item.get('temp_min', '?')}~{item.get('temp_max', '?')}°"
        tb = draw.textbbox((0, 0), temp_text, font=temp_font)
        tw = tb[2] - tb[0]
        draw.text((bx + card_w - tw - 12, by + 14), temp_text, fill=0, font=temp_font)
        icon = weather_icon_char(item.get("weather_code"))
        ib = draw.textbbox((0, 0), icon, font=icon_font)
        iw = ib[2] - ib[0]
        ih = ib[3] - ib[1]
        icon_x = bx + (card_w - iw) // 2 + 12
        icon_y = by + max(38, (card_h - ih) // 2 - 4)
        draw.text((icon_x, icon_y), icon, fill=0, font=icon_font)
        desc = str(item.get("description") or "天气")[:8]
        draw.text((bx + 14, by + card_h - 34), desc, fill=0, font=desc_font)


def render_traffic_dashboard_card(draw: ImageDraw.ImageDraw, widget: Widget, style: GlobalStyle, bridge: HermesBridge | None) -> None:
    x, y, w, h = widget.x, widget.y, widget.w, widget.h
    extra = widget.extra if isinstance(widget.extra, dict) else {}
    endpoint = extra.get("endpoint")
    token = extra.get("token")
    cache_key = f"traffic::{endpoint or 'default'}::{token or 'default'}"
    cached = bridge.read_content_cache(cache_key) if bridge else {}
    lines = cached.get("lines") if isinstance(cached, dict) else []
    title_font = get_font(widget.font_path or style.font_path, 30)
    big_font = get_font(widget.font_path or style.font_path, 58)
    meta_font = get_font(widget.font_path or style.font_path, 22)
    small_font = get_font(widget.font_path or style.font_path, 18)
    draw.rectangle([x, y, x + w, y + h], outline=255, width=2)
    if not isinstance(lines, list) or len(lines) < 6:
        draw.text((x + 20, y + 24), "VPS 缓存为空", fill=255, font=title_font)
        return
    status = lines[0].replace("VPS Traffic", "") or "OK"
    used_line = lines[1].replace("Used:", "已用：").replace(" / ", " / ")
    remain_line = lines[2].replace("Remain:", "剩余：")
    percent_text = lines[3].replace("Percent:", "").strip()
    message = lines[4]
    cycle = lines[5].replace("Cycle:", "周期：")
    try:
        percent_value = float(percent_text.rstrip('%'))
    except Exception:
        percent_value = 0.0
    draw.text((x + 18, y + 16), "VPS 流量面板", fill=255, font=title_font)
    draw.text((x + w - 148, y + 22), f"状态 {status}", fill=255, font=small_font)
    pb = draw.textbbox((0, 0), percent_text, font=big_font)
    pw = pb[2] - pb[0]
    draw.text((x + (w - pw)//2, y + 72), percent_text, fill=255, font=big_font)
    bar_x1, bar_y1 = x + 46, y + 154
    bar_x2, bar_y2 = x + w - 46, y + 192
    draw.rectangle([bar_x1, bar_y1, bar_x2, bar_y2], outline=255, width=2)
    fill_w = round((bar_x2 - bar_x1 - 8) * max(0, min(100, percent_value)) / 100)
    if fill_w > 0:
        draw.rectangle([bar_x1 + 4, bar_y1 + 4, bar_x1 + 4 + fill_w, bar_y2 - 4], fill=255)
    cards = [
        ("◉", "已用", used_line.replace("已用：", "")),
        ("◎", "剩余", remain_line.replace("剩余：", "")),
        ("◌", "周期", cycle.replace("周期：", "")),
    ]
    gap = 14
    card_w = (w - 36 - gap * 2) // 3
    for i, (icon, label, value) in enumerate(cards):
        bx = x + 18 + i * (card_w + gap)
        by = y + 222
        draw.rectangle([bx, by, bx + card_w, by + 120], outline=255, width=2)
        draw.text((bx + 12, by + 10), icon, fill=255, font=meta_font)
        draw.text((bx + 42, by + 10), label, fill=255, font=small_font)
        vals = wrap_text(draw, value, meta_font, card_w - 24)[:2]
        vy = by + 48
        for line in vals:
            draw.text((bx + 12, vy), line, fill=255, font=meta_font)
            vy += 26
    draw.rectangle([x + 18, y + 364, x + w - 18, y + 452], outline=255, width=2)
    draw.text((x + 28, y + 382), "提示", fill=255, font=small_font)
    for idx, line in enumerate(wrap_text(draw, message, meta_font, w - 72)[:2]):
        draw.text((x + 28, y + 408 + idx * 24), line, fill=255, font=meta_font)
    updated = str(cached.get("updated_at") or "")[:16].replace("T", " ") if isinstance(cached, dict) else ""
    if updated:
        draw.text((x + 18, y + h - 28), f"缓存 {updated}", fill=255, font=small_font)


def render_news_dashboard_card(draw: ImageDraw.ImageDraw, widget: Widget, style: GlobalStyle, bridge: HermesBridge | None) -> None:
    x, y, w, h = widget.x, widget.y, widget.w, widget.h
    cache_key = f"rss::{widget.rss_url}::{widget.max_items}"
    cached = bridge.read_content_cache(cache_key) if bridge else {}
    lines = cached.get("lines") if isinstance(cached, dict) else []
    item_font = get_font(widget.font_path or style.font_path, 32)
    line_font = get_font(widget.font_path or style.font_path, 30)
    empty_font = get_font(widget.font_path or style.font_path, 36)
    draw.rectangle([x, y, x + w, y + h], outline=0, width=2)
    if not isinstance(lines, list) or not lines:
        draw.text((x + 20, y + 24), "新闻缓存为空", fill=0, font=empty_font)
        return
    card_gap = 10
    card_h = (h - card_gap * 3) // 4
    inner_x1 = x + 16
    inner_x2 = x + w - 16
    text_width = w - 56
    for idx, title in enumerate(lines[:4]):
        by = y + idx * (card_h + card_gap)
        draw.rectangle([inner_x1, by, inner_x2, by + card_h], outline=0, width=2)
        wrapped = wrap_text(draw, str(title).strip(), item_font, text_width)
        wrapped = wrapped[:3]
        line_h = 36
        total_h = max(line_h, len(wrapped) * line_h)
        ty = by + max(16, (card_h - total_h) // 2)
        for line in wrapped:
            draw.text((x + 28, ty), line, fill=0, font=line_font)
            ty += line_h


def render_hermes_chat_bubbles(draw: ImageDraw.ImageDraw, widget: Widget, style: GlobalStyle, bridge: HermesBridge | None) -> None:
    x, y, w, h = widget.x, widget.y, widget.w, widget.h
    session = bridge.read_session_status() if bridge else {}
    title_font = get_font(widget.font_path or style.font_path, 22)
    bubble_font = get_font(widget.font_path or style.font_path, 24)
    meta_font = get_font(widget.font_path or style.font_path, 18)
    draw.rectangle([x, y, x + w, y + h], outline=0, width=2)
    if not isinstance(session, dict) or not session:
        draw.text((x + 20, y + 20), "聊天摘要未就绪", fill=0, font=title_font)
        return

    summary = str(session.get("summary") or "").strip()
    updated = str(session.get("updated_at") or "").strip()[:16].replace("T", " ")
    recent_messages = session.get("recent_messages") or []
    bubbles = []
    if isinstance(recent_messages, list):
        for item in recent_messages[-4:]:
            if not isinstance(item, dict):
                continue
            role = str(item.get("role") or "").strip()
            content = str(item.get("content") or "").strip()
            if role in {"user", "assistant"} and content:
                bubbles.append({"role": role, "content": content})
    if not bubbles:
        user_last = str(session.get("user_last") or "").strip()
        assistant_last = str(session.get("assistant_last") or "").strip()
        if user_last:
            bubbles.append({"role": "user", "content": user_last})
        if assistant_last:
            bubbles.append({"role": "assistant", "content": assistant_last})

    if summary:
        summary_text = " ".join(summary.split())
        if len(summary_text) > 36:
            summary_text = summary_text[:35].rstrip() + "…"
        draw.text((x + 18, y + 16), summary_text, fill=0, font=title_font)
    if updated:
        bbox = draw.textbbox((0, 0), updated, font=meta_font)
        draw.text((x + w - (bbox[2] - bbox[0]) - 18, y + 20), updated, fill=0, font=meta_font)

    top = y + 58
    bubble_gap = 14
    max_bubble_w = int(w * 0.74)
    cursor_y = top
    for item in bubbles:
        role = item["role"]
        content = item["content"]
        wrapped = wrap_text(draw, content, bubble_font, max_bubble_w - 26)[:4] or [content]
        line_h = 32
        bubble_h = 18 + len(wrapped) * line_h
        text_w = 0
        for line in wrapped:
            bbox = draw.textbbox((0, 0), line, font=bubble_font)
            text_w = max(text_w, bbox[2] - bbox[0])
        bubble_w = min(max_bubble_w, max(120, text_w + 28))
        bx = x + 16 if role == "assistant" else x + w - bubble_w - 16
        invert = role == "user"
        draw.rounded_rectangle([bx, cursor_y, bx + bubble_w, cursor_y + bubble_h], radius=16, outline=0, width=2, fill=0 if invert else 255)
        ty = cursor_y + 10
        for line in wrapped:
            draw.text((bx + 14, ty), line, fill=255 if invert else 0, font=bubble_font)
            ty += line_h
        cursor_y += bubble_h + bubble_gap
        if cursor_y > y + h - 36:
            break


def render_hermes_work_board(draw: ImageDraw.ImageDraw, widget: Widget, style: GlobalStyle, bridge: HermesBridge | None) -> None:
    x, y, w, h = widget.x, widget.y, widget.w, widget.h
    ws = bridge.read_work_status() if bridge else {}
    title_font = get_font(widget.font_path or style.font_path, 22)
    hero_font = get_font(widget.font_path or style.font_path, 34)
    meta_font = get_font(widget.font_path or style.font_path, 20)
    small_font = get_font(widget.font_path or style.font_path, 16)
    draw.rectangle([x, y, x + w, y + h], outline=0, width=2)
    if not isinstance(ws, dict) or not ws:
        draw.text((x + 20, y + 20), "工作仪表未就绪", fill=0, font=title_font)
        return
    summary = str(ws.get("summary") or "").strip()
    current_task = str(ws.get("current_task") or "").strip() or "等待新任务"
    next_task = str(ws.get("next_task") or "").strip() or "继续当前项"
    updated = str(ws.get("updated_at") or "").strip()[:16].replace("T", " ")
    blocked = bool(ws.get("blocked"))
    blocker = str(ws.get("blocker") or "").strip()

    draw.text((x + 18, y + 14), "工作仪表", fill=0, font=title_font)
    status_text = "阻塞" if blocked else "冲出！"
    badge = [x + w - 104, y + 12, x + w - 18, y + 42]
    draw.rectangle(badge, outline=0, width=2, fill=0 if blocked else 255)
    bbox = draw.textbbox((0, 0), status_text, font=small_font)
    draw.text((badge[0] + (badge[2]-badge[0]-(bbox[2]-bbox[0]))//2, badge[1] + 6), status_text, fill=255 if blocked else 0, font=small_font)

    task_box = [x + 18, y + 56, x + w - 18, y + 152]
    draw.rectangle(task_box, outline=0, width=2)
    draw.text((x + 30, y + 68), "当前任务", fill=0, font=small_font)
    current_lines = wrap_text(draw, current_task, hero_font, w - 72)[:2]
    ty = y + 96
    for line in current_lines:
        draw.text((x + 30, ty), line, fill=0, font=hero_font)
        ty += 36

    bar_x1, bar_y1 = x + 22, y + 168
    bar_x2, bar_y2 = x + w - 22, y + 194
    draw.rectangle([bar_x1, bar_y1, bar_x2, bar_y2], outline=0, width=2)
    fill_ratio = 0.72 if not blocked else 0.28
    fill_w = round((bar_x2 - bar_x1 - 8) * fill_ratio)
    if fill_w > 0:
        draw.rectangle([bar_x1 + 4, bar_y1 + 4, bar_x1 + 4 + fill_w, bar_y2 - 4], fill=0)
    draw.text((x + 24, y + 202), "进度条", fill=0, font=small_font)
    draw.text((x + w - 58, y + 202), "72%" if not blocked else "28%", fill=0, font=small_font)

    cards_top = y + 232
    min_cards_bottom = cards_top + 96
    cards_bottom = max(min_cards_bottom, y + h - 56)
    cards_h = max(96, cards_bottom - cards_top)
    card_gap = 12
    card_w = (w - 48 - card_gap) // 2
    cards = [("新线索", next_task), ("洞见", summary or current_task)]
    for index, (label, value) in enumerate(cards):
        bx = x + 18 + index * (card_w + card_gap)
        draw.rectangle([bx, cards_top, bx + card_w, cards_bottom], outline=0, width=2)
        header_h = 30
        if index == 0:
            draw.rectangle([bx, cards_top, bx + card_w, cards_top + header_h], fill=0)
            draw.text((bx + 10, cards_top + 7), label, fill=255, font=small_font)
        else:
            draw.text((bx + 10, cards_top + 7), label, fill=0, font=small_font)
        lines = wrap_text(draw, value, meta_font, card_w - 24)
        line_h = 22
        max_lines = max(2, (cards_h - header_h - 18) // line_h)
        ly = cards_top + header_h + 10
        for line in lines[:max_lines]:
            draw.text((bx + 12, ly), line, fill=0, font=meta_font)
            ly += line_h

    footer_y = y + h - 46
    footer_text = blocker if blocked and blocker else (f"{updated}" if updated else "等待同步")
    footer_text = f"[ terminal ]   {footer_text}" if footer_text else "[ terminal ]"
    fb = draw.textbbox((0, 0), footer_text, font=small_font)
    fw = fb[2] - fb[0]
    draw.text((x + (w - fw)//2, footer_y + 8), footer_text, fill=0, font=small_font)


def render_system_dashboard_card(draw: ImageDraw.ImageDraw, widget: Widget, style: GlobalStyle) -> None:
    x, y, w, h = widget.x, widget.y, widget.w, widget.h
    metrics = get_system_metrics()
    title_font = get_font(widget.font_path or style.font_path, 22)
    hero_font = get_font(widget.font_path or style.font_path, 30)
    value_font = get_font(widget.font_path or style.font_path, 26)
    small_font = get_font(widget.font_path or style.font_path, 16)
    draw.rectangle([x, y, x + w, y + h], outline=0, width=2)
    draw.text((x + 18, y + 14), "系统状态", fill=0, font=title_font)

    cpu_user = float(metrics.get("cpu_user") or 0.0)
    cpu_sys = float(metrics.get("cpu_sys") or 0.0)
    cpu_idle = float(metrics.get("cpu_idle") or 0.0)
    cpu_total = max(0.0, min(100.0, cpu_user + cpu_sys))
    mem_pressure = int(metrics.get("memory_pressure") or 0)
    disk_used = int(metrics.get("disk_used_pct") or 0)

    cards = [
        ("CPU", f"{cpu_total:.0f}%", cpu_total),
        ("内存", f"{mem_pressure}%", mem_pressure),
        ("磁盘", f"{disk_used}%", disk_used),
    ]
    gap = 12
    card_w = (w - 36 - gap * 2) // 3
    for index, (label, value, pct) in enumerate(cards):
        bx = x + 18 + index * (card_w + gap)
        by = y + 52
        draw.rectangle([bx, by, bx + card_w, by + 118], outline=0, width=2)
        draw.text((bx + 10, by + 10), label, fill=0, font=small_font)
        vb = draw.textbbox((0, 0), value, font=hero_font)
        vw = vb[2] - vb[0]
        draw.text((bx + (card_w - vw)//2, by + 34), value, fill=0, font=hero_font)
        bar_x1, bar_y1 = bx + 10, by + 86
        bar_x2, bar_y2 = bx + card_w - 10, by + 104
        draw.rectangle([bar_x1, bar_y1, bar_x2, bar_y2], outline=0, width=2)
        fill_w = round((bar_x2 - bar_x1 - 6) * max(0, min(100, pct)) / 100)
        if fill_w > 0:
            draw.rectangle([bar_x1 + 3, bar_y1 + 3, bar_x1 + 3 + fill_w, bar_y2 - 3], fill=0)

    load_box = [x + 18, y + 188, x + w - 18, y + 276]
    draw.rectangle(load_box, outline=0, width=2)
    draw.text((load_box[0] + 12, load_box[1] + 10), "负载 / 热状态", fill=0, font=small_font)
    load_text = f"{metrics.get('load_1m') or 0:.2f} / {metrics.get('load_5m') or 0:.2f} / {metrics.get('load_15m') or 0:.2f}"
    thermal = str(metrics.get("thermal_status") or "未知")
    draw.text((load_box[0] + 12, load_box[1] + 38), load_text, fill=0, font=value_font)
    draw.text((load_box[0] + 12, load_box[1] + 66), f"热状态 {thermal}", fill=0, font=value_font)

    stats_top = y + 296
    stats = [
        ("CPU 明细", f"U {cpu_user:.1f}% / S {cpu_sys:.1f}% / I {cpu_idle:.1f}%"),
        ("内存", f"{metrics.get('memory_used_gb') or 0:.1f} / {metrics.get('memory_total_gb') or 0:.1f} GB"),
        ("交换", f"IN {metrics.get('swapins') or 0} / OUT {metrics.get('swapouts') or 0}"),
        ("存储", f"剩余 {metrics.get('disk_free_gb') or 0:.1f} GB"),
        ("CPU 限速", f"{metrics.get('cpu_speed_limit') or 100}% / 核心 {metrics.get('cpu_available') or '-'}"),
    ]
    row_h = 34
    for index, (label, value) in enumerate(stats):
        ry = stats_top + index * row_h
        draw.text((x + 20, ry), label, fill=0, font=small_font)
        draw.text((x + 148, ry), value, fill=0, font=small_font)

    footer = str(metrics.get("os") or "")
    if footer:
        draw.text((x + 20, y + h - 30), footer[:42], fill=0, font=small_font)


def resolve_widget_content(widget: Widget, bridge: HermesBridge | None, live_data: bool = True) -> str:
    if widget.type == "text":
        return widget.text
    if widget.type == "clock":
        return datetime.now().strftime(widget.text or "%Y-%m-%d\n%H:%M:%S")
    if widget.type == "system_status":
        return "\n".join(system_lines())
    if widget.type == "weather":
        if not live_data:
            return "\n".join([
                f"{widget.city or 'Beijing'}: 22°C 多云",
                "风速: 8 km/h",
                "今日: 18~26°C",
            ])
        cache_key = f"weather::{widget.city or 'Beijing'}"
        cached = bridge.read_content_cache(cache_key) if bridge else {}
        lines = cached.get("lines") if isinstance(cached, dict) else []
        return "\n".join(lines) if isinstance(lines, list) and lines else f"Weather cache empty: {widget.city or 'Beijing'}"
    if widget.type == "weather_weekly":
        if not live_data:
            return "\n".join([
                "周一 22~29° 晴",
                "周二 23~30° 多云",
                "周三 24~31° 阵雨",
                "周四 25~32° 阴",
                "周五 24~30° 雨",
                "周六 23~29° 多云",
            ])
        cache_key = f"weather_weekly::{widget.city or 'Beijing'}::{widget.max_items or 6}"
        cached = bridge.read_content_cache(cache_key) if bridge else {}
        lines = cached.get("lines") if isinstance(cached, dict) else []
        return "\n".join(lines) if isinstance(lines, list) and lines else f"Weekly weather cache empty: {widget.city or 'Beijing'}"
    if widget.type == "rss_news":
        if not live_data:
            return "\n".join([f"新闻标题 {i + 1}" for i in range(max(1, min(widget.max_items, 5)))])
        cache_key = f"rss::{widget.rss_url}::{widget.max_items}"
        cached = bridge.read_content_cache(cache_key) if bridge else {}
        lines = cached.get("lines") if isinstance(cached, dict) else []
        return "\n".join(lines) if isinstance(lines, list) and lines else "News cache empty"
    if widget.type == "traffic_usage":
        if not live_data:
            return "\n".join([
                "VPS Traffic OK",
                "Used: 128GB / 1000GB",
                "Remain: 872GB",
                "Percent: 12.8%",
                "Preview data",
                "Cycle: 2026-06-01 -> 2026-06-30",
            ])
        endpoint = widget.extra.get("endpoint") if isinstance(widget.extra, dict) else None
        token = widget.extra.get("token") if isinstance(widget.extra, dict) else None
        cache_key = f"traffic::{endpoint or 'default'}::{token or 'default'}"
        cached = bridge.read_content_cache(cache_key) if bridge else {}
        lines = cached.get("lines") if isinstance(cached, dict) else []
        return "\n".join(lines) if isinstance(lines, list) and lines else "Traffic cache empty"
    if widget.type == "hermes_greeting":
        daily = bridge.read_daily() if bridge else {}
        hour = datetime.now().hour
        if hour < 6:
            greeting_prefix = "主人们，凌晨好"
        elif hour < 9:
            greeting_prefix = "主人们，早上好"
        elif hour < 12:
            greeting_prefix = "主人们，上午好"
        elif hour < 14:
            greeting_prefix = "主人们，中午好"
        elif hour < 18:
            greeting_prefix = "主人们，下午好"
        else:
            greeting_prefix = "主人们，晚上好"
        stored = str(daily.get("greeting") or "").strip()
        quote = str(daily.get("quote") or "").strip()
        if stored:
            if "方老大" in stored or "主人们" in stored:
                base = greeting_prefix
            else:
                base = f"{greeting_prefix}\n{stored}"
        else:
            base = greeting_prefix
        return f"{base}\n{quote}".strip() if quote else base
    if widget.type == "hermes_alerts":
        inbox = bridge.read_inbox() if bridge else []
        if not inbox:
            return "No Hermes alerts"
        return "\n".join(f"[{m.get('severity','info')}] {m.get('title','')}: {m.get('body','')}" for m in inbox[:3])
    if widget.type == "hermes_work_status":
        return "__RENDER_HERMES_WORK_BOARD__"
    if widget.type == "hermes_session_status":
        session = bridge.read_session_status() if bridge else {}
        if not session:
            return "No live Hermes session"
        lines: list[str] = []
        title = str(session.get("title") or "Hermes Session").strip()
        if title:
            lines.append(title)
        summary = str(session.get("summary") or "").strip()
        if summary:
            lines.append(summary)
        user_last = str(session.get("user_last") or "").strip()
        if user_last:
            lines.append("主人们: " + user_last)
        assistant_last = str(session.get("assistant_last") or "").strip()
        if assistant_last:
            lines.append("Hermes: " + assistant_last)
        tasks = session.get("tasks") or []
        if isinstance(tasks, list):
            for item in tasks[:3]:
                if isinstance(item, str) and item.strip():
                    lines.append("- " + item.strip())
        updated = str(session.get("updated_at") or "").strip()
        if updated:
            lines.append(updated[:16].replace("T", " "))
        return "\n".join(lines[:8])
    if widget.type == "hermes_custom_text":
        daily = bridge.read_daily() if bridge else {}
        return str(daily.get("custom_text", widget.text))
    if widget.type == "bilibili_status":
        data = bridge.read_bilibili() if bridge else {}
        if not data:
            return "B站状态未接入\n等待登录态"
        lines = []
        if data.get("account_name"):
            lines.append(str(data.get("account_name")))
        if data.get("followers") is not None:
            lines.append(f"粉丝 {data.get('followers')}")
        if data.get("new_replies") is not None:
            lines.append(f"新回复 {data.get('new_replies')}")
        if data.get("new_messages") is not None:
            lines.append(f"新消息 {data.get('new_messages')}")
        latest = data.get("latest_video") or {}
        if isinstance(latest, dict) and latest:
            title = str(latest.get("title") or "最近视频")
            views = latest.get("views", "?")
            lines.append(f"{title}")
            lines.append(f"播放 {views}")
        if data.get("updated_at"):
            lines.append(str(data.get("updated_at"))[:16].replace("T", " "))
        return "\n".join(lines[:7])
    if widget.type == "printmana_overview":
        data = bridge.read_printmana() if bridge else {}
        printers = data.get("printers") if isinstance(data, dict) else []
        if not printers:
            return "NO DATA"
        printer = printers[0]
        name = str(printer.get("name") or printer.get("model") or "Printer")[:16]
        status = str(printer.get("statusText") or printer.get("status") or "UNKNOWN")[:8]
        progress = int(printer.get("progress") or 0)
        remain = printer.get("remainingMinutes")
        file_name = str(printer.get("fileName") or "")[:14]
        bar_chars = 10
        filled = max(0, min(bar_chars, round(progress / 100 * bar_chars)))
        bar = "█" * filled + "░" * (bar_chars - filled)
        lines = [
            f"● {name}",
            f"{status}",
            f"[{bar}] {progress}%",
        ]
        if remain not in (None, ""):
            lines.append(f"ETA {remain}m")
        if file_name:
            lines.append(f"JOB {file_name}")
        return "\n".join(lines[:5])
    if widget.type == "printmana_temps":
        data = bridge.read_printmana() if bridge else {}
        primary = data.get("primary") if isinstance(data, dict) else {}
        if not isinstance(primary, dict) or not primary:
            return "温度数据未就绪"
        temps = primary.get("temps") or {}
        nozzles = temps.get('nozzles') or []
        progress = int(primary.get('progress') or 0)
        remain = primary.get('remainingMinutes', '?')
        layer = primary.get('layer', '?')
        total = primary.get('totalLayers', '?')
        bar_chars = 18
        filled = max(0, min(bar_chars, round(progress / 100 * bar_chars)))
        bar = "█" * filled + "░" * (bar_chars - filled)
        lines = [
            str(primary.get("name") or primary.get("model") or "Printer"),
            str(primary.get("statusText") or primary.get("status") or "UNKNOWN"),
            f"[{bar}] {progress}%",
            f"LAYER {layer}/{total}  ETA {remain}m",
        ]
        if nozzles:
            for nozzle in nozzles[:2]:
                active = "*" if nozzle.get('active') else '-'
                lines.append(f"{active} {nozzle.get('name','喷嘴')} {nozzle.get('temp', 0)}C")
        else:
            lines.append(f"♨ NOZZLE  {temps.get('nozzle', 0)}C")
        lines.append(f"▦ BED     {temps.get('bed', 0)}C")
        lines.append(f"⌂ CHAMBER {temps.get('chamber', 0)}C")
        return "\n".join(lines[:8])
    if widget.type == "printmana_filament":
        data = bridge.read_printmana() if bridge else {}
        primary = data.get("primary") if isinstance(data, dict) else {}
        if not isinstance(primary, dict) or not primary:
            return "耗材数据未就绪"
        lines = [str(primary.get("name") or primary.get("model") or "Printer")]
        entries = []
        for unit in (primary.get("ams") or []):
            for slot in (unit.get("slots") or []):
                if slot.get("isEmpty"):
                    continue
                bound = slot.get("bound") or {}
                material = str(bound.get("name") or slot.get("type") or f"AMS{unit.get('index','?')}S{slot.get('slot','?')}")[:18]
                remain_pct = bound.get("remainingPercent", slot.get("remainPercent", 999))
                remain_g = bound.get("remainingGram")
                total_g = bound.get("totalGram")
                entries.append((float(remain_pct if remain_pct not in (None, '') else 999), unit.get('index', '?'), slot.get('slot', '?'), material, remain_g, total_g, remain_pct))
        entries.sort(key=lambda item: item[0])
        shown = 0
        for _, ams_idx, slot_idx, material, remain_g, total_g, remain_pct in entries[:3]:
            lines.append(f"A{ams_idx} S{slot_idx} {material}")
            if remain_g not in (None, "") and total_g not in (None, ""):
                lines.append(f"{remain_g:.1f}g / {total_g:.0f}g  ({float(remain_pct):.1f}%)")
            else:
                lines.append(f"余量 {float(remain_pct):.1f}%")
            shown += 1
        if shown == 0:
            lines.append("无有效 AMS 槽位数据")
        return "\n".join(lines[:8])
    return widget.text or f"Unsupported widget: {widget.type}"
