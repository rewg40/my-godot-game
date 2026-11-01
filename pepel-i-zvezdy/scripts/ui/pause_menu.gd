class_name PauseMenu
extends CanvasLayer
## Пауза: сохранение, настройки чувствительности и выход.

signal menu_requested
signal quit_requested

const UI := preload("res://scripts/ui/ui_theme.gd")

var _status: Label
var _sensitivity: HSlider
var _fov: HSlider


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	GameState.pause_changed.connect(_on_pause_changed)


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.03, 0.72)
	add_child(shade)
	UI.full_rect(shade)

	var panel := UI.panel()
	add_child(panel)
	UI.anchor(panel, Control.PRESET_CENTER, Vector4(-230.0, -270.0, 230.0, 270.0))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := UI.title("ПАУЗА", 32)
	box.add_child(title)

	var resume := UI.button("Продолжить")
	resume.pressed.connect(_resume)
	box.add_child(resume)

	var save := UI.button("Сохранить игру")
	save.pressed.connect(_save)
	box.add_child(save)

	_status = UI.label("", 13, UI.MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

	var settings_title := UI.label("НАСТРОЙКИ", 13, UI.MUTED)
	box.add_child(settings_title)

	var sensitivity_label := UI.label("Чувствительность мыши", 14, UI.TEXT)
	box.add_child(sensitivity_label)
	_sensitivity = HSlider.new()
	_sensitivity.min_value = 0.2
	_sensitivity.max_value = 3.0
	_sensitivity.step = 0.05
	_sensitivity.value = float(GameState.settings.get("sensitivity", 1.0))
	_sensitivity.value_changed.connect(_on_sensitivity_changed)
	box.add_child(_sensitivity)

	var fov_label := UI.label("Угол обзора", 14, UI.TEXT)
	box.add_child(fov_label)
	_fov = HSlider.new()
	_fov.min_value = 65.0
	_fov.max_value = 110.0
	_fov.step = 1.0
	_fov.value = float(GameState.settings.get("fov", 78.0))
	_fov.value_changed.connect(_on_fov_changed)
	box.add_child(_fov)

	var to_menu := UI.button("В главное меню")
	to_menu.pressed.connect(_to_menu)
	box.add_child(to_menu)

	var quit := UI.button("Выход")
	quit.pressed.connect(func() -> void: quit_requested.emit())
	box.add_child(quit)


func _unhandled_input(event: InputEvent) -> void:
	if not GameState.run_active:
		return
	if not event.is_action_pressed("pause"):
		return
	if GameState.ui_open:
		return
	if GameState.is_paused:
		_resume()
	else:
		_pause()
	get_viewport().set_input_as_handled()


func _pause() -> void:
	GameState.set_paused(true)
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume() -> void:
	GameState.set_paused(false)
	visible = false


func _on_pause_changed(paused_flag: bool) -> void:
	visible = paused_flag


func _save() -> void:
	var world = get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("get_save_data"):
		_status.text = "Нечего сохранять."
		return
	if SaveSystem.save_game(world.get_save_data()):
		_status.text = "Игра сохранена."
	else:
		_status.text = "Не удалось сохранить."


func _on_sensitivity_changed(value: float) -> void:
	GameState.settings["sensitivity"] = value
	SaveSystem.save_settings()


func _on_fov_changed(value: float) -> void:
	GameState.settings["fov"] = value
	SaveSystem.save_settings()
	var player = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("apply_settings"):
		player.apply_settings()


func _to_menu() -> void:
	GameState.abandon_run()
	menu_requested.emit()
