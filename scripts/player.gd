extends CharacterBody3D

const ActorVisual = preload("res://scripts/model_3d.gd")
const MeshCleanup = preload("res://scripts/mesh_cleanup.gd")
const HERO_MODEL = "res://assets/models/characters/Casual_Male.glb"

var world
var health: float = 100.0
var stamina: float = 100.0
var hunger: float = 100.0
var thirst: float = 100.0
var facing := Vector3.FORWARD
var attack_cooldown: float = 0.0
var attack_flash: float = 0.0
var invulnerable: float = 0.0
var visual: Node3D
var camera_pivot: Node3D
var camera_arm: SpringArm3D
var camera: Camera3D
var orbit_dragging := false
var weapon_root: Node3D
var current_weapon := ""

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.35
	var collision = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.75
	collision.shape = capsule
	collision.position.y = 0.88
	add_child(collision)
	visual = ActorVisual.new()
	visual.name = "AnimatedHero"
	add_child(visual)
	visual.setup(HERO_MODEL, 0.55, Color("b98060"))
	visual.rotation.y = atan2(facing.x, facing.z)
	weapon_root = Node3D.new()
	weapon_root.position = Vector3(0.43, 0.9, 0.20)
	visual.add_child(weapon_root)
	_setup_camera()

func _setup_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position.y = 1.15
	camera_pivot.rotation.y = -0.7
	add_child(camera_pivot)
	camera_arm = SpringArm3D.new()
	camera_arm.name = "CameraArm"
	camera_arm.rotation.x = -0.30
	camera_arm.spring_length = 6.5
	camera_arm.margin = 0.15
	camera_arm.collision_mask = 1
	camera_pivot.add_child(camera_arm)
	camera = Camera3D.new()
	camera.name = "FollowCamera"
	camera.fov = 58.0
	camera.near = 0.08
	camera.far = 350.0
	camera_arm.add_child(camera)
	camera.make_current()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		orbit_dragging = event.pressed and not world.is_paused()
	elif event is InputEventMouseMotion and orbit_dragging and not world.is_paused():
		camera_pivot.rotate_y(-event.relative.x * 0.006)
		camera_arm.rotation.x = clampf(camera_arm.rotation.x - event.relative.y * 0.004, -1.05, -0.18)
	elif event is InputEventMouseButton and event.pressed and not world.is_paused():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_arm.spring_length = maxf(4.5, camera_arm.spring_length - 0.75)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_arm.spring_length = minf(13.0, camera_arm.spring_length + 0.75)

func _physics_process(delta: float) -> void:
	if world.is_paused():
		velocity = Vector3.ZERO
		orbit_dragging = false
		return
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	attack_flash = maxf(0.0, attack_flash - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	var axis = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var camera_right = camera_pivot.global_transform.basis.x
	var camera_back = camera_pivot.global_transform.basis.z
	var direction = (camera_right * axis.x + camera_back * axis.y)
	direction.y = 0
	if direction.length() > 0.01:
		direction = direction.normalized()
		facing = direction
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(facing.x, facing.z), minf(1.0, delta * 12.0))
	var running = Input.is_action_pressed("sprint") and direction.length() > 0.1 and stamina > 2.0
	var speed = 9.0 if running else 6.2
	if running:
		stamina = maxf(0.0, stamina - 23.0 * delta)
	else:
		stamina = minf(100.0, stamina + 16.0 * delta)
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = 7.0
	elif not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = -0.1
	move_and_slide()
	global_position.x = clampf(global_position.x, 120.0 * world.MAP_SCALE, 3080.0 * world.MAP_SCALE)
	global_position.z = clampf(global_position.z, 110.0 * world.MAP_SCALE, 2080.0 * world.MAP_SCALE)
	if global_position.y < -5.0:
		world.player_defeated()
	if Input.is_action_just_pressed("attack") and attack_cooldown <= 0.0:
		attack_cooldown = 0.42
		attack_flash = 0.36
		world.player_attack(facing)
	if attack_flash > 0.0:
		visual.play("SwordSlash" if world.flags.get("spear", false) else "Punch")
	elif not is_on_floor():
		visual.play("Jump")
	elif direction.length() > 0.1:
		visual.play("Run" if running else "Walk")
	else:
		visual.play("Idle")
	_update_weapon()

func _update_weapon() -> void:
	var equipped = "spear" if world.flags.get("spear", false) else ("club" if world.flags.get("club", false) else "")
	if equipped == current_weapon:
		return
	current_weapon = equipped
	for child in weapon_root.get_children():
		MeshCleanup.before_free(child)
		child.queue_free()
	if equipped.is_empty():
		return
	var shaft = CylinderMesh.new()
	shaft.top_radius = 0.045 if equipped == "spear" else 0.11
	shaft.bottom_radius = 0.05 if equipped == "spear" else 0.14
	shaft.height = 1.5 if equipped == "spear" else 0.8
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("7f5b3d")
	material.roughness = 1.0
	shaft.material = material
	var mesh = MeshInstance3D.new()
	mesh.mesh = shaft
	mesh.rotation.x = -0.45
	weapon_root.add_child(mesh)
	if equipped == "spear":
		var tip = CylinderMesh.new()
		tip.bottom_radius = 0.10
		tip.top_radius = 0.0
		tip.height = 0.35
		var metal = StandardMaterial3D.new()
		metal.albedo_color = Color("a5aaa1")
		tip.material = metal
		var point = MeshInstance3D.new()
		point.mesh = tip
		point.position = Vector3(0, 0.75, -0.36)
		point.rotation.x = -0.45
		weapon_root.add_child(point)

func take_damage(amount: float) -> void:
	if invulnerable > 0.0 or world.is_paused():
		return
	health = maxf(0.0, health - amount)
	invulnerable = 0.8
	world.play_sound("hit")
	if health <= 0.0:
		world.player_defeated()
