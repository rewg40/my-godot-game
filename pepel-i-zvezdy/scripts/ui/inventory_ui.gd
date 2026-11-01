class_name InventoryUI
extends CanvasLayer
## Экран инвентаря: сетка слотов, описание предмета, «использовать» и «выбросить».

const UI := preload("res://scripts/ui/ui_theme.gd")
const PICKUP_SCENE := preload("res://scenes/items/Pickup.tscn")

var player: PlayerCharacter

var _grid: GridContainer
var _detail: Label
var _cells := []
var _selected := -1


func _ready() -> void:
	layer = 10
	visible = false
	_build()
	GameState.player_spawned.connect(_on_player_spawned)
	var existing = get_tree().get_first_node_in_group("player")
	if existing != null:
		_on_player_spawned(existing)


func _build() -> void:
	var panel := UI.panel()
	add_child(panel)
	UI.anchor(panel, Control.PRESET_CENTER, Vector4(-320.0, -250.0, 320.0, 250.0))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var title := UI.label("РЮКЗАК", 26, UI.TEXT)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_button := UI.button("Закрыть", 34.0)
	close_button.custom_minimum_size = Vector2(110.0, 34.0)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(_grid)

	for i in Inventory.CAPACITY:
		var button := UI.button("·", 56.0)
		button.custom_minimum_size = Vector2(140.0, 56.0)
		button.toggle_mode = true
		button.pressed.connect(_on_slot_pressed.bind(i))
		_grid.add_child(button)
		_cells.append(button)

	_detail = UI.label("Выберите слот.", 14, UI.MUTED)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(0.0, 60.0)
	box.add_child(_detail)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	box.add_child(actions)

	var use_button := UI.button("Использовать", 40.0)
	use_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	use_button.pressed.connect(_use_selected)
	actions.add_child(use_button)

	var drop_button := UI.button("Выбросить", 40.0)
	drop_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drop_button.pressed.connect(_drop_selected)
	actions.add_child(drop_button)

	var hint := UI.label("1–5 — быстрый слот · Tab — закрыть", 12, UI.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _on_player_spawned(spawned: Node) -> void:
	player = spawned as PlayerCharacter
	if player != null:
		player.inventory.changed.connect(_refresh)
	_refresh()


func open() -> void:
	if not GameState.run_active:
		return
	visible = true
	GameState.set_ui_open(true)
	_selected = -1
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	GameState.set_ui_open(false)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("inventory"):
		close()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	if player == null or not is_instance_valid(player):
		return
	for i in _cells.size():
		var button: Button = _cells[i]
		var slot: Dictionary = player.inventory.slot_at(i)
		if slot.is_empty():
			button.text = "·"
			button.button_pressed = false
			button.disabled = true
			continue
		button.disabled = false
		var id := String(slot["id"])
		var count := int(slot["count"])
		button.text = String(ItemDB.display_name(id))
		if count > 1:
			button.text += " ×%d" % count
		button.button_pressed = (i == _selected)
	_update_detail()


func _on_slot_pressed(index: int) -> void:
	_selected = index
	_refresh()


func _update_detail() -> void:
	if _selected < 0 or player == null:
		_detail.text = "Выберите слот."
		_detail.add_theme_color_override("font_color", UI.MUTED)
		return
	var slot: Dictionary = player.inventory.slot_at(_selected)
	if slot.is_empty():
		_detail.text = "Пусто."
		_detail.add_theme_color_override("font_color", UI.MUTED)
		return
	var item := ItemDB.get_item(String(slot["id"]))
	_detail.text = "%s ×%d\n%s" % [
		String(item.get("name", "?")),
		int(slot["count"]),
		String(item.get("desc", "")),
	]
	_detail.add_theme_color_override("font_color", UI.TEXT)


func _use_selected() -> void:
	if _selected < 0 or player == null:
		return
	player.use_slot(_selected)
	_refresh()


func _drop_selected() -> void:
	if _selected < 0 or player == null:
		return
	var slot: Dictionary = player.inventory.slot_at(_selected)
	if slot.is_empty():
		return
	var world = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var waypoint := -player.global_transform.basis.z
	var pickup := PICKUP_SCENE.instantiate() as Pickup
	pickup.setup(String(slot["id"]), 1)
	world.add_child(pickup)
	pickup.global_position = player.global_position + waypoint * 1.5 + Vector3(0.0, 0.6, 0.0)
	player.inventory.remove(String(slot["id"]), 1)
	_refresh()
