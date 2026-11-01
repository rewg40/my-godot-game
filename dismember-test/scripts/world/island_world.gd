class_name IslandWorld
extends Node3D
## Остров как площадка для заруб.
##
## Модель острова — плотная скульптура (≈1.5 млн треугольников, высота всего
## 6% ширины), поэтому её нельзя ставить в физику как есть. Мир делает так:
##   1. грузит GLB, растягивает до MODEL_SIZE метров и укладывает на ноль;
##   2. снимает карту высот по вершинам модели (сетка GRID×GRID);
##   3. строит по этой сетке статичную коллизию (≈115 тысяч треугольников);
##   4. отдаёт высоты для расстановки игрока, зомби и полёта камеры.
## Если моделей нет, рисуется процедурная заглушка по той же сетке.

const MODEL_IMPROVED := "res://assets/models/island_improved.glb"
const MODEL_PLAIN := "res://assets/models/island.glb"
const MODEL_SIZE := 220.0
const GRID := 241
const FALLBACK_SIZE := 120.0
const FALLBACK_GRID := 121

var heights := PackedFloat32Array()
var grid_size := GRID
var step := 1.0
var half_size := MODEL_SIZE * 0.5
var source := ""

var _body: StaticBody3D


func build() -> void:
	grid_size = GRID
	half_size = MODEL_SIZE * 0.5
	step = MODEL_SIZE / float(GRID - 1)
	var path := ""
	if ResourceLoader.exists(MODEL_IMPROVED):
		path = MODEL_IMPROVED
	elif ResourceLoader.exists(MODEL_PLAIN):
		path = MODEL_PLAIN

	if path.is_empty():
		source = "процедурная заглушка (положите assets/models/island.glb)"
		_build_procedural()
	else:
		source = path.get_file()
		await _build_from_model(path)

	_fill_holes()
	_build_collision()


func _build_from_model(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		source = "процедурная заглушка (%s не читается)" % path.get_file()
		_build_procedural()
		return
	var instance := packed.instantiate()
	add_child(instance)
	await get_tree().process_frame

	# у островов бывает несколько мешей (улучшенный — 60 штук: рельеф, скалы, постройки)
	var meshes := _collect_meshes(instance)
	if meshes.is_empty():
		instance.queue_free()
		source = "процедурная заглушка (в модели нет меша)"
		_build_procedural()
		return

	var box := _bounds_of(meshes)
	var widest := maxf(box.size.x, box.size.z)
	instance.scale = instance.scale * (MODEL_SIZE / maxf(widest, 0.001))
	await get_tree().process_frame

	box = _bounds_of(meshes)
	instance.position += Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)
	await get_tree().process_frame

	_snapshot_heights(meshes)


func _collect_meshes(root: Node) -> Array:
	var result := []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
			result.append(mesh_node)
	return result


func _bounds_of(meshes: Array) -> AABB:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for mesh_node in meshes:
		var box := SceneUtil.world_aabb(mesh_node as MeshInstance3D)
		low = low.min(box.position)
		high = high.max(box.position + box.size)
	return AABB(low, high - low)


func _snapshot_heights(meshes: Array) -> void:
	heights.resize(GRID * GRID)
	heights.fill(-999.0)
	for mesh_node in meshes:
		var snapshot: Transform3D = (mesh_node as MeshInstance3D).global_transform
		var mesh: Mesh = (mesh_node as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			if arrays.is_empty():
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point := snapshot * vertex
				var ix := int(round((point.x + half_size) / step))
				var iz := int(round((point.z + half_size) / step))
				if ix < 0 or ix >= GRID or iz < 0 or iz >= GRID:
					continue
				var index := iz * GRID + ix
				if point.y > heights[index]:
					heights[index] = point.y


func _build_procedural() -> void:
	grid_size = FALLBACK_GRID
	half_size = FALLBACK_SIZE * 0.5
	step = FALLBACK_SIZE / float(FALLBACK_GRID - 1)
	heights.resize(FALLBACK_GRID * FALLBACK_GRID)
	heights.fill(-999.0)

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	for z in grid_size:
		for x in grid_size:
			var world_x := -half_size + x * step
			var world_z := -half_size + z * step
			var radius := Vector2(world_x, world_z).length() / half_size
			var base := (1.0 - radius) * 7.0
			var detail := noise.get_noise_2d(world_x, world_z) * 2.2
			heights[z * grid_size + x] = clampf(base + detail, -2.0, 9.0)

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stride := 2
	for z in range(0, grid_size - 1, stride):
		for x in range(0, grid_size - 1, stride):
			var p00 := _grid_point(x, z)
			var p10 := _grid_point(mini(x + stride, grid_size - 1), z)
			var p01 := _grid_point(x, mini(z + stride, grid_size - 1))
			var p11 := _grid_point(mini(x + stride, grid_size - 1), mini(z + stride, grid_size - 1))
			surface.add_vertex(p00)
			surface.add_vertex(p11)
			surface.add_vertex(p10)
			surface.add_vertex(p00)
			surface.add_vertex(p01)
			surface.add_vertex(p11)
	surface.generate_normals()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.29, 0.34, 0.24)
	material.roughness = 0.9
	var mesh := surface.commit()
	var node := MeshInstance3D.new()
	node.name = "FallbackIsland"
	node.mesh = mesh
	node.material_override = material
	add_child(node)


func _fill_holes() -> void:
	for _pass in 3:
		var copy := heights.duplicate()
		var filled := false
		for z in grid_size:
			for x in grid_size:
				var index := z * grid_size + x
				if copy[index] > -900.0:
					continue
				var sum := 0.0
				var count := 0
				var offsets: Array[int] = [-1, 0, 1]
				for dz in offsets:
					for dx in offsets:
						var nx: int = x + dx
						var nz: int = z + dz
						if nx < 0 or nx >= grid_size or nz < 0 or nz >= grid_size:
							continue
						var value := copy[nz * grid_size + nx]
						if value > -900.0:
							sum += value
							count += 1
				if count > 0:
					heights[index] = sum / float(count)
					filled = true
		if not filled:
			break
	# остатки по краям сетки прижимаем к самому низкому месту острова:
	# получается «отмель» на уровне берега, а не провал до нуля
	var lowest := 0.0
	for index in heights.size():
		if heights[index] > -900.0:
			lowest = heights[index] if lowest == 0.0 else minf(lowest, heights[index])
	for index in heights.size():
		if heights[index] <= -900.0:
			heights[index] = lowest


func _build_collision() -> void:
	var faces := PackedVector3Array()
	for z in grid_size - 1:
		for x in grid_size - 1:
			var p00 := _grid_point(x, z)
			var p10 := _grid_point(x + 1, z)
			var p01 := _grid_point(x, z + 1)
			var p11 := _grid_point(x + 1, z + 1)
			faces.append(p00)
			faces.append(p11)
			faces.append(p10)
			faces.append(p00)
			faces.append(p01)
			faces.append(p11)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true

	if _body != null:
		_body.queue_free()
	_body = StaticBody3D.new()
	_body.name = "Terrain"
	_body.collision_layer = 1
	_body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.name = "HeightField"
	collision.shape = shape
	_body.add_child(collision)
	add_child(_body)


func _grid_point(x: int, z: int) -> Vector3:
	return Vector3(-half_size + x * step, heights[z * grid_size + x], -half_size + z * step)


## Высота земли в любой точке мира (билинейно по сетке).
func height_at(world_x: float, world_z: float) -> float:
	var fx := (world_x + half_size) / step
	var fz := (world_z + half_size) / step
	var x0 := clampi(int(floor(fx)), 0, grid_size - 1)
	var z0 := clampi(int(floor(fz)), 0, grid_size - 1)
	var x1 := mini(x0 + 1, grid_size - 1)
	var z1 := mini(z0 + 1, grid_size - 1)
	var tx := clampf(fx - float(x0), 0.0, 1.0)
	var tz := clampf(fz - float(z0), 0.0, 1.0)
	var h00 := heights[z0 * grid_size + x0]
	var h10 := heights[z0 * grid_size + x1]
	var h01 := heights[z1 * grid_size + x0]
	var h11 := heights[z1 * grid_size + x1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Точка появления игрока: центр площадки, чуть выше земли.
func spawn_point() -> Vector3:
	var point := Vector3(0.0, 0.0, 0.0)
	point.y = height_at(0.0, 0.0) + 0.6
	return point


## Круг из точек вокруг центра — для расстановки зомби.
func ring_points(count: int, radius: float) -> Array:
	var points := []
	for i in count:
		var angle := TAU * float(i) / float(count) + 0.4
		var world_x := cos(angle) * radius
		var world_z := sin(angle) * radius
		points.append(Vector3(world_x, height_at(world_x, world_z) + 0.4, world_z))
	return points
