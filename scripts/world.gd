extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const PropScript = preload("res://scripts/prop.gd")
const HudScript = preload("res://scripts/hud.gd")
const SaveGame = preload("res://scripts/save_game.gd")
const Environment3D = preload("res://scripts/environment_3d.gd")
const Roadside3D = preload("res://scripts/roadside_3d.gd")
const MeshCleanup = preload("res://scripts/mesh_cleanup.gd")
const BuildingSystem = preload("res://scripts/build_system.gd")
const IslandMigration = preload("res://scripts/island_migration.gd")
const MAP_SCALE := 0.08
const STARTING_SHORE = Vector2(360, 1830)
const SITES = {
	"hotel": Vector2(2150, 1440), "safe": Vector2(2250, 1510),
	"keycard": Vector2(2850, 500), "chip": Vector2(2850, 700),
	"coil": Vector2(590, 430), "cell": Vector2(1360, 450),
	"lighthouse": Vector2(2750, 1800), "boat": Vector2(380, 1950),
}

var main
var load_data: Dictionary = {}
var player
var hud
var building: Node3D
var props: Array = []
var enemies: Array = []
var inventory: Dictionary = {"wood": 0, "stone": 0, "iron": 0, "cloth": 1, "food": 2, "water": 2, "herbs": 0, "bandage": 1}
var flags: Dictionary = {}
var equipped_weapon: String = ""
var dead_ids: Array = []
var depleted_resources: Array[String] = []
var quest_stage: int = 0
var day: int = 1
var minute: float = 480.0
var elapsed: float = 0.0
var autosave_clock: float = 0.0
var environment_3d: Node3D
var goal_marker: Node3D
var sound: AudioStreamPlayer

func _ready() -> void:
	name = "ShelterWorld3D"
	if not load_data.is_empty():
		load_data = IslandMigration.migrate(load_data)
	environment_3d = Environment3D.new()
	environment_3d.saved_layout = load_data
	add_child(environment_3d)
	if not load_data.is_empty():
		_apply_save(load_data)
	# Restore the player's base before scattering resources so an existing
	# house never has a newly generated tree or boulder placed inside it.
	building = BuildingSystem.new()
	building.world = self
	add_child(building)
	var saved_buildings = load_data.get("buildings", [])
	if saved_buildings is Array:
		building.restore(saved_buildings)
	_build_world()
	var roadside = Roadside3D.new()
	roadside.name = "RoadsideDetails"
	add_child(roadside)
	roadside.build(self)
	player = PlayerScript.new()
	player.world = self
	player.position = _safe_player_spawn(_saved_position()) + Vector3.UP * 0.12
	if not load_data.is_empty():
		var ps = load_data.get("player", {})
		if ps is Dictionary:
			player.health = clampf(float(ps.get("health", 100.0)), 1, 100)
			player.stamina = clampf(float(ps.get("stamina", 100.0)), 0, 100)
			player.hunger = clampf(float(ps.get("hunger", 100.0)), 0, 100)
			player.thirst = clampf(float(ps.get("thirst", 100.0)), 0, 100)
	add_child(player)
	sound = AudioStreamPlayer.new()
	sound.volume_db = -14
	add_child(sound)
	hud = HudScript.new()
	hud.world = self
	add_child(hud)
	_spawn_initial_enemies()
	_setup_goal_marker()
	if load_data.is_empty():
		hud.dialogue("Один на острове", "Вы на берегу Приюта. Собирайте древесину и камень, выберите место и нажмите B, чтобы построить собственную базу. Исследуйте остров, но берегитесь заражённых.")
		save_progress(false)
	else:
		hud.toast("С возвращением на остров Приют.")

func _exit_tree() -> void:
	if is_instance_valid(sound):
		sound.stop()
		sound.stream = null
	MeshCleanup.before_free(self)

# Map coordinates remain stable for the journal and old saves; world actors,
# collisions and the camera all use true 3D metres in X/Y/Z.
func map_to_world(point: Vector2, clearance: float = 1.0) -> Vector3:
	var position_2d: Vector2 = environment_3d.nearest_walkable(point.x * MAP_SCALE, point.y * MAP_SCALE, clearance)
	return Vector3(position_2d.x, environment_3d.height_at(position_2d.x, position_2d.y), position_2d.y)

func world_to_map(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z) / MAP_SCALE

func _safe_player_spawn(point: Vector2) -> Vector3:
	# A constructed floor is already checked for solid scenery at placement.
	# Preserve an exact saved position on it even when the terrain's conservative
	# walkability map would move a player to a distant clearing. Avoid placing
	# the character inside one of their own walls or closed doors.
	var requested := point * MAP_SCALE
	if is_instance_valid(building):
		var floor_y: float = building.floor_height_at(requested)
		if is_finite(floor_y):
			if _built_spawn_clear(requested, floor_y):
				return Vector3(requested.x, _spawn_height(requested.x, requested.y), requested.y)
			for ring in range(1, 9):
				var radius := float(ring) * 0.2
				for i in range(16):
					var angle := TAU * float(i) / 16.0
					var candidate := requested + Vector2(cos(angle), sin(angle)) * radius
					var candidate_floor: float = building.floor_height_at(candidate)
					if is_finite(candidate_floor) and _built_spawn_clear(candidate, candidate_floor):
						return Vector3(candidate.x, _spawn_height(candidate.x, candidate.y), candidate.y)
	# Legacy positions may be in water or inside scenery.
	var origin = map_to_world(point)
	origin.y = _spawn_height(origin.x, origin.z)
	var circles: Array[Vector3] = [] # x / z / conservative horizontal radius
	var island_body = environment_3d.get_node("IslandCollision")
	for body in find_children("*", "StaticBody3D", true, false):
		if body == island_body or body.get_meta("player_built", false):
			continue
		for item in body.find_children("*", "CollisionShape3D", true, false):
			var shape = item as CollisionShape3D
			if shape.disabled or shape.shape == null:
				continue
			var radius = 0.0
			if shape.shape is CylinderShape3D:
				radius = (shape.shape as CylinderShape3D).radius
			elif shape.shape is CapsuleShape3D:
				radius = (shape.shape as CapsuleShape3D).radius
			elif shape.shape is SphereShape3D:
				radius = (shape.shape as SphereShape3D).radius
			elif shape.shape is BoxShape3D:
				var size = (shape.shape as BoxShape3D).size
				radius = Vector2(size.x, size.z).length() * 0.5
			if radius > 0.0:
				var scale = shape.global_basis.get_scale()
				radius *= maxf(absf(scale.x), absf(scale.z))
				circles.append(Vector3(shape.global_position.x, shape.global_position.z, radius + 0.42))
	var horizontal = Vector2(origin.x, origin.z)
	if _spawn_clear(horizontal, circles):
		return origin
	for ring in range(1, 51):
		var radius = float(ring) * 0.4
		var steps = clampi(ceili(TAU * radius / 0.4), 16, 160)
		for i in range(steps):
			var angle = TAU * float(i) / float(steps)
			var candidate = horizontal + Vector2(cos(angle), sin(angle)) * radius
			if environment_3d.is_walkable(candidate.x, candidate.y) and _spawn_clear(candidate, circles):
				return Vector3(candidate.x, _spawn_height(candidate.x, candidate.y), candidate.y)
	return origin

func _built_spawn_clear(point: Vector2, floor_y: float) -> bool:
	var middle := Vector3(point.x, floor_y + 0.88, point.y)
	for piece in building.pieces.values():
		if not is_instance_valid(piece) or piece.data.get("type", "") not in ["wall", "doorway", "door"]:
			continue
		for collision in piece.find_children("*", "CollisionShape3D", true, false):
			if collision.disabled or not collision.shape is BoxShape3D:
				continue
			var local: Vector3 = collision.to_local(middle)
			var half: Vector3 = (collision.shape as BoxShape3D).size * 0.5
			if absf(local.x) < half.x + 0.40 and absf(local.z) < half.z + 0.40 and absf(local.y) < half.y + 0.87:
				return false
	return true

func _spawn_height(x: float, z: float) -> float:
	var height: float = environment_3d.height_at(x, z)
	if is_instance_valid(building):
		height = maxf(height, building.floor_height_at(Vector2(x, z)))
	return height

func _spawn_clear(point: Vector2, circles: Array[Vector3]) -> bool:
	for obstacle in circles:
		if point.distance_squared_to(Vector2(obstacle.x, obstacle.y)) < obstacle.z * obstacle.z:
			return false
	return true

func _setup_goal_marker() -> void:
	goal_marker = Node3D.new()
	goal_marker.name = "ObjectiveBeacon"
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("f4c971")
	material.emission_enabled = true
	material.emission = Color("f4c971")
	material.emission_energy_multiplier = 1.3
	var diamond = BoxMesh.new()
	diamond.size = Vector3(0.35, 0.35, 0.35)
	diamond.material = material
	var mesh = MeshInstance3D.new()
	mesh.mesh = diamond
	mesh.rotation_degrees = Vector3(0, 45, 45)
	goal_marker.add_child(mesh)
	add_child(goal_marker)

func _build_world() -> void:
	# The first-island landmarks now use actual 3D geometry. Their map
	# coordinates match the original quest, which also keeps old saves usable.
	_deco(Vector2(2314, 1443), "res://assets/models/kenney/city-industrial/building-a.glb", 3.5, 35)
	_deco(Vector2(2500, 500), "res://assets/models/kenney/city-industrial/building-a.glb", 3.8, 33)
	_deco(Vector2(570, 345), "res://assets/models/kenney/nature/cliff_cave_rock.glb", 5.0, 30)
	_deco(Vector2(1550, 380), "res://assets/models/kenney/survival/structure-metal.glb", 4.8, 24)
	# Abandoned cars sit beside old routes without replacing quest objects.
	_deco(Vector2(500, 1770), "res://assets/models/props/abandoned_sedan.glb", 0.08, 24, -0.45)
	_deco(Vector2(1530, 1510), "res://assets/models/props/abandoned_sedan.glb", 0.08, 24, 0.35)
	_deco(Vector2(2128, 1589), "res://assets/models/props/abandoned_sedan.glb", 0.08, 24, 2.4)
	_deco(Vector2(2460, 960), "res://assets/models/props/abandoned_sedan.glb", 0.08, 24, -0.6)
	# No NPC camp, fixed tower plots or defence wave: the player chooses where
	# to build. Refillable water barrels keep survival possible without a well.
	var water_points = [Vector2(475, 1770), Vector2(1010, 1410), Vector2(1950, 1450), Vector2(2620, 780)]
	for i in range(water_points.size()):
		_make("water_%d" % i, "water", "Бочка с водой", water_points[i], {"collision": 10})
	_make("hotel", "hotel", "Руины отеля «Аврора»", SITES.hotel)
	_make("safe", "safe", "Сейф в руинах «Авроры»", SITES.safe, {"collision": 15})
	_make("keycard", "keycard", "Ключ-карта на аэродроме", SITES.keycard)
	_make("chip", "chip", "Микросхема на аэродроме", SITES.chip, {"collision": 14})
	_make("coil", "coil", "Медная катушка у пещеры", SITES.coil, {"collision": 14})
	_make("cell", "cell", "Энергоячейка в лесу", SITES.cell, {"collision": 14})
	_make("lighthouse", "lighthouse", "Старый маяк", SITES.lighthouse, {"collision": 23})
	_make("boat", "boat", "Лодка у причала", SITES.boat, {"collision": 15})
	var trees = [Vector2(330,1530),Vector2(460,1515),Vector2(535,1580),Vector2(290,1320),Vector2(445,1260),Vector2(1160,1010),Vector2(1220,1170),Vector2(1330,1200),Vector2(1300,850),Vector2(1440,720),Vector2(1535,665),Vector2(1600,540),Vector2(1420,350),Vector2(1280,430),Vector2(1140,470),Vector2(860,420),Vector2(780,590),Vector2(350,600),Vector2(480,700),Vector2(1790,940),Vector2(1850,1150),Vector2(1850,1730),Vector2(2400,1750),Vector2(900,1820),Vector2(650,1830)]
	for i in range(trees.size()):
		_make("tree_%d" % i, "tree", "Дерево", trees[i], {"collision": 14})
	var rocks = [Vector2(415,1640),Vector2(520,1410),Vector2(310,1120),Vector2(1170,1420),Vector2(1270,1510),Vector2(1310,950),Vector2(750,680),Vector2(650,550),Vector2(490,470),Vector2(800,320),Vector2(1640,760),Vector2(1810,1400),Vector2(2400,1220),Vector2(2800,1510)]
	for i in range(rocks.size()):
		_make("rock_%d" % i, "rock", "Камни", rocks[i], {"collision": 15})
	var scrap = [Vector2(2200,1630),Vector2(2350,1380),Vector2(2510,800),Vector2(2700,540),Vector2(2770,850),Vector2(2440,680),Vector2(1270,1700),Vector2(650,1740)]
	for i in range(scrap.size()):
		_make("scrap_%d" % i, "scrap", "Металлолом", scrap[i], {"collision": 12})
	var crates = [Vector2(310,1760),Vector2(500,1710),Vector2(570,1320),Vector2(1150,1320),Vector2(1940,1490),Vector2(2300,1310),Vector2(2500,710),Vector2(2760,740),Vector2(510,980),Vector2(1650,500)]
	for i in range(crates.size()):
		_make("crate_%d" % i, "crate", "Ящик с тканью", crates[i], {"collision": 12})
	var bushes = [Vector2(530,1830),Vector2(650,1550),Vector2(1190,1580),Vector2(1230,760),Vector2(1540,820),Vector2(1040,660),Vector2(400,820),Vector2(510,540),Vector2(1720,1300),Vector2(1950,1750)]
	for i in range(bushes.size()):
		_make("bush_%d" % i, "bush", "Ягоды и травы", bushes[i])
	_scatter_resource_nodes()

func _resource_near_base(pos: Vector3) -> bool:
	if not is_instance_valid(building):
		return false
	var x := roundi(pos.x / 3.0)
	var z := roundi(pos.z / 3.0)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var floor = building.foundation_at(x + dx, z + dz)
			if is_instance_valid(floor) and Vector2(pos.x - floor.position.x, pos.z - floor.position.z).length() < 3.0:
				return true
	return false

func _scatter_resource_nodes() -> void:
	# Deterministic, separate physical objects (not decorative multimeshes).
	# A depleted id remains reserved, so reloading does not regrow the same
	# tree at a different index or move another tree into a player's base.
	var rng := RandomNumberGenerator.new()
	rng.seed = 91732
	var placed: Array[Vector2] = []
	var landmarks := [STARTING_SHORE, SITES.hotel, SITES.safe, SITES.keycard, SITES.chip, SITES.coil, SITES.cell, SITES.lighthouse, SITES.boat]
	var accepted := 0
	for i in range(1100):
		if accepted >= 245:
			break
		var point := Vector2(rng.randf_range(180, 3020), rng.randf_range(160, 2040))
		var tree := rng.randf() < 0.70
		var broadleaf := rng.randf() < 0.32
		var size := rng.randf_range(1.0, 1.35) if broadleaf else rng.randf_range(0.48, 0.66)
		var rock_size := rng.randf_range(3.2, 5.0)
		var yaw := rng.randf_range(0.0, TAU)
		var world_point := point * MAP_SCALE
		if not environment_3d.is_walkable(world_point.x, world_point.y, 1.5) or environment_3d._near_road(point) or environment_3d.is_lake(world_point.x, world_point.y, 5.0):
			continue
		var clear := true
		for landmark in landmarks:
			if point.distance_to(landmark) * MAP_SCALE < 11.0:
				clear = false
				break
		if not clear:
			continue
		for other in placed:
			if world_point.distance_squared_to(other) < 4.8 * 4.8:
				clear = false
				break
		if not clear:
			continue
		var pos := Vector3(world_point.x, environment_3d.height_at(world_point.x, world_point.y), world_point.y)
		if _resource_near_base(pos):
			continue
		placed.append(world_point)
		accepted += 1
		var id := ("grove_tree_%04d" if tree else "grove_rock_%04d") % i
		var model := "res://assets/models/nature_real/broadleaf.glb" if broadleaf else "res://assets/models/nature_real/pine.glb"
		if tree:
			_make(id, "tree", "Дерево", point, {"collision": 14, "model": model, "model_scale": size, "yaw": yaw})
		else:
			_make(id, "rock", "Камень", point, {"collision": 15, "model_scale": rock_size, "yaw": yaw})

func _make(identity: String, kind: String, title: String, pos: Vector2, detail: Dictionary = {}):
	if kind in ["tree", "rock"] and identity in depleted_resources:
		return null
	var prop = PropScript.new()
	prop.configure(self, identity, kind, title, detail)
	# Keep large decorative buildings clear of the imported cliffs and walls.
	var clearance = 2.5 if kind == "deco" and "building-" in String(detail.get("model", "")) else 1.0
	prop.position = map_to_world(pos, clearance)
	if kind in ["tree", "rock"] and _resource_near_base(prop.position):
		prop.free()
		return null
	add_child(prop)
	if kind in ["keycard", "chip", "coil", "cell"] and flags.get(kind, false):
		prop.visible = false
	props.append(prop)
	return prop

func _deco(pos: Vector2, model_path: String, size: float, radius: float, yaw: float = 0.0) -> void:
	_make("", "deco", "", pos, {"model": model_path, "model_scale": size, "collision": radius, "yaw": yaw})

func _spawn_initial_enemies() -> void:
	var data = [
		["wild_0", "walker", Vector2(1400, 700)], ["wild_1", "runner", Vector2(1590, 510)],
		["wild_2", "walker", Vector2(570, 570)], ["wild_3", "walker", Vector2(740, 400)],
		["wild_4", "walker", Vector2(1990, 1430)], ["wild_5", "walker", Vector2(2320, 1550)],
		["wild_6", "runner", Vector2(2500, 610)], ["wild_7", "walker", Vector2(2650, 590)],
		["wild_8", "walker", Vector2(2780, 770)], ["wild_9", "walker", Vector2(2680, 1670)],
		["wild_10", "runner", Vector2(2860, 1820)], ["wild_11", "walker", Vector2(1820, 1020)],
	]
	for item in data:
		if item[0] not in dead_ids:
			spawn_enemy(item[0], item[1], item[2], "wild")
	if quest_stage == 4:
		spawn_enemy("boss_hotel", "bloated", SITES.hotel + Vector2(110, 70), "boss")
	if quest_stage == 7:
		spawn_enemy("boss_lighthouse", "screamer", SITES.lighthouse + Vector2(-100, -50), "boss")

func spawn_enemy(identity: String, kind: String, pos: Vector2, group_name: String):
	var enemy = EnemyScript.new()
	enemy.configure(self, identity, kind, group_name)
	enemy.position = map_to_world(pos) + Vector3.UP * 0.12
	add_child(enemy)
	enemies.append(enemy)
	return enemy

func _process(delta: float) -> void:
	if not is_instance_valid(hud) or is_paused():
		return
	elapsed += delta
	autosave_clock += delta
	minute += delta # 1440 real seconds = one game day.
	if minute >= 1440.0:
		minute -= 1440.0
		day += 1
	player.hunger = maxf(0.0, player.hunger - delta * 0.022)
	player.thirst = maxf(0.0, player.thirst - delta * 0.035)
	if player.hunger <= 0.0 or player.thirst <= 0.0:
		player.health = maxf(0.0, player.health - delta * 1.2)
		if player.health <= 0.0:
			player_defeated()
	var light = 0.0
	if minute >= 1140 and minute < 1200:
		light = (minute - 1140.0) / 60.0
	elif minute >= 1200 or minute < 300:
		light = 1.0
	elif minute < 360:
		light = 1.0 - (minute - 300.0) / 60.0
	environment_3d.set_night(light)
	if is_instance_valid(goal_marker):
		goal_marker.position = map_to_world(objective_position()) + Vector3.UP * (3.0 + 0.18 * sin(elapsed * 3.0))
		goal_marker.rotation.y += delta * 0.8
	if autosave_clock >= 45.0:
		autosave_clock = 0.0
		save_progress(false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if building.active and not hud.is_modal_open():
			building.place_current()
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode
	if key == 0:
		key = event.keycode
	if key == KEY_ESCAPE:
		if hud.is_modal_open():
			hud.close_modal()
		elif building.active:
			building.set_active(false)
		else:
			hud.show_pause()
		get_viewport().set_input_as_handled()
		return
	if hud.is_modal_open():
		return
	if key == KEY_B:
		building.toggle()
		get_viewport().set_input_as_handled()
		return
	if building.active:
		match key:
			KEY_1: building.select_type("foundation")
			KEY_2: building.select_type("wall")
			KEY_3: building.select_type("roof")
			KEY_4: building.select_type("doorway")
			KEY_5: building.select_type("door")
			KEY_R: building.rotate_selection()
			KEY_X: building.remove_current()
			KEY_E:
				var door = building.nearest_door()
				if door: building.interact_door(door)
			KEY_F5: save_progress(true)
		get_viewport().set_input_as_handled()
		return
	match key:
		KEY_E:
			var door = building.nearest_door()
			if door:
				building.interact_door(door)
			else:
				var prop = nearest_prop()
				if prop: interact(prop)
		KEY_C: hud.show_crafting()
		KEY_TAB: hud.show_inventory()
		KEY_M: hud.show_map()
		KEY_Q: switch_weapon()
		KEY_1: use_item("food")
		KEY_2: use_item("water")
		KEY_3: use_item("bandage")
		KEY_F5: save_progress(true)

func is_paused() -> bool:
	return is_instance_valid(hud) and hud.is_modal_open()

func is_night() -> bool:
	return minute >= 1200.0 or minute < 360.0

func clock_string() -> String:
	return "%02d:%02d" % [int(minute / 60.0), int(minute) % 60]

func play_sound(which: String) -> void:
	if DisplayServer.get_name() == "headless" or not is_instance_valid(sound):
		return
	var sounds = {"pickup": "res://assets/audio/pickup.ogg", "hit": "res://assets/audio/hit.ogg", "complete": "res://assets/audio/complete.ogg"}
	if sounds.has(which):
		sound.stream = load(sounds[which])
		sound.play()

func count(item: String) -> int:
	return int(inventory.get(item, 0))

func give(item: String, amount: int) -> void:
	inventory[item] = count(item) + amount

func can_afford(cost: Dictionary) -> bool:
	for item in cost:
		if count(item) < int(cost[item]):
			return false
	return true

func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for item in cost:
		inventory[item] = count(item) - int(cost[item])
	return true

func nearest_prop():
	if not is_instance_valid(player):
		return null
	var nearest = null
	var distance = 3.8 / MAP_SCALE
	for prop in props:
		if not is_instance_valid(prop) or prop.kind == "deco" or not prop.usable:
			continue
		if prop.kind in ["keycard", "chip", "coil", "cell"] and flags.get(prop.kind, false):
			continue
		var d: float = world_to_map(player.global_position).distance_to(world_to_map(prop.global_position))
		if d < distance:
			distance = d
			nearest = prop
	return nearest

func prompt_for(prop) -> String:
	if prop.kind in ["tree", "rock"]:
		return "%s  ·  ударьте ЛКМ/F или E" % prop.title
	if prop.kind == "boat" and quest_stage == 9:
		return "Починить лодку  ·  15 дерева + 5 металла + 5 ткани"
	return prop.title

func interact(prop) -> void:
	if not is_instance_valid(prop) or not prop.usable:
		return
	match prop.kind:
		"tree", "rock": _damage_resource(prop)
		"scrap", "crate", "bush", "water": _harvest(prop)
		"hotel": _enter_hotel()
		"safe": _open_safe()
		"keycard", "chip", "coil", "cell": _collect_quest_item(prop)
		"lighthouse": _repair_lighthouse()
		"boat": _repair_boat()

func _harvest(prop) -> void:
	var message = ""
	match prop.kind:
		"scrap": give("iron", 3); message = "+3 металлолома"
		"crate": give("cloth", 2); message = "+2 ткани"
		"bush": give("food", 2); give("herbs", 1); message = "+2 еды и +1 трава"
		"water": give("water", 3); message = "+3 воды"
	prop.deplete(35.0 if prop.kind != "water" else 15.0)
	play_sound("pickup")
	hud.toast(message)

func _damage_resource(prop) -> void:
	if not is_instance_valid(prop) or not prop.usable or prop.kind not in ["tree", "rock"]:
		return
	prop.resource_health -= 2 if flags.get("axe", false) else 1
	if prop.resource_health > 0:
		play_sound("hit")
		hud.toast("%s  ·  прочность %d / %d" % [prop.title, prop.resource_health, prop.resource_max_health], 1.2)
		return
	prop.usable = false
	var item := "wood" if prop.kind == "tree" else "stone"
	var amount := (8 if flags.get("axe", false) else 6) if item == "wood" else (6 if flags.get("axe", false) else 4)
	give(item, amount)
	if prop.prop_id not in depleted_resources:
		depleted_resources.append(prop.prop_id)
	# Remove collision immediately as well as the visible instance. The state
	# is saved so a cleared spot stays usable for the player's own base.
	for body in prop.find_children("*", "StaticBody3D", true, false):
		body.collision_layer = 0
	prop.visible = false
	prop.queue_free()
	play_sound("pickup")
	hud.toast("+%d %s" % [amount, "древесины" if item == "wood" else "камня"])
	if not save_progress(false):
		hud.toast("Ресурсы добыты, но сохранить игру не удалось.")

func player_attack(direction: Vector3) -> void:
	var weapon = weapon_id()
	var damage = 28.0 if weapon == "spear" else (20.0 if weapon == "club" else 12.0)
	var hit = false
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.is_dead:
			continue
		var offset: Vector3 = enemy.global_position - player.global_position
		offset.y = 0
		if offset.length() <= 3.4 and (offset.length() < 0.48 or offset.normalized().dot(direction) > -0.05):
			var from: Vector3 = player.global_position + Vector3.UP * 0.85
			var to: Vector3 = enemy.global_position + Vector3.UP * 0.85
			var query = PhysicsRayQueryParameters3D.create(from, to, 1 | (1 << 3))
			if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				enemy.take_damage(damage, player.global_position)
				hit = true
	var closest = null
	var closest_distance := 3.0
	for prop in props:
		if not is_instance_valid(prop) or not prop.usable or prop.kind not in ["tree", "rock"]:
			continue
		var offset: Vector3 = prop.global_position - player.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance >= closest_distance or (distance > 0.48 and offset.normalized().dot(direction) < 0.35):
			continue
		var from: Vector3 = player.global_position + Vector3.UP * 0.85
		var to: Vector3 = prop.global_position + Vector3.UP * 0.85
		var query = PhysicsRayQueryParameters3D.create(from, to, 1 | (1 << 3))
		var obstacle = get_world_3d().direct_space_state.intersect_ray(query)
		if obstacle.is_empty() or prop.is_ancestor_of(obstacle.get("collider")):
			closest = prop
			closest_distance = distance
	if closest != null:
		_damage_resource(closest)
	elif hit:
		play_sound("hit")

func enemy_defeated(enemy) -> void:
	if enemy.group_name == "wild" and enemy.enemy_id not in dead_ids:
		dead_ids.append(enemy.enemy_id)
		give("cloth", 1)
	if enemy.enemy_id == "boss_hotel" and quest_stage == 4:
		quest_stage = 5
		give("bandage", 2)
		play_sound("complete")
		hud.toast("Раздутый повержен. Найдите ключ-карту на аэродроме.", 5.0)
		save_progress(false)
	elif enemy.enemy_id == "boss_lighthouse" and quest_stage == 7:
		quest_stage = 9
		flags["lighthouse"] = true
		play_sound("complete")
		hud.dialogue("Маяк надежды", "Крикун повержен, антенна снова работает. Теперь можно восстановить лодку на берегу и продолжить путь.")
		save_progress(false)

func screamer_call(pos: Vector3) -> void:
	var active = 0
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.is_dead and enemy.group_name == "summon":
			active += 1
	if active < 3:
		spawn_enemy("summon_%d" % int(elapsed * 1000), "walker", world_to_map(pos) + Vector2(95, 30), "summon")
		hud.toast("Крикун зовёт заражённых!", 2.5)

func player_defeated() -> void:
	# A queued bat strike must not land from the respawn location.
	player.cancel_attack()
	player.health = 65.0
	player.stamina = 100.0
	player.hunger = maxf(player.hunger, 25.0)
	player.thirst = maxf(player.thirst, 25.0)
	var base: Vector3 = building.first_foundation_position()
	var spawn = world_to_map(base) if base.is_finite() else STARTING_SHORE
	player.global_position = _safe_player_spawn(spawn) + Vector3.UP * 0.12
	player.velocity = Vector3.ZERO
	player.invulnerable = 3.0
	hud.toast("Вы потеряли сознание и очнулись на своей базе." if base.is_finite() else "Вы потеряли сознание и очнулись на берегу.", 5.0)
	save_progress(false)

func _enter_hotel() -> void:
	if quest_stage <= 3:
		quest_stage = 4
		spawn_enemy("boss_hotel", "bloated", SITES.hotel + Vector2(110, 70), "boss")
		hud.dialogue("Тени в «Авроре»", "Под обвалившимся входом обнаружен запертый сейф. Из руин выходит Раздутый — не стойте рядом, когда он погибнет: он взрывается.")
		save_progress(false)
	elif quest_stage == 4:
		hud.toast("Победите Раздутого у отеля.")
	else:
		hud.dialogue("Отель «Аврора»", "В руинах ещё сохранился старый серверный сейф. Ключ-карту могли оставить на аэродроме.")

func _open_safe() -> void:
	if flags.get("fragment", false):
		hud.dialogue("Сейф «Авроры»", "Сейф открыт. Первый фрагмент кода ПРОМЕТЕЯ уже у вас.")
	elif quest_stage < 5:
		hud.dialogue("Сейф «Авроры»", "Сейф заперт. Сначала исследуйте отель и разберитесь с тем, кто скрывается в руинах.")
	elif not flags.get("keycard", false):
		hud.dialogue("Сейф «Авроры»", "Замок требует ключ-карту. Ищите её у разбитой техники на аэродроме.")
	else:
		flags["fragment"] = true
		quest_stage = 6
		play_sound("complete")
		hud.dialogue("Голограмма доктора Вранской", "Если вы видите эту запись, ПРОМЕТЕЙ ещё активен. Код разделён на семь частей. Возьмите первую и восстановите маяк: людям понадобится свет, чтобы найти друг друга.")
		save_progress(false)

func _collect_quest_item(prop) -> void:
	flags[prop.kind] = true
	play_sound("pickup")
	match prop.kind:
		"keycard": hud.toast("Найдена ключ-карта от сейфа «Авроры».")
		"chip": hud.toast("Найдена микросхема для антенны.")
		"coil": hud.toast("Найдена медная катушка для антенны.")
		"cell": hud.toast("Найдена энергоячейка для антенны.")
	prop.visible = false
	save_progress(false)

func component_count() -> int:
	var total = 0
	for key in ["coil", "chip", "cell"]:
		if flags.get(key, false): total += 1
	return total

func _repair_lighthouse() -> void:
	if quest_stage < 6:
		hud.dialogue("Старый маяк", "Антенна подавления повреждена. Чтобы понять, как её восстановить, сначала найдите фрагмент кода в «Авроре».")
	elif quest_stage == 6 and component_count() < 3:
		hud.dialogue("Старый маяк", "Не хватает компонентов: медная катушка у пещеры, микросхема на аэродроме и энергоячейка в лесу. Собрано: %d из 3." % component_count())
	elif quest_stage == 6:
		quest_stage = 7
		spawn_enemy("boss_lighthouse", "screamer", SITES.lighthouse + Vector2(-100, -50), "boss")
		hud.dialogue("Маяк надежды", "Компоненты установлены, но сигнал привлёк Крикуна. Остановите его, иначе он позовёт орду!")
		save_progress(false)
	elif quest_stage == 7:
		hud.toast("Победите Крикуна у маяка.")
	else:
		hud.dialogue("Старый маяк", "Антенна работает. Над морем снова виден свет.")

func _repair_boat() -> void:
	if quest_stage < 9:
		hud.dialogue("Лодка на берегу", "Старая лодка нуждается в ремонте. Сначала найдите фрагмент кода и восстановите маяк.")
	elif quest_stage == 9:
		if not spend({"wood": 15, "iron": 5, "cloth": 5}):
			hud.toast("Для лодки нужно 15 дерева, 5 металлолома и 5 ткани.")
			return
		quest_stage = 10
		flags["boat"] = true
		play_sound("complete")
		hud.dialogue("Путь вперёд", "Лодка готова. Первый фрагмент найден, маяк восстановлен. Глава «Приют» пройдена! Остальные острова и финал истории пока не созданы.")
		save_progress(false)
	else:
		hud.dialogue("Путь вперёд", "Лодка готова. История Приюта завершена; другие острова архипелага пока находятся в разработке.")

func recipe_list() -> Array:
	return [
		{"id":"club", "name":"Бейсбольная бита", "description":"2 древесины", "done":flags.get("club", false)},
		{"id":"spear", "name":"Каменное копьё", "description":"2 древесины + 1 камень", "done":flags.get("spear", false)},
		{"id":"axe", "name":"Каменный топор", "description":"1 древесина + 2 камня + 1 ткань", "done":flags.get("axe", false)},
		{"id":"bandage", "name":"Бинт", "description":"2 ткани"},
		{"id":"salve", "name":"Лечебная мазь", "description":"2 травы + 1 вода; лечит 35 HP"},
	]

func craft(recipe: String) -> void:
	var costs = {"club":{"wood":2}, "spear":{"wood":2,"stone":1}, "axe":{"wood":1,"stone":2,"cloth":1}, "bandage":{"cloth":2}, "salve":{"herbs":2,"water":1}}
	if not costs.has(recipe):
		return
	if recipe in ["club", "spear", "axe"] and flags.get(recipe, false):
		hud.toast("Этот предмет уже создан.")
		return
	if recipe == "salve" and player.health >= 100:
		hud.toast("Здоровье уже полное.")
		return
	if not spend(costs[recipe]):
		hud.toast("Не хватает ресурсов для создания.")
		return
	match recipe:
		"club", "spear":
			flags[recipe] = true
			equipped_weapon = recipe
			player.cancel_attack()
		"axe": flags[recipe] = true
		"bandage": give("bandage", 1)
		"salve": player.health = minf(100.0, player.health + 35.0)
	play_sound("pickup")
	hud.toast("Предмет создан.")
	save_progress(false)

# Old saves have no equipped weapon field: prefer the spear as before, then
# fall back to the bat. Invalid or unavailable saved choices are ignored.
func weapon_id() -> String:
	if equipped_weapon in ["club", "spear"] and flags.get(equipped_weapon, false):
		return equipped_weapon
	if flags.get("spear", false): return "spear"
	if flags.get("club", false): return "club"
	return ""

func weapon_name() -> String:
	match weapon_id():
		"spear": return "каменное копьё"
		"club": return "бейсбольная бита"
		_: return "руки"

func switch_weapon() -> void:
	if not flags.get("club", false) or not flags.get("spear", false):
		hud.toast("Создайте биту и копьё, чтобы менять оружие.")
		return
	equipped_weapon = "club" if weapon_id() == "spear" else "spear"
	player.cancel_attack()
	player._update_weapon()
	hud.toast("Оружие: " + weapon_name())
	save_progress(false)

func use_item(item: String) -> void:
	if count(item) <= 0:
		hud.toast("Этот предмет закончился.")
		return
	match item:
		"food":
			if player.hunger >= 99.0:
				hud.toast("Вы не голодны."); return
			player.hunger = minf(100.0, player.hunger + 32.0)
		"water":
			if player.thirst >= 99.0:
				hud.toast("Вы не испытываете жажды."); return
			player.thirst = minf(100.0, player.thirst + 36.0)
		"bandage":
			if player.health >= 100.0:
				hud.toast("Здоровье уже полное."); return
			player.health = minf(100.0, player.health + 40.0)
		_: return
	inventory[item] = count(item) - 1
	play_sound("pickup")
	hud.toast("Использовано.")

func quest_title() -> String:
	match quest_stage:
		0, 1, 2, 3: return "Выживание на острове"
		4: return "Тени в «Авроре»"
		5: return "Ключ от прошлого"
		6, 7: return "Маяк надежды"
		8, 9: return "Путь вперёд"
		_: return "Глава «Приют» завершена"

func quest_description() -> String:
	match quest_stage:
		0, 1, 2, 3: return "Собирайте ресурсы, стройте базу (B) или исследуйте отель «Аврора»."
		4: return "Победите Раздутого у отеля."
		5:
			if flags.get("keycard", false): return "Откройте сейф в руинах «Авроры»."
			return "Найдите ключ-карту на аэродроме."
		6: return "Соберите детали антенны: %d / 3." % component_count() if component_count() < 3 else "Установите детали на маяке."
		7: return "Победите Крикуна у маяка."
		8, 9: return "Почините лодку на берегу."
		_: return "Первый фрагмент найден. Другие острова пока не созданы."

func _objective() -> Dictionary:
	match quest_stage:
		0, 1, 2, 3, 4: return {"name":"Отель «Аврора»", "position": SITES.hotel}
		5:
			if flags.get("keycard", false): return {"name":"Сейф «Авроры»", "position": SITES.safe}
			return {"name":"Ключ-карта · аэродром", "position": SITES.keycard}
		6:
			var best_key = ""
			var best_dist = INF
			for key in ["coil", "chip", "cell"]:
				if not flags.get(key, false):
					var d: float = world_to_map(player.global_position).distance_to(SITES[key])
					if d < best_dist:
						best_dist = d; best_key = key
			if best_key != "":
				var labels = {"coil":"Катушка · пещера", "chip":"Микросхема · аэродром", "cell":"Энергоячейка · лес"}
				return {"name":labels[best_key], "position":SITES[best_key]}
			return {"name":"Старый маяк", "position":SITES.lighthouse}
		7: return {"name":"Крикун · маяк", "position":SITES.lighthouse}
		8, 9, 10: return {"name":"Лодка · берег", "position":SITES.boat}
	return {"name":"Отель «Аврора»", "position":SITES.hotel}

func objective_name() -> String:
	return _objective()["name"]

func objective_position() -> Vector2:
	return _objective()["position"]

func map_markers() -> Array:
	var marks = [
		{"name":"Пещеры", "position":SITES.coil}, {"name":"Лес Шёпотов", "position":SITES.cell},
		{"name":"Аэродром", "position":SITES.keycard}, {"name":"Отель «Аврора»", "position":SITES.hotel},
		{"name":"Маяк", "position":SITES.lighthouse}, {"name":"Лодка", "position":SITES.boat},
	]
	if is_instance_valid(building):
		var base: Vector3 = building.first_foundation_position()
		if base.is_finite(): marks.append({"name":"Моя база", "position":world_to_map(base)})
	return marks

func _saved_position() -> Vector2:
	var ps = load_data.get("player", {})
	if ps is Dictionary:
		var pos = ps.get("position", [])
		if pos is Array and pos.size() == 2 and (typeof(pos[0]) in [TYPE_FLOAT, TYPE_INT]) and (typeof(pos[1]) in [TYPE_FLOAT, TYPE_INT]):
			return Vector2(clampf(float(pos[0]), 120, 3080), clampf(float(pos[1]), 110, 2080))
	return Vector2(360, 1830)

func _apply_save(data: Dictionary) -> void:
	var saved_inventory = data.get("inventory", {})
	if saved_inventory is Dictionary:
		for item in inventory.keys():
			inventory[item] = clampi(int(saved_inventory.get(item, inventory[item])), 0, 9999)
	var saved_flags = data.get("flags", {})
	if saved_flags is Dictionary:
		for key in ["club", "spear", "axe", "keycard", "chip", "coil", "cell", "teddy", "fragment", "lighthouse", "boat"]:
			flags[key] = bool(saved_flags.get(key, false))
	equipped_weapon = ""
	var saved_weapon = data.get("equipped_weapon", "")
	if saved_weapon is String and saved_weapon in ["club", "spear"] and flags.get(saved_weapon, false):
		equipped_weapon = saved_weapon
	else:
		equipped_weapon = weapon_id()
	# Old tower-defence saves keep their progress. Refund the removed towers
	# once; newly written saves no longer contain the legacy tower field.
	var saved_towers = data.get("towers", [])
	if saved_towers is Array and not data.has("buildings"):
		for built in saved_towers:
			if bool(built):
				inventory["wood"] = mini(9999, count("wood") + 10)
				inventory["stone"] = mini(9999, count("stone") + 5)
	var saved_dead = data.get("dead_ids", [])
	if saved_dead is Array:
		dead_ids = saved_dead.duplicate()
	depleted_resources.clear()
	var saved_resources = data.get("depleted_resources", [])
	if saved_resources is Array:
		for identity in saved_resources:
			if identity is String:
				depleted_resources.append(identity)
	quest_stage = clampi(int(data.get("quest_stage", 0)), 0, 10)
	# The old stage 8 asked the removed NPC for boat instructions.
	if quest_stage == 8: quest_stage = 9
	day = maxi(1, int(data.get("day", 1)))
	minute = clampf(float(data.get("minute", 480.0)), 0, 1439.99)

func save_progress(show_message: bool = false) -> bool:
	if not is_instance_valid(player):
		return false
	var data = {
		"quest_stage": quest_stage, "inventory": inventory.duplicate(), "flags": flags.duplicate(),
		"island_revision": IslandMigration.CURRENT_REVISION,
		"lake_position": [environment_3d.lake_map_position.x, environment_3d.lake_map_position.y],
		"equipped_weapon": weapon_id(), "buildings": building.serialize(),
		"dead_ids": dead_ids.duplicate(), "depleted_resources": depleted_resources.duplicate(), "day": day, "minute": minute,
		"player": {"position": [world_to_map(player.global_position).x, world_to_map(player.global_position).y], "health":player.health, "stamina":player.stamina, "hunger":player.hunger, "thirst":player.thirst},
	}
	var ok = SaveGame.save_data(data)
	if show_message and is_instance_valid(hud):
		hud.toast("Игра сохранена." if ok else "Не удалось записать сохранение.")
	return ok
