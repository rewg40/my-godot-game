class_name Survival
extends Node
## Выживание: здоровье, голод, жажда, выносливость, заражение и тепло.
##
## Все числа — «единицы за секунду»: голод уходит медленно, заражение быстрее,
## а ночью без костра тепло падает особенно зло.

signal changed
signal died(cause: String)
signal damaged(amount: float)
signal healed(amount: float)

const MAX_HEALTH := 100.0

var max_health := MAX_HEALTH
var health := MAX_HEALTH
var hunger := 100.0
var thirst := 100.0
var stamina := 100.0
var infection := 0.0
var warmth := 100.0
var alive := true

var heal_mult := 1.0
var infection_mult := 1.0
var damage_taken_mult := 1.0

var death_cause := ""

var _last_hit := -100.0
var _last_fire_check := 0.0
var _near_fire := false


func _ready() -> void:
	set_process(true)


func apply_class(class_id: String) -> void:
	var data := ItemDB.class_data(class_id)
	heal_mult = float(data.get("heal_mult", 1.0))
	infection_mult = float(data.get("infection_mult", 1.0))
	damage_taken_mult = float(data.get("damage_taken_mult", 1.0))
	max_health = float(data.get("max_health", MAX_HEALTH))
	health = max_health
	hunger = 100.0
	thirst = 100.0
	stamina = 100.0
	infection = 0.0
	warmth = 100.0
	alive = true
	changed.emit()


func _process(delta: float) -> void:
	if not GameState.run_active or GameState.is_paused or not alive:
		return
	_tick(delta)


func _tick(delta: float) -> void:
	hunger = maxf(0.0, hunger - 0.34 * delta)
	thirst = maxf(0.0, thirst - 0.46 * delta)

	if hunger <= 0.0:
		_apply_health(-0.55 * delta)
	if thirst <= 0.0:
		_apply_health(-0.85 * delta)

	if infection >= 60.0:
		_apply_health(-(infection - 60.0) * 0.02 * delta)

	_last_fire_check -= delta
	if _last_fire_check <= 0.0:
		_last_fire_check = 0.4
		_near_fire = _check_fire()

	if _near_fire:
		warmth = minf(100.0, warmth + 6.0 * delta)
	elif GameState.is_night:
		warmth = maxf(0.0, warmth - 1.1 * delta)
	else:
		warmth = minf(100.0, warmth + 0.4 * delta)

	if warmth <= 0.0:
		_apply_health(-0.9 * delta)

	var since_hit := float(Time.get_ticks_msec()) / 1000.0 - _last_hit
	if since_hit > 8.0 and hunger > 35.0 and thirst > 35.0 and health < max_health:
		_apply_health(0.5 * delta)

	if not is_sprinting():
		stamina = minf(100.0, stamina + 11.0 * delta)

	changed.emit()


func is_sprinting() -> bool:
	var player := get_parent()
	if player == null or not player.has_method("is_sprinting"):
		return false
	return bool(player.is_sprinting())


func _check_fire() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var pos := (get_parent() as Node3D).global_position
	for fire in tree.get_nodes_in_group("campfires"):
		if fire is Node3D:
			var radius := 7.0
			if fire.has_method("heat_radius"):
				radius = float(fire.heat_radius())
			if (fire as Node3D).global_position.distance_to(pos) <= radius:
				return true
	return false


func take_damage(amount: float, cause: String = "зомби", infection_chance: float = 0.35) -> void:
	if not alive:
		return
	var dealt := amount * damage_taken_mult
	_last_hit = float(Time.get_ticks_msec()) / 1000.0
	_apply_health(-dealt)
	if infection_chance > 0.0 and _rng_roll(infection_chance):
		infection = minf(100.0, infection + dealt * 0.5 * infection_mult)
	damaged.emit(dealt)
	if not alive:
		_die(cause)
	changed.emit()


func _rng_roll(chance: float) -> bool:
	return randf() < chance


func add_infection(amount: float) -> void:
	infection = clampf(infection + amount * infection_mult, 0.0, 100.0)
	changed.emit()


func spend_stamina(amount: float) -> bool:
	if stamina < amount:
		return false
	stamina = maxf(0.0, stamina - amount)
	changed.emit()
	return true


func warm_up(amount: float) -> void:
	warmth = minf(100.0, warmth + amount)
	changed.emit()


## Применяет эффект расходника. Возвращает true, если предмет был использован.
func consume(id: String) -> bool:
	var item := ItemDB.get_item(id)
	if not item.has("use"):
		return false
	var effects: Dictionary = item["use"]
	var healing := 0.0
	if effects.has("health"):
		healing = float(effects["health"]) * (heal_mult if float(effects["health"]) > 0.0 else 1.0)
		_apply_health(healing)
	if effects.has("hunger"):
		hunger = clampf(hunger + float(effects["hunger"]), 0.0, 100.0)
	if effects.has("thirst"):
		thirst = clampf(thirst + float(effects["thirst"]), 0.0, 100.0)
	if effects.has("infection"):
		infection = clampf(infection + float(effects["infection"]) * infection_mult, 0.0, 100.0)
	if effects.has("warmth"):
		warmth = clampf(warmth + float(effects["warmth"]), 0.0, 100.0)
	changed.emit()
	return true


func _apply_health(delta_value: float) -> void:
	if delta_value > 0.0:
		var before := health
		health = minf(max_health, health + delta_value)
		if health - before > 0.01:
			healed.emit(health - before)
	else:
		health = maxf(0.0, health + delta_value)
		if health <= 0.0 and alive:
			_die("Тело не выдержало истощения")


func _die(cause: String = "") -> void:
	if not alive:
		return
	alive = false
	death_cause = cause if not cause.is_empty() else "Вы не выжили на острове"
	died.emit(death_cause)


func health_ratio() -> float:
	return clampf(health / maxf(max_health, 1.0), 0.0, 1.0)


func get_state() -> Dictionary:
	return {
		"health": health,
		"hunger": hunger,
		"thirst": thirst,
		"stamina": stamina,
		"infection": infection,
		"warmth": warmth,
		"alive": alive,
	}


func set_state(data: Dictionary) -> void:
	health = float(data.get("health", max_health))
	hunger = float(data.get("hunger", 100.0))
	thirst = float(data.get("thirst", 100.0))
	stamina = float(data.get("stamina", 100.0))
	infection = float(data.get("infection", 0.0))
	warmth = float(data.get("warmth", 100.0))
	alive = bool(data.get("alive", true))
	changed.emit()
