extends SceneTree

const SaveGame = preload("res://scripts/save_game.gd")
const WorldScript = preload("res://scripts/world.gd")
const MeshCleanup = preload("res://scripts/mesh_cleanup.gd")
var failures: Array[String] = []
var watchdog: Timer

func _initialize() -> void:
	# Never touch a player's normal save, even when this test is run manually.
	OS.set_environment("SHARDS_TEST_SAVE", "1")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.TEST_PATH + suffix))
	watchdog = Timer.new()
	watchdog.one_shot = true
	watchdog.autostart = true
	watchdog.wait_time = 60.0
	watchdog.timeout.connect(_on_timeout)
	root.add_child(watchdog)
	_run.call_deferred()

func _on_timeout() -> void:
	push_error("Smoke test timed out")
	quit(1)

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		push_error("FAIL: " + message)
		failures.append(message)

func prop(world, identity: String):
	for p in world.props:
		if p.prop_id == identity:
			return p
	return null

func enemy(world, identity: String):
	for e in world.enemies:
		if is_instance_valid(e) and not e.is_dead and e.enemy_id == identity:
			return e
	return null

func has_interaction_space(world, landmark: Node3D, island_body: StaticBody3D) -> bool:
	# Check there is connected, collision-free ground from which E selects this
	# landmark. This also detects relocated props buried in an old building.
	var sphere = SphereShape3D.new()
	sphere.radius = 0.37
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = 1
	query.exclude = [island_body.get_rid()]
	var saved_position: Vector3 = world.player.global_position
	for radius in [1.4, 2.4, 3.2]:
		for i in range(20):
			var angle = TAU * float(i) / 20.0
			var x = landmark.global_position.x + cos(angle) * radius
			var z = landmark.global_position.z + sin(angle) * radius
			if not world.environment_3d.is_walkable(x, z):
				continue
			var y: float = world.environment_3d.height_at(x, z)
			query.transform = Transform3D(Basis.IDENTITY, Vector3(x, y + 0.85, z))
			if not world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
				continue
			world.player.global_position = Vector3(x, y, z)
			if world.nearest_prop() == landmark:
				world.player.global_position = saved_position
				return true
	world.player.global_position = saved_position
	return false

func button(parent: Node, text: String) -> Button:
	for node in parent.find_children("*", "Button", true, false):
		if node.text == text:
			return node
	return null

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var start = button(main.current_screen, "НОВАЯ ИГРА")
	check(start != null, "new-game button is available")
	if start == null:
		quit(1)
		return
	start.pressed.emit()
	await process_frame
	var world = main.current_screen
	check(world.player != null and world.hud != null, "world, player and HUD start")
	check(world is Node3D and world.player is CharacterBody3D and world.player.camera is Camera3D, "game world, character and perspective camera are 3D")
	check(world.environment_3d.get_node_or_null("IslandTerrain") is MeshInstance3D and world.environment_3d.get_node_or_null("IslandCollision") is StaticBody3D, "3D terrain and physics collision exist")
	var terrain: MeshInstance3D = world.environment_3d.get_node("IslandTerrain")
	check(terrain.mesh.surface_get_material(0) is ShaderMaterial, "terrain combines the user's PBR textures with road masks")
	check(terrain.get_meta("source_model", "") == "res://assets/models/environment/user_island.glb", "terrain comes from the newly supplied island GLB")
	var island_bounds: AABB = terrain.mesh.get_aabb()
	var island_arrays = terrain.mesh.surface_get_arrays(0)
	check(absf(island_bounds.size.x - 128.0) < 0.05 and absf(island_bounds.size.z - 88.0) < 0.05, "supplied island matches the old 128 by 88 metre world")
	check(island_bounds.size.y > 4.9 and island_bounds.size.y < 5.2 and island_arrays[Mesh.ARRAY_INDEX].size() == 360000, "new island retains its terrain and trees in 120000 optimized triangles")
	check(island_arrays[Mesh.ARRAY_TEX_UV].size() == island_arrays[Mesh.ARRAY_VERTEX].size() and island_arrays[Mesh.ARRAY_TEX_UV2].size() == island_arrays[Mesh.ARRAY_VERTEX].size(), "source UVs and separate road-mask UVs are both retained")
	var imported_island = load("res://assets/models/environment/user_island.glb").instantiate()
	var original_meshes = imported_island.find_children("*", "MeshInstance3D", true, false)
	if imported_island is MeshInstance3D:
		original_meshes.push_front(imported_island)
	check(not original_meshes.is_empty(), "source island has a mesh")
	if not original_meshes.is_empty():
		var original_arrays = (original_meshes[0] as MeshInstance3D).mesh.surface_get_arrays(0)
		check(island_arrays[Mesh.ARRAY_TEX_UV] == original_arrays[Mesh.ARRAY_TEX_UV], "island keeps the exact UV coordinates of the supplied model")
	MeshCleanup.before_free(imported_island)
	imported_island.free()
	var island_material = terrain.mesh.surface_get_material(0) as ShaderMaterial
	check(island_material.get_shader_parameter("base_tex") is Texture2D and island_material.get_shader_parameter("normal_tex") is Texture2D and island_material.get_shader_parameter("metal_rough_tex") is Texture2D, "island keeps its original base-color, normal and metallic-roughness textures")
	var collision_shape = world.environment_3d.get_node("IslandCollision").get_child(0) as CollisionShape3D
	check(collision_shape.shape is ConcavePolygonShape3D and (collision_shape.shape as ConcavePolygonShape3D).get_faces().size() == 360000, "physical collision uses the complete island mesh")
	var repaired_point: Vector2 = world.environment_3d.nearest_walkable(67.0, 22.0)
	check(world.environment_3d.is_walkable(repaired_point.x, repaired_point.y), "a saved position inside the new geometry moves to connected ground")
	for site in ["hotel", "safe", "keycard", "chip", "coil", "cell", "lighthouse", "boat", "water_0"]:
		var landmark = prop(world, site)
		check(landmark != null and world.environment_3d.is_walkable(landmark.position.x, landmark.position.z), "landmark is on connected, unobstructed ground: " + site)
	var path = world.environment_3d.navigation_path(world.map_to_world(Vector2(360, 1830)), world.map_to_world(world.SITES.hotel))
	check(path.size() > 4, "navigation can route from the shore around the model to the hotel")
	path = world.environment_3d.navigation_path(world.map_to_world(Vector2(850, 1280)), world.map_to_world(world.SITES.keycard))
	check(path.size() > 4, "navigation can route from the central island to the airfield")
	for site in ["boat", "lighthouse", "coil", "cell"]:
		path = world.environment_3d.navigation_path(world.map_to_world(Vector2(850, 1280)), world.map_to_world(world.SITES[site]))
		check(path.size() > 4, "navigation reaches the new island landmark: " + site)
	var grass = world.environment_3d.get_node_or_null("GrassCover")
	check(grass is MultiMeshInstance3D and grass.multimesh.instance_count > 500, "3D grass is batched across the island")
	var weeds = world.environment_3d.get_node_or_null("GroundWeeds")
	check(weeds is MultiMeshInstance3D and weeds.multimesh.instance_count > 300, "broad-leaved ground vegetation is batched")
	var forest = world.environment_3d.get_node_or_null("ForestColliders")
	check(forest is StaticBody3D and forest.get_child_count() > 0, "3D forest trunks have physical collision")
	check(world.environment_3d.get_node_or_null("ForestBroadleaf") is Node3D, "forest includes photoreal broadleaf trees")
	check(world.player.visual.animation != null and world.player.visual.animation.has_animation("Walk"), "rigged 3D hero has a walking animation")
	check(world.player.visual.animation.get_animation("Walk").get_track_count() > 10, "walking animation contains skeletal tracks")
	var hero_skeletons = world.player.visual.model.find_children("*", "Skeleton3D", true, false)
	check(not hero_skeletons.is_empty(), "supplied hero has a 3D skeleton")
	if not hero_skeletons.is_empty():
		var hero_skeleton = hero_skeletons[0] as Skeleton3D
		var thigh = hero_skeleton.find_bone("thigh_l")
		check(thigh >= 0, "supplied hero has a leg bone")
		if thigh >= 0:
			world.player.visual.play("Walk")
			world.player.visual.animation.advance(0.2)
			world.player.visual.animation.seek(0.15, true)
			var pose_a = hero_skeleton.get_bone_pose_rotation(thigh)
			world.player.visual.animation.seek(0.75, true)
			var pose_b = hero_skeleton.get_bone_pose_rotation(thigh)
			check(absf(pose_a.dot(pose_b)) < 0.999, "supplied hero's walking animation moves its legs")
			world.player.visual.play("Idle")
	check(world.player.visual.animation != null and world.player.visual.animation.has_animation("ZombieWalk"), "character rig also contains infected animations")
	check(world.player.visual.model.scene_file_path == "res://assets/models/hero/user_hero.glb", "only the playable hero uses the newly supplied character")
	var hero_meshes = world.player.visual.model.find_children("*", "MeshInstance3D", true, false)
	check(not hero_meshes.is_empty(), "supplied hero has a mesh")
	if not hero_meshes.is_empty():
		var hero_mesh = hero_meshes[0] as MeshInstance3D
		var hero_material = hero_mesh.get_active_material(0)
		var hero_arrays = hero_mesh.mesh.surface_get_arrays(0)
		check(hero_material is BaseMaterial3D and hero_material.albedo_texture != null and hero_material.normal_texture != null and hero_material.roughness_texture != null, "supplied hero retains its original PBR textures")
		check(hero_arrays[Mesh.ARRAY_INDEX].size() == 180000 and hero_arrays[Mesh.ARRAY_BONES].size() > 0, "supplied hero is optimized and skinned")
	check(world.player.camera_arm.rotation.x < deg_to_rad(-50.0) and world.player.camera_arm.spring_length >= 12.0, "default perspective camera provides a high survival-game overview")
	check(world.get_node_or_null("RoadsideDetails/RoadDebris") is MultiMeshInstance3D, "roadside debris is present")
	check(world.quest_stage == 0 and world.hud.is_modal_open(), "new game opens introduction")
	world.hud.close_modal()
	await create_timer(0.35).timeout
	# Raycast only against the island (not props or trees) to verify that the
	# placement samples and the imported collision are the same real surface.
	var excluded: Array[RID] = []
	var island_body = world.environment_3d.get_node("IslandCollision") as StaticBody3D
	for body in world.find_children("*", "StaticBody3D", true, false):
		if body != island_body:
			excluded.append(body.get_rid())
	for sample in [Vector2(360, 1830), Vector2(850, 1280), world.SITES.coil, world.SITES.keycard, world.SITES.lighthouse]:
		var point: Vector3 = world.map_to_world(sample)
		var ray = PhysicsRayQueryParameters3D.create(Vector3(point.x, 40.0, point.z), Vector3(point.x, -3.0, point.z), 1, excluded)
		var hit = world.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and hit.collider == island_body and absf(hit.position.y - point.y) < 0.25, "sampled placement height matches island collision at " + str(sample))
	for identity in ["hotel", "safe", "keycard", "chip", "coil", "cell", "lighthouse", "boat", "water_0"]:
		check(has_interaction_space(world, prop(world, identity), island_body), "landmark has a clear, usable interaction approach: " + identity)
	var tree_position: Vector3 = prop(world, "tree_8").global_position
	var rescued: Vector3 = world._safe_player_spawn(world.world_to_map(tree_position))
	check(Vector2(rescued.x, rescued.z).distance_to(Vector2(tree_position.x, tree_position.z)) > 0.95, "a saved position inside an old tree is moved out of its collision")
	check(world.player.is_on_floor(), "3D player stands on terrain")
	var ground_y: float = world.player.global_position.y
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	await physics_frame
	check(world.player.global_position.y > ground_y + 0.01, "jump changes vertical position")
	await create_timer(0.8).timeout
	var initial_yaw: float = world.player.camera_pivot.rotation.y
	var orbit_press = InputEventMouseButton.new()
	orbit_press.button_index = MOUSE_BUTTON_RIGHT
	orbit_press.pressed = true
	world.player._unhandled_input(orbit_press)
	var orbit_motion = InputEventMouseMotion.new()
	orbit_motion.relative = Vector2(40, -10)
	world.player._unhandled_input(orbit_motion)
	var orbit_release = InputEventMouseButton.new()
	orbit_release.button_index = MOUSE_BUTTON_RIGHT
	orbit_release.pressed = false
	world.player._unhandled_input(orbit_release)
	check(absf(world.player.camera_pivot.rotation.y - initial_yaw) > 0.1, "right-drag rotates the 3D camera")
	var initial_zoom: float = world.player.camera_arm.spring_length
	var scroll = InputEventMouseButton.new()
	scroll.button_index = MOUSE_BUTTON_WHEEL_DOWN
	scroll.pressed = true
	world.player._unhandled_input(scroll)
	check(world.player.camera_arm.spring_length > initial_zoom, "mouse wheel changes camera distance")
	var camera_right: Vector3 = world.player.camera_pivot.global_transform.basis.x
	var start_pos: Vector3 = world.player.global_position
	Input.action_press("move_right")
	await physics_frame
	await physics_frame
	check(world.player.visual.animation.current_animation == "Walk", "moving the survivor plays the walk animation")
	Input.action_release("move_right")
	var displacement: Vector3 = world.player.global_position - start_pos
	check(displacement.dot(camera_right) > 0.01, "player moves relative to the camera through the input map")
	world.hud.show_inventory()
	check(world.hud.is_modal_open() and world.is_paused(), "inventory opens and pauses the world")
	world.hud.close_modal()
	world.hud.show_crafting()
	check(world.hud.is_modal_open(), "crafting menu opens")
	world.hud.close_modal()
	world.hud.show_map()
	check(world.hud.is_modal_open(), "island map opens")
	world.hud.close_modal()
	var target = world.spawn_enemy("test_target", "walker", world.world_to_map(world.player.global_position) + Vector2(45, 0), "test")
	var user_zombie = "res://assets/models/zombie/user_zombie.glb"
	check(target.visual.model != null and target.visual.model.scene_file_path == user_zombie, "walker uses the supplied zombie rather than the survivor model")
	var zombie_skeletons = target.visual.model.find_children("*", "Skeleton3D", true, false)
	var zombie_meshes = target.visual.model.find_children("*", "MeshInstance3D", true, false)
	check(not zombie_skeletons.is_empty(), "supplied zombie has a skinning skeleton")
	check(not zombie_meshes.is_empty(), "supplied zombie has its own mesh")
	if not zombie_meshes.is_empty():
		var zombie_mesh = zombie_meshes[0] as MeshInstance3D
		var material = zombie_mesh.get_active_material(0)
		var arrays = zombie_mesh.mesh.surface_get_arrays(0)
		check(material is BaseMaterial3D and material.albedo_texture != null, "supplied zombie keeps its textured material")
		check(arrays[Mesh.ARRAY_INDEX].size() / 3 <= 40000 and arrays[Mesh.ARRAY_BONES].size() > 0, "supplied zombie is optimized and skinned")
	var zombie_animation: AnimationPlayer = target.visual.animation
	check(zombie_animation != null and zombie_animation.has_animation("ZombieWalk") and zombie_animation.has_animation("ZombieAttack") and zombie_animation.current_animation == "ZombieIdle", "infected have idle, walk and attack clips")
	if zombie_animation != null and zombie_animation.has_animation("ZombieWalk") and not zombie_skeletons.is_empty():
		var skeleton = zombie_skeletons[0] as Skeleton3D
		var leg = skeleton.find_bone("UpperLegL")
		check(leg >= 0 and zombie_animation.get_animation("ZombieWalk").get_track_count() > 5, "zombie walk contains multiple skeletal tracks")
		if leg >= 0:
			target.visual.play("Walk")
			# Finish the normal cross-fade before sampling the new clip.
			zombie_animation.advance(0.2)
			zombie_animation.seek(0.275, true)
			var first_pose = skeleton.get_bone_pose_rotation(leg)
			zombie_animation.seek(0.825, true)
			var second_pose = skeleton.get_bone_pose_rotation(leg)
			check(absf(first_pose.dot(second_pose)) < 0.999, "zombie walk actually moves its leg bones")
			target.visual.play("Punch")
			check(zombie_animation.current_animation == "ZombieAttack", "zombie attack plays the supplied-model animation")
			var arm = skeleton.find_bone("UpperArmL")
			if arm >= 0:
				zombie_animation.advance(0.2)
				zombie_animation.seek(0.0, true)
				var resting_arm = skeleton.get_bone_pose_rotation(arm)
				zombie_animation.seek(0.15, true)
				var reaching_arm = skeleton.get_bone_pose_rotation(arm)
				check(absf(resting_arm.dot(reaching_arm)) < 0.995, "zombie attack reaches with its arm")
			else:
				check(false, "zombie attack has an arm bone")
	for zombie_kind in ["runner", "bloated", "screamer"]:
		var variant = world.spawn_enemy("visual_" + zombie_kind, zombie_kind, Vector2(1200, 900), "test")
		check(variant.visual.model != null and variant.visual.model.scene_file_path == user_zombie, zombie_kind + " also uses the supplied zombie model")
		if zombie_kind == "runner":
			variant.visual.play("Run")
			check(variant.visual.animation.current_animation == "Run", "runner plays the supplied-model run clip")
		variant.queue_free()
	target.set_physics_process(false)
	var unobstructed := false
	for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var from: Vector3 = world.player.global_position + Vector3.UP * 0.85
		var ray = PhysicsRayQueryParameters3D.create(from, from + direction * 1.2, 1)
		if world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			target.global_position = world.player.global_position + direction * 1.2
			world.player_attack(direction)
			unobstructed = true
			break
	check(unobstructed and target.health < target.max_health, "directional player attack damages a nearby unobstructed enemy")
	target.queue_free()
	check(prop(world, "marta") == null and prop(world, "grom") == null and prop(world, "plot_0") == null, "NPC camp and fixed defence plots are removed")
	world.player.global_position = world._safe_player_spawn(Vector2(850, 1280)) + Vector3.UP * 0.12
	var water_before = world.count("water")
	world.interact(prop(world, "water_0"))
	check(world.count("water") == water_before + 3, "water remains renewable without an NPC camp")
	var wood_before = world.count("wood")
	var first_tree = prop(world, "tree_0")
	world.interact(first_tree)
	check(world.count("wood") > wood_before and not prop(world, "tree_0").usable, "resource harvesting and cooldown")
	var stone_before = world.count("stone")
	world.craft("axe")
	check(not world.flags.get("axe", false) and world.count("stone") == stone_before, "craft failure does not spend resources")
	world.inventory["wood"] = 50
	world.inventory["stone"] = 25
	world.inventory["cloth"] = 10
	world.craft("club")
	world.player._update_weapon()
	var bat_model = world.player.weapon_root.get_node_or_null("SuppliedBat")
	check(world.flags.get("club", false) and bat_model != null and bat_model.scene_file_path == "res://Bloody Baseball Bat with Nails.glb", "crafted bat uses the model supplied by the user")
	check(world.player.hand_attachment is BoneAttachment3D and world.player.hand_attachment.bone_name == "hand_r" and world.player.weapon_root.get_parent() == world.player.hand_attachment, "weapon is attached to the animated right hand")
	var hand_skeleton = world.player.hand_attachment.get_parent() as Skeleton3D
	var index_bone = hand_skeleton.find_bone("index_02_r")
	check(index_bone >= 0, "survivor rig has a finger bone")
	if index_bone >= 0:
		var finger_pose: Quaternion = hand_skeleton.get_bone_pose_rotation(index_bone)
		var finger_rest: Quaternion = hand_skeleton.get_bone_rest(index_bone).basis.get_rotation_quaternion()
		check(absf(finger_pose.dot(finger_rest)) < 0.98, "the survivor's animation closes the hand around the bat")
	world.player.facing = Vector3.RIGHT
	world.player.visual.rotation.y = PI / 2.0
	var bat_target = world.spawn_enemy("bat_target", "walker", world.world_to_map(world.player.global_position) + Vector2(45, 0), "test")
	bat_target.set_physics_process(false)
	var bat_hp: float = bat_target.health
	Input.action_press("attack")
	await physics_frame
	await physics_frame
	Input.action_release("attack")
	check(world.player.visual.animation.current_animation == "SwordSlash" and world.player.visual.animation.speed_scale > 2.0, "bat input starts a fast animated swing")
	check(world.player.bat_hit_pending and is_equal_approx(bat_target.health, bat_hp), "bat waits for the swing before applying damage")
	var grip_start: Vector3 = world.player.weapon_root.global_position
	await create_timer(0.25).timeout
	check(grip_start.distance_to(world.player.weapon_root.global_position) > 0.03, "bat grip moves with the animated hand")
	check(is_equal_approx(bat_target.health, bat_hp - 20.0) and not world.player.bat_hit_pending, "bat swing hits once at its impact")
	await create_timer(0.1).timeout
	check(is_equal_approx(bat_target.health, bat_hp - 20.0), "bat does not apply damage repeatedly during one swing")
	await create_timer(0.3).timeout
	Input.action_press("attack")
	await physics_frame
	await physics_frame
	Input.action_release("attack")
	check(world.player.bat_hit_pending, "another bat swing can begin after its cooldown")
	world.flags["spear"] = true
	world.switch_weapon()
	await create_timer(0.2).timeout
	check(not world.player.bat_hit_pending and is_equal_approx(bat_target.health, bat_hp - 20.0), "changing weapons cancels a queued bat hit")
	world.flags["spear"] = false
	world.equipped_weapon = "club"
	bat_target.queue_free()
	world.flags["club"] = false
	world.player._update_weapon()
	check(world.player.weapon_root.get_child_count() == 0, "unequipping removes the bat from the hand")
	world.flags["club"] = true
	world.player._update_weapon()
	world.craft("axe")
	world.craft("spear")
	world.player._update_weapon()
	check(world.flags.get("axe", false) and world.flags.get("spear", false), "tools and weapons craft successfully")
	check(world.player.current_weapon == "spear" and world.player.weapon_root.get_node_or_null("SpearShaft") != null and world.player.weapon_root.get_node_or_null("SuppliedBat") == null, "crafting the spear equips it in the hand")
	var switch_key = InputEventKey.new()
	switch_key.keycode = KEY_Q
	switch_key.physical_keycode = KEY_Q
	switch_key.pressed = true
	world._unhandled_input(switch_key)
	check(world.weapon_id() == "club" and world.player.weapon_root.get_node_or_null("SuppliedBat") != null, "Q switches from the spear back to the supplied bat")
	var selected_save = SaveGame.load_data()
	check(selected_save.get("equipped_weapon", "") == "club", "selected bat is saved")
	var choice_restore = WorldScript.new()
	choice_restore._apply_save(selected_save)
	check(choice_restore.weapon_id() == "club", "saved weapon selection is restored")
	selected_save.erase("equipped_weapon")
	choice_restore._apply_save(selected_save)
	check(choice_restore.weapon_id() == "spear", "old saves without weapon selection keep the previous spear priority")
	choice_restore.free()
	var choice_target = world.spawn_enemy("weapon_choice_target", "walker", world.world_to_map(world.player.global_position) + Vector2(45, 0), "test")
	choice_target.set_physics_process(false)
	world.player_attack(Vector3.RIGHT)
	check(is_equal_approx(choice_target.health, choice_target.max_health - 20.0), "selected bat deals bat damage even when a spear is owned")
	world._unhandled_input(switch_key)
	check(world.weapon_id() == "spear" and world.player.weapon_root.get_node_or_null("SpearShaft") != null, "Q switches back to the spear")
	world.player_attack(Vector3.RIGHT)
	check(choice_target.is_dead, "selected spear deals spear damage")
	check(world.quest_stage == 0, "survival and building do not require an NPC defence quest")
	world.interact(prop(world, "hotel"))
	check(world.quest_stage == 4 and enemy(world, "boss_hotel") != null, "hotel boss encounter starts")
	world.hud.close_modal()
	world.save_progress(false)
	var pending_boss = SaveGame.load_data()
	# A 2D-era save stores the same two map coordinates. They are mapped onto
	# the new 3D X/Z plane rather than discarded or interpreted as height.
	pending_boss["player"]["position"] = [1200, 800]
	var restored = WorldScript.new()
	restored.main = main
	restored.load_data = pending_boss
	root.add_child(restored)
	await process_frame
	check(restored.quest_stage == 4 and enemy(restored, "boss_hotel") != null, "unfinished boss survives save/load")
	var restored_map_position: Vector2 = restored.world_to_map(restored.player.global_position)
	var safe_legacy: Vector2 = restored.world_to_map(restored._safe_player_spawn(Vector2(1200, 800)))
	if restored_map_position.distance_to(safe_legacy) >= 5.0:
		print("Legacy position: expected ", safe_legacy, ", got ", restored_map_position)
	check(restored_map_position.distance_to(safe_legacy) < 5.0, "legacy save restores its safe position on the new island")
	restored.queue_free()
	await process_frame
	pending_boss["player"]["position"] = [100, 100] # water outside the new island
	var relocated = WorldScript.new()
	relocated.main = main
	relocated.load_data = pending_boss
	root.add_child(relocated)
	await process_frame
	check(relocated.environment_3d.is_walkable(relocated.player.position.x, relocated.player.position.z) and relocated.world_to_map(relocated.player.global_position).distance_to(Vector2(100, 100)) > 100.0 and relocated.quest_stage == 4, "legacy save in water moves safely to land without losing quest progress")
	relocated.queue_free()
	await process_frame
	var boss = enemy(world, "boss_hotel")
	boss.take_damage(9999, world.player.global_position)
	check(world.quest_stage == 5, "hotel boss unlocks key-card quest")
	world.interact(prop(world, "keycard"))
	world.interact(prop(world, "safe"))
	check(world.quest_stage == 6 and world.flags.get("fragment", false), "key-card opens safe and grants fragment")
	world.hud.close_modal()
	for key in ["coil", "chip", "cell"]:
		world.interact(prop(world, key))
	check(world.component_count() == 3, "all antenna components can be found")
	world.interact(prop(world, "lighthouse"))
	check(world.quest_stage == 7 and enemy(world, "boss_lighthouse") != null, "lighthouse encounter starts")
	world.hud.close_modal()
	var screamer = enemy(world, "boss_lighthouse")
	screamer.take_damage(9999, world.player.global_position)
	check(world.quest_stage == 9 and world.flags.get("lighthouse", false), "screamer defeat repairs antenna and unlocks the boat")
	world.hud.close_modal()
	world.inventory["wood"] = 15
	world.inventory["iron"] = 5
	world.inventory["cloth"] = 5
	world.interact(prop(world, "boat"))
	check(world.quest_stage == 10 and world.flags.get("boat", false), "boat completes the playable chapter")
	world.hud.close_modal()
	world.player.health = 50
	world.inventory["bandage"] = 1
	world.use_item("bandage")
	check(world.player.health == 90 and world.count("bandage") == 0, "bandage heals and is consumed")
	world.player_defeated()
	check(world.player.health > 0 and world.world_to_map(world.player.global_position).distance_to(world.STARTING_SHORE) < 150, "defeated player respawns")
	world.minute = 1201
	world.day = 2
	world._process(0.1)
	check(enemy(world, "raid_2_0") == null, "no forced camp-defence raid starts at night")
	check(world.save_progress(false), "save writes successfully")
	var saved = SaveGame.load_data()
	check(int(saved.get("quest_stage", -1)) == 10 and bool(saved.get("flags", {}).get("boat", false)), "completed story persists")
	# Exercise menu signal wiring and make sure cancellation doesn't overwrite a save.
	main.show_menu()
	await process_frame
	var menu = main.current_screen
	start = button(menu, "НОВАЯ ИГРА")
	start.pressed.emit()
	var cancel = button(menu, "ОТМЕНА")
	check(cancel != null, "new game asks before replacing a save")
	if cancel:
		cancel.pressed.emit()
	await process_frame
	check(int(SaveGame.load_data().get("quest_stage", -1)) == 10, "cancelling new game keeps the save")
	var resume = button(menu, "ПРОДОЛЖИТЬ")
	check(resume != null and not resume.disabled, "continue is enabled for an existing save")
	if resume:
		resume.pressed.emit()
	await process_frame
	world = main.current_screen
	check(world.quest_stage == 10 and world.flags.get("boat", false), "continue restores completed chapter")
	var save_abs = ProjectSettings.globalize_path(SaveGame.TEST_PATH)
	DirAccess.copy_absolute(save_abs, save_abs + ".bak")
	var broken = FileAccess.open(SaveGame.TEST_PATH, FileAccess.WRITE)
	broken.store_string("{not valid json")
	broken.close()
	check(int(SaveGame.load_data().get("quest_stage", -1)) == 10, "backup is used if the primary save is damaged")
	DirAccess.remove_absolute(save_abs + ".bak")
	check(SaveGame.load_data().is_empty(), "malformed save is rejected")
	# An existing file still requires confirmation, even if it is unreadable.
	main.show_menu()
	await process_frame
	menu = main.current_screen
	start = button(menu, "НОВАЯ ИГРА")
	start.pressed.emit()
	var confirm = button(menu, "НАЧАТЬ ЗАНОВО")
	check(confirm != null, "overwrite confirmation is available")
	if confirm:
		confirm.pressed.emit()
	await process_frame
	world = main.current_screen
	check(world.quest_stage == 0 and int(SaveGame.load_data().get("quest_stage", -1)) == 0, "confirmed new game creates a fresh save")
	DirAccess.remove_absolute(save_abs)
	# Free every node and let deferred deletion finish before quitting so the
	# headless runner does not report resources held by the active game scene.
	world.sound.stop()
	main.music.stop()
	main.queue_free()
	watchdog.queue_free()
	# AudioServer releases stopped playbacks on its mixing thread; allow it to
	# run before exiting instead of terminating immediately after this fast test.
	await create_timer(0.75).timeout
	await process_frame
	check(not is_instance_valid(main), "test scene cleans up")
	if failures.is_empty():
		print("ALL SMOKE TESTS PASSED")
		quit(0)
	else:
		print("SMOKE TESTS FAILED: ", failures)
		quit(1)
