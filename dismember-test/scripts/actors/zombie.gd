class_name Zombie
extends CharacterBody3D
## Зомби для проверки меча.
##
## Корпус держит 1000 HP, каждая рука и нога — 3 HP: три удачных удара мечом,
## и конечность отваливается. Без ног зомби ложится и ползёт, без рук — идёт,
## но не бьёт; отрубленные части остаются лежать на земле.

signal died(zombie: Zombie)
signal limb_lost(zombie: Zombie, part_id: String)
signal body_damaged(zombie: Zombie)
signal attack_landed(zombie: Zombie)

const BODY_HP := 1000.0
const GRAVITY := 22.0
const WALK_SPEED := 1.5
const LIMP_SPEED := 1.05
const CRAWL_SPEED := 0.85
const ATTACK_REACH := 1.75
const ATTACK_TIME := 0.9
const ATTACK_DAMAGE := 6.0
const ATTACK_COOLDOWN := 1.5
const PRONE_ANGLE := 1.25
const STAND_HEIGHT := 1.7
const PRONE_HEIGHT := 0.65

var index := 1
var hp := BODY_HP
var max_hp := BODY_HP
var target: Node3D
var rig: HumanoidRig
var visual: Node3D
var label: Label3D

var _capsule: CapsuleShape3D
var _shape: CollisionShape3D
var _attack := -1.0
var _attack_hit := false
var _cooldown := 0.0
var _prone := 0.0
var _recoil := 0.0
var _speed := 0.0
var _mode := "idle"
var _dead := false


func setup(zombie_index: int, target_node: Node3D) -> void:
	index = zombie_index
	target = target_node


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2

	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.34
	_capsule.height = STAND_HEIGHT
	_shape = CollisionShape3D.new()
	_shape.name = "Body"
	_shape.shape = _capsule
	_shape.position = Vector3(0.0, STAND_HEIGHT * 0.5, 0.0)
	add_child(_shape)

	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)

	rig = HumanoidRig.new()
	rig.name = "Rig"
	visual.add_child(rig)
	rig.build("zombie", true)
	for part_id in rig.parts.keys():
		var limb: Limb = rig.parts[part_id]
		limb.max_hp = ModelProfiles.LIMB_HP
		limb.hp = limb.max_hp
		limb.hp_changed.connect(_on_limb_hp_changed)
		limb.set_meta("zombie", self)

	label = Label3D.new()
	label.name = "Label"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.0024
	label.outline_size = 16
	label.modulate = Color(1.0, 0.94, 0.86)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.position = Vector3(0.0, 2.1, 0.0)
	add_child(label)
	_update_label()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if target == null or not is_instance_valid(target):
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_update_pose(delta)
		return

	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	var direction := Vector3.FORWARD if distance < 0.01 else to_target / distance

	_mode = _pick_mode(distance)
	_speed = _speed_for(_mode)
	var move := Vector3.ZERO
	if distance > ATTACK_REACH * 0.8:
		move = direction * _speed
	elif rig.limb_count("arm") > 0 and _cooldown <= 0.0 and _attack < 0.0:
		_start_attack()

	velocity.x = move.x
	velocity.z = move.z
	move_and_slide()
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 8.0 * delta)
	_update_attack(delta)
	_update_pose(delta)


func _pick_mode(distance: float) -> String:
	if rig.limb_count("leg") == 0:
		return "crawl"
	if _attack >= 0.0:
		return "idle"
	if distance <= ATTACK_REACH * 0.8:
		return "idle"
	return "run" if distance > 5.0 and rig.limb_count("leg") == 2 else "walk"


func _speed_for(mode: String) -> float:
	match mode:
		"crawl":
			return CRAWL_SPEED
		"run":
			return WALK_SPEED * 1.3
		"walk":
			return WALK_SPEED if rig.limb_count("leg") == 2 else LIMP_SPEED
		_:
			return 0.0


func _update_pose(delta: float) -> void:
	rig.animate(delta, _mode, _speed, _attack)
	var want_prone := 1.0 if _mode == "crawl" else 0.0
	_prone = move_toward(_prone, want_prone, delta * 2.2)
	visual.rotation.x = -PRONE_ANGLE * _prone
	visual.rotation.z = _recoil * 0.2
	_recoil = maxf(0.0, _recoil - delta * 3.5)
	visual.position.y = -0.55 * _prone
	var wanted_height := lerpf(STAND_HEIGHT, PRONE_HEIGHT, _prone)
	if absf(_capsule.height - wanted_height) > 0.02:
		_capsule.height = wanted_height
		_shape.position.y = wanted_height * 0.5
	label.position.y = lerpf(2.1, 1.0, _prone)


func _start_attack() -> void:
	_attack = 0.0
	_attack_hit = false


func _update_attack(delta: float) -> void:
	if _attack < 0.0:
		return
	_attack += delta / ATTACK_TIME
	if not _attack_hit and _attack >= 0.5:
		_attack_hit = true
		_strike()
	if _attack >= 1.0:
		_attack = -1.0
		_cooldown = ATTACK_COOLDOWN


func _strike() -> void:
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) > ATTACK_REACH + 0.5:
		return
	if target.has_method("take_damage"):
		target.take_damage(ATTACK_DAMAGE, "зомби")
		attack_landed.emit(self)


## Урон корпусу: 1000 HP, меч снимает 25.
func damage_body(amount: float) -> void:
	if _dead:
		return
	hp = maxf(0.0, hp - amount)
	_recoil = 1.0
	body_damaged.emit(self)
	_update_label()
	if hp <= 0.0:
		_die()


## Урон конечности. true — если она отрублена этим ударом.
func damage_limb(part_id: String, amount: float) -> bool:
	if _dead:
		return false
	var severed := rig.take_hit(part_id, amount)
	if severed:
		sever(part_id)
	return severed


## Отделяет конечность и роняет её рядом отдельным объектом.
func sever(part_id: String) -> void:
	var data := rig.detach(part_id)
	if data.is_empty():
		return
	var piece := SeveredLimb.new()
	piece.name = "Severed_%s_%d" % [part_id, index]
	var parent_node := get_parent()
	if parent_node == null:
		parent_node = get_tree().current_scene
	parent_node.add_child(piece)
	piece.setup(data["mesh"], data["transform"], part_id)
	limb_lost.emit(self, part_id)
	_update_label()


func _on_limb_hp_changed(_limb: Limb) -> void:
	_update_label()


func is_dead() -> bool:
	return _dead


func leg_count() -> int:
	return rig.limb_count("leg")


func arm_count() -> int:
	return rig.limb_count("arm")


func limb_state(part_id: String) -> String:
	if not rig.parts.has(part_id):
		return "отрублена"
	var limb: Limb = rig.parts[part_id]
	return "%d/%d" % [int(ceil(limb.hp)), int(limb.max_hp)]


func _update_label() -> void:
	if label == null:
		return
	if _dead:
		label.text = "Зомби %d — мёртв" % index
		return
	label.text = "Зомби %d · %d HP\nР %s · %s  Н %s · %s" % [
		index, int(ceil(hp)),
		limb_state("arm_l"), limb_state("arm_r"),
		limb_state("leg_l"), limb_state("leg_r"),
	]


func _die() -> void:
	_dead = true
	velocity = Vector3.ZERO
	collision_layer = 0
	rig.set_hit_zones_enabled(false)
	rig.animate(0.0, "idle", 0.0)
	_update_label()
	var tween := create_tween()
	tween.tween_property(visual, "rotation:x", visual.rotation.x + 1.45, 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(visual, "position:y", -0.35, 0.7)
	died.emit(self)
