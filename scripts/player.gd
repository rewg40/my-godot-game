extends CharacterBody3D
## Простой контроллер игрока от первого/третьего лица с логикой входа в здания.
## Управление: WASD — движение, мышь — обзор (правый клик — орбита), E — вход/выход.
## Здесь используется хитбокс-капсула и коллизии с островом через move_and_slide.

const WALK_SPEED := 6.0
const SPRINT_SPEED := 9.0
const JUMP_VELOCITY := 6.5
const GRAVITY := 20.0
const CAMERA_PITCH_LIMIT := 1.3
const INTERACT_DISTANCE := 3.0

var world: Node3D
var yaw := 0.0
var pitch := 0.0
var grip := false
var current_door: Area3D = null
var in_interior := false
var return_point := Vector3.ZERO
var camera: Camera3D
var camera_pivot: Node3D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1  # остров
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	_setup_camera()

func _setup_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.position.y = 1.5
	add_child(camera_pivot)
	camera = Camera3D.new()
	camera.name = "PlayerCamera"
	camera.fov = 60.0
	camera_pivot.add_child(camera)
	camera.make_current()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and grip:
		yaw -= event.relative.x * 0.004
		pitch = clampf(pitch - event.relative.y * 0.004, -CAMERA_PITCH_LIMIT, CAMERA_PITCH_LIMIT)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		grip = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey and event.pressed and event.keycode == KEY_E and in_interior:
		_exit_interior()

func _physics_process(delta: float) -> void:
	_scan_door()
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if Input.is_action_just_pressed("ui_accept"):
		velocity.y = JUMP_VELOCITY
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var forward := -cam_basis_z()
	var right := cam_basis_x()
	var dir := (input.x * right + input.y * forward) if in_interior else (input.x * right + input.y * forward)
	if dir.length() > 0.001:
		dir = dir.normalized()
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()
	camera_pivot.rotation = Vector3(pitch, yaw, 0)
	# вход по E рядом с дверью
	if Input.is_action_just_pressed("enter") and current_door != null and not in_interior:
		_enter_interior()

func cam_basis_x() -> Vector3:
	return camera_pivot.global_transform.basis.x

func cam_basis_z() -> Vector3:
	return -camera_pivot.global_transform.basis.z

func _scan_door() -> void:
	current_door = null
	var parent := get_parent()
	if parent == null:
		return
	for area in parent.find_children("Door_*", "Area3D", true, false):
		var a := area as Area3D
		if global_position.distance_to(a.global_position) < INTERACT_DISTANCE:
			current_door = a
			break

func _enter_interior() -> void:
	if current_door == null:
		return
	var interior: String = current_door.get_meta("interior", "")
	if interior.is_empty():
		return
	return_point = global_position
	var scene_path := "res://scenes/interiors/%s.tscn" % interior
	if not ResourceLoader.exists(scene_path):
		push_warning("Нет сцены интерьера: " + scene_path)
		return
	var interior_scene: PackedScene = load(scene_path)
	var inst := interior_scene.instantiate()
	get_tree().current_scene.add_child(inst)
	in_interior = true
	_camera_set_height(0.0)
	inst.start(self)
	world = get_parent()

func _exit_interior() -> void:
	in_interior = false
	var container := get_tree().current_scene.find_child("InteriorRoot*", true, false)
	if container != null:
		container.queue_free()
	global_position = return_point

func _camera_set_height(y: float) -> void:
	camera_pivot.position.y = y