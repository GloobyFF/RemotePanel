import datetime
import json
import os
import re
from pathlib import Path


manifest_path = Path(__file__).resolve().parents[1] / "ipad/data/h5_daily_photos/2026-09-28/manifest.json"
data = json.loads(manifest_path.read_text(encoding="utf-8"))
items = data.get("items") or []

editorial = [
    ("绿衫琴声", "GREEN PIANO NOTES", "戴黄色镜框的孩子坐在黑色钢琴前，双手落在琴键上看着谱页。", "#B7D44A"),
    ("圆环下的搭档", "BENEATH THE WHITE RING", "两名孩子站在白色圆环装置下，各自举着黑白色玩具般的物件面对镜头。", "#F08A38"),
    ("烛火照亮蛋糕", "CAKE BY CANDLELIGHT", "昏暗餐桌旁的两个孩子望着一支点燃的蜡烛，浅色蛋糕摆在桌子中央。", "#F2A33A"),
    ("琴凳旁的小发现", "A FIND BY THE PIANO", "戴眼镜的孩子蹲在黑色琴凳旁，双手捧着浅绿色圆形物件仔细端详。", "#80BFA8"),
    ("蓝紫灯下的琴房", "KEYS IN BLUE LIGHT", "穿深色上衣的孩子站在数码钢琴旁，蓝紫色灯光掠过昏暗房间。", "#7968D8"),
    ("沙发上的头显体验", "HEADSET ON THE SOFA", "一人仰靠米色沙发戴着银黑色头显，身旁穿蓝衣的孩子安静坐着。", "#91A7C4"),
    ("举起卡通甜筒", "CARTOON CONE CLOSE-UP", "戴黑框眼镜的孩子把带动物轮廓的白色冰淇淋甜筒举到镜头前。", "#F4B8D2"),
    ("高空车厢看城景", "CITY THROUGH THE CABIN", "孩子坐在黄色立柱围合的高空车厢内，窗外铺开密集的城市楼群。", "#E1C328"),
    ("雾色水岸的人群", "CROWD ALONG THE WATER", "阴天里人们沿石质水岸停留，一名孩子蹲在水边望向灰蓝水面。", "#728C94"),
    ("孩子们的手持星火", "SPARKLERS IN A CIRCLE", "几名孩子在夜色中围着手持烟花棒，白黄色火花照亮红橙色外套。", "#FFB21A"),
    ("复古电话听筒", "THE VINTAGE RECEIVER", "戴眼镜的孩子坐在桌边，把复古电话装置的黑色听筒举到耳旁。", "#B87333"),
    ("橙衣西瓜小队", "WATERMELON CREW", "三名穿橙色上衣的孩子站在铺满西瓜切片的长桌前，其中一人捧着红绿果块。", "#E85D3F"),
    ("人潮里的抬头一刻", "LOOKING UP IN THE CROWD", "繁忙步行街的人群从树下穿过，前景几个人一同抬头望向上方。", "#C85B4A"),
    ("花瀑边的蓝衣少年", "BLOOMS BESIDE THE FALLS", "穿浅蓝上衣的孩子站在水池边岩石上，身后粉紫花坡间流下一道小瀑布。", "#E35D96"),
    ("池畔共看一屏", "ONE SCREEN BY THE POND", "两个人蹲在绿荫覆盖的池塘石岸边，靠在一起看手中的手机。", "#85B75A"),
    ("红金木马同行", "RIDERS IN RED AND GOLD", "一大一小分别坐在彩绘木马上，红金色旋转木马顶棚在晴空下格外醒目。", "#D93A32"),
    ("夜路上的火花扇", "FAN OF NIGHT SPARKS", "穿深色衣服的孩子在夜路旁握着烟花棒，密集金色火花横向铺开。", "#FF8C24"),
    ("方格桌布旁的合影", "PORTRAIT AT THE CHECKERED TABLE", "三个人靠在方格桌布前面对镜头，桌上摆着点心、餐具和蓝色长盒。", "#D5A52E"),
    ("昏灯下的居家片段", "HOME IN LOW LIGHT", "昏暗房间里，前景穿格纹上衣的孩子低头看向桌面，后方有人站在门边。", "#6F7C6A"),
    ("长桌上的热菜相聚", "FEAST AROUND THE LONG TABLE", "多人围坐餐厅长桌分享小龙虾与各色菜肴，孩子伸手与对面的人互动。", "#D94C32"),
]

if len(items) != 20 or len(editorial) != 20:
    raise SystemExit(f"expected 20 items, found {len(items)}")

for item, (title, english, caption, accent) in zip(items, editorial):
    item.update(
        poster_title=title,
        poster_english=english,
        ai_caption=caption,
        poster_accent=accent,
        caption_source="vision_contact_sheet",
        caption_asset_id=item.get("asset_id"),
    )

for field in ("poster_title", "poster_english", "ai_caption"):
    values = [str(item.get(field) or "").strip() for item in items]
    if not all(values) or len(set(values)) != 20:
        raise SystemExit(f"invalid or duplicate {field}")
if not all(re.fullmatch(r"#[0-9A-F]{6}", str(item.get("poster_accent") or "")) for item in items):
    raise SystemExit("invalid poster_accent")

data["count"] = 20
data["editorial_updated_at"] = datetime.datetime.now().astimezone().isoformat()
temporary_path = manifest_path.with_suffix(".json.tmp")
temporary_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
os.replace(temporary_path, manifest_path)
print(json.dumps({
    "items": len(items),
    "unique_titles": len({item["poster_title"] for item in items}),
    "unique_english": len({item["poster_english"] for item in items}),
    "unique_captions": len({item["ai_caption"] for item in items}),
    "editorial_updated_at": data["editorial_updated_at"],
}, ensure_ascii=False))