extends CharacterBody3D

const ActorVisual = preload("res://scripts/model_3d.gd")
const MeshCleanup = preload("res://scripts/mesh_cleanup.gd")
const ZOMBIE_MODEL = "res://assets/models/characters/Zombie_Male.glb"
const FONT = preload("res://assets/fonts/DejaVuSans-Bold.ttf")

var world
var enemy_id: String = ""
var kind: String = "walker"
var group_name: String = "wild"
var health: float = 35.0
var max_health: float = 35.0
var speed: float = 2.4
var damage: float = 8.0
var hit_flash: float = 0.0
var attack_timer: float = 0.0
var call_timer: float = 8.0
var is_dead: bool = false
var facing := Vector3.FORWARD
var knockback := Vector3.ZERO
var visual: Node3D
var name_label: Label3D

func configure(owner_world, identity: String, enemy_kind: String, enemy_group: String) -> void:
	world = owner_world
	enemy_id = identity
	kind = enemy_kind
	group_name = enemy_group
	match kind:
		"runner":
			max_health = 28.0; speed = 4.48; damage = 8.0
		"bloated":
			max_health = 115.0; speed = 1.76; damage = 14.0
		"screamer":
			max_health = 95.0; speed = 2.64; damage = 9.0
		_:
			max_health = 38.0; speed = 2.4; damage = 7.0
	health = max_health

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.35
	var collision = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.56 if kind == "bloated" else 0.37
	capsule.height = 2.25 if kind == "bloated" else 1.75
	collision.shape = capsule
	collision.position.y = capsule.height / 2.0
	add_child(collision)
	visual = ActorVisual.new()
	visual.name = "AnimatedInfected"
	add_child(visual)
	var model_scale = 0.78 if kind == "bloated" else (0.64 if kind == "screamer" else 0.55)
	visual.setup(ZOMBIE_MODEL, model_scale)
	if group_name == "boss":
		name_label = Label3D.new()
		name_label.text = "РАЗДУТЫЙ" if kind == "bloated" else "КРИКУН"
		name_label.font = FONT
		name_label.font_size = 32
		name_label.pixel_size = 0.0045
		name_label.outline_size = 7
		name_label.modulate = Color("ef9a83")
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.position.y = 3.0 if kind == "bloated" else 2.5
		add_child(name_label)

func _exit_tree() -> void:
	MeshCleanup.before_free(self)

func _physics_process(delta: float) -> void:
	if world.is_paused() or is_dead:
		velocity = Vector3.ZERO
		return
	attack_timer = maxf(0.0, attack_timer - delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	call_timer -= delta
	var target: Vector3 = world.player.global_position
	var offset_to_player = target - global_position
	offset_to_player.y = 0
	var distance_to_player = offset_to_player.length()
	var aggressive = distance_to_player < (15.2 if world.is_night() else 11.8)
	var attacking_camp = false
	if group_name in ["wave", "raid"] and distance_to_player > 7.0:
		target = world.map_to_world(world.camp_position)
		aggressive = true
		attacking_camp = true
	var offset = target - global_position
	offset.y = 0
	var distance = offset.length()
	if aggressive and distance > 1.52:
		facing = offset.normalized()
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(facing.x, facing.z), minf(1.0, delta * 7.0))
		velocity.x = facing.x * speed + knockback.x
		velocity.z = facing.z * speed + knockback.z
	else:
		velocity.x = knockback.x
		velocity.z = knockback.z
	knockback = knockback.move_toward(Vector3.ZERO, 28.0 * delta)
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = -0.1
	move_and_slide()
	if aggressive and distance <= 1.92 and attack_timer <= 0.0:
		attack_timer = 1.15
		if attacking_camp and distance < 2.2:
			world.damage_camp(damage)
		else:
			world.player.take_damage(damage)
	if kind == "screamer" and aggressive and call_timer <= 0.0:
		call_timer = 11.0
		world.screamer_call(global_position)
	if attack_timer > 0.83:
		visual.play("Punch")
	elif aggressive and distance > 1.52:
		visual.play("Run" if kind == "runner" else "Walk")
	else:
		visual.play("Idle")

func take_damage(amount: float, from_pos: Vector3) -> void:
	if is_dead:
		return
	health -= amount
	hit_flash = 0.16
	knockback = global_position - from_pos
	knockback.y = 0
	knockback = knockback.normalized() * 6.0
	if health <= 0.0:
		is_dead = true
		var from_player = global_position - world.player.global_position
		from_player.y = 0
		if kind == "bloated" and from_player.length() < 3.8:
			world.player.take_damage(15.0)
		world.enemy_defeated(self)
		queue_free()
