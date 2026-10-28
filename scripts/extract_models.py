#!/usr/bin/env python3
"""Распаковка 3D-моделей из 7z-архивов репозитория в assets/models/.

Использование:
    python3 scripts/extract_models.py

Архивы уже лежат в git, поэтому сами .glb в git не коммитятся
(assets/models/ в .gitignore) — этот скрипт воспроизводит их локально.
Требуется: pip install py7zr
"""
import os
import shutil
from pathlib import Path

import py7zr

ROOT = Path(__file__).resolve().parent.parent

JOBS = [
    (['ZOMBI.7z.001', 'ZOMBI.7z.002', 'ZOMBI.7z.003', 'ZOMBI.7z.004'], 'ZOMBI.glb', 'zombi.glb'),
    (['остров 1.7z.001', 'остров 1.7z.002'], 'остров 1.glb', 'island.glb'),
    (['персонаж 1.7z.001', 'персонаж 1.7z.002', 'персонаж 1.7z.003'], 'персонаж 1.glb', 'character.glb'),
]


def main() -> None:
    out = ROOT / 'assets' / 'models'
    out.mkdir(parents=True, exist_ok=True)
    for parts, inner, dst in JOBS:
        target = out / dst
        if target.exists():
            print(f'skip {dst} (уже есть)')
            continue
        merged = Path('/tmp') / dst.replace('.glb', '.7z')
        with open(merged, 'wb') as w:
            for p in parts:
                with open(ROOT / p, 'rb') as r:
                    shutil.copyfileobj(r, w)
        with py7zr.SevenZipFile(merged) as z:
            z.extract(targets=[inner], path='/tmp/x')
        shutil.move(os.path.join('/tmp/x', inner), target)
        merged.unlink(missing_ok=True)
        print(f'{dst}: {target.stat().st_size // 1048576} MB')


if __name__ == '__main__':
    main()
