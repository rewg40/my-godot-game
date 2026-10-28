extends Node

const UI = preload("res://scripts/ui_style.gd")
const SaveGame = preload("res://scripts/save_game.gd")
const WORLD_SCRIPT = "res://scripts/world.gd"

var current_screen: Node
var music: AudioStreamPlayer

func _ready() -> void:
	_setup_input()
	music = AudioStreamPlayer.new()
	music.stream = load("res://assets/audio/shelter.ogg")
	if music.stream:
		music.stream.loop = true
	music.volume_db = -22.0
	add_child(music)
	# Headless runs have no audio output, and short-lived dummy audio playbacks
	# can still be held by the mixing thread when Godot shuts down.
	if DisplayServer.get_name() != "headless":
		music.play()
	show_menu()

func _exit_tree() -> void:
	# Release looping audio before the scene tree and AudioServer shut down.
	# Recent Godot versions otherwise keep playback resources alive at exit.
	if is_instance_valid(music):
		music.stop()
		music.stream = null

func _setup_input() -> void:
	var actions = {
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT], "jump": [KEY_SPACE], "attack": [KEY_F]
	}
	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for code in actions[action]:
			var event = InputEventKey.new()
			event.physical_keycode = code
			InputMap.action_add_event(action, event)
	var mouse = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", mouse)

func show_menu(message: String = "") -> void:
	if is_instance_valid(current_screen):
		current_screen.queue_free()
	var menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	current_screen = menu
	var background = TextureRect.new()
	background.texture = load("res://assets/art/shelter_menu.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(background)
	var veil = ColorRect.new()
	veil.color = Color(0.02, 0.06, 0.07, 0.30)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(veil)
	var left = ColorRect.new()
	left.position = Vector2(0, 0)
	left.size = Vector2(615, 720)
	left.color = Color(0.025, 0.06, 0.065, 0.80)
	menu.add_child(left)
	var line = ColorRect.new()
	line.position = Vector2(70, 68)
	line.size = Vector2(44, 3)
	line.color = UI.GOLD
	menu.add_child(line)
	var eyebrow = UI.label("НОВАЯ АРКАДИЯ  /  2291", 13, UI.GOLD, true)
	eyebrow.position = Vector2(126, 60)
	menu.add_child(eyebrow)
	var title = UI.label("ОСКОЛКИ\nЦИВИЛИЗАЦИИ", 36, UI.TEXT, true)
	title.position = Vector2(70, 115)
	title.add_theme_constant_override("line_spacing", 10)
	menu.add_child(title)
	var sub = UI.label("Выживи. Защити. Найди надежду.", 17, UI.MUTED)
	sub.position = Vector2(72, 224)
	menu.add_child(sub)
	var buttons = VBoxContainer.new()
	buttons.position = Vector2(70, 296)
	buttons.add_theme_constant_override("separation", 11)
	menu.add_child(buttons)
	var start = UI.button("НОВАЯ ИГРА", Vector2(330, 51))
	buttons.add_child(start)
	start.pressed.connect(func(): _confirm_new_game(menu))
	var resume = UI.button("ПРОДОЛЖИТЬ", Vector2(330, 51))
	resume.disabled = not SaveGame.exists()
	buttons.add_child(resume)
	resume.pressed.connect(func(): start_game(true))
	var help = UI.button("УПРАВЛЕНИЕ", Vector2(330, 51))
	buttons.add_child(help)
	help.pressed.connect(func(): _show_menu_help(menu))
	var note = UI.label("ПРИЮТ  •  ИГРАБЕЛЬНАЯ ГЛАВА 01", 12, UI.GOLD, true)
	note.position = Vector2(72, 629)
	menu.add_child(note)
	var foot = UI.label("По мотивам сценария «Осколки цивилизации»", 12, UI.MUTED)
	foot.position = Vector2(72, 656)
	menu.add_child(foot)
	if not message.is_empty():
		var warning = UI.label(message, 13, Color("e7b17c"))
		warning.position = Vector2(72, 550)
		warning.size = Vector2(475, 45)
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		menu.add_child(warning)
	start.grab_focus()

func _confirm_new_game(menu: Control) -> void:
	if not SaveGame.exists():
		start_game(false)
		return
	var shade = ColorRect.new()
	shade.color = Color(0.01, 0.025, 0.025, 0.84)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(shade)
	var panel = UI.panel()
	panel.position = Vector2(360, 235)
	panel.size = Vector2(560, 230)
	shade.add_child(panel)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	panel.add_child(content)
	content.add_child(UI.label("НАЧАТЬ ЗАНОВО?", 22, UI.GOLD, true))
	var warning = UI.label("Новая игра заменит существующее сохранение.", 15, UI.TEXT)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(warning)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	var confirm = UI.button("НАЧАТЬ ЗАНОВО", Vector2(210, 44))
	row.add_child(confirm)
	confirm.pressed.connect(func(): start_game(false))
	var cancel = UI.button("ОТМЕНА", Vector2(180, 44))
	row.add_child(cancel)
	cancel.pressed.connect(shade.queue_free)
	cancel.grab_focus()

func _show_menu_help(menu: Control) -> void:
	var veil = ColorRect.new()
	veil.color = Color(0.01, 0.025, 0.025, 0.82)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(veil)
	var panel = UI.panel()
	panel.position = Vector2(345, 105)
	panel.size = Vector2(590, 490)
	veil.add_child(panel)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	panel.add_child(content)
	content.add_child(UI.label("УПРАВЛЕНИЕ", 23, UI.GOLD, true))
	var info = UI.label("WASD / стрелки  —  движение относительно камеры\nПКМ + мышь  —  поворот камеры; колесо  —  приближение\nShift  —  бег     Пробел  —  прыжок\nЛКМ или F  —  удар     E  —  взаимодействие\nQ  —  сменить биту / копьё\nC  —  крафт     Tab  —  рюкзак     B  —  строительство\nВ стройке: 1–5 — элемент, ЛКМ — поставить, R — сторона, X — разобрать\nM  —  карта     1 / 2 / 3  —  еда / вода / бинт\nEsc  —  пауза     F5  —  сохранить", 15, UI.TEXT)
	info.add_theme_constant_override("line_spacing", 8)
	content.add_child(info)
	var close = UI.button("ПОНЯТНО", Vector2(240, 46))
	content.add_child(close)
	close.pressed.connect(veil.queue_free)
	close.grab_focus()

func start_game(continue_game: bool) -> void:
	var data = {}
	if continue_game:
		data = SaveGame.load_data()
		if data.is_empty():
			show_menu("Не удалось прочитать сохранение. Файл не изменён.")
			return
	# Load the heavy 3D world only after the player chooses to start. This
	# keeps opening the game/menu responsive on less powerful Windows PCs.
	var world_script = load(WORLD_SCRIPT)
	if world_script == null:
		show_menu("Не удалось загрузить игровой мир. Проверьте импорт ресурсов в Godot.")
		return
	if is_instance_valid(current_screen):
		current_screen.queue_free()
	var world = world_script.new()
	world.main = self
	world.load_data = data
	add_child(world)
	current_screen = world
