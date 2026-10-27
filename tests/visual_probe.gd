extends SceneTree

# Temporary diagnostic: capture the real 3D renderer in a virtual display.
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
	main.start_game(false)
	await process_frame
	var world = main.current_screen
	world.hud.close_modal()
	await create_timer(1.5).timeout
	await _capture(out_dir + "/beach3d.png")
	world.player.global_position = world.map_to_world(Vector2(840, 1345)) + Vector3.UP * 0.12
	world.player.velocity = Vector3.ZERO
	await create_timer(1.5).timeout
	await _capture(out_dir + "/camp3d.png")
	world.sound.stop()
	main.music.stop()
	main.queue_free()
	await create_timer(0.75).timeout
	quit()
