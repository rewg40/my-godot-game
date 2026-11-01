class_name AshFall
extends MultiMeshInstance3D
## Пепел, который всегда падает с неба — вторая половина названия.
##
## Хлопья живут в кубе вокруг камеры и переиспользуются: дешёвая имитация
## частиц без GPUParticles, полностью под контролем кода.

const COUNT := 420
const AREA := 34.0
const TOP := 18.0

var _positions := PackedVector3Array()
var _speeds := PackedFloat32Array()
var _sway := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _center := Vector3.ZERO


func setup(seed_value: int) -> void:
	_rng.seed = seed_value + 3131
	var flake := QuadMesh.new()
	flake.size = Vector2(0.085, 0.085)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.78, 0.76, 0.72, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.disable_receive_shadows = true
	material.disable_fog = false
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = false
	multimesh.mesh = flake
	multimesh.instance_count = COUNT
	self.multimesh = multimesh
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_positions.resize(COUNT)
	_speeds.resize(COUNT)
	_sway.resize(COUNT)
	for i in COUNT:
		_positions[i] = Vector3(
			_rng.randf_range(-AREA, AREA),
			_rng.randf_range(0.0, TOP),
			_rng.randf_range(-AREA, AREA)
		)
		_speeds[i] = _rng.randf_range(0.5, 1.6)
		_sway[i] = _rng.randf_range(0.0, TAU)
	_update_transforms()


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_center = camera.global_position
	var time := float(Time.get_ticks_msec()) / 1000.0
	for i in COUNT:
		var point := _positions[i]
		point.y -= _speeds[i] * delta
		point.x += sin(time * 0.6 + _sway[i]) * 0.35 * delta
		point.z += cos(time * 0.4 + _sway[i]) * 0.25 * delta
		if point.x > _center.x + AREA:
			point.x -= AREA * 2.0
		elif point.x < _center.x - AREA:
			point.x += AREA * 2.0
		if point.z > _center.z + AREA:
			point.z -= AREA * 2.0
		elif point.z < _center.z - AREA:
			point.z += AREA * 2.0
		if point.y < _center.y - 10.0:
			point.y = _center.y + TOP
		_positions[i] = point
	_update_transforms()


func _update_transforms() -> void:
	for i in COUNT:
		var basis := Basis().scaled(Vector3.ONE * _rng.randf_range(0.7, 1.3))
		multimesh.set_instance_transform(i, Transform3D(basis, _positions[i]))
