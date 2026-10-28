extends RefCounted

# The enlarged island keeps the old 0..3200 / 0..2200 map coordinates, but
# doubles physical metres. Old buildings cannot be scaled: a 3 m foundation
# must stay 3 m wide. Translate each connected base as a unit instead, keeping
# wall edges, door hinges, shape, resources and relative player position.
const OLD_MAP_SCALE := 0.04
const NEW_MAP_SCALE := 0.08
const CELL := 3.0
const CURRENT_REVISION := 2

static func migrate(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	if int(result.get("island_revision", 1)) >= CURRENT_REVISION:
		return result
	var records = result.get("buildings", [])
	if not records is Array:
		return result
	var pending := {}
	for record in records:
		if record is Dictionary and record.get("type", "") == "foundation":
			pending[Vector2i(int(record["x"]), int(record["z"]))] = true
	var offsets := {}
	while not pending.is_empty():
		var anchor: Vector2i = pending.keys()[0]
		var queue: Array[Vector2i] = [anchor]
		pending.erase(anchor)
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back()
			offsets[cell] = anchor
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var neighbor: Vector2i = cell + step
				if pending.has(neighbor):
					pending.erase(neighbor)
					queue.append(neighbor)
	# Preserve a player standing on one of the old floors relative to their
	# base; everyone else keeps their old normalized island/map position.
	var player = result.get("player", {})
	if player is Dictionary and player.get("position", []) is Array and player["position"].size() == 2:
		var old_position := Vector2(float(player["position"][0]), float(player["position"][1])) * OLD_MAP_SCALE
		var old_cell := Vector2i(roundi(old_position.x / CELL), roundi(old_position.y / CELL))
		if offsets.has(old_cell) and absf(old_position.x - float(old_cell.x) * CELL) <= CELL * 0.5 and absf(old_position.y - float(old_cell.y) * CELL) <= CELL * 0.5:
			var offset: Vector2i = offsets[old_cell]
			var new_position := (old_position + Vector2(offset) * CELL) / NEW_MAP_SCALE
			player["position"] = [new_position.x, new_position.y]
	for record in records:
		if not record is Dictionary:
			continue
		var kind: String = record.get("type", "")
		var x := int(record.get("x", 0))
		var z := int(record.get("z", 0))
		var support := Vector2i(x, z)
		if kind in ["wall", "doorway", "door"]:
			if int(record.get("axis", 0)) == 0:
				support = Vector2i(x / 2, (z - 1) / 2)
				if not offsets.has(support): support = Vector2i(x / 2, (z + 1) / 2)
			else:
				support = Vector2i((x - 1) / 2, z / 2)
				if not offsets.has(support): support = Vector2i((x + 1) / 2, z / 2)
		if not offsets.has(support):
			continue
		var delta: Vector2i = offsets[support]
		var multiplier := 1 if kind in ["foundation", "roof"] else 2
		record["x"] = x + delta.x * multiplier
		record["z"] = z + delta.y * multiplier
		record["y"] = float(record["y"]) * 2.0
	result["island_revision"] = CURRENT_REVISION
	return result
