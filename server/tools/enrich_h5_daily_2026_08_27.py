from __future__ import annotations

import json
import os
import re
from datetime import datetime
from pathlib import Path

DAY = "2026-08-27"
ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "ipad" / "data" / "h5_daily_photos" / DAY / "manifest.json"
EDITORIAL = [
    ("树下展板", "PHOTO BOARD", "一名戴眼镜的年轻人坐在树旁，双手向镜头展示印有多幅照片的纸板。", "#6E9F45"),
    ("泡沫对话", "FOAM CONVERSATION", "白色泡沫铺满户外场地，穿蓝衣的人正与前景的橙衣参加者交谈。", "#F26A2E"),
    ("琴键练习", "KEYBOARD PRACTICE", "一名戴眼镜的人坐在电子琴前弹奏，琴键、显示器和窗边家具围在身旁。", "#8B5A9E"),
    ("灯笼字墙", "LANTERN LETTERS", "两个人并排坐在粉色座椅上，身后的书法字墙与红灯笼构成合影背景。", "#D8425A"),
    ("桌边一餐", "TABLESIDE MEAL", "一名戴眼镜的人坐在桌边用筷子吃饭，面前摆着米饭、菜肴和饮料杯。", "#C9823B"),
    ("大巴集合", "BUS SIDE GROUP", "一群戴蓝帽、背背包的参加者聚集在大巴车旁，准备结队出发。", "#2E88A7"),
    ("彩框合影", "EVENT FRAME", "多名孩子站在彩色活动宣传框后合影，号码布与卡通图案清晰可见。", "#F0A520"),
    ("屏前操作", "AT THE COMPUTER", "一名穿浅绿色上衣的人站在电脑桌前操作键盘，显示器上呈现着彩色画面。", "#3F74D9"),
    ("红车草地", "RED BUGGY", "一名穿黄色上衣的孩子坐在草地上的红色小型越野车内，双手靠近方向盘。", "#D63D35"),
    ("桌边切蛋糕", "CUTTING THE CAKE", "一名戴眼镜的人站在餐桌旁切分蛋糕，彩色桌布四周摆着盘子和餐具。", "#A87B58"),
    ("蓝馆伞影", "UMBRELLA AT BLUE HALL", "一名撑浅色雨伞的人站在大型蓝色建筑入口前，周围有行人经过。", "#2F83B8"),
    ("屏前落笔", "WRITING BY THE SCREEN", "一名戴眼镜的人坐在平板电脑前对照乐谱，手持笔在纸上书写。", "#C28A36"),
    ("蓝色广场", "BLUE PLAZA", "撑伞的人站在宽阔铺装地面中央，远处是带巨大蓝色曲线装饰的建筑入口。", "#43A9C7"),
    ("绳网穿行", "THROUGH THE ROPES", "穿彩色条纹外套的孩子双手抓住绳索，俯身穿过弧形攀爬网。", "#218F9E"),
    ("草地驾乘", "GRASSLAND KART", "一名戴帽子的人坐进带红色防滚架的越野卡丁车，远处还有车辆与树木。", "#D84D47"),
    ("泡沫背影", "BACK INTO THE FOAM", "橙衣参加者背对镜头站在大片泡沫前，右侧蓝衣人物正从泡沫中走过。", "#EE7A31"),
    ("门前并立", "BY THE ENTRANCE", "两名年轻人穿白色和紫色上衣并排站在玻璃门前，室内灯光从身后透出。", "#7258B5"),
    ("五人跃起", "FIVE IN THE AIR", "五个人在户外道路旁同时跳起并张开手臂，身后排列着树木与栏杆。", "#D93C50"),
    ("奖牌队影", "MEDAL TEAM", "一群穿号码服的孩子在蓝色设施前合影，多人举手并展示圆形奖牌。", "#E3A52E"),
    ("水族窗前", "AQUARIUM WINDOW", "两名戴帽子和眼镜的人在大型水族箱前合影，玻璃后清楚可见游动的鱼群。", "#287F8F"),
]


def main() -> None:
    payload = json.loads(MANIFEST.read_text(encoding="utf-8"))
    items = payload.get("items") or []
    if len(items) != 20 or len(EDITORIAL) != 20:
        raise RuntimeError(f"expected 20 items, found {len(items)}")

    for item, (title, english, caption, accent) in zip(items, EDITORIAL, strict=True):
        item["poster_title"] = title
        item["poster_english"] = english
        item["ai_caption"] = caption
        item["poster_accent"] = accent
        item["caption_asset_id"] = item.get("asset_id")
        item["caption_source"] = "vision"

    for field in ("poster_title", "poster_english", "ai_caption"):
        values = [str(item.get(field) or "").strip() for item in items]
        if len(set(values)) != 20 or not all(values):
            raise RuntimeError(f"{field} values must be non-empty and unique")
    accents = [str(item.get("poster_accent") or "").strip() for item in items]
    if not all(re.fullmatch(r"#[0-9A-Fa-f]{6}", value) for value in accents):
        raise RuntimeError("poster_accent values must be six-digit hex colors")

    payload["count"] = 20
    payload["editorial_updated_at"] = datetime.now().astimezone().isoformat()
    temporary = MANIFEST.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, MANIFEST)
    print(json.dumps({
        "items": len(items),
        "unique_titles": len({item["poster_title"] for item in items}),
        "unique_english": len({item["poster_english"] for item in items}),
        "unique_captions": len({item["ai_caption"] for item in items}),
        "editorial_updated_at": payload["editorial_updated_at"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
