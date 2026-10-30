"""Twenty OFFLINE H5-lite compositions; live folio renderer is not modified.

All twenty, including the original first three, use the same photo-derived
palette and measured layout engine. Source derivatives are only read.
"""
from io import BytesIO
import re
from PIL import Image, ImageDraw, ImageOps
from h5_photo_folio import font
from h5_photo_palette import palette

NAMES = ['书封边注','非对称跨页','电影画幅','上图下刊','竖排诗笺','牵手宽幅','满幅书页','深色画廊','明信片','合影札记','胶片索引','彩色刊头','餐桌图录','音乐画报','城市侧记','舞台展签','花畔档案','折页书信','纪念腰封','终章海报']
# margin, headline position, alignment, heading scale, header rule style.
# These are twenty distinct geometric compositions, not merely color swaps.
STYLES = [(52,'top','left',84,0),(28,'bottom','right',86,1),
 (44,'top','center',78,2),(36,'bottom','left',92,0),
 (60,'top','right',80,1),(28,'top','left',96,2),
 (36,'bottom','left',78,1),(48,'bottom','center',94,2),
 (40,'top','center',88,0),(24,'bottom','right',96,0),
 (54,'top','left',76,2),(32,'top','right',102,1),
 (46,'bottom','right',82,2),(20,'bottom','left',104,1),
 (48,'top','right',86,0),(36,'top','center',100,2),
 (32,'bottom','center',80,0),(56,'top','left',98,1),
 (24,'top','center',82,1),(44,'bottom','center',102,0)]


def render(item, index, count=20, audit=None):
    k = index % 20
    margin, position, align, title_size, rule = STYLES[k]
    with Image.open(item['image_path']) as opened:
        photo = ImageOps.exif_transpose(opened).convert('RGB')
    tokens = palette(photo, k)
    bg, fg, muted = (tokens[key] for key in ('background','foreground','muted'))
    canvas = Image.new('RGB', (1080, 1800), bg)
    d = ImageDraw.Draw(canvas)
    boxes = []

    def block(value, rect, size, color=fg, latin=False, alignment='left'):
        value = str(value or '').strip()
        if not value:
            return
        x,y,w,h = rect
        for s in range(size, 23, -1):
            f = font(s, latin)
            lines, line = [], ''
            for ch in value:
                if ch == '\n' or (line and d.textlength(line+ch, font=f) > w):
                    lines.append(line)
                    line = '' if ch == '\n' else ch
                else:
                    line += ch
            if line:
                lines.append(line)
            step = s + max(10, s//5)
            if len(lines)*step <= h:
                break
        else:
            raise ValueError(('Text cannot fit at readable size', k, value, rect))
        for j,line in enumerate(lines):
            raw = d.textbbox((0,0),line,font=f,anchor='lt')
            length = raw[2]-raw[0]
            xx = x - raw[0] + (w-length if alignment=='right' else (w-length)/2 if alignment=='center' else 0)
            b = d.textbbox((xx,y+j*step),line,font=f,anchor='lt')
            assert b[0]>=x-1 and b[2]<=x+w+1 and b[1]>=y and b[3]<=y+h, (k,line,b,rect)
            d.text((xx,y+j*step),line,font=f,fill=color,anchor='lt')
            boxes.append({'text':line,'box':b,'font_size':s,'color':color})

    width = 1080-2*margin
    portrait = photo.height > photo.width
    max_height = 1140 if portrait else 900
    if k == 6:
        max_height = 1200
    fitted = ImageOps.contain(photo,(width,max_height),Image.Resampling.LANCZOS)
    # Content is a contiguous, centered editorial stack, not a tiny picture
    # marooned inside a tall preallocated rectangle.
    title_h = 150 if portrait else 210
    caption_h = 180 if portrait else 280
    if k == 6:
        title_h, caption_h = 128, 172
    gap = 28 if portrait else 40
    stack_h = title_h + fitted.height + caption_h + 2*gap
    start = 132 + max(0,(1520-stack_h)//2)
    if position == 'top':
        title_y, photo_y = start, start+title_h+gap
        caption_y = photo_y+fitted.height+gap
    else:
        photo_y = start
        title_y = photo_y+fitted.height+gap
        caption_y = title_y+title_h+gap
    px = (1080-fitted.width)//2
    canvas.paste(fitted,(px,int(photo_y)))
    photo_box = (px,int(photo_y),px+fitted.width,int(photo_y)+fitted.height)
    block('日常成册  /  '+NAMES[k],(margin,48,780,40),26)
    block(f'{index+1:02d} / {count:02d}',(900,48,140,40),26,muted,True)
    if rule != 2:
        d.line((margin,106,1080-margin if rule==0 else 540,106),fill=muted,width=2)
    title = item.get('poster_title') or item.get('title') or '今日一帧'
    block(title,(margin,title_y,width,title_h-44),title_size,alignment=align)
    block(item.get('poster_english') or '',(margin,title_y+title_h-38,width,38),26,muted,True,align)
    caption = str(item.get('ai_caption') or item.get('description') or '').strip()
    # Preserve the supplied scene narrative; never infer visited POIs from district.
    place = str(item.get('place_display') or '').strip()
    scene_h = 80 if portrait else 112
    block(caption,(margin,caption_y,width,scene_h),34 if portrait else 42)
    location = '照片地点  /  '+place if place else '照片地点  /  未提供地点信息'
    block(location,(margin,caption_y+scene_h+10,width,68),26,muted)
    if not portrait:
        block('地点依照片记录；不据行政区推定具体景点。' if place else '保留现场叙事，不补写未经确认的拍摄地点。',
              (margin,caption_y+scene_h+92,width,65),25,muted)
    date = re.sub(r'星期.', '', item.get('date_display') or '').strip()
    block(date,(margin,1724,width,40),26,muted)
    d.line((margin,1698,1080-margin,1698),fill=muted,width=1)
    def overlaps(a,b):
        return a[0]<b[2] and a[2]>b[0] and a[1]<b[3] and a[3]>b[1]
    for i,record in enumerate(boxes):
        assert not overlaps(record['box'],photo_box), ('photo overlap',k,record)
        assert all(not overlaps(record['box'],other['box']) for other in boxes[:i]), ('text overlap',k,record)
        assert record['box'][3] < 1780
    if audit is not None:
        audit.update({'layout':NAMES[k],'style':STYLES[k],'palette':tokens,
                      'photo_box':photo_box,'source_size':photo.size,'fit_size':fitted.size,
                      'uncropped':True,'text_boxes':boxes,'min_font_size':min(b['font_size'] for b in boxes),
                      'location_source':'place_display' if place else None,
                      'nearby_poi_claims':[], 'image_text_collisions':0,'text_text_collisions':0})
    out = BytesIO()
    canvas.save(out,'JPEG',quality=92,optimize=True)
    return out.getvalue()
