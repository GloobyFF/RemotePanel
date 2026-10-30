from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import sys
from datetime import datetime
from pathlib import Path
sys.path.insert(0, '.')
from tools.export_person_photo import visual_editorial

manifest_path = Path('ipad/data/h5_daily_photos/2026-08-04/manifest.json')
data = json.loads(manifest_path.read_text(encoding='utf-8'))
items = data.get('items') or []

def one(item):
    try:
        editorial = visual_editorial(Path(str(item['image_path'])), str(item.get('asset_id') or ''))
        return item.get('asset_id'), {k: editorial[k] for k in ('ai_caption', 'caption_asset_id', 'caption_source')}, None
    except Exception as exc:
        return item.get('asset_id'), None, f'{type(exc).__name__}: {exc}'

results = {}
with ThreadPoolExecutor(max_workers=4) as pool:
    futures = [pool.submit(one, item) for item in items]
    for future in as_completed(futures):
        asset_id, editorial, error = future.result()
        results[asset_id] = (editorial, error)
updated = 0
for item in items:
    editorial, error = results.get(item.get('asset_id'), (None, 'missing result'))
    if editorial:
        item.update(editorial)
        updated += 1
    elif error:
        print('KEEP_OLD', item.get('asset_id'), error)
data['editorial_updated_at'] = datetime.now().isoformat()
tmp = manifest_path.with_suffix('.json.tmp')
tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
tmp.replace(manifest_path)
print(f'MANIFEST_UPDATED updated={updated}/{len(items)}')
for item in items:
    print(item.get('poster_title'), '=>', item.get('ai_caption'))
