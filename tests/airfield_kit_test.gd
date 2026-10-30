extends SceneTree

# Import and instantiate the actual new GLBs in Godot; no airfield is placed in
# the game world by this test. Geometry/doorway ray tests live in the Blender test.
const MeshCleanup = preload("res://scripts/mesh_cleanup.gd")
const MODEL_DIR := "res://assets/models/airport_kit/glb/"
const ASSETS := [
	"hangar_large", "hangar_small", "control_tower", "service_building",
	"fuel_canopy", "fuel_tank", "fuel_pump", "pickup_olive", "pickup_red",
	"utility_truck", "abandoned_sedan", "cargo_crate", "cargo_pallet", "rusty_barrel",
	"wire_cage", "waste_container", "fence_section", "fence_gate", "concrete_barrier", "antenna_mast",
	"light_pole", "roof_panel", "wall_panel", "sliding_door_panel", "runway_10x10",
	"pine_tree", "grass_clump", "shrub", "rock_cluster", "marker_infected", "marker_loot", "marker_story"
]
const PREFABS := ["hangar_large", "hangar_small", "service_building", "control_tower", "fuel_station", "fence_section", "fence_gate", "runway_10x10"]
const REQUIRED := {
	"hangar_large": ["Floor_concrete_walkable", "Roof_arched_separate", "Sliding_door_left_OPEN_separate", "Sliding_door_right_OPEN_separate", "MARKER_LOOT_HANGAR"],
	"hangar_small": ["Floor_concrete_walkable", "Roof_gabled_separate", "Sliding_door_-1_OPEN_separate"],
	"service_building": ["Floor_concrete_walkable", "Personnel_door_OPEN_separate", "Interior_partition_front", "MARKER_STORY_OFFICE"],
	"control_tower": ["Floor_ground_walkable", "Stair_step_01", "Cabin_roof_separate"],
	"fence_gate": ["Gate_left_pivot_OPEN", "Gate_right_pivot_OPEN"],
}
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func has_named_part(instance: Node, prefix: String) -> bool:
	if String(instance.name).begins_with(prefix):
		return true
	for child in instance.find_children("*", "", true, false):
		if String(child.name).begins_with(prefix):
			return true
	return false

func ray_hits(start: Vector3, end: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(start, end, 1)
	return not root.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func verify_physics(name: String) -> void:
	match name:
		"hangar_large":
			if ray_hits(Vector3(0, 1.2, 18), Vector3(0, 1.2, 11)):
				failures.append("large hangar entrance is blocked")
			if not ray_hits(Vector3(0, 2, 9), Vector3(0, -1, 9)):
				failures.append("large hangar floor has no collision")
			if not ray_hits(Vector3(0, 1.2, 0), Vector3(20, 1.2, 0)):
				failures.append("large hangar side wall has no collision")
		"hangar_small":
			if ray_hits(Vector3(0, 1.2, 13), Vector3(0, 1.2, 7)):
				failures.append("small hangar entrance is blocked")
			if not ray_hits(Vector3(0, 2, 5), Vector3(0, -1, 5)):
				failures.append("small hangar floor has no collision")
		"service_building":
			if ray_hits(Vector3(-4, 1.2, 7), Vector3(-4, 1.2, 3)):
				failures.append("service entrance is blocked")
			if not ray_hits(Vector3(-4, 2, 3), Vector3(-4, -1, 3)):
				failures.append("service floor has no collision")
			if ray_hits(Vector3(-2, 1.2, 0), Vector3(2, 1.2, 0)):
				failures.append("service interior doorway is blocked")
		"control_tower":
			if ray_hits(Vector3(-3.8, 1.2, 7), Vector3(-3.8, 1.2, 3)):
				failures.append("tower entrance is blocked")
			if not ray_hits(Vector3(-3.8, 2, 3), Vector3(-3.8, -1, 3)):
				failures.append("tower floor has no collision")
		"fence_gate":
			if ray_hits(Vector3(0, 1.2, 3), Vector3(0, 1.2, -3)):
				failures.append("open fence gate is blocked")
		"fence_section":
			if not ray_hits(Vector3(0, 1.2, 2), Vector3(0, 1.2, -2)):
				failures.append("fence section has no collision")
		"runway_10x10":
			if not ray_hits(Vector3(0, 2, 0), Vector3(0, -1, 0)):
				failures.append("runway has no floor collision")
		"fuel_station":
			if not ray_hits(Vector3(-1, 1.2, 5), Vector3(-1, 1.2, 0)):
				failures.append("fuel tank has no collision")

func _run() -> void:
	for name in ASSETS:
		var packed := load(MODEL_DIR + name + ".glb") as PackedScene
		if packed == null:
			failures.append("Could not load " + name)
			continue
		var instance := packed.instantiate()
		root.add_child(instance)
		var meshes := instance.find_children("*", "MeshInstance3D", true, false)
		if meshes.is_empty() and not instance is MeshInstance3D:
			failures.append("No mesh in " + name)
		for prefix in REQUIRED.get(name, []):
			if not has_named_part(instance, prefix):
				failures.append(name + " lacks separate part " + prefix)
		MeshCleanup.before_free(instance)
		instance.free()
	for name in PREFABS:
		var packed := load("res://assets/models/airport_kit/godot_scenes/" + name + ".tscn") as PackedScene
		if packed == null:
			failures.append("Could not load prefab " + name)
			continue
		var instance := packed.instantiate()
		root.add_child(instance)
		await physics_frame
		if instance.find_children("*", "CollisionShape3D", true, false).is_empty():
			failures.append("No collision shapes in " + name)
		else:
			verify_physics(name)
		MeshCleanup.before_free(instance)
		instance.free()
		await physics_frame
	if failures.is_empty():
		print("AIRFIELD GODOT IMPORT TESTS PASSED: ", ASSETS.size(), " GLBs and ", PREFABS.size(), " collision scenes")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
