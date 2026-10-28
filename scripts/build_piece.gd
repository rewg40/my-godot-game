extends Node3D

# One modular 3D piece. All dimensions are in metres; the controller positions
# these parts on a 3 m grid, but a base is not tied to a predefined location.
const CELL := 3.0
const WALL_HEIGHT := 2.6
const DOOR_WIDTH := 1.32
const DOOR_HEIGHT := 2.12
# The source models are from the repository's 05_buildings_structures set.
# We adapt their timber geometry to the existing 3 m snapping grid.
const PLANK_PLATFORM = preload("res://assets/models/construction/pir/pir_platform.glb")
const PLANK_ROOF = preload("res://assets/models/construction/pir/pir_platform-planks.glb")
const TIMBER_FRAME = preload("res://assets/models/construction/tower/td_wood-structure-high-part.glb")
# The camera ignores this layer; characters and construction still collide.
const ROOF_COLLISION_LAYER := 1 << 3

var data: Dictionary = {}
var preview := false
var materials: Dictionary = {}
var hinge: Node3D
var door_tween: Tween
var roof_hidden := false

func configure(piece_data: Dictionary, palette: Dictionary, is_preview: bool = false) -> void:
	data = piece_data.duplicate(true)
	materials = palette
	preview = is_preview
	var kind: String = data.get("type", "")
	var y := float(data.get("y", 0.0))
	if kind in ["foundation", "roof"]:
		position = Vector3(float(data["x"]) * CELL, y, float(data["z"]) * CELL)
		if kind == "roof":
			position.y += WALL_HEIGHT
	else:
		position = Vector3(float(data["x"]) * CELL * 0.5, y, float(data["z"]) * CELL * 0.5)
		rotation.y = PI * 0.5 if int(data.get("axis", 0)) == 1 else 0.0
	name = "Built_" + kind
	_build(kind)

func _build(kind: String) -> void:
	match kind:
		"foundation":
			_part(Vector3(2.96, 0.20, 2.96), Vector3(0, -0.10, 0), "wood", true, null, false)
			_flat_model(PLANK_PLATFORM, Vector3(2.96, 0.20, 2.96), Vector3(0, -0.20, 0), "wood")
			for z in [-1.40, 1.40]:
				_part(Vector3(2.96, 0.10, 0.10), Vector3(0, -0.02, z), "trim")
		"wall":
			_part(Vector3(2.96, WALL_HEIGHT, 0.14), Vector3(0, WALL_HEIGHT * 0.5, 0), "wood", true, null, false)
			_upright_model(Vector3(2.96, WALL_HEIGHT, 0.14), Vector3(0, WALL_HEIGHT * 0.5, 0), "wood")
			_add_timber_frame()
			for x in [-1.38, 0.0, 1.38]:
				_part(Vector3(0.10, WALL_HEIGHT, 0.19), Vector3(x, WALL_HEIGHT * 0.5, 0), "trim")
			_part(Vector3(2.96, 0.10, 0.20), Vector3(0, WALL_HEIGHT - 0.08, 0), "trim")
		"doorway":
			var side_width := (CELL - DOOR_WIDTH) * 0.5
			for sign in [-1.0, 1.0]:
				var x: float = sign * (DOOR_WIDTH * 0.5 + side_width * 0.5)
				var dimensions := Vector3(side_width - 0.02, WALL_HEIGHT, 0.14)
				var center := Vector3(x, WALL_HEIGHT * 0.5, 0)
				_part(dimensions, center, "wood", true, null, false)
				_upright_model(dimensions, center, "wood")
				_part(Vector3(0.10, WALL_HEIGHT, 0.20), Vector3(sign * DOOR_WIDTH * 0.5, WALL_HEIGHT * 0.5, 0), "trim")
			var top_height := WALL_HEIGHT - DOOR_HEIGHT
			var top_size := Vector3(DOOR_WIDTH, top_height, 0.14)
			var top_center := Vector3(0, DOOR_HEIGHT + top_height * 0.5, 0)
			_part(top_size, top_center, "wood", true, null, false)
			_upright_model(top_size, top_center, "wood")
			_part(Vector3(DOOR_WIDTH + 0.1, 0.10, 0.20), Vector3(0, DOOR_HEIGHT, 0), "trim")
		"roof":
			_part(Vector3(2.96, 0.18, 2.96), Vector3(0, 0.09, 0), "roof", true, null, false)
			_flat_model(PLANK_ROOF, Vector3(2.96, 0.18, 2.96), Vector3.ZERO, "roof")
			for z in [-1.25, 1.25]:
				_part(Vector3(2.96, 0.10, 0.12), Vector3(0, -0.02, z), "trim")
		"door":
			var side := -1.0 if int(data.get("hinge", -1)) < 0 else 1.0
			hinge = Node3D.new()
			hinge.name = "DoorHinge"
			hinge.position.x = side * (DOOR_WIDTH * 0.5 - 0.035)
			add_child(hinge)
			var center_x := -side * (DOOR_WIDTH * 0.5 - 0.05)
			var panel_size := Vector3(DOOR_WIDTH - 0.10, DOOR_HEIGHT - 0.05, 0.12)
			var panel_center := Vector3(center_x, DOOR_HEIGHT * 0.5, 0)
			_part(panel_size, panel_center, "door", true, hinge, false)
			_upright_model(panel_size, panel_center, "door", hinge)
			for h in [0.30, 1.76]:
				_part(Vector3(DOOR_WIDTH - 0.12, 0.10, 0.17), Vector3(center_x, h, 0), "trim", false, hinge)
			_part(Vector3(0.10, 0.12, 0.23), Vector3(-side * (DOOR_WIDTH - 0.22), 1.05, 0), "metal", false, hinge)
			_apply_door_pose(false)

func _part(size: Vector3, at: Vector3, material_key: String, collidable: bool = false, parent: Node3D = null, show_visual: bool = true) -> void:
	var target: Node3D = self if parent == null else parent
	if show_visual:
		var box = BoxMesh.new()
		box.size = size
		box.material = materials.get(material_key)
		var visual = MeshInstance3D.new()
		visual.mesh = box
		visual.position = at
		if preview:
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		target.add_child(visual)
	if collidable and not preview:
		var body = StaticBody3D.new()
		body.collision_layer = ROOF_COLLISION_LAYER if data.get("type", "") == "roof" else 1
		body.collision_mask = 0
		body.set_meta("player_built", true)
		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		collision.position = at
		body.add_child(collision)
		target.add_child(body)

func _apply_model_material(model: Node3D, material_key: String) -> void:
	var meshes = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.push_front(model)
	for mesh in meshes:
		(mesh as MeshInstance3D).material_override = materials.get(material_key)
		if preview:
			(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _flat_model(scene: PackedScene, size: Vector3, at: Vector3, material_key: String) -> void:
	var model := scene.instantiate() as Node3D
	var source_size := Vector3(1.894, 0.428, 2.702) if scene == PLANK_ROOF else Vector3(2.50, 0.228, 2.513)
	model.scale = size / source_size
	model.position = at
	model.set_meta("construction_model", true)
	_apply_model_material(model, material_key)
	add_child(model)

func _upright_model(size: Vector3, at: Vector3, material_key: String, parent: Node3D = null) -> void:
	var model := PLANK_PLATFORM.instantiate() as Node3D
	model.scale = Vector3(size.x / 2.50, size.z / 0.228, size.y / 2.513)
	model.rotation.x = PI * 0.5
	model.position = at + Vector3(0, 0, -size.z * 0.5)
	model.set_meta("construction_model", true)
	_apply_model_material(model, material_key)
	(self if parent == null else parent).add_child(model)

func _add_timber_frame() -> void:
	var model := TIMBER_FRAME.instantiate() as Node3D
	model.scale = Vector3(2.96, WALL_HEIGHT, 0.40)
	model.position = Vector3(0, 0, 0.27)
	model.set_meta("construction_model", true)
	_apply_model_material(model, "trim")
	add_child(model)

func set_roof_hidden(hidden: bool) -> void:
	if data.get("type", "") != "roof" or preview or roof_hidden == hidden:
		return
	roof_hidden = hidden
	# Only the visual disappears: the slab remains solid to actors and rays.
	for mesh in find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).visible = not hidden

func set_preview_valid(valid: bool) -> void:
	if not preview:
		return
	var material: Material = materials["preview_valid"] if valid else materials["preview_invalid"]
	for mesh in find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = material

func set_door_open(open: bool, animate: bool = true) -> void:
	if data.get("type", "") != "door" or not is_instance_valid(hinge):
		return
	data["open"] = open
	_apply_door_pose(animate)

func _apply_door_pose(animate: bool) -> void:
	if not is_instance_valid(hinge):
		return
	var side := -1.0 if int(data.get("hinge", -1)) < 0 else 1.0
	var target_angle := side * PI * 0.5 if bool(data.get("open", false)) else 0.0
	if is_instance_valid(door_tween):
		door_tween.kill()
	if animate and is_inside_tree():
		door_tween = create_tween()
		door_tween.tween_property(hinge, "rotation:y", target_angle, 0.28)
	else:
		hinge.rotation.y = target_angle

func serialize() -> Dictionary:
	return data.duplicate(true)
