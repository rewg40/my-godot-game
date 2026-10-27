extends Node3D

# Quiet roadside storytelling: physical utility poles and fences, plus paper
# and metal scraps instanced as lightweight 3D geometry. None are quest items.
const WOOD = preload("res://assets/environment/textures/planks_diff_1k.jpg")
const METAL = preload("res://assets/environment/textures/metal_diff_1k.jpg")

var world
var wood_material: StandardMaterial3D
var metal_material: StandardMaterial3D

func build(owner_world) -> void:
	world = owner_world
	wood_material = _material(Color("9a8f7c"), WOOD)
	metal_material = _material(Color("8d8d7d"), METAL)
	var pole_points = [Vector2(550,1700), Vector2(1010,1355), Vector2(1420,1360), Vector2(1830,1350), Vector2(2240,1280), Vector2(2420,1020)]
	var pole_tops: Array[Vector3] = []
	for point in pole_points:
		var base: Vector3 = world.map_to_world(point)
		_pole(base)
		pole_tops.append(base + Vector3.UP * 5.05)
	for i in range(pole_tops.size() - 1):
		_wire(pole_tops[i], pole_tops[i + 1])
	_fence(Vector2(1960, 1615), 7.0, 0.20)
	_fence(Vector2(2680, 985), 5.5, -0.10)
	_scatter_paper()

func _material(color: Color, texture: Texture2D = null) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = texture
	material.roughness = 1.0
	return material

func _box(size: Vector3, pos: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var mesh = BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	(self if parent == null else parent).add_child(node)
	return node

func _pole(base: Vector3) -> void:
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.11
	mesh.bottom_radius = 0.18
	mesh.height = 5.4
	mesh.radial_segments = 10
	mesh.material = wood_material
	var pole = MeshInstance3D.new()
	pole.mesh = mesh
	pole.position = base + Vector3.UP * 2.7
	add_child(pole)
	_box(Vector3(1.65, 0.15, 0.16), base + Vector3.UP * 4.8, wood_material)
	for x in [-0.55, 0.55]:
		_box(Vector3(0.13, 0.21, 0.13), base + Vector3(x, 4.98, 0), metal_material)
	var body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape = CollisionShape3D.new()
	var cylinder = CylinderShape3D.new()
	cylinder.radius = 0.18
	cylinder.height = 3.0
	shape.shape = cylinder
	shape.position = base + Vector3.UP * 1.5
	body.add_child(shape)
	add_child(body)

func _wire(from: Vector3, to: Vector3) -> void:
	var difference = to - from
	var shape = CylinderMesh.new()
	shape.top_radius = 0.025
	shape.bottom_radius = 0.025
	shape.height = difference.length()
	shape.radial_segments = 5
	shape.material = metal_material
	var node = MeshInstance3D.new()
	node.mesh = shape
	var up = difference.normalized()
	var right = up.cross(Vector3.UP).normalized()
	node.basis = Basis(right, up, right.cross(up).normalized())
	node.position = (from + to) * 0.5
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

func _fence(point: Vector2, length: float, yaw: float) -> void:
	var root = Node3D.new()
	root.position = world.map_to_world(point)
	root.rotation.y = yaw
	add_child(root)
	_box(Vector3(length, 1.18, 0.13), Vector3(0, 0.75, 0), wood_material, root)
	for x in [-length * 0.5, 0.0, length * 0.5]:
		_box(Vector3(0.14, 1.55, 0.18), Vector3(x, 0.77, 0), wood_material, root)
	var body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(length, 1.5, 0.18)
	shape.shape = box
	shape.position.y = 0.75
	body.add_child(shape)
	root.add_child(body)

func _scatter_paper() -> void:
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.22, 0.012, 0.28)
	mesh.material = _material(Color("b5afa0"))
	var rng = RandomNumberGenerator.new()
	rng.seed = 3491
	var points = [Vector2(600, 1690), Vector2(1220, 1410), Vector2(1700, 1450), Vector2(2110, 1410), Vector2(2400, 1000)]
	var transforms: Array[Transform3D] = []
	for center in points:
		for i in range(19):
			var point = center + Vector2(rng.randf_range(-85, 85), rng.randf_range(-48, 48))
			var pos: Vector3 = world.map_to_world(point) + Vector3.UP * 0.05
			var basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * rng.randf_range(0.55, 1.5))
			transforms.append(Transform3D(basis, pos))
	var multi = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in range(transforms.size()):
		multi.set_instance_transform(i, transforms[i])
	var scraps = MultiMeshInstance3D.new()
	scraps.name = "RoadDebris"
	scraps.multimesh = multi
	scraps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(scraps)
