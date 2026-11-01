class_name Limb
extends Node3D
## Конечность: кусок меша, зона попадания и запас прочности.
##
## Зона — Area3D на слое «limb»: игрок целится лучом из камеры, попадает
## в конкретную конечность и снимает с неё единицу прочности (3 удара — отрубил).

signal hp_changed(limb: Limb)
signal severed(limb: Limb)

var id := ""
var title := ""
var max_hp := 3.0
var hp := 3.0
var alive := true

var mesh_instance: MeshInstance3D
var area: Area3D

var _flash: StandardMaterial3D
var _flash_alpha := 0.0
var _debug: MeshInstance3D = null


func configure(part_id: String, hp_value: float, interactive: bool) -> void:
	id = part_id
	title = ModelProfiles.part_title(part_id)
	max_hp = hp_value
	hp = hp_value
	set_meta("limb", self)
	if not interactive:
		return
	_flash = StandardMaterial3D.new()
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash.albedo_color = Color(1.0, 0.25, 0.15, 0.0)
	_flash.disable_receive_shadows = true


## Коробка попадания в локальных координатах конечности.
func build_zone(size: Vector3, offset: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(size.x, 0.04), maxf(size.y, 0.04), maxf(size.z, 0.04))
	var collision := CollisionShape3D.new()
	collision.name = "HitShape"
	collision.shape = box
	collision.position = offset
	area = Area3D.new()
	area.name = "HitZone"
	area.collision_layer = 8
	area.collision_mask = 0
	area.monitoring = false
	area.add_child(collision)
	area.set_meta("limb", self)
	add_child(area)


## Удар по конечности. Возвращает true, если она отрублена этим ударом.
func take_hit(damage: float) -> bool:
	if not alive:
		return false
	hp = maxf(0.0, hp - damage)
	_flash_alpha = 1.0
	hp_changed.emit(self)
	if hp > 0.0:
		return false
	alive = false
	severed.emit(self)
	return true


func flash_alpha() -> float:
	return _flash_alpha


## Показ зоны попадания (F3) — видно, куда именно бьёт меч.
func set_debug_visible(enabled: bool) -> void:
	if area == null:
		return
	if _debug == null:
		if not enabled:
			return
		var shape := area.get_child(0) as CollisionShape3D
		if shape == null or not (shape.shape is BoxShape3D):
			return
		var box := shape.shape as BoxShape3D
		var mesh := BoxMesh.new()
		mesh.size = box.size
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1.0, 0.38, 0.2, 0.25)
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_debug = MeshInstance3D.new()
		_debug.name = "DebugZone"
		_debug.mesh = mesh
		_debug.material_override = material
		_debug.position = shape.position
		add_child(_debug)
	_debug.visible = enabled


func _process(delta: float) -> void:
	if _flash == null or mesh_instance == null:
		return
	if _flash_alpha <= 0.0:
		return
	_flash_alpha = maxf(0.0, _flash_alpha - delta * 5.0)
	_flash.albedo_color = Color(1.0, 0.25, 0.15, _flash_alpha * 0.55)
	mesh_instance.material_overlay = _flash
