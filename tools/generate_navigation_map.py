"""Build an offline navigation chart from the island's existing atlases.

No invented terrain: coastline comes from user_island_map, contours from the
height atlas, and paths from the same layout mask used by the 3D shader.
Requires Pillow, NumPy and SciPy. Runtime lake/base/markers are drawn by Godot.
"""
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt, gaussian_filter

base = Path("assets/environment")
old = np.array(Image.open(base / "user_island_map.png").convert("RGB"))
layout = np.asarray(Image.open(base / "user_island_layout.png").convert("RGB"), dtype=np.float32) / 255.0
data = np.array(Image.open(base / "user_island_data.png").convert("RGB"), dtype=np.float32)
height = ((data[:, :, 0] * 256 + data[:, :, 1]) / 65535 * 0.067732 - 0.011) * 150
height = np.asarray(Image.fromarray(height).resize((old.shape[1], old.shape[0]), Image.Resampling.BILINEAR))
land = np.any(old != np.array([31, 67, 71]), axis=2)
coast = distance_transform_edt(land)
water_distance = distance_transform_edt(~land)
h = gaussian_filter(height, 4.5)
gy, gx = np.gradient(h)
shade = np.clip(0.96 - gx * 3.5 - gy * 2.2, 0.65, 1.25)
elevation = np.clip((h + 0.5) / 7.0, 0.0, 1.0)
land_col = np.zeros((*land.shape, 3), dtype=np.float32)
low = np.array([104, 121, 86]); high = np.array([145, 146, 116])
land_col[:] = low[None, None, :] * (1 - elevation[..., None]) + high[None, None, :] * elevation[..., None]
land_col *= shade[..., None]
# Fine contour bands; larger altitude changes become easy to read without
# mistaking the very fine tree geometry for cliffs.
contour_phase = np.abs((h + 0.125) % 1.0 - 0.5)
contour = np.clip((0.035 - contour_phase) / 0.035, 0, 1) * (coast > 4)
land_col *= (1.0 - contour[..., None] * 0.19)
beach = np.clip((11.0 - coast) / 11.0, 0, 1) * 0.76
land_col = land_col * (1 - beach[..., None]) + np.array([172, 159, 122]) * beach[..., None]
# Road/trail are the exact masks applied by island_surface.gdshader.
road = np.clip(np.maximum(layout[:, :, 0], layout[:, :, 1] * 0.8), 0, 1) * 0.9
land_col = land_col * (1 - road[..., None]) + np.array([184, 169, 137]) * road[..., None]
y, x = np.indices(land.shape)
noise = (np.sin(x * 0.19) * np.cos(y * 0.14) + np.sin(x * 0.047 + y * 0.08)) * 1.3
land_col += noise[..., None]
water = np.zeros_like(land_col); water[:] = [37, 69, 74]
shallows = np.clip((14 - water_distance) / 14, 0, 1) * 0.45
water = water * (1 - shallows[..., None]) + np.array([76, 113, 109]) * shallows[..., None]
# Decorative depth contours are strictly in the water.
water_band = (np.abs(water_distance % 34 - 17) < 0.6) & (water_distance > 20)
water[water_band] += 4
image = np.where(land[..., None], land_col, water).clip(0, 255).astype(np.uint8)
Image.fromarray(image).save(base / "user_island_navigation.png", optimize=True)
print("Wrote", base / "user_island_navigation.png")
