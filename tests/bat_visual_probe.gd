extends SceneTree

# Temporary diagnostic for weapon alignment in the actual Godot renderer.
const Player = preload("res://scripts/player.gd")

class PreviewWorld extends Node3D:
	var flags = {"club": true}
	func is_paused() -> bool:
		return false

func _initialize() -> void:
	_run.call_deferred()

func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(path) != OK:
		push_error("Could not capture bat preview: " + path)

func _run() -> void:
	var out := OS.get_environment("SHARDS_PREVIEW_DIR")
	var stage := PreviewWorld.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("383d39")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c6d0c4")
	settings.ambient_light_energy = 0.6
	env.environment = settings
	stage.add_child(env)
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
	var player := Player.new()
	player.world = stage
	stage.add_child(player)
	player.set_physics_process(false)
	player.visual.rotation.y = 0.0
	player._update_weapon()
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(-1.5, 1.5, 3.2)
	camera.fov = 34.0
	camera.look_at(Vector3(-0.08, 0.95, 0.0))
	camera.current = true
	await create_timer(0.4).timeout
	player.visual.animation.pause()
	await _capture(out + "/bat_idle.png")
	# Close-up of the actual grip, then restore the full-body view.
	var old_transform := camera.transform
	var old_fov := camera.fov
	camera.position = Vector3(-0.9, 1.18, 1.35)
	camera.fov = 25.0
	camera.look_at(player.weapon_root.global_position + Vector3(0, 0.08, 0))
	await _capture(out + "/bat_close.png")
	player.weapon_grip.active = false
	player.visual.animation.seek(0.4, true)
	await create_timer(0.15).timeout
	await _capture(out + "/bat_no_modifier.png")
	player.weapon_grip.active = true
	player.visual.animation.seek(0.4, true)
	await process_frame
	camera.transform = old_transform
	camera.fov = old_fov
	player.visual.play("SwordSlash", 1.0, 0.0)
	player.visual.animation.seek(0.20, true)
	player.visual.animation.pause()
	await process_frame
	await _capture(out + "/bat_windup.png")
	player.visual.animation.play("SwordSlash", 0.0)
	player.visual.animation.seek(0.40, true)
	player.visual.animation.pause()
	await process_frame
	await _capture(out + "/bat_impact.png")
	stage.queue_free()
	await create_timer(0.5).timeout
	quit()
