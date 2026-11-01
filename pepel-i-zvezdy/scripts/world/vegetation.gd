class_name Vegetation
extends Node3D
## Растительность и камни через MultiMesh.
##
## Два режима:
##   1. Если найден файл точек из репозитория ассетов
##      (растительность_точки.json: [{t, x, y, z, s}, ...]) — используются
##      настоящие точки леса/травы, координаты нормализуются под карту.
##   2. Иначе точки генерируются процедурно по рельефу.
##
## Каждый вид — отдельный MultiMeshInstance3D, поэтому вся трава и лес
## укладываются в пару draw call.

const POINT_FILES := [
	"res://assets/data/vegetation_points.json",
	"res://assets/data/растительность_точки.json",
]
const MAX_TUFTS := 14000
const LAYERS := [
	"trunk_conifer", "top_conifer", "trunk_leaf", "top_leaf",
	"bush", "rock", "grass",
]

var _island: Island
var _rng := RandomNumberGenerator.new()
var _layers := {}
var _instance_count := 0


func setup(island: Island, seed_value: int) -> void:
	_island = island
	_rng.seed = seed_value + 99
	for layer in LAYERS:
		_layers[layer] = []
	var points := _load_points()
	if points.is_empty():
		_generate_procedural()
	else:
		_place_points(points)
	_build_instances()


func instance_count() -> int:
	return _instance_count


# --- Источники точек ---------------------------------------------------------

func _load_points() -> Array:
	for path in POINT_FILES:
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var text := file.get_as_text()
		file.close()
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_ARRAY and not parsed.is_empty():
			print("[Растительность] Точки из файла: %s (%d)" % [path, parsed.size()])
			return parsed
	return []


func _place_points(points: Array) -> void:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var counts := {}
	for point in points:
		if typeof(point) != TYPE_DICTIONARY:
			continue
		min_x = minf(min_x, float(point.get("x", 0.0)))
		max_x = maxf(max_x, float(point.get("x", 0.0)))
		min_z = minf(min_z, float(point.get("y", 0.0)))
		max_z = maxf(max_z, float(point.get("y", 0.0)))
		var kind := String(point.get("t", ""))
		counts[kind] = int(counts.get(kind, 0)) + 1

	var center_x := (min_x + max_x) * 0.5
	var center_z := (min_z + max_z) * 0.5
	var span := maxf(max_x - min_x, max_z - min_z)
	var island_size := float(_island.get_size())
	var factor := island_size * 0.9 / maxf(span, 1.0)
	var tuft_stride := maxi(1, ceili(float(counts.get("tuft", 0)) / float(MAX_TUFTS)))
	var tuft_seen := 0

	for point in points:
		if typeof(point) != TYPE_DICTIONARY:
			continue
		var kind := String(point.get("t", ""))
		if kind == "tuft":
			tuft_seen += 1
			if tuft_seen % tuft_stride != 0:
				continue
		var x := (float(point.get("x", 0.0)) - center_x) * factor
		var z := (float(point.get("y", 0.0)) - center_z) * factor
		var scale_value := float(point.get("s", 1.0)) * 0.8
		_place(kind, x, z, scale_value)


func _generate_procedural() -> void:
	var island_size := float(_island.get_size())
	var half := island_size * 0.46
	var plan := {
		"pine_a": 260, "pine_b": 180, "pine_snow": 30,
		"decid": 200, "decid_b": 140, "bush": 220,
		"rock_a": 70, "rock_b": 45, "rock_c": 35, "tuft": MAX_TUFTS,
	}
	for kind in plan.keys():
		var target: int = plan[kind]
		var placed := 0
		var attempts := 0
		while placed < target and attempts < target * 12:
			attempts += 1
			var x := _rng.randf_range(-half, half)
			var z := _rng.randf_range(-half, half)
			var height := float(_island.height_at(x, z))
			if height < 1.2:
				continue
			if String(kind).begins_with("pine_snow") and height < 30.0:
				continue
			if String(kind) == "tuft" and (height < 2.0 or height > 32.0):
				continue
			if float(_island.slope_at(x, z)) > 0.85:
				continue
			var scale_value := _rng.randf_range(0.55, 1.15)
			if kind == "tuft":
				scale_value = _rng.randf_range(0.7, 1.4)
			_place(kind, x, z, scale_value)
			placed += 1


# --- Расстановка -------------------------------------------------------------

func _place(kind: String, x: float, z: float, scale_value: float) -> void:
	var height := float(_island.height_at(x, z))
	if height < 0.7:
		return
	var pos := Vector3(x, height, z)
	var yaw := _rng.randf() * TAU
	var base := Basis(Vector3.UP, yaw)
	var s := scale_value * _rng.randf_range(0.9, 1.1)

	match kind:
		"pine_a", "pine_b":
			_add_conifer(pos, base, s, Color(0.15, 0.27, 0.17), false)
		"pine_snow":
			_add_conifer(pos, base, s, Color(0.48, 0.56, 0.52), true)
		"decid", "decid_b":
			_add_leaf_tree(pos, base, s, Color(0.26, 0.36, 0.19))
		"bush":
			var bush_color := Color(0.22, 0.31, 0.16).lerp(Color(0.32, 0.4, 0.2), _rng.randf())
			var bush_basis := base.scaled(Vector3(0.9 * s, 0.7 * s, 0.9 * s))
			_add("bush", Transform3D(bush_basis, pos + Vector3(0.0, 0.4 * s, 0.0)), bush_color)
		"rock_a", "rock_b", "rock_c":
			var rock_color := Color(0.36, 0.35, 0.33).lerp(Color(0.5, 0.48, 0.44), _rng.randf())
			var rock_basis := base.scaled(Vector3(1.3 * s, 0.9 * s, 1.1 * s))
			_add("rock", Transform3D(rock_basis, pos + Vector3(0.0, 0.25 * s, 0.0)), rock_color)
		"tuft":
			var grass_color := Color(0.24, 0.34, 0.17).lerp(Color(0.4, 0.46, 0.24), _rng.randf())
			var grass_basis := base.scaled(Vector3(0.5 * s, 0.6 * s, 0.5 * s))
			_add("grass", Transform3D(grass_basis, pos + Vector3(0.0, 0.3 * s, 0.0)), grass_color)


func _add_conifer(pos: Vector3, base: Basis, s: float, color: Color, snowy: bool) -> void:
	var bark := Color(0.24, 0.18, 0.13)
	_add("trunk_conifer", Transform3D(base.scaled(Vector3(0.9 * s, 3.0 * s, 0.9 * s)),
			pos + Vector3(0.0, 1.5 * s, 0.0)), bark)
	var top_color := color
	if snowy:
		top_color = color.lerp(Color(0.86, 0.9, 0.93), 0.55)
	_add("top_conifer", Transform3D(base.scaled(Vector3(1.9 * s, 4.4 * s, 1.9 * s)),
			pos + Vector3(0.0, 4.1 * s, 0.0)), top_color)


func _add_leaf_tree(pos: Vector3, base: Basis, s: float, color: Color) -> void:
	var bark := Color(0.26, 0.2, 0.15)
	_add("trunk_leaf", Transform3D(base.scaled(Vector3(0.85 * s, 2.8 * s, 0.85 * s)),
			pos + Vector3(0.0, 1.4 * s, 0.0)), bark)
	var leaf_color := color.lerp(Color(0.36, 0.45, 0.22), _rng.randf())
	_add("top_leaf", Transform3D(base.scaled(Vector3(1.7 * s, 1.5 * s, 1.7 * s)),
			pos + Vector3(0.0, 3.4 * s, 0.0)), leaf_color)


func _add(layer: String, xform: Transform3D, color: Color) -> void:
	if not _layers.has(layer):
		return
	_layers[layer].append({"x": xform, "c": color})


# --- Сборка MultiMesh --------------------------------------------------------

func _build_instances() -> void:
	var meshes := _make_meshes()
	var materials := _make_materials()
	var shadows := {
		"grass": GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"bush": GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
	}
	for layer in LAYERS:
		var entries: Array = _layers[layer]
		if entries.is_empty():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = meshes[layer]
		multimesh.instance_count = entries.size()
		for i in entries.size():
			var entry: Dictionary = entries[i]
			multimesh.set_instance_transform(i, entry["x"])
			multimesh.set_instance_color(i, entry["c"])
		var node := MultiMeshInstance3D.new()
		node.name = layer
		node.multimesh = multimesh
		node.material_override = materials[layer]
		node.cast_shadow = shadows.get(layer, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		add_child(node)
		_instance_count += entries.size()
	print("[Растительность] Инстансов: %d" % _instance_count)


func _make_materials() -> Dictionary:
	var result := {}
	for layer in LAYERS:
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color.WHITE
		material.roughness = 1.0
		material.metallic = 0.0
		if layer == "grass":
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.roughness = 0.9
		result[layer] = material
	return result


func _make_meshes() -> Dictionary:
	var bark := CylinderMesh.new()
	bark.top_radius = 0.12
	bark.bottom_radius = 0.22
	bark.height = 1.0
	bark.radial_segments = 6
	bark.rings = 1

	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 7
	cone.rings = 1

	var crown := SphereMesh.new()
	crown.radius = 1.0
	crown.height = 2.0
	crown.radial_segments = 8
	crown.rings = 5

	var stone := SphereMesh.new()
	stone.radius = 1.0
	stone.height = 2.0
	stone.radial_segments = 7
	stone.rings = 4

	return {
		"trunk_conifer": bark,
		"trunk_leaf": bark,
		"top_conifer": cone,
		"top_leaf": crown,
		"bush": crown,
		"rock": stone,
		"grass": _make_grass_mesh(),
	}


## Две скрещённые плоскости — дешёвый кустик травы без текстур.
func _make_grass_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.35
	var h := 1.0
	_add_quad(tool, Vector3(-w, 0.0, 0.0), Vector3(w, 0.0, 0.0), Vector3(w, h, 0.0), Vector3(-w, h, 0.0))
	_add_quad(tool, Vector3(0.0, 0.0, -w), Vector3(0.0, 0.0, w), Vector3(0.0, h, w), Vector3(0.0, h, -w))
	return tool.commit()


func _add_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var normal := (b - a).cross(d - a).normalized()
	tool.set_normal(normal)
	tool.set_color(Color.WHITE)
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)
	tool.add_vertex(a)
	tool.add_vertex(c)
	tool.add_vertex(d)
