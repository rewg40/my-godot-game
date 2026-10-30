"""Render a closer view of the actual saved island, not the concept artwork.

Run from the repository root: blender --background --python tools/render_island_detail.py
"""
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
KIT = ROOT / 'assets/models/island_nature_4km'
bpy.ops.wm.open_mainfile(filepath=str(KIT / 'blender/island_nature_4km.blend'))
scene = bpy.context.scene
camera = scene.camera
camera.location = (-800, -100, 500)
target = Vector((-950, 620, 35))
camera.rotation_euler = (target - camera.location).to_track_quat('-Z', 'Y').to_euler()
camera.data.ortho_scale = 1150
scene.render.resolution_x = 1400
scene.render.resolution_y = 1000
scene.cycles.samples = 20
scene.cycles.use_denoising = True
scene.render.filepath = str(KIT / 'island_forest_preview.jpg')
bpy.ops.render.render(write_still=True)
print('Rendered actual island forest detail', flush=True)
