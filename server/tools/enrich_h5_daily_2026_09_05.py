from datetime import datetime
from pathlib import Path
import json, os, re

root = Path('/Users/teamc/Documents/RemotePanelih5Standalone')
manifest_path = root / 'ipad/data/h5_daily_photos/2026-09-05/manifest.json'
data = json.loads(manifest_path.read_text(encoding='utf-8'))
items = data.get('items') or []
editorial = [
 ('峡谷石阶','CANYON STAIRS','人群沿着植被环绕的石阶走向峡谷，蓝绿色溪流和小桥藏在岩壁之间。','#4B9BC5'),
 ('围桌分餐','SHARED TABLE','四个人围坐餐桌分享菜肴，碗筷、饮料和一大盘面条铺满桌面。','#D86A3D'),
 ('蓝幕肖像','BLUE PORTRAIT','年轻人穿棕色外套和深蓝衬衫，面向镜头站在平整的蓝色背景前。','#4C82B8'),
 ('摊前递食','STALL HANDOFF','摊位里的戴口罩摊主从木柜台递出食物，年轻顾客伸手接过并拿着纸券。','#D27B3F'),
 ('洞穴彩光','CAVE LIGHTS','年轻人手持饮料站在岩洞里抬头张望，红蓝紫色灯光映亮起伏的岩壁。','#B24C9B'),
 ('灯下合影','LIGHTS TOGETHER','大人和孩子在夜色中的暖灯下合影，有人微笑挥手，有人举起手臂。','#E3A14A'),
 ('机器人前比耶','ROBOT V SIGN','戴口罩的年轻人在绿化旁举起V字手势，身后的彩色机器人雕像高高立在建筑前。','#D44F58'),
 ('篮球待投','ARCADE SHOT','穿蓝衣的年轻人在街机篮球机前握住黑球，正准备朝机器的篮筐投出。','#4B9BB2'),
 ('瀑布张臂','WATERFALL REACH','戴遮阳帽的人在瀑布下方石阶上张开双臂，水流从森林覆盖的岩壁倾泻而下。','#4D9B72'),
 ('棉花糖餐桌','COTTON CANDY','餐桌旁的人们面对热菜和饮料用餐，桌上的甜点与两朵粉彩棉花糖格外醒目。','#E58A68'),
 ('灯旁弹琴','PIANO LAMP','穿黄色上衣的人坐在立式钢琴前看着摊开的谱页，房间被一盏近旁的灯照亮。','#C89A45'),
 ('林间跑步','WOODLAND RUN','孩子和大人穿着活动服沿树木环绕的道路跑来，队伍中有人佩戴红色号码布。','#5F9B62'),
 ('摩天轮车厢','FERRIS CAR','大人和年轻人坐在明黄色游乐车厢里，身后的摩天轮和深色屋顶映在夜色中。','#E1B33F'),
 ('叶下仰望','LOOKING UP','大人和年轻人站在宽大的绿叶下共同仰望，后方可见岩石景观和来往游客。','#6B9B5A'),
 ('红幕证书','RED BACKDROP','穿红裙的大人和戴眼镜的年轻人并肩展示黄色证书与蓝色文件夹。','#D64C45'),
 ('键盘练习','KEYBOARD STUDY','戴眼镜的年轻人坐在电子键盘前看向琴键，柔和室内光线落在正在演奏的手边。','#6B86A8'),
 ('客厅钢琴','HOME PIANO','年轻人在黑色琴凳上弹立式钢琴，谱页、植物和相框围出生活化的室内背景。','#8A735C'),
 ('围观讲解','SHOP DEMO','大人坐在桌边向前方示范或讲解，几名穿彩色外套的孩子在玻璃柜旁围拢观看。','#C9784A'),
 ('车厢相逢','TRAIN SEATS','两名年轻人在列车相邻座位间互动，一人回身举着设备，另一人探身靠近并露出笑容。','#5089A5'),
 ('白厅沉思','WHITE HALL','戴眼镜的年轻人在开阔的现代大厅里托腮站立，弧形白墙、金属栏杆和远处人群延展开来。','#8B9BA6'),
]
if len(items) != 20:
    raise SystemExit(f'expected 20 items, got {len(items)}')
for item, values in zip(items, editorial):
    title, english, caption, accent = values
    item.update({
        'poster_title': title,
        'poster_english': english,
        'ai_caption': caption,
        'poster_accent': accent,
        'caption_source': 'vision_contact_sheet',
        'caption_asset_id': item.get('asset_id'),
    })
for field in ('poster_title','poster_english','ai_caption'):
    values = [str(item.get(field) or '').strip() for item in items]
    if not all(values) or len(set(values)) != 20:
        raise SystemExit(f'invalid unique {field}')
if not all(re.fullmatch(r'#[0-9A-Fa-f]{6}', str(item.get('poster_accent') or '')) for item in items):
    raise SystemExit('invalid accent')
data['count'] = 20
data['editorial_updated_at'] = datetime.now().astimezone().isoformat()
tmp = manifest_path.with_suffix('.json.tmp')
tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
os.replace(tmp, manifest_path)
print(json.dumps({
    'items': len(items),
    'unique_titles': len({i['poster_title'] for i in items}),
    'unique_english': len({i['poster_english'] for i in items}),
    'unique_captions': len({i['ai_caption'] for i in items}),
    'editorial_updated_at': data['editorial_updated_at'],
}, ensure_ascii=False))
