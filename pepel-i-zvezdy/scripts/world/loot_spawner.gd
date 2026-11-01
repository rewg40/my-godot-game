class_name LootSpawner
extends Node3D
## Раскладка лута по острову.
##
## Стартовая россыпь + медленное «довозвращение» предметов, чтобы мир не
## опустел за десять минут. Вес предметов зависит от высоты: у воды — бутылки,
## в горах — камень и трава, в лесу — дерево и тряпки.

const PICKUP_SCENE := preload("res://scenes/items/Pickup.tscn")
const INITIAL := 70
const MAX_ITEMS := 110
const RESPAWN_INTERVAL := 14.0

var island: Island
var player: PlayerCharacter

var _rng := RandomNumberGenerator.new()
var _timer := 0.0


func setup(island_node: Island, player_node: PlayerCharacter, seed_value: int) -> void:
	island = island_node
	player = player_node
	_rng.seed = seed_value + 4242
	for i in INITIAL:
		_spawn_random(6.0, 118.0)
	_timer = RESPAWN_INTERVAL


func _process(delta: float) -> void:
	if not GameState.run_active or GameState.is_paused:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = RESPAWN_INTERVAL
	if get_tree().get_nodes_in_group("pickups").size() < MAX_ITEMS:
		_spawn_random(10.0, 118.0)


func _spawn_random(min_radius: float, max_radius: float) -> void:
	if island == null or player == null:
		return
	for attempt in 14:
		var angle := _rng.randf() * TAU
		var radius := _rng.randf_range(min_radius, max_radius)
		var x := player.global_position.x + cos(angle) * radius
		var z := player.global_position.z + sin(angle) * radius
		if not island.is_inside(x, z):
			continue
		var y := float(island.height_at(x, z))
		if y < 1.2 or float(island.slope_at(x, z)) > 0.9:
			continue
		var pickup := PICKUP_SCENE.instantiate()
		pickup.setup(_pick_item(y), 1)
		add_child(pickup)
		pickup.global_position = Vector3(x, y + 0.15, z)
		return


func _pick_item(height: float) -> String:
	var table := {}
	if height < 4.0:
		table = {"water_dirty": 16, "cloth": 12, "wood": 14, "scrap": 8, "bandage": 3}
	elif height > 26.0:
		table = {"stone": 18, "herb": 14, "scrap": 10, "antibiotics": 2, "bandage": 3}
	else:
		table = {
			"wood": 18, "cloth": 14, "herb": 16, "scrap": 10, "stone": 8,
			"canned_food": 7, "water_clean": 3, "water_dirty": 6,
			"bandage": 5, "torch": 3, "pipe": 2, "campfire_kit": 3,
			"antibiotics": 2, "sword": 1,
		}
	var total := 0
	for key in table.keys():
		total += int(table[key])
	var roll := _rng.randi_range(1, maxi(total, 1))
	for key in table.keys():
		roll -= int(table[key])
		if roll <= 0:
			return String(key)
	return "cloth"
