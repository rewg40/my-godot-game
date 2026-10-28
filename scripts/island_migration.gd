extends RefCounted

# The enlarged island keeps the old 0..3200 / 0..2200 map coordinates, but
# doubles physical metres. Old buildings cannot be scaled: a 3 m foundation
# must stay 3 m wide. Translate each connected base as a unit instead, keeping
# wall edges, door hinges, shape, resources and relative player position.
const SaveGame = preload("res://scripts/save_game.gd")
const OLD_MAP_SCALE := 0.04
const NEW_MAP_SCALE := 0.08
const CELL := 3.0
const CURRENT_REVISION := 2

static func _support_cell(record: Dictionary, cell_groups: Dictionary) -> Vector2i:
	var x := int(record.get("x", 0))
	var z := int(record.get("z", 0))
	if record.get("type", "") in ["foundation", "roof"]:
		return Vector2i(x, z)
	var a := Vector2i(x / 2, (z - 1) / 2) if int(record.get("axis", 0)) == 0 else Vector2i((x - 1) / 2, z / 2)
	var b := Vector2i(x / 2, (z + 1) / 2) if int(record.get("axis", 0)) == 0 else Vector2i((x + 1) / 2, z / 2)
	return a if cell_groups.has(a) else b

static func _edge_key(record: Dictionary, offset: Vector2i) -> String:
	return "%d:%d:%d" % [int(record["axis"]), int(record["x"]) + offset.x * 2, int(record["z"]) + offset.y * 2]

static func _fits(cells: Array, records: Array, offset: Vector2i, occupied: Dictionary, occupied_edges: Dictionary, keep_gap: bool) -> bool:
	for old_cell in cells:
		var cell: Vector2i = old_cell + offset
		if cell.x < 0 or cell.x > 86 or cell.y < 0 or cell.y > 59:
			return false
		if occupied.has(cell):
			return false
		if keep_gap:
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if occupied.has(cell + step):
					return false
	# The edge grid extends twice as far as the foundation grid. Check all
	# boundaries here as a wall just beyond a floor can reach the edge.
	for record in records:
		var multiplier := 1 if record.get("type", "") in ["foundation", "roof"] else 2
		var x := int(record["x"]) + offset.x * multiplier
		var z := int(record["z"]) + offset.y * multiplier
		if x < 0 or z < 0 or x > (86 if multiplier == 1 else 172) or z > (59 if multiplier == 1 else 118):
			return false
		if multiplier == 2 and occupied_edges.has(_edge_key(record, offset)):
			return false
	return true

static func _find_offset(cells: Array, records: Array, desired: Vector2i, occupied: Dictionary, occupied_edges: Dictionary, keep_gap: bool) -> Vector2i:
	# Try the geographically closest position first. Expand outwards only when
	# another disconnected base would overlap it after the island doubled.
	if _fits(cells, records, desired, occupied, occupied_edges, keep_gap):
		return desired
	for radius in range(1, 176):
		# Visit each square perimeter without repeatedly scanning its interior.
		for n in range(-radius, radius + 1):
			for step in [Vector2i(n, -radius), Vector2i(n, radius), Vector2i(-radius, n), Vector2i(radius, n)]:
				var candidate: Vector2i = desired + step
				if _fits(cells, records, candidate, occupied, occupied_edges, keep_gap):
					return candidate
	return Vector2i(-1000, -1000)

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
	var groups: Array = []
	var cell_groups := {}
	while not pending.is_empty():
		var anchor: Vector2i = pending.keys()[0]
		var queue: Array[Vector2i] = [anchor]
		var cells: Array[Vector2i] = []
		pending.erase(anchor)
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back()
			cell_groups[cell] = groups.size()
			cells.append(cell)
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var neighbor: Vector2i = cell + step
				if pending.has(neighbor):
					pending.erase(neighbor)
					queue.append(neighbor)
		groups.append({"anchor": anchor, "cells": cells, "records": []})
	for record in records:
		if record is Dictionary:
			var support := _support_cell(record, cell_groups)
			if cell_groups.has(support):
				groups[int(cell_groups[support])]["records"].append(record)
	var offsets := {}
	var occupied := {}
	var occupied_edges := {}
	for group in groups:
		var offset := _find_offset(group.cells, group.records, group.anchor, occupied, occupied_edges, true)
		if offset.x == -1000:
			# A dense legacy settlement can use touching floors, but never
			# overlapping floors or duplicate wall/door grid coordinates.
			offset = _find_offset(group.cells, group.records, group.anchor, occupied, occupied_edges, false)
		if offset.x == -1000:
			# Do not silently drop a base if no valid translation exists.
			return source.duplicate(true)
		for cell in group.cells:
			offsets[cell] = offset
			occupied[cell + offset] = true
		for record in group.records:
			if record.get("type", "") not in ["foundation", "roof"]:
				occupied_edges[_edge_key(record, offset)] = true
	# Preserve a player standing on one of the old floors relative to their
	# base; everyone else keeps their old normalized island/map position.
	var player = result.get("player", {})
	var player_position = player.get("position", []) if player is Dictionary else []
	if player is Dictionary and player_position is Array and player_position.size() == 2:
		var old_position := Vector2(float(player_position[0]), float(player_position[1])) * OLD_MAP_SCALE
		var old_cell := Vector2i(roundi(old_position.x / CELL), roundi(old_position.y / CELL))
		if offsets.has(old_cell) and absf(old_position.x - float(old_cell.x) * CELL) <= CELL * 0.5 and absf(old_position.y - float(old_cell.y) * CELL) <= CELL * 0.5:
			var offset: Vector2i = offsets[old_cell]
			var new_position := (old_position + Vector2(offset) * CELL) / NEW_MAP_SCALE
			player["position"] = [new_position.x, new_position.y]
	for record in records:
		if not record is Dictionary:
			continue
		var support := _support_cell(record, offsets)
		if not offsets.has(support):
			continue
		var delta: Vector2i = offsets[support]
		var multiplier := 1 if record.get("type", "") in ["foundation", "roof"] else 2
		record["x"] = int(record["x"]) + delta.x * multiplier
		record["z"] = int(record["z"]) + delta.y * multiplier
		record["y"] = float(record["y"]) * 2.0
	result["island_revision"] = CURRENT_REVISION
	# A legacy save can contain unusual (but valid) heights. If the scaled
	# result fails validation, keep every original record instead of letting a
	# later save silently replace it with an incomplete structure.
	return result if SaveGame._valid_data(result) else source.duplicate(true)
