#!/usr/bin/env python3
"""Dependency-free checks for the nature-only island and portable GLBs."""
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KIT = ROOT / "assets/models/island_nature_4km"


def glb(path):
    blob = path.read_bytes()
    magic, version, size = struct.unpack_from('<4sII', blob, 0)
    assert magic == b'glTF' and version == 2 and size == len(blob), path
    json_size, kind = struct.unpack_from('<I4s', blob, 12)
    assert kind == b'JSON'
    doc = json.loads(blob[20:20 + json_size])
    binary_size, kind = struct.unpack_from('<I4s', blob, 20 + json_size)
    assert kind == b'BIN\0' and 20 + json_size + 8 + binary_size == len(blob)
    for image in doc.get('images', []):
        assert 'bufferView' in image and 'uri' not in image, (path, 'texture is not embedded')
    return doc


def read_uv(path, doc, accessor_index):
    blob = path.read_bytes()
    json_size = struct.unpack_from('<I', blob, 12)[0]
    binary_start = 20 + json_size + 8
    accessor = doc['accessors'][accessor_index]
    assert accessor['componentType'] == 5126 and accessor['type'] == 'VEC2'
    view = doc['bufferViews'][accessor['bufferView']]
    offset = binary_start + view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
    stride = view.get('byteStride', 8)
    return [struct.unpack_from('<2f', blob, offset + i * stride) for i in range(accessor['count'])]


def main():
    m = json.loads((KIT / 'island_metrics.json').read_text(encoding='utf-8'))
    trees = json.loads((KIT / 'godot/forest_positions.json').read_text(encoding='utf-8'))
    assert abs(m['shoreline_width_m'] - 4000) <= 8 and abs(m['shoreline_depth_m'] - 4000) <= 8
    assert m['grid_size_m'] == 4400 and m['grid_step_m'] == 8
    assert m['tree_count'] == len(trees) > 5000
    assert sum(t['type'] == 'pine' for t in trees) == m['pine_count']
    assert sum(t['type'] == 'broadleaf' for t in trees) == m['broadleaf_count']
    assert m['lake_area_m2'] > 500_000 and m['lake_level_m'] > 0
    for t in trees:
        assert t['type'] in {'pine', 'broadleaf'}
        assert all(math.isfinite(t[k]) for k in ('x', 'y', 'z', 'rotation', 'scale'))
        assert abs(t['x']) < 2000 and abs(t['y']) < 2000 and .8 < t['scale'] < 1.3
        for x, y, r in m['clearings']:
            assert math.hypot(t['x'] - x, t['y'] - y) >= r * .84 - 8, 'Tree blocks a base clearing'
    for p in ('blender/.gdignore', 'glb/.gdignore', 'blender/island_nature_4km.blend',
              'heightmap_16bit.png', 'island_model_preview.jpg', 'concept_reference.jpg'):
        assert (KIT / p).is_file(), p
    landscape = glb(KIT / 'godot/island_landscape.glb')
    assert len(landscape.get('meshes', [])) == 2, 'Landscape must include separate terrain and lake'
    names = [n.get('name', '') for n in landscape.get('nodes', [])]
    assert any('Terrain_4km' in name for name in names)
    assert any('Lake_water' in name for name in names)
    terrain = next(mesh for mesh in landscape['meshes'] if 'Terrain' in mesh.get('name', ''))
    a = landscape['accessors'][terrain['primitives'][0]['attributes']['POSITION']]
    assert abs((a['max'][0] - a['min'][0]) - 4400) < 1
    assert abs((a['max'][2] - a['min'][2]) - 4400) < 1
    assert a['count'] >= 300_000
    for name in ('pine', 'broadleaf'):
        path = KIT / f'godot/tree_{name}.glb'
        doc = glb(path)
        assert len(doc['meshes']) == 1
        materials = doc.get('materials', [])
        assert any(material.get('alphaMode') in ('BLEND', 'MASK') for material in materials), 'Leaves lost alpha'
        cards = [p for p in doc['meshes'][0]['primitives']
                 if 'canopy card' in materials[p['material']].get('name', '').lower()]
        assert len(cards) >= 2, 'Top/side canopy cards missing'
        for primitive in cards:
            uv = read_uv(path, doc, primitive['attributes']['TEXCOORD_0'])
            assert min(u[0] for u in uv) == 0 and max(u[0] for u in uv) == 1
            assert min(u[1] for u in uv) == 0 and max(u[1] for u in uv) == 1, 'Transparent foliage has collapsed UVs'
    complete = glb(KIT / 'glb/island_4km_complete.glb')
    n = [node.get('name', '') for node in complete['nodes']]
    assert sum(name.startswith('Tree_') for name in n) == m['tree_count']
    assert len(complete['meshes']) <= 4, 'Trees must share meshes rather than duplicate them'
    for forbidden in ('Road_', 'City_', 'Village_', 'Building_'):
        assert not any(name.startswith(forbidden) for name in n), f'Unexpected object: {forbidden}'
    print(f"ISLAND 4KM STRUCTURE TESTS PASSED: {len(trees)} trees, lake, 4 km shoreline, no buildings")


if __name__ == '__main__':
    main()
