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

static func _valid_buildings(value: Variant) -> bool:
	if not value is Array or value.size() > 10000:
		return false
	var foundations := {}
	var edges := {}
	var records := {}
	for piece in value:
		if not piece is Dictionary:
			return false
		var kind = piece.get("type", "")
		if kind not in ["foundation", "wall", "roof", "doorway", "door"]:
			return false
		for key in ["x", "z", "y"]:
			if not piece.has(key) or not _is_number(piece[key]):
				return false
		var x := int(piece["x"])
		var z := int(piece["z"])
		var y := float(piece["y"])
		if float(piece["x"]) != x or float(piece["z"]) != z or y < -10.0 or y > 24.0:
			return false
		var identity := ""
		if kind in ["foundation", "roof"]:
			if x < 0 or x > 86 or z < 0 or z > 59:
				return false
			identity = ("f:%d:%d" if kind == "foundation" else "r:%d:%d") % [x, z]
			if kind == "foundation": foundations["%d:%d" % [x, z]] = y
		else:
			if x < 0 or x > 172 or z < 0 or z > 118 or not piece.has("axis") or not _is_number(piece["axis"]):
				return false
			var axis := int(piece["axis"])
			if float(piece["axis"]) != axis or axis not in [0, 1]:
				return false
			if (axis == 0 and (x % 2 != 0 or z % 2 != 1)) or (axis == 1 and (x % 2 != 1 or z % 2 != 0)):
				return false
			var edge_id = "%d:%d:%d" % [axis, x, z]
			identity = ("d:" if kind == "door" else "e:") + edge_id
			if kind != "door": edges[edge_id] = piece
			if kind == "door":
				if not piece.has("hinge") or not _is_number(piece["hinge"]) or float(piece["hinge"]) not in [-1.0, 1.0] or typeof(piece.get("open")) != TYPE_BOOL:
					return false
		if records.has(identity):
			return false
		records[identity] = piece
	# Check structural relationships before loading; never silently discard a
	# malformed base and overwrite its only save with an incomplete structure.
	for piece in value:
		var kind: String = piece["type"]
		var x := int(piece["x"])
		var z := int(piece["z"])
		var y := float(piece["y"])
		if kind == "roof":
			var floor_key = "%d:%d" % [x, z]
			if not foundations.has(floor_key) or absf(float(foundations[floor_key]) - y) > 0.08:
				return false
		elif kind in ["wall", "doorway", "door"]:
			var axis := int(piece["axis"])
			var a := Vector2i(x / 2, (z - 1) / 2) if axis == 0 else Vector2i((x - 1) / 2, z / 2)
			var b := Vector2i(x / 2, (z + 1) / 2) if axis == 0 else Vector2i((x + 1) / 2, z / 2)
			var akey = "%d:%d" % [a.x, a.y]
			var bkey = "%d:%d" % [b.x, b.y]
			var supported = (foundations.has(akey) and absf(float(foundations[akey]) - y) <= 0.08) or (foundations.has(bkey) and absf(float(foundations[bkey]) - y) <= 0.08)
			if not supported:
				return false
			if kind == "door":
				var edge_id = "%d:%d:%d" % [axis, x, z]
				if not edges.has(edge_id) or edges[edge_id].get("type", "") != "doorway" or absf(float(edges[edge_id]["y"]) - y) > 0.08:
					return false
	return true

static func _valid_data(data: Dictionary) -> bool:
	if data.has("buildings") and not _valid_buildings(data["buildings"]):
		return false
	if not data.has("version") or not _is_number(data["version"]) or float(data["version"]) != VERSION:
		return false
	if data.has("island_revision") and (not _is_number(data["island_revision"]) or float(data["island_revision"]) not in [1.0, 2.0]):
		return false
	if data.has("lake_position"):
		var lake = data["lake_position"]
		if not lake is Array or lake.size() != 2 or not _is_number(lake[0]) or not _is_number(lake[1]):
			return false
		if float(lake[0]) < 0.0 or float(lake[0]) > 3200.0 or float(lake[1]) < 0.0 or float(lake[1]) > 2200.0:
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
	for list_name in ["dead_ids", "depleted_resources"]:
		if data.has(list_name):
			var ids = data[list_name]
			if not ids is Array or ids.size() > 20000:
				return false
			for identity in ids:
				if not identity is String or identity.length() > 128:
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
	# Never replace an existing save with state that would fail to load.
	if not _valid_data(data):
		return false
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
	# If the primary is damaged but its backup is valid, the backup is the
	# only recoverable copy. Do not overwrite it with the damaged primary
	# before a replacement succeeds (especially when Windows has it locked).
	var preserve_backup = had_old and not _read(backup).is_empty() and _read(path).is_empty()
	if had_old and not preserve_backup and DirAccess.copy_absolute(old_abs, backup_abs) != OK:
		DirAccess.remove_absolute(tmp_abs)
		return false
	if DirAccess.rename_absolute(tmp_abs, old_abs) != OK:
		if had_old and not FileAccess.file_exists(path):
			DirAccess.copy_absolute(backup_abs, old_abs)
		DirAccess.remove_absolute(tmp_abs)
		return false
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup_abs)
	return true
