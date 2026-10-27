extends RefCounted

const FONT = preload("res://assets/fonts/DejaVuSans.ttf")
const FONT_BOLD = preload("res://assets/fonts/DejaVuSans-Bold.ttf")
const TEXT = Color("e9e5d4")
const MUTED = Color("a9b6a9")
const GOLD = Color("e6bd75")
const DARK = Color("101e20")
const PANEL = Color(0.055, 0.095, 0.092, 0.94)

static func box(color: Color, border: Color = Color(0.34, 0.42, 0.36, 0.7), radius: int = 8) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func label(text: String, size: int = 16, color: Color = TEXT, bold: bool = false) -> Label:
	var result = Label.new()
	result.text = text
	result.add_theme_font_override("font", FONT_BOLD if bold else FONT)
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func button(text: String, minimum: Vector2 = Vector2(260, 46)) -> Button:
	var result = Button.new()
	result.text = text
	result.custom_minimum_size = minimum
	result.add_theme_font_override("font", FONT_BOLD)
	result.add_theme_font_size_override("font_size", 15)
	result.add_theme_color_override("font_color", TEXT)
	result.add_theme_color_override("font_hover_color", Color("fff5db"))
	result.add_theme_color_override("font_disabled_color", Color("718077"))
	result.add_theme_stylebox_override("normal", box(Color("243d37"), Color("799065"), 5))
	result.add_theme_stylebox_override("hover", box(Color("385548"), GOLD, 5))
	result.add_theme_stylebox_override("pressed", box(Color("182e29"), GOLD, 5))
	result.add_theme_stylebox_override("disabled", box(Color("1a2928"), Color("43534a"), 5))
	result.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), GOLD, 5))
	return result

static func panel() -> PanelContainer:
	var result = PanelContainer.new()
	result.add_theme_stylebox_override("panel", box(PANEL))
	return result

static func bar(color: Color) -> ProgressBar:
	var result = ProgressBar.new()
	result.show_percentage = false
	result.custom_minimum_size = Vector2(175, 8)
	result.add_theme_stylebox_override("background", box(Color("273c37"), Color(0, 0, 0, 0), 4))
	result.add_theme_stylebox_override("fill", box(color, Color(0, 0, 0, 0), 4))
	return result
