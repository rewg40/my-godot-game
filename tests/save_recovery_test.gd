extends SceneTree

# The normal save is never read or modified, even if this test is run manually.
const SaveGame = preload("res://scripts/save_game.gd")
const IslandMigration = preload("res://scripts/island_migration.gd")
var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("SHARDS_TEST_SAVE", "1")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.TEST_PATH + suffix))
	create_timer(60.0).timeout.connect(func():
		push_error("Save recovery test timed out")
		quit(1)
	)
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)

func write_primary(text: String) -> void:
	var file := FileAccess.open(SaveGame.TEST_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func find_button(parent: Node, text: String) -> Button:
	for button in parent.find_children("*", "Button", true, false):
		if button.text == text:
			return button
	return null

func _run() -> void:
	# These are valid JSON but have wrong types or unsafe numeric values.
	var damaged_cases = [
		["version object", '{"version":{}}'],
		["fractional version", '{"version":1.5}'],
		["quest stage object", '{"version":1,"quest_stage":{}}'],
		["day array", '{"version":1,"day":[]}'],
		["huge number", '{"version":1,"minute":1e999}'],
		["inventory structure", '{"version":1,"inventory":[]}'],
		["inventory value", '{"version":1,"inventory":{"wood":[]}}'],
		["flag value", '{"version":1,"flags":{"club":{}}}'],
		["weapon type", '{"version":1,"equipped_weapon":[]}'],
		["tower count", '{"version":1,"towers":[true,false]}'],
		["tower value", '{"version":1,"towers":[true,false,{}]}'],
		["dead enemy id", '{"version":1,"dead_ids":[123]}'],
		["destroyed resource id", '{"version":1,"depleted_resources":[{}]}'],
		["lake coordinate", '{"version":1,"lake_position":[[],123]}'],
		["waypoint bounds", '{"version":1,"waypoint":[99999,123]}'],
		["island revision", '{"version":1,"island_revision":{}}'],
		["player structure", '{"version":1,"player":[]}'],
		["player health", '{"version":1,"player":{"health":[]}}'],
		["position length", '{"version":1,"player":{"position":[1]}}'],
		["position coordinate", '{"version":1,"player":{"position":["1",2]}}'],
		["building collection", '{"version":1,"buildings":{}}'],
		["building record", '{"version":1,"buildings":[42]}'],
		["building kind", '{"version":1,"buildings":[{"type":"tower","x":10,"z":10,"y":1}]}'],
		["building coordinate type", '{"version":1,"buildings":[{"type":"foundation","x":{},"z":10,"y":1}]}'],
		["building coordinate bounds", '{"version":1,"buildings":[{"type":"foundation","x":999,"z":10,"y":1}]}'],
		["building coordinate fraction", '{"version":1,"buildings":[{"type":"foundation","x":10.5,"z":10,"y":1}]}'],
		["duplicate foundation", '{"version":1,"buildings":[{"type":"foundation","x":10,"z":10,"y":1},{"type":"foundation","x":10,"z":10,"y":1}]}'],
		["unsupported roof", '{"version":1,"buildings":[{"type":"roof","x":10,"z":10,"y":1}]}'],
		["unsupported wall", '{"version":1,"buildings":[{"type":"wall","x":20,"z":19,"y":1,"axis":0}]}'],
		["bad edge grid", '{"version":1,"buildings":[{"type":"foundation","x":10,"z":10,"y":1},{"type":"wall","x":20,"z":20,"y":1,"axis":0}]}'],
		["wall height mismatch", '{"version":1,"buildings":[{"type":"foundation","x":10,"z":10,"y":1},{"type":"wall","x":20,"z":19,"y":3,"axis":0}]}'],
		["door without doorway", '{"version":1,"buildings":[{"type":"foundation","x":10,"z":10,"y":1},{"type":"door","x":20,"z":19,"y":1,"axis":0,"hinge":1,"open":false}]}'],
		["invalid door hinge", '{"version":1,"buildings":[{"type":"door","x":20,"z":19,"y":1,"axis":0,"hinge":0,"open":false}]}'],
		["invalid door state", '{"version":1,"buildings":[{"type":"door","x":20,"z":19,"y":1,"axis":0,"hinge":1,"open":"open"}]}'],
	]
	for sample in damaged_cases:
		write_primary(sample[1])
		check(SaveGame.load_data().is_empty(), "damaged " + sample[0] + " is rejected without backup")
		check(FileAccess.get_file_as_string(SaveGame.TEST_PATH) == sample[1], "rejecting " + sample[0] + " preserves the file")

	# Buildings from the smaller island retain their 3 m module spacing, the
	# complete structure and the player's position relative to the same floor.
	var old_base = {"version": 1, "buildings": [
		{"type":"foundation", "x":10, "z":10, "y":1.2},
		{"type":"foundation", "x":11, "z":10, "y":1.2},
		{"type":"foundation", "x":20, "z":12, "y":1.5},
		{"type":"roof", "x":10, "z":10, "y":1.2},
		{"type":"doorway", "x":20, "z":19, "y":1.2, "axis":0},
		{"type":"door", "x":20, "z":19, "y":1.2, "axis":0, "hinge":1, "open":true},
	], "player":{"position":[780, 750]}, "inventory":{"wood":7}}
	var enlarged: Dictionary = IslandMigration.migrate(old_base)
	var pieces: Array = enlarged["buildings"]
	check(SaveGame._valid_data(enlarged) and pieces[0].x == 20 and pieces[1].x == 21 and pieces[2].x == 40, "old connected and separate bases migrate without stretching their modules")
	check(pieces[3].x == 20 and pieces[4].x == 40 and pieces[5].x == 40 and bool(pieces[5].open) and is_equal_approx(pieces[0].y, 2.4), "roof, door and floor migrate together with height and state")
	check(is_equal_approx(float(enlarged.player.position[0]), 765.0) and IslandMigration.migrate(enlarged) == enlarged, "player stays relative to the base and migration runs only once")

	# A detached hut inside a larger compound used to land on top of the
	# compound when each base was moved independently. Keep both intact and
	# move a player standing inside the hut with it.
	var ring: Array = []
	for x in range(10, 15):
		for z in range(10, 15):
			if x in [10, 14] or z in [10, 14]:
				ring.append({"type":"foundation", "x":x, "z":z, "y":1.0})
	ring.append({"type":"foundation", "x":12, "z":12, "y":1.0})
	ring.append({"type":"roof", "x":12, "z":12, "y":1.0})
	ring.append({"type":"doorway", "x":24, "z":23, "y":1.0, "axis":0})
	ring.append({"type":"door", "x":24, "z":23, "y":1.0, "axis":0, "hinge":1, "open":true})
	var compound = {"version":1, "buildings":ring, "player":{"position":[900, 900]}}
	var expanded_compound: Dictionary = IslandMigration.migrate(compound)
	var expanded_pieces: Array = expanded_compound.buildings
	var hut: Dictionary = expanded_pieces[16]
	var unique_floors := {}
	for piece in expanded_pieces:
		if piece.type == "foundation":
			unique_floors["%d:%d" % [int(piece.x), int(piece.z)]] = true
	check(SaveGame._valid_data(compound) and SaveGame._valid_data(expanded_compound) and expanded_pieces.size() == ring.size() and unique_floors.size() == 17, "nested separate bases migrate without overlapping or losing pieces")
	check(bool(expanded_pieces[19].open) and is_equal_approx(float(expanded_compound.player.position[0]), float(hut.x) * 3.0 / 0.08) and is_equal_approx(float(expanded_compound.player.position[1]), float(hut.z) * 3.0 / 0.08), "player, roof and open door stay with the relocated detached hut")
	var unusual = {"version":1, "buildings":[{"type":"foundation", "x":10, "z":10, "y":1.2}, {"type":"roof", "x":10, "z":10, "y":1.25}]}
	check(SaveGame._valid_data(unusual) and IslandMigration.migrate(unusual) == unusual, "unusual legacy heights are preserved if scaling cannot produce a valid save")

	# The removed towers are refunded once, and the obsolete Tim objective is
	# advanced without resetting any other legacy progress.
	var legacy = load("res://scripts/world.gd").new()
	legacy._apply_save({"quest_stage": 8, "inventory": {"wood": 7, "stone": 4}, "towers": [true, false, true]})
	check(legacy.quest_stage == 9 and legacy.count("wood") == 27 and legacy.count("stone") == 14, "old towers refund their materials and the removed NPC quest advances")
	var migrated = load("res://scripts/world.gd").new()
	migrated._apply_save({"quest_stage": legacy.quest_stage, "inventory": legacy.inventory.duplicate(), "towers": [true, false, true], "buildings": []})
	check(migrated.quest_stage == 9 and migrated.count("wood") == 27 and migrated.count("stone") == 14, "a save in the new format cannot refund legacy towers twice")
	legacy.free()
	migrated.free()

	# Exercise the user's Continue button, not just the save parser.
	var damaged: String = damaged_cases[2][1]
	write_primary(damaged)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var resume = find_button(main.current_screen, "ПРОДОЛЖИТЬ")
	check(resume != null and not resume.disabled, "damaged save can be selected without deleting it")
	if resume:
		resume.pressed.emit()
		await process_frame
		check(main.current_screen is Control, "Continue reports an unreadable save instead of starting a broken world")
		if main.current_screen is Control:
			var found_warning := false
			for label in main.current_screen.find_children("*", "Label", true, false):
				if "Файл не изменён" in label.text:
					found_warning = true
			check(found_warning, "menu explains that the unreadable save was not changed")
	check(FileAccess.get_file_as_string(SaveGame.TEST_PATH) == damaged, "failed Continue preserves the original save file")
	main.queue_free()
	await create_timer(0.5).timeout

	# A valid older-style backup must be preferred over each damaged primary.
	# In particular, older saves do not contain the equipped_weapon field.
	var backup = {"quest_stage": 4, "inventory": {"wood": 13}, "player": {"position": [1200, 800]}}
	check(SaveGame.save_data(backup), "older save fixture can be written")
	var primary_abs = ProjectSettings.globalize_path(SaveGame.TEST_PATH)
	check(DirAccess.copy_absolute(primary_abs, primary_abs + ".bak") == OK, "backup fixture can be created")
	for sample in damaged_cases:
		write_primary(sample[1])
		var restored = SaveGame.load_data()
		var quest = restored.get("quest_stage", -1)
		var inventory = restored.get("inventory", {})
		check(typeof(quest) in [TYPE_INT, TYPE_FLOAT] and int(quest) == 4 and inventory is Dictionary and inventory.get("wood", -1) == 13, "valid backup is used for damaged " + sample[0])
		check(FileAccess.get_file_as_string(SaveGame.TEST_PATH) == sample[1], "backup recovery leaves damaged " + sample[0] + " untouched")

	write_primary(damaged)
	check(not SaveGame.save_data({"quest_stage": []}), "invalid new state is not written over an existing save")
	check(FileAccess.get_file_as_string(SaveGame.TEST_PATH) == damaged, "rejecting a bad write preserves the primary")
	var safe_backup = SaveGame.load_data()
	var safe_quest = safe_backup.get("quest_stage", -1)
	check(typeof(safe_quest) in [TYPE_INT, TYPE_FLOAT] and int(safe_quest) == 4, "rejecting a bad write preserves the backup")

	if OS.get_name() == "Windows":
		# A Windows read handle prevents deleting/renaming the primary file.
		# A failed write must not replace the only good backup with corruption.
		var locked = FileAccess.open(SaveGame.TEST_PATH, FileAccess.READ)
		check(locked != null, "primary save can be locked for a failed-write test")
		if locked:
			var saved = SaveGame.save_data({"quest_stage": 5})
			locked.close()
			check(not saved, "a locked primary refuses replacement")
			check(not FileAccess.file_exists(SaveGame.TEST_PATH + ".tmp"), "failed replacement cleans up the temporary file")
			var recovered = SaveGame.load_data()
			var quest = recovered.get("quest_stage", -1)
			check(typeof(quest) in [TYPE_INT, TYPE_FLOAT] and int(quest) == 4, "a failed save preserves the good recovery backup")

	write_primary(damaged)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	resume = find_button(main.current_screen, "ПРОДОЛЖИТЬ")
	if resume:
		resume.pressed.emit()
		await process_frame
		var world = main.current_screen
		check(world is Node3D and world.quest_stage == 4 and world.count("wood") == 13, "Continue starts the world with the recovered backup")
		check(FileAccess.get_file_as_string(SaveGame.TEST_PATH) == damaged, "opening a backup does not overwrite the damaged primary")
		if world is Node3D:
			check(world.save_progress(false), "a recovered game can be saved successfully")
			var saved_again = SaveGame.load_data()
			var saved_quest = saved_again.get("quest_stage", -1)
			var saved_inventory = saved_again.get("inventory", {})
			check(typeof(saved_quest) in [TYPE_INT, TYPE_FLOAT] and int(saved_quest) == 4 and saved_inventory is Dictionary and saved_inventory.get("wood", -1) == 13, "saving after recovery keeps the recovered progress")
			check(not FileAccess.file_exists(SaveGame.TEST_PATH + ".bak"), "backup is removed only after a successful replacement")
	else:
		check(false, "Continue is available for a valid backup")
	main.queue_free()
	await create_timer(0.5).timeout

	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(primary_abs + suffix)
	await process_frame
	if failures.is_empty():
		print("SAVE RECOVERY TESTS PASSED")
		quit(0)
	else:
		print("SAVE RECOVERY TESTS FAILED: ", failures)
		quit(1)
