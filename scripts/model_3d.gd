extends Node3D

# Quaternius Universal Base Characters with retargeted Universal Animation
# Library clips. Clothing masks are baked in rest-pose vertex colours, so the
# outfits remain attached to the real skinned mesh when it moves.
const MALE = "res://assets/models/survivors/male.glb"
const FEMALE = "res://assets/models/survivors/female.glb"
const CLOTHES = preload("res://shaders/survivor_clothes.gdshader")

var model: Node3D
var animation: AnimationPlayer
var active_clip := ""
var infected := false

func setup(path: String, model_scale: float = 0.55, skin_tone: Variant = null) -> void:
	var female = "female" in path.to_lower()
	infected = "zombie" in path.to_lower()
	var scene := load(FEMALE if female else MALE) as PackedScene
	if scene == null:
		push_error("Не удалось загрузить 3D-модель персонажа")
		return
	model = scene.instantiate() as Node3D
	# Previous characters were ~3.3 m before their 0.55 scale. These new
	# anatomically proportioned rigs are authored at roughly 1.8 m already.
	model.scale = Vector3.ONE * (model_scale / 0.55)
	add_child(model)
	var shirt = Color("667565")
	var pants = Color("444945")
	var hair = Color("332b25")
	if "OldClassy" in path:
		shirt = Color("77736a")
		pants = Color("4c4c49")
		hair = Color("9b978d")
	elif "Worker" in path:
		shirt = Color("736d52")
		pants = Color("454d50")
	elif female:
		shirt = Color("68735d")
		pants = Color("524b43")
	if infected:
		shirt = Color("595f52")
		pants = Color("46473d")
		hair = Color("332f29")
	for instance in model.find_children("*", "MeshInstance3D", true, false):
		if instance.mesh == null:
			continue
		for surface in range(instance.mesh.get_surface_count()):
			var original = instance.get_active_material(surface)
			if not original is BaseMaterial3D:
				continue
			var name_lower = original.resource_name.to_lower()
			if "superhero" in name_lower:
				var material = ShaderMaterial.new()
				material.shader = CLOTHES
				material.set_shader_parameter("skin_texture", original.albedo_texture)
				var skin = Color("9eae93") if infected else Color.WHITE
				if skin_tone is Color and not infected:
					skin = Color.WHITE.lerp(skin_tone, 0.18)
				material.set_shader_parameter("skin_tint", skin)
				material.set_shader_parameter("shirt_tint", shirt)
				material.set_shader_parameter("pants_tint", pants)
				material.set_shader_parameter("shoes_tint", Color("38352e"))
				instance.set_surface_override_material(surface, material)
			elif "hair" in name_lower:
				var material = original.duplicate()
				material.albedo_color = hair
				instance.set_surface_override_material(surface, material)
	var players = model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		animation = players[0] as AnimationPlayer
		for clip in ["Idle", "Walk", "Run", "ZombieIdle", "ZombieWalk"]:
			if animation.has_animation(clip):
				animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		play("Idle")

func play(clip: String) -> void:
	if infected:
		var zombie_clips = {"Idle": "ZombieIdle", "Walk": "ZombieWalk", "Punch": "ZombieAttack"}
		clip = zombie_clips.get(clip, clip)
	if not is_instance_valid(animation) or not animation.has_animation(clip):
		return
	if active_clip != clip or not animation.is_playing():
		active_clip = clip
		animation.play(clip, 0.15)
