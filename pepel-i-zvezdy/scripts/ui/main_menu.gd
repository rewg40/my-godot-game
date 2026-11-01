class_name MainMenu
extends CanvasLayer
## Главное меню: выбор класса, новая игра, продолжение и выход.
##
## Класс — это не только цифры: у каждого свой стартовый набор и своя манера
## выживать. Описание обновляется при выборе.

signal start_requested(class_id: String)
signal continue_requested
signal quit_requested

const UI := preload("res://scripts/ui/ui_theme.gd")

var _selected := "medic"
var _class_buttons := {}
var _class_desc: Label
var _continue_button: Button


func _ready() -> void:
	layer = 30
	_build()
	_refresh_classes()


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0.035, 0.043, 0.055)
	add_child(background)
	UI.full_rect(background)

	var gradient := TextureRect.new()
	var texture := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.add_point(0.0, Color(0.06, 0.09, 0.13))
	grad.add_point(0.55, Color(0.05, 0.06, 0.08))
	grad.add_point(1.0, Color(0.14, 0.08, 0.05))
	texture.gradient = grad
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	gradient.texture = texture
	gradient.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gradient.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(gradient)
	UI.full_rect(gradient)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	add_child(content)
	UI.anchor(content, Control.PRESET_CENTER, Vector4(-460.0, -280.0, 460.0, 300.0))

	var title := UI.title("ПЕПЕЛ И ЗВЁЗДЫ", 60)
	title.add_theme_color_override("font_color", UI.TEXT)
	content.add_child(title)

	var subtitle := UI.label("выживание на заражённом острове", 17, UI.EMBER)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(subtitle)

	var line := ColorRect.new()
	line.color = Color(1.0, 1.0, 1.0, 0.08)
	line.custom_minimum_size = Vector2(0.0, 1.0)
	content.add_child(line)

	var pick := UI.label("Выберите, кем вы пришли на остров:", 15, UI.MUTED)
	pick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(pick)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(row)

	for class_id in ItemDB.class_ids():
		var data := ItemDB.class_data(String(class_id))
		var button := UI.button("", 92.0)
		button.custom_minimum_size = Vector2(210.0, 92.0)
		button.text = "%s\n%s" % [String(data["name"]), String(data["tagline"])]
		button.add_theme_color_override("font_color", data.get("color", UI.TEXT))
		button.pressed.connect(_select_class.bind(String(class_id)))
		row.add_child(button)
		_class_buttons[String(class_id)] = button

	_class_desc = UI.label("", 15, UI.TEXT)
	_class_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_class_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_class_desc.custom_minimum_size = Vector2(0.0, 52.0)
	content.add_child(_class_desc)

	var start := UI.button("Начать новую игру", 50.0)
	start.add_theme_font_size_override("font_size", 20)
	start.pressed.connect(func() -> void: start_requested.emit(_selected))
	content.add_child(start)

	_continue_button = UI.button("Продолжить", 40.0)
	_continue_button.pressed.connect(func() -> void: continue_requested.emit())
	_continue_button.disabled = not SaveSystem.has_save()
	content.add_child(_continue_button)

	var quit := UI.button("Выход", 36.0)
	quit.pressed.connect(func() -> void: quit_requested.emit())
	content.add_child(quit)

	var hint := "WASD — идти · Shift — бежать · E — действие · ЛКМ — удар"
	hint += " · Tab — рюкзак · C — крафт · Esc — пауза"
	var footer := UI.label(hint, 12, UI.MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(footer)
	UI.anchor(footer, Control.PRESET_CENTER_BOTTOM, Vector4(-460.0, -54.0, 460.0, -26.0))


func _select_class(class_id: String) -> void:
	_selected = class_id
	_refresh_classes()


func _refresh_classes() -> void:
	for id in _class_buttons.keys():
		var button: Button = _class_buttons[id]
		if String(id) == _selected:
			button.add_theme_stylebox_override("normal", UI.make_stylebox(UI.PANEL_LIGHT, 8, 2, UI.EMBER))
		else:
			button.add_theme_stylebox_override("normal", UI.make_stylebox(UI.PANEL_LIGHT, 8, 1, UI.BORDER))
	var data := ItemDB.class_data(_selected)
	if _class_desc != null:
		_class_desc.text = "%s\nСтарт: %s" % [String(data["desc"]), _start_items_text(data)]
	if _continue_button != null:
		_continue_button.disabled = not SaveSystem.has_save()


func _start_items_text(data: Dictionary) -> String:
	var text := ""
	var start: Dictionary = data.get("start", {})
	for id in start.keys():
		if not text.is_empty():
			text += ", "
		text += "%s ×%d" % [ItemDB.display_name(String(id)), int(start[id])]
	return text
