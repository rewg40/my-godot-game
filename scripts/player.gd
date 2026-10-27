extends CharacterBody2D

var world
var health: float = 100.0
var stamina: float = 100.0
var hunger: float = 100.0
var thirst: float = 100.0
var facing = Vector2.DOWN
var attack_cooldown: float = 0.0
var attack_flash: float = 0.0
var invulnerable: float = 0.0
var animation_clock: float = 0.0
var sprite: Sprite2D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var collision = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 13.0
	collision.shape = circle
	collision.position = Vector2(0, -5)
	add_child(collision)
	sprite = Sprite2D.new()
	sprite.texture = load("res://assets/sprites/player.png")
	sprite.hframes = 4
	sprite.vframes = 7
	sprite.scale = Vector2(4, 4)
	sprite.offset = Vector2(0, -7)
	add_child(sprite)
	var camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = 3200
	camera.limit_bottom = 2200
	add_child(camera)
	camera.make_current()

func _physics_process(delta: float) -> void:
	if world.is_paused():
		velocity = Vector2.ZERO
		return
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	attack_flash = maxf(0.0, attack_flash - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction.length() > 0.01:
		facing = direction.normalized()
	var running = Input.is_action_pressed("sprint") and direction.length() > 0.1 and stamina > 2.0
	var speed = 225.0 if running else 155.0
	if running:
		stamina = maxf(0.0, stamina - 23.0 * delta)
	else:
		stamina = minf(100.0, stamina + 16.0 * delta)
	velocity = direction * speed
	move_and_slide()
	global_position.x = clampf(global_position.x, 120, 3080)
	global_position.y = clampf(global_position.y, 110, 2080)
	if Input.is_action_just_pressed("attack") and attack_cooldown <= 0.0:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var aim = get_global_mouse_position() - global_position
			if aim.length() > 14.0:
				facing = aim.normalized()
		attack_cooldown = 0.42
		attack_flash = 0.18
		world.player_attack(facing)
	animation_clock += delta * 8.0
	var direction_frame = 0
	if absf(facing.x) > absf(facing.y):
		direction_frame = 3 if facing.x > 0 else 2
	else:
		direction_frame = 0 if facing.y > 0 else 1
	var anim_row = 0
	if attack_flash > 0:
		anim_row = 4
	elif direction.length() > 0.1:
		anim_row = int(animation_clock) % 4
	sprite.frame_coords = Vector2i(direction_frame, anim_row)
	sprite.modulate = Color(1.0, 0.55, 0.50) if invulnerable > 0.25 and int(invulnerable * 15.0) % 2 == 0 else Color.WHITE
	queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2(0, 0), 0.0, Vector2(1, 0.45))
	draw_circle(Vector2(0, 0), 19, Color(0.02, 0.08, 0.07, 0.38))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if attack_flash > 0:
		var angle = facing.angle()
		draw_arc(Vector2(0, -12), 58, angle - 0.7, angle + 0.7, 12, Color(1.0, 0.87, 0.57, 0.85), 5.0, true)

func take_damage(amount: float) -> void:
	if invulnerable > 0.0 or world.is_paused():
		return
	health = maxf(0.0, health - amount)
	invulnerable = 0.8
	world.play_sound("hit")
	if health <= 0.0:
		world.player_defeated()
