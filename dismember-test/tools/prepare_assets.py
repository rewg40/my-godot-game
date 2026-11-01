#!/usr/bin/env python3
"""Подготовка ассетов полигона: распаковка архивов и нарезка моделей на части.

Что делает:

1. Склеивает разрезанные архивы из корня репозитория и раскладывает модели::

       ZOMBI.7z.*      -> assets/models/zombie.glb
       остров 1.7z.*   -> assets/models/island.glb
       персонаж 1.7z.* -> assets/models/character.glb

2. Режет скульптуры без скелета на пять частей по правилам из
   ``tools/split_profiles.json`` и пишет рядом готовые для Godot файлы::

       assets/models/zombie_parts.glb   + zombie_parts.json
       assets/models/character_parts.glb + character_parts.json

   В GLB у меша появляется пять примитивов (тело, две руки, две ноги) — все
   с общим буфером вершин и одной текстурой, поэтому файл почти не тяжелеет.
   В JSON лежат шарниры и габариты частей, чтобы Godot не считал их сам.

Зависимости: ``python -m pip install py7zr numpy``

Примеры::

    python tools/prepare_assets.py
    python tools/prepare_assets.py --models-dir /tmp/models --out-dir /tmp/models
"""
from __future__ import annotations

import argparse
import json
import shutil
import struct
import sys
import tempfile
from pathlib import Path

import numpy as np

PROJECT = Path(__file__).resolve().parent.parent
PROFILES_PATH = Path(__file__).resolve().parent / "split_profiles.json"

ARCHIVES = {
    "ZOMBI.7z": ("ZOMBI.glb", "zombie.glb"),
    "остров 1.7z": ("остров 1.glb", "island.glb"),
    "персонаж 1.7z": ("персонаж 1.glb", "character.glb"),
}

PART_ORDER = ["body", "arm_l", "arm_r", "leg_l", "leg_r"]
COMPONENT = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


# --- GLB ---------------------------------------------------------------------

def read_glb(path: Path):
    data = path.read_bytes()
    magic, version, length = struct.unpack("<4sII", data[:12])
    if magic != b"glTF":
        raise ValueError(f"{path} — не GLB")
    offset = 12
    gltf = None
    binary = b""
    while offset < length:
        chunk_len, chunk_type = struct.unpack("<I4s", data[offset:offset + 8])
        chunk = data[offset + 8:offset + 8 + chunk_len]
        if chunk_type == b"JSON":
            gltf = json.loads(chunk)
        elif chunk_type == b"BIN\x00":
            binary = chunk
        offset += 8 + chunk_len
    return gltf, bytearray(binary)


def write_glb(path: Path, gltf, binary: bytes) -> None:
    gltf["buffers"][0]["byteLength"] = len(binary)
    js = json.dumps(gltf, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    bin_chunk = binary + b"\x00" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(bin_chunk)
    with open(path, "wb") as handle:
        handle.write(struct.pack("<4sII", b"glTF", 2, total))
        handle.write(struct.pack("<I4s", len(js), b"JSON"))
        handle.write(js)
        handle.write(struct.pack("<I4s", len(bin_chunk), b"BIN\x00"))
        handle.write(bin_chunk)


def local_matrix(node: dict) -> np.ndarray:
    if "matrix" in node:
        return np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
    mat = np.eye(4)
    if "translation" in node:
        trans = np.eye(4)
        trans[:3, 3] = node["translation"]
        mat = mat @ trans
    if "rotation" in node:
        x, y, z, w = node["rotation"]
        rot = np.array([
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ])
        rot4 = np.eye(4)
        rot4[:3, :3] = rot
        mat = mat @ rot4
    if "scale" in node:
        scale = np.diag(list(node["scale"]) + [1.0])
        mat = mat @ scale
    return mat


def find_mesh_node(gltf, mesh_index: int):
    """Первый узел сцены с нужным мешем и его мировая матрица."""
    def walk(index: int, parent: np.ndarray):
        node = gltf["nodes"][index]
        world = parent @ local_matrix(node)
        if node.get("mesh") == mesh_index:
            return index, world
        for child in node.get("children", []):
            found = walk(child, world)
            if found is not None:
                return found
        return None

    for root in gltf["scenes"][gltf.get("scene", 0)]["nodes"]:
        found = walk(root, np.eye(4))
        if found is not None:
            return found
    return None, np.eye(4)


def append_accessor(gltf, binary: bytearray, array: np.ndarray, component: int,
                    type_name: str, target: int | None = None,
                    with_bounds: bool = False) -> int:
    """Дописывает данные в буфер и возвращает индекс нового accessor."""
    dtype = np.dtype(COMPONENT[component]).newbyteorder("<")
    payload = np.ascontiguousarray(array, dtype=dtype).tobytes()
    binary.extend(b"\x00" * ((4 - len(binary) % 4) % 4))
    offset = len(binary)
    binary.extend(payload)
    view = {"buffer": 0, "byteOffset": offset, "byteLength": len(payload)}
    if target is not None:
        view["target"] = target
    gltf["bufferViews"].append(view)
    count = int(array.shape[0]) if array.ndim > 1 else int(array.size)
    accessor = {
        "bufferView": len(gltf["bufferViews"]) - 1,
        "componentType": component,
        "count": count,
        "type": type_name,
    }
    if with_bounds:
        flat = array.reshape(count, -1)
        accessor["min"] = [float(v) for v in flat.min(axis=0)]
        accessor["max"] = [float(v) for v in flat.max(axis=0)]
    gltf["accessors"].append(accessor)
    return len(gltf["accessors"]) - 1


def rot_y(degrees: float) -> np.ndarray:
    angle = np.radians(degrees)
    cos_a, sin_a = np.cos(angle), np.sin(angle)
    return np.array([
        [cos_a, 0.0, sin_a, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [-sin_a, 0.0, cos_a, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ])


def bake_transform(gltf, binary: bytearray, mesh_index: int,
                   extra: np.ndarray | None = None) -> np.ndarray:
    """Запекает трансформацию узла в вершины: на выходе честный Y-up."""
    node_index, world = find_mesh_node(gltf, mesh_index)
    if node_index is None:
        return np.eye(4)
    if extra is not None:
        world = extra @ world
    rotation = world[:3, :3]
    if np.allclose(world, np.eye(4), atol=1e-6):
        return world

    normal_matrix = np.linalg.inv(rotation).T
    cache: dict[int, int] = {}
    for primitive in gltf["meshes"][mesh_index]["primitives"]:
        for key in ("POSITION", "NORMAL"):
            old = primitive["attributes"].get(key)
            if old is None:
                continue
            if old not in cache:
                values = accessor_array(gltf, binary, old).astype(np.float64)
                if key == "POSITION":
                    hom = np.hstack([values, np.ones((len(values), 1))])
                    baked = (hom @ world.T)[:, :3]
                    cache[old] = append_accessor(gltf, binary, baked, 5126, "VEC3",
                                                 with_bounds=True)
                else:
                    baked = values @ normal_matrix.T
                    lengths = np.linalg.norm(baked, axis=1, keepdims=True)
                    lengths[lengths == 0.0] = 1.0
                    cache[old] = append_accessor(gltf, binary, baked / lengths,
                                                 5126, "VEC3")
            primitive["attributes"][key] = cache[old]

    node = gltf["nodes"][node_index]
    for key in ("matrix", "translation", "rotation", "scale"):
        node.pop(key, None)
    return world


def accessor_array(gltf, binary, index: int) -> np.ndarray:
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    dtype = np.dtype(COMPONENT[acc["componentType"]]).newbyteorder("<")
    ncomp = NCOMP[acc["type"]]
    count = acc["count"]
    stride = view.get("byteStride", dtype.itemsize * ncomp)
    if stride == dtype.itemsize * ncomp:
        values = np.frombuffer(bytes(binary), dtype=dtype, count=count * ncomp, offset=start)
        return values.reshape(count, ncomp)
    rows = np.zeros((count, ncomp), dtype=dtype)
    raw = np.frombuffer(bytes(binary), dtype=np.uint8, count=stride * count, offset=start)
    for i in range(count):
        rows[i] = np.frombuffer(raw[i * stride:i * stride + dtype.itemsize * ncomp].tobytes(),
                                dtype=dtype, count=ncomp)
    return rows


# --- Нарезка ----------------------------------------------------------------

def segment_distance(points: np.ndarray, start: np.ndarray, end: np.ndarray):
    """Расстояние точек до отрезка и параметр проекции t в [0, 1]."""
    axis = end - start
    denominator = float(axis @ axis)
    if denominator < 1e-12:
        return np.linalg.norm(points - start, axis=1), np.zeros(len(points))
    t = np.clip(((points - start) @ axis) / denominator, 0.0, 1.0)
    projected = start + t[:, None] * axis
    return np.linalg.norm(points - projected, axis=1), t


def arm_axis(points: np.ndarray, center_x: float, hip_y: float, shoulder_y: float,
             height: float, side: float, arm_x: float):
    """Ось руки: от плеча к кисти.

    Кисть ищется как точка полосы рук, максимально удалённая от позвоночника,
    с бонусом за то, что она ниже плеча: у сгорбленной позы плечо само торчит
    в сторону, и без бонуса ось уходит вбок, а не вниз по руке.
    """
    band = (points[:, 1] > hip_y) & (points[:, 1] < shoulder_y + 0.03 * height)
    candidates = points[band]
    if len(candidates) == 0:
        return None
    nx = (candidates[:, 0] - center_x) / height
    ny = (candidates[:, 1] - points[:, 1].min()) / height
    score = side * nx + 0.7 * ((shoulder_y - points[:, 1].min()) / height - ny)
    tip = candidates[int(np.argmax(score))]
    start = np.array([
        center_x + side * arm_x * 0.6,
        shoulder_y - 0.02 * height,
        tip[2],
    ])
    return start, tip


def classify(points: np.ndarray, indices: np.ndarray, profile: dict):
    """Разметка треугольников: тело, две руки, две ноги.

    Ноги режутся плоскостью бёдер по половинам, руки — «трубой» вокруг оси
    плечо-кисть: у скульптур руки часто прижаты к корпусу, и прямоугольный
    рез по X вместе с рукой уносит кусок груди.
    """
    lo = points.min(axis=0)
    hi = points.max(axis=0)
    height = max(hi[1] - lo[1], 1e-6)
    center_x = (lo[0] + hi[0]) * 0.5 + profile.get("center_x", 0.0)
    hip_y = lo[1] + height * profile.get("hip_y", 0.45)
    shoulder_y = lo[1] + height * profile.get("shoulder_y", 0.84)
    arm_x = profile.get("arm_x", 0.14)
    radius = profile.get("arm_radius", 0.08)
    taper = profile.get("arm_taper", 1.2)

    triangles = indices.reshape(-1, 3)
    centroids = points[triangles].mean(axis=1)
    slots = np.zeros(len(triangles), dtype=np.uint8)
    legs = centroids[:, 1] < hip_y
    slots[legs & (centroids[:, 0] < center_x)] = 3
    slots[legs & (centroids[:, 0] >= center_x)] = 4

    arm_band = (centroids[:, 1] >= hip_y) & (centroids[:, 1] <= shoulder_y + 0.03 * height)
    pivots = {}
    for side, slot, part_id in ((-1.0, 1, "arm_l"), (1.0, 2, "arm_r")):
        axis = arm_axis(points, center_x, hip_y, shoulder_y, height, side, arm_x)
        if axis is None:
            continue
        start, tip = axis
        distance, t = segment_distance(centroids, start, tip)
        # труба расширяется к кисти: ладонь и пальцы шире предплечья, а корпуса
        # на дальнем конце руки уже нет, поэтому расширение ничего не задевает
        local_radius = radius * (1.0 + taper * t)
        mask = arm_band & (distance < local_radius) & (t > 0.15)
        slots[mask] = slot
        pivots[part_id] = start.tolist()

    info = {
        "height": float(height),
        "min": lo.tolist(),
        "max": hi.tolist(),
        "center_x": float(center_x),
        "hip_y": float(hip_y),
        "shoulder_y": float(shoulder_y),
        "arm_x": float(arm_x),
        "pivots": pivots,
    }
    return slots, info


def part_bounds(points: np.ndarray, triangles: np.ndarray, slots: np.ndarray, slot: int):
    mask = slots == slot
    if not mask.any():
        return None
    used = np.unique(triangles[mask].ravel())
    sub = points[used]
    return sub.min(axis=0), sub.max(axis=0)


def split_model(source: Path, target: Path, profile: dict) -> dict:
    gltf, binary = read_glb(source)
    if len(gltf.get("meshes", [])) > 1:
        print(f"[внимание] {source.name}: мешей {len(gltf['meshes'])}, берём первый")
    bake_transform(gltf, binary, 0, rot_y(profile.get("yaw", 180.0)))
    mesh = gltf["meshes"][0]
    primitive = mesh["primitives"][0]
    points = accessor_array(gltf, binary, primitive["attributes"]["POSITION"]).astype(np.float64)
    if "indices" in primitive:
        indices = accessor_array(gltf, binary, primitive["indices"]).ravel().astype(np.int64)
    else:
        indices = np.arange(len(points), dtype=np.int64)

    slots, info = classify(points, indices, profile)
    triangles = indices.reshape(-1, 3)

    base_offset = (len(binary) + 3) // 4 * 4
    binary.extend(b"\x00" * (base_offset - len(binary)))

    new_primitives = []
    pivots = {}
    bounds = {}
    counts = {}
    for slot, part_id in enumerate(PART_ORDER):
        indices32 = triangles[slots == slot].ravel().astype(np.uint32)
        counts[part_id] = int(len(indices32) // 3)
        part_bounds_result = part_bounds(points, triangles, slots, slot)
        if part_bounds_result is None:
            bounds[part_id] = {"min": [0, 0, 0], "max": [0, 0, 0]}
        else:
            low, high = part_bounds_result
            bounds[part_id] = {"min": low.tolist(), "max": high.tolist()}

        if part_id == "body":
            pivots[part_id] = [0.0, 0.0, float((info["min"][2] + info["max"][2]) * 0.5)]
        else:
            side = -1.0 if part_id.endswith("_l") else 1.0
            if part_id.startswith("arm") and part_id in info["pivots"]:
                pivots[part_id] = info["pivots"][part_id]
            elif part_id.startswith("arm"):
                pivots[part_id] = [
                    info["center_x"] + side * info["arm_x"],
                    info["shoulder_y"],
                    float((info["min"][2] + info["max"][2]) * 0.5),
                ]
            else:
                pivots[part_id] = [
                    info["center_x"] + side * profile.get("leg_offset", 0.09),
                    info["hip_y"],
                    float((info["min"][2] + info["max"][2]) * 0.5),
                ]

        if len(indices32) == 0:
            continue

        offset = len(binary)
        binary.extend(indices32.tobytes())
        binary.extend(b"\x00" * ((4 - len(binary) % 4) % 4))

        gltf["bufferViews"].append({
            "buffer": 0,
            "byteOffset": offset,
            "byteLength": int(len(indices32) * 4),
            "target": 34963,
        })
        gltf["accessors"].append({
            "bufferView": len(gltf["bufferViews"]) - 1,
            "componentType": 5125,
            "count": int(len(indices32)),
            "type": "SCALAR",
        })
        attributes = dict(primitive["attributes"])
        new_primitive = {
            "attributes": attributes,
            "indices": len(gltf["accessors"]) - 1,
            "mode": 4,
        }
        if "material" in primitive:
            new_primitive["material"] = primitive["material"]
        new_primitives.append(new_primitive)

    mesh["primitives"] = new_primitives
    mesh["extras"] = {"parts": PART_ORDER, "source": source.name}
    write_glb(target, gltf, bytes(binary))

    meta = {
        "source": source.name,
        "order": PART_ORDER,
        "pivots": pivots,
        "bounds": bounds,
        "triangles": counts,
        "height": info["height"],
        "yaw": profile.get("yaw", 180.0),
        "size": [info["max"][0] - info["min"][0], info["height"], info["max"][2] - info["min"][2]],
    }
    meta_path = target.with_suffix(".json")
    meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
    return meta


# --- Архивы -----------------------------------------------------------------

def find_parts(repo: Path, base: str) -> list[Path]:
    parts = sorted(repo.glob(base + ".*[0-9][0-9][0-9]"))
    return [p for p in parts if p.suffix[1:].isdigit()]


def unpack_models(repo: Path, models_dir: Path) -> None:
    models_dir.mkdir(parents=True, exist_ok=True)
    try:
        import py7zr  # type: ignore
    except ImportError:
        print("Нужен py7zr:  python -m pip install py7zr")
        return
    for base, (inner, out_name) in ARCHIVES.items():
        target = models_dir / out_name
        if target.exists():
            continue
        parts = find_parts(repo, base)
        if not parts:
            continue
        merged = Path(tempfile.mkstemp(suffix=".7z")[1])
        with open(merged, "wb") as handle:
            for part in parts:
                with open(part, "rb") as source:
                    shutil.copyfileobj(source, handle, length=1024 * 1024)
        try:
            with tempfile.TemporaryDirectory() as tmp:
                with py7zr.SevenZipFile(str(merged)) as archive:
                    archive.extractall(path=tmp)
                found = Path(tmp) / inner
                if not found.exists():
                    candidates = list(Path(tmp).glob("*.glb"))
                    found = candidates[0] if candidates else found
                if found.exists():
                    shutil.move(str(found), str(target))
                    print(f"[модель] {target.name} ({target.stat().st_size // (1024 * 1024)} МБ)")
        finally:
            merged.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Ассеты полигона: распаковка и нарезка")
    parser.add_argument("--repo", default=str(PROJECT.parent),
                        help="каталог с архивами .7z.001 (по умолчанию корень репозитория)")
    parser.add_argument("--models-dir", default=str(PROJECT / "assets" / "models"))
    parser.add_argument("--out-dir", default="", help="куда писать *_parts.glb (по умолчанию туда же)")
    parser.add_argument("--skip-unpack", action="store_true")
    args = parser.parse_args()

    models_dir = Path(args.models_dir)
    out_dir = Path(args.out_dir) if args.out_dir else models_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    if not args.skip_unpack:
        unpack_models(Path(args.repo), models_dir)

    profiles = json.loads(PROFILES_PATH.read_text(encoding="utf-8"))
    for name, profile in profiles.items():
        source = models_dir / profile["source"]
        if not source.exists():
            print(f"[пропуск] нет {source}")
            continue
        target = out_dir / (name + "_parts.glb")
        meta = split_model(source, target, profile)
        print(f"[нарезка] {target.name}: " + ", ".join(
            f"{part}={meta['triangles'][part]}" for part in meta["order"]))
        print(f"          шарниры: {json.dumps(meta['pivots'], ensure_ascii=False)}")

    improved = models_dir / "island_improved.glb"
    plain = models_dir / "island.glb"
    if improved.exists():
        print(f"[карта] используется улучшенный остров: {improved.name}")
    elif plain.exists():
        print(f"[карта] улучшенного острова нет, берём {plain.name}")
        print("        положите «2 остров улучшенный.glb» как assets/models/island_improved.glb")
    else:
        print("[карта] острова нет — будет процедурная заглушка")

    print("\nГотово. Откройте проект в Godot 4.4+ и нажмите F5.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
