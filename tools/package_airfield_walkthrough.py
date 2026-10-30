"""Create a small self-contained Godot project for viewing the airfield.

The archive is a separate inspection scene, not the full survival game, and
uses its own project.godot so it can never overwrite the main game's save.
No generated archive is stored in the repository.
"""
from __future__ import annotations

import argparse
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
README = """# Аэродром — отдельный проект для осмотра

Это не полная игра и не новое сохранение. Здесь находится отдельная площадка
900 × 350 м с ВПП 700 × 28 м и персонажем для прогулки. Основной остров,
инвентарь, заражённые, спавн и сюжет в этой сборке не подключены.

1. Распакуйте архив в отдельную папку.
2. Откройте Godot 4.3 или новее → «Импортировать» → выберите в этой папке
   `project.godot` и дождитесь импорта.
3. Нажмите F5. WASD — движение, Shift — бег, ПКМ и мышь — поворот камеры,
   колесо — масштаб, Esc — закрыть просмотр.

`scenes/airfield_full.tscn` — редактируемая сцена площадки;
`assets/models/airport_kit/blender/airport_kit.blend` — отдельные модели
в Blender. При отсутствии Blender импорт в Godot не требуется: в той папке
лежит `.gdignore`. Маркеры заражённых и предметов пока не запускают логику.

Сцена пересобирается скриптом `tools/generate_airfield_site.py`, который
перезапишет ручные правки этой сцены. Полный генератор отдельных GLB в этот
мини-проект не включён; редактировать исходные модели можно в Blender или в
полной версии репозитория. Источники и условия использования находятся в
`docs/ASSET_CREDITS.md` и README набора.
"""

FILES = [
    "scenes/airfield_full.tscn", "scenes/airfield_walkthrough.tscn",
    "scripts/airfield_preview.gd", "scripts/player.gd", "scripts/model_3d.gd",
    "scripts/ui_style.gd", "scripts/mesh_cleanup.gd", "shaders/survivor_clothes.gdshader",
    "Bloody Baseball Bat with Nails.glb", "assets/models/hero/user_hero.glb",
    "assets/environment/textures/grass_short.jpg", "assets/environment/textures/dirt_diff_1k.jpg",
    "assets/fonts/DejaVuSans.ttf", "assets/fonts/DejaVuSans-Bold.ttf", "assets/fonts/LICENSE-DejaVu.txt",
    "docs/ASSET_CREDITS.md", "docs/AIRFIELD_SITE_RU.md", "tools/generate_airfield_site.py",
    "tools/render_airfield_site.py", "tools/prepare_airfield_apron_texture.py", "tools/package_airfield_walkthrough.py",
    "tests/airfield_package_test.gd", "tests/validate_airfield_site.py",
]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path, help="destination ZIP (outside the repository is recommended)")
    args = parser.parse_args()
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    original = 'run/main_scene="res://scenes/main.tscn"'
    assert original in project
    project = project.replace(original, 'run/main_scene="res://scenes/airfield_walkthrough.tscn"')
    project = project.replace('config/name="Осколки цивилизации — Приют"', 'config/name="Аэродром — отдельный осмотр"')
    kit_files = sorted(p for p in (ROOT / "assets/models/airport_kit").rglob("*")
                       if p.is_file() and not p.name.endswith(".import"))
    paths = [ROOT / name for name in FILES] + kit_files
    assert all(p.is_file() for p in paths)
    assert len(set(paths)) == len(paths)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(args.output, "w", compression=ZIP_DEFLATED, compresslevel=6) as archive:
        archive.writestr("project.godot", project)
        archive.writestr("README.md", README)
        for path in paths:
            archive.write(path, path.relative_to(ROOT).as_posix())
    with ZipFile(args.output) as archive:
        bad = archive.testzip()
        assert bad is None, f"CRC failure: {bad}"
        names = archive.namelist()
        assert len(names) == len(set(names))
        assert "assets/models/airport_kit/blender/.gdignore" in names
        assert sum(name.endswith(".glb") and "/airport_kit/glb/" in name for name in names) == 32
        print(f"AIRFIELD PACKAGE CREATED: {args.output} ({len(names)} files, {args.output.stat().st_size / 1048576:.2f} MiB)")


if __name__ == "__main__":
    main()
