extends Node3D

const ActorVisual = preload("res://scripts/model_3d.gd")
const MeshCleanup = preload("res://scripts/mesh_cleanup.gd")
const Ruins3D = preload("res://scripts/ruins_3d.gd")
const REAL_NATURE = "res://assets/models/nature_real/"
const WOOD_TEXTURE = preload("res://assets/environment/textures/planks_diff_1k.jpg")
const METAL_TEXTURE = preload("res://assets/environment/textures/metal_diff_1k.jpg")
const FONT = preload("res://assets/fonts/DejaVuSans-Bold.ttf")
const NATURE = "res://assets/models/kenney/nature/"
const SURVIVAL = "res://assets/models/kenney/survival/"
const CHARACTERS = "res://assets/models/characters/"

var world
var prop_id: String = ""
var kind: String = ""
var title: String = ""
var detail: Dictionary = {}
var usable: bool = true
var respawn_at: float = 0.0
var visual: Node3D
var flame: Node3D
var idle_actor: Node3D

func configure(owner_world, identity: String, prop_kind: String, display_title: String, properties: Dictionary = {}) -> void:
	world = owner_world
	prop_id = identity
	kind = prop_kind
	title = display_title
	detail = properties

func _ready() -> void:
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	_build_visual()
	# Prop sizes are already in metres; map scaling must not double their collision.
	var radius = float(detail.get("collision", 0.0)) * 0.04
	if radius > 0.0:
		var height = 1.5
		if kind in ["npc", "well"]:
			height = 2.0
		elif kind == "tree":
			height = 3.0
		elif kind == "lighthouse":
			height = 6.0
		elif kind == "deco" and "building-" in String(detail.get("model", "")):
			height = 3.8
			radius = maxf(radius, 2.15)
		_add_collision(radius, height)

func _process(_delta: float) -> void:
	if not usable and respawn_at > 0.0 and world.elapsed >= respawn_at:
		usable = true
		respawn_at = 0.0
		visual.scale.y = 1.0
	if is_instance_valid(flame):
		var flicker = 1.0 + 0.10 * sin(world.elapsed * 9.0)
		flame.scale = Vector3(flicker, 1.0 / flicker, flicker)

func _build_visual() -> void:
	match kind:
		"npc":
			var paths = {"marta": "OldClassy_Female.glb", "grom": "OldClassy_Male.glb", "borg": "Worker_Male.glb", "lina": "Casual_Female.glb", "tim": "Casual2_Male.glb"}
			var skin_tones = {"marta": Color("cf9f7e"), "grom": Color("b88d6f"), "borg": Color("815844"), "lina": Color("c79170"), "tim": Color("a16b50")}
			idle_actor = ActorVisual.new()
			visual.add_child(idle_actor)
			idle_actor.setup(CHARACTERS + String(paths.get(prop_id, "Casual_Male.glb")), 0.42 if prop_id == "tim" else 0.55, skin_tones.get(prop_id, Color("b98060")))
			_add_name_tag()
		"tree": _add_model(REAL_NATURE + "pine.glb", 0.54)
		"rock": _add_model(REAL_NATURE + "rock_07.glb", 4.2)
		"bush": _add_model(REAL_NATURE + "fern_02.glb", 1.8)
		"scrap":
			_build_scrap()
		"water": _build_water_barrel()
		"crate": _build_crate()
		"deco":
			var path = String(detail.get("model", ""))
			if "city-suburban/building-" in path or "city-industrial/building-" in path:
				var ruin = Ruins3D.new()
				visual.add_child(ruin)
				ruin.build("city-industrial" in path, absi(path.hash()) % 4)
			elif "nature/tree_" in path:
				_add_model(REAL_NATURE + "pine.glb", 0.50 if "pine" in path else 0.60)
			else:
				_add_model(path, float(detail.get("model_scale", 3.0)))
			visual.rotation.y = float(detail.get("yaw", 0.0))
		"fire": _build_fire()
		"well": _build_well()
		"plot":
			if bool(detail.get("built", false)):
				_build_tower()
			else:
				_build_plot()
		"hotel": _add_model(SURVIVAL + "signpost.glb", 4.3)
		"safe": _add_model(SURVIVAL + "chest.glb", 3.5)
		"keycard":
			_box(Vector3(0.55, 0.07, 0.35), Vector3(0, 0.24, 0), Color("b9d6db"))
			_box(Vector3(0.18, 0.075, 0.20), Vector3(-0.12, 0.245, 0), Color("4aa5ae"))
			_glow(Vector3(0, 0.7, 0), Color("82d9df"))
		"chip", "coil", "cell":
			_add_model(SURVIVAL + "box.glb", 2.5)
			var color = Color("efc678") if kind == "coil" else (Color("76cdd8") if kind == "chip" else Color("9fe6a8"))
			_glow(Vector3(0, 1.1, 0), color)
		"teddy": _build_teddy()
		"lighthouse": _build_lighthouse()
		"boat": _add_model(NATURE + "canoe.glb", 5.5)

func _add_model(path: String, model_scale: float) -> void:
	var packed = load(path) as PackedScene
	if packed == null:
		push_error("Не удалось загрузить 3D-объект: " + path)
		return
	var node = packed.instantiate() as Node3D
	node.scale = Vector3.ONE * model_scale
	if path == REAL_NATURE + "pine.glb":
		node.add_to_group("tall_tree_visual")
		node.set_meta("tree_height", 14.5 * model_scale)
		node.set_meta("tree_radius", 3.6 * model_scale)
	visual.add_child(node)

func _add_collision(radius: float, height: float) -> void:
	var body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape = CollisionShape3D.new()
	var cylinder = CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	shape.shape = cylinder
	shape.position.y = height / 2.0
	body.add_child(shape)
	add_child(body)

func _material(color: Color, emission: bool = false) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.5
	return material

func _box(size: Vector3, pos: Vector3, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var shape = BoxMesh.new()
	shape.size = size
	shape.material = _material(color)
	var mesh = MeshInstance3D.new()
	mesh.mesh = shape
	mesh.position = pos
	(visual if parent == null else parent).add_child(mesh)
	return mesh

func _cylinder(bottom: float, top: float, height: float, pos: Vector3, color: Color, emission: bool = false, parent: Node3D = null) -> MeshInstance3D:
	var shape = CylinderMesh.new()
	shape.bottom_radius = bottom
	shape.top_radius = top
	shape.height = height
	shape.radial_segments = 12
	shape.material = _material(color, emission)
	var mesh = MeshInstance3D.new()
	mesh.mesh = shape
	mesh.position = pos
	(visual if parent == null else parent).add_child(mesh)
	return mesh

func _sphere(radius: float, pos: Vector3, color: Color, emission: bool = false, parent: Node3D = null) -> MeshInstance3D:
	var shape = SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	shape.radial_segments = 12
	shape.rings = 6
	shape.material = _material(color, emission)
	var mesh = MeshInstance3D.new()
	mesh.mesh = shape
	mesh.position = pos
	(visual if parent == null else parent).add_child(mesh)
	return mesh

func _glow(pos: Vector3, color: Color) -> void:
	var gem = _sphere(0.18, pos, color, true)
	gem.scale.y = 1.4

func _surface(texture: Texture2D, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = tint
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.roughness = 1.0
	return material

func _build_crate() -> void:
	var body = _box(Vector3(0.95, 0.85, 0.85), Vector3(0, 0.43, 0), Color.WHITE)
	body.material_override = _surface(WOOD_TEXTURE, Color("aaa399"))
	for x in [-0.38, 0.38]:
		_box(Vector3(0.08, 0.88, 0.90), Vector3(x, 0.43, 0), Color("5e5141"))
	_box(Vector3(1.0, 0.09, 0.90), Vector3(0, 0.76, 0), Color("5e5141"))

func _build_scrap() -> void:
	var barrel = CylinderMesh.new()
	barrel.bottom_radius = 0.38
	barrel.top_radius = 0.38
	barrel.height = 1.05
	barrel.radial_segments = 20
	barrel.material = _surface(METAL_TEXTURE, Color("a09987"))
	var node = MeshInstance3D.new()
	node.mesh = barrel
	node.position.y = 0.53
	visual.add_child(node)
	_cylinder(0.40, 0.40, 0.05, Vector3(0, 0.25, 0), Color("51483f"))
	_cylinder(0.40, 0.40, 0.05, Vector3(0, 0.80, 0), Color("51483f"))
	var sheet = _box(Vector3(0.8, 0.08, 0.52), Vector3(0.52, 0.08, 0.25), Color.WHITE)
	sheet.rotation.y = 0.3
	sheet.material_override = _surface(METAL_TEXTURE, Color("9e9a8c"))

func _build_water_barrel() -> void:
	var barrel = CylinderMesh.new()
	barrel.bottom_radius = 0.38
	barrel.top_radius = 0.38
	barrel.height = 1.0
	barrel.radial_segments = 20
	barrel.material = _surface(METAL_TEXTURE, Color("72969a"))
	var node = MeshInstance3D.new()
	node.mesh = barrel
	node.position.y = 0.5
	visual.add_child(node)
	_cylinder(0.39, 0.39, 0.05, Vector3(0, 0.25, 0), Color("475c5e"))
	_cylinder(0.39, 0.39, 0.05, Vector3(0, 0.8, 0), Color("475c5e"))
	_cylinder(0.30, 0.30, 0.02, Vector3(0, 1.01, 0), Color("72a9b1"))

func _add_name_tag() -> void:
	var label = Label3D.new()
	label.text = title
	label.font = FONT
	label.font_size = 32
	label.pixel_size = 0.004
	label.outline_size = 8
	label.modulate = Color("f2e4c0")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 2.35 if prop_id != "tim" else 1.95, 0)
	visual.add_child(label)

func _build_fire() -> void:
	_add_model(SURVIVAL + "campfire-pit.glb", 4.2)
	flame = Node3D.new()
	visual.add_child(flame)
	_cylinder(0.25, 0.0, 0.8, Vector3(0, 0.48, 0), Color("ef914e"), true, flame)
	_cylinder(0.13, 0.0, 0.56, Vector3(0.05, 0.38, 0), Color("ffe5a0"), true, flame)
	var light = OmniLight3D.new()
	light.position = Vector3(0, 1.1, 0)
	light.light_color = Color("ffad68")
	light.light_energy = 1.2
	light.omni_range = 7.0
	visual.add_child(light)

func _build_well() -> void:
	_cylinder(0.75, 0.75, 0.7, Vector3(0, 0.35, 0), Color("80867d"))
	_cylinder(0.55, 0.55, 0.72, Vector3(0, 0.38, 0), Color("344d4b"))
	_box(Vector3(0.12, 1.8, 0.12), Vector3(-0.65, 0.9, 0), Color("806045"))
	_box(Vector3(0.12, 1.8, 0.12), Vector3(0.65, 0.9, 0), Color("806045"))
	_box(Vector3(1.6, 0.15, 0.65), Vector3(0, 1.8, 0), Color("6d5140"))

func _build_plot() -> void:
	_box(Vector3(1.8, 0.10, 1.8), Vector3(0, 0.05, 0), Color("8f7655"))
	for x in [-0.8, 0.8]:
		for z in [-0.8, 0.8]:
			_box(Vector3(0.12, 0.4, 0.12), Vector3(x, 0.2, z), Color("d5b271"))
	_glow(Vector3(0, 0.55, 0), Color("e8c778"))

func _build_tower() -> void:
	_add_collision(0.95, 3.6)
	_box(Vector3(2.2, 0.20, 2.2), Vector3(0, 0.1, 0), Color("604c37"))
	for x in [-0.85, 0.85]:
		for z in [-0.85, 0.85]:
			_box(Vector3(0.18, 3.4, 0.18), Vector3(x, 1.7, z), Color("795639"))
	_box(Vector3(2.4, 0.22, 2.4), Vector3(0, 2.8, 0), Color("8f6c45"))
	_box(Vector3(2.4, 0.16, 2.4), Vector3(0, 3.65, 0), Color("5f4735"))
	_cylinder(0.9, 0.05, 0.9, Vector3(0, 4.15, 0), Color("835b3f"))
	_box(Vector3(0.16, 0.16, 1.7), Vector3(0, 3.2, 0), Color("b1a784"))

func _build_lighthouse() -> void:
	_cylinder(1.65, 1.25, 5.8, Vector3(0, 2.9, 0), Color("e6dfc5"))
	_cylinder(1.51, 1.44, 0.75, Vector3(0, 1.5, 0), Color("b75c48"))
	_cylinder(1.30, 1.30, 0.75, Vector3(0, 4.3, 0), Color("b75c48"))
	_cylinder(1.7, 1.7, 0.18, Vector3(0, 5.95, 0), Color("544c44"))
	_cylinder(0.95, 0.95, 1.1, Vector3(0, 6.55, 0), Color("f2d47c"), true)
	_cylinder(1.1, 0.05, 0.8, Vector3(0, 7.5, 0), Color("5f4a3d"))
	_box(Vector3(0.65, 1.25, 0.12), Vector3(0, 0.65, 1.55), Color("4c4539"))

func _build_teddy() -> void:
	var fur = Color("a77a54")
	_sphere(0.23, Vector3(0, 0.25, 0), fur)
	_sphere(0.18, Vector3(0, 0.55, 0), fur)
	_sphere(0.09, Vector3(-0.14, 0.68, 0), fur)
	_sphere(0.09, Vector3(0.14, 0.68, 0), fur)
	_sphere(0.08, Vector3(-0.24, 0.27, 0), fur)
	_sphere(0.08, Vector3(0.24, 0.27, 0), fur)
	_sphere(0.035, Vector3(-0.07, 0.59, 0.16), Color("2c2721"))
	_sphere(0.035, Vector3(0.07, 0.59, 0.16), Color("2c2721"))
	_glow(Vector3(0, 1.0, 0), Color("e8c778"))

func set_built() -> void:
	detail["built"] = true
	title = "Оборонительная башня"
	for child in visual.get_children():
		MeshCleanup.before_free(child)
		child.queue_free()
	_build_tower()

func deplete(seconds: float) -> void:
	usable = false
	respawn_at = world.elapsed + seconds
	visual.scale.y = 0.3
