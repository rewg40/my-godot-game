#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_inventory.py — строит `модели/inventory.json` по фактическому содержимому
папки: все .glb, их категория, размер, происхождение (скачано из пака Kenney
или сгенерировано) и исходное имя файла.

Запуск:
    python3 build_inventory.py <папка_модели>
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

PACK_BY_PREFIX = {
    "hex": "Kenney Hexagon Kit",
    "nat": "Kenney Nature Kit",
    "td": "Kenney Tower Defense Kit",
    "pir": "Kenney Pirate Kit",
    "kay": "KayKit Medieval Hexagon Pack",
}

CATEGORY_TITLES = {
    "01_terrain_ground": "Местность — грунт, трава, песок, камень, склоны, дороги",
    "02_islands": "Острова — основание острова, берег, вода и реки",
    "03_cliffs_rocks": "Скалы, утёсы, камни, пещеры, горы",
    "04_vegetation": "Растительность — деревья, пальмы, трава, кусты, цветы, пни",
    "05_buildings_structures": "Постройки и конструкции — дома, доки, причалы, мосты, стены, башни",
    "06_props_decor": "Реквизит и декор — бочки, ящики, корабли, оружие, противники",
}


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    root = Path(sys.argv[1]).resolve()

    models = []
    for path in sorted(root.rglob("*.glb")):
        category = path.parent.name
        prefix, _, rest = path.stem.partition("_")
        if path.stem.startswith("gen_"):
            origin = "generated"
            pack = "generate_islands.py"
            original = path.stem
        else:
            origin = "downloaded"
            pack = PACK_BY_PREFIX.get(prefix, prefix)
            # KayKit поставляется в формате glTF separate (.gltf + .bin),
            # остальные паки — уже .glb.
            source_ext = ".gltf" if pack == PACK_BY_PREFIX["kay"] else ".glb"
            original = f"{rest}{source_ext}"
        models.append(
            {
                "file": f"{category}/{path.name}",
                "category": category,
                "origin": origin,
                "pack": pack,
                "original_name": original,
                "size_bytes": path.stat().st_size,
            }
        )

    per_category: dict[str, int] = {}
    for item in models:
        per_category[item["category"]] = per_category.get(item["category"], 0) + 1

    textures = sorted(p.name for p in (root / "textures").glob("*")) if (root / "textures").is_dir() else []

    payload = {
        "description": "Инвентарь 3D-моделей местности и островов",
        "sources": {
            "downloaded": [
                {
                    "name": "Kenney",
                    "repository": "https://github.com/shorepine/kenney (каталог 3d/)",
                    "packs": ["Hexagon Kit", "Nature Kit", "Tower Defense Kit", "Pirate Kit"],
                    "author": "Kenney — https://kenney.nl",
                    "license": "CC0 1.0 — https://creativecommons.org/publicdomain/zero/1.0/",
                    "prefixes": ["hex_", "nat_", "td_", "pir_"],
                },
                {
                    "name": "KayKit",
                    "repository": "https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0",
                    "packs": ["Medieval Hexagon Pack 1.0"],
                    "author": "Kay Lousberg — https://www.kaylousberg.com",
                    "license": "CC0 1.0 — https://creativecommons.org/publicdomain/zero/1.0/",
                    "prefixes": ["kay_"],
                    "note": (
                        "Конвертировано из glTF separate (.gltf + .bin + атлас) в "
                        "самодостаточный .glb скриптом scripts/convert_kaykit.py; "
                        "геометрия не изменялась."
                    ),
                },
            ],
            "generated": {
                "script": "scripts/generate_islands.py",
                "license": "CC0 1.0 (та же, что и у остального контента папки)",
            },
        },
        "categories": CATEGORY_TITLES,
        "total_models": len(models),
        "total_textures": len(textures),
        "per_category": per_category,
        "textures": textures,
        "models": models,
    }

    out = root / "inventory.json"
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"{out.relative_to(root.parent)}: моделей {len(models)}, текстур {len(textures)}")
    for name in sorted(CATEGORY_TITLES):
        if per_category.get(name):
            print(f"  {name:26s} {per_category[name]:4d}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
