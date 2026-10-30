from __future__ import annotations
import json, os, re, shutil
from datetime import datetime
from pathlib import Path

ROOT = Path('/Users/teamc/Documents/RemotePanelih5Standalone')
DAY = datetime.now().strftime('%Y-%m-%d')
DAY_DIR = ROOT/'ipad'/'data'/'h5_daily_photos'/DAY
MANIFEST = DAY_DIR/'manifest.json'
EDITORIAL = [
 ('屏前案头','DESK BESIDE THE BED','孩子坐在床边的案头前，笔记本电脑、纸张和家居物件铺在身旁。','#6FA7B8'),
 ('林间木架','WOODLAND STRUCTURE','戴眼镜的孩子站在树林与木制设施旁，低头观察脚下的游乐区域。','#548C79'),
 ('镜框肖像','FRAMED PORTRAIT','戴圆眼镜和浅色帽饰的孩子出现在黑白装饰边框围成的彩色肖像中。','#568F94'),
 ('花园同行','GARDEN COMPANIONS','花园里一名戴宽檐帽的人举着手机，孩子站在花坛边握着细长的绿色物件。','#6F8F5B'),
 ('穹顶指向','POINTING THROUGH GLASS','玻璃金属亭内，大人抬手指向上方，孩子站在旁边一起望向开阔的外部空间。','#59615F'),
 ('琴谱开场','KEYS AND SHEET MUSIC','孩子坐在钢琴或电子琴前，琴架上摊着乐谱，双手正靠近琴键。','#D99A3D'),
 ('镜头前的近照','CLOSE TO THE CAMERA','戴圆眼镜的孩子在室内靠近镜头坐着，身后的枕头与生活物件构成亲密背景。','#557A91'),
 ('围桌午餐','LUNCH AROUND THE TABLE','孩子和大人围坐在餐桌旁，盘碗、饮料和多道菜肴铺满桌面。','#C96A38'),
 ('勋章外套','MEDALS ON THE BLAZER','穿深色西装外套和红领带的孩子站在户外树木前，胸前别着多枚奖章或徽章。','#9B3146'),
 ('舞台颁奖','AWARDS ON STAGE','一群人在红色活动舞台前合影，手中举着证书或奖品，身后是醒目的活动横幅。','#D53245'),
 ('黄色背景的证书','CERTIFICATE IN YELLOW','孩子和大人站在黄色活动背景前合影，孩子打开证书夹展示其中的奖状。','#D6A62C'),
 ('雕像广场','SCULPTURES IN THE PLAZA','孩子穿浅蓝上衣站在户外雕塑和展陈物前，脚下是开阔的铺装广场。','#4D83A8'),
 ('桌边一餐','A MEAL AT THE TABLE','戴眼镜的孩子穿迷彩外套坐在桌边，手边有餐盘、外带杯、食品包装和背包。','#B97845'),
 ('车厢里的剪刀手','PEACE SIGN IN THE CAR','孩子坐在车内对着镜头举起剪刀手，食物容器和饮料放在座位周围。','#C5484D'),
 ('花坛边的琴友','GUITARS BY THE MONUMENT','两个孩子站在花坛旁的白红色纪念性雕塑前，各自抱着吉他面对镜头。','#B94A42'),
 ('花坛边再合奏','DUET BY THE FLOWERS','两个孩子在同一处户外纪念性雕塑旁并肩抱琴，身后是台阶、花朵和树木。','#C06B45'),
 ('玻璃结构中的仰拍','LOOKING DOWN THROUGH GLASS','穿迷彩外套的孩子站在玻璃与金属结构内，画面从上方俯拍向下。','#5A8792'),
 ('新年舞台','NEW YEAR ON STAGE','两个孩子站在红色新年舞台上手持麦克风，周围点缀花朵、扇面和彩色节庆图案。','#D13D48'),
 ('服装店试装','COSTUME SHOP MIRROR','穿彩色服装的孩子站在服装店入口，四周衣架上的衣物和镜面反射形成层叠画面。','#9C5B9D'),
 ('湖上桨板','PADDLEBOARD ON THE LAKE','穿蓝色救生衣的人坐在湖面充气桨板上，手中的桨斜举向树林环绕的水面。','#3F86A8'),
]

def main():
 data=json.loads(MANIFEST.read_text(encoding='utf-8'))
 items=data.get('items') or []
 photos=sorted(DAY_DIR.glob('photo-*.jpg'))
 if len(items)!=20 or len(photos)!=20: raise SystemExit(f'expected 20 items/photos, got {len(items)}/{len(photos)}')
 for item, (title, eng, cap, accent) in zip(items, EDITORIAL):
  item.update(poster_title=title, poster_english=eng, ai_caption=cap, poster_accent=accent, caption_asset_id=item.get('asset_id',''), caption_source='vision')
 data['count']=20; data['editorial_updated_at']=datetime.now().astimezone().isoformat()
 for f in ('poster_title','poster_english','ai_caption'):
  vals=[str(x.get(f) or '').strip() for x in items]
  if len(vals)!=20 or not all(vals) or len(set(vals))!=20: raise SystemExit(f'invalid {f}')
 for x in items:
  if not re.fullmatch(r'#[0-9A-Fa-f]{6}', str(x.get('poster_accent',''))): raise SystemExit('invalid accent')
 tmp=MANIFEST.with_suffix('.json.tmp'); tmp.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8'); os.replace(tmp,MANIFEST)
 removed=[]
 for p in DAY_DIR.glob('rendered-v*'):
  if p.is_dir(): shutil.rmtree(p); removed.append(p.name)
 print(json.dumps({'day':DAY,'items':20,'unique_titles':20,'unique_english':20,'unique_captions':20,'editorial_updated_at':data['editorial_updated_at'],'removed_caches':removed},ensure_ascii=False))
main()
