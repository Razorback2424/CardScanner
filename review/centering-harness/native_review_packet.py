#!/usr/bin/env python3
"""Unmarked native-photo crops with coordinate ticks for source-only review.

Centers locate review windows, not annotations. No detector geometry or scoring
enters this packet; reviewer bands must be recorded separately before comparison.
"""
import argparse,hashlib,json
from pathlib import Path
from PIL import Image,ImageOps,ImageDraw,ImageFont
import pillow_heif


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['image','windows','output']:p.add_argument(name,type=Path)
    a=p.parse_args();pillow_heif.register_heif_opener()
    im=ImageOps.exif_transpose(Image.open(a.image)).convert('RGB');spec=json.loads(a.windows.read_text())
    a.output.mkdir(parents=True,exist_ok=True);font=ImageFont.load_default(size=12)
    metadata=[]
    for frame,sides in spec.items():
        sheet=Image.new('RGB',(1200,960),'white');d=ImageDraw.Draw(sheet)
        for row,(side,centers) in enumerate(sides.items()):
            for col,(x,y) in enumerate(centers):
                x0,y0=int(x)-48,int(y)-48;bx,by=col*240,row*240
                if min(x0,y0)<0 or x0+96>im.width or y0+96>im.height:raise ValueError('window outside photo')
                crop=im.crop((x0,y0,x0+96,y0+96)).resize((192,192),Image.Resampling.NEAREST)
                sheet.paste(crop,(bx+40,by+24));d.text((bx+40,by+4),f'{frame} {side} ({x},{y})',fill='black',font=font)
                for t in [0,32,64,95]:
                    d.text((bx+max(0,40+2*t-12),by+218),str(x0+t),fill='black',font=font)
                    d.text((bx,by+20+2*t),str(y0+t),fill='black',font=font)
                metadata.append(dict(frame=frame,side=side,center=[x,y],box=[x0,y0,x0+96,y0+96]))
        sheet.save(a.output/(frame+'-windows.png'))
    (a.output/'packet.json').write_text(json.dumps(dict(inputSHA256=hashlib.sha256(a.image.read_bytes()).hexdigest(),
        dimensions=list(im.size),windows=metadata,status='unmarked photo crops; not boundary annotations'),indent=2)+'\n')
