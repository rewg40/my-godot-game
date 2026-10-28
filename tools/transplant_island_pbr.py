#!/usr/bin/env python3
"""Пересаживает PBR-карты normal + metallicRoughness из старого user_island.glb
(d1da09e, 3 встроенных JPEG) в новый (0e2ae32, только albedo "grass").

Новую геометрию (улучшенный рельеф) и новый albedo не трогаем. JPEG старых
карт переносится байт-в-байт: GLB пересобирается — к BIN-чанку добавляются
данные, в JSON добавляются bufferViews, images, textures, а в материал —
ссылки normalTexture и pbrMetallicRoughness.metallicRoughnessTexture.

UV-развёртка между экспортами не менялась (правился только рельеф),
поэтому старые карты остаются валидными для новой сетки.

Запуск: git checkout предыдущей версии острова в /tmp/old_island.glb,
затем python3 tools/transplant_island_pbr.py
"""
import json
import struct
from pathlib import Path

GLB = Path(__file__).resolve().parent.parent / "assets/models/environment/user_island.glb"
OLD = Path("/tmp/old_island.glb")


def read_chunks(path: Path):
    raw = path.read_bytes()
    magic, version, length = struct.unpack("<III", raw[:12])
    assert magic == 0x46546C67, "не glTF"
    jlen, jtype = struct.unpack("<II", raw[12:20])
    doc = json.loads(raw[20 : 20 + jlen])
    bin_data = raw[28 + jlen :]
    return doc, bin_data


def main() -> None:
    doc, bin_data = read_chunks(GLB)
    old_doc, old_bin = read_chunks(OLD)

    old_imgs = old_doc.get("images", [])
    idx_normal = next(i for i, im in enumerate(old_imgs) if "normal" in (im.get("name") or ""))
    idx_mr = next(i for i, im in enumerate(old_imgs) if "metallic" in (im.get("name") or ""))

    def blob(src_doc, src_bin, img_index: int) -> bytes:
        bv = src_doc["bufferViews"][src_doc["images"][img_index]["bufferView"]]
        off = bv.get("byteOffset", 0)
        return src_bin[off : off + bv["byteLength"]]

    normal_jpg = blob(old_doc, old_bin, idx_normal)
    mr_jpg = blob(old_doc, old_bin, idx_mr)
    print(f"old normal: {len(normal_jpg)//1024} КБ, old mr: {len(mr_jpg)//1024} КБ")

    bin_len = len(bin_data)

    def aligned(n: int) -> int:
        return (n + 3) & ~3

    off_normal = aligned(bin_len)
    off_mr = aligned(off_normal + len(normal_jpg))
    # Хвост: паддинг до off_normal, затем сами JPEG-блока, между ними паддинг.
    new_bin = (
        bin_data
        + b"\x00" * (off_normal - bin_len)
        + normal_jpg
        + b"\x00" * (off_mr - off_normal - len(normal_jpg))
        + mr_jpg
    )

    bv_len = len(doc["bufferViews"])
    doc["bufferViews"].append({"buffer": 0, "byteOffset": off_normal, "byteLength": len(normal_jpg)})
    doc["bufferViews"].append({"buffer": 0, "byteOffset": off_mr, "byteLength": len(mr_jpg)})
    img_len = len(doc.get("images", []))
    doc.setdefault("images", []).append(
        {"bufferView": bv_len, "mimeType": "image/jpeg", "name": "texture_pbr_20250901_normal"}
    )
    doc["images"].append(
        {
            "bufferView": bv_len + 1,
            "mimeType": "image/jpeg",
            "name": "texture_pbr_20250901_metallic-roughness",
        }
    )
    # Материалы ссылаются на текстуры, а не напрямую на изображения:
    # добавляем записи textures[source] для двух новых карт.
    doc.setdefault("textures", []).append({"source": img_len})
    doc["textures"].append({"source": img_len + 1})

    material = doc["materials"][0]
    material["normalTexture"] = {"index": img_len}
    material.setdefault("pbrMetallicRoughness", {})[
        "metallicRoughnessTexture"
    ] = {"index": img_len + 1}
    print("материал обновлён:", material.get("name"))

    new_json = json.dumps(doc, separators=(",", ":")).encode()
    new_json += b" " * ((4 - len(new_json) % 4) % 4)
    total = 12 + 8 + len(new_json) + 8 + len(new_bin)
    out = (
        struct.pack("<III", 0x46546C67, 2, total)
        + struct.pack("<II", len(new_json), 0x4E4F534A)
        + new_json
        + struct.pack("<II", len(new_bin), 0x004E4942)
        + new_bin
    )
    tmp = GLB.with_suffix(".tmp")
    tmp.write_bytes(out)
    tmp.replace(GLB)
    print(f"размер: {len(out)//1024//1024} МБ (было {bin_len//1024//1024} МБ)")


if __name__ == "__main__":
    main()
