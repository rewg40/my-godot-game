class_name Island
extends Node3D
## Остров: рельеф, вода и точки для расстановки объектов.
##
## По умолчанию рельеф строится процедурно из шума (вершины раскрашиваются по
## высоте: песок → трава → камень → снег). Если в assets/models лежит
## island.glb, используется готовая модель из репозитория ассетов: она
## масштабируется под размер карты, а высоты берутся рейкастами.

const TEMPLATE_GLB := "res://assets/models/island.glb"
const RESOLUTION := 148
const SIZE := 240.0
const MAX_HEIGHT := 52.0
const SEA_LEVEL := 0.0

var world_seed := 1
var heights := PackedFloat32Array()
var spawn_point := Vector3(0.0, 12.0, 0.0)
var using_glb := false

var _cells := RESOLUTION
var _continent: FastNoiseLite
var _detail: FastNoiseLite
var _ridge: FastNoiseLite
var _mesh_instance: MeshInstance3D
var _water: MeshInstance3D


func setup(p_seed: int) -> void:
	world_seed = p_seed
	_prepare_noise()
	if ResourceLoader.exists(TEMPLATE_GLB):
		_build_from_model()
	else:
		_build_procedural()
	_build_water()
	await get_tree().physics_frame
	await get_tree().physics_frame
	spawn_point = _find_spawn_point()


func _prepare_noise() -> void:
	_continent = FastNoiseLite.new()
	_continent.seed = world_seed
	_continent.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_continent.frequency = 1.0
	_continent.fractal_type = FastNoiseLite.FRACTAL_FBM
	_continent.fractal_octaves = 4

	_detail = FastNoiseLite.new()
	_detail.seed = world_seed + 917
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = 1.0
	_detail.fractal_octaves = 3

	_ridge = FastNoiseLite.new()
	_ridge.seed = world_seed + 4231
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge.frequency = 1.0
	_ridge.fractal_octaves = 2


# --- Генерация рельефа -------------------------------------------------------

func _build_procedural() -> void:
	var side := _cells + 1
	heights = PackedFloat32Array()
	heights.resize(side * side)
	for iz in side:
		for ix in side:
			var nx := ((float(ix) / float(_cells)) - 0.5) * 2.0
			var nz := ((float(iz) / float(_cells)) - 0.5) * 2.0
			heights[iz * side + ix] = _sample_shape(nx, nz)

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in side:
		for ix in side:
			var x := (float(ix) / float(_cells) - 0.5) * SIZE
			var z := (float(iz) / float(_cells) - 0.5) * SIZE
			var y := heights[iz * side + ix]
			tool.set_normal(_normal_at_index(ix, iz))
			tool.set_color(_vertex_color(y, x, z))
			tool.set_uv(Vector2(float(ix) / float(_cells), float(iz) / float(_cells)) * 14.0)
			tool.add_vertex(Vector3(x, y, z))

	for iz in _cells:
		for ix in _cells:
			var i0 := iz * side + ix
			var i1 := i0 + 1
			var i2 := i0 + side
			var i3 := i2 + 1
			tool.add_index(i0)
			tool.add_index(i2)
			tool.add_index(i1)
			tool.add_index(i1)
			tool.add_index(i2)
			tool.add_index(i3)

	var mesh: ArrayMesh = tool.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Terrain"
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = material
	add_child(_mesh_instance)
	_add_collision(mesh)


func _sample_shape(nx: float, nz: float) -> float:
	var dist := sqrt(nx * nx + nz * nz)
	var falloff := 1.0 - smoothstep(0.42, 1.02, dist)
	var continent := _continent.get_noise_2d(nx * 2.1, nz * 2.1) * 0.5 + 0.5
	var hills := _detail.get_noise_2d(nx * 6.5, nz * 6.5)
	var ridge := 1.0 - absf(_ridge.get_noise_2d(nx * 3.4, nz * 3.4))
	var mass := continent * continent
	var height := (mass * (0.72 + hills * 0.22) + ridge * 0.26 * mass) * MAX_HEIGHT
	height = height * falloff - 5.0
	return height


func _normal_at_index(ix: int, iz: int) -> Vector3:
	var side := _cells + 1
	var step := SIZE / float(_cells)
	var left := heights[iz * side + maxi(ix - 1, 0)]
	var right := heights[iz * side + mini(ix + 1, _cells)]
	var down := heights[maxi(iz - 1, 0) * side + ix]
	var up := heights[mini(iz + 1, _cells) * side + ix]
	var normal := Vector3(left - right, 2.0 * step, down - up)
	return normal.normalized()


func _vertex_color(y: float, x: float, z: float) -> Color:
	var variation := _detail.get_noise_2d(x * 3.0, z * 3.0) * 0.5 + 0.5
	var sand := Color(0.70, 0.65, 0.52)
	var grass := Color(0.20, 0.30, 0.17).lerp(Color(0.33, 0.42, 0.24), variation)
	var rock := Color(0.31, 0.30, 0.29).lerp(Color(0.44, 0.42, 0.39), variation)
	var snow := Color(0.83, 0.87, 0.91)
	var color := sand
	if y > 2.5:
		color = sand.lerp(grass, clampf((y - 2.5) / 4.5, 0.0, 1.0))
	if y > 24.0:
		color = color.lerp(rock, clampf((y - 24.0) / 9.0, 0.0, 1.0))
	if y > 38.0:
		color = color.lerp(snow, clampf((y - 38.0) / 8.0, 0.0, 1.0))
	if y < 0.8:
		color = color.lerp(Color(0.26, 0.32, 0.32), clampf((0.8 - y) / 3.0, 0.0, 1.0))
	return color


func _add_collision(mesh: Mesh) -> void:
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE * 4.0, SIZE * 4.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.05, 0.13, 0.18, 0.86)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.08
	material.metallic = 0.25
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_water = MeshInstance3D.new()
	_water.name = "Sea"
	_water.mesh = plane
	_water.material_override = material
	_water.position.y = SEA_LEVEL - 0.15
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)


# --- Модель из репозитория ассетов ------------------------------------------

func _build_from_model() -> void:
	var packed := load(TEMPLATE_GLB) as PackedScene
	if packed == null:
		_build_procedural()
		return
	var model := packed.instantiate() as Node3D
	if model == null:
		_build_procedural()
		return
	using_glb = true
	model.name = "TerrainModel"
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		model.queue_free()
		_build_procedural()
		return
	var first: MeshInstance3D = meshes[0]
	var box: AABB = first.get_aabb()
	var span := maxf(box.size.x, box.size.z)
	var factor := SIZE / maxf(span, 0.001)
	model.scale = Vector3.ONE * factor
	model.position = Vector3(
		-box.get_center().x * factor,
		-box.position.y * factor,
		-box.get_center().z * factor
	)
	add_child(model)
	for mesh_node in model.find_children("*", "MeshInstance3D", true, false):
		mesh_node.create_trimesh_collision()


# --- Запросы к рельефу -------------------------------------------------------

## Высота поверхности в мировых координатах.
func height_at(x: float, z: float) -> float:
	if using_glb:
		return _raycast_height(x, z)
	if heights.is_empty():
		return SEA_LEVEL - 5.0
	var side := _cells + 1
	var fx := (x / SIZE + 0.5) * float(_cells)
	var fz := (z / SIZE + 0.5) * float(_cells)
	if fx < 0.0 or fz < 0.0 or fx >= float(_cells) or fz >= float(_cells):
		return SEA_LEVEL - 8.0
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var h00 := heights[iz * side + ix]
	var h10 := heights[iz * side + ix + 1]
	var h01 := heights[(iz + 1) * side + ix]
	var h11 := heights[(iz + 1) * side + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Перепад высот на участке 1.5 м — чем больше, тем круче склон.
func slope_at(x: float, z: float) -> float:
	var d := 1.5
	var hx := height_at(x + d, z) - height_at(x - d, z)
	var hz := height_at(x, z + d) - height_at(x, z - d)
	return Vector2(hx, hz).length() / (2.0 * d)


func is_land(x: float, z: float) -> bool:
	return height_at(x, z) > SEA_LEVEL + 0.4


func is_inside(x: float, z: float) -> bool:
	return absf(x) < SIZE * 0.5 and absf(z) < SIZE * 0.5


func _raycast_height(x: float, z: float) -> float:
	if not is_inside_tree() or get_world_3d() == null:
		return SEA_LEVEL
	var space := get_world_3d().direct_space_state
	var from := Vector3(x, 400.0, z)
	var to := Vector3(x, -60.0, z)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return SEA_LEVEL - 8.0
	return float(hit["position"].y)


func _find_spawn_point() -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var candidates: Array[Vector3] = []
	var tries := 900
	for i in tries:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(SIZE * 0.16, SIZE * 0.36)
		var x := cos(angle) * radius
		var z := sin(angle) * radius
		if not is_land(x, z):
			continue
		var y := height_at(x, z)
		if y < 1.6 or y > 12.0:
			continue
		if slope_at(x, z) > 0.45:
			continue
		candidates.append(Vector3(x, y + 0.6, z))
	if candidates.is_empty():
		return Vector3(0.0, height_at(0.0, 0.0) + 2.0, 0.0)
	return candidates[rng.randi() % candidates.size()]


func get_spawn_point() -> Vector3:
	return spawn_point


## Сторона карты в метрах — нужна расстановщику растительности.
func get_size() -> float:
	return SIZE
