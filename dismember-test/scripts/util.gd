class_name SceneUtil
extends RefCounted
## Мелкие помощники, общие для рига, мира и актёров.


static func first_mesh(root: Node) -> MeshInstance3D:
	var found := root.find_children("*", "MeshInstance3D", true, false)
	for node in found:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
			return mesh_node
	return null


static func to_vector3(values: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if values is Array and values.size() >= 3:
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return fallback


static func world_aabb(mesh_node: MeshInstance3D) -> AABB:
	var local := mesh_node.get_aabb()
	var transform := mesh_node.global_transform
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for index in 8:
		var corner := local.position + local.size * Vector3(
			float(index & 1), float((index >> 1) & 1), float((index >> 2) & 1))
		var point := transform * corner
		low = low.min(point)
		high = high.max(point)
	return AABB(low, high - low)


static func read_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed
