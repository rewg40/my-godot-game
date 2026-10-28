extends CanvasLayer

const UI = preload("res://scripts/ui_style.gd")
const MapView = preload("res://scripts/map_view.gd")
const BuildingSystem = preload("res://scripts/build_system.gd")
const ITEM_ORDER := ["wood", "stone", "iron", "cloth", "food", "water", "herbs", "bandage", "club", "spear", "axe", "keycard", "chip", "coil", "cell", "fragment"]
const ITEM_INFO := {
	"wood": ["Древесина", "Доски и поленья для строительства и крафта."],
	"stone": ["Камень", "Камень для фундаментов и инструментов."],
	"iron": ["Металлолом", "Пригодится для дверей и снаряжения."],
	"cloth": ["Ткань", "Материал для повязок и снаряжения."],
	"food": ["Еда", "Восстанавливает сытость."],
	"water": ["Вода", "Утоляет жажду."],
	"herbs": ["Травы", "Лекарственные растения для крафта."],
	"bandage": ["Повязка", "Восстанавливает здоровье."],
	"club": ["Бита", "Оружие ближнего боя. Можно взять в руку."],
	"spear": ["Копьё", "Оружие ближнего боя. Можно взять в руку."],
	"axe": ["Каменный топор", "Помогает быстрее разрушать деревья и камни."],
	"keycard": ["Ключ-карта", "Открывает сейф отеля."],
	"chip": ["Микросхема", "Деталь для ремонта маяка."],
	"coil": ["Катушка", "Деталь для ремонта маяка."],
	"cell": ["Энергоячейка", "Деталь для ремонта маяка."],
	"fragment": ["Фрагмент", "Найденный на острове предмет."],
}
var world
var root: Control
var modal: Control
var modal_kind := ""
var minimap: Control
var inventory_grid: GridContainer
var inventory_detail: Label
var inventory_action: Button
var selected_inventory_item := ""
var hp_bar: ProgressBar
var stamina_bar: ProgressBar
var stats_text: Label
var clock_label: Label
var quest_name: Label
var quest_text: Label
var objective_direction: Label
var waypoint_direction: Label
var interact_panel: PanelContainer
var interact_label: Label
var quick_label: Label
var toast_label: Label
var build_panel: PanelContainer
var build_status: Label
var build_buttons: Dictionary = {}
var quick_panel: PanelContainer
var controls_panel: PanelContainer
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
	quest.position = Vector2(785, 20)
	quest.size = Vector2(270, 155)
	root.add_child(quest)
	var qbox = VBoxContainer.new()
	qbox.add_theme_constant_override("separation", 7)
	quest.add_child(qbox)
	qbox.add_child(UI.label("ТЕКУЩАЯ ЦЕЛЬ", 11, UI.GOLD, true))
	quest_name = UI.label("", 17, UI.TEXT, true)
	qbox.add_child(quest_name)
	quest_text = UI.label("", 13, UI.MUTED)
	quest_text.custom_minimum_size = Vector2(230, 42)
	quest_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	qbox.add_child(quest_text)
	objective_direction = UI.label("", 12, Color("d8c594"))
	qbox.add_child(objective_direction)
	waypoint_direction = UI.label("", 11, Color("86c9ce"))
	waypoint_direction.visible = false
	qbox.add_child(waypoint_direction)
	var map_frame = UI.panel()
	map_frame.position = Vector2(1072, 20)
	map_frame.size = Vector2(186, 186)
	map_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(map_frame)
	minimap = MapView.new()
	minimap.world = world
	minimap.minimap = true
	minimap.custom_minimum_size = Vector2(160, 160)
	map_frame.add_child(minimap)
	interact_panel = UI.panel()
	interact_panel.position = Vector2(350, 580)
	interact_panel.size = Vector2(580, 46)
	root.add_child(interact_panel)
	interact_label = UI.label("", 14, UI.TEXT, true)
	interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_panel.add_child(interact_label)
	quick_panel = UI.panel()
	quick_panel.position = Vector2(22, 655)
	quick_panel.size = Vector2(525, 43)
	root.add_child(quick_panel)
	quick_label = UI.label("", 12, UI.TEXT)
	quick_panel.add_child(quick_label)
	controls_panel = UI.panel()
	controls_panel.position = Vector2(805, 655)
	controls_panel.size = Vector2(453, 43)
	root.add_child(controls_panel)
	controls_panel.add_child(UI.label("[ B ] Стройка   [ C ] Крафт   [ Tab ] Рюкзак   [ M ] Карта", 12, UI.MUTED))
	_build_construction_panel()
	toast_label = UI.label("", 15, UI.TEXT, true)
	toast_label.position = Vector2(320, 90)
	toast_label.size = Vector2(640, 55)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.add_theme_color_override("font_shadow_color", Color(0,0,0,0.85))
	toast_label.add_theme_constant_override("shadow_offset_x", 2)
	toast_label.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(toast_label)

func _build_construction_panel() -> void:
	build_panel = UI.panel()
	build_panel.position = Vector2(20, 472)
	build_panel.size = Vector2(1240, 170)
	build_panel.visible = false
	root.add_child(build_panel)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	build_panel.add_child(column)
	column.add_child(UI.label("СТРОИТЕЛЬСТВО  /  ВЫБЕРИТЕ ЭЛЕМЕНТ", 14, UI.GOLD, true))
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	column.add_child(row)
	var titles = ["1  ФУНДАМЕНТ\n4 дерево + 2 камня", "2  СТЕНА\n3 дерева", "3  КРЫША\n3 дерева", "4  ПРОЁМ\n3 дерева", "5  ДВЕРЬ\n2 дерева + 1 металл"]
	for i in range(BuildingSystem.TYPES.size()):
		var kind: String = BuildingSystem.TYPES[i]
		var button = UI.button(titles[i], Vector2(218, 47))
		button.add_theme_font_size_override("font_size", 11)
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): world.building.select_type(kind))
		row.add_child(button)
		build_buttons[kind] = button
	build_status = UI.label("", 13, UI.TEXT, true)
	column.add_child(build_status)
	column.add_child(UI.label("ЛКМ — построить  •  R — повернуть сторону / петлю  •  X — разобрать  •  E — дверь  •  B / Esc — выход", 12, UI.MUTED))

func set_build_mode(enabled: bool) -> void:
	build_panel.visible = enabled
	quick_panel.visible = not enabled
	controls_panel.visible = not enabled

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
	waypoint_direction.visible = world.waypoint_map.x >= 0.0
	if waypoint_direction.visible:
		var waypoint_meters: float = world.player_map_position().distance_to(world.waypoint_map) * world.MAP_SCALE
		waypoint_direction.text = "◆  Моя метка  ·  %d м" % int(waypoint_meters)
	quick_label.text = "[ 1 ] Еда %d      [ 2 ] Вода %d      [ 3 ] Бинт %d      ◈ %d / 7" % [world.count("food"), world.count("water"), world.count("bandage"), 1 if world.flags.get("fragment", false) else 0]
	if world.building.active:
		interact_panel.visible = false
		var selected: String = world.building.selected
		var color = Color("92dcb1") if world.building.valid else Color("e8a095")
		build_status.add_theme_color_override("font_color", color)
		build_status.text = "%s  •  %s     |     Дерево %d  Камень %d  Металл %d" % [BuildingSystem.NAMES[selected], world.building.reason, world.count("wood"), world.count("stone"), world.count("iron")]
		for kind in build_buttons:
			build_buttons[kind].modulate = Color.WHITE if kind == selected else Color(0.67, 0.72, 0.69)
	else:
		var door = world.building.nearest_door()
		var nearest = world.nearest_prop()
		interact_panel.visible = (door != null or nearest != null) and not is_modal_open()
		if door:
			interact_label.text = "[ E ]  Закрыть дверь" if bool(door.data.get("open", false)) else "[ E ]  Открыть дверь"
		elif nearest:
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
	modal_kind = ""

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

func _item_count(item: String) -> int:
	if item in ["wood", "stone", "iron", "cloth", "food", "water", "herbs", "bandage"]:
		return world.count(item)
	return 1 if world.flags.get(item, false) else 0

func show_inventory() -> void:
	var box = _window("РЮКЗАК  /  ПРЕДМЕТЫ", "")
	modal_kind = "inventory"
	box.add_child(UI.label("Выберите предмет в ячейке. Еда, вода и повязки используются здесь или клавишами 1–3.", 12, UI.MUTED))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	box.add_child(body)
	inventory_grid = GridContainer.new()
	inventory_grid.name = "InventoryGrid"
	inventory_grid.columns = 6
	inventory_grid.add_theme_constant_override("h_separation", 5)
	inventory_grid.add_theme_constant_override("v_separation", 5)
	body.add_child(inventory_grid)
	var details := VBoxContainer.new()
	details.custom_minimum_size = Vector2(160, 0)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 14)
	body.add_child(details)
	details.add_child(UI.label("ВЫБРАННЫЙ ПРЕДМЕТ", 11, UI.GOLD, true))
	inventory_detail = UI.label("", 14, UI.TEXT, true)
	inventory_detail.name = "InventoryDetails"
	inventory_detail.custom_minimum_size = Vector2(160, 100)
	inventory_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(inventory_detail)
	inventory_action = UI.button("Использовать", Vector2(150, 42))
	inventory_action.name = "InventoryUse"
	inventory_action.pressed.connect(_use_selected_item)
	details.add_child(inventory_action)
	details.add_child(UI.label("[ Q ] смена оружия", 11, UI.MUTED))
	var items: Array[String] = []
	for item in ITEM_ORDER:
		if _item_count(item) > 0:
			items.append(item)
	if selected_inventory_item not in items:
		selected_inventory_item = items[0] if not items.is_empty() else ""
	var group := ButtonGroup.new()
	for i in range(24):
		var item: String = items[i] if i < items.size() else ""
		var slot := UI.button("", Vector2(84, 78))
		slot.name = "InventorySlot_%02d" % i
		slot.focus_mode = Control.FOCUS_NONE
		slot.disabled = item.is_empty()
		slot.toggle_mode = not item.is_empty()
		slot.button_group = group
		inventory_grid.add_child(slot)
		if item.is_empty():
			slot.tooltip_text = "Пустая ячейка"
			continue
		slot.set_meta("item_id", item)
		slot.tooltip_text = ITEM_INFO[item][0]
		slot.button_pressed = item == selected_inventory_item
		var icon := TextureRect.new()
		icon.name = "ItemIcon"
		icon.texture = load("res://assets/icons/%s.png" % item)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(5, 2)
		icon.size = Vector2(68, 68)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		var amount := UI.label(str(_item_count(item)), 13, Color.WHITE, true)
		amount.name = "ItemCount"
		amount.position = Vector2(53, 53)
		amount.size = Vector2(26, 20)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.add_theme_color_override("font_shadow_color", Color.BLACK)
		amount.add_theme_constant_override("shadow_offset_x", 1)
		amount.add_theme_constant_override("shadow_offset_y", 1)
		slot.add_child(amount)
		slot.pressed.connect(_select_inventory_item.bind(item))
	_select_inventory_item(selected_inventory_item)
	var close := UI.button("ЗАКРЫТЬ", Vector2(180, 42))
	box.add_child(close)
	close.pressed.connect(close_modal)

func _select_inventory_item(item: String) -> void:
	selected_inventory_item = item
	if item.is_empty():
		inventory_detail.text = "Рюкзак пуст."
		inventory_action.disabled = true
		return
	var data: Array = ITEM_INFO[item]
	inventory_detail.text = "%s  × %d\n\n%s" % [data[0], _item_count(item), data[1]]
	if item in ["club", "spear"] and world.weapon_id() == item:
		inventory_detail.text += "\n\nВ руке"
	inventory_action.text = "Взять в руку" if item in ["club", "spear"] else "Использовать"
	inventory_action.disabled = item not in ["food", "water", "bandage", "club", "spear"]

func _use_selected_item() -> void:
	if selected_inventory_item in ["food", "water", "bandage"]:
		world.use_item(selected_inventory_item)
	elif selected_inventory_item in ["club", "spear"] and _item_count(selected_inventory_item) > 0:
		world.equipped_weapon = selected_inventory_item
		world.player._update_weapon()
		world.save_progress(false)
	show_inventory()

func show_crafting() -> void:
	var content = _window("КРАФТ", "Созданное оружие экипируется автоматически. Биту и копьё можно менять клавишей Q. Каменный топор увеличивает добычу древесины и камня.")
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
	modal_kind = "map"
	var panel = UI.panel()
	panel.position = Vector2(170, 48)
	panel.size = Vector2(940, 625)
	screen.add_child(panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(UI.label("ПРИЮТ  /  КАРТА ОСТРОВА", 22, UI.GOLD, true))
	box.add_child(UI.label("▲ Вы    •    ● Цель    •    ■ База    •    ◆ Метка    •    Деревья / камни   |   Колесо — масштаб  ·  ЛКМ — метка или перетаскивание  ·  ПКМ — убрать", 11, UI.MUTED))
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
	content.add_child(UI.label("WASD — движение  •  Shift — бег  •  Пробел — прыжок\nЛКМ/F — удар  •  E — предмет или дверь  •  Q — оружие\nB — строительство  •  1–5 — элемент  •  R — сторона  •  X — разобрать\nПКМ + мышь — камера  •  M — карта  •  C — крафт", 14, UI.MUTED))
	resume.grab_focus()
