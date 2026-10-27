extends Node3D

# Imported, rigged low-poly characters. Each model contains its own animation
# library, so NPCs, the player and enemies are genuine animated 3D meshes.
var model: Node3D
var animation: AnimationPlayer
var active_clip := ""

func setup(path: String, model_scale: float = 0.55, skin_tone: Variant = null) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Не удалось загрузить 3D-модель: " + path)
		return
	model = scene.instantiate() as Node3D
	model.scale = Vector3.ONE * model_scale
	add_child(model)
	if skin_tone is Color:
		for instance in model.find_children("*", "MeshInstance3D", true, false):
			if instance.mesh == null:
				continue
			for surface in range(instance.mesh.get_surface_count()):
				var material = instance.get_active_material(surface)
				if material is BaseMaterial3D and material.resource_name.to_lower() == "skin":
					var tinted = material.duplicate()
					tinted.albedo_color = skin_tone
					instance.set_surface_override_material(surface, tinted)
	var players = model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		animation = players[0] as AnimationPlayer
		for clip in ["Idle", "Walk", "Run"]:
			if animation.has_animation(clip):
				animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		play("Idle")

func play(clip: String) -> void:
	if not is_instance_valid(animation) or not animation.has_animation(clip):
		return
	if active_clip != clip or not animation.is_playing():
		active_clip = clip
		animation.play(clip, 0.15)
