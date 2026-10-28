extends Node3D

const SURFACE_SHADER = preload("res://shaders/island_surface.gdshader")
const WATER_SHADER = preload("res://shaders/water_surface.gdshader")
const ISLAND_MODEL = preload("res://assets/models/environment/user_island.glb")
const SURFACE_MASK = preload("res://assets/environment/user_island_layout.png")
const TERRAIN_DATA = preload("res://assets/environment/user_island_data.png")
const NEAREST_DATA = preload("res://assets/environment/user_island_nearest.png")
const PINE_PATH = "res://assets/models/nature_real/pine.glb"
const GRASS_PATH = "res://assets/models/nature_real/grass.glb"
const FERN_PATH = "res://assets/models/nature_real/fern_02.glb"
const MeshCleanup = preload("res://scripts/mesh_cleanup.gd")
const CityZone = preload("res://scripts/ruined_city.gd")
const SCALE := 0.08
const WIDTH := 3200.0 * SCALE
const DEPTH := 2200.0 * SCALE
const RAW_GROUND := 0.011
const RAW_HEIGHT_MIN := 0.0
const RAW_HEIGHT_MAX := 0.067732
const HEIGHT_SCALE := 150.0
const MAX_CLEARANCE := 16.0
const NAV_COLS := 256
const NAV_ROWS := 176
const LAKE_RADII := Vector2(8.0, 6.0)
# Chosen on broad, very flat patches of the supplied terrain; map coordinates
# are independent of the island's physical scale.
const LAKE_SITES := [Vector2(1843, 1824), Vector2(1472, 1654), Vector2(361, 1323), Vector2(1232, 1233), Vector2(811, 1443)]

var saved_layout: Dictionary = {}
var lake_map_position := Vector2.ZERO
var lake_surface_y := 0.0
var sun: DirectionalLight3D
var sky_material: ProceduralSkyMaterial
var environment: Environment
var occlusion_timer := 0.0
var height_data: Image
var nearest_data: Image
var surface_data: Image
var navigation: AStarGrid2D

func _ready() -> void:
	# Data is sampled from the optimized supplied model by
	# tools/prepare_user_island.py, only for placement and routing. The same
	# 3D mesh supplies both the visible island and its physical collision.
	height_data = TERRAIN_DATA.get_image()
	nearest_data = NEAREST_DATA.get_image()
	surface_data = SURFACE_MASK.get_image()
	_select_lake_site()
	_build_lighting()
	_build_terrain()
	_build_sea()
	_build_lake()
	_build_navigation()
	_scatter_scenery()
	_build_city_zone()

func _build_city_zone() -> void:
	# Разрушенный городской район: площадка под рельеф, улица и здания.
	# Добавляется последним: четыре плотные GLB-руины разбираются несколько секунд.
	var city := CityZone.new()
	city.name = "RuinedCity"
	city.setup(self)
	add_child(city)

func _select_lake_site() -> void:
	var saved = saved_layout.get("lake_position", [])
	if saved is Array and saved.size() == 2:
		lake_map_position = Vector2(float(saved[0]), float(saved[1]))
		return
	for candidate in LAKE_SITES:
		if _lake_clear_of_bases(candidate):
			lake_map_position = candidate
			return
	# Old bases can cover the preselected clearings. Search other flat, open
	# ground instead of ever placing new water underneath a player's house.
	for z in range(240, 1961, 80):
		for x in range(240, 2961, 80):
			var candidate := Vector2(float(x), float(z))
			if _lake_clear_of_bases(candidate) and _flat_lake_site(candidate):
				lake_map_position = candidate
				return
	# If a highly unusual save leaves no suitable clearing, omit the lake; the
	# saved structures take priority over the decorative water surface.
	lake_map_position = Vector2.ZERO

func _lake_clear_of_bases(candidate: Vector2) -> bool:
	var center := candidate * SCALE
	for record in saved_layout.get("buildings", []):
		if record is Dictionary and record.get("type", "") == "foundation":
			var floor_point := Vector2(float(record["x"]) * 3.0, float(record["z"]) * 3.0)
			if absf(floor_point.x - center.x) < LAKE_RADII.x + 3.0 and absf(floor_point.y - center.y) < LAKE_RADII.y + 3.0:
				return false
	return true

func _flat_lake_site(candidate: Vector2) -> bool:
	if _near_road(candidate):
		return false
	var center := candidate * SCALE
	var low := INF
	var high := -INF
	for ring in [0.0, 0.5, 1.0]:
		for i in range(16):
			var angle := TAU * float(i) / 16.0
			var point: Vector2 = center + Vector2(cos(angle) * LAKE_RADII.x, sin(angle) * LAKE_RADII.y) * float(ring)
			if not is_walkable(point.x, point.y, 1.0):
				return false
			var h := height_at(point.x, point.y)
			low = minf(low, h)
			high = maxf(high, h)
	return high - low < 0.25

func is_lake(x: float, z: float, extra: float = 0.0) -> bool:
	if lake_map_position == Vector2.ZERO:
		return false
	var delta := Vector2(x, z) - lake_map_position * SCALE
	var radii := LAKE_RADII + Vector2.ONE * extra
	return pow(delta.x / radii.x, 2.0) + pow(delta.y / radii.y, 2.0) < 1.0

func _data_coordinate(x: float, z: float) -> Vector2:
	return Vector2(clampf(x / WIDTH, 0.0, 1.0) * float(height_data.get_width() - 1), clampf(z / DEPTH, 0.0, 1.0) * float(height_data.get_height() - 1))

func _raw_height(pixel: Color) -> float:
	var value = roundi(pixel.r * 255.0) * 256 + roundi(pixel.g * 255.0)
	return lerpf(RAW_HEIGHT_MIN, RAW_HEIGHT_MAX, float(value) / 65535.0)

func height_at(x: float, z: float) -> float:
	# Bilinear samples of the model's upper triangles, with 16-bit precision.
	# Placements first check is_walkable(), avoiding trees and steep obstacles.
	var point = _data_coordinate(x, z)
	var x0 = floori(point.x)
	var z0 = floori(point.y)
	var x1 = mini(x0 + 1, height_data.get_width() - 1)
	var z1 = mini(z0 + 1, height_data.get_height() - 1)
	var a = lerpf(_raw_height(height_data.get_pixel(x0, z0)), _raw_height(height_data.get_pixel(x1, z0)), point.x - x0)
	var b = lerpf(_raw_height(height_data.get_pixel(x0, z1)), _raw_height(height_data.get_pixel(x1, z1)), point.x - x0)
	return (lerpf(a, b, point.y - z0) - RAW_GROUND) * HEIGHT_SCALE

func is_walkable(x: float, z: float, clearance: float = 1.0) -> bool:
	if x < 0.0 or x > WIDTH or z < 0.0 or z > DEPTH or is_lake(x, z, clearance * 0.5):
		return false
	var point = _data_coordinate(x, z)
	var pixel = height_data.get_pixel(roundi(point.x), roundi(point.y))
	return pixel.b * MAX_CLEARANCE + 0.0001 >= clearance

func nearest_walkable(x: float, z: float, clearance: float = 1.0) -> Vector2:
	# Existing saves and all quest coordinates remain map-space values. If a
	# point is inside a cliff/building or in water, use the nearest connected
	# ground instead of spawning a character or item inside the supplied mesh.
	if is_walkable(x, z, clearance):
		return Vector2(x, z)
	# The lake was added after the original nearest-land atlas was baked.
	# Search its perimeter explicitly rather than returning a point in water.
	if is_lake(x, z, clearance):
		for ring in range(1, 81):
			var radius := float(ring) * 0.25
			for i in range(32):
				var angle := TAU * float(i) / 32.0
				var candidate := Vector2(x, z) + Vector2(cos(angle), sin(angle)) * radius
				if is_walkable(candidate.x, candidate.y, clearance):
					return candidate
	if clearance > 1.0:
		# Large decorative buildings need more room than a character capsule.
		# Search by increasing radius; most are resolved in the first few rings.
		for ring in range(1, 65):
			var radius = float(ring) * 0.4
			var steps = clampi(ceili(TAU * radius / 0.4), 16, 160)
			for i in range(steps):
				var angle = TAU * float(i) / float(steps)
				var candidate = Vector2(x, z) + Vector2(cos(angle), sin(angle)) * radius
				if is_walkable(candidate.x, candidate.y, clearance):
					return candidate
	var point = _data_coordinate(x, z)
	var packed = nearest_data.get_pixel(roundi(point.x), roundi(point.y))
	var index = (roundi(packed.r * 255.0) << 16) | (roundi(packed.g * 255.0) << 8) | roundi(packed.b * 255.0)
	var px = index % height_data.get_width()
	var pz = floori(float(index) / float(height_data.get_width()))
	var destination := Vector2(float(px) / float(height_data.get_width() - 1) * WIDTH, float(pz) / float(height_data.get_height() - 1) * DEPTH)
	if is_lake(destination.x, destination.y, clearance):
		return nearest_walkable(destination.x, destination.y, clearance)
	return destination

func _build_navigation() -> void:
	# The imported diorama contains tall obstacles. A coarse grid keeps enemy
	# pursuit connected around them; local ray steering still avoids props.
	navigation = AStarGrid2D.new()
	navigation.region = Rect2i(0, 0, NAV_COLS, NAV_ROWS)
	navigation.cell_size = Vector2(WIDTH / NAV_COLS, DEPTH / NAV_ROWS)
	navigation.offset = navigation.cell_size * 0.5
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	for z in range(NAV_ROWS):
		for x in range(NAV_COLS):
			var px = (float(x) + 0.5) * WIDTH / NAV_COLS
			var pz = (float(z) + 0.5) * DEPTH / NAV_ROWS
			if not is_walkable(px, pz, 1.0):
				navigation.set_point_solid(Vector2i(x, z), true)

func _nearest_navigation_cell(pos: Vector2) -> Vector2i:
	var cell = Vector2i(clampi(floori(pos.x / WIDTH * NAV_COLS), 0, NAV_COLS - 1), clampi(floori(pos.y / DEPTH * NAV_ROWS), 0, NAV_ROWS - 1))
	if not navigation.is_point_solid(cell):
		return cell
	for radius in range(1, 15):
		var best = Vector2i(-1, -1)
		var best_distance = INF
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dz) != radius:
					continue
				var candidate = cell + Vector2i(dx, dz)
				if not navigation.region.has_point(candidate) or navigation.is_point_solid(candidate):
					continue
				var center = (Vector2(candidate) + Vector2(0.5, 0.5)) * navigation.cell_size
				var distance = center.distance_squared_to(pos)
				if distance < best_distance:
					best_distance = distance
					best = candidate
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)

func navigation_path(from: Vector3, to: Vector3) -> PackedVector2Array:
	var result = PackedVector2Array()
	var start = _nearest_navigation_cell(Vector2(from.x, from.z))
	var target = _nearest_navigation_cell(Vector2(to.x, to.z))
	if start.x < 0 or target.x < 0:
		return result
	for cell in navigation.get_id_path(start, target):
		result.append((Vector2(cell) + Vector2(0.5, 0.5)) * navigation.cell_size)
	return result

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
	# Soften tree and building shadows to keep the camp readable in daylight.
	sun.shadow_opacity = 0.55
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
	# Bake the GLB node's +90 degree X rotation and an additional 180 degree
	# Y rotation into its mesh. The supplied island is now 256 x 176 m while
	# keeping the model's painted UVs and PBR textures.
	var source = ISLAND_MODEL.instantiate()
	var candidates = source.find_children("*", "MeshInstance3D", true, false)
	if source is MeshInstance3D:
		candidates.push_front(source)
	if candidates.is_empty():
		push_error("Модель острова не содержит сетку")
		source.free()
		return
	var original = (candidates[0] as MeshInstance3D).mesh
	var bounds = original.get_aabb()
	var sx = WIDTH / bounds.size.x
	var sz = DEPTH / bounds.size.y
	var arrays = original.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var layout_uvs = PackedVector2Array()
	layout_uvs.resize(vertices.size())
	for i in range(vertices.size()):
		var p = vertices[i]
		var n = normals[i]
		var x = (bounds.end.x - p.x) * sx
		var z = (bounds.end.y - p.y) * sz
		vertices[i] = Vector3(x, (-p.z - RAW_GROUND) * HEIGHT_SCALE, z)
		var world_normal = Vector3(-n.x / sx, -n.z / HEIGHT_SCALE, -n.y / sz).normalized()
		normals[i] = world_normal
		# Tangents transform as directions, then are re-orthogonalized against
		# the inverse-transpose normal after the non-uniform scale.
		var j = i * 4
		var tangent = Vector3(-tangents[j] * sx, -tangents[j + 2] * HEIGHT_SCALE, -tangents[j + 1] * sz)
		tangent = (tangent - world_normal * tangent.dot(world_normal)).normalized()
		tangents[j] = tangent.x
		tangents[j + 1] = tangent.y
		tangents[j + 2] = tangent.z
		layout_uvs[i] = Vector2(x / WIDTH, z / DEPTH)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV2] = layout_uvs
	var ground_mesh = ArrayMesh.new()
	ground_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material = ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	var source_material = original.surface_get_material(0) as BaseMaterial3D
	material.set_shader_parameter("base_tex", source_material.get_texture(BaseMaterial3D.TEXTURE_ALBEDO))
	material.set_shader_parameter("normal_tex", source_material.get_texture(BaseMaterial3D.TEXTURE_NORMAL))
	material.set_shader_parameter("metal_rough_tex", source_material.get_texture(BaseMaterial3D.TEXTURE_ROUGHNESS))
	material.set_shader_parameter("layout_mask", SURFACE_MASK)
	material.set_shader_parameter("grass_tex", load("res://assets/environment/textures/grass_short.jpg"))
	material.set_shader_parameter("litter_tex", load("res://assets/environment/textures/leafy_grass.jpg"))
	material.set_shader_parameter("dirt_tex", load("res://assets/environment/textures/dirt_diff_1k.jpg"))
	material.set_shader_parameter("sand_tex", load("res://assets/environment/textures/sand.jpg"))
	material.set_shader_parameter("asphalt_tex", load("res://assets/environment/textures/asphalt.jpg"))
	material.set_shader_parameter("snow_tex", load("res://assets/environment/textures/biome_snow.png"))
	material.set_shader_parameter("desert_tex", load("res://assets/environment/textures/biome_desert.png"))
	material.set_shader_parameter("rad_tex", load("res://assets/environment/textures/biome_radioactive.png"))
	material.set_shader_parameter("island_size", Vector2(WIDTH, DEPTH))
	ground_mesh.surface_set_material(0, material)
	var ground = MeshInstance3D.new()
	ground.name = "IslandTerrain"
	ground.mesh = ground_mesh
	ground.set_meta("source_model", "res://assets/models/environment/user_island.glb")
	add_child(ground)
	var body = StaticBody3D.new()
	body.name = "IslandCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape = CollisionShape3D.new()
	shape.shape = ground_mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)
	MeshCleanup.before_free(source)
	source.free()

func _build_sea() -> void:
	var mesh = PlaneMesh.new()
	mesh.size = Vector2(500, 500)
	var water := ShaderMaterial.new()
	water.shader = WATER_SHADER
	water.set_shader_parameter("deep_color", Color("294b50"))
	water.set_shader_parameter("light_color", Color("476a68"))
	water.set_shader_parameter("wave_scale", 9.0)
	mesh.material = water
	var instance = MeshInstance3D.new()
	instance.name = "Sea"
	instance.mesh = mesh
	instance.position = Vector3(WIDTH / 2.0, -1.6, DEPTH / 2.0)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _build_lake() -> void:
	if lake_map_position == Vector2.ZERO:
		return
	var center := lake_map_position * SCALE
	lake_surface_y = -INF
	for ring in [0.0, 0.5, 1.0]:
		for i in range(64):
			var angle := TAU * float(i) / 64.0
			var sample: Vector2 = center + Vector2(cos(angle) * LAKE_RADII.x, sin(angle) * LAKE_RADII.y) * float(ring)
			lake_surface_y = maxf(lake_surface_y, height_at(sample.x, sample.y))
	lake_surface_y += 0.04
	var vertices := PackedVector3Array([Vector3(center.x, lake_surface_y, center.y)])
	var normals := PackedVector3Array([Vector3.UP])
	var uvs := PackedVector2Array([Vector2(0.5, 0.5)])
	var indices := PackedInt32Array()
	for i in range(65):
		var angle := TAU * float(i) / 64.0
		var wobble := 1.0 + 0.035 * sin(angle * 5.0) + 0.02 * cos(angle * 7.0)
		var dx := cos(angle) * LAKE_RADII.x * wobble
		var dz := sin(angle) * LAKE_RADII.y * wobble
		vertices.append(Vector3(center.x + dx, lake_surface_y, center.y + dz))
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.5 + dx / (LAKE_RADII.x * 2.0), 0.5 + dz / (LAKE_RADII.y * 2.0)))
		if i > 0:
			indices.append_array(PackedInt32Array([0, i + 1, i]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var water := ShaderMaterial.new()
	water.shader = WATER_SHADER
	water.set_shader_parameter("deep_color", Color("284b4b"))
	water.set_shader_parameter("light_color", Color("6c8c7b"))
	water.set_shader_parameter("wave_scale", 1.2)
	mesh.surface_set_material(0, water)
	_build_lake_shore(center)
	var lake := MeshInstance3D.new()
	lake.name = "ForestLake"
	lake.mesh = mesh
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lake)

func _build_lake_shore(center: Vector2) -> void:
	# A narrow sandy margin follows the actual terrain and joins the animated
	# water to the surrounding clearing instead of a hard blue ellipse.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in range(65):
		var angle := TAU * float(i) / 64.0
		var wobble := 1.0 + 0.035 * sin(angle * 5.0) + 0.02 * cos(angle * 7.0)
		for scale_factor in [0.97, 1.18]:
			var offset := Vector2(cos(angle) * LAKE_RADII.x, sin(angle) * LAKE_RADII.y) * wobble * float(scale_factor)
			var p := center + offset
			vertices.append(Vector3(p.x, height_at(p.x, p.y) + 0.035, p.y))
			normals.append(Vector3.UP)
			uvs.append(p * 0.28)
		if i > 0:
			var previous := (i - 1) * 2
			var current := i * 2
			indices.append_array(PackedInt32Array([previous, current, previous + 1, previous + 1, current, current + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var sand := StandardMaterial3D.new()
	sand.albedo_texture = load("res://assets/environment/textures/sand.jpg")
	sand.albedo_color = Color("b5ad8f")
	sand.roughness = 1.0
	sand.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, sand)
	var shore := MeshInstance3D.new()
	shore.name = "ForestLakeShore"
	shore.mesh = mesh
	shore.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shore)

func _scatter_scenery() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 2291
	var fern_scene = load(FERN_PATH) as PackedScene
	var stump_scene = load("res://assets/models/nature_real/tree_stump_01.glb") as PackedScene
	if lake_map_position != Vector2.ZERO:
		var center := lake_map_position * SCALE
		for i in range(10):
			var angle := TAU * float(i) / 10.0 + 0.22
			var point := center + Vector2(cos(angle) * (LAKE_RADII.x + 2.5), sin(angle) * (LAKE_RADII.y + 2.5))
			if not is_walkable(point.x, point.y, 0.5) or _near_road(point / SCALE):
				continue
			var fern := fern_scene.instantiate() as Node3D
			fern.name = "LakeFern"
			fern.position = Vector3(point.x, height_at(point.x, point.y), point.y)
			fern.scale = Vector3.ONE * rng.randf_range(0.8, 1.2)
			fern.rotation.y = rng.randf_range(0.0, TAU)
			add_child(fern)
	# Photographic fern clusters; no invisible blockers are added to routes.
	for i in range(55):
		var p = Vector2(rng.randf_range(250, 2950), rng.randf_range(220, 1980))
		if _near_road(p) or not is_walkable(p.x * SCALE, p.y * SCALE, 1.0):
			continue
		var instance = fern_scene.instantiate() as Node3D
		instance.scale = Vector3.ONE * rng.randf_range(0.8, 1.6)
		instance.rotation.y = rng.randf_range(0, TAU)
		instance.position = Vector3(p.x * SCALE, height_at(p.x * SCALE, p.y * SCALE), p.y * SCALE)
		add_child(instance)
	for i in range(16):
		var p = Vector2(rng.randf_range(350, 2750), rng.randf_range(250, 1900))
		if _near_road(p) or not is_walkable(p.x * SCALE, p.y * SCALE, 1.0):
			continue
		var stump = stump_scene.instantiate() as Node3D
		stump.scale = Vector3.ONE * rng.randf_range(0.8, 1.4)
		stump.rotation.y = rng.randf_range(0, TAU)
		stump.position = Vector3(p.x * SCALE, height_at(p.x * SCALE, p.y * SCALE), p.y * SCALE)
		add_child(stump)
	_build_grass(rng)
	_build_sorrel(rng)

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
	var mask = surface_data
	var positions: Array[Transform3D] = []
	for i in range(26000):
		var p = Vector2(rng.randf_range(150, 3050), rng.randf_range(130, 2070))
		var uv = Vector2i(clampi(int(p.x / 3200.0 * mask.get_width()), 0, mask.get_width() - 1), clampi(int(p.y / 2200.0 * mask.get_height()), 0, mask.get_height() - 1))
		var pixel = mask.get_pixelv(uv)
		if pixel.r > 0.06 or pixel.g > 0.12 or pixel.b > 0.12 or not is_walkable(p.x * SCALE, p.y * SCALE, 1.0):
			continue
		# Spread each tuft sideways while keeping its height natural. Thin alpha
		# blades otherwise disappear at the elevated gameplay camera distance.
		var width = rng.randf_range(1.8, 4.0)
		var height = rng.randf_range(0.9, 1.6)
		var basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(width, height, width))
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

func _build_sorrel(rng: RandomNumberGenerator) -> void:
	# Broad-leaved weeds add readable detail alongside the finer grass blades.
	# Like grass, they are one batched draw and do not add collision obstacles.
	var scene = load("res://assets/models/nature_real/sorrel.glb") as PackedScene
	var source = scene.instantiate()
	var candidates = source.find_children("*", "MeshInstance3D", true, false)
	if source is MeshInstance3D:
		candidates.push_front(source)
	if candidates.is_empty():
		source.free()
		return
	var weed_mesh = (candidates[0] as MeshInstance3D).mesh
	var mask = surface_data
	var transforms: Array[Transform3D] = []
	var patches: Array[Vector2] = []
	for i in range(460):
		patches.append(Vector2(rng.randf_range(150, 3050), rng.randf_range(130, 2070)))
	for i in range(2300):
		var center = patches[int(i / 5.0)]
		var p = center + Vector2(rng.randf_range(-35, 35), rng.randf_range(-35, 35))
		var uv = Vector2i(clampi(int(p.x / 3200.0 * mask.get_width()), 0, mask.get_width() - 1), clampi(int(p.y / 2200.0 * mask.get_height()), 0, mask.get_height() - 1))
		var pixel = mask.get_pixelv(uv)
		if pixel.r > 0.06 or pixel.g > 0.12 or pixel.b > 0.12 or not is_walkable(p.x * SCALE, p.y * SCALE, 1.0):
			continue
		var size = rng.randf_range(4.5, 7.5)
		var basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
		var origin = Vector3(p.x * SCALE, height_at(p.x * SCALE, p.y * SCALE) - 0.01, p.y * SCALE)
		transforms.append(Transform3D(basis, origin))
	var multi = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = weed_mesh
	multi.instance_count = transforms.size()
	for i in range(transforms.size()):
		multi.set_instance_transform(i, transforms[i])
	var weeds = MultiMeshInstance3D.new()
	weeds.name = "GroundWeeds"
	weeds.multimesh = multi
	var weed_material = weed_mesh.surface_get_material(0)
	if weed_material is BaseMaterial3D:
		var tinted = weed_material.duplicate() as BaseMaterial3D
		tinted.albedo_color = Color(0.84, 0.88, 0.78)
		weeds.material_override = tinted
	weeds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(weeds)
	MeshCleanup.before_free(source)
	source.free()

func _near_road(p: Vector2) -> bool:
	# Share the generated road layout with the terrain shader.
	var mask = surface_data
	var x = clampi(roundi(p.x / 3200.0 * float(mask.get_width() - 1)), 0, mask.get_width() - 1)
	var z = clampi(roundi(p.y / 2200.0 * float(mask.get_height() - 1)), 0, mask.get_height() - 1)
	var pixel = mask.get_pixel(x, z)
	return pixel.r > 0.03 or pixel.g > 0.05

func _process(delta: float) -> void:
	occlusion_timer -= delta
	if occlusion_timer > 0.0:
		return
	occlusion_timer = 0.12
	var world = get_parent()
	# В headless-тестах родитель — Window без свойства player; get() вернёт
	# null без ошибки доступа. В игре поведение не меняется.
	var player = world.get("player") if world != null else null
	if player == null or not is_instance_valid(player) or not is_instance_valid(player.camera):
		return
	var target: Vector3 = player.global_position + Vector3.UP
	var eye: Vector3 = player.camera.global_position
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
