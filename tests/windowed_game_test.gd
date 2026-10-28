extends SceneTree

# An actual compatibility-renderer window exercises startup beyond the menu.
# The separate test slot prevents changes to a player's normal save.
const SaveGame = preload("res://scripts/save_game.gd")
var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("SHARDS_TEST_SAVE", "1")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.TEST_PATH + suffix))
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)

func button(parent: Node, text: String) -> Button:
	for node in parent.find_children("*", "Button", true, false):
		if node.text == text:
			return node
	return null

func visible_frame_has_content() -> bool:
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	if image == null or image.is_empty():
		return false
	image.resize(32, 18, Image.INTERPOLATE_BILINEAR)
	var low := 1.0
	var high := 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var p = image.get_pixel(x, y)
			var value = (p.r + p.g + p.b) / 3.0
			low = minf(low, value)
			high = maxf(high, value)
	return high - low > 0.08 and high > 0.1

func _run() -> void:
	check(DisplayServer.get_name() != "headless", "game uses a real display and renderer")
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("Main scene could not be loaded")
		quit(1)
		return
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	var start = button(main.current_screen, "НОВАЯ ИГРА")
	check(start != null, "new game is accessible from the rendered menu")
	check(await visible_frame_has_content(), "main menu renders a non-blank frame")
	if start == null:
		quit(1)
		return
	start.pressed.emit()
	await process_frame
	var world = main.current_screen
	check(world is Node3D and is_instance_valid(world.player), "new game constructs the 3D world and player")
	if not world is Node3D or not is_instance_valid(world.player):
		quit(1)
		return
	check(world.player.camera.current and world.player.visual.animation != null, "3D camera and animated hero start")
	check(world.environment_3d.get_node_or_null("IslandTerrain") is MeshInstance3D, "the island mesh starts in the rendered world")
	world.hud.close_modal()
	world.player.invulnerable = 999.0
	await create_timer(0.8).timeout
	check(world.player.is_on_floor(), "player lands on the 3D island")
	check(await visible_frame_has_content(), "3D world renders a non-blank frame")
	var moved := false
	for action in ["move_right", "move_up", "move_left", "move_down"]:
		var before: Vector3 = world.player.global_position
		Input.action_press(action)
		await create_timer(0.2).timeout
		Input.action_release(action)
		await physics_frame
		if world.player.global_position.distance_to(before) > 0.05:
			moved = true
			break
	check(moved, "player movement works while the 3D world is rendered")

	world.inventory["wood"] = 13
	world.quest_stage = 1
	check(world.save_progress(false), "rendered game can write a save")
	var old_data = SaveGame.load_data()
	# Simulate a pre-weapon-selection save at a position now under water.
	old_data.erase("equipped_weapon")
	old_data["player"]["position"] = [100, 100]
	check(SaveGame.save_data(old_data), "legacy save fixture is written to the isolated test slot")
	main.show_menu()
	await process_frame
	var resume = button(main.current_screen, "ПРОДОЛЖИТЬ")
	check(resume != null and not resume.disabled, "Continue is enabled for the existing save")
	if resume:
		resume.pressed.emit()
		await process_frame
		world = main.current_screen
		check(world is Node3D and world.quest_stage == 1 and world.count("wood") == 13, "Continue restores quest and inventory in the rendered game")
		var position: Vector2 = world.world_to_map(world.player.global_position)
		check(position.distance_to(Vector2(100, 100)) > 100.0 and world.environment_3d.is_walkable(world.player.position.x, world.player.position.z), "legacy water position is relocated onto the new island")
		check(await visible_frame_has_content(), "restored game renders a non-blank frame")

	main.queue_free()
	await create_timer(0.75).timeout
	await process_frame
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.TEST_PATH + suffix))
	if failures.is_empty():
		print("WINDOWED GAME STARTUP PASSED")
		quit(0)
	else:
		print("WINDOWED GAME STARTUP FAILED: ", failures)
		quit(1)
