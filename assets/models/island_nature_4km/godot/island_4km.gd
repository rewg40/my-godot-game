@tool
extends Node3D

# A visual-only nature island.  Each source tree mesh is shared by spatial
# MultiMeshes; unlike the portable GLB, this avoids thousands of draw calls.
const PINE_SCENE = preload("res://assets/models/island_nature_4km/godot/tree_pine.glb")
const BROADLEAF_SCENE = preload("res://assets/models/island_nature_4km/godot/tree_broadleaf.glb")
const FOREST_FILE := "res://assets/models/island_nature_4km/godot/forest_positions.json"
const CELL_SIZE := 550.0

var tree_count := 0


func _ready() -> void:
	if get_node_or_null("ForestCells") != null:
		return
	var file := FileAccess.open(FOREST_FILE, FileAccess.READ)
	if file == null:
		push_error("Island forest positions could not be opened: " + FOREST_FILE)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		push_error("Island forest positions are not a JSON array")
		return
	var meshes := {
		"pine": _first_mesh(PINE_SCENE),
		"broadleaf": _first_mesh(BROADLEAF_SCENE),
	}
	if meshes["pine"] == null or meshes["broadleaf"] == null:
		push_error("Island tree prototype is missing its mesh")
		return
	var groups := {}
	for point in parsed:
		if not point is Dictionary:
			continue
		var kind = point.get("type", "")
		if not meshes.has(kind):
			continue
		# The source was authored Z-up in Blender; GLB imports Y-up in Godot.
		var x := float(point["x"])
		var z := -float(point["y"])
		var cell_x := floori((x + 2200.0) / CELL_SIZE)
		var cell_z := floori((z + 2200.0) / CELL_SIZE)
		var key := "%s_%d_%d" % [kind, cell_x, cell_z]
		if not groups.has(key):
			groups[key] = {"kind": kind, "points": []}
		groups[key]["points"].append(point)
	var forest := Node3D.new()
	forest.name = "ForestCells"
	add_child(forest)
	for key in groups:
		var group = groups[key]
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = meshes[group["kind"]]
		batch.instance_count = group["points"].size()
		for i in range(group["points"].size()):
			var point = group["points"][i]
			var scale := float(point["scale"])
			var basis := Basis(Vector3.UP, float(point["rotation"])).scaled(Vector3.ONE * scale)
			var position := Vector3(float(point["x"]), float(point["z"]), -float(point["y"]))
			batch.set_instance_transform(i, Transform3D(basis, position))
		var node := MultiMeshInstance3D.new()
		node.name = str(key)
		node.multimesh = batch
		forest.add_child(node)
		tree_count += batch.instance_count


func _first_mesh(scene: PackedScene) -> Mesh:
	var root = scene.instantiate()
	var source: MeshInstance3D = root if root is MeshInstance3D else null
	if source == null:
		var children = root.find_children("*", "MeshInstance3D", true, false)
		if not children.is_empty():
			source = children[0] as MeshInstance3D
	var mesh: Mesh = source.mesh if source != null else null
	# Avoid a Godot 4.3 dummy-renderer error when freeing a temporary
	# MeshInstance3D during headless tests (godotengine/godot#86806).
	if source != null and DisplayServer.get_name() == "headless":
		source.mesh = null
	root.free()
	return mesh
