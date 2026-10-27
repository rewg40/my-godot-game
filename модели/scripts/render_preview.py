#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
render_preview.py — рисует PNG-превью сгенерированных моделей (gen_*.glb).

Нужны trimesh + matplotlib:
    python3 -m venv .venv && .venv/bin/pip install trimesh matplotlib
    .venv/bin/python модели/scripts/render_preview.py модели модели/preview.png

Рендер намеренно простой (мягкий шейдинг по нормали + отрисовка граней
от дальних к ближним), он нужен как визуальная проверка: сразу видно
дыры в юбке острова и неверный масштаб. Тёмные «кляксы» — известное
ограничение painter's algorithm на выпуклых формах, а НЕ дефект моделей:
геометрию проверяют validate_glb.py и verify_winding.py.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
import trimesh
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.collections import PolyCollection  # noqa: E402

TITLES = {
    "gen_terrain_large": "Равнина 64×64 м",
    "gen_terrain_small": "Чанк 32×32 м",
    "gen_hex_tiles": "Гексагональные тайлы",
    "gen_island_a": "Остров с пляжем",
    "gen_island_b": "Вулкан с кратером",
    "gen_atoll": "Атолл с лагуной",
    "gen_rock_islet": "Скалистый островок",
    "gen_island_cluster": "Архипелаг",
}


def project(mesh: trimesh.Trimesh, yaw: float, pitch: float):
    """Поворот вокруг Y, затем вокруг X; возвращает (x, y, глубина)."""
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)
    v = mesh.vertices
    x1 = v[:, 0] * cy + v[:, 2] * sy
    z1 = -v[:, 0] * sy + v[:, 2] * cy
    y2 = v[:, 1] * cp - z1 * sp
    z2 = v[:, 1] * sp + z1 * cp
    return x1, y2, z2


def draw(ax, mesh: trimesh.Trimesh, title: str) -> None:
    yaw, pitch = math.radians(35.0), math.radians(28.0)
    x, y, depth = project(mesh, yaw, pitch)

    tris = mesh.faces
    face_colors = mesh.visual.vertex_colors[tris].mean(axis=1)[:, :3] / 255.0

    # Простой шейдинг: две направленные «лампы» + фоновая засветка.
    normals = mesh.face_normals
    light1 = np.array([0.45, 0.75, 0.48])
    light2 = np.array([-0.5, 0.3, -0.6])
    shade = (
        0.45
        + 0.45 * np.clip(normals @ light1, 0, None)
        + 0.20 * np.clip(normals @ light2, 0, None)
        + 0.18 * np.clip(-(normals @ light1), 0, None)  # подсветка сзади
    )
    rgb = np.clip(face_colors * shade[:, None], 0, 1)

    order = np.argsort(depth[tris].mean(axis=1))
    polys = np.stack([x[tris], y[tris]], axis=-1)[order]
    colors = rgb[order]

    ax.add_collection(
        PolyCollection(polys, facecolors=colors, edgecolors="none", antialiaseds=True)
    )
    pad = 0.06 * max(float(np.ptp(x)), float(np.ptp(y)))
    ax.set_xlim(x.min() - pad, x.max() + pad)
    ax.set_ylim(y.min() - pad, y.max() + pad)
    ax.set_aspect("equal")
    ax.axis("off")
    ax.set_title(title, fontsize=9, pad=4)


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    root = Path(sys.argv[1]).resolve()
    out = Path(sys.argv[2]).resolve()

    order = list(TITLES)
    files = sorted(
        root.rglob("gen_*.glb"),
        key=lambda f: (order.index(f.stem) if f.stem in order else len(order), f.stem),
    )
    if not files:
        print(f"В {root} не найдено gen_*.glb")
        return 1

    cols = 3
    rows = math.ceil(len(files) / cols)
    fig, axes = plt.subplots(rows, cols, figsize=(11, 3.4 * rows), dpi=130)
    axes = np.atleast_1d(axes).ravel()

    for ax, path in zip(axes, files):
        scene = trimesh.load(str(path), force="scene")
        mesh = trimesh.util.concatenate(tuple(scene.geometry.values()))
        draw(ax, mesh, TITLES.get(path.stem, path.stem))
    for ax in axes[len(files) :]:
        ax.axis("off")

    fig.suptitle("Процедурные модели местности и островов (gen_*.glb)", fontsize=13)
    fig.tight_layout(rect=[0, 0, 1, 0.965])
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, bbox_inches="tight", facecolor="white")
    print(f"Превью сохранено: {out} ({len(files)} моделей)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
