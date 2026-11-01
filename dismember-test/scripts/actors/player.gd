class_name SwordPlayer
extends CharacterBody3D
## Медик с мечом: ходьба от третьего лица, замах, удары по конечностям.
##
## Меч бьёт по Area3D-зонам конечностей: у руки и ноги по 3 HP, один удар
## снимает единицу. Попадание в корпус снимает 25 из 1000.

signal health_changed(player: SwordPlayer)
signal hit_landed(info: Dictionary)

const RAY_MASK := 1 | 4 | 8
const SWORD_BODY_DAMAGE := 25.0
const SWORD_LIMB_DAMAGE := 1.0
const SWING_TIME := 0.55
const SWING_CONTACT := 0.34
const WALK_SPEED := 3.6
const RUN_SPEED := 5.6
const GRAVITY := 22.0
const JUMP_SPEED := 6.0
const MOUSE_SENSITIVITY := 0.0022
const CAMERA_BASE := Vector3(0.75, 0.5, 3.4)

var max_hp := 500.0
var hp := 500.0
var spawn_point := Vector3(0.0, 1.0, 0.0)
var rig: HumanoidRig
var camera: Camera3D
var last_damage_source := ""

var _yaw: Node3D
var _pitch: Node3D
var _sword: Node3D
var _swing := -1.0
var _swing_hit := false
var _shake := 0.0
var _speed := 0.0
var _mode := "idle"


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var shape := CollisionShape3D.new()
	shape.name = "Body"
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(shape)

	rig = HumanoidRig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.build("medic", false)

	_sword = _build_sword()
	if rig.parts.has("arm_r"):
		var arm: Limb = rig.parts["arm_r"]
		arm.add_child(_sword)
		_sword.position = rig.hand_anchor("arm_r")
		_sword.rotation_degrees = Vector3(0.0, 0.0, -90.0)

	_yaw = Node3D.new()
	_yaw.name = "CameraYaw"
	_yaw.position = Vector3(0.0, 1.45, 0.0)
	add_child(_yaw)
	_pitch = Node3D.new()
	_pitch.name = "CameraPitch"
	_pitch.rotation.x = -0.1
	_yaw.add_child(_pitch)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.position = CAMERA_BASE
	camera.fov = 72.0
	camera.current = true
	_pitch.add_child(camera)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw.rotation.y -= motion.relative.x * MOUSE_SENSITIVITY
		_pitch.rotation.x = clampf(_pitch.rotation.x - motion.relative.y * MOUSE_SENSITIVITY,
			-1.15, 0.85)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_SPEED

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis := Basis(Vector3.UP, _yaw.rotation.y)
	var wish := basis * Vector3(input.x, 0.0, input.y)
	var running := Input.is_action_pressed("sprint")
	var speed := (RUN_SPEED if running else WALK_SPEED) * (0.45 if _swing >= 0.0 else 1.0)
	if wish.length() > 1.0:
		wish = wish.normalized()
	velocity.x = wish.x * speed
	velocity.z = wish.z * speed
	move_and_slide()

	if wish.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-wish.x, -wish.z), 12.0 * delta)

	_speed = Vector2(velocity.x, velocity.z).length()
	_mode = "idle" if _speed < 0.15 else ("run" if running else "walk")
	rig.animate(delta, _mode, _speed, _swing)

	if Input.is_action_just_pressed("attack") and _swing < 0.0:
		_swing = 0.0
		_swing_hit = false
	_update_swing(delta)
	_update_camera_shake(delta)


func _update_swing(delta: float) -> void:
	if _swing < 0.0:
		return
	_swing += delta / SWING_TIME
	if not _swing_hit and _swing >= SWING_CONTACT:
		_swing_hit = true
		_strike()
	if _swing >= 1.0:
		_swing = -1.0


func _strike() -> void:
	var info := aim_info()
	if info.is_empty():
		_shake = maxf(_shake, 0.05)
		return
	var zombie: Zombie = info.get("zombie", null) as Zombie
	if zombie == null:
		return
	if String(info.get("kind", "")) == "limb":
		var limb: Limb = info.get("limb", null) as Limb
		if limb == null:
			return
		var severed := zombie.damage_limb(limb.id, SWORD_LIMB_DAMAGE)
		var result := info.duplicate()
		result["severed"] = severed
		result["hp"] = limb.hp if not severed else 0.0
		hit_landed.emit(result)
		_shake = 0.28 if severed else 0.12
		if severed:
			_hit_stop(0.07)
	else:
		zombie.damage_body(SWORD_BODY_DAMAGE)
		_shake = 0.16
		var result := info.duplicate()
		result["severed"] = false
		hit_landed.emit(result)


func _hit_stop(duration: float) -> void:
	Engine.time_scale = 0.25
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func _update_camera_shake(delta: float) -> void:
	_shake = maxf(0.0, _shake - delta * 2.2)
	var offset := Vector3(
		randf_range(-_shake, _shake) * 0.12,
		randf_range(-_shake, _shake) * 0.08,
		0.0)
	camera.position = CAMERA_BASE + offset


## Что под прицелом: конечность или корпус.
func aim_info() -> Dictionary:
	var hit := _raycast()
	if hit.is_empty():
		return {}
	var collider: Object = hit.get("collider")
	if collider is Area3D and collider.has_meta("limb"):
		var limb: Limb = collider.get_meta("limb") as Limb
		if limb == null:
			return {}
		var owner_zombie: Variant = limb.get_meta("zombie", null)
		if owner_zombie == null or not is_instance_valid(owner_zombie):
			return {}
		return {
			"kind": "limb",
			"title": limb.title,
			"hp": limb.hp,
			"max": limb.max_hp,
			"limb": limb,
			"zombie": owner_zombie,
		}
	if collider is Zombie:
		var zombie := collider as Zombie
		return {
			"kind": "body",
			"title": "Корпус зомби %d" % zombie.index,
			"hp": zombie.hp,
			"max": zombie.max_hp,
			"zombie": zombie,
		}
	return {}


func _raycast() -> Dictionary:
	var origin := global_position + Vector3(0.0, 1.35, 0.0)
	var forward := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * 3.4, RAY_MASK)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


func take_damage(amount: float, source: String = "") -> void:
	last_damage_source = source
	hp = maxf(0.0, hp - amount)
	_shake = maxf(_shake, 0.35)
	health_changed.emit(self)
	if hp <= 0.0:
		_respawn()


func _respawn() -> void:
	hp = max_hp
	global_position = spawn_point
	velocity = Vector3.ZERO
	health_changed.emit(self)


func heal_full() -> void:
	hp = max_hp
	health_changed.emit(self)


func _build_sword() -> Node3D:
	var root := Node3D.new()
	root.name = "Sword"

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.82, 0.88)
	steel.metallic = 0.9
	steel.roughness = 0.22

	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.24, 0.15, 0.11)
	leather.roughness = 0.9

	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.72, 0.55, 0.25)
	brass.metallic = 0.8
	brass.roughness = 0.35

	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.045, 0.62, 0.012)
	var blade := MeshInstance3D.new()
	blade.name = "Blade"
	blade.mesh = blade_mesh
	blade.material_override = steel
	blade.position = Vector3(0.0, 0.42, 0.0)
	root.add_child(blade)

	var guard_mesh := BoxMesh.new()
	guard_mesh.size = Vector3(0.2, 0.025, 0.035)
	var guard := MeshInstance3D.new()
	guard.name = "Guard"
	guard.mesh = guard_mesh
	guard.material_override = brass
	guard.position = Vector3(0.0, 0.1, 0.0)
	root.add_child(guard)

	var handle_mesh := BoxMesh.new()
	handle_mesh.size = Vector3(0.035, 0.16, 0.035)
	var handle := MeshInstance3D.new()
	handle.name = "Handle"
	handle.mesh = handle_mesh
	handle.material_override = leather
	handle.position = Vector3(0.0, 0.02, 0.0)
	root.add_child(handle)

	return root
