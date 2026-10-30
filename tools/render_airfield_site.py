"""Render two honest overview images of the generated airfield with Blender.

The geometry and placements come from generate_airfield_site.py; the rendered
images are illustrations of that scene, not screenshots from the Godot game.
Requires Blender 4.3 or its bpy Python module. Run from the repository root:
    blender --background --python tools/render_airfield_site.py
"""
from __future__ import annotations

import importlib.util
import math
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("site", ROOT / "tools/generate_airfield_site.py")
site = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(site)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 20
scene.cycles.use_denoising = True
scene.render.image_settings.file_format = "JPEG"
scene.render.image_settings.quality = 88
scene.render.resolution_percentage = 100
scene.world = bpy.data.worlds.new("Overcast daylight")
scene.world.use_nodes = True
scene.world.node_tree.nodes.get("Background").inputs["Color"].default_value = (.67, .72, .68, 1)
scene.world.node_tree.nodes.get("Background").inputs["Strength"].default_value = .46


def textured(name, path, tint=(1, 1, 1, 1), scale=(1, 1), alpha=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    links = m.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = .98
    uv = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (scale[0], scale[1], 1)
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(ROOT / path), check_existing=True)
    tint_node = nodes.new("ShaderNodeMixRGB")
    tint_node.blend_type = "MULTIPLY"
    tint_node.inputs[0].default_value = 1.0
    tint_node.inputs[2].default_value = tint
    links.new(uv.outputs["UV"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
    links.new(tex.outputs["Color"], tint_node.inputs[1])
    links.new(tint_node.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        m.surface_render_method = "DITHERED"
    return m


def flat_color(name, color, metallic=0.0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = .95
    bsdf.inputs["Metallic"].default_value = metallic
    return m


def plane(name, x, game_z, width, depth, height, material):
    bpy.ops.mesh.primitive_plane_add(size=2, location=(x, -game_z, height))
    obj = bpy.context.object
    obj.name = name
    obj.scale = (width / 2, depth / 2, 1)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    return obj


def bar(name, center, size, material):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    obj.data.materials.append(material)
    return obj


grass = textured("Short grass", "assets/environment/textures/grass_short.jpg", (.69,.72,.59,1), (120,48))
asphalt = textured("Cracked runway", "assets/models/airport_kit/textures/cracked_asphalt.jpg", (.75,.76,.72,1), (70,3))
apron = textured("Weathered apron", "assets/models/airport_kit/textures/weathered_concrete.jpg", (.67,.67,.62,1), (30,10))
taxi = textured("Weathered taxiway", "assets/models/airport_kit/textures/cracked_asphalt.jpg", (.69,.70,.67,1), (3,7))
road = textured("Access road", "assets/models/airport_kit/textures/cracked_asphalt.jpg", (.68,.69,.65,1), (2,5))
paint = flat_color("Old runway paint", (.72,.70,.60))
metal = flat_color("Aged fence metal", (.28,.27,.22), .65)
plane("GrassTerrain", 0, 0, *site.FIELD, 0, grass)
plane("Runway", 0, site.RUNWAY_Z, site.RUNWAY_LENGTH, site.RUNWAY_WIDTH, .018, asphalt)
plane("Apron", -10, 64, 300, 108, .016, apron)
plane("Taxiway", -118, -5, 16, 70, .017, taxi)
for x in site.GATES:
    plane("Access road", x, 132, 8, 48, .015, road)
for side in (-1, 1):
    plane("Runway edge", 0, site.RUNWAY_Z + side * 12.65, 680, .18, .033, paint)
for i, x in enumerate(range(-326, 327, 14)):
    if i not in (6, 21, 34):
        plane("Centre marking", x, site.RUNWAY_Z, 7, .28, .034, paint)
for side in (-1, 1):
    for i in range(8):
        plane("Threshold", side * 322, site.RUNWAY_Z - 9.8 + i * 2.8, 11, 1.05, .034, paint)

# Import each GLB once and instance copies with shared meshes and materials.
templates = {}

def asset_template(model):
    if model in templates:
        return templates[model]
    before = set(bpy.data.objects)
    result = bpy.ops.import_scene.gltf(filepath=str(ROOT / "assets/models/airport_kit/glb" / (model + ".glb")))
    if "FINISHED" not in result:
        raise RuntimeError("Could not import " + model)
    objects = [obj for obj in bpy.data.objects if obj not in before]
    collection = bpy.data.collections.new("Template_" + model)
    # An unlinked collection keeps prototypes out of the render.
    for obj in objects:
        for old in list(obj.users_collection):
            old.objects.unlink(obj)
        collection.objects.link(obj)
    templates[model] = objects
    return objects


def add_asset(model, name, x, game_z, yaw=0, scale=1, height=.03):
    originals = asset_template(model)
    parent = bpy.data.objects.new(name, None)
    scene.collection.objects.link(parent)
    parent.location = (x, -game_z, height)
    parent.rotation_euler.z = math.radians(yaw)
    parent.scale = (scale, scale, scale)
    copies = {}
    for original in originals:
        copy = original.copy()
        scene.collection.objects.link(copy)
        copies[original] = copy
    for original, copy in copies.items():
        copy.parent = copies.get(original.parent, parent)
    return parent


for name, model, x, z, yaw in site.STRUCTURES:
    if model == "fuel_station":
        # Composite matches the standalone fuel_station.tscn.
        add_asset("fuel_canopy", name + "Canopy", x, z, yaw)
        angle = math.radians(yaw)
        for component, lx in (("fuel_tank", -1), ("fuel_pump", 4.5)):
            dx, dz = math.cos(angle) * lx, -math.sin(angle) * lx
            add_asset(component, name + component, x + dx, z + dz, yaw)
    else:
        add_asset(model, name, x, z, yaw)
for name, model, x, z, yaw, _ in site.PROPS:
    add_asset(model, name, x, z, yaw, 1, .035)
for name, model, x, z, yaw, size in site.plant_layout():
    add_asset(model, name, x, z, yaw, size, .015)

# Draw the same six continuous fence spans and two openings as the Godot scene.
gaps = [(g-2.15,g+2.15) for g in site.GATES]
spans = [(-site.FENCE_X,gaps[0][0]),(gaps[0][1],gaps[1][0]),(gaps[1][1],site.FENCE_X)]
fences = [("North", 0, site.FENCE_NORTH, site.FENCE_X*2, 0)]
fences += [(f"South{i}",(l+r)/2,site.FENCE_SOUTH,r-l,0) for i,(l,r) in enumerate(spans)]
fences += [("West",-site.FENCE_X,0,site.FENCE_SOUTH-site.FENCE_NORTH,90),
           ("East",site.FENCE_X,0,site.FENCE_SOUTH-site.FENCE_NORTH,90)]
for name,x,z,width,yaw in fences:
    mat = textured("Fence " + name, "assets/models/airport_kit/textures/chainlink.png", (.72,.73,.67,1), (width/2.4,1), True)
    mesh = bpy.data.meshes.new("FenceMesh_" + name)
    mesh.from_pydata([(-width/2,0,.15),(width/2,0,.15),(width/2,0,2.35),(-width/2,0,2.35)], [], [(0,1,2,3)])
    mesh.materials.append(mat)
    uv = mesh.uv_layers.new()
    for loop, co in zip(uv.data, [(0,0),(1,0),(1,1),(0,1)]):
        loop.uv = co
    fence = bpy.data.objects.new(name,mesh)
    scene.collection.objects.link(fence)
    fence.location = (x,-z,0)
    fence.rotation_euler.z = math.radians(yaw)
    count = max(1, math.floor(width/8))
    for j in range(count + 1):
        xx = -width/2 + width*j/count
        post = bar("Fence post", (0,0,0), (.14,.14,2.65), metal)
        post.parent = fence
        post.location = (xx,0,1.325)
    for height in (.15,2.35):
        rail = bar("Fence rail", (0,0,0), (width,.065,.065), metal)
        rail.parent = fence
        rail.location = (0,0,height)

sun_data = bpy.data.lights.new("Overcast sun", type="SUN")
sun_data.energy = 2.0
sun_data.angle = math.radians(18)
sun = bpy.data.objects.new("Overcast sun", sun_data)
scene.collection.objects.link(sun)
sun.rotation_euler = (math.radians(30), math.radians(-25), math.radians(-35))

camera_data = bpy.data.cameras.new("Airfield camera")
camera = bpy.data.objects.new("Airfield camera", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera_data.type = "ORTHO"


def render(name, location, target, ortho, width, height):
    camera.location = location
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.ortho_scale = ortho
    scene.render.resolution_x, scene.render.resolution_y = width, height
    scene.render.filepath = str(ROOT / "assets/models/airport_kit" / name)
    bpy.ops.render.render(write_still=True)
    print("Rendered", scene.render.filepath)


render("airfield_site_campus.jpg", (220,-315,245), (-12,-20,0), 350, 1800, 1100)
render("airfield_site_overview.jpg", (620,-800,780), (0,0,0), 1100, 1800, 1000)
