extends SceneTree

# Exercise real placement, physics and persistence in the isolated test slot.
const SaveGame = preload("res://scripts/save_game.gd")
const CELL := 3.0
var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("SHARDS_TEST_SAVE", "1")
	_clear_save()
	create_timer(100.0).timeout.connect(func():
		push_error("Building test timed out")
		quit(1)
	)
	_run.call_deferred()

func _clear_save() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.TEST_PATH + suffix))

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)

# Search the actual imported island, not a mocked plane. A 3x2 patch proves
# that adjacent foundations share a level and a house is not a fixed prefab.
func find_patch(world) -> Vector2i:
	var building = world.building
	for x in range(4, 39):
		for z in range(4, 27):
			var levels: Array[float] = []
			var clear := true
			for dx in range(3):
				for dz in range(2):
					var level: float = building.foundation_level(x + dx, z + dz)
					if not is_finite(level):
						clear = false
						break
					levels.append(level)
					var data = {"type": "foundation", "x": x + dx, "z": z + dz, "y": level}
					if not building._volume_clear(data):
						clear = false
						break
				if not clear:
					break
			if clear:
				var low: float = levels.min()
				var high: float = levels.max()
				if high - low <= 0.14:
					return Vector2i(x, z)
	return Vector2i(-1, -1)

func find_other_site(world, first: Vector2i) -> Vector2i:
	for x in range(4, 39):
		for z in range(4, 27):
			if Vector2(x - first.x, z - first.y).length() < 10.0:
				continue
			var level: float = world.building.foundation_level(x, z)
			if is_finite(level) and world.building._volume_clear({"type": "foundation", "x": x, "z": z, "y": level}):
				return Vector2i(x, z)
	return Vector2i(-1, -1)

func move_player(world, position: Vector3) -> void:
	world.player.global_position = position
	world.player.velocity = Vector3.ZERO
	await physics_frame

func move_near(world, position: Vector3, offset := Vector3(0, 0, -4.0)) -> void:
	var p: Vector3 = position + offset
	p.y = world.environment_3d.height_at(p.x, p.z) + 0.15
	await move_player(world, p)

func edge_record(building, kind: String, x: int, z: int, side: int, level: float) -> Dictionary:
	var foundation = building.foundation_at(x, z)
	var record: Dictionary = building._edge_for(foundation, side, kind)
	record["type"] = kind
	record["y"] = level
	return record

func uses_model(piece: Node, suffix: String) -> bool:
	if not is_instance_valid(piece):
		return false
	for node in piece.find_children("*", "Node3D", true, false):
		if node.get_meta("construction_model", false) and String(node.scene_file_path).ends_with(suffix):
			return true
	return false

func ray_blocked(world, from: Vector3, to: Vector3) -> bool:
	var query = PhysicsRayQueryParameters3D.create(from, to, 1 | (1 << 3))
	return not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game(false)
	await process_frame
	var world = main.current_screen
	world.hud.close_modal()
	world.player.set_physics_process(false)
	for enemy in world.enemies:
		enemy.set_physics_process(false)
	await physics_frame
	var building = world.building
	world.inventory["wood"] = 300
	world.inventory["stone"] = 300
	world.inventory["iron"] = 300
	var site := find_patch(world)
	check(site.x >= 0, "a clear 3x2 building site exists on the real island")
	if site.x < 0:
		main.queue_free()
		await create_timer(0.5).timeout
		_clear_save()
		quit(1)
		return
	var initial_level: float = building.foundation_level(site.x, site.y)
	var center := Vector3(float(site.x) * CELL, initial_level, float(site.y) * CELL)
	var first: Dictionary = building.candidate_for_point("foundation", center)
	check(first.get("x", -1) == site.x and first.get("z", -1) == site.y and is_finite(float(first.get("y", INF))), "foundation preview snaps to a free grid cell")
	await move_near(world, center)

	var wood_before: int = world.count("wood")
	var stone_before: int = world.count("stone")
	world.inventory["wood"] = 0
	check(not building.try_place(first) and world.count("stone") == stone_before and building.pieces.is_empty(), "unaffordable construction neither spends resources nor creates a piece")
	world.inventory["wood"] = wood_before
	await move_player(world, center + Vector3.UP * 0.10)
	check(not building.placement_error(first, false).is_empty(), "a foundation cannot be placed on top of the player")
	await move_near(world, center, Vector3(0, 0, -10.0))
	check(not building.placement_error(first, false).is_empty(), "a foundation cannot be placed beyond build range")
	await move_near(world, center)
	check(building.try_place(first), "a player can build a foundation at the chosen location")
	check(world.count("wood") == wood_before - 4 and world.count("stone") == stone_before - 2, "foundation charges its exact wood and stone price")
	check(not building.try_place(first), "a second foundation cannot occupy the same cell")

	# Make the rest of a six-cell rectangular base, not a fixed-size building.
	var complete := true
	for dx in range(3):
		for dz in range(2):
			if dx == 0 and dz == 0:
				continue
			var point := Vector3(float(site.x + dx) * CELL, initial_level, float(site.y + dz) * CELL)
			await move_near(world, point)
			var record: Dictionary = building.candidate_for_point("foundation", point)
			if not building.try_place(record):
				print("Foundation placement diagnostic: ", record, " ", building.placement_error(record))
				complete = false
	check(complete and building.pieces.size() == 6, "six adjoining foundations form a freely sized 3x2 base")
	if not complete:
		main.queue_free()
		await create_timer(0.5).timeout
		_clear_save()
		quit(1)
		return
	for dx in range(3):
		for dz in range(2):
			var foundation = building.foundation_at(site.x + dx, site.y + dz)
			check(is_instance_valid(foundation) and absf(float(foundation.data.y) - initial_level) < 0.001, "adjacent foundation shares the first floor's height")

	# A foundation edge is selected by cursor position; R rotates to another.
	building.rotation_step = 0
	var edge_point := center + Vector3(0, 0, -1.35)
	var wall: Dictionary = building.candidate_for_point("wall", edge_point)
	var expected_wall := edge_record(building, "wall", site.x, site.y, 0, initial_level)
	check(building.piece_key(wall) == building.piece_key(expected_wall), "wall preview snaps to the targeted foundation edge")
	building.rotate_selection()
	var rotated: Dictionary = building.candidate_for_point("wall", edge_point)
	check(building.piece_key(rotated) != building.piece_key(wall), "R rotates a wall preview onto another edge")
	building.rotation_step = 0
	await move_near(world, building._record_position(wall))
	var before_wall: int = world.count("wood")
	check(building.try_place(wall) and world.count("wood") == before_wall - 3, "wall is built on its foundation for three wood")
	await physics_frame
	var corner := edge_record(building, "wall", site.x, site.y, 3, initial_level)
	await move_near(world, building._record_position(corner), Vector3(-4, 0, 0))
	var corner_built: bool = building.try_place(corner)
	check(corner_built, "perpendicular walls can meet at a foundation corner")
	if corner_built:
		check(building.remove_piece(building.pieces.get(building.piece_key(corner))), "a corner wall can be removed independently")
	await physics_frame

	# Melee attacks in either direction must respect the solid wall.
	var wall_pos: Vector3 = building._record_position(wall)
	await move_player(world, wall_pos + Vector3(0, 0.10, -0.70))
	var target = world.spawn_enemy("building_test_enemy", "walker", world.world_to_map(wall_pos), "test")
	target.set_physics_process(false)
	target.global_position = wall_pos + Vector3(0, 0.10, 0.70)
	await physics_frame
	var enemy_hp: float = target.health
	var player_hp: float = world.player.health
	world.player_attack(Vector3.BACK)
	target._physics_process(0.0)
	check(target.health == enemy_hp and world.player.health == player_hp, "the wall blocks player and zombie melee attacks")
	target.global_position = wall_pos + Vector3(0, 0.10, -1.65)
	await physics_frame
	world.player_attack(Vector3.FORWARD)
	target._physics_process(0.0)
	check(target.health < enemy_hp and world.player.health < player_hp, "melee works again when both actors are on the same side")
	target.queue_free()
	await physics_frame

	# Doorway and hinged door are separate pieces on another outside edge.
	var door_cell_z := site.y + 1
	var frame := edge_record(building, "doorway", site.x, door_cell_z, 2, initial_level)
	var frame_pos: Vector3 = building._record_position(frame)
	await move_near(world, frame_pos, Vector3(0, 0, 4.0))
	check(building.try_place(frame), "doorway can be built independently on a foundation edge")
	await physics_frame
	building.rotation_step = 0
	var left_door: Dictionary = building.candidate_for_point("door", frame_pos)
	building.rotate_selection()
	var right_door: Dictionary = building.candidate_for_point("door", frame_pos)
	check(int(left_door.get("hinge", 0)) == -1 and int(right_door.get("hinge", 0)) == 1, "R switches the door hinge side")
	var iron_before: int = world.count("iron")
	var door_wood_before: int = world.count("wood")
	check(building.try_place(right_door) and world.count("wood") == door_wood_before - 2 and world.count("iron") == iron_before - 1, "door fits the frame and charges wood and metal")
	await physics_frame
	var door = building.pieces.get(building.piece_key(right_door))
	check(is_instance_valid(door), "installed door exists")
	if is_instance_valid(door):
		var ray_start := frame_pos + Vector3(0, 1.0, -1.0)
		var ray_end := frame_pos + Vector3(0, 1.0, 1.0)
		check(ray_blocked(world, ray_start, ray_end), "a closed door blocks the opening")
		await move_player(world, frame_pos + Vector3(0, 0.10, 1.7))
		building.interact_door(door)
		check(bool(door.data.open), "E can open a nearby door")
		await create_timer(0.4).timeout
		await physics_frame
		check(bool(door.data.open) and not ray_blocked(world, ray_start, ray_end), "open door swings clear of the doorway")
		await move_player(world, frame_pos + Vector3(0, 0.10, 0))
		building.interact_door(door)
		check(bool(door.data.open), "a door cannot close on the player")
		await move_player(world, frame_pos + Vector3(0, 0.10, 1.7))
		building.interact_door(door)
		check(not bool(door.data.open), "open door can close again when the opening is clear")
		await create_timer(0.4).timeout
		await physics_frame
		check(not bool(door.data.open) and ray_blocked(world, ray_start, ray_end), "closed door restores its physical collision")
		building.interact_door(door)
		check(bool(door.data.open), "door can be left open for a save")

	await move_near(world, center)
	var roof: Dictionary = building.candidate_for_point("roof", center)
	check(building.try_place(roof), "roof can be installed above a foundation and wall")
	await physics_frame
	var floor_piece = building.foundation_at(site.x, site.y)
	var roof_piece = building.pieces.get(building.piece_key(roof))
	var wall_piece = building.pieces.get(building.piece_key(wall))
	var frame_piece = building.pieces.get(building.piece_key(frame))
	var roof_meshes: Array = roof_piece.find_children("*", "MeshInstance3D", true, false) if is_instance_valid(roof_piece) else []
	check(uses_model(floor_piece, "pir_platform.glb") and uses_model(wall_piece, "td_wood-structure-high-part.glb") and uses_model(roof_piece, "pir_platform-planks.glb") and uses_model(door, "pir_platform.glb"), "foundation, wall, roof and door render adapted models from the repository library")
	await move_player(world, center + Vector3(0, 0.12, 0))
	await process_frame
	check(not roof_meshes.is_empty() and not roof_meshes[0].visible, "roof hides visually when the player is inside")
	check(ray_blocked(world, center + Vector3(0, 2.3, 0), center + Vector3(0, 3.2, 0)) and (world.player.collision_mask & (1 << 3)) != 0, "hidden roof remains physically solid to the player")
	check((world.player.camera_arm.collision_mask & (1 << 3)) == 0, "the overhead roof does not trap the follow camera")
	await move_player(world, center + Vector3(0, 3.0, 0))
	await process_frame
	check(not roof_meshes.is_empty() and roof_meshes[0].visible, "roof becomes visible again above the house")
	world.player.set_physics_process(true)
	await create_timer(0.7).timeout
	world.player.set_physics_process(false)
	check(world.player.is_on_floor() and absf(world.player.global_position.y - (initial_level + 2.78)) < 0.15, "the player can physically land on the roof")
	check(not building.remove_piece(floor_piece), "supporting foundation cannot be removed while parts depend on it")
	check(not building.remove_piece(frame_piece), "doorframe cannot be removed while its door is installed")

	var other := find_other_site(world, site)
	var second_base_built := false
	if other.x >= 0:
		var other_level: float = building.foundation_level(other.x, other.y)
		var other_point := Vector3(float(other.x) * CELL, other_level, float(other.y) * CELL)
		await move_near(world, other_point)
		second_base_built = building.try_place(building.candidate_for_point("foundation", other_point))
	check(second_base_built, "a second independent base can be started elsewhere on the island")

	await move_player(world, center + Vector3(0, 0.12, 0))
	check(world.save_progress(false), "base and current player position can be saved")
	var saved: Dictionary = SaveGame.load_data()
	check(saved.get("buildings", []).size() == 11, "all five piece types and both bases are serialized")
	var saved_buildings: Array = saved.get("buildings", []).duplicate(true)
	main.show_menu()
	await process_frame
	main.start_game(true)
	await process_frame
	world = main.current_screen
	world.hud.close_modal()
	world.player.set_physics_process(false)
	for enemy in world.enemies:
		enemy.set_physics_process(false)
	building = world.building
	await physics_frame
	check(building.serialize().size() == saved_buildings.size(), "save restores the entire base")
	door = building.pieces.get(building.piece_key(right_door))
	check(is_instance_valid(door) and bool(door.data.open) and int(door.data.hinge) == 1, "save restores the open state and hinge side")
	var loaded_position: Vector3 = world.player.global_position
	# The capsule bottom is 0.005 m above the CharacterBody origin, so a
	# grounded character's origin can sit just below the floor surface.
	if Vector2(loaded_position.x, loaded_position.z).distance_to(Vector2(center.x, center.z)) >= 0.2 or loaded_position.y < initial_level - 0.03:
		print("Resume position diagnostic: expected floor ", center, "; got ", loaded_position)
	check(Vector2(loaded_position.x, loaded_position.z).distance_to(Vector2(center.x, center.z)) < 0.2 and loaded_position.y >= initial_level - 0.03, "Continue returns the player inside the base on its floor")
	var safe_near_wall: Vector3 = world._safe_player_spawn(world.world_to_map(wall_pos))
	check(world._built_spawn_clear(Vector2(safe_near_wall.x, safe_near_wall.z), safe_near_wall.y), "resume position is adjusted away from built walls")
	world.player_defeated()
	var spawn: Vector3 = world.player.global_position
	check(is_finite(building.floor_height_at(Vector2(spawn.x, spawn.z))) and spawn.y > initial_level, "defeated player respawns on a built foundation")

	floor_piece = building.foundation_at(site.x, site.y)
	roof_piece = building.pieces.get(building.piece_key(roof))
	wall_piece = building.pieces.get(building.piece_key(wall))
	frame_piece = building.pieces.get(building.piece_key(frame))
	var refund_wood: int = world.count("wood")
	check(building.remove_piece(roof_piece) and world.count("wood") == refund_wood + 3, "dismantling a roof returns its resources")
	check(building.remove_piece(wall_piece), "wall can be dismantled")
	check(building.remove_piece(door), "door can be dismantled")
	check(building.remove_piece(frame_piece), "empty doorway can then be dismantled")
	check(building.remove_piece(floor_piece), "unsupported foundation can then be dismantled")

	# Simulate a save written before the island doubled in size. Loading it
	# must move connected pieces together without changing the 3 m grid, retain
	# a separate second base, and keep a player who was inside the first one.
	var old_save := saved.duplicate(true)
	old_save.erase("island_revision")
	old_save.erase("lake_position")
	old_save.erase("waypoint")
	var old_records: Array = old_save["buildings"]
	for record in old_records:
		var part := Vector2(float(record.x), float(record.z))
		if record.type in ["wall", "doorway", "door"]: part *= 0.5
		var anchor := site if part.distance_to(Vector2(site)) < part.distance_to(Vector2(other)) else other
		var terrain: float = world.environment_3d.height_at(float(anchor.x) * CELL * 2.0, float(anchor.y) * CELL * 2.0)
		record["y"] = (terrain + 0.16) * 0.5
	old_save["player"]["position"] = [center.x / 0.04, center.z / 0.04]
	check(SaveGame.save_data(old_save), "pre-expansion save fixture is valid")
	main.show_menu()
	await process_frame
	main.start_game(true)
	await process_frame
	world = main.current_screen
	world.hud.close_modal()
	world.player.set_physics_process(false)
	building = world.building
	await physics_frame
	var migrated_floor = building.foundation_at(site.x * 2, site.y * 2)
	var migrated_neighbor = building.foundation_at(site.x * 2 + 1, site.y * 2)
	var migrated_other = building.foundation_at(other.x * 2, other.y * 2)
	var expected_position := Vector2(center.x * 2.0, center.z * 2.0)
	var player_position := Vector2(world.player.global_position.x, world.player.global_position.z)
	check(is_instance_valid(migrated_floor) and is_instance_valid(migrated_neighbor) and is_instance_valid(migrated_other) and player_position.distance_to(expected_position) < 0.3, "old bases and the player migrate together in the running world")
	var migrated_door: Dictionary = right_door.duplicate(true)
	migrated_door["x"] = int(migrated_door.x) + site.x * 2
	migrated_door["z"] = int(migrated_door.z) + site.y * 2
	var door_after_migration = building.pieces.get(building.piece_key(migrated_door))
	check(is_instance_valid(door_after_migration) and bool(door_after_migration.data.open) and world.save_progress(false) and int(SaveGame.load_data().get("island_revision", 0)) == 2, "migrated door remains open and the new revision saves safely")

	main.queue_free()
	await create_timer(0.5).timeout
	_clear_save()
	await process_frame
	if failures.is_empty():
		print("BUILDING TESTS PASSED")
		quit(0)
	else:
		print("BUILDING TESTS FAILED: ", failures)
		quit(1)
