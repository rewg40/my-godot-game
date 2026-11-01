class_name StarField
extends MultiMeshInstance3D
## Звёзды: половина названия игры.
##
## Это не скайбокс, а настоящие точки в мире — их можно поймать взглядом сквозь
## ветки, и они медленно поворачиваются вместе с ночным небом.

var _material: StandardMaterial3D
var _base_color := Color(0.84, 0.91, 1.0)


func setup(seed_value: int, count: int = 700) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 5150

	var star_mesh := SphereMesh.new()
	star_mesh.radius = 1.0
	star_mesh.height = 2.0
	star_mesh.radial_segments = 5
	star_mesh.rings = 3

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = star_mesh
	multimesh.instance_count = count
	for i in count:
		var direction := _random_direction(rng)
		var distance := rng.randf_range(840.0, 940.0)
		var size := rng.randf_range(1.3, 3.6)
		var basis := Basis().scaled(Vector3.ONE * size)
		multimesh.set_instance_transform(i, Transform3D(basis, direction * distance))
		var tint := _base_color.lerp(Color(1.0, 0.86, 0.7), rng.randf() * 0.65)
		multimesh.set_instance_color(i, tint)
	self.multimesh = multimesh

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.disable_fog = true
	_material.disable_receive_shadows = true
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_night_factor(0.0)


func set_night_factor(value: float) -> void:
	if _material == null:
		return
	_material.albedo_color.a = clampf(value, 0.0, 1.0)


func _random_direction(rng: RandomNumberGenerator) -> Vector3:
	var y := rng.randf_range(0.04, 1.0)
	var horizontal := sqrt(maxf(0.0, 1.0 - y * y))
	var angle := rng.randf() * TAU
	return Vector3(cos(angle) * horizontal, y, sin(angle) * horizontal).normalized()


func _process(delta: float) -> void:
	rotate_y(delta * 0.005)
