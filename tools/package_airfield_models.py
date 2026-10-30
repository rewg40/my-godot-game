#!/usr/bin/env python3
"""Create a distributable archive of the airfield models and their previews."""
from __future__ import annotations

import argparse
import re
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
KIT = ROOT / "assets/models/airport_kit"
README = """# Модели аэродрома и картинки-превью

В архиве находятся 32 отдельные модели GLB, исходная сцена Blender,
восемь сцен Godot с упрощёнными коллизиями и отдельная собранная сцена
аэродрома размером 900 × 350 м. Текстуры GLB и Blender-файла встроены.

Файлы `PREVIEW_MODELS.jpg` и `PREVIEW_AIRFIELD.jpg` в корне архива —
рендеры моделей и расположения аэродрома, созданные в Blender, не скриншоты
игры. Дополнительные изображения интерьеров и общий вид находятся в
`assets/models/airport_kit/`.

## Открыть модели

- Blender 4.3 или новее: откройте
  `assets/models/airport_kit/blender/airport_kit.blend`.
- Отдельные объекты: файлы `assets/models/airport_kit/glb/*.glb`.
- Godot 4.3: скопируйте папки `assets/` и `scenes/` из архива в корень
  своего проекта Godot, сохраняя пути, и дождитесь импорта. Не перезаписывайте
  одноимённые файлы проекта без резервной копии. Основные постройки с
  коллизиями находятся в `assets/models/airport_kit/godot_scenes/`.
- Полную расстановку можно открыть в редакторе Godot как сцену
  `scenes/airfield_full.tscn`. Это именно сцена для редактирования, без
  игрового режима, героя и освещения; она не интегрирована в основной остров.
  Отдельные GLB импортируются без коллизий, а маркеры — без игровой логики.

Файл `assets/models/airport_kit/README.md` содержит описание моделей и
источников; авторство и лицензии также указаны в `docs/ASSET_CREDITS.md`.
"""


def build_archive(output: Path) -> None:
    files = sorted(path for path in KIT.rglob("*") if path.is_file() and not path.name.endswith(".import"))
    files.extend([
        ROOT / "scenes/airfield_full.tscn",
        ROOT / "assets/environment/textures/grass_short.jpg",
        ROOT / "docs/ASSET_CREDITS.md",
    ])
    output.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(output, "w", compression=ZIP_DEFLATED, compresslevel=6) as archive:
        archive.writestr("README_RU.md", README)
        archive.write(KIT / "airport_kit_preview.jpg", "PREVIEW_MODELS.jpg")
        archive.write(KIT / "airfield_site_campus.jpg", "PREVIEW_AIRFIELD.jpg")
        for path in files:
            assert path.is_file(), f"Missing file: {path}"
            archive.write(path, path.relative_to(ROOT).as_posix())
    with ZipFile(output) as archive:
        names = archive.namelist()
        available = set(names)
        assert len(names) == len(available), "Duplicate archive paths"
        assert archive.testzip() is None, "ZIP CRC failure"
        assert sum(name.startswith("assets/models/airport_kit/glb/") and name.endswith(".glb") for name in names) == 32
        assert sum(name.startswith("assets/models/airport_kit/godot_scenes/") and name.endswith(".tscn") for name in names) == 8
        assert "assets/models/airport_kit/blender/.gdignore" in available
        assert "assets/models/airport_kit/blender/airport_kit.blend" in available
        for scene in (name for name in names if name.endswith(".tscn")):
            for resource in re.findall(r'path="res://([^\"]+)"', archive.read(scene).decode("utf-8")):
                assert resource in available, f"Missing {resource} referenced by {scene}"
        for preview in ("PREVIEW_MODELS.jpg", "PREVIEW_AIRFIELD.jpg"):
            image = archive.read(preview)
            assert image.startswith(b"\xff\xd8") and image.endswith(b"\xff\xd9"), f"Invalid JPEG: {preview}"
        print(f"AIRFIELD MODEL ARCHIVE CREATED: {output} ({len(names)} files, {output.stat().st_size / 1048576:.2f} MiB)")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path, help="destination ZIP (outside the repository is recommended)")
    args = parser.parse_args()
    build_archive(args.output)


if __name__ == "__main__":
    main()
