extends Node3D
## Точка входа полигона: остров, медик с мечом, три зомби и интерфейс.
##
## Всё собирается кодом, поэтому отдельные сцены не нужны: модели подхватываются из
## assets/models, а если их нет — подставляются заглушки из примитивов.

const UI := preload("res://scripts/ui_theme.gd")
const ZOMBIE_COUNT := 3
const ZOMBIE_RING := 7.5

var world: IslandWorld
var player: SwordPlayer
var zombies: Array = []
var hud: Hud

var _loading: Label
var _zones_debug := false


func _ready() -> void:
	Controls.register()
	_build_environment()
	_show_loading()
	await get_tree().process_frame

	world = IslandWorld.new()
	world.name = "Island"
	add_child(world)
	await world.build()

	_spawn_player()
	_spawn_zombies()
	_build_hud()
	_clear_loading()
	hud.show_log("Меч: 3 удара по конечности — отрубит. Корпус — 1000 HP.")


func _build_environment() -> void:
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.24, 0.33, 0.45)
	sky_material.sky_horizon_color = Color(0.63, 0.67, 0.71)
	sky_material.ground_bottom_color = Color(0.08, 0.09, 0.1)
	sky_material.ground_horizon_color = Color(0.42, 0.45, 0.47)
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.85
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.56, 0.61, 0.66)
	environment.fog_density = 0.0035
	environment.fog_sky_affect = 0.4

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-46.0, -38.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	add_child(sun)


func _show_loading() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Loading"
	layer.layer = 20
	add_child(layer)
	_loading = UI.title("Загрузка острова…", 30)
	UI.anchor(_loading, Control.PRESET_CENTER, Vector4(-260.0, -30.0, 260.0, 30.0))
	layer.add_child(_loading)


func _clear_loading() -> void:
	var layer := get_node_or_null("Loading")
	if layer != null:
		layer.queue_free()
	_loading = null


func _spawn_player() -> void:
	player = SwordPlayer.new()
	player.name = "Player"
	player.spawn_point = world.spawn_point()
	add_child(player)
	player.global_position = world.spawn_point()
	player.health_changed.connect(_on_player_health)
	player.hit_landed.connect(_on_hit_landed)


func _spawn_zombies() -> void:
	var spots := world.ring_points(ZOMBIE_COUNT, ZOMBIE_RING)
	for index in ZOMBIE_COUNT:
		var zombie := Zombie.new()
		zombie.name = "Zombie%d" % (index + 1)
		zombie.setup(index + 1, player)
		add_child(zombie)
		zombie.global_position = spots[index]
		zombie.limb_lost.connect(_on_limb_lost)
		zombie.died.connect(_on_zombie_died)
		zombie.attack_landed.connect(_on_zombie_attack)
		zombies.append(zombie)


func _build_hud() -> void:
	hud = Hud.new()
	hud.name = "Hud"
	hud.setup(player, zombies, world.source)
	add_child(hud)


func _on_hit_landed(info: Dictionary) -> void:
	if hud == null:
		return
	hud.flash_hit()
	if bool(info.get("severed", false)):
		hud.show_log("Отрублено: %s" % String(info.get("title", "")))
	else:
		hud.show_log("Удар: %s — осталось %d" % [
			String(info.get("title", "")), int(ceil(float(info.get("hp", 0.0))))])


func _on_limb_lost(zombie: Zombie, part_id: String) -> void:
	if hud == null:
		return
	var title := ModelProfiles.part_title(part_id)
	var note := "Зомби %d: %s отрублена — " % [zombie.index, title]
	if part_id.begins_with("leg"):
		if zombie.leg_count() == 0:
			note += "он больше не может идти и ползёт"
		else:
			note += "хромает на одной ноге"
	elif zombie.arm_count() == 0:
		note += "рук нет, бить не может"
	else:
		note += "продолжает идти"
	hud.show_log(note)


func _on_zombie_died(zombie: Zombie) -> void:
	if hud != null:
		hud.show_log("Зомби %d добит" % zombie.index)


func _on_zombie_attack(zombie: Zombie) -> void:
	if hud != null:
		hud.show_log("Зомби %d ударил" % zombie.index)


func _on_player_health(_player: SwordPlayer) -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()
	elif event.is_action_pressed("quit"):
		get_tree().quit()
	elif event.is_action_pressed("toggle_help") and hud != null:
		hud.toggle_help()
	elif event.is_action_pressed("toggle_limb_zones"):
		_zones_debug = not _zones_debug
		for zombie in zombies:
			if is_instance_valid(zombie):
				zombie.rig.set_debug_zones(_zones_debug)
		if hud != null:
			hud.show_log("Зоны попадания: %s" % ("включены" if _zones_debug else "выключены"))
