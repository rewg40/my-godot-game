extends Node3D

## A separate, non-saving walkthrough of the 900 x 350 m airfield scene.
## It deliberately does not move or alter the current island or its save.
const PlayerScript = preload("res://scripts/player.gd")
const UI = preload("res://scripts/ui_style.gd")
const MeshCleanup = preload("res://scripts/mesh_cleanup.gd")
const AIRFIELD_SCENE := "res://scenes/airfield_full.tscn"

class PreviewBuildMode:
	extends RefCounted
	var active := false

var main: Node
var player: CharacterBody3D
var field: Node3D
var building := PreviewBuildMode.new()


func _ready() -> void:
	name = "AirfieldWalkthrough"
	_ensure_input_actions()
	var packed := load(AIRFIELD_SCENE) as PackedScene
	if packed == null:
		push_error("Airfield scene is missing: " + AIRFIELD_SCENE)
		return
	field = packed.instantiate() as Node3D
	add_child(field)
	_setup_environment()
	player = PlayerScript.new()
	player.name = "Visitor"
	player.world = self
	player.position = field.get_node("SpawnAndLootMarkers/VisitorSpawn").position
	add_child(player)
	player.camera.far = 1200.0
	_setup_overlay()


func _exit_tree() -> void:
	MeshCleanup.before_free(self)


func _ensure_input_actions() -> void:
	# Main normally registers these; this also allows F6 on the walkthrough
	# scene directly without requiring the main menu to have run first.
	var actions := {
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT], "jump": [KEY_SPACE], "attack": [KEY_F],
	}
	for action in actions:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for code in actions[action]:
			var event := InputEventKey.new()
			event.physical_keycode = code
			InputMap.action_add_event(action, event)


func _setup_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("536b72")
	sky_material.sky_horizon_color = Color("bac0ad")
	sky_material.ground_bottom_color = Color("4b5549")
	sky_material.ground_horizon_color = Color("9ca590")
	var sky := Sky.new()
	sky.sky_material = sky_material
	var settings := Environment.new()
	settings.background_mode = Environment.BG_SKY
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("cbd2be")
	settings.ambient_light_energy = 0.56
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.adjustment_enabled = true
	settings.adjustment_saturation = 0.9
	settings.fog_enabled = true
	settings.fog_light_color = Color("a1aca0")
	settings.fog_density = 0.0015
	var atmosphere := WorldEnvironment.new()
	atmosphere.name = "PreviewEnvironment"
	atmosphere.environment = settings
	add_child(atmosphere)
	var sun := DirectionalLight3D.new()
	sun.name = "PreviewSun"
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("f1e7d4")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	add_child(sun)


func _setup_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "WalkthroughHUD"
	add_child(layer)
	var panel := UI.panel()
	panel.position = Vector2(18, 16)
	layer.add_child(panel)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 5)
	panel.add_child(lines)
	lines.add_child(UI.label("АЭРОДРОМ  /  РЕЖИМ ОСМОТРА", 16, UI.GOLD, true))
	lines.add_child(UI.label("WASD — движение   ·   Shift — бег   ·   ПКМ — камера   ·   Esc — назад", 13, UI.TEXT))
	lines.add_child(UI.label("Отдельная сцена: игровой прогресс и сохранения не меняются.", 12, UI.MUTED))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if is_instance_valid(main):
			main.show_menu()
		else:
			get_tree().quit()


func clamp_player_position(point: Vector3) -> Vector3:
	# Stay on the physical ground, including the perimeter and both entrances.
	return Vector3(clampf(point.x, -448.5, 448.5), point.y, clampf(point.z, -173.5, 173.5))


func is_paused() -> bool:
	return false


func weapon_id() -> String:
	return "club" # Same supplied bat model and animation; no combat in the viewer.


func player_attack(_direction: Vector3) -> void:
	pass


func player_defeated() -> void:
	if is_instance_valid(player) and is_instance_valid(field):
		player.global_position = field.get_node("SpawnAndLootMarkers/VisitorSpawn").global_position
		player.velocity = Vector3.ZERO
		player.health = 100.0


func play_sound(_effect: String) -> void:
	pass
