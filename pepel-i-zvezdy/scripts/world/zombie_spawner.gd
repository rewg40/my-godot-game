class_name ZombieSpawner
extends Node3D
## Спавн зомби: днём их немного, ночью — волна. Каждый день злее.

const ZOMBIE_SCENE := preload("res://scenes/enemies/Zombie.tscn")
const SPAWN_MIN := 42.0
const SPAWN_MAX := 92.0
const DESPAWN_DISTANCE := 135.0
const MAX_ALIVE := 34

var island: Island
var player: PlayerCharacter

var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _wave_announced := 0


func setup(island_node: Island, player_node: PlayerCharacter, seed_value: int) -> void:
	island = island_node
	player = player_node
	_rng.seed = seed_value + 8123
	_timer = 1.5
	GameState.night_fell.connect(_on_night_fell)


func _on_night_fell(day_index: int) -> void:
	_wave_announced = day_index
	GameState.message.emit("Ночь опустилась на остров. Зомби идут на запах.")


func _process(delta: float) -> void:
	if not GameState.run_active or GameState.is_paused or player == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.6
	_maintain()


func _maintain() -> void:
	var alive := get_tree().get_nodes_in_group("zombies")
	for zombie in alive:
		if zombie is Node3D and (zombie as Node3D).global_position.distance_to(player.global_position) > DESPAWN_DISTANCE:
			zombie.queue_free()

	var target := _target_count()
	var attempts := 0
	while alive.size() < target and attempts < 8:
		attempts += 1
		_spawn_one()
		alive = get_tree().get_nodes_in_group("zombies")


func _target_count() -> int:
	var count := 9
	if GameState.is_night:
		count = 22
	count += int(maxi(0, GameState.day_index - 1)) * 2
	return mini(count, MAX_ALIVE)


func _spawn_one() -> void:
	if island == null:
		return
	var angle := _rng.randf() * TAU
	var radius := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
	var x := player.global_position.x + cos(angle) * radius
	var z := player.global_position.z + sin(angle) * radius
	if not island.is_inside(x, z):
		return
	if not bool(island.is_land(x, z)):
		return
	var y := float(island.height_at(x, z))
	if y < 1.0:
		return

	var zombie := ZOMBIE_SCENE.instantiate() as Zombie
	zombie.variant = "runner" if _runner_chance() > _rng.randf() else "walker"
	zombie.player = player
	add_child(zombie)
	zombie.global_position = Vector3(x, y + 0.4, z)


func _runner_chance() -> float:
	var chance := 0.22 + 0.04 * float(maxi(0, GameState.day_index - 1))
	if GameState.is_night:
		chance += 0.15
	return clampf(chance, 0.0, 0.7)
