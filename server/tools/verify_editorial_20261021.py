import json, urllib.request, io, concurrent.futures
from pathlib import Path
from PIL import Image
from editorial_check_20261021 import OUT, sheet
BASE='http://127.0.0.1:9121'
def get(path):
    with urllib.request.urlopen(BASE+path,timeout=120) as r:
        body=r.read(); assert r.status==200
        return body
routes={}
for route in ['/h5-lite','/ipad/control','/api/h5/state','/api/h5/photos']:
    b=get(route); routes[route]={'status':200,'bytes':len(b)}
    if route.startswith('/api/'):
        (OUT/(route.rsplit('/',1)[1]+'.json')).write_bytes(b)
photos=json.loads((OUT/'photos.json').read_text()); items=photos['items']; assert len(items)==20
for field in ['poster_title','poster_english','ai_caption']:
    assert all(i.get(field) for i in items)
    assert len({i[field] for i in items})==20
assert all(i.get('poster_accent') for i in items)
def fetch(i):
    body=get('/h5-photo-frame.jpg?index='+str(i))
    im=Image.open(io.BytesIO(body)); im.load(); assert im.format=='JPEG' and im.size==(1080,1800),(i,im.size)
    p=OUT/f'frame-{i+1:02d}.jpg'; p.write_bytes(body)
    return p
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool: paths=list(pool.map(fetch,range(20)))
sheet(paths,OUT/'rendered-contact.jpg',(270,480))
report={'routes':routes,'frame_count':len(paths),'dimensions':[1080,1800],'unique_editorial_counts':{f:len({i[f] for i in items}) for f in ['poster_title','poster_english','ai_caption']},'editorial_updated_at':photos.get('editorial_updated_at')}
(OUT/'verification.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,ensure_ascii=False))
