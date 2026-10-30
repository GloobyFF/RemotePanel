from __future__ import annotations

import json
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "ipad" / "data" / "h5_daily_photos" / "2026-10-02" / "cron-verified-frames"
OUT_DIR.mkdir(parents=True, exist_ok=True)

results = []
for index in range(20):
    url = f"http://127.0.0.1:9121/h5-photo-frame.jpg?index={index}&verify=20261002"
    path = OUT_DIR / f"frame-{index + 1:02d}.jpg"
    with urllib.request.urlopen(url, timeout=90) as response:
        body = response.read()
        status = response.status
        content_type = response.headers.get_content_type()
    path.write_bytes(body)
    with Image.open(path) as image:
        size = image.size
        image_format = image.format
    valid = status == 200 and content_type == "image/jpeg" and image_format == "JPEG" and size == (1080, 1800)
    results.append({"index": index, "status": status, "type": content_type, "format": image_format, "size": size, "bytes": len(body), "valid": valid})

if not all(result["valid"] for result in results):
    raise RuntimeError(json.dumps(results, ensure_ascii=False))

font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 28)
cell_width, cell_height = 270, 450
sheet = Image.new("RGB", (cell_width * 5, cell_height * 4), "#111111")
for position, result in enumerate(results):
    with Image.open(OUT_DIR / f"frame-{position + 1:02d}.jpg") as image:
        tile = ImageOps.fit(image.convert("RGB"), (cell_width, cell_height), method=Image.Resampling.LANCZOS)
    draw = ImageDraw.Draw(tile)
    draw.rectangle((0, 0, 58, 40), fill="black")
    draw.text((8, 4), str(position + 1), font=font, fill="white")
    sheet.paste(tile, ((position % 5) * cell_width, (position // 5) * cell_height))
contact_path = OUT_DIR / "rendered-contact-sheet.jpg"
sheet.save(contact_path, quality=92)
print(json.dumps({"frames": len(results), "valid": sum(result["valid"] for result in results), "contact_sheet": str(contact_path), "results": results}, ensure_ascii=False))
