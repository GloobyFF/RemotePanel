from pathlib import Path
from PIL import Image, ImageOps, ImageDraw, ImageFont
root = Path('/Users/teamc/Documents/RemotePanelih5Standalone/ipad/data/h5_daily_photos/2026-08-31')
files = sorted(root.glob('photo-*.jpeg'))
cell_w, cell_h, label_h = 270, 310, 34
sheet = Image.new('RGB', (cell_w * 4, (cell_h + label_h) * 5), '#20242b')
draw = ImageDraw.Draw(sheet)
for index, path in enumerate(files):
    image = Image.open(path).convert('RGB')
    thumb = ImageOps.contain(image, (cell_w - 16, cell_h - 16))
    cell = Image.new('RGB', (cell_w, cell_h), '#39414d')
    cell.paste(thumb, ((cell_w - thumb.width) // 2, (cell_h - thumb.height) // 2))
    x, y = (index % 4) * cell_w, (index // 4) * (cell_h + label_h)
    sheet.paste(cell, (x, y))
    draw.text((x + 10, y + cell_h + 8), f'{index + 1:02d}  {path.name}', fill='white')
sheet.save(root / 'source-contact-sheet.jpg', quality=92, optimize=True)
print(root / 'source-contact-sheet.jpg', sheet.size, len(files))
