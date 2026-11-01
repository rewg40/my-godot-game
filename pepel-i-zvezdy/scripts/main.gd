extends Node
## Корневой узел игры: меню → забег → смерть → снова меню.
##
## Здесь же живёт вся «клеевая» логика: смена режима мыши, открытие панелей,
## автопересохранение на рассвете.

const WORLD_SCENE := preload("res://scenes/world/World.tscn")
const HUD_SCENE := preload("res://scenes/ui/HUD.tscn")
const MENU_SCENE := preload("res://scenes/ui/MainMenu.tscn")
const INVENTORY_SCENE := preload("res://scenes/ui/InventoryUI.tscn")
const CRAFTING_SCENE := preload("res://scenes/ui/CraftingUI.tscn")
const PAUSE_SCENE := preload("res://scenes/ui/PauseMenu.tscn")

var world: GameWorld
var hud: GameHUD
var menu: MainMenu
var inventory_ui: InventoryUI
var crafting_ui: CraftingUI
var pause_menu: PauseMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().title = "Пепел и Звёзды"
	GameState.pause_changed.connect(_on_pause_changed)
	GameState.ui_open_changed.connect(_on_ui_open_changed)
	GameState.run_started.connect(_on_run_started)
	GameState.run_ended.connect(_on_run_ended)
	GameState.day_started.connect(_on_day_started)
	_show_menu()


# --- Сценарии ---------------------------------------------------------------

func _show_menu() -> void:
	_clear_run()
	GameState.abandon_run()
	GameState.ui_open = false
	menu = MENU_SCENE.instantiate() as MainMenu
	add_child(menu)
	menu.start_requested.connect(_on_start_requested)
	menu.continue_requested.connect(_on_continue_requested)
	menu.quit_requested.connect(_on_quit)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _start_new_game(class_id: String) -> void:
	GameState.start_run(class_id)
	_spawn_run({})


func _continue_game() -> void:
	var data := SaveSystem.load_game()
	if data.is_empty():
		return
	GameState.start_run(String(data.get("class", "medic")), int(data.get("seed", 0)))
	_spawn_run(data)


func _spawn_run(data: Dictionary) -> void:
	_clear_run()
	menu = null

	world = WORLD_SCENE.instantiate() as GameWorld
	add_child(world)
	await world.setup(GameState.world_seed, data)

	hud = HUD_SCENE.instantiate() as GameHUD
	add_child(hud)
	hud.restart_requested.connect(_on_restart)
	hud.menu_requested.connect(_show_menu)

	inventory_ui = INVENTORY_SCENE.instantiate() as InventoryUI
	add_child(inventory_ui)

	crafting_ui = CRAFTING_SCENE.instantiate() as CraftingUI
	add_child(crafting_ui)

	pause_menu = PAUSE_SCENE.instantiate() as PauseMenu
	add_child(pause_menu)
	pause_menu.menu_requested.connect(_show_menu)
	pause_menu.quit_requested.connect(_on_quit)

	_apply_mouse_mode()
	GameState.message.emit("Остров принял вас. Найдите воду до темноты.")


func _clear_run() -> void:
	var nodes := [world, hud, inventory_ui, crafting_ui, pause_menu, menu]
	for node in nodes:
		if node != null and is_instance_valid(node):
			var child := node as Node
			if child.get_parent() != null:
				child.get_parent().remove_child(child)
			child.queue_free()
	world = null
	hud = null
	inventory_ui = null
	crafting_ui = null
	pause_menu = null
	menu = null


# --- Обработчики ------------------------------------------------------------

func _on_start_requested(class_id: String) -> void:
	_start_new_game(class_id)


func _on_continue_requested() -> void:
	_continue_game()


func _on_restart() -> void:
	GameState.start_run(GameState.selected_class)
	_spawn_run({})


func _on_quit() -> void:
	get_tree().quit()


func _on_run_started(_class_id: String) -> void:
	_apply_mouse_mode()


func _on_run_ended(_cause: String) -> void:
	_apply_mouse_mode()


func _on_pause_changed(_paused_flag: bool) -> void:
	_apply_mouse_mode()


func _on_ui_open_changed(_is_open: bool) -> void:
	_apply_mouse_mode()


func _on_day_started(day: int) -> void:
	if world == null or not is_instance_valid(world):
		return
	if SaveSystem.save_game(world.get_save_data()):
		GameState.message.emit("Рассвет дня %d. Игра сохранена." % day)


func _apply_mouse_mode() -> void:
	var capture := GameState.run_active and not GameState.is_paused and not GameState.ui_open
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not GameState.run_active or GameState.is_paused:
		return
	if event.is_action_pressed("inventory") and inventory_ui != null:
		inventory_ui.toggle()
		if inventory_ui.visible and crafting_ui != null:
			crafting_ui.close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("craft") and crafting_ui != null:
		crafting_ui.toggle()
		if crafting_ui.visible and inventory_ui != null:
			inventory_ui.close()
		get_viewport().set_input_as_handled()
