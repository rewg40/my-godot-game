class_name GameWorld
extends Node3D
## Мир забега: небо и свет, остров, растительность, лут, зомби и игрок.
##
## Всё собирается кодом в setup(): так один и тот же seed даёт один и тот же
## остров, а сохранение занимает несколько килобайт вместо гигабайтов.

const PLAYER_SCENE := preload("res://scenes/player/Player.tscn")

var island: Island
var vegetation: Vegetation
var day_night: DayNight
var stars: StarField
var player: PlayerCharacter
var save_data := {}

var environment: Environment
var sky_material: ProceduralSkyMaterial


func _ready() -> void:
	add_to_group("world")


func setup(seed_value: int, data: Dictionary = {}) -> void:
	save_data = data
	_setup_environment()

	island = Island.new()
	island.name = "Island"
	add_child(island)
	await island.setup(seed_value)

	stars = StarField.new()
	stars.name = "Stars"
	add_child(stars)
	stars.setup(seed_value)

	vegetation = Vegetation.new()
	vegetation.name = "Vegetation"
	add_child(vegetation)
	vegetation.setup(island, seed_value)

	day_night = DayNight.new()
	day_night.name = "DayNight"
	add_child(day_night)
	day_night.setup(environment, sky_material, stars)

	var ash := AshFall.new()
	ash.name = "Ash"
	add_child(ash)
	ash.setup(seed_value)

	_spawn_player()
	_restore_world_state()

	var loot := LootSpawner.new()
	loot.name = "Loot"
	add_child(loot)
	loot.setup(island, player, seed_value)

	var spawner := ZombieSpawner.new()
	spawner.name = "Zombies"
	add_child(spawner)
	spawner.setup(island, player, seed_value)


func _setup_environment() -> void:
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.2, 0.42, 0.72)
	sky_material.sky_horizon_color = Color(0.66, 0.75, 0.82)
	sky_material.ground_horizon_color = Color(0.4, 0.42, 0.4)
	sky_material.ground_bottom_color = Color(0.05, 0.05, 0.05)
	sky_material.sun_angle_max = 25.0
	sky_material.sun_curve = 0.18

	var sky := Sky.new()
	sky.sky_material = sky_material

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 1.0
	environment.ambient_light_energy = 1.0
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.32
	environment.glow_bloom = 0.06
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.6, 0.65, 0.69)
	environment.fog_density = 0.006
	environment.fog_sky_affect = 0.25
	environment.fog_aerial_perspective = 0.45
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.05
	environment.adjustment_saturation = 1.05

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = environment
	add_child(world_env)


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate() as PlayerCharacter
	player.name = "Player"
	add_child(player)
	if save_data.has("player"):
		player.apply_state(save_data["player"])
	else:
		player.global_position = island.get_spawn_point()
	GameState.player_spawned.emit(player)


func _restore_world_state() -> void:
	if save_data.is_empty():
		return
	GameState.day_index = int(save_data.get("day", 1))
	GameState.time_of_day = float(save_data.get("time", 0.29))
	GameState.run_stats = save_data.get("stats", GameState.run_stats)
	var fires: Array = save_data.get("campfires", [])
	for entry in fires:
		if entry is Array and entry.size() == 3:
			spawn_campfire(Vector3(float(entry[0]), float(entry[1]), float(entry[2])))


## Ставит костёр на землю в указанной точке.
func spawn_campfire(position: Vector3) -> void:
	var fire := Campfire.new()
	fire.name = "Campfire"
	add_child(fire)
	var ground := 0.0
	if island != null:
		ground = island.height_at(position.x, position.z)
	fire.global_position = Vector3(position.x, ground, position.z)


func get_player() -> PlayerCharacter:
	return player


## Точка, куда возвращаем игрока, если он ушёл под воду.
func get_spawn_point() -> Vector3:
	if island != null:
		return island.get_spawn_point()
	return Vector3(0.0, 6.0, 0.0)


func get_save_data() -> Dictionary:
	var data := {
		"version": 1,
		"seed": GameState.world_seed,
		"class": GameState.selected_class,
		"day": GameState.day_index,
		"time": GameState.time_of_day,
		"stats": GameState.run_stats.duplicate(),
		"player": {},
		"campfires": [],
	}
	if player != null and is_instance_valid(player):
		data["player"] = player.get_state()
	for fire in get_tree().get_nodes_in_group("campfires"):
		if fire is Node3D:
			var pos := (fire as Node3D).global_position
			data["campfires"].append([pos.x, pos.y, pos.z])
	return data


func is_near_fire(position: Vector3, radius: float = 6.0) -> bool:
	for fire in get_tree().get_nodes_in_group("campfires"):
		if fire is Node3D and (fire as Node3D).global_position.distance_to(position) <= radius:
			return true
	return false
