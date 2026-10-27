#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
validate_glb.py — проверка целостности всех .glb в папке.

Только stdlib. Для каждого файла проверяет:
  * magic / version / общую длину GLB;
  * длины и типы чанков JSON и BIN;
  * что JSON разбирается и BIN ровно столько, сколько заявлено в buffers[0];
  * что каждый accessor (byteOffset + count * stride) не выходит за BIN;
  * что у каждого меша есть POSITION, а индексы ссылаются на существующие вершины;
  * что цепочка materials -> textures -> images -> bufferViews цела и ни один
    индекс не выходит за диапазон (важно для .glb, собранных из glTF separate).

Запуск:
    python3 validate_glb.py <папка>        # рекурсивно по *.glb
Код возврата: 0 — все файлы валидны, 1 — есть ошибки.
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

COMPONENT_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
COMPONENT_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def validate(path: Path) -> list[str]:
    errors: list[str] = []
    data = path.read_bytes()

    if len(data) < 12:
        return ["файл короче 12 байт — это не GLB"]

    magic, version, total_len = struct.unpack("<4sII", data[:12])
    if magic != b"glTF":
        return [f"неверный magic: {magic!r}"]
    if version != 2:
        errors.append(f"version={version}, ожидалось 2")
    if total_len != len(data):
        errors.append(f"в заголовке длина {total_len}, фактически {len(data)}")

    offset = 12
    json_chunk = None
    bin_chunk = None
    while offset + 8 <= len(data):
        chunk_len, chunk_type = struct.unpack("<I4s", data[offset : offset + 8])
        start = offset + 8
        end = start + chunk_len
        if end > len(data):
            errors.append(f"чанк {chunk_type!r} выходит за конец файла")
            break
        payload = data[start:end]
        if chunk_type == b"JSON":
            json_chunk = payload
        elif chunk_type in (b"BIN\x00", b"BIN "):
            bin_chunk = payload
        offset = end

    if json_chunk is None:
        return errors + ["нет чанка JSON"]
    if bin_chunk is None:
        return errors + ["нет чанка BIN"]

    try:
        gltf = json.loads(json_chunk.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        return errors + [f"JSON не разбирается: {exc}"]

    buffers = gltf.get("buffers", [])
    if not buffers:
        return errors + ["нет buffers[]"]
    declared = buffers[0].get("byteLength", -1)
    if declared > len(bin_chunk):
        errors.append(f"buffers[0].byteLength={declared} больше BIN ({len(bin_chunk)})")

    buffer_views = gltf.get("bufferViews", [])
    accessors = gltf.get("accessors", [])
    meshes = gltf.get("meshes", [])

    for i, view in enumerate(buffer_views):
        start = view.get("byteOffset", 0)
        length = view.get("byteLength", 0)
        if start + length > len(bin_chunk):
            errors.append(f"bufferViews[{i}] выходит за BIN")

    for i, acc in enumerate(accessors):
        comp = COMPONENT_SIZE.get(acc.get("componentType", 0), 0)
        count_per = COMPONENT_COUNT.get(acc.get("type", ""), 0)
        if not comp or not count_per:
            errors.append(f"accessors[{i}]: неизвестный componentType/type")
            continue
        stride = acc.get("byteStride") or comp * count_per
        view_index = acc.get("bufferView", 0)
        view_start = buffer_views[view_index].get("byteOffset", 0) if view_index < len(buffer_views) else 0
        need = acc.get("byteOffset", 0) + view_start + stride * max(0, acc.get("count", 0) - 1) + comp * count_per
        if need > len(bin_chunk):
            errors.append(f"accessors[{i}] выходит за BIN (нужно {need} байт)")

    for i, mesh in enumerate(meshes):
        for p, prim in enumerate(mesh.get("primitives", [])):
            attrs = prim.get("attributes", {})
            if "POSITION" not in attrs:
                errors.append(f"meshes[{i}].primitives[{p}]: нет атрибута POSITION")
                continue
            pos_acc = accessors[attrs["POSITION"]]
            vertex_count = pos_acc.get("count", 0)
            if "indices" in prim:
                idx_acc = accessors[prim["indices"]]
                max_index = idx_acc.get("count", 0)
                if max_index and vertex_count == 0:
                    errors.append(f"meshes[{i}].primitives[{p}]: индексы есть, вершин 0")
                # Проверяем сами значения индексов.
                idx_view = buffer_views[idx_acc.get("bufferView", 0)]
                base = idx_view.get("byteOffset", 0) + idx_acc.get("byteOffset", 0)
                comp = idx_acc.get("componentType")
                fmt = {5121: "B", 5123: "H", 5125: "I"}.get(comp)
                if fmt is None:
                    errors.append(f"meshes[{i}].primitives[{p}]: componentType индексов {comp}")
                else:
                    size = COMPONENT_SIZE[comp]
                    values = struct.unpack(
                        "<" + fmt * idx_acc["count"],
                        bin_chunk[base : base + size * idx_acc["count"]],
                    )
                    if values and max(values) >= vertex_count:
                        errors.append(
                            f"meshes[{i}].primitives[{p}]: индекс {max(values)} при {vertex_count} вершинах"
                        )

    for i, node in enumerate(gltf.get("nodes", [])):
        if "mesh" in node and node["mesh"] >= len(meshes):
            errors.append(f"nodes[{i}] ссылается на несуществующий mesh {node['mesh']}")

    errors.extend(_check_materials(gltf, len(bin_chunk)))
    return errors


def _check_materials(gltf: dict, bin_len: int) -> list[str]:
    """
    Целостность цепочки materials -> textures -> images -> bufferViews.
    Важно для .glb, собранных из glTF separate (см. convert_kaykit.py):
    там текстура вшита как bufferView вместо внешнего uri, и любую ошибку
    в индексах видно именно здесь.
    """
    errors: list[str] = []
    views = gltf.get("bufferViews", [])
    textures = gltf.get("textures", [])
    images = gltf.get("images", [])
    samplers = gltf.get("samplers", [])
    materials = gltf.get("materials", [])
    meshes = gltf.get("meshes", [])

    for i, image in enumerate(images):
        has_uri = "uri" in image
        has_view = "bufferView" in image
        if has_uri == has_view:
            errors.append(f"images[{i}]: должен быть ровно один из uri / bufferView")
            continue
        if has_view:
            if not image.get("mimeType"):
                errors.append(f"images[{i}]: bufferView без mimeType")
            view_index = image["bufferView"]
            if view_index >= len(views):
                errors.append(f"images[{i}]: bufferView {view_index} вне диапазона")
                continue
            view = views[view_index]
            if view.get("byteOffset", 0) + view.get("byteLength", 0) > bin_len:
                errors.append(f"images[{i}]: данные текстуры вне BIN-чанка")

    for i, texture in enumerate(textures):
        source = texture.get("source")
        if source is None or source >= len(images):
            errors.append(f"textures[{i}]: source {source} вне диапазона")
        if "sampler" in texture and texture["sampler"] >= len(samplers):
            errors.append(f"textures[{i}]: sampler {texture['sampler']} вне диапазона")

    def check_index(label: str, value, limit: int, what: str):
        if value is not None and value >= limit:
            return f"{label}: {what} {value} вне диапазона ({limit})"
        return None

    for i, material in enumerate(materials):
        pbr = material.get("pbrMetallicRoughness", {})
        for key, source in (
            ("baseColorTexture", pbr),
            ("metallicRoughnessTexture", pbr),
            ("normalTexture", material),
            ("occlusionTexture", material),
            ("emissiveTexture", material),
        ):
            entry = source.get(key)
            if entry is None:
                continue
            problem = check_index(f"materials[{i}].{key}", entry.get("index"), len(textures), "texture")
            if problem:
                errors.append(problem)

    for i, mesh in enumerate(meshes):
        for p, prim in enumerate(mesh.get("primitives", [])):
            problem = check_index(
                f"meshes[{i}].primitives[{p}]", prim.get("material"), len(materials), "material"
            )
            if problem:
                errors.append(problem)

    return errors


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    root = Path(sys.argv[1]).resolve()
    files = sorted(root.rglob("*.glb"))
    if not files:
        print(f"В {root} не найдено ни одного .glb")
        return 1

    bad = 0
    for path in files:
        errors = validate(path)
        if errors:
            bad += 1
            print(f"FAIL {path.relative_to(root)}")
            for error in errors:
                print(f"     - {error}")
    print(f"Проверено {len(files)} файлов, ошибок в {bad}.")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
