#!/usr/bin/env python3
"""Распаковка 3D-моделей из разрезных архивов репозитория в assets/models.

В корне репозитория лежат архивы вида ``ZOMBI.7z.001``, ``остров 1.7z.001``
и ``персонаж 1.7z.001`` — так модели обошли лимит GitHub в 100 МБ на файл.
Скрипт склеивает части, распаковывает GLB и переименовывает их в имена,
которые ждёт проект:

    ZOMBI.7z.*      -> assets/models/zombie.glb
    остров 1.7z.*   -> assets/models/island.glb
    персонаж 1.7z.* -> assets/models/character.glb

Дополнительно можно скопировать точки растительности из репозитория ассетов:

    python tools/unpack_assets.py --assets-repo "D:/my games/Godot/Пепел и Звёзды"

Требуется пакет py7zr:  python -m pip install py7zr
"""
from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
MODELS = PROJECT / "assets" / "models"
DATA = PROJECT / "assets" / "data"

# базовое имя архива (без .001) -> (имя GLB внутри архива, имя файла в проекте)
ARCHIVES = {
    "ZOMBI.7z": ("ZOMBI.glb", "zombie.glb"),
    "остров 1.7z": ("остров 1.glb", "island.glb"),
    "персонаж 1.7z": ("персонаж 1.glb", "character.glb"),
}

VEGETATION_NAME = "растительность_точки.json"


def find_parts(repo: Path, base: str) -> list[Path]:
    """Собирает части разрезанного архива по возрастанию номера."""
    parts = sorted(repo.glob(base + ".*[0-9][0-9][0-9]"))
    return [p for p in parts if p.suffix[1:].isdigit()]


def merge_parts(parts: list[Path]) -> Path:
    handle, name = tempfile.mkstemp(suffix=".7z")
    Path(name).unlink(missing_ok=True)
    with open(name, "wb") as target:
        for part in parts:
            with open(part, "rb") as source:
                shutil.copyfileobj(source, target, length=1024 * 1024)
    return Path(name)


def extract(archive: Path, destination: Path) -> None:
    try:
        import py7zr  # type: ignore
    except ImportError:
        print("Нужен пакет py7zr:  python -m pip install py7zr")
        raise SystemExit(2)
    with py7zr.SevenZipFile(str(archive)) as zf:
        zf.extractall(path=str(destination))


def unpack_models(repo: Path) -> int:
    MODELS.mkdir(parents=True, exist_ok=True)
    done = 0
    for base, (inner, out_name) in ARCHIVES.items():
        parts = find_parts(repo, base)
        if not parts:
            print(f"[пропуск] нет частей архива «{base}.001»")
            continue
        target = MODELS / out_name
        if target.exists():
            print(f"[уже есть] {target.relative_to(PROJECT)}")
            done += 1
            continue
        print(f"[склейка] {base}: {len(parts)} частей, {sum(p.stat().st_size for p in parts) // (1024 * 1024)} МБ")
        merged = merge_parts(parts)
        try:
            with tempfile.TemporaryDirectory() as tmp:
                extract(merged, Path(tmp))
                source = Path(tmp) / inner
                if not source.exists():
                    candidates = list(Path(tmp).glob("*.glb"))
                    source = candidates[0] if candidates else source
                if not source.exists():
                    print(f"[ошибка] внутри архива нет {inner}")
                    continue
                shutil.move(str(source), str(target))
                print(f"[готово] {target.relative_to(PROJECT)} "
                      f"({target.stat().st_size // (1024 * 1024)} МБ)")
                done += 1
        finally:
            merged.unlink(missing_ok=True)
    return done


def copy_vegetation(repo_assets: Path) -> None:
    candidate = repo_assets / "остров" / VEGETATION_NAME
    if not candidate.exists():
        found = list(repo_assets.rglob(VEGETATION_NAME))
        candidate = found[0] if found else candidate
    if not candidate.exists():
        print(f"[пропуск] не найдено «{VEGETATION_NAME}» в {repo_assets}")
        return
    DATA.mkdir(parents=True, exist_ok=True)
    target = DATA / "vegetation_points.json"
    shutil.copyfile(candidate, target)
    print(f"[готово] {target.relative_to(PROJECT)} ({target.stat().st_size // (1024 * 1024)} МБ)")


def main() -> int:
    parser = argparse.ArgumentParser(description="Распаковка ассетов «Пепла и Звёзд»")
    parser.add_argument("--repo", default=str(PROJECT.parent),
                        help="каталог с архивами .7z.001 (по умолчанию — корень этого репозитория)")
    parser.add_argument("--assets-repo", default="",
                        help="локальная копия репозитория pepel-i-zvezdy с точками растительности")
    args = parser.parse_args()

    count = unpack_models(Path(args.repo))
    if args.assets_repo:
        copy_vegetation(Path(args.assets_repo))

    print()
    if count == 0:
        print("Модели не распакованы — игра всё равно запустится на процедурных.")
    else:
        print("Готово. Откройте проект в Godot: он импортирует GLB при первом запуске.")
    print("Файлы моделей намеренно не попадают в git (см. .gitignore).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
