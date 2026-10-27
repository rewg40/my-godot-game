extends Node3D

const SURFACE_SHADER = preload("res://shaders/island_surface.gdshader")
const SURFACE_MASK = preload("res://assets/environment/terrain_mask.png")
const PINE_PATH = "res://assets/models/nature_real/pine.glb"
const GRASS_PATH = "res://assets/models/nature_real/grass.glb"
const FERN_PATH = "res://assets/models/nature_real/fern_02.glb"
const MeshCleanup = preload("res://scripts/mesh_cleanup.gd")
const SCALE := 0.04
const WIDTH := 3200.0 * SCALE
const DEPTH := 2200.0 * SCALE

var sun: DirectionalLight3D
var sky_material: ProceduralSkyMaterial
var environment: Environment
var occlusion_timer := 0.0

# Heights stay gentle enough to cross, but the terrain is a real triangle mesh
# with a matching 3D collision surface, not a 2D picture or a flat billboard.
func height_at(x: float, z: float) -> float:
	return 0.22 * sin(x * 0.11) * cos(z * 0.12) + 0.10 * sin(x * 0.29 + z * 0.23)

func _ready() -> void:
	_build_lighting()
	_build_terrain()
	_build_sea()
	_scatter_scenery()

func _build_lighting() -> void:
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("3c5059")
	sky_material.sky_horizon_color = Color("a1aca4")
	sky_material.ground_bottom_color = Color("46544b")
	sky_material.ground_horizon_color = Color("9da9a0")
	var sky = Sky.new()
	sky.sky_material = sky_material
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d1d8cd")
	environment.ambient_light_energy = 0.40
	environment.fog_enabled = true
	environment.fog_light_color = Color("899a94")
	environment.fog_density = 0.006
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.72
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.90
	environment.adjustment_contrast = 1.12
	var atmosphere = WorldEnvironment.new()
	atmosphere.environment = environment
	add_child(atmosphere)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -34, 0)
	sun.light_color = Color("f1e7d4")
	sun.light_energy = 0.78
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = 55.0
	add_child(sun)

func set_night(amount: float) -> void:
	var t = clampf(amount, 0.0, 1.0)
	sun.light_energy = lerpf(0.78, 0.20, t)
	sun.light_color = Color("f1e7d4").lerp(Color("94abc1"), t)
	environment.ambient_light_energy = lerpf(0.40, 0.24, t)
	environment.fog_light_color = Color("899a94").lerp(Color("394e5b"), t)
	sky_material.sky_top_color = Color("3c5059").lerp(Color("162536"), t)
	sky_material.sky_horizon_color = Color("a1aca4").lerp(Color("485c6d"), t)
	sky_material.ground_horizon_color = sky_material.sky_horizon_color

func _build_terrain() -> void:
	const NX := 80
	const NZ := 55
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	for iz in range(NZ + 1):
		for ix in range(NX + 1):
			var x = WIDTH * float(ix) / NX
			var z = DEPTH * float(iz) / NZ
			vertices.append(Vector3(x, height_at(x, z), z))
			var dx = height_at(x + 0.2, z) - height_at(x - 0.2, z)
			var dz = height_at(x, z + 0.2) - height_at(x, z - 0.2)
			normals.append(Vector3(-dx, 0.4, -dz).normalized())
			uvs.append(Vector2(float(ix) / NX, float(iz) / NZ))
	for iz in range(NZ):
		for ix in range(NX):
			var a = iz * (NX + 1) + ix
			var b = a + 1
			var c = a + NX + 1
			var d = c + 1
			# Godot treats clockwise triangles as front-facing. Winding upward is
			# essential: the concave physics shape only collides with its front.
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var ground_mesh = ArrayMesh.new()
	ground_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material = ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	material.set_shader_parameter("layout_mask", SURFACE_MASK)
	material.set_shader_parameter("grass_tex", load("res://assets/environment/textures/grass_short.jpg"))
	material.set_shader_parameter("litter_tex", load("res://assets/environment/textures/leafy_grass.jpg"))
	material.set_shader_parameter("forest_tex", load("res://assets/environment/textures/forest_diff_1k.jpg"))
	material.set_shader_parameter("dirt_tex", load("res://assets/environment/textures/dirt_diff_1k.jpg"))
	material.set_shader_parameter("sand_tex", load("res://assets/environment/textures/sand.jpg"))
	material.set_shader_parameter("asphalt_tex", load("res://assets/environment/textures/asphalt.jpg"))
	ground_mesh.surface_set_material(0, material)
	var ground = MeshInstance3D.new()
	ground.name = "IslandTerrain"
	ground.mesh = ground_mesh
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	var body = StaticBody3D.new()
	body.name = "IslandCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape = CollisionShape3D.new()
	shape.shape = ground_mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)

func _build_sea() -> void:
	var mesh = PlaneMesh.new()
	mesh.size = Vector2(500, 500)
	var water = StandardMaterial3D.new()
	water.albedo_color = Color("294f55")
	water.roughness = 0.36
	water.metallic = 0.08
	mesh.material = water
	var instance = MeshInstance3D.new()
	instance.name = "Sea"
	instance.mesh = mesh
	instance.position = Vector3(WIDTH / 2.0, -0.8, DEPTH / 2.0)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _scatter_scenery() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 2291
	var pine_scene = load(PINE_PATH) as PackedScene
	var broadleaf_scene = load("res://assets/models/nature_real/broadleaf.glb") as PackedScene
	var fern_scene = load(FERN_PATH) as PackedScene
	var stump_scene = load("res://assets/models/nature_real/tree_stump_01.glb") as PackedScene
	var forest_colliders = StaticBody3D.new()
	forest_colliders.name = "ForestColliders"
	forest_colliders.collision_layer = 1
	forest_colliders.collision_mask = 0
	add_child(forest_colliders)
	var trunk_shape = CylinderShape3D.new()
	trunk_shape.radius = 0.27
	trunk_shape.height = 2.0
	# Trees cluster away from the village, roads and quest landmarks, keeping
	# the chapter's routes, encounters and old saves unobstructed.
	var exclusion = [Vector2(850, 1300), Vector2(2150, 1440), Vector2(2570, 625), Vector2(2750, 1800), Vector2(590, 430), Vector2(360, 1830)]
	for i in range(115):
		var p = Vector2(rng.randf_range(260, 2940), rng.randf_range(240, 1960))
		var clear = true
		for landmark in exclusion:
			if p.distance_to(landmark) < 230:
				clear = false
				break
		if not clear or _near_road(p):
			continue
		var broadleaf = rng.randf() < 0.32
		var instance = (broadleaf_scene if broadleaf else pine_scene).instantiate() as Node3D
		instance.name = "ForestBroadleaf" if broadleaf else "ForestPine"
		var size = rng.randf_range(1.1, 1.4) if broadleaf else rng.randf_range(0.48, 0.63)
		instance.scale = Vector3.ONE * size
		instance.rotation.y = rng.randf_range(0, TAU)
		instance.position = Vector3(p.x * SCALE, height_at(p.x * SCALE, p.y * SCALE), p.y * SCALE)
		instance.set_meta("tree_height", (4.6 if broadleaf else 14.5) * size)
		instance.set_meta("tree_radius", (2.3 if broadleaf else 3.6) * size)
		instance.add_to_group("tall_tree_visual")
		add_child(instance)
		var trunk = CollisionShape3D.new()
		trunk.shape = trunk_shape
		trunk.position = instance.position + Vector3.UP
		forest_colliders.add_child(trunk)
	# Photographic fern clusters; no invisible blockers are added to routes.
	for i in range(55):
		var p = Vector2(rng.randf_range(250, 2950), rng.randf_range(220, 1980))
		if _near_road(p):
			continue
		var instance = fern_scene.instantiate() as Node3D
		instance.scale = Vector3.ONE * rng.randf_range(0.8, 1.6)
		instance.rotation.y = rng.randf_range(0, TAU)
		instance.position = Vector3(p.x * SCALE, height_at(p.x * SCALE, p.y * SCALE), p.y * SCALE)
		add_child(instance)
	for i in range(16):
		var p = Vector2(rng.randf_range(350, 2750), rng.randf_range(250, 1900))
		if _near_road(p):
			continue
		var stump = stump_scene.instantiate() as Node3D
		stump.scale = Vector3.ONE * rng.randf_range(0.8, 1.4)
		stump.rotation.y = rng.randf_range(0, TAU)
		stump.position = Vector3(p.x * SCALE, height_at(p.x * SCALE, p.y * SCALE), p.y * SCALE)
		add_child(stump)
	_build_grass(rng)

func _build_grass(rng: RandomNumberGenerator) -> void:
	# One shared 3D grass mesh and one MultiMesh draw rather than thousands of
	# independent scene nodes. Skip asphalt, paths, beach and water by mask.
	var grass_scene = load(GRASS_PATH) as PackedScene
	var source = grass_scene.instantiate()
	var candidates = source.find_children("*", "MeshInstance3D", true, false)
	if source is MeshInstance3D:
		candidates.push_front(source)
	if candidates.is_empty():
		source.free()
		return
	var grass_mesh = (candidates[0] as MeshInstance3D).mesh
	var mask = SURFACE_MASK.get_image()
	var positions: Array[Transform3D] = []
	for i in range(10500):
		var p = Vector2(rng.randf_range(150, 3050), rng.randf_range(130, 2070))
		var uv = Vector2i(clampi(int(p.x / 3200.0 * mask.get_width()), 0, mask.get_width() - 1), clampi(int(p.y / 2200.0 * mask.get_height()), 0, mask.get_height() - 1))
		var pixel = mask.get_pixelv(uv)
		if pixel.a < 0.95 or pixel.r > 0.06 or pixel.g > 0.12 or pixel.b > 0.45:
			continue
		var size = rng.randf_range(1.15, 2.5)
		var basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
		var origin = Vector3(p.x * SCALE, height_at(p.x * SCALE, p.y * SCALE) - 0.02, p.y * SCALE)
		positions.append(Transform3D(basis, origin))
	var multi = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = grass_mesh
	multi.instance_count = positions.size()
	for i in range(positions.size()):
		multi.set_instance_transform(i, positions[i])
	var cover = MultiMeshInstance3D.new()
	cover.name = "GrassCover"
	cover.multimesh = multi
	cover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cover)
	MeshCleanup.before_free(source)
	source.free()

func _near_road(p: Vector2) -> bool:
	var roads = [
		[Vector2(360, 1840), Vector2(600, 1720)], [Vector2(600, 1720), Vector2(680, 1550)], [Vector2(680, 1550), Vector2(850, 1300)],
		[Vector2(850, 1300), Vector2(1200, 1400)], [Vector2(1200, 1400), Vector2(1640, 1460)], [Vector2(1640, 1460), Vector2(2190, 1400)],
		[Vector2(2190, 1400), Vector2(2300, 1180)], [Vector2(2300, 1180), Vector2(2420, 940)], [Vector2(2420, 940), Vector2(2570, 650)],
		[Vector2(2190, 1400), Vector2(2460, 1540)], [Vector2(2460, 1540), Vector2(2640, 1640)], [Vector2(2640, 1640), Vector2(2750, 1800)],
		[Vector2(850, 1300), Vector2(730, 1110)], [Vector2(730, 1110), Vector2(680, 800)], [Vector2(680, 800), Vector2(590, 430)],
		[Vector2(850, 1300), Vector2(1120, 1236)], [Vector2(1120, 1236), Vector2(1430, 1120)], [Vector2(1430, 1120), Vector2(1620, 880)], [Vector2(1620, 880), Vector2(1460, 480)],
	]
	for road in roads:
		if Geometry2D.get_closest_point_to_segment(p, road[0], road[1]).distance_to(p) < 90:
			return true
	return false

func _process(delta: float) -> void:
	occlusion_timer -= delta
	if occlusion_timer > 0.0:
		return
	occlusion_timer = 0.12
	var world = get_parent()
	if not is_instance_valid(world.player) or not is_instance_valid(world.player.camera):
		return
	var target: Vector3 = world.player.global_position + Vector3.UP
	var eye: Vector3 = world.player.camera.global_position
	var segment = Vector2(eye.x - target.x, eye.z - target.z)
	if segment.length_squared() < 0.01:
		return
	# Hide only trees physically between camera and character; their trunk
	# colliders remain active. This keeps the elevated view readable in woods.
	for tree in get_tree().get_nodes_in_group("tall_tree_visual"):
		if not world.is_ancestor_of(tree):
			continue
		var relative = Vector2(tree.global_position.x - target.x, tree.global_position.z - target.z)
		var t = clampf(relative.dot(segment) / segment.length_squared(), 0.0, 1.0)
		var distance = (relative - segment * t).length()
		var ray_height = lerpf(target.y, eye.y, t)
		var bottom: float = tree.global_position.y
		var top = bottom + float(tree.get_meta("tree_height", 7.0))
		var radius = float(tree.get_meta("tree_radius", 2.0))
		tree.visible = not (t > 0.02 and t < 0.98 and distance < radius and ray_height > bottom and ray_height < top)
