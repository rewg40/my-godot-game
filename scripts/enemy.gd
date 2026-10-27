extends CharacterBody2D

var world
var enemy_id: String = ""
var kind: String = "walker"
var group_name: String = "wild"
var health: float = 35.0
var max_health: float = 35.0
var speed: float = 61.0
var damage: float = 8.0
var animation_clock: float = 0.0
var hit_flash: float = 0.0
var attack_timer: float = 0.0
var call_timer: float = 8.0
var is_dead: bool = false
var sprite: Sprite2D
var facing = Vector2.DOWN
var knockback = Vector2.ZERO

func configure(owner_world, identity: String, enemy_kind: String, enemy_group: String) -> void:
	world = owner_world
	enemy_id = identity
	kind = enemy_kind
	group_name = enemy_group
	match kind:
		"runner":
			max_health = 28.0; speed = 112.0; damage = 8.0
		"bloated":
			max_health = 115.0; speed = 44.0; damage = 14.0
		"screamer":
			max_health = 95.0; speed = 66.0; damage = 9.0
		_:
			max_health = 38.0; speed = 60.0; damage = 7.0
	health = max_health

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 18.0 if kind == "bloated" else 12.0
	shape.shape = circle
	shape.position.y = -4
	add_child(shape)
	sprite = Sprite2D.new()
	sprite.texture = load("res://assets/sprites/zombie.png")
	sprite.hframes = 4
	sprite.vframes = 7
	var size = 5.6 if kind == "bloated" else (4.5 if kind == "screamer" else 4.0)
	sprite.scale = Vector2(size, size)
	sprite.offset = Vector2(0, -7)
	if kind == "runner":
		sprite.modulate = Color(0.9, 0.9, 0.75)
	elif kind == "screamer":
		sprite.modulate = Color(0.77, 0.95, 0.9)
	add_child(sprite)

func _physics_process(delta: float) -> void:
	if world.is_paused() or is_dead:
		return
	attack_timer = maxf(0.0, attack_timer - delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	call_timer -= delta
	var target = world.player.global_position
	var distance_to_player = global_position.distance_to(target)
	var aggressive = distance_to_player < (380.0 if world.is_night() else 295.0)
	if group_name in ["wave", "raid"] and distance_to_player > 175.0:
		target = world.camp_position
		aggressive = true
	var distance = global_position.distance_to(target)
	if aggressive and distance > 38.0:
		facing = (target - global_position).normalized()
		velocity = facing * speed + knockback
	else:
		velocity = knockback
	knockback = knockback.move_toward(Vector2.ZERO, 700.0 * delta)
	move_and_slide()
	if aggressive and distance <= 48.0 and attack_timer <= 0.0:
		attack_timer = 1.15
		if target == world.camp_position and global_position.distance_to(world.camp_position) < 55.0:
			world.damage_camp(damage)
		else:
			world.player.take_damage(damage)
	if kind == "screamer" and aggressive and call_timer <= 0.0:
		call_timer = 11.0
		world.screamer_call(global_position)
	animation_clock += delta * (7.0 if aggressive else 2.0)
	var col = 0
	if absf(facing.x) > absf(facing.y):
		col = 3 if facing.x > 0 else 2
	else:
		col = 0 if facing.y > 0 else 1
	var row = int(animation_clock) % 4 if velocity.length() > 4 else 0
	if attack_timer > 0.95:
		row = 4
	sprite.frame_coords = Vector2i(col, row)
	if hit_flash > 0.0:
		sprite.modulate = Color(1.8, 1.3, 1.2)
	elif kind == "runner":
		sprite.modulate = Color(0.9, 0.9, 0.75)
	elif kind == "screamer":
		sprite.modulate = Color(0.77, 0.95, 0.9)
	else:
		sprite.modulate = Color.WHITE
	queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.45))
	draw_circle(Vector2.ZERO, 17, Color(0.02, 0.06, 0.05, 0.4))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if health < max_health:
		var width = 46.0 if kind in ["bloated", "screamer"] else 32.0
		draw_rect(Rect2(-width/2, -80 if kind == "bloated" else -62, width, 5), Color("263b36"))
		draw_rect(Rect2(-width/2, -80 if kind == "bloated" else -62, width * maxf(health, 0.0) / max_health, 5), Color("d27660"))

func take_damage(amount: float, from_pos: Vector2) -> void:
	if is_dead:
		return
	health -= amount
	hit_flash = 0.16
	knockback = (global_position - from_pos).normalized() * 150.0
	if health <= 0.0:
		is_dead = true
		if kind == "bloated" and global_position.distance_to(world.player.global_position) < 95.0:
			world.player.take_damage(15.0)
		world.enemy_defeated(self)
		queue_free()
