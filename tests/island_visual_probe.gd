extends SceneTree

# Temporary diagnostic: inspect the actual GL Compatibility renderer, not a
# synthetic rendering of the GLB. Removed after the island has been checked.
const World = preload("res://scripts/world.gd")

func _initialize() -> void:
	OS.set_environment("SHARDS_TEST_SAVE", "1")
	_run.call_deferred()

func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(path) != OK:
		push_error("Could not capture island preview: " + path)

func _run() -> void:
	var out = OS.get_environment("SHARDS_PREVIEW_DIR")
	var world = World.new()
	root.add_child(world)
	await process_frame
	world.hud.close_modal()
	world.player.set_physics_process(false)
	for enemy in world.enemies:
		enemy.set_physics_process(false)
	await create_timer(0.6).timeout
	await _capture(out + "/island_spawn.png")
	var camera = Camera3D.new()
	world.add_child(camera)
	camera.far = 400.0
	camera.fov = 42.0
	camera.position = Vector3(147, 152, 154)
	camera.look_at(Vector3(64, 2, 44))
	camera.make_current()
	world.hud.visible = false
	await create_timer(0.6).timeout
	await _capture(out + "/island_overview.png")
	camera.position = Vector3(51, 29, 10)
	camera.look_at(Vector3(71, 6, 28))
	await create_timer(0.3).timeout
	await _capture(out + "/island_structures.png")
	world.player.global_position = world.map_to_world(world.CAMP) + Vector3.UP * 0.12
	world.player.camera.make_current()
	world.hud.visible = true
	await create_timer(0.5).timeout
	await _capture(out + "/island_camp.png")
	world.queue_free()
	await create_timer(0.5).timeout
	quit()
