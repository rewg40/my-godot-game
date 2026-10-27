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
	var grass = world.environment_3d.get_node("GrassCover") as MultiMeshInstance3D
	var nearby = 0
	for i in range(grass.multimesh.instance_count):
		if grass.multimesh.get_instance_transform(i).origin.distance_to(world.player.global_position) < 10.0:
			nearby += 1
	var first_material = grass.multimesh.mesh.surface_get_material(0)
	print("GRASS_REPORT instances=", grass.multimesh.instance_count, " nearby=", nearby,
		" mesh_aabb=", grass.multimesh.mesh.get_aabb(), " combined_aabb=", grass.get_aabb(),
		" material=", first_material.resource_name if first_material else "none")
	await _capture(out_dir + "/beach3d.png")
	world.environment_3d.environment.tonemap_exposure = 0.62
	await create_timer(0.4).timeout
	await _capture(out_dir + "/dark3d.png")
	world.environment_3d.environment.tonemap_exposure = 1.0
	world.player.global_position = world.map_to_world(Vector2(840, 1345)) + Vector3.UP * 0.12
	world.player.velocity = Vector3.ZERO
	await create_timer(1.5).timeout
	await _capture(out_dir + "/camp3d.png")
	world.player.global_position = world.map_to_world(Vector2(1560, 610)) + Vector3.UP * 0.12
	world.player.velocity = Vector3.ZERO
	await create_timer(1.5).timeout
	await _capture(out_dir + "/forest3d.png")
	world.sound.stop()
	main.music.stop()
	main.queue_free()
	await create_timer(0.75).timeout
	quit()
