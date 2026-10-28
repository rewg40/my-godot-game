#!/usr/bin/env python3
"""Сборка GLB-моделей зданий из чанков в assets/city_3d/.

Каждая модель разложена на бинарные чанки по 15 МБ (assets/city_3d/
<model>.glb.NNN.bin), потому что GitHub API не принимает файлы > 50 МБ.
Этот скрипт склеивает чанки обратно в .glb в assets/city_3d/.

Использование:
    python3 scripts/assemble_city_models.py [--suffix _assembled]

Файлы .glb в git не хранятся (модели воспроизводятся локально).
"""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHUNKS = ROOT / 'assets' / 'city_3d'

MODELS = ['ruined_building_2f', 'ruined_building_3f_a',
          'ruined_building_3f_b', 'ruined_building_3f_c']


def assemble(name: str, suffix: str = '') -> Path:
    parts = sorted(p for p in CHUNKS.glob(f'{name}.glb.[0-9][0-9][0-9].bin'))
    if not parts:
        print(f'skip {name}: нет чанков')
        return None
    out = CHUNKS / f'{name}{suffix}.glb'
    with open(out, 'wb') as w:
        for p in parts:
            w.write(p.read_bytes())
    print(f'{name}{suffix}.glb: {out.stat().st_size // 1048576} MB '
          f'из {len(parts)} чанков')
    return out


def main() -> int:
    suffix = ''
    if '--suffix' in sys.argv:
        i = sys.argv.index('--suffix')
        if i + 1 < len(sys.argv):
            suffix = sys.argv[i + 1]
    for name in MODELS:
        assemble(name, suffix)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())