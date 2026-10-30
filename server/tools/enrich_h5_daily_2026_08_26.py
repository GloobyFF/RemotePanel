"""Apply reviewed, image-grounded editorial fields to the daily H5 photo set."""
import json
import os
from datetime import datetime
from pathlib import Path


DAY = "2026-08-26"
MANIFEST = Path(__file__).resolve().parents[1] / "ipad" / "data" / "h5_daily_photos" / DAY / "manifest.json"
NOTES = [
    ("红衣合影", "RED OUTFITS", "红衣男孩与长者靠近镜头，在室内并肩合影。", "#C92D3D"),
    ("馆前合照", "MUSEUM SIGN", "几人站在博物馆标牌前，身后是树木与入口建筑。", "#465B6B"),
    ("绿廊同行", "GARDEN WALK", "两人走在植物环绕的木栈道上，前景有手指掠过镜头。", "#5D8E62"),
    ("琴边侧望", "PIANO SIDE", "戴黄框眼镜的男孩侧望钢琴键盘，手停在琴边。", "#D39A35"),
    ("山栏合影", "MOUNTAIN RAIL", "成人与孩子站在石栏旁，背后是岩壁和晴空。", "#688B5E"),
    ("床上阅读", "BOOK IN BED", "戴眼镜的男孩靠着枕头坐在床上，低头翻读书页。", "#7992A8"),
    ("草间相伴", "TALL GRASS", "成人和孩子站在高草间，抬手整理头边物件。", "#8EA86B"),
    ("朱门庭院", "RED GATE", "男孩站在朱红门楼前，檐角与石地铺开在身后。", "#A33D32"),
    ("钢琴演奏", "PIANO PLAY", "男孩坐在钢琴前按下琴键，展柜与暖灯围在旁边。", "#AA8051"),
    ("广场指向", "PLAZA POINT", "男孩站在广场入口前抬手指向一侧，游客散在远处。", "#6B6BAA"),
    ("尖顶之前", "TOWER FRONT", "男孩站在栏杆前看向镜头，尖顶建筑立在蓝天下。", "#679ACB"),
    ("积木门洞", "BLOCK PORTAL", "男孩站进彩色积木围出的门洞，几何色块铺满背景。", "#E5B91D"),
    ("灯树街角", "LIGHT TREE", "戴帽子的人站在街边灯树旁，金色灯点落在夜色里。", "#D2A843"),
    ("餐桌照看", "TABLE CARE", "成人在餐桌旁扶着孩子，盘碟和饮料摆在桌面。", "#B68B4D"),
    ("车厢相望", "CABIN GLANCE", "两名孩子在车厢座位旁相望，一人手里拿着纸张。", "#8295A6"),
    ("锅前晚餐", "HOT POT TABLE", "成人和孩子围坐在热锅后，红墙与碗碟映着室内灯光。", "#B83A37"),
    ("积木座角", "BLOCK CORNER", "孩子坐在高高的彩色积木角落里，抬头面对镜头。", "#E67E22"),
    ("舞台举手", "STAGE GESTURE", "孩子站在紫蓝灯光的活动屏幕前，抬手做展示动作。", "#7653B6"),
    ("羽饰看屏", "FEATHER PHONE", "戴彩色羽饰的人低头看红色手机，树木与草地在身后。", "#D0A824"),
    ("浅海站立", "SHALLOW SEA", "人物站在海边浅水中，湿沙与白色浪沫延向远处海面。", "#5B93AC"),
]


def main() -> None:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    items = data.get("items", [])
    assert len(items) == len(NOTES) == 20, f"expected 20 items, got {len(items)}"
    for item, (title, english, caption, accent) in zip(items, NOTES):
        item.update({
            "poster_title": title,
            "poster_english": english,
            "ai_caption": caption,
            "poster_accent": accent,
            "caption_source": "visual_editorial_review",
            "caption_asset_id": item.get("asset_id") or Path(item["image_path"]).stem,
        })
    for key in ("poster_title", "poster_english", "ai_caption"):
        values = [str(item.get(key) or "").strip() for item in items]
        assert all(values) and len(set(values)) == 20, f"invalid {key}"
    assert all(str(item.get("poster_accent") or "").strip() for item in items)
    data["count"] = 20
    data["editorial_updated_at"] = datetime.now().isoformat()
    temporary = MANIFEST.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, MANIFEST)
    print(json.dumps({"items": len(items), "updated": data["editorial_updated_at"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()