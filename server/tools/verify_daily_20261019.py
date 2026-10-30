import pathlib,json,urllib.request,io,datetime
from PIL import Image,ImageOps,ImageDraw
root=pathlib.Path('/Users/teamc/Documents/RemotePanelih5Standalone');out=root/'ipad/data/h5_daily_photos/2026-10-19/audit'
sheet=Image.new('RGB',(1800,3100),'white');draw=ImageDraw.Draw(sheet)
for i in range(20):
 with urllib.request.urlopen(f'http://127.0.0.1:9121/h5-photo-frame.jpg?index={i}',timeout=90) as r:
  assert r.status==200;b=r.read()
 im=Image.open(io.BytesIO(b));assert im.format=='JPEG' and im.size==(1080,1800);im.load()
 (out/f'frame-{i+1:02d}.jpg').write_bytes(b)
 im.thumbnail((360,600));x=i%5*360;y=i//5*775
 sheet.paste(im,(x,y+30));draw.text((x+10,y+5),str(i+1),fill='black',font_size=22)
 print('frame',i+1,'OK',flush=True)
sheet.save(out/'rendered.jpg')
with urllib.request.urlopen('http://127.0.0.1:9121/api/h5/photos',timeout=40) as r: m=json.load(r)
print('photos keys',list(m));assert len(m['items'])==20
for k in ['poster_title','poster_english','ai_caption']:
 assert all(x.get(k) for x in m['items']);assert len({x[k] for x in m['items']})==20
print('API unique fields: 20 each',m.get('editorial_updated_at'))
c=json.loads((root/'ipad/hermes_bridge/content_cache.json').read_text())
print('cache mtime',datetime.datetime.fromtimestamp((root/'ipad/hermes_bridge/content_cache.json').stat().st_mtime).isoformat())
print('cache structure',list(c)[:12])
for k,v in c.items():
 if isinstance(v,dict) and any(s in k for s in ['steam','movies','weather']):print(k,'updated',v.get('updated_at'),'items',len(v.get('items',[])))
with urllib.request.urlopen('http://127.0.0.1:9121/api/h5/state',timeout=40) as r: s=json.load(r)
print('state times',{k:v for k,v in s.items() if 'updated' in k or 'refresh' in k});print('screens',[(x.get('id'),x.get('title')) for x in s.get('screens',[])])
with urllib.request.urlopen('http://127.0.0.1:9121/ipad/control',timeout=40) as r: print('control',r.status)
(out/'verification.json').write_text(json.dumps({'frames':20,'dimensions':[1080,1800],'unique_editorial':20,'checked_at':datetime.datetime.now().isoformat()},indent=2))
