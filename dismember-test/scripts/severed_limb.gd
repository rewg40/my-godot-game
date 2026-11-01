class_name SeveredLimb
extends Node3D
## Отрубленная конечность: тот же меш, что был на теле, падает и остаётся
## лежать рядом. Живёт до перезапуска сцены, чтобы было видно результат.

const LIFETIME := 120.0

var part_id := ""
var _mesh_node: MeshInstance3D
var _life := 0.0


func setup(mesh: Mesh, world_transform: Transform3D, source_part: String) -> void:
	part_id = source_part
	global_transform = world_transform
	_mesh_node = MeshInstance3D.new()
	_mesh_node.name = "Mesh"
	_mesh_node.mesh = mesh
	add_child(_mesh_node)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 0.35, 0.45) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation:x", rotation.x + randf_range(-1.4, 1.4), 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation:z", rotation.z + randf_range(-1.2, 1.2), 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_life += delta
	if _life > LIFETIME:
		queue_free()
