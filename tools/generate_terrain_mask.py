"""Create the original island's surface masks for the 3D terrain shader.

The map coordinates match generate_original_art.py and world.gd. Requires
Pillow; run from the repository root. Not required to play the game.
R: paved road / lane paint, G: dirt paths, B: forest floor or sand,
A: island silhouette. The blue channel reserves its upper half for sand. Photographic surface textures are separately credited.
"""
from pathlib import Path
from math import hypot
from PIL import Image, ImageChops, ImageDraw, ImageFilter

W, H = 1600, 1100
shore = [(105,60),(330,23),(720,38),(1115,25),(1455,75),(1530,198),(1555,444),(1536,742),(1514,1010),(1372,1068),(980,1053),(656,1077),(307,1065),(70,1007),(45,795),(55,540),(40,303)]
land = [(121,78),(345,52),(720,65),(1100,53),(1430,99),(1500,222),(1517,445),(1507,736),(1485,987),(1354,1035),(979,1023),(655,1046),(326,1031),(100,977),(79,788),(83,536),(70,310)]

def channel():
    return Image.new('L', (W, H), 0)

# Island silhouette. Sand is encoded separately from dirt so a blurred path
# edge does not accidentally turn into a bright, unrealistic strip of beach.
a = channel()
ImageDraw.Draw(a).polygon(shore, fill=255)
a = a.filter(ImageFilter.GaussianBlur(2))
sand = channel()
sd = ImageDraw.Draw(sand)
sd.polygon(shore, fill=255)
sd.polygon(land, fill=0)
sand = sand.filter(ImageFilter.GaussianBlur(2))
g = channel()
gd = ImageDraw.Draw(g)

# Worn footpaths through the forest and along the shore.
footpaths = [
    [(425,650),(560,618),(715,560),(810,440),(730,240)],
    [(425,650),(365,555),(340,400),(295,215)],
    [(180,975),(220,905),(330,840),(425,650)],
]
for path in footpaths:
    gd.line(path, fill=255, width=36, joint='curve')
g = g.filter(ImageFilter.GaussianBlur(4))

# The main asphalt route connects the village, hotel, airfield and lighthouse.
r = channel()
rd = ImageDraw.Draw(r)
roads = [
    [(180,920),(300,860),(340,775),(425,650)],
    [(425,650),(600,700),(820,730),(1095,700)],
    [(1095,700),(1150,590),(1210,470),(1285,325)],
    [(1095,700),(1230,770),(1320,820),(1375,900)],
]
for path in roads:
    rd.line(path, fill=158, width=48, joint='curve')
rd.rounded_rectangle((980,620,1180,780), radius=7, fill=158)
rd.rounded_rectangle((1150,220,1468,395), radius=5, fill=158)

def dashed(path, dash=16.0, gap=18.0):
    """Draw faded road markings at an even spacing, following the polyline."""
    phase = 0.0
    for (x0,y0),(x1,y1) in zip(path, path[1:]):
        length = hypot(x1-x0, y1-y0)
        dist = 0.0
        while dist < length:
            left = dash + gap - phase
            step = min(left if phase >= dash else dash - phase, length - dist)
            if phase < dash:
                start = (x0+(x1-x0)*dist/length, y0+(y1-y0)*dist/length)
                end = (x0+(x1-x0)*(dist+step)/length, y0+(y1-y0)*(dist+step)/length)
                rd.line((start,end), fill=245, width=2)
            dist += step
            phase = (phase + step) % (dash + gap)
            if phase > dash + gap - 1e-6:
                phase = 0.0

for path in roads:
    dashed(path)
# Airfield centre markings.
for x in range(1180, 1450, 60):
    rd.rectangle((x,301,x+32,304), fill=245)
r = r.filter(ImageFilter.GaussianBlur(1.0))

b = channel()
bd = ImageDraw.Draw(b)
bd.ellipse((300,60,930,510), fill=68)
bd.ellipse((290,115,735,440), fill=76)
b = b.filter(ImageFilter.GaussianBlur(55))
b = ImageChops.lighter(b, sand)

out = Path('assets/environment/terrain_mask.png')
out.parent.mkdir(parents=True, exist_ok=True)
Image.merge('RGBA', (r, g, b, a)).save(out, optimize=True)
print('Wrote', out)
