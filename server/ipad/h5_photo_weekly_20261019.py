"""Weekly offline edition. Reads generated daily JPEGs; never exports originals."""
from pathlib import Path
from io import BytesIO
import sys, json, hashlib, re
from PIL import Image, ImageOps, ImageDraw, ImageFont
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from h5_photo_type import FONTS, LATIN
from h5_photo_palette import palette
OUT = Path(__file__).resolve().parent
# name, photo region, title region, title posture. Each is an editorial composition.
LAYOUTS = [
 ('右页竖题',(50,170,865,1390),(925,175,1030,1260),'vertical'),
 ('草坪宽刊',(50,450,1030,1200),(65,145,1000,410),'split'),
 ('广场落题',(110,125,1000,1310),(50,1350,1020,1450),'line'),
 ('餐桌上刊',(50,140,1030,875),(90,965,1000,1405),'split'),
 ('左页长笺',(205,160,1030,1390),(55,260,155,1330),'vertical'),
 ('琴键低刊',(50,620,1030,1355),(65,155,990,565),'split'),
 ('举手封面',(80,330,950,1470),(50,140,1010,300),'line'),
 ('仰望双行',(50,490,1030,1225),(120,150,1000,450),'split'),
 ('方幅题尾',(60,135,1020,1095),(65,1135,1000,1445),'split'),
 ('拼装页首',(50,170,1030,905),(70,995,990,1415),'split'),
 ('背靠侧笺',(50,160,865,1380),(925,400,1030,1370),'vertical'),
 ('沙滩低幅',(50,635,1030,1370),(65,150,1010,585),'split'),
 ('拥抱下题',(100,130,990,1315),(50,1350,1020,1450),'line'),
 ('跃起中刊',(50,395,1030,1130),(65,140,990,350),'split'),
 ('灯下短题',(70,420,1030,1380),(50,145,1000,370),'split'),
 ('横景对题',(50,145,1030,880),(180,1000,1010,1440),'split'),
 ('庆生竖笺',(210,145,1030,1375),(55,180,155,1260),'vertical'),
 ('展板下刊',(50,555,1030,1290),(60,145,1000,510),'split'),
 ('张臂书封',(105,345,950,1470),(50,140,1000,305),'line'),
 ('长桌终页',(50,300,1030,1035),(80,1110,1010,1445),'split'),
]

def render(item, i):
    with Image.open(item['image_path']) as src:
        photo = ImageOps.exif_transpose(src).convert('RGB')
    pal = palette(photo, i)
    bg, ink, muted = [pal[k] for k in ('background','foreground','muted')]
    im = Image.new('RGB',(1080,1800),bg)
    d = ImageDraw.Draw(im)
    name, region, titlebox, mode = LAYOUTS[i]
    records=[]
    def txt(s, box, size, font=None, color=None, track=True):
        if not s: return
        x,y,r,b=box
        while size>=24:
            f=ImageFont.truetype(font or FONTS[i%4],size)
            bb=d.textbbox((x,y),s,font=f,anchor='lt')
            if bb[2]<=r and bb[3]<=b:break
            size-=1
        assert size>=24,(i,s,box)
        d.text((x,y),s,font=f,fill=color or ink,anchor='lt')
        if track:records.append({'text':s,'box':bb,'size':size,'font':font or FONTS[i%4]})
    title=item.get('poster_title') or '今日一帧'
    english=item.get('poster_english') or ''
    x,y,r,b=titlebox
    ghost=tuple(round(a*.89+c*.11) for a,c in zip(bg,ink))
    # Large English sits under Chinese, confined to the title region.
    if mode=='vertical':
        layer=Image.new('RGBA',(b-y,r-x),(0,0,0,0)); ld=ImageDraw.Draw(layer)
        f=ImageFont.truetype(LATIN,86)
        while ld.textlength(english,font=f)>layer.width-10:f=ImageFont.truetype(LATIN,f.size-1)
        ld.text((0,0),english,font=f,fill=ghost+(255,),anchor='lt')
        im.paste(layer.rotate(90,expand=True),(x,y),layer.rotate(90,expand=True))
        step=min(126,(b-y)//len(title));size=min(96,step-18)
        for j,ch in enumerate(title):txt(ch,(x,y+j*step,r,y+(j+1)*step),size)
    else:
        words=english.split();cut=max(1,len(words)//2)
        for j,s in enumerate([' '.join(words[:cut]),' '.join(words[cut:])]):
            txt(s,(x,y+j*max(50,(b-y)//2),r,b),160,font=LATIN,color=ghost,track=False)
        if mode=='split':
            cut=(len(title)+1)//2
            txt(title[:cut],(x,y+16,r,y+(b-y)//2),132)
            txt(title[cut:],(x+100,y+(b-y)//2+10,r,b),88)
        else:txt(title,(x,y+8,r,b),100)
    # Preserve all content; a small background mat keeps rounded corners off faces.
    x,y,r,b=region
    fitted=ImageOps.contain(photo,(r-x-16,b-y-16),Image.Resampling.LANCZOS)
    px=x+(r-x-fitted.width)//2;py=y+(b-y-fitted.height)//2
    d.rounded_rectangle((px-8,py-8,px+fitted.width+8,py+fitted.height+8),radius=36,fill=muted)
    # Rounded image over the rounded mat, without a rectangular underlay.
    mask=Image.new('L',fitted.size,0)
    ImageDraw.Draw(mask).rounded_rectangle((0,0,fitted.width-1,fitted.height-1),radius=24,fill=255)
    im.paste(fitted,(px,py),mask)
    photo_box=(px-8,py-8,px+fitted.width+8,py+fitted.height+8)
    # Rotated readable English rail is separate from the low-contrast title layer.
    side=Image.new('RGBA',(1100,36),(0,0,0,0));sd=ImageDraw.Draw(side)
    f=ImageFont.truetype(LATIN,27)
    while sd.textlength(english,font=f)>1080:f=ImageFont.truetype(LATIN,f.size-1)
    sd.text((0,0),english,font=f,fill=muted+(255,),anchor='lt')
    side=side.rotate(90,expand=True); im.paste(side,(1040,300),side)
    txt('日常 / JOURNAL',(50,40,600,85),26,font=FONTS[0])
    txt(f'{i+1:02d} / 20',(905,40,1030,85),26,font=LATIN)
    d.line((50,100,1030,100),fill=muted,width=1)
    txt(english,(50,1490,1030,1530),32,font=LATIN)
    lines=[v.strip() for v in re.split('[，。]',item.get('ai_caption','')) if v.strip()]
    for j,s in enumerate(lines[:2]):txt(s,(50,1555+j*48,1030,1600+j*48),33)
    txt(item.get('place_display',''),(50,1680,1030,1720),27,color=muted)
    txt(item.get('date_display',''),(50,1735,1030,1775),25,color=muted)
    def overlap(a,b):return a[0]<b[2] and a[2]>b[0] and a[1]<b[3] and a[3]>b[1]
    for n,a in enumerate(records):
        box=a['box'];assert 0<=box[0]<box[2]<=1080 and 0<=box[1]<box[3]<=1800
        assert not overlap(box,photo_box),(i,'photo text overlap',a)
        for old in records[:n]:assert not overlap(box,old['box']),(i,'text collision',a,old)
    buf=BytesIO(); im.save(buf,'JPEG',quality=93)
    return buf.getvalue(),dict(index=i+1,layout=name,photo_box=photo_box,source_size=photo.size,photo_fit='contain',palette=pal,text=records)

