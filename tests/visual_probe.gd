extends SceneTree

# Temporary visual diagnostic; rendered by Godot under a virtual X display.
func _initialize() -> void:
	OS.set_environment("SHARDS_TEST_SAVE", "1")
	_run.call_deferred()

func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(path) != OK:
		push_error("Could not capture rendered viewport: " + path)

func _run() -> void:
	var out_dir := OS.get_environment("SHARDS_PREVIEW_DIR")
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.5).timeout
	await _capture(out_dir + "/menu.png")
	main.start_game(false)
	await process_frame
	var world = main.current_screen
	world.hud.close_modal()
	world.player.global_position = Vector2(830, 1330)
	for child in world.player.get_children():
		if child is Camera2D:
			child.reset_smoothing()
	await create_timer(0.75).timeout
	await _capture(out_dir + "/world.png")
	world.hud.show_map()
	await create_timer(0.25).timeout
	await _capture(out_dir + "/map.png")
	world.sound.stop()
	main.music.stop()
	main.queue_free()
	await create_timer(0.75).timeout
	quit()
