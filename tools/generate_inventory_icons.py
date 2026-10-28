"""Draw offline inventory item icons, using project CC0 wood/rock/metal textures.

The resulting PNGs are transparent and ship with the game; no network, AI
service or runtime rendering is required. Requires Pillow.
"""
from pathlib import Path
import math
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = Path("assets/icons")
OUT.mkdir(parents=True, exist_ok=True)
S = 3
N = 192
random.seed(2291)


def xy(points):
    return [(round(x * S), round(y * S)) for x, y in points]


def polygon(mask, points, fill=255):
    ImageDraw.Draw(mask).polygon(xy(points), fill=fill)


def ellipse(mask, box, fill=255):
    ImageDraw.Draw(mask).ellipse(tuple(round(x * S) for x in box), fill=fill)


def layer_texture(canvas, mask, texture, tint=(1.0, 1.0, 1.0)):
    img = Image.open(texture).convert("RGB").resize((N * S, N * S), Image.Resampling.LANCZOS)
    if tint != (1.0, 1.0, 1.0):
        r, g, b = img.split()
        img = Image.merge("RGB", (r.point(lambda v: min(255, int(v * tint[0]))), g.point(lambda v: min(255, int(v * tint[1]))), b.point(lambda v: min(255, int(v * tint[2])))))
    canvas.paste(img, (0, 0), mask)


def new_canvas():
    return Image.new("RGBA", (N * S, N * S), (0, 0, 0, 0))


def draw_shadow(canvas, box=(23, 149, 171, 172)):
    sh = Image.new("RGBA", canvas.size)
    ImageDraw.Draw(sh).ellipse(tuple(round(v * S) for v in box), fill=(0, 0, 0, 110))
    canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(6 * S)))


def save(canvas, name):
    canvas.resize((N, N), Image.Resampling.LANCZOS).save(OUT / (name + ".png"), optimize=True)


def stroke(draw, points, color, width=2):
    draw.line(xy(points), fill=color, width=width * S, joint="curve")

wood = "assets/environment/textures/planks_diff_1k.jpg"
rock = "assets/environment/textures/rock_diff_1k.jpg"
metal = "assets/environment/textures/metal_diff_1k.jpg"

# Stacked timber, with cut rings at the ends.
c = new_canvas(); draw_shadow(c); mask = Image.new("L", c.size)
for dx, dy in [(0, 27), (13, 1), (-12, -19)]:
    polygon(mask, [(33+dx, 91+dy), (128+dx, 48+dy), (151+dx, 59+dy), (151+dx, 82+dy), (57+dx, 126+dy), (33+dx, 114+dy)])
layer_texture(c, mask, wood, (0.85, 0.72, 0.59)); d = ImageDraw.Draw(c)
for dx, dy in [(0, 27), (13, 1), (-12, -19)]:
    b = (30+dx, 89+dy, 62+dx, 123+dy); d.ellipse(tuple(v*S for v in b), fill=(159,120,76,255), outline=(63,47,32,255), width=2*S)
    for inset in (6, 11):
        bb = (b[0]+inset,b[1]+inset,b[2]-inset,b[3]-inset); d.ellipse(tuple(v*S for v in bb), outline=(100,72,45,220), width=S)
    stroke(d, [(61+dx, 96+dy),(151+dx, 56+dy)], (75,55,36,220), 2)
save(c, "wood")

# Irregular textured stone.
c = new_canvas(); draw_shadow(c); m = Image.new("L", c.size)
pts=[(28,116),(36,78),(67,46),(103,38),(142,62),(162,104),(149,141),(110,158),(61,150)]
polygon(m, pts); layer_texture(c,m,rock,(0.91,0.95,0.91)); d=ImageDraw.Draw(c)
stroke(d, pts+[pts[0]], (49,56,51,230), 3); stroke(d,[(67,46),(81,79),(61,109),(28,116)],(105,116,107,150),2); stroke(d,[(81,79),(123,84),(149,141)],(65,75,69,150),2); save(c,"stone")

# Bent metal plates and bolts.
c=new_canvas();draw_shadow(c);m=Image.new("L",c.size)
polygon(m,[(35,82),(108,39),(150,65),(150,98),(77,143),(35,117)]); polygon(m,[(63,118),(132,79),(161,96),(158,131),(91,163),(63,150)])
layer_texture(c,m,metal,(0.88,0.93,0.91));d=ImageDraw.Draw(c)
for pts in [[(35,82),(108,39),(150,65),(150,98),(77,143),(35,117),(35,82)],[(63,118),(132,79),(161,96),(158,131),(91,163),(63,150),(63,118)]]:stroke(d,pts,(54,60,58,230),3)
for x,y in [(52,91),(126,64),(80,128),(142,101)]:d.ellipse(((x-4)*S,(y-4)*S,(x+4)*S,(y+4)*S),fill=(32,36,34),outline=(170,170,150),width=S)
save(c,"iron")

# Folded canvas.
c=new_canvas();draw_shadow(c);d=ImageDraw.Draw(c)
d.polygon(xy([(31,79),(107,42),(161,69),(160,123),(84,160),(31,132)]),fill=(158,153,129),outline=(75,72,60),width=3*S)
d.polygon(xy([(31,79),(107,42),(161,69),(84,106)]),fill=(207,201,176),outline=(97,91,74),width=2*S)
d.polygon(xy([(84,106),(161,69),(160,123),(84,160)]),fill=(176,171,145),outline=(97,91,74),width=2*S)
for i in range(9):stroke(d,[(46+i*6,77-i*3),(98+i*6,103-i*3)],(229,220,194,70),1)
save(c,"cloth")

# Herbs, individual leaves and stems.
c=new_canvas();draw_shadow(c);d=ImageDraw.Draw(c)
for tip in [(47,48),(73,31),(115,31),(150,55),(151,94),(51,100)]:
    stroke(d,[(96,151),tip],(66,88,41),4)
    mx=(96+tip[0])/2;my=(151+tip[1])/2
    d.ellipse(((mx-24)*S,(my-15)*S,(mx+24)*S,(my+15)*S),fill=(74,113,52),outline=(39,69,35),width=2*S)
    stroke(d,[(mx-14,my),(mx+16,my)],(141,166,94,210),1)
save(c,"herbs")

# Berries in a small tin.
c=new_canvas();draw_shadow(c);d=ImageDraw.Draw(c)
d.polygon(xy([(34,106),(155,106),(145,149),(46,149)]),fill=(114,119,104),outline=(47,56,50),width=3*S)
for x,y,r in [(53,96,18),(82,79,21),(112,91,19),(139,83,17),(67,113,19),(105,116,22),(137,111,19)]:
    d.ellipse(((x-r)*S,(y-r)*S,(x+r)*S,(y+r)*S),fill=(139,39,37),outline=(72,29,27),width=2*S)
    d.ellipse(((x-r//2)*S,(y-r//2)*S,(x-r//5)*S,(y-r//5)*S),fill=(216,117,99,190))
save(c,"food")

# Refillable water bottle.
c=new_canvas();draw_shadow(c);d=ImageDraw.Draw(c)
d.polygon(xy([(72,50),(75,35),(116,35),(119,50),(134,66),(138,148),(127,160),(64,160),(54,149),(58,66)]),fill=(81,142,153,240),outline=(37,70,76,255),width=4*S)
d.rounded_rectangle((74*S,24*S,116*S,40*S),radius=3*S,fill=(76,84,77),outline=(36,42,39),width=2*S)
d.polygon(xy([(62,107),(133,107),(132,145),(124,153),(68,153),(61,145)]),fill=(62,126,151,230))
d.rounded_rectangle((63*S,75*S,129*S,104*S),radius=3*S,fill=(200,213,193,220));stroke(d,[(70,64),(70,144)],(200,236,229,150),3);save(c,"water")

# Medical bandage roll.
c=new_canvas();draw_shadow(c);d=ImageDraw.Draw(c)
d.rounded_rectangle((42*S,66*S,143*S,135*S),radius=22*S,fill=(207,202,183),outline=(84,88,76),width=3*S)
d.ellipse((112*S,66*S,156*S,135*S),fill=(235,231,210),outline=(93,96,84),width=3*S)
d.ellipse((123*S,82*S,145*S,119*S),fill=(175,174,156),outline=(113,112,99),width=2*S)
d.rectangle((73*S,75*S,98*S,126*S),fill=(239,232,211));d.rectangle((68*S,91*S,103*S,109*S),fill=(173,56,47));d.rectangle((77*S,82*S,94*S,118*S),fill=(173,56,47));save(c,"bandage")

# A dark, weathered bat.
c=new_canvas();draw_shadow(c);d=ImageDraw.Draw(c)
d.polygon(xy([(44,142),(52,149),(122,83),(145,56),(139,43),(126,41),(105,61)]),fill=(121,84,55),outline=(48,37,28),width=3*S)
for k in range(4):stroke(d,[(48+k*3,137+k*3),(56+k*3,145+k*3)],(215,204,171),2)
save(c,"club")

# Spear and stone axe.
c=new_canvas();draw_shadow(c);d=ImageDraw.Draw(c);stroke(d,[(44,155),(143,45)],(100,70,43),8);stroke(d,[(45,155),(144,45)],(178,139,88),3);d.polygon(xy([(131,49),(162,22),(151,61),(141,72)]),fill=(148,153,143),outline=(58,65,60),width=3*S);save(c,"spear")
c=new_canvas();draw_shadow(c);d=ImageDraw.Draw(c);stroke(d,[(63,157),(122,48)],(99,71,46),9);d.polygon(xy([(104,48),(137,34),(154,47),(140,80),(114,87),(99,69)]),fill=(130,138,129),outline=(51,58,52),width=3*S);stroke(d,[(109,76),(130,84)],(205,194,161),4);save(c,"axe")

# A few quest objects use the same tactile icon language.
c=new_canvas();draw_shadow(c);d=ImageDraw.Draw(c);d.rounded_rectangle((38*S,57*S,155*S,135*S),radius=8*S,fill=(170,184,166),outline=(62,81,75),width=3*S);d.rectangle((48*S,70*S,79*S,120*S),fill=(64,124,120));d.rectangle((94*S,76*S,141*S,83*S),fill=(79,104,93));d.rectangle((94*S,91*S,132*S,97*S),fill=(79,104,93));save(c,"keycard")
c=new_canvas();draw_shadow(c);d=ImageDraw.Draw(c);d.rounded_rectangle((49*S,48*S,143*S,142*S),radius=5*S,fill=(53,102,82),outline=(33,55,43),width=3*S);d.rectangle((76*S,73*S,116*S,113*S),fill=(39,47,41),outline=(182,169,112),width=2*S)
for x in range(59,139,13):stroke(d,[(x,40),(x,48)],(189,170,108),4);stroke(d,[(x,142),(x,150)],(189,170,108),4)
save(c,"chip")
c=new_canvas();draw_shadow(c);d=ImageDraw.Draw(c)
for r in [50,42,34,26,18]:d.ellipse(((96-r)*S,(98-r)*S,(96+r)*S,(98+r)*S),outline=(173,105,57),width=5*S)
save(c,"coil")
c=new_canvas();draw_shadow(c);d=ImageDraw.Draw(c);d.rounded_rectangle((56*S,50*S,137*S,145*S),radius=8*S,fill=(68,102,79),outline=(31,52,39),width=4*S);d.rectangle((71*S,38*S,122*S,53*S),fill=(93,105,76));d.rectangle((70*S,70*S,123*S,112*S),fill=(142,180,117));stroke(d,[(96,75),(86,96),(101,96),(92,108)],(236,228,155),5);save(c,"cell")
c=new_canvas();draw_shadow(c);d=ImageDraw.Draw(c);d.polygon(xy([(95,34),(140,53),(150,106),(117,151),(64,147),(42,103),(57,54)]),fill=(98,143,153),outline=(45,69,77),width=4*S);stroke(d,[(60,56),(100,71),(133,53)],(185,217,207),3);stroke(d,[(100,71),(89,137)],(52,81,89),3);save(c,"fragment")
print("Wrote", len(list(OUT.glob('*.png'))), "inventory icons")
