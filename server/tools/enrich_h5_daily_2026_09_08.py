from __future__ import annotations

import json
import shutil
from datetime import datetime
from pathlib import Path

from PIL import Image


DAY = "2026-09-08"
ROOT = Path(__file__).resolve().parents[1]
DAY_DIR = ROOT / "ipad" / "data" / "h5_daily_photos" / DAY
MANIFEST = DAY_DIR / "manifest.json"
EDITORIAL = [
    ("穹顶仰望", "UNDER THE CANOPY", "人们站在几何玻璃穹顶下仰望高处，远处草地与树木铺向天际。", "#7FC8A9"),
    ("瀑布并肩", "TOGETHER BY THE FALLS", "两个人并肩站在层叠瀑布前，白色水流沿岩石落入池中。", "#67B7D1"),
    ("玫红小门", "MAGENTA DOOR", "穿蓝色衣服的人站在玫红色小门旁，前景有人举起手机拍照。", "#E83E8C"),
    ("甜点一勺", "SPOONFUL OF SWEET", "戴眼镜的孩子坐在餐桌旁，用勺子品尝盘中的浅黄色甜点。", "#F2C66D"),
    ("环球展臂", "ARMS AROUND THE GLOBE", "孩子在巨型环球标志前张开双臂，身后游客穿行于开阔广场。", "#3C91D4"),
    ("霓虹同框", "NEON GROUP NIGHT", "一群人在卡通造型与彩色灯牌前合影，紫粉灯光照亮夜间展区。", "#B74DFF"),
    ("石门之下", "BENEATH THE STONE GATE", "一行人站在刻有中文的大型石门下，灰色门体与绿树构成入口景观。", "#87968A"),
    ("草地招手", "WAVE ACROSS THE LAWN", "两个人站在宽阔草地上，其中一人高高举手，远处还有零散游客。", "#70B657"),
    ("碑前驻足", "PAUSE BY THE MONUMENT", "穿棕色外套的人站在刻字石碑前，林间步道上还有其他游人。", "#9A8063"),
    ("木桌长宴", "LONG TABLE FEAST", "多人围坐在木质长桌旁用餐，桌面摆满碗碟、杯子与共享菜品。", "#C58A54"),
    ("机甲之下", "BENEATH THE MECHA", "戴口罩的人站在巨型蓝白机器人雕像前，抬起一只手与它呼应。", "#5A9BD5"),
    ("影城展翼", "STUDIO GATE POSE", "一个人在红色拱门建筑前张开双臂，入口上方可见影城英文标识。", "#C9544D"),
    ("古楼冬影", "WINTER AT THE GATE", "三名穿厚外套的人站在传统多层城楼前，在阴天广场上并肩合影。", "#B94B43"),
    ("山亭远眺", "VIEW FROM THE RAIL", "穿棕色外套的人倚近石栏远眺，树林间露出一座浅色圆顶建筑。", "#668F62"),
    ("心愿花墙", "WISHES IN COLOR", "戴眼镜的孩子在缀满彩色心形挂饰的墙前比出剪刀手，身后站着两位成人。", "#F04C79"),
    ("银色镜头", "THE SILVER MACHINE", "孩子站在大型银色机械装置旁，鲜红展墙上的白色曲线环绕其后。", "#D94B43"),
    ("峡谷听瀑", "WATERFALL TRAIL", "穿彩色外套的孩子站在峡谷步道栏杆旁，身侧瀑布从高处倾泻而下。", "#4FA3A5"),
    ("红台双座", "TWO ON THE RED RIDE", "两个孩子坐在大型红色圆台上，周围绿植与暖色灯柱映亮夜色。", "#D74A3A"),
    ("庭院石阶", "COURTYARD STEPS", "穿迷彩外套的孩子站在传统庭院石阶旁，深色木构建筑延伸在身后。", "#697C57"),
    ("掌心星火", "SPARK IN HAND", "戴眼镜的孩子在暗处把点燃的仙女棒伸向镜头，白金色火花照亮面庞。", "#FFD166"),
]


def main() -> None:
    photos = sorted(DAY_DIR.glob("photo-*.jpeg"))
    if len(photos) != 20:
        raise RuntimeError(f"expected 20 photos, found {len(photos)}")
    items = []
    for index, (photo, editorial) in enumerate(zip(photos, EDITORIAL), 1):
        with Image.open(photo) as image:
            width, height = image.size
        title, english, caption, accent = editorial
        items.append({
            "person": "方宇轩",
            "orientation": "landscape" if width > height else "portrait",
            "asset_id": f"daily-{DAY}-{index:02d}",
            "date_display": "",
            "width": width,
            "height": height,
            "pixel_width": width,
            "pixel_height": height,
            "image_path": str(photo),
            "image_url": f"/assets/h5-photo/{DAY}/{photo.name}",
            "poster_title": title,
            "poster_english": english,
            "ai_caption": caption,
            "poster_accent": accent,
            "caption_asset_id": f"daily-{DAY}-{index:02d}",
            "caption_source": "visual_editorial_review",
        })
    for field in ("poster_title", "poster_english", "ai_caption"):
        values = [str(item[field]).strip() for item in items]
        if len(values) != 20 or len(set(values)) != 20 or not all(values):
            raise RuntimeError(f"invalid unique editorial field: {field}")
    payload = {
        "date": DAY,
        "person": "方宇轩",
        "count": 20,
        "created_at": datetime.now().isoformat(),
        "editorial_updated_at": datetime.now().isoformat(),
        "items": items,
    }
    temporary = MANIFEST.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(MANIFEST)
    for cache in DAY_DIR.glob("rendered-v*"):
        if cache.is_dir():
            shutil.rmtree(cache)
    print(json.dumps({"count": len(items), "unique": {field: len({item[field] for item in items}) for field in ("poster_title", "poster_english", "ai_caption")}, "manifest": str(MANIFEST)}, ensure_ascii=False))


if __name__ == "__main__":
    main()