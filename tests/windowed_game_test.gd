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

func press_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func click_at(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

# Feed events to the rendered root viewport in its own logical coordinates.
# This exercises Godot's real GUI hit-testing and button/drag handling rather
# than emitting signals directly. Input.parse_input_event expects window
# coordinates and is transformed again when the 960x540 window is stretched.
func click_gui_at(position: Vector2) -> void:
	root.warp_mouse(position)
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.global_position = position
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func clear_build_site(world) -> Vector2i:
	for x in range(4, 39):
		for z in range(4, 27):
			var level: float = world.building.foundation_level(x, z)
			if is_finite(level) and world.building._volume_clear({"type": "foundation", "x": x, "z": z, "y": level}):
				return Vector2i(x, z)
	return Vector2i(-1, -1)

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
	var original_position: Vector3 = world.player.global_position
	var lake: Vector2 = world.environment_3d.lake_map_position * world.MAP_SCALE
	var shore := lake + Vector2(-6.0, 8.0)
	world.player.set_physics_process(false)
	world.player.global_position = Vector3(shore.x, world.environment_3d.height_at(shore.x, shore.y) + 0.15, shore.y)
	await process_frame
	await process_frame
	check(await visible_frame_has_content(), "the lake and shoreline render in the 3D world")
	world.player.global_position = original_position
	world.player.set_physics_process(true)
	check(is_instance_valid(world.hud.minimap) and world.hud.minimap.visible, "a player-centred minimap is visible in the rendered HUD")
	await press_key(KEY_TAB)
	check(world.hud.modal_kind == "inventory" and world.hud.inventory_grid.get_child_count() == 24, "Tab opens the rendered icon inventory")
	check(await visible_frame_has_content(), "icon inventory renders in the game window")
	var food_slot: Control = null
	for slot in world.hud.inventory_grid.get_children():
		if slot.get_meta("item_id", "") == "food":
			food_slot = slot
			break
	check(is_instance_valid(food_slot), "food has an inventory icon")
	if is_instance_valid(food_slot):
		var food_before: int = world.count("food")
		world.player.hunger = 20.0
		var food_click: Vector2 = food_slot.get_global_rect().get_center()
		await click_gui_at(food_click)
		if world.hud.selected_inventory_item != "food":
			print("GUI inventory target=", food_slot, " hovered=", root.gui_get_hovered_control(), " rect=", food_slot.get_global_rect(), " canvas=", food_slot.get_global_transform_with_canvas(), " final=", root.get_final_transform())
		check(world.hud.selected_inventory_item == "food", "clicking the icon selects food in the rendered viewport")
		var use_button: Control = world.hud.inventory_action
		var use_click: Vector2 = use_button.get_global_rect().get_center()
		await click_gui_at(use_click)
		check(world.count("food") == food_before - 1 and world.player.hunger > 20.0, "clicking Use consumes the selected food in the actual window")
	await press_key(KEY_TAB)
	check(not world.hud.is_modal_open(), "Tab closes the inventory")
	await press_key(KEY_M)
	var rendered_map = world.hud.modal.find_child("IslandMap", true, false) if world.hud.is_modal_open() else null
	check(world.hud.modal_kind == "map" and is_instance_valid(rendered_map), "M opens the rendered interactive island map")
	check(await visible_frame_has_content(), "island map renders in the game window")
	if is_instance_valid(rendered_map):
		var waypoint := Vector2(1600, 1100)
		var map_click: Vector2 = rendered_map.get_global_rect().position + rendered_map.map_to_screen(waypoint)
		await click_gui_at(map_click)
		if world.waypoint_map.distance_to(waypoint) >= 15.0:
			print("GUI map target=", rendered_map, " hovered=", root.gui_get_hovered_control(), " click=", map_click, " rect=", rendered_map.get_global_rect())
		check(world.waypoint_map.distance_to(waypoint) < 15.0, "clicking the displayed chart sets a map waypoint")
	await press_key(KEY_M)
	check(not world.hud.is_modal_open(), "M closes the map")

	# Use the real keyboard, cursor ray and left click through the window, not
	# just direct calls to the building API.
	world.player.set_physics_process(false)
	for enemy in world.enemies:
		enemy.set_physics_process(false)
	world.inventory["wood"] = 100
	world.inventory["stone"] = 100
	var site := clear_build_site(world)
	check(site.x >= 0, "rendered island has a clear foundation site")
	await press_key(KEY_B)
	check(world.building.active and world.hud.build_panel.visible, "B opens the visible building panel")
	await press_key(KEY_2)
	check(world.building.selected == "wall", "number key selects a wall in the building panel")
	await press_key(KEY_1)
	check(world.building.selected == "foundation", "number key selects a foundation")
	var aimed := false
	if site.x >= 0:
		var level: float = world.building.foundation_level(site.x, site.y)
		var point := Vector3(float(site.x) * 3.0, level, float(site.y) * 3.0)
		for offset in [Vector3(0, 0, -4), Vector3(4, 0, 0), Vector3(0, 0, 4), Vector3(-4, 0, 0)]:
			var player_pos: Vector3 = point + offset
			player_pos.y = world.environment_3d.height_at(player_pos.x, player_pos.z) + 0.15
			world.player.global_position = player_pos
			await physics_frame
			await process_frame
			var cursor: Vector2 = world.player.camera.unproject_position(point)
			var viewport_size: Vector2 = root.get_visible_rect().size
			if cursor.x < 10 or cursor.x > viewport_size.x - 10 or cursor.y < 10 or cursor.y > viewport_size.y * 0.63:
				continue
			root.warp_mouse(cursor)
			await process_frame
			await process_frame
			var candidate: Dictionary = world.building.candidate
			if world.building.valid and candidate.get("x", -1) == site.x and candidate.get("z", -1) == site.y:
				aimed = true
				break
	check(aimed and is_instance_valid(world.building.ghost) and world.building.ghost.visible, "mouse shows a valid 3D foundation preview in the real window")
	if aimed:
		check(await visible_frame_has_content(), "building preview and panel render")
		var cursor: Vector2 = root.get_mouse_position()
		await click_at(cursor)
		check(world.building.pieces.size() == 1 and world.count("wood") == 96 and world.count("stone") == 98, "left click places a foundation and spends its resources")
		await physics_frame
		await process_frame
		await press_key(KEY_X)
		check(world.building.pieces.is_empty() and world.count("wood") == 100 and world.count("stone") == 100, "X dismantles the targeted foundation and refunds materials")
	await press_key(KEY_ESCAPE)
	check(not world.building.active and not world.hud.build_panel.visible, "Escape closes building mode without opening pause")
	world.player.set_physics_process(true)

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
