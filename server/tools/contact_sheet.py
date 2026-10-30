from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import sys
root=Path(sys.argv[1])
out=Path(sys.argv[2])
files=sorted(root.glob('photo-*')) or sorted(root.glob('frame-*.jpg'))
thumb_w,thumb_h=270,300
cols=4
rows=(len(files)+cols-1)//cols
sheet=Image.new('RGB',(cols*thumb_w,rows*thumb_h),(24,28,36))
d=ImageDraw.Draw(sheet)
for i,p in enumerate(files):
    with Image.open(p) as im:
        im=im.convert('RGB'); im.thumbnail((thumb_w-20,thumb_h-48))
        x=(i%cols)*thumb_w+(thumb_w-im.width)//2; y=(i//cols)*thumb_h+28
        sheet.paste(im,(x,y))
    d.text(((i%cols)*thumb_w+10,(i//cols)*thumb_h+8),f'{i+1:02d}  {p.name}',fill='white')
sheet.save(out,quality=92)
print(out, len(files), sheet.size)
