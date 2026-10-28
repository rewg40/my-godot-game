#!/usr/bin/env python3
"""Генерация повторяющихся файлов Godot-проекта из набора текстур:

- materials/m_<name>.tres      StandardMaterial3D: albedo + normal + roughness
- <tex>.import                 для normal/roughness карт (правильные цветовые пространства)
- scenes/material_showcase.tscn стенд со всеми материалами и 4 биомами

Использование: python3 scripts/build_godot_project.py
"""
import hashlib
import random
import string
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ALBEDO = ROOT / 'assets' / 'textures' / 'albedo'
NORMAL = ROOT / 'assets' / 'textures' / 'normal'
ROUGH = ROOT / 'assets' / 'textures' / 'roughness'
MAT = ROOT / 'materials'
SCENES = ROOT / 'scenes'

BIOMES = ['t06_grass_muted', 't07_snow_frozen', 't08_sand_desert', 't09_toxic_ground']


def uid() -> str:
    return 'uid://' + ''.join(random.choices(string.ascii_lowercase + string.digits, k=13))


def write_import(png: Path, normal: bool) -> None:
    rel = png.relative_to(ROOT).as_posix()
    h = hashlib.md5(rel.encode()).hexdigest()
    dst = f'res://.godot/imported/{png.name}-{h}.ctex'
    params = [
        'compress/mode = 2',
        'compress/lossy_quality = 0.7',
        'compress/channel_pack = 0',
        'mipmaps/generate = true',
        'mipmaps/limit = -1',
        'roughness/mode = 5' if not normal else 'roughness/mode = 0',
        'roughness/src_normal = ""',
        'process/fix_alpha_border = true',
        'process/premult_alpha = false',
        'process/normal_map_invert_y = false',
        'process/hdr_as_srgb = false',
        'process/high_quality = false',
        'process/size_limit = 0',
        'detect_3d/compress_to = 1',
    ]
    if normal:
        params.insert(0, 'compress/normal = 1')
    (png.parent / (png.name + '.import')).write_text(
        '[remap]\n\n'
        f'importer = "texture"\n'
        f'type = "CompressedTexture2D"\n'
        f'uid = "{uid()}"\n'
        f'path = "{dst}"\n\n'
        '[deps]\n\n'
        f'source_file = "res://{rel}"\n'
        f'dest_files = ["{dst}"]\n\n'
        '[params]\n\n' + '\n'.join(params) + '\n')


def write_material(name: str) -> None:
    MAT.mkdir(parents=True, exist_ok=True)
    a = f'res://assets/textures/albedo/{name}.png'
    n = f'res://assets/textures/normal/{name}_normal.png'
    r = f'res://assets/textures/roughness/{name}_roughness.png'
    (MAT / f'm_{name}.tres').write_text(
        '[gd_resource type="StandardMaterial3D" load_steps=4 format=3 uid="%s"]\n\n'
        '[ext_resource type="Texture2D" path="%s" id="1_a"]\n'
        '[ext_resource type="Texture2D" path="%s" id="2_n"]\n'
        '[ext_resource type="Texture2D" path="%s" id="3_r"]\n\n'
        '[resource]\n'
        'albedo_texture = ExtResource("1_a")\n'
        'roughness = 1.0\n'
        'roughness_texture = ExtResource("3_r")\n'
        'normal_enabled = true\n'
        'normal_texture = ExtResource("2_n")\n' % (uid(), a, n, r))


def write_showcase(names: list) -> None:
    SCENES.mkdir(parents=True, exist_ok=True)
    lines = ['[gd_scene load_steps=%d format=3]' % (len(names) + 3), '']
    for i, nm in enumerate(names):
        lines.append('[ext_resource type="Material" path="res://materials/m_%s.tres" id="m%d"]' % (nm, i))
    lines += ['',
              '[sub_resource type="PlaneMesh" id="plane4"]',
              'size = Vector2(4, 4)',
              '',
              '[sub_resource type="PlaneMesh" id="plane8"]',
              'size = Vector2(8, 8)',
              '']
    lines.append('[node name="Showcase" type="Node3D"]')
    for i, nm in enumerate(names):
        x, z = (i % 5) * 5.0, (i // 5) * 5.0
        lines += ['', '[node name="%s" type="MeshInstance3D" parent="."]' % nm,
                  'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %g, 0, %g)' % (x, z),
                  'mesh = SubResource("plane4")',
                  'material_override = ExtResource("m%d")' % i]
    for j, bn in enumerate(BIOMES):
        bx, bz = (j % 2) * 8.2 - 4.1, (j // 2) * 8.2 - 4.1 + 22.0
        idx = names.index(bn)
        lines += ['', '[node name="biome_%s" type="MeshInstance3D" parent="."]' % bn,
                  'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %g, 0, %g)' % (bx, bz),
                  'mesh = SubResource("plane8")',
                  'material_override = ExtResource("m%d")' % idx]
    (SCENES / 'material_showcase.tscn').write_text('\n'.join(lines) + '\n')


def main() -> None:
    names = sorted(p.stem for p in ALBEDO.glob('*.png'))
    for nm in names:
        write_material(nm)
        write_import(NORMAL / f'{nm}_normal.png', normal=True)
        write_import(ROUGH / f'{nm}_roughness.png', normal=False)
    write_showcase(names)
    print(f'materials: {len(names)}, imports: {len(names) * 2}, showcase: ok')


if __name__ == '__main__':
    main()
