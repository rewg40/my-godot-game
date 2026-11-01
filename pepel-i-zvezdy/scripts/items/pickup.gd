class_name Pickup
extends Area3D
## Предмет, лежащий в мире. Подбирается на [E] (игрок смотрит на него).
##
## Модель процедурная: цвет и форма берутся из ItemDB. Если для предмета указан
## файл модели (например, клинок «Дракон») и он есть в проекте — используется он.

const MODELS_DIR := "res://assets/models/"

var item_id := "cloth"
var count := 1

var _visual: Node3D
var _time := 0.0


func setup(id: String, amount: int = 1) -> void:
	item_id = id
	count = amount
	if is_inside_tree():
		_build()


func _ready() -> void:
	add_to_group("pickups")
	collision_layer = 8
	collision_mask = 0
	_build()


func get_interaction_text() -> String:
	return "[E] Подобрать: %s%s" % [ItemDB.display_name(item_id), _amount_suffix()]


func interact(player) -> void:
	if player == null:
		return
	var inventory = player.get("inventory")
	if inventory == null:
		return
	var leftover: int = inventory.add(item_id, count)
	if leftover >= count:
		GameState.message.emit("Инвентарь полон.")
		return
	GameState.add_stat("looted", float(count - leftover))
	var taken := count - leftover
	count = leftover
	GameState.message.emit("Подобрано: %s ×%d" % [ItemDB.display_name(item_id), taken])
	if count <= 0:
		_dissolve()


func _amount_suffix() -> String:
	if count > 1:
		return " ×%d" % count
	return ""


func _dissolve() -> void:
	set_deferred("monitoring", false)
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ONE * 0.05, 0.18)
	tween.tween_callback(queue_free)


func _build() -> void:
	if _visual != null:
		return
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	var item := ItemDB.get_item(item_id)
	var color: Color = item.get("color", Color(0.7, 0.7, 0.7))
	var model_path := String(item.get("model", ""))
	if not model_path.is_empty() and ResourceLoader.exists(model_path):
		var packed := load(model_path) as PackedScene
		if packed != null:
			var model := packed.instantiate()
			_visual.add_child(model)
			_add_collider(0.5)
			return

	var shape_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var kind := String(item.get("kind", "material"))
	mesh.size = Vector3(0.22, 0.22, 0.22)
	if kind == "weapon":
		mesh.size = Vector3(0.08, 0.08, 0.85)
	elif kind == "water" or kind == "food":
		mesh.size = Vector3(0.18, 0.3, 0.18)
	elif kind == "material":
		mesh.size = Vector3(0.2, 0.14, 0.2)
	shape_node.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	material.metallic = 0.15 if kind == "weapon" else 0.0
	if kind == "weapon":
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.35
	material.vertex_color_use_as_albedo = false
	shape_node.material_override = material
	shape_node.position.y = 0.22
	shape_node.rotation_degrees = Vector3(0.0, 0.0, 18.0)
	_visual.add_child(shape_node)
	_add_collider(0.42)


func _add_collider(radius: float) -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	shape.position.y = 0.25
	add_child(shape)


func _process(delta: float) -> void:
	_time += delta
	if _visual == null:
		return
	_visual.rotation.y = _time * 1.2
	_visual.position.y = 0.08 + sin(_time * 2.0) * 0.05
