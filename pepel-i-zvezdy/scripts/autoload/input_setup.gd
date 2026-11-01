extends Node
## Автозагрузка «InputSetup».
##
## Вся раскладка собрана в одном месте и регистрируется в InputMap при старте.
## Новое действие достаточно добавить в словарь ниже — код игры подхватит его
## автоматически, а физические клавиши будут одинаковыми на любой раскладке.

const KEY_BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"crouch": [KEY_CTRL],
	"interact": [KEY_E],
	"inventory": [KEY_TAB, KEY_I],
	"craft": [KEY_C],
	"pause": [KEY_ESCAPE],
	"use_slot_1": [KEY_1],
	"use_slot_2": [KEY_2],
	"use_slot_3": [KEY_3],
	"use_slot_4": [KEY_4],
	"use_slot_5": [KEY_5],
}

const MOUSE_BINDINGS := {
	"attack": MOUSE_BUTTON_LEFT,
	"slot_next": MOUSE_BUTTON_WHEEL_DOWN,
	"slot_prev": MOUSE_BUTTON_WHEEL_UP,
}


func _ready() -> void:
	_register_keys()
	_register_mouse()


func _register_keys() -> void:
	for action in KEY_BINDINGS.keys():
		_prepare_action(String(action))
		var events: Array = InputMap.action_get_events(String(action))
		if not events.is_empty():
			continue
		for keycode in KEY_BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(String(action), event)


func _register_mouse() -> void:
	for action in MOUSE_BINDINGS.keys():
		_prepare_action(String(action))
		var events: Array = InputMap.action_get_events(String(action))
		if not events.is_empty():
			continue
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BINDINGS[action]
		InputMap.action_add_event(String(action), event)


func _prepare_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
