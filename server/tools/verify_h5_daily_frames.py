from pathlib import Path
from PIL import Image, ImageOps, ImageDraw, ImageFont
import time
import urllib.error
import urllib.request

base = 'http://127.0.0.1:9121/h5-photo-frame.jpg?index={}'
out = Path('/tmp/h5_rendered_frames')
out.mkdir(exist_ok=True)
files = []
for i in range(20):
    p = out / f'frame-{i+1:02d}.jpg'
    last = None
    for attempt in range(5):
        try:
            request = urllib.request.Request(base.format(i), headers={'Connection': 'close'})
            with urllib.request.urlopen(request, timeout=60) as response:
                body = response.read()
                assert response.status == 200 and response.headers.get_content_type() == 'image/jpeg'
            p.write_bytes(body)
            break
        except (OSError, urllib.error.URLError, AssertionError) as exc:
            last = exc
            time.sleep(1.5)
    else:
        raise RuntimeError(f'frame {i + 1} failed: {last}')
    with Image.open(p) as im:
        im.verify()
    with Image.open(p) as im:
        assert im.size == (1080, 1800), (i + 1, im.size)
    files.append(p)
thumb = (216, 360)
label_h = 28
sheet = Image.new('RGB', (5 * thumb[0], 4 * (thumb[1] + label_h)), (18, 20, 25))
draw = ImageDraw.Draw(sheet)
font = ImageFont.load_default()
for i, p in enumerate(files):
    with Image.open(p).convert('RGB') as im:
        tile = ImageOps.fit(im, thumb, method=Image.Resampling.LANCZOS)
    x = (i % 5) * thumb[0]
    y = (i // 5) * (thumb[1] + label_h)
    sheet.paste(tile, (x, y))
    draw.text((x + 8, y + thumb[1] + 6), f'{i+1:02d} {p.name}', fill='white', font=font)
sheet_path = Path('/tmp/h5_rendered_contact.jpg')
sheet.save(sheet_path, quality=92)
print({'frames': len(files), 'dimensions': '1080x1800', 'contact_sheet': str(sheet_path)})
