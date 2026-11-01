class_name PlayerCharacter
extends CharacterBody3D
## Игрок от первого лица.
##
## Узел сам собирает себя: капсулу-коллайдер, голову с камерой, луч
## взаимодействия и дочерние узлы Survival/Inventory. Благодаря этому сцена
## Player.tscn остаётся крошечной, а всё поведение живёт в коде.

const WALK_SPEED := 4.3
const SPRINT_SPEED := 7.4
const CROUCH_SPEED := 2.2
const JUMP_VELOCITY := 5.6
const GRAVITY := 19.0
const MOUSE_SENSITIVITY := 0.0022
const INTERACT_DISTANCE := 3.4
const HEAD_HEIGHT := 1.62
const CROUCH_HEAD_HEIGHT := 1.05
const HOTBAR_SIZE := 5

var survival: Survival
var inventory: Inventory
var head: Node3D
var camera: Camera3D
var ray: RayCast3D
var torch_light: OmniLight3D

var weapon_id := "fists"
var attack_cooldown := 0.0

var _pitch := 0.0
var _kick := 0.0
var _bob_time := 0.0
var _sprinting := false
var _crouching := false
var _head_target := HEAD_HEIGHT


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4

	_build_collision()
	_build_head()
	_build_nodes()
	_apply_class()
	apply_settings()
	survival.died.connect(_on_died)


func _build_collision() -> void:
	if get_node_or_null("Collision") != null:
		return
	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.78
	shape.shape = capsule
	shape.position.y = 0.89
	add_child(shape)


func _build_head() -> void:
	head = get_node_or_null("Head") as Node3D
	if head == null:
		head = Node3D.new()
		head.name = "Head"
		head.position.y = HEAD_HEIGHT
		add_child(head)

	camera = head.get_node_or_null("Camera") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera"
		camera.current = true
		camera.fov = 78.0
		camera.near = 0.05
		camera.far = 1400.0
		head.add_child(camera)
	camera.current = true

	ray = camera.get_node_or_null("InteractRay") as RayCast3D
	if ray == null:
		ray = RayCast3D.new()
		ray.name = "InteractRay"
		ray.target_position = Vector3(0.0, 0.0, -INTERACT_DISTANCE)
		ray.collide_with_areas = true
		ray.collide_with_bodies = true
		ray.collision_mask = 1 | 4 | 8
		camera.add_child(ray)

	torch_light = head.get_node_or_null("TorchLight") as OmniLight3D
	if torch_light == null:
		torch_light = OmniLight3D.new()
		torch_light.name = "TorchLight"
		torch_light.light_color = Color(1.0, 0.72, 0.4)
		torch_light.light_energy = 1.8
		torch_light.omni_range = 9.0
		torch_light.visible = false
		head.add_child(torch_light)


func _build_nodes() -> void:
	survival = get_node_or_null("Survival")
	if survival == null:
		survival = preload("res://scripts/player/survival.gd").new() as Survival
		survival.name = "Survival"
		add_child(survival)

	inventory = get_node_or_null("Inventory")
	if inventory == null:
		inventory = preload("res://scripts/player/inventory.gd").new() as Inventory
		inventory.name = "Inventory"
		add_child(inventory)


func _apply_class() -> void:
	var data := ItemDB.class_data(GameState.selected_class)
	survival.apply_class(GameState.selected_class)
	inventory.setup(data.get("start", {}))
	weapon_id = "fists"
	for slot in inventory.slots:
		if slot.is_empty():
			continue
		var id := String(slot["id"])
		if ItemDB.is_weapon(id):
			weapon_id = id
			break
	_refresh_weapon_visuals()


func apply_settings() -> void:
	if camera == null:
		return
	camera.fov = float(GameState.settings.get("fov", 78.0))


# --- Движение ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if attack_cooldown > 0.0:
		attack_cooldown = maxf(0.0, attack_cooldown - delta)
	if not GameState.run_active or GameState.ui_open:
		velocity.x = 0.0
		velocity.z = 0.0
		if is_on_floor():
			velocity.y = 0.0
		move_and_slide()
		return

	_crouching = Input.is_action_pressed("crouch")
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()

	_sprinting = false
	var wants_sprint := Input.is_action_pressed("sprint") and input.length() > 0.1 and not _crouching
	if wants_sprint and float(survival.stamina) > 5.0 and is_on_floor():
		_sprinting = survival.spend_stamina(14.0 * delta)

	var speed := WALK_SPEED
	if _sprinting:
		speed = SPRINT_SPEED
	elif _crouching:
		speed = CROUCH_SPEED
	if float(survival.hunger) <= 0.0:
		speed *= 0.8

	var acceleration := 12.0 if is_on_floor() else 3.5
	var blend := clampf(acceleration * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, wish.x * speed, blend)
	velocity.z = lerpf(velocity.z, wish.z * speed, blend)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump") and float(survival.stamina) > 10.0:
		velocity.y = JUMP_VELOCITY
		survival.spend_stamina(10.0)

	move_and_slide()
	GameState.add_stat("distance", velocity.length() * delta)

	if global_position.y < -4.0:
		_wash_ashore()

	_handle_actions()
	_head_target = CROUCH_HEAD_HEIGHT if _crouching else HEAD_HEIGHT


func _handle_actions() -> void:
	if Input.is_action_just_pressed("attack") and attack_cooldown <= 0.0:
		_attack()
	if Input.is_action_just_pressed("interact"):
		_interact()
	for i in HOTBAR_SIZE:
		if Input.is_action_just_pressed("use_slot_%d" % (i + 1)):
			use_slot(i)


func _process(delta: float) -> void:
	if head == null:
		return
	head.position.y = lerpf(head.position.y, _head_target, clampf(10.0 * delta, 0.0, 1.0))
	_kick = lerpf(_kick, 0.0, clampf(9.0 * delta, 0.0, 1.0))
	head.rotation.x = _pitch + _kick

	if _sprinting and is_on_floor():
		_bob_time += delta * 11.0
	elif velocity.length() > 0.5 and is_on_floor():
		_bob_time += delta * 7.0
	var bob := sin(_bob_time) * 0.025
	camera.position = Vector3(0.0, bob, 0.0)


func is_sprinting() -> bool:
	return _sprinting


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if not GameState.run_active or GameState.ui_open:
		return
	var motion := event as InputEventMouseMotion
	var sensitivity := MOUSE_SENSITIVITY * float(GameState.settings.get("sensitivity", 1.0))
	var invert := -1.0 if bool(GameState.settings.get("invert_y", false)) else 1.0
	rotate_y(-motion.relative.x * sensitivity)
	_pitch = clampf(_pitch + motion.relative.y * sensitivity * invert,
			deg_to_rad(-88.0), deg_to_rad(88.0))


# --- Действия ---------------------------------------------------------------

func _attack() -> void:
	var item := ItemDB.get_item(weapon_id)
	var damage := float(item.get("damage", 8.0))
	damage *= float(GameState.class_data().get("damage_mult", 1.0))
	attack_cooldown = float(item.get("cooldown", 0.55))
	survival.spend_stamina(5.0)
	_kick = 0.045

	ray.force_raycast_update()
	if not ray.is_colliding():
		return
	var target := ray.get_collider()
	if target != null and target.has_method("take_damage"):
		target.take_damage(damage, self)


func _interact() -> void:
	ray.force_raycast_update()
	if not ray.is_colliding():
		return
	var target := ray.get_collider()
	if target != null and target.has_method("interact"):
		target.interact(self)


func get_interaction_target() -> Node:
	if ray == null:
		return null
	ray.force_raycast_update()
	if not ray.is_colliding():
		return null
	var target := ray.get_collider()
	if target != null and target.has_method("get_interaction_text"):
		return target
	return null


func use_slot(index: int) -> void:
	var slot: Dictionary = inventory.slot_at(index)
	if slot.is_empty():
		return
	var id := String(slot["id"])
	if ItemDB.is_weapon(id):
		equip(id)
	elif ItemDB.is_consumable(id):
		if bool(survival.consume(id)):
			inventory.remove(id, 1)
			GameState.message.emit("Использовано: %s" % ItemDB.display_name(id))
	elif id == "campfire_kit":
		_place_campfire()
	else:
		GameState.message.emit("%s — материал для крафта." % ItemDB.display_name(id))


func equip(id: String) -> void:
	weapon_id = id
	_refresh_weapon_visuals()
	GameState.message.emit("В руках: %s" % ItemDB.display_name(id))


func _refresh_weapon_visuals() -> void:
	var item := ItemDB.get_item(weapon_id)
	if torch_light != null:
		torch_light.visible = bool(item.get("light", false))


func _place_campfire() -> void:
	if not inventory.remove("campfire_kit", 1):
		return
	var world = get_tree().get_first_node_in_group("world")
	if world != null and world.has_method("spawn_campfire"):
		var forward := -global_transform.basis.z
		var spot := global_position + forward * 1.8
		world.spawn_campfire(spot)
		GameState.message.emit("Костёр разожжён.")


func warm_up(amount: float) -> void:
	survival.warm_up(amount)


## Игрок ушёл под воду — возвращаем его на берег с потерей здоровья.
func _wash_ashore() -> void:
	var world = get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("get_spawn_point"):
		return
	global_position = world.get_spawn_point() + Vector3(0.0, 1.0, 0.0)
	velocity = Vector3.ZERO
	survival.take_damage(12.0, "холодная вода", 0.15)
	GameState.message.emit("Волна выбросила вас на берег.")


func shake(amount: float) -> void:
	_kick = clampf(_kick - amount, -0.12, 0.12)


func _on_died(cause: String) -> void:
	GameState.end_run(cause)


# --- Сохранение -------------------------------------------------------------

func get_state() -> Dictionary:
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"yaw": rotation.y,
		"pitch": _pitch,
		"weapon": weapon_id,
		"stats": survival.get_state(),
		"inventory": inventory.get_state(),
	}


func apply_state(data: Dictionary) -> void:
	if data.has("pos"):
		var pos: Array = data["pos"]
		if pos.size() == 3:
			global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	rotation.y = float(data.get("yaw", 0.0))
	_pitch = float(data.get("pitch", 0.0))
	if data.has("stats"):
		survival.set_state(data["stats"])
	if data.has("inventory"):
		inventory.set_state(data["inventory"])
	weapon_id = String(data.get("weapon", "fists"))
	_refresh_weapon_visuals()
