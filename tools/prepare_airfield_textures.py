#!/usr/bin/env python3
"""Prepare compact, reusable PBR base-color textures for the airfield kit.

The photographic inputs already belong to this project (see docs/ASSET_CREDITS.md).
This is offline and deterministic. Pillow and NumPy are only needed to regenerate
these textures; Blender can build the models from the checked-in images directly.
"""
from pathlib import Path
from io import BytesIO
import json
import struct
import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/environment/textures"
OUT = ROOT / "assets/models/airport_kit/textures"
OUT.mkdir(parents=True, exist_ok=True)


def load(name, size=1024):
    return Image.open(SRC / name).convert("RGB").resize((size, size), Image.Resampling.LANCZOS)


def save_jpeg(image, name):
    image.save(OUT / name, "JPEG", quality=87, optimize=True, progressive=True)


def make_corrugated():
    source = np.asarray(load("metal_diff_1k.jpg"), dtype=np.float32)
    lum = source.mean(axis=2, keepdims=True)
    # Cooler galvanized paint, with the photograph revealing random rust below it.
    # A mask based on the source avoids a uniform, all-brown dotted roof.
    rust = np.clip((source[:, :, 0] - source[:, :, 2] - 16) / 95.0, 0, .78)[:, :, None]
    painted = np.array([157, 166, 164], dtype=np.float32) + (lum - 168) * .22
    patina = source * np.array([.79, .70, .62], dtype=np.float32)
    color = painted * (1-rust) + patina * rust
    x = np.arange(1024, dtype=np.float32)[None, :]
    rib = 0.88 + 0.12 * np.cos(2 * np.pi * x / 32.0)
    color *= rib[:, :, None]
    im = Image.fromarray(np.uint8(np.clip(color, 0, 255)))
    draw = ImageDraw.Draw(im, "RGBA")
    rng = np.random.default_rng(7301)
    # Subtle overlaps, dirty water streaks and fasteners read as metal sheets.
    for y in (3, 512):
        draw.line((0, y, 1024, y), fill=(45, 45, 42, 75), width=3)
        draw.line((0, y+4, 1024, y+4), fill=(218, 222, 215, 35), width=2)
    for _ in range(110):
        x = int(rng.integers(0, 1024))
        y = int(rng.integers(0, 900))
        length = int(rng.integers(14, 140))
        draw.line((x, y, x + int(rng.integers(-2, 3)), y + length), fill=(84, 46, 30, int(rng.integers(18, 54))), width=int(rng.integers(1, 4)))
    for x in range(16, 1024, 64):
        for y in (10, 250, 514, 762):
            draw.ellipse((x - 1, y - 1, x + 1, y + 1), fill=(29, 32, 30, 110))
    save_jpeg(im, "corrugated_rust.jpg")


def make_wall_and_paint():
    rng = np.random.default_rng(5531)
    wall = ImageEnhance.Brightness(load("concrete_diff_1k.jpg")).enhance(1.16)
    wall = ImageEnhance.Color(wall).enhance(.5)
    draw = ImageDraw.Draw(wall, "RGBA")
    # Weathered vertical deposits and fine cracks; the original CC0 photograph
    # supplies the underlying material variation and concrete surface details.
    for _ in range(160):
        x = int(rng.integers(0, 1024)); y = int(rng.integers(0, 950))
        length = int(rng.integers(5, 150)); width = int(rng.integers(1, 6))
        draw.line((x,y,x+int(rng.integers(-4,5)),y+length), fill=(57,54,47,int(rng.integers(8,35))),width=width)
    for _ in range(14):
        x = int(rng.integers(0,1024)); y = int(rng.integers(0,1024))
        points=[(x,y)]
        for i in range(int(rng.integers(3,7))):
            x += int(rng.integers(-16,17)); y += int(rng.integers(12,40)); points.append((x,y))
        draw.line(points, fill=(55,52,47,55), width=1)
    save_jpeg(wall, "weathered_concrete.jpg")
    rust_src = np.asarray(load("metal_diff_1k.jpg", 512), dtype=np.float32)
    rust_mask = np.clip((rust_src[:,:,0]-rust_src[:,:,2]-30)/160,0,.40)[:,:,None]
    noise = (rust_src.mean(axis=2,keepdims=True)-170)*.12
    for name,base in (("paint_olive.jpg",[66,82,62]),("paint_red.jpg",[119,59,49]),("paint_sand.jpg",[128,121,103])):
        surface=np.array(base,dtype=np.float32)+noise
        patches=rust_src*np.array([.70,.50,.42],dtype=np.float32)
        result=surface*(1-rust_mask)+patches*rust_mask
        save_jpeg(Image.fromarray(np.uint8(np.clip(result,0,255))),name)



def make_spruce_branch():
    """Crop one transparent twig from the project's CC0 Poly Haven pine atlas."""
    data = (ROOT / "assets/models/nature_real/pine.glb").read_bytes()
    json_size, tag = struct.unpack_from("<I4s", data, 12)
    if data[:4] != b"glTF" or tag != b"JSON":
        raise ValueError("The source pine is not a GLB")
    doc = json.loads(data[20:20+json_size])
    binary_start = 20+json_size+8
    img = next(image for image in doc["images"] if "twig_diff" in image["name"])
    view = doc["bufferViews"][img["bufferView"]]
    start = binary_start + view.get("byteOffset", 0)
    raw = data[start:start+view["byteLength"]]
    atlas = Image.open(BytesIO(raw)).convert("RGBA")
    # Source atlas is 512 square; this rectangle contains a single needle twig.
    crop = atlas.crop((8, 8, 110, 180))
    crop.save(OUT / "spruce_branch.png", optimize=True)


def make_chainlink():
    size = 512
    scale = 2
    canvas = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    step = 128 * scale
    for shift in range(-size * 3 * scale, size * 3 * scale, step):
        draw.line((shift, 0, shift + size * scale, size * scale), fill=(105, 109, 102, 215), width=5)
        draw.line((shift, size * scale, shift + size * scale, 0), fill=(105, 109, 102, 215), width=5)
    canvas = canvas.resize((size, size), Image.Resampling.LANCZOS)
    canvas.save(OUT / "chainlink.png", optimize=True)


def main():
    make_corrugated()
    make_chainlink()
    make_spruce_branch()
    make_wall_and_paint()
    save_jpeg(ImageEnhance.Color(load("concrete_diff_1k.jpg")).enhance(0.75), "concrete.jpg")
    save_jpeg(ImageEnhance.Color(load("planks_diff_1k.jpg")).enhance(0.85), "planks.jpg")
    save_jpeg(load("metal_diff_1k.jpg"), "rusted_metal.jpg")
    save_jpeg(ImageEnhance.Contrast(load("asphalt.jpg")).enhance(1.1), "cracked_asphalt.jpg")
    print("Prepared", len(list(OUT.iterdir())), "textures in", OUT)


if __name__ == "__main__":
    main()
