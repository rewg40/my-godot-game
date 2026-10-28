extends RefCounted

const PATH = "user://shelter_save_v1.json"
const TEST_PATH = "user://shelter_test_save_v1.json"
const VERSION = 1

static func save_path() -> String:
	return TEST_PATH if OS.get_environment("SHARDS_TEST_SAVE") == "1" else PATH

static func exists() -> bool:
	return FileAccess.file_exists(save_path()) or FileAccess.file_exists(save_path() + ".bak")

# A file can be valid JSON and still contain corrupt types. Reject it before
# World tries to convert the values, so load_data() can try the backup instead.
# Missing fields are allowed for older saves; present fields must be safe.
static func _is_number(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number = float(value)
	# Stay within the exact integer range of JSON numbers before int() casts.
	return is_finite(number) and absf(number) <= 9007199254740991.0

static func _is_boolean(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL or _is_number(value)

static func _valid_data(data: Dictionary) -> bool:
	if not data.has("version") or not _is_number(data["version"]) or float(data["version"]) != VERSION:
		return false
	for key in ["quest_stage", "side_stage", "day", "minute", "last_raid_day"]:
		if data.has(key) and not _is_number(data[key]):
			return false
	var inventory = data.get("inventory", {})
	if not inventory is Dictionary:
		return false
	for amount in inventory.values():
		if not _is_number(amount):
			return false
	var flags = data.get("flags", {})
	if not flags is Dictionary:
		return false
	for enabled in flags.values():
		if not _is_boolean(enabled):
			return false
	if data.has("equipped_weapon") and not data["equipped_weapon"] is String:
		return false
	if data.has("towers"):
		var towers = data["towers"]
		if not towers is Array or towers.size() != 3:
			return false
		for built in towers:
			if not _is_boolean(built):
				return false
	if data.has("dead_ids"):
		var dead_ids = data["dead_ids"]
		if not dead_ids is Array:
			return false
		for identity in dead_ids:
			if not identity is String:
				return false
	var player = data.get("player", {})
	if not player is Dictionary:
		return false
	for key in ["health", "stamina", "hunger", "thirst"]:
		if player.has(key) and not _is_number(player[key]):
			return false
	if player.has("position"):
		var position = player["position"]
		if not position is Array or position.size() != 2:
			return false
		if not _is_number(position[0]) or not _is_number(position[1]):
			return false
	return true

static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser = JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {}
	var parsed = parser.data
	if not parsed is Dictionary or not _valid_data(parsed):
		return {}
	return parsed

static func load_data() -> Dictionary:
	var data = _read(save_path())
	if data.is_empty():
		data = _read(save_path() + ".bak")
	return data

static func save_data(data: Dictionary) -> bool:
	# Keep a backup as well as a temporary file. Some platforms remove the
	# destination during rename; a failed rename can then restore the backup.
	data["version"] = VERSION
	var path = save_path()
	var tmp = path + ".tmp"
	var backup = path + ".bak"
	var file = FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	var write_error = file.get_error()
	file.close()
	var old_abs = ProjectSettings.globalize_path(path)
	var tmp_abs = ProjectSettings.globalize_path(tmp)
	if write_error != OK:
		DirAccess.remove_absolute(tmp_abs)
		return false
	var backup_abs = ProjectSettings.globalize_path(backup)
	var had_old = FileAccess.file_exists(path)
	if had_old and DirAccess.copy_absolute(old_abs, backup_abs) != OK:
		DirAccess.remove_absolute(tmp_abs)
		return false
	if DirAccess.rename_absolute(tmp_abs, old_abs) != OK:
		if had_old and not FileAccess.file_exists(path):
			DirAccess.copy_absolute(backup_abs, old_abs)
		return false
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup_abs)
	return true
