class_name Campfire
extends Node3D
## Костёр: свет, тепло и место, где можно вскипятить воду.
##
## Ставится из набора «Набор для костра». Ночью рядом с ним тепло не уходит,
## а крафт с меткой «fire» становится доступен.

const HEAT_RADIUS := 7.0
const LIGHT_RADIUS := 12.0

var _light: OmniLight3D
var _flame: Node3D
var _time := 0.0


func _ready() -> void:
	add_to_group("campfires")
	_build()


func heat_radius() -> float:
	return HEAT_RADIUS


func get_interaction_text() -> String:
	return "[E] Костёр — согреться"


func interact(player) -> void:
	if player != null and player.has_method("warm_up"):
		player.warm_up(35.0)
	GameState.message.emit("Вы греетесь у костра. Здесь можно вскипятить воду (C).")


func _build() -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1 | 8
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.7
	cylinder.height = 0.7
	shape.shape = cylinder
	shape.position.y = 0.35
	body.add_child(shape)
	add_child(body)

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.26, 0.18, 0.12)
	wood.roughness = 0.95

	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.34, 0.33, 0.31)
	stone.roughness = 1.0

	for i in 4:
		var log_mesh := CylinderMesh.new()
		log_mesh.top_radius = 0.09
		log_mesh.bottom_radius = 0.11
		log_mesh.height = 1.1
		log_mesh.radial_segments = 6
		log_mesh.rings = 1
		var log_node := MeshInstance3D.new()
		log_node.mesh = log_mesh
		log_node.material_override = wood
		log_node.rotation_degrees = Vector3(90.0, float(i) * 45.0, 0.0)
		log_node.position = Vector3(0.0, 0.12, 0.0)
		add_child(log_node)

	for i in 8:
		var angle := TAU * float(i) / 8.0
		var rock_mesh := SphereMesh.new()
		rock_mesh.radius = 0.22
		rock_mesh.height = 0.4
		rock_mesh.radial_segments = 6
		rock_mesh.rings = 4
		var rock_node := MeshInstance3D.new()
		rock_node.mesh = rock_mesh
		rock_node.material_override = stone
		rock_node.position = Vector3(cos(angle) * 0.85, 0.1, sin(angle) * 0.85)
		add_child(rock_node)

	_flame = Node3D.new()
	_flame.name = "Flame"
	add_child(_flame)

	var flame_material := StandardMaterial3D.new()
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_material.albedo_color = Color(1.0, 0.62, 0.22, 0.9)
	flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_material.emission_enabled = true
	flame_material.emission = Color(1.0, 0.55, 0.15)
	flame_material.emission_energy_multiplier = 2.5

	for i in 3:
		var flame_mesh := SphereMesh.new()
		flame_mesh.radius = 0.22 - 0.05 * float(i)
		flame_mesh.height = 0.75 - 0.15 * float(i)
		flame_mesh.radial_segments = 7
		flame_mesh.rings = 4
		var flame_node := MeshInstance3D.new()
		flame_node.mesh = flame_mesh
		flame_node.material_override = flame_material
		flame_node.position = Vector3(0.0, 0.55 + 0.12 * float(i), 0.0)
		flame_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flame.add_child(flame_node)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.66, 0.32)
	_light.light_energy = 2.2
	_light.omni_range = LIGHT_RADIUS
	_light.position = Vector3(0.0, 0.9, 0.0)
	_light.shadow_enabled = false
	add_child(_light)


func _process(delta: float) -> void:
	_time += delta
	if _light != null:
		_light.light_energy = 2.0 + sin(_time * 9.0) * 0.25 + sin(_time * 17.0) * 0.12
	if _flame != null:
		_flame.scale = Vector3.ONE * (1.0 + sin(_time * 11.0) * 0.06)
		_flame.rotation.y = _time * 0.7
