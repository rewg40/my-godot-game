extends SceneTree

# Run after import: godot --headless --path . --script res://tests/airfield_site_test.gd
# The walkthrough never reads or writes the player's ordinary save.
const MeshCleanup = preload("res://scripts/mesh_cleanup.gd")
const SaveGame = preload("res://scripts/save_game.gd")

var failures: Array[String] = []
var watchdog: Timer

func _initialize() -> void:
	OS.set_environment("SHARDS_TEST_SAVE", "1")
	watchdog = Timer.new()
	watchdog.one_shot = true
	watchdog.autostart = true
	watchdog.wait_time = 180.0
	watchdog.timeout.connect(_on_timeout)
	root.add_child(watchdog)
	_run.call_deferred()

func _on_timeout() -> void:
	push_error("Airfield site test timed out")
	quit(1)

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)

func ray_hit(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return not root.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func capsule_passes(from: Vector3, to: Vector3) -> bool:
	var actor := CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.75
	collider.shape = capsule
	collider.position.y = 0.88
	actor.add_child(collider)
	actor.position = from
	root.add_child(actor)
	await physics_frame
	var hit := actor.move_and_collide(to - from)
	actor.free()
	return hit == null

func find_button(parent: Node, text: String) -> Button:
	for node in parent.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			return node as Button
	return null

func file_bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()

func _run() -> void:
	var packed := load("res://scenes/airfield_full.tscn") as PackedScene
	check(packed != null, "editable airfield scene loads")
	if packed == null:
		quit(1)
		return
	var field := packed.instantiate() as Node3D
	root.add_child(field)
	await physics_frame
	await physics_frame
	var ground := field.get_node_or_null("Ground/GrassTerrain") as MeshInstance3D
	var runway := field.get_node_or_null("Ground/Runway") as MeshInstance3D
	check(ground != null and ground.mesh is PlaneMesh and (ground.mesh as PlaneMesh).size == Vector2(900, 350), "site is 900 x 350 metres")
	check(runway != null and runway.mesh is PlaneMesh and (runway.mesh as PlaneMesh).size == Vector2(700, 28), "runway is 700 x 28 metres")
	check(get_nodes_in_group("standalone_airfield").has(field), "scene is explicitly standalone")
	for name in ["HangarLarge", "HangarSmall", "ServiceBuilding", "ControlTower", "FuelStation", "GateWest", "GateEast"]:
		var structure := field.get_node_or_null("Structures/" + name)
		check(structure != null and not structure.find_children("*", "CollisionShape3D", true, false).is_empty(), "structure has collision: " + name)
	check(get_nodes_in_group("airfield_infected_marker").size() == 15, "15 invisible infected spawn markers")
	check(get_nodes_in_group("airfield_loot_marker").size() == 8, "8 invisible loot markers")
	check(get_nodes_in_group("airfield_story_marker").size() == 2, "2 invisible story-item markers")
	check(ray_hit(Vector3(0, 4, -54), Vector3(0, -2, -54)), "runway has physical ground")
	check(ray_hit(Vector3(-118, 3, 65), Vector3(-118, -2, 65)), "large hangar has a walkable floor")
	check(ray_hit(Vector3(-50, 3, 65), Vector3(-50, -2, 65)), "small hangar has a walkable floor")
	check(not ray_hit(Vector3(-118, 1.2, 47), Vector3(-118, 1.2, 54)), "large hangar opening is clear in the assembled site")
	check(not ray_hit(Vector3(-50, 1.2, 52), Vector3(-50, 1.2, 58)), "small hangar opening is clear in the assembled site")
	check(not ray_hit(Vector3(14, 1.2, 68), Vector3(14, 1.2, 72)), "service-building opening is clear")
	check(not ray_hit(Vector3(12, 1.2, 75), Vector3(8, 1.2, 75)), "service-building internal doorway is clear")
	check(not ray_hit(Vector3(48.8, 1.2, 68), Vector3(48.8, 1.2, 72)), "control-tower opening is clear")
	check(not ray_hit(Vector3(-100, 1.2, 150), Vector3(-100, 1.2, 160)), "western gate is open")
	check(not ray_hit(Vector3(100, 1.2, 150), Vector3(100, 1.2, 160)), "eastern gate is open")
	check(ray_hit(Vector3(0, 1.2, 150), Vector3(0, 1.2, 160)), "perimeter fence blocks passage outside its gates")
	check(ray_hit(Vector3(-72, 0.9, 26), Vector3(-80, 0.9, 26)), "parked vehicle has collision")
	check(await capsule_passes(Vector3(-118, .10, 47), Vector3(-118, .10, 54)), "player-sized capsule fits through the large hangar entrance")
	check(await capsule_passes(Vector3(14, .10, 68), Vector3(14, .10, 72)), "player-sized capsule fits through the service entrance")
	check(await capsule_passes(Vector3(-100, .10, 150), Vector3(-100, .10, 160)), "player-sized capsule fits through the open gate")
	MeshCleanup.before_free(field)
	field.free()
	await process_frame

	# The preview is deliberately separate from, and never changes, the save.
	var save_path := SaveGame.TEST_PATH
	var save_exists_before := FileAccess.file_exists(save_path)
	var save_before := file_bytes(save_path)
	var main := load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var button := find_button(main.current_screen, "ОСМОТР АЭРОДРОМА")
	check(button != null, "main menu opens a separate walkthrough")
	if button != null:
		button.pressed.emit()
		await process_frame
		await physics_frame
		var preview = main.current_screen
		check(preview.name == "AirfieldWalkthrough" and preview.player is CharacterBody3D, "walkthrough contains the actual 3D player")
		check(preview.field.get_node_or_null("Ground/Runway") != null, "walkthrough uses the editable airfield scene")
		var bounded: Vector3 = preview.clamp_player_position(Vector3(1000, 2, -1000))
		check(bounded == Vector3(448.5, 2, -173.5), "walkthrough uses airfield-sized movement bounds")
		check(preview.player.visual.animation != null, "walkthrough uses the supplied animated hero")
		main.show_menu()
		await process_frame
	check(FileAccess.file_exists(save_path) == save_exists_before and file_bytes(save_path) == save_before, "preview does not touch the save")
	MeshCleanup.before_free(main)
	main.free()
	await process_frame
	if failures.is_empty():
		print("AIRFIELD SITE TESTS PASSED")
		quit(0)
	else:
		print("AIRFIELD SITE TESTS FAILED: ", failures)
		quit(1)
