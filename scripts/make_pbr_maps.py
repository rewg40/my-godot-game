#!/usr/bin/env python3
"""Деривация PBR-карт (normal + roughness) из albedo-текстур.

Использование:
    python3 scripts/make_pbr_maps.py assets/textures/albedo assets/textures

Для каждого файла <name>.png из каталога albedo создаются:
    <out>/normal/<name>_normal.png       нормаль из градиента яркости (Sobel, wrap)
    <out>/roughness/<name>_roughness.png шероховатость из инвертированной яркости

Плюс печатает метрику шва (разница противоположных краёв тайла):
чем меньше seam_err, тем лучше текстура тайлится без стыков.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

NORMAL_STRENGTH = 2.0
ROUGH_MIN, ROUGH_MAX = 0.60, 0.95


def luminance(rgb: np.ndarray) -> np.ndarray:
    return rgb @ np.array([0.2126, 0.7152, 0.0722])


def make_normal(lum: np.ndarray, strength: float) -> np.ndarray:
    dx = (np.roll(lum, -1, axis=1) - np.roll(lum, 1, axis=1)) * strength
    dy = (np.roll(lum, -1, axis=0) - np.roll(lum, 1, axis=0)) * strength
    nz = np.ones_like(lum)
    length = np.sqrt(dx * dx + dy * dy + nz * nz)
    nx, ny, nzn = -dx / length, -dy / length, nz / length
    return np.stack([nx * 0.5 + 0.5, ny * 0.5 + 0.5, nzn * 0.5 + 0.5], axis=-1)


def make_roughness(lum: np.ndarray) -> np.ndarray:
    r = ROUGH_MIN + (ROUGH_MAX - ROUGH_MIN) * (1.0 - lum)
    return np.clip(r, 0.0, 1.0)


def seam_error(rgb: np.ndarray) -> float:
    lr = np.abs(rgb[:, 0] - rgb[:, -1]).mean()
    tb = np.abs(rgb[0, :] - rgb[-1, :]).mean()
    return float((lr + tb) / 2.0)


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 1
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    (out / "normal").mkdir(parents=True, exist_ok=True)
    (out / "roughness").mkdir(parents=True, exist_ok=True)

    for path in sorted(src.glob("*.png")):
        img = Image.open(path).convert("RGB")
        rgb = np.asarray(img, dtype=np.float64) / 255.0
        lum = luminance(rgb)
        normal = make_normal(lum, NORMAL_STRENGTH)
        rough = make_roughness(lum)
        Image.fromarray((normal * 255).astype(np.uint8)).save(
            out / "normal" / f"{path.stem}_normal.png")
        Image.fromarray((np.stack([rough] * 3, axis=-1) * 255).astype(np.uint8)).save(
            out / "roughness" / f"{path.stem}_roughness.png")
        print(f"{path.name}: seam_err={seam_error(rgb):.4f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
