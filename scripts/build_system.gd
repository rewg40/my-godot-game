extends Node3D

const BuildPiece = preload("res://scripts/build_piece.gd")
const MeshCleanup = preload("res://scripts/mesh_cleanup.gd")
const WOOD_TEXTURE = preload("res://assets/environment/textures/planks_diff_1k.jpg")
const CELL := 3.0
const WALL_HEIGHT := 2.6
const BUILD_RANGE := 8.0
const TYPES := ["foundation", "wall", "roof", "doorway", "door"]
const NAMES := {"foundation": "Фундамент", "wall": "Стена", "roof": "Крыша", "doorway": "Дверной проём", "door": "Дверь"}
const COSTS := {
	"foundation": {"wood": 4, "stone": 2},
	"wall": {"wood": 3},
	"roof": {"wood": 3},
	"doorway": {"wood": 3},
	"door": {"wood": 2, "iron": 1},
}

var world
var pieces: Dictionary = {} # stable grid key -> BuildPiece
var materials: Dictionary = {}
var active := false
var selected := "foundation"
var rotation_step := 0
var candidate: Dictionary = {}
var reason := "Наведите на землю рядом с персонажем."
var valid := false
var ghost: Node3D
var ghost_signature := ""
var hit_piece: Node3D

func _ready() -> void:
	name = "PlayerConstruction"
	materials["wood"] = _surface(Color("ab9a83"), WOOD_TEXTURE)
	materials["trim"] = _surface(Color("69513e"))
	materials["roof"] = _surface(Color("807a6e"), WOOD_TEXTURE)
	materials["door"] = _surface(Color("947d65"), WOOD_TEXTURE)
	materials["metal"] = _surface(Color("777d78"))
	materials["preview_valid"] = _preview_material(Color(0.25, 0.95, 0.65, 0.54))
	materials["preview_invalid"] = _preview_material(Color(1.0, 0.24, 0.20, 0.54))

func _surface(color: Color, texture: Texture2D = null) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = texture
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return material

func _preview_material(color: Color) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	return material

func toggle() -> void:
	set_active(not active)

func set_active(enabled: bool) -> void:
	active = enabled
	candidate = {}
	valid = false
	reason = "Наведите на землю рядом с персонажем."
	if enabled:
		world.player.cancel_attack()
	else:
		_clear_ghost()
	if is_instance_valid(world.hud):
		world.hud.set_build_mode(enabled)

func select_type(kind: String) -> void:
	if kind not in TYPES:
		return
	selected = kind
	rotation_step = 0
	ghost_signature = ""

func rotate_selection() -> void:
	rotation_step = (rotation_step + 1) % 4
	ghost_signature = ""

func _process(_delta: float) -> void:
	if not active or not is_instance_valid(world.player) or world.is_paused():
		if is_instance_valid(ghost):
			ghost.visible = false
		return
	var hit = cursor_hit()
	hit_piece = _piece_from_collider(hit.get("collider")) if not hit.is_empty() else null
	if hit.is_empty():
		candidate = {}
		valid = false
		reason = "Наведите на землю или существующий фундамент."
		if is_instance_valid(ghost):
			ghost.visible = false
		return
	candidate = candidate_for_point(selected, hit.position)
	if candidate.is_empty():
		valid = false
		reason = "Нужен фундамент рядом." if selected != "door" else "Сначала постройте дверной проём."
		if is_instance_valid(ghost):
			ghost.visible = false
		return
	reason = placement_error(candidate)
	valid = reason.is_empty()
	if valid:
		reason = "Можно построить"
	_update_ghost(candidate, valid)

func cursor_hit() -> Dictionary:
	var camera: Camera3D = world.player.camera
	if not is_instance_valid(camera):
		return {}
	var mouse = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse)
	var to = from + camera.project_ray_normal(mouse) * 300.0
	var query = PhysicsRayQueryParameters3D.create(from, to, 1)
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(query)

func _piece_from_collider(collider):
	var node = collider
	while is_instance_valid(node) and node != self:
		if node.get_parent() == self and node.has_meta("build_key"):
			return node
		node = node.get_parent()
	return null

func _clear_ghost() -> void:
	if is_instance_valid(ghost):
		ghost.visible = false
		MeshCleanup.before_free(ghost)
		ghost.queue_free()
	ghost = null
	ghost_signature = ""

func _update_ghost(record: Dictionary, can_place: bool) -> void:
	var signature := JSON.stringify(record)
	if not is_instance_valid(ghost) or signature != ghost_signature:
		_clear_ghost()
		ghost = BuildPiece.new()
		ghost.configure(record, materials, true)
		add_child(ghost)
		ghost_signature = signature
	ghost.visible = true
	ghost.set_preview_valid(can_place)

func _foundation_key(x: int, z: int) -> String:
	return "f:%d:%d" % [x, z]

func _edge_key(axis: int, x: int, z: int) -> String:
	return "e:%d:%d:%d" % [axis, x, z]

func _door_key(axis: int, x: int, z: int) -> String:
	return "d:%d:%d:%d" % [axis, x, z]

func piece_key(record: Dictionary) -> String:
	var kind: String = record.get("type", "")
	var x := int(record.get("x", 0))
	var z := int(record.get("z", 0))
	match kind:
		"foundation": return _foundation_key(x, z)
		"roof": return "r:%d:%d" % [x, z]
		"wall", "doorway": return _edge_key(int(record.get("axis", 0)), x, z)
		"door": return _door_key(int(record.get("axis", 0)), x, z)
	return ""

func foundation_at(x: int, z: int):
	return pieces.get(_foundation_key(x, z))

func floor_height_at(point: Vector2) -> float:
	var foundation = foundation_at(roundi(point.x / CELL), roundi(point.y / CELL))
	if not is_instance_valid(foundation):
		return -INF
	if absf(point.x - foundation.position.x) > CELL * 0.5 or absf(point.y - foundation.position.z) > CELL * 0.5:
		return -INF
	return float(foundation.data["y"])

# Connected foundations share a level. A new, disconnected base can start at
# any suitable patch of land. Corners are checked to avoid water and cliffs.
func foundation_level(x: int, z: int) -> float:
	var low := INF
	var high := -INF
	for dx in [-1.25, 0.0, 1.25]:
		for dz in [-1.25, 0.0, 1.25]:
			var px = float(x) * CELL + dx
			var pz = float(z) * CELL + dz
			if not world.environment_3d.is_walkable(px, pz, 0.30):
				return INF
			var height: float = world.environment_3d.height_at(px, pz)
			low = minf(low, height)
			high = maxf(high, height)
	if high - low > 0.85:
		return INF
	var level := INF
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbor = foundation_at(x + offset.x, z + offset.y)
		if not is_instance_valid(neighbor):
			continue
		var neighbor_level: float = neighbor.data["y"]
		if is_finite(level) and absf(level - neighbor_level) > 0.08:
			return INF
		level = neighbor_level
	if is_finite(level):
		if high > level + 0.10 or level - low > 0.95:
			return INF
		return level
	return high + 0.08

func _nearest_foundation(point: Vector3):
	var cx := roundi(point.x / CELL)
	var cz := roundi(point.z / CELL)
	var closest = null
	var best := (CELL * 0.9) * (CELL * 0.9)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var foundation = foundation_at(cx + dx, cz + dz)
			if not is_instance_valid(foundation):
				continue
			var distance = Vector2(point.x - foundation.position.x, point.z - foundation.position.z).length_squared()
			if distance < best:
				best = distance
				closest = foundation
	return closest

func _edge_for(foundation, side: int, kind: String) -> Dictionary:
	var x := int(foundation.data["x"])
	var z := int(foundation.data["z"])
	var edge = {"type": kind, "x": x * 2, "z": z * 2, "axis": 0, "y": float(foundation.data["y"])}
	match side:
		0: edge["z"] = z * 2 - 1
		1: edge["x"] = x * 2 + 1; edge["axis"] = 1
		2: edge["z"] = z * 2 + 1
		3: edge["x"] = x * 2 - 1; edge["axis"] = 1
	return edge

func candidate_for_point(kind: String, point: Vector3) -> Dictionary:
	if kind not in TYPES:
		return {}
	if kind == "foundation":
		var x := roundi(point.x / CELL)
		var z := roundi(point.z / CELL)
		var level := foundation_level(x, z)
		if not is_finite(level):
			level = world.environment_3d.height_at(point.x, point.z) + 0.08
		return {"type": kind, "x": x, "z": z, "y": level}
	if kind == "door":
		# A door attaches only to a previously built doorway, on either side.
		var closest = null
		var best := 2.4 * 2.4
		for piece in pieces.values():
			if piece.data.get("type", "") != "doorway":
				continue
			var distance = Vector2(point.x - piece.position.x, point.z - piece.position.z).length_squared()
			if distance < best:
				best = distance
				closest = piece
		if closest == null:
			return {}
		var door: Dictionary = closest.serialize()
		door["type"] = "door"
		door["hinge"] = -1 if rotation_step % 2 == 0 else 1
		door["open"] = false
		return door
	var foundation = _nearest_foundation(point)
	if not is_instance_valid(foundation):
		return {}
	if kind == "roof":
		return {"type": kind, "x": int(foundation.data["x"]), "z": int(foundation.data["z"]), "y": float(foundation.data["y"])}
	var dx: float = point.x - foundation.position.x
	var dz: float = point.z - foundation.position.z
	var side := 0
	if absf(dx) > absf(dz):
		side = 1 if dx >= 0.0 else 3
	else:
		side = 2 if dz >= 0.0 else 0
	return _edge_for(foundation, (side + rotation_step) % 4, kind)

func _record_position(record: Dictionary) -> Vector3:
	var multiplier := CELL if record["type"] in ["foundation", "roof"] else CELL * 0.5
	return Vector3(float(record["x"]) * multiplier, float(record["y"]), float(record["z"]) * multiplier)

func placement_error(record: Dictionary, require_resources: bool = true) -> String:
	if record.is_empty() or record.get("type", "") not in TYPES:
		return "Выберите элемент строительства."
	var kind: String = record["type"]
	var location := _record_position(record)
	if is_instance_valid(world.player):
		var distance = Vector2(location.x - world.player.global_position.x, location.z - world.player.global_position.z).length()
		if distance > BUILD_RANGE:
			return "Слишком далеко: подойдите ближе."
	if pieces.has(piece_key(record)):
		return "Здесь уже установлен элемент."
	if kind == "foundation":
		var level := foundation_level(int(record["x"]), int(record["z"]))
		if not is_finite(level) or absf(level - float(record["y"])) > 0.05:
			return "Нужен достаточно ровный участок суши."
	elif kind == "roof":
		if not is_instance_valid(foundation_at(int(record["x"]), int(record["z"]))):
			return "Крыша крепится над фундаментом."
	elif kind == "door":
		var frame = pieces.get(_edge_key(int(record["axis"]), int(record["x"]), int(record["z"])))
		if not is_instance_valid(frame) or frame.data.get("type", "") != "doorway":
			return "Сначала постройте дверной проём."
	if not _volume_clear(record):
		return "Мешает персонаж, дерево или другой объект."
	if require_resources and not world.can_afford(COSTS[kind]):
		return "Не хватает ресурсов."
	return ""

func _volume_clear(record: Dictionary) -> bool:
	var kind: String = record["type"]
	var size := Vector3(2.76, 2.30, 0.11)
	var center := _record_position(record)
	var angle := 0.0
	match kind:
		"foundation":
			size = Vector3(2.70, 1.35, 2.70)
			center.y += 0.72
		"roof":
			size = Vector3(2.75, 0.18, 2.75)
			center.y += WALL_HEIGHT + 0.10
		"door":
			size = Vector3(1.12, 1.98, 0.09)
			center.y += 1.06
		_:
			center.y += 1.25
	if kind in ["wall", "doorway", "door"] and int(record.get("axis", 0)) == 1:
		angle = PI * 0.5
	var shape = BoxShape3D.new()
	shape.size = size
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP, angle), center)
	query.collision_mask = 1 | 2 | 4
	query.collide_with_areas = false
	var terrain = world.environment_3d.get_node_or_null("IslandCollision") as StaticBody3D
	if is_instance_valid(terrain):
		query.exclude = [terrain.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func place_current() -> bool:
	if not active or candidate.is_empty():
		world.hud.toast(reason)
		return false
	return try_place(candidate)

func try_place(record: Dictionary) -> bool:
	var error := placement_error(record)
	if not error.is_empty():
		world.hud.toast(error)
		return false
	var kind: String = record["type"]
	if not world.spend(COSTS[kind]):
		world.hud.toast("Не хватает ресурсов.")
		return false
	_add_piece(record)
	world.play_sound("complete")
	world.hud.toast(NAMES[kind] + " построен(а).", 1.7)
	if not world.save_progress(false):
		world.hud.toast("Постройка создана, но сохранить игру не удалось.")
	return true

func _add_piece(record: Dictionary) -> void:
	var key := piece_key(record)
	if key.is_empty() or pieces.has(key):
		return
	var piece = BuildPiece.new()
	piece.configure(record, materials)
	piece.set_meta("build_key", key)
	pieces[key] = piece
	add_child(piece)

func serialize() -> Array:
	var result: Array = []
	for piece in pieces.values():
		if is_instance_valid(piece):
			result.append(piece.serialize())
	return result

func restore(saved: Array) -> void:
	# Dependencies are restored in order even if a save lists them differently.
	for kind in TYPES:
		for record in saved:
			if record is Dictionary and record.get("type", "") == kind:
				_add_piece(record)

func first_foundation_position() -> Vector3:
	for piece in pieces.values():
		if is_instance_valid(piece) and piece.data.get("type", "") == "foundation":
			return piece.global_position
	return Vector3(INF, INF, INF)

func nearest_door():
	if not is_instance_valid(world.player):
		return null
	var closest = null
	var best := 2.25 * 2.25
	for piece in pieces.values():
		if piece.data.get("type", "") != "door":
			continue
		var delta: Vector3 = piece.global_position - world.player.global_position
		if absf(delta.y) > 2.5:
			continue
		var distance = Vector2(delta.x, delta.z).length_squared()
		if distance < best:
			best = distance
			closest = piece
	return closest

func interact_door(door) -> void:
	if not is_instance_valid(door):
		return
	var was_open: bool = bool(door.data.get("open", false))
	if was_open and not _volume_clear(door.data):
		world.hud.toast("Нельзя закрыть: в проходе кто-то стоит.")
		return
	door.set_door_open(not was_open)
	world.hud.toast("Дверь открыта." if not was_open else "Дверь закрыта.", 1.5)
	if not world.save_progress(false):
		world.hud.toast("Не удалось сохранить состояние двери.")

func _edge_has_other_foundation(record: Dictionary, removed_x: int, removed_z: int) -> bool:
	var x := int(record["x"])
	var z := int(record["z"])
	var candidates: Array[Vector2i] = []
	if int(record["axis"]) == 0:
		candidates = [Vector2i(x / 2, (z - 1) / 2), Vector2i(x / 2, (z + 1) / 2)]
	else:
		candidates = [Vector2i((x - 1) / 2, z / 2), Vector2i((x + 1) / 2, z / 2)]
	for cell in candidates:
		if (cell.x != removed_x or cell.y != removed_z) and is_instance_valid(foundation_at(cell.x, cell.y)):
			return true
	return false

func remove_piece(piece) -> bool:
	if not is_instance_valid(piece) or not piece.has_meta("build_key"):
		world.hud.toast("Наведите на постройку, чтобы разобрать её.")
		return false
	var location: Vector3 = piece.global_position
	if Vector2(location.x - world.player.global_position.x, location.z - world.player.global_position.z).length() > BUILD_RANGE:
		world.hud.toast("Слишком далеко: подойдите ближе.")
		return false
	var record: Dictionary = piece.data
	var kind: String = record["type"]
	if kind == "doorway" and pieces.has(_door_key(int(record["axis"]), int(record["x"]), int(record["z"]))):
		world.hud.toast("Сначала разберите дверь.")
		return false
	if kind == "foundation":
		var x := int(record["x"])
		var z := int(record["z"])
		if pieces.has("r:%d:%d" % [x, z]):
			world.hud.toast("Сначала разберите крышу над фундаментом.")
			return false
		for side in range(4):
			var edge = _edge_for(piece, side, "wall")
			if pieces.has(piece_key(edge)) and not _edge_has_other_foundation(edge, x, z):
				world.hud.toast("Сначала разберите стены на этом фундаменте.")
				return false
	pieces.erase(String(piece.get_meta("build_key")))
	for item in COSTS[kind]:
		world.give(item, int(COSTS[kind][item]))
	MeshCleanup.before_free(piece)
	piece.queue_free()
	world.hud.toast(NAMES[kind] + " разобран(а); ресурсы возвращены.", 2.0)
	if not world.save_progress(false):
		world.hud.toast("Элемент разобран, но сохранить игру не удалось.")
	return true

func remove_current() -> bool:
	return remove_piece(hit_piece)
