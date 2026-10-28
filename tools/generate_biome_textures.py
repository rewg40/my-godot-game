"""Generate seamless biome ground textures for the 4-sector island shader.

Outputs (512x512, tiling in both axes):
  assets/environment/textures/biome_snow.png         — RGB, snow with drifts
  assets/environment/textures/biome_desert.png       — RGB, rippled sand dunes
  assets/environment/textures/biome_radioactive.png  — RGBA, dark cracked soil,
                                                       alpha channel = glow mask
Requires Pillow + NumPy; run from the repository root. Not required to play.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 512
SEED = 2091  # year of the Zeroing, for reproducibility


def fourier_noise(rng: np.random.Generator, octaves: int = 4,
                  base: int = 3, decay: float = 0.55) -> np.ndarray:
    """Perfectly tileable value noise as a sum of periodic sinusoids."""
    x = np.arange(SIZE, dtype=np.float64) / SIZE
    y = np.arange(SIZE, dtype=np.float64) / SIZE
    xx, yy = np.meshgrid(x, y)
    out = np.zeros((SIZE, SIZE), dtype=np.float64)
    amp, freq = 1.0, base
    for _ in range(octaves):
        for _ in range(3):
            fx = int(rng.integers(1, freq + 1))
            fy = int(rng.integers(1, freq + 1))
            phase = rng.random() * 2.0 * np.pi
            out += amp * np.sin(2.0 * np.pi * (fx * xx + fy * yy) + phase)
        amp *= decay
        freq *= 2
    return out / np.abs(out).max()


def norm(a: np.ndarray) -> np.ndarray:
    lo, hi = a.min(), a.max()
    return (a - lo) / max(hi - lo, 1e-9)


def to_rgb(arr: np.ndarray) -> Image.Image:
    return Image.fromarray((np.clip(arr, 0.0, 1.0) * 255.0).astype(np.uint8))


def make_snow(rng: np.random.Generator) -> Image.Image:
    """Bluish-white snow: soft large drifts, fine powder, sparse sparkle."""
    drifts = norm(fourier_noise(rng, octaves=3, base=2))
    powder = norm(fourier_noise(rng, octaves=5, base=8, decay=0.4))
    bumps = drifts * 0.72 + powder * 0.28
    base = 0.86 + 0.11 * bumps - 0.05 * powder
    r = base * 0.985
    g = base * 0.995
    b = np.clip(base * 1.045, 0.0, 1.0)          # cold blue in the shadows
    img = to_rgb(np.dstack([r, g, b]))
    px = img.load()
    for _ in range(260):                          # glinting ice crystals
        x, y = int(rng.integers(0, SIZE)), int(rng.integers(0, SIZE))
        px[x, y] = (255, 255, 255)
    return img


def make_desert(rng: np.random.Generator) -> Image.Image:
    """Warm dune sand: wind ripples warped by noise, sparse darker grains."""
    warp = fourier_noise(rng, octaves=4, base=3)
    yy = np.arange(SIZE, dtype=np.float64) / SIZE
    ripple = 0.5 + 0.5 * np.sin(2.0 * np.pi * (yy * 26.0 + warp * 1.9))
    ripple = ripple ** 1.6                        # sharp dune crests
    grain = norm(fourier_noise(rng, octaves=5, base=10, decay=0.4))
    patches = norm(fourier_noise(rng, octaves=3, base=2))
    value = 0.62 + 0.26 * ripple + 0.10 * grain - 0.14 * patches
    base = np.dstack([
        value * 1.06,                             # warm tan
        value * 0.90,
        value * 0.64,
    ])
    img = to_rgb(base)
    px = img.load()
    for _ in range(180):                          # scattered pebbles
        x, y = int(rng.integers(0, SIZE)), int(rng.integers(0, SIZE))
        shade = int(rng.integers(120, 165))
        px[x, y] = (shade, int(shade * 0.88), int(shade * 0.66))
    return img


def make_radioactive(rng: np.random.Generator) -> Image.Image:
    """Dark contaminated soil with chartreuse glow cracks (alpha = glow)."""
    soil = norm(fourier_noise(rng, octaves=5, base=4))
    value = 0.16 + 0.20 * soil
    rgb = np.dstack([value * 0.95, value * 1.05, value * 0.80])

    # Draw glow cracks and seepage blobs on a 3x3-tiled canvas so the
    # strokes that leave one edge continue from the opposite one.
    canvas = Image.new('L', (SIZE * 3, SIZE * 3), 0)
    d = ImageDraw.Draw(canvas)
    for _ in range(26):
        x, y = SIZE + int(rng.integers(0, SIZE)), SIZE + int(rng.integers(0, SIZE))
        width = int(rng.integers(2, 6))
        for _ in range(int(rng.integers(24, 64))):
            nx = x + int(rng.integers(-14, 15))
            ny = y + int(rng.integers(-9, 10))
            d.line((x, y, nx, ny), fill=255, width=width)
            d.ellipse((nx - width, ny - width, nx + width, ny + width), fill=200)
            x, y = nx, ny
    for _ in range(34):                           # pooled contamination
        x = SIZE + int(rng.integers(0, SIZE))
        y = SIZE + int(rng.integers(0, SIZE))
        r = int(rng.integers(6, 22))
        d.ellipse((x - r, y - r, x + r, y + r), fill=110)
    glow = canvas.crop((SIZE, SIZE, SIZE * 2, SIZE * 2))
    glow = glow.filter(ImageFilter.GaussianBlur(1.6))
    g = np.asarray(glow, dtype=np.float64) / 255.0

    rad = np.dstack([
        np.clip(rgb[:, :, 0] * (1.0 - g) + 0.62 * g, 0, 1),
        np.clip(rgb[:, :, 1] * (1.0 - g) + 1.00 * g, 0, 1),
        np.clip(rgb[:, :, 2] * (1.0 - g) + 0.28 * g, 0, 1),
    ])
    rgba = np.dstack([rad, g])                    # alpha drives EMISSION
    return Image.fromarray((rgba * 255.0).astype(np.uint8))


def main() -> None:
    out_dir = Path('assets/environment/textures')
    out_dir.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(SEED)
    targets = {
        'biome_snow.png': make_snow(rng),
        'biome_desert.png': make_desert(rng),
        'biome_radioactive.png': make_radioactive(rng),
    }
    for name, img in targets.items():
        path = out_dir / name
        img.save(path, optimize=True)
        print('Wrote', path, img.size, img.mode)


if __name__ == '__main__':
    main()
