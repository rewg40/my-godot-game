#!/usr/bin/env python3
"""Create an editable nature-only 4 km island and Godot-ready visual assets.

Requires Blender 4.3 (or bpy 4.3), NumPy, SciPy and Pillow. Run from the
repository root, e.g. blender --background --python tools/generate_island_4km.py.
This writes only assets/models/island_nature_4km and never replaces the current
playable island or modifies saves. The full GLB is ignored by the Godot scanner;
use the optimized Godot scene for interactive editing.
"""
from __future__ import annotations

import importlib.util
import json
import math
import os
import sys
from pathlib import Path

import bpy
import bmesh
import numpy as np
from mathutils import Vector, Matrix
from mathutils.geometry import tessellate_polygon
from PIL import Image
from scipy.ndimage import gaussian_filter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/island_nature_4km"
BLENDER = OUT / "blender"
GLB = OUT / "glb"
GODOT = OUT / "godot"
for directory in (OUT, BLENDER, GLB, GODOT):
    directory.mkdir(parents=True, exist_ok=True)
for directory in (BLENDER, GLB):
    (directory / ".gdignore").write_text("", encoding="utf-8")

spec = importlib.util.spec_from_file_location("island_4km_topography", ROOT / "tools/island_4km_topography.py")
topo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(topo)
data = topo.build()
trees = topo.forest_positions(data)
meta = topo.metrics(data, trees)
(GODOT / "forest_positions.json").write_text(json.dumps(trees, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
(OUT / "island_metrics.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("ISLAND METRICS", json.dumps(meta, ensure_ascii=False), flush=True)

# A compact editable 16-bit heightmap plus a baked PBR base-colour atlas.
height = data["height"]
hmin, hmax = float(height.min()), float(height.max())
height_u16 = np.uint16(np.rint(np.clip((height - hmin) / (hmax - hmin), 0, 1) * 65535))
Image.fromarray(height_u16).save(OUT / "heightmap_16bit.png")
tex_size = 2048

def resample(array):
    return np.asarray(Image.fromarray(np.asarray(array, dtype=np.float32)).resize((tex_size, tex_size), Image.Resampling.BILINEAR))


def tiled(path: Path, pixel_size: int):
    im = Image.open(path).convert("RGB").resize((pixel_size, pixel_size), Image.Resampling.LANCZOS)
    tile = np.asarray(im, dtype=np.float32)
    count = int(math.ceil(tex_size / pixel_size))
    return np.tile(tile, (count, count, 1))[:tex_size, :tex_size, :]


grass = tiled(ROOT / "assets/environment/textures/grass_short.jpg", 86)
sand = tiled(ROOT / "assets/environment/textures/sand.jpg", 112)
rock = tiled(ROOT / "assets/environment/textures/rock_diff_1k.jpg", 135)
forest_floor = tiled(ROOT / "assets/environment/textures/forest_diff_1k.jpg", 105)
land = resample(data["land"].astype(np.float32))
coast_d = resample(data["land_d"])
lake_d = resample(data["lake_out"])
forest = resample(data["forest"])
gy, gx = np.gradient(height, topo.STEP)
slope = resample(np.sqrt(gx * gx + gy * gy))
rng = np.random.default_rng(topo.SEED + 4)
noise = gaussian_filter(rng.standard_normal((tex_size, tex_size)).astype(np.float32), 35)
noise /= max(float(noise.std()), .001)
# Mix photographs with muted natural colours. Large-scale variation breaks up
# repetitive tiling while beaches, rocky slopes and forest floor stay distinct.
base = (.53 * grass + .47 * np.array([105, 116, 76], dtype=np.float32))
base *= (np.clip(1 + .035 * noise, .85, 1.15))[..., None]
woodland = .42 * forest_floor + .58 * np.array([77, 92, 61], dtype=np.float32)
forest_alpha = np.clip(forest * .5, 0, .45)[..., None]
base = base * (1 - forest_alpha) + woodland * forest_alpha
rock_col = .50 * rock + .50 * np.array([112, 113, 101], dtype=np.float32)
rock_alpha = (topo.smoothstep(.16, .52, slope) * .78)[..., None]
base = base * (1 - rock_alpha) + rock_col * rock_alpha
# Alternate beach and rocky headlands instead of a uniform ring of sand.
beach = np.maximum((1 - topo.smoothstep(16, 75, coast_d)) * np.clip(.7 - .18 * noise, .25, 1),
                   (1 - topo.smoothstep(10, 38, lake_d)) * .55) * (land > .4)
beach_col = .58 * sand + .42 * np.array([162, 151, 118], dtype=np.float32)
beach_alpha = np.clip(beach * .84, 0, .84)[..., None]
base = base * (1 - beach_alpha) + beach_col * beach_alpha
Image.fromarray(np.uint8(np.clip(base, 0, 255))).save(GODOT / "terrain_color.jpg", quality=88, optimize=True)
del grass, sand, rock, forest_floor, land, coast_d, lake_d, forest, slope, noise, base, woodland, beach_col, rock_col
print("Terrain atlas and heightmap prepared", flush=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.render.engine = "CYCLES"
scene.cycles.samples = 24
scene.cycles.use_denoising = True
scene.render.image_settings.file_format = "JPEG"
scene.render.image_settings.quality = 90
scene.render.resolution_x = 1600
scene.render.resolution_y = 1600
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "AgX"
scene.view_settings.exposure = .2
scene.world = bpy.data.worlds.new("Overcast daylight")
scene.world.use_nodes = True
background = scene.world.node_tree.nodes.get("Background")
background.inputs["Color"].default_value = (.68, .75, .78, 1)
background.inputs["Strength"].default_value = .55


def collection(name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    return c

land_collection = collection("01_Landscape_and_lake")
forest_collection = collection("02_Editable_linked_trees")
proto_collection = collection("03_Tree_prototypes")
preview_collection = collection("04_Preview_ocean_camera_light")


def material_color(name, color, roughness=.8):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.diffuse_color = (*color, 1)
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    return m


terrain_mat = material_color("Landscape — grass, forest floor, sand and rock (CC0)", (.36, .42, .27))
image = bpy.data.images.load(str(GODOT / "terrain_color.jpg"), check_existing=True)
image.pack()
tex = terrain_mat.node_tree.nodes.new("ShaderNodeTexImage")
tex.name = "Baked editable terrain colour"
tex.image = image
terrain_mat.node_tree.links.new(tex.outputs["Color"], terrain_mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
lake_mat = material_color("Freshwater lake", (.11, .26, .27), .38)
ocean_mat = material_color("Preview sea (separate)", (.105, .21, .26), .38)

# Allocate the 551x551 grid without millions of slow Python mesh operators.
n = topo.GRID
verts = np.column_stack([data["x"].ravel(), data["y"].ravel(), height.ravel()]).astype(np.float32)
ix, iy = np.meshgrid(np.arange(n - 1), np.arange(n - 1))
a = (iy * n + ix).ravel()
quads = np.stack([a, a + 1, a + n + 1, a + n], axis=1).astype(np.int32).ravel()
mesh = bpy.data.meshes.new("Terrain_grid_8m")
mesh.vertices.add(len(verts))
mesh.vertices.foreach_set("co", verts.ravel())
mesh.loops.add(len(quads))
mesh.loops.foreach_set("vertex_index", quads)
mesh.polygons.add(len(a))
mesh.polygons.foreach_set("loop_start", np.arange(len(a), dtype=np.int32) * 4)
mesh.polygons.foreach_set("loop_total", np.full(len(a), 4, dtype=np.int32))
mesh.polygons.foreach_set("use_smooth", np.ones(len(a), dtype=bool))
mesh.update()
uv_vertex = np.column_stack([(verts[:, 0] + topo.SIZE / 2) / topo.SIZE,
                             1 - (verts[:, 1] + topo.SIZE / 2) / topo.SIZE]).astype(np.float32)
mesh.uv_layers.new(name="TerrainAtlasUV").data.foreach_set("uv", uv_vertex[quads].ravel())
mesh.materials.append(terrain_mat)
terrain = bpy.data.objects.new("Terrain_4km_shoreline_8m_grid", mesh)
land_collection.objects.link(terrain)
print(f"Terrain built: {len(mesh.vertices)} vertices, {len(mesh.polygons)} quads", flush=True)

# Smooth, irregular lake polygon. The lowered lake bed remains part of the
# terrain; the separate water surface is not a rectangular overlay.
lake_boundary = [Vector((float(x), float(y), topo.LAKE_LEVEL)) for x, y in topo.lake_outline()]
water_triangles = tessellate_polygon([lake_boundary])
water_verts = [tuple(p) for p in lake_boundary]
water_faces = [tuple(triangle) for triangle in water_triangles]
water_mesh = bpy.data.meshes.new("Lake_water_surface")
water_mesh.from_pydata(water_verts, [], water_faces)
water_mesh.materials.append(lake_mat)
water = bpy.data.objects.new("Lake_water_separate", water_mesh)
land_collection.objects.link(water)
print(f"Lake built: {len(water_faces)} triangles", flush=True)


def canopy_material(kind, orientation):
    name = f"{kind} {orientation} canopy card (Poly Haven CC0)"
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.surface_render_method = "DITHERED"
    mat.use_backface_culling = False
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = .93
    image_node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    image_node.image = bpy.data.images.load(str(GODOT / f"{kind}_{orientation}_canopy.png"), check_existing=True)
    mat.node_tree.links.new(image_node.outputs["Color"], shader.inputs["Base Color"])
    mat.node_tree.links.new(image_node.outputs["Alpha"], shader.inputs["Alpha"])
    return mat


def add_canopy_cards(obj, kind):
    # A horizontal crown card plus two crossed side cards keep distant tree
    # canopies visible without instancing the 10k–16k-triangle source meshes.
    # They supplement, rather than replace, actual 3D trunks and branches.
    if kind == "pine":
        top_size, side_size, crown_height = 9.2, 16.4, 11.2
    else:
        top_size, side_size, crown_height = 11.4, 11.4, 8.3
    a, b = top_size / 2, side_size / 2
    vertices = [(-a, -a, crown_height), (a, -a, crown_height), (a, a, crown_height), (-a, a, crown_height),
                (-b, 0, 0), (b, 0, 0), (b, 0, side_size), (-b, 0, side_size),
                (0, -b, 0), (0, b, 0), (0, b, side_size), (0, -b, side_size)]
    faces = [(0, 1, 2, 3), (4, 5, 6, 7), (8, 9, 10, 11)]
    card_mesh = bpy.data.meshes.new("Canopy_cards_" + kind)
    card_mesh.from_pydata(vertices, [], faces)
    card_mesh.materials.append(canopy_material(kind, "top"))
    card_mesh.materials.append(canopy_material(kind, "side"))
    # Match the source's active UV layer: after joining meshes, Blender and
    # glTF otherwise sample (0, 0) on every card and foliage disappears.
    uv_name = obj.data.uv_layers.active.name if obj.data.uv_layers.active else "UVMap"
    uv = card_mesh.uv_layers.new(name=uv_name)
    for face in card_mesh.polygons:
        face.material_index = 0 if face.index == 0 else 1
        for loop, coords in zip(face.loop_indices, [(0, 0), (1, 0), (1, 1), (0, 1)]):
            uv.data[loop].uv = coords
    card_obj = bpy.data.objects.new("Canopy_" + kind, card_mesh)
    scene.collection.objects.link(card_obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    card_obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.join()


def imported_tree(kind, size_factor):
    bpy.ops.object.select_all(action="DESELECT")
    path = ROOT / "assets/models/nature_real" / (kind + ".glb")
    bpy.ops.import_scene.gltf(filepath=str(path))
    candidates = [obj for obj in bpy.context.selected_objects if obj.type == "MESH"]
    assert len(candidates) == 1, (kind, candidates)
    obj = candidates[0]
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Decimating the entire mesh would delete all disconnected leaf cards.
    # Separate alpha foliage first, keep a deterministic sample of complete
    # triangle pairs, and decimate only the opaque trunk/branch geometry.
    leaf_material = next(i for i, mat in enumerate(obj.data.materials)
                         if ("twig" if kind == "pine" else "leaves") in mat.name.lower())
    source = obj.data.copy()
    leaf_indices = [face.index for face in source.polygons if face.material_index == leaf_material]
    choices = np.random.default_rng(topo.SEED + (20 if kind == "pine" else 21))
    pair_count = (len(leaf_indices) + 1) // 2
    chosen_pairs = set(choices.choice(pair_count, size=max(1, pair_count // 11), replace=False).tolist())
    chosen_faces = {index for n, index in enumerate(leaf_indices) if n // 2 in chosen_pairs}

    def keep_faces(mesh_data, keep):
        bm = bmesh.new()
        bm.from_mesh(mesh_data)
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[face for face in bm.faces if not keep(face.index, face.material_index)], context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(mesh_data)
        bm.free()
        mesh_data.update()

    keep_faces(obj.data, lambda _i, mat: mat != leaf_material)
    keep_faces(source, lambda index, mat: mat == leaf_material and index in chosen_faces)
    modifier = obj.modifiers.new("Forest_LOD_trunk", "DECIMATE")
    modifier.ratio = .24
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    leaf_obj = bpy.data.objects.new("Preserved_foliage_" + kind, source)
    bpy.context.scene.collection.objects.link(leaf_obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    leaf_obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.join()
    obj.data.validate(clean_customdata=False)
    obj.data.transform(Matrix.Scale(size_factor, 4))
    min_z = min(v.co.z for v in obj.data.vertices)
    obj.data.transform(Matrix.Translation((0, 0, -min_z)))
    add_canopy_cards(obj, kind)
    obj.name = "Prototype_" + kind
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    proto_collection.objects.link(obj)
    obj.location = (0, 0, 0)
    obj.rotation_euler = (0, 0, 0)
    obj.scale = (1, 1, 1)
    print(f"{obj.name}: {len(obj.data.polygons)} low-detail triangles", flush=True)
    return obj

pine = imported_tree("pine", 1.0)
broadleaf = imported_tree("broadleaf", 2.2)
prototypes = {"pine": pine, "broadleaf": broadleaf}

# Blender source exposes every position as a separately editable object while
# linked mesh data keeps the file compact. The Godot scene batches the same
# positions into spatial MultiMeshes, avoiding thousands of draw calls.
forest_objects = []
for index, point in enumerate(trees):
    prototype = prototypes[point["type"]]
    obj = bpy.data.objects.new(f"Tree_{point['type']}_{index + 1:05d}", prototype.data)
    obj.location = (point["x"], point["y"], point["z"])
    obj.rotation_euler.z = point["rotation"]
    obj.scale = (point["scale"],) * 3
    forest_collection.objects.link(obj)
    forest_objects.append(obj)
proto_collection.hide_render = True
proto_collection.hide_viewport = True
print(f"Forest built: {len(forest_objects)} linked, individually movable trees", flush=True)

# The ocean, sun and camera are for Blender presentation only; the GLBs contain
# the terrain/lake/trees, not a gigantic fixed sea plane or a camera.
ocean_mesh = bpy.data.meshes.new("Preview_ocean_mesh")
ocean_mesh.from_pydata([(-7000, -7000, -.5), (7000, -7000, -.5), (7000, 7000, -.5), (-7000, 7000, -.5)], [], [(0, 1, 2, 3)])
ocean_mesh.materials.append(ocean_mat)
ocean = bpy.data.objects.new("PREVIEW_ONLY_Ocean", ocean_mesh)
preview_collection.objects.link(ocean)
light_data = bpy.data.lights.new("Soft daylight", "SUN")
light_data.energy = 2.0
light_data.angle = math.radians(16)
light = bpy.data.objects.new("PREVIEW_ONLY_Sun", light_data)
light.rotation_euler = (math.radians(28), math.radians(-22), math.radians(-32))
preview_collection.objects.link(light)
camera_data = bpy.data.cameras.new("Island overview")
camera_data.type = "ORTHO"
camera_data.ortho_scale = 5500
camera_data.clip_end = 40000
camera = bpy.data.objects.new("PREVIEW_ONLY_Camera", camera_data)
preview_collection.objects.link(camera)
camera.location = (3600, -5000, 12500)
camera.rotation_euler = (Vector((0, 0, 5)) - camera.location).to_track_quat("-Z", "Y").to_euler()
scene.camera = camera

# Pack every imported image into the .blend so it remains independently editable.
bpy.ops.file.pack_all()
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(BLENDER / "island_nature_4km.blend"), compress=True)
print("Saved editable Blender source", flush=True)


def export_glb(path, objects):
    bpy.ops.object.select_all(action="DESELECT")
    proto_collection.hide_viewport = False
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                              export_yup=True, export_animations=False, export_cameras=False,
                              export_lights=False, export_apply=False)
    proto_collection.hide_viewport = True
    print("Exported", path.relative_to(ROOT), round(path.stat().st_size / 1048576, 2), "MiB", flush=True)


export_glb(GODOT / "island_landscape.glb", [terrain, water])
export_glb(GODOT / "tree_pine.glb", [pine])
export_glb(GODOT / "tree_broadleaf.glb", [broadleaf])
export_glb(GLB / "island_4km_complete.glb", [terrain, water, *forest_objects])

scene.render.filepath = str(OUT / "island_model_preview.jpg")
bpy.ops.render.render(write_still=True)
print("Rendered actual 3D model preview", flush=True)
