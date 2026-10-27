extends Node3D

const MAP_TEXTURE = preload("res://assets/environment/island_ground.png")
const SCALE := 0.04
const WIDTH := 3200.0 * SCALE
const DEPTH := 2200.0 * SCALE

var sun: DirectionalLight3D
var sky_material: ProceduralSkyMaterial
var environment: Environment

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
	sky_material.sky_top_color = Color("365d77")
	sky_material.sky_horizon_color = Color("b5c9c3")
	sky_material.ground_bottom_color = Color("53665e")
	sky_material.ground_horizon_color = Color("b5c9c3")
	var sky = Sky.new()
	sky.sky_material = sky_material
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d8e4d6")
	environment.ambient_light_energy = 0.72
	environment.fog_enabled = true
	environment.fog_light_color = Color("9fb5ac")
	environment.fog_density = 0.004
	var atmosphere = WorldEnvironment.new()
	atmosphere.environment = environment
	add_child(atmosphere)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -34, 0)
	sun.light_color = Color("fff0d4")
	sun.light_energy = 1.12
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 55.0
	add_child(sun)

func set_night(amount: float) -> void:
	var t = clampf(amount, 0.0, 1.0)
	sun.light_energy = lerpf(1.12, 0.28, t)
	sun.light_color = Color("fff0d4").lerp(Color("94b0d1"), t)
	environment.ambient_light_energy = lerpf(0.72, 0.39, t)
	environment.fog_light_color = Color("9fb5ac").lerp(Color("455f75"), t)
	sky_material.sky_top_color = Color("365d77").lerp(Color("162536"), t)
	sky_material.sky_horizon_color = Color("b5c9c3").lerp(Color("485c6d"), t)
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
	var material = StandardMaterial3D.new()
	material.albedo_texture = MAP_TEXTURE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.roughness = 1.0
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
	water.albedo_color = Color("376e7a")
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
	var tree_scenes = [
		load("res://assets/models/kenney/nature/tree_pineTallA.glb"),
		load("res://assets/models/kenney/nature/tree_pineTallB.glb"),
		load("res://assets/models/kenney/nature/tree_oak.glb"),
	]
	var bush = load("res://assets/models/kenney/nature/plant_bush.glb")
	var grass = load("res://assets/models/kenney/survival/grass.glb")
	var rng = RandomNumberGenerator.new()
	rng.seed = 2291
	var forest_colliders = StaticBody3D.new()
	forest_colliders.name = "ForestColliders"
	forest_colliders.collision_layer = 1
	forest_colliders.collision_mask = 0
	add_child(forest_colliders)
	var trunk_shape = CylinderShape3D.new()
	trunk_shape.radius = 0.24
	trunk_shape.height = 2.0
	# Trees cluster away from the village, roads and named quest locations.
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
		var scene = tree_scenes[rng.randi_range(0, tree_scenes.size() - 1)]
		var instance = scene.instantiate() as Node3D
		var size = rng.randf_range(2.6, 4.2)
		instance.scale = Vector3.ONE * size
		instance.rotation.y = rng.randf_range(0, TAU)
		instance.position = Vector3(p.x * SCALE, height_at(p.x * SCALE, p.y * SCALE), p.y * SCALE)
		add_child(instance)
		var trunk = CollisionShape3D.new()
		trunk.shape = trunk_shape
		trunk.position = instance.position + Vector3.UP
		forest_colliders.add_child(trunk)
	for i in range(100):
		var p = Vector2(rng.randf_range(250, 2950), rng.randf_range(220, 1980))
		if _near_road(p):
			continue
		var scene = bush if i % 3 == 0 else grass
		var instance = scene.instantiate() as Node3D
		instance.scale = Vector3.ONE * rng.randf_range(2.0, 3.6)
		instance.rotation.y = rng.randf_range(0, TAU)
		instance.position = Vector3(p.x * SCALE, height_at(p.x * SCALE, p.y * SCALE), p.y * SCALE)
		add_child(instance)

func _near_road(p: Vector2) -> bool:
	var roads = [
		[Vector2(350, 1850), Vector2(650, 1620)], [Vector2(650, 1620), Vector2(850, 1300)],
		[Vector2(850, 1300), Vector2(1500, 1420)], [Vector2(1500, 1420), Vector2(2150, 1440)],
		[Vector2(2150, 1440), Vector2(2570, 625)], [Vector2(2150, 1440), Vector2(2750, 1800)],
		[Vector2(850, 1300), Vector2(590, 430)], [Vector2(850, 1300), Vector2(1480, 470)],
	]
	for road in roads:
		if Geometry2D.get_closest_point_to_segment(p, road[0], road[1]).distance_to(p) < 95:
			return true
	return false
