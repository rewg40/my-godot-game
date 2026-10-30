#!/usr/bin/env python3
"""Render tiny CC0 tree canopy cards from the existing Poly Haven models.

Run with Blender 4.3 or bpy: blender --background --python tools/prepare_island_canopies.py.
These cards supplement the reduced 3D trunks/branches in the distant forest.
"""
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/models/island_nature_4km/godot'
OUT.mkdir(parents=True, exist_ok=True)

for kind in ('pine', 'broadleaf'):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.resolution_x = scene.render.resolution_y = 512
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = 'AgX'
    scene.world = bpy.data.worlds.new('Soft canopy light')
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.75, .8, .7, 1)
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .8
    bpy.ops.import_scene.gltf(filepath=str(ROOT / 'assets/models/nature_real' / (kind + '.glb')))
    objects = [o for o in bpy.context.selected_objects if o.type == 'MESH']
    assert len(objects) == 1
    obj = objects[0]
    bpy.context.view_layer.update()
    bounds = [obj.matrix_world @ Vector(v) for v in obj.bound_box]
    low = Vector(tuple(min(v[i] for v in bounds) for i in range(3)))
    high = Vector(tuple(max(v[i] for v in bounds) for i in range(3)))
    center = (low + high) * .5
    size = high - low
    sun_data = bpy.data.lights.new('Soft sunlight', 'SUN')
    sun_data.energy = 2.0
    sun_data.angle = .35
    sun = bpy.data.objects.new('Sun', sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (.4, -.3, -.3)
    camera_data = bpy.data.cameras.new('Tree reference camera')
    camera_data.type = 'ORTHO'
    camera_data.clip_end = 200
    camera = bpy.data.objects.new('Tree camera', camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    for orientation in ('top', 'side'):
        if orientation == 'top':
            camera.location = center + Vector((0, 0, max(size) * 3))
            camera_data.ortho_scale = max(size.x, size.y) * 1.13
        else:
            camera.location = center + Vector((0, -max(size) * 3, max(size) * .25))
            camera_data.ortho_scale = max(size.x, size.z) * 1.13
        camera.rotation_euler = (center - camera.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = str(OUT / f'{kind}_{orientation}_canopy.png')
        bpy.ops.render.render(write_still=True)
        print('Rendered', scene.render.filepath, flush=True)
