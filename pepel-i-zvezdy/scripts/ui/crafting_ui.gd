class_name CraftingUI
extends CanvasLayer
## Крафт: список рецептов, стоимость и кнопка «сделать».
##
## Рецепты с меткой station = "fire" требуют стоять у костра — это единственный
## способ получить чистую воду и клинок.

const UI := preload("res://scripts/ui/ui_theme.gd")

var player: PlayerCharacter

var _list: VBoxContainer
var _hint: Label


func _ready() -> void:
	layer = 11
	visible = false
	_build()
	GameState.player_spawned.connect(_on_player_spawned)
	var existing = get_tree().get_first_node_in_group("player")
	if existing != null:
		_on_player_spawned(existing)


func _build() -> void:
	var panel := UI.panel()
	add_child(panel)
	UI.anchor(panel, Control.PRESET_CENTER, Vector4(-330.0, -260.0, 330.0, 260.0))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	header.add_child(UI.label("МАСТЕРСКАЯ", 26, UI.TEXT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_button := UI.button("Закрыть", 34.0)
	close_button.custom_minimum_size = Vector2(110.0, 34.0)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0.0, 330.0)
	box.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_hint = UI.label("У костра открываются новые рецепты.", 12, UI.MUTED)
	box.add_child(_hint)


func _on_player_spawned(spawned: Node) -> void:
	player = spawned as PlayerCharacter
	if player != null:
		player.inventory.changed.connect(_refresh)


func open() -> void:
	if not GameState.run_active:
		return
	visible = true
	GameState.set_ui_open(true)
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
	if event.is_action_pressed("pause") or event.is_action_pressed("craft"):
		close()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	if player == null or not is_instance_valid(player):
		return

	var fire := _near_fire()
	for recipe in ItemDB.all_recipes():
		_list.add_child(_make_row(recipe, fire))

	if fire:
		_hint.text = "Костёр рядом: доступны рецепты с огнём."
	else:
		_hint.text = "У костра открываются новые рецепты."


func _make_row(recipe: Dictionary, near_fire: bool) -> Control:
	var cost := ItemDB.recipe_cost(recipe, GameState.selected_class)
	var station := String(recipe.get("station", ""))
	var needs_fire := station == "fire"

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)

	var result_id := String(recipe["result"])
	var title := UI.label("%s ×%d" % [ItemDB.display_name(result_id), int(recipe["count"])], 16, UI.TEXT)
	info.add_child(title)

	var cost_text := _cost_text(cost)
	var color := UI.MUTED
	if needs_fire and not near_fire:
		cost_text += "  · нужен костёр"
		color = UI.EMBER
	elif not player.inventory.has_items(cost):
		color = UI.DANGER
	var cost_label := UI.label(cost_text, 13, color)
	info.add_child(cost_label)

	var craft_button := UI.button("Сделать", 34.0)
	craft_button.custom_minimum_size = Vector2(120.0, 34.0)
	craft_button.disabled = not _can_craft(recipe, cost, near_fire)
	craft_button.pressed.connect(_on_craft.bind(recipe))
	row.add_child(craft_button)
	return row


func _cost_text(cost: Dictionary) -> String:
	var text := ""
	for id in cost.keys():
		if not text.is_empty():
			text += ", "
		text += "%s ×%d" % [ItemDB.display_name(String(id)), int(cost[id])]
	return text


func _can_craft(recipe: Dictionary, cost: Dictionary, near_fire: bool) -> bool:
	if String(recipe.get("station", "")) == "fire" and not near_fire:
		return false
	return player.inventory.has_items(cost)


func _near_fire() -> bool:
	var world = get_tree().get_first_node_in_group("world")
	if world != null and world.has_method("is_near_fire"):
		return bool(world.is_near_fire(player.global_position, 6.0))
	return false


func _on_craft(recipe: Dictionary) -> void:
	if player == null:
		return
	var cost := ItemDB.recipe_cost(recipe, GameState.selected_class)
	if not _can_craft(recipe, cost, _near_fire()):
		return
	if not player.inventory.consume(cost):
		return
	player.inventory.add(String(recipe["result"]), int(recipe["count"]))
	GameState.add_stat("crafted", 1.0)
	GameState.message.emit("Изготовлено: %s" % ItemDB.display_name(String(recipe["result"])))
	_refresh()
