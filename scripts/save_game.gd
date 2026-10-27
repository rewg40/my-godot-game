extends RefCounted

const PATH = "user://shelter_save_v1.json"
const TEST_PATH = "user://shelter_test_save_v1.json"
const VERSION = 1

static func save_path() -> String:
	return TEST_PATH if OS.get_environment("SHARDS_TEST_SAVE") == "1" else PATH

static func exists() -> bool:
	return FileAccess.file_exists(save_path()) or FileAccess.file_exists(save_path() + ".bak")

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
	if not parsed is Dictionary or int(parsed.get("version", 0)) != VERSION:
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
