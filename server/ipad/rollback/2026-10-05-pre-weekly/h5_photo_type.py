"""Typography study: offline only, source photos remain untouched."""
from io import BytesIO
from PIL import Image,ImageDraw,ImageFont,ImageOps
from h5_photo_palette import palette
FONTS=['/System/Library/Fonts/Supplemental/Songti.ttc','/System/Library/Fonts/STHeiti Medium.ttc','/System/Library/Fonts/Hiragino Sans GB.ttc','/System/Library/Fonts/Supplemental/Arial Unicode.ttf']
LATIN='/System/Library/Fonts/Supplemental/Baskerville.ttc'
VERTICAL={0,3,4,8,11,14,17}

def render(item,i):
 with Image.open(item['image_path']) as im: photo=ImageOps.exif_transpose(im).convert('RGB')
 p=palette(photo,i); bg,fg,muted=[p[k] for k in ('background','foreground','muted')]
 out=Image.new('RGB',(1080,1800),bg);d=ImageDraw.Draw(out);records=[]
 family=FONTS[i%4];vertical=i in VERTICAL
 def text(s,x,y,size,width=960,path=None,color=None):
  s=str(s or '')
  if not s:return
  while size>=20:
   f=ImageFont.truetype(path or family,size)
   b=d.textbbox((x,y),s,font=f,anchor='lt')
   if b[2]<=x+width:break
   size-=1
  assert b[2]<=1080 and b[3]<1785,(i,s,b)
  d.text((x,y),s,font=f,fill=color or fg,anchor='lt');records.append({'text':s,'box':b,'font':path or family,'size':size})
 title=item.get('poster_title') or '今日一帧';eng=item.get('poster_english') or ''
 # English is a compositional layer behind the Chinese, not a tiny subtitle.
 ghost=tuple(round(bg[c]*.70+fg[c]*.30) for c in range(3))
 layer=Image.new('RGBA',(1080,1800),(0,0,0,0));ld=ImageDraw.Draw(layer)
 words=eng.upper().split(); lines=[];line=''
 ef=ImageFont.truetype(LATIN,130 if i%2 else 150)
 for word in words:
  trial=(line+' '+word).strip()
  if line and ld.textlength(trial,font=ef)>1040:lines.append(line);line=word
  else:line=trial
 if line:lines.append(line)
 for j,line in enumerate(lines[:3]):
  ld.text((20,112+j*110),line,font=ef,fill=ghost+(255,),anchor='lt')
 if vertical:
  side=Image.new('RGBA',(1240,170),(0,0,0,0));sd=ImageDraw.Draw(side)
  sf=ImageFont.truetype(LATIN,76)
  while sd.textlength(eng.upper(),font=sf)>1200:sf=ImageFont.truetype(LATIN,sf.size-1)
  sd.text((0,15),eng.upper(),font=sf,fill=ghost+(255,),anchor='lt')
  layer.alpha_composite(side.rotate(90,expand=True),(12,260))
 out=Image.alpha_composite(out.convert('RGBA'),layer).convert('RGB');d=ImageDraw.Draw(out)
 def paste_photo(fit,xy):
  mask=Image.new('L',fit.size,0)
  ImageDraw.Draw(mask).rounded_rectangle((0,0,fit.width-1,fit.height-1),radius=36 if i%2 else 52,fill=255)
  out.paste(fit,xy,mask)
 text('日常 / JOURNAL',50,45,25,path=LATIN)
 text(f'{i+1:02d} — 20',910,45,24,width=130,path=LATIN)
 d.line((50,99,1030,99),fill=muted)
 if vertical:
  fit=ImageOps.contain(photo,(865,1230),Image.Resampling.LANCZOS)
  px=190+(865-fit.width)//2;py=240+(1230-fit.height)//2
  paste_photo(fit,(px,py))
  size=min(112,1080//max(1,len(title)))
  for j,ch in enumerate(title):text(ch,48,240+j*(size+24),size,width=135)
  # English remains readable horizontally, paired with Chinese title above.
  text(eng,190,150,38,width=850,path=LATIN,color=muted)
  cy=1510
 else:
  fit=ImageOps.contain(photo,(1020,1180),Image.Resampling.LANCZOS)
  px=(1080-fit.width)//2;py=280+(1180-fit.height)//2
  paste_photo(fit,(px,py))
  if i%3==1:
   # Big leading character and a compact continuation form a split-scale heading.
   text(title[:1],46,126,142,width=170)
   text(title[1:],225,158,76,width=800)
  else:text(title,45,138,116 if i%2 else 86,width=985)
  text(eng,50,py+fit.height+22,34,path=LATIN,color=muted)
  cy=max(1530,py+fit.height+77)
 caption=str(item.get('ai_caption') or '')
 import re
 clauses=[s.strip() for s in re.split('[，。]',caption) if s.strip()]
 for j,s in enumerate(clauses[:2]):text(s,50,cy+j*46,32,width=980)
 text(item.get('place_display') or '',50,1660,25,color=muted)
 text(item.get('date_display') or '',50,1730,24,color=muted)
 # Text is kept out of faces; photo overlay experiments need individual visual review.
 for a in range(len(records)):
  b=records[a]['box']
  for old in records[:a]:
   c=old['box'];assert not(b[0]<c[2] and b[2]>c[0] and b[1]<c[3] and b[3]>c[1]),(i,'text overlap',records[a],old)
 buf=BytesIO();out.save(buf,'JPEG',quality=92)
 return buf.getvalue(),{'index':i+1,'vertical':vertical,'title_font':family,'text':records,'intentional_photo_overlap':False}
