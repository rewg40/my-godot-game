#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
organize_models.py — раскладка скачанных 3D-моделей (Kenney, CC0) по категориям.

Источник: https://github.com/shorepine/kenney , каталог 3d/,
паки: hexagon, nature, tower-defense, pirate.
Лицензия: CC0 1.0 — https://creativecommons.org/publicdomain/zero/1.0/

Запуск:
    python3 organize_models.py <путь_к_kenney/3d> <путь_к_папке_модели>

Скрипт копирует .glb и .png из исходных паков в категории папки `модели/`,
добавляя к имени префикс пака (чтобы файлы с одинаковыми именами из разных
паков не перезаписывали друг друга), и пишет machine-readable инвентарь
`модели/inventory.json`.
"""

from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

# Префикс имени файла по исходному паку.
PACK_PREFIX = {
    "hexagon": "hex",
    "nature": "nat",
    "tower-defense": "td",
    "pirate": "pir",
}

# Категория, куда попадает всё, что не подошло ни под одно правило.
FALLBACK_CATEGORY = "06_props_decor"

# Категории: (каталог, заголовок для README, правила).
# Правило = (regex по имени файла без расширения, пак или None = любой пак).
# Порядок категорий и порядок правил внутри имеют значение: первое совпадение побеждает.
CATEGORIES = [
    (
        "01_terrain_ground",
        "Местность — грунт, трава, песок, камень, склоны, дороги",
        [
            (r"^(grass|dirt|sand|stone)$", "hexagon"),
            (r"^(grass-hill|dirt-lumber|sand-desert|sand-rocks|grass-forest)$", "hexagon"),
            (r"^path-", "hexagon"),
            (r"^path_", "nature"),
            # ground_river* — это вода, они попадают в 02_islands.
            (r"^ground_(?!river)", "nature"),
            (r"^(patch-grass|patch-sand|patch-dirt|grass$)", "pirate"),
            (r"^(snow-)?detail-dirt", "tower-defense"),
            # Реки (tile-river-*) намеренно пропускаем — они попадают в 02_islands.
            (r"^(snow-)?tile(?!-river)(-|$)", "tower-defense"),
        ],
    ),
    (
        "02_islands",
        "Острова — основание острова, берег, вода и реки",
        [
            (r"^(water|river)", "hexagon"),
            (r"^(river|water|ground_river)", "nature"),
            (r"^(snow-)?tile-river-", "tower-defense"),
            (r"^hole$", "pirate"),
            (r"(island|lagoon|reef|atoll)", None),
        ],
    ),
    (
        "03_cliffs_rocks",
        "Скалы, утёсы, камни, пещеры, горы",
        [
            (r"^(cliff|rock|mountain|cave|stone)", "nature"),
            (r"^(stone|rock|mountain)", "hexagon"),
            (r"^rocks", "pirate"),
            (r"^(snow-)?detail-rocks", "tower-defense"),
        ],
    ),
    (
        "04_vegetation",
        "Растительность — деревья, пальмы, трава, кусты, цветы, пни",
        [
            (r"^(grass|foliage|hanging_moss|lily|stump)", "nature"),
            (r"^(unit-tree|grass-forest)$", "hexagon"),
            (r"^(snow-)?tile-tree", "tower-defense"),
            (r"^(snow-)?detail-tree", "tower-defense"),
            (r"^(snow-)?detail-crystal", "tower-defense"),
            (r"^(snow-)?tile-crystal$", "tower-defense"),
            (r"^(grass-plant|grass-patch)", "pirate"),
            (r"^(tree|palm|plant|bush|flower|crop|cactus|hedge|mushroom)", None),
        ],
    ),
    (
        "05_buildings_structures",
        "Постройки и конструкции — дома, доки, причалы, мосты, стены, башни",
        [
            (r"^(building|bridge)", "hexagon"),
            (r"^(unit-house|unit-mansion|unit-mill|unit-tower|unit-wall-tower)$", "hexagon"),
            (r"^(bridge|fence|tent|platform|statue|log|sign|pot)", "nature"),
            (r"^(wood-structure|snow-wood-structure)", "tower-defense"),
            (r"^(tower-round|tower-square|spawn)", "tower-defense"),
            (r"^(castle|structure|platform|mast|flag|tower|windmill|watermill)", "pirate"),
        ],
    ),
    (
        "06_props_decor",
        "Реквизит и декор — всё остальное (бочки, ящики, корабли, оружие, противники)",
        [],
    ),
]

CATEGORY_TITLES = {name: title for name, title, _ in CATEGORIES}


def match_category(stem: str, pack: str) -> str:
    """Возвращает каталог категории для модели `stem` из пака `pack`."""
    for dirname, _title, rules in CATEGORIES:
        for pattern, rule_pack in rules:
            if rule_pack is not None and rule_pack != pack:
                continue
            if re.search(pattern, stem):
                return dirname
    return FALLBACK_CATEGORY


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2

    src_root = Path(sys.argv[1]).resolve()
    dst_root = Path(sys.argv[2]).resolve()

    if not src_root.is_dir():
        print(f"Исходная папка не найдена: {src_root}", file=sys.stderr)
        return 1

    inventory: list[dict] = []
    textures = 0

    for pack, prefix in PACK_PREFIX.items():
        pack_dir = src_root / pack
        if not pack_dir.is_dir():
            print(f"Пропущен пак {pack}: нет каталога {pack_dir}")
            continue

        for path in sorted(pack_dir.rglob("*")):
            if not path.is_file():
                continue
            suffix = path.suffix.lower()

            if suffix == ".png":
                rel = path.relative_to(pack_dir)
                target = dst_root / "textures" / f"{prefix}_{'_'.join(rel.parts)}"
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, target)
                textures += 1
                continue

            if suffix != ".glb":
                continue

            category = match_category(path.stem, pack)
            target = dst_root / category / f"{prefix}_{path.stem}.glb"
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)

            inventory.append(
                {
                    "file": f"{category}/{target.name}",
                    "category": category,
                    "pack": pack,
                    "original_name": path.name,
                    "size_bytes": target.stat().st_size,
                }
            )

    inventory.sort(key=lambda item: (item["category"], item["file"]))

    per_category: dict[str, int] = {}
    for item in inventory:
        per_category[item["category"]] = per_category.get(item["category"], 0) + 1

    payload = {
        "source": "https://github.com/shorepine/kenney (каталог 3d/)",
        "license": "CC0 1.0 — https://creativecommons.org/publicdomain/zero/1.0/",
        "author": "Kenney — https://kenney.nl",
        "total_models": len(inventory),
        "total_textures": textures,
        "per_category": per_category,
        "models": inventory,
    }
    dst_root.mkdir(parents=True, exist_ok=True)
    (dst_root / "inventory.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    print(f"Моделей: {len(inventory)}, текстур: {textures}")
    for name in sorted(CATEGORY_TITLES):
        print(f"  {name:26s} {per_category.get(name, 0):4d}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
