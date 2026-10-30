extends SceneTree

# Smoke test for the standalone subset archive after a clean Godot import.
const MeshCleanup = preload("res://scripts/mesh_cleanup.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed := load("res://scenes/airfield_walkthrough.tscn") as PackedScene
	if packed == null:
		push_error("Standalone walkthrough scene failed to load")
		quit(1)
		return
	var preview = packed.instantiate()
	root.add_child(preview)
	await physics_frame
	await process_frame
	if not is_instance_valid(preview.player) or not is_instance_valid(preview.field):
		push_error("Standalone walkthrough has no visitor or airfield")
		quit(1)
		return
	if preview.field.get_node_or_null("Ground/Runway") == null or preview.player.visual.animation == null:
		push_error("Standalone walkthrough is missing the runway or animated hero")
		quit(1)
		return
	MeshCleanup.before_free(preview)
	preview.free()
	await process_frame
	print("AIRFIELD PACKAGE TESTS PASSED")
	quit(0)
