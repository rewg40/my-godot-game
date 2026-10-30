extends SceneTree

# Tests the separately authored scene without replacing the playable island.
const MeshCleanup = preload("res://scripts/mesh_cleanup.gd")
const SCENE := "res://assets/models/island_nature_4km/godot/island_4km.tscn"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		_fail("island scene did not load")
		return
	var island = packed.instantiate()
	root.add_child(island)
	await process_frame
	var file := FileAccess.open("res://assets/models/island_nature_4km/godot/forest_positions.json", FileAccess.READ)
	var points = JSON.parse_string(file.get_as_text()) if file != null else null
	if not points is Array or island.tree_count != points.size() or island.tree_count < 10000:
		_fail("forest count differs: " + str(island.tree_count))
		return
	var cells = island.get_node_or_null("ForestCells")
	if cells == null or cells.get_child_count() < 10:
		_fail("forest was not divided into spatial MultiMesh cells")
		return
	var total := 0
	for child in cells.get_children():
		if not child is MultiMeshInstance3D or child.multimesh == null or child.multimesh.mesh == null:
			_fail("forest cell has no mesh")
			return
		total += child.multimesh.instance_count
	if total != island.tree_count:
		_fail("forest cell counts do not sum correctly")
		return
	var landscape = island.get_node_or_null("LandscapeAndLake")
	var meshes = landscape.find_children("*", "MeshInstance3D", true, false) if landscape else []
	if meshes.size() < 2:
		_fail("terrain or lake surface did not import")
		return
	var ground: MeshInstance3D
	for item in meshes:
		if "Terrain_4km" in item.name:
			ground = item
	if ground == null or ground.mesh == null:
		_fail("terrain mesh is missing")
		return
	var bounds := ground.mesh.get_aabb()
	if absf(bounds.size.x - 4400.0) > 2.0 or absf(bounds.size.z - 4400.0) > 2.0:
		_fail("terrain size including the submerged shelf is incorrect: " + str(bounds.size))
		return
	MeshCleanup.before_free(island)
	island.free()
	await process_frame
	print("ISLAND 4KM GODOT TESTS PASSED")
	quit(0)

func _fail(message: String) -> void:
	push_error("ISLAND 4KM TESTS FAILED: " + message)
	quit(1)
