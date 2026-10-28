"""Render a top-down preview of the 4-biome island split.

Reproduces the island_surface.gdshader biome weights (same hash12/fbm border
noise) and samples the generated biome textures, so the picture matches what
the game shows from above. Run from the repository root:
    python3 tools/generate_biome_preview.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

MAP_W, MAP_H = 1600, 1100          # terrain_mask.png space, 1 px = 0.16 m
M_PER_PX = 256.0 / 1600.0
ISLAND = 256.0                     # island_size passed to the shader
BIOME_EDGE, BIOME_NOISE = 16.0, 10.0
TEX = 512

# world.gd landmarks in map pixels (world px * 0.5)
MARKS = {
    "Спавн": (180, 915),
    "Лодка": (190, 975),
    "Отель «Аврора»": (1075, 720),
    "Маяк": (1375, 900),
    "Аэродром": (1425, 250),
}


def fract(a: np.ndarray) -> np.ndarray:
    return a - np.floor(a)


def hash12(px: np.ndarray, py: np.ndarray) -> np.ndarray:
    """Exact port of the shader's hash12(vec2)."""
    p3x = fract(px * 0.1031)
    p3y = fract(py * 0.1031)
    p3z = fract(px * 0.1031)              # vec3(p.xyx) → (x, y, x)
    d = p3x * (p3y + 33.33) + p3y * (p3z + 33.33) + p3z * (p3x + 33.33)
    p3x, p3y, p3z = p3x + d, p3y + d, p3z + d
    return fract((p3x + p3y) * p3z)


def vnoise(px: np.ndarray, py: np.ndarray) -> np.ndarray:
    ix, iy = np.floor(px), np.floor(py)
    fx, fy = px - ix, py - iy
    ux = fx * fx * (3.0 - 2.0 * fx)
    uy = fy * fy * (3.0 - 2.0 * fy)
    a = hash12(ix, iy)
    b = hash12(ix + 1.0, iy)
    c = hash12(ix, iy + 1.0)
    d = hash12(ix + 1.0, iy + 1.0)
    return (a + (b - a) * ux) * (1.0 - uy) + (c + (d - c) * ux) * uy


def fbm(px: np.ndarray, py: np.ndarray) -> np.ndarray:
    v = np.zeros_like(px)
    amp = 0.5
    for _ in range(4):
        v += amp * vnoise(px, py)
        px, py = px * 2.03 + 17.1, py * 2.03 + 9.7
        amp *= 0.5
    return v


def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def sample(tex: Image.Image, scale: float, mx: np.ndarray, my: np.ndarray) -> np.ndarray:
    """Tile a texture at `scale` texels per metre (nearest)."""
    idx_x = np.mod((mx * scale).astype(np.int64), TEX)
    idx_y = np.mod((my * scale).astype(np.int64), TEX)
    arr = np.asarray(tex.convert('RGBA'), dtype=np.float64)
    return arr[idx_y, idx_x]           # [H, W, 4]


def main() -> None:
    root = Path('.')
    mask = np.asarray(Image.open('assets/environment/terrain_mask.png').convert('RGBA'),
                      dtype=np.float64) / 255.0
    snow = Image.open('assets/environment/textures/biome_snow.png')
    desert = Image.open('assets/environment/textures/biome_desert.png')
    rad = Image.open('assets/environment/textures/biome_radioactive.png')
    grass = Image.open('assets/environment/textures/grass_short.jpg')

    yy, xx = np.mgrid[0:MAP_H, 0:MAP_W].astype(np.float64)
    mx = xx * M_PER_PX                  # metres, matches island_position.xz
    my = yy * M_PER_PX

    qx = mx - ISLAND * 0.5
    qy = my - ISLAND * 0.5
    qx += (fbm(mx * 0.02, my * 0.02) - 0.47) * 2.0 * BIOME_NOISE \
          + (vnoise(mx * 0.07, my * 0.07) - 0.5) * 12.0
    qy += (fbm(mx * 0.02 + 31.7, my * 0.02 + 11.3) - 0.47) * 2.0 * BIOME_NOISE \
          + (vnoise(mx * 0.07 + 19.3, my * 0.07 + 5.1) - 0.5) * 12.0
    half = BIOME_EDGE * 0.5
    west = smoothstep(half, -half, qx)
    east = 1.0 - west
    north = smoothstep(half, -half, qy)
    south = 1.0 - north
    w_grass, w_snow = west * south, west * north
    w_rad, w_desert = east * north, east * south

    def mixed(top: Image.Image, bottom: Image.Image, s_top: float, s_bot: float, k: float):
        return (sample(top, s_top, mx, my)[:, :, :3] * k
                + sample(bottom, s_bot, mx, my)[:, :, :3] * (1.0 - k))

    grass_c = mixed(grass, grass, 0.5, 0.8, 0.72) * 0.93
    snow_c = mixed(snow, snow, 0.55, 0.21, 0.65)
    desert_c = mixed(desert, desert, 0.7, 0.23, 0.70)
    rad_c = mixed(rad, rad, 0.75, 0.3, 0.70)
    glow = sample(rad, 0.75, mx, my)[:, :, 3:4] / 255.0
    rad_c = rad_c * (1.0 - glow * 0.55) + np.array([0.62, 1.0, 0.28]) * glow * 0.55

    color = (grass_c * w_grass[..., None] + snow_c * w_snow[..., None]
             + desert_c * w_desert[..., None] + rad_c * w_rad[..., None])

    # Roads and footpaths from the layout mask stay visible in every biome.
    road = np.clip(mask[:, :, 0] * 3.0, 0, 1) * mask[:, :, 3]
    trail = np.clip(mask[:, :, 1] * 2.5, 0, 1) * mask[:, :, 3]
    color = color * (1.0 - road[..., None] * 0.55) + np.array([72.0, 74.0, 72.0]) * road[..., None] * 0.55
    color = color * (1.0 - trail[..., None] * 0.45) + np.array([104.0, 88.0, 64.0]) * trail[..., None] * 0.45

    sea = np.array([26.0, 42.0, 48.0])
    color = sea + (color - sea) * mask[:, :, 3, None]

    img = Image.fromarray(np.clip(color, 0, 255).astype(np.uint8))
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 26)
    except OSError:
        font = ImageFont.load_default()
    for name, (px, py) in MARKS.items():
        draw.ellipse((px - 6, py - 6, px + 6, py + 6), outline=(255, 255, 255), width=3)
        tx, ty = px + 12, py - 30
        draw.text((tx + 1, ty + 1), name, fill=(0, 0, 0), font=font)
        draw.text((tx, ty), name, fill=(255, 255, 255), font=font)
    labels = [
        ((300, 140), 'СЕКТОР: СНЕГ'),
        ((1140, 140), 'СЕКТОР: РАДИОАКТИВНЫЙ'),
        ((300, 1030), 'СЕКТОР: ТРАВА'),
        ((1230, 1030), 'СЕКТОР: ПУСТЫНЯ'),
    ]
    for (tx, ty), name in labels:
        draw.text((tx + 1, ty + 1), name, fill=(0, 0, 0), font=font)
        draw.text((tx, ty), name, fill=(255, 255, 255), font=font)

    out = Path('docs/biome_preview.png')
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out, optimize=True)
    copy = Path('/home/z/my-project/download/осколки_биомы_превью.png')
    copy.parent.mkdir(parents=True, exist_ok=True)
    img.save(copy, optimize=True)
    print('Wrote', out, 'and', copy)


if __name__ == '__main__':
    main()
