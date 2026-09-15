#!/usr/bin/env python3
"""Deterministic, original vector-like app icon. No network or third-party dependencies."""
from pathlib import Path
import json,math,struct,zlib
root=Path(__file__).resolve().parents[1]/'TraceGlass/Resources/Assets.xcassets'
root.mkdir(parents=True,exist_ok=True)
(root/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
icon=root/'AppIcon.appiconset';icon.mkdir(exist_ok=True)
(icon/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2))
accent=root/'AccentColor.colorset';accent.mkdir(exist_ok=True)
(accent/'Contents.json').write_text(json.dumps({'colors':[{'idiom':'universal','color':{'color-space':'srgb','components':{'red':'0.57','green':'0.96','blue':'0.83','alpha':'1'}}}],'info':{'author':'xcode','version':1}},indent=2))
def rounded(x,y,cx,cy,w,h,r):
 dx=abs(x-cx)-(w/2-r);dy=abs(y-cy)-(h/2-r)
 return math.hypot(max(0,dx),max(0,dy))+min(0,max(dx,dy))-r
rows=[]
for y in range(1024):
 row=bytearray([0])
 for x in range(1024):
  light=max(0,1-math.hypot(x-250,y-170)/1050)
  rgb=[int(10+light*12),int(19+light*20),int(25+light*27)]
  for cx,cy,angle,w,h in [(430,494,-.15,415,556),(551,524,.14,415,556)]:
   dx=x-cx;dy=y-cy;xx=dx*math.cos(angle)+dy*math.sin(angle);yy=-dx*math.sin(angle)+dy*math.cos(angle)
   d=rounded(xx,yy,0,0,w,h,67)
   if d<0:
    rgb=[int(rgb[0]*.65+56*.35),int(rgb[1]*.65+102*.35),int(rgb[2]*.65+104*.35)]
   if abs(d)<2.7:rgb=[124,206,188]
  # A continuous tracing path inside the front sheet.
  yy=(y-310)/430
  if 0<yy<1:
   target=550+90*math.sin(yy*math.pi*2-.6)
   if abs(x-target)<5.5:rgb=[158,248,215]
  if math.hypot(x-558,y-755)<18:rgb=[158,248,215]
  row.extend(rgb)
 rows.append(bytes(row))
def chunk(t,d):return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1024,1024,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(rows),9))+chunk(b'IEND',b'')
(icon/'AppIcon.png').write_bytes(png)
print('Generated app icon and accent color')
