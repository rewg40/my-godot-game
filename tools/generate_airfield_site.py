"""Build a deterministic, editable 900 x 350 m Godot airfield scene.

The scene is deliberately independent of the small existing island.  Running
this script overwrites scenes/airfield_full.tscn, but never modifies a save,
the island mesh, or the separate Blender/GLB assets.  Open the resulting scene
in the Godot editor: its buildings, props and markers are ordinary scene nodes.
"""
from __future__ import annotations

import math
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "scenes/airfield_full.tscn"
KIT = "res://assets/models/airport_kit/"
FIELD = (900.0, 350.0)
RUNWAY_LENGTH, RUNWAY_WIDTH, RUNWAY_Z = 700.0, 28.0, -54.0
FENCE_X, FENCE_NORTH, FENCE_SOUTH = 432.0, -155.0, 155.0
GATES = (-100.0, 100.0)

# All major building entrances face the central apron/runway, toward -Z.
STRUCTURES = [
    ("HangarLarge", "hangar_large", -118, 65, 180),
    ("HangarSmall", "hangar_small", -50, 65, 180),
    ("ServiceBuilding", "service_building", 10, 75, 180),
    ("ControlTower", "control_tower", 45, 75, 180),
    ("FuelStation", "fuel_station", 91, 61, 180),
    ("GateWest", "fence_gate", -100, 155, 0),
    ("GateEast", "fence_gate", 100, 155, 0),
]

# Model name, position, yaw and a shared, conservative box-collider kind.
PROPS = [
    ("OlivePickup", "pickup_olive", -76, 26, -18, "car"),
    ("RedPickup", "pickup_red", 22, 33, 26, "car"),
    ("UtilityTruck", "utility_truck", 102, 26, -58, "truck"),
    ("AbandonedSedan", "abandoned_sedan", 51, 28, 28, "car"),
    ("CrateHangarA", "cargo_crate", -130, 72, 7, "crate"),
    ("CrateHangarB", "cargo_crate", -128, 72.5, -9, "crate"),
    ("CrateSmallHangar", "cargo_crate", -56, 70, 5, "crate"),
    ("CrateApronA", "cargo_crate", -86, 98, 10, "crate"),
    ("CrateApronB", "cargo_crate", -84.5, 98.3, -5, "crate"),
    ("CrateService", "cargo_crate", 24, 80, 5, "crate"),
    ("PalletApron", "cargo_pallet", -83, 100, 8, "pallet"),
    ("PalletService", "cargo_pallet", 23, 82, -20, "pallet"),
    ("RustyBarrelA", "rusty_barrel", 78, 70, 0, "barrel"),
    ("RustyBarrelB", "rusty_barrel", 79.2, 70.2, 0, "barrel"),
    ("RustyBarrelC", "rusty_barrel", -136, 81, 0, "barrel"),
    ("WireCage", "wire_cage", -78, 99, 4, "cage"),
    ("WasteContainer", "waste_container", 27, 84, -15, "container"),
    ("BarrierA", "concrete_barrier", 62, 119, 10, "barrier"),
    ("BarrierB", "concrete_barrier", 65, 119.5, 10, "barrier"),
    ("BarrierC", "concrete_barrier", -63, 117, -7, "barrier"),
    ("Antenna", "antenna_mast", 63, 90, 0, "antenna"),
    ("LightWest", "light_pole", -147, 33, 80, "pole"),
    ("LightMiddle", "light_pole", -17, 25, 80, "pole"),
    ("LightEast", "light_pole", 122, 33, 80, "pole"),
    ("LightEntranceWest", "light_pole", -108, 146, 0, "pole"),
    ("LightEntranceEast", "light_pole", 92, 146, 0, "pole"),
]

# Invisible Godot editor markers; they deliberately do not spawn game logic.
INFECTED = [
    (-119, 62), (-111, 70), (-52, 65), (-45, 71),
    (9, 75), (40, 70), (51, 81), (86, 63),
    (-92, 25), (-18, 31), (64, 20), (109, 28),
    (-135, 107), (10, 118), (131, 106),
]
LOOT = [(-124, 70), (-54, 71), (-86, 100), (5, 78),
        (38, 73), (80, 68), (25, 83), (109, 29)]
STORY = [("StoryKeycard", 5, 78), ("StoryChip", -54, 71)]

COLLIDERS = {
    "car": (1.9, 1.65, 4.65), "truck": (2.0, 1.9, 5.15),
    "crate": (1.3, 1.3, 1.3), "pallet": (1.2, 0.2, 1.0),
    "barrel": (0.7, 0.98, 0.7), "cage": (2.1, 1.65, 1.5),
    "container": (2.16, 1.32, 1.44), "barrier": (2.8, 1.05, 1.0),
    "antenna": (1.0, 10.0, 1.0), "pole": (0.28, 7.0, 0.28),
}


def n(v: float) -> str:
    return f"{float(v):.6f}".rstrip("0").rstrip(".") or "0"


def v2(x: float, y: float) -> str:
    return f"Vector2({n(x)}, {n(y)})"


def v3(x: float, y: float, z: float) -> str:
    return f"Vector3({n(x)}, {n(y)}, {n(z)})"


def plant_layout() -> list[tuple[str, str, float, float, float, float]]:
    """Low-node-count foliage avoids the runway, apron, buildings and gates."""
    rng = random.Random(638239)
    result = []
    for i in range(175):
        for _ in range(200):
            x = rng.uniform(-420, 420)
            z = rng.uniform(-146, 146)
            if -165 < x < 150 and 7 < z < 124:  # apron and buildings
                continue
            if -355 < x < 355 and abs(z - RUNWAY_Z) < 19:
                continue
            if abs(z - FENCE_SOUTH) < 12 or abs(abs(x) - FENCE_X) < 12:
                continue
            if any(abs(x - g) < 7 and z > 125 for g in GATES):
                continue
            break
        model = "pine_tree" if i < 33 else ("shrub" if i < 83 else "grass_clump")
        scale = rng.uniform(0.64, 0.95) if model == "pine_tree" else rng.uniform(0.65, 1.2)
        result.append((f"{model}_{i:03}", model, x, z, rng.uniform(-180, 180), scale))
    # A few sparse tufts break the runway edges rather than covering the strip.
    for i in range(32):
        x = -325 + i * 21 + rng.uniform(-3, 3)
        z = RUNWAY_Z + (-1 if i % 2 else 1) * rng.uniform(11.5, 14.5)
        result.append((f"RunwayWeed_{i:02}", "grass_clump", x, z, rng.uniform(-180, 180), rng.uniform(.35, .68)))
    return result


def render() -> str:
    ext: list[str] = []
    subs: list[str] = []
    nodes: list[str] = []
    ext_ids: set[str] = set()

    def external(kind: str, path: str, identity: str) -> None:
        if identity not in ext_ids:
            ext_ids.add(identity)
            ext.append(f'[ext_resource type="{kind}" path="{path}" id="{identity}"]')

    def sub(kind: str, identity: str, *props: str) -> None:
        subs.append("\n".join([f'[sub_resource type="{kind}" id="{identity}"]', *props]))

    def node(name: str, kind: str, parent: str, *props: str, instance: str = "", groups: str = "") -> None:
        tag = f'[node name="{name}"'
        if kind:
            tag += f' type="{kind}"'
        tag += f' parent="{parent}"' if parent else ""
        if instance:
            tag += f' instance=ExtResource("{instance}")'
        if groups:
            tag += f' groups=["{groups}"]'
        nodes.append("\n".join([tag + "]", *props]))

    for identity, path in [
        ("grass_tex", "res://assets/environment/textures/grass_short.jpg"),
        ("asphalt_tex", KIT + "textures/cracked_asphalt.jpg"),
        ("concrete_tex", KIT + "textures/weathered_concrete.jpg"),
        ("fence_tex", KIT + "textures/chainlink.png"),
    ]:
        external("Texture2D", path, identity)
    for _, model, *_ in STRUCTURES:
        external("PackedScene", KIT + "godot_scenes/" + model + ".tscn", "scene_" + model)
    for _, model, *_ in PROPS:
        external("PackedScene", KIT + "glb/" + model + ".glb", "model_" + model)
    for model in ("pine_tree", "shrub", "grass_clump"):
        external("PackedScene", KIT + "glb/" + model + ".glb", "model_" + model)

    for identity, texture, tint, uv in [
        ("grass_mat", "grass_tex", "Color(0.69, 0.72, 0.59, 1)", (120, 48)),
        ("asphalt_mat", "asphalt_tex", "Color(0.75, 0.76, 0.72, 1)", (70, 3)),
        ("apron_mat", "concrete_tex", "Color(0.67, 0.67, 0.62, 1)", (30, 10)),
        ("taxi_mat", "asphalt_tex", "Color(0.69, 0.7, 0.67, 1)", (3, 7)),
        ("access_mat", "asphalt_tex", "Color(0.68, 0.69, 0.65, 1)", (2, 5)),
    ]:
        sub("StandardMaterial3D", identity, f"albedo_color = {tint}",
            f'albedo_texture = ExtResource("{texture}")', "roughness = 1.0",
            "texture_repeat = true", f"uv1_scale = {v3(*uv, 1)}")
    sub("StandardMaterial3D", "paint_mat", "albedo_color = Color(0.72, 0.7, 0.6, 1)", "roughness = 1.0")
    sub("StandardMaterial3D", "rust_mat", "albedo_color = Color(0.28, 0.27, 0.22, 1)", "metallic = 0.65", "roughness = 0.85")
    sub("PlaneMesh", "grass_mesh", f"size = {v2(*FIELD)}", 'material = SubResource("grass_mat")')
    sub("BoxShape3D", "ground_shape", f"size = {v3(FIELD[0], .5, FIELD[1])}")
    sub("PlaneMesh", "runway_mesh", f"size = {v2(RUNWAY_LENGTH, RUNWAY_WIDTH)}", 'material = SubResource("asphalt_mat")')
    sub("PlaneMesh", "apron_mesh", f"size = {v2(300, 108)}", 'material = SubResource("apron_mat")')
    sub("PlaneMesh", "taxi_mesh", f"size = {v2(16, 70)}", 'material = SubResource("taxi_mat")')
    sub("PlaneMesh", "access_mesh", f"size = {v2(8, 48)}", 'material = SubResource("access_mat")')
    sub("BoxMesh", "unit_paint", f"size = {v3(1, .012, 1)}", 'material = SubResource("paint_mat")')
    sub("BoxMesh", "unit_rail", f"size = {v3(1, .065, .065)}", 'material = SubResource("rust_mat")')
    sub("CylinderMesh", "post_mesh", "top_radius = 0.07", "bottom_radius = 0.08", "height = 2.65", 'material = SubResource("rust_mat")')
    for identity, size in COLLIDERS.items():
        sub("BoxShape3D", "shape_" + identity, f"size = {v3(*size)}")

    node("AirfieldFull", "Node3D", "", groups="standalone_airfield")
    node("Ground", "Node3D", ".")
    node("GrassTerrain", "MeshInstance3D", "Ground", 'mesh = SubResource("grass_mesh")')
    node("GroundCollision", "StaticBody3D", "Ground", "collision_mask = 0")
    node("GroundShape", "CollisionShape3D", "Ground/GroundCollision", f"position = {v3(0, -.25, 0)}", 'shape = SubResource("ground_shape")')
    node("Runway", "MeshInstance3D", "Ground", f"position = {v3(0, .018, RUNWAY_Z)}", 'mesh = SubResource("runway_mesh")')
    node("Apron", "MeshInstance3D", "Ground", f"position = {v3(-10, .016, 64)}", 'mesh = SubResource("apron_mesh")')
    node("Taxiway", "MeshInstance3D", "Ground", f"position = {v3(-118, .017, -5)}", 'mesh = SubResource("taxi_mesh")')
    for i, x in enumerate(GATES):
        node(f"AccessRoad{i+1}", "MeshInstance3D", "Ground", f"position = {v3(x, .015, 132)}", 'mesh = SubResource("access_mesh")')
    node("RunwayMarkings", "Node3D", ".")
    for side in (-1, 1):
        node(f"EdgeLine{side}", "MeshInstance3D", "RunwayMarkings", f"position = {v3(0, .031, RUNWAY_Z + side * 12.65)}", f"scale = {v3(680, 1, .18)}", 'mesh = SubResource("unit_paint")')
    for i, x in enumerate(range(-326, 327, 14)):
        # Uneven gaps in the old paint are intentional.
        if i in (6, 21, 34):
            continue
        node(f"CentreDash{i:02}", "MeshInstance3D", "RunwayMarkings", f"position = {v3(x, .032, RUNWAY_Z)}", f"scale = {v3(7.0, 1, .28)}", 'mesh = SubResource("unit_paint")')
    for side in (-1, 1):
        for i in range(8):
            x = side * 322
            z = RUNWAY_Z - 9.8 + i * 2.8
            node(f"Threshold{side}_{i}", "MeshInstance3D", "RunwayMarkings", f"position = {v3(x, .032, z)}", f"scale = {v3(11, 1, 1.05)}", 'mesh = SubResource("unit_paint")')
    node("Structures", "Node3D", ".")
    for name, model, x, z, yaw in STRUCTURES:
        node(name, "", "Structures", f"position = {v3(x, .03, z)}", f"rotation = {v3(0, math.radians(yaw), 0)}", instance="scene_" + model, groups="airfield_structure")

    node("Props", "Node3D", ".")
    for name, model, x, z, yaw, collider in PROPS:
        node(name, "Node3D", "Props", f"position = {v3(x, .035, z)}", f"rotation = {v3(0, math.radians(yaw), 0)}", groups="airfield_prop")
        node("Visual", "", f"Props/{name}", instance="model_" + model)
        node("Collision", "StaticBody3D", f"Props/{name}", "collision_mask = 0")
        node("Shape", "CollisionShape3D", f"Props/{name}/Collision", f"position = {v3(0, COLLIDERS[collider][1] / 2, 0)}", f'shape = SubResource("shape_{collider}")')

    # Long fence sections are one alpha-textured quad + one simple collider,
    # not hundreds of heavyweight GLB instances. Gates use the actual kit.
    node("PerimeterFence", "Node3D", ".")
    gaps = [(g - 2.15, g + 2.15) for g in GATES]
    spans = [(-FENCE_X, gaps[0][0]), (gaps[0][1], gaps[1][0]), (gaps[1][1], FENCE_X)]
    fences = [("North", 0, FENCE_NORTH, FENCE_X * 2, 0)]
    fences += [(f"South{i}", (left + right) / 2, FENCE_SOUTH, right - left, 0) for i, (left, right) in enumerate(spans)]
    fences += [("West", -FENCE_X, 0, FENCE_SOUTH - FENCE_NORTH, 90),
               ("East", FENCE_X, 0, FENCE_SOUTH - FENCE_NORTH, 90)]
    for name, x, z, width, yaw in fences:
        sub("StandardMaterial3D", "fence_mat_" + name, 'albedo_texture = ExtResource("fence_tex")',
            "albedo_color = Color(0.72, 0.73, 0.67, 1)", "transparency = 1", "cull_mode = 2", "roughness = 0.95", "texture_repeat = true", f"uv1_scale = {v3(width / 2.4, 1, 1)}")
        sub("QuadMesh", "fence_mesh_" + name, f"size = {v2(width, 2.2)}", f'material = SubResource("fence_mat_{name}")')
        sub("BoxShape3D", "fence_shape_" + name, f"size = {v3(width, 2.4, .12)}")
        path = f"PerimeterFence/{name}"
        node(name, "Node3D", "PerimeterFence", f"position = {v3(x, 0, z)}", f"rotation = {v3(0, math.radians(yaw), 0)}")
        node("Wire", "MeshInstance3D", path, f"position = {v3(0, 1.25, 0)}", f'mesh = SubResource("fence_mesh_{name}")')
        node("Collision", "StaticBody3D", path, "collision_mask = 0")
        node("Shape", "CollisionShape3D", path + "/Collision", f"position = {v3(0, 1.2, 0)}", f'shape = SubResource("fence_shape_{name}")')
        for j, y in enumerate((.15, 2.35)):
            node(f"Rail{j}", "MeshInstance3D", path, f"position = {v3(0, y, 0)}", f"scale = {v3(width, 1, 1)}", 'mesh = SubResource("unit_rail")')
        # One MultiMesh draw per fence span, instead of hundreds of draw calls.
        count = max(1, math.floor(width / 8))
        buffer: list[str] = []
        for j in range(count + 1):
            local_x = -width / 2 + width * j / count
            buffer.extend(["1", "0", "0", n(local_x), "0", "1", "0", "1.325", "0", "0", "1", "0"])
        sub("MultiMesh", "posts_" + name, "transform_format = 1", f"instance_count = {count + 1}",
            'mesh = SubResource("post_mesh")', "buffer = PackedFloat32Array(" + ", ".join(buffer) + ")")
        node("Posts", "MultiMeshInstance3D", path, f'multimesh = SubResource("posts_{name}")')

    node("Vegetation", "Node3D", ".")
    for name, model, x, z, yaw, scale in plant_layout():
        node(name, "", "Vegetation", f"position = {v3(x, .015, z)}", f"rotation = {v3(0, math.radians(yaw), 0)}", f"scale = {v3(scale, scale, scale)}", instance="model_" + model)

    node("SpawnAndLootMarkers", "Node3D", ".")
    for prefix, positions, group in [("Infected", INFECTED, "airfield_infected_marker"), ("Loot", LOOT, "airfield_loot_marker")]:
        for i, (x, z) in enumerate(positions):
            node(f"{prefix}{i+1:02}", "Marker3D", "SpawnAndLootMarkers", f"position = {v3(x, .05, z)}", groups=group)
    for name, x, z in STORY:
        node(name, "Marker3D", "SpawnAndLootMarkers", f"position = {v3(x, .05, z)}", groups="airfield_story_marker")
    node("VisitorSpawn", "Marker3D", "SpawnAndLootMarkers", f"position = {v3(-100, .08, 139)}", groups="airfield_visitor_spawn")

    header = f"[gd_scene load_steps={1 + len(ext) + len(subs)} format=3]"
    return "\n\n".join([header, *ext, *subs, *nodes]) + "\n"


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    contents = render()
    OUTPUT.write_text(contents, encoding="utf-8")
    print(f"Wrote {OUTPUT.relative_to(ROOT)}: {len(contents):,} characters, {len(STRUCTURES)} structures, {len(PROPS)} props and {len(plant_layout())} plants")


if __name__ == "__main__":
    main()
