from pathlib import Path
from datetime import datetime
from PIL import Image
import json, os
root=Path('/Users/teamc/Documents/RemotePanelih5Standalone')
day='2026-08-25'; d=root/'ipad/data/h5_daily_photos'/day; manifest=d/'manifest.json'
notes=[
('蓝洞双臂','BLUE CAVE ARMS','蓝色灯光照亮的狭窄洞穴通道里，两个人张开双臂站在彩色鱼类投影上。','#39B7FF'),
('举杯餐桌','TOAST AT TABLE','室内餐桌旁坐着几位家人，桌上摆着餐盘、饮料和食物，大家举杯面对镜头。','#F6B73C'),
('展牌前阅读','READING THE DISPLAY','两个人站在室内展示牌前，侧身一起阅读墙面的说明内容。','#A77BFF'),
('车窗手势','WINDOWSIDE GESTURE','两名年轻人坐在透明窗边的车厢里，举起手势回应镜头，窗外是蓝黄色结构。','#5AD6C4'),
('积木穿行','BLOCKS IN PLAY','一个孩子站在红黄绿蓝大型积木搭成的室内游乐结构中。','#FF6B5E'),
('砖墙晚餐','BRICKWALL DINNER','两个人坐在砖墙餐厅的餐桌两侧，桌上摆满菜肴、餐具和饮料。','#E9895E'),
('蛋糕切面','CAKE CUTTING','戴眼镜的男孩在桌边用刀切下一块带彩色装饰的蛋糕。','#FF4F91'),
('节庆合影','FESTIVE PORTRAIT','两个人站在红色节庆背景板前合影，身后有花朵、烟花和中英文装饰字样。','#E94747'),
('礼服侧望','SIDEWAYS IN FORMALWEAR','几名孩子坐在室内一排座椅上，其中穿浅蓝礼服的女孩侧身望向一旁。','#79A9FF'),
('生日气球桌','BIRTHDAY BALLOON TABLE','孩子们围坐在铺有彩色餐具和水果的生日桌旁，墙上挂着气球和银色字母。','#FFCF4A'),
('沙发前胜利手势','VICTORY BY THE SOFA','戴黑框眼镜的男孩站在沙发前近距离面对镜头，举起一只手做出胜利手势。','#7C8CFF'),
('夜色烟花棒','SPARKLERS AFTER DARK','夜色里几名孩子手持燃烧的烟花棒，穿红外套的女孩把手伸向前方。','#FF7A45'),
('岩洞彩光','COLORED CAVE LIGHT','一个男孩站在彩色灯光映照的岩洞中，头顶和四周都是凹凸不平的岩壁。','#C16CFF'),
('木墙全家合影','WOODWALL GROUP','几位成人和孩子并排站在木质背景墙前合影，墙上有彩色中文字符和卡通图案。','#56C596'),
('红白围巾','RED WHITE SCARF','一个男孩在室内近距离面对镜头，脖子上围着红白相间图案的围巾。','#F25555'),
('玻璃柜旁用餐','DINNER BY THE DISPLAY','成人和孩子围坐在餐厅桌旁用餐，桌上有餐盘、饮料和玩偶，身后是玻璃展示柜。','#D99B58'),
('水边白袍','WHITE ROBE BY WATER','戴眼镜的人穿白色红边长袍站在水边，灰色水面远处浮着朦胧的城市高楼。','#8BA7C9'),
('木楼街巷','WOODEN STREET WALK','古朴街巷两侧排列着木质建筑和店铺，行人坐在临街桌旁或沿街走过。','#D8784A'),
('蓝车与红亭','BLUE BIKE RED PAVILION','一个男孩站在人行道上扶着蓝色自行车，旁边是红色木结构亭架和树木。','#3E9BE8'),
('男孩抱小狗','BOY WITH SMALL DOG','戴眼镜的男孩在室内抱着一只黑色小狗，身后是店铺玻璃门、招牌和行人。','#F08A3C'),
]
items=[]
for i,(title,eng,caption,accent) in enumerate(notes,1):
 p=next(d.glob(f'photo-{i:02d}.*'))
 with Image.open(p) as im: w,h=im.size
 old={}
 # Preserve any compatible metadata if a prior manifest existed.
 if manifest.exists():
  try: old=next((x for x in json.loads(manifest.read_text()).get('items',[]) if Path(str(x.get('image_path',''))).name==p.name),{})
  except Exception: old={}
 item={k:v for k,v in old.items() if k not in {'poster_title','poster_english','ai_caption','poster_accent','image_path','image_url'}}
 item.update({'image_path':str(p),'image_url':f'/assets/h5-photo/{day}/{p.name}','filename':p.name,'width':w,'height':h,'poster_title':title,'poster_english':eng,'ai_caption':caption,'poster_accent':accent,'caption_source':'visual_editorial_review','caption_asset_id':old.get('asset_id') or p.stem})
 items.append(item)
assert len(items)==20
for key in ('poster_title','poster_english','ai_caption'):
 vals=[x[key] for x in items]; assert all(v.strip() for v in vals) and len(set(vals))==20, key
payload={'date':day,'person':'方宇轩','count':20,'created_at':datetime.now().isoformat(),'editorial_updated_at':datetime.now().isoformat(),'items':items}
tmp=manifest.with_suffix('.json.tmp'); tmp.write_text(json.dumps(payload,ensure_ascii=False,indent=2),encoding='utf-8'); os.replace(tmp,manifest)
print(json.dumps({'manifest':str(manifest),'items':len(items),'unique_titles':len({x['poster_title'] for x in items}),'unique_english':len({x['poster_english'] for x in items}),'unique_captions':len({x['ai_caption'] for x in items}),'editorial_updated_at':payload['editorial_updated_at']},ensure_ascii=False))
