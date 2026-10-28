#!/usr/bin/env python3
"""Удаляет битый ключ "uri": null из секции images всех GLB района руин.

Blender-экспорт оставил в images одновременно bufferView и uri=null.
Godot превращает null в строку '<null>' и пытается открыть файл, из-за
чего встроенные текстуры пропускаются и здания грузятся серыми.
По спецификации glTF 2.0 uri и bufferView взаимоисключающи: удаляем uri,
остаётся чистая загрузка JPEG из бинарного чанка.

Заодно проверяет, что данные в bufferView — валидные JPEG (FFD8) или PNG.
"""
import json
import struct
import sys
from pathlib import Path

MODELS_DIR = Path(__file__).resolve().parent.parent / "assets" / "city_3d"


def fix_glb(path: Path) -> None:
    raw = path.read_bytes()
    magic, version, length = struct.unpack("<III", raw[:12])
    if magic != 0x46546C67:
        raise SystemExit(f"{path.name}: не glTF-контейнер")

    json_len, json_type = struct.unpack("<II", raw[12:20])
    if json_type != 0x4E4F534A:  # 'JSON'
        raise SystemExit(f"{path.name}: JSON-чанк не найден")
    doc = json.loads(raw[20 : 20 + json_len])

    images = doc.get("images", [])
    fixed = 0
    report = []
    for img in images:
        if img.get("uri") is None and "bufferView" in img:
            img.pop("uri")
            fixed += 1
        bv = doc["bufferViews"][img["bufferView"]]
        offset = bv.get("byteOffset", 0)
        blob = raw[
            20 + json_len + 8 + offset : 20 + json_len + 8 + offset + bv["byteLength"]
        ]
        kind = "jpeg" if blob[:2] == b"\xff\xd8" else "png" if blob[:4] == b"\x89PNG" else "???"
        report.append(f"    {img.get('name', '?')}: {len(blob)//1024} КБ {kind}")

    if fixed == 0:
        print(f"{path.name}: uri=null не найдены, пропускаю")
        return

    # Перепаковываем контейнер: JSON-чанк заново, бинарный чанк нетронут
    # (вместе со своим 8-байтовым заголовком 'BIN\0' — иначе Godot падает).
    bin_chunk = raw[20 + json_len :]
    new_json = json.dumps(doc, separators=(",", ":")).encode()
    pad = (4 - len(new_json) % 4) % 4
    new_json += b" " * pad
    total = 12 + 8 + len(new_json) + len(bin_chunk)
    out = (
        struct.pack("<III", 0x46546C67, 2, total)
        + struct.pack("<II", len(new_json), 0x4E4F534A)
        + new_json
        + bin_chunk
    )
    tmp = path.with_suffix(".tmp")
    tmp.write_bytes(out)
    tmp.replace(path)
    print(f"{path.name}: удалено uri=null: {fixed}, размер {length//1024//1024} -> {total//1024//1024} МБ")
    for line in report:
        print(line)


if __name__ == "__main__":
    glbs = sorted(MODELS_DIR.glob("*.glb"))
    if not glbs:
        raise SystemExit("GLB не найдены")
    for glb in glbs:
        fix_glb(glb)
    print("ГОТОВО")
