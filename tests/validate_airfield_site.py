"""Fast structural checks for the standalone, editable airfield scene."""
from __future__ import annotations

import importlib.util
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
script = ROOT / "tools/generate_airfield_site.py"
spec = importlib.util.spec_from_file_location("airfield_site", script)
assert spec and spec.loader
site = importlib.util.module_from_spec(spec)
spec.loader.exec_module(site)
scene = ROOT / "scenes/airfield_full.tscn"
text = scene.read_text(encoding="utf-8")
assert text == site.render(), "scene and deterministic generator disagree"
assert site.FIELD == (900.0, 350.0)
assert site.RUNWAY_LENGTH == 700.0 and site.RUNWAY_WIDTH == 28.0
assert abs(site.RUNWAY_Z) + site.RUNWAY_WIDTH / 2 < site.FIELD[1] / 2
assert site.RUNWAY_LENGTH < site.FIELD[0]
assert len(site.STRUCTURES) == 7 and len(site.PROPS) >= 20
assert len(site.INFECTED) == 15 and len(site.LOOT) == 8 and len(site.STORY) == 2
assert text.count('groups=["airfield_infected_marker"]') == 15
assert text.count('groups=["airfield_loot_marker"]') == 8
assert text.count('groups=["airfield_story_marker"]') == 2
assert text.count('type="MultiMeshInstance3D"') == 6  # batched fence posts
assert text.count('instance=ExtResource("scene_fence_gate")') == 2
assert 'EDITOR_ONLY_' not in text
for path in re.findall(r'path="res://([^"]+)"', text):
    assert (ROOT / path).is_file(), path
for _, _, x, z, _ in site.STRUCTURES:
    assert abs(x) < site.FIELD[0] / 2 and abs(z) < site.FIELD[1] / 2
for name, _, x, z, _, _ in site.PROPS + site.plant_layout():
    assert abs(x) < site.FIELD[0] / 2 and abs(z) < site.FIELD[1] / 2, name
for x, z in site.INFECTED + site.LOOT + [(x, z) for _, x, z in site.STORY]:
    assert abs(x) < site.FIELD[0] / 2 and abs(z) < site.FIELD[1] / 2

# No authored spawn/loot marker should be placed inside a solid prop collider.
for marker in site.INFECTED + site.LOOT + [(x, z) for _, x, z in site.STORY]:
    for name, _, x, z, angle, shape in site.PROPS:
        dx, dz = marker[0] - x, marker[1] - z
        angle = math.radians(angle)
        # Inverse of Godot's yaw about the Y axis.
        lx = math.cos(angle) * dx - math.sin(angle) * dz
        lz = math.sin(angle) * dx + math.cos(angle) * dz
        size = site.COLLIDERS[shape]
        assert abs(lx) >= size[0] / 2 + .15 or abs(lz) >= size[2] / 2 + .15, (marker, name)
print("AIRFIELD SITE STRUCTURE TESTS PASSED: 900 x 350 m, runway 700 x 28 m, two gates, 25 gameplay markers")
