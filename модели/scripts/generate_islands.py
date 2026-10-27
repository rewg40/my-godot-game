#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
generate_islands.py — генерация процедурных 3D-моделей местности и островов
в формате glTF 2.0 Binary (.glb). Никаких внешних зависимостей: только stdlib.

Запуск:
    python3 generate_islands.py <папка_назначения>   # например: models/02_islands

Что генерируется:
    01_terrain_ground/
        gen_terrain_large.glb        — 64×64 м, холмистая равнина, вертексные цвета биомов
        gen_terrain_small.glb        — 32×32 м, компактный чанк для сборки карты
        gen_hex_tiles.glb            — набор гексагональных тайлов разной высоты
    02_islands/
        gen_island_a.glb             — остров с пляжем и скалистым центром
        gen_island_b.glb             — вулканический остров с кратером
        gen_atoll.glb                — атолл с лагуной
        gen_rock_islet.glb           — маленький скалистый островок
        gen_island_cluster.glb       — архипелаг из трёх островов на одной плите

Каждая модель: единый треугольный меш с позициями, нормалями и вертексными
цветами (POSITION / NORMAL / COLOR_0), метры как единица измерения, ось Y — вверх.
Подводная «юбка» у островов уходит на глубину SKIRT_DEPTH, чтобы стык с
поверхностью воды не просвечивал.
"""

from __future__ import annotations

import json
import math
import random
import struct
import sys
from pathlib import Path

SKIRT_DEPTH = 2.0  # насколько глубоко под воду уходит основание острова, метры
WATER_LEVEL = 0.0  # уровень моря в моделях островов


# --------------------------------------------------------------------------- #
# Шум
# --------------------------------------------------------------------------- #
def _hash2(ix: int, iy: int, seed: int) -> float:
    """Детерминированный псевдослучайный float в [0, 1) для целочисленной сетки."""
    h = (ix * 374761393 + iy * 668265263 + seed * 1442695040888963407) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFFFF) / float(0x1000000)


def _smooth(t: float) -> float:
    return t * t * (3.0 - 2.0 * t)


def value_noise(x: float, y: float, seed: int = 0) -> float:
    """Билинейно интерполированный value noise, результат в [0, 1)."""
    x0, y0 = math.floor(x), math.floor(y)
    fx, fy = _smooth(x - x0), _smooth(y - y0)
    a = _hash2(x0, y0, seed)
    b = _hash2(x0 + 1, y0, seed)
    c = _hash2(x0, y0 + 1, seed)
    d = _hash2(x0 + 1, y0 + 1, seed)
    top = a + (b - a) * fx
    bottom = c + (d - c) * fx
    return top + (bottom - top) * fy


def fbm(x: float, y: float, octaves: int = 5, seed: int = 0) -> float:
    """Фрактальный шум (fBm), результат примерно в [0, 1)."""
    total, amplitude, frequency, norm = 0.0, 0.5, 1.0, 0.0
    for i in range(octaves):
        total += value_noise(x * frequency, y * frequency, seed + i * 101) * amplitude
        norm += amplitude
        amplitude *= 0.5
        frequency *= 2.0
    return total / norm


# --------------------------------------------------------------------------- #
# Меш
# --------------------------------------------------------------------------- #
class Mesh:
    """Простой накапливающий меш: вершины + цвета + треугольники."""

    def __init__(self) -> None:
        self.vertices: list[tuple[float, float, float]] = []
        self.colors: list[tuple[float, float, float]] = []
        self.triangles: list[int] = []

    def add_vertex(self, x: float, y: float, z: float, color: tuple[float, float, float]) -> int:
        self.vertices.append((x, y, z))
        self.colors.append(color)
        return len(self.vertices) - 1

    def add_triangle(self, a: int, b: int, c: int) -> None:
        self.triangles.extend((a, b, c))

    def merge_from(self, other: "Mesh", dx: float = 0.0, dy: float = 0.0, dz: float = 0.0) -> None:
        """Добавляет копию другого меша со сдвигом."""
        offset = len(self.vertices)
        for (x, y, z), color in zip(other.vertices, other.colors):
            self.vertices.append((x + dx, y + dy, z + dz))
            self.colors.append(color)
        self.triangles.extend(i + offset for i in other.triangles)

    def add_quad(self, a: int, b: int, c: int, d: int) -> None:
        """
        a-b-c-d — обход против часовой стрелки, если смотреть СНАРУЖИ:
        внешняя сторона треугольника в glTF — та, откуда вершины идут против
        часовой стрелки. Порядок проверен эмпирически (см. assert_outward()).
        """
        self.add_triangle(a, b, c)
        self.add_triangle(a, c, d)


def lerp_color(c1: tuple[float, float, float], c2: tuple[float, float, float], t: float):
    t = max(0.0, min(1.0, t))
    return (
        c1[0] + (c2[0] - c1[0]) * t,
        c1[1] + (c2[1] - c1[1]) * t,
        c1[2] + (c2[2] - c1[2]) * t,
    )


def compute_normals(mesh: Mesh) -> list[tuple[float, float, float]]:
    """Площадные нормали, сглаженные по вершинам."""
    normals = [[0.0, 0.0, 0.0] for _ in mesh.vertices]
    for i in range(0, len(mesh.triangles), 3):
        ia, ib, ic = mesh.triangles[i], mesh.triangles[i + 1], mesh.triangles[i + 2]
        ax, ay, az = mesh.vertices[ia]
        bx, by, bz = mesh.vertices[ib]
        cx, cy, cz = mesh.vertices[ic]
        ux, uy, uz = bx - ax, by - ay, bz - az
        vx, vy, vz = cx - ax, cy - ay, cz - az
        nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        for idx in (ia, ib, ic):
            normals[idx][0] += nx
            normals[idx][1] += ny
            normals[idx][2] += nz
    out = []
    for nx, ny, nz in normals:
        length = math.sqrt(nx * nx + ny * ny + nz * nz)
        out.append((nx / length, ny / length, nz / length) if length > 1e-9 else (0.0, 1.0, 0.0))
    return out


# --------------------------------------------------------------------------- #
# Палитра
# --------------------------------------------------------------------------- #
SAND = (0.90, 0.82, 0.60)
GRASS = (0.36, 0.62, 0.28)
DARK_GRASS = (0.22, 0.45, 0.22)
ROCK = (0.47, 0.45, 0.42)
SNOW = (0.95, 0.96, 0.98)
WET_SAND = (0.72, 0.63, 0.45)
DARK_ROCK = (0.30, 0.28, 0.27)


def terrain_color(height: float, slope: float) -> tuple[float, float, float]:
    """
    Цвет биома по высоте (метры) и крутизне склона (0 = плоско, 1 = отвесно).
    Пороги подобраны под масштаб паков: один тайл Kenney = 1×1 м с подъёмом
    0.2–0.8 м, поэтому вся палитра умещается в диапазон 0–4.5 м.
    """
    if height < 0.12:
        return WET_SAND
    if height < 0.45:
        return lerp_color(SAND, GRASS, (height - 0.12) / 0.33)
    if slope > 0.55:
        return lerp_color(ROCK, DARK_ROCK, min(1.0, (slope - 0.55) / 0.35))
    if height < 2.6:
        return lerp_color(GRASS, DARK_GRASS, (height - 0.45) / 2.15)
    if height < 4.0:
        return lerp_color(DARK_GRASS, ROCK, (height - 2.6) / 1.4)
    return lerp_color(ROCK, SNOW, min(1.0, (height - 4.0) / 1.6))


# --------------------------------------------------------------------------- #
# Высотные поля
# --------------------------------------------------------------------------- #
def height_terrain(u: float, v: float, seed: int) -> float:
    """
    Холмистая равнина: пологие холмы + сглаженные скальные гребни.
    Гребни поднимаются функцией smoothstep, а не «max», иначе на сетке 1 м
    получаются иглы. Диапазон высот ~0..6 м при шаге сетки 0.67 м.
    """
    base = fbm(u * 3.2, v * 3.2, octaves=5, seed=seed)
    ridges = fbm(u * 5.5 + 11.0, v * 5.5 - 4.0, octaves=3, seed=seed + 7)
    r = max(0.0, min(1.0, (ridges - 0.55) / 0.45))
    ridge = r * r * (3.0 - 2.0 * r)  # smoothstep: плавный подъём и спуск
    return base * 3.4 + ridge * 2.4


def height_island(u: float, v: float, seed: int, radius: float = 1.0, peak: float = 4.5) -> float:
    """
    Остров: купол с шумовым берегом. u, v — координаты в [-1, 1].
    Ниже WATER_LEVEL за пределами суши.
    """
    dist = math.hypot(u, v) / radius
    noise = fbm(u * 4.0 + 5.0, v * 4.0 + 2.0, octaves=5, seed=seed) - 0.5
    coast = dist + noise * 0.34
    if coast >= 1.0:
        return WATER_LEVEL - SKIRT_DEPTH * min(1.0, (coast - 1.0) / 0.35)
    falloff = 1.0 - coast
    shape = math.pow(falloff, 1.35)
    detail = fbm(u * 9.0, v * 9.0, octaves=4, seed=seed + 3) - 0.5
    return shape * peak + detail * 0.8 * shape - 0.15


def height_volcano(u: float, v: float, seed: int) -> float:
    """Вулканический остров: конус + кратер на вершине."""
    dist = math.hypot(u, v)
    noise = fbm(u * 4.0, v * 4.0, octaves=5, seed=seed) - 0.5
    coast = dist + noise * 0.3
    if coast >= 1.0:
        return WATER_LEVEL - SKIRT_DEPTH * min(1.0, (coast - 1.0) / 0.35)
    falloff = 1.0 - coast
    cone = math.pow(falloff, 1.0) * 6.6
    crater = math.exp(-math.pow((dist - 0.12) / 0.16, 2.0)) * 2.6
    detail = (fbm(u * 12.0, v * 12.0, octaves=4, seed=seed + 5) - 0.5) * 0.9
    return cone - crater + detail * falloff - 0.2


def height_atoll(u: float, v: float, seed: int) -> float:
    """Атолл: кольцо рифа вокруг мелкой лагуны."""
    dist = math.hypot(u, v)
    ring = math.exp(-math.pow((dist - 0.72) / 0.14, 2.0))
    noise = fbm(u * 6.0, v * 6.0, octaves=5, seed=seed) - 0.5
    coast_noise = fbm(u * 3.0 + 9.0, v * 3.0, octaves=3, seed=seed + 2) - 0.5
    h = ring * 1.5 + noise * 0.6 * ring
    if dist > 1.0 + coast_noise * 0.12:
        return WATER_LEVEL - SKIRT_DEPTH * min(1.0, (dist - 1.0) / 0.3)
    return max(h, WATER_LEVEL - 1.0 + ring * 1.0) - 0.06


def height_rock(u: float, v: float, seed: int) -> float:
    """Скалистый островок: резкие грани, почти без почвы."""
    dist = math.hypot(u, v)
    noise = fbm(u * 5.0, v * 5.0, octaves=5, seed=seed) - 0.5
    coast = dist + noise * 0.3
    if coast >= 1.0:
        return WATER_LEVEL - SKIRT_DEPTH * min(1.0, (coast - 1.0) / 0.3)
    falloff = 1.0 - coast
    spike = math.pow(falloff, 1.1) * 4.0
    jag = (fbm(u * 14.0, v * 14.0, octaves=3, seed=seed + 9) - 0.5) * 1.4
    return spike + jag * falloff - 0.1


# --------------------------------------------------------------------------- #
# Построение сеток
# --------------------------------------------------------------------------- #
def build_heightfield(size: float, segments: int, height_fn, seed: int) -> Mesh:
    """Квадратная сетка size×size метров, segments×segments ячеек."""
    mesh = Mesh()
    step = size / segments
    heights: list[list[float]] = []
    for j in range(segments + 1):
        row = []
        for i in range(segments + 1):
            u = i / segments * 2.0 - 1.0
            v = j / segments * 2.0 - 1.0
            row.append(height_fn(u, v, seed))
        heights.append(row)

    index_grid: list[list[int]] = []
    for j in range(segments + 1):
        row = []
        for i in range(segments + 1):
            x = -size / 2.0 + i * step
            z = -size / 2.0 + j * step
            y = heights[j][i]
            # Крутизна по соседям — нужна для цвета биома.
            hl = heights[j][max(0, i - 1)]
            hr = heights[j][min(segments, i + 1)]
            hd = heights[max(0, j - 1)][i]
            hu = heights[min(segments, j + 1)][i]
            dx, dz = (hr - hl) / (2 * step), (hu - hd) / (2 * step)
            slope = math.sqrt(dx * dx + dz * dz) / 2.0
            row.append(mesh.add_vertex(x, y, z, terrain_color(y, slope)))
        index_grid.append(row)

    for j in range(segments):
        for i in range(segments):
            a = index_grid[j][i]
            b = index_grid[j][i + 1]
            c = index_grid[j + 1][i + 1]
            d = index_grid[j + 1][i]
            mesh.add_quad(a, d, c, b)

    return mesh


def build_island_with_base(size: float, segments: int, height_fn, seed: int) -> Mesh:
    """
    Остров: верхняя поверхность + «юбка» вниз до -SKIRT_DEPTH и плоское дно.
    Юбка нужна, чтобы стык с плоскостью воды не просвечивал.
    """
    top = build_heightfield(size, segments, height_fn, seed)

    # Обод сетки — для юбки.
    n = segments + 1
    edge: list[int] = []
    idx = {}
    grid = list(range(n * n))
    for i in range(n):
        idx[(i, 0)] = grid[i]
    for j in range(1, n):
        idx[(n - 1, j)] = grid[j * n + (n - 1)]
    for i in range(n - 2, -1, -1):
        idx[(i, n - 1)] = grid[(n - 1) * n + i]
    for j in range(n - 2, 0, -1):
        idx[(0, j)] = grid[j * n]
    edge = [idx[(i, 0)] for i in range(n)]
    edge += [idx[(n - 1, j)] for j in range(1, n)]
    edge += [idx[(i, n - 1)] for i in range(n - 2, -1, -1)]
    edge += [idx[(0, j)] for j in range(n - 2, 0, -1)]

    bottom = -SKIRT_DEPTH - 0.25
    bottom_index = []
    for vi in edge:
        x, _y, z = top.vertices[vi]
        bottom_index.append(top.add_vertex(x, bottom, z, DARK_ROCK))

    count = len(edge)
    for k in range(count):
        top_i = edge[k]
        next_i = edge[(k + 1) % count]
        b_cur = bottom_index[k]
        b_next = bottom_index[(k + 1) % count]
        # Юбка: a-b-ba-bb против часовой снаружи = add_quad(top, top_next, bottom_next, bottom).
        top.add_quad(top_i, next_i, b_next, b_cur)

    # Дно: веер от центральной точки.
    center = top.add_vertex(0.0, bottom, 0.0, DARK_ROCK)
    for k in range(count):
        top.add_triangle(center, bottom_index[k], bottom_index[(k + 1) % count])

    assert_closed(top, "island")
    return top


def build_hex_tiles(radius: float = 1.0) -> Mesh:
    """
    Плоскогранный гексагональный тайл (как в Hexagon Kit) четырёх высот:
    низкий, средний, высокий, гора. Удобен для сборки карты островов по сетке.
    """
    mesh = Mesh()
    offsets = [
        (-radius * 3.2, 0.0, 0.2, SAND),
        (0.0, 0.0, 0.6, GRASS),
        (radius * 3.2, 0.0, 1.0, DARK_GRASS),
        (radius * 1.6, -radius * 2.8, 1.6, ROCK),
    ]
    for cx, cz, height, top_color in offsets:
        tile = Mesh()  # собираем тайл в своих координатах, чтобы проверить ориентацию
        ring = []
        for k in range(6):
            angle = math.radians(60 * k)
            ring.append(
                tile.add_vertex(
                    radius * math.cos(angle),
                    height,
                    radius * math.sin(angle),
                    top_color,
                )
            )
        apex = tile.add_vertex(0.0, height, cz * 0.0, top_color)
        for k in range(6):
            tile.add_triangle(apex, ring[(k + 1) % 6], ring[k])

        base = -0.6
        bottom_ring = []
        for k in range(6):
            angle = math.radians(60 * k)
            bottom_ring.append(
                tile.add_vertex(
                    radius * math.cos(angle),
                    base,
                    radius * math.sin(angle),
                    DARK_ROCK,
                )
            )
        bottom_center = tile.add_vertex(0.0, base, 0.0, DARK_ROCK)
        for k in range(6):
            a, b = ring[k], ring[(k + 1) % 6]
            ba, bb = bottom_ring[k], bottom_ring[(k + 1) % 6]
            tile.add_quad(a, b, bb, ba)
            tile.add_triangle(bottom_center, ba, bb)

        good, total = outward_fraction(tile)
        if good != total:
            raise AssertionError(
                f"hex tile ({cx:.1f}, {cz:.1f}): наружу смотрят {good} граней из {total}"
            )
        mesh.merge_from(tile, dx=cx, dz=cz)

    return mesh


def transformed(mesh: Mesh, dx: float, dy: float, dz: float, scale: float, yaw: float) -> Mesh:
    """Копия меша со сдвигом, масштабом и поворотом вокруг Y."""
    out = Mesh()
    cos_y, sin_y = math.cos(yaw), math.sin(yaw)
    mapping = {}
    for i, ((x, y, z), color) in enumerate(zip(mesh.vertices, mesh.colors)):
        sx, sy, sz = x * scale, y * scale, z * scale
        rx = sx * cos_y - sz * sin_y
        rz = sx * sin_y + sz * cos_y
        mapping[i] = out.add_vertex(rx + dx, sy + dy, rz + dz, color)
    for t in mesh.triangles:
        out.triangles.append(mapping[t])
    return out


def merge(meshes: list[Mesh]) -> Mesh:
    out = Mesh()
    for m in meshes:
        offset = len(out.vertices)
        out.vertices.extend(m.vertices)
        out.colors.extend(m.colors)
        out.triangles.extend(i + offset for i in m.triangles)
    return out


# --------------------------------------------------------------------------- #
# Запись GLB
# --------------------------------------------------------------------------- #
def _pack_accessor(values, fmt: str) -> bytes:
    return b"".join(struct.pack("<" + fmt, *v) for v in values)


def signed_volume(mesh: Mesh) -> float:
    """
    Знаковый объём замкнутого меша. Проверено на эталонном кубе: при обходе
    против часовой стрелки, если смотреть снаружи (нормали наружу), объём
    ПОЛОЖИТЕЛЕН; отрицательный означает, что меш вывернут наизнанку.
    """
    total = 0.0
    for i in range(0, len(mesh.triangles), 3):
        a = mesh.vertices[mesh.triangles[i]]
        b = mesh.vertices[mesh.triangles[i + 1]]
        c = mesh.vertices[mesh.triangles[i + 2]]
        total += (
            a[0] * (b[1] * c[2] - b[2] * c[1])
            - a[1] * (b[0] * c[2] - b[2] * c[0])
            + a[2] * (b[0] * c[1] - b[1] * c[0])
        ) / 6.0
    return total


def outward_fraction(mesh: Mesh) -> tuple[int, int]:
    """
    Сколько граней смотрят наружу (нормаль сонаправлена с лучом из центра масс
    в центр грани). Возвращает (наружу, всего). Работает только для одного
    выпуклого меша, центрированного вокруг собственного центра масс, — поэтому
    для набора тайлов вызывается по каждому тайлу отдельно.
    """
    if not mesh.triangles:
        return 0, 0
    cx = sum(v[0] for v in mesh.vertices) / len(mesh.vertices)
    cy = sum(v[1] for v in mesh.vertices) / len(mesh.vertices)
    cz = sum(v[2] for v in mesh.vertices) / len(mesh.vertices)
    good = total = 0
    for i in range(0, len(mesh.triangles), 3):
        a = mesh.vertices[mesh.triangles[i]]
        b = mesh.vertices[mesh.triangles[i + 1]]
        c = mesh.vertices[mesh.triangles[i + 2]]
        ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
        nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        fx = (a[0] + b[0] + c[0]) / 3.0 - cx
        fy = (a[1] + b[1] + c[1]) / 3.0 - cy
        fz = (a[2] + b[2] + c[2]) / 3.0 - cz
        total += 1
        if nx * fx + ny * fy + nz * fz > 0.0:
            good += 1
    return good, total


def inconsistent_edges(mesh: Mesh) -> int:
    """
    Число общих рёбер, которые обе соседние грани обходят в ОДНУ сторону.
    У корректно ориентированного меша каждое общее ребро обходится встречно,
    поэтому 0 — норма. Ненулевое значение означает вывернутые треугольники,
    даже если знаковый объём при этом остаётся положительным.
    """
    directed: dict[tuple[int, int], int] = {}
    for i in range(0, len(mesh.triangles), 3):
        a, b, c = mesh.triangles[i], mesh.triangles[i + 1], mesh.triangles[i + 2]
        for u, v in ((a, b), (b, c), (c, a)):
            key = (min(u, v), max(u, v))
            directed[key] = directed.get(key, 0) + (1 if u < v else -1)
    return sum(1 for value in directed.values() if abs(value) != 1 and value != 0 and value % 2 == 0)


def assert_closed(mesh: Mesh, name: str) -> None:
    """Замкнутый меш (остров, тайл): нормали должны смотреть наружу."""
    volume = signed_volume(mesh)
    if volume <= 0.0:
        raise AssertionError(
            f"{name}: signed volume {volume:.2f} <= 0 — меш вывернут наизнанку"
        )
    bad = inconsistent_edges(mesh)
    if bad:
        raise AssertionError(f"{name}: {bad} рёбер с несогласованным обходом — часть граней вывернута")


def assert_upward(mesh: Mesh, name: str) -> None:
    """Открытая поверхность местности: все нормали должны смотреть вверх."""
    bad = 0
    for i in range(0, len(mesh.triangles), 3):
        a = mesh.vertices[mesh.triangles[i]]
        b = mesh.vertices[mesh.triangles[i + 1]]
        c = mesh.vertices[mesh.triangles[i + 2]]
        ux, uz = b[0] - a[0], b[2] - a[2]
        vx, vz = c[0] - a[0], c[2] - a[2]
        ny = uz * vx - ux * vz
        if ny <= 0.0:
            bad += 1
    if bad:
        raise AssertionError(f"{name}: {bad} граней смотрят вниз из {len(mesh.triangles) // 3}")


def write_glb(path: Path, mesh: Mesh, check_winding=None) -> None:
    """
    Пишет glTF 2.0 Binary с POSITION / NORMAL / COLOR_0.
    check_winding — колбэк-проверка ориентации (assert_closed / assert_upward);
    вызывается до записи и падает, если нормали вывернуты.
    """
    if check_winding is not None:
        check_winding(mesh, path.name)
    normals = compute_normals(mesh)

    positions = _pack_accessor(mesh.vertices, "fff")
    normals_blob = _pack_accessor(normals, "fff")
    colors = _pack_accessor(mesh.colors, "fff")
    indices = _pack_accessor([(i,) for i in mesh.triangles], "I")

    chunks = [indices, positions, normals_blob, colors]
    buffer = b""
    offsets = []
    for chunk in chunks:
        offsets.append(len(buffer))
        buffer += chunk
        pad = (-len(buffer)) % 4
        buffer += b"\x00" * pad

    xs = [v[0] for v in mesh.vertices]
    ys = [v[1] for v in mesh.vertices]
    zs = [v[2] for v in mesh.vertices]
    bounds = [min(xs), min(ys), min(zs), max(xs), max(ys), max(zs)]

    def accessor(offset: int, count: int, comp_type: int, type_name: str, with_minmax=False):
        acc = {
            "bufferView": 0,
            "byteOffset": offset,
            "componentType": comp_type,
            "count": count,
            "type": type_name,
        }
        if with_minmax:
            acc["min"] = bounds[:3]
            acc["max"] = bounds[3:]
        return acc

    gltf = {
        "asset": {"version": "2.0", "generator": "generate_islands.py (my-godot-game)"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": path.stem}],
        "meshes": [
            {
                "name": path.stem,
                "primitives": [
                    {
                        "attributes": {
                            "POSITION": 1,
                            "NORMAL": 2,
                            "COLOR_0": 3,
                        },
                        "indices": 0,
                        "mode": 4,
                    }
                ],
            }
        ],
        "accessors": [
            accessor(offsets[0], len(mesh.triangles), 5125, "SCALAR"),
            accessor(offsets[1], len(mesh.vertices), 5126, "VEC3", with_minmax=True),
            accessor(offsets[2], len(mesh.vertices), 5126, "VEC3"),
            accessor(offsets[3], len(mesh.vertices), 5126, "VEC3"),
        ],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": len(buffer), "target": 34963},
        ],
        "buffers": [{"byteLength": len(buffer)}],
    }

    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((-len(json_bytes)) % 4)

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as fh:
        fh.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(json_bytes) + 8 + len(buffer)))
        fh.write(struct.pack("<I4s", len(json_bytes), b"JSON"))
        fh.write(json_bytes)
        fh.write(struct.pack("<I4s", len(buffer), b"BIN\x00"))
        fh.write(buffer)


# --------------------------------------------------------------------------- #
# Точка входа
# --------------------------------------------------------------------------- #
def generate(root: Path) -> list[tuple[str, int, int]]:
    """Генерирует все модели. Возвращает [(категория/имя, вершины, треугольники)]."""
    rng = random.Random(20261027)
    seeds = [rng.randrange(1, 999_983) for _ in range(12)]
    results = []

    jobs = [
        # (категория, имя файла, построитель, проверка ориентации)
        ("01_terrain_ground", "gen_terrain_large.glb", lambda: build_heightfield(64.0, 96, height_terrain, seeds[0]), assert_upward),
        ("01_terrain_ground", "gen_terrain_small.glb", lambda: build_heightfield(32.0, 48, height_terrain, seeds[1]), assert_upward),
        ("01_terrain_ground", "gen_hex_tiles.glb", build_hex_tiles, None),
        ("02_islands", "gen_island_a.glb", lambda: build_island_with_base(48.0, 96, height_island, seeds[2]), assert_closed),
        ("02_islands", "gen_island_b.glb", lambda: build_island_with_base(40.0, 88, height_volcano, seeds[3]), assert_closed),
        ("02_islands", "gen_atoll.glb", lambda: build_island_with_base(56.0, 96, height_atoll, seeds[4]), assert_closed),
        ("02_islands", "gen_rock_islet.glb", lambda: build_island_with_base(20.0, 64, height_rock, seeds[5]), assert_closed),
        (
            "02_islands",
            "gen_island_cluster.glb",
            lambda: merge(
                [
                    build_island_with_base(44.0, 80, height_island, seeds[6]),
                    transformed(build_island_with_base(24.0, 56, height_rock, seeds[7]), 38.0, 0.0, 14.0, 1.0, 0.6),
                    transformed(build_island_with_base(30.0, 60, height_atoll, seeds[8]), -34.0, 0.0, -26.0, 0.9, 2.1),
                ]
            ),
            None,
        ),
    ]

    for category, filename, builder, check in jobs:
        mesh = builder()
        target = root / category / filename
        write_glb(target, mesh, check_winding=check)
        results.append((f"{category}/{filename}", len(mesh.vertices), len(mesh.triangles) // 3))

    return results


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    root = Path(sys.argv[1]).resolve()
    results = generate(root)
    print(f"Сгенерировано моделей: {len(results)} -> {root}")
    for name, verts, tris in results:
        print(f"  {name:38s} вершин {verts:7d}  треугольников {tris:7d}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
