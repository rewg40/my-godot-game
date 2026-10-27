extends SceneTree

const SaveGame = preload("res://scripts/save_game.gd")
const WorldScript = preload("res://scripts/world.gd")
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
	check(terrain.mesh.surface_get_material(0) is ShaderMaterial, "terrain uses blended photographic surface materials")
	var grass = world.environment_3d.get_node_or_null("GrassCover")
	check(grass is MultiMeshInstance3D and grass.multimesh.instance_count > 500, "3D grass is batched across the island")
	var weeds = world.environment_3d.get_node_or_null("GroundWeeds")
	check(weeds is MultiMeshInstance3D and weeds.multimesh.instance_count > 300, "broad-leaved ground vegetation is batched")
	var forest = world.environment_3d.get_node_or_null("ForestColliders")
	check(forest is StaticBody3D and forest.get_child_count() > 0, "3D forest trunks have physical collision")
	check(world.environment_3d.get_node_or_null("ForestBroadleaf") is Node3D, "forest includes photoreal broadleaf trees")
	check(world.player.visual.animation != null and world.player.visual.animation.has_animation("Walk"), "rigged 3D hero has a walking animation")
	check(world.player.visual.animation.get_animation("Walk").get_track_count() > 10, "walking animation contains skeletal tracks")
	check(not world.player.visual.model.find_children("*", "Skeleton3D", true, false).is_empty(), "survivor has a 3D skeleton")
	check(world.player.visual.animation != null and world.player.visual.animation.has_animation("ZombieWalk"), "character rig also contains infected animations")
	var has_clothing_shader = false
	for instance in world.player.visual.model.find_children("*", "MeshInstance3D", true, false):
		for surface in range(instance.mesh.get_surface_count()):
			if instance.get_surface_override_material(surface) is ShaderMaterial:
				has_clothing_shader = true
	check(has_clothing_shader, "survivor body has the clothing material")
	check(world.player.camera_arm.rotation.x < deg_to_rad(-50.0) and world.player.camera_arm.spring_length >= 12.0, "default perspective camera provides a high survival-game overview")
	check(world.get_node_or_null("RoadsideDetails/RoadDebris") is MultiMeshInstance3D, "roadside debris is present")
	check(world.quest_stage == 0 and world.hud.is_modal_open(), "new game opens introduction")
	world.hud.close_modal()
	await create_timer(0.35).timeout
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
			print("ZOMBIE_POSES first=", first_pose, " second=", second_pose)
			check(absf(first_pose.dot(second_pose)) < 0.999, "zombie walk actually moves its leg bones")
			target.visual.play("Punch")
			check(zombie_animation.current_animation == "ZombieAttack", "zombie attack plays the supplied-model animation")
	for zombie_kind in ["runner", "bloated", "screamer"]:
		var variant = world.spawn_enemy("visual_" + zombie_kind, zombie_kind, Vector2(1200, 900), "test")
		check(variant.visual.model != null and variant.visual.model.scene_file_path == user_zombie, zombie_kind + " also uses the supplied zombie model")
		if zombie_kind == "runner":
			variant.visual.play("Run")
			check(variant.visual.animation.current_animation == "Run", "runner plays the supplied-model run clip")
		variant.queue_free()
	world.player_attack(Vector3.RIGHT)
	check(target.health < target.max_health, "directional player attack damages a nearby enemy")
	target.queue_free()
	var marta = prop(world, "marta")
	check(marta.idle_actor.animation != null and marta.idle_actor.animation.has_animation("Walk"), "female survivor rig imports its animations")
	world.player.global_position = marta.global_position + Vector3(0, 0, -2.4)
	check(world.nearest_prop() == marta, "nearby interaction selects Marta")
	var interact_key = InputEventKey.new()
	interact_key.keycode = KEY_E
	interact_key.physical_keycode = KEY_E
	interact_key.pressed = true
	Input.parse_input_event(interact_key)
	Input.flush_buffered_events()
	var release_key = InputEventKey.new()
	release_key.keycode = KEY_E
	release_key.physical_keycode = KEY_E
	release_key.pressed = false
	Input.parse_input_event(release_key)
	Input.flush_buffered_events()
	check(world.quest_stage == 1 and world.hud.is_modal_open(), "E opens Marta's defense quest")
	world.hud.close_modal()
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
	world.craft("axe")
	world.craft("spear")
	check(world.flags.get("axe", false) and world.flags.get("spear", false), "tools and weapons craft successfully")
	for i in range(3):
		world.interact(prop(world, "plot_%d" % i))
	check(world.tower_count() == 3, "three towers can be built")
	check(prop(world, "plot_0").find_children("*", "StaticBody3D", true, false).size() > 0, "built tower has 3D collision")
	world.interact(marta)
	var begin_defense = button(world.hud.modal, "НАЧАТЬ ОБОРОНУ")
	check(begin_defense != null, "Marta offers the defense after three towers")
	if begin_defense:
		begin_defense.pressed.emit()
	check(world.quest_stage == 2 and world.save_progress(false), "dialogue starts the scripted wave and it can be saved")
	var during_wave = SaveGame.load_data()
	check(int(during_wave.get("quest_stage", -1)) == 1, "saving during raid restarts it safely")
	var wave_first = enemy(world, "wave_0")
	wave_first.global_position = world.map_to_world(world.tower_positions[0] + Vector2(100, 0)) + Vector3.UP * 0.12
	var old_hp: float = wave_first.health
	world._update_towers(0.1)
	check(wave_first.health < old_hp, "built tower damages enemies in range")
	# Let the actual physics, enemy AI and towers resolve the wave rather than
	# instantly defeating the enemies. Only protect the idle test player.
	world.player.global_position = world.map_to_world(world.camp_position + Vector2(0, 60)) + Vector3.UP * 0.12
	world.player.invulnerable = 999.0
	Engine.time_scale = 2.0
	for i in range(25):
		await create_timer(1.0).timeout
		if world.quest_stage != 2:
			break
	Engine.time_scale = 1.0
	world.player.invulnerable = 0.0
	if world.quest_stage != 3 or world.wave_kills != 5:
		print("Wave diagnostics: stage=", world.quest_stage, " kills=", world.wave_kills, " camp_hp=", world.camp_health)
		for raider in world.enemies:
			if is_instance_valid(raider) and raider.group_name == "wave" and not raider.is_dead:
				print("  ", raider.enemy_id, " map=", world.world_to_map(raider.global_position), " hp=", raider.health, " floor=", raider.is_on_floor())
	check(world.quest_stage == 3 and world.wave_kills == 5, "AI and towers defeat all five raiders and advance the story")
	if world.quest_stage != 3:
		# Preserve the failed assertion while allowing later systems to be tested.
		world.quest_stage = 3
	world.interact(prop(world, "hotel"))
	check(world.quest_stage == 4 and enemy(world, "boss_hotel") != null, "hotel boss encounter starts")
	world.hud.close_modal()
	world.save_progress(false)
	var pending_boss = SaveGame.load_data()
	# A 2D-era save stores the same two map coordinates. They are mapped onto
	# the new 3D X/Z plane rather than discarded or interpreted as height.
	pending_boss["player"]["position"] = [1200, 900]
	var restored = WorldScript.new()
	restored.main = main
	restored.load_data = pending_boss
	root.add_child(restored)
	await process_frame
	check(restored.quest_stage == 4 and enemy(restored, "boss_hotel") != null, "unfinished boss survives save/load")
	var restored_map_position: Vector2 = restored.world_to_map(restored.player.global_position)
	if restored_map_position.distance_to(Vector2(1200, 900)) >= 5.0:
		print("Legacy position: expected (1200, 900), got ", restored_map_position)
	check(restored_map_position.distance_to(Vector2(1200, 900)) < 5.0, "legacy 2D save position maps to 3D terrain")
	restored.queue_free()
	await process_frame
	var boss = enemy(world, "boss_hotel")
	boss.take_damage(9999, world.player.global_position)
	check(world.quest_stage == 5, "hotel boss unlocks key-card quest")
	world.interact(prop(world, "keycard"))
	world.interact(prop(world, "safe"))
	check(world.quest_stage == 6 and world.flags.get("fragment", false), "key-card opens safe and grants fragment")
	world.hud.close_modal()
	world.interact(prop(world, "tim"))
	world.hud.close_modal()
	world.interact(prop(world, "teddy"))
	world.interact(prop(world, "tim"))
	check(world.side_stage == 3, "Tim's side quest can be completed")
	world.hud.close_modal()
	for key in ["coil", "chip", "cell"]:
		world.interact(prop(world, key))
	check(world.component_count() == 3, "all antenna components can be found")
	world.interact(prop(world, "lighthouse"))
	check(world.quest_stage == 7 and enemy(world, "boss_lighthouse") != null, "lighthouse encounter starts")
	world.hud.close_modal()
	var screamer = enemy(world, "boss_lighthouse")
	screamer.take_damage(9999, world.player.global_position)
	check(world.quest_stage == 8 and world.flags.get("lighthouse", false), "screamer defeat repairs antenna")
	world.hud.close_modal()
	world.interact(prop(world, "grom"))
	check(world.quest_stage == 9, "Grom unlocks boat repair")
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
	check(world.player.health > 0 and world.world_to_map(world.player.global_position).distance_to(world.camp_position) < 150, "defeated player respawns")
	world.minute = 1201
	world.day = 2
	world.last_raid_day = 0
	world._process(0.1)
	check(world.last_raid_day == 2 and enemy(world, "raid_2_0") != null, "night raid triggers once per day")
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
