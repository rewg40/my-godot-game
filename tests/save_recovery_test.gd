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

func _run() -> void:
	# Valid JSON, but the wrong type for a field consumed during world startup.
	var damaged = '{"version":1,"quest_stage":{}}'
	write_primary(damaged)
	check(SaveGame.load_data().is_empty(), "structured corruption without backup is rejected")
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var resume: Button
	for button in main.current_screen.find_children("*", "Button", true, false):
		if button.text == "ПРОДОЛЖИТЬ":
			resume = button
			break
	check(resume != null and not resume.disabled, "damaged save can be selected without deleting it")
	if resume:
		resume.pressed.emit()
		await process_frame
		check(main.current_screen is Control, "Continue reports an unreadable save instead of starting a broken world")
	check(FileAccess.get_file_as_string(SaveGame.TEST_PATH) == damaged, "failed Continue preserves the original save file")
	main.queue_free()
	await create_timer(0.5).timeout

	# A valid backup must be preferred over syntactically valid damaged data.
	var backup = {"quest_stage": 4, "inventory": {"wood": 13}, "player": {"position": [1200, 800]}}
	check(SaveGame.save_data(backup), "recovery fixture can be written")
	var primary_abs = ProjectSettings.globalize_path(SaveGame.TEST_PATH)
	check(DirAccess.copy_absolute(primary_abs, primary_abs + ".bak") == OK, "backup fixture can be created")
	write_primary(damaged)
	var restored = SaveGame.load_data()
	check(restored.get("quest_stage", -1) == 4 and restored.get("inventory", {}).get("wood", -1) == 13, "valid backup is used for structured corruption")
	check(FileAccess.get_file_as_string(SaveGame.TEST_PATH) == damaged, "recovering from a backup does not overwrite the damaged primary file")

	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(primary_abs + suffix)
	await process_frame
	if failures.is_empty():
		print("SAVE RECOVERY TESTS PASSED")
		quit(0)
	else:
		print("SAVE RECOVERY TESTS FAILED: ", failures)
		quit(1)
