class_name Controls
extends RefCounted
## Раскладка управления: физические клавиши, регистрируются при старте.

const KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"attack": [KEY_F],
	"restart": [KEY_R],
	"quit": [KEY_ESCAPE],
	"toggle_help": [KEY_F1],
	"toggle_limb_zones": [KEY_F3],
}

const MOUSE := {
	"attack": MOUSE_BUTTON_LEFT,
}


static func register() -> void:
	for action in KEYS.keys():
		_ensure(String(action))
		if not InputMap.action_get_events(String(action)).is_empty():
			continue
		for key in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(String(action), event)
	for action in MOUSE.keys():
		_ensure(String(action))
		if not InputMap.action_get_events(String(action)).is_empty():
			continue
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE[action]
		InputMap.action_add_event(String(action), mouse)


static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
