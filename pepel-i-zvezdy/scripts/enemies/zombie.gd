class_name Zombie
extends CharacterBody3D
## Зомби: два варианта поведения, погоня, удары и выпадение лута.
##
## Если в assets/models/zombie.glb лежит модель из репозитория ассетов, она
## используется как тело. Модель статичная (без скелета), поэтому «анимация» —
## процедурная: покачивание и наклон при ударе.

signal died(zombie: Node)

const MODEL := "res://assets/models/zombie.glb"
const PICKUP_SCENE := preload("res://scenes/items/Pickup.tscn")
const GRAVITY := 19.0

const STATE_WANDER := 0
const STATE_CHASE := 1
const STATE_ATTACK := 2
const STATE_DEAD := 3

var variant := "walker"
var variant_name := "Ходок"
var max_health := 60.0
var health := 60.0
var chase_speed := 3.2
var wander_speed := 1.0
var attack_damage := 11.0
var attack_range := 1.9
var aggro_range := 26.0
var player: PlayerCharacter

var _state := STATE_WANDER
var _wander_target := Vector3.ZERO
var _attack_timer := 0.0
var _bob := 0.0
var _flash := 0.0
var _dead_time := 0.0
var _visual: Node3D
var _overlay: StandardMaterial3D
var _whisker: RayCast3D


func _ready() -> void:
	add_to_group("zombies")
	collision_layer = 4
	collision_mask = 1 | 2
	_apply_variant()
	_build_collision()
	_build_visual()
	_build_whisker()
	_wander_target = global_position


func _apply_variant() -> void:
	var night_scale := 1.0 + 0.12 * float(maxi(0, GameState.day_index - 1))
	if variant == "runner":
		variant_name = "Бегун"
		max_health = 40.0 * night_scale
		chase_speed = 5.0
		attack_damage = 8.0
	else:
		variant_name = "Ходок"
		max_health = 65.0 * night_scale
		chase_speed = 3.2
		attack_damage = 12.0
	health = max_health
	if GameState.is_night:
		aggro_range = 34.0


func _build_collision() -> void:
	if get_node_or_null("Collision") != null:
		return
	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	add_child(shape)


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.albedo_color = Color(1.0, 0.25, 0.15, 0.0)
	_overlay.disable_receive_shadows = true

	if ResourceLoader.exists(MODEL):
		var packed := load(MODEL) as PackedScene
		if packed != null:
			var model := packed.instantiate() as Node3D
			if model != null:
				model.scale = Vector3.ONE * 1.75
				_visual.add_child(model)
				_apply_overlay(model)
				_scale_shadow(model)
				return
	_build_procedural_visual()


func _apply_overlay(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		mesh_node.material_overlay = _overlay


func _scale_shadow(root: Node) -> void:
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _build_procedural_visual() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.33, 0.39, 0.3)
	skin.roughness = 0.95

	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.2, 0.21, 0.19)
	cloth.roughness = 1.0

	var torso := MeshInstance3D.new()
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.26
	torso_mesh.height = 1.0
	torso_mesh.radial_segments = 8
	torso_mesh.rings = 4
	torso.mesh = torso_mesh
	torso.material_override = cloth
	torso.position.y = 1.05
	_visual.add_child(torso)

	var head_node := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.18
	head_mesh.height = 0.36
	head_mesh.radial_segments = 8
	head_mesh.rings = 5
	head_node.mesh = head_mesh
	head_node.material_override = skin
	head_node.position.y = 1.62
	_visual.add_child(head_node)

	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.12, 0.62, 0.12)
		arm.mesh = arm_mesh
		arm.material_override = skin
		arm.position = Vector3(0.32 * side, 1.15, -0.38)
		arm.rotation_degrees = Vector3(-70.0, 0.0, 0.0)
		_visual.add_child(arm)

		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.16, 0.8, 0.16)
		leg.mesh = leg_mesh
		leg.material_override = cloth
		leg.position = Vector3(0.13 * side, 0.4, 0.0)
		_visual.add_child(leg)

	var eyes := MeshInstance3D.new()
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.035
	eye_mesh.height = 0.07
	eyes.mesh = eye_mesh
	var eye_material := StandardMaterial3D.new()
	eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_material.albedo_color = Color(1.0, 0.3, 0.25)
	eye_material.emission_enabled = true
	eye_material.emission = Color(1.0, 0.25, 0.2)
	eye_material.emission_energy_multiplier = 3.0
	eyes.material_override = eye_material
	eyes.position = Vector3(0.0, 1.66, -0.16)
	_visual.add_child(eyes)


func _build_whisker() -> void:
	_whisker = RayCast3D.new()
	_whisker.name = "Whisker"
	_whisker.target_position = Vector3(0.0, 0.0, -2.0)
	_whisker.position = Vector3(0.0, 1.0, 0.0)
	_whisker.collision_mask = 1
	add_child(_whisker)


func _physics_process(delta: float) -> void:
	if _state == STATE_DEAD:
		_dead_time += delta
		return
	if not GameState.run_active:
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		return

	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()
	var aggro := aggro_range * (1.35 if GameState.is_night else 1.0)

	if distance < aggro:
		_state = STATE_CHASE
	else:
		_state = STATE_WANDER

	var desired := Vector3.ZERO
	if _state == STATE_CHASE:
		if distance > attack_range * 0.85:
			desired = to_player.normalized() * chase_speed
		else:
			desired = Vector3.ZERO
			_try_attack(delta, distance)
	else:
		desired = _wander_direction() * wander_speed

	desired += _separation()

	if _whisker.is_colliding() and desired.length() > 0.1 and _state == STATE_CHASE:
		var tangent := Vector3(-desired.z, 0.0, desired.x).normalized()
		desired = (desired.normalized() + tangent * 0.8).normalized() * desired.length()

	velocity.x = lerpf(velocity.x, desired.x, clampf(7.0 * delta, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, desired.z, clampf(7.0 * delta, 0.0, 1.0))
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.15:
		var yaw := atan2(-flat.x, -flat.z)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(8.0 * delta, 0.0, 1.0))

	_bob += delta * (9.0 if _state == STATE_CHASE else 3.0)
	_animate(delta)


func _wander_direction() -> Vector3:
	var flat := _wander_target - global_position
	flat.y = 0.0
	if flat.length() < 1.5:
		_wander_target = global_position + Vector3(randf_range(-9.0, 9.0), 0.0, randf_range(-9.0, 9.0))
		return Vector3.ZERO
	return flat.normalized()


func _separation() -> Vector3:
	var push := Vector3.ZERO
	var count := 0
	for other in get_tree().get_nodes_in_group("zombies"):
		if other == self or not (other is Node3D):
			continue
		var offset := global_position - (other as Node3D).global_position
		offset.y = 0.0
		if offset.length() < 1.7 and offset.length() > 0.01:
			push += offset.normalized()
			count += 1
		if count >= 6:
			break
	if count == 0:
		return Vector3.ZERO
	return push.normalized() * 1.4


func _try_attack(delta: float, distance: float) -> void:
	_attack_timer -= delta
	if _attack_timer > 0.0 or distance > attack_range:
		return
	_attack_timer = 1.25
	_state = STATE_ATTACK
	var target_survival = player.get("survival")
	if target_survival != null and target_survival.has_method("take_damage"):
		target_survival.take_damage(attack_damage, "зомби", 0.35)
	if player.has_method("shake"):
		player.shake(0.06)


func _animate(delta: float) -> void:
	if _visual == null:
		return
	_visual.position.y = absf(sin(_bob)) * 0.05
	_visual.rotation.z = sin(_bob * 0.5) * 0.03
	if _attack_timer > 1.0:
		_visual.rotation.x = -0.18
	else:
		_visual.rotation.x = lerpf(_visual.rotation.x, 0.0, 0.15)
	if _overlay != null:
		_flash = maxf(0.0, _flash - delta * 3.0)
		_overlay.albedo_color = Color(1.0, 0.25, 0.15, _flash * 0.7)


func take_damage(amount: float, _source: Node = null) -> void:
	if _state == STATE_DEAD:
		return
	health -= amount
	_flash = 1.0
	_state = STATE_CHASE
	if health <= 0.0:
		_die()


func _die() -> void:
	_state = STATE_DEAD
	remove_from_group("zombies")
	collision_layer = 0
	set_deferred("collision_mask", 0)
	GameState.add_stat("kills", 1.0)
	_drop_loot()
	died.emit(self)
	var tween := create_tween()
	tween.set_parallel(true)
	if _visual != null:
		tween.tween_property(_visual, "rotation:z", 1.45, 0.7)
		tween.tween_property(_visual, "position:y", -0.35, 0.7)
	tween.chain().tween_callback(queue_free)


func _drop_loot() -> void:
	var table := [
		{"id": "cloth", "chance": 0.5},
		{"id": "scrap", "chance": 0.32},
		{"id": "herb", "chance": 0.22},
		{"id": "bandage", "chance": 0.12},
	]
	for entry in table:
		if randf() > float(entry["chance"]):
			continue
		var parent := get_parent()
		if parent == null:
			return
		var pickup := PICKUP_SCENE.instantiate() as Pickup
		pickup.setup(String(entry["id"]), 1)
		parent.add_child(pickup)
		pickup.global_position = global_position + Vector3(randf_range(-0.6, 0.6), 0.4, randf_range(-0.6, 0.6))
