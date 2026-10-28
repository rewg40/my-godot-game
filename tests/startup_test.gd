extends SceneTree

var failed := false

func _initialize() -> void:
	# This test must never read or overwrite a player's normal save.
	OS.set_environment("SHARDS_TEST_SAVE", "1")
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failed = true
		push_error("FAIL: " + message)

func _run() -> void:
	var main_path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	_check(main_path == "res://scenes/main.tscn", "project has its main scene configured")
	var packed := load(main_path) as PackedScene
	if packed == null:
		push_error("Main scene could not be loaded")
		quit(1)
		return
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	_check(is_instance_valid(main.current_screen), "main menu opens")
	var found_start := false
	if is_instance_valid(main.current_screen):
		for button in main.current_screen.find_children("*", "Button", true, false):
			if button.text == "НОВАЯ ИГРА":
				found_start = true
				break
	_check(found_start, "main menu has the New Game button")
	_check(is_instance_valid(main.music) and main.music.stream != null, "menu music is available")
	# Let the window and audio initialize, then exercise normal scene cleanup.
	await create_timer(0.5).timeout
	main.queue_free()
	await create_timer(0.75).timeout
	await process_frame
	_check(not is_instance_valid(main), "main scene closes cleanly")
	if failed:
		quit(1)
	else:
		print("MAIN MENU STARTUP PASSED")
		quit(0)
