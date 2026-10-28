extends Node3D

# One modular 3D piece. All dimensions are in metres; the controller positions
# these parts on a 3 m grid, but a base is not tied to a predefined location.
const CELL := 3.0
const WALL_HEIGHT := 2.6
const DOOR_WIDTH := 1.32
const DOOR_HEIGHT := 2.12

var data: Dictionary = {}
var preview := false
var materials: Dictionary = {}
var hinge: Node3D
var door_tween: Tween

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
			_part(Vector3(2.96, 0.20, 2.96), Vector3(0, -0.10, 0), "wood", true)
			for z in [-1.40, 1.40]:
				_part(Vector3(2.96, 0.10, 0.10), Vector3(0, -0.02, z), "trim")
		"wall":
			_part(Vector3(2.96, WALL_HEIGHT, 0.14), Vector3(0, WALL_HEIGHT * 0.5, 0), "wood", true)
			for x in [-1.38, 0.0, 1.38]:
				_part(Vector3(0.10, WALL_HEIGHT, 0.19), Vector3(x, WALL_HEIGHT * 0.5, 0), "trim")
			_part(Vector3(2.96, 0.10, 0.20), Vector3(0, WALL_HEIGHT - 0.08, 0), "trim")
		"doorway":
			var side_width := (CELL - DOOR_WIDTH) * 0.5
			for sign in [-1.0, 1.0]:
				var x: float = sign * (DOOR_WIDTH * 0.5 + side_width * 0.5)
				_part(Vector3(side_width - 0.02, WALL_HEIGHT, 0.14), Vector3(x, WALL_HEIGHT * 0.5, 0), "wood", true)
				_part(Vector3(0.10, WALL_HEIGHT, 0.20), Vector3(sign * DOOR_WIDTH * 0.5, WALL_HEIGHT * 0.5, 0), "trim")
			var top_height := WALL_HEIGHT - DOOR_HEIGHT
			_part(Vector3(DOOR_WIDTH, top_height, 0.14), Vector3(0, DOOR_HEIGHT + top_height * 0.5, 0), "wood", true)
			_part(Vector3(DOOR_WIDTH + 0.1, 0.10, 0.20), Vector3(0, DOOR_HEIGHT, 0), "trim")
		"roof":
			_part(Vector3(2.96, 0.18, 2.96), Vector3(0, 0.09, 0), "roof", true)
			for z in [-1.25, 1.25]:
				_part(Vector3(2.96, 0.10, 0.12), Vector3(0, -0.02, z), "trim")
		"door":
			var side := -1.0 if int(data.get("hinge", -1)) < 0 else 1.0
			hinge = Node3D.new()
			hinge.name = "DoorHinge"
			hinge.position.x = side * (DOOR_WIDTH * 0.5 - 0.035)
			add_child(hinge)
			var center_x := -side * (DOOR_WIDTH * 0.5 - 0.05)
			_part(Vector3(DOOR_WIDTH - 0.10, DOOR_HEIGHT - 0.05, 0.12), Vector3(center_x, DOOR_HEIGHT * 0.5, 0), "door", true, hinge)
			for h in [0.30, 1.76]:
				_part(Vector3(DOOR_WIDTH - 0.12, 0.10, 0.17), Vector3(center_x, h, 0), "trim", false, hinge)
			_part(Vector3(0.10, 0.12, 0.23), Vector3(-side * (DOOR_WIDTH - 0.22), 1.05, 0), "metal", false, hinge)
			_apply_door_pose(false)

func _part(size: Vector3, at: Vector3, material_key: String, collidable: bool = false, parent: Node3D = null) -> void:
	var target: Node3D = self if parent == null else parent
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
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("player_built", true)
		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		collision.position = at
		body.add_child(collision)
		target.add_child(body)

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
