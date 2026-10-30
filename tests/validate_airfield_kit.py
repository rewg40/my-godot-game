#!/usr/bin/env python3
"""Dependency-free structural smoke tests for the authored GLB airfield kit."""
from pathlib import Path
import json
import math
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
KIT = ROOT / "assets/models/airport_kit"
GLB = KIT / "glb"
ASSETS = {
    "hangar_large", "hangar_small", "control_tower", "service_building",
    "fuel_canopy", "fuel_tank", "fuel_pump", "pickup_olive", "pickup_red",
    "utility_truck", "abandoned_sedan", "cargo_crate", "cargo_pallet", "rusty_barrel", "wire_cage",
    "fence_section", "fence_gate", "concrete_barrier", "antenna_mast", "light_pole",
    "roof_panel", "wall_panel", "sliding_door_panel", "runway_10x10", "pine_tree",
    "grass_clump", "shrub", "rock_cluster", "marker_infected", "marker_loot", "marker_story",
}
REQUIRED_PARTS = {
    "hangar_large": ["Floor_concrete_walkable", "Roof_arched_separate", "Wall_left_separate", "Sliding_door_left_OPEN_separate", "Sliding_door_right_OPEN_separate", "MARKER_INFECTED_HANGAR", "MARKER_LOOT_HANGAR"],
    "hangar_small": ["Floor_concrete_walkable", "Roof_gabled_separate", "Sliding_door_-1_OPEN_separate", "Sliding_door_1_OPEN_separate"],
    "service_building": ["Floor_concrete_walkable", "Roof_flat_separate", "Personnel_door_OPEN_separate", "Interior_partition_front", "MARKER_STORY_OFFICE"],
    "control_tower": ["Floor_ground_walkable", "Floor_upper_main_walkable", "Stair_step_01", "Cabin_roof_separate", "MARKER_INFECTED_TOWER"],
    "fence_gate": ["Gate_left_pivot_OPEN", "Gate_right_pivot_OPEN", "Gate_leaf_-1_chain_separate", "Gate_leaf_1_chain_separate"],
    "pickup_olive": ["Chassis_separate", "Body_lower_separate", "Tyre_-1", "Tyre_1", "Roof_rack_separate"],
    "runway_10x10": ["Runway_cracked_asphalt_module_10m", "Surface_crack_strips"],
    "pine_tree": ["Spruce_like_needle_cards_separate", "Spruce_branch_stems_separate"],
    "marker_infected": ["MARKER_INFECTED"],
    "marker_loot": ["MARKER_LOOT"],
    "marker_story": ["MARKER_STORY"],
}


def read_glb(path):
    data = path.read_bytes()
    assert len(data) >= 28, f"{path.name}: truncated"
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF" and version == 2 and length == len(data), f"{path.name}: invalid GLB header"
    json_len, kind = struct.unpack_from("<I4s", data, 12)
    assert kind == b"JSON" and 20 + json_len + 8 <= len(data), f"{path.name}: invalid JSON chunk"
    doc = json.loads(data[20:20+json_len])
    bin_len, bin_kind = struct.unpack_from("<I4s", data, 20+json_len)
    assert bin_kind == b"BIN\0" and 20+json_len+8+bin_len == len(data), f"{path.name}: invalid BIN chunk"
    assert doc.get("asset", {}).get("version") == "2.0"
    buffers = doc.get("buffers", [])
    assert len(buffers) == 1 and "uri" not in buffers[0] and buffers[0]["byteLength"] <= bin_len
    for view in doc.get("bufferViews", []):
        assert view.get("buffer", 0) == 0
        assert view.get("byteOffset", 0) + view["byteLength"] <= buffers[0]["byteLength"]
    for image in doc.get("images", []):
        assert "uri" not in image and 0 <= image["bufferView"] < len(doc["bufferViews"]), f"{path.name}: external texture"
    nodes = doc.get("nodes", [])
    roots = doc["scenes"][doc.get("scene", 0)]["nodes"]
    assert len(roots) == 1 and nodes[roots[0]]["name"] == path.stem
    assert nodes[roots[0]].get("translation", [0, 0, 0]) == [0, 0, 0], f"{path.name}: layout offset leaked into export"
    assert doc.get("meshes"), f"{path.name}: missing geometry"
    names = [n.get("name", "") for n in nodes]
    for prefix in REQUIRED_PARTS.get(path.stem, []):
        assert any(name.startswith(prefix) for name in names), f"{path.name}: missing separate part {prefix}"
    for mesh in doc["meshes"]:
        for primitive in mesh["primitives"]:
            position = doc["accessors"][primitive["attributes"]["POSITION"]]
            assert position["count"] >= 3 and position["type"] == "VEC3"
            assert all(math.isfinite(value) for value in position["min"] + position["max"])
            if "indices" in primitive:
                assert doc["accessors"][primitive["indices"]]["count"] >= 3
    return doc


def main():
    files = {path.stem for path in GLB.glob("*.glb")}
    assert files == ASSETS, f"Missing: {ASSETS-files}; unexpected: {files-ASSETS}"
    docs = {name: read_glb(GLB / f"{name}.glb") for name in sorted(ASSETS)}
    assert any(m.get("alphaMode") == "BLEND" for m in docs["fence_section"]["materials"]), "fence wire alpha was lost"
    for marker in ("marker_infected", "marker_loot", "marker_story"):
        assert any(n.get("extras", {}).get("purpose") for n in docs[marker]["nodes"]), f"{marker}: missing marker metadata"
    assert (KIT / "airport_kit.blend").stat().st_size > 100_000
    scenes = {"hangar_large", "hangar_small", "control_tower", "service_building", "fuel_station", "fence_section", "fence_gate", "runway_10x10"}
    scene_dir = KIT / "godot_scenes"
    assert {p.stem for p in scene_dir.glob("*.tscn")} == scenes
    for scene_name in scenes:
        text = (scene_dir / (scene_name + ".tscn")).read_text(encoding="utf-8")
        links = re.findall(r'path="res://assets/models/airport_kit/glb/([^"]+\.glb)"', text)
        assert links and all((GLB / link).is_file() for link in links), f"{scene_name}: broken model link"
        shapes = text.count('type="CollisionShape3D"')
        assert 'type="StaticBody3D"' in text and shapes > 0
        assert shapes == text.count('[sub_resource type="BoxShape3D"')
    print(f"AIRFIELD GLB TESTS PASSED: {len(ASSETS)} independent models and {len(scenes)} collision scenes")


if __name__ == "__main__":
    main()
