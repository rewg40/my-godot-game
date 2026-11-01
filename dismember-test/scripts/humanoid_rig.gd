class_name HumanoidRig
extends Node3D
## Процедурный «риг» из статичной скульптуры.
##
## Модели в архивах — скульптуры без скелета и анимаций, поэтому тело собрано
## из пяти кусков одного меша (тело и четыре конечности), а движения —
## покачивание частей вокруг шарниров. Отсюда всё остальное: конечность можно
## снять и уронить отдельным объектом, а корпус продолжает ходить без неё.
##
## Шарниры и габариты приходят из *_parts.json (их считает
## tools/prepare_assets.py по настоящей геометрии). Если нарезанных моделей
## нет, собирается примитивная заглушка — полигон всё равно запускается.

signal limb_severed(part_id: String)

var kind := ""
var profile := {}
var parts := {}
var part_bounds := {}
var rest_rotations := {}
var built := false
var placeholder := false
var height := 1.0
var arm_rest_z := 0.0
var body_node: MeshInstance3D

var _cycle := 0.0


## Собирает риг. Возвращает true, если удалось взять нарезанную модель.
func build(model_kind: String, interactive: bool = true) -> bool:
	kind = model_kind
	profile = ModelProfiles.get_profile(model_kind)
	scale = Vector3.ONE * float(profile.get("scale", 1.75))
	var loaded := _build_from_parts(interactive)
	if not loaded:
		_build_placeholder(interactive)
		placeholder = true
	_apply_rest_pose()
	built = true
	return loaded


func _build_from_parts(interactive: bool) -> bool:
	var parts_path := String(profile.get("parts_model", ""))
	if parts_path.is_empty() or not ResourceLoader.exists(parts_path):
		return false
	var meta := SceneUtil.read_json(String(profile.get("meta", "")))
	if meta.is_empty():
		push_warning("%s: нет описания частей %s" % [name, parts_path])
		return false
	var packed := load(parts_path) as PackedScene
	if packed == null:
		return false
	var instance := packed.instantiate()
	var source := SceneUtil.first_mesh(instance)
	if source == null or source.mesh == null:
		instance.queue_free()
		return false

	var mesh := source.mesh
	height = float(meta.get("height", 1.0))
	# угол доворота рук посчитан при нарезке: у T-позы руки вытянуты в стороны,
	# у A-позы уже висят вдоль тела — тогда их трогать не надо
	arm_rest_z = float(meta.get("arm_rest_z", profile.get("arm_rest_z", 0.0)))
	var order: Array = meta.get("order", [])
	var pivots: Dictionary = meta.get("pivots", {})
	var bounds: Dictionary = meta.get("bounds", {})
	var count := mini(mesh.get_surface_count(), order.size())
	for index in count:
		var part_id := String(order[index])
		var part_mesh := _surface_mesh(mesh, index)
		if part_mesh == null:
			continue
		var pivot := SceneUtil.to_vector3(pivots.get(part_id, []))
		var box: Dictionary = bounds.get(part_id, {})
		var low := SceneUtil.to_vector3(box.get("min", []))
		var high := SceneUtil.to_vector3(box.get("max", []))
		_add_part(part_id, part_mesh, pivot, -pivot, low, high, interactive)
	instance.queue_free()
	return parts.size() > 0


func _surface_mesh(mesh: Mesh, index: int) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(index)
	if arrays.is_empty():
		return null
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := mesh.surface_get_material(index)
	if material != null:
		result.surface_set_material(0, material)
	return result


func _add_part(part_id: String, mesh: Mesh, pivot: Vector3, mesh_offset: Vector3,
		low: Vector3, high: Vector3, interactive: bool) -> void:
	if part_id == ModelProfiles.BODY_ID:
		body_node = MeshInstance3D.new()
		body_node.name = "Body"
		body_node.mesh = mesh
		body_node.position = mesh_offset
		add_child(body_node)
		return

	var limb := Limb.new()
	limb.name = part_id
	limb.position = pivot
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Mesh"
	mesh_node.mesh = mesh
	mesh_node.position = mesh_offset
	limb.mesh_instance = mesh_node
	limb.add_child(mesh_node)
	limb.configure(part_id, ModelProfiles.LIMB_HP, interactive)
	if interactive:
		var center := (low + high) * 0.5 - pivot
		var extents := (high - low) * 1.1 + Vector3.ONE * 0.02
		limb.build_zone(extents, center)
	add_child(limb)
	parts[part_id] = limb
	part_bounds[part_id] = {"min": low, "max": high}


func _build_placeholder(interactive: bool) -> void:
	arm_rest_z = float(profile.get("arm_rest_z", 0.0))
	var material := StandardMaterial3D.new()
	material.albedo_color = profile.get("fallback_color", Color(0.5, 0.55, 0.5))
	material.roughness = 0.85
	height = float(profile.get("fallback_height", 1.8)) / maxf(scale.x, 0.001)

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.16
	body_mesh.height = 0.72
	var body_center := Vector3(0.0, 0.62, 0.0)
	_add_primitive(ModelProfiles.BODY_ID, body_mesh, body_center, Vector3.ZERO,
		body_center - Vector3(0.16, 0.36, 0.12), body_center + Vector3(0.16, 0.36, 0.12),
		material, interactive)

	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.1
	head_mesh.height = 0.2
	var head := MeshInstance3D.new()
	head.name = "Head"
	head.mesh = head_mesh
	head.material_override = material
	head.position = Vector3(0.0, 0.98, 0.0)
	add_child(head)

	var leg_mesh := CapsuleMesh.new()
	leg_mesh.radius = 0.075
	leg_mesh.height = 0.5
	for part_id in ["leg_l", "leg_r"]:
		var side: float = -1.0 if part_id == "leg_l" else 1.0
		var pivot := Vector3(side * 0.08, 0.5, 0.0)
		var center := Vector3(side * 0.08, 0.25, 0.0)
		_add_primitive(part_id, leg_mesh, center, pivot,
			center - Vector3(0.08, 0.25, 0.08), center + Vector3(0.08, 0.25, 0.08),
			material, interactive)

	var arm_mesh := CapsuleMesh.new()
	arm_mesh.radius = 0.05
	arm_mesh.height = 0.55
	for part_id in ["arm_l", "arm_r"]:
		var side: float = -1.0 if part_id == "arm_l" else 1.0
		var pivot := Vector3(side * 0.19, 0.82, 0.0)
		var center := Vector3(side * 0.19, 0.56, 0.0)
		_add_primitive(part_id, arm_mesh, center, pivot,
			center - Vector3(0.06, 0.27, 0.06), center + Vector3(0.06, 0.27, 0.06),
			material, interactive)


func _add_primitive(part_id: String, mesh: Mesh, center: Vector3, pivot: Vector3,
		low: Vector3, high: Vector3, material: Material, interactive: bool) -> void:
	if part_id == ModelProfiles.BODY_ID:
		var node := MeshInstance3D.new()
		node.name = "Body"
		node.mesh = mesh
		node.material_override = material
		node.position = center
		add_child(node)
		body_node = node
		return
	var limb := Limb.new()
	limb.name = part_id
	limb.position = pivot
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Mesh"
	mesh_node.mesh = mesh
	mesh_node.material_override = material
	mesh_node.position = center - pivot
	limb.mesh_instance = mesh_node
	limb.add_child(mesh_node)
	limb.configure(part_id, ModelProfiles.LIMB_HP, interactive)
	if interactive:
		limb.build_zone((high - low) * 1.1 + Vector3.ONE * 0.02, (low + high) * 0.5 - pivot)
	add_child(limb)
	parts[part_id] = limb
	part_bounds[part_id] = {"min": low, "max": high}


func _apply_rest_pose() -> void:
	var rest_z := arm_rest_z
	for part_id in parts.keys():
		var limb: Limb = parts[part_id]
		var offset := Vector3.ZERO
		if absf(rest_z) > 0.01 and String(part_id).begins_with("arm"):
			# T-поза: руки вдоль оси X, опускаем их вращением вокруг Z.
			offset.z = deg_to_rad(rest_z) * (1.0 if String(part_id) == "arm_l" else -1.0)
		rest_rotations[part_id] = offset
		limb.rotation = offset


## Поза по состоянию: idle / walk / run / crawl и замах на удар.
func animate(delta: float, mode: String, speed: float, attack: float = -1.0) -> void:
	var rate := 2.6 + speed * 1.6
	if mode == "crawl":
		rate = 4.2 + speed * 2.0
	_cycle += delta * rate
	var swing := sin(_cycle)
	var leg_amplitude := 0.0
	var arm_amplitude := 0.06
	match mode:
		"walk":
			leg_amplitude = 0.42
			arm_amplitude = 0.26
		"run":
			leg_amplitude = 0.72
			arm_amplitude = 0.46
		"crawl":
			leg_amplitude = 0.1
			arm_amplitude = 0.8
		_:
			pass
	_pose("leg_l", swing * leg_amplitude)
	_pose("leg_r", -swing * leg_amplitude)
	var arm_swing := -swing * arm_amplitude
	if mode == "crawl":
		arm_swing = -0.45 + arm_swing
	_pose("arm_l", arm_swing)
	_pose("arm_r", -arm_swing)
	if attack >= 0.0:
		_pose("arm_r", 2.0 * sin(clampf(attack, 0.0, 1.0) * PI))


func _pose(part_id: String, pitch: float, roll: float = 0.0) -> void:
	if not parts.has(part_id):
		return
	var limb: Limb = parts[part_id]
	var rest: Vector3 = rest_rotations.get(part_id, Vector3.ZERO)
	limb.rotation = Vector3(rest.x + pitch, rest.y, rest.z + roll)


## Удар по конечности; true — если она отрублена.
func take_hit(part_id: String, damage: float) -> bool:
	if not parts.has(part_id):
		return false
	var limb: Limb = parts[part_id]
	var severed := limb.take_hit(damage)
	if severed:
		limb_severed.emit(part_id)
	return severed


## Отделяет конечность от рига и отдаёт меш с мировой позой.
func detach(part_id: String) -> Dictionary:
	if not parts.has(part_id):
		return {}
	var limb: Limb = parts[part_id]
	var result := {
		"mesh": limb.mesh_instance.mesh,
		"transform": limb.mesh_instance.global_transform,
	}
	parts.erase(part_id)
	limb.queue_free()
	return result


func limb_count(prefix: String) -> int:
	var count := 0
	for part_id in parts.keys():
		if String(part_id).begins_with(prefix):
			count += 1
	return count


func alive_limbs(prefix: String) -> Array:
	var result := []
	for part_id in parts.keys():
		if String(part_id).begins_with(prefix):
			result.append(part_id)
	return result


## Точка кисти в локальных координатах конечности: самый дальний от шарнира
## угол её габаритов.
func hand_anchor(part_id: String) -> Vector3:
	if not part_bounds.has(part_id) or not parts.has(part_id):
		return Vector3.ZERO
	var data: Dictionary = part_bounds[part_id]
	var low: Vector3 = data["min"]
	var high: Vector3 = data["max"]
	var pivot: Vector3 = parts[part_id].position
	var best := low
	var best_distance := -1.0
	var xs: Array[float] = [low.x, high.x]
	var ys: Array[float] = [low.y, high.y]
	var zs: Array[float] = [low.z, high.z]
	var corners: Array[Vector3] = []
	for x in xs:
		for y in ys:
			for z in zs:
				corners.append(Vector3(x, y, z))
	for corner in corners:
		var distance := corner.distance_squared_to(pivot)
		if distance > best_distance:
			best_distance = distance
			best = corner
	return best - pivot


func set_debug_zones(enabled: bool) -> void:
	for part_id in parts.keys():
		var limb: Limb = parts[part_id]
		limb.set_debug_visible(enabled)


func set_hit_zones_enabled(enabled: bool) -> void:
	for part_id in parts.keys():
		var limb: Limb = parts[part_id]
		if limb.area != null:
			limb.area.collision_layer = 8 if enabled else 0
