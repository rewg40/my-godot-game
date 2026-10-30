"""Check the delivered .blend directly, not just the generation scripts.
Run with Blender 4.3 or bpy: blender --background --python tests/validate_island_in_blender.py
"""
import json
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[1]
KIT = ROOT / 'assets/models/island_nature_4km'
metrics = json.loads((KIT / 'island_metrics.json').read_text(encoding='utf-8'))
bpy.ops.wm.open_mainfile(filepath=str(KIT / 'blender/island_nature_4km.blend'))
scene = bpy.context.scene
assert scene.unit_settings.system == 'METRIC'
land = bpy.data.objects['Terrain_4km_shoreline_8m_grid']
lake = bpy.data.objects['Lake_water_separate']
assert len(land.data.vertices) == 551 * 551
assert abs(land.dimensions.x - 4400) < .1 and abs(land.dimensions.y - 4400) < .1
assert len(lake.data.polygons) > 100
forest = bpy.data.collections['02_Editable_linked_trees']
assert len(forest.objects) == metrics['tree_count'] > 10000
assert len({obj.data.as_pointer() for obj in forest.objects}) == 2, 'Tree meshes are not linked'
assert all(not obj.hide_render for obj in forest.objects)
prototypes = bpy.data.collections['03_Tree_prototypes']
for obj in prototypes.objects:
    assert len(obj.data.uv_layers) > 0
    uv = obj.data.uv_layers.active.data
    cards = [f for f in obj.data.polygons if 'canopy card' in obj.data.materials[f.material_index].name]
    assert len(cards) == 3
    for card in cards:
        coords = [tuple(uv[loop].uv) for loop in card.loop_indices]
        assert min(v[0] for v in coords) == 0 and max(v[0] for v in coords) == 1, 'Canopy UV collapsed'
        assert min(v[1] for v in coords) == 0 and max(v[1] for v in coords) == 1, 'Canopy UV collapsed'
    assert any('leaves' in m.name.lower() or 'twig' in m.name.lower() for m in obj.data.materials)
used_images = {n.image for m in bpy.data.materials if m.use_nodes for n in m.node_tree.nodes
               if n.type == 'TEX_IMAGE' and n.image is not None}
assert used_images and all(img.packed_file is not None for img in used_images), 'Some Blender textures are not packed'
assert '04_Preview_ocean_camera_light' in bpy.data.collections
print(f'ISLAND BLENDER TESTS PASSED: {len(forest.objects)} trees, packed images, separate land and water')
