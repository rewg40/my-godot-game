extends RefCounted
## Общая палитра и фабрика элементов интерфейса.
##
## Интерфейс игры собирается кодом, поэтому все цвета и стили живут здесь:
## поменяв константу, вы меняете вид всех экранов сразу.

const BG := Color("#0b0d10")
const PANEL := Color("#14181d")
const PANEL_LIGHT := Color("#1c2228")
const EMBER := Color("#e3893f")
const EMBER_LIGHT := Color("#ffc884")
const STAR := Color("#8fd3ff")
const TEXT := Color("#e6e3dd")
const MUTED := Color("#8d9298")
const DANGER := Color("#cf4a45")
const OK := Color("#6fa86b")
const BORDER := Color(1.0, 1.0, 1.0, 0.08)


static func make_stylebox(color: Color, radius: int = 6, border: int = 0,
		border_color: Color = BORDER) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.border_width_left = border
	box.border_width_right = border
	box.border_width_top = border
	box.border_width_bottom = border
	box.border_color = border_color
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 15

	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.4))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)

	theme.set_stylebox("panel", "Panel", make_stylebox(PANEL, 10, 1))
	theme.set_stylebox("panel", "PanelContainer", make_stylebox(PANEL, 10, 1))

	var normal := make_stylebox(PANEL_LIGHT, 8, 1)
	var hover := make_stylebox(PANEL_LIGHT.lerp(EMBER, 0.25), 8, 1, EMBER)
	var pressed := make_stylebox(EMBER.darkened(0.35), 8, 1, EMBER)
	var disabled := make_stylebox(PANEL_LIGHT.darkened(0.25), 8, 1, Color(1, 1, 1, 0.04))
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", make_stylebox(Color(0, 0, 0, 0), 8, 1, EMBER))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", EMBER_LIGHT)
	theme.set_color("font_pressed_color", "Button", Color("#0b0d10"))
	theme.set_color("font_disabled_color", "Button", MUTED.darkened(0.2))
	theme.set_font_size("font_size", "Button", 16)

	theme.set_stylebox("background", "ProgressBar", make_stylebox(Color(1, 1, 1, 0.07), 4))
	theme.set_stylebox("fill", "ProgressBar", make_stylebox(EMBER, 4))

	theme.set_stylebox("scroll", "VScrollBar", make_stylebox(PANEL, 4))
	theme.set_stylebox("grabber", "VScrollBar", make_stylebox(MUTED, 4))
	theme.set_stylebox("grabber_highlight", "VScrollBar", make_stylebox(EMBER, 4))
	theme.set_stylebox("grabber_pressed", "VScrollBar", make_stylebox(EMBER_LIGHT, 4))

	theme.set_stylebox("slider", "HSlider", make_stylebox(Color(1, 1, 1, 0.09), 3))
	theme.set_stylebox("grabber_area", "HSlider", make_stylebox(EMBER, 3))
	theme.set_stylebox("grabber_area_highlight", "HSlider", make_stylebox(EMBER_LIGHT, 3))
	return theme


static func label(text: String, size: int = 15, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node


static func title(text: String, size: int = 46) -> Label:
	var node := label(text, size, TEXT)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return node


static func button(text: String, min_height: float = 42.0) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(0.0, min_height)
	node.focus_mode = Control.FOCUS_ALL
	return node


static func panel(color: Color = PANEL) -> PanelContainer:
	var node := PanelContainer.new()
	var box := make_stylebox(color, 10, 1)
	node.add_theme_stylebox_override("panel", box)
	return node


static func bar(fill_color: Color, width: float = 150.0, height: float = 10.0) -> ProgressBar:
	var node := ProgressBar.new()
	node.custom_minimum_size = Vector2(width, height)
	node.show_percentage = false
	node.max_value = 100.0
	node.value = 100.0
	node.add_theme_stylebox_override("background", make_stylebox(Color(1, 1, 1, 0.08), 4))
	node.add_theme_stylebox_override("fill", make_stylebox(fill_color, 4))
	return node


## Ставит узел по якорю и задаёт отступы (left, top, right, bottom).
static func anchor(node: Control, preset: int, offsets: Vector4) -> Control:
	node.set_anchors_preset(preset, false)
	node.offset_left = offsets.x
	node.offset_top = offsets.y
	node.offset_right = offsets.z
	node.offset_bottom = offsets.w
	return node


static func full_rect(node: Control) -> Control:
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.offset_left = 0.0
	node.offset_top = 0.0
	node.offset_right = 0.0
	node.offset_bottom = 0.0
	return node
