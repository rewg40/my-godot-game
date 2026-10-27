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
	# Place one real infected beside the player for an in-world scale check.
	var offset: Vector3 = world.player.camera_pivot.global_transform.basis.x * 2.8
	var position: Vector3 = world.player.global_position + offset
	var zombie = world.spawn_enemy("preview_zombie", "walker", world.world_to_map(position), "test")
	zombie.set_physics_process(false)
	var toward_camera: Vector3 = world.player.camera.global_position - zombie.global_position
	zombie.visual.rotation.y = atan2(toward_camera.x, toward_camera.z)
	world.player.camera_arm.spring_length = 8.0
	await create_timer(0.5).timeout
	await _capture(out_dir + "/zombie_ingame.png")
	zombie.queue_free()
	world.player.camera_arm.spring_length = 16.0
	world.environment_3d.environment.tonemap_exposure = 0.62
	await create_timer(0.4).timeout
	await _capture(out_dir + "/dark3d.png")
	world.environment_3d.environment.tonemap_exposure = 0.72
	# Briefly make one oversized, bright tuft to verify real MultiMesh drawing.
	var old_transform = grass.multimesh.get_instance_transform(0)
	var check_mat = StandardMaterial3D.new()
	check_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	check_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	check_mat.albedo_color = Color.RED
	grass.material_override = check_mat
	grass.multimesh.set_instance_transform(0, Transform3D(Basis().scaled(Vector3(12, 12, 12)), world.player.global_position + Vector3(2, 0, 0)))
	await create_timer(0.5).timeout
	await _capture(out_dir + "/grasscheck3d.png")
	grass.material_override = null
	grass.multimesh.set_instance_transform(0, old_transform)
	world.player.global_position = world.map_to_world(Vector2(840, 1345)) + Vector3.UP * 0.12
	world.player.velocity = Vector3.ZERO
	await create_timer(1.5).timeout
	await _capture(out_dir + "/camp3d.png")
	var broadleaf = world.environment_3d.get_node("ForestBroadleaf") as Node3D
	var forest_pos = broadleaf.global_position + Vector3(-4, 0, 4)
	forest_pos.y = world.environment_3d.height_at(forest_pos.x, forest_pos.z) + 0.12
	world.player.global_position = forest_pos
	world.player.velocity = Vector3.ZERO
	await create_timer(1.5).timeout
	await _capture(out_dir + "/forest3d.png")
	world.sound.stop()
	main.music.stop()
	main.queue_free()
	await create_timer(0.75).timeout
	quit()
