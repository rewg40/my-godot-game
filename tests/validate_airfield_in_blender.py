#!/usr/bin/env python3
"""Re-import real GLBs and ray-test geometry, with Blender 4.3+ / bpy.

Run: blender --background --python tests/validate_airfield_in_blender.py
This checks geometry and Blender round trips, not Godot collision or gameplay.
"""
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
KIT = ROOT / "assets/models/airport_kit"
GLB = KIT / "glb"


def check(condition, message):
    if not condition:
        raise AssertionError(message)
    print("PASS:", message)


def ray_clear(origin, direction, length, label):
    bpy.context.view_layer.update()
    result, hit, normal, face, obj, matrix = bpy.context.scene.ray_cast(
        bpy.context.evaluated_depsgraph_get(), Vector(origin), Vector(direction), distance=length)
    check(not result, label + (f" (hit {obj.name} at {tuple(round(v,2) for v in hit)})" if result else ""))


def floor_below(point, label):
    bpy.context.view_layer.update()
    result, hit, normal, face, obj, matrix = bpy.context.scene.ray_cast(
        bpy.context.evaluated_depsgraph_get(), Vector(point), Vector((0, 0, -1)), distance=4)
    check(result and abs(hit.z) < .3, label + (f" (hit {obj.name})" if result else ""))


def import_asset(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    result = bpy.ops.import_scene.gltf(filepath=str(GLB / (name + ".glb")))
    check("FINISHED" in result, name + " imports into Blender")
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    check(bool(meshes), name + " contains real mesh geometry")
    bpy.context.view_layer.update()
    points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    check(all(abs(coordinate) < 100 for point in points for coordinate in point), name + " exports near the origin in metres")
    triangles = sum(sum(len(face.vertices)-2 for face in obj.data.polygons) for obj in meshes)
    check(triangles > 10, name + " has faces")


def main():
    result = bpy.ops.wm.open_mainfile(filepath=str(KIT / "blender/airport_kit.blend"))
    check("FINISHED" in result, "editable Blender source opens")
    for name in ("hangar_large", "hangar_small", "service_building", "control_tower", "fence_gate", "pine_tree"):
        check(bpy.data.collections.get(name) is not None, name + " has a separate Blender collection")
    used_images = [im for im in bpy.data.images if im.source == "FILE" and im.users > 0]
    check(bool(used_images) and all(im.packed_file is not None for im in used_images), "Blender textures are packed")
    check(bpy.data.objects.get("MARKER_STORY_OFFICE") is not None, "story marker exists without a gameplay script")

    for path in sorted(GLB.glob("*.glb")):
        import_asset(path.stem)
        if path.stem == "hangar_large":
            ray_clear((0,-18,1.2),(0,1,0),7,"large hangar front doorway is genuinely open")
            floor_below((0,-9,2),"large hangar contains an actual floor")
        elif path.stem == "hangar_small":
            ray_clear((0,-13,1.2),(0,1,0),7,"small hangar front doorway is genuinely open")
            floor_below((0,-5,2),"small hangar contains an actual floor")
        elif path.stem == "service_building":
            ray_clear((-4,-7,1.2),(0,1,0),4,"service building entrance is genuinely open")
            floor_below((-4,-3,2),"service building contains an actual floor")
            ray_clear((-2,0,1.2),(1,0,0),4,"service rooms connect through an actual doorway")
        elif path.stem == "control_tower":
            ray_clear((-3.8,-7,1.2),(0,1,0),4,"control tower ground entrance is genuinely open")
            floor_below((-3.8,-3,2),"control tower contains an actual ground floor")
        elif path.stem == "fence_gate":
            ray_clear((0,-2,1.2),(0,1,0),4,"open gate leaves leave a passage")
    print("AIRFIELD BLENDER TESTS PASSED")


if __name__ == "__main__":
    main()
