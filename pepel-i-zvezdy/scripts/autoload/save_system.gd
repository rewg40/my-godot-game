extends Node
## Автозагрузка «SaveSystem»: сохранения забега и настройки управления.
##
## Сохранение — обычный JSON в user://saves/slot1.json. Мир восстанавливается
## из того же seed, поэтому рельеф, растительность и лут остаются на местах.

const SAVE_DIR := "user://saves"
const SAVE_PATH := "user://saves/slot1.json"
const SETTINGS_PATH := "user://settings.json"
const SAVE_VERSION := 1


func _ready() -> void:
	_load_settings()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	data["version"] = SAVE_VERSION
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Не удалось открыть файл сохранения: %s" % SAVE_PATH)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


func load_game() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Файл сохранения повреждён.")
		return {}
	var data: Dictionary = parsed
	if int(data.get("version", 0)) > SAVE_VERSION:
		push_warning("Сохранение из более новой версии игры.")
		return {}
	return data


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)


func save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(GameState.settings, "\t"))
	file.close()


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for key in parsed.keys():
		GameState.settings[key] = parsed[key]
