extends Node2D

const SHEET = preload("res://assets/environment/village_sheet.png")
var world
var prop_id: String = ""
var kind: String = ""
var title: String = ""
var detail: Dictionary = {}
var usable: bool = true
var respawn_at: float = 0.0
var sprite: Sprite2D

func configure(owner_world, identity: String, prop_kind: String, display_title: String, properties: Dictionary = {}) -> void:
	world = owner_world
	prop_id = identity
	kind = prop_kind
	title = display_title
	detail = properties

func _ready() -> void:
	sprite = Sprite2D.new()
	add_child(sprite)
	_update_sprite()
	var radius = float(detail.get("collision", 0.0))
	if radius > 0.0:
		var body = StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape = CollisionShape2D.new()
		var circle = CircleShape2D.new()
		circle.radius = radius
		shape.shape = circle
		shape.position.y = -5
		body.add_child(shape)
		add_child(body)

func _process(_delta: float) -> void:
	if not usable and respawn_at > 0.0 and world.elapsed >= respawn_at:
		usable = true
		respawn_at = 0.0
		_update_sprite()

func _update_sprite() -> void:
	if not is_instance_valid(sprite):
		return
	var region = detail.get("region", Rect2())
	if region is Rect2 and region.size.x > 0:
		var atlas = AtlasTexture.new()
		atlas.atlas = SHEET
		atlas.region = region
		sprite.texture = atlas
	else:
		var texture_path = String(detail.get("texture", ""))
		if not texture_path.is_empty():
			sprite.texture = load(texture_path)
	if not sprite.texture:
		return
	var factor = float(detail.get("scale", 3.0))
	sprite.scale = Vector2(factor, factor)
	if kind == "npc":
		sprite.hframes = 4
		sprite.vframes = int(detail.get("frames_y", 7))
		sprite.frame_coords = Vector2i(0, 0)
		sprite.offset = Vector2(0, -7)
	else:
		sprite.hframes = 1
		sprite.vframes = 1
		sprite.offset = Vector2(0, -sprite.texture.get_height() / 2.0 + 2.0)
	sprite.modulate = Color(0.5, 0.55, 0.48, 0.55) if not usable else Color.WHITE
	queue_redraw()

func set_built() -> void:
	detail["region"] = Rect2(224, 0, 48, 80)
	detail["scale"] = 2.0
	title = "Оборонительная башня"
	_update_sprite()

func deplete(seconds: float) -> void:
	usable = false
	respawn_at = world.elapsed + seconds
	_update_sprite()

func _draw() -> void:
	if kind == "plot" and not detail.get("built", false):
		draw_arc(Vector2.ZERO, 40, 0, TAU, 32, Color(0.92, 0.76, 0.43, 0.7), 2.0)
