from __future__ import annotations

import json
import os
import re
import shutil
from datetime import datetime
from pathlib import Path

DAY = "2026-10-02"
ROOT = Path(__file__).resolve().parents[1]
DAY_DIR = ROOT / "ipad" / "data" / "h5_daily_photos" / DAY
MANIFEST = DAY_DIR / "manifest.json"

EDITORIAL = [
    ("坡上独树", "SOLITARY TREE", "一棵枝叶繁茂的大树立在草坡上，远处山林隐入灰蓝色天空。", "#6F8F55"),
    ("红幕大合影", "GRAND STAGE PORTRAIT", "大人与孩子分排站在舞台中央，在写有数字三十的红色大屏前合影。", "#D53245"),
    ("红锅旁的晚餐", "DINNER BY THE RED POT", "两名少年低头在餐桌前吃饭，红色带盖餐锅摆在两人中间。", "#D67A2C"),
    ("圣诞沙发角", "CHRISTMAS SOFA CORNER", "戴眼镜的孩子坐在沙发边手扶花纹袋，身旁堆着圣诞装饰与礼物。", "#B9323A"),
    ("石刻前举手", "GESTURE BY THE STONE", "穿棕色外套的少年站在刻有红字的景观石前，双手抬在胸前摆姿势。", "#A84D3F"),
    ("林中双重奏", "WOODLAND DUET", "两名少年在林木间笑着合影，一人抱吉他，另一人背着白色键盘乐器。", "#C93F35"),
    ("横杆下仰望", "LOOKING PAST THE BAR", "戴圆框眼镜的孩子从低处仰望，双臂举起握向面前的黑色横杆。", "#78AFC2"),
    ("广场展臂", "ARMS ACROSS THE PLAZA", "戴口罩的少年站在开阔广场中央张开双臂，身后铺展着树木与云层。", "#5794CA"),
    ("蓝衣吃面", "NOODLES IN BLUE", "穿亮蓝上衣的少年俯身用筷子夹取餐盘里的面食与青菜。", "#2459AF"),
    ("奇装伙伴", "COSTUMED COMPANIONS", "两名游客站在室内主题布景中，与戴护目镜和华丽头饰的装扮者并肩合影。", "#B98945"),
    ("灯树骑行记", "RIDE BENEATH THE LIGHTS", "夜色里一名少年跨坐在彩色编织装置上，另一人站在发光树木之间。", "#8D4CA8"),
    ("音乐赛展墙", "MUSIC CONTEST WALL", "佩戴证件的少年独自站在音乐赛事展墙前，两侧排列着多幅选手肖像。", "#2874B9"),
    ("红装比耶", "PEACE SIGN IN RED", "穿红色衣服的孩子靠近镜头微笑并举起剪刀手，身后另一人也露出笑脸。", "#C6283E"),
    ("叉起一口蛋糕", "A BITE OF CAKE", "穿黑白条纹上衣的少年坐在桌边，用餐具叉起盘中的黄色蛋糕。", "#E4B43E"),
    ("红柱间的冬日", "WINTER AMONG RED COLUMNS", "裹着黑色冬衣的少年站在红柱灰墙之间，手中举着印有楼阁图案的青色包装袋。", "#38AEB6"),
    ("沙发上的午后", "AFTERNOON ON THE SOFA", "少年斜靠在米色转角沙发上，毯子、衣物和提袋散放在四周。", "#B98A68"),
    ("广场边尝一口", "A BITE IN THE PLAZA", "戴眼镜的少年在人群密集的石铺广场上把点心送到嘴边，同行者站在身旁。", "#9B5A45"),
    ("圆桌团聚", "ROUND TABLE GATHERING", "多人围坐在摆满菜肴的圆桌旁面对镜头微笑，几个人举起剪刀手。", "#C96A38"),
    ("挤进自拍", "CROWD INTO THE SELFIE", "几个人把笑脸挤进近距离自拍画面，前排戴眼镜的人几乎贴近镜头。", "#557EB5"),
    ("草地协力长杆", "TEAMWORK WITH LONG POLES", "一队穿橙色上衣的孩子在草地上共同扶举多根长杆，旁边有成人协助。", "#E9782F"),
]


def main() -> None:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    items = data.get("items") or []
    if len(items) != 20 or len(EDITORIAL) != 20:
        raise RuntimeError(f"expected 20 photos, got {len(items)}")

    for item, (title, english, caption, accent) in zip(items, EDITORIAL):
        item["poster_title"] = title
        item["poster_english"] = english
        item["ai_caption"] = caption
        item["poster_accent"] = accent
        item["caption_asset_id"] = item.get("asset_id", "")
        item["caption_source"] = "vision"

    items[17]["place_display"] = "江苏省 · 滨湖区"

    for field in ("poster_title", "poster_english", "ai_caption"):
        values = [str(item.get(field) or "").strip() for item in items]
        if not all(values) or len(set(values)) != 20:
            raise RuntimeError(f"invalid or duplicate {field}")
    for item in items:
        accent = str(item.get("poster_accent") or "")
        if not re.fullmatch(r"#[0-9A-Fa-f]{6}", accent):
            raise RuntimeError(f"invalid accent: {accent}")

    data["count"] = 20
    data["editorial_updated_at"] = datetime.now().astimezone().isoformat()
    temporary = MANIFEST.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, MANIFEST)

    removed = []
    for cache_dir in DAY_DIR.glob("rendered-v*"):
        if cache_dir.is_dir():
            shutil.rmtree(cache_dir)
            removed.append(cache_dir.name)
    print(json.dumps({
        "items": len(items),
        "unique_titles": len({item["poster_title"] for item in items}),
        "unique_english": len({item["poster_english"] for item in items}),
        "unique_captions": len({item["ai_caption"] for item in items}),
        "editorial_updated_at": data["editorial_updated_at"],
        "removed_caches": removed,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
