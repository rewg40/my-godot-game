#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_winding.py — проверка ориентации граней у СГЕНЕРИРОВАННЫХ моделей
(файлы gen_*.glb). Требует trimesh (+ networkx/scipy для разбора на компоненты):

    python3 -m venv .venv && .venv/bin/pip install trimesh networkx scipy
    .venv/bin/python модели/scripts/verify_winding.py модели

Что проверяется и почему именно так:

* Замкнутый компонент (остров, гексагональный тайл):
  watertight == True  И  volume > 0  И  is_winding_consistent == True.
  Для замкнутого связного меша согласованная ориентация даёт |объём|,
  а знак объёма показывает, куда смотрят нормали: положительный — наружу.
  Тест «нормаль от центра масс наружу» здесь НЕ применяется: острова
  вогнутые (склоны, кратер, лагуна), и у части граней нормаль legitimately
  смотрит к центру масс — такой тест даёт ложные срабатывания.

* Открытая поверхность (gen_terrain_*.glb): ny > 0 у каждой грани.
  Знаковый объём для незамкнутой поверхности смысла не имеет.
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    import trimesh
except ImportError:  # pragma: no cover
    print("Нужен trimesh: pip install trimesh networkx scipy", file=sys.stderr)
    raise SystemExit(2)


def check_file(path: Path) -> list[str]:
    problems: list[str] = []
    scene = trimesh.load(str(path), force="scene")
    if not scene.geometry:
        return [f"{path.name}: в файле нет геометрии"]
    mesh = trimesh.util.concatenate(tuple(scene.geometry.values()))

    if path.name.startswith("gen_terrain_"):
        down = int((mesh.face_normals[:, 1] <= 0).sum())
        if down:
            problems.append(f"{down} граней смотрят вниз из {len(mesh.faces)}")
        return problems

    components = mesh.split(only_watertight=False)
    for i, comp in enumerate(components):
        label = f"{path.name}[{i}]" if len(components) > 1 else path.name
        if not comp.is_watertight:
            problems.append(f"{label}: компонент не замкнут — ориентацию проверить нельзя")
        if not comp.is_winding_consistent:
            problems.append(f"{label}: ориентация граней несогласована")
        if comp.volume <= 0:
            problems.append(f"{label}: объём {comp.volume:.2f} <= 0 — нормали внутрь")
    return problems


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    root = Path(sys.argv[1]).resolve()
    files = sorted(root.rglob("gen_*.glb"))
    if not files:
        print(f"В {root} не найдено gen_*.glb")
        return 1

    bad = 0
    for path in files:
        problems = check_file(path)
        status = "FAIL" if problems else "OK  "
        scene = trimesh.load(str(path), force="scene")
        mesh = trimesh.util.concatenate(tuple(scene.geometry.values()))
        print(f"{status} {path.relative_to(root)}  граней={len(mesh.faces)}")
        for problem in problems:
            print(f"       - {problem}")
        bad += bool(problems)

    print(f"Проверено {len(files)} файлов, с проблемами {bad}.")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
