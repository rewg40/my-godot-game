extends SceneTree

# The normal save is never read or modified, even if this test is run manually.
const SaveGame = preload("res://scripts/save_game.gd")
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
		["player structure", '{"version":1,"player":[]}'],
		["player health", '{"version":1,"player":{"health":[]}}'],
		["position length", '{"version":1,"player":{"position":[1]}}'],
		["position coordinate", '{"version":1,"player":{"position":["1",2]}}'],
	]
	for sample in damaged_cases:
		write_primary(sample[1])
		check(SaveGame.load_data().is_empty(), "damaged " + sample[0] + " is rejected without backup")
		check(FileAccess.get_file_as_string(SaveGame.TEST_PATH) == sample[1], "rejecting " + sample[0] + " preserves the file")

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

	if OS.get_name() == "Windows":
		# A Windows read handle prevents deleting/renaming the primary file.
		# A failed write must not replace the only good backup with corruption.
		write_primary(damaged)
		var locked = FileAccess.open(SaveGame.TEST_PATH, FileAccess.READ)
		check(locked != null, "primary save can be locked for a failed-write test")
		if locked:
			var saved = SaveGame.save_data({"quest_stage": 5})
			locked.close()
			check(not saved, "a locked primary refuses replacement")
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
	else:
		check(false, "Continue is available for a valid backup")
	check(FileAccess.get_file_as_string(SaveGame.TEST_PATH) == damaged, "opening a backup does not overwrite the damaged primary")
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
