"""Deterministic 4 km nature-only island height field and forest positions.

Coordinates here are Blender coordinates: X/Y are horizontal and Z is up.
The shoreline fits approximately 4000 x 4000 metres. The 4400 m terrain grid
includes a 200 m submerged shelf around it; the preview ocean is separate.
Requires NumPy, SciPy and Pillow. No gameplay state is touched.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt, gaussian_filter, map_coordinates

SEED = 174913
SIZE = 4400.0
GRID = 551
STEP = SIZE / (GRID - 1)
LAKE_LEVEL = 20.0


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def outline():
    # A continuous organic outline, normalized to a full 4 km in each axis.
    theta = np.linspace(0, 2 * np.pi, 2048, endpoint=False)
    radius = (1.0 + .085 * np.sin(3 * theta + .65) + .072 * np.sin(5 * theta - 1.15)
              + .030 * np.cos(8 * theta + .2) + .015 * np.sin(13 * theta + .7))
    # Recesses form broad natural bays rather than a perfect round island.
    for angle, width, depth in [(0.22, .18, .13), (2.95, .16, .12), (4.75, .18, .17), (5.65, .12, .10)]:
        delta = np.arctan2(np.sin(theta - angle), np.cos(theta - angle))
        radius -= depth * np.exp(-.5 * (delta / width) ** 2)
    x, y = radius * np.cos(theta), radius * np.sin(theta)
    x = (x - (x.max() + x.min()) / 2) * 4000.0 / np.ptp(x)
    y = (y - (y.max() + y.min()) / 2) * 4000.0 / np.ptp(y)
    return np.column_stack([x, y])


def lake_outline():
    # One large irregular lake with two lobes, inspired by the concept image.
    theta = np.linspace(0, 2 * np.pi, 720, endpoint=False)
    radius = 1 + .14 * np.sin(3 * theta + .7) + .09 * np.cos(5 * theta + .1)
    # A shallow inlet and a small peninsula break up the shoreline.
    delta = np.arctan2(np.sin(theta - 4.6), np.cos(theta - 4.6))
    radius -= .26 * np.exp(-.5 * (delta / .18) ** 2)
    x = -75.0 + 680.0 * radius * np.cos(theta)
    y = 230.0 + 430.0 * radius * np.sin(theta)
    return np.column_stack([x, y])


def raster_polygon(coords):
    pixels = np.rint((coords + SIZE / 2) / STEP).astype(int)
    canvas = Image.new("1", (GRID, GRID), 0)
    ImageDraw.Draw(canvas).polygon([tuple(v) for v in pixels], fill=1)
    return np.array(canvas, dtype=bool)


def gauss(x, y, cx, cy, sx, sy):
    return np.exp(-.5 * (((x - cx) / sx) ** 2 + ((y - cy) / sy) ** 2))


def sample(array, x, y):
    # Terrain and vegetation are sampled with the same bilinear interpolation.
    return map_coordinates(array, [(np.asarray(y) + SIZE / 2) / STEP,
                                   (np.asarray(x) + SIZE / 2) / STEP],
                           order=1, mode="nearest")


def build():
    rng = np.random.default_rng(SEED)
    coords = np.linspace(-SIZE / 2, SIZE / 2, GRID, dtype=np.float32)
    x, y = np.meshgrid(coords, coords)
    land = raster_polygon(outline())
    lake = raster_polygon(lake_outline()) & land
    land_d = distance_transform_edt(land).astype(np.float32) * STEP
    sea_d = distance_transform_edt(~land).astype(np.float32) * STEP
    lake_in = distance_transform_edt(lake).astype(np.float32) * STEP
    lake_out = distance_transform_edt(~lake).astype(np.float32) * STEP
    noise = gaussian_filter(rng.standard_normal((GRID, GRID)).astype(np.float32), 22)
    noise /= max(float(noise.std()), 1e-6)
    fine = gaussian_filter(rng.standard_normal((GRID, GRID)).astype(np.float32), 5)
    fine /= max(float(fine.std()), 1e-6)
    hills = (115 * gauss(x, y, 1050, -1030, 650, 520)
             + 82 * gauss(x, y, -1130, 1160, 650, 460)
             + 72 * gauss(x, y, 700, 1360, 800, 440)
             + 52 * gauss(x, y, -1390, -760, 460, 600)
             + 27 * gauss(x, y, -600, -100, 900, 650))
    land_height = (2.0 + 13 * smoothstep(0, 170, land_d)
                   + (hills + 4.5 * noise + 1.0 * fine) * smoothstep(30, 300, land_d))
    # Flatten a gradual natural lake basin while retaining hills further away.
    lake_rim = LAKE_LEVEL + .35 + np.minimum(lake_out, 140) * .05
    blend = 1.0 - smoothstep(35, 220, lake_out)
    land_height = land_height * (1 - blend) + lake_rim * blend
    land_height = np.where(lake, LAKE_LEVEL - np.minimum(13.0, lake_in * .055), land_height)
    height = np.where(land, land_height, -1.0 - np.minimum(sea_d * .06, 28.0)).astype(np.float32)
    # Blend a few broad meadows into the land so they really are flat enough
    # for future building, with no artificial foundation or placed objects.
    clearings = [(-1070, -790, 190), (960, 720, 185), (950, -1020, 210), (-1180, 860, 105)]
    for cx, cy, radius in clearings:
        centre_height = float(sample(height, np.array([cx]), np.array([cy]))[0])
        distance = np.hypot(x - cx, y - cy)
        theta = np.arctan2(y - cy, x - cx)
        organic_edge = distance + radius * (.10 * np.sin(3 * theta + .8) + .06 * np.cos(5 * theta - .4))
        weight = 1.0 - smoothstep(radius * .65, radius * 1.25, organic_edge)
        height = (height * (1.0 - weight) + centre_height * weight).astype(np.float32)

    # Main forest covers the upper left / upper middle, plus smaller groups.
    forest = (1.10 * gauss(x, y, -850, 800, 720, 490)
              + .80 * gauss(x, y, -250, 1350, 600, 310)
              + .58 * gauss(x, y, -1300, 50, 330, 480)
              + .38 * gauss(x, y, 850, 1100, 420, 300)
              + .18 * gauss(x, y, 1180, -500, 360, 430)
              + .16 * gauss(x, y, -650, -1150, 550, 320))
    patch = gaussian_filter(rng.random((GRID, GRID)).astype(np.float32), 6)
    patch = (patch - patch.mean()) / max(float(patch.std()), 1e-6)
    forest = np.clip(forest * (.80 + .22 * np.clip(patch, -1, 1)), 0, 1)
    forest *= (land_d > 30) & (lake_out > 35)
    # Clear spaces remain unobstructed for later base construction; nothing is built here.
    for cx, cy, radius in clearings:
        distance = np.hypot(x - cx, y - cy)
        theta = np.arctan2(y - cy, x - cx)
        # Preserve a clear core but break up the outer edge like a natural glade.
        outer = radius + 75 + radius * (.14 * np.sin(3 * theta + .8) + .08 * np.cos(5 * theta - .4))
        forest *= smoothstep(radius * .85, outer, distance)
    return {"x": x, "y": y, "height": height, "land": land, "lake": lake,
            "land_d": land_d, "lake_out": lake_out, "forest": forest.astype(np.float32),
            "clearings": clearings}


def forest_positions(data):
    rng = np.random.default_rng(SEED + 1)
    # A jittered grid makes the main forest dense while retaining clearings.
    # Individual trees stay separate in Blender; Godot batches spatial cells.
    spacing = 12.5
    axis = np.arange(-2000, 2000, spacing, dtype=np.float32)
    x, y = np.meshgrid(axis, axis)
    x = x.ravel() + rng.uniform(-spacing * .48, spacing * .48, x.size)
    y = y.ravel() + rng.uniform(-spacing * .48, spacing * .48, y.size)
    density = sample(data["forest"], x, y)
    dry = sample(data["land_d"], x, y) > 34
    near_lake = sample(data["lake_out"], x, y) < 37
    accepted = dry & ~near_lake & (rng.random(x.size) < np.clip(density * .85, 0, .88))
    x, y = x[accepted], y[accepted]
    z = sample(data["height"], x, y)
    kind = rng.choice(["broadleaf", "pine"], size=x.size, p=[.62, .38])
    angle = rng.uniform(0, math.tau, x.size)
    scale = rng.uniform(.82, 1.28, x.size)
    return [{"type": str(k), "x": round(float(xx), 3), "y": round(float(yy), 3),
             "z": round(float(zz), 3), "rotation": round(float(a), 6), "scale": round(float(s), 4)}
            for k, xx, yy, zz, a, s in zip(kind, x, y, z, angle, scale)]


def metrics(data, forest):
    indices = np.argwhere(data["land"])
    y_min, x_min = indices.min(axis=0)
    y_max, x_max = indices.max(axis=0)
    return {"seed": SEED, "grid_size_m": SIZE, "shoreline_width_m": round(float((x_max - x_min) * STEP), 2),
            "shoreline_depth_m": round(float((y_max - y_min) * STEP), 2), "terrain_grid": GRID,
            "grid_step_m": STEP, "lake_level_m": LAKE_LEVEL,
            "terrain_min_m": round(float(data["height"].min()), 2),
            "terrain_max_m": round(float(data["height"].max()), 2),
            "lake_area_m2": int(data["lake"].sum() * STEP ** 2),
            "tree_count": len(forest), "pine_count": sum(p["type"] == "pine" for p in forest),
            "broadleaf_count": sum(p["type"] == "broadleaf" for p in forest),
            "clearings": data["clearings"]}


if __name__ == "__main__":
    terrain = build()
    trees = forest_positions(terrain)
    print(json.dumps(metrics(terrain, trees), ensure_ascii=False, indent=2))
