class_name GameHUD
extends CanvasLayer
## Интерфейс забега: показатели выживания, часы, хотбар, подсказки и смерть.
##
## HUD ничего не хранит сам — он читает состояние игрока и GameState, поэтому
## его можно свободно пересоздавать.

signal restart_requested
signal menu_requested

const UI := preload("res://scripts/ui/ui_theme.gd")

const VITALS := [
	{"key": "health", "name": "Здоровье", "color": Color(0.78, 0.34, 0.3)},
	{"key": "hunger", "name": "Сытость", "color": Color(0.82, 0.6, 0.3)},
	{"key": "thirst", "name": "Жажда", "color": Color(0.45, 0.7, 0.88)},
	{"key": "stamina", "name": "Силы", "color": Color(0.82, 0.8, 0.4)},
	{"key": "infection", "name": "Заражение", "color": Color(0.55, 0.45, 0.72)},
	{"key": "warmth", "name": "Тепло", "color": Color(0.9, 0.55, 0.35)},
]

var player: PlayerCharacter

var _root: Control
var _bars := {}
var _bar_values := {}
var _clock_label: Label
var _day_label: Label
var _status_label: Label
var _prompt: Label
var _hotbar_cells := []
var _toast_box: VBoxContainer
var _toasts := []
var _vignette: ColorRect
var _death_layer: Control
var _death_cause: Label
var _death_stats: Label


func _ready() -> void:
	layer = 5
	_build()
	GameState.player_spawned.connect(_on_player_spawned)
	GameState.message.connect(_on_message)
	GameState.run_ended.connect(_on_run_ended)
	var existing = get_tree().get_first_node_in_group("player")
	if existing != null:
		_on_player_spawned(existing)


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UI.make_theme()
	add_child(_root)
	UI.full_rect(_root)

	_build_vitals()
	_build_clock()
	_build_hotbar()
	_build_crosshair()
	_build_prompt()
	_build_toasts()
	_build_vignette()
	_build_death()


func _build_vitals() -> void:
	var panel := UI.panel()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)
	UI.anchor(panel, Control.PRESET_BOTTOM_LEFT, Vector4(24.0, -252.0, 318.0, -24.0))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	for entry in VITALS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)

		var name_label := UI.label(String(entry["name"]), 13, UI.MUTED)
		name_label.custom_minimum_size = Vector2(84.0, 0.0)
		row.add_child(name_label)

		var bar := UI.bar(entry["color"], 150.0, 9.0)
		row.add_child(bar)

		var value_label := UI.label("100", 13, UI.TEXT)
		value_label.custom_minimum_size = Vector2(42.0, 0.0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)

		_bars[String(entry["key"])] = bar
		_bar_values[String(entry["key"])] = value_label


func _build_clock() -> void:
	var panel := UI.panel()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)
	UI.anchor(panel, Control.PRESET_TOP_RIGHT, Vector4(-230.0, 24.0, -24.0, 132.0))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	_clock_label = UI.label("06:00", 34, UI.TEXT)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_clock_label)

	_day_label = UI.label("День 1", 14, UI.MUTED)
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_day_label)

	_status_label = UI.label("ДЕНЬ", 14, UI.EMBER)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_status_label)


func _build_hotbar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar)
	UI.anchor(bar, Control.PRESET_CENTER_BOTTOM, Vector4(-280.0, -96.0, 280.0, -24.0))
	bar.alignment = BoxContainer.ALIGNMENT_CENTER

	for i in 5:
		var cell := UI.panel(UI.PANEL_LIGHT)
		cell.custom_minimum_size = Vector2(104.0, 64.0)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(cell)

		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		cell.add_child(box)

		var key_label := UI.label("[%d]" % (i + 1), 11, UI.MUTED)
		box.add_child(key_label)

		var item_label := UI.label("—", 13, UI.TEXT)
		item_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item_label.custom_minimum_size = Vector2(88.0, 0.0)
		box.add_child(item_label)

		_hotbar_cells.append({"cell": cell, "item": item_label})


func _build_crosshair() -> void:
	var dot := ColorRect.new()
	dot.color = Color(1.0, 1.0, 1.0, 0.75)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dot)
	UI.anchor(dot, Control.PRESET_CENTER, Vector4(-2.0, -2.0, 2.0, 2.0))


func _build_prompt() -> void:
	_prompt = UI.label("", 16, UI.EMBER_LIGHT)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.visible = false
	_root.add_child(_prompt)
	UI.anchor(_prompt, Control.PRESET_CENTER_BOTTOM, Vector4(-320.0, -140.0, 320.0, -108.0))


func _build_toasts() -> void:
	_toast_box = VBoxContainer.new()
	_toast_box.add_theme_constant_override("separation", 6)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast_box)
	UI.anchor(_toast_box, Control.PRESET_CENTER_TOP, Vector4(-300.0, 24.0, 300.0, 240.0))


func _build_vignette() -> void:
	_vignette = ColorRect.new()
	_vignette.color = Color(0.6, 0.06, 0.05, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_vignette)
	UI.full_rect(_vignette)


func _build_death() -> void:
	_death_layer = Control.new()
	_death_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_death_layer.visible = false
	_root.add_child(_death_layer)
	UI.full_rect(_death_layer)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.03, 0.78)
	_death_layer.add_child(shade)
	UI.full_rect(shade)

	var panel := UI.panel()
	_death_layer.add_child(panel)
	UI.anchor(panel, Control.PRESET_CENTER, Vector4(-280.0, -200.0, 280.0, 200.0))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)

	var title := UI.title("ВЫ ПОГИБЛИ", 40)
	title.add_theme_color_override("font_color", UI.DANGER)
	box.add_child(title)

	_death_cause = UI.label("", 16, UI.MUTED)
	_death_cause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_death_cause)

	_death_stats = UI.label("", 15, UI.TEXT)
	_death_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_death_stats)

	var restart := UI.button("Начать заново")
	restart.pressed.connect(func() -> void: restart_requested.emit())
	box.add_child(restart)

	var to_menu := UI.button("В главное меню")
	to_menu.pressed.connect(func() -> void: menu_requested.emit())
	box.add_child(to_menu)


# --- Обновление -------------------------------------------------------------

func _process(delta: float) -> void:
	if player != null and is_instance_valid(player):
		_update_vitals()
		_update_prompt()
		_update_hotbar()
	_update_clock()
	_update_toasts(delta)


func _update_vitals() -> void:
	var survival := player.survival
	_set_bar("health", survival.health / maxf(survival.max_health, 1.0) * 100.0, survival.health)
	_set_bar("hunger", survival.hunger, survival.hunger)
	_set_bar("thirst", survival.thirst, survival.thirst)
	_set_bar("stamina", survival.stamina, survival.stamina)
	_set_bar("infection", survival.infection, survival.infection)
	_set_bar("warmth", survival.warmth, survival.warmth)


func _set_bar(key: String, ratio: float, value: float) -> void:
	if not _bars.has(key):
		return
	var bar: ProgressBar = _bars[key]
	bar.value = clampf(ratio, 0.0, 100.0)
	var value_label: Label = _bar_values[key]
	value_label.text = "%d" % int(round(value))


func _update_prompt() -> void:
	var target = player.get_interaction_target()
	if target == null:
		_prompt.visible = false
		return
	_prompt.text = String(target.get_interaction_text())
	_prompt.visible = true


func _update_hotbar() -> void:
	for i in _hotbar_cells.size():
		var slot: Dictionary = player.inventory.slot_at(i)
		var label: Label = _hotbar_cells[i]["item"]
		if slot.is_empty():
			label.text = "—"
			label.add_theme_color_override("font_color", UI.MUTED)
			continue
		var id := String(slot["id"])
		var count := int(slot["count"])
		label.text = String(ItemDB.display_name(id))
		if count > 1:
			label.text += " ×%d" % count
		var color := UI.TEXT
		if id == player.weapon_id:
			color = UI.EMBER_LIGHT
		label.add_theme_color_override("font_color", color)


func _update_clock() -> void:
	_clock_label.text = GameState.clock_text()
	_day_label.text = "День %d · %s" % [GameState.day_index, ItemDB.class_data(GameState.selected_class)["name"]]
	if GameState.is_night:
		_status_label.text = "НОЧЬ"
		_status_label.add_theme_color_override("font_color", UI.STAR)
	else:
		_status_label.text = "ДЕНЬ"
		_status_label.add_theme_color_override("font_color", UI.EMBER)


# --- События ----------------------------------------------------------------

func _on_player_spawned(spawned: Node) -> void:
	player = spawned as PlayerCharacter
	if player == null:
		return
	player.survival.damaged.connect(_on_damaged)


func _on_damaged(amount: float) -> void:
	var strength := clampf(amount / 25.0, 0.15, 0.75)
	_vignette.color.a = strength
	var tween := create_tween()
	tween.tween_property(_vignette, "color:a", 0.0, 0.6)


func _on_message(text: String) -> void:
	var panel := UI.panel(Color(0.06, 0.07, 0.09, 0.9))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var label := UI.label(text, 15, UI.TEXT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420.0, 0.0)
	panel.add_child(label)
	_toast_box.add_child(panel)
	_toasts.append({"node": panel, "time": 4.5})
	while _toasts.size() > 5:
		var oldest: Dictionary = _toasts.pop_front()
		if is_instance_valid(oldest["node"]):
			oldest["node"].queue_free()


func _update_toasts(delta: float) -> void:
	for i in range(_toasts.size() - 1, -1, -1):
		var entry: Dictionary = _toasts[i]
		entry["time"] = float(entry["time"]) - delta
		var node: Control = entry["node"]
		if not is_instance_valid(node):
			_toasts.remove_at(i)
			continue
		if float(entry["time"]) <= 0.0:
			node.queue_free()
			_toasts.remove_at(i)
		elif float(entry["time"]) < 1.0:
			node.modulate.a = clampf(float(entry["time"]), 0.0, 1.0)


func _on_run_ended(cause: String) -> void:
	if _death_layer == null:
		return
	_death_layer.visible = true
	_death_cause.text = cause
	var stats: Dictionary = GameState.run_stats
	_death_stats.text = "Дней: %d · Убито зомби: %d · Найдено предметов: %d · Пройдено: %d м" % [
		int(stats.get("days", 1)),
		int(stats.get("kills", 0)),
		int(stats.get("looted", 0)),
		int(stats.get("distance", 0.0)),
	]
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
