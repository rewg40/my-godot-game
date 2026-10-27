extends Node3D

# Imported, rigged low-poly characters. Each model contains its own animation
# library, so NPCs, the player and enemies are genuine animated 3D meshes.
var model: Node3D
var animation: AnimationPlayer
var active_clip := ""

func setup(path: String, model_scale: float = 0.55) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Не удалось загрузить 3D-модель: " + path)
		return
	model = scene.instantiate() as Node3D
	model.scale = Vector3.ONE * model_scale
	add_child(model)
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
