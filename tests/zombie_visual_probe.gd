extends SceneTree

# Temporary real-renderer check of the user-supplied zombie in three poses.
const ActorVisual = preload("res://scripts/model_3d.gd")

func _initialize() -> void:
	_run.call_deferred()

func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(path) != OK:
		push_error("Could not capture zombie viewport: " + path)

func _run() -> void:
	var out := OS.get_environment("SHARDS_PREVIEW_DIR")
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("383d39")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c6d0c4")
	settings.ambient_light_energy = 0.6
	environment.environment = settings
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.0
	stage.add_child(sun)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("62665d")
	floor.material_override = floor_material
	stage.add_child(floor)
	var visual := ActorVisual.new()
	stage.add_child(visual)
	visual.setup("res://assets/models/zombie/user_zombie.glb", 0.55)
	var camera := Camera3D.new()
	camera.position = Vector3(1.8, 1.8, 4.7)
	camera.fov = 29.0
	stage.add_child(camera)
	camera.look_at(Vector3(0, 0.9, 0))
	camera.current = true
	await create_timer(0.5).timeout
	visual.play("Idle")
	visual.animation.seek(0.5, true)
	await _capture(out + "/zombie_idle.png")
	visual.play("Walk")
	visual.animation.advance(0.2)
	visual.animation.seek(0.275, true)
	await process_frame
	await _capture(out + "/zombie_walk.png")
	visual.play("Punch")
	visual.animation.advance(0.2)
	visual.animation.seek(0.15, true)
	await process_frame
	await _capture(out + "/zombie_attack.png")
	stage.queue_free()
	await create_timer(0.5).timeout
	quit()
