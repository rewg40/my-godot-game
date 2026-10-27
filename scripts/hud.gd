extends CanvasLayer

const UI = preload("res://scripts/ui_style.gd")
const MapView = preload("res://scripts/map_view.gd")
var world
var root: Control
var modal: Control
var hp_bar: ProgressBar
var stamina_bar: ProgressBar
var stats_text: Label
var clock_label: Label
var quest_name: Label
var quest_text: Label
var objective_direction: Label
var interact_panel: PanelContainer
var interact_label: Label
var quick_label: Label
var toast_label: Label
var toast_time: float = 0.0

func _ready() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_hud()

func _build_hud() -> void:
	var status = UI.panel()
	status.position = Vector2(22, 20)
	status.size = Vector2(274, 136)
	root.add_child(status)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	status.add_child(column)
	column.add_child(UI.label("СЛЕДОПЫТ   /   ПРИЮТ", 13, UI.GOLD, true))
	var hp_row = HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	column.add_child(hp_row)
	hp_row.add_child(UI.label("HP", 12, UI.TEXT, true))
	hp_bar = UI.bar(Color("ce6b59"))
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_row.add_child(hp_bar)
	var stamina_row = HBoxContainer.new()
	stamina_row.add_theme_constant_override("separation", 8)
	column.add_child(stamina_row)
	stamina_row.add_child(UI.label("SP", 12, UI.TEXT, true))
	stamina_bar = UI.bar(Color("d7bd79"))
	stamina_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stamina_row.add_child(stamina_bar)
	stats_text = UI.label("", 12, UI.MUTED)
	column.add_child(stats_text)
	var clock_panel = UI.panel()
	clock_panel.position = Vector2(490, 20)
	clock_panel.size = Vector2(300, 45)
	root.add_child(clock_panel)
	clock_label = UI.label("", 12, UI.GOLD, true)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_panel.add_child(clock_label)
	var quest = UI.panel()
	quest.position = Vector2(930, 20)
	quest.size = Vector2(328, 155)
	root.add_child(quest)
	var qbox = VBoxContainer.new()
	qbox.add_theme_constant_override("separation", 7)
	quest.add_child(qbox)
	qbox.add_child(UI.label("ТЕКУЩАЯ ЦЕЛЬ", 11, UI.GOLD, true))
	quest_name = UI.label("", 17, UI.TEXT, true)
	qbox.add_child(quest_name)
	quest_text = UI.label("", 13, UI.MUTED)
	quest_text.custom_minimum_size = Vector2(285, 42)
	quest_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	qbox.add_child(quest_text)
	objective_direction = UI.label("", 12, Color("d8c594"))
	qbox.add_child(objective_direction)
	interact_panel = UI.panel()
	interact_panel.position = Vector2(350, 580)
	interact_panel.size = Vector2(580, 46)
	root.add_child(interact_panel)
	interact_label = UI.label("", 14, UI.TEXT, true)
	interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_panel.add_child(interact_label)
	var bottom = UI.panel()
	bottom.position = Vector2(22, 655)
	bottom.size = Vector2(525, 43)
	root.add_child(bottom)
	quick_label = UI.label("", 12, UI.TEXT)
	bottom.add_child(quick_label)
	var controls = UI.panel()
	controls.position = Vector2(865, 655)
	controls.size = Vector2(393, 43)
	root.add_child(controls)
	controls.add_child(UI.label("[ C ] Крафт     [ Tab ] Рюкзак     [ M ] Карта", 12, UI.MUTED))
	toast_label = UI.label("", 15, UI.TEXT, true)
	toast_label.position = Vector2(320, 90)
	toast_label.size = Vector2(640, 55)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.add_theme_color_override("font_shadow_color", Color(0,0,0,0.85))
	toast_label.add_theme_constant_override("shadow_offset_x", 2)
	toast_label.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(toast_label)

func _process(delta: float) -> void:
	if not is_instance_valid(world) or not is_instance_valid(world.player):
		return
	hp_bar.value = world.player.health
	stamina_bar.value = world.player.stamina
	stats_text.text = "ГОЛОД %d%%   •   ВОДА %d%%" % [int(world.player.hunger), int(world.player.thirst)]
	clock_label.text = "ОСТРОВ ПРИЮТ    /    ДЕНЬ %02d   %s" % [world.day, world.clock_string()]
	quest_name.text = world.quest_title()
	quest_text.text = world.quest_description()
	var delta_to_goal: Vector3 = world.map_to_world(world.objective_position()) - world.player.global_position
	delta_to_goal.y = 0
	var arrow = "•"
	if delta_to_goal.length() > 1.4:
		var camera_basis: Basis = world.player.camera_pivot.global_transform.basis
		var right = delta_to_goal.dot(camera_basis.x)
		var forward = -delta_to_goal.dot(camera_basis.z)
		if absf(right) > absf(forward):
			arrow = "→" if right > 0 else "←"
		else:
			arrow = "↑" if forward > 0 else "↓"
	objective_direction.text = "%s  %s  ·  %d м" % [arrow, world.objective_name(), int(delta_to_goal.length())]
	quick_label.text = "[ 1 ] Еда %d      [ 2 ] Вода %d      [ 3 ] Бинт %d      ◈ %d / 7" % [world.count("food"), world.count("water"), world.count("bandage"), 1 if world.flags.get("fragment", false) else 0]
	var nearest = world.nearest_prop()
	interact_panel.visible = nearest != null and not is_modal_open()
	if nearest:
		interact_label.text = "[ E ]  " + world.prompt_for(nearest)
	if toast_time > 0.0:
		toast_time -= delta
		toast_label.modulate.a = minf(1.0, toast_time * 2.0)
	else:
		toast_label.text = ""

func toast(text: String, seconds: float = 3.5) -> void:
	toast_label.text = text
	toast_label.position = Vector2(320, 675 if is_modal_open() else 90)
	toast_label.modulate.a = 1.0
	toast_time = seconds
	root.move_child(toast_label, root.get_child_count() - 1)

func is_modal_open() -> bool:
	return is_instance_valid(modal)

func close_modal() -> void:
	if is_instance_valid(modal):
		modal.queue_free()
	modal = null

func _new_modal() -> Control:
	close_modal()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(modal)
	var shade = ColorRect.new()
	shade.color = Color(0.01, 0.025, 0.024, 0.75)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(shade)
	root.move_child(toast_label, root.get_child_count() - 1)
	return modal

func dialogue(speaker: String, text: String, choices: Array = []) -> void:
	var screen = _new_modal()
	var panel = UI.panel()
	panel.position = Vector2(195, 430)
	panel.size = Vector2(890, 245)
	screen.add_child(panel)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 9)
	panel.add_child(vbox)
	vbox.add_child(UI.label(speaker.to_upper(), 14, UI.GOLD, true))
	var body = UI.label(text, 16, UI.TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(820, 84)
	vbox.add_child(body)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vbox.add_child(row)
	if choices.is_empty():
		choices = [{"text": "ПОНЯТНО"}]
	var first: Button
	for choice in choices:
		var button = UI.button(String(choice.get("text", "ЗАКРЫТЬ")), Vector2(165, 43))
		row.add_child(button)
		if first == null:
			first = button
		var action: Callable = choice.get("action", Callable())
		button.pressed.connect(func():
			close_modal()
			if action.is_valid():
				action.call()
		)
	if first:
		first.grab_focus()

func _window(title: String, subtitle: String) -> VBoxContainer:
	var screen = _new_modal()
	var panel = UI.panel()
	panel.position = Vector2(250, 85)
	panel.size = Vector2(780, 550)
	screen.add_child(panel)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)
	content.add_child(UI.label(title, 24, UI.GOLD, true))
	if not subtitle.is_empty():
		var sub = UI.label(subtitle, 13, UI.MUTED)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(sub)
	return content

func show_inventory() -> void:
	var content = _window("РЮКЗАК", "Ресурсы автоматически собираются в рюкзак. Используйте еду, воду и бинты кнопками ниже или клавишами 1–3.")
	var items = world.inventory
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 38)
	grid.add_theme_constant_override("v_separation", 14)
	content.add_child(grid)
	for entry in [["wood", "Древесина"], ["stone", "Камень"], ["iron", "Металлолом"], ["cloth", "Ткань"], ["herbs", "Травы"], ["food", "Еда"], ["water", "Вода"], ["bandage", "Бинты"]]:
		grid.add_child(UI.label("%s   × %d" % [entry[1], int(items.get(entry[0], 0))], 16, UI.TEXT, true))
	content.add_child(UI.label("ОРУЖИЕ: %s    •    ИНСТРУМЕНТ: %s" % [world.weapon_name(), "каменный топор" if world.flags.get("axe", false) else "нет"], 14, UI.GOLD))
	var q = UI.label("Ключ-карта: %s     Компоненты антенны: %d / 3     Фрагмент кода: %d / 7" % ["да" if world.flags.get("keycard", false) else "нет", world.component_count(), 1 if world.flags.get("fragment", false) else 0], 13, UI.MUTED)
	content.add_child(q)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	for pair in [["СЪЕСТЬ", "food"], ["ВЫПИТЬ", "water"], ["ЛЕЧИТЬСЯ", "bandage"]]:
		var b = UI.button(pair[0], Vector2(150, 42))
		row.add_child(b)
		var item_key: String = pair[1]
		b.pressed.connect(func(): world.use_item(item_key); show_inventory())
	var close = UI.button("ЗАКРЫТЬ", Vector2(180, 42))
	content.add_child(close)
	close.pressed.connect(close_modal)

func show_crafting() -> void:
	var content = _window("КРАФТ", "Созданное оружие экипируется автоматически. Каменный топор увеличивает добычу древесины и камня.")
	var resources = UI.label("Дерево %d    Камень %d    Ткань %d    Травы %d    Вода %d" % [world.count("wood"), world.count("stone"), world.count("cloth"), world.count("herbs"), world.count("water")], 14, UI.GOLD, true)
	content.add_child(resources)
	for recipe in world.recipe_list():
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		content.add_child(row)
		var label = UI.label(recipe["name"] + "  —  " + recipe["description"], 14, UI.TEXT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button = UI.button("СОЗДАТЬ", Vector2(130, 38))
		button.disabled = bool(recipe.get("done", false))
		if button.disabled:
			button.text = "ГОТОВО"
		row.add_child(button)
		var recipe_id: String = recipe["id"]
		button.pressed.connect(func(): world.craft(recipe_id); show_crafting())
	var close = UI.button("ЗАКРЫТЬ", Vector2(160, 42))
	content.add_child(close)
	close.pressed.connect(close_modal)

func show_map() -> void:
	var screen = _new_modal()
	var panel = UI.panel()
	panel.position = Vector2(170, 48)
	panel.size = Vector2(940, 625)
	screen.add_child(panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(UI.label("ПРИЮТ  /  КАРТА ОСТРОВА", 22, UI.GOLD, true))
	box.add_child(UI.label("Красная точка — вы    •    Золотое кольцо — текущая цель", 13, UI.MUTED))
	var map = MapView.new()
	map.world = world
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(map)
	var close = UI.button("ЗАКРЫТЬ КАРТУ", Vector2(190, 40))
	box.add_child(close)
	close.pressed.connect(close_modal)

func show_pause() -> void:
	var content = _window("ПАУЗА", "Приостановлено. Сохранение также происходит автоматически после важных событий.")
	var resume = UI.button("ПРОДОЛЖИТЬ", Vector2(260, 50))
	content.add_child(resume)
	resume.pressed.connect(close_modal)
	var save = UI.button("СОХРАНИТЬ", Vector2(260, 50))
	content.add_child(save)
	save.pressed.connect(func(): world.save_progress(true))
	var menu = UI.button("СОХРАНИТЬ И ВЫЙТИ В МЕНЮ", Vector2(260, 50))
	content.add_child(menu)
	menu.pressed.connect(func():
		if world.save_progress(false):
			world.main.show_menu()
		else:
			toast("Не удалось сохранить. Выход отменён.")
	)
	content.add_child(UI.label("WASD — движение  •  Shift — бег  •  Пробел — прыжок\nЛКМ/F — удар  •  E — взаимодействие\nПКМ + мышь — камера  •  M — карта  •  C — крафт", 14, UI.MUTED))
	resume.grab_focus()
