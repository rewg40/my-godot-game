extends Node
## Автозагрузка «GameState»: состояние забега, часы, пауза, настройки.
##
## Здесь же живёт «глобальная шина» сигналов: интерфейс, мир и игрок не знают
## друг о друге напрямую, а подписываются на события этого узла.

signal run_started(class_id: String)
signal run_ended(cause: String)
signal player_spawned(player: Node)
signal message(text: String)
signal pause_changed(paused_flag: bool)
signal ui_open_changed(is_open: bool)
signal time_changed(time_of_day: float, day_index: int)
signal day_started(day_index: int)
signal night_fell(day_index: int)

## Полные сутки длятся 10 минут: 5 минут дня (06:00–19:00) и ночь.
const DAY_LENGTH := 600.0
const DAY_START_HOUR := 6.0
const NIGHT_START_HOUR := 19.0

var time_of_day := 0.29
var day_index := 1
var is_night := false
var run_active := false
var selected_class := "medic"
var world_seed := 0
var run_cause := ""
var run_stats := {"days": 1, "kills": 0, "looted": 0, "crafted": 0, "distance": 0.0}
var settings := {"sensitivity": 1.0, "fov": 78.0, "invert_y": false}

var ui_open := false
var is_paused := false

var _last_hour := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_hour = time_of_day * 24.0


func start_run(class_id: String, seed_value: int = 0) -> void:
	selected_class = class_id
	if seed_value == 0:
		seed_value = randi() % 1000000 + 1
	world_seed = seed_value
	time_of_day = 0.29
	day_index = 1
	is_night = false
	run_cause = ""
	run_stats = {"days": 1, "kills": 0, "looted": 0, "crafted": 0, "distance": 0.0}
	run_active = true
	ui_open = false
	_last_hour = time_of_day * 24.0
	run_started.emit(class_id)


func end_run(cause: String) -> void:
	if not run_active:
		return
	run_active = false
	run_cause = cause
	set_ui_open(false)
	run_ended.emit(cause)


## Тихий выход из забега (в меню), без экрана смерти.
func abandon_run() -> void:
	run_active = false
	ui_open = false
	if is_paused:
		set_paused(false)


func restart_run() -> void:
	start_run(selected_class)


## Продвигает игровые часы. Вызывается узлом DayNight.
func advance_time(delta: float) -> void:
	if not run_active:
		return
	time_of_day += delta / DAY_LENGTH
	if time_of_day >= 1.0:
		time_of_day -= 1.0
	var hour := time_of_day * 24.0
	var night_now := hour < DAY_START_HOUR or hour >= NIGHT_START_HOUR
	if night_now and not is_night:
		is_night = true
		night_fell.emit(day_index)
	elif not night_now and is_night:
		is_night = false
	if _last_hour > hour:
		_last_hour = hour
	if _last_hour < DAY_START_HOUR and hour >= DAY_START_HOUR:
		day_index += 1
		run_stats["days"] = day_index
		day_started.emit(day_index)
	_last_hour = hour
	time_changed.emit(time_of_day, day_index)


func clock_text() -> String:
	var hours := time_of_day * 24.0
	var h := int(hours)
	var m := int((hours - float(h)) * 60.0)
	return "%02d:%02d" % [h, m]


func set_paused(value: bool) -> void:
	if is_paused == value:
		return
	is_paused = value
	get_tree().paused = value
	pause_changed.emit(value)


func set_ui_open(value: bool) -> void:
	if ui_open == value:
		return
	ui_open = value
	ui_open_changed.emit(value)


func add_stat(key: String, amount: float) -> void:
	run_stats[key] = float(run_stats.get(key, 0.0)) + amount


func class_data() -> Dictionary:
	return ItemDB.class_data(selected_class)


func difficulty_scale() -> float:
	## Каждая ночь чуть злее: множитель здоровья и агрессии зомби.
	return 1.0 + 0.18 * float(maxi(0, day_index - 1))
