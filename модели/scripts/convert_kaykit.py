#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
convert_kaykit.py — конвертирует паки KayKit (glTF separate: .gltf + .bin + атлас)
в самодостаточные .glb и раскладывает их по категориям папки «модели/».

Запуск:
    python3 convert_kaykit.py <путь_к_Assets/gltf> <путь_к_папке_модели>

Что делает с каждым .gltf:
  1. читает его .bin (геометрия) и подкладывает его в единый BIN-чанк GLB;
  2. читает текстуру-атлас из той же папки и тоже вшивает её в BIN-чанк,
     заменяя images[i].uri на images[i].bufferView — так каждый .glb становится
     ОДНИМ файлом без внешних зависимостей (атлас у пака один и весит ~15 КБ,
     поэтому дублирование почти ничего не стоит);
  3. раскладывает по категории (см. CATEGORY_RULES) и пишет с префиксом kay_.

Только стандартная библиотека Python.
"""

from __future__ import annotations

import json
import re
import struct
import sys
from pathlib import Path

PACK_NAME = "KayKit Medieval Hexagon Pack"
PREFIX = "kay"

# Правила категорий: (regex по имени модели, regex по исходному относительному
# пути или None), проверяются ПЕРВЫМ СОВПАДЕНИЕМ. Порядок важен: например
# mountain_A_grass_trees — это гора, а не дерево, поэтому скалы проверяются
# раньше растительности, а buildings — раньше всего остального.
CATEGORY_RULES = [
    # Сначала — маршрутизация по папке пака: сам автор разложил props и
    # buildings, спорить с этим незачем.
    (r".*", r"^buildings/", "05_buildings_structures"),
    (r"(^|_)flag", r"^decoration/props/", "05_buildings_structures"),  # флаги — как в Pirate Kit
    (r".*", r"^decoration/props/", "06_props_decor"),
    # Дальше — по имени: вода/берега/реки, потом рельеф, и только потом растения
    # (hills_A_trees — это холм, а не дерево; mountain_A_grass_trees — гора).
    (r"(^|_)(coast|river|water|waterlily|waterplant|lake|sea|bridge)(_|$)", None, "02_islands"),
    (r"(^|_)(rock|rocks|mountain|cliff|boulder|stone)(_|$)", None, "03_cliffs_rocks"),
    (r"(^|_)(hill|hills|terrain|ground|grass|dirt|sand|snow|road)(_|$)", None, "01_terrain_ground"),
    (r"(^|_)(tree|trees|bush|shrub|plant|flower|mushroom)(_|$)", None, "04_vegetation"),
    (r"^cloud", None, "06_props_decor"),
    # Оставшееся из tiles/ — базовые тайлы местности.
    (r".*", r"^tiles/", "01_terrain_ground"),
]
FALLBACK_CATEGORY = "06_props_decor"

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
JPEG_MAGIC = b"\xff\xd8\xff"


def categorize(stem: str, rel: str) -> str:
    for name_re, path_re, category in CATEGORY_RULES:
        if path_re is not None and not re.search(path_re, rel):
            continue
        if re.search(name_re, stem):
            return category
    return FALLBACK_CATEGORY


def _align4(length: int) -> int:
    return length + ((-length) % 4)


def convert_one(gltf_path: Path, gltf_root: Path) -> tuple[str, str, bytes] | None:
    """Возвращает (категория, имя_файла, байты_glb) либо None при пропуске."""
    doc = json.loads(gltf_path.read_text(encoding="utf-8"))
    folder = gltf_path.parent
    rel = gltf_path.relative_to(gltf_root).as_posix()

    # --- 1. буферы геометрии -> единый бинарный чанк ---
    buffers = doc.get("buffers", [])
    if not buffers:
        return None
    blob = bytearray()
    buffer_offsets = []
    for buf in buffers:
        uri = buf.get("uri")
        if uri:
            data = (folder / uri).read_bytes()
        else:
            # Буфер уже встроен (data: URI) — не ожидаем для этого пака.
            data = b""
        buffer_offsets.append(len(blob))
        blob += data
        pad = _align4(len(data)) - len(data)
        blob += b"\x00" * pad

    shifts = [offset for offset in buffer_offsets]
    if any(shift != 0 for shift in shifts):
        # Сдвиг только у 2-го и далее буфера; у первого offset 0 и всё совпадает.
        for view in doc.get("bufferViews", []):
            view["byteOffset"] = view.get("byteOffset", 0) + shifts[view.get("buffer", 0)]
            view["buffer"] = 0

    # --- 2. текстуры: uri -> bufferView внутри того же чанка ---
    for image in doc.get("images", []):
        uri = image.get("uri")
        if not uri or uri.startswith("data:"):
            continue
        data = (folder / uri).read_bytes()
        mime = "image/png" if data.startswith(PNG_MAGIC) else "image/jpeg"
        offset = len(blob)
        blob += data
        pad = _align4(len(data)) - len(data)
        blob += b"\x00" * pad
        doc.setdefault("bufferViews", []).append(
            {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        )
        image["bufferView"] = len(doc["bufferViews"]) - 1
        image["mimeType"] = mime
        image.pop("uri", None)

    doc["buffers"] = [{"byteLength": len(blob)}]

    # --- 3. самопроверка: всё должно влезать в чанк ---
    length = len(blob)
    for i, view in enumerate(doc["bufferViews"]):
        start, size = view.get("byteOffset", 0), view["byteLength"]
        if start % 4 or start + size > length:
            raise AssertionError(f"{gltf_path.name}: bufferViews[{i}] вне буфера")
    for i, acc in enumerate(doc.get("accessors", [])):
        view = doc["bufferViews"][acc["bufferView"]]
        comp_size = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}[acc["componentType"]]
        count_per = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[acc["type"]]
        stride = view.get("byteStride") or comp_size * count_per
        need = view["byteOffset"] + acc.get("byteOffset", 0) + stride * (acc["count"] - 1) + comp_size * count_per
        if need > length:
            raise AssertionError(f"{gltf_path.name}: accessors[{i}] вне буфера")

    doc.setdefault("asset", {})["generator"] = "convert_kaykit.py (my-godot-game)"

    # --- 4. упаковка в GLB ---
    json_bytes = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * (_align4(len(json_bytes)) - len(json_bytes))
    bin_bytes = bytes(blob)
    total = 12 + 8 + len(json_bytes) + 8 + len(bin_bytes)
    return (
        categorize(gltf_path.stem, rel),
        gltf_path.stem,
        struct.pack("<4sII", b"glTF", 2, total)
        + struct.pack("<I4s", len(json_bytes), b"JSON")
        + json_bytes
        + struct.pack("<I4s", len(bin_bytes), b"BIN\x00")
        + bin_bytes,
    )


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    gltf_root = Path(sys.argv[1]).resolve()
    models_dir = Path(sys.argv[2]).resolve()
    if not gltf_root.is_dir():
        print(f"Каталог gltf не найден: {gltf_root}", file=sys.stderr)
        return 1

    files = sorted(gltf_root.rglob("*.gltf"))
    if not files:
        print(f"В {gltf_root} нет ни одного .gltf", file=sys.stderr)
        return 1

    written: dict[str, str] = {}
    per_category: dict[str, int] = {}
    skipped: list[str] = []

    for path in files:
        result = convert_one(path, gltf_root)
        if result is None:
            skipped.append(path.name)
            continue
        category, stem, data = result
        rel = path.relative_to(gltf_root).as_posix()
        # Имена вида tiles/rivers/hex_river_A.gltf и
        # tiles/rivers/waterless/hex_river_A.gltf совпадают, хотя модели разные:
        # версии без воды помечаем суффиксом.
        if "waterless" in path.parent.parts and not stem.endswith("_waterless"):
            stem += "_waterless"
        name = f"{PREFIX}_{stem}.glb"
        if name in written:
            # На всякий случай разбираем коллизию именем родительской папки.
            stem_dir = path.parent.name
            name = f"{PREFIX}_{stem}_{stem_dir}.glb"
        target = models_dir / category / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        written[name] = category
        per_category[category] = per_category.get(category, 0) + 1

    print(f"Конвертировано {len(written)} моделей (пропущено {len(skipped)}) из {PACK_NAME}")
    for category in sorted(per_category):
        print(f"  {category:26s} {per_category[category]:4d}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
