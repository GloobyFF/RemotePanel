import json, os, re, shutil
from pathlib import Path
from datetime import datetime
from PIL import Image, ImageDraw
ROOT=Path('/Users/teamc/Documents/RemotePanelih5Standalone')
DAY=ROOT/'ipad/data/h5_daily_photos/2026-10-21'
OUT=ROOT/'ipad/data/healthchecks/2026-10-21'
OUT.mkdir(parents=True,exist_ok=True)
rows=[
('巨石前驻足','BESIDE THE ROCK','穿棕色外套的孩子站在刻有红字的巨石前，身后树木枝叶茂密。','#648342'),
('满桌相聚','SHARED FEAST','人们围坐在摆满菜肴的餐桌旁，几人朝镜头举手示意。','#C77835'),
('临水远楼','WATERSIDE SKYLINE','戴眼镜的人穿着棕黄色外套站在水边，远处高楼隐在薄雾中。','#A5753E'),
('彩灯合影','COLORFUL STAGE','几个人站在彩色灯光照亮的布景前合影，周围布满大型装饰。','#A64DFF'),
('案板切片','AT THE COUNTER','操作台前的人低头切配食物，旁边的人站着观看。','#C87836'),
('并肩用电脑','SIDE BY SIDE','两名穿蓝色上衣的孩子并排坐在桌前，各自面前摆着笔记本电脑。','#194B9A'),
('树荫碑前','STONE AND SHADE','孩子站在刻有竖排文字的石碑前，身后树荫下有人走动。','#617D43'),
('琴旁站姿','BESIDE THE PIANO','穿白衬衫和深色短裤的孩子站在屋内，身后摆着黑色钢琴。','#6D5950'),
('镜前上妆','MAKEUP MOMENT','孩子侧身坐着接受上妆，旁边台面摆着化妆刷和瓶罐。','#BD8C83'),
('木台四人','GARDEN GROUP','四个人并排坐在花木环绕的木台上，面朝镜头合影。','#6E9761'),
('栈道花丛','GARDEN WALKWAY','人们沿着花木间的木栈道前行，有人撑着伞。','#B29B34'),
('沙发小物','SOFA ACTIVITY','穿条纹上衣和黄色裤子的孩子坐在沙发上，低头摆弄手中的小物件。','#D5A636'),
('双手琴键','HANDS ON KEYS','孩子坐在琴凳上，双手放在黑色立式钢琴的键盘上。','#997654'),
('木窗座间','WOODEN CABIN','戴宽檐帽、穿粉色上衣的人坐在木框窗旁，身边还有同行的人。','#BB7486'),
('绿栏纸页','PAPERS BY THE RAIL','戴眼镜的孩子站在绿色栏杆旁，手里拿着纸页，身后是茂密植被。','#388564'),
('膝上翻书','BOOK ON THE LAP','戴眼镜的孩子低头看着膝上的图画书，一手扶着书页。','#AD825B'),
('眼镜侧影','GLASSES IN PROFILE','孩子戴着黄绿色镜腿的眼镜侧脸站着，短发在浅色墙面前清晰可见。','#97AB43'),
('红幕大合影','RED STAGE PORTRAIT','一大群人在红色舞台背景前分排合影，背景上印有醒目的数字。','#BD3342'),
('石屋台阶','SUNLIT STONE STEPS','两个人站在石砌建筑前的台阶上，拱形窗和小钟楼映着蓝天。','#4D8EB8'),
('草坪筒口','PLAYGROUND TUBE','戴蓝色帽子的人站在绿色草坪上，双手伸向灰色大型装置的开口。','#56A74F'),
]
def sheet(paths,dest,cell=(280,390)):
    result=Image.new('RGB',(cell[0]*5,cell[1]*4),'#dddddd')
    draw=ImageDraw.Draw(result)
    for i,p in enumerate(paths):
        im=Image.open(p).convert('RGB'); im.thumbnail((cell[0]-16,cell[1]-32))
        x=i%5*cell[0]; y=i//5*cell[1]
        result.paste(im,(x+(cell[0]-im.width)//2,y+28))
        draw.text((x+8,y+6),f'{i+1:02d}',fill='black')
    result.save(dest,quality=94)
if __name__=='__main__':
    p=DAY/'manifest.json'; d=json.loads(p.read_text()); assert len(d['items'])==len(rows)==20
    shutil.copy2(p,OUT/'manifest-before.json')
    for item,row in zip(d['items'],rows):
        item.update(dict(zip(('poster_title','poster_english','ai_caption','poster_accent'),row)))
        item['caption_asset_id']=item['asset_id']; item['caption_source']='vision_reviewed'
    for k in ('poster_title','poster_english','ai_caption'):
        assert len({i[k] for i in d['items']})==20
    assert all(re.fullmatch(r'#[0-9A-F]{6}',i['poster_accent']) for i in d['items'])
    d['editorial_updated_at']=datetime.now().astimezone().isoformat()
    tmp=p.with_suffix('.json.tmp'); tmp.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n'); os.replace(tmp,p)
    for cache in DAY.glob('rendered-*'):
        if cache.is_dir(): shutil.rmtree(cache)
    sheet([Path(i['image_path']) for i in d['items']],OUT/'source-contact.jpg')
    print(json.dumps({'count':20,'unique_titles':20,'unique_english':20,'unique_captions':20,'updated':d['editorial_updated_at'],'sheet':str(OUT/'source-contact.jpg')},ensure_ascii=False))
