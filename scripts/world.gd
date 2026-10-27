extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const PropScript = preload("res://scripts/prop.gd")
const HudScript = preload("res://scripts/hud.gd")
const SaveGame = preload("res://scripts/save_game.gd")
const Environment3D = preload("res://scripts/environment_3d.gd")
const MAP_SCALE := 0.04
const CAMP = Vector2(850, 1300)
const SITES = {
	"marta": Vector2(900, 1240), "grom": Vector2(1050, 1375),
	"hotel": Vector2(2150, 1440), "safe": Vector2(2250, 1510),
	"keycard": Vector2(2570, 625), "chip": Vector2(2680, 700),
	"coil": Vector2(590, 430), "cell": Vector2(1480, 470),
	"teddy": Vector2(1390, 565), "lighthouse": Vector2(2750, 1800),
	"boat": Vector2(380, 1950),
}

var main
var load_data: Dictionary = {}
var player
var hud
var camp_position = CAMP
var props: Array = []
var enemies: Array = []
var inventory: Dictionary = {"wood": 0, "stone": 0, "iron": 0, "cloth": 1, "food": 2, "water": 2, "herbs": 0, "bandage": 1}
var flags: Dictionary = {}
var dead_ids: Array = []
var towers: Array = [false, false, false]
var tower_timers: Array = [0.0, 0.0, 0.0]
var tower_positions: Array = [Vector2(610, 1180), Vector2(1060, 1110), Vector2(1090, 1530)]
var quest_stage: int = 0
var side_stage: int = 0
var wave_kills: int = 0
var camp_health: float = 100.0
var day: int = 1
var minute: float = 480.0
var elapsed: float = 0.0
var last_raid_day: int = 0
var autosave_clock: float = 0.0
var environment_3d: Node3D
var goal_marker: Node3D
var sound: AudioStreamPlayer
var effects: Array = []

func _ready() -> void:
	name = "ShelterWorld3D"
	environment_3d = Environment3D.new()
	add_child(environment_3d)
	if not load_data.is_empty():
		_apply_save(load_data)
	_build_world()
	player = PlayerScript.new()
	player.world = self
	player.position = map_to_world(_saved_position()) + Vector3.UP * 0.12
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
		hud.dialogue("День обнуления — 200 лет спустя", "Море выбросило вас на берег Приюта. Антенны подавления гаснут, а заражённые снова приближаются к поселениям. Найдите «Очаг» и поговорите со старейшиной Мартой.")
		save_progress(false)
	else:
		hud.toast("С возвращением на остров Приют.")

# Map coordinates remain stable for the journal and old saves; world actors,
# collisions and the camera all use true 3D metres in X/Y/Z.
func map_to_world(point: Vector2) -> Vector3:
	var x = point.x * MAP_SCALE
	var z = point.y * MAP_SCALE
	return Vector3(x, environment_3d.height_at(x, z), z)

func world_to_map(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z) / MAP_SCALE

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
	_deco(Vector2(690, 1110), "res://assets/models/kenney/city-suburban/building-type-a.glb", 5.0, 34)
	_deco(Vector2(1025, 1035), "res://assets/models/kenney/city-suburban/building-type-c.glb", 4.7, 34)
	_deco(Vector2(600, 1490), "res://assets/models/kenney/city-suburban/building-type-g.glb", 4.3, 31)
	_deco(Vector2(1110, 1640), "res://assets/models/kenney/survival/structure.glb", 6.0, 28)
	_deco(Vector2(2200, 1360), "res://assets/models/kenney/city-industrial/building-a.glb", 3.5, 35)
	_deco(Vector2(2500, 500), "res://assets/models/kenney/city-industrial/building-a.glb", 3.8, 33)
	_deco(Vector2(570, 345), "res://assets/models/kenney/nature/cliff_cave_rock.glb", 5.0, 30)
	_deco(Vector2(1550, 380), "res://assets/models/kenney/survival/structure-metal.glb", 4.8, 24)
	_make("marta", "npc", "Старейшина Марта", SITES.marta, {"collision": 12})
	_make("grom", "npc", "Старик Гром", SITES.grom, {"collision": 12})
	_make("borg", "npc", "Кузнец Борг", Vector2(655, 1365), {"collision": 12})
	_make("lina", "npc", "Лина-Травница", Vector2(960, 1390), {"collision": 12})
	_make("tim", "npc", "Мальчик Тим", Vector2(720, 1290), {"collision": 10})
	_make("fire", "fire", "Костёр «Очага»", CAMP, {"collision": 14})
	_make("well", "well", "Колодец", Vector2(785, 1410), {"collision": 15})
	for i in range(3):
		_make("plot_%d" % i, "plot", "Место для башни", tower_positions[i], {"index": i, "built": towers[i]})
	_make("hotel", "hotel", "Руины отеля «Аврора»", SITES.hotel)
	_make("safe", "safe", "Сейф в руинах «Авроры»", SITES.safe, {"collision": 15})
	_make("keycard", "keycard", "Ключ-карта на аэродроме", SITES.keycard)
	_make("chip", "chip", "Микросхема на аэродроме", SITES.chip, {"collision": 14})
	_make("coil", "coil", "Медная катушка у пещеры", SITES.coil, {"collision": 14})
	_make("cell", "cell", "Энергоячейка в лесу", SITES.cell, {"collision": 14})
	_make("teddy", "teddy", "Потерянный медвежонок", SITES.teddy)
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
	# Extra scenery is non-interactive, leaving clear routes to objectives.
	for p in [Vector2(220,840),Vector2(280,750),Vector2(190,1000),Vector2(1710,290),Vector2(1850,500),Vector2(1900,650),Vector2(2000,800),Vector2(2050,1000),Vector2(3020,1020),Vector2(2920,1150),Vector2(1700,1920),Vector2(1450,1850),Vector2(730,1960)]:
		_deco(p, "res://assets/models/kenney/nature/tree_pineTallA.glb", 4.0, 12)
	# Groves add silhouettes without obstructing the marked routes.
	for p in [Vector2(240,390), Vector2(900,180), Vector2(1150,250), Vector2(1750,190), Vector2(1950,350), Vector2(1850,850), Vector2(1850,1850), Vector2(1550,2050), Vector2(1100,2000), Vector2(2880,1300), Vector2(3000,520), Vector2(280,2010)]:
		_deco(p, "res://assets/models/kenney/nature/tree_oak.glb", 5.0, 16)

func _make(identity: String, kind: String, title: String, pos: Vector2, detail: Dictionary = {}):
	var prop = PropScript.new()
	prop.configure(self, identity, kind, title, detail)
	prop.position = map_to_world(pos)
	add_child(prop)
	if kind in ["keycard", "chip", "coil", "cell", "teddy"] and flags.get(kind, false):
		prop.visible = false
	props.append(prop)
	return prop

func _deco(pos: Vector2, model_path: String, size: float, radius: float) -> void:
	_make("", "deco", "", pos, {"model": model_path, "model_scale": size, "collision": radius})

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
	if is_night() and quest_stage >= 3 and last_raid_day != day:
		last_raid_day = day
		_start_night_raid()
	_update_towers(delta)
	for i in range(effects.size() - 1, -1, -1):
		effects[i]["time"] -= delta
		if effects[i]["time"] <= 0:
			if is_instance_valid(effects[i]["node"]):
				effects[i]["node"].queue_free()
			effects.remove_at(i)
	if is_instance_valid(goal_marker):
		goal_marker.position = map_to_world(objective_position()) + Vector3.UP * (3.0 + 0.18 * sin(elapsed * 3.0))
		goal_marker.rotation.y += delta * 0.8
	if autosave_clock >= 45.0:
		autosave_clock = 0.0
		save_progress(false)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode
	if key == 0:
		key = event.keycode
	if key == KEY_ESCAPE:
		if hud.is_modal_open():
			hud.close_modal()
		else:
			hud.show_pause()
		get_viewport().set_input_as_handled()
		return
	if hud.is_modal_open():
		return
	match key:
		KEY_E:
			var prop = nearest_prop()
			if prop:
				interact(prop)
		KEY_C: hud.show_crafting()
		KEY_TAB: hud.show_inventory()
		KEY_M: hud.show_map()
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
	if not is_instance_valid(sound):
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
	var distance = 95.0
	for prop in props:
		if not is_instance_valid(prop) or prop.kind == "deco" or not prop.usable:
			continue
		if prop.kind in ["keycard", "chip", "coil", "cell", "teddy"] and flags.get(prop.kind, false):
			continue
		var d: float = world_to_map(player.global_position).distance_to(world_to_map(prop.global_position))
		if d < distance:
			distance = d
			nearest = prop
	return nearest

func prompt_for(prop) -> String:
	if prop.kind == "plot" and not towers[int(prop.detail.get("index", 0))]:
		return "Построить башню  ·  10 дерева + 5 камня"
	if prop.kind == "boat" and quest_stage == 9:
		return "Починить лодку  ·  15 дерева + 5 металла + 5 ткани"
	return prop.title

func interact(prop) -> void:
	match prop.kind:
		"npc": _talk_to(prop.prop_id)
		"tree", "rock", "scrap", "crate", "bush", "well": _harvest(prop)
		"plot": _build_tower(prop)
		"fire": hud.dialogue("Очаг", "Костёр — сердце поселения. Враг будет пытаться добраться до него во время набега. Построенные башни обстреливают заражённых рядом с поселением.")
		"hotel": _enter_hotel()
		"safe": _open_safe()
		"keycard", "chip", "coil", "cell", "teddy": _collect_quest_item(prop)
		"lighthouse": _repair_lighthouse()
		"boat": _repair_boat()

func _harvest(prop) -> void:
	var amount = 0
	var message = ""
	match prop.kind:
		"tree":
			amount = 8 if flags.get("axe", false) else 6
			give("wood", amount); message = "+%d древесины" % amount
		"rock":
			amount = 6 if flags.get("axe", false) else 4
			give("stone", amount); message = "+%d камня" % amount
		"scrap": give("iron", 3); message = "+3 металлолома"
		"crate": give("cloth", 2); message = "+2 ткани"
		"bush": give("food", 2); give("herbs", 1); message = "+2 еды и +1 трава"
		"well": give("water", 3); message = "+3 воды"
	prop.deplete(35.0 if prop.kind != "well" else 15.0)
	play_sound("pickup")
	hud.toast(message)

func _build_tower(prop) -> void:
	var index: int = int(prop.detail.get("index", 0))
	if towers[index]:
		hud.dialogue("Оборонительная башня", "Башня автоматически атакует заражённых, которые приблизятся к «Очагу».")
		return
	if quest_stage == 0:
		hud.toast("Сначала поговорите с Мартой в поселении.")
		return
	if not spend({"wood": 10, "stone": 5}):
		hud.toast("Не хватает ресурсов: нужно 10 дерева и 5 камня.")
		return
	towers[index] = true
	prop.detail["built"] = true
	prop.set_built()
	play_sound("complete")
	hud.toast("Башня построена: %d / 3" % tower_count())
	save_progress(false)

func tower_count() -> int:
	var total = 0
	for built in towers:
		if built:
			total += 1
	return total

func _talk_to(who: String) -> void:
	match who:
		"marta": _talk_marta()
		"grom":
			if quest_stage == 8:
				quest_stage = 9
				hud.dialogue("Старик Гром", "ПРОМЕТЕЙ ещё жив. Семь фрагментов откроют путь к его ядру. Первый у нас. Почини лодку на берегу: нужны 15 дерева, 5 металлолома и 5 ткани.")
				save_progress(false)
			else:
				hud.dialogue("Старик Гром", "До Обнуления ПРОМЕТЕЙ управлял медицинскими нанороботами. Потом он решил, что человечество надо спасать от самого себя. На других островах спрятаны оставшиеся части кода.")
		"borg": hud.dialogue("Кузнец Борг", "В рюкзаке открой крафт клавишей C. Из дерева получится дубина, а дерево и камень станут копьём. Каменный топор помогает добывать больше ресурсов.")
		"lina":
			hud.dialogue("Лина-Травница", "Ягоды утоляют голод, колодец даёт воду. Из ткани сделай бинты; две травы и вода станут лечебной мазью. Следи за собой — в лесу помощь далеко.")
		"tim": _talk_tim()

func _talk_marta() -> void:
	if quest_stage == 0:
		quest_stage = 1
		give("cloth", 1)
		hud.dialogue("Старейшина Марта", "Ты жив! Добро пожаловать в Очаг. Мы видели заражённых у леса. Собери древесину и камень, затем построй три башни на отмеченных площадках. Держи немного ткани — пригодится для бинта.")
		save_progress(false)
	elif quest_stage == 1 and tower_count() < 3:
		hud.dialogue("Старейшина Марта", "Для защиты нужны три башни. На каждой отмеченной площадке нажми E. Одна башня стоит 10 древесины и 5 камня. Деревья и камни со временем восстанавливаются.")
	elif quest_stage == 1:
		hud.dialogue("Старейшина Марта", "Башни готовы. Заражённые уже идут к костру. Начнём оборону?", [
			{"text": "НАЧАТЬ ОБОРОНУ", "action": Callable(self, "start_wave")}, {"text": "ПОЗЖЕ"}
		])
	elif quest_stage == 2:
		hud.dialogue("Старейшина Марта", "Защити костёр! Башни помогут, но их стрелам нужно время.")
	elif quest_stage < 8:
		hud.dialogue("Старейшина Марта", "Держи путь к своей цели. Все отмеченные места видны на карте — нажми M. А если понадобится оружие, загляни к Боргу.")
	elif quest_stage == 8:
		hud.dialogue("Старейшина Марта", "Маяк снова светит. Гром знает, что делать с фрагментом. Поговори с ним у восточного края поселения.")
	else:
		hud.dialogue("Старейшина Марта", "Теперь у нас есть надежда. Следующий путь начинается у старой лодки на берегу.")

func _talk_tim() -> void:
	if side_stage == 3:
		hud.dialogue("Тим", "Спасибо, что нашёл медвежонка. Теперь он снова охраняет мой сон!")
	elif flags.get("teddy", false):
		side_stage = 3
		give("food", 3); give("bandage", 1)
		play_sound("complete")
		hud.dialogue("Тим", "Мишка! Я думал, что потерял его навсегда. Спасибо! Я сохранил для тебя немного еды и бинт.")
		save_progress(false)
	else:
		side_stage = 1
		hud.dialogue("Тим", "Я потерял своего медвежонка в Лесу Шёпотов, недалеко от старых руин. Если найдёшь его, пожалуйста, принеси мне.")
		save_progress(false)

func start_wave() -> void:
	quest_stage = 2
	wave_kills = 0
	camp_health = 100.0
	for i in range(5):
		var angle = TAU * float(i) / 5.0
		var pos = CAMP + Vector2(cos(angle), sin(angle)) * 510.0
		spawn_enemy("wave_%d" % i, "walker", pos, "wave")
	hud.toast("Набег начался! Защитите костёр: 0 / 5", 5.0)
	save_progress(false)

func _start_night_raid() -> void:
	for i in range(3):
		var angle = TAU * float(i) / 3.0 + float(day) * 0.4
		spawn_enemy("raid_%d_%d" % [day, i], "runner" if i == 0 else "walker", CAMP + Vector2(cos(angle), sin(angle)) * 570.0, "raid")
	hud.toast("Ночь. Заражённые идут к Очагу!", 5.0)

func _update_towers(delta: float) -> void:
	for i in range(3):
		if not towers[i]:
			continue
		tower_timers[i] = maxf(0.0, float(tower_timers[i]) - delta)
		if tower_timers[i] > 0.0:
			continue
		var target = null
		var best_distance = 300.0
		for enemy in enemies:
			if not is_instance_valid(enemy) or enemy.is_dead:
				continue
			var distance: float = tower_positions[i].distance_to(world_to_map(enemy.global_position))
			if distance < best_distance:
				best_distance = distance
				target = enemy
		if target:
			tower_timers[i] = 1.25
			var from = map_to_world(tower_positions[i]) + Vector3.UP * 3.2
			var to: Vector3 = target.global_position + Vector3.UP * 1.0
			_spawn_tracer(from, to)
			target.take_damage(13.0, from)

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var difference = to - from
	if difference.length() < 0.01:
		return
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("f4cf87")
	material.emission_enabled = true
	material.emission = Color("f4cf87")
	var beam = CylinderMesh.new()
	beam.top_radius = 0.035
	beam.bottom_radius = 0.035
	beam.height = difference.length()
	beam.radial_segments = 6
	beam.material = material
	var instance = MeshInstance3D.new()
	instance.mesh = beam
	var up = difference.normalized()
	var reference = Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var right = up.cross(reference).normalized()
	instance.basis = Basis(right, up, right.cross(up).normalized())
	instance.position = (from + to) * 0.5
	add_child(instance)
	effects.append({"node": instance, "time": 0.25})

func player_attack(direction: Vector3) -> void:
	var damage = 28.0 if flags.get("spear", false) else (20.0 if flags.get("club", false) else 12.0)
	var hit = false
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.is_dead:
			continue
		var offset: Vector3 = enemy.global_position - player.global_position
		offset.y = 0
		if offset.length() <= 3.4 and (offset.length() < 0.48 or offset.normalized().dot(direction) > -0.05):
			enemy.take_damage(damage, player.global_position)
			hit = true
	if hit:
		play_sound("hit")

func enemy_defeated(enemy) -> void:
	if enemy.group_name == "wild" and enemy.enemy_id not in dead_ids:
		dead_ids.append(enemy.enemy_id)
		give("cloth", 1)
	if enemy.group_name == "wave" and quest_stage == 2:
		wave_kills += 1
		if wave_kills >= 5:
			quest_stage = 3
			give("food", 3)
			play_sound("complete")
			hud.toast("Набег отражён! Исследуйте отель «Аврора».", 5.0)
			save_progress(false)
		else:
			hud.toast("Набег: %d / 5. Костёр: %d%%" % [wave_kills, int(camp_health)])
	elif enemy.enemy_id == "boss_hotel" and quest_stage == 4:
		quest_stage = 5
		give("bandage", 2)
		play_sound("complete")
		hud.toast("Раздутый повержен. Найдите ключ-карту на аэродроме.", 5.0)
		save_progress(false)
	elif enemy.enemy_id == "boss_lighthouse" and quest_stage == 7:
		quest_stage = 8
		flags["lighthouse"] = true
		play_sound("complete")
		hud.dialogue("Маяк надежды", "Крикун повержен, антенна снова работает. Свет маяка разгоняет туман над Приютом. Вернитесь в Очаг и поговорите с Громом.")
		save_progress(false)

func damage_camp(amount: float) -> void:
	camp_health = maxf(0.0, camp_health - amount)
	if camp_health > 0.0:
		return
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.group_name in ["wave", "raid"]:
			enemy.is_dead = true
			enemy.queue_free()
	camp_health = 100.0
	if quest_stage == 2:
		quest_stage = 1
		wave_kills = 0
		hud.toast("Очаг повреждён. Подготовьтесь и снова поговорите с Мартой.", 6.0)
	else:
		hud.toast("Поселение отбилось, но костёр пришлось восстановить.", 5.0)
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
	player.health = 65.0
	player.stamina = 100.0
	player.hunger = maxf(player.hunger, 25.0)
	player.thirst = maxf(player.thirst, 25.0)
	player.global_position = map_to_world(CAMP + Vector2(-40, 100)) + Vector3.UP * 0.12
	player.velocity = Vector3.ZERO
	player.invulnerable = 3.0
	hud.toast("Вы потеряли сознание и очнулись у костра Очага.", 5.0)
	save_progress(false)

func _enter_hotel() -> void:
	if quest_stage < 3:
		hud.dialogue("Отель «Аврора»", "Заросшие руины бывшего отеля. Сначала помогите жителям укрепить Очаг.")
	elif quest_stage == 3:
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
		"teddy": hud.toast("Найден медвежонок Тима. Верните его в Очаг.")
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
		hud.dialogue("Лодка на берегу", "Старая лодка нуждается в ремонте. Сначала помогите Очагу и поговорите с Громом.")
	elif quest_stage == 9:
		if not spend({"wood": 15, "iron": 5, "cloth": 5}):
			hud.toast("Для лодки нужно 15 дерева, 5 металлолома и 5 ткани.")
			return
		quest_stage = 10
		flags["boat"] = true
		play_sound("complete")
		hud.dialogue("Путь вперёд", "Лодка готова. Первый фрагмент найден, маяк восстановлен, а Очаг защищён. Глава «Приют» пройдена! Остальные острова и финал истории пока не созданы.")
		save_progress(false)
	else:
		hud.dialogue("Путь вперёд", "Лодка готова. История Приюта завершена; другие острова архипелага пока находятся в разработке.")

func recipe_list() -> Array:
	return [
		{"id":"club", "name":"Деревянная дубина", "description":"2 древесины", "done":flags.get("club", false)},
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
		"club", "spear", "axe": flags[recipe] = true
		"bandage": give("bandage", 1)
		"salve": player.health = minf(100.0, player.health + 35.0)
	play_sound("pickup")
	hud.toast("Предмет создан.")
	save_progress(false)

func weapon_name() -> String:
	if flags.get("spear", false): return "каменное копьё"
	if flags.get("club", false): return "деревянная дубина"
	return "руки"

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
		0: return "Пробуждение"
		1, 2: return "Стены держат"
		3, 4: return "Тени в «Авроре»"
		5: return "Ключ от прошлого"
		6, 7: return "Маяк надежды"
		8, 9: return "Путь вперёд"
		_: return "Глава «Приют» завершена"

func quest_description() -> String:
	match quest_stage:
		0: return "Найдите поселение Очаг и поговорите с Мартой."
		1:
			if tower_count() == 3: return "Башни готовы. Поговорите с Мартой."
			return "Постройте башни вокруг Очага: %d / 3." % tower_count()
		2: return "Отразите набег: %d / 5. Костёр: %d%%." % [wave_kills, int(camp_health)]
		3: return "Исследуйте руины отеля «Аврора»."
		4: return "Победите Раздутого у отеля."
		5:
			if flags.get("keycard", false): return "Откройте сейф в руинах «Авроры»."
			return "Найдите ключ-карту на аэродроме."
		6: return "Соберите детали антенны: %d / 3." % component_count() if component_count() < 3 else "Установите детали на маяке."
		7: return "Победите Крикуна у маяка."
		8: return "Поговорите со стариком Громом в Очаге."
		9: return "Почините лодку на берегу."
		_: return "Первый фрагмент найден. Другие острова пока не созданы."

func _objective() -> Dictionary:
	match quest_stage:
		0: return {"name":"Марта · Очаг", "position": SITES.marta}
		1:
			var chosen = -1
			var best = INF
			for i in range(3):
				if not towers[i]:
					var d: float = world_to_map(player.global_position).distance_to(tower_positions[i])
					if d < best:
						best = d; chosen = i
			if chosen >= 0: return {"name":"Площадка башни", "position":tower_positions[chosen]}
			return {"name":"Марта · Очаг", "position":SITES.marta}
		2: return {"name":"Защита Очага", "position":CAMP}
		3, 4: return {"name":"Отель «Аврора»", "position":SITES.hotel}
		5:
			if flags.get("keycard", false): return {"name":"Сейф «Авроры»", "position":SITES.safe}
			return {"name":"Ключ-карта · аэродром", "position":SITES.keycard}
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
		8: return {"name":"Гром · Очаг", "position":SITES.grom}
		9, 10: return {"name":"Лодка · берег", "position":SITES.boat}
	return {"name":"Очаг", "position":CAMP}

func objective_name() -> String:
	return _objective()["name"]

func objective_position() -> Vector2:
	return _objective()["position"]

func map_markers() -> Array:
	return [
		{"name":"Очаг", "position":CAMP}, {"name":"Пещеры", "position":SITES.coil},
		{"name":"Лес Шёпотов", "position":SITES.cell}, {"name":"Аэродром", "position":SITES.keycard},
		{"name":"Отель «Аврора»", "position":SITES.hotel}, {"name":"Маяк", "position":SITES.lighthouse},
		{"name":"Лодка", "position":SITES.boat},
	]

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
	var saved_towers = data.get("towers", [])
	if saved_towers is Array and saved_towers.size() == 3:
		for i in range(3): towers[i] = bool(saved_towers[i])
	var saved_dead = data.get("dead_ids", [])
	if saved_dead is Array:
		dead_ids = saved_dead.duplicate()
	quest_stage = clampi(int(data.get("quest_stage", 0)), 0, 10)
	# The scripted raid is restarted safely after a reload, never left half-resolved.
	if quest_stage == 2: quest_stage = 1
	side_stage = clampi(int(data.get("side_stage", 0)), 0, 3)
	day = maxi(1, int(data.get("day", 1)))
	minute = clampf(float(data.get("minute", 480.0)), 0, 1439.99)
	last_raid_day = maxi(0, int(data.get("last_raid_day", 0)))
	camp_health = 100.0

func save_progress(show_message: bool = false) -> bool:
	if not is_instance_valid(player):
		return false
	var data = {
		"quest_stage": 1 if quest_stage == 2 else quest_stage,
		"side_stage": side_stage, "inventory": inventory.duplicate(), "flags": flags.duplicate(),
		"towers": towers.duplicate(), "dead_ids": dead_ids.duplicate(), "day": day,
		"minute": minute, "last_raid_day": last_raid_day,
		"player": {"position": [world_to_map(player.global_position).x, world_to_map(player.global_position).y], "health":player.health, "stamina":player.stamina, "hunger":player.hunger, "thirst":player.thirst},
	}
	var ok = SaveGame.save_data(data)
	if show_message and is_instance_valid(hud):
		hud.toast("Игра сохранена." if ok else "Не удалось записать сохранение.")
	return ok
