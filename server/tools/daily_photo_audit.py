import json, pathlib, urllib.request
from PIL import Image, ImageOps, ImageDraw
root=pathlib.Path('/Users/teamc/Documents/RemotePanelih5Standalone')
out=root/'ipad/data/h5_daily_photos/2026-10-19/audit'
out.mkdir(exist_ok=True)
m=json.loads((out.parent/'manifest.json').read_text())
for route in ['/h5-lite','/api/h5/state','/api/h5/photos']:
 with urllib.request.urlopen('http://127.0.0.1:9121'+route,timeout=40) as r:
  data=r.read();print(route,r.status,len(data))
  if route.startswith('/api'): (out/(route.rsplit('/',1)[-1]+'.json')).write_bytes(data)
print('items',len(m['items']))
sheet=Image.new('RGB',(1600,2000),'white');d=ImageDraw.Draw(sheet)
for i,item in enumerate(m['items']):
 im=Image.open(item['image_path']);im=ImageOps.contain(im,(390,355))
 x=(i%4)*400;y=(i//4)*400
 sheet.paste(im,(x+(400-im.width)//2,y+35));d.text((x+12,y+8),str(i+1),fill='black',font_size=24)
sheet.save(out/'sources.jpg')
print(out/'sources.jpg')
