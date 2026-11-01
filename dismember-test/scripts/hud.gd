class_name Hud
extends CanvasLayer
## Интерфейс полигона: прицел, что под прицелом, состояние трёх зомби,
## здоровье медика и лог ударов.

const UI := preload("res://scripts/ui_theme.gd")

var player: SwordPlayer
var zombies: Array = []
var world_source := ""

var _crosshair: Label
var _hitmarker: Label
var _target_title: Label
var _target_hint: Label
var _zombie_lines: VBoxContainer
var _health_bar: ProgressBar
var _health_label: Label
var _log: Label
var _help: PanelContainer

var _hit_timer := 0.0
var _log_timer := 0.0
var _refresh := 0.0


func setup(player_node: SwordPlayer, zombie_list: Array, source_text: String) -> void:
	player = player_node
	zombies = zombie_list
	world_source = source_text


func _ready() -> void:
	layer = 10
	_build()


func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	UI.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.make_theme()
	add_child(root)

	_crosshair = UI.label("+", 30, Color(1.0, 1.0, 1.0, 0.85))
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.anchor(_crosshair, Control.PRESET_CENTER, Vector4(-20.0, -22.0, 20.0, 22.0))
	root.add_child(_crosshair)

	_hitmarker = UI.label("x", 26, UI.DANGER)
	_hitmarker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hitmarker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hitmarker.modulate = Color(1.0, 1.0, 1.0, 0.0)
	UI.anchor(_hitmarker, Control.PRESET_CENTER, Vector4(-20.0, -22.0, 20.0, 22.0))
	root.add_child(_hitmarker)

	var target_panel := UI.panel()
	UI.anchor(target_panel, Control.PRESET_CENTER_TOP, Vector4(-190.0, 26.0, 190.0, 116.0))
	root.add_child(target_panel)
	var target_box := VBoxContainer.new()
	target_box.add_theme_constant_override("separation", 4)
	target_panel.add_child(target_box)
	_target_title = UI.label("—", 20, UI.TEXT)
	_target_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_box.add_child(_target_title)
	_target_hint = UI.label("", 13, UI.MUTED)
	_target_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_box.add_child(_target_hint)

	var zombie_panel := UI.panel()
	UI.anchor(zombie_panel, Control.PRESET_TOP_RIGHT, Vector4(-330.0, 24.0, -24.0, 210.0))
	root.add_child(zombie_panel)
	_zombie_lines = VBoxContainer.new()
	_zombie_lines.add_theme_constant_override("separation", 6)
	zombie_panel.add_child(_zombie_lines)

	var player_panel := UI.panel()
	UI.anchor(player_panel, Control.PRESET_BOTTOM_LEFT, Vector4(24.0, -104.0, 404.0, -24.0))
	root.add_child(player_panel)
	var player_box := VBoxContainer.new()
	player_box.add_theme_constant_override("separation", 8)
	player_panel.add_child(player_box)
	_health_label = UI.label("Здоровье", 16, UI.TEXT)
	player_box.add_child(_health_label)
	_health_bar = UI.bar(UI.OK, 340.0, 14.0)
	player_box.add_child(_health_bar)

	_log = UI.label("", 16, UI.EMBER_LIGHT)
	_log.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.anchor(_log, Control.PRESET_CENTER_BOTTOM, Vector4(-400.0, -132.0, 400.0, -96.0))
	root.add_child(_log)

	_help = UI.panel()
	UI.anchor(_help, Control.PRESET_TOP_LEFT, Vector4(24.0, 24.0, 470.0, 232.0))
	root.add_child(_help)
	var help_box := VBoxContainer.new()
	help_box.add_theme_constant_override("separation", 4)
	_help.add_child(help_box)
	help_box.add_child(UI.label("Полигон меча", 20, UI.EMBER_LIGHT))
	help_box.add_child(UI.label("WASD — идти, Shift — бежать, Space — прыжок", 13, UI.TEXT))
	help_box.add_child(UI.label("ЛКМ / F — удар мечом", 13, UI.TEXT))
	help_box.add_child(UI.label("R — сбросить сцену, Esc — выход", 13, UI.TEXT))
	help_box.add_child(UI.label("F3 — показать зоны попадания, F1 — скрыть справку", 13, UI.TEXT))
	help_box.add_child(UI.label("Карта: %s" % world_source, 13, UI.MUTED))
	help_box.add_child(UI.label("Меч: корпус −25 HP, рука/нога −1 (всего 3)", 13, UI.MUTED))
	help_box.add_child(UI.label("Руки и ноги отрубаются за три удара", 13, UI.MUTED))


func _process(delta: float) -> void:
	if player == null:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.15
		_refresh_zombies()
	_update_target()

	_health_bar.value = clampf(player.hp / maxf(player.max_hp, 1.0) * 100.0, 0.0, 100.0)
	_health_label.text = "Здоровье: %d / %d" % [int(ceil(player.hp)), int(player.max_hp)]

	if _log_timer > 0.0:
		_log_timer = maxf(0.0, _log_timer - delta)
		_log.modulate.a = clampf(_log_timer / 1.2, 0.0, 1.0)
	if _hit_timer > 0.0:
		_hit_timer = maxf(0.0, _hit_timer - delta)
		_hitmarker.modulate.a = clampf(_hit_timer / 0.25, 0.0, 1.0)


func _update_target() -> void:
	var info := player.aim_info()
	if info.is_empty():
		_target_title.text = "—"
		_target_title.add_theme_color_override("font_color", UI.MUTED)
		_target_hint.text = "наведите прицел на зомби"
		_crosshair.modulate = Color(1.0, 1.0, 1.0, 0.85)
		return
	var title := String(info.get("title", ""))
	var hp := float(info.get("hp", 0.0))
	var max_hp := float(info.get("max", 1.0))
	_target_title.text = "%s · %d/%d" % [title, int(ceil(hp)), int(max_hp)]
	if String(info.get("kind", "")) == "limb":
		_target_title.add_theme_color_override("font_color", UI.DANGER)
		_target_hint.text = "удар мечом снимает 1 — осталось %d" % int(ceil(hp))
		_crosshair.modulate = Color(1.0, 0.55, 0.45)
	else:
		_target_title.add_theme_color_override("font_color", UI.EMBER_LIGHT)
		_target_hint.text = "корпус: меч снимает 25"
		_crosshair.modulate = Color(1.0, 0.8, 0.5)


func _refresh_zombies() -> void:
	for child in _zombie_lines.get_children():
		child.queue_free()
	_zombie_lines.add_child(UI.label("Зомби", 16, UI.EMBER_LIGHT))
	for zombie in zombies:
		if zombie == null or not is_instance_valid(zombie):
			continue
		var line := Label.new()
		line.text = "№%d  %d HP\nРуки %s · %s   Ноги %s · %s" % [
			zombie.index, int(ceil(zombie.hp)),
			zombie.limb_state("arm_l"), zombie.limb_state("arm_r"),
			zombie.limb_state("leg_l"), zombie.limb_state("leg_r"),
		]
		line.add_theme_font_size_override("font_size", 13)
		line.add_theme_color_override("font_color", UI.OK if not zombie.is_dead() else UI.MUTED)
		_zombie_lines.add_child(line)


func show_log(text: String) -> void:
	_log.text = text
	_log_timer = 3.5
	_log.modulate = Color(1.0, 1.0, 1.0, 1.0)


func flash_hit() -> void:
	_hit_timer = 0.25
	_hitmarker.modulate = Color(1.0, 1.0, 1.0, 1.0)


func toggle_help() -> void:
	_help.visible = not _help.visible
