"""Create a deterministic dirty concrete tile from the project's CC0 textures.

Requires Pillow and NumPy. The source concrete and brown mud are credited in
assets/models/airport_kit/README.md and docs/ASSET_CREDITS.md.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SIZE = 1024
rng = np.random.default_rng(98121)
base = Image.open(ROOT / "assets/models/airport_kit/textures/weathered_concrete.jpg").convert("RGB").resize((SIZE, SIZE))
mud = Image.open(ROOT / "assets/environment/textures/dirt_diff_1k.jpg").convert("RGB").resize((SIZE, SIZE))


def noise(side: int) -> np.ndarray:
    # Mirrored coarse noise has matching opposite edges when tiled.
    inner = rng.integers(0, 256, (side, side), dtype=np.uint8)
    wrapped = np.pad(inner, ((1, 1), (1, 1)), mode="wrap")
    image = Image.fromarray(wrapped).resize((SIZE + 2 * (SIZE // side),) * 2, Image.Resampling.BICUBIC)
    trim = SIZE // side
    return np.asarray(image.crop((trim, trim, trim + SIZE, trim + SIZE))).astype(np.float32) / 255

clouds = np.clip((noise(12) * .66 + noise(38) * .34 - .39) * 1.8, 0, 1)
# Keep dirt subtle: strongly contrasted small tiles form an obvious repeating
# pattern across a 300-metre apron when viewed from above.
alpha = np.uint8(np.clip(clouds * 52, 0, 55))
mask = Image.fromarray(alpha).filter(ImageFilter.GaussianBlur(1.0))
result = Image.composite(mud, base, mask)
# Fine, broken fissures: short jagged sections rather than a painted grid.
draw = ImageDraw.Draw(result, "RGBA")
for _ in range(26):
    x, y = rng.integers(0, SIZE, 2).tolist()
    length = int(rng.integers(22, 100))
    angle = rng.uniform(0, np.pi * 2)
    points = [(x, y)]
    for j in range(1, 7):
        distance = length * j / 6
        jitter = rng.uniform(-7, 7)
        points.append((int(x + np.cos(angle) * distance - np.sin(angle) * jitter),
                       int(y + np.sin(angle) * distance + np.cos(angle) * jitter)))
    draw.line(points, fill=(34, 32, 27, int(rng.integers(50, 95))), width=int(rng.integers(1, 4)))
path = ROOT / "assets/models/airport_kit/textures/apron_weathered.jpg"
result.save(path, quality=88, optimize=True)
print("Wrote", path.relative_to(ROOT))
