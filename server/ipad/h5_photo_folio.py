"""H5-lite only: three uncropped photographic book compositions."""
from pathlib import Path
from io import BytesIO
import re
from PIL import Image, ImageDraw, ImageFont, ImageOps

VERSION = 'folio-25'
SERIF = '/System/Library/Fonts/Supplemental/Songti.ttc'
LATIN = '/System/Library/Fonts/Supplemental/Baskerville.ttc'
PAPER = '#F2EEE5'
INK = '#272A26'
RUST = '#8B3D2E'


def font(size, latin=False):
    return ImageFont.truetype(LATIN if latin else SERIF, size)


def render(item, index, count):
    with Image.open(item['image_path']) as opened:
        photo = ImageOps.exif_transpose(opened).convert('RGB')
    mode = index % 3
    dark = mode == 2
    bg, fg, muted = ('#18221F', PAPER, '#C2C8BC') if dark else (PAPER, INK, '#62655B')
    canvas = Image.new('RGB', (1080, 1800), bg)
    d = ImageDraw.Draw(canvas)
    boxes = []

    def text(value, x, y, size, color=None, latin=False, width=None):
        value = str(value or '')
        f = font(size, latin)
        while width and d.textbbox((0, 0), value, font=f)[2] > width and size > 18:
            size -= 1
            f = font(size, latin)
        box = d.textbbox((x, y), value, font=f, anchor='lt')
        assert box[0] >= 0 and box[2] <= 1080 and box[3] < 1780, (value, box)
        d.text((x, y), value, font=f, fill=color or fg, anchor='lt')
        boxes.append({'text': value, 'box': box})
        return box

    def image(rect, align='center'):
        x,y,w,h = rect
        fitted = ImageOps.contain(photo, (w,h), Image.Resampling.LANCZOS)
        yy = y if align == 'top' else y+(h-fitted.height)//2
        xx = x+(w-fitted.width)//2
        canvas.paste(fitted,(xx,yy))
        return (xx,yy,xx+fitted.width,yy+fitted.height)

    title = item.get('poster_title') or item.get('title') or '今日一帧'
    english = item.get('poster_english') or ''
    caption = item.get('ai_caption') or item.get('description') or ''
    date = re.search(r'(\d{4})年(\d+)月(\d+)日', item.get('date_display',''))
    year, day = (date[1], f'{int(date[2]):02d} / {int(date[3]):02d}') if date else ('', '')
    place = item.get('place_display') or ''
    clauses = [s.strip() for s in re.split('[，,。]',caption) if s.strip()]
    text('日常成册', 64, 58, 28)
    text('THE DAILY PHOTO JOURNAL', 270, 61, 23, muted, True)
    text(f'{index+1:02d} / {count:02d}', 904, 60, 26, muted, True)
    d.line((64,110,1016,110), fill=muted, width=1)

    if mode == 0:
        # A book cover: headline above, full image right, date in the margin.
        text(title, 64, 167, 104, width=950)
        text(english, 70, 300, 28, RUST, True, 940)
        image_box = image((242,400,774,1050),'top')
        text(year, 64, 407, 54, RUST, True)
        text(day, 66, 476, 27, muted, True)
        d.line((98,555,98,790),fill='#ABA99C',width=1)
        for j,c in enumerate('生活切片'):
            text(c, 82, 836+j*48, 31, muted)
        caption_y = max(1300, image_box[3]+58)
        for j,line in enumerate(clauses):
            text(line, 242, caption_y+j*52, 33, width=764)
    elif mode == 1:
        # An asymmetric spread: solid ink title block, borderless full-width photo.
        d.rectangle((0,146,756,395),fill=INK)
        text(title,64,190,88,PAPER,width=638)
        text(english,68,310,25,'#D3CAB8',True,635)
        text(year,803,202,62,RUST,True)
        text(day,807,285,28,muted,True)
        image_box = image((64,444,952,1000),'top')
        cy = image_box[3]+58
        text('影像札记',64,cy,28,RUST)
        for j,line in enumerate(clauses):
            text(line,302,cy+j*53,35,width=708)
        d.line((64,cy+152,1016,cy+152),fill='#B6B1A4',width=1)
    else:
        # A cinema plate: no overlay, no blur; photograph and credits separated.
        text(english,64,163,31,'#D3B88C',True,950)
        text(title,64,218,85,width=950)
        image_box = image((64,374,952,1120))
        for j,line in enumerate(clauses):
            text(line,64,1531+j*47,31,width=950)
        text(year+'  /  '+day,64,1642,29,'#D3B88C',True)

    d.line((64,1700,1016,1700),fill=muted,width=1)
    text(place,64,1730,25,muted,width=820)
    text(f'{index+1:02d}',960,1726,34,muted,True)
    # Keep typography entirely outside the uncropped photograph.
    for record in boxes:
        a,b,c,e=record['box']; x,y,z,w=image_box
        assert c<=x or a>=z or e<=y or b>=w, ('photo/text overlap',record)
    output=BytesIO()
    canvas.save(output,'JPEG',quality=92,optimize=True,progressive=True)
    return output.getvalue()


def render_cached(payload,index,root):
    items=payload.get('items') or []
    if not items:
        return None
    index %= len(items)
    item=items[index]
    source=Path(item.get('image_path') or '')
    if not source.is_file():
        return None
    directory=Path(root)/str(payload.get('date') or 'unknown')
    cache=directory/('rendered-'+VERSION)/f'frame-{index+1:02d}.jpg'
    manifest=directory/'manifest.json'
    changed=max(source.stat().st_mtime,Path(__file__).stat().st_mtime,manifest.stat().st_mtime if manifest.exists() else 0)
    if cache.exists() and cache.stat().st_mtime>=changed:
        return cache.read_bytes()
    body=render(item,index,len(items))
    cache.parent.mkdir(parents=True,exist_ok=True)
    cache.write_bytes(body)
    return body
