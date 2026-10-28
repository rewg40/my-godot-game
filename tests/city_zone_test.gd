extends SceneTree

## Проверка разрушенного городского района: построен, здания в группе,
## стоят на своём рельефе и в пределах острова. Запуск:
##   godot --headless --path . --script res://tests/city_zone_test.gd

const EnvironmentScript = preload("res://scripts/environment_3d.gd")

var failures: Array[String] = []
var watchdog: Timer

func _initialize() -> void:
	# Не трогаем обычное сохранение игрока.
	OS.set_environment("SHARDS_TEST_SAVE", "1")
	watchdog = Timer.new()
	watchdog.one_shot = true
	watchdog.autostart = true
	watchdog.wait_time = 240.0
	watchdog.timeout.connect(_on_timeout)
	root.add_child(watchdog)
	_run.call_deferred()

func _on_timeout() -> void:
	push_error("City zone test timed out")
	quit(1)

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		push_error("FAIL: " + message)
		failures.append(message)

func _run() -> void:
	var env = EnvironmentScript.new()
	root.add_child(env)
	# Модели руин тяжёлые: даём сборке несколько кадров.
	for i in range(8):
		await process_frame
	var city = env.find_child("RuinedCity", true, false)
	check(city != null, "район RuinedCity создан")
	if city == null:
		quit(1)
		return
	check(city.find_child("CityPad", true, false) != null, "площадка CityPad построена")
	check(city.find_child("CityRoad", true, false) != null, "улица CityRoad построена")
	var buildings = get_nodes_in_group("city_building")
	check(buildings.size() >= 19,
			"зданий в районе >= 19 (4 руины + 5 фасадов + 10 спрайтов): получено %d" % buildings.size())
	var in_bounds := true
	var grounded := true
	for building in buildings:
		var p = building.global_position
		if p.x < 0.0 or p.x > 256.0 or p.z < 0.0 or p.z > 176.0:
			in_bounds = false
		var h = env.height_at(p.x, p.z)
		if p.y < h - 4.0:
			grounded = false
			print("  провалено: ", building.name, " y=", p.y, " рельеф=", h)
	check(in_bounds, "все здания в пределах острова")
	check(grounded, "здания стоят на рельефе, провалов нет")
	# Коллизии: у каждого 3D-здания есть StaticBody3D.
	var with_collision := 0
	for building in buildings:
		if building is StaticBody3D:
			with_collision += 1
		elif building.has_node("StaticBody3D") or building.find_children("*", "StaticBody3D", true, false).size() > 0:
			with_collision += 1
	check(with_collision >= buildings.size() - 2,
			"почти у всех зданий есть коллизия: %d из %d" % [with_collision, buildings.size()])
	if failures.is_empty():
		print("City zone test: все проверки пройдены")
		quit(0)
	else:
		print("City zone test: есть провалы — ", failures)
		quit(1)
