extends SceneTree

const SaveGame = preload("res://scripts/save_game.gd")
const WorldScript = preload("res://scripts/world.gd")
var failures: Array[String] = []

func _initialize() -> void:
	# Never touch a player's normal save, even when this test is run manually.
	OS.set_environment("SHARDS_TEST_SAVE", "1")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.TEST_PATH + suffix))
	_run.call_deferred()

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

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game(false)
	await process_frame
	var world = main.current_screen
	check(world.player != null and world.hud != null, "world, player and HUD start")
	check(world.quest_stage == 0 and world.hud.is_modal_open(), "new game opens introduction")
	world.hud.close_modal()
	var start_pos: Vector2 = world.player.global_position
	Input.action_press("move_right")
	await physics_frame
	await physics_frame
	Input.action_release("move_right")
	check(world.player.global_position.x > start_pos.x, "player moves through the input map")
	world.hud.show_inventory()
	check(world.hud.is_modal_open() and world.is_paused(), "inventory opens and pauses the world")
	world.hud.close_modal()
	world.hud.show_crafting()
	check(world.hud.is_modal_open(), "crafting menu opens")
	world.hud.close_modal()
	world.hud.show_map()
	check(world.hud.is_modal_open(), "island map opens")
	world.hud.close_modal()
	var target = world.spawn_enemy("test_target", "walker", world.player.global_position + Vector2(45, 0), "test")
	world.player_attack(Vector2.RIGHT)
	check(target.health < target.max_health, "directional player attack damages a nearby enemy")
	target.queue_free()
	world.interact(prop(world, "marta"))
	check(world.quest_stage == 1, "Marta starts the defense quest")
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
	world.start_wave()
	check(world.quest_stage == 2 and world.save_progress(false), "scripted wave starts and can be saved")
	var during_wave = SaveGame.load_data()
	check(int(during_wave.get("quest_stage", -1)) == 1, "saving during raid restarts it safely")
	var wave_first = enemy(world, "wave_0")
	wave_first.global_position = world.tower_positions[0] + Vector2(100, 0)
	var old_hp: float = wave_first.health
	world._update_towers(0.1)
	check(wave_first.health < old_hp, "built tower damages enemies in range")
	for i in range(5):
		var e = enemy(world, "wave_%d" % i)
		if e: e.take_damage(9999, world.player.global_position)
	check(world.quest_stage == 3, "five defeated raiders advance the story")
	world.interact(prop(world, "hotel"))
	check(world.quest_stage == 4 and enemy(world, "boss_hotel") != null, "hotel boss encounter starts")
	world.hud.close_modal()
	world.save_progress(false)
	var pending_boss = SaveGame.load_data()
	var restored = WorldScript.new()
	restored.main = main
	restored.load_data = pending_boss
	root.add_child(restored)
	await process_frame
	check(restored.quest_stage == 4 and enemy(restored, "boss_hotel") != null, "unfinished boss survives save/load")
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
	check(world.player.health > 0 and world.player.global_position.distance_to(world.camp_position) < 150, "defeated player respawns")
	world.minute = 1201
	world.day = 2
	world.last_raid_day = 0
	world._process(0.1)
	check(world.last_raid_day == 2 and enemy(world, "raid_2_0") != null, "night raid triggers once per day")
	check(world.save_progress(false), "save writes successfully")
	var saved = SaveGame.load_data()
	check(int(saved.get("quest_stage", -1)) == 10 and bool(saved.get("flags", {}).get("boat", false)), "completed story persists")
	var save_abs = ProjectSettings.globalize_path(SaveGame.TEST_PATH)
	DirAccess.copy_absolute(save_abs, save_abs + ".bak")
	var broken = FileAccess.open(SaveGame.TEST_PATH, FileAccess.WRITE)
	broken.store_string("{not valid json")
	broken.close()
	check(int(SaveGame.load_data().get("quest_stage", -1)) == 10, "backup is used if the primary save is damaged")
	DirAccess.remove_absolute(save_abs + ".bak")
	check(SaveGame.load_data().is_empty(), "malformed save is rejected")
	DirAccess.remove_absolute(save_abs)
	# Free every node and let deferred deletion finish before quitting so the
	# headless runner does not report resources held by the active game scene.
	world.sound.stop()
	main.music.stop()
	main.queue_free()
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
