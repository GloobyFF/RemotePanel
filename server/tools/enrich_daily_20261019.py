import json,pathlib,datetime,os,shutil
p=pathlib.Path('/Users/teamc/Documents/RemotePanelih5Standalone/ipad/data/h5_daily_photos/2026-10-19/manifest.json')
m=json.loads(p.read_text())
rows=[
('绿叶间的依偎','LEANING INTO GREEN','两人在岩石与绿植之间靠在一起，白衣人物侧头倚向身旁的人。','#72934E'),
('草坪边举起手机','PHONE BY THE LAWN','戴宽檐帽的人举起手机，儿童迈步经过一旁装着物品的绿色拖车。','#6294BB'),
('云下广场合影','SIDE BY SIDE UNDER CLOUDS','两人并排站在石铺广场上，身后的人群与道路延伸向远处的层叠屋顶。','#71889C'),
('围锅夹一筷','SHARING THE HOT POT','三人围坐桌旁，右侧的人将筷子伸向盛着玉米与食材的白色电锅。','#B77552'),
('蓝色操作台前','AT THE BLUE CONSOLE','穿迷彩外套的儿童站在蓝色互动操作台前，双手靠近面板上的圆形部件。','#438CB8'),
('琴键排成行','KEYBOARDS IN COMPANY','多人坐在电子键盘后，前排中央的人将白色肩背式键盘斜放在身前。','#AE8C66'),
('人群里举起手','A HAND ABOVE THE CROWD','明亮的室内挤满穿外套的人，右侧有人把手高高举过头顶。','#8C7C69'),
('木台后仰望','LOOKING UP BEHIND WOOD','戴浅色帽子的人双臂交叠站在深色木台后，抬头望向侧上方。','#926343'),
('门前小路并肩','TOGETHER ON THE PATH','两人站在绿篱夹着的小路上，左侧儿童在身前拿着小物件。','#9B755F'),
('指尖拼装时刻','SMALL PARTS IN HAND','戴圆框眼镜的儿童低头摆弄白色底板上的拼插部件，桌旁放着蓝色收纳盒。','#4D86B8'),
('三楼背靠背','BACK TO BACK ON THREE','两人在标有三楼的导览牌旁背靠背站立，身后是玻璃栏杆与商场店铺。','#9971AD'),
('湿沙上的挥臂','ARMS ABOVE WET SAND','两人靠在湿沙滩上，右侧披着蓝色花纹布料的人向上伸出手臂。','#4F91BE'),
('客厅里的拥抱','A LIVING ROOM EMBRACE','白衣人物侧身搂着穿粉色上衣的人，两人在沙发与电视之间靠头合影。','#C2848F'),
('门前一起跃起','JUMP AT THE DOORWAY','八人在玻璃店门前排开，多人抬手屈膝跃起，身后贴着餐饮海报。','#C67B4D'),
('蓝紫灯下合影','PORTRAIT IN STAGE LIGHT','两人在观众席前靠近合影，后方舞台亮着蓝紫色灯光。','#8073BB'),
('拖车旁伸出的脚','A STEP BESIDE THE WAGON','儿童在绿色拖车旁向前伸出一条腿，戴帽子的人背向镜头举着手机。','#668E57'),
('心形气球庆生','HEART BALLOON CELEBRATION','三人在写有生日祝福的粉色心形气球后举手摆姿势，地面散落着气球。','#CE668D'),
('红色展板前腾空','LEAP BY THE RED DISPLAY','五人在红色展板前合影，最右侧的人双臂举高、两腿分开跃起。','#B9564F'),
('镜头前张开双臂','OPEN ARMS THROUGH A PHONE','前景的人竖持手机，为圆形层叠屋顶建筑前张开双臂的人拍照。','#578F9D'),
('长桌旁回头一望','A GLANCE ALONG THE TABLE','多人围坐摆满小锅与菜盘的长桌，中央儿童转头望向镜头。','#AA8056')]
assert len(m['items'])==len(rows)==20
for item,row in zip(m['items'],rows):
 item.update(dict(zip(['poster_title','poster_english','ai_caption','poster_accent'],row)))
 item['caption_asset_id']=item['asset_id'];item['caption_source']='vision'
for k in ['poster_title','poster_english','ai_caption']:
 assert len({i[k] for i in m['items']})==20
m['editorial_updated_at']=datetime.datetime.now().astimezone().isoformat()
tmp=p.with_suffix('.json.tmp');tmp.write_text(json.dumps(m,ensure_ascii=False,indent=2));os.replace(tmp,p)
for d in p.parent.glob('rendered-v*'):
 if d.is_dir(): shutil.rmtree(d)
print('Atomic editorial update: 20 unique titles, English titles and captions; rendered caches removed.')
