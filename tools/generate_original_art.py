"""Regenerate the original island map and terrain texture.
Requires Pillow. Not required to play the game. Run from repository root.
"""
from pathlib import Path
from PIL import Image, ImageDraw
import random

ROOT = Path('assets/environment')
ROOT.mkdir(parents=True, exist_ok=True)
rng = random.Random(2291)
# The map doubles as the texture of the 3D terrain.
w, h = 1600, 1100
im = Image.new('RGB', (w, h), '#1e414a')
d = ImageDraw.Draw(im)
shore = [(105,60),(330,23),(720,38),(1115,25),(1455,75),(1530,198),(1555,444),(1536,742),(1514,1010),(1372,1068),(980,1053),(656,1077),(307,1065),(70,1007),(45,795),(55,540),(40,303)]
land = [(121,78),(345,52),(720,65),(1100,53),(1430,99),(1500,222),(1517,445),(1507,736),(1485,987),(1354,1035),(979,1023),(655,1046),(326,1031),(100,977),(79,788),(83,536),(70,310)]
d.polygon(shore, fill='#b8a174')
d.line(shore + shore[:1], fill='#5c7b72', width=6, joint='curve')
d.polygon(land, fill='#526b4c')
# Biome areas, deliberately faded under the landmarks.
d.ellipse((300,60,930,510), fill='#455f45')
d.ellipse((290,115,735,440), fill='#405b43')
d.ellipse((1040,185,1510,620), fill='#65705b')
d.ellipse((900,495,1430,845), fill='#61705b')
d.ellipse((180,450,665,820), fill='#677b52')
d.ellipse((1170,785,1500,1030), fill='#6b755a')
# Coast and paths: all points correspond to named places in scripts/world.gd.
paths = [
 [(180,920),(300,860),(340,775),(425,650)], # beach to village
 [(425,650),(560,618),(715,560),(810,440),(730,240)], # forest
 [(425,650),(365,555),(340,400),(295,215)], # caves
 [(425,650),(600,700),(820,730),(1095,700)], # hotel
 [(1095,700),(1150,590),(1210,470),(1285,325)], # runway
 [(1095,700),(1230,770),(1320,820),(1375,900)], # lighthouse
 [(180,975),(220,905),(330,840),(425,650)], # dock
]
for p in paths:
 d.line(p, fill='#425541', width=50, joint='curve')
 d.line(p, fill='#988966', width=38, joint='curve')
 d.line(p, fill='#a4946f', width=30, joint='curve')
# Airfield and hotel ground silhouettes.
d.rounded_rectangle((1150,220,1468,395), radius=8, fill='#747a6d', outline='#4f5f56', width=4)
d.rectangle((1170,255,1460,355), fill='#626d64')
for x in range(1190, 1450, 60): d.rectangle((x,302,x+32,306),fill='#b2ae8e')
d.rounded_rectangle((980,620,1180,780), radius=8, fill='#7a7c6b', outline='#59685b', width=4)
# Gentle low-resolution grass and dust marks, clamped to the island.
for _ in range(19000):
 x, y = rng.randint(45,1550), rng.randint(45,1055)
 c = im.getpixel((x,y))
 if c in [(82,107,76), (69,95,69), (64,91,67), (103,123,82), (97,112,91), (107,117,90)]:
  color = rng.choice(['#73875c','#6b8055','#405941','#819269','#526e4b'])
  if rng.random()<.35:
   d.line((x,y,x+2,y-2,x+4,y), fill=color, width=1)
  else:
   d.point((x,y), fill=color)
 elif c in [(164,148,111),(152,137,102)]:
  if rng.random()<.3: d.rectangle((x,y,x+rng.randrange(1,3),y+1), fill='#b3a17c')
# Small pixel tufts, stones and wildflowers add detail at the playable scale.
for _ in range(4200):
 x,y = rng.randint(90,1500),rng.randint(75,1015)
 c = im.getpixel((x,y))
 if c in [(82,107,76), (69,95,69), (64,91,67), (103,123,82), (97,112,91), (107,117,90)]:
  shade = rng.choice(['#73885c', '#3e5c43', '#81916a', '#667d54'])
  d.line((x,y,x-1,y-3),fill=shade); d.line((x,y,x+2,y-2),fill=shade)
  if rng.random() < .09:
   d.rectangle((x-1,y-4,x,y-3),fill=rng.choice(['#c87d5d','#d7b979','#caa98c']))
# Clumps of grass and small flowers break up open ground near the routes.
for _ in range(1200):
 x,y = rng.randint(90,1500),rng.randint(75,1015)
 c = im.getpixel((x,y))
 if c in [(82,107,76), (69,95,69), (64,91,67), (103,123,82), (97,112,91), (107,117,90)]:
  d.line((x-3,y+1,x-5,y-3),fill='#435e42',width=1)
  d.line((x,y+1,x-1,y-5),fill='#789263',width=1)
  d.line((x+1,y+1,x+4,y-3),fill='#6d8657',width=1)
  if rng.random() < .23:
   d.rectangle((x+3,y-5,x+4,y-4),fill=rng.choice(['#d29173','#dfbb7b','#b76d5f']))
# Water ripples.
for _ in range(420):
 x,y = rng.randrange(w),rng.randrange(h)
 if im.getpixel((x,y)) == (30,65,74):
  d.line((x,y,x+rng.randrange(3,13),y),fill=rng.choice(['#2b5660','#365e63','#28505a']))
im.save(ROOT / 'island_ground.png', optimize=True)
