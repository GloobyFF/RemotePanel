from datetime import datetime
from pathlib import Path
import json
import os
import re

ROOT = Path(__file__).resolve().parents[1]
DAY = "2026-09-02"
MANIFEST = ROOT / "ipad" / "data" / "h5_daily_photos" / DAY / "manifest.json"
EDITORIAL = [
    ("彩绘眼镜像", "PASTEL GLASSES", "戴圆眼镜的孩子以侧脸望向镜头，柔和彩色纹样围在画像四周。", "#D99B78"),
    ("蓝帽围桌", "PARTY TABLE", "大人和孩子围坐长桌用餐，红色桌面与蓝色圆点帽子点亮户外聚会。", "#D44543"),
    ("红门石阶", "RED DOOR STEPS", "人们沿着雕花石栏两侧的宽台阶走向红色门廊，传统建筑占满画面上方。", "#1C5962"),
    ("彩幕舞台", "COLORFUL STAGE", "台上人物面对观众表演，身后的投影屏和彩色帷幕与台前花饰形成热闹背景。", "#D73B58"),
    ("人潮俯拍", "CROWD ABOVE", "戴眼镜的人站在画面前景，红衣行人和其他人群穿过灰色铺地的拥挤通道。", "#B8323B"),
    ("柱间广场", "PLAZA COLUMNS", "穿蓝衣的人站在开阔广场中央，两侧高柱、树木和远处的彩色装置共同展开。", "#4B91BD"),
    ("牌楼合影", "GATEWAY GROUP", "一群人在写有中文牌匾的传统门楼前聚集，前排人物面向镜头举手互动。", "#4D7D9C"),
    ("课桌并坐", "DESK BUDDIES", "两名戴眼镜的孩子并肩坐在课桌前，红白饰物、纸张和文具清晰可见。", "#A83E45"),
    ("塔下蓝天", "TOWER SKY", "三个人站在高塔下的观景平台上合影，栏杆把视线引向直入蓝天的塔身。", "#4B9AD1"),
    ("草地举手", "GREEN FIELD", "孩子和大人铺展在明亮草地上，有人向镜头举起手臂，远处仍有人在活动。", "#52A34A"),
    ("爱心气球", "HEART BALLOONS", "孩子站在爱心气球和粉色心形展板旁，红粉色装饰把室内角落变成庆祝场景。", "#E45A82"),
    ("蛋糕烛光", "CAKE CANDLES", "三个人围在小蛋糕旁，其中一人双手合拢面对点亮的蜡烛，桌面摆着庆祝用品。", "#D95743"),
    ("街边同行", "SIDEWALK WALK", "两个人沿着建筑旁的人行道并肩前行，其中一人手里拿着浅色饮品，车辆在后方经过。", "#1FAA91"),
    ("暗室比耶", "CANDLE VICTORY", "戴眼镜的孩子在昏暗房间里对着蛋糕举起双手比V，彩色灯光映出笑脸和桌面装饰。", "#F0AD3D"),
    ("屏前伸手", "SCREEN DESK", "孩子站在室内桌边伸手触碰电脑屏幕或桌上设备，椅子和窗帘围出安静房间。", "#3E7185"),
    ("餐桌满席", "RESTAURANT TABLES", "多人坐在餐馆桌边用餐，碗盘和杯子铺满桌面，后方红色招牌照亮室内。", "#D93632"),
    ("檐下人群", "EAVES AND PEOPLE", "人们在传统建筑的红门和雕栏台阶间行走，浅蓝衣人物站在纵向画面的前景。", "#28706A"),
    ("花径同行", "FLOWER PATH", "戴浅色帽子的人穿亮青外套走在花坛旁，孩子和更多行人沿树荫小路向前。", "#6B9C38"),
    ("霓虹自拍", "NEON SELFIE", "三个人在夜色中靠近镜头自拍，粉蓝紫色灯牌和装饰光点铺在身后的暗墙上。", "#D45B9B"),
    ("红盒相递", "RED BOX HANDOFF", "男子和穿粉衣的长者在室内面对面共同托住红色盒子，桌椅和花卉画作位于身后。", "#D63C4D"),
]


def main():
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    items = data.get("items") or []
    if len(items) != 20:
        raise SystemExit(f"expected 20 items, got {len(items)}")
    for index, (title, english, caption, accent) in enumerate(EDITORIAL):
        item = items[index]
        item.update({
            "poster_title": title,
            "poster_english": english,
            "ai_caption": caption,
            "poster_accent": accent,
            "caption_source": "vision",
            "caption_asset_id": item.get("asset_id"),
        })
    for key in ("poster_title", "poster_english", "ai_caption"):
        values = [str(item.get(key) or "").strip() for item in items]
        if not all(values) or len(set(values)) != 20:
            raise SystemExit(f"invalid {key}")
    if not all(re.fullmatch(r"#[0-9A-Fa-f]{6}", str(item.get("poster_accent") or "")) for item in items):
        raise SystemExit("invalid accent")
    data["count"] = 20
    data["editorial_updated_at"] = datetime.now().astimezone().isoformat()
    temporary = MANIFEST.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, MANIFEST)
    print(json.dumps({"items": 20, "unique_titles": 20, "unique_english": 20, "unique_captions": 20, "editorial_updated_at": data["editorial_updated_at"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()