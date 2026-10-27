"""Prepare placement, surface and map data for the supplied island GLB.

The uploaded original is never rewritten. The game builds its visible and
physical mesh from the optimized copy at runtime. This script rasterizes its
top surface for height queries and safe placements, derives a connected
walkable area, and routes roads around the model's existing trees and rocks.

Run from the repository root with Python 3, numpy, scipy and Pillow installed:
    python tools/prepare_user_island.py

The dimensions, orientation and height calibration must match
scripts/environment_3d.gd. The RGB data textures are deliberately opaque and
lossless: R/G encode a 16-bit source height and B encodes clearance; the other
texture encodes the index of the nearest safe pixel as a 24-bit integer.
"""
from __future__ import annotations

import heapq
import json
import math
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import binary_dilation, distance_transform_edt, label, minimum_filter

SOURCE = Path("assets/models/environment/user_island.glb")
OUTPUT = Path("assets/environment")
WIDTH, HEIGHT = 640, 440
WORLD_WIDTH, WORLD_DEPTH = 128.0, 88.0
WORLD_HEIGHT_SCALE, RAW_GROUND = 75.0, 0.011
SEA_Y = -0.8
HEIGHT_MIN, HEIGHT_MAX = 0.0, 0.067732
MAX_CLEARANCE = 8.0
# Positions are legacy map coordinates, matching scripts/world.gd.
SITES = {
    "spawn": (360, 1830), "camp": (850, 1280),
    "hotel": (2150, 1440), "airfield": (2850, 500),
    "chip": (2850, 700), "cave": (590, 430),
    "cell": (1360, 450), "teddy": (1390, 565),
    "lighthouse": (2750, 1800), "boat": (380, 1950),
}


def read_glb(path: Path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data)
    if magic != b"glTF" or version != 2 or length != len(data):
        raise ValueError("Expected an intact glTF 2.0 binary")
    json_size, json_type = struct.unpack_from("<I4s", data, 12)
    if json_type != b"JSON":
        raise ValueError("The first GLB chunk must be JSON")
    gltf = json.loads(data[20:20 + json_size])
    bin_size, bin_type = struct.unpack_from("<I4s", data, 20 + json_size)
    if bin_type != b"BIN\0":
        raise ValueError("The GLB needs an embedded binary buffer")
    blob = memoryview(data)[28 + json_size:28 + json_size + bin_size]

    def accessor(index):
        a = gltf["accessors"][index]
        view = gltf["bufferViews"][a["bufferView"]]
        count = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        dtype = {5123: np.dtype("<u2"), 5125: np.dtype("<u4"), 5126: np.dtype("<f4")}[a["componentType"]]
        stride = view.get("byteStride", count * dtype.itemsize)
        offset = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        return np.ndarray((a["count"], count), dtype, buffer=blob, offset=offset,
                          strides=(stride, dtype.itemsize)).copy()

    mesh_nodes = [node for node in gltf["nodes"] if node.get("mesh") == 0]
    rotation = mesh_nodes[0].get("rotation", []) if len(mesh_nodes) == 1 else []
    if len(rotation) != 4 or not np.allclose(rotation, [2**-0.5, 0, 0, 2**-0.5], atol=1e-5):
        raise ValueError("Unexpected island node rotation; recalibrate the placement transform")
    if mesh_nodes[0].get("translation", [0, 0, 0]) != [0, 0, 0] or mesh_nodes[0].get("scale", [1, 1, 1]) != [1, 1, 1]:
        raise ValueError("Unexpected island translation/scale; recalibrate the placement transform")
    primitive = gltf["meshes"][0]["primitives"][0]
    if primitive.get("mode", 4) != 4:
        raise ValueError("The supplied island must contain triangles")
    return (accessor(primitive["attributes"]["POSITION"]),
            accessor(primitive["attributes"]["NORMAL"]),
            accessor(primitive["indices"]).reshape(-1, 3))


def rasterize(positions, normals, triangles):
    # The GLB node first rotates +90 degrees around X; the game then rotates
    # the island 180 degrees around Y and fits it to 128 x 88 metres. Source
    # mesh coordinates are therefore (world X, Y, Z) = (-x, -z, -y).
    x = -positions[:, 0]
    z = -positions[:, 1]
    x = (x - x.min()) / np.ptp(x) * (WIDTH - 1)
    z = (z - z.min()) / np.ptp(z) * (HEIGHT - 1)
    y = -positions[:, 2]
    top = np.full((HEIGHT, WIDTH), -np.inf, dtype=np.float32)
    top_normal_y = np.zeros_like(top)
    for triangle in triangles:
        xp, zp, yp = x[triangle], z[triangle], y[triangle]
        xl = max(0, int(np.floor(xp.min())))
        xh = min(WIDTH - 1, int(np.ceil(xp.max())))
        zl = max(0, int(np.floor(zp.min())))
        zh = min(HEIGHT - 1, int(np.ceil(zp.max())))
        if xl > xh or zl > zh:
            continue
        denominator = ((zp[1] - zp[2]) * (xp[0] - xp[2])
                       + (xp[2] - xp[1]) * (zp[0] - zp[2]))
        if abs(denominator) < 1e-9:
            continue
        xx, zz = np.meshgrid(np.arange(xl, xh + 1), np.arange(zl, zh + 1))
        u = ((zp[1] - zp[2]) * (xx - xp[2]) + (xp[2] - xp[1]) * (zz - zp[2])) / denominator
        v = ((zp[2] - zp[0]) * (xx - xp[2]) + (xp[0] - xp[2]) * (zz - zp[2])) / denominator
        w = 1.0 - u - v
        inside = (u >= -1e-5) & (v >= -1e-5) & (w >= -1e-5)
        yy = u * yp[0] + v * yp[1] + w * yp[2]
        section = top[zl:zh + 1, xl:xh + 1]
        update = inside & (yy > section)
        section[update] = yy[update]
        ny = -(u * normals[triangle[0], 2] + v * normals[triangle[1], 2] + w * normals[triangle[2], 2])
        top_normal_y[zl:zh + 1, xl:xh + 1][update] = ny[update]
    return top, top_normal_y


def build_walkable(top, normals):
    land = np.isfinite(top) & ((top - RAW_GROUND) * WORLD_HEIGHT_SCALE > SEA_Y)
    # The model includes trees and rocks in a single mesh. Detect raised
    # obstacles relative to the surrounding terrain, instead of banning every
    # high-altitude place on an otherwise gently sloping island.
    local_minimum = minimum_filter(np.where(land, top, np.inf), size=31, mode="nearest")
    difference = np.zeros_like(top)
    np.subtract(top, local_minimum, out=difference, where=land)
    raised_obstacle = difference > 0.014
    blocked = (~land) | raised_obstacle | (normals < 0.55)
    blocked = binary_dilation(blocked, iterations=2)
    pitch = (WORLD_DEPTH / (HEIGHT - 1), WORLD_WIDTH / (WIDTH - 1))
    clearance = distance_transform_edt(~blocked, sampling=pitch)
    components, _ = label(clearance >= 1.0)
    sizes = np.bincount(components.ravel())
    sizes[0] = 0
    if not sizes.any():
        raise ValueError("No connected ground suitable for gameplay")
    main = components == np.argmax(sizes)
    # Smaller isolated ledges are excluded, even if their centres are flat.
    clearance[~main] = 0.0
    safe_destination = main & (clearance >= 1.15)
    if not safe_destination.any():
        raise ValueError("No destination with sufficient character clearance")
    _, nearest = distance_transform_edt(~safe_destination, sampling=pitch, return_indices=True)
    return land, clearance, nearest


def save_placement_data(top, clearance, nearest):
    safe_height = np.where(np.isfinite(top), top, HEIGHT_MIN)
    value = np.rint(np.clip((safe_height - HEIGHT_MIN) / (HEIGHT_MAX - HEIGHT_MIN), 0, 1) * 65535).astype(np.uint16)
    data = np.stack((value >> 8, value & 255,
                     np.rint(np.clip(clearance / MAX_CLEARANCE, 0, 1) * 255).astype(np.uint16)), axis=-1).astype(np.uint8)
    Image.fromarray(data).save(OUTPUT / "user_island_data.png", optimize=True)
    index = nearest[0].astype(np.uint32) * WIDTH + nearest[1].astype(np.uint32)
    encoded = np.stack(((index >> 16) & 255, (index >> 8) & 255, index & 255), axis=-1).astype(np.uint8)
    Image.fromarray(encoded).save(OUTPUT / "user_island_nearest.png", optimize=True)


def point_pixel(map_point):
    return (round(map_point[0] / 3200.0 * (WIDTH - 1)),
            round(map_point[1] / 2200.0 * (HEIGHT - 1)))


def make_roads(clearance, nearest):
    # A small A* grid provides visual road routes that follow connected ground
    # rather than crossing the baked-in buildings and cliffs.
    cols, rows = 160, 110
    px = np.rint((np.arange(cols) + 0.5) / cols * (WIDTH - 1)).astype(int)
    pz = np.rint((np.arange(rows) + 0.5) / rows * (HEIGHT - 1)).astype(int)
    costs = clearance[np.ix_(pz, px)]
    open_cells = costs >= 1.0
    _, closest_grid = distance_transform_edt(~open_cells, return_indices=True)

    def cell(name):
        x, z = point_pixel(SITES[name])
        x, z = int(nearest[1, z, x]), int(nearest[0, z, x])
        gx = min(cols - 1, max(0, int(x / WIDTH * cols)))
        gz = min(rows - 1, max(0, int(z / HEIGHT * rows)))
        if not open_cells[gz, gx]:
            gz, gx = int(closest_grid[0, gz, gx]), int(closest_grid[1, gz, gx])
        return gx, gz

    def route(start, goal):
        queue = [(0.0, 0.0, start)]
        best = {start: 0.0}
        previous = {}
        neighbors = [(dx, dz) for dz in (-1, 0, 1) for dx in (-1, 0, 1) if dx or dz]
        while queue:
            _, cost, here = heapq.heappop(queue)
            if cost > best.get(here, float("inf")):
                continue
            if here == goal:
                path = [here]
                while here != start:
                    here = previous[here]
                    path.append(here)
                return list(reversed(path))
            for dx, dz in neighbors:
                x, z = here[0] + dx, here[1] + dz
                if x < 0 or x >= cols or z < 0 or z >= rows or not open_cells[z, x]:
                    continue
                if dx and dz and (not open_cells[here[1], x] or not open_cells[z, here[0]]):
                    continue
                penalty = 0.16 / max(1.0, float(costs[z, x]))
                candidate = cost + math.hypot(dx, dz) * (1.0 + penalty)
                nxt = (x, z)
                if candidate < best.get(nxt, float("inf")):
                    best[nxt] = candidate
                    previous[nxt] = here
                    heuristic = math.hypot(goal[0] - x, goal[1] - z)
                    heapq.heappush(queue, (candidate + heuristic, candidate, nxt))
        raise ValueError(f"No road route between {start} and {goal}")

    def clear_line(a, b):
        distance = math.hypot(b[0] - a[0], b[1] - a[1])
        for t in np.linspace(0.0, 1.0, max(2, math.ceil(distance * 3))):
            x = round(a[0] + (b[0] - a[0]) * t)
            z = round(a[1] + (b[1] - a[1]) * t)
            if not open_cells[z, x]:
                return False
        return True

    def simplify(path):
        result = [path[0]]
        start = 0
        while start < len(path) - 1:
            end = start + 1
            for j in range(end + 1, len(path)):
                if not clear_line(path[start], path[j]):
                    break
                end = j
            result.append(path[end])
            start = end
        return result

    # Paths are drawn at twice the sampling resolution for soft, narrow edges.
    size = (WIDTH * 2, HEIGHT * 2)
    road = Image.new("L", size, 0)
    trail = Image.new("L", size, 0)
    branches = [
        ("spawn", "camp", road), ("camp", "hotel", road),
        ("hotel", "airfield", road), ("hotel", "lighthouse", road),
        ("camp", "cave", trail), ("camp", "cell", trail),
        ("cell", "teddy", trail), ("airfield", "chip", trail),
        ("spawn", "boat", trail),
    ]
    for origin, destination, image in branches:
        path = simplify(route(cell(origin), cell(destination)))
        points = [((x + 0.5) / cols * size[0], (z + 0.5) / rows * size[1]) for x, z in path]
        ImageDraw.Draw(image).line(points, fill=164 if image is road else 190,
                                   width=24 if image is road else 15, joint="curve")
        print(f"  {origin:10} -> {destination:10}: {len(path)} waypoints")
    road = np.asarray(road.filter(ImageFilter.GaussianBlur(1.5)), dtype=np.uint8).copy()
    trail = np.asarray(trail.filter(ImageFilter.GaussianBlur(1.5)), dtype=np.uint8).copy()
    allowed = np.asarray(Image.fromarray((clearance >= 0.95).astype(np.uint8) * 255).resize(size, Image.Resampling.NEAREST))
    road[allowed == 0] = 0
    trail[allowed == 0] = 0
    return road, trail


def save_surface_and_map(top, land, clearance, nearest):
    road, trail = make_roads(clearance, nearest)
    size = (WIDTH * 2, HEIGHT * 2)
    land_img = Image.fromarray((land * 255).astype(np.uint8)).resize(size, Image.Resampling.NEAREST)
    coast_distance = distance_transform_edt(land, sampling=(WORLD_DEPTH / (HEIGHT - 1), WORLD_WIDTH / (WIDTH - 1)))
    # The blue channel marks the water's edge; the source model already has
    # UV/PBR textures for all of its trees and rocks, not untextured buildings.
    shore = np.clip((1.25 - coast_distance) / 1.25, 0, 1) * 255
    blue = Image.fromarray(shore.astype(np.uint8)).resize(size, Image.Resampling.BILINEAR)
    layout = np.dstack((road, trail, np.asarray(blue))).astype(np.uint8)
    Image.fromarray(layout).save(OUTPUT / "user_island_layout.png", optimize=True)

    # The map is derived from the same silhouette, heights and routes. Its
    # landmarks are drawn by map_view.gd using the actual relocated positions.
    h = np.asarray(Image.fromarray(np.where(np.isfinite(top), top, HEIGHT_MIN).astype(np.float32)).resize(size, Image.Resampling.BILINEAR))
    land2 = np.asarray(land_img) > 127
    elevation = np.clip((h - RAW_GROUND) / 0.055, 0, 1)
    zz, xx = np.indices((size[1], size[0]))
    noise = 3.5 * np.sin(xx * 0.037) * np.cos(zz * 0.031)
    color = np.empty((size[1], size[0], 3), dtype=np.float32)
    color[:] = (31, 67, 71)
    terrain = np.stack((91 + noise + elevation * 8, 111 + noise + elevation * 9,
                        76 + noise + elevation * 5), axis=-1)
    local_minimum = minimum_filter(np.where(land, top, np.inf), size=31, mode="nearest")
    rise = np.zeros_like(top)
    np.subtract(top, local_minimum, out=rise, where=land)
    raised = np.asarray(Image.fromarray(np.clip(rise / 0.025, 0, 1).astype(np.float32)).resize(size, Image.Resampling.BILINEAR))[..., None]
    terrain = terrain * (1 - raised * 0.6) + np.array([54, 76, 51]) * raised * 0.6
    sand = (np.asarray(blue) / 255.0 * 0.75)[..., None]
    terrain = terrain * (1 - sand) + np.array([153, 142, 107]) * sand
    paths = (np.maximum(road, trail) / 255.0 * 0.75)[..., None]
    terrain = terrain * (1 - paths) + np.array([135, 126, 105]) * paths
    color[land2] = terrain[land2]
    Image.fromarray(np.clip(color, 0, 255).astype(np.uint8)).save(OUTPUT / "user_island_map.png", optimize=True)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    positions, normals, triangles = read_glb(SOURCE)
    print(f"Rasterizing {len(positions)} vertices and {len(triangles)} triangles from {SOURCE}")
    if len(positions) != 108946 or len(triangles) != 120000:
        raise ValueError("Unexpected island model; recheck the transform and placement masks")
    top, normals = rasterize(positions, normals, triangles)
    land, clearance, nearest = build_walkable(top, normals)
    save_placement_data(top, clearance, nearest)
    save_surface_and_map(top, land, clearance, nearest)
    print(f"Land coverage {land.mean():.1%}, connected gameplay area {(clearance >= 1.0).mean():.1%}")
    print("Wrote user_island_data, user_island_nearest, user_island_layout and user_island_map PNGs")


if __name__ == "__main__":
    main()
