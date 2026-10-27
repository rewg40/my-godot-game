"""Regenerate original terrain, prop art and the CC0 zombie recolour.
Requires Pillow. Not required to play the game. Run from repository root.
"""
from pathlib import Path
from PIL import Image, ImageDraw
import random

ROOT = Path('assets/environment')
ROOT.mkdir(parents=True, exist_ok=True)
rng = random.Random(2291)
# The terrain is drawn at half the world resolution, then displayed with nearest filtering.
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
# Simple handcrafted, transparent pixel props. All are rendered nearest-neighbour.
def canvas(name, size, painter):
 i=Image.new('RGBA',size,(0,0,0,0)); painter(ImageDraw.Draw(i)); i.save(ROOT/(name+'.png'),optimize=True)

def scrap(d):
 d.polygon([(2,25),(4,16),(11,13),(14,17),(23,12),(29,17),(29,26)], fill='#384952', outline='#1d3037')
 d.rectangle((6,14,13,23),fill='#83968c',outline='#293d3b'); d.rectangle((17,17,27,24),fill='#aa7553',outline='#4d5147')
 d.line((4,26,30,26),fill='#1b3333',width=2)
def bush(d):
 d.ellipse((2,10,29,26),fill='#1f4939'); d.ellipse((5,5,24,22),fill='#467c4f'); d.ellipse((13,7,30,23),fill='#548855')
 for x,y in [(8,13),(16,10),(22,16),(12,21),(26,11)]:d.rectangle((x,y,x+2,y+2),fill='#de7054')
def well(d):
 d.ellipse((3,21,29,29),fill='#243c3d'); d.rectangle((5,14,27,25),fill='#a4a18a',outline='#394941',width=2)
 d.ellipse((6,11,26,19),fill='#485c53');d.ellipse((10,13,22,17),fill='#538d99')
 d.rectangle((7,3,9,14),fill='#6c4d37');d.rectangle((23,3,25,14),fill='#6c4d37');d.polygon([(4,5),(16,0),(28,5),(26,8),(6,8)],fill='#805a3a',outline='#354238')
def fire(d):
 d.ellipse((3,24,29,29),fill='#263d34');d.line((6,25,24,20),fill='#735038',width=4);d.line((9,20,25,25),fill='#a36b46',width=4)
 d.polygon([(9,21),(12,10),(15,14),(18,3),(22,14),(25,21),(19,25),(12,25)],fill='#e0733d');d.polygon([(13,21),(17,12),(20,21),(18,24),(15,24)],fill='#f5c766')
def safe(d):
 d.rectangle((3,6,28,28),fill='#3d5660',outline='#1b3036',width=2);d.rectangle((6,9,25,25),fill='#8b9891',outline='#526760');d.ellipse((11,11,21,21),fill='#405959');d.ellipse((14,14,18,18),fill='#d9cb91')
def cache(d):
 d.rectangle((3,11,28,27),fill='#866443',outline='#283b38',width=2);d.rectangle((4,8,27,15),fill='#ae8755',outline='#4d5845');d.rectangle((13,13,18,19),fill='#d7c47c',outline='#594d38')
def sign(d):
 d.rectangle((14,8,17,29),fill='#5d4838');d.rectangle((2,3,29,15),fill='#8b6745',outline='#344539',width=2);d.line((6,7,24,7),fill='#c7aa72');d.line((6,11,19,11),fill='#c7aa72')
def teddy(d):
 d.ellipse((5,3,12,10),fill='#855a3d');d.ellipse((20,3,27,10),fill='#855a3d');d.ellipse((7,5,25,21),fill='#b17c52',outline='#5b493b');d.ellipse((8,18,24,29),fill='#a96f49',outline='#5b493b');d.point((12,11),fill='#263331');d.point((20,11),fill='#263331');d.rectangle((15,14,17,15),fill='#3f3934')
def boat(d):
 d.polygon([(1,21),(4,30),(28,30),(32,21)],fill='#81543c',outline='#334b43');d.line((4,25,29,25),fill='#c79464');d.rectangle((15,2,17,23),fill='#675140');d.polygon([(17,3),(17,19),(28,18)],fill='#d1c39b',outline='#6b705d')
def lighthouse(d):
 d.rectangle((5,48,27,61),fill='#697270',outline='#34484a');d.polygon([(9,48),(11,15),(21,15),(24,48)],fill='#d9c8a1',outline='#485b57');
 d.rectangle((10,23,22,28),fill='#b8674c');d.rectangle((9,9,23,16),fill='#638b88',outline='#344848');d.rectangle((12,10,20,14),fill='#f7d77d');d.polygon([(7,9),(16,2),(25,9)],fill='#994b42',outline='#394943');d.rectangle((14,40,19,49),fill='#344d4a')
def antenna(d):
 d.line((16,27,16,4),fill='#9ba9a1',width=2);d.line((7,28,16,8,25,28),fill='#526c68',width=2);d.line((10,18,22,18),fill='#a8b4a1');d.ellipse((13,1,19,7),fill='#eabf6b',outline='#526c68')
def plot(d):
 d.rectangle((2,5,29,28),outline='#d1bf79',width=1)
 for x,y in [(2,5),(27,5),(2,26),(27,26)]: d.rectangle((x,y,x+2,y+2),fill='#e0c786')
 d.line((6,16,26,16),fill='#c2b379');d.line((16,8,16,24),fill='#c2b379')
def keycard(d):
 d.rounded_rectangle((4,8,28,24),2,fill='#d5bc76',outline='#435956',width=2);d.rectangle((7,11,12,15),fill='#63928b');d.rectangle((16,12,24,13),fill='#526c68');d.line((7,20,25,20),fill='#526c68')
for name, size, fn in [('scrap',(32,32),scrap),('bush',(32,32),bush),('well',(32,32),well),('fire',(32,32),fire),('safe',(32,32),safe),('cache',(32,32),cache),('sign',(32,32),sign),('teddy',(32,32),teddy),('boat',(32,32),boat),('lighthouse',(32,64),lighthouse),('antenna',(32,32),antenna),('plot',(32,32),plot),('keycard',(32,32),keycard)]: canvas(name,size,fn)
# Zombie: a CC0 Pixel-boy villager recoloured into an infected character.
src=Image.open('assets/sprites/villager_original.png').convert('RGBA')
colors={}
for p in src.getdata():
 if p[3] and p[0] > 150 and p[0] > p[1]*1.13 and p[1] > p[2]*1.1:
  colors[p]=(int(p[0]*.52),int(p[1]*.85),int(p[2]*.65),p[3])
src.putdata([colors.get(p,p) for p in src.getdata()]); src.save('assets/sprites/zombie.png',optimize=True)
