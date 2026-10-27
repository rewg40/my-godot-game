extends SceneTree

const WorldScript = preload("res://scripts/world.gd")

func _initialize() -> void:
	OS.set_environment("SHARDS_TEST_SAVE", "1")
	_run.call_deferred()

func _run() -> void:
	var mode = "hero"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			mode = arg.trim_prefix("--view=")
	var world = WorldScript.new()
	root.add_child(world)
	await process_frame
	world.hud.visible = false
	world.player.set_physics_process(false)
	world.flags["club"] = true
	world.equipped_weapon = "club"
	world.player._update_weapon()
	world.player.visual.rotation.y = 0.0
	world.player.visual.play("Idle")
	var camera = Camera3D.new()
	camera.name = "VisualProbeCamera"
	root.add_child(camera)
	camera.far = 500.0
	if mode == "hero":
		var pos = world.player.global_position
		camera.position = pos + Vector3(2.6, 2.15, 4.5)
		camera.fov = 32.0
		camera.look_at(pos + Vector3(0.0, 1.02, 0.0), Vector3.UP)
	elif mode == "camp":
		var target: Vector3 = world.map_to_world(world.CAMP)
		camera.position = target + Vector3(8, 10, 14)
		camera.fov = 52.0
		camera.look_at(target + Vector3.UP, Vector3.UP)
	else:
		camera.position = Vector3(64, 75, 135)
		camera.fov = 55.0
		camera.look_at(Vector3(64, 0, 44), Vector3.UP)
	camera.make_current()
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	image.resize(640, 360, Image.INTERPOLATE_LANCZOS)
	var encoded = Marshalls.raw_to_base64(image.save_jpg_to_buffer(0.40))
	print("JPEG:" + encoded)
	world.queue_free()
	camera.queue_free()
	await process_frame
	quit()
